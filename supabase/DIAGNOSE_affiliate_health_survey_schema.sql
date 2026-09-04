-- =====================================================================
-- DIAGNOSE_affiliate_health_survey_schema.sql   (READ ONLY)
--
-- Run in Supabase SQL editor to inspect the affiliate / referral / customer /
-- health-survey surface against the REAL deployed schema. Every statement is a
-- SELECT — it changes nothing. Use it to confirm migration 158 landed and to
-- surface any data that needs manual (staff) attention.
-- =====================================================================

-- A. customers columns (confirm updated_at exists, NOT NULL, default now())
select column_name, data_type, column_default, is_nullable
from information_schema.columns
where table_schema='public' and table_name='customers'
order by ordinal_position;

-- B. customers triggers (confirm the updated_at stamp is attached)
select tgname, pg_get_triggerdef(oid) as def
from pg_trigger where tgrelid='public.customers'::regclass and not tgisinternal;

-- C. customers indexes
select indexname, indexdef from pg_indexes where schemaname='public' and tablename='customers';

-- D. active definitions of the RPCs touched by the recent work
select p.proname, pg_get_functiondef(p.oid) as definition
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and p.proname in (
  'submit_health_survey','reassign_customer_referrer','complete_affiliate_onboarding',
  'resolve_affiliate_account_claim','reject_affiliate_account_claim','delete_affiliate_account_claim',
  'affiliate_pending_claims','affiliate_rejected_claims','affiliate_referral_signup',
  'normalize_customer_phone','customer_phone_collisions','set_updated_at')
order by p.proname;

-- E. customers whose phones normalize to the same canonical value (would-be dupes)
select public.normalize_customer_phone(phone) as canonical_phone,
       count(*) as n, array_agg(id order by created_at) as customer_ids,
       array_agg(full_name order by created_at) as names
from public.customers
where deleted_at is null and public.normalize_customer_phone(phone) is not null
group by 1 having count(*) > 1
order by n desc;

-- F. customers whose referred_by points to a missing or soft-deleted customer
select c.id, c.full_name, c.referred_by
from public.customers c
left join public.customers r on r.id = c.referred_by
where c.referred_by is not null and (r.id is null or r.deleted_at is not null);

-- G. referral cycles (walk up to 10 hops; any row returned is a cycle)
with recursive chain(start_id, cur_id, depth, seen) as (
  select id, referred_by, 1, array[id] from public.customers where referred_by is not null
  union all
  select ch.start_id, c.referred_by, ch.depth+1, ch.seen || c.id
  from chain ch join public.customers c on c.id = ch.cur_id
  where ch.cur_id is not null and ch.depth < 10 and not (c.id = any(ch.seen))
)
select distinct start_id from chain where cur_id = start_id;

-- H. affiliate_accounts with missing customer / affiliate references
select a.id, a.auth_user_id, a.customer_id, a.affiliate_id
from public.affiliate_accounts a
left join public.customers c on c.id = a.customer_id
left join public.customer_affiliates ca on ca.id = a.affiliate_id
where c.id is null or (a.affiliate_id is not null and ca.id is null);

-- I. duplicate PENDING affiliate account claims (should be none after mig 156)
select auth_user_id, count(*) as pending_count
from public.affiliate_account_claims where status='pending'
group by auth_user_id having count(*) > 1;

-- J. health surveys with a broken / missing customer link
select h.id, h.survey_no, h.customer_id
from public.health_surveys h
left join public.customers c on c.id = h.customer_id
where h.customer_id is null or c.id is null;

-- K. health surveys whose stored phone doesn't normalize-match its linked customer
select h.id, h.survey_no, h.phone as survey_phone, c.phone as customer_phone
from public.health_surveys h join public.customers c on c.id = h.customer_id
where public.normalize_customer_phone(h.phone) is distinct from public.normalize_customer_phone(c.phone);

-- L. any function body still referencing a legacy/obsolete customers column name
--    (customers has full_name, NOT first_name/last_name at table level)
select p.proname
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public'
  and pg_get_functiondef(p.oid) ~* '\mcustomers\M'
  and pg_get_functiondef(p.oid) ~* '(new|old|c)\.(first_name|last_name)\M'
order by p.proname;
