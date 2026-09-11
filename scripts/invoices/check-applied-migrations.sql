-- Which of the recent invoice migrations are actually applied?
-- Read-only. Paste into the Supabase SQL editor and run.
select '292 — sales on the payment date' as migration,
       (to_regprocedure('public.payment_sales_date(timestamptz,timestamptz)') is not null) as applied,
       'Without it, money is still reported on the invoice date' as if_missing
union all
select '293 — dashboard tiles share one basis',
       (to_regprocedure('public.invoice_sales_day(uuid)') is not null),
       'Without it, Sales uses the payment date but Items sold and Discount still use the invoice date'
union all
select '291 — credit package reward resolution',
       (to_regprocedure('public.resolve_invoice_credit_rewards(uuid,text,uuid,boolean,uuid)') is not null),
       'Without it, a credit package with rewards cannot be refunded or cancelled'
union all
select '290 — historical date recovery tooling',
       (to_regprocedure('public.preview_invoice_date_recovery(uuid[])') is not null),
       'Without it, the date review and recovery tools are unavailable'
order by migration;
