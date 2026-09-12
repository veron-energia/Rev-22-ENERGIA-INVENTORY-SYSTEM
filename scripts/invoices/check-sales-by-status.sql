-- =====================================================================
-- HOW MUCH OF SALES COMES FROM EACH INVOICE STATUS
-- Supabase SQL editor version.
--
-- READ ONLY: one SELECT. It writes nothing and changes nothing.
--
-- Run this BEFORE applying 294 to see exactly what the reported problem is
-- worth, and AFTER to confirm the excluded rows have gone to zero.
--
-- Edit the two dates on the next line and run. That is the only change needed.
--
-- The SQL editor runs with no signed-in user, so auth.uid() is null and every
-- security-definer report function returns ZERO rows. Calling sales_between()
-- here would print 0.00 and look like you had no sales at all. This reads the
-- base tables directly and reproduces the same arithmetic.
-- =====================================================================
with params as (
  select date '2026-09-01' as from_date,
         date '2026-09-30' as to_date
),

-- Every receipt and refund, with no status filter at all -- deliberately, so
-- the statuses that SHOULD be excluded are still visible and can be counted.
ledger as (
  select i.id as invoice_id, i.status::text as status,
         (coalesce(p.effective_at, p.created_at) at time zone 'Asia/Singapore')::date as sales_date,
         case when p.entry_kind = 'correction_reversal' then -p.amount else p.amount end as amount
    from public.invoice_payments p
    join public.invoices i on i.id = p.invoice_id
    join public.payment_methods m on m.id = p.payment_method_id
   where i.deleted_at is null
     and not coalesce(m.is_wallet_credit, false)
  union all
  select i.id, i.status::text,
         (r.created_at at time zone 'Asia/Singapore')::date,
         -(r.amount - coalesce(r.credit_returned, 0))
    from public.invoice_refunds r
    join public.invoices i on i.id = r.invoice_id
   where i.deleted_at is null
     and r.payment_id is not null
),
in_period as (
  select l.* from ledger l, params pr
   where l.sales_date between pr.from_date and pr.to_date
),
counted as (
  -- The rule 294 installs.
  select status,
         status in ('paid','partially_paid','completed_foc',
                    'cancellation_requested','refund_requested') as counts_as_sale
    from (select distinct status from in_period) s
)

-- Section 1: the split. "counts_as_sale = false" is money leaving the figure.
select '1. BY STATUS' as section,
       l.status,
       case when c.counts_as_sale then 'stays in Sales' else 'LEAVES Sales' end as after_294,
       count(distinct l.invoice_id)::text as detail,
       to_char(round(sum(l.amount),2),'FM999999990.00') as amount
  from in_period l join counted c on c.status = l.status
 group by l.status, c.counts_as_sale

union all
select '2. TOTAL', 'all statuses', 'sales before 294', '',
       to_char(round(sum(amount),2),'FM999999990.00') from in_period

union all
select '2. TOTAL', 'counted statuses only', 'sales after 294', '',
       to_char(round(sum(l.amount),2),'FM999999990.00')
  from in_period l join counted c on c.status = l.status where c.counts_as_sale

union all
select '2. TOTAL', 'difference', 'what the change removes', '',
       to_char(round(coalesce((select sum(l.amount) from in_period l
                               join counted c on c.status=l.status
                              where not c.counts_as_sale),0),2),'FM999999990.00')

union all
-- Section 3: the one consequence worth knowing about. Money received against an
-- invoice that was later cancelled, with no refund recorded against it. After
-- 294 this money is not in Sales, so Sales will be lower than cash banked by
-- this amount. Each row needs either a recorded refund or the invoice reopening.
-- An empty section 3 means the change costs you nothing.
select '3. CANCELLED BUT MONEY KEPT', i.invoice_no, i.status::text,
       to_char(coalesce(rf.refunded,0),'FM999999990.00'),
       to_char(round(coalesce(rc.received,0) - coalesce(rf.refunded,0),2),'FM999999990.00')
  from public.invoices i
  left join lateral (
    select sum(case when p.entry_kind='correction_reversal' then -p.amount else p.amount end) received
      from public.invoice_payments p join public.payment_methods m on m.id=p.payment_method_id
     where p.invoice_id=i.id and not coalesce(m.is_wallet_credit,false)) rc on true
  left join lateral (
    select sum(r.amount - coalesce(r.credit_returned,0)) refunded
      from public.invoice_refunds r where r.invoice_id=i.id and r.payment_id is not null) rf on true
 where i.deleted_at is null
   and i.status::text in ('cancelled','refunded')
   and round(coalesce(rc.received,0) - coalesce(rf.refunded,0),2) > 0

 order by 1, 2;
