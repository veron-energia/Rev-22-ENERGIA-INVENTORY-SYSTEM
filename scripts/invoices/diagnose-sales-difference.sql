-- =====================================================================
-- WHY THE DASHBOARD SALES FIGURE DIFFERS FROM THE INVOICES
--
-- READ ONLY. Opens a read-only transaction, writes nothing, and is safe to run
-- against production with an approved connection. It outputs no customer
-- contact details — invoice number, store, status and amounts only.
--
--   psql -X -v ON_ERROR_STOP=1 -v from=2026-09-01 -v to=2026-09-30 \
--        -v actor=OWNER_PROFILE_UUID -f scripts/invoices/diagnose-sales-difference.sql
--
-- The dashboard and an invoice answer two different questions, and some of the
-- difference is deliberate. This separates the deliberate part from anything
-- that is actually wrong, so only the remainder needs investigating.
-- =====================================================================
begin isolation level repeatable read read only;
set local timezone='UTC';
select set_config('request.jwt.claim.sub', :'actor', true) as ignored \gset
set local role authenticated;

\echo ''
\echo '=== 1. The headline: dashboard sales for the period ==='
select public.sales_between(:'from'::date, :'to'::date, null) as dashboard_sales;

\echo ''
\echo '=== 2. Where every cent in that period comes from ==='
select event_kind,
       count(*)                      as rows,
       count(distinct invoice_id)    as invoices,
       round(sum(amount),2)          as amount
  from public.invoice_sales_ledger()
 where sales_date between :'from'::date and :'to'::date
 group by event_kind
 union all
select 'TOTAL', count(*), count(distinct invoice_id), round(sum(amount),2)
  from public.invoice_sales_ledger()
 where sales_date between :'from'::date and :'to'::date;

\echo ''
\echo '=== 3. Money on invoices dated in this period that is NOT in the figure ==='
\echo '    Each row explains itself. "wallet credit" and "received in another'
\echo '    period" are deliberate; anything else is worth investigating.'
with dated as (
  select i.id, i.invoice_no, i.store_id, i.status,
         public.invoice_effective_date(i.id) as invoice_day,
         i.total_amount
    from public.invoices i
   where i.deleted_at is null
     and public.user_has_store_access(i.store_id)
     and public.invoice_effective_date(i.id) between :'from'::date and :'to'::date
),
pay as (
  select d.id,
         round(coalesce(sum(case when m.is_wallet_credit
                                 then case when p.entry_kind='correction_reversal' then -p.amount else p.amount end
                                 else 0 end),0),2) as credit_funded,
         round(coalesce(sum(case when not coalesce(m.is_wallet_credit,false)
                                  and public.payment_sales_date(p.effective_at,p.created_at)
                                      not between :'from'::date and :'to'::date
                                 then case when p.entry_kind='correction_reversal' then -p.amount else p.amount end
                                 else 0 end),0),2) as received_other_period,
         round(coalesce(sum(case when not coalesce(m.is_wallet_credit,false)
                                  and public.payment_sales_date(p.effective_at,p.created_at)
                                      between :'from'::date and :'to'::date
                                 then case when p.entry_kind='correction_reversal' then -p.amount else p.amount end
                                 else 0 end),0),2) as counted_here
    from dated d
    left join public.invoice_payments p on p.invoice_id=d.id
    left join public.payment_methods m on m.id=p.payment_method_id
   group by d.id
)
select d.invoice_no, s.name as store, d.status, d.invoice_day,
       d.total_amount,
       p.counted_here            as in_dashboard,
       p.credit_funded           as paid_by_credit,
       p.received_other_period   as received_other_period,
       case
         when p.counted_here=0 and p.credit_funded>0 and p.received_other_period=0
           then 'Paid with wallet credit. Counted as sales when the credit package was sold, not again here.'
         when p.received_other_period<>0
           then 'Some money arrived outside this period and is reported on the day it arrived.'
         when p.counted_here=0 and p.credit_funded=0 and p.received_other_period=0
           then 'No money received yet. An unpaid invoice is not sales.'
         else 'Counted in full.'
       end as explanation
  from dated d join pay p on p.id=d.id
  left join public.stores s on s.id=d.store_id
 where p.credit_funded<>0 or p.received_other_period<>0 or p.counted_here=0
 order by d.invoice_day, d.invoice_no;

\echo ''
\echo '=== 4. The reconciliation, as one set of numbers ==='
with dated as (
  select i.id from public.invoices i
   where i.deleted_at is null and public.user_has_store_access(i.store_id)
     and public.invoice_effective_date(i.id) between :'from'::date and :'to'::date
),
parts as (
  select
    round(coalesce(sum(case when not coalesce(m.is_wallet_credit,false)
                       then case when p.entry_kind='correction_reversal' then -p.amount else p.amount end end),0),2) as cash_all_time,
    round(coalesce(sum(case when coalesce(m.is_wallet_credit,false)
                       then case when p.entry_kind='correction_reversal' then -p.amount else p.amount end end),0),2) as credit_all_time,
    round(coalesce(sum(case when not coalesce(m.is_wallet_credit,false)
                        and public.payment_sales_date(p.effective_at,p.created_at) between :'from'::date and :'to'::date
                       then case when p.entry_kind='correction_reversal' then -p.amount else p.amount end end),0),2) as cash_in_period
  from dated d left join public.invoice_payments p on p.invoice_id=d.id
  left join public.payment_methods m on m.id=p.payment_method_id
)
select 'received on invoices dated in this period (all methods, all time)' as line,
       cash_all_time+credit_all_time as amount from parts
union all select '  less paid by wallet credit (already sales when the credit was sold)', -credit_all_time from parts
union all select '  less received outside this period (reported on the day it arrived)', -(cash_all_time-cash_in_period) from parts
union all select '= receipts from these invoices counted in this period', cash_in_period from parts
union all select 'plus receipts in this period from invoices dated elsewhere',
  round(public.sales_between(:'from'::date,:'to'::date,null)
        - (select cash_in_period from parts)
        + coalesce((select round(sum(-amount),2) from public.invoice_sales_ledger()
                     where sales_date between :'from'::date and :'to'::date and event_kind='refund'),0),2)
union all select 'less refunds recorded in this period',
  coalesce((select round(sum(amount),2) from public.invoice_sales_ledger()
             where sales_date between :'from'::date and :'to'::date and event_kind='refund'),0)
union all select '= DASHBOARD SALES', public.sales_between(:'from'::date,:'to'::date,null);

\echo ''
\echo '=== 5. Anything genuinely unexplained ==='
\echo '    This should be empty. A row here is a real defect, not a basis difference.'
select p.id as payment_id, i.invoice_no, p.amount, p.entry_kind,
       public.payment_sales_date(p.effective_at,p.created_at) as counted_on,
       'Payment has no method, so it can be neither cash nor credit' as issue
  from public.invoice_payments p
  join public.invoices i on i.id=p.invoice_id
  left join public.payment_methods m on m.id=p.payment_method_id
 where m.id is null and i.deleted_at is null
   and public.payment_sales_date(p.effective_at,p.created_at) between :'from'::date and :'to'::date
union all
select r.id, i.invoice_no, r.amount, 'refund',
       (r.created_at at time zone 'Asia/Singapore')::date,
       'Refund has no linked payment, so it is excluded from sales'
  from public.invoice_refunds r join public.invoices i on i.id=r.invoice_id
 where r.payment_id is null and i.deleted_at is null
   and (r.created_at at time zone 'Asia/Singapore')::date between :'from'::date and :'to'::date;

rollback;
