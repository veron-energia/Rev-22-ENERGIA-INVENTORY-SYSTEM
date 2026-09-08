-- Run this in the Supabase SQL editor BEFORE applying migration 201.
-- It confirms the cause on your actual data rather than taking the diagnosis
-- on trust. Read-only: it changes nothing.

-- 1. Unpaid commission rows whose referrer the browser cannot see.
--    Any row here is one that shows as "—" on the Commissions page.
select
  to_char(c.invoice_paid_date, 'YYYY-MM')      as month,
  cu.full_name                                  as referrer_name,
  cu.phone,
  cu.deleted_at,
  count(*)                                      as rows,
  sum(c.commission_amount)                      as unpaid_amount
from public.commissions c
join public.customers cu on cu.id = c.referrer_customer_id
where c.status = 'earned'
  and cu.deleted_at is not null          -- hidden from the browser by RLS
group by 1, 2, 3, 4
order by 1 desc;

-- 2. Belt and braces: any earned commission whose referrer row is missing
--    outright. Should return nothing — the foreign key makes it impossible —
--    but if it does, the cause is something other than a soft delete.
select c.id, c.referrer_customer_id, c.commission_amount
from public.commissions c
left join public.customers cu on cu.id = c.referrer_customer_id
where c.status = 'earned' and cu.id is null;

-- 3. The reverse view: what the Referrers tab is silently omitting.
select cu.full_name, cu.deleted_at, sum(c.commission_amount) as unpaid
from public.commissions c
join public.customers cu on cu.id = c.referrer_customer_id
where c.status = 'earned' and cu.deleted_at is not null
group by 1, 2;
