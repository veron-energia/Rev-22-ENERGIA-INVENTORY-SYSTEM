-- =====================================================================
-- ENERGIA — IN-STORE USE, AND FULFILLING AN INVOICE FROM A WAREHOUSE
--
--   1. "Use" — staff record stock consumed in the store (demo units, samples,
--      testers, internal use). Stock reduces immediately, with a reason and a
--      full audit trail. This is deliberately NOT an adjustment: an adjustment
--      corrects a counting error and needs approval, whereas a use is a real
--      consumption that staff should be able to record themselves.
--
--   2. An invoice can be FULFILLED FROM A WAREHOUSE instead of store stock.
--      The invoice still belongs to a store — that is what prices the lines,
--      earns commission and drives every report — but the goods come out of
--      warehouse inventory. Owner/Manager only.
--
-- Additive and idempotent. Run AFTER 84.
-- =====================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------
-- 1. Stock used in the store.
-- ---------------------------------------------------------------------
create table if not exists public.stock_uses (
  id uuid primary key default gen_random_uuid(),
  use_no text unique,
  location_type text not null check (location_type in ('store','warehouse')),
  store_id uuid references public.stores(id),
  warehouse_id uuid references public.warehouses(id),
  product_id uuid not null references public.products(id),
  quantity integer not null check (quantity > 0),
  reason text not null,
  note text,
  used_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  constraint stock_use_location_present check (
    (location_type = 'store' and store_id is not null and warehouse_id is null) or
    (location_type = 'warehouse' and warehouse_id is not null and store_id is null))
);
create index if not exists idx_stock_uses_product on public.stock_uses (product_id, created_at desc);
alter table public.stock_uses enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where schemaname='public'
                  and tablename='stock_uses' and policyname='read stock uses') then
    create policy "read stock uses" on public.stock_uses for select to authenticated using (true);
  end if;
end $$;

create sequence if not exists public.stock_use_no_seq;
create or replace function public.next_stock_use_no()
returns text language sql security definer set search_path to 'public' as $function$
  select 'USE-' || lpad(nextval('stock_use_no_seq')::text, 6, '0')
$function$;

create or replace function public.record_stock_use(
  p_location_type text, p_location_id uuid, p_product_id uuid,
  p_quantity integer, p_reason text, p_note text default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare
  v_id uuid; v_no text; v_have integer; v_name text;
begin
  if p_location_type not in ('store','warehouse') then
    raise exception 'Location must be a store or a warehouse'; end if;
  if coalesce(p_quantity,0) <= 0 then raise exception 'Quantity must be greater than zero'; end if;
  if coalesce(trim(p_reason),'') = '' then raise exception 'A reason is required'; end if;
  if p_location_type = 'store' and not public.user_has_store_access(p_location_id) then
    raise exception 'No access to this store'; end if;

  select name into v_name from public.products where id = p_product_id;
  if v_name is null then raise exception 'Product not found'; end if;

  -- Stock must actually be there; using more than is held would leave a
  -- negative balance, which is never allowed.
  if p_location_type = 'store' then
    select current_qty into v_have from public.store_inventory
     where store_id = p_location_id and product_id = p_product_id for update;
    if coalesce(v_have,0) < p_quantity then
      raise exception 'Only % of "%" in stock at this store', coalesce(v_have,0), v_name; end if;
    update public.store_inventory set current_qty = current_qty - p_quantity, updated_at = now()
     where store_id = p_location_id and product_id = p_product_id;
  else
    select current_qty into v_have from public.warehouse_inventory
     where warehouse_id = p_location_id and product_id = p_product_id for update;
    if coalesce(v_have,0) < p_quantity then
      raise exception 'Only % of "%" in stock at this warehouse', coalesce(v_have,0), v_name; end if;
    update public.warehouse_inventory set current_qty = current_qty - p_quantity, updated_at = now()
     where warehouse_id = p_location_id and product_id = p_product_id;
  end if;

  v_no := public.next_stock_use_no();
  insert into public.stock_uses (use_no, location_type, store_id, warehouse_id,
    product_id, quantity, reason, note, used_by)
  values (v_no, p_location_type,
    case when p_location_type = 'store' then p_location_id end,
    case when p_location_type = 'warehouse' then p_location_id end,
    p_product_id, p_quantity, trim(p_reason), p_note, auth.uid())
  returning id into v_id;

  perform public.write_audit_ex('stock_uses', v_id, 'stock_used', null,
    jsonb_build_object('product', v_name, 'quantity', p_quantity, 'reason', trim(p_reason),
      'location_type', p_location_type),
    'inventory', trim(p_reason),
    case when p_location_type = 'store' then p_location_id end);

  return jsonb_build_object('success', true, 'use_no', v_no,
    'remaining', coalesce(v_have,0) - p_quantity);
end $function$;

-- ---------------------------------------------------------------------
-- 2. Fulfilling an invoice from a warehouse.
--    The invoice still belongs to its store for pricing, commission and
--    reporting; only where the stock comes from changes.
-- ---------------------------------------------------------------------
alter table public.invoices
  add column if not exists fulfil_warehouse_id uuid references public.warehouses(id);

create or replace function public.set_invoice_fulfilment_warehouse(
  p_invoice_id uuid, p_warehouse_id uuid)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare v_inv public.invoices%rowtype; v_it record; v_have integer; v_short text[] := '{}';
begin
  if not public.is_owner_or_manager() then
    raise exception 'Only an Owner or Manager can fulfil an invoice from a warehouse'; end if;
  select * into v_inv from public.invoices where id = p_invoice_id for update;
  if not found then raise exception 'Invoice not found'; end if;
  if v_inv.status not in ('draft','unpaid','partially_paid') then
    raise exception 'The fulfilment source cannot change once the invoice is settled'; end if;

  if p_warehouse_id is null then
    update public.invoices set fulfil_warehouse_id = null where id = p_invoice_id;
    return jsonb_build_object('success', true, 'fulfil_from', 'store');
  end if;

  if not exists (select 1 from public.warehouses where id = p_warehouse_id and deleted_at is null) then
    raise exception 'Warehouse not found'; end if;

  -- Check the warehouse can actually cover the physical lines.
  for v_it in
    select ii.product_id, sum(ii.quantity) as qty, p.name
      from public.invoice_items ii join public.products p on p.id = ii.product_id
     where ii.invoice_id = p_invoice_id and ii.line_kind = 'product' and ii.product_id is not null
     group by ii.product_id, p.name
  loop
    select coalesce(current_qty,0) into v_have from public.warehouse_inventory
     where warehouse_id = p_warehouse_id and product_id = v_it.product_id;
    if coalesce(v_have,0) < v_it.qty then
      v_short := array_append(v_short, v_it.name || ' (need ' || v_it.qty || ', have ' || coalesce(v_have,0) || ')');
    end if;
  end loop;
  if array_length(v_short,1) is not null then
    raise exception 'That warehouse cannot cover this invoice: %', array_to_string(v_short, '; ');
  end if;

  update public.invoices set fulfil_warehouse_id = p_warehouse_id where id = p_invoice_id;
  perform public.write_audit_ex('invoices', p_invoice_id, 'invoice_fulfilment_set', null,
    jsonb_build_object('warehouse', p_warehouse_id), 'inventory', null, v_inv.store_id);
  return jsonb_build_object('success', true, 'fulfil_from', 'warehouse');
end $function$;

-- When the invoice settles, take the stock from the warehouse instead of the
-- store, and put back whatever the normal store deduction removed.
create or replace function public.trg_fulfil_from_warehouse()
returns trigger language plpgsql security definer set search_path to 'public' as $function$
declare v_it record; v_have integer;
begin
  if new.fulfil_warehouse_id is null then return null; end if;
  if new.status not in ('paid','completed_foc') or old.status is not distinct from new.status then
    return null; end if;

  for v_it in
    select ii.product_id, sum(ii.quantity) as qty, p.name
      from public.invoice_items ii join public.products p on p.id = ii.product_id
     where ii.invoice_id = new.id and ii.line_kind = 'product' and ii.product_id is not null
     group by ii.product_id, p.name
  loop
    select coalesce(current_qty,0) into v_have from public.warehouse_inventory
     where warehouse_id = new.fulfil_warehouse_id and product_id = v_it.product_id for update;
    if coalesce(v_have,0) < v_it.qty then
      raise exception 'Warehouse stock ran out for "%" (need %, have %)',
        v_it.name, v_it.qty, coalesce(v_have,0);
    end if;
    update public.warehouse_inventory
       set current_qty = current_qty - v_it.qty, updated_at = now()
     where warehouse_id = new.fulfil_warehouse_id and product_id = v_it.product_id;

    -- Give back the store stock the normal paid-invoice flow removed, so the
    -- goods are only ever counted out once.
    update public.store_inventory
       set current_qty = current_qty + v_it.qty, updated_at = now()
     where store_id = new.store_id and product_id = v_it.product_id;
  end loop;

  perform public.write_audit_ex('invoices', new.id, 'invoice_fulfilled_from_warehouse', null,
    jsonb_build_object('warehouse', new.fulfil_warehouse_id), 'inventory', null, new.store_id);
  return null;
end $function$;

drop trigger if exists fulfil_from_warehouse on public.invoices;
create trigger fulfil_from_warehouse after update on public.invoices
  for each row execute function public.trg_fulfil_from_warehouse();

notify pgrst, 'reload schema';
