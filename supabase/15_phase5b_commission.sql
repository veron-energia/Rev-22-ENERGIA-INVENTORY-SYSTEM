-- =====================================================================
-- ENERGIA — PHASE 5B: Two-tier customer-referral commission
--   * New commissions table (per invoice line, tier 1 + tier 2)
--   * Monthly commission payout grouping
--   * pay_invoice rewritten to compute referral commission
--   * resolve_invoice_action reverses commission on refund/cancel
--
-- Tier 1: Own 15% / 3rd-party 4.5% of the line amount AFTER discount.
-- Tier 2: 5% of the Tier-1 commission amount.
-- Referrers come from customers.referred_by (5A). Stops at Tier 2.
--
-- Additive + idempotent. Run AFTER 14_phase5a_foundations.sql.
-- =====================================================================

-- Ensure commission_status has 'paid' (older databases were created without it).
alter type public.commission_status add value if not exists 'paid';

-- ---------------------------------------------------------------------
-- Commission rate constants (kept in one place for clarity).
-- Own product Tier-1 = 15%, 3rd-party Tier-1 = 4.5%, Tier-2 = 5% of Tier-1.
-- ---------------------------------------------------------------------

-- ---------------------------------------------------------------------
-- 1. New per-line commission table.
-- ---------------------------------------------------------------------
do $$ begin
  create type commission_tier as enum ('tier1','tier2');
exception when duplicate_object then null; end $$;

create table if not exists public.commissions (
  id uuid primary key default gen_random_uuid(),
  invoice_id uuid not null references public.invoices(id) on delete cascade,
  invoice_item_id uuid references public.invoice_items(id) on delete set null,
  buyer_customer_id uuid not null references public.customers(id),
  referrer_customer_id uuid not null references public.customers(id),
  tier commission_tier not null,
  product_type text,                       -- 'own' | 'third_party'
  line_amount numeric(12,2) not null default 0,   -- after-discount basis
  rate numeric(6,3) not null default 0,           -- percent applied
  commission_amount numeric(12,2) not null default 0,
  status commission_status not null default 'earned',
  payout_id uuid,                          -- set when grouped into a monthly payout
  invoice_paid_date date,
  reversal_reason text,
  created_at timestamptz not null default now(),
  reversed_at timestamptz
);
create index if not exists idx_commissions_invoice on public.commissions(invoice_id);
create index if not exists idx_commissions_referrer on public.commissions(referrer_customer_id);
create index if not exists idx_commissions_status on public.commissions(status);
create index if not exists idx_commissions_paid_date on public.commissions(invoice_paid_date);

alter table public.commissions enable row level security;
drop policy if exists "read commissions new" on public.commissions;
create policy "read commissions new" on public.commissions for select to authenticated
  using (public.is_manager_or_above());

-- ---------------------------------------------------------------------
-- 2. Monthly commission payouts.
-- ---------------------------------------------------------------------
create table if not exists public.commission_payouts (
  id uuid primary key default gen_random_uuid(),
  payout_month date not null,              -- first day of the month
  referrer_customer_id uuid not null references public.customers(id),
  total_tier1 numeric(12,2) not null default 0,
  total_tier2 numeric(12,2) not null default 0,
  total_amount numeric(12,2) not null default 0,
  payment_method_id uuid references public.payment_methods(id),
  reference text,
  notes text,
  status text not null default 'paid',     -- 'paid' | 'cancelled'
  paid_by uuid references public.profiles(id),
  paid_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);
create index if not exists idx_payouts_month on public.commission_payouts(payout_month);
create index if not exists idx_payouts_referrer on public.commission_payouts(referrer_customer_id);

alter table public.commission_payouts enable row level security;
drop policy if exists "read payouts" on public.commission_payouts;
create policy "read payouts" on public.commission_payouts for select to authenticated
  using (public.is_manager_or_above());

-- ---------------------------------------------------------------------
-- 3. Core engine: earn commission for a fully-paid invoice.
--    Called from pay_invoice once an invoice flips to paid.
--    Allocates invoice discount proportionally across lines so the
--    commission basis is "after discount" (voucher-ready for 5C).
-- ---------------------------------------------------------------------
create or replace function public.earn_invoice_commission(p_invoice_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_inv public.invoices%rowtype;
  v_tier1 uuid; v_tier2 uuid;
  v_item record;
  v_ptype text;
  v_subtotal numeric;
  v_discount numeric;
  v_line_after numeric;
  v_t1_rate numeric;
  v_t1_amt numeric;
  v_t2_amt numeric;
  v_paid_date date;
begin
  select * into v_inv from public.invoices where id = p_invoice_id;
  if not found then return; end if;

  -- Resolve the buyer's referral chain (Tier 1 + Tier 2).
  select tier1, tier2 into v_tier1, v_tier2 from public.customer_referrers(v_inv.customer_id);
  if v_tier1 is null then return; end if;  -- no referrer → no commission

  v_paid_date := coalesce(v_inv.paid_at, now())::date;
  v_subtotal := nullif(v_inv.subtotal, 0);
  v_discount := coalesce(v_inv.discount_total, 0);

  for v_item in
    select ii.id, ii.product_id, ii.quantity, ii.line_total, p.product_type::text as ptype
    from public.invoice_items ii
    join public.products p on p.id = ii.product_id
    where ii.invoice_id = p_invoice_id
  loop
    v_ptype := v_item.ptype;

    -- Line amount after proportional discount allocation.
    if v_subtotal is null then
      v_line_after := v_item.line_total;
    else
      v_line_after := v_item.line_total - (v_discount * (v_item.line_total / v_subtotal));
    end if;
    if v_line_after < 0 then v_line_after := 0; end if;

    -- Tier-1 rate by product type (own 15%, third_party 4.5%).
    v_t1_rate := case when v_ptype = 'third_party' then 4.5 else 15 end;
    v_t1_amt := round(v_line_after * v_t1_rate / 100.0, 2);
    if v_t1_amt <= 0 then continue; end if;

    insert into public.commissions
      (invoice_id, invoice_item_id, buyer_customer_id, referrer_customer_id, tier,
       product_type, line_amount, rate, commission_amount, status, invoice_paid_date)
    values
      (p_invoice_id, v_item.id, v_inv.customer_id, v_tier1, 'tier1',
       v_ptype, v_line_after, v_t1_rate, v_t1_amt, 'earned', v_paid_date);

    -- Tier-2 = 5% of the Tier-1 amount (only if a Tier-2 referrer exists).
    if v_tier2 is not null then
      v_t2_amt := round(v_t1_amt * 5.0 / 100.0, 2);
      if v_t2_amt > 0 then
        insert into public.commissions
          (invoice_id, invoice_item_id, buyer_customer_id, referrer_customer_id, tier,
           product_type, line_amount, rate, commission_amount, status, invoice_paid_date)
        values
          (p_invoice_id, v_item.id, v_inv.customer_id, v_tier2, 'tier2',
           v_ptype, v_t1_amt, 5.0, v_t2_amt, 'earned', v_paid_date);
      end if;
    end if;
  end loop;

  perform public.write_audit('commissions', p_invoice_id, 'commission_calculated', null,
    jsonb_build_object('invoice_no', v_inv.invoice_no, 'tier1', v_tier1, 'tier2', v_tier2));
end; $$;

-- ---------------------------------------------------------------------
-- 4. Reverse commission for an invoice (on refund/cancel).
-- ---------------------------------------------------------------------
create or replace function public.reverse_invoice_commission(p_invoice_id uuid, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
begin
  update public.commissions
    set status = 'reversed', reversed_at = now(), reversal_reason = coalesce(p_reason,'invoice reversed')
    where invoice_id = p_invoice_id and status in ('earned');
  perform public.write_audit('commissions', p_invoice_id, 'commission_reversed', null,
    jsonb_build_object('reason', p_reason));
end; $$;

-- ---------------------------------------------------------------------
-- 5. pay_invoice — rewritten to use the new commission engine.
--    (Stock deduction + payment logic unchanged; only the commission
--    block at the end is replaced.)
-- ---------------------------------------------------------------------
create or replace function public.pay_invoice(p_invoice_id uuid, p_payments jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_inv public.invoices%rowtype; v_pay jsonb; v_method uuid; v_amount numeric;
  v_total_paying numeric := 0; v_already_paid numeric; v_new_paid numeric;
  v_item record; v_available integer;
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

  if v_new_paid >= v_inv.total_amount - 0.001 then
    for v_item in select product_id, quantity from public.invoice_items where invoice_id = p_invoice_id
    loop
      select current_qty into v_available from public.store_inventory
        where store_id = v_inv.store_id and product_id = v_item.product_id for update;
      if coalesce(v_available,0) < v_item.quantity then
        raise exception 'Insufficient store stock for a product (have %, need %). Payment blocked.', coalesce(v_available,0), v_item.quantity;
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
    for v_item in select product_id, quantity from public.invoice_items where invoice_id = p_invoice_id
    loop
      update public.store_inventory set current_qty = current_qty - v_item.quantity, updated_at = now()
        where store_id = v_inv.store_id and product_id = v_item.product_id;
      insert into public.stock_movements (product_id, movement_type, from_store_id, invoice_id, quantity, notes, created_by)
      values (v_item.product_id, 'store_sale', v_inv.store_id, p_invoice_id, v_item.quantity, 'Sale — '||v_inv.invoice_no, auth.uid());
    end loop;

    update public.invoices set status = 'paid', paid_amount = v_new_paid, paid_at = now(), locked_at = now()
      where id = p_invoice_id;

    -- NEW: two-tier referral commission.
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
-- 6. resolve_invoice_action — reverse NEW commissions on refund/cancel.
--    (Same logic as before; swaps the old affiliate_commissions update
--     for reverse_invoice_commission.)
-- ---------------------------------------------------------------------
create or replace function public.resolve_invoice_action(
  p_request_id uuid, p_approve boolean, p_note text default null
) returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_req public.approval_requests%rowtype; v_inv public.invoices%rowtype;
  v_return_stock boolean; v_item record; v_is_refund boolean; v_final_status invoice_status;
begin
  if not public.is_owner_or_manager() then raise exception 'Only Owner or Manager can approve'; end if;
  select * into v_req from public.approval_requests where id = p_request_id for update;
  if not found then raise exception 'Request not found'; end if;
  if v_req.status <> 'pending' then raise exception 'Request is not pending'; end if;

  select * into v_inv from public.invoices where id = v_req.related_record_id for update;
  v_is_refund := (v_req.request_type = 'invoice_refund');
  v_return_stock := coalesce((v_req.payload->>'return_stock')::boolean, false);

  if not p_approve then
    update public.invoices set status = (case when v_is_refund then 'paid' else 'unpaid' end)::invoice_status where id = v_inv.id;
    update public.approval_requests set status = 'rejected', approved_by = auth.uid(),
      approved_at = now(), response_note = p_note where id = p_request_id;
    perform public.write_audit('invoices', v_inv.id, 'invoice_action_rejected', null,
      jsonb_build_object('request_type', v_req.request_type));
    return jsonb_build_object('success', true, 'status', 'rejected');
  end if;

  v_final_status := case when v_is_refund then 'refunded'::invoice_status else 'cancelled'::invoice_status end;

  if v_return_stock then
    for v_item in select product_id, quantity from public.invoice_items where invoice_id = v_inv.id
    loop
      insert into public.store_inventory (store_id, product_id, current_qty)
      values (v_inv.store_id, v_item.product_id, v_item.quantity)
      on conflict (store_id, product_id)
      do update set current_qty = public.store_inventory.current_qty + v_item.quantity, updated_at = now();
      insert into public.stock_movements (product_id, movement_type, to_store_id, invoice_id, quantity, notes, created_by)
      values (v_item.product_id,
        (case when v_is_refund then 'invoice_refund_return' else 'invoice_cancel_return' end)::stock_movement_type,
        v_inv.store_id, v_inv.id, v_item.quantity, 'Stock returned — '||v_inv.invoice_no, auth.uid());
    end loop;
  end if;

  -- NEW: reverse two-tier commission.
  perform public.reverse_invoice_commission(v_inv.id,
    case when v_is_refund then 'invoice refunded' else 'invoice cancelled' end);

  update public.invoices set status = v_final_status where id = v_inv.id;
  update public.approval_requests set status = 'approved', approved_by = auth.uid(),
    approved_at = now(), response_note = p_note where id = p_request_id;

  perform public.write_audit('invoices', v_inv.id,
    case when v_is_refund then 'invoice_refunded' else 'invoice_cancelled' end, null,
    jsonb_build_object('return_stock', v_return_stock, 'invoice_no', v_inv.invoice_no));
  return jsonb_build_object('success', true, 'status', v_final_status, 'stock_returned', v_return_stock);
end; $$;

-- ---------------------------------------------------------------------
-- 7. Create a monthly payout: groups all earned+unpaid commissions for a
--    referrer in a given month (by invoice_paid_date) into one payout.
-- ---------------------------------------------------------------------
create or replace function public.create_commission_payout(
  p_referrer_customer_id uuid, p_month date, p_payment_method_id uuid,
  p_reference text default null, p_notes text default null
) returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_month_start date := date_trunc('month', p_month)::date;
  v_month_end date := (date_trunc('month', p_month) + interval '1 month - 1 day')::date;
  v_t1 numeric := 0; v_t2 numeric := 0; v_payout_id uuid;
begin
  if not public.is_owner_or_manager() then raise exception 'Only Owner or Manager can mark commission paid'; end if;

  select
    coalesce(sum(case when tier='tier1' then commission_amount else 0 end),0),
    coalesce(sum(case when tier='tier2' then commission_amount else 0 end),0)
    into v_t1, v_t2
    from public.commissions
    where referrer_customer_id = p_referrer_customer_id
      and status = 'earned' and payout_id is null
      and invoice_paid_date between v_month_start and v_month_end;

  if (v_t1 + v_t2) <= 0 then raise exception 'No unpaid commission for this referrer in that month'; end if;

  insert into public.commission_payouts
    (payout_month, referrer_customer_id, total_tier1, total_tier2, total_amount,
     payment_method_id, reference, notes, status, paid_by)
  values (v_month_start, p_referrer_customer_id, v_t1, v_t2, v_t1 + v_t2,
     p_payment_method_id, p_reference, p_notes, 'paid', auth.uid())
  returning id into v_payout_id;

  update public.commissions
    set status = 'paid', payout_id = v_payout_id
    where referrer_customer_id = p_referrer_customer_id
      and status = 'earned' and payout_id is null
      and invoice_paid_date between v_month_start and v_month_end;

  perform public.write_audit('commission_payouts', v_payout_id, 'commission_payout_created', null,
    jsonb_build_object('month', v_month_start, 'referrer', p_referrer_customer_id, 'total', v_t1 + v_t2));
  return v_payout_id;
end; $$;

notify pgrst, 'reload schema';
