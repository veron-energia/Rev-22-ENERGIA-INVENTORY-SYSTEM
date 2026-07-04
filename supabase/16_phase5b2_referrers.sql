-- =====================================================================
-- ENERGIA — PHASE 5B.2: Referrer relationship + earnings views
--   * referrer_downline(p_customer_id)  → full recursive downline tree
--   * referrer_list()                   → everyone who referred / earned
--   * referrer_earnings(p_customer_id)  → lifetime + per-month + paid/unpaid,
--                                          plus per-buyer (Tier 2 traceback)
--
-- Additive + idempotent. Run AFTER 15_phase5b_commission.sql.
--
-- PREREQUISITE: the commission_status enum must include 'paid'. If you get
-- "invalid input value for enum commission_status: paid", run
-- 15b_fix_commission_status_enum.sql by itself first, then re-run this file.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Full downline tree for a referrer, however deep the chain goes.
--    Returns each descendant with its depth (1 = directly referred).
-- ---------------------------------------------------------------------
create or replace function public.referrer_downline(p_customer_id uuid)
returns table (
  customer_id uuid,
  full_name text,
  phone text,
  referred_by uuid,
  depth integer,
  paid_purchases integer,
  total_spend numeric
)
language sql stable security definer set search_path = public as $$
  with recursive tree as (
    select c.id, c.full_name, c.phone, c.referred_by, 1 as depth
    from public.customers c
    where c.referred_by = p_customer_id and c.deleted_at is null
    union all
    select c.id, c.full_name, c.phone, c.referred_by, t.depth + 1
    from public.customers c
    join tree t on c.referred_by = t.id
    where c.deleted_at is null and t.depth < 50   -- safety bound
  )
  select
    t.id, t.full_name, t.phone, t.referred_by, t.depth,
    coalesce(inv.cnt, 0)::integer as paid_purchases,
    coalesce(inv.spend, 0) as total_spend
  from tree t
  left join lateral (
    select count(*) as cnt, sum(i.total_amount) as spend
    from public.invoices i
    where i.customer_id = t.id and i.status = 'paid' and i.deleted_at is null
  ) inv on true
  order by t.depth, t.full_name
$$;

-- ---------------------------------------------------------------------
-- 2. List of referrers: any customer who has referred someone OR earned
--    commission. Includes quick headline numbers for the list view.
-- ---------------------------------------------------------------------
create or replace function public.referrer_list()
returns table (
  customer_id uuid,
  full_name text,
  phone text,
  direct_referrals integer,
  total_downline integer,
  lifetime_earned numeric,
  unpaid_earned numeric
)
language sql stable security definer set search_path = public as $$
  with referrers as (
    -- customers who have referred at least one person
    select distinct referred_by as cid from public.customers
    where referred_by is not null
    union
    -- customers who have earned commission
    select distinct referrer_customer_id as cid from public.commissions
  )
  select
    c.id, c.full_name, c.phone,
    coalesce(d.direct_cnt, 0)::integer as direct_referrals,
    coalesce(dl.total_cnt, 0)::integer as total_downline,
    coalesce(e.lifetime, 0) as lifetime_earned,
    coalesce(e.unpaid, 0) as unpaid_earned
  from referrers r
  join public.customers c on c.id = r.cid and c.deleted_at is null
  left join lateral (
    select count(*) as direct_cnt from public.customers x
    where x.referred_by = c.id and x.deleted_at is null
  ) d on true
  left join lateral (
    select count(*) as total_cnt from public.referrer_downline(c.id)
  ) dl on true
  left join lateral (
    select
      coalesce(sum(case when status in ('earned','paid') then commission_amount else 0 end),0) as lifetime,
      coalesce(sum(case when status = 'earned' then commission_amount else 0 end),0) as unpaid
    from public.commissions cm where cm.referrer_customer_id = c.id
  ) e on true
  order by coalesce(e.lifetime, 0) desc, c.full_name
$$;

-- ---------------------------------------------------------------------
-- 3. Full earnings detail for one referrer.
--    Returns a JSON object with:
--      - lifetime totals (tier1/tier2, paid/unpaid)
--      - per-month breakdown
--      - per-buyer subtotals (the Tier 2 "from which Tier 1" trace)
--      - every commission line (for the expandable detail)
-- ---------------------------------------------------------------------
create or replace function public.referrer_earnings(p_customer_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_lifetime jsonb;
  v_monthly jsonb;
  v_by_buyer jsonb;
  v_lines jsonb;
begin
  -- Lifetime split by tier and paid/unpaid.
  select jsonb_build_object(
    'tier1_earned', coalesce(sum(case when tier='tier1' and status='earned' then commission_amount else 0 end),0),
    'tier1_paid',   coalesce(sum(case when tier='tier1' and status='paid'   then commission_amount else 0 end),0),
    'tier2_earned', coalesce(sum(case when tier='tier2' and status='earned' then commission_amount else 0 end),0),
    'tier2_paid',   coalesce(sum(case when tier='tier2' and status='paid'   then commission_amount else 0 end),0),
    'reversed',     coalesce(sum(case when status='reversed' then commission_amount else 0 end),0),
    'total_earned', coalesce(sum(case when status='earned' then commission_amount else 0 end),0),
    'total_paid',   coalesce(sum(case when status='paid'   then commission_amount else 0 end),0)
  ) into v_lifetime
  from public.commissions where referrer_customer_id = p_customer_id;

  -- Per-month breakdown (by invoice paid date), tier + paid/unpaid split.
  select coalesce(jsonb_agg(row_to_json(m)), '[]'::jsonb) into v_monthly
  from (
    select
      to_char(date_trunc('month', invoice_paid_date), 'YYYY-MM') as month,
      sum(case when tier='tier1' then commission_amount else 0 end) as tier1,
      sum(case when tier='tier2' then commission_amount else 0 end) as tier2,
      sum(case when status='earned' then commission_amount else 0 end) as unpaid,
      sum(case when status='paid' then commission_amount else 0 end) as paid,
      sum(commission_amount) as total
    from public.commissions
    where referrer_customer_id = p_customer_id and status in ('earned','paid')
    group by date_trunc('month', invoice_paid_date)
    order by date_trunc('month', invoice_paid_date) desc
  ) m;

  -- Per-buyer subtotals: how much this referrer earned from each buyer,
  -- split by tier. For Tier 2 rows the buyer is Customer 3, so this is the
  -- "from which downline" trace.
  select coalesce(jsonb_agg(row_to_json(b)), '[]'::jsonb) into v_by_buyer
  from (
    select
      cm.buyer_customer_id,
      cust.full_name as buyer_name,
      sum(case when cm.tier='tier1' then cm.commission_amount else 0 end) as tier1,
      sum(case when cm.tier='tier2' then cm.commission_amount else 0 end) as tier2,
      sum(cm.commission_amount) as total,
      count(*) as lines
    from public.commissions cm
    join public.customers cust on cust.id = cm.buyer_customer_id
    where cm.referrer_customer_id = p_customer_id and cm.status in ('earned','paid')
    group by cm.buyer_customer_id, cust.full_name
    order by total desc
  ) b;

  -- Every commission line (for expandable detail under each buyer).
  select coalesce(jsonb_agg(row_to_json(l)), '[]'::jsonb) into v_lines
  from (
    select
      cm.id, cm.buyer_customer_id, cm.tier, cm.product_type,
      cm.line_amount, cm.rate, cm.commission_amount, cm.status,
      cm.invoice_paid_date, inv.invoice_no, p.name as product_name
    from public.commissions cm
    join public.invoices inv on inv.id = cm.invoice_id
    left join public.invoice_items ii on ii.id = cm.invoice_item_id
    left join public.products p on p.id = ii.product_id
    where cm.referrer_customer_id = p_customer_id
    order by cm.invoice_paid_date desc, cm.tier
  ) l;

  return jsonb_build_object(
    'lifetime', v_lifetime,
    'monthly', v_monthly,
    'by_buyer', v_by_buyer,
    'lines', v_lines
  );
end; $$;

notify pgrst, 'reload schema';
