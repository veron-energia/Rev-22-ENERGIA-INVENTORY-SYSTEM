-- =====================================================================
-- ENERGIA — SPLIT ONE PREMIUM BUNDLE PURCHASE INTO SEVERAL NORMAL INVOICES
--
-- The multi-customer split (migration 153, Credit Packages) is extended to
-- Premium Bundles. One bundle is allocated between several customers at
-- creation time; each customer gets their OWN ordinary invoice carrying that
-- customer's allocated Paid Credit, Bonus Credit and reward-voucher SELECTION
-- as permanent snapshots. When a child invoice is paid, the settlement path
-- issues exactly the snapshotted allocation — never the full bundle — so no
-- customer can receive the whole bundle's benefit.
--
-- Differences from a Credit Package that this migration handles:
--   * Bonus is a fixed amount (premium_bundles.bonus_credit_amount), still
--     divided proportionally to payment.
--   * Reward vouchers are SPECIFIC catalogue vouchers chosen from the bundle's
--     allowed set (premium_bundle_vouchers), with real per-store stock, issued
--     as customer_reward_vouchers. Each child therefore carries a voucher
--     SELECTION (which vouchers, how many), not a single integer, and the
--     selections across all children must total the bundle's free_voucher_qty.
--
-- Reuses grant_customer_credit, the customer_reward_vouchers + voucher stock
-- path from sell_premium_bundle, earn_premium_bundle_commission, invoice,
-- Served-by and audit architecture, and the cent-safe split_amount_by_weights
-- helper from 153. No new wallet / payment / commission / voucher / invoice
-- systems are introduced.
--
-- Additive and idempotent. Run AFTER 153.
-- =====================================================================

set check_function_bodies = off;

-- =====================================================================
-- 1. Split-group + allocation records (audit / reconciliation linkage).
--    Parallel to the Credit Package tables; the allocation stores a per-child
--    voucher SELECTION rather than a single count.
-- =====================================================================
create table if not exists public.premium_bundle_split_groups (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id),
  premium_bundle_id uuid not null references public.premium_bundles(id),
  bundle_name_snapshot text not null,
  payment_snapshot numeric(12,2) not null,
  paid_credit_total_snapshot numeric(12,2) not null,
  bonus_credit_total_snapshot numeric(12,2) not null,
  free_voucher_total_snapshot integer not null default 0,
  customer_count integer not null,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now()
);

create table if not exists public.premium_bundle_split_allocations (
  id uuid primary key default gen_random_uuid(),
  split_group_id uuid not null references public.premium_bundle_split_groups(id) on delete cascade,
  invoice_id uuid not null references public.invoices(id),
  invoice_item_id uuid not null references public.invoice_items(id),
  customer_id uuid not null references public.customers(id),
  payment_amount numeric(12,2) not null,
  allocation_percent numeric(7,4) not null,
  paid_credit_amount numeric(12,2) not null,
  bonus_credit_amount numeric(12,2) not null,
  voucher_qty integer not null default 0,
  voucher_selection jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists idx_pbsg_bundle on public.premium_bundle_split_groups(premium_bundle_id);
create index if not exists idx_pbsg_store on public.premium_bundle_split_groups(store_id);
create index if not exists idx_pbsa_group on public.premium_bundle_split_allocations(split_group_id);
create index if not exists idx_pbsa_invoice on public.premium_bundle_split_allocations(invoice_id);
create index if not exists idx_pbsa_customer on public.premium_bundle_split_allocations(customer_id);

alter table public.premium_bundle_split_groups enable row level security;
alter table public.premium_bundle_split_allocations enable row level security;
drop policy if exists "read bundle split groups" on public.premium_bundle_split_groups;
create policy "read bundle split groups" on public.premium_bundle_split_groups for select using (auth.uid() is not null);
drop policy if exists "read bundle split allocations" on public.premium_bundle_split_allocations;
create policy "read bundle split allocations" on public.premium_bundle_split_allocations for select using (auth.uid() is not null);

-- =====================================================================
-- 2. Linkage columns on the invoice line. The per-child money reuses the
--    existing paid/bonus snapshot columns (a bundle grants Paid + Bonus
--    Credit too); the per-child voucher SELECTION reuses bundle_voucher_selection.
-- =====================================================================
alter table public.invoice_items add column if not exists bundle_split_group_id uuid references public.premium_bundle_split_groups(id);
alter table public.invoice_items add column if not exists bundle_split_allocation_id uuid references public.premium_bundle_split_allocations(id);
alter table public.invoice_items add column if not exists bundle_split_ratio numeric(7,4);
alter table public.invoice_items add column if not exists premium_bundle_full_price_snapshot numeric(12,2);
create index if not exists idx_invoice_items_bundle_split_group on public.invoice_items(bundle_split_group_id);

-- =====================================================================
-- 3. Snapshot-based bundle issuer: grants EXACTLY the invoice line's
--    allocation. Reuses grant_customer_credit and the customer_reward_vouchers
--    + voucher-stock path; never re-reads the full bundle's benefit. Records a
--    premium_bundle_sales row (so commission is earned on the child's external
--    money) and returns its sale_id.
-- =====================================================================
create or replace function public.issue_premium_bundle_invoice_item(p_invoice_item_id uuid)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare
  v_it public.invoice_items%rowtype; v_inv public.invoices%rowtype;
  b public.premium_bundles%rowtype;
  v_paid_lot uuid; v_bonus_lot uuid; v_sale uuid; v_restrict jsonb;
  v_vouchers uuid[]; v_qual numeric; v_external numeric;
  v_paid numeric; v_bonus numeric; v_sel jsonb; v_vid uuid; v_qty integer;
  v_stock integer; v_issued integer := 0; v_vq integer;
begin
  select * into v_it from public.invoice_items where id = p_invoice_item_id for update;
  if not found then raise exception 'Invoice item not found'; end if;
  if v_it.line_kind <> 'premium_bundle' then
    raise exception 'issue_premium_bundle_invoice_item is only for premium_bundle lines'; end if;
  select * into v_inv from public.invoices where id = v_it.invoice_id;

  select * into b from public.premium_bundles where id = v_it.premium_bundle_id;
  if not found then raise exception 'Premium bundle not found'; end if;

  v_paid  := coalesce(v_it.credit_paid_snapshot, 0);
  v_bonus := coalesce(v_it.credit_bonus_snapshot, 0);
  v_vq    := coalesce(v_it.credit_voucher_qty_snapshot, 0);

  v_external := round(coalesce(v_it.line_total,0)
    - case when coalesce(v_inv.subtotal,0) > 0
           then coalesce(v_inv.discount_total,0) * (coalesce(v_it.line_total,0) / v_inv.subtotal)
           else 0 end, 2);
  if v_external < 0 then v_external := 0; end if;

  -- Same broad usability restriction the full-bundle issuer applies.
  v_restrict := jsonb_build_object(
    'allowed_purposes', jsonb_build_array('product','voucher','promotion','therapy','rental'),
    'allowed_voucher_ids', '[]'::jsonb, 'source', 'premium_bundle');

  if v_paid > 0 then
    v_paid_lot := public.grant_customer_credit(v_inv.customer_id, 'paid', v_paid,
      'premium_bundle', b.id, v_inv.store_id, public.sg_today(), null,
      'Premium bundle: ' || b.name, null, null, auth.uid(), v_restrict);
  end if;
  if v_bonus > 0 then
    v_bonus_lot := public.grant_customer_credit(v_inv.customer_id, 'bonus', v_bonus,
      'premium_bundle', b.id, v_inv.store_id, public.sg_today(), null,
      'Premium bundle bonus: ' || b.name, null, null, auth.uid(), v_restrict);
  end if;

  v_qual := coalesce(b.reward_qualifying_amount, 994);
  select coalesce(array_agg(voucher_id),'{}') into v_vouchers
    from public.premium_bundle_vouchers where bundle_id = b.id;

  insert into public.premium_bundle_sales (
    bundle_id, customer_id, store_id, invoice_id, bundle_name_snapshot,
    payment_snapshot, paid_credit_snapshot, bonus_credit_snapshot, voucher_qty_snapshot,
    classification_snapshot, tier1_rate_snapshot, tier2_rate_snapshot, staff_rate_snapshot,
    reward_qualifying_snapshot, forfeited_remainder, eligible_voucher_ids,
    external_paid, paid_credit_lot_id, bonus_credit_lot_id, created_by)
  values (b.id, v_inv.customer_id, v_inv.store_id, v_inv.id,
    coalesce(v_it.plan_name_snapshot, b.name),
    coalesce(v_it.unit_price, v_paid), v_paid, v_bonus, v_vq,
    b.commission_classification, b.tier1_rate, b.tier2_rate, b.staff_commission_rate,
    v_qual, 0, v_vouchers, coalesce(v_external,0), v_paid_lot, v_bonus_lot, auth.uid())
  returning id into v_sale;

  -- Issue exactly this child's voucher SELECTION, deducting stock like the
  -- full-bundle issuer. A shortage blocks this child's payment (its own
  -- transaction rolls back) and never affects the other customers.
  for v_sel in select * from jsonb_array_elements(coalesce(v_it.bundle_voucher_selection,'[]'::jsonb)) loop
    v_vid := (v_sel->>'voucher_id')::uuid;
    v_qty := coalesce((v_sel->>'quantity')::integer, 0);
    if v_qty <= 0 then continue; end if;
    if exists (select 1 from public.vouchers where id = v_vid and qty_type <> 'unlimited') then
      select current_qty into v_stock from public.voucher_store_stock
       where voucher_id = v_vid and store_id = v_inv.store_id for update;
      if coalesce(v_stock,0) < v_qty then
        raise exception 'Payment blocked — stock of "%" ran out',
          (select name from public.vouchers where id = v_vid); end if;
      update public.voucher_store_stock set current_qty = current_qty - v_qty, updated_at = now()
       where voucher_id = v_vid and store_id = v_inv.store_id;
    end if;
    insert into public.customer_reward_vouchers
      (customer_id, voucher_id, entitlement_id, store_id, quantity, issued_by, notes, source_type, source_id)
    values (v_inv.customer_id, v_vid, null, v_inv.store_id, v_qty, auth.uid(),
      'Premium bundle reward (split) — never expires, not transferable', 'premium_bundle', v_sale);
    v_issued := v_issued + v_qty;
  end loop;

  update public.premium_bundle_sales set vouchers_issued = v_issued where id = v_sale;

  perform public.write_audit_ex('premium_bundle_sales', v_sale, 'premium_bundle_sold_split', null,
    jsonb_build_object('bundle', b.name, 'paid_credit', v_paid, 'bonus_credit', v_bonus,
      'vouchers', v_issued, 'external_paid', v_external,
      'split_allocation', v_it.bundle_split_allocation_id), 'credit', null, v_inv.store_id);

  return jsonb_build_object('sale_id', v_sale, 'paid_credit_lot_id', v_paid_lot,
    'bonus_credit_lot_id', v_bonus_lot, 'paid_credit', v_paid, 'bonus_credit', v_bonus,
    'vouchers_issued', v_issued, 'commission', public.earn_premium_bundle_commission(v_sale),
    'snapshot_based', true);
end $function$;

-- =====================================================================
-- 4. Settlement router — add the bundle-split branch. A premium_bundle line
--    that is a split child (bundle_split_allocation_id set) is issued by the
--    snapshot issuer; an ordinary bundle line still goes through
--    sell_premium_bundle unchanged. Credit-package handling (incl. its own
--    split + legacy branches) is preserved exactly as migration 153 left it.
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
        -- New multi-customer child: issue exactly the snapshot allocation.
        v_res := public.issue_credit_package_invoice_item(v_it.id);
        v_res := v_res || jsonb_build_object('commission',
          public.earn_credit_package_commission((v_res->>'sale_id')::uuid));

      elsif exists (select 1 from public.invoice_credit_splits s where s.invoice_item_id = v_it.id) then
        -- Legacy 141 split recorded on one line: preserved unchanged.
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
        -- Ordinary single-customer package: unchanged full-package issuance.
        v_res := public.issue_credit_package(v_it.credit_package_id, v_inv.customer_id,
                                             v_inv.store_id, v_external, p_invoice_id);
        v_res := v_res || jsonb_build_object('commission',
          public.earn_credit_package_commission((v_res->>'sale_id')::uuid));
      end if;

    else
      -- premium_bundle
      if v_it.bundle_split_allocation_id is not null then
        -- New multi-customer child: issue exactly the snapshot allocation.
        v_res := public.issue_premium_bundle_invoice_item(v_it.id);
      else
        -- Ordinary single-customer bundle: unchanged full-bundle issuance.
        v_res := public.sell_premium_bundle(
          v_it.premium_bundle_id, v_inv.customer_id, v_inv.store_id,
          jsonb_build_array(jsonb_build_object('method','invoice','amount', v_external)),
          coalesce(v_it.bundle_voucher_selection, '[]'::jsonb),
          0, coalesce(v_it.foc_amount,0), p_invoice_id,
          coalesce(v_it.foc_amount,0) >= coalesce(v_it.unit_price,0));
      end if;
    end if;

    update public.invoice_items set credit_issued_at = now() where id = v_it.id;
    v_out := v_out || jsonb_build_object('line_kind', v_it.line_kind, 'external', v_external, 'result', v_res);
  end loop;

  return jsonb_build_object('issued', v_out);
end $function$;

-- =====================================================================
-- 5. Atomic creation RPC. All-or-nothing: one transaction, zero invoices on
--    any failure. The backend recalculates Paid/Bonus from the payment weights
--    and accepts only customers, payments and the per-child voucher selections.
-- =====================================================================
create or replace function public.create_split_premium_bundle_invoices(
  p_store_id uuid,
  p_premium_bundle_id uuid,
  p_allocations jsonb,
  p_service_staff uuid[] default null,
  p_affiliate_id uuid default null,
  p_notes text default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare
  b public.premium_bundles%rowtype;
  v_n integer; i integer; v_alloc jsonb; v_sel jsonb; v_sub jsonb; v_vid uuid; v_qty integer;
  v_cust uuid[]; v_pay numeric[]; v_vq integer[]; v_seljson jsonb[];
  v_sum_pay numeric := 0; v_sum_vou integer := 0;
  v_paid_parts numeric[]; v_bonus_parts numeric[];
  v_group uuid; v_inv uuid; v_item uuid; v_alloc_id uuid; v_no text;
  v_ss uuid; v_ss_role user_role; v_pct numeric; v_childvq integer;
  v_invoices jsonb := '[]'::jsonb;
begin
  if not public.user_has_store_access(p_store_id) then
    raise exception 'You do not have access to this store'; end if;

  select * into b from public.premium_bundles
    where id = p_premium_bundle_id and deleted_at is null and is_active = true;
  if not found then raise exception 'Premium bundle not found, inactive or deleted'; end if;
  if not exists (select 1 from public.premium_bundles_for_store(p_store_id) x where x.id = b.id) then
    raise exception 'This Premium Bundle is not available at the selected store'; end if;

  if p_allocations is null or jsonb_typeof(p_allocations) <> 'array' then
    raise exception 'Allocations are required'; end if;
  v_n := jsonb_array_length(p_allocations);
  if v_n < 2 then raise exception 'Splitting requires at least 2 customers'; end if;

  v_cust := array_fill(null::uuid, array[v_n]);
  v_pay  := array_fill(0::numeric, array[v_n]);
  v_vq   := array_fill(0, array[v_n]);
  v_seljson := array_fill('[]'::jsonb, array[v_n]);

  for i in 0 .. v_n - 1 loop
    v_alloc := p_allocations -> i;
    v_cust[i+1] := (v_alloc->>'customer_id')::uuid;
    v_pay[i+1]  := round((v_alloc->>'payment_amount')::numeric, 2);
    v_sel := coalesce(v_alloc->'voucher_selection', '[]'::jsonb);
    if jsonb_typeof(v_sel) <> 'array' then raise exception 'voucher_selection must be an array'; end if;

    if v_cust[i+1] is null then raise exception 'Every allocation needs a customer'; end if;
    if not exists (select 1 from public.customers c
                    where c.id = v_cust[i+1] and c.is_active = true and c.deleted_at is null) then
      raise exception 'A selected customer was not found or is inactive'; end if;
    if v_pay[i+1] is null or v_pay[i+1] <= 0 then
      raise exception 'Every customer''s payment must be greater than zero'; end if;

    -- validate + total this child's voucher selection
    v_childvq := 0;
    for v_sub in select * from jsonb_array_elements(v_sel) loop
      v_vid := (v_sub->>'voucher_id')::uuid;
      v_qty := coalesce((v_sub->>'quantity')::integer, 0);
      if v_qty < 0 then raise exception 'Voucher quantities cannot be negative'; end if;
      if v_qty = 0 then continue; end if;
      if v_vid is null or not exists (select 1 from public.premium_bundle_vouchers
                                       where bundle_id = b.id and voucher_id = v_vid) then
        raise exception 'A selected voucher is not an eligible choice for this bundle'; end if;
      v_childvq := v_childvq + v_qty;
    end loop;
    v_vq[i+1] := v_childvq;
    v_seljson[i+1] := v_sel;

    v_sum_pay := v_sum_pay + v_pay[i+1];
    v_sum_vou := v_sum_vou + v_childvq;
  end loop;

  if (select count(distinct c) from unnest(v_cust) c) <> v_n then
    raise exception 'The same customer cannot appear twice in a split'; end if;

  if round(v_sum_pay, 2) <> round(b.customer_payment_amount, 2) then
    raise exception 'Allocated payments total S$% but the bundle price is S$%. They must match exactly.',
      to_char(v_sum_pay, 'FM999999990.00'), to_char(b.customer_payment_amount, 'FM999999990.00');
  end if;

  -- vouchers across all children must total the bundle's free_voucher_qty
  if v_sum_vou <> coalesce(b.free_voucher_qty, 0) then
    raise exception 'Reward vouchers allocated (%) must equal the bundle total (%)',
      v_sum_vou, coalesce(b.free_voucher_qty, 0); end if;

  v_paid_parts  := public.split_amount_by_weights(b.paid_credit_amount, v_pay);
  v_bonus_parts := public.split_amount_by_weights(b.bonus_credit_amount, v_pay);
  if round((select sum(x) from unnest(v_paid_parts) x),2) <> round(b.paid_credit_amount,2) then
    raise exception 'internal: paid-credit allocation does not reconcile'; end if;
  if round((select sum(x) from unnest(v_bonus_parts) x),2) <> round(b.bonus_credit_amount,2) then
    raise exception 'internal: bonus allocation does not reconcile'; end if;

  if p_service_staff is not null then
    foreach v_ss in array p_service_staff loop
      select role into v_ss_role from public.profiles
        where id = v_ss and is_active = true and deleted_at is null;
      if v_ss_role is null then raise exception 'A selected service staff was not found or is inactive'; end if;
      if v_ss_role not in ('owner','manager','staff') then
        raise exception 'Service staff must be Owner, Manager, or Staff'; end if;
    end loop;
  end if;

  insert into public.premium_bundle_split_groups (
    store_id, premium_bundle_id, bundle_name_snapshot, payment_snapshot,
    paid_credit_total_snapshot, bonus_credit_total_snapshot, free_voucher_total_snapshot,
    customer_count, created_by)
  values (p_store_id, b.id, b.name, b.customer_payment_amount,
    b.paid_credit_amount, b.bonus_credit_amount, coalesce(b.free_voucher_qty,0), v_n, auth.uid())
  returning id into v_group;

  perform public.write_audit_ex('premium_bundle_split_groups', v_group, 'bundle_split_group_created', null,
    jsonb_build_object('bundle', b.name, 'price', b.customer_payment_amount,
      'paid_credit_total', b.paid_credit_amount, 'bonus_total', b.bonus_credit_amount,
      'free_voucher_total', coalesce(b.free_voucher_qty,0), 'customers', v_n), 'credit', null, p_store_id);

  for i in 1 .. v_n loop
    v_pct := round(v_pay[i] / nullif(b.customer_payment_amount,0) * 100, 4);
    v_no := public.next_invoice_no();

    insert into public.invoices (
      invoice_no, store_id, customer_id, affiliate_id, created_by, status,
      subtotal, discount_total, manual_discount, total_amount, paid_amount, notes)
    values (v_no, p_store_id, v_cust[i], p_affiliate_id, auth.uid(), 'unpaid',
      v_pay[i], 0, 0, v_pay[i], 0, p_notes)
    returning id into v_inv;

    insert into public.invoice_items (
      invoice_id, line_kind, premium_bundle_id, quantity, unit_price, line_total,
      credit_paid_snapshot, credit_bonus_snapshot, credit_voucher_qty_snapshot,
      bundle_voucher_selection, plan_name_snapshot, bundle_split_group_id, bundle_split_ratio,
      premium_bundle_full_price_snapshot)
    values (v_inv, 'premium_bundle', b.id, 1, v_pay[i], v_pay[i],
      v_paid_parts[i], v_bonus_parts[i], v_vq[i],
      v_seljson[i], b.name, v_group, v_pct, b.customer_payment_amount)
    returning id into v_item;

    if p_service_staff is not null then
      foreach v_ss in array p_service_staff loop
        insert into public.invoice_service_staff (invoice_id, staff_id)
        values (v_inv, v_ss) on conflict (invoice_id, staff_id) do nothing;
      end loop;
    end if;

    insert into public.premium_bundle_split_allocations (
      split_group_id, invoice_id, invoice_item_id, customer_id, payment_amount,
      allocation_percent, paid_credit_amount, bonus_credit_amount, voucher_qty, voucher_selection)
    values (v_group, v_inv, v_item, v_cust[i], v_pay[i], v_pct,
      v_paid_parts[i], v_bonus_parts[i], v_vq[i], v_seljson[i])
    returning id into v_alloc_id;

    update public.invoice_items set bundle_split_allocation_id = v_alloc_id where id = v_item;

    perform public.write_audit_ex('premium_bundle_split_allocations', v_alloc_id, 'bundle_split_allocation_created', null,
      jsonb_build_object('invoice_no', v_no, 'customer', v_cust[i], 'payment', v_pay[i],
        'percent', v_pct, 'paid_credit', v_paid_parts[i], 'bonus', v_bonus_parts[i],
        'vouchers', v_vq[i], 'selection', v_seljson[i], 'split_group', v_group), 'credit', null, p_store_id);

    v_invoices := v_invoices || jsonb_build_object(
      'invoice_id', v_inv, 'invoice_no', v_no, 'customer_id', v_cust[i],
      'payment_amount', v_pay[i], 'paid_credit', v_paid_parts[i],
      'bonus_credit', v_bonus_parts[i], 'reward_vouchers', v_vq[i]);
  end loop;

  return jsonb_build_object(
    'split_group_id', v_group, 'bundle_name', b.name, 'bundle_price', b.customer_payment_amount,
    'paid_credit_total', b.paid_credit_amount, 'bonus_credit_total', b.bonus_credit_amount,
    'reward_voucher_total', coalesce(b.free_voucher_qty,0), 'invoices', v_invoices);
end $function$;

-- =====================================================================
-- 6. Read-only reconciliation for a bundle split group.
-- =====================================================================
create or replace function public.premium_bundle_split_group_detail(p_split_group_id uuid)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $function$
declare v_g public.premium_bundle_split_groups%rowtype; v_children jsonb;
begin
  select * into v_g from public.premium_bundle_split_groups where id = p_split_group_id;
  if not found then return jsonb_build_object('found', false); end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'invoice_id', a.invoice_id, 'invoice_no', i.invoice_no,
           'customer_id', a.customer_id, 'customer_name', c.full_name,
           'invoice_status', i.status, 'payment_amount', a.payment_amount,
           'allocation_percent', a.allocation_percent,
           'paid_credit', a.paid_credit_amount, 'bonus_credit', a.bonus_credit_amount,
           'reward_vouchers', a.voucher_qty, 'voucher_selection', a.voucher_selection,
           'credit_issued', (ii.credit_issued_at is not null))
           order by i.invoice_no), '[]'::jsonb)
    into v_children
    from public.premium_bundle_split_allocations a
    join public.invoices i on i.id = a.invoice_id
    left join public.customers c on c.id = a.customer_id
    left join public.invoice_items ii on ii.id = a.invoice_item_id
   where a.split_group_id = p_split_group_id;

  return jsonb_build_object(
    'found', true, 'split_group_id', v_g.id, 'bundle_name', v_g.bundle_name_snapshot,
    'store_id', v_g.store_id, 'customer_count', v_g.customer_count,
    'totals', jsonb_build_object(
      'bundle_price', v_g.payment_snapshot,
      'paid_credit', v_g.paid_credit_total_snapshot,
      'bonus_credit', v_g.bonus_credit_total_snapshot,
      'reward_vouchers', v_g.free_voucher_total_snapshot),
    'allocated', jsonb_build_object(
      'payment', (select coalesce(sum(payment_amount),0) from public.premium_bundle_split_allocations where split_group_id = p_split_group_id),
      'paid_credit', (select coalesce(sum(paid_credit_amount),0) from public.premium_bundle_split_allocations where split_group_id = p_split_group_id),
      'bonus_credit', (select coalesce(sum(bonus_credit_amount),0) from public.premium_bundle_split_allocations where split_group_id = p_split_group_id),
      'reward_vouchers', (select coalesce(sum(voucher_qty),0) from public.premium_bundle_split_allocations where split_group_id = p_split_group_id)),
    'invoices', v_children);
end $function$;

-- =====================================================================
-- 7. Authoritative benefit preview (mirrors 153's, incl. the allowed voucher
--    set + per-store stock so the UI can render per-child voucher pickers).
-- =====================================================================
create or replace function public.premium_bundle_benefit_preview(p_bundle_id uuid, p_store_id uuid)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $function$
declare b public.premium_bundles%rowtype; v_vouchers jsonb;
begin
  select * into b from public.premium_bundles where id = p_bundle_id and deleted_at is null;
  if not found then return jsonb_build_object('found', false); end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'voucher_id', v.id, 'name', v.name,
           'unlimited', (v.qty_type = 'unlimited'),
           'stock', coalesce(vs.current_qty, 0)) order by v.name), '[]'::jsonb)
    into v_vouchers
    from public.premium_bundle_vouchers pbv
    join public.vouchers v on v.id = pbv.voucher_id
    left join public.voucher_store_stock vs on vs.voucher_id = v.id and vs.store_id = p_store_id
   where pbv.bundle_id = b.id;

  return jsonb_build_object(
    'found', true, 'bundle_name', b.name,
    'customer_price', b.customer_payment_amount,
    'paid_credit_total', b.paid_credit_amount,
    'bonus_total', b.bonus_credit_amount,
    'free_voucher_total', coalesce(b.free_voucher_qty,0),
    'allowed_vouchers', v_vouchers);
end $function$;

-- =====================================================================
-- 8. Assertions — the bundle split path + snapshot issuer must be live.
-- =====================================================================
do $$
declare v_src text;
begin
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
                  where n.nspname='public' and p.proname='create_split_premium_bundle_invoices') then
    raise exception 'create_split_premium_bundle_invoices is missing'; end if;
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
                  where n.nspname='public' and p.proname='issue_premium_bundle_invoice_item') then
    raise exception 'issue_premium_bundle_invoice_item is missing'; end if;

  select prosrc into v_src from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='issue_credit_lines_for_invoice';
  if v_src is null or position('bundle_split_allocation_id' in v_src) = 0 then
    raise exception 'issue_credit_lines_for_invoice does not route bundle split children to the snapshot issuer'; end if;
  if position('issue_premium_bundle_invoice_item' in v_src) = 0 then
    raise exception 'issue_credit_lines_for_invoice is not bundle-snapshot-aware'; end if;
  -- credit-package split path from 153 must remain intact
  if position('credit_split_allocation_id' in v_src) = 0
     or position('issue_credit_package_invoice_item' in v_src) = 0 then
    raise exception 'the Credit Package split path from 153 was lost'; end if;

  raise notice 'Confirmed: multi-customer Premium Bundle split path + snapshot issuance are active (Credit Package path preserved).';
end $$;

notify pgrst, 'reload schema';
