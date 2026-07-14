-- =====================================================================
-- ENERGIA — NEW SPEC PHASE 3A: Simple product-to-product exchange
--
-- Scope 3A: single products only (not bundles/promotions — that's 3B).
-- Staff complete the exchange directly (no approval, per your decision).
-- Exchange credit uses the CURRENT store price at exchange time (your
-- decision), not the original invoice price.
--
-- Rules enforced (spec 3.1/3.3/3.4/3.5):
--   * original invoice fully paid, not cancelled/refunded/soft-deleted
--   * within 5 calendar days SG time (Day 1 = purchase date; deadline end
--     of Day 5 = paid date + 4 days, Asia/Singapore)
--   * each original item exchanged at most once
--   * own <-> own, third_party <-> third_party only
--   * returned qty added to processing store; replacement deducted from it
--   * replacement stock must be sufficient
--   * top-up collected (multi-payment) when replacement > credit;
--     non-refundable balance recorded when replacement < credit
--   * everything atomic; exchange locked on completion
--
-- Additive + idempotent. Run AFTER 32_specphase2b_phone_history.sql.
-- =====================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------
-- 0. Movement types for exchange in/out (extend enum if missing).
-- ---------------------------------------------------------------------
do $$ begin alter type stock_movement_type add value if not exists 'exchange_return_in'; exception when others then null; end $$;
do $$ begin alter type stock_movement_type add value if not exists 'exchange_replacement_out'; exception when others then null; end $$;

-- ---------------------------------------------------------------------
-- 1. Tables.
-- ---------------------------------------------------------------------
create table if not exists public.product_exchanges (
  id uuid primary key default gen_random_uuid(),
  exchange_no text not null unique,
  original_invoice_id uuid not null references public.invoices(id),
  customer_id uuid not null references public.customers(id),
  processing_store_id uuid not null references public.stores(id),
  affiliate_id uuid references public.affiliates(id),
  returned_credit_total numeric(12,2) not null default 0,
  replacement_total numeric(12,2) not null default 0,
  topup_amount numeric(12,2) not null default 0,
  nonrefundable_amount numeric(12,2) not null default 0,
  status text not null default 'completed',
  reason text,
  notes text,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  locked_at timestamptz
);
create index if not exists idx_pex_orig on public.product_exchanges(original_invoice_id);
create index if not exists idx_pex_cust on public.product_exchanges(customer_id);

create table if not exists public.product_exchange_items (
  id uuid primary key default gen_random_uuid(),
  exchange_id uuid not null references public.product_exchanges(id) on delete cascade,
  direction text not null check (direction in ('returned','replacement')),
  original_invoice_item_id uuid references public.invoice_items(id),
  product_id uuid not null references public.products(id),
  quantity integer not null check (quantity > 0),
  unit_price numeric(12,2) not null default 0,
  line_total numeric(12,2) not null default 0
);
create index if not exists idx_pexi_ex on public.product_exchange_items(exchange_id);

create table if not exists public.product_exchange_payments (
  id uuid primary key default gen_random_uuid(),
  exchange_id uuid not null references public.product_exchanges(id) on delete cascade,
  payment_method_id uuid references public.payment_methods(id),
  amount numeric(12,2) not null check (amount > 0),
  reference text,
  created_at timestamptz not null default now()
);
create index if not exists idx_pexp_ex on public.product_exchange_payments(exchange_id);

-- Track which original invoice items have been exchanged (prevents re-use).
alter table public.invoice_items add column if not exists exchanged_at timestamptz;
alter table public.invoice_items add column if not exists exchange_id uuid references public.product_exchanges(id);

-- ---------------------------------------------------------------------
-- 2. RLS: read for users with access to the processing store; Owner/
--    Manager see all. Writes go through the RPC only.
-- ---------------------------------------------------------------------
alter table public.product_exchanges enable row level security;
alter table public.product_exchange_items enable row level security;
alter table public.product_exchange_payments enable row level security;

drop policy if exists "read exchanges" on public.product_exchanges;
create policy "read exchanges" on public.product_exchanges for select to authenticated
  using (public.is_manager_or_above() or public.user_has_store_access(processing_store_id));
drop policy if exists "read exchange items" on public.product_exchange_items;
create policy "read exchange items" on public.product_exchange_items for select to authenticated
  using (exists (select 1 from public.product_exchanges e where e.id = exchange_id
    and (public.is_manager_or_above() or public.user_has_store_access(e.processing_store_id))));
drop policy if exists "read exchange payments" on public.product_exchange_payments;
create policy "read exchange payments" on public.product_exchange_payments for select to authenticated
  using (exists (select 1 from public.product_exchanges e where e.id = exchange_id
    and (public.is_manager_or_above() or public.user_has_store_access(e.processing_store_id))));

-- ---------------------------------------------------------------------
-- 3. Eligibility helper: is this invoice within the 5-day SG window and
--    in an exchangeable state? Returns text reason ('' = ok).
-- ---------------------------------------------------------------------
create or replace function public.exchange_ineligibility_reason(p_invoice_id uuid)
returns text language plpgsql stable security definer set search_path = public as $$
declare v_inv public.invoices%rowtype; v_paid_date date; v_deadline date;
begin
  select * into v_inv from public.invoices where id = p_invoice_id;
  if not found then return 'Invoice not found'; end if;
  if v_inv.deleted_at is not null then return 'Invoice has been deleted'; end if;
  if v_inv.status <> 'paid' then return 'Invoice is not fully paid'; end if;
  if v_inv.paid_at is null then return 'Invoice has no payment date'; end if;
  v_paid_date := (v_inv.paid_at at time zone 'Asia/Singapore')::date;
  v_deadline := v_paid_date + 4;   -- Day 1 = purchase date; through end of Day 5
  if public.sg_today() > v_deadline then
    return 'Exchange window has closed (5 days from purchase, by ' || to_char(v_deadline, 'DD Mon YYYY') || ')';
  end if;
  return '';
end $$;

-- ---------------------------------------------------------------------
-- 4. Create + complete a product exchange (atomic, direct completion).
-- ---------------------------------------------------------------------
create or replace function public.create_product_exchange(
  p_original_invoice_id uuid,
  p_processing_store_id uuid,
  p_returned jsonb,        -- [{invoice_item_id, quantity}]
  p_replacement jsonb,     -- [{product_id, quantity}]
  p_payments jsonb default '[]'::jsonb,  -- [{payment_method_id, amount, reference}]
  p_reason text default null,
  p_notes text default null
) returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_inv public.invoices%rowtype;
  v_reason text; v_line jsonb; v_ex_id uuid; v_no text;
  v_item public.invoice_items%rowtype; v_ptype product_type; v_side_type product_type;
  v_price numeric; v_qty integer; v_avail integer;
  v_credit numeric := 0; v_repl numeric := 0; v_topup numeric; v_nonref numeric := 0;
  v_pay_sum numeric := 0; v_prod_id uuid; v_role user_role;
begin
  v_role := public.current_user_role();
  if v_role is null then raise exception 'No profile for current user'; end if;

  -- Eligibility.
  v_reason := public.exchange_ineligibility_reason(p_original_invoice_id);
  if v_reason <> '' then raise exception '%', v_reason; end if;

  select * into v_inv from public.invoices where id = p_original_invoice_id for update;

  -- Staff may only process for their assigned store.
  if v_role = 'staff' and public.my_assigned_store_id() is distinct from p_processing_store_id then
    raise exception 'You can only process exchanges for your assigned store';
  end if;
  if not public.user_has_store_access(p_processing_store_id) then
    raise exception 'You do not have access to the processing store';
  end if;

  if p_returned is null or jsonb_array_length(p_returned) = 0 then raise exception 'Select at least one item to return'; end if;
  if p_replacement is null or jsonb_array_length(p_replacement) = 0 then raise exception 'Select at least one replacement product'; end if;
  if p_reason is null or length(trim(p_reason)) = 0 then raise exception 'A reason is required for the exchange'; end if;

  -- ---- Returned side: validate items, determine product type, credit ----
  for v_line in select * from jsonb_array_elements(p_returned)
  loop
    select * into v_item from public.invoice_items
      where id = (v_line->>'invoice_item_id')::uuid and invoice_id = p_original_invoice_id for update;
    if not found then raise exception 'A returned item is not part of the original invoice'; end if;
    if v_item.line_kind <> 'product' then raise exception 'Bundle/voucher lines are handled in the bundle exchange (3B), not here'; end if;
    if v_item.exchanged_at is not null then raise exception 'An item on this invoice has already been exchanged'; end if;
    v_qty := coalesce((v_line->>'quantity')::integer, v_item.quantity);
    if v_qty <> v_item.quantity then raise exception 'Return the full quantity of the purchased line in 3A'; end if;

    select product_type into v_ptype from public.products where id = v_item.product_id;
    if v_side_type is null then v_side_type := v_ptype;
    elsif v_side_type <> v_ptype then raise exception 'All returned items must be the same product type'; end if;

    -- Credit = current processing-store price * qty.
    select selling_price into v_price from public.store_product_prices
      where store_id = p_processing_store_id and product_id = v_item.product_id and is_active = true;
    if v_price is null then raise exception 'Returned product has no active price at the processing store'; end if;
    v_credit := v_credit + v_price * v_item.quantity;
  end loop;

  -- ---- Replacement side: validate type match + stock, compute total ----
  for v_line in select * from jsonb_array_elements(p_replacement)
  loop
    v_prod_id := (v_line->>'product_id')::uuid;
    v_qty := (v_line->>'quantity')::integer;
    if v_qty is null or v_qty <= 0 then raise exception 'Replacement quantity must be greater than zero'; end if;

    select product_type into v_ptype from public.products where id = v_prod_id;
    if v_ptype is null then raise exception 'Replacement product not found'; end if;
    if v_ptype <> v_side_type then
      raise exception 'Own products may only be exchanged for own products, and third-party for third-party';
    end if;

    select selling_price into v_price from public.store_product_prices
      where store_id = p_processing_store_id and product_id = v_prod_id and is_active = true;
    if v_price is null then raise exception 'A replacement product has no active price at the processing store'; end if;
    v_repl := v_repl + v_price * v_qty;

    select current_qty into v_avail from public.store_inventory
      where store_id = p_processing_store_id and product_id = v_prod_id for update;
    if coalesce(v_avail, 0) < v_qty then raise exception 'Insufficient replacement stock at the processing store'; end if;
  end loop;

  -- ---- Money ----
  v_topup := round(v_repl - v_credit, 2);
  if v_topup > 0 then
    select coalesce(sum((x->>'amount')::numeric), 0) into v_pay_sum from jsonb_array_elements(p_payments) x;
    if round(v_pay_sum, 2) <> v_topup then
      raise exception 'Top-up payment (%.2f) must equal the amount due (%.2f)', v_pay_sum, v_topup;
    end if;
    v_nonref := 0;
  elsif v_topup < 0 then
    v_nonref := -v_topup; v_topup := 0;   -- non-refundable, no money moves
  else
    v_topup := 0; v_nonref := 0;
  end if;

  -- ---- Create exchange header ----
  v_no := 'EX-' || to_char(now() at time zone 'Asia/Singapore', 'YYYYMMDD') || '-' || substr(gen_random_uuid()::text, 1, 6);
  insert into public.product_exchanges
    (exchange_no, original_invoice_id, customer_id, processing_store_id, affiliate_id,
     returned_credit_total, replacement_total, topup_amount, nonrefundable_amount,
     status, reason, notes, created_by, locked_at)
  values (v_no, p_original_invoice_id, v_inv.customer_id, p_processing_store_id, v_inv.affiliate_id,
     v_credit, v_repl, v_topup, v_nonref, 'completed', p_reason, p_notes, auth.uid(), now())
  returning id into v_ex_id;

  -- ---- Returned items: record, mark exchanged, add stock back ----
  for v_line in select * from jsonb_array_elements(p_returned)
  loop
    select * into v_item from public.invoice_items where id = (v_line->>'invoice_item_id')::uuid;
    select selling_price into v_price from public.store_product_prices
      where store_id = p_processing_store_id and product_id = v_item.product_id and is_active = true;

    insert into public.product_exchange_items (exchange_id, direction, original_invoice_item_id, product_id, quantity, unit_price, line_total)
    values (v_ex_id, 'returned', v_item.id, v_item.product_id, v_item.quantity, v_price, v_price * v_item.quantity);

    update public.invoice_items set exchanged_at = now(), exchange_id = v_ex_id where id = v_item.id;

    insert into public.store_inventory (store_id, product_id, current_qty)
      values (p_processing_store_id, v_item.product_id, v_item.quantity)
      on conflict (store_id, product_id) do update set current_qty = public.store_inventory.current_qty + excluded.current_qty, updated_at = now();

    insert into public.stock_movements (product_id, movement_type, to_store_id, quantity, notes, created_by)
      values (v_item.product_id, 'exchange_return_in', p_processing_store_id, v_item.quantity, 'Exchange ' || v_no || ' — returned', auth.uid());
  end loop;

  -- ---- Replacement items: record, deduct stock ----
  for v_line in select * from jsonb_array_elements(p_replacement)
  loop
    v_prod_id := (v_line->>'product_id')::uuid;
    v_qty := (v_line->>'quantity')::integer;
    select selling_price into v_price from public.store_product_prices
      where store_id = p_processing_store_id and product_id = v_prod_id and is_active = true;

    insert into public.product_exchange_items (exchange_id, direction, product_id, quantity, unit_price, line_total)
    values (v_ex_id, 'replacement', v_prod_id, v_qty, v_price, v_price * v_qty);

    update public.store_inventory set current_qty = current_qty - v_qty, updated_at = now()
      where store_id = p_processing_store_id and product_id = v_prod_id;

    insert into public.stock_movements (product_id, movement_type, from_store_id, quantity, notes, created_by)
      values (v_prod_id, 'exchange_replacement_out', p_processing_store_id, v_qty, 'Exchange ' || v_no || ' — replacement', auth.uid());
  end loop;

  -- ---- Top-up payments ----
  if v_topup > 0 then
    for v_line in select * from jsonb_array_elements(p_payments)
    loop
      insert into public.product_exchange_payments (exchange_id, payment_method_id, amount, reference)
      values (v_ex_id, nullif(v_line->>'payment_method_id','')::uuid, (v_line->>'amount')::numeric, nullif(v_line->>'reference',''));
    end loop;
  end if;

  perform public.write_audit_ex('product_exchanges', v_ex_id, 'exchange_completed', null,
    jsonb_build_object('exchange_no', v_no, 'credit', v_credit, 'replacement', v_repl, 'topup', v_topup, 'nonrefundable', v_nonref),
    'exchanges', p_reason, p_processing_store_id);

  return jsonb_build_object('success', true, 'id', v_ex_id, 'exchange_no', v_no,
    'credit', v_credit, 'replacement', v_repl, 'topup', v_topup, 'nonrefundable', v_nonref);
end $$;

notify pgrst, 'reload schema';
