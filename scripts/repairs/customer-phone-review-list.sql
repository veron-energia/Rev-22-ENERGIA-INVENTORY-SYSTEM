-- CUSTOMERS-17: the review list of phone numbers the Owner confirms (the
-- Owner, 9 Oct 2026, Q8 A, part d).
--
-- Read only. One row per live customer whose number cannot be used as it
-- is: an eight-digit number that could be Singapore or Malaysia, a "+"
-- number of the wrong length, or a number too short (the 7,835 LEGACY-*
-- placeholders are expected and left out). On 9 Oct 2026: 46 + 80 + 1 = 127.
--
-- It names each customer by their customer number (CUST-… in the notes) or,
-- when they have none, by their record id, never by name or phone: the Owner
-- looks the customer up in the app. The answers go back in through
-- apply_customer_phone_review (see scripts/repairs/customer-phones-singapore.sql).
-- Save the result outside the repository; it is not to be committed.

with live as (
  select c.id, c.phone, c.notes, c.created_at,
         public.inspect_customer_phone(c.phone) as inspection
    from public.customers c
   where c.deleted_at is null and c.phone not like 'LEGACY-%'
)
select coalesce((regexp_match(l.notes, 'CUST-\d+', 'i'))[1], 'id:' || l.id::text) as customer_ref,
       case when l.phone ~ '^[0-9]{8}$' then 'eight digits: Singapore or Malaysia?'
            when l.phone like '+%' then 'number of the wrong length'
            else 'number too short or not a phone number' end as what_to_confirm,
       l.inspection->>'reason' as review_note,
       length(regexp_replace(l.phone, '[^0-9]', '', 'g')) as digits,
       (select count(*) from public.invoices i where i.customer_id = l.id and i.deleted_at is null) as invoices,
       (select max(i.business_date) from public.invoices i where i.customer_id = l.id and i.deleted_at is null) as last_invoice,
       (l.created_at at time zone 'Asia/Singapore')::date as created_on
  from live l
 where l.inspection->>'status' = 'pending_review'
 order by 2, 1;
