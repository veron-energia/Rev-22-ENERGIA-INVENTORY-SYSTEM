-- Read-only diagnostics AFTER migrations 280–282. Run as the database owner;
-- ordinary application users use the role-checked overview/history RPCs.
begin read only;
select jsonb_pretty(jsonb_build_object(
 'mode','after_282',
 'payouts_needing_review',(select coalesce(jsonb_agg(jsonb_build_object('payout_id',p.id,'customer_id',p.referrer_customer_id,
  'name',c.full_name,'month',p.payout_month,'recorded_amount',p.total_amount,'reason',p.allocation_review_reason)),'[]')
  from public.commission_payouts p join public.customers c on c.id=p.referrer_customer_id where allocation_state='review'),
 'months_needing_review',(select coalesce(jsonb_agg(to_jsonb(b)||jsonb_build_object('name',c.full_name)),'[]')
  from public.affiliate_month_balances() b join public.customers c on c.id=b.referrer where b.review_reason is not null),
 'negative_balances',(select coalesce(jsonb_agg(to_jsonb(b)||jsonb_build_object('name',c.full_name)),'[]')
  from public.affiliate_month_balances() b join public.customers c on c.id=b.referrer where b.balance<0),
 'allocation_total_mismatches',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from (
  select p.id payout_id,p.total_amount,sum(a.amount) allocated from public.commission_payouts p
  left join public.commission_payout_allocations a on a.payout_id=p.id where p.status='paid' and p.allocation_state='verified'
  group by p.id having p.total_amount<>coalesce(sum(a.amount),0)) x)));
rollback;
