begin;
-- Allocation-aware report definitions; existing earning and staff rules are unchanged.

CREATE OR REPLACE FUNCTION public.affiliate_admin_directory()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_rows jsonb;
begin
  if not public.affiliate_payout_access(true) then raise exception 'Owner or Manager only'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'customer_id', ca.customer_id, 'name', c.full_name,
    'status', case when ca.manually_suspended then 'suspended' else ca.status end,
    'manually_suspended', ca.manually_suspended,
    'referral_code', ca.referral_code,
    'portal_account', case when acc.id is null then 'not_claimed'
                           when acc.status = 'disabled' then 'disabled' else 'claimed' end,
    'direct_referrals', (select count(*) from public.customers x where x.referred_by = ca.customer_id and x.deleted_at is null),
    'tier2', (select count(*) from public.customers x join public.customers p on p.id = x.referred_by
               where p.referred_by = ca.customer_id and x.deleted_at is null and p.deleted_at is null),
    'lifetime', (select coalesce(sum(commission_amount),0) from public.commission_reporting_rows() where referrer_customer_id = ca.customer_id and status in ('earned','paid')),
    'unpaid', (select coalesce(sum(balance),0) from public.affiliate_month_balances() where referrer = ca.customer_id),
    'blocked', (select coalesce(sum(commission_amount),0) from public.commission_reporting_rows() where referrer_customer_id = ca.customer_id and status = 'cancelled'),
    'last_commission', (select max(created_at) from public.commission_reporting_rows() where referrer_customer_id = ca.customer_id)
  ) order by c.full_name), '[]'::jsonb) into v_rows
  from public.customer_affiliates ca
  join public.customers c on c.id = ca.customer_id
  left join public.affiliate_accounts acc on acc.customer_id = ca.customer_id
  where ca.deleted_at is null;
  return v_rows;
end $function$;

CREATE OR REPLACE FUNCTION public.affiliate_directory()
 RETURNS TABLE(customer_id uuid, full_name text, phone text, member_id text, membership_status text, membership_plan text, membership_expiry date, affiliate_state text, block_reason text, store_id uuid, store_name text, direct_referrals integer, downline integer, lifetime_earned numeric, unpaid_payable numeric, blocked_commission numeric, last_commission_date date, has_profile boolean, manually_suspended boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with affs as (
    select distinct c.id as customer_id
    from public.customers c
    where c.deleted_at is null and (
      exists (select 1 from public.customer_affiliates a where a.customer_id = c.id and a.deleted_at is null)
      or exists (select 1 from public.customers r where r.referred_by = c.id)
      or exists (select 1 from public.commission_reporting_rows() cm where cm.referrer_customer_id = c.id)
    )
  )
  select
    c.id, c.full_name, c.phone,
    null::text, null::text, null::text, null::date,
    st->>'state', st->>'block_reason',
    a.store_id, s.name,
    (select count(*)::int from public.customers r where r.referred_by = c.id),
    (select count(*)::int from public.customers r1
      where r1.referred_by = c.id
         or r1.referred_by in (select id from public.customers r2 where r2.referred_by = c.id)),
    coalesce((select sum(commission_amount) from public.commission_reporting_rows() cm where cm.referrer_customer_id = c.id and cm.status in ('earned','paid')),0),
    coalesce((select sum(b.balance) from public.affiliate_month_balances() b where b.referrer=c.id),0),
    coalesce((select sum(commission_amount) from public.commission_reporting_rows() cm where cm.referrer_customer_id = c.id and cm.status = 'blocked'),0),
    (select max(invoice_paid_date) from public.commission_reporting_rows() cm where cm.referrer_customer_id = c.id),
    a.id is not null, coalesce(a.manually_suspended,false)
  from affs
  join public.customers c on c.id = affs.customer_id
  left join public.customer_affiliates a on a.customer_id = c.id and a.deleted_at is null
  left join public.stores s on s.id = a.store_id
  cross join lateral public.customer_affiliate_state(c.id) st
  where public.affiliate_payout_access()
  order by c.full_name;
$function$;

CREATE OR REPLACE FUNCTION public.affiliate_portal_earnings()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_me uuid := public.current_affiliate_customer_id();
        v_unpaid numeric; v_paid numeric; v_reversed numeric; v_blocked numeric; v_lifetime numeric;
        v_t1 numeric; v_t2 numeric; v_by_month jsonb; v_by_customer jsonb; v_by_purchase jsonb;
begin
  if v_me is null then raise exception 'Not an affiliate account'; end if;

  select
    coalesce(sum(commission_amount) filter (where status='earned'),0),
    coalesce(sum(commission_amount) filter (where status='paid'),0),
    coalesce(sum(commission_amount) filter (where status='reversed'),0),
    coalesce(sum(commission_amount) filter (where status='cancelled'),0),
    coalesce(sum(commission_amount) filter (where status='paid' and tier='tier1'),0)
           + coalesce(sum(commission_amount) filter (where status='earned' and tier='tier1'),0),
    coalesce(sum(commission_amount) filter (where status='paid' and tier='tier2'),0)
           + coalesce(sum(commission_amount) filter (where status='earned' and tier='tier2'),0)
    into v_unpaid, v_paid, v_reversed, v_blocked, v_t1, v_t2
  from public.commission_reporting_rows() where referrer_customer_id = v_me;
  v_lifetime := v_unpaid + v_paid;
  select coalesce(sum(total_amount),0) into v_paid from public.commission_payouts where referrer_customer_id=v_me and status='paid';
  v_unpaid:=v_lifetime-v_paid;

  select coalesce(jsonb_agg(jsonb_build_object('month', m, 'tier1', t1, 'tier2', t2, 'total', t1+t2) order by m desc),'[]'::jsonb)
    into v_by_month from (
      select to_char(date_trunc('month', coalesce(invoice_paid_date, created_at::date)),'YYYY-MM') as m,
             coalesce(sum(commission_amount) filter (where tier='tier1' and status in ('earned','paid')),0) as t1,
             coalesce(sum(commission_amount) filter (where tier='tier2' and status in ('earned','paid')),0) as t2
        from public.commission_reporting_rows() where referrer_customer_id = v_me group by 1) mm;

  select coalesce(jsonb_agg(jsonb_build_object('customer', cust, 'tier', tier, 'purchase_amount', spend, 'commission', comm) order by comm desc),'[]'::jsonb)
    into v_by_customer from (
      select c.full_name as cust, cm.tier::text as tier,
             public._aff_settled_spend(c.id) as spend,
             coalesce(sum(cm.commission_amount) filter (where cm.status in ('earned','paid')),0) as comm
        from public.commission_reporting_rows() cm join public.customers c on c.id = cm.buyer_customer_id
       where cm.referrer_customer_id = v_me group by c.id, c.full_name, cm.tier) cc;

  v_by_purchase := public.affiliate_portal_purchases();

  return jsonb_build_object(
    'summary', jsonb_build_object('lifetime', v_lifetime, 'unpaid', v_unpaid, 'paid', v_paid,
      'reversed', v_reversed, 'blocked', v_blocked),
    'by_tier', jsonb_build_object('tier1', v_t1, 'tier2', v_t2),
    'by_month', v_by_month, 'by_customer', v_by_customer, 'by_purchase', v_by_purchase);
end $function$;

CREATE OR REPLACE FUNCTION public.affiliate_portal_payouts()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_me uuid := public.current_affiliate_customer_id(); v_rows jsonb;
begin
  if v_me is null then raise exception 'Not an affiliate account'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
           'payout_month', to_char(payout_month,'YYYY-MM'),
           'tier1', total_tier1, 'tier2', total_tier2, 'total', total_amount,
           'paid_date', payment_date, 'status', status, 'reference', reference, 'method', payment_method_name, 'notes', notes) order by payout_month desc), '[]'::jsonb)
    into v_rows from public.commission_payouts where referrer_customer_id = v_me;
  return v_rows;
end $function$;

CREATE OR REPLACE FUNCTION public.report_affiliates()
 RETURNS TABLE(customer_id uuid, customer_name text, member_id text, affiliate_state text, block_reason text, store_name text, direct_referrals integer, downline integer, earned numeric, paid numeric, reversed numeric, blocked numeric, tier1_earned numeric, tier2_earned numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select
    d.customer_id, d.full_name, d.member_id, d.affiliate_state, d.block_reason,
    d.store_name, d.direct_referrals, d.downline,
    d.lifetime_earned, coalesce((select sum(total_amount) from public.commission_payouts p where p.referrer_customer_id=d.customer_id and p.status='paid'),0),
    coalesce((select sum(commission_amount) from public.commission_reporting_rows() cm where cm.referrer_customer_id = d.customer_id and cm.status = 'reversed'),0),
    d.blocked_commission,
    coalesce((select sum(commission_amount) from public.commission_reporting_rows() cm where cm.referrer_customer_id = d.customer_id and cm.tier = 'tier1' and cm.status in ('earned','paid')),0),
    coalesce((select sum(commission_amount) from public.commission_reporting_rows() cm where cm.referrer_customer_id = d.customer_id and cm.tier = 'tier2' and cm.status in ('earned','paid')),0)
  from public.affiliate_directory() d
  order by d.full_name;
$function$;

CREATE OR REPLACE FUNCTION public.referrer_list()
 RETURNS TABLE(customer_id uuid, full_name text, phone text, direct_referrals integer, total_downline integer, lifetime_earned numeric, unpaid_earned numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
    coalesce((select sum(b.balance) from public.affiliate_month_balances() b where b.referrer=c.id),0) as unpaid_earned
  from referrers r
  join public.customers c on c.id = r.cid
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
    from public.commission_reporting_rows() cm where cm.referrer_customer_id = c.id
  ) e on true
  where public.affiliate_payout_access()
  order by coalesce(e.lifetime, 0) desc, c.full_name
$function$;

CREATE OR REPLACE FUNCTION public.referrer_earnings(p_customer_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_lifetime jsonb;
  v_monthly jsonb;
  v_by_buyer jsonb;
  v_lines jsonb;
begin
  if not public.affiliate_payout_access() then raise exception 'Commission access denied' using errcode='42501'; end if;
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
  from public.commission_reporting_rows() where referrer_customer_id = p_customer_id;

  v_lifetime:=v_lifetime||jsonb_build_object('total_paid',(select coalesce(sum(total_amount),0) from public.commission_payouts where referrer_customer_id=p_customer_id and status='paid'), 'total_earned',(select coalesce(sum(balance),0) from public.affiliate_month_balances() where referrer=p_customer_id));

  -- Per-month breakdown (by invoice paid date), tier + paid/unpaid split.
  select coalesce(jsonb_agg(jsonb_build_object('month',to_char(month,'YYYY-MM'),'tier1',tier1,'tier2',tier2,'unpaid',balance,'paid',paid,'total',earned+adjustments,'review_reason',review_reason) order by month desc),'[]') into v_monthly from public.affiliate_month_balances() where referrer=p_customer_id;

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
      cm.line_amount, cm.rate, cm.commission_amount,
      case when cm.status in ('earned','paid') and coalesce(a.amount,0)>0 and a.amount<cm.commission_amount then 'partially_paid'
       when cm.status in ('earned','paid') and a.amount=0 then 'earned' else cm.status::text end as status,
      coalesce(a.amount,case when cm.status='paid' then cm.commission_amount else 0 end) as allocated_amount,
      cm.invoice_paid_date, inv.invoice_no, p.name as product_name
    from public.commissions cm
    left join lateral (select sum(amount) amount from public.commission_payout_allocations where commission_id=cm.id) a on true
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
end; $function$;


CREATE OR REPLACE FUNCTION public.affiliate_portal_network()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_me uuid := public.current_affiliate_customer_id(); v_t1 jsonb; v_t2 jsonb;
begin
  if v_me is null then raise exception 'Not an affiliate account'; end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'customer_name', c.full_name, 'tier', 'tier1',
           'referral_date', c.referred_at, 'joined_at', c.created_at,
           'purchases', (select count(*) from public.invoices i where i.customer_id = c.id and i.deleted_at is null and i.status in ('paid','completed_foc','partially_paid')),
           'total_spent', public._aff_settled_spend(c.id),
           'your_commission', (select coalesce(sum(cm.commission_amount),0) from public.commissions cm
                                where cm.referrer_customer_id = v_me and cm.buyer_customer_id = c.id
                                  and cm.status in ('earned','paid'))
         ) order by c.created_at desc), '[]'::jsonb)
    into v_t1
    from public.customers c where c.referred_by = v_me and c.deleted_at is null;

  select coalesce(jsonb_agg(jsonb_build_object(
           'customer_name', c.full_name, 'tier', 'tier2',
           'parent_name', p.full_name,
           'referral_date', c.referred_at, 'joined_at', c.created_at,
           'purchases', (select count(*) from public.invoices i where i.customer_id = c.id and i.deleted_at is null and i.status in ('paid','completed_foc','partially_paid')),
           'total_spent', public._aff_settled_spend(c.id),
           'your_commission', (select coalesce(sum(cm.commission_amount),0) from public.commissions cm
                                where cm.referrer_customer_id = v_me and cm.buyer_customer_id = c.id and cm.status in ('earned','paid'))
         ) order by c.created_at desc), '[]'::jsonb)
    into v_t2
    from public.customers c
    join public.customers p on p.id = c.referred_by
   where p.referred_by = v_me and c.deleted_at is null and p.deleted_at is null;

  return jsonb_build_object('tier1', v_t1, 'tier2', v_t2);
end $function$;

CREATE OR REPLACE FUNCTION public.affiliate_portal_purchases()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_me uuid := public.current_affiliate_customer_id(); v_rows jsonb;
begin
  if v_me is null then raise exception 'Not an affiliate account'; end if;
  select coalesce(jsonb_agg(row_to_json(t)::jsonb order by (t.purchase_date) desc), '[]'::jsonb) into v_rows
  from (
    select
      c.full_name as customer_name,
      cm.tier::text as tier,
      i.business_date as purchase_date,
      'Purchase'::text as description,
      public.invoice_received_sales_amount(i.id) as purchase_amount,
      coalesce(sum(cm.commission_amount) filter(where cm.status in ('earned','paid')),0) as your_commission,
      case when coalesce(sum(cm.commission_amount) filter(where cm.status in ('earned','paid')),0)<=0 then 'reversed'
        when coalesce(sum(cm.commission_amount) filter(where cm.status='paid'),0)>0
         and coalesce(sum(cm.commission_amount) filter(where cm.status='earned'),0)>0 then 'partially_paid'
        when coalesce(sum(cm.commission_amount) filter(where cm.status='paid'),0)>0 then 'paid'
        when bool_or(cm.status='earned') then 'earned' else 'blocked' end as status
    from public.commission_reporting_rows() cm
    join public.invoices i on i.id = cm.invoice_id
    join public.customers c on c.id = cm.buyer_customer_id
   where cm.referrer_customer_id = v_me
   group by c.full_name, cm.tier, i.id, i.created_at, i.total_amount
  ) t;
  return v_rows;
end $function$;

revoke all on function public.referrer_list(),public.referrer_earnings(uuid),public.affiliate_directory(),public.report_affiliates() from public,anon;
grant execute on function public.referrer_list(),public.referrer_earnings(uuid),public.affiliate_directory(),public.report_affiliates() to authenticated;
notify pgrst,'reload schema';
commit;
