-- 508 lists the logins already joined with an unproven link, once; 508 and 509
-- each leave everything alone when run again, in either order after both are in.
--
-- Needs a disposable copy WITHOUT 508 (production's functions at 502):
--   psql -X -v ON_ERROR_STOP=1 -d <disposable copy> -f scripts/affiliate-signup/tests/rerun-508-509.sql
-- Everything is rolled back. Made-up records only (P50R, +61491570xxx, @example.com).
\set ON_ERROR_STOP on
begin;
create function pg_temp.check(ok boolean, msg text) returns void language plpgsql as
$f$ begin if ok is distinct from true then raise exception 'FAIL: %', msg; end if; raise notice 'PASS  %', msg; end $f$;
select pg_temp.check(to_regprocedure('public.affiliate_portal_record_id()') is null,
  '0 this copy has no 508 yet (run on a copy of production at 502)');
create temp table p50r(k text primary key, id uuid not null);
create function pg_temp.fp() returns text language sql as $f$
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.oid::regprocedure::text)) || ' ' || count(*)
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.prokind in ('f', 'p')
$f$;

-- a login joined before 508 on the phone and the record's own name: not listed before 508
do $$
declare u uuid := gen_random_uuid(); c uuid;
begin
  insert into auth.users(id, email, email_confirmed_at, raw_user_meta_data, raw_app_meta_data)
    values (u, 'p50r-joined@example.com', now(), '{}', '{"affiliate_email_unverified": true}');
  insert into public.customers(full_name, phone, created_at)
    values ('Rerun Recordholder', '+61491570171', now() - interval '30 days') returning id into c;
  insert into p50r values ('u', u), ('c', c);
  perform set_config('request.jwt.claim.sub', u::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', u, 'role', 'authenticated')::text, true);
  perform public.complete_affiliate_onboarding('Rerun', 'Recordholder', '+61491570171', true);
end $$;
select pg_temp.check((select count(*) from public.affiliate_signup_matches where auth_user_id = (select id from p50r where k = 'u')) = 0,
  '1 before 508, a join under the record''s own name is not listed');

\ir ../../../supabase/508_an_unproven_login_sees_nothing_of_the_record.sql
select pg_temp.check((select count(*) from public.affiliate_signup_matches
                       where auth_user_id = (select id from p50r where k = 'u') and status = 'open'
                         and reason = 'phone_other_name' and fresh_customer_id = (select id from p50r where k = 'c')) = 1,
  '2 508 lists the login already joined with an unproven link, once');
-- the entry is closed some other way (here by hand); a re-run must not list it again
update public.affiliate_signup_matches set status = 'kept_separate', decided_at = now()
 where auth_user_id = (select id from p50r where k = 'u');
select pg_temp.fp() as fp_508 \gset

\ir ../../../supabase/508_an_unproven_login_sees_nothing_of_the_record.sql
select pg_temp.check(pg_temp.fp() = :'fp_508'
    and (select count(*) from public.affiliate_signup_matches where auth_user_id = (select id from p50r where k = 'u')) = 1,
  '3 508 run again changes no function and lists nobody again');

\ir ../../../supabase/509_a_suspended_affiliate_portal_shows_nothing.sql
select pg_temp.fp() as fp_509 \gset
select pg_temp.check(:'fp_509' <> :'fp_508', '4 509 changes the portal functions');
\ir ../../../supabase/509_a_suspended_affiliate_portal_shows_nothing.sql
\ir ../../../supabase/508_an_unproven_login_sees_nothing_of_the_record.sql
select pg_temp.check(pg_temp.fp() = :'fp_509'
    and (select count(*) from public.affiliate_signup_matches where auth_user_id = (select id from p50r where k = 'u')) = 1,
  '5 509 run again, then 508 run again after 509, leave everything alone');
\echo fingerprint after 508: :fp_508
\echo fingerprint after 509: :fp_509
rollback;
