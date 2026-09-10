-- READ ONLY, compatible before and after invoice migrations 170+.
-- Run with a read-only database role and keep customer/financial output private.
begin transaction read only;
-- A reviewed business date is required. Creation dates are suggestions only.
select i.id invoice_id,i.invoice_no,i.customer_id,c.full_name customer_name,i.status,
 to_jsonb(i)->>'business_date' business_date,(i.created_at at time zone 'Asia/Singapore')::date created_date_suggestion,
 case when nullif(to_jsonb(i)->>'business_date','') is null then 'Review business date; excluded from invoice-date sales until assigned'
 when i.status='refunded' and not exists(select 1 from public.invoice_refunds r where r.invoice_id=i.id) then 'Historical refunded status without refund ledger evidence'
 when exists(select 1 from public.invoice_refunds r where r.invoice_id=i.id and nullif(to_jsonb(r)->>'payment_id','') is null) then 'Map historical refund to original payment source'
 else 'Review original component/benefit evidence before operational corrections' end review_reason
from public.invoices i left join public.customers c on c.id=i.customer_id
where i.deleted_at is null and (nullif(to_jsonb(i)->>'business_date','') is null
 or (i.status='refunded' and not exists(select 1 from public.invoice_refunds r where r.invoice_id=i.id))
 or exists(select 1 from public.invoice_refunds r where r.invoice_id=i.id and nullif(to_jsonb(r)->>'payment_id','') is null)
 or (nullif(to_jsonb(i)->>'stock_snapshot_version','') is null and exists(select 1 from public.invoice_items it where it.invoice_id=i.id and it.line_kind in ('promotion','premium_bundle','voucher'))))
order by i.created_at,i.id;

-- Compare the SAME eligible actual receipts under two reporting-date bases.
-- Wallet redemptions are excluded; actual payment/creation timestamps are kept.
with receipts as (
 select i.id,coalesce(nullif(to_jsonb(p)->>'effective_at','')::timestamptz,p.created_at) actual_date,
 nullif(to_jsonb(i)->>'business_date','')::date business_date,
 case when to_jsonb(p)->>'entry_kind'='correction_reversal' then -p.amount else p.amount end amount
 from public.invoices i join public.invoice_payments p on p.invoice_id=i.id join public.payment_methods m on m.id=p.payment_method_id
 where i.deleted_at is null and not coalesce(m.is_wallet_credit,false)
), comparison as (
 select date_trunc('month',actual_date at time zone 'Asia/Singapore')::date as report_month,amount collections,0::numeric invoice_date_sales,0::numeric pending_review from receipts
 union all select date_trunc('month',business_date)::date,0,amount,0 from receipts where business_date is not null
 union all select null,0,0,amount from receipts where business_date is null
 union all select date_trunc('month',r.created_at at time zone 'Asia/Singapore')::date,0,
  -(r.amount-coalesce((to_jsonb(r)->>'credit_returned')::numeric,0)),0 from public.invoice_refunds r
  join public.invoices i on i.id=r.invoice_id where i.deleted_at is null and nullif(to_jsonb(r)->>'payment_id','') is not null
)
select report_month,sum(collections) actual_payment_date_collections,sum(invoice_date_sales) proposed_invoice_date_sales,
 sum(pending_review) receipts_pending_business_date,sum(invoice_date_sales)-sum(collections) difference
from comparison group by report_month order by report_month nulls last;

-- Exact source mapping is required before refunding old wallet payments.
select i.id invoice_id,i.invoice_no,p.id payment_id,p.amount,m.name payment_method,
 'Historical wallet allocations have no payment link; do not guess between receipts or recipients' review_reason
from public.invoice_payments p join public.invoices i on i.id=p.invoice_id join public.payment_methods m on m.id=p.payment_method_id
where coalesce(m.is_wallet_credit,false) and not exists(select 1 from public.invoice_line_credit_allocations a where to_jsonb(a)->>'payment_id'=p.id::text)
and coalesce(to_jsonb(p)->>'entry_kind','receipt')<>'correction_reversal';

-- No current catalogue is substituted for historical stock movement evidence.
select i.id invoice_id,i.invoice_no,m.id movement_id,m.product_id,m.quantity,m.movement_type,
 'Historical return needs its original sale movement identified before another stock reversal' review_reason
from public.stock_movements m join public.invoices i on i.id=m.invoice_id
where m.movement_type::text in ('invoice_cancel_return','invoice_refund_return','refund_return') and nullif(to_jsonb(m)->>'reversed_sale_id','') is null;
rollback;
