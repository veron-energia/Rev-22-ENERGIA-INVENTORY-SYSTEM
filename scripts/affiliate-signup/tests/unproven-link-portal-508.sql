-- A login whose link to a customer is not proven sees nothing of that record (508).
--
-- Sign-up still joins the customer who holds the typed phone at once (437).
-- This shows what such a login gets from the portal before and after an Owner
-- says Same person, and that a join under the record's own name is listed for
-- staff as well.
--
--   sh scripts/invoices/local-sql.sh -f scripts/affiliate-signup/tests/unproven-link-portal-508.sql
-- 508 is installed here when it is not in yet. Disposable local database only;
-- everything is rolled back. Made-up records only (P508, @example.com).
\set ON_ERROR_STOP on
begin;
select to_regprocedure('public.affiliate_portal_record_id()') is not null as m508_in \gset
\if :m508_in
\else
\ir ../../../supabase/508_an_unproven_login_sees_nothing_of_the_record.sql
\endif
create function pg_temp.check(ok boolean, msg text) returns void language plpgsql as
$f$ begin if ok is distinct from true then raise exception 'FAIL: %', msg; end if; raise notice 'PASS  %', msg; end $f$;
create temp table p508(k text primary key, id uuid not null);
create function pg_temp.as_login(p_who text) returns void language plpgsql as $f$
declare v uuid := (select id from p508 where k = p_who);
begin
  perform set_config('request.jwt.claim.sub', v::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', v, 'role', 'authenticated')::text, true);
end $f$;

do $$
declare own uuid := gen_random_uuid(); u1 uuid := gen_random_uuid(); u2 uuid := gen_random_uuid();
        c1 uuid; c2 uuid; friend uuid;
begin
  insert into auth.users(id, email, email_confirmed_at, raw_user_meta_data, raw_app_meta_data) values
    (own, 'p508-owner@example.com', now(), '{}', '{}'),
    (u1, 'p508-other@example.com', now(), '{}', '{"affiliate_email_unverified": true}'),
    (u2, 'p508-same@example.com', now(), '{}', '{"affiliate_email_unverified": true}');
  insert into public.profiles(id, full_name, email, role, is_active) values (own, 'P508 Owner', 'p508-owner@example.com', 'owner', true);
  -- two customers who were there before, each with a phone of their own; the first has a friend under them.
  -- Their created_at is set a month back: a record made in the same transaction as the login's account
  -- would count as the login's own (affiliate_login_link_proof, 'own_record').
  insert into public.customers(full_name, phone, email, created_at)
    values ('Recorda Holderly', '+61491570181', 'p508-record@example.com', now() - interval '30 days') returning id into c1;
  insert into public.customers(full_name, phone, created_at)
    values ('Samena Nameford', '+61491570182', now() - interval '30 days') returning id into c2;
  set local session_replication_role = replica;
  insert into public.customers(full_name, phone, referred_by, referred_at) values ('P508 Friend', '+61491570183', c1, now()) returning id into friend;
  set local session_replication_role = origin;
  insert into p508 values ('own', own), ('u1', u1), ('u2', u2), ('c1', c1), ('c2', c2), ('friend', friend);
end $$;

-- 1. a login joins the first customer on the phone alone, under another name
select pg_temp.as_login('u1');
select public.complete_affiliate_onboarding('Otto', 'Typedname', '+61491570181', true) as joined \gset
select pg_temp.check((:'joined'::jsonb->>'customer_id')::uuid = (select id from p508 where k = 'c1') and (:'joined'::jsonb->>'new_customer') = 'false',
  '1 the sign-up still joins the customer who holds the phone, at once (437): ' || :'joined');
select pg_temp.check(public.affiliate_portal_record_id() = '00000000-0000-0000-0000-000000000000',
  '1 its link is not proven: the portal''s record is the nil id');
select pg_temp.check((public.affiliate_portal_me()->>'link_proven') = 'false'
    and public.affiliate_portal_me()->>'name' = 'Otto Typedname'
    and (public.affiliate_portal_me()->>'direct_referrals')::int = 0,
  '1 "me" gives the name the login typed, no referral count, link_proven false: ' || public.affiliate_portal_me()::text);
select pg_temp.check(public.affiliate_portal_details()->>'first_name' = 'Otto'
    and public.affiliate_portal_details()->>'email' is distinct from 'p508-record@example.com'
    and public.affiliate_portal_details()::text not like '%Recorda%'
    and (public.affiliate_portal_details()->>'link_proven') = 'false',
  '1 "details" gives what the login typed, not the record''s name or email');
select pg_temp.check(public.affiliate_portal_me()->>'email' = 'p508-other@example.com'
    and public.affiliate_portal_me()->>'joined_at' is null,
  '1 "me" gives the login''s own email, and not the date the record became an affiliate');
select pg_temp.check((public.affiliate_portal_referral_info()->>'direct_referrals')::int = 0
    and public.affiliate_portal_referral_info()->>'referral_code' is not null,
  '1 the referral code is still given, but no count of the record''s referrals');
select pg_temp.check(jsonb_array_length(public.affiliate_portal_network()->'tier1') = 0
    and (public.affiliate_portal_dashboard()->'network'->>'total')::int = 0
    and public.affiliate_portal_purchases() = '[]'::jsonb and public.affiliate_portal_payouts() = '[]'::jsonb
    and public.affiliate_portal_network()::text not like '%P508 Friend%',
  '1 network, dashboard, purchases and payouts come back empty; the friend under the record is not shown');
select pg_temp.check(public.affiliate_portal_earnings() ? 'summary' and public.affiliate_portal_campaign_progress() ? 'campaign',
  '1 earnings and campaign progress still answer in their usual shape');
select pg_temp.check((select count(*) from public.affiliate_signup_matches m
                       where m.auth_user_id = (select id from p508 where k = 'u1') and m.status = 'open'
                         and m.reason = 'phone_other_name' and m.fresh_customer_id = (select id from p508 where k = 'c1')) = 1,
  '1 the join is listed for an Owner or Manager');

-- 2. an Owner says Same person: the login now sees the record
select pg_temp.as_login('own');
select pg_temp.check((public.confirm_affiliate_signup_same_person(
    (select m.id from public.affiliate_signup_matches m where m.auth_user_id = (select id from p508 where k = 'u1') and m.status = 'open'),
    'P508 check: confirmed by phone')->>'ok') = 'true', '2 an Owner says Same person');
select pg_temp.as_login('u1');
select pg_temp.check(public.affiliate_portal_record_id() = (select id from p508 where k = 'c1')
    and (public.affiliate_portal_me()->>'link_proven') = 'true'
    and public.affiliate_portal_me()->>'name' = 'Recorda Holderly'
    and (public.affiliate_portal_me()->>'direct_referrals')::int = 1,
  '2 the link is proven: "me" gives the record''s name and its one referral');
select pg_temp.check(jsonb_array_length(public.affiliate_portal_network()->'tier1') = 1
    and public.affiliate_portal_details()->>'first_name' is distinct from 'Otto'
    and (public.affiliate_portal_details()->>'link_proven') = 'true',
  '2 the network shows the friend, and "details" the record''s own');
select pg_temp.check((public.affiliate_portal_referral_info()->>'direct_referrals')::int = 1
    and public.affiliate_portal_me()->>'joined_at' is not null,
  '2 the referral count and the date it became an affiliate are given once proven');

-- 3. a login that joins under the record's own name is listed too (before 508 it was not)
select pg_temp.as_login('u2');
select public.complete_affiliate_onboarding('Samena', 'Nameford', '+61491570182', true) as joined2 \gset
select pg_temp.check((:'joined2'::jsonb->>'customer_id')::uuid = (select id from p508 where k = 'c2'),
  '3 a sign-up under the record''s own name joins it at once');
select pg_temp.check((public.affiliate_portal_me()->>'link_proven') = 'false'
    and (select count(*) from public.affiliate_signup_matches m
          where m.auth_user_id = (select id from p508 where k = 'u2') and m.status = 'open' and m.reason = 'phone_other_name') = 1,
  '3 its link is not proven either, and it is listed for an Owner or Manager');

-- 4. the helper is not an endpoint
select pg_temp.check(not has_function_privilege('anon', 'public.affiliate_portal_record_id()', 'execute')
    and not has_function_privilege('authenticated', 'public.affiliate_portal_record_id()', 'execute'),
  '4 affiliate_portal_record_id() is callable by no client role');
rollback;
