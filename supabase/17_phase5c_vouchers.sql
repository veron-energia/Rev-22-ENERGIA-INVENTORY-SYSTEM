-- =====================================================================
-- ENERGIA — PHASE 5C: Vouchers (sellable + discount redemption)
--   * vouchers catalog (normal / fixed-amount / percentage, +optional cap)
--   * limited vouchers: per-store stock; unlimited: no stock
--   * sellable vouchers become invoice lines (commission like Own product)
--   * discount vouchers: compute discount, one per invoice, recorded as a
--     redemption; never on bundle invoices; total can't go negative
--   * create_invoice extended to accept voucher lines + a discount voucher
--
-- Additive + idempotent. Run AFTER 16_phase5b2_referrers.sql.
-- =====================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------
do $$ begin create type voucher_kind as enum ('normal','fixed_discount','percentage_discount');
exception when duplicate_object then null; end $$;
do $$ begin create type voucher_qty_type as enum ('unlimited','limited');
exception when duplicate_object then null; end $$;

-- New invoice-line kinds so a line can be a product OR a voucher (5D adds promotion).
do $$ begin create type invoice_line_kind as enum ('product','voucher','promotion');
exception when duplicate_object then null; end $$;

-- ---------------------------------------------------------------------
-- 1. Voucher catalog
-- ---------------------------------------------------------------------
create table if not exists public.vouchers (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  code text not null,                       -- fixed code (shared); not unique-enforced
  voucher_kind voucher_kind not null default 'normal',
  discount_amount numeric(12,2),            -- for fixed_discount
  discount_percent numeric(6,3),            -- for percentage_discount
  max_discount_cap numeric(12,2),           -- optional cap for percentage
  qty_type voucher_qty_type not null default 'unlimited',
  selling_price numeric(12,2) not null default 0,
  valid_from date,
  valid_until date,
  is_active boolean not null default true,
  description text,
  terms text,
  deleted_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists idx_vouchers_active on public.vouchers(is_active) where deleted_at is null;

-- ---------------------------------------------------------------------
-- 2. Per-store voucher stock (limited vouchers only)
-- ---------------------------------------------------------------------
create table if not exists public.voucher_store_stock (
  id uuid primary key default gen_random_uuid(),
  voucher_id uuid not null references public.vouchers(id) on delete cascade,
  store_id uuid not null references public.stores(id) on delete cascade,
  current_qty integer not null default 0 check (current_qty >= 0),
  updated_at timestamptz not null default now(),
  unique(voucher_id, store_id)
);

-- ---------------------------------------------------------------------
-- 3. Voucher redemptions (discount usage record)
-- ---------------------------------------------------------------------
create table if not exists public.voucher_redemptions (
  id uuid primary key default gen_random_uuid(),
  voucher_id uuid not null references public.vouchers(id),
  invoice_id uuid references public.invoices(id) on delete set null,
  customer_id uuid references public.customers(id),
  discount_applied numeric(12,2) not null default 0,
  redeemed_by uuid references public.profiles(id),
  created_at timestamptz not null default now()
);
create index if not exists idx_voucher_redemptions_voucher on public.voucher_redemptions(voucher_id);
create index if not exists idx_voucher_redemptions_invoice on public.voucher_redemptions(invoice_id);

-- ---------------------------------------------------------------------
-- 4. Extend invoice_items + invoices for vouchers
-- ---------------------------------------------------------------------
alter table public.invoice_items add column if not exists line_kind invoice_line_kind not null default 'product';
alter table public.invoice_items add column if not exists voucher_id uuid references public.vouchers(id);
alter table public.invoice_items alter column product_id drop not null;

alter table public.invoices add column if not exists discount_voucher_id uuid references public.vouchers(id);

-- ---------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------
alter table public.vouchers enable row level security;
drop policy if exists "read vouchers" on public.vouchers;
create policy "read vouchers" on public.vouchers for select to authenticated using (deleted_at is null);
drop policy if exists "manage vouchers" on public.vouchers;
create policy "manage vouchers" on public.vouchers for all to authenticated
  using (public.is_owner_or_manager()) with check (public.is_owner_or_manager());

alter table public.voucher_store_stock enable row level security;
drop policy if exists "read voucher stock" on public.voucher_store_stock;
create policy "read voucher stock" on public.voucher_store_stock for select to authenticated using (true);
drop policy if exists "manage voucher stock" on public.voucher_store_stock;
create policy "manage voucher stock" on public.voucher_store_stock for all to authenticated
  using (public.is_owner_or_manager()) with check (public.is_owner_or_manager());

alter table public.voucher_redemptions enable row level security;
drop policy if exists "read voucher redemptions" on public.voucher_redemptions;
create policy "read voucher redemptions" on public.voucher_redemptions for select to authenticated using (true);
-- inserts happen via create_invoice (SECURITY DEFINER), no direct insert policy needed.

-- ---------------------------------------------------------------------
-- 5. Manual voucher stock-in (limited vouchers, per store)
-- ---------------------------------------------------------------------
create or replace function public.voucher_stock_in(
  p_voucher_id uuid, p_store_id uuid, p_quantity integer, p_note text default null
) returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner_or_manager() then raise exception 'Only Owner or Manager can add voucher stock'; end if;
  if p_quantity is null or p_quantity <= 0 then raise exception 'Quantity must be greater than zero'; end if;

  insert into public.voucher_store_stock (voucher_id, store_id, current_qty)
  values (p_voucher_id, p_store_id, p_quantity)
  on conflict (voucher_id, store_id)
  do update set current_qty = public.voucher_store_stock.current_qty + excluded.current_qty, updated_at = now();

  perform public.write_audit('voucher_store_stock', p_voucher_id, 'voucher_stock_added', null,
    jsonb_build_object('store_id', p_store_id, 'quantity', p_quantity, 'note', p_note));
end; $$;

-- ---------------------------------------------------------------------
-- 6. Compute a discount voucher's amount for a given pre-discount base.
--    Returns the discount (never more than the base).
-- ---------------------------------------------------------------------
create or replace function public.voucher_discount_amount(p_voucher_id uuid, p_base numeric)
returns numeric language plpgsql stable security definer set search_path = public as $$
declare v public.vouchers%rowtype; v_disc numeric := 0;
begin
  select * into v from public.vouchers where id = p_voucher_id and deleted_at is null;
  if not found then raise exception 'Voucher not found'; end if;
  if not v.is_active then raise exception 'Voucher is not active'; end if;
  if v.valid_from is not null and now()::date < v.valid_from then raise exception 'Voucher is not yet valid'; end if;
  if v.valid_until is not null and now()::date > v.valid_until then raise exception 'Voucher has expired'; end if;

  if v.voucher_kind = 'fixed_discount' then
    v_disc := coalesce(v.discount_amount, 0);
  elsif v.voucher_kind = 'percentage_discount' then
    v_disc := round(p_base * coalesce(v.discount_percent,0) / 100.0, 2);
    if v.max_discount_cap is not null and v_disc > v.max_discount_cap then
      v_disc := v.max_discount_cap;
    end if;
  else
    raise exception 'This voucher is not a discount voucher';
  end if;

  if v_disc > p_base then v_disc := p_base; end if;   -- never negative total
  if v_disc < 0 then v_disc := 0; end if;
  return v_disc;
end; $$;

-- ---------------------------------------------------------------------
-- 7. create_invoice (extended): product + voucher lines, optional discount voucher.
--    p_items: [{ kind:'product'|'voucher', product_id?, voucher_id?, quantity }]
--    p_discount_voucher_id: optional voucher used as a discount on this invoice.
--    Keeps the old positional signature working by adding params with defaults.
-- ---------------------------------------------------------------------
create or replace function public.create_invoice(
  p_store_id uuid, p_customer_id uuid, p_affiliate_id uuid,
  p_items jsonb, p_discount_total numeric default 0, p_notes text default null,
  p_discount_voucher_id uuid default null
) returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_item jsonb; v_kind text; v_product_id uuid; v_voucher_id uuid; v_qty integer; v_price numeric;
  v_subtotal numeric := 0; v_line_total numeric; v_invoice_id uuid; v_invoice_no text;
  v_discount numeric := coalesce(p_discount_total,0);
begin
  if not public.user_has_store_access(p_store_id) then raise exception 'You do not have access to this store'; end if;
  if p_items is null or jsonb_array_length(p_items) = 0 then raise exception 'At least one item is required'; end if;

  -- Price every line, compute subtotal.
  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_kind := coalesce(v_item->>'kind','product');
    v_qty := (v_item->>'quantity')::integer;
    if v_qty is null or v_qty <= 0 then raise exception 'Quantity must be greater than zero'; end if;

    if v_kind = 'voucher' then
      v_voucher_id := (v_item->>'voucher_id')::uuid;
      select selling_price into v_price from public.vouchers
        where id = v_voucher_id and is_active = true and deleted_at is null;
      if v_price is null then raise exception 'Voucher not found or inactive'; end if;
    else
      v_product_id := (v_item->>'product_id')::uuid;
      select selling_price into v_price from public.store_product_prices
        where store_id = p_store_id and product_id = v_product_id and is_active = true and deleted_at is null;
      if v_price is null then raise exception 'No price set for a product in this store'; end if;
    end if;
    v_subtotal := v_subtotal + (v_price * v_qty);
  end loop;

  -- Apply discount voucher (on top of any manual discount). One voucher per invoice.
  if p_discount_voucher_id is not null then
    v_discount := v_discount + public.voucher_discount_amount(p_discount_voucher_id, v_subtotal - v_discount);
  end if;
  if v_discount > v_subtotal then v_discount := v_subtotal; end if;

  v_invoice_no := public.next_invoice_no();
  insert into public.invoices
    (invoice_no, store_id, customer_id, affiliate_id, created_by, status,
     subtotal, discount_total, total_amount, paid_amount, notes, discount_voucher_id)
  values (v_invoice_no, p_store_id, p_customer_id, p_affiliate_id, auth.uid(), 'unpaid',
          v_subtotal, v_discount, v_subtotal - v_discount, 0, p_notes, p_discount_voucher_id)
  returning id into v_invoice_id;

  -- Insert lines.
  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_kind := coalesce(v_item->>'kind','product');
    v_qty := (v_item->>'quantity')::integer;
    if v_kind = 'voucher' then
      v_voucher_id := (v_item->>'voucher_id')::uuid;
      select selling_price into v_price from public.vouchers where id = v_voucher_id;
      v_line_total := v_price * v_qty;
      insert into public.invoice_items (invoice_id, line_kind, voucher_id, product_id, quantity, unit_price, line_total)
      values (v_invoice_id, 'voucher', v_voucher_id, null, v_qty, v_price, v_line_total);
    else
      v_product_id := (v_item->>'product_id')::uuid;
      select selling_price into v_price from public.store_product_prices
        where store_id = p_store_id and product_id = v_product_id and is_active = true and deleted_at is null;
      v_line_total := v_price * v_qty;
      insert into public.invoice_items (invoice_id, line_kind, product_id, quantity, unit_price, line_total)
      values (v_invoice_id, 'product', v_product_id, v_qty, v_price, v_line_total);
    end if;
  end loop;

  perform public.write_audit('invoices', v_invoice_id, 'invoice_created', null,
    jsonb_build_object('invoice_no', v_invoice_no, 'total', v_subtotal - v_discount,
                       'discount_voucher', p_discount_voucher_id));
  return v_invoice_id;
end; $$;

-- ---------------------------------------------------------------------
-- 8. pay_invoice (extended): also deduct limited-voucher store stock on
--    full payment, record voucher redemption, and record voucher sales.
--    Product stock + commission logic unchanged from 5B.
-- ---------------------------------------------------------------------
create or replace function public.pay_invoice(p_invoice_id uuid, p_payments jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_inv public.invoices%rowtype; v_pay jsonb; v_method uuid; v_amount numeric;
  v_total_paying numeric := 0; v_already_paid numeric; v_new_paid numeric;
  v_item record; v_available integer; v_vavail integer;
begin
  select * into v_inv from public.invoices where id = p_invoice_id for update;
  if not found then raise exception 'Invoice not found'; end if;
  if not public.user_has_store_access(v_inv.store_id) then raise exception 'No access to this invoice''s store'; end if;
  if v_inv.status in ('paid','cancelled','refunded') then raise exception 'Invoice is already %', v_inv.status; end if;
  if p_payments is null or jsonb_array_length(p_payments) = 0 then raise exception 'At least one payment is required'; end if;

  for v_pay in select * from jsonb_array_elements(p_payments)
  loop
    v_amount := (v_pay->>'amount')::numeric;
    if v_amount is null or v_amount <= 0 then raise exception 'Payment amount must be positive'; end if;
    v_total_paying := v_total_paying + v_amount;
  end loop;

  v_already_paid := v_inv.paid_amount;
  v_new_paid := v_already_paid + v_total_paying;
  if v_new_paid > v_inv.total_amount + 0.001 then raise exception 'Payment exceeds remaining balance'; end if;

  -- On full payment: check product stock AND limited-voucher stock first.
  if v_new_paid >= v_inv.total_amount - 0.001 then
    for v_item in
      select line_kind, product_id, voucher_id, quantity from public.invoice_items where invoice_id = p_invoice_id
    loop
      if v_item.line_kind = 'product' then
        select current_qty into v_available from public.store_inventory
          where store_id = v_inv.store_id and product_id = v_item.product_id for update;
        if coalesce(v_available,0) < v_item.quantity then
          raise exception 'Insufficient store stock for a product (have %, need %). Payment blocked.', coalesce(v_available,0), v_item.quantity;
        end if;
      elsif v_item.line_kind = 'voucher' then
        -- only limited vouchers track stock
        if exists (select 1 from public.vouchers where id = v_item.voucher_id and qty_type = 'limited') then
          select current_qty into v_vavail from public.voucher_store_stock
            where store_id = v_inv.store_id and voucher_id = v_item.voucher_id for update;
          if coalesce(v_vavail,0) < v_item.quantity then
            raise exception 'Insufficient voucher stock at this store (have %, need %). Payment blocked.', coalesce(v_vavail,0), v_item.quantity;
          end if;
        end if;
      end if;
    end loop;
  end if;

  for v_pay in select * from jsonb_array_elements(p_payments)
  loop
    v_method := (v_pay->>'payment_method_id')::uuid;
    v_amount := (v_pay->>'amount')::numeric;
    insert into public.invoice_payments (invoice_id, payment_method_id, amount, payment_reference, received_by)
    values (p_invoice_id, v_method, v_amount, v_pay->>'reference', auth.uid());
  end loop;

  if v_new_paid >= v_inv.total_amount - 0.001 then
    for v_item in
      select line_kind, product_id, voucher_id, quantity from public.invoice_items where invoice_id = p_invoice_id
    loop
      if v_item.line_kind = 'product' then
        update public.store_inventory set current_qty = current_qty - v_item.quantity, updated_at = now()
          where store_id = v_inv.store_id and product_id = v_item.product_id;
        insert into public.stock_movements (product_id, movement_type, from_store_id, invoice_id, quantity, notes, created_by)
        values (v_item.product_id, 'store_sale', v_inv.store_id, p_invoice_id, v_item.quantity, 'Sale — '||v_inv.invoice_no, auth.uid());
      elsif v_item.line_kind = 'voucher' then
        if exists (select 1 from public.vouchers where id = v_item.voucher_id and qty_type = 'limited') then
          update public.voucher_store_stock set current_qty = current_qty - v_item.quantity, updated_at = now()
            where store_id = v_inv.store_id and voucher_id = v_item.voucher_id;
        end if;
        perform public.write_audit('vouchers', v_item.voucher_id, 'voucher_sold', null,
          jsonb_build_object('invoice_no', v_inv.invoice_no, 'qty', v_item.quantity));
      end if;
    end loop;

    update public.invoices set status = 'paid', paid_amount = v_new_paid, paid_at = now(), locked_at = now()
      where id = p_invoice_id;

    -- Record discount voucher redemption (no serial / no reuse check, per spec).
    if v_inv.discount_voucher_id is not null then
      insert into public.voucher_redemptions (voucher_id, invoice_id, customer_id, discount_applied, redeemed_by)
      values (v_inv.discount_voucher_id, p_invoice_id, v_inv.customer_id, v_inv.discount_total, auth.uid());
      perform public.write_audit('vouchers', v_inv.discount_voucher_id, 'voucher_redeemed', null,
        jsonb_build_object('invoice_no', v_inv.invoice_no, 'discount', v_inv.discount_total));
    end if;

    perform public.earn_invoice_commission(p_invoice_id);

    perform public.write_audit('invoices', p_invoice_id, 'invoice_paid', null,
      jsonb_build_object('paid_amount', v_new_paid, 'invoice_no', v_inv.invoice_no));
    return jsonb_build_object('success', true, 'status', 'paid', 'paid_amount', v_new_paid);
  else
    update public.invoices set paid_amount = v_new_paid, status = 'partially_paid' where id = p_invoice_id;
    perform public.write_audit('invoices', p_invoice_id, 'invoice_partial_payment', null,
      jsonb_build_object('paid_amount', v_new_paid));
    return jsonb_build_object('success', true, 'status', 'partially_paid', 'paid_amount', v_new_paid, 'remaining', v_inv.total_amount - v_new_paid);
  end if;
end; $$;

-- ---------------------------------------------------------------------
-- 9. earn_invoice_commission (extended): voucher lines earn commission
--    like an Own product (15% tier1). Products keep their own/3rd-party rate.
-- ---------------------------------------------------------------------
create or replace function public.earn_invoice_commission(p_invoice_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_inv public.invoices%rowtype; v_tier1 uuid; v_tier2 uuid; v_item record;
  v_ptype text; v_subtotal numeric; v_discount numeric; v_line_after numeric;
  v_t1_rate numeric; v_t1_amt numeric; v_t2_amt numeric; v_paid_date date;
begin
  select * into v_inv from public.invoices where id = p_invoice_id;
  if not found then return; end if;

  select tier1, tier2 into v_tier1, v_tier2 from public.customer_referrers(v_inv.customer_id);
  if v_tier1 is null then return; end if;

  v_paid_date := coalesce(v_inv.paid_at, now())::date;
  v_subtotal := nullif(v_inv.subtotal, 0);
  v_discount := coalesce(v_inv.discount_total, 0);

  for v_item in
    select ii.id, ii.line_kind, ii.voucher_id, ii.line_total,
           coalesce(p.product_type::text, 'own') as ptype
    from public.invoice_items ii
    left join public.products p on p.id = ii.product_id
    where ii.invoice_id = p_invoice_id
  loop
    -- Vouchers commission like Own product; products by their type.
    if v_item.line_kind = 'voucher' then v_ptype := 'own'; else v_ptype := v_item.ptype; end if;

    if v_subtotal is null then v_line_after := v_item.line_total;
    else v_line_after := v_item.line_total - (v_discount * (v_item.line_total / v_subtotal)); end if;
    if v_line_after < 0 then v_line_after := 0; end if;

    v_t1_rate := case when v_ptype = 'third_party' then 4.5 else 15 end;
    v_t1_amt := round(v_line_after * v_t1_rate / 100.0, 2);
    if v_t1_amt <= 0 then continue; end if;

    insert into public.commissions
      (invoice_id, invoice_item_id, buyer_customer_id, referrer_customer_id, tier,
       product_type, line_amount, rate, commission_amount, status, invoice_paid_date)
    values (p_invoice_id, v_item.id, v_inv.customer_id, v_tier1, 'tier1',
       v_ptype, v_line_after, v_t1_rate, v_t1_amt, 'earned', v_paid_date);

    if v_tier2 is not null then
      v_t2_amt := round(v_t1_amt * 5.0 / 100.0, 2);
      if v_t2_amt > 0 then
        insert into public.commissions
          (invoice_id, invoice_item_id, buyer_customer_id, referrer_customer_id, tier,
           product_type, line_amount, rate, commission_amount, status, invoice_paid_date)
        values (p_invoice_id, v_item.id, v_inv.customer_id, v_tier2, 'tier2',
           v_ptype, v_t1_amt, 5.0, v_t2_amt, 'earned', v_paid_date);
      end if;
    end if;
  end loop;

  perform public.write_audit('commissions', p_invoice_id, 'commission_calculated', null,
    jsonb_build_object('invoice_no', v_inv.invoice_no, 'tier1', v_tier1, 'tier2', v_tier2));
end; $$;

notify pgrst, 'reload schema';
