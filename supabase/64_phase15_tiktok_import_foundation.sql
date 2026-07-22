-- =====================================================================
-- ENERGIA — PHASE 15: TIKTOK SALES IMPORT FOUNDATION
--
--  * Staging-first import: rows are uploaded, evaluated and shown with a
--    status; NOTHING touches stock until a batch is confirmed.
--  * Order IDs are TEXT end-to-end (19-digit TikTok IDs stay exact).
--  * Uniqueness: order header = store_id + order_id;
--                order item   = store_id + order_id + seller_sku.
--    Duplicate rows inside one file keep the first, later ones are marked
--    'Duplicate Row'.
--  * SKU matching is exact and case-sensitive; mappings are remembered as
--    store-specific aliases (store_id + seller_sku) targeting a product,
--    voucher or promotion. Inactive targets are refused.
--  * Confirmation applies stock deltas:
--      product   -> store_inventory
--      voucher   -> voucher_store_stock + an UNASSIGNED TikTok voucher
--                   issuance record linked to the order row (no customer
--                   is ever created from masked TikTok data)
--      promotion -> the EXISTING promotion_stock_items() resolution,
--                   multiplied by the TikTok quantity
--    and keeps cumulative per-item state so re-imports become
--    'Additional Deduction' / 'Stock Return' / 'Already Imported'.
--  * Access: Owner/Manager/Admin/Inventory Manager on any store; Staff on
--    their assigned store only. Deleting unconfirmed batches and
--    correcting confirmed batches is Owner/Manager only.
--  * Times are interpreted in Asia/Singapore.
--
-- Additive + idempotent. Run AFTER 63.
-- =====================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------
-- 1. Tables.
-- ---------------------------------------------------------------------
create table if not exists public.tiktok_import_batches (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id),
  file_kind text not null check (file_kind in ('order','settlement')),
  file_name text,
  sheet_name text,
  status text not null default 'staged' check (status in ('staged','confirmed')),
  row_count integer not null default 0,
  uploaded_by uuid references public.profiles(id),
  uploaded_at timestamptz not null default now(),
  confirmed_by uuid references public.profiles(id),
  confirmed_at timestamptz,
  deleted_at timestamptz,
  notes text
);

create table if not exists public.tiktok_order_rows (
  id uuid primary key default gen_random_uuid(),
  batch_id uuid not null references public.tiktok_import_batches(id) on delete cascade,
  store_id uuid not null references public.stores(id),
  row_no integer not null,
  -- TikTok IDs live as TEXT, always.
  order_id text,
  seller_sku text,
  product_name text,
  quantity integer,
  order_status text,
  sku_subtotal_before numeric(12,2),
  sku_subtotal_after numeric(12,2),
  refund_amount numeric(12,2),
  return_quantity integer,
  rts_time timestamptz,
  created_time timestamptz,
  paid_time timestamptz,
  shipped_time timestamptz,
  delivered_time timestamptz,
  cancelled_time timestamptz,
  tracking_id text,
  package_id text,
  warehouse text,
  shipping_provider text,
  payment_method text,
  category text,
  raw jsonb,
  staging_status text,
  stock_delta integer not null default 0,
  matched_kind text check (matched_kind in ('product','voucher','promotion')),
  matched_id uuid,
  excluded boolean not null default false,
  confirmed boolean not null default false,
  confirmed_at timestamptz
);
create index if not exists idx_ttrows_batch on public.tiktok_order_rows(batch_id);
create index if not exists idx_ttrows_order on public.tiktok_order_rows(store_id, order_id, seller_sku);

create table if not exists public.tiktok_settlement_rows (
  id uuid primary key default gen_random_uuid(),
  batch_id uuid not null references public.tiktok_import_batches(id) on delete cascade,
  store_id uuid not null references public.stores(id),
  row_no integer not null,
  order_id text,
  adjustment_id text,
  settlement_amount numeric(12,2),
  fee_amount numeric(12,2),
  revenue_amount numeric(12,2),
  currency text,
  settled_time timestamptz,
  raw jsonb
);
create index if not exists idx_ttsettle_batch on public.tiktok_settlement_rows(batch_id);
create index if not exists idx_ttsettle_order on public.tiktok_settlement_rows(store_id, order_id);

-- Store-specific SKU aliases. seller_sku comparisons are case-sensitive by
-- default text collation — exactly what the spec requires.
create table if not exists public.tiktok_sku_aliases (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id),
  seller_sku text not null,
  target_kind text not null check (target_kind in ('product','voucher','promotion')),
  target_id uuid not null,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (store_id, seller_sku)
);

-- Cumulative imported state per order item — the memory that turns a
-- re-import into 'Additional Deduction' / 'Stock Return' / 'Already Imported'.
create table if not exists public.tiktok_order_state (
  store_id uuid not null references public.stores(id),
  order_id text not null,
  seller_sku text not null,
  deducted_qty integer not null default 0,
  last_status text,
  updated_at timestamptz not null default now(),
  primary key (store_id, order_id, seller_sku)
);

-- Unassigned TikTok voucher issuances — linked to the order row, never to a
-- customer (TikTok buyer data is masked).
create table if not exists public.tiktok_voucher_sales (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id),
  voucher_id uuid not null references public.vouchers(id),
  order_row_id uuid references public.tiktok_order_rows(id) on delete set null,
  order_id text,
  seller_sku text,
  quantity integer not null,          -- negative = stock return
  created_at timestamptz not null default now()
);

create table if not exists public.tiktok_corrections (
  id uuid primary key default gen_random_uuid(),
  order_row_id uuid references public.tiktok_order_rows(id) on delete set null,
  batch_id uuid references public.tiktok_import_batches(id),
  store_id uuid not null references public.stores(id),
  matched_kind text,
  matched_id uuid,
  qty_delta integer not null,
  reason text,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now()
);

do $$ begin
  perform 1;
  alter table public.tiktok_import_batches enable row level security;
  alter table public.tiktok_order_rows enable row level security;
  alter table public.tiktok_settlement_rows enable row level security;
  alter table public.tiktok_sku_aliases enable row level security;
  alter table public.tiktok_order_state enable row level security;
  alter table public.tiktok_voucher_sales enable row level security;
  alter table public.tiktok_corrections enable row level security;
end $$;
do $$
declare t text;
begin
  foreach t in array array['tiktok_import_batches','tiktok_order_rows','tiktok_settlement_rows',
                           'tiktok_sku_aliases','tiktok_order_state','tiktok_voucher_sales','tiktok_corrections'] loop
    execute format('drop policy if exists "read %s" on public.%I', t, t);
    execute format('create policy "read %s" on public.%I for select to authenticated using (true)', t, t);
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- 2. Access helper. Upload/preview/map/confirm are open to every role
--    except that Staff are pinned to their assigned store(s).
-- ---------------------------------------------------------------------
create or replace function public.tiktok_access_check(p_store_id uuid)
returns void language plpgsql stable security definer set search_path = public as $$
declare v_role user_role := public.current_user_role();
begin
  if v_role is null then raise exception 'No profile for current user'; end if;
  if v_role in ('owner','manager','admin','inventory_manager') then return; end if;
  -- staff: assigned store only
  if not public.user_has_store_access(p_store_id) then
    raise exception 'You can only import TikTok sales for your assigned store'; end if;
end $$;

-- ---------------------------------------------------------------------
-- 3. Helpers: Singapore-time parsing, status effect, row evaluation.
-- ---------------------------------------------------------------------
create or replace function public.tiktok_parse_time(p_text text)
returns timestamptz language plpgsql immutable as $$
declare v text := nullif(trim(coalesce(p_text,'')),'');
begin
  if v is null then return null; end if;
  -- ISO-ish '2026-07-01 13:45[:00]' / '2026/07/01 13:45:00'
  begin return (replace(v,'/','-')::timestamp) at time zone 'Asia/Singapore';
  exception when others then null; end;
  -- TikTok's common 'DD/MM/YYYY HH24:MI[:SS]'
  begin return (to_timestamp(v, 'DD/MM/YYYY HH24:MI:SS')::timestamp) at time zone 'Asia/Singapore';
  exception when others then null; end;
  begin return (to_timestamp(v, 'DD/MM/YYYY HH24:MI')::timestamp) at time zone 'Asia/Singapore';
  exception when others then null; end;
  return null;
end $$;

-- deduct: the sale stands (stock leaves) · return: the sale is undone
-- · unknown: 'Invalid Status'
create or replace function public.tiktok_status_effect(p_status text)
returns text language sql immutable as $$
  select case
    when lower(trim(coalesce(p_status,''))) in
      ('to ship','to_ship','awaiting shipment','awaiting_shipment','awaiting collection','awaiting_collection',
       'shipped','in transit','in_transit','delivered','completed','complete','paid','packed')
      then 'deduct'
    when lower(trim(coalesce(p_status,''))) in
      ('cancelled','canceled','cancel','returned','refunded','returned/refunded','return','refund')
      then 'return'
    else 'invalid'
  end
$$;

-- Projected availability for a mapping at a store (used for the
-- 'Negative Stock Warning' status).
create or replace function public.tiktok_projected_short(
  p_store_id uuid, p_kind text, p_id uuid, p_delta integer
) returns boolean language plpgsql stable security definer set search_path = public as $$
declare v_comp record; v_have integer;
begin
  if p_delta <= 0 then return false; end if;
  if p_kind = 'product' then
    select coalesce(current_qty,0) into v_have from public.store_inventory
      where store_id = p_store_id and product_id = p_id;
    return coalesce(v_have,0) < p_delta;
  elsif p_kind = 'voucher' then
    if not exists (select 1 from public.vouchers where id = p_id and qty_type = 'limited') then return false; end if;
    select coalesce(current_qty,0) into v_have from public.voucher_store_stock
      where store_id = p_store_id and voucher_id = p_id;
    return coalesce(v_have,0) < p_delta;
  elsif p_kind = 'promotion' then
    for v_comp in select * from public.promotion_stock_items(p_id, p_delta) loop
      if v_comp.kind = 'product' then
        select coalesce(current_qty,0) into v_have from public.store_inventory
          where store_id = p_store_id and product_id = v_comp.item_id;
        if coalesce(v_have,0) < v_comp.quantity then return true; end if;
      elsif v_comp.kind = 'voucher' then
        select coalesce(current_qty,0) into v_have from public.voucher_store_stock
          where store_id = p_store_id and voucher_id = v_comp.item_id;
        if coalesce(v_have,0) < v_comp.quantity then return true; end if;
      end if;
    end loop;
    return false;
  end if;
  return false;
end $$;

-- One evaluator used by staging, re-staging and confirmation, so the three
-- can never disagree. Returns the staging status, the stock delta that
-- confirmation would apply, and the resolved mapping.
create or replace function public.tiktok_evaluate(
  p_store_id uuid, p_order_id text, p_seller_sku text,
  p_quantity integer, p_order_status text, p_is_duplicate boolean
) returns table (staging_status text, stock_delta integer, matched_kind text, matched_id uuid)
language plpgsql stable security definer set search_path = public as $$
declare
  v_alias public.tiktok_sku_aliases%rowtype;
  v_effect text; v_prev integer; v_target integer; v_delta integer;
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

  -- Exact, case-sensitive SKU match against the store's aliases.
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

  select coalesce(deducted_qty,0) into v_prev from public.tiktok_order_state
    where store_id = p_store_id and order_id = p_order_id and seller_sku = p_seller_sku;
  v_prev := coalesce(v_prev, 0);
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
-- 4. Staging. Rows arrive as parsed JSON from the client (which never
--    converts IDs to numbers); everything is stored, statuses computed,
--    and NO stock is touched.
-- ---------------------------------------------------------------------
create or replace function public.stage_tiktok_orders(
  p_store_id uuid, p_file_name text, p_sheet_name text, p_rows jsonb
) returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_batch uuid; v_r jsonb; v_no integer := 0;
  v_order text; v_sku text; v_qty integer; v_status text; v_dup boolean;
  v_eval record;
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

    -- Duplicate inside THIS file (store + order + sku): keep first.
    v_dup := exists (select 1 from public.tiktok_order_rows
                      where batch_id = v_batch and order_id = v_order and seller_sku = v_sku
                        and v_order is not null and v_sku is not null);

    select * into v_eval from public.tiktok_evaluate(p_store_id, v_order, v_sku, v_qty, v_status, v_dup);

    insert into public.tiktok_order_rows (
      batch_id, store_id, row_no, order_id, seller_sku, product_name, quantity, order_status,
      sku_subtotal_before, sku_subtotal_after, refund_amount, return_quantity,
      rts_time, created_time, paid_time, shipped_time, delivered_time, cancelled_time,
      tracking_id, package_id, warehouse, shipping_provider, payment_method, category, raw,
      staging_status, stock_delta, matched_kind, matched_id)
    values (
      v_batch, p_store_id, v_no, v_order, v_sku,
      nullif(trim(coalesce(v_r->>'product_name','')),''), v_qty, v_status,
      nullif(v_r->>'sku_subtotal_before','')::numeric, nullif(v_r->>'sku_subtotal_after','')::numeric,
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
      v_eval.staging_status, v_eval.stock_delta, v_eval.matched_kind, v_eval.matched_id);
  end loop;

  update public.tiktok_import_batches set row_count = v_no where id = v_batch;
  perform public.write_audit_ex('tiktok_import_batches', v_batch, 'tiktok_orders_staged', null,
    jsonb_build_object('file', p_file_name, 'sheet', p_sheet_name, 'rows', v_no),
    'tiktok_import', null, p_store_id);
  return v_batch;
end $$;

create or replace function public.stage_tiktok_settlement(
  p_store_id uuid, p_file_name text, p_sheet_name text, p_rows jsonb
) returns uuid language plpgsql security definer set search_path = public as $$
declare v_batch uuid; v_r jsonb; v_no integer := 0;
begin
  perform public.tiktok_access_check(p_store_id);
  if p_rows is null or jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) = 0 then
    raise exception 'No rows to import'; end if;

  insert into public.tiktok_import_batches (store_id, file_kind, file_name, sheet_name, uploaded_by)
  values (p_store_id, 'settlement', p_file_name, p_sheet_name, auth.uid())
  returning id into v_batch;

  for v_r in select * from jsonb_array_elements(p_rows) loop
    v_no := v_no + 1;
    insert into public.tiktok_settlement_rows (
      batch_id, store_id, row_no, order_id, adjustment_id,
      settlement_amount, fee_amount, revenue_amount, currency, settled_time, raw)
    values (
      v_batch, p_store_id, v_no,
      nullif(trim(coalesce(v_r->>'order_id','')),''), nullif(trim(coalesce(v_r->>'adjustment_id','')),''),
      nullif(v_r->>'settlement_amount','')::numeric, nullif(v_r->>'fee_amount','')::numeric,
      nullif(v_r->>'revenue_amount','')::numeric, nullif(trim(coalesce(v_r->>'currency','')),''),
      public.tiktok_parse_time(v_r->>'settled_time'), v_r);
  end loop;

  update public.tiktok_import_batches set row_count = v_no where id = v_batch;
  perform public.write_audit_ex('tiktok_import_batches', v_batch, 'tiktok_settlement_staged', null,
    jsonb_build_object('file', p_file_name, 'sheet', p_sheet_name, 'rows', v_no),
    'tiktok_import', null, p_store_id);
  return v_batch;
end $$;

-- Re-evaluate all unconfirmed rows of a staged batch (after new mappings).
create or replace function public.refresh_tiktok_staging(p_batch_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_b public.tiktok_import_batches%rowtype; v_row record; v_eval record;
begin
  select * into v_b from public.tiktok_import_batches where id = p_batch_id and deleted_at is null;
  if not found then raise exception 'Batch not found'; end if;
  perform public.tiktok_access_check(v_b.store_id);
  if v_b.status <> 'staged' then raise exception 'Confirmed batches are locked'; end if;

  for v_row in select * from public.tiktok_order_rows where batch_id = p_batch_id and not confirmed loop
    select * into v_eval from public.tiktok_evaluate(
      v_row.store_id, v_row.order_id, v_row.seller_sku, v_row.quantity, v_row.order_status,
      v_row.staging_status = 'Duplicate Row');
    update public.tiktok_order_rows
       set staging_status = v_eval.staging_status, stock_delta = v_eval.stock_delta,
           matched_kind = v_eval.matched_kind, matched_id = v_eval.matched_id
     where id = v_row.id;
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- 5. SKU aliases — remembered per store; inactive targets refused.
-- ---------------------------------------------------------------------
create or replace function public.upsert_tiktok_sku_alias(
  p_store_id uuid, p_seller_sku text, p_target_kind text, p_target_id uuid
) returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_ok boolean := false; v_name text;
begin
  perform public.tiktok_access_check(p_store_id);
  if nullif(coalesce(p_seller_sku,''),'') is null then raise exception 'Seller SKU is required'; end if;
  if p_target_kind not in ('product','voucher','promotion') then
    raise exception 'Mapping target must be a product, voucher or promotion'; end if;

  if p_target_kind = 'product' then
    select is_active and deleted_at is null, name into v_ok, v_name from public.products where id = p_target_id;
  elsif p_target_kind = 'voucher' then
    select is_active and deleted_at is null, name into v_ok, v_name from public.vouchers where id = p_target_id;
  else
    select is_active and deleted_at is null, name into v_ok, v_name from public.promotions where id = p_target_id;
  end if;
  if v_ok is null then raise exception 'Mapping target not found'; end if;
  if not v_ok then raise exception 'Cannot map to an inactive %', p_target_kind; end if;

  insert into public.tiktok_sku_aliases (store_id, seller_sku, target_kind, target_id, created_by)
  values (p_store_id, p_seller_sku, p_target_kind, p_target_id, auth.uid())
  on conflict (store_id, seller_sku)
  do update set target_kind = excluded.target_kind, target_id = excluded.target_id, updated_at = now()
  returning id into v_id;

  perform public.write_audit_ex('tiktok_sku_aliases', v_id, 'tiktok_sku_mapped', null,
    jsonb_build_object('seller_sku', p_seller_sku, 'target_kind', p_target_kind, 'target', v_name),
    'tiktok_import', null, p_store_id);
  return v_id;
end $$;

-- ---------------------------------------------------------------------
-- 6. Staging management: exclude / remove rows; delete batches (O/M only).
-- ---------------------------------------------------------------------
create or replace function public.set_tiktok_row_excluded(p_row_id uuid, p_excluded boolean)
returns void language plpgsql security definer set search_path = public as $$
declare v_row public.tiktok_order_rows%rowtype; v_b public.tiktok_import_batches%rowtype;
begin
  select * into v_row from public.tiktok_order_rows where id = p_row_id;
  if not found then raise exception 'Row not found'; end if;
  select * into v_b from public.tiktok_import_batches where id = v_row.batch_id;
  perform public.tiktok_access_check(v_b.store_id);
  if v_b.status <> 'staged' or v_b.deleted_at is not null then raise exception 'Confirmed batches are locked'; end if;
  update public.tiktok_order_rows set excluded = p_excluded where id = p_row_id;
end $$;

create or replace function public.delete_tiktok_row(p_row_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_row public.tiktok_order_rows%rowtype; v_b public.tiktok_import_batches%rowtype;
begin
  select * into v_row from public.tiktok_order_rows where id = p_row_id;
  if not found then raise exception 'Row not found'; end if;
  select * into v_b from public.tiktok_import_batches where id = v_row.batch_id;
  perform public.tiktok_access_check(v_b.store_id);
  if v_b.status <> 'staged' or v_b.deleted_at is not null then raise exception 'Confirmed batches are locked'; end if;
  delete from public.tiktok_order_rows where id = p_row_id;
  update public.tiktok_import_batches set row_count = greatest(0, row_count - 1) where id = v_b.id;
end $$;

create or replace function public.delete_tiktok_batch(p_batch_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_b public.tiktok_import_batches%rowtype;
begin
  if public.current_user_role() not in ('owner','manager') then
    raise exception 'Only Owners and Managers can delete import batches'; end if;
  select * into v_b from public.tiktok_import_batches where id = p_batch_id and deleted_at is null;
  if not found then raise exception 'Batch not found'; end if;
  if v_b.status <> 'staged' then
    raise exception 'A confirmed batch cannot be deleted — create a correction instead'; end if;
  update public.tiktok_import_batches set deleted_at = now() where id = p_batch_id;
  perform public.write_audit_ex('tiktok_import_batches', p_batch_id, 'tiktok_batch_deleted', null,
    jsonb_build_object('file', v_b.file_name, 'rows', v_b.row_count),
    'tiktok_import', null, v_b.store_id);
end $$;

-- ---------------------------------------------------------------------
-- 7. Confirmation — the ONLY place stock moves. Each selected row is
--    re-evaluated against live state at confirm time, so a stale preview
--    can never double-deduct.
-- ---------------------------------------------------------------------
create or replace function public.tiktok_adjust_product_stock(p_store_id uuid, p_product_id uuid, p_delta integer)
returns void language plpgsql security definer set search_path = public as $$
begin
  -- store_inventory has a hard current_qty >= 0 constraint, so deductions
  -- clamp at zero — the shortfall is what 'Negative Stock Warning' flagged.
  update public.store_inventory
     set current_qty = greatest(0, current_qty - p_delta), updated_at = now()
   where store_id = p_store_id and product_id = p_product_id;
  if not found then
    insert into public.store_inventory (store_id, product_id, current_qty)
    values (p_store_id, p_product_id, greatest(0, -p_delta));
  end if;
end $$;

create or replace function public.tiktok_adjust_voucher_stock(p_store_id uuid, p_voucher_id uuid, p_delta integer)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from public.vouchers where id = p_voucher_id and qty_type = 'limited') then return; end if;
  update public.voucher_store_stock
     set current_qty = greatest(0, current_qty - p_delta), updated_at = now()
   where store_id = p_store_id and voucher_id = p_voucher_id;
  if not found then
    insert into public.voucher_store_stock (voucher_id, store_id, current_qty)
    values (p_voucher_id, p_store_id, greatest(0, -p_delta));
  end if;
end $$;

create or replace function public.apply_tiktok_stock_delta(
  p_store_id uuid, p_kind text, p_id uuid, p_delta integer,
  p_row_id uuid, p_order_id text, p_sku text, p_note text
) returns void language plpgsql security definer set search_path = public as $$
declare v_comp record;
begin
  if p_delta = 0 then return; end if;

  if p_kind = 'product' then
    perform public.tiktok_adjust_product_stock(p_store_id, p_id, p_delta);
    insert into public.stock_movements (product_id, movement_type, from_store_id, quantity, notes, created_by)
    values (p_id, (case when p_delta > 0 then 'store_sale' else 'inventory_adjustment' end)::stock_movement_type,
            p_store_id, abs(p_delta), coalesce(p_note,'TikTok import') || ' — order ' || coalesce(p_order_id,'?'), auth.uid());

  elsif p_kind = 'voucher' then
    perform public.tiktok_adjust_voucher_stock(p_store_id, p_id, p_delta);
    -- The unassigned issuance record (negative quantity = return). No
    -- customer is ever created from masked TikTok data.
    insert into public.tiktok_voucher_sales (store_id, voucher_id, order_row_id, order_id, seller_sku, quantity)
    values (p_store_id, p_id, p_row_id, p_order_id, p_sku, p_delta);

  elsif p_kind = 'promotion' then
    -- Existing component resolution, multiplied by the TikTok quantity.
    for v_comp in select * from public.promotion_stock_items(p_id, abs(p_delta)) loop
      if v_comp.kind = 'product' then
        perform public.tiktok_adjust_product_stock(p_store_id, v_comp.item_id,
          case when p_delta > 0 then v_comp.quantity else -v_comp.quantity end);
        insert into public.stock_movements (product_id, movement_type, from_store_id, quantity, notes, created_by)
        values (v_comp.item_id, (case when p_delta > 0 then 'store_sale' else 'inventory_adjustment' end)::stock_movement_type,
                p_store_id, v_comp.quantity,
                coalesce(p_note,'TikTok import') || ' (promotion component) — order ' || coalesce(p_order_id,'?'), auth.uid());
      elsif v_comp.kind = 'voucher' then
        perform public.tiktok_adjust_voucher_stock(p_store_id, v_comp.item_id,
          case when p_delta > 0 then v_comp.quantity else -v_comp.quantity end);
      end if;
    end loop;
  end if;
end $$;

create or replace function public.confirm_tiktok_batch(p_batch_id uuid, p_row_ids jsonb default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_b public.tiktok_import_batches%rowtype; v_row record; v_eval record;
  v_applied integer := 0; v_skipped integer := 0; v_deducted integer := 0; v_returned integer := 0;
  v_selected boolean;
begin
  select * into v_b from public.tiktok_import_batches where id = p_batch_id and deleted_at is null for update;
  if not found then raise exception 'Batch not found'; end if;
  perform public.tiktok_access_check(v_b.store_id);
  if v_b.file_kind <> 'order' then raise exception 'Only order batches can be confirmed for stock'; end if;
  if v_b.status <> 'staged' then raise exception 'This batch is already confirmed and locked'; end if;

  for v_row in select * from public.tiktok_order_rows where batch_id = p_batch_id order by row_no loop
    v_selected := (p_row_ids is null or p_row_ids @> to_jsonb(v_row.id::text));
    if not v_selected or v_row.excluded or v_row.confirmed then
      if not v_row.confirmed then
        update public.tiktok_order_rows set excluded = true where id = v_row.id;
        v_skipped := v_skipped + 1;
      end if;
      continue;
    end if;

    -- Live re-evaluation: staging previews can be stale.
    select * into v_eval from public.tiktok_evaluate(
      v_row.store_id, v_row.order_id, v_row.seller_sku, v_row.quantity, v_row.order_status,
      v_row.staging_status = 'Duplicate Row');

    if v_eval.staging_status in ('Invalid Row','Duplicate Row','Unmatched SKU','Invalid Status') then
      update public.tiktok_order_rows
         set staging_status = v_eval.staging_status, stock_delta = 0, excluded = true where id = v_row.id;
      v_skipped := v_skipped + 1;
      continue;
    end if;

    perform public.apply_tiktok_stock_delta(
      v_row.store_id, v_eval.matched_kind, v_eval.matched_id, v_eval.stock_delta,
      v_row.id, v_row.order_id, v_row.seller_sku, 'TikTok import ' || coalesce(v_b.file_name,''));

    insert into public.tiktok_order_state (store_id, order_id, seller_sku, deducted_qty, last_status, updated_at)
    values (v_row.store_id, v_row.order_id, v_row.seller_sku,
            case when public.tiktok_status_effect(v_row.order_status) = 'deduct' then v_row.quantity else 0 end,
            v_row.order_status, now())
    on conflict (store_id, order_id, seller_sku)
    do update set deducted_qty = excluded.deducted_qty, last_status = excluded.last_status, updated_at = now();

    update public.tiktok_order_rows
       set staging_status = v_eval.staging_status, stock_delta = v_eval.stock_delta,
           matched_kind = v_eval.matched_kind, matched_id = v_eval.matched_id,
           confirmed = true, confirmed_at = now()
     where id = v_row.id;

    v_applied := v_applied + 1;
    if v_eval.stock_delta > 0 then v_deducted := v_deducted + v_eval.stock_delta;
    elsif v_eval.stock_delta < 0 then v_returned := v_returned - v_eval.stock_delta; end if;
  end loop;

  update public.tiktok_import_batches
     set status = 'confirmed', confirmed_by = auth.uid(), confirmed_at = now()
   where id = p_batch_id;

  perform public.write_audit_ex('tiktok_import_batches', p_batch_id, 'tiktok_batch_confirmed', null,
    jsonb_build_object('file', v_b.file_name, 'applied', v_applied, 'skipped', v_skipped,
                       'units_deducted', v_deducted, 'units_returned', v_returned),
    'tiktok_import', null, v_b.store_id);

  return jsonb_build_object('success', true, 'applied', v_applied, 'skipped', v_skipped,
                            'units_deducted', v_deducted, 'units_returned', v_returned);
end $$;

-- ---------------------------------------------------------------------
-- 8. Corrections on CONFIRMED batches — Owner/Manager only.
--    qty_delta > 0 deducts more stock; < 0 returns stock. State follows.
-- ---------------------------------------------------------------------
create or replace function public.correct_tiktok_row(p_row_id uuid, p_qty_delta integer, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare v_row public.tiktok_order_rows%rowtype; v_b public.tiktok_import_batches%rowtype;
begin
  if public.current_user_role() not in ('owner','manager') then
    raise exception 'Only Owners and Managers can correct confirmed imports'; end if;
  if coalesce(p_qty_delta,0) = 0 then raise exception 'Correction quantity cannot be zero'; end if;
  if nullif(trim(coalesce(p_reason,'')),'') is null then raise exception 'A correction reason is required'; end if;

  select * into v_row from public.tiktok_order_rows where id = p_row_id;
  if not found then raise exception 'Row not found'; end if;
  select * into v_b from public.tiktok_import_batches where id = v_row.batch_id;
  if v_b.status <> 'confirmed' then raise exception 'Corrections apply to confirmed batches only'; end if;
  if v_row.matched_kind is null or v_row.matched_id is null then
    raise exception 'This row has no mapping to correct against'; end if;

  perform public.apply_tiktok_stock_delta(
    v_row.store_id, v_row.matched_kind, v_row.matched_id, p_qty_delta,
    v_row.id, v_row.order_id, v_row.seller_sku, 'TikTok correction');

  insert into public.tiktok_order_state (store_id, order_id, seller_sku, deducted_qty, last_status, updated_at)
  values (v_row.store_id, v_row.order_id, v_row.seller_sku, greatest(0, p_qty_delta), v_row.order_status, now())
  on conflict (store_id, order_id, seller_sku)
  do update set deducted_qty = greatest(0, public.tiktok_order_state.deducted_qty + p_qty_delta), updated_at = now();

  insert into public.tiktok_corrections
    (order_row_id, batch_id, store_id, matched_kind, matched_id, qty_delta, reason, created_by)
  values (p_row_id, v_row.batch_id, v_row.store_id, v_row.matched_kind, v_row.matched_id,
          p_qty_delta, trim(p_reason), auth.uid());

  perform public.write_audit_ex('tiktok_order_rows', p_row_id, 'tiktok_correction', null,
    jsonb_build_object('order_id', v_row.order_id, 'seller_sku', v_row.seller_sku,
                       'qty_delta', p_qty_delta, 'reason', trim(p_reason)),
    'tiktok_import', trim(p_reason), v_row.store_id);
end $$;

-- ---------------------------------------------------------------------
-- 9. Reports. Staff see only stores they can access.
-- ---------------------------------------------------------------------
create or replace function public.report_tiktok_imports(
  p_store_id uuid default null, p_from date default null, p_to date default null
) returns table (
  batch_id uuid, store_name text, file_kind text, file_name text, status text,
  uploaded_at timestamptz, uploaded_by_name text, row_count integer,
  confirmed_rows bigint, units_deducted bigint, units_returned bigint, unmatched bigint
) language sql stable security definer set search_path = public as $$
  select b.id, s.name, b.file_kind, b.file_name, b.status,
         b.uploaded_at, p.full_name, b.row_count,
         (select count(*) from public.tiktok_order_rows r where r.batch_id = b.id and r.confirmed),
         (select coalesce(sum(r.stock_delta),0) from public.tiktok_order_rows r
           where r.batch_id = b.id and r.confirmed and r.stock_delta > 0),
         (select coalesce(-sum(r.stock_delta),0) from public.tiktok_order_rows r
           where r.batch_id = b.id and r.confirmed and r.stock_delta < 0),
         (select count(*) from public.tiktok_order_rows r
           where r.batch_id = b.id and r.staging_status = 'Unmatched SKU')
    from public.tiktok_import_batches b
    join public.stores s on s.id = b.store_id
    left join public.profiles p on p.id = b.uploaded_by
   where b.deleted_at is null
     and (p_store_id is null or b.store_id = p_store_id)
     and (p_from is null or b.uploaded_at::date >= p_from)
     and (p_to is null or b.uploaded_at::date <= p_to)
     and (public.current_user_role() in ('owner','manager','admin','inventory_manager')
          or public.user_has_store_access(b.store_id))
   order by b.uploaded_at desc
$$;

notify pgrst, 'reload schema';
