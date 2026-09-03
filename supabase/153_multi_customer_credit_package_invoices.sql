-- =====================================================================
-- ENERGIA — SPLIT ONE CREDIT PACKAGE PURCHASE INTO SEVERAL NORMAL INVOICES
--
-- One Credit Package is allocated between several customers at creation time,
-- and each customer gets their OWN ordinary invoice (own number, payment,
-- issuance, commission, refund, audit). Each invoice's credit_package line
-- carries THAT customer's allocated Paid Credit, Bonus Credit and reward
-- voucher quantity as permanent snapshots. When a child invoice is paid, the
-- existing settlement path issues exactly the snapshotted allocation — never
-- the full package — so no customer can receive the whole package's benefit.
--
-- This supersedes migration 141 (invoice_credit_splits + set_invoice_credit_split),
-- which recorded several recipients against ONE invoice line and — because it
-- reused the full-package issuer per recipient — granted each recipient the
-- FULL package credit. Nothing here deletes 141's data or functions; the new
-- UI simply does not use them, and the settlement path keeps a legacy branch
-- so any historical invoice_credit_splits rows still settle as before.
--
-- Reuses the existing Credit Package, wallet (grant_customer_credit), invoice,
-- commission (earn_credit_package_commission), reward-entitlement, Served-by
-- (invoice_service_staff) and audit architecture. No new wallet/payment/
-- commission/voucher/invoice systems are introduced.
--
-- Additive and idempotent. Run AFTER 152.
-- =====================================================================

set check_function_bodies = off;

-- =====================================================================
-- 1. Split-group + allocation records (audit / reconciliation linkage).
-- =====================================================================
create table if not exists public.credit_package_split_groups (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id),
  credit_package_id uuid not null references public.credit_packages(id),
  package_name_snapshot text not null,
  package_price_snapshot numeric(12,2) not null,
  paid_credit_total_snapshot numeric(12,2) not null,
  bonus_credit_total_snapshot numeric(12,2) not null,
  reward_voucher_total_snapshot integer not null default 0,
  customer_count integer not null,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now()
);

create table if not exists public.credit_package_split_allocations (
  id uuid primary key default gen_random_uuid(),
  split_group_id uuid not null references public.credit_package_split_groups(id) on delete cascade,
  invoice_id uuid not null references public.invoices(id),
  invoice_item_id uuid not null references public.invoice_items(id),
  customer_id uuid not null references public.customers(id),
  payment_amount numeric(12,2) not null,
  allocation_percent numeric(7,4) not null,
  paid_credit_amount numeric(12,2) not null,
  bonus_credit_amount numeric(12,2) not null,
  reward_voucher_qty integer not null default 0,
  created_at timestamptz not null default now()
);

create index if not exists idx_cpsg_package on public.credit_package_split_groups(credit_package_id);
create index if not exists idx_cpsg_store on public.credit_package_split_groups(store_id);
create index if not exists idx_cpsa_group on public.credit_package_split_allocations(split_group_id);
create index if not exists idx_cpsa_invoice on public.credit_package_split_allocations(invoice_id);
create index if not exists idx_cpsa_customer on public.credit_package_split_allocations(customer_id);

alter table public.credit_package_split_groups enable row level security;
alter table public.credit_package_split_allocations enable row level security;
drop policy if exists "read split groups" on public.credit_package_split_groups;
create policy "read split groups" on public.credit_package_split_groups for select using (auth.uid() is not null);
drop policy if exists "read split allocations" on public.credit_package_split_allocations;
create policy "read split allocations" on public.credit_package_split_allocations for select using (auth.uid() is not null);

-- =====================================================================
-- 2. Snapshot columns on the invoice line (never overwrite catalogue price).
-- =====================================================================
alter table public.invoice_items add column if not exists credit_split_group_id uuid references public.credit_package_split_groups(id);
alter table public.invoice_items add column if not exists credit_split_allocation_id uuid references public.credit_package_split_allocations(id);
alter table public.invoice_items add column if not exists credit_split_ratio numeric(7,4);
alter table public.invoice_items add column if not exists credit_package_full_price_snapshot numeric(12,2);
create index if not exists idx_invoice_items_split_group on public.invoice_items(credit_split_group_id);

-- =====================================================================
-- 3. Exact allocated voucher count on the sale record (reward_units alone
--    could only express multiples of the per-unit voucher count).
-- =====================================================================
alter table public.credit_package_sales add column if not exists reward_voucher_qty integer;
-- Backfill: historically each reward unit granted 10 vouchers.
update public.credit_package_sales
   set reward_voucher_qty = reward_units * 10
 where reward_voucher_qty is null;

-- =====================================================================
-- 4. Deterministic, remainder-safe proportional allocation helpers.
--    The sum of the parts always equals the whole — no cent or voucher is
--    lost or created. Reused everywhere an amount is divided by weights.
-- =====================================================================

-- Money: split p_total into one amount per weight, cents exact.
create or replace function public.split_amount_by_weights(p_total numeric, p_weights numeric[])
returns numeric[] language plpgsql immutable as $function$
declare
  n integer := array_length(p_weights, 1);
  v_sumw numeric := 0; v_base numeric[]; v_frac numeric[]; v_cents_total bigint;
  v_assigned bigint := 0; v_short bigint; i integer;
  v_order integer[];
begin
  if n is null or n = 0 then return '{}'::numeric[]; end if;
  for i in 1..n loop v_sumw := v_sumw + coalesce(p_weights[i],0); end loop;
  v_base := array_fill(0::numeric, array[n]);
  v_frac := array_fill(0::numeric, array[n]);
  v_cents_total := round(p_total * 100)::bigint;

  if v_sumw <= 0 then
    -- No weights: put everything on the first slot deterministically.
    v_base[1] := p_total;
    return v_base;
  end if;

  -- Floor each share to the cent; remember the dropped fractional cents.
  for i in 1..n loop
    declare v_raw numeric := (v_cents_total::numeric) * coalesce(p_weights[i],0) / v_sumw;
    begin
      v_base[i] := floor(v_raw);          -- in cents
      v_frac[i] := v_raw - floor(v_raw);  -- fractional cent remainder
      v_assigned := v_assigned + floor(v_raw)::bigint;
    end;
  end loop;

  -- Hand out the remaining cents to the largest fractional remainders,
  -- ties broken by lowest index — fully deterministic.
  v_short := v_cents_total - v_assigned;
  select array_agg(idx order by v_frac[idx] desc, idx) into v_order
    from generate_series(1, n) idx;
  for i in 1..v_short loop
    v_base[v_order[i]] := v_base[v_order[i]] + 1;
  end loop;

  -- Back to currency.
  for i in 1..n loop v_base[i] := round(v_base[i] / 100.0, 2); end loop;
  return v_base;
end; $function$;

-- Whole units (vouchers): largest-remainder split of an integer total.
create or replace function public.split_int_by_weights(p_total integer, p_weights numeric[])
returns integer[] language plpgsql immutable as $function$
declare
  n integer := array_length(p_weights, 1);
  v_sumw numeric := 0; v_base integer[]; v_frac numeric[]; v_assigned integer := 0;
  v_short integer; i integer; v_order integer[];
begin
  if n is null or n = 0 then return '{}'::integer[]; end if;
  if coalesce(p_total,0) = 0 then return array_fill(0, array[n]); end if;
  for i in 1..n loop v_sumw := v_sumw + coalesce(p_weights[i],0); end loop;
  v_base := array_fill(0, array[n]);
  v_frac := array_fill(0::numeric, array[n]);
  if v_sumw <= 0 then v_base[1] := p_total; return v_base; end if;

  for i in 1..n loop
    declare v_raw numeric := p_total * coalesce(p_weights[i],0) / v_sumw;
    begin
      v_base[i] := floor(v_raw)::integer;
      v_frac[i] := v_raw - floor(v_raw);
      v_assigned := v_assigned + floor(v_raw)::integer;
    end;
  end loop;

  v_short := p_total - v_assigned;
  select array_agg(idx order by v_frac[idx] desc, idx) into v_order
    from generate_series(1, n) idx;
  for i in 1..v_short loop
    v_base[v_order[i]] := v_base[v_order[i]] + 1;
  end loop;
  return v_base;
end; $function$;

-- =====================================================================
-- 5. Snapshot-based issuer: grants EXACTLY the invoice line's allocation.
--    Used for split-child credit_package lines. Reuses grant_customer_credit
--    and the reward-entitlement structure; never re-reads the full package
--    monetary values. Records a credit_package_sales row (so commission is
--    earned on the child's external money) and returns its sale_id.
-- =====================================================================
create or replace function public.issue_credit_package_invoice_item(p_invoice_item_id uuid)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare
  v_it public.invoice_items%rowtype; v_inv public.invoices%rowtype;
  pk public.credit_packages%rowtype;
  v_lot uuid; v_bonus_lot uuid; v_sale uuid; v_ent uuid;
  v_vouchers uuid[]; v_restrict jsonb; v_qual numeric; v_rule public.therapy_package_rules;
  v_external numeric; v_paid numeric; v_bonus numeric; v_vq integer; v_deadline date;
begin
  select * into v_it from public.invoice_items where id = p_invoice_item_id for update;
  if not found then raise exception 'Invoice item not found'; end if;
  if v_it.line_kind <> 'credit_package' then
    raise exception 'issue_credit_package_invoice_item is only for credit_package lines'; end if;
  select * into v_inv from public.invoices where id = v_it.invoice_id;

  select * into pk from public.credit_packages where id = v_it.credit_package_id;
  if not found then raise exception 'Credit package not found'; end if;

  v_paid  := coalesce(v_it.credit_paid_snapshot, 0);
  v_bonus := coalesce(v_it.credit_bonus_snapshot, 0);
  v_vq    := coalesce(v_it.credit_voucher_qty_snapshot, 0);

  -- External money attributable to this line (mirrors issue_credit_lines_for_invoice).
  v_external := round(coalesce(v_it.line_total,0)
    - case when coalesce(v_inv.subtotal,0) > 0
           then coalesce(v_inv.discount_total,0) * (coalesce(v_it.line_total,0) / v_inv.subtotal)
           else 0 end, 2);
  if v_external < 0 then v_external := 0; end if;

  -- Category restrictions snapshotted exactly as the full-package issuer does.
  select coalesce(array_agg(voucher_id), '{}') into v_vouchers
    from public.credit_package_vouchers where package_id = pk.id;
  v_restrict := jsonb_build_object('allowed_purposes', public.credit_package_purposes(pk.id),
                                   'source', 'credit_package');
  if array_length(v_vouchers, 1) is not null and not pk.allow_voucher then
    v_restrict := v_restrict || jsonb_build_object(
      'allowed_voucher_ids', (select jsonb_agg(v::text) from unnest(v_vouchers) v));
  end if;

  -- Paid Credit — exactly the allocated amount.
  if v_paid > 0 then
    v_lot := public.grant_customer_credit(
      v_inv.customer_id, 'paid', v_paid, 'credit_package', pk.id, v_inv.store_id,
      public.sg_today(), null, 'Credit package: ' || pk.name, null, null, auth.uid(), v_restrict);
  end if;

  -- Bonus Credit — exactly the allocated amount (already apportioned at creation).
  if v_bonus > 0 then
    v_bonus_lot := public.grant_customer_credit(
      v_inv.customer_id, 'bonus', v_bonus, 'credit_package', pk.id, v_inv.store_id,
      public.sg_today(), null, 'Credit package bonus: ' || pk.name, null, null, auth.uid(),
      jsonb_build_object('allowed_purposes', public.bonus_credit_purposes(),
                         'source', 'credit_package_bonus'));
  end if;

  v_rule := public.legacy_lowest_rule(v_inv.store_id, public.sg_today());
  v_qual := coalesce(pk.reward_qualifying_amount, v_rule.qualifying_amount, 994);

  -- Sale record — allocated price / credit, exact allocated voucher count.
  insert into public.credit_package_sales (
    package_id, customer_id, store_id, invoice_id, package_name_snapshot,
    price_snapshot, credit_snapshot, classification_snapshot,
    tier1_rate_snapshot, tier2_rate_snapshot, staff_rate_snapshot,
    reward_qualifying_snapshot, eligible_voucher_ids, external_paid,
    credit_lot_id, reward_units, reward_voucher_qty, created_by)
  values (pk.id, v_inv.customer_id, v_inv.store_id, v_inv.id,
    coalesce(v_it.plan_name_snapshot, pk.name),
    coalesce(v_it.unit_price, v_paid), v_paid, pk.commission_classification,
    pk.tier1_rate, pk.tier2_rate, pk.staff_commission_rate,
    v_qual, v_vouchers, coalesce(v_external,0), v_lot,
    0, v_vq, auth.uid())
  returning id into v_sale;

  -- Reward vouchers — ONE entitlement for the exact allocated quantity
  -- (arbitrary whole numbers such as 3, 12, 17 — not fixed multiples).
  if v_vq > 0 then
    v_deadline := public.sg_today() + coalesce(v_rule.activation_deadline_days, 365);
    insert into public.therapy_entitlements (
      entitlement_no, customer_id, store_id, rule_id, package_name,
      entitlement_kind, duration_months, voucher_qty, qualifying_amount,
      qualified_value, forfeited_value, activation_deadline, status,
      created_by, qualification_group_id, earner_kind)
    values (public.next_legacy_entitlement_no(), v_inv.customer_id, v_inv.store_id, null,
      'Credit package reward — ' || pk.name,
      'voucher', coalesce(v_rule.duration_months, 1), v_vq, v_qual,
      coalesce(v_it.unit_price, v_paid), 0, v_deadline,
      'pending_activation', auth.uid(), md5('credit_pkg_item:' || v_it.id::text)::uuid, 'credit_package')
    returning id into v_ent;
  end if;

  perform public.write_audit_ex('credit_package_sales', v_sale, 'credit_package_issued_split', null,
    jsonb_build_object('package', pk.name, 'credit', v_paid, 'bonus', v_bonus,
      'external_paid', v_external, 'reward_vouchers', v_vq,
      'split_allocation', v_it.credit_split_allocation_id), 'credit', null, v_inv.store_id);

  return jsonb_build_object('sale_id', v_sale, 'credit_lot_id', v_lot, 'bonus_lot_id', v_bonus_lot,
    'credit_issued', v_paid, 'bonus_issued', v_bonus, 'reward_vouchers', v_vq,
    'entitlement_id', v_ent, 'snapshot_based', true);
end $function$;

-- =====================================================================
-- 6. Canonical settlement issuance. Three cases for a credit_package line:
--      a) NEW split child (credit_split_allocation_id set) -> snapshot issuer;
--      b) LEGACY invoice_credit_splits rows present -> old per-recipient path;
--      c) ordinary single-customer package -> the full-package issuer.
--    credit_issued_at remains the idempotency guard, rows locked FOR UPDATE.
-- =====================================================================
create or replace function public.issue_credit_lines_for_invoice(p_invoice_id uuid)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare
  v_inv public.invoices%rowtype; v_it record; v_res jsonb;
  v_out jsonb := '[]'::jsonb; v_external numeric; v_s record; v_share_ext numeric; v_line numeric;
begin
  select * into v_inv from public.invoices where id = p_invoice_id;
  if not found then return jsonb_build_object('skipped', true); end if;
  if v_inv.status not in ('paid','completed_foc') then
    return jsonb_build_object('skipped', true, 'reason', 'invoice not settled'); end if;

  for v_it in
    select * from public.invoice_items
     where invoice_id = p_invoice_id
       and line_kind in ('credit_package','premium_bundle')
       and credit_issued_at is null
     order by id
     for update
  loop
    v_external := round(coalesce(v_it.line_total,0)
      - case when coalesce(v_inv.subtotal,0) > 0
             then coalesce(v_inv.discount_total,0) * (coalesce(v_it.line_total,0) / v_inv.subtotal)
             else 0 end, 2);
    if v_external < 0 then v_external := 0; end if;

    if v_it.line_kind = 'credit_package' then
      if v_it.credit_split_allocation_id is not null then
        -- (a) New multi-customer child: issue exactly the snapshot allocation.
        v_res := public.issue_credit_package_invoice_item(v_it.id);
        v_res := v_res || jsonb_build_object('commission',
          public.earn_credit_package_commission((v_res->>'sale_id')::uuid));

      elsif exists (select 1 from public.invoice_credit_splits s where s.invoice_item_id = v_it.id) then
        -- (b) Legacy 141 split recorded on one line: preserved unchanged.
        v_line := nullif(round(coalesce(v_it.line_total, 0), 2), 0);
        for v_s in select * from public.invoice_credit_splits
                    where invoice_item_id = v_it.id order by created_at
        loop
          v_share_ext := case when v_line is null then 0
                              else round(v_external * (v_s.amount / v_line), 2) end;
          v_res := public.issue_credit_package(v_it.credit_package_id, v_s.customer_id,
                                               v_inv.store_id, v_share_ext, p_invoice_id);
          update public.invoice_credit_splits set issued_lot_id = (v_res->>'credit_lot_id')::uuid
           where id = v_s.id;
          v_res := v_res || jsonb_build_object('commission',
            public.earn_credit_package_commission((v_res->>'sale_id')::uuid));
        end loop;

      else
        -- (c) Ordinary single-customer package: unchanged full-package issuance.
        v_res := public.issue_credit_package(v_it.credit_package_id, v_inv.customer_id,
                                             v_inv.store_id, v_external, p_invoice_id);
        v_res := v_res || jsonb_build_object('commission',
          public.earn_credit_package_commission((v_res->>'sale_id')::uuid));
      end if;

    else
      -- premium_bundle: unchanged.
      v_res := public.sell_premium_bundle(
        v_it.premium_bundle_id, v_inv.customer_id, v_inv.store_id,
        jsonb_build_array(jsonb_build_object('method','invoice','amount', v_external)),
        coalesce(v_it.bundle_voucher_selection, '[]'::jsonb),
        0, coalesce(v_it.foc_amount,0), p_invoice_id,
        coalesce(v_it.foc_amount,0) >= coalesce(v_it.unit_price,0));
    end if;

    update public.invoice_items set credit_issued_at = now() where id = v_it.id;
    v_out := v_out || jsonb_build_object('line_kind', v_it.line_kind, 'external', v_external, 'result', v_res);
  end loop;

  return jsonb_build_object('issued', v_out);
end $function$;

-- =====================================================================
-- 7. Atomic creation RPC. All-or-nothing: one transaction, zero invoices on
--    any failure. The backend recalculates every monetary benefit from the
--    package + payment weights; it accepts only customers, payments and the
--    staff-confirmed voucher counts from the client.
-- =====================================================================
create or replace function public.create_split_credit_package_invoices(
  p_store_id uuid,
  p_credit_package_id uuid,
  p_allocations jsonb,
  p_service_staff uuid[] default null,
  p_affiliate_id uuid default null,
  p_notes text default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare
  pk public.credit_packages%rowtype;
  v_n integer; i integer; v_alloc jsonb;
  v_cust uuid[]; v_pay numeric[]; v_vou integer[];
  v_sum_pay numeric := 0; v_sum_vou integer := 0;
  v_bonus_total numeric; v_reward_total integer; v_units_full integer; v_qual numeric;
  v_rule public.therapy_package_rules;
  v_paid_parts numeric[]; v_bonus_parts numeric[];
  v_group uuid; v_inv uuid; v_item uuid; v_alloc_id uuid; v_no text;
  v_ss uuid; v_ss_role user_role; v_pct numeric;
  v_invoices jsonb := '[]'::jsonb;
begin
  -- ---- store access ----
  if not public.user_has_store_access(p_store_id) then
    raise exception 'You do not have access to this store'; end if;

  -- ---- package validity + availability ----
  select * into pk from public.credit_packages
    where id = p_credit_package_id and deleted_at is null and is_active = true;
  if not found then raise exception 'Credit package not found, inactive or deleted'; end if;
  if exists (select 1 from public.credit_package_stores s where s.package_id = pk.id)
     and not exists (select 1 from public.credit_package_stores s
                      where s.package_id = pk.id and s.store_id = p_store_id) then
    raise exception 'This Credit Package is not available at the selected store';
  end if;

  -- ---- parse allocations ----
  if p_allocations is null or jsonb_typeof(p_allocations) <> 'array' then
    raise exception 'Allocations are required'; end if;
  v_n := jsonb_array_length(p_allocations);
  if v_n < 2 then raise exception 'Splitting requires at least 2 customers'; end if;

  v_cust := array_fill(null::uuid, array[v_n]);
  v_pay  := array_fill(0::numeric, array[v_n]);
  v_vou  := array_fill(0, array[v_n]);

  for i in 0 .. v_n - 1 loop
    v_alloc := p_allocations -> i;
    v_cust[i+1] := (v_alloc->>'customer_id')::uuid;
    v_pay[i+1]  := round((v_alloc->>'payment_amount')::numeric, 2);
    v_vou[i+1]  := coalesce((v_alloc->>'reward_voucher_qty')::integer, 0);

    if v_cust[i+1] is null then raise exception 'Every allocation needs a customer'; end if;
    if not exists (select 1 from public.customers c
                    where c.id = v_cust[i+1] and c.is_active = true and c.deleted_at is null) then
      raise exception 'A selected customer was not found or is inactive'; end if;
    if v_pay[i+1] is null or v_pay[i+1] <= 0 then
      raise exception 'Every customer''s payment must be greater than zero'; end if;
    if v_vou[i+1] < 0 then raise exception 'Voucher allocations cannot be negative'; end if;

    v_sum_pay := v_sum_pay + v_pay[i+1];
    v_sum_vou := v_sum_vou + v_vou[i+1];
  end loop;

  -- no duplicate customers
  if (select count(distinct c) from unnest(v_cust) c) <> v_n then
    raise exception 'The same customer cannot appear twice in a split'; end if;

  -- payments must total the package price exactly
  if round(v_sum_pay, 2) <> round(pk.customer_price, 2) then
    raise exception 'Allocated payments total S$% but the package price is S$%. They must match exactly.',
      to_char(v_sum_pay, 'FM999999990.00'), to_char(pk.customer_price, 'FM999999990.00');
  end if;

  -- ---- full package benefit totals ----
  v_bonus_total := public.credit_package_bonus_amount(pk.id);
  v_rule := public.legacy_lowest_rule(p_store_id, public.sg_today());
  v_qual := coalesce(pk.reward_qualifying_amount, v_rule.qualifying_amount, 994);
  v_units_full := case when not coalesce(pk.grants_reward,false) then 0
                       when v_qual > 0 then floor(coalesce(pk.customer_price,0) / v_qual)::integer
                       else 0 end;
  v_reward_total := v_units_full * 10;   -- each reward unit = 10 vouchers

  -- voucher totals must reconcile with the package's reward exactly
  if v_reward_total = 0 then
    if v_sum_vou <> 0 then
      raise exception 'This package grants no reward vouchers, so every allocation must be 0'; end if;
  else
    if v_sum_vou <> v_reward_total then
      raise exception 'Reward vouchers allocated (%) must equal the package total (%)',
        v_sum_vou, v_reward_total; end if;
  end if;

  -- ---- authoritative monetary allocation (cent-exact) ----
  v_paid_parts  := public.split_amount_by_weights(pk.paid_credit_amount, v_pay);
  v_bonus_parts := public.split_amount_by_weights(v_bonus_total, v_pay);

  -- defensive: parts must reconcile to the full totals
  if round((select sum(x) from unnest(v_paid_parts) x),2) <> round(pk.paid_credit_amount,2) then
    raise exception 'internal: paid-credit allocation does not reconcile'; end if;
  if round((select sum(x) from unnest(v_bonus_parts) x),2) <> round(v_bonus_total,2) then
    raise exception 'internal: bonus allocation does not reconcile'; end if;

  -- ---- validate service staff (same rule as create_invoice) ----
  if p_service_staff is not null then
    foreach v_ss in array p_service_staff loop
      select role into v_ss_role from public.profiles
        where id = v_ss and is_active = true and deleted_at is null;
      if v_ss_role is null then raise exception 'A selected service staff was not found or is inactive'; end if;
      if v_ss_role not in ('owner','manager','staff') then
        raise exception 'Service staff must be Owner, Manager, or Staff'; end if;
    end loop;
  end if;

  -- ---- create the split group ----
  insert into public.credit_package_split_groups (
    store_id, credit_package_id, package_name_snapshot, package_price_snapshot,
    paid_credit_total_snapshot, bonus_credit_total_snapshot, reward_voucher_total_snapshot,
    customer_count, created_by)
  values (p_store_id, pk.id, pk.name, pk.customer_price,
    pk.paid_credit_amount, v_bonus_total, v_reward_total, v_n, auth.uid())
  returning id into v_group;

  perform public.write_audit_ex('credit_package_split_groups', v_group, 'split_group_created', null,
    jsonb_build_object('package', pk.name, 'price', pk.customer_price,
      'paid_credit_total', pk.paid_credit_amount, 'bonus_total', v_bonus_total,
      'reward_voucher_total', v_reward_total, 'customers', v_n), 'credit', null, p_store_id);

  -- ---- one normal invoice per customer ----
  for i in 1 .. v_n loop
    v_pct := round(v_pay[i] / nullif(pk.customer_price,0) * 100, 4);
    v_no := public.next_invoice_no();

    insert into public.invoices (
      invoice_no, store_id, customer_id, affiliate_id, created_by, status,
      subtotal, discount_total, manual_discount, total_amount, paid_amount, notes)
    values (v_no, p_store_id, v_cust[i], p_affiliate_id, auth.uid(), 'unpaid',
      v_pay[i], 0, 0, v_pay[i], 0, p_notes)
    returning id into v_inv;

    insert into public.invoice_items (
      invoice_id, line_kind, credit_package_id, quantity, unit_price, line_total,
      credit_paid_snapshot, credit_bonus_snapshot, credit_voucher_qty_snapshot,
      plan_name_snapshot, credit_split_group_id, credit_split_ratio,
      credit_package_full_price_snapshot)
    values (v_inv, 'credit_package', pk.id, 1, v_pay[i], v_pay[i],
      v_paid_parts[i], v_bonus_parts[i], v_vou[i],
      pk.name, v_group, v_pct, pk.customer_price)
    returning id into v_item;

    -- Served by — same staff on every child invoice.
    if p_service_staff is not null then
      foreach v_ss in array p_service_staff loop
        insert into public.invoice_service_staff (invoice_id, staff_id)
        values (v_inv, v_ss) on conflict (invoice_id, staff_id) do nothing;
      end loop;
    end if;

    insert into public.credit_package_split_allocations (
      split_group_id, invoice_id, invoice_item_id, customer_id, payment_amount,
      allocation_percent, paid_credit_amount, bonus_credit_amount, reward_voucher_qty)
    values (v_group, v_inv, v_item, v_cust[i], v_pay[i], v_pct,
      v_paid_parts[i], v_bonus_parts[i], v_vou[i])
    returning id into v_alloc_id;

    update public.invoice_items set credit_split_allocation_id = v_alloc_id where id = v_item;

    perform public.write_audit_ex('credit_package_split_allocations', v_alloc_id, 'split_allocation_created', null,
      jsonb_build_object('invoice_no', v_no, 'customer', v_cust[i], 'payment', v_pay[i],
        'percent', v_pct, 'paid_credit', v_paid_parts[i], 'bonus', v_bonus_parts[i],
        'reward_vouchers', v_vou[i], 'split_group', v_group), 'credit', null, p_store_id);

    v_invoices := v_invoices || jsonb_build_object(
      'invoice_id', v_inv, 'invoice_no', v_no, 'customer_id', v_cust[i],
      'payment_amount', v_pay[i], 'paid_credit', v_paid_parts[i],
      'bonus_credit', v_bonus_parts[i], 'reward_vouchers', v_vou[i]);
  end loop;

  return jsonb_build_object(
    'split_group_id', v_group, 'package_name', pk.name, 'package_price', pk.customer_price,
    'paid_credit_total', pk.paid_credit_amount, 'bonus_credit_total', v_bonus_total,
    'reward_voucher_total', v_reward_total, 'invoices', v_invoices);
end $function$;

-- =====================================================================
-- 8. Read-only reconciliation for a split group.
-- =====================================================================
create or replace function public.credit_package_split_group_detail(p_split_group_id uuid)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $function$
declare v_g public.credit_package_split_groups%rowtype; v_children jsonb;
begin
  select * into v_g from public.credit_package_split_groups where id = p_split_group_id;
  if not found then return jsonb_build_object('found', false); end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'invoice_id', a.invoice_id, 'invoice_no', i.invoice_no,
           'customer_id', a.customer_id, 'customer_name', c.full_name,
           'invoice_status', i.status, 'payment_amount', a.payment_amount,
           'allocation_percent', a.allocation_percent,
           'paid_credit', a.paid_credit_amount, 'bonus_credit', a.bonus_credit_amount,
           'reward_vouchers', a.reward_voucher_qty,
           'credit_issued', (ii.credit_issued_at is not null))
           order by i.invoice_no), '[]'::jsonb)
    into v_children
    from public.credit_package_split_allocations a
    join public.invoices i on i.id = a.invoice_id
    left join public.customers c on c.id = a.customer_id
    left join public.invoice_items ii on ii.id = a.invoice_item_id
   where a.split_group_id = p_split_group_id;

  return jsonb_build_object(
    'found', true, 'split_group_id', v_g.id, 'package_name', v_g.package_name_snapshot,
    'store_id', v_g.store_id, 'customer_count', v_g.customer_count,
    'totals', jsonb_build_object(
      'package_price', v_g.package_price_snapshot,
      'paid_credit', v_g.paid_credit_total_snapshot,
      'bonus_credit', v_g.bonus_credit_total_snapshot,
      'reward_vouchers', v_g.reward_voucher_total_snapshot),
    'allocated', jsonb_build_object(
      'payment', (select coalesce(sum(payment_amount),0) from public.credit_package_split_allocations where split_group_id = p_split_group_id),
      'paid_credit', (select coalesce(sum(paid_credit_amount),0) from public.credit_package_split_allocations where split_group_id = p_split_group_id),
      'bonus_credit', (select coalesce(sum(bonus_credit_amount),0) from public.credit_package_split_allocations where split_group_id = p_split_group_id),
      'reward_vouchers', (select coalesce(sum(reward_voucher_qty),0) from public.credit_package_split_allocations where split_group_id = p_split_group_id)),
    'invoices', v_children);
end $function$;

-- =====================================================================
-- 8b. Authoritative benefit preview so the UI shows exactly what the RPC will
--     enforce (avoids client/server divergence on the reward voucher total).
-- =====================================================================
create or replace function public.credit_package_benefit_preview(p_package_id uuid, p_store_id uuid)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $function$
declare pk public.credit_packages%rowtype; v_rule public.therapy_package_rules;
        v_qual numeric; v_units integer;
begin
  select * into pk from public.credit_packages where id = p_package_id and deleted_at is null;
  if not found then return jsonb_build_object('found', false); end if;
  v_rule := public.legacy_lowest_rule(p_store_id, public.sg_today());
  v_qual := coalesce(pk.reward_qualifying_amount, v_rule.qualifying_amount, 994);
  v_units := case when not coalesce(pk.grants_reward,false) then 0
                  when v_qual > 0 then floor(coalesce(pk.customer_price,0) / v_qual)::integer
                  else 0 end;
  return jsonb_build_object(
    'found', true, 'package_name', pk.name,
    'customer_price', pk.customer_price,
    'paid_credit_total', pk.paid_credit_amount,
    'bonus_total', public.credit_package_bonus_amount(pk.id),
    'grants_reward', coalesce(pk.grants_reward,false),
    'reward_voucher_total', v_units * 10);
end $function$;

-- =====================================================================
-- 9. Assertions — the split path and snapshot issuer must be live (req 56).
-- =====================================================================
do $$
declare v_src text;
begin
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
                  where n.nspname='public' and p.proname='create_split_credit_package_invoices') then
    raise exception 'create_split_credit_package_invoices is missing'; end if;
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
                  where n.nspname='public' and p.proname='issue_credit_package_invoice_item') then
    raise exception 'issue_credit_package_invoice_item is missing'; end if;

  select prosrc into v_src from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='issue_credit_lines_for_invoice';
  if v_src is null or position('credit_split_allocation_id' in v_src) = 0 then
    raise exception 'issue_credit_lines_for_invoice does not route split children to the snapshot issuer'; end if;
  if position('issue_credit_package_invoice_item' in v_src) = 0 then
    raise exception 'issue_credit_lines_for_invoice is not snapshot-aware'; end if;

  raise notice 'Confirmed: multi-customer Credit Package split path + snapshot issuance are active.';
end $$;

notify pgrst, 'reload schema';
