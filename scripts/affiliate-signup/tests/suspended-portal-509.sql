-- A suspended affiliate's portal shows a "suspended" notice and nothing else (509).
--
-- An affiliate whose link is proven sees their record. Once an Owner or Manager
-- suspends them, affiliate_portal_me says "suspended" and nothing else, every
-- other portal function refuses, and their details cannot be changed. Reactivated,
-- the portal is back as it was. A login whose account is not 'claimed' gets the
-- same notice. Suspension wins over an unproven link (508).
--
--   psql -X -v ON_ERROR_STOP=1 -d <disposable copy> -f scripts/affiliate-signup/tests/suspended-portal-509.sql
-- 508 and 509 are installed here when they are not in yet. Disposable local database
-- only; everything is rolled back. Made-up records only (P509, +61491570xxx, @example.com).
\set ON_ERROR_STOP on
begin;
-- 546 (security audit of 17 Nov 2026, L15): where it is in, its UNDO goes first, as this file pins
-- md5s of functions it changes (only their search path); this run only, rolled back with the rest.
select coalesce('search_path=public, pg_temp' = any (proconfig), false) as t546_in
  from pg_proc where oid = 'public.current_user_role()'::regprocedure \gset
\if :t546_in
select set_config('energia.undo546_skip_body_check', 'on', true) \g /dev/null
\ir ../../permissions/undo-546.sql
\endif
select to_regprocedure('public.affiliate_portal_record_id()') is not null as m508_in \gset
\if :m508_in
\else
\ir ../../../supabase/508_an_unproven_login_sees_nothing_of_the_record.sql
\endif
select md5(pg_get_functiondef('public.current_affiliate_customer_id()'::regprocedure)) = '4f552894d48ef799c071d4b95c37745d' as m509_in \gset
\if :m509_in
\else
\ir ../../../supabase/509_a_suspended_affiliate_portal_shows_nothing.sql
\endif
create function pg_temp.check(ok boolean, msg text) returns void language plpgsql as
$f$ begin if ok is distinct from true then raise exception 'FAIL: %', msg; end if; raise notice 'PASS  %', msg; end $f$;
-- the error a call raises, or null when it answers
create function pg_temp.err_of(p_sql text) returns text language plpgsql as
$f$ begin execute p_sql; return null; exception when others then return sqlerrm; end $f$;
create temp table p509(k text primary key, id uuid not null);
create function pg_temp.as_login(p_who text) returns void language plpgsql as $f$
declare v uuid := (select id from p509 where k = p_who);
begin
  perform set_config('request.jwt.claim.sub', v::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', v, 'role', 'authenticated')::text, true);
end $f$;
-- every portal read but "me", and the error each gives (null: it answered)
create function pg_temp.portal_errors() returns jsonb language sql as $f$
  select jsonb_object_agg(f, pg_temp.err_of('select public.' || f || '()'))
    from unnest(array['affiliate_portal_dashboard', 'affiliate_portal_earnings', 'affiliate_portal_payouts',
                      'affiliate_portal_purchases', 'affiliate_portal_network', 'affiliate_portal_campaign_progress',
                      'affiliate_portal_referral_info', 'affiliate_portal_details']) f
$f$;

do $$
declare own uuid := gen_random_uuid(); u1 uuid := gen_random_uuid(); u2 uuid := gen_random_uuid(); nobody uuid := gen_random_uuid();
        c2 uuid;
begin
  insert into auth.users(id, email, email_confirmed_at, raw_user_meta_data, raw_app_meta_data) values
    (own, 'p509-owner@example.com', now(), '{}', '{}'),
    (u1, 'p509-aff@example.com', now(), '{}', '{"affiliate_email_unverified": true}'),
    (u2, 'p509-other@example.com', now(), '{}', '{"affiliate_email_unverified": true}'),
    (nobody, 'p509-nobody@example.com', now(), '{}', '{}');
  insert into public.profiles(id, full_name, email, role, is_active) values (own, 'P509 Owner', 'p509-owner@example.com', 'owner', true);
  -- a customer who was there before, for the unproven case (created a month back: see 508's suite)
  insert into public.customers(full_name, phone, created_at)
    values ('Holda Recordwell', '+61491570192', now() - interval '30 days') returning id into c2;
  insert into p509 values ('own', own), ('u1', u1), ('u2', u2), ('nobody', nobody), ('c2', c2);
end $$;

-- 1. a sign-up with a new phone makes its own record: its link is proven (own_record)
select pg_temp.as_login('u1');
select public.complete_affiliate_onboarding('Ada', 'Portalson', '+61491570191', true) as joined \gset
insert into p509 values ('c1', (:'joined'::jsonb->>'customer_id')::uuid);
set local session_replication_role = replica;
insert into public.customers(full_name, phone, referred_by, referred_at)
  values ('P509 Friend', '+61491570193', (select id from p509 where k = 'c1'), now());
set local session_replication_role = origin;
select pg_temp.check((public.affiliate_portal_me()->>'link_proven') = 'true'
    and public.affiliate_portal_me()->>'status' = 'active'
    and jsonb_array_length(public.affiliate_portal_network()->'tier1') = 1,
  '1 an open, proven affiliate sees their record and the friend under them');
select pg_temp.check((select count(*) from jsonb_each(pg_temp.portal_errors()) e where e.value <> 'null'::jsonb) = 0,
  '1 every portal read answers: ' || pg_temp.portal_errors()::text);
select pg_temp.check(public.affiliate_detail_state((select id from p509 where k = 'u1'))->>'route' <> 'closed',
  '1 their details can be changed (route ' || (public.affiliate_detail_state((select id from p509 where k = 'u1'))->>'route') || ')');

-- 2. an Owner suspends them: "me" says suspended and nothing else; everything else refuses
select pg_temp.as_login('own');
select public.suspend_affiliate((select id from p509 where k = 'c1'), 'P509 check');
select pg_temp.as_login('u1');
select pg_temp.check(public.affiliate_portal_me() = '{"status": "suspended", "portal_closed": true}'::jsonb,
  '2 "me" says suspended and nothing else: ' || public.affiliate_portal_me()::text);
select pg_temp.check((select bool_and(e.value #>> '{}' = 'Not an affiliate account') from jsonb_each(pg_temp.portal_errors() - 'affiliate_portal_details') e),
  '2 dashboard, earnings, payouts, purchases, network, campaign progress and the referral code all refuse: ' || pg_temp.portal_errors()::text);
select pg_temp.check(pg_temp.portal_errors()->>'affiliate_portal_details' = 'This affiliate account is suspended.',
  '2 "details" refuses, so the record''s name, phone and email are not shown');
select pg_temp.check(public.affiliate_detail_state((select id from p509 where k = 'u1'))->>'route' = 'closed'
    and public.affiliate_detail_change_start((select id from p509 where k = 'u1'),
          jsonb_build_object('first_name', 'Adda'))->>'error' = 'not_allowed',
  '2 a change of their details is refused');
select pg_temp.check(public.current_affiliate_customer_id() is null and public.affiliate_portal_record_id() is null,
  '2 neither helper names the record');

-- 3. reactivated, the portal is back as it was
select pg_temp.as_login('own');
select public.reactivate_affiliate((select id from p509 where k = 'c1'));
select pg_temp.as_login('u1');
select pg_temp.check((public.affiliate_portal_me()->>'link_proven') = 'true'
    and jsonb_array_length(public.affiliate_portal_network()->'tier1') = 1
    and (select count(*) from jsonb_each(pg_temp.portal_errors()) e where e.value <> 'null'::jsonb) = 0,
  '3 reactivated: every portal read answers again, with the friend');

-- 4. an account that is not 'claimed' gets the same notice
update public.affiliate_accounts set status = 'disabled' where auth_user_id = (select id from p509 where k = 'u1');
select pg_temp.check(public.affiliate_portal_me() = '{"status": "suspended", "portal_closed": true}'::jsonb
    and (select bool_and(e.value <> 'null'::jsonb) from jsonb_each(pg_temp.portal_errors()) e),
  '4 a disabled account: "me" says suspended and every other read refuses');
update public.affiliate_accounts set status = 'claimed' where auth_user_id = (select id from p509 where k = 'u1');

-- 5. an unproven login (508) whose affiliate is suspended: suspended wins
select pg_temp.as_login('u2');
select public.complete_affiliate_onboarding('Otto', 'Elsewise', '+61491570192', true) as joined2 \gset
select pg_temp.check((:'joined2'::jsonb->>'customer_id')::uuid = (select id from p509 where k = 'c2')
    and (public.affiliate_portal_me()->>'link_proven') = 'false',
  '5 a login joined on the phone alone is not proven (508)');
select pg_temp.as_login('own');
select public.suspend_affiliate((select id from p509 where k = 'c2'), 'P509 check');
select pg_temp.as_login('u2');
select pg_temp.check(public.affiliate_portal_me() = '{"status": "suspended", "portal_closed": true}'::jsonb
    and pg_temp.portal_errors()->>'affiliate_portal_details' = 'This affiliate account is suspended.',
  '5 suspended, it gets the suspended notice, not the typed details');

-- 6. a login with no affiliate account is refused as before
select pg_temp.as_login('nobody');
select pg_temp.check(pg_temp.err_of('select public.affiliate_portal_me()') = 'Not an affiliate account',
  '6 a login with no affiliate account: "me" refuses as before');

-- 7. the helpers are not endpoints; the portal functions still are
select pg_temp.check(not has_function_privilege('authenticated', 'public.current_affiliate_customer_id()', 'execute')
    and not has_function_privilege('authenticated', 'public.affiliate_detail_state(uuid)', 'execute')
    and has_function_privilege('authenticated', 'public.affiliate_portal_me()', 'execute')
    and has_function_privilege('authenticated', 'public.affiliate_portal_details()', 'execute'),
  '7 the helpers are callable by no client role; me and details are, as before');
rollback;
