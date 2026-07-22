-- =====================================================================
-- ENERGIA — PHASE 16: TIKTOK STATUS AND STOCK LIFECYCLE
--
--  * Configurable status mappings (Owner/Manager managed): every TikTok
--    order status maps to Deduct Stock / Return Stock / No Stock Action,
--    with a "marks shipped" flag driving the cancellation lifecycle.
--  * Deduction stays cumulative: stock deducts ONCE per order item;
--    quantity changes apply only the difference (up = extra deduction,
--    down before shipment = partial return).
--  * Cancellation BEFORE shipment stages an automatic return, applied when
--    the updated import is confirmed. Cancellation AFTER shipment never
--    returns automatically — it becomes 'Awaiting Physical Return', and
--    Owner/Manager/assigned-store Staff later resolve it as Stock Return
--    or No Stock Return (mandatory categorised reason: damaged / lost /
--    not_received / other).
--  * Negative stock is now possible — but ONLY through confirmed TikTok
--    sales: the old hard CHECK constraints are replaced by guard triggers
--    that keep blocking every other path (invoices, transfers,
--    adjustments). A TikTok confirm that would go negative demands an
--    explicit confirmation + mandatory reason, writes an audit entry, and
--    surfaces on a dashboard alert.
--  * Versioning: confirmed rows are IMMUTABLE (trigger-enforced). A
--    re-imported row becomes a new, linked version carrying the previous
--    values, the stock difference and the financial difference.
--  * Corrections: Owner/Manager create CORRECTION BATCHES against
--    confirmed imports; they apply reversing/additional stock movements
--    and are fully audited. Confirmed batches still cannot be deleted.
--
-- Additive except for two documented constraint swaps (CHECK -> trigger).
-- Run AFTER 64.
-- =====================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------
-- 1. Configurable status mappings.
-- ---------------------------------------------------------------------
create table if not exists public.tiktok_status_mappings (
  id uuid primary key default gen_random_uuid(),
  status_label text not null,                      -- matched case-insensitively
  status_norm text not null unique,                -- normalised key
  action text not null check (action in ('deduct','return','none')),
  marks_shipped boolean not null default false,    -- drives the cancellation lifecycle
  is_active boolean not null default true,
  sort_order integer not null default 100,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.tiktok_status_mappings enable row level security;
drop policy if exists "read tiktok_status_mappings" on public.tiktok_status_mappings;
create policy "read tiktok_status_mappings" on public.tiktok_status_mappings
  for select to authenticated using (true);

insert into public.tiktok_status_mappings (status_label, status_norm, action, marks_shipped, sort_order) values
  ('Paid',              'paid',               'deduct', false, 10),
  ('To Ship',           'to ship',            'deduct', false, 20),
  ('Awaiting Shipment', 'awaiting shipment',  'deduct', false, 30),
  ('Ready to Ship',     'ready to ship',      'deduct', false, 40),
  ('Shipped',           'shipped',            'deduct', true,  50),
  ('In Transit',        'in transit',         'deduct', true,  60),
  ('Delivered',         'delivered',          'deduct', true,  70),
  ('Completed',         'completed',          'deduct', true,  80),
  ('Packed',            'packed',             'deduct', false, 45),
  ('Awaiting Collection','awaiting collection','deduct', false, 35),
  ('Cancelled',         'cancelled',          'return', false, 110),
  ('Canceled',          'canceled',           'return', false, 111),
  ('Returned',          'returned',           'return', false, 120),
  ('Refunded',          'refunded',           'return', false, 130)
on conflict (status_norm) do nothing;

create or replace function public.tiktok_norm_status(p text)
returns text language sql immutable as $$
  select regexp_replace(lower(trim(coalesce(p,''))), '[_\s]+', ' ', 'g')
$$;

create or replace function public.upsert_tiktok_status_mapping(
  p_status_label text, p_action text, p_marks_shipped boolean default null, p_is_active boolean default null
) returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_norm text;
begin
  if public.current_user_role() not in ('owner','manager') then
    raise exception 'Only Owners and Managers can manage TikTok status mappings'; end if;
  if nullif(trim(coalesce(p_status_label,'')),'') is null then raise exception 'Status label is required'; end if;
  if p_action not in ('deduct','return','none') then
    raise exception 'Action must be deduct, return or none'; end if;
  v_norm := public.tiktok_norm_status(p_status_label);

  insert into public.tiktok_status_mappings (status_label, status_norm, action, marks_shipped, is_active)
  values (trim(p_status_label), v_norm, p_action, coalesce(p_marks_shipped,false), coalesce(p_is_active,true))
  on conflict (status_norm) do update
    set status_label = excluded.status_label, action = excluded.action,
        marks_shipped = coalesce(p_marks_shipped, public.tiktok_status_mappings.marks_shipped),
        is_active = coalesce(p_is_active, public.tiktok_status_mappings.is_active),
        updated_at = now()
  returning id into v_id;

  perform public.write_audit('tiktok_status_mappings', v_id, 'tiktok_status_mapping_upserted', null,
    jsonb_build_object('status', trim(p_status_label), 'action', p_action,
                       'marks_shipped', p_marks_shipped, 'is_active', p_is_active));
  return v_id;
end $$;

create or replace function public.set_tiktok_status_mapping_active(p_id uuid, p_active boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  if public.current_user_role() not in ('owner','manager') then
    raise exception 'Only Owners and Managers can manage TikTok status mappings'; end if;
  update public.tiktok_status_mappings set is_active = p_active, updated_at = now() where id = p_id;
  if not found then raise exception 'Status mapping not found'; end if;
end $$;

-- Re-issued: the effect now comes from the configurable table.
create or replace function public.tiktok_status_effect(p_status text)
returns text language sql stable security definer set search_path = public as $$
  select coalesce(
    (select case m.action when 'none' then 'none' else m.action end
       from public.tiktok_status_mappings m
      where m.status_norm = public.tiktok_norm_status(p_status) and m.is_active),
    'invalid')
$$;

create or replace function public.tiktok_status_marks_shipped(p_status text)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(
    (select m.marks_shipped from public.tiktok_status_mappings m
      where m.status_norm = public.tiktok_norm_status(p_status) and m.is_active),
    false)
$$;

-- ---------------------------------------------------------------------
-- 2. Schema additions: shipped flag on state, version links on rows,
--    correction batches, physical returns.
-- ---------------------------------------------------------------------
alter table public.tiktok_order_state add column if not exists was_shipped boolean not null default false;

alter table public.tiktok_order_rows add column if not exists previous_row_id uuid references public.tiktok_order_rows(id);
alter table public.tiktok_order_rows add column if not exists version_no integer not null default 1;
alter table public.tiktok_order_rows add column if not exists prev_quantity integer;
alter table public.tiktok_order_rows add column if not exists prev_order_status text;
alter table public.tiktok_order_rows add column if not exists prev_sku_subtotal_after numeric(12,2);
alter table public.tiktok_order_rows add column if not exists financial_delta numeric(12,2);

alter table public.tiktok_import_batches add column if not exists corrects_batch_id uuid references public.tiktok_import_batches(id);
alter table public.tiktok_import_batches drop constraint if exists tiktok_import_batches_file_kind_check;
alter table public.tiktok_import_batches add constraint tiktok_import_batches_file_kind_check
  check (file_kind in ('order','settlement','correction'));

alter table public.tiktok_corrections add column if not exists correction_batch_id uuid references public.tiktok_import_batches(id);

create table if not exists public.tiktok_physical_returns (
  id uuid primary key default gen_random_uuid(),
  order_row_id uuid references public.tiktok_order_rows(id),
  store_id uuid not null references public.stores(id),
  order_id text not null,
  seller_sku text not null,
  expected_qty integer not null,
  status text not null default 'awaiting' check (status in ('awaiting','restocked','no_restock')),
  resolution_reason text,          -- damaged / lost / not_received / other
  resolution_note text,
  resolved_by uuid references public.profiles(id),
  resolved_at timestamptz,
  created_at timestamptz not null default now()
);
alter table public.tiktok_physical_returns enable row level security;
drop policy if exists "read tiktok_physical_returns" on public.tiktok_physical_returns;
create policy "read tiktok_physical_returns" on public.tiktok_physical_returns
  for select to authenticated using (true);
create index if not exists idx_ttphys_store on public.tiktok_physical_returns(store_id, status);

-- ---------------------------------------------------------------------
-- 3. Negative stock: TikTok-only. The hard CHECK constraints are replaced
--    by guard triggers with identical behaviour for every non-TikTok path.
--    The TikTok confirm/correction path opens a transaction-local gate.
-- ---------------------------------------------------------------------
alter table public.store_inventory drop constraint if exists store_inventory_current_qty_check;
alter table public.voucher_store_stock drop constraint if exists voucher_store_stock_current_qty_check;

create or replace function public.trg_block_negative_stock() returns trigger
language plpgsql as $$
begin
  if new.current_qty < 0
     and coalesce(current_setting('energia.tiktok_negative', true), '') <> 'allow' then
    raise exception 'Stock cannot go negative (only confirmed TikTok sales may drive stock below zero)';
  end if;
  return new;
end $$;
drop trigger if exists block_negative_stock on public.store_inventory;
create trigger block_negative_stock
  before insert or update on public.store_inventory
  for each row execute function public.trg_block_negative_stock();
drop trigger if exists block_negative_stock on public.voucher_store_stock;
create trigger block_negative_stock
  before insert or update on public.voucher_store_stock
  for each row execute function public.trg_block_negative_stock();

-- Re-issued WITHOUT the clamp: real arithmetic; the guard trigger decides.
create or replace function public.tiktok_adjust_product_stock(p_store_id uuid, p_product_id uuid, p_delta integer)
returns void language plpgsql security definer set search_path = public as $$
begin
  update public.store_inventory
     set current_qty = current_qty - p_delta, updated_at = now()
   where store_id = p_store_id and product_id = p_product_id;
  if not found then
    insert into public.store_inventory (store_id, product_id, current_qty)
    values (p_store_id, p_product_id, -p_delta);
  end if;
end $$;

create or replace function public.tiktok_adjust_voucher_stock(p_store_id uuid, p_voucher_id uuid, p_delta integer)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from public.vouchers where id = p_voucher_id and qty_type = 'limited') then return; end if;
  update public.voucher_store_stock
     set current_qty = current_qty - p_delta, updated_at = now()
   where store_id = p_store_id and voucher_id = p_voucher_id;
  if not found then
    insert into public.voucher_store_stock (voucher_id, store_id, current_qty)
    values (p_voucher_id, p_store_id, -p_delta);
  end if;
end $$;

-- Dashboard alert: any negative stock can only have come from TikTok.
create or replace function public.tiktok_negative_stock_alerts()
returns table (store_name text, kind text, item_name text, current_qty integer)
language sql stable security definer set search_path = public as $$
  select s.name, 'product'::text, p.name, si.current_qty
    from public.store_inventory si
    join public.stores s on s.id = si.store_id
    join public.products p on p.id = si.product_id
   where si.current_qty < 0
  union all
  select s.name, 'voucher', v.name, vs.current_qty
    from public.voucher_store_stock vs
    join public.stores s on s.id = vs.store_id
    join public.vouchers v on v.id = vs.voucher_id
   where vs.current_qty < 0
   order by 4
$$;

-- ---------------------------------------------------------------------
-- 4. Immutability of confirmed rows (versions are linked, never edited).
-- ---------------------------------------------------------------------
create or replace function public.trg_tiktok_row_immutable() returns trigger
language plpgsql as $$
begin
  if tg_op = 'DELETE' then
    if old.confirmed then
      raise exception 'Confirmed import rows are immutable — create a correction instead'; end if;
    return old;
  end if;
  if old.confirmed then
    raise exception 'Confirmed import rows are immutable — a re-import creates a new linked version'; end if;
  return new;
end $$;
drop trigger if exists tiktok_row_immutable on public.tiktok_order_rows;
create trigger tiktok_row_immutable
  before update or delete on public.tiktok_order_rows
  for each row execute function public.trg_tiktok_row_immutable();

-- ---------------------------------------------------------------------
-- 5. Evaluation — re-issued: shipped-aware cancellations.
-- ---------------------------------------------------------------------
create or replace function public.tiktok_evaluate(
  p_store_id uuid, p_order_id text, p_seller_sku text,
  p_quantity integer, p_order_status text, p_is_duplicate boolean
) returns table (staging_status text, stock_delta integer, matched_kind text, matched_id uuid)
language plpgsql stable security definer set search_path = public as $$
declare
  v_alias public.tiktok_sku_aliases%rowtype;
  v_effect text; v_prev integer; v_shipped boolean; v_target integer; v_delta integer;
begin
  staging_status := null; stock_delta := 0; matched_kind := null; matched_id := null;

  if nullif(trim(coalesce(p_order_id,'')),'') is null
     or nullif(coalesce(p_seller_sku,''),'') is null
     or p_quantity is null or p_quantity <= 0 then
    staging_status := 'Invalid Row'; return next; return;
  end if;
  if p_is_duplicate then
    staging_status := 'Duplicate Row'; return next; return;
  end if;

  select * into v_alias from public.tiktok_sku_aliases
    where store_id = p_store_id and seller_sku = p_seller_sku;
  if found then matched_kind := v_alias.target_kind; matched_id := v_alias.target_id; end if;

  v_effect := public.tiktok_status_effect(p_order_status);
  if v_effect = 'invalid' then
    staging_status := 'Invalid Status'; return next; return;
  end if;

  if matched_id is null then
    staging_status := 'Unmatched SKU'; return next; return;
  end if;

  select coalesce(deducted_qty,0), coalesce(was_shipped,false) into v_prev, v_shipped
    from public.tiktok_order_state
   where store_id = p_store_id and order_id = p_order_id and seller_sku = p_seller_sku;
  v_prev := coalesce(v_prev, 0); v_shipped := coalesce(v_shipped, false);

  -- 'No Stock Action' statuses never move stock and never touch state.
  if v_effect = 'none' then
    staging_status := 'No Stock Change'; stock_delta := 0; return next; return;
  end if;

  -- Cancellation AFTER shipment: never an automatic return.
  if v_effect = 'return' and v_prev > 0 and v_shipped then
    staging_status := 'Awaiting Physical Return'; stock_delta := 0; return next; return;
  end if;

  v_target := case when v_effect = 'deduct' then p_quantity else 0 end;
  v_delta := v_target - v_prev;
  stock_delta := v_delta;

  if v_delta = 0 then
    staging_status := case when v_prev > 0 or v_effect = 'return' then 'Already Imported' else 'No Stock Change' end;
  elsif v_delta < 0 then
    staging_status := 'Updated — Stock Return';
  elsif v_prev > 0 then
    staging_status := 'Updated — Additional Deduction';
  else
    staging_status := 'New — Will Deduct';
  end if;

  if v_delta > 0 and public.tiktok_projected_short(p_store_id, matched_kind, matched_id, v_delta) then
    staging_status := 'Negative Stock Warning';
  end if;
  return next;
end $$;

-- ---------------------------------------------------------------------
-- 6. Staging — re-issued: fills the version link + previous values +
--    stock/financial differences against the latest confirmed version.
-- ---------------------------------------------------------------------
create or replace function public.stage_tiktok_orders(
  p_store_id uuid, p_file_name text, p_sheet_name text, p_rows jsonb
) returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_batch uuid; v_r jsonb; v_no integer := 0;
  v_order text; v_sku text; v_qty integer; v_status text; v_dup boolean;
  v_eval record; v_after numeric;
  v_prev_id uuid; v_prev_qty integer; v_prev_status text; v_prev_after numeric; v_prev_ver integer;
begin
  perform public.tiktok_access_check(p_store_id);
  if p_rows is null or jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) = 0 then
    raise exception 'No rows to import'; end if;

  insert into public.tiktok_import_batches (store_id, file_kind, file_name, sheet_name, uploaded_by)
  values (p_store_id, 'order', p_file_name, p_sheet_name, auth.uid())
  returning id into v_batch;

  for v_r in select * from jsonb_array_elements(p_rows) loop
    v_no := v_no + 1;
    v_order  := nullif(trim(coalesce(v_r->>'order_id','')),'');
    v_sku    := nullif(coalesce(v_r->>'seller_sku',''),'');
    v_qty    := case when (v_r->>'quantity') ~ '^\d+$' then (v_r->>'quantity')::integer else null end;
    v_status := nullif(trim(coalesce(v_r->>'order_status','')),'');

    v_dup := exists (select 1 from public.tiktok_order_rows
                      where batch_id = v_batch and order_id = v_order and seller_sku = v_sku
                        and v_order is not null and v_sku is not null);

    select * into v_eval from public.tiktok_evaluate(p_store_id, v_order, v_sku, v_qty, v_status, v_dup);

    -- Version chain: link the latest CONFIRMED version of this order item.
    v_prev_id := null; v_prev_qty := null; v_prev_status := null; v_prev_after := null; v_prev_ver := null;
    if v_order is not null and v_sku is not null then
      select id, quantity, order_status, sku_subtotal_after, coalesce(version_no,1)
        into v_prev_id, v_prev_qty, v_prev_status, v_prev_after, v_prev_ver
        from public.tiktok_order_rows
       where store_id = p_store_id and order_id = v_order and seller_sku = v_sku and confirmed
       order by confirmed_at desc nulls last, row_no desc limit 1;
    end if;
    v_after := nullif(v_r->>'sku_subtotal_after','')::numeric;

    insert into public.tiktok_order_rows (
      batch_id, store_id, row_no, order_id, seller_sku, product_name, quantity, order_status,
      sku_subtotal_before, sku_subtotal_after, refund_amount, return_quantity,
      rts_time, created_time, paid_time, shipped_time, delivered_time, cancelled_time,
      tracking_id, package_id, warehouse, shipping_provider, payment_method, category, raw,
      staging_status, stock_delta, matched_kind, matched_id,
      previous_row_id, version_no, prev_quantity, prev_order_status, prev_sku_subtotal_after, financial_delta)
    values (
      v_batch, p_store_id, v_no, v_order, v_sku,
      nullif(trim(coalesce(v_r->>'product_name','')),''), v_qty, v_status,
      nullif(v_r->>'sku_subtotal_before','')::numeric, v_after,
      nullif(v_r->>'refund_amount','')::numeric,
      case when (v_r->>'return_quantity') ~ '^\d+$' then (v_r->>'return_quantity')::integer else null end,
      public.tiktok_parse_time(v_r->>'rts_time'),
      public.tiktok_parse_time(v_r->>'created_time'),
      public.tiktok_parse_time(v_r->>'paid_time'),
      public.tiktok_parse_time(v_r->>'shipped_time'),
      public.tiktok_parse_time(v_r->>'delivered_time'),
      public.tiktok_parse_time(v_r->>'cancelled_time'),
      nullif(trim(coalesce(v_r->>'tracking_id','')),''), nullif(trim(coalesce(v_r->>'package_id','')),''),
      nullif(trim(coalesce(v_r->>'warehouse','')),''), nullif(trim(coalesce(v_r->>'shipping_provider','')),''),
      nullif(trim(coalesce(v_r->>'payment_method','')),''), nullif(trim(coalesce(v_r->>'category','')),''),
      v_r,
      v_eval.staging_status, v_eval.stock_delta, v_eval.matched_kind, v_eval.matched_id,
      v_prev_id,
      coalesce(v_prev_ver, 0) + 1,
      v_prev_qty,
      v_prev_status,
      v_prev_after,
      case when v_prev_id is not null
           then coalesce(v_after,0) - coalesce(v_prev_after,0) end);
  end loop;

  update public.tiktok_import_batches set row_count = v_no where id = v_batch;
  perform public.write_audit_ex('tiktok_import_batches', v_batch, 'tiktok_orders_staged', null,
    jsonb_build_object('file', p_file_name, 'sheet', p_sheet_name, 'rows', v_no),
    'tiktok_import', null, p_store_id);
  return v_batch;
end $$;

-- ---------------------------------------------------------------------
-- 7. Confirmation — re-issued: shipped tracking, physical-return
--    creation, and the explicit negative-stock gate.
-- ---------------------------------------------------------------------
-- Phase 15's 2-arg overload is superseded (defaults would make calls ambiguous).
drop function if exists public.confirm_tiktok_batch(uuid, jsonb);
create or replace function public.confirm_tiktok_batch(
  p_batch_id uuid, p_row_ids jsonb default null,
  p_allow_negative boolean default false, p_negative_reason text default null
) returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_b public.tiktok_import_batches%rowtype; v_row record; v_eval record; v_effect text;
  v_applied integer := 0; v_skipped integer := 0; v_deducted integer := 0; v_returned integer := 0;
  v_awaiting integer := 0; v_selected boolean; v_neg text := '';
begin
  select * into v_b from public.tiktok_import_batches where id = p_batch_id and deleted_at is null for update;
  if not found then raise exception 'Batch not found'; end if;
  perform public.tiktok_access_check(v_b.store_id);
  if v_b.file_kind <> 'order' then raise exception 'Only order batches can be confirmed for stock'; end if;
  if v_b.status <> 'staged' then raise exception 'This batch is already confirmed and locked'; end if;

  -- Pass 1: would any selected row push stock negative? If so, demand the
  -- explicit confirmation + reason BEFORE anything is applied.
  for v_row in select * from public.tiktok_order_rows where batch_id = p_batch_id order by row_no loop
    v_selected := (p_row_ids is null or p_row_ids @> to_jsonb(v_row.id::text));
    if not v_selected or v_row.excluded or v_row.confirmed then continue; end if;
    select * into v_eval from public.tiktok_evaluate(
      v_row.store_id, v_row.order_id, v_row.seller_sku, v_row.quantity, v_row.order_status,
      v_row.staging_status = 'Duplicate Row');
    if v_eval.stock_delta > 0
       and public.tiktok_projected_short(v_row.store_id, v_eval.matched_kind, v_eval.matched_id, v_eval.stock_delta) then
      v_neg := v_neg || format('order %s / %s (needs %s); ', v_row.order_id, v_row.seller_sku, v_eval.stock_delta);
    end if;
  end loop;

  if v_neg <> '' then
    if not p_allow_negative then
      raise exception 'NEGATIVE_STOCK_CONFIRMATION_REQUIRED: confirming will drive stock negative for %', v_neg;
    end if;
    if nullif(trim(coalesce(p_negative_reason,'')),'') is null then
      raise exception 'A reason is required to confirm TikTok sales into negative stock'; end if;
    -- Transaction-local gate: only THIS confirm may go below zero.
    perform set_config('energia.tiktok_negative', 'allow', true);
    perform public.write_audit_ex('tiktok_import_batches', p_batch_id, 'tiktok_negative_stock_confirmed', null,
      jsonb_build_object('file', v_b.file_name, 'shortfalls', v_neg, 'reason', trim(p_negative_reason)),
      'tiktok_import', trim(p_negative_reason), v_b.store_id);
  end if;

  -- Pass 2: apply.
  for v_row in select * from public.tiktok_order_rows where batch_id = p_batch_id order by row_no loop
    v_selected := (p_row_ids is null or p_row_ids @> to_jsonb(v_row.id::text));
    if not v_selected or v_row.excluded or v_row.confirmed then
      if not v_row.confirmed then
        update public.tiktok_order_rows set excluded = true where id = v_row.id;
        v_skipped := v_skipped + 1;
      end if;
      continue;
    end if;

    select * into v_eval from public.tiktok_evaluate(
      v_row.store_id, v_row.order_id, v_row.seller_sku, v_row.quantity, v_row.order_status,
      v_row.staging_status = 'Duplicate Row');

    if v_eval.staging_status in ('Invalid Row','Duplicate Row','Unmatched SKU','Invalid Status') then
      update public.tiktok_order_rows
         set staging_status = v_eval.staging_status, stock_delta = 0, excluded = true where id = v_row.id;
      v_skipped := v_skipped + 1;
      continue;
    end if;

    v_effect := public.tiktok_status_effect(v_row.order_status);

    if v_eval.staging_status = 'Awaiting Physical Return' then
      -- No automatic return after shipment: create the pending record once.
      if not exists (select 1 from public.tiktok_physical_returns
                      where store_id = v_row.store_id and order_id = v_row.order_id
                        and seller_sku = v_row.seller_sku and status = 'awaiting') then
        insert into public.tiktok_physical_returns
          (order_row_id, store_id, order_id, seller_sku, expected_qty)
        select v_row.id, v_row.store_id, v_row.order_id, v_row.seller_sku, coalesce(s.deducted_qty,0)
          from public.tiktok_order_state s
         where s.store_id = v_row.store_id and s.order_id = v_row.order_id and s.seller_sku = v_row.seller_sku;
      end if;
      update public.tiktok_order_state set last_status = v_row.order_status, updated_at = now()
       where store_id = v_row.store_id and order_id = v_row.order_id and seller_sku = v_row.seller_sku;
      v_awaiting := v_awaiting + 1;
    else
      perform public.apply_tiktok_stock_delta(
        v_row.store_id, v_eval.matched_kind, v_eval.matched_id, v_eval.stock_delta,
        v_row.id, v_row.order_id, v_row.seller_sku, 'TikTok import ' || coalesce(v_b.file_name,''));

      -- 'No Stock Action' statuses leave state untouched.
      if v_effect in ('deduct','return') then
        insert into public.tiktok_order_state (store_id, order_id, seller_sku, deducted_qty, last_status, was_shipped, updated_at)
        values (v_row.store_id, v_row.order_id, v_row.seller_sku,
                case when v_effect = 'deduct' then v_row.quantity else 0 end,
                v_row.order_status,
                public.tiktok_status_marks_shipped(v_row.order_status), now())
        on conflict (store_id, order_id, seller_sku)
        do update set deducted_qty = excluded.deducted_qty, last_status = excluded.last_status,
                      was_shipped = public.tiktok_order_state.was_shipped or excluded.was_shipped,
                      updated_at = now();
      end if;
    end if;

    update public.tiktok_order_rows
       set staging_status = v_eval.staging_status, stock_delta = v_eval.stock_delta,
           matched_kind = v_eval.matched_kind, matched_id = v_eval.matched_id,
           confirmed = true, confirmed_at = now()
     where id = v_row.id;

    v_applied := v_applied + 1;
    if v_eval.stock_delta > 0 then v_deducted := v_deducted + v_eval.stock_delta;
    elsif v_eval.stock_delta < 0 then v_returned := v_returned - v_eval.stock_delta; end if;
  end loop;

  -- Close the negative-stock gate immediately (not merely at COMMIT).
  perform set_config('energia.tiktok_negative', '', true);

  update public.tiktok_import_batches
     set status = 'confirmed', confirmed_by = auth.uid(), confirmed_at = now()
   where id = p_batch_id;

  perform public.write_audit_ex('tiktok_import_batches', p_batch_id, 'tiktok_batch_confirmed', null,
    jsonb_build_object('file', v_b.file_name, 'applied', v_applied, 'skipped', v_skipped,
                       'units_deducted', v_deducted, 'units_returned', v_returned,
                       'awaiting_physical_return', v_awaiting),
    'tiktok_import', null, v_b.store_id);

  return jsonb_build_object('success', true, 'applied', v_applied, 'skipped', v_skipped,
                            'units_deducted', v_deducted, 'units_returned', v_returned,
                            'awaiting_physical_return', v_awaiting);
end $$;

-- ---------------------------------------------------------------------
-- 8. Physical returns: resolved by Owner/Manager or Staff assigned to the
--    store. Restock returns the stock; No Stock Return demands a
--    categorised reason (note mandatory for 'other').
-- ---------------------------------------------------------------------
create or replace function public.resolve_tiktok_physical_return(
  p_return_id uuid, p_restock boolean, p_reason text default null, p_note text default null
) returns void language plpgsql security definer set search_path = public as $$
declare v_pr public.tiktok_physical_returns%rowtype; v_row public.tiktok_order_rows%rowtype; v_role user_role;
begin
  v_role := public.current_user_role();
  select * into v_pr from public.tiktok_physical_returns where id = p_return_id for update;
  if not found then raise exception 'Physical return not found'; end if;
  -- Spec: Owner, Manager, or Staff assigned to the store.
  if not (v_role in ('owner','manager')
          or (v_role = 'staff' and public.user_has_store_access(v_pr.store_id))) then
    raise exception 'Only Owners, Managers or Staff assigned to this store can confirm physical returns'; end if;
  if v_pr.status <> 'awaiting' then raise exception 'This physical return is already resolved'; end if;

  if p_restock then
    if v_pr.order_row_id is not null then
      select * into v_row from public.tiktok_order_rows where id = v_pr.order_row_id;
      perform public.apply_tiktok_stock_delta(
        v_pr.store_id, v_row.matched_kind, v_row.matched_id, -v_pr.expected_qty,
        v_row.id, v_pr.order_id, v_pr.seller_sku, 'TikTok physical return');
    end if;
    update public.tiktok_order_state
       set deducted_qty = greatest(0, deducted_qty - v_pr.expected_qty), updated_at = now()
     where store_id = v_pr.store_id and order_id = v_pr.order_id and seller_sku = v_pr.seller_sku;
    update public.tiktok_physical_returns
       set status = 'restocked', resolved_by = auth.uid(), resolved_at = now(),
           resolution_reason = nullif(trim(coalesce(p_reason,'')),''), resolution_note = nullif(trim(coalesce(p_note,'')),'')
     where id = p_return_id;
  else
    if coalesce(p_reason,'') not in ('damaged','lost','not_received','other') then
      raise exception 'No Stock Return requires a reason: damaged, lost, not_received or other'; end if;
    if p_reason = 'other' and nullif(trim(coalesce(p_note,'')),'') is null then
      raise exception 'Please describe the reason when choosing "other"'; end if;
    update public.tiktok_physical_returns
       set status = 'no_restock', resolved_by = auth.uid(), resolved_at = now(),
           resolution_reason = p_reason, resolution_note = nullif(trim(coalesce(p_note,'')),'')
     where id = p_return_id;
  end if;

  perform public.write_audit_ex('tiktok_physical_returns', p_return_id,
    case when p_restock then 'tiktok_physical_return_restocked' else 'tiktok_physical_return_no_restock' end,
    null,
    jsonb_build_object('order_id', v_pr.order_id, 'seller_sku', v_pr.seller_sku,
                       'expected_qty', v_pr.expected_qty, 'reason', p_reason, 'note', p_note),
    'tiktok_import', p_reason, v_pr.store_id);
end $$;

-- ---------------------------------------------------------------------
-- 9. Correction batches (Owner/Manager, confirmed imports only) —
--    reversing/additional stock movements, fully recorded.
-- ---------------------------------------------------------------------
create or replace function public.create_tiktok_correction_batch(
  p_batch_id uuid, p_items jsonb, p_reason text
) returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_b public.tiktok_import_batches%rowtype; v_cb uuid; v_i jsonb;
  v_row public.tiktok_order_rows%rowtype; v_delta integer; v_n integer := 0;
begin
  if public.current_user_role() not in ('owner','manager') then
    raise exception 'Only Owners and Managers can create correction batches'; end if;
  if nullif(trim(coalesce(p_reason,'')),'') is null then
    raise exception 'A correction reason is required'; end if;
  select * into v_b from public.tiktok_import_batches where id = p_batch_id and deleted_at is null;
  if not found then raise exception 'Batch not found'; end if;
  if v_b.status <> 'confirmed' then
    raise exception 'Correction batches apply to confirmed imports only'; end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'No correction items'; end if;

  insert into public.tiktok_import_batches
    (store_id, file_kind, file_name, status, uploaded_by, confirmed_by, confirmed_at, corrects_batch_id, notes)
  values (v_b.store_id, 'correction', 'Correction of ' || coalesce(v_b.file_name, p_batch_id::text),
          'confirmed', auth.uid(), auth.uid(), now(), p_batch_id, trim(p_reason))
  returning id into v_cb;

  -- Corrections are TikTok stock activity: the same transaction-local gate
  -- lets a reversing entry restock or an additional entry go negative.
  perform set_config('energia.tiktok_negative', 'allow', true);

  for v_i in select * from jsonb_array_elements(p_items) loop
    select * into v_row from public.tiktok_order_rows where id = (v_i->>'row_id')::uuid;
    if not found then raise exception 'Correction row not found'; end if;
    if v_row.batch_id <> p_batch_id then raise exception 'Row does not belong to the batch being corrected'; end if;
    if not v_row.confirmed then raise exception 'Corrections apply to confirmed rows only'; end if;
    if v_row.matched_kind is null then raise exception 'Row % has no mapping to correct against', v_row.row_no; end if;
    v_delta := coalesce((v_i->>'qty_delta')::integer, 0);
    if v_delta = 0 then raise exception 'Correction quantity cannot be zero'; end if;

    -- Reversing (negative) or additional (positive) stock movement.
    perform public.apply_tiktok_stock_delta(
      v_row.store_id, v_row.matched_kind, v_row.matched_id, v_delta,
      v_row.id, v_row.order_id, v_row.seller_sku, 'TikTok correction');

    insert into public.tiktok_order_state (store_id, order_id, seller_sku, deducted_qty, last_status, updated_at)
    values (v_row.store_id, v_row.order_id, v_row.seller_sku, greatest(0, v_delta), v_row.order_status, now())
    on conflict (store_id, order_id, seller_sku)
    do update set deducted_qty = greatest(0, public.tiktok_order_state.deducted_qty + v_delta), updated_at = now();

    insert into public.tiktok_corrections
      (order_row_id, batch_id, correction_batch_id, store_id, matched_kind, matched_id, qty_delta, reason, created_by)
    values (v_row.id, p_batch_id, v_cb, v_row.store_id, v_row.matched_kind, v_row.matched_id,
            v_delta, coalesce(nullif(trim(coalesce(v_i->>'reason','')),''), trim(p_reason)), auth.uid());
    v_n := v_n + 1;
  end loop;

  perform set_config('energia.tiktok_negative', '', true);
  update public.tiktok_import_batches set row_count = v_n where id = v_cb;
  perform public.write_audit_ex('tiktok_import_batches', v_cb, 'tiktok_correction_batch_created', null,
    jsonb_build_object('corrects', p_batch_id, 'items', v_n, 'reason', trim(p_reason)),
    'tiktok_import', trim(p_reason), v_b.store_id);
  return v_cb;
end $$;

-- Phase 15's single-row correction now records through a correction batch.
create or replace function public.correct_tiktok_row(p_row_id uuid, p_qty_delta integer, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare v_row public.tiktok_order_rows%rowtype;
begin
  select * into v_row from public.tiktok_order_rows where id = p_row_id;
  if not found then raise exception 'Row not found'; end if;
  perform public.create_tiktok_correction_batch(
    v_row.batch_id,
    jsonb_build_array(jsonb_build_object('row_id', p_row_id, 'qty_delta', p_qty_delta, 'reason', p_reason)),
    coalesce(p_reason, 'Correction'));
end $$;

notify pgrst, 'reload schema';
