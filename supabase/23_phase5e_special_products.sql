-- =====================================================================
-- ENERGIA — PHASE 5E: Special warehouse products (sale & rental)
--
-- * Special products: separate catalog, warehouse-only, Owner/Manager.
--   Sale price + rental rates (day/week/month/year) + fixed daily late fee.
-- * Per-warehouse stock with manual stock-in.
-- * Sales: immediate payment, stock deducts atomically. Cancellable with
--   optional stock return.
-- * Rentals: Draft -> Paid (fee collected upfront, stock deducts) ->
--   Active (picked up) -> Returned (condition Good/Damaged/Lost recorded,
--   checkbox decides stock return, late fee = days past expected return
--   x daily fee x quantity, collected at return). Cancellable.
--   Overdue is derived (paid/active past the expected return date).
-- * NO commission on special products (per decision).
--
-- Additive + idempotent. Run AFTER 22_phase5d5_discount_rules.sql.
-- =====================================================================

set check_function_bodies = off;

do $$ begin create type special_rate_type as enum ('day','week','month','year');
exception when duplicate_object then null; end $$;
do $$ begin create type rental_status as enum ('draft','paid','active','returned','overdue','cancelled');
exception when duplicate_object then null; end $$;
do $$ begin create type return_condition as enum ('good','damaged','lost');
exception when duplicate_object then null; end $$;

-- ---------------------------------------------------------------------
-- 1. Catalog
-- ---------------------------------------------------------------------
create table if not exists public.special_products (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  sku text not null,
  description text,
  sale_price numeric(12,2) not null default 0,
  rate_day numeric(12,2) not null default 0,
  rate_week numeric(12,2) not null default 0,
  rate_month numeric(12,2) not null default 0,
  rate_year numeric(12,2) not null default 0,
  late_fee_per_day numeric(12,2) not null default 0,
  is_active boolean not null default true,
  deleted_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.special_product_stock (
  id uuid primary key default gen_random_uuid(),
  special_product_id uuid not null references public.special_products(id) on delete cascade,
  warehouse_id uuid not null references public.warehouses(id) on delete cascade,
  current_qty integer not null default 0 check (current_qty >= 0),
  updated_at timestamptz not null default now(),
  unique(special_product_id, warehouse_id)
);

-- ---------------------------------------------------------------------
-- 2. Sales
-- ---------------------------------------------------------------------
create table if not exists public.special_sales (
  id uuid primary key default gen_random_uuid(),
  sale_no text not null,
  special_product_id uuid not null references public.special_products(id),
  warehouse_id uuid not null references public.warehouses(id),
  customer_id uuid references public.customers(id),
  quantity integer not null check (quantity > 0),
  unit_price numeric(12,2) not null default 0,
  total_amount numeric(12,2) not null default 0,
  payment_method_id uuid references public.payment_methods(id),
  payment_reference text,
  notes text,
  status text not null default 'paid',            -- 'paid' | 'cancelled'
  stock_returned boolean,
  sold_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  cancelled_at timestamptz
);
create sequence if not exists public.special_sale_no_seq;

-- ---------------------------------------------------------------------
-- 3. Rentals
-- ---------------------------------------------------------------------
create table if not exists public.rentals (
  id uuid primary key default gen_random_uuid(),
  rental_no text not null,
  special_product_id uuid not null references public.special_products(id),
  warehouse_id uuid not null references public.warehouses(id),
  customer_id uuid not null references public.customers(id),
  quantity integer not null check (quantity > 0),
  rate_type special_rate_type not null,
  rate_amount numeric(12,2) not null default 0,   -- per period, per unit
  periods integer not null check (periods > 0),
  rental_fee numeric(12,2) not null default 0,    -- rate x periods x qty
  start_date date not null,
  expected_return_date date not null,
  status rental_status not null default 'draft',
  payment_method_id uuid references public.payment_methods(id),
  payment_reference text,
  paid_at timestamptz,
  activated_at timestamptz,
  returned_at timestamptz,
  return_condition return_condition,
  stock_returned boolean,
  late_days integer not null default 0,
  late_fee_per_day numeric(12,2) not null default 0,  -- copied from product at creation
  late_fee_total numeric(12,2) not null default 0,
  late_payment_method_id uuid references public.payment_methods(id),
  late_payment_reference text,
  notes text,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  cancelled_at timestamptz
);
create sequence if not exists public.rental_no_seq;
create index if not exists idx_rentals_status on public.rentals(status);

-- ---------------------------------------------------------------------
-- RLS (Owner/Manager only, per spec)
-- ---------------------------------------------------------------------
alter table public.special_products enable row level security;
drop policy if exists "manage special products" on public.special_products;
create policy "manage special products" on public.special_products for all to authenticated
  using (public.is_owner_or_manager()) with check (public.is_owner_or_manager());

alter table public.special_product_stock enable row level security;
drop policy if exists "read special stock" on public.special_product_stock;
create policy "read special stock" on public.special_product_stock for select to authenticated
  using (public.is_owner_or_manager());

alter table public.special_sales enable row level security;
drop policy if exists "read special sales" on public.special_sales;
create policy "read special sales" on public.special_sales for select to authenticated
  using (public.is_owner_or_manager());

alter table public.rentals enable row level security;
drop policy if exists "read rentals" on public.rentals;
create policy "read rentals" on public.rentals for select to authenticated
  using (public.is_owner_or_manager());

-- ---------------------------------------------------------------------
-- 4. Stock in
-- ---------------------------------------------------------------------
create or replace function public.special_stock_in(
  p_special_product_id uuid, p_warehouse_id uuid, p_quantity integer, p_note text default null
) returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner_or_manager() then raise exception 'Only Owner or Manager can manage special products'; end if;
  if p_quantity is null or p_quantity <= 0 then raise exception 'Quantity must be greater than zero'; end if;
  insert into public.special_product_stock (special_product_id, warehouse_id, current_qty)
  values (p_special_product_id, p_warehouse_id, p_quantity)
  on conflict (special_product_id, warehouse_id)
  do update set current_qty = public.special_product_stock.current_qty + excluded.current_qty, updated_at = now();
  perform public.write_audit('special_product_stock', p_special_product_id, 'special_stock_added', null,
    jsonb_build_object('warehouse_id', p_warehouse_id, 'quantity', p_quantity, 'note', p_note));
end; $$;

-- ---------------------------------------------------------------------
-- 5. Create sale (immediate payment, stock deducts atomically)
-- ---------------------------------------------------------------------
create or replace function public.create_special_sale(
  p_special_product_id uuid, p_warehouse_id uuid, p_customer_id uuid,
  p_quantity integer, p_payment_method_id uuid, p_reference text default null, p_notes text default null
) returns uuid language plpgsql security definer set search_path = public as $$
declare v_sp public.special_products%rowtype; v_avail integer; v_id uuid; v_no text;
begin
  if not public.is_owner_or_manager() then raise exception 'Only Owner or Manager can sell special products'; end if;
  if p_quantity is null or p_quantity <= 0 then raise exception 'Quantity must be greater than zero'; end if;
  select * into v_sp from public.special_products where id = p_special_product_id and deleted_at is null;
  if not found then raise exception 'Special product not found'; end if;
  if not v_sp.is_active then raise exception 'Special product "%" is not active', v_sp.name; end if;

  select current_qty into v_avail from public.special_product_stock
    where special_product_id = p_special_product_id and warehouse_id = p_warehouse_id for update;
  if coalesce(v_avail,0) < p_quantity then
    raise exception 'Insufficient special stock (have %, need %)', coalesce(v_avail,0), p_quantity;
  end if;

  update public.special_product_stock set current_qty = current_qty - p_quantity, updated_at = now()
    where special_product_id = p_special_product_id and warehouse_id = p_warehouse_id;

  v_no := 'SPS-' || to_char(now(),'YYYY') || '-' || lpad(nextval('public.special_sale_no_seq')::text, 4, '0');
  insert into public.special_sales
    (sale_no, special_product_id, warehouse_id, customer_id, quantity, unit_price, total_amount,
     payment_method_id, payment_reference, notes, status, sold_by)
  values (v_no, p_special_product_id, p_warehouse_id, p_customer_id, p_quantity, v_sp.sale_price,
     v_sp.sale_price * p_quantity, p_payment_method_id, p_reference, p_notes, 'paid', auth.uid())
  returning id into v_id;

  perform public.write_audit('special_sales', v_id, 'special_sale_created', null,
    jsonb_build_object('sale_no', v_no, 'total', v_sp.sale_price * p_quantity));
  return v_id;
end; $$;

-- ---------------------------------------------------------------------
-- 6. Cancel sale (optional stock return)
-- ---------------------------------------------------------------------
create or replace function public.cancel_special_sale(
  p_sale_id uuid, p_return_stock boolean, p_note text default null
) returns void language plpgsql security definer set search_path = public as $$
declare v_s public.special_sales%rowtype;
begin
  if not public.is_owner_or_manager() then raise exception 'Only Owner or Manager can cancel special sales'; end if;
  select * into v_s from public.special_sales where id = p_sale_id for update;
  if not found then raise exception 'Sale not found'; end if;
  if v_s.status <> 'paid' then raise exception 'Sale is already %', v_s.status; end if;

  if p_return_stock then
    insert into public.special_product_stock (special_product_id, warehouse_id, current_qty)
    values (v_s.special_product_id, v_s.warehouse_id, v_s.quantity)
    on conflict (special_product_id, warehouse_id)
    do update set current_qty = public.special_product_stock.current_qty + excluded.current_qty, updated_at = now();
  end if;

  update public.special_sales set status = 'cancelled', stock_returned = p_return_stock,
    cancelled_at = now(), notes = coalesce(notes,'') || case when p_note is null then '' else ' | Cancelled: '||p_note end
    where id = p_sale_id;
  perform public.write_audit('special_sales', p_sale_id, 'special_sale_cancelled', null,
    jsonb_build_object('sale_no', v_s.sale_no, 'stock_returned', p_return_stock));
end; $$;

-- ---------------------------------------------------------------------
-- 7. Create rental (Draft — no stock taken yet)
--    Rate is read server-side from the product for the chosen rate type.
-- ---------------------------------------------------------------------
create or replace function public.create_rental(
  p_special_product_id uuid, p_warehouse_id uuid, p_customer_id uuid,
  p_quantity integer, p_rate_type special_rate_type, p_periods integer,
  p_start_date date, p_expected_return_date date, p_notes text default null
) returns uuid language plpgsql security definer set search_path = public as $$
declare v_sp public.special_products%rowtype; v_rate numeric; v_id uuid; v_no text;
begin
  if not public.is_owner_or_manager() then raise exception 'Only Owner or Manager can create rentals'; end if;
  if p_quantity is null or p_quantity <= 0 then raise exception 'Quantity must be greater than zero'; end if;
  if p_periods is null or p_periods <= 0 then raise exception 'Rental duration must be at least 1 period'; end if;
  if p_expected_return_date <= p_start_date then raise exception 'Expected return date must be after the start date'; end if;

  select * into v_sp from public.special_products where id = p_special_product_id and deleted_at is null;
  if not found then raise exception 'Special product not found'; end if;
  if not v_sp.is_active then raise exception 'Special product "%" is not active', v_sp.name; end if;

  v_rate := case p_rate_type
    when 'day' then v_sp.rate_day when 'week' then v_sp.rate_week
    when 'month' then v_sp.rate_month else v_sp.rate_year end;
  if v_rate <= 0 then raise exception 'No % rate set for "%"', p_rate_type, v_sp.name; end if;

  v_no := 'RENT-' || to_char(now(),'YYYY') || '-' || lpad(nextval('public.rental_no_seq')::text, 4, '0');
  insert into public.rentals
    (rental_no, special_product_id, warehouse_id, customer_id, quantity, rate_type, rate_amount,
     periods, rental_fee, start_date, expected_return_date, status, late_fee_per_day, notes, created_by)
  values (v_no, p_special_product_id, p_warehouse_id, p_customer_id, p_quantity, p_rate_type, v_rate,
     p_periods, v_rate * p_periods * p_quantity, p_start_date, p_expected_return_date, 'draft',
     v_sp.late_fee_per_day, p_notes, auth.uid())
  returning id into v_id;

  perform public.write_audit('rentals', v_id, 'rental_created', null,
    jsonb_build_object('rental_no', v_no, 'fee', v_rate * p_periods * p_quantity));
  return v_id;
end; $$;

-- ---------------------------------------------------------------------
-- 8. Pay rental (fee collected upfront; stock deducts here)
-- ---------------------------------------------------------------------
create or replace function public.pay_rental(
  p_rental_id uuid, p_payment_method_id uuid, p_reference text default null
) returns void language plpgsql security definer set search_path = public as $$
declare v_r public.rentals%rowtype; v_avail integer;
begin
  if not public.is_owner_or_manager() then raise exception 'Only Owner or Manager can manage rentals'; end if;
  select * into v_r from public.rentals where id = p_rental_id for update;
  if not found then raise exception 'Rental not found'; end if;
  if v_r.status <> 'draft' then raise exception 'Only draft rentals can be paid (current: %)', v_r.status; end if;

  select current_qty into v_avail from public.special_product_stock
    where special_product_id = v_r.special_product_id and warehouse_id = v_r.warehouse_id for update;
  if coalesce(v_avail,0) < v_r.quantity then
    raise exception 'Insufficient special stock (have %, need %)', coalesce(v_avail,0), v_r.quantity;
  end if;
  update public.special_product_stock set current_qty = current_qty - v_r.quantity, updated_at = now()
    where special_product_id = v_r.special_product_id and warehouse_id = v_r.warehouse_id;

  update public.rentals set status = 'paid', paid_at = now(),
    payment_method_id = p_payment_method_id, payment_reference = p_reference
    where id = p_rental_id;
  perform public.write_audit('rentals', p_rental_id, 'rental_paid', null,
    jsonb_build_object('rental_no', v_r.rental_no, 'fee', v_r.rental_fee));
end; $$;

-- ---------------------------------------------------------------------
-- 9. Activate rental (customer picked up)
-- ---------------------------------------------------------------------
create or replace function public.activate_rental(p_rental_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_r public.rentals%rowtype;
begin
  if not public.is_owner_or_manager() then raise exception 'Only Owner or Manager can manage rentals'; end if;
  select * into v_r from public.rentals where id = p_rental_id for update;
  if not found then raise exception 'Rental not found'; end if;
  if v_r.status <> 'paid' then raise exception 'Only paid rentals can be activated (current: %)', v_r.status; end if;
  update public.rentals set status = 'active', activated_at = now() where id = p_rental_id;
  perform public.write_audit('rentals', p_rental_id, 'rental_activated', null,
    jsonb_build_object('rental_no', v_r.rental_no));
end; $$;

-- ---------------------------------------------------------------------
-- 10. Return rental: condition recorded; checkbox decides stock return;
--     late fee = days past expected return x daily fee x quantity,
--     collected now (separate from the upfront rental fee).
-- ---------------------------------------------------------------------
create or replace function public.return_rental(
  p_rental_id uuid, p_condition return_condition, p_return_stock boolean,
  p_late_payment_method_id uuid default null, p_late_reference text default null, p_note text default null
) returns jsonb language plpgsql security definer set search_path = public as $$
declare v_r public.rentals%rowtype; v_late_days integer; v_late_total numeric;
begin
  if not public.is_owner_or_manager() then raise exception 'Only Owner or Manager can manage rentals'; end if;
  select * into v_r from public.rentals where id = p_rental_id for update;
  if not found then raise exception 'Rental not found'; end if;
  if v_r.status not in ('paid','active','overdue') then
    raise exception 'Only paid/active rentals can be returned (current: %)', v_r.status;
  end if;

  v_late_days := greatest(0, (now()::date - v_r.expected_return_date));
  v_late_total := round(v_late_days * v_r.late_fee_per_day * v_r.quantity, 2);
  if v_late_total > 0 and p_late_payment_method_id is null then
    raise exception 'Late fee of S$% is due — select a payment method for it', v_late_total;
  end if;

  if p_return_stock then
    insert into public.special_product_stock (special_product_id, warehouse_id, current_qty)
    values (v_r.special_product_id, v_r.warehouse_id, v_r.quantity)
    on conflict (special_product_id, warehouse_id)
    do update set current_qty = public.special_product_stock.current_qty + excluded.current_qty, updated_at = now();
  end if;

  update public.rentals set status = 'returned', returned_at = now(),
    return_condition = p_condition, stock_returned = p_return_stock,
    late_days = v_late_days, late_fee_total = v_late_total,
    late_payment_method_id = p_late_payment_method_id, late_payment_reference = p_late_reference,
    notes = coalesce(notes,'') || case when p_note is null then '' else ' | Return: '||p_note end
    where id = p_rental_id;

  perform public.write_audit('rentals', p_rental_id, 'rental_returned', null,
    jsonb_build_object('rental_no', v_r.rental_no, 'condition', p_condition,
      'stock_returned', p_return_stock, 'late_days', v_late_days, 'late_fee', v_late_total));
  return jsonb_build_object('success', true, 'late_days', v_late_days, 'late_fee_total', v_late_total);
end; $$;

-- ---------------------------------------------------------------------
-- 11. Cancel rental (draft: nothing to restore; paid/active: optional
--     stock return — the fee refund, if any, is handled outside per your
--     normal refund practice).
-- ---------------------------------------------------------------------
create or replace function public.cancel_rental(
  p_rental_id uuid, p_return_stock boolean, p_note text default null
) returns void language plpgsql security definer set search_path = public as $$
declare v_r public.rentals%rowtype;
begin
  if not public.is_owner_or_manager() then raise exception 'Only Owner or Manager can manage rentals'; end if;
  select * into v_r from public.rentals where id = p_rental_id for update;
  if not found then raise exception 'Rental not found'; end if;
  if v_r.status in ('returned','cancelled') then raise exception 'Rental is already %', v_r.status; end if;

  if v_r.status in ('paid','active') and p_return_stock then
    insert into public.special_product_stock (special_product_id, warehouse_id, current_qty)
    values (v_r.special_product_id, v_r.warehouse_id, v_r.quantity)
    on conflict (special_product_id, warehouse_id)
    do update set current_qty = public.special_product_stock.current_qty + excluded.current_qty, updated_at = now();
  end if;

  update public.rentals set status = 'cancelled', cancelled_at = now(),
    stock_returned = case when v_r.status in ('paid','active') then p_return_stock else null end,
    notes = coalesce(notes,'') || case when p_note is null then '' else ' | Cancelled: '||p_note end
    where id = p_rental_id;
  perform public.write_audit('rentals', p_rental_id, 'rental_cancelled', null,
    jsonb_build_object('rental_no', v_r.rental_no, 'stock_returned', p_return_stock));
end; $$;

notify pgrst, 'reload schema';
