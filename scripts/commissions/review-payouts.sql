-- Read-only BEFORE migration 280. Export JSON with psql -X -qAt -f this-file.
begin read only;
do $$begin if exists(select 1 from information_schema.columns where table_schema='public' and table_name='commission_payouts' and column_name='allocation_state') then raise exception 'Allocation ledger already installed. Use review-payouts-after.sql instead.';end if;end$$;
with payout_review as (
select p.id payout_id,p.referrer_customer_id customer_id,c.full_name,p.payout_month,p.status,p.total_amount,
 p.total_tier1,p.total_tier2,p.payment_method_id,p.paid_at,
 case when p.status='paid' and p.total_amount>0 and p.payout_month=date_trunc('month',p.payout_month)::date
  and x.link_count>0 and not x.bad_link and x.linked_total=p.total_amount and x.tier1=p.total_tier1 and x.tier2=p.total_tier2
 then 'verified_explicit_links' else 'manual_review' end as review_state,
 case when p.status<>'paid' then 'Payout is not active.'
 when p.total_amount<=0 then 'Non-positive historical payout.'
 when p.payout_month<>date_trunc('month',p.payout_month)::date then 'Commission month is not the first day.'
 when x.link_count=0 then 'No explicit commission links; invoice allocations cannot be inferred.'
 when x.bad_link then 'Linked commission affiliate, month or paid status differs.'
 when x.linked_total<>p.total_amount or x.tier1<>p.total_tier1 or x.tier2<>p.total_tier2 then 'Linked commission total or tier totals differ from the recorded payment.' end reason,
 x.linked_total,x.entries
from public.commission_payouts p join public.customers c on c.id=p.referrer_customer_id
cross join lateral(select count(*) link_count,coalesce(sum(cm.commission_amount),0) linked_total,
 coalesce(sum(cm.commission_amount) filter(where cm.tier='tier1'),0) tier1,
 coalesce(sum(cm.commission_amount) filter(where cm.tier='tier2'),0) tier2,
 coalesce(bool_or(cm.referrer_customer_id<>p.referrer_customer_id or cm.invoice_paid_date is null or date_trunc('month',cm.invoice_paid_date)::date<>p.payout_month or cm.status<>'paid'),false) bad_link,
 coalesce(jsonb_agg(jsonb_build_object('commission_id',cm.id,'invoice_id',cm.invoice_id,'customer_id',cm.referrer_customer_id,'date',cm.invoice_paid_date,'tier',cm.tier,'amount',cm.commission_amount,'status',cm.status) order by cm.id),'[]') entries
 from public.commissions cm where cm.payout_id=p.id) x
order by review_state,p.payout_month,p.id
), entry_review as (
select cm.id commission_id,cm.invoice_id,cm.referrer_customer_id customer_id,c.full_name,cm.payout_id,cm.invoice_paid_date,cm.commission_amount,
 case when cm.invoice_paid_date is null then 'Commission date missing.' else 'Paid commission has no consistent active payout for this affiliate and month.' end reason
from public.commissions cm join public.customers c on c.id=cm.referrer_customer_id
where (cm.status in ('earned','paid') and cm.invoice_paid_date is null)
 or ((cm.status='paid' or cm.payout_id is not null) and not exists(select 1 from public.commission_payouts p where p.id=cm.payout_id and p.status='paid' and p.referrer_customer_id=cm.referrer_customer_id and p.payout_month=date_trunc('month',cm.invoice_paid_date)::date))
order by cm.id
) select jsonb_pretty(jsonb_build_object('mode','before_280','payouts',(select coalesce(jsonb_agg(to_jsonb(p)),'[]') from payout_review p),
 'commission_entries',(select coalesce(jsonb_agg(to_jsonb(e)),'[]') from entry_review e)));
rollback;
