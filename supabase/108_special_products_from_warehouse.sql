-- =====================================================================
-- ENERGIA — SPECIAL PRODUCTS ARE WAREHOUSE PRODUCTS
--
-- Until now a Special Product was a SEPARATE record with its OWN stock table,
-- so the same physical machine could exist twice with two unrelated counts.
--
-- From here a special product IS a warehouse product:
--
--   * you pick an existing product and give it sale/rental rates, rather than
--     retyping its name and stock;
--   * there is ONE stock pool. Renting a unit reduces the same warehouse stock
--     a transfer would draw on, so the two can never disagree;
--   * a returned rental goes back into the warehouse it came from;
--   * PENDING transfer requests hold stock back: if the last unit is already
--     claimed by an unapproved request, releasing a rental is refused.
--     (Approved transfers already deduct, so only pending ones are an
--     unreflected claim.)
--
-- special_product_stock is retired. It is left in place but no longer read or
-- written, so nothing is destroyed if this needs reviewing.
--
-- Additive and idempotent. Run AFTER 107.
-- =====================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------
-- 1. A special product now points at a real product.
-- ---------------------------------------------------------------------
alter table public.special_products add column if not exists product_id uuid references public.products(id);
create unique index if not exists uq_special_products_product
  on public.special_products (product_id) where product_id is not null and deleted_at is null;

-- name and sku become derived rather than typed, so they cannot drift.
create or replace function public.special_product_name(p_special_product_id uuid)
returns text language sql stable security definer set search_path to 'public' as $function$
  select coalesce(p.name, sp.name)
    from public.special_products sp
    left join public.products p on p.id = sp.product_id
   where sp.id = p_special_product_id
$function$;

-- ---------------------------------------------------------------------
-- 2. What is actually available, honouring pending transfer claims.
--
--    Approved transfers have already deducted, so only PENDING requests are a
--    claim the stock figure does not yet reflect.
-- ---------------------------------------------------------------------
create or replace function public.warehouse_available_qty(
  p_warehouse_id uuid, p_product_id uuid)
returns table(on_hand integer, reserved integer, available integer)
language sql stable security definer set search_path to 'public' as $function$
  with hand as (
    select coalesce(wi.current_qty, 0)::integer as q
      from public.warehouse_inventory wi
     where wi.warehouse_id = p_warehouse_id and wi.product_id = p_product_id
  ),
  claimed as (
    -- Pending requests sourced from this warehouse, plus pending per-line
    -- allocations against it.
    select coalesce(sum(l.quantity), 0)::integer as q
      from public.transfer_request_lines l
      join public.transfer_requests r on r.id = l.transfer_request_id
     where r.status = 'pending'
       and l.product_id = p_product_id
       and (
         -- Named this warehouse as the source...
         r.source_id = p_warehouse_id
         -- ...or allocated to it per line at approval...
         or exists (select 1 from public.transfer_line_sources ts
                     where ts.line_id = l.id and ts.source_id = p_warehouse_id)
         -- ...or has NO source yet. A deferred request (raised by staff, or by
         -- an Owner leaving the warehouse open) is still a real claim on the
         -- stock: the warehouse is simply not decided. Ignoring these would let
         -- the last unit be rented out from under a request that is about to be
         -- approved, which is exactly what must be prevented.
         or (r.source_id is null
             and not exists (select 1 from public.transfer_line_sources ts2
                              where ts2.line_id = l.id))
       )
  )
  select coalesce((select q from hand), 0),
         coalesce((select q from claimed), 0),
         greatest(coalesce((select q from hand), 0) - coalesce((select q from claimed), 0), 0)
$function$;

-- Where a special product can be released from, for the picker.
create or replace function public.special_product_availability(p_special_product_id uuid)
returns table(warehouse_id uuid, warehouse_name text,
              on_hand integer, reserved integer, available integer)
language sql stable security definer set search_path to 'public' as $function$
  select w.id, w.name, a.on_hand, a.reserved, a.available
    from public.warehouses w
    join public.special_products sp on sp.id = p_special_product_id
    cross join lateral public.warehouse_available_qty(w.id, sp.product_id) a
   where w.deleted_at is null
   order by a.available desc, w.name
$function$;

-- ---------------------------------------------------------------------
-- 3. Adding a special product = choosing a product and pricing it.
-- ---------------------------------------------------------------------
create or replace function public.upsert_special_product_from_product(
  p_id uuid, p_product_id uuid,
  p_sale_price numeric default null, p_rate_day numeric default null,
  p_rate_week numeric default null, p_rate_month numeric default null,
  p_rate_year numeric default null, p_late_fee_per_day numeric default null,
  p_description text default null, p_is_active boolean default true)
returns uuid language plpgsql security definer set search_path to 'public' as $function$
declare v_id uuid; v_name text; v_sku text;
begin
  if not public.is_owner_or_manager() then
    raise exception 'Only an Owner or Manager can manage special products'; end if;
  if p_product_id is null then raise exception 'Choose a product'; end if;

  select name, sku into v_name, v_sku from public.products
   where id = p_product_id and deleted_at is null;
  if v_name is null then raise exception 'That product does not exist'; end if;

  if coalesce(p_sale_price,0) <= 0
     and coalesce(p_rate_day,0) <= 0 and coalesce(p_rate_week,0) <= 0
     and coalesce(p_rate_month,0) <= 0 and coalesce(p_rate_year,0) <= 0 then
    raise exception 'Set a sale price or at least one rental rate, or this cannot be sold or rented';
  end if;

  if p_id is null then
    -- Already added: update rather than creating a duplicate for the same product.
    select id into v_id from public.special_products
     where product_id = p_product_id and deleted_at is null;
  else
    v_id := p_id;
  end if;

  if v_id is null then
    insert into public.special_products
      (name, sku, product_id, sale_price, rate_day, rate_week, rate_month, rate_year,
       late_fee_per_day, description, is_active)
    values (v_name, v_sku, p_product_id, coalesce(p_sale_price,0),
       coalesce(p_rate_day,0), coalesce(p_rate_week,0), coalesce(p_rate_month,0),
       coalesce(p_rate_year,0), coalesce(p_late_fee_per_day,0), p_description,
       coalesce(p_is_active,true))
    returning id into v_id;
  else
    update public.special_products set
      name = v_name, sku = v_sku, product_id = p_product_id,
      sale_price = coalesce(p_sale_price, sale_price),
      rate_day = coalesce(p_rate_day, rate_day),
      rate_week = coalesce(p_rate_week, rate_week),
      rate_month = coalesce(p_rate_month, rate_month),
      rate_year = coalesce(p_rate_year, rate_year),
      late_fee_per_day = coalesce(p_late_fee_per_day, late_fee_per_day),
      description = coalesce(p_description, description),
      is_active = coalesce(p_is_active, is_active)
    where id = v_id;
  end if;

  perform public.write_audit_ex('special_products', v_id, 'special_product_saved', null,
    jsonb_build_object('product', v_name, 'sku', v_sku), 'catalogue', null, null);
  return v_id;
end $function$;

-- Products not yet added as special products, for the picker.
create or replace function public.products_available_as_special()
returns table(product_id uuid, name text, sku text, total_stock integer)
language sql stable security definer set search_path to 'public' as $function$
  select p.id, p.name, p.sku,
         coalesce((select sum(wi.current_qty)::integer from public.warehouse_inventory wi
                    where wi.product_id = p.id), 0)
    from public.products p
   where p.deleted_at is null and coalesce(p.is_active, true)
     and not exists (select 1 from public.special_products sp
                      where sp.product_id = p.id and sp.deleted_at is null)
   order by p.name
$function$;

-- ---------------------------------------------------------------------
-- 4. Release stock from WAREHOUSE INVENTORY, refusing when pending transfer
--    requests have already claimed it.
-- ---------------------------------------------------------------------
create or replace function public.fulfil_special_doc(
  p_doc_kind text, p_doc_id uuid, p_warehouse_id uuid)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare
  v_sp uuid; v_qty integer; v_no text; v_prod uuid; v_name text;
  v_avail record;
begin
  if not public.is_owner_or_manager() then
    raise exception 'Only an Owner or Manager can choose the warehouse'; end if;
  if p_warehouse_id is null then raise exception 'Choose a warehouse'; end if;
  if not exists (select 1 from public.warehouses where id = p_warehouse_id and deleted_at is null) then
    raise exception 'That warehouse does not exist'; end if;

  if p_doc_kind = 'special_sale' then
    select special_product_id, quantity, sale_no into v_sp, v_qty, v_no
      from public.special_sales where id = p_doc_id and warehouse_id is null
        and status <> 'cancelled' for update;
    if v_sp is null then raise exception 'That sale is not awaiting a warehouse'; end if;
  elsif p_doc_kind = 'rental' then
    select special_product_id, quantity, rental_no into v_sp, v_qty, v_no
      from public.rentals where id = p_doc_id and warehouse_id is null
        and status <> 'cancelled' for update;
    if v_sp is null then raise exception 'That rental is not awaiting a warehouse'; end if;
  else
    raise exception 'Unknown document kind "%"', p_doc_kind;
  end if;

  select product_id into v_prod from public.special_products where id = v_sp;
  if v_prod is null then
    raise exception 'This special product is not linked to a warehouse product yet';
  end if;
  v_name := public.special_product_name(v_sp);

  select * into v_avail from public.warehouse_available_qty(p_warehouse_id, v_prod);

  -- A pending transfer request has already claimed this stock. Blocking is the
  -- safe answer: releasing it here would leave that request unfillable and the
  -- shortfall would only surface at dispatch.
  if v_avail.available < v_qty then
    if v_avail.on_hand >= v_qty then
      raise exception
        'Only % of "%" free at that warehouse (% on hand, % already claimed by pending transfer requests). Approve or reject those first.',
        v_avail.available, v_name, v_avail.on_hand, v_avail.reserved;
    end if;
    raise exception 'Not enough "%" at that warehouse: % needed, % on hand',
      v_name, v_qty, v_avail.on_hand;
  end if;

  update public.warehouse_inventory
     set current_qty = current_qty - v_qty, updated_at = now()
   where warehouse_id = p_warehouse_id and product_id = v_prod;

  insert into public.stock_movements
    (product_id, movement_type, from_warehouse_id, quantity, notes, created_by)
  values (v_prod, 'store_sale'::stock_movement_type, p_warehouse_id, v_qty,
    case when p_doc_kind = 'rental' then 'Rental released — ' else 'Special sale released — ' end || v_no,
    auth.uid());

  if p_doc_kind = 'special_sale' then
    update public.special_sales
       set warehouse_id = p_warehouse_id, status = 'completed',
           fulfilled_at = now(), fulfilled_by = auth.uid()
     where id = p_doc_id;
  else
    update public.rentals
       set warehouse_id = p_warehouse_id, status = 'active',
           activated_at = now(), fulfilled_at = now(), fulfilled_by = auth.uid()
     where id = p_doc_id;
  end if;

  perform public.write_audit_ex(p_doc_kind, p_doc_id, 'special_doc_fulfilled', null,
    jsonb_build_object('warehouse', p_warehouse_id, 'product', v_name,
      'quantity', v_qty, 'doc_no', v_no), 'special', null, null);

  return jsonb_build_object('success', true, 'doc_no', v_no,
    'warehouse_id', p_warehouse_id, 'quantity', v_qty, 'product', v_name);
end $function$;

-- ---------------------------------------------------------------------
-- 5. A returned rental goes back to the warehouse it came from.
-- ---------------------------------------------------------------------
create or replace function public.return_rental_to_warehouse(p_rental_id uuid)
returns integer language plpgsql security definer set search_path to 'public' as $function$
declare v_r public.rentals%rowtype; v_prod uuid;
begin
  select * into v_r from public.rentals where id = p_rental_id for update;
  if not found then raise exception 'Rental not found'; end if;
  if v_r.warehouse_id is null then return 0; end if;
  if coalesce(v_r.stock_returned, false) then return 0; end if;

  select product_id into v_prod from public.special_products where id = v_r.special_product_id;
  if v_prod is null then return 0; end if;

  insert into public.warehouse_inventory (warehouse_id, product_id, current_qty)
  values (v_r.warehouse_id, v_prod, v_r.quantity)
  on conflict (warehouse_id, product_id)
    do update set current_qty = public.warehouse_inventory.current_qty + excluded.current_qty,
                  updated_at = now();

  insert into public.stock_movements
    (product_id, movement_type, to_warehouse_id, quantity, notes, created_by)
  values (v_prod, 'invoice_cancel_return'::stock_movement_type, v_r.warehouse_id,
    v_r.quantity, 'Rental returned — ' || v_r.rental_no, auth.uid());

  update public.rentals set stock_returned = true where id = p_rental_id;
  return v_r.quantity;
end $function$;

-- Hook it onto the existing return, so the return flow itself is unchanged.
create or replace function public.trg_rental_stock_back()
returns trigger language plpgsql security definer set search_path to 'public' as $function$
begin
  if new.status::text = 'returned' and coalesce(old.status::text,'') <> 'returned' then
    perform public.return_rental_to_warehouse(new.id);
  end if;
  return new;
end $function$;

drop trigger if exists rental_stock_back on public.rentals;
create trigger rental_stock_back after update on public.rentals
  for each row execute function public.trg_rental_stock_back();

notify pgrst, 'reload schema';

-- ---------------------------------------------------------------------
-- 6. The waiting queue also returns the special product id and the rental
--    terms, so the release screen can show real availability and let an Owner
--    correct the dates before releasing.
-- ---------------------------------------------------------------------
drop function if exists public.special_docs_awaiting_fulfilment();

create or replace function public.special_docs_awaiting_fulfilment()
returns table(doc_kind text, doc_id uuid, doc_no text, invoice_no text,
              special_product_id uuid, product_name text, customer_name text,
              store_name text, quantity integer,
              rate_type text, periods integer,
              start_date date, expected_return_date date,
              rental_fee numeric, created_at timestamptz)
language sql stable security definer set search_path to 'public' as $function$
  select 'special_sale', s.id, s.sale_no, i.invoice_no,
         s.special_product_id, public.special_product_name(s.special_product_id),
         c.full_name, st.name, s.quantity,
         null::text, null::integer, null::date, null::date, s.total_amount, s.created_at
    from public.special_sales s
    left join public.invoices i on i.id = s.invoice_id
    left join public.customers c on c.id = s.customer_id
    left join public.stores st on st.id = s.store_id
   where s.warehouse_id is null and s.status <> 'cancelled'
  union all
  select 'rental', r.id, r.rental_no, i.invoice_no,
         r.special_product_id, public.special_product_name(r.special_product_id),
         c.full_name, st.name, r.quantity,
         r.rate_type::text, r.periods, r.start_date, r.expected_return_date,
         r.rental_fee, r.created_at
    from public.rentals r
    left join public.invoices i on i.id = r.invoice_id
    left join public.customers c on c.id = r.customer_id
    left join public.stores st on st.id = r.store_id
   where r.warehouse_id is null and r.status <> 'cancelled'
  order by 15
$function$;

-- ---------------------------------------------------------------------
-- 7. An Owner or Manager may correct a rental's terms before release.
--    Once released the stock has moved and the customer has the goods, so the
--    dates are corrected through the normal return/late-fee flow instead.
-- ---------------------------------------------------------------------
create or replace function public.update_pending_rental(
  p_rental_id uuid, p_quantity integer default null,
  p_rate_type public.special_rate_type default null, p_periods integer default null,
  p_start_date date default null, p_expected_return_date date default null,
  p_notes text default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare v_r public.rentals%rowtype; sp public.special_products%rowtype;
        v_rate numeric; v_qty integer; v_per integer; v_type public.special_rate_type;
        v_fee numeric;
begin
  if not public.is_owner_or_manager() then
    raise exception 'Only an Owner or Manager can change a rental'; end if;

  select * into v_r from public.rentals where id = p_rental_id for update;
  if not found then raise exception 'Rental not found'; end if;
  if v_r.warehouse_id is not null then
    raise exception 'This rental has already been released — the stock has gone out. Handle changes through the return.';
  end if;

  select * into sp from public.special_products where id = v_r.special_product_id;
  v_type := coalesce(p_rate_type, v_r.rate_type);
  v_per  := greatest(coalesce(p_periods, v_r.periods), 1);
  v_qty  := greatest(coalesce(p_quantity, v_r.quantity), 1);

  v_rate := case v_type
    when 'day' then sp.rate_day when 'week' then sp.rate_week
    when 'month' then sp.rate_month when 'year' then sp.rate_year end;
  if coalesce(v_rate,0) <= 0 then
    raise exception '"%" has no % rate set', sp.name, v_type; end if;

  if p_expected_return_date is not null and p_start_date is not null
     and p_expected_return_date < p_start_date then
    raise exception 'The return date cannot be before the start date'; end if;

  v_fee := round(v_rate * v_per * v_qty, 2);

  update public.rentals set
    quantity = v_qty, rate_type = v_type, rate_amount = v_rate, periods = v_per,
    rental_fee = v_fee,
    start_date = coalesce(p_start_date, start_date),
    expected_return_date = coalesce(p_expected_return_date, expected_return_date),
    notes = coalesce(p_notes, notes)
  where id = p_rental_id;

  perform public.write_audit_ex('rental', p_rental_id, 'pending_rental_edited', null,
    jsonb_build_object('quantity', v_qty, 'rate_type', v_type, 'periods', v_per,
      'fee_was', v_r.rental_fee, 'fee_now', v_fee), 'special', null, null);

  -- The fee may now differ from what was invoiced; the caller is told so it can
  -- be said plainly rather than discovered later.
  return jsonb_build_object('success', true, 'rental_fee', v_fee,
    'invoiced_fee', v_r.rental_fee,
    'difference', round(v_fee - coalesce(v_r.rental_fee,0), 2));
end $function$;

notify pgrst, 'reload schema';
