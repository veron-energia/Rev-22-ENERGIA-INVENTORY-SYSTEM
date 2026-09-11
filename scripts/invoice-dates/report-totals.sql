-- Per-date reporting attribution, separately from actual collections.
begin isolation level repeatable read read only;
set local timezone='UTC';
select set_config('request.jwt.claim.sub', :'actor',true) as ignored \gset
set local role authenticated;
select jsonb_build_object('sales_by_date',coalesce((select jsonb_agg(s order by s.sales_date) from (
 select sales_date,sum(amount) amount,count(*) event_rows,count(distinct (invoice_id,event_id,event_kind)) distinct_events
 from public.invoice_sales_ledger() group by sales_date) s),'[]'),
 'collections',coalesce((select jsonb_agg(d order by d.pay_date,d.payment_method_id) from public.daily_payments_by_method(null,null,null) d),'[]'));
commit;
