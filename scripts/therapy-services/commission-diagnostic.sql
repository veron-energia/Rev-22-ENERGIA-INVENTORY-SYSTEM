-- =====================================================================
-- HOW MUCH PACKAGE COMMISSION WAS PAID AT THE WRONG RATE
--
-- Read-only. Nothing here updates, inserts or deletes anything.
--
-- WHY THIS FILE EXISTS RATHER THAN package_commission_diagnostic().
--
-- That function is security definer and gated on is_manager_or_above(), which
-- reads public.profiles for auth.uid(). In the Supabase SQL editor there is no
-- signed-in user, auth.uid() is null, and the function returns ZERO ROWS —
-- which is indistinguishable from "nothing was wrong". Use the function from
-- inside the application, signed in as an Owner or Manager. Use THIS file in
-- the SQL editor.
--
-- It also reports TIER 2, which the function does not. Tier 2 is a percentage
-- of the tier 1 amount, so an inflated tier 1 inflated it too; the function's
-- figure understates the total by that much.
--
-- What counts as a package commission: a commissions row on the sale's invoice
-- with invoice_item_id IS NULL. The package functions record no line;
-- line-based product commission does. That keeps a mixed invoice's product
-- commission out of these figures.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. The headline. Run this first.
--
-- "already paid out" is money that has reached someone. "not yet paid out" is
-- the part still in hand. They are separated because they are different
-- decisions, not because one of them is less real.
-- ---------------------------------------------------------------------
with rates as (
  select commission_tier1_third_rate as t1_third,
         commission_tier2_third_rate as t2_third
    from public.app_settings where id = true),
sales as (
  select 'Credit package'::text as kind, s.id as sale_id, s.invoice_id,
         s.external_paid, coalesce(s.classification_snapshot,'own') as classification
    from public.credit_package_sales s
  union all
  select 'Premium bundle', s.id, s.invoice_id,
         s.external_paid, coalesce(s.classification_snapshot,'third_party')
    from public.premium_bundle_sales s),
affected as (
  select * from sales
   where classification <> 'third_party' and coalesce(external_paid,0) > 0),
lines as (
  select a.sale_id, c.tier::text as tier, c.commission_amount, c.payout_id,
         c.status::text as status,
         round(a.external_paid * r.t1_third / 100.0, 2) as t1_expected,
         round(round(a.external_paid * r.t1_third / 100.0, 2) * r.t2_third / 100.0, 2) as t2_expected
    from affected a
    cross join rates r
    join public.commissions c
      on c.invoice_id = a.invoice_id and c.invoice_item_id is null)
select
  case when payout_id is not null then 'already paid out'
       when status = 'reversed' then 'reversed'
       else 'not yet paid out' end                                   as payout_status,
  count(distinct sale_id)                                            as sales,
  sum(commission_amount)                                             as commission_paid,
  sum(case when tier = 'tier1' then t1_expected else t2_expected end) as should_have_been,
  sum(commission_amount - case when tier = 'tier1' then t1_expected else t2_expected end) as overpaid
from lines
group by 1
union all
select 'TOTAL', count(distinct sale_id), sum(commission_amount),
       sum(case when tier = 'tier1' then t1_expected else t2_expected end),
       sum(commission_amount - case when tier = 'tier1' then t1_expected else t2_expected end)
from lines;


-- ---------------------------------------------------------------------
-- 2. Row by row, if the headline is worth acting on.
-- ---------------------------------------------------------------------
with rates as (
  select commission_tier1_third_rate as t1_third,
         commission_tier2_third_rate as t2_third
    from public.app_settings where id = true),
sales as (
  select 'Credit package'::text as kind, s.id as sale_id, s.invoice_id, s.customer_id,
         s.external_paid, coalesce(s.classification_snapshot,'own') as classification,
         s.created_at::date as sold_on
    from public.credit_package_sales s
  union all
  select 'Premium bundle', s.id, s.invoice_id, s.customer_id,
         s.external_paid, coalesce(s.classification_snapshot,'third_party'),
         s.created_at::date
    from public.premium_bundle_sales s)
select sa.sold_on, sa.kind, i.invoice_no,
       buyer.full_name  as bought_by,
       earner.full_name as commission_to,
       sa.external_paid as money_received,
       c.tier::text     as tier,
       c.rate           as rate_used,
       c.commission_amount as paid,
       case when c.tier::text = 'tier1'
            then round(sa.external_paid * r.t1_third / 100.0, 2)
            else round(round(sa.external_paid * r.t1_third / 100.0, 2) * r.t2_third / 100.0, 2)
       end as should_have_been,
       c.commission_amount - case when c.tier::text = 'tier1'
            then round(sa.external_paid * r.t1_third / 100.0, 2)
            else round(round(sa.external_paid * r.t1_third / 100.0, 2) * r.t2_third / 100.0, 2)
       end as overpaid,
       case when c.payout_id is not null then 'already paid out'
            when c.status::text = 'reversed' then 'reversed'
            else 'not yet paid out' end as payout_status
  from sales sa
  cross join rates r
  join public.commissions c
    on c.invoice_id = sa.invoice_id and c.invoice_item_id is null
  left join public.invoices  i      on i.id = sa.invoice_id
  left join public.customers buyer  on buyer.id  = sa.customer_id
  left join public.customers earner on earner.id = c.referrer_customer_id
 where sa.classification <> 'third_party'
   and coalesce(sa.external_paid, 0) > 0
 order by sa.sold_on desc, i.invoice_no, c.tier;


-- ---------------------------------------------------------------------
-- 3. A sanity check on the rates the figures above assume.
--
-- If tier1_third is not 4.5, everything above is measured against a different
-- rule and the numbers mean something else.
-- ---------------------------------------------------------------------
select commission_tier1_own_rate   as own_tier1,
       commission_tier1_third_rate as third_tier1,
       commission_tier2_own_rate   as own_tier2,
       commission_tier2_third_rate as third_tier2
  from public.app_settings where id = true;
