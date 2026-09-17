-- WHAT 327 WOULD RELEASE ON INVOICES THAT ARE ALREADY PART PAID
--
-- 327 releases paid credit when a payment is recorded. It does nothing to money
-- that was received before it was installed, so a customer who paid S$1,000
-- toward a S$5,000 package last year still holds nothing until their next
-- payment — at which point the whole S$1,000 appears at once.
--
-- This script CHANGES NOTHING. It is a SELECT. Run it first, read it, and only
-- then decide whether and how far back to apply backfill-apply.sql.
--
-- Safe to run against production.

\pset pager off
\echo ''
\echo '=== Invoices that would release credit, oldest first ==='

with candidate as (
  select
    i.id                as invoice_id,
    i.invoice_no,
    i.status::text      as status,
    i.business_date,
    i.created_at,
    c.full_name         as customer,
    s.name              as store,
    it.id               as invoice_item_id,
    cp.name             as package,
    i.total_amount,
    i.paid_amount,
    coalesce(it.credit_paid_snapshot, cp.paid_credit_amount, 0) as entitled,
    public.credit_package_money_toward_line(it.id)   as money_toward_line,
    public.credit_package_released_paid_credit(it.id) as already_released
  from public.invoices i
  join public.invoice_items it on it.invoice_id = i.id and it.line_kind = 'credit_package'
  join public.credit_packages cp on cp.id = it.credit_package_id
  join public.customers c on c.id = i.customer_id
  join public.stores s on s.id = i.store_id
  where i.deleted_at is null
    -- The same conditions release_credit_package_paid_credit applies.
    and i.status not in ('cancelled','refunded','draft')
    and it.credit_issued_at is null
    and it.credit_split_allocation_id is null
    and not exists (select 1 from public.invoice_credit_splits x where x.invoice_item_id = it.id)
    and coalesce(i.paid_amount,0) > 0
), sized as (
  select *,
    round(least(money_toward_line, entitled) - already_released, 2) as would_release
  from candidate
)
select
  invoice_no,
  status,
  customer,
  store,
  package,
  to_char(coalesce(business_date, created_at::date), 'YYYY-MM-DD') as invoice_date,
  (current_date - coalesce(business_date, created_at::date))       as days_old,
  total_amount,
  paid_amount,
  entitled,
  already_released,
  would_release
from sized
where would_release > 0
order by coalesce(business_date, created_at::date), invoice_no;

\echo ''
\echo '=== Totals, by how old the invoice is ==='

with candidate as (
  select i.id, i.status::text as status, i.business_date, i.created_at, it.id as item_id,
    coalesce(it.credit_paid_snapshot, cp.paid_credit_amount, 0) as entitled,
    public.credit_package_money_toward_line(it.id)   as money_toward_line,
    public.credit_package_released_paid_credit(it.id) as already_released
  from public.invoices i
  join public.invoice_items it on it.invoice_id = i.id and it.line_kind = 'credit_package'
  join public.credit_packages cp on cp.id = it.credit_package_id
  where i.deleted_at is null
    and i.status not in ('cancelled','refunded','draft')
    and it.credit_issued_at is null
    and it.credit_split_allocation_id is null
    and not exists (select 1 from public.invoice_credit_splits x where x.invoice_item_id = it.id)
    and coalesce(i.paid_amount,0) > 0
), sized as (
  select *, round(least(money_toward_line, entitled) - already_released, 2) as would_release,
    (current_date - coalesce(business_date, created_at::date)) as days_old
  from candidate
)
select
  case when days_old <=  90 then 'a. 0-90 days'
       when days_old <= 180 then 'b. 91-180 days'
       when days_old <= 365 then 'c. 181-365 days'
       else                      'd. over a year' end as age,
  count(*)                        as invoices,
  sum(would_release)              as credit_that_would_be_released
from sized
where would_release > 0
group by 1 order by 1;

\echo ''
\echo 'Nothing above has been changed. backfill-apply.sql is what applies it.'
\echo ''
