-- =====================================================================
-- ENERGIA — PHASE 17: TIKTOK SETTLEMENT IMPORT AND RECONCILIATION
--
--  * Settlement files carry full financial detail per transaction:
--    Order/Adjustment ID (TEXT, exact), Transaction Type, Order Created /
--    Settled times, Total Settlement Amount, Total Revenue, Total Fees,
--    Related Order ID, Currency, adjustment/refund data, raw row JSON.
--  * Matching to previously imported orders of the SAME store:
--      normal order        -> Order/Adjustment ID = Order ID
--      adjustment / refund -> Related Order ID    = Order ID
--    One order may carry many settlement transactions; a transaction is
--    unique per store_id + order/adjustment id.
--  * Re-uploading the same Order/Adjustment ID NEVER overwrites silently:
--    identical rows are 'Already Imported'; changed rows become
--    'Updated — Requires Confirmation' with a field-by-field diff, and
--    confirmation creates a NEW immutable version linked to the old one
--    (old versions stay queryable; value columns are trigger-frozen).
--  * Settlements that arrive before their order are saved as Pending and
--    matched AUTOMATICALLY when the order is later imported (a trigger on
--    the order state does the re-match) — and shown in reports.
--  * Settlement imports NEVER change inventory.
--  * Total Settlement Amount is the main financial figure; revenue, fees,
--    adjustments and refunds are shown separately. The default
--    financial-report date is the Order Created Date.
--  * SKU allocation spreads order-level settlement across the order's
--    items by SKU Subtotal After Discount (equal split when all
--    subtotals are zero); the rounding difference lands on the final SKU
--    line so allocations ALWAYS sum exactly to the order totals.
--  * Reconciliation: Total Settlement = Total Revenue + Total Fees within
--    $0.01; mismatches are flagged as warnings, values are never altered.
--
-- Additive + idempotent. Run AFTER 65.
-- =====================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------
-- 1. Schema additions on tiktok_settlement_rows.
-- ---------------------------------------------------------------------
alter table public.tiktok_settlement_rows add column if not exists transaction_type text;
alter table public.tiktok_settlement_rows add column if not exists txn_class text
  check (txn_class in ('order','adjustment','refund'));
alter table public.tiktok_settlement_rows add column if not exists order_created_time timestamptz;
alter table public.tiktok_settlement_rows add column if not exists related_order_id text;
alter table public.tiktok_settlement_rows add column if not exists adjustment_amount numeric(12,2);
alter table public.tiktok_settlement_rows add column if not exists refund_amount numeric(12,2);
alter table public.tiktok_settlement_rows add column if not exists match_status text not null default 'pending'
  check (match_status in ('matched','pending'));
alter table public.tiktok_settlement_rows add column if not exists matched_order_id text;
alter table public.tiktok_settlement_rows add column if not exists staging_status text;
alter table public.tiktok_settlement_rows add column if not exists excluded boolean not null default false;
alter table public.tiktok_settlement_rows add column if not exists confirmed boolean not null default false;
alter table public.tiktok_settlement_rows add column if not exists confirmed_at timestamptz;
alter table public.tiktok_settlement_rows add column if not exists is_current boolean not null default false;
alter table public.tiktok_settlement_rows add column if not exists version_no integer not null default 1;
alter table public.tiktok_settlement_rows add column if not exists previous_row_id uuid
  references public.tiktok_settlement_rows(id);
alter table public.tiktok_settlement_rows add column if not exists value_diff jsonb;
alter table public.tiktok_settlement_rows add column if not exists reconciled boolean;

create index if not exists idx_ttsettle_current
  on public.tiktok_settlement_rows(store_id, order_id) where is_current;
create index if not exists idx_ttsettle_pending
  on public.tiktok_settlement_rows(store_id, match_status) where match_status = 'pending';

-- ---------------------------------------------------------------------
-- 2. Helpers.
-- ---------------------------------------------------------------------
-- Amounts may arrive as '1,234.56', 'SGD 12.30', '(5.00)' etc.
create or replace function public.tiktok_parse_amount(p text)
returns numeric language plpgsql immutable as $$
declare v text := trim(coalesce(p,'')); v_neg boolean := false;
begin
  if v = '' then return null; end if;
  if v like '(%' and v like '%)' then v_neg := true; end if;
  v := regexp_replace(v, '[^0-9.\-]', '', 'g');
  if v in ('','-','.','-.') then return null; end if;
  begin
    return case when v_neg then -abs(v::numeric) else v::numeric end;
  exception when others then return null; end;
end $$;

create or replace function public.tiktok_txn_class(p_type text)
returns text language sql immutable as $$
  select case
    when lower(coalesce(p_type,'')) like '%adjust%' then 'adjustment'
    when lower(coalesce(p_type,'')) like '%refund%' or lower(coalesce(p_type,'')) like '%return%' then 'refund'
    else 'order'
  end
$$;

-- Match a settlement transaction to a previously imported order of the
-- SAME store. Normal orders match on the Order/Adjustment ID itself;
-- adjustments/refunds match on the Related Order ID (falling back to the
-- Order/Adjustment ID when TikTok leaves the related column empty).
create or replace function public.tiktok_settlement_match(
  p_store_id uuid, p_order_adjustment_id text, p_related_order_id text, p_class text
) returns text language sql stable security definer set search_path = public as $$
  select case
    when p_class = 'order' then
      (select s.order_id from public.tiktok_order_state s
        where s.store_id = p_store_id and s.order_id = p_order_adjustment_id limit 1)
    else
      coalesce(
        (select s.order_id from public.tiktok_order_state s
          where s.store_id = p_store_id and s.order_id = p_related_order_id limit 1),
        (select s.order_id from public.tiktok_order_state s
          where s.store_id = p_store_id and s.order_id = p_order_adjustment_id limit 1))
  end
$$;

-- Reconciliation check: Settlement = Revenue + Fees within $0.01.
-- NULL when the file did not carry both components.
create or replace function public.tiktok_settlement_reconciled(
  p_settlement numeric, p_revenue numeric, p_fees numeric
) returns boolean language sql immutable as $$
  select case
    when p_settlement is null or p_revenue is null or p_fees is null then null
    else abs(p_settlement - (p_revenue + p_fees)) <= 0.01
  end
$$;

-- ---------------------------------------------------------------------
-- 3. Immutability: confirmed settlement values are frozen. Only matching
--    flags and the is_current pointer may move afterwards.
-- ---------------------------------------------------------------------
create or replace function public.trg_tiktok_settlement_immutable() returns trigger
language plpgsql as $$
begin
  if tg_op = 'DELETE' then
    if old.confirmed then
      raise exception 'Confirmed settlement rows are immutable — re-import creates a new linked version'; end if;
    return old;
  end if;
  if old.confirmed then
    if new.order_id            is distinct from old.order_id
    or new.adjustment_id       is distinct from old.adjustment_id
    or new.related_order_id    is distinct from old.related_order_id
    or new.transaction_type    is distinct from old.transaction_type
    or new.txn_class           is distinct from old.txn_class
    or new.settlement_amount   is distinct from old.settlement_amount
    or new.revenue_amount      is distinct from old.revenue_amount
    or new.fee_amount          is distinct from old.fee_amount
    or new.adjustment_amount   is distinct from old.adjustment_amount
    or new.refund_amount       is distinct from old.refund_amount
    or new.currency            is distinct from old.currency
    or new.order_created_time  is distinct from old.order_created_time
    or new.settled_time        is distinct from old.settled_time
    or new.raw                 is distinct from old.raw
    or new.version_no          is distinct from old.version_no
    or new.previous_row_id     is distinct from old.previous_row_id
    or new.confirmed           is distinct from old.confirmed then
      raise exception 'Confirmed settlement values are immutable — re-import creates a new linked version';
    end if;
  end if;
  return new;
end $$;
drop trigger if exists tiktok_settlement_immutable on public.tiktok_settlement_rows;
create trigger tiktok_settlement_immutable
  before update or delete on public.tiktok_settlement_rows
  for each row execute function public.trg_tiktok_settlement_immutable();

-- ---------------------------------------------------------------------
-- 4. Staging — re-issued: full fields, duplicate/version detection,
--    matching, reconciliation. NEVER touches inventory.
-- ---------------------------------------------------------------------
create or replace function public.stage_tiktok_settlement(
  p_store_id uuid, p_file_name text, p_sheet_name text, p_rows jsonb
) returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_batch uuid; v_r jsonb; v_no integer := 0;
  v_oaid text; v_type text; v_class text; v_related text;
  v_settle numeric; v_rev numeric; v_fees numeric; v_adj numeric; v_ref numeric;
  v_created timestamptz; v_settled timestamptz; v_curr text;
  v_cur record; v_status text; v_diff jsonb; v_match text; v_dup boolean;
  v_prev_id uuid; v_prev_ver integer;
begin
  perform public.tiktok_access_check(p_store_id);
  if p_rows is null or jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) = 0 then
    raise exception 'No rows to import'; end if;

  insert into public.tiktok_import_batches (store_id, file_kind, file_name, sheet_name, uploaded_by)
  values (p_store_id, 'settlement', p_file_name, p_sheet_name, auth.uid())
  returning id into v_batch;

  for v_r in select * from jsonb_array_elements(p_rows) loop
    v_no := v_no + 1;
    v_oaid    := nullif(trim(coalesce(v_r->>'order_id','')),'');
    v_type    := nullif(trim(coalesce(v_r->>'transaction_type','')),'');
    v_class   := public.tiktok_txn_class(v_type);
    v_related := nullif(trim(coalesce(v_r->>'related_order_id','')),'');
    v_settle  := public.tiktok_parse_amount(v_r->>'settlement_amount');
    v_rev     := public.tiktok_parse_amount(v_r->>'revenue_amount');
    v_fees    := public.tiktok_parse_amount(v_r->>'fee_amount');
    v_adj     := public.tiktok_parse_amount(v_r->>'adjustment_amount');
    v_ref     := public.tiktok_parse_amount(v_r->>'refund_amount');
    v_created := public.tiktok_parse_time(v_r->>'order_created_time');
    v_settled := public.tiktok_parse_time(v_r->>'settled_time');
    v_curr    := nullif(trim(coalesce(v_r->>'currency','')),'');
    v_status  := null; v_diff := null;

    if v_oaid is null or v_settle is null then
      v_status := 'Invalid Row';
    end if;

    -- Duplicate inside THIS file (store + order/adjustment id): keep first.
    v_dup := v_status is null and exists (select 1 from public.tiktok_settlement_rows
              where batch_id = v_batch and order_id = v_oaid);
    if v_dup then v_status := 'Duplicate Row'; end if;

    v_match := case when v_status is null
                    then public.tiktok_settlement_match(p_store_id, v_oaid, v_related, v_class) end;

    v_prev_id := null; v_prev_ver := null;
    if v_status is null then
      -- Compare against the CURRENT confirmed version of this transaction.
      select * into v_cur from public.tiktok_settlement_rows
       where store_id = p_store_id and order_id = v_oaid and is_current
       order by version_no desc limit 1;
      if found then
        v_prev_id := v_cur.id; v_prev_ver := v_cur.version_no;
        if  v_type    is not distinct from v_cur.transaction_type
        and v_settle  is not distinct from v_cur.settlement_amount
        and v_rev     is not distinct from v_cur.revenue_amount
        and v_fees    is not distinct from v_cur.fee_amount
        and v_adj     is not distinct from v_cur.adjustment_amount
        and v_ref     is not distinct from v_cur.refund_amount
        and v_curr    is not distinct from v_cur.currency
        and v_related is not distinct from v_cur.related_order_id
        and v_created is not distinct from v_cur.order_created_time
        and v_settled is not distinct from v_cur.settled_time then
          v_status := 'Already Imported';
        else
          v_status := 'Updated — Requires Confirmation';
          select coalesce(jsonb_object_agg(f.field, jsonb_build_object('old', f.o, 'new', f.n))
                          filter (where f.o is distinct from f.n), '{}'::jsonb)
            into v_diff
            from (values
              ('transaction_type',    to_jsonb(v_cur.transaction_type),  to_jsonb(v_type)),
              ('settlement_amount',   to_jsonb(v_cur.settlement_amount), to_jsonb(v_settle)),
              ('revenue_amount',      to_jsonb(v_cur.revenue_amount),    to_jsonb(v_rev)),
              ('fee_amount',          to_jsonb(v_cur.fee_amount),        to_jsonb(v_fees)),
              ('adjustment_amount',   to_jsonb(v_cur.adjustment_amount), to_jsonb(v_adj)),
              ('refund_amount',       to_jsonb(v_cur.refund_amount),     to_jsonb(v_ref)),
              ('currency',            to_jsonb(v_cur.currency),          to_jsonb(v_curr)),
              ('related_order_id',    to_jsonb(v_cur.related_order_id),  to_jsonb(v_related)),
              ('order_created_time',  to_jsonb(v_cur.order_created_time),to_jsonb(v_created)),
              ('settled_time',        to_jsonb(v_cur.settled_time),      to_jsonb(v_settled))
            ) as f(field, o, n);
        end if;
      else
        v_status := case when v_match is not null then 'New — Matched' else 'New — Pending Order' end;
      end if;
    end if;

    insert into public.tiktok_settlement_rows (
      batch_id, store_id, row_no, order_id, adjustment_id, related_order_id,
      transaction_type, txn_class, settlement_amount, revenue_amount, fee_amount,
      adjustment_amount, refund_amount, currency, order_created_time, settled_time, raw,
      staging_status, value_diff, excluded,
      match_status, matched_order_id,
      version_no, previous_row_id, reconciled)
    values (
      v_batch, p_store_id, v_no, v_oaid,
      nullif(trim(coalesce(v_r->>'adjustment_id','')),''), v_related,
      v_type, case when v_status in ('Invalid Row') then null else v_class end,
      v_settle, v_rev, v_fees, v_adj, v_ref, v_curr, v_created, v_settled, v_r,
      v_status, v_diff,
      v_status in ('Invalid Row','Duplicate Row','Already Imported'),
      case when v_match is not null then 'matched' else 'pending' end,
      v_match,
      coalesce(v_prev_ver, 0) + 1,
      v_prev_id,
      public.tiktok_settlement_reconciled(v_settle, v_rev, v_fees));
  end loop;

  update public.tiktok_import_batches set row_count = v_no where id = v_batch;
  perform public.write_audit_ex('tiktok_import_batches', v_batch, 'tiktok_settlement_staged', null,
    jsonb_build_object('file', p_file_name, 'sheet', p_sheet_name, 'rows', v_no),
    'tiktok_import', null, p_store_id);
  return v_batch;
end $$;

-- ---------------------------------------------------------------------
-- 5. Confirmation: versions become current; updates were explicitly
--    selected (that IS the confirmation of the displayed differences).
--    Inventory is NEVER touched here.
-- ---------------------------------------------------------------------
create or replace function public.confirm_tiktok_settlement_batch(p_batch_id uuid, p_row_ids jsonb default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_b public.tiktok_import_batches%rowtype; v_row record; v_selected boolean;
  v_applied integer := 0; v_skipped integer := 0; v_updates integer := 0;
  v_pending integer := 0; v_unrec integer := 0;
begin
  select * into v_b from public.tiktok_import_batches where id = p_batch_id and deleted_at is null for update;
  if not found then raise exception 'Batch not found'; end if;
  perform public.tiktok_access_check(v_b.store_id);
  if v_b.file_kind <> 'settlement' then raise exception 'Only settlement batches can be confirmed here'; end if;
  if v_b.status <> 'staged' then raise exception 'This batch is already confirmed and locked'; end if;

  for v_row in select * from public.tiktok_settlement_rows where batch_id = p_batch_id order by row_no loop
    v_selected := (p_row_ids is null or p_row_ids @> to_jsonb(v_row.id::text));
    if not v_selected or v_row.excluded
       or v_row.staging_status in ('Invalid Row','Duplicate Row','Already Imported') then
      if not v_row.confirmed then
        update public.tiktok_settlement_rows set excluded = true where id = v_row.id;
        v_skipped := v_skipped + 1;
      end if;
      continue;
    end if;

    -- The previous version steps aside; the new one becomes current.
    if v_row.previous_row_id is not null then
      update public.tiktok_settlement_rows set is_current = false where id = v_row.previous_row_id;
      v_updates := v_updates + 1;
    end if;
    update public.tiktok_settlement_rows
       set confirmed = true, confirmed_at = now(), is_current = true
     where id = v_row.id;

    v_applied := v_applied + 1;
    if v_row.match_status = 'pending' then v_pending := v_pending + 1; end if;
    if v_row.reconciled is false then v_unrec := v_unrec + 1; end if;
  end loop;

  update public.tiktok_import_batches
     set status = 'confirmed', confirmed_by = auth.uid(), confirmed_at = now()
   where id = p_batch_id;

  perform public.write_audit_ex('tiktok_import_batches', p_batch_id, 'tiktok_settlement_confirmed', null,
    jsonb_build_object('file', v_b.file_name, 'applied', v_applied, 'skipped', v_skipped,
                       'versioned_updates', v_updates, 'pending', v_pending, 'unreconciled', v_unrec),
    'tiktok_import', null, v_b.store_id);

  return jsonb_build_object('success', true, 'applied', v_applied, 'skipped', v_skipped,
                            'versioned_updates', v_updates, 'pending', v_pending, 'unreconciled', v_unrec);
end $$;

-- ---------------------------------------------------------------------
-- 6. Pending settlements match AUTOMATICALLY when the order arrives:
--    the order-state write (confirmed order imports) triggers a re-match.
-- ---------------------------------------------------------------------
create or replace function public.rematch_tiktok_settlements(p_store_id uuid, p_order_id text)
returns integer language plpgsql security definer set search_path = public as $$
declare v_n integer := 0;
begin
  update public.tiktok_settlement_rows r
     set match_status = 'matched', matched_order_id = p_order_id,
         staging_status = case when r.staging_status = 'New — Pending Order'
                               then 'New — Matched' else r.staging_status end
   where r.store_id = p_store_id and r.match_status = 'pending'
     and ( (r.txn_class = 'order' and r.order_id = p_order_id)
        or (r.txn_class in ('adjustment','refund')
            and (r.related_order_id = p_order_id
                 or (r.related_order_id is null and r.order_id = p_order_id))) );
  get diagnostics v_n = row_count;
  return v_n;
end $$;

create or replace function public.trg_tiktok_state_rematch() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform public.rematch_tiktok_settlements(new.store_id, new.order_id);
  return new;
end $$;
drop trigger if exists tiktok_state_rematch on public.tiktok_order_state;
create trigger tiktok_state_rematch
  after insert on public.tiktok_order_state
  for each row execute function public.trg_tiktok_state_rematch();

-- ---------------------------------------------------------------------
-- 7. SKU allocation: order-level settlement spread across the order's
--    items by SKU Subtotal After Discount (equal split when all zero);
--    the rounding difference lands on the FINAL SKU line, so the
--    allocation always sums exactly to the order totals.
-- ---------------------------------------------------------------------
create or replace function public.tiktok_settlement_allocation(p_store_id uuid, p_order_id text)
returns table (
  seller_sku text, quantity integer, sku_subtotal_after numeric,
  weight numeric, allocated_settlement numeric, allocated_revenue numeric, allocated_fees numeric
) language sql stable security definer set search_path = public as $$
  with items as (
    select distinct on (o.seller_sku)
           o.seller_sku as sku, o.quantity as qty, coalesce(o.sku_subtotal_after, 0) as sub
      from public.tiktok_order_rows o
     where o.store_id = p_store_id and o.order_id = p_order_id and o.confirmed
     order by o.seller_sku, o.version_no desc, o.confirmed_at desc
  ), tot as (
    select coalesce(sum(r.settlement_amount),0) as s,
           coalesce(sum(r.revenue_amount),0) as r,
           coalesce(sum(r.fee_amount),0) as f
      from public.tiktok_settlement_rows r
     where r.store_id = p_store_id and r.matched_order_id = p_order_id
       and r.is_current and r.confirmed
  ), agg as (
    select count(*) as n, sum(sub) as wsum from items
  ), weighted as (
    -- Equal allocation when every SKU subtotal is zero.
    select i.sku, i.qty, i.sub,
           case when a.wsum = 0 then 1::numeric / a.n else i.sub / a.wsum end as wt,
           row_number() over (order by i.sku) as rn, a.n
      from items i cross join agg a
  ), rounded as (
    select w.*, t.s, t.r, t.f,
           round(t.s * w.wt, 2) as rs, round(t.r * w.wt, 2) as rr, round(t.f * w.wt, 2) as rf,
           coalesce(sum(round(t.s * w.wt, 2)) over (order by w.rn rows between unbounded preceding and 1 preceding), 0) as prior_s,
           coalesce(sum(round(t.r * w.wt, 2)) over (order by w.rn rows between unbounded preceding and 1 preceding), 0) as prior_r,
           coalesce(sum(round(t.f * w.wt, 2)) over (order by w.rn rows between unbounded preceding and 1 preceding), 0) as prior_f
      from weighted w cross join tot t
  )
  -- The rounding difference lands on the FINAL SKU line: exact totals.
  select sku, qty, sub, round(wt, 6),
         case when rn < n then rs else s - prior_s end,
         case when rn < n then rr else r - prior_r end,
         case when rn < n then rf else f - prior_f end
    from rounded
   order by rn
$$;

-- ---------------------------------------------------------------------
-- 8. Reports. Total Settlement Amount is the MAIN figure; the default
--    financial date is the Order Created Date. Staff see their stores.
-- ---------------------------------------------------------------------
create or replace function public.report_tiktok_settlement(
  p_store_id uuid default null, p_from date default null, p_to date default null
) returns table (
  row_id uuid, store_name text, financial_date date,
  order_adjustment_id text, txn_class text, transaction_type text,
  matched_order_id text, match_status text,
  settlement_amount numeric, revenue_amount numeric, fee_amount numeric,
  adjustment_amount numeric, refund_amount numeric, currency text,
  reconciled boolean, version_no integer
) language sql stable security definer set search_path = public as $$
  select r.id, s.name,
         coalesce(r.order_created_time at time zone 'Asia/Singapore',
                  r.settled_time at time zone 'Asia/Singapore')::date,
         r.order_id, r.txn_class, r.transaction_type,
         r.matched_order_id, r.match_status,
         r.settlement_amount, r.revenue_amount, r.fee_amount,
         r.adjustment_amount, r.refund_amount, r.currency,
         r.reconciled, r.version_no
    from public.tiktok_settlement_rows r
    join public.stores s on s.id = r.store_id
   where r.confirmed and r.is_current
     and (p_store_id is null or r.store_id = p_store_id)
     and (p_from is null or coalesce(r.order_created_time at time zone 'Asia/Singapore',
                                     r.settled_time at time zone 'Asia/Singapore')::date >= p_from)
     and (p_to is null or coalesce(r.order_created_time at time zone 'Asia/Singapore',
                                   r.settled_time at time zone 'Asia/Singapore')::date <= p_to)
     and (public.current_user_role() in ('owner','manager','admin','inventory_manager')
          or public.user_has_store_access(r.store_id))
   order by 3 desc nulls last, r.order_id
$$;

create or replace function public.report_tiktok_settlement_summary(
  p_store_id uuid default null, p_from date default null, p_to date default null
) returns table (
  total_settlement numeric, total_revenue numeric, total_fees numeric,
  total_adjustments numeric, total_refunds numeric,
  transactions bigint, matched_count bigint, pending_count bigint, unreconciled_count bigint
) language sql stable security definer set search_path = public as $$
  select coalesce(sum(r.settlement_amount),0),
         coalesce(sum(r.revenue_amount),0),
         coalesce(sum(r.fee_amount),0),
         coalesce(sum(r.settlement_amount) filter (where r.txn_class = 'adjustment'),0),
         coalesce(sum(r.settlement_amount) filter (where r.txn_class = 'refund'),0),
         count(*),
         count(*) filter (where r.match_status = 'matched'),
         count(*) filter (where r.match_status = 'pending'),
         count(*) filter (where r.reconciled is false)
    from public.report_tiktok_settlement(p_store_id, p_from, p_to) r
$$;

notify pgrst, 'reload schema';
