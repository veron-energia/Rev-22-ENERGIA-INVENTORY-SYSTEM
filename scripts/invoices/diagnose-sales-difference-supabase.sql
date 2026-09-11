-- =====================================================================
-- WHY THE DASHBOARD SALES FIGURE DIFFERS FROM THE INVOICES
-- Supabase SQL editor version.
--
-- READ ONLY: one SELECT. It writes nothing and changes nothing.
--
-- Edit the two dates on the next line and run. That is the only change needed.
--
-- Why this differs from the psql version: the SQL editor has no \gset and no
-- :variables, and it runs with no signed-in user — so auth.uid() is null and
-- every security-definer report function returns ZERO. Calling sales_between()
-- here would show "0.00" and look like you had no sales at all. This reads the
-- base tables directly instead, reproducing the same arithmetic.
-- =====================================================================
with params as (
  select date '2026-09-01' as from_date,
         date '2026-09-30' as to_date
),

-- The same ledger the dashboard uses: external receipts on the day the money
-- arrived, refunds on the refund date, wallet credit excluded from both.
ledger as (
  select i.id as invoice_id,
         (coalesce(p.effective_at, p.created_at) at time zone 'Asia/Singapore')::date as sales_date,
         case when p.entry_kind = 'correction_reversal' then -p.amount else p.amount end as amount,
         'receipt'::text as event_kind
    from public.invoice_payments p
    join public.invoices i on i.id = p.invoice_id
    join public.payment_methods m on m.id = p.payment_method_id
   where i.deleted_at is null
     and not coalesce(m.is_wallet_credit, false)
  union all
  select i.id,
         (r.created_at at time zone 'Asia/Singapore')::date,
         -(r.amount - coalesce(r.credit_returned, 0)),
         'refund'
    from public.invoice_refunds r
    join public.invoices i on i.id = r.invoice_id
   where i.deleted_at is null
     and r.payment_id is not null
),
in_period as (
  select l.* from ledger l, params pr
   where l.sales_date between pr.from_date and pr.to_date
),

-- Invoices whose own date falls in the period. An invoice with no recorded
-- business date uses the Singapore day it was created, matching the list.
dated as (
  select i.id, i.invoice_no, i.status, i.total_amount, i.store_id,
         coalesce(i.business_date, (i.created_at at time zone 'Asia/Singapore')::date) as invoice_day
    from public.invoices i, params pr
   where i.deleted_at is null
     and coalesce(i.business_date, (i.created_at at time zone 'Asia/Singapore')::date)
         between pr.from_date and pr.to_date
),
per_invoice as (
  select d.id, d.invoice_no, d.status, d.invoice_day, d.total_amount, d.store_id,
         round(coalesce(sum(case when coalesce(m.is_wallet_credit,false)
              then case when p.entry_kind='correction_reversal' then -p.amount else p.amount end end),0),2) as paid_by_credit,
         round(coalesce(sum(case when not coalesce(m.is_wallet_credit,false)
               and (coalesce(p.effective_at,p.created_at) at time zone 'Asia/Singapore')::date
                   between (select from_date from params) and (select to_date from params)
              then case when p.entry_kind='correction_reversal' then -p.amount else p.amount end end),0),2) as counted_here,
         round(coalesce(sum(case when not coalesce(m.is_wallet_credit,false)
               and (coalesce(p.effective_at,p.created_at) at time zone 'Asia/Singapore')::date
                   not between (select from_date from params) and (select to_date from params)
              then case when p.entry_kind='correction_reversal' then -p.amount else p.amount end end),0),2) as received_other_period
    from dated d
    left join public.invoice_payments p on p.invoice_id = d.id
    left join public.payment_methods m on m.id = p.payment_method_id
   group by d.id, d.invoice_no, d.status, d.invoice_day, d.total_amount, d.store_id
),
totals as (
  select
    round(coalesce((select sum(total_amount) from dated),0),2) as invoiced_total,
    round(coalesce((select sum(counted_here + paid_by_credit + received_other_period) from per_invoice),0),2) as received_total,
    round(coalesce((select sum(amount) from in_period),0),2) as dashboard_sales,
    round(coalesce((select sum(amount) from in_period where event_kind='refund'),0),2) as refunds,
    round(coalesce((select sum(paid_by_credit) from per_invoice),0),2) as credit,
    round(coalesce((select sum(received_other_period) from per_invoice),0),2) as other_period,
    round(coalesce((select sum(counted_here) from per_invoice),0),2) as counted_here
)

-- 0. What the invoices add up to, versus what counts as sales.
--    This is the comparison people usually mean by "the invoices and the
--    dashboard disagree". An invoice is billed in full the day it is raised;
--    only the money actually received is sales.
select 0 as section, 1 as ord, 'INVOICED versus SALES' as line, null::numeric as amount, null::text as note
union all select 0,2,'invoices dated in this period, billed in full', invoiced_total, null from totals
union all select 0,3,'  of which never received (unpaid or still outstanding)',
  -(invoiced_total - received_total), 'This is not sales until the money arrives' from totals
union all select 0,4,'= money actually received on those invoices', received_total, null from totals
union all select 0,5,'(the reconciliation below turns that into the dashboard figure)', null, null

-- 1. The reconciliation
union all select 1 as section, 1 as ord, 'RECONCILIATION' as line, null::numeric as amount, null::text as note
union all select 1,2,'received on invoices dated in this period (all methods, all time)',
  counted_here + credit + other_period, null from totals
union all select 1,3,'  less paid by wallet credit (already sales when the credit was sold)', -credit, null from totals
union all select 1,4,'  less received outside this period (reported on the day it arrived)', -other_period, null from totals
union all select 1,5,'= receipts from these invoices counted in this period', counted_here, null from totals
union all select 1,6,'plus receipts in this period from invoices dated elsewhere',
  dashboard_sales - refunds - counted_here, null from totals
union all select 1,7,'less refunds recorded in this period', refunds, null from totals
union all select 1,8,'= DASHBOARD SALES', dashboard_sales, 'This must equal the dashboard figure' from totals

-- 2. Every invoice that differs, and why
union all select 2,1,'--- INVOICES THAT DIFFER ---', null, null
union all
select 2, 2, pi.invoice_no || '  (' || pi.status || ', ' || pi.invoice_day || ')',
       pi.total_amount,
       case
         when pi.counted_here = 0 and pi.paid_by_credit > 0 and pi.received_other_period = 0
           then 'Paid with wallet credit — counted as sales when the credit package was sold, not again here'
         when pi.received_other_period <> 0
           then 'S$' || pi.received_other_period || ' arrived outside this period and is reported on the day it arrived'
         when pi.counted_here = 0 and pi.paid_by_credit = 0 and pi.received_other_period = 0
           then 'No money received yet — an unpaid invoice is not sales'
         else 'Counted in full'
       end
  from per_invoice pi
 where pi.paid_by_credit <> 0 or pi.received_other_period <> 0 or pi.counted_here = 0

-- 2b. Invoices with money still outstanding, which sales correctly excludes.
union all select 2,3,'--- BILLED BUT NOT YET RECEIVED ---', null, null
union all
select 2, 4, pi.invoice_no || '  (' || pi.status || ', ' || pi.invoice_day || ')',
       round(pi.total_amount - (pi.counted_here + pi.paid_by_credit + pi.received_other_period),2),
       'Billed S$' || pi.total_amount || ', received S$'
         || (pi.counted_here + pi.paid_by_credit + pi.received_other_period)
         || ' — the remainder is not sales until it arrives'
  from per_invoice pi
 where round(pi.total_amount - (pi.counted_here + pi.paid_by_credit + pi.received_other_period),2) <> 0

-- 3. Anything the arithmetic cannot explain. Empty means nothing is broken.
union all select 3,1,'--- UNEXPLAINED (should be empty) ---', null, null
union all
select 3, 2, i.invoice_no, p.amount, 'Payment has no payment method, so it is neither cash nor credit'
  from public.invoice_payments p
  join public.invoices i on i.id = p.invoice_id
  left join public.payment_methods m on m.id = p.payment_method_id, params pr
 where m.id is null and i.deleted_at is null
   and (coalesce(p.effective_at,p.created_at) at time zone 'Asia/Singapore')::date between pr.from_date and pr.to_date
union all
select 3, 3, i.invoice_no, r.amount, 'Refund is not linked to a payment, so it is excluded from sales'
  from public.invoice_refunds r
  join public.invoices i on i.id = r.invoice_id, params pr
 where r.payment_id is null and i.deleted_at is null
   and (r.created_at at time zone 'Asia/Singapore')::date between pr.from_date and pr.to_date

order by section, ord, line;
