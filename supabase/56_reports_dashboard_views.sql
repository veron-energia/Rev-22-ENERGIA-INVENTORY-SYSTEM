-- =====================================================================
-- ENERGIA — PHASE 8: REPORTS & ROLE-SCOPED DASHBOARD (view functions)
--
-- Read-only report queries (membership, pricing, affiliate, therapy, discounts)
-- and a role-scoped dashboard summary. All SECURITY DEFINER + STABLE; no writes.
-- Exports can be layered on later — these return clean rows.
--
-- Additive + idempotent. Run AFTER 55.
-- =====================================================================

set check_function_bodies = off;

-- =====================================================================
-- 1. Membership report — one row per membership with derived status.
-- =====================================================================
create or replace function public.report_memberships()
returns table (
  membership_id uuid, membership_no text, customer_id uuid, customer_name text, phone text,
  member_id text, plan_name text, store_id uuid, store_name text,
  start_date date, expiry_date date, status text, source text,
  is_complimentary boolean, is_renewal boolean, days_left integer,
  missing_member_id boolean, missing_store boolean
) language sql stable security definer set search_path = public as $$
  select
    m.id, m.membership_no, m.customer_id, c.full_name, c.phone,
    mi.member_id, mp.name, m.store_id, s.name,
    m.start_date, m.expiry_date,
    (public.customer_membership_status(m.customer_id)->>'status'),
    m.source, coalesce(m.is_complimentary,false), coalesce(m.is_renewal,false),
    case when m.expiry_date is not null then (m.expiry_date - public.sg_today()) end,
    mi.member_id is null, m.store_id is null
  from public.customer_memberships m
  join public.customers c on c.id = m.customer_id
  left join public.member_ids mi on mi.customer_id = m.customer_id
  left join public.membership_plans mp on mp.id = m.plan_id
  left join public.stores s on s.id = m.store_id
  where m.deleted_at is null
  order by m.created_at desc;
$$;

-- =====================================================================
-- 2. Pricing report — member / non-member / override lines on paid invoices.
-- =====================================================================
create or replace function public.report_pricing()
returns table (
  invoice_id uuid, invoice_no text, paid_date date, store_id uuid, store_name text,
  customer_name text, line_kind text, item_name text, quantity integer,
  unit_price numeric, price_mode text, price_overridden boolean, override_reason text,
  member_price numeric, non_member_price numeric
) language sql stable security definer set search_path = public as $$
  select
    i.id, i.invoice_no, i.paid_at::date, i.store_id, s.name, c.full_name,
    ii.line_kind,
    coalesce(p.name, mp.name, ii.plan_name_snapshot, v.name, 'item'),
    ii.quantity, ii.unit_price, ii.price_mode,
    coalesce(ii.price_overridden,false), ii.override_reason,
    ii.member_price_snapshot, ii.non_member_price_snapshot
  from public.invoice_items ii
  join public.invoices i on i.id = ii.invoice_id
  left join public.customers c on c.id = i.customer_id
  left join public.stores s on s.id = i.store_id
  left join public.products p on p.id = ii.product_id
  left join public.membership_plans mp on mp.id = ii.membership_plan_id
  left join public.vouchers v on v.id = ii.voucher_id
  where i.status = 'paid'
  order by i.paid_at desc;
$$;

-- =====================================================================
-- 3. Affiliate report — reuses the Phase 5 directory + commission splits.
-- =====================================================================
create or replace function public.report_affiliates()
returns table (
  customer_id uuid, customer_name text, member_id text, affiliate_state text,
  block_reason text, store_name text, direct_referrals integer, downline integer,
  earned numeric, paid numeric, reversed numeric, blocked numeric,
  tier1_earned numeric, tier2_earned numeric
) language sql stable security definer set search_path = public as $$
  select
    d.customer_id, d.full_name, d.member_id, d.affiliate_state, d.block_reason,
    d.store_name, d.direct_referrals, d.downline,
    d.lifetime_earned, d.unpaid_payable,
    coalesce((select sum(commission_amount) from public.commissions cm where cm.referrer_customer_id = d.customer_id and cm.status = 'reversed'),0),
    d.blocked_commission,
    coalesce((select sum(commission_amount) from public.commissions cm where cm.referrer_customer_id = d.customer_id and cm.tier = 'tier1' and cm.status in ('earned','paid')),0),
    coalesce((select sum(commission_amount) from public.commissions cm where cm.referrer_customer_id = d.customer_id and cm.tier = 'tier2' and cm.status in ('earned','paid')),0)
  from public.affiliate_directory() d
  order by d.full_name;
$$;

-- =====================================================================
-- 4. Therapy report — purchased entitlements with package + pricing.
-- =====================================================================
create or replace function public.report_therapy()
returns table (
  entitlement_no text, customer_name text, package_name text, store_name text,
  price_snapshot numeric, price_mode text, purchase_date date,
  activation_deadline date, activation_date date, expiry_date date, status text,
  is_legacy boolean
) language sql stable security definer set search_path = public as $$
  select e.entitlement_no, c.full_name, e.package_name, s.name,
    e.price_snapshot, e.price_mode, e.purchase_date,
    e.activation_deadline, e.activation_date, e.expiry_date, e.status, false
  from public.purchased_therapy_entitlements e
  join public.customers c on c.id = e.customer_id
  left join public.stores s on s.id = e.store_id
  union all
  select le.entitlement_no, c.full_name, le.package_name, s.name,
    coalesce(le.qualified_value,0), null, null,
    le.activation_deadline, null, null, le.status, true
  from public.therapy_entitlements le
  join public.customers c on c.id = le.customer_id
  left join public.stores s on s.id = le.store_id
  order by 7 desc nulls last;
$$;

-- =====================================================================
-- 5. Consolidated discount report — one row per paid invoice with a breakdown.
-- =====================================================================
create or replace function public.report_discounts()
returns table (
  invoice_id uuid, invoice_no text, paid_date date, store_name text, staff_names text,
  customer_name text, save_earth numeric, voucher_discount numeric, promotion_discount numeric,
  line_discount numeric, manual_discount numeric, total_discount numeric
) language sql stable security definer set search_path = public as $$
  select
    i.id, i.invoice_no, i.paid_at::date, s.name,
    (select string_agg(pr.full_name, ', ') from public.invoice_service_staff iss
      join public.profiles pr on pr.id = iss.staff_id where iss.invoice_id = i.id),
    c.full_name,
    case when i.save_earth_applied then coalesce(i.save_earth_amount,0) else 0 end,
    case when i.discount_voucher_id is not null then public.voucher_discount_amount(i.discount_voucher_id, i.subtotal) else 0 end,
    coalesce((select sum(ii.line_discount) from public.invoice_items ii
      join public.promotions pm on pm.id = ii.promotion_id where ii.invoice_id = i.id), 0),
    coalesce((select sum(coalesce(ii.line_discount,0)) from public.invoice_items ii where ii.invoice_id = i.id), 0),
    coalesce(i.manual_discount,0),
    coalesce(i.discount_total,0)
  from public.invoices i
  left join public.customers c on c.id = i.customer_id
  left join public.stores s on s.id = i.store_id
  where i.status = 'paid' and coalesce(i.discount_total,0) > 0
  order by i.paid_at desc;
$$;

-- =====================================================================
-- 6. Role-scoped dashboard summary (single JSON payload).
--    Owner/Manager: full. Admin: all-store operational. Staff: own store.
--    Inventory Manager: inventory only.
-- =====================================================================
create or replace function public.dashboard_summary()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_role text := public.current_user_role(); v_today date := public.sg_today(); v_out jsonb;
begin
  -- Sales today (paid invoices).
  v_out := jsonb_build_object(
    'role', v_role,
    'today_sales', coalesce((select sum(total_amount) from public.invoices where status='paid' and paid_at::date = v_today),0),
    'today_count', coalesce((select count(*) from public.invoices where status='paid' and paid_at::date = v_today),0),
    'membership_sales', coalesce((select sum(ii.line_total) from public.invoice_items ii join public.invoices i on i.id=ii.invoice_id
       where ii.line_kind='membership' and i.status='paid' and i.paid_at::date = v_today),0),
    'member_sales', coalesce((select sum(ii.line_total) from public.invoice_items ii join public.invoices i on i.id=ii.invoice_id
       where ii.price_mode='member' and i.status='paid' and i.paid_at::date = v_today),0),
    'non_member_sales', coalesce((select sum(ii.line_total) from public.invoice_items ii join public.invoices i on i.id=ii.invoice_id
       where ii.price_mode='non_member' and i.status='paid' and i.paid_at::date = v_today),0),
    'expiring_memberships', coalesce((select count(*) from public.customer_memberships
       where deleted_at is null and status='active' and expiry_date is not null and expiry_date <= v_today + 90 and expiry_date >= v_today),0),
    'missing_member_ids', coalesce((select count(*) from public.customer_memberships m
       where m.deleted_at is null and m.status in ('active','pending_activation')
         and not exists (select 1 from public.member_ids mi where mi.customer_id = m.customer_id)),0),
    'missing_stores', coalesce((select count(*) from public.customer_memberships where deleted_at is null and store_id is null),0),
    'blocked_commission', coalesce((select sum(commission_amount) from public.commissions where status='blocked'),0),
    'therapy_awaiting', coalesce((select count(*) from public.purchased_therapy_entitlements where status='pending_activation'),0),
    'therapy_deadline_warn', coalesce((select count(*) from public.purchased_therapy_entitlements
       where status='pending_activation' and activation_deadline <= v_today + 30),0),
    'discount_today', coalesce((select sum(discount_total) from public.invoices where status='paid' and paid_at::date = v_today),0)
  );
  return v_out;
end $$;

notify pgrst, 'reload schema';

-- =====================================================================
-- 7. Customer 360 — everything the Customer page needs in one payload.
-- =====================================================================
create or replace function public.customer_overview(p_customer_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_out jsonb;
begin
  v_out := jsonb_build_object(
    'membership_status', public.customer_membership_status(p_customer_id),
    'affiliate_state', public.customer_affiliate_state(p_customer_id),
    'member_id', (select member_id from public.member_ids where customer_id = p_customer_id),
    'memberships', coalesce((select jsonb_agg(jsonb_build_object(
        'membership_no', m.membership_no, 'plan', mp.name, 'store', s.name,
        'start', m.start_date, 'expiry', m.expiry_date, 'status', m.status,
        'is_renewal', m.is_renewal, 'is_complimentary', m.is_complimentary,
        'cancelled_at', m.cancelled_at, 'cancel_reason', m.cancel_reason) order by m.created_at desc)
      from public.customer_memberships m
      left join public.membership_plans mp on mp.id = m.plan_id
      left join public.stores s on s.id = m.store_id
      where m.customer_id = p_customer_id and m.deleted_at is null), '[]'::jsonb),
    'refunds', coalesce((select jsonb_agg(jsonb_build_object(
        'invoice', i.invoice_no, 'amount', r.amount, 'kind', r.kind, 'reason', r.reason, 'date', r.created_at) order by r.created_at desc)
      from public.invoice_refunds r join public.invoices i on i.id = r.invoice_id
      where i.customer_id = p_customer_id), '[]'::jsonb),
    'purchased_therapy', coalesce((select jsonb_agg(jsonb_build_object(
        'no', e.entitlement_no, 'package', e.package_name, 'status', e.status,
        'purchase', e.purchase_date, 'deadline', e.activation_deadline,
        'activation', e.activation_date, 'expiry', e.expiry_date) order by e.created_at desc)
      from public.purchased_therapy_entitlements e where e.customer_id = p_customer_id), '[]'::jsonb),
    'legacy_therapy', coalesce((select jsonb_agg(jsonb_build_object(
        'no', le.entitlement_no, 'package', le.package_name, 'status', le.status,
        'deadline', le.activation_deadline) order by le.created_at desc)
      from public.therapy_entitlements le where le.customer_id = p_customer_id), '[]'::jsonb),
    'deleted_invoices', coalesce((select jsonb_agg(jsonb_build_object(
        'invoice', i.invoice_no, 'total', i.total_amount, 'deleted_at', i.deleted_at) order by i.deleted_at desc)
      from public.invoices i where i.customer_id = p_customer_id and i.deleted_at is not null), '[]'::jsonb)
  );
  return v_out;
end $$;

notify pgrst, 'reload schema';
