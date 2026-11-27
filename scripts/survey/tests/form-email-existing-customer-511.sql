-- A form puts no email on a customer who was there before it (511).
--
-- Since 508 a portal login is shown its record only once its link is proven,
-- and one proof is that the login's verified email is the record's (484's
-- proof (d)). So the email a form's sender types must not become the email
-- of a customer who was there already. This shows, for a customer with no
-- email, no survey, no portal login and no affiliate record:
--
--   1  The QR health form, signed out, finds her by phone and name: her
--      record keeps no email and takes the other details; the form keeps the
--      email typed.
--   2  The route this closes: a login with that same email joins her on the
--      phone (437), verifies its own inbox, and is still not proven. The
--      portal shows it nothing of her record or of the friend under her.
--   3  An Owner's Same person still proves a link.
--   4  Someone new: the form makes the customer with the email typed, and a
--      login with that verified email is proven by it (as before).
--   5  Staff attaching a held QR form: the customer keeps no email and takes
--      the other details.
--   6  The event website's registration, as its server: the customer keeps
--      no email and takes the source the event names; an email already there
--      stays exactly as it is.
--   7  Staff linking a held registration: the same.
--   8  A customer's own email is never replaced.
--   9  A registration that makes a customer gives it the email typed (as
--      before).
--  10  Grants: the QR form stays a signed-out endpoint; the registration's
--      fill stays the server's.
--
--   sh scripts/invoices/local-sql.sh -f scripts/survey/tests/form-email-existing-customer-511.sql
-- 511 is installed here when it is not in yet. Disposable local database only;
-- everything is rolled back. Made-up records only (S511, +61 491 570 5xx,
-- @example.com).
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
select coalesce(position('511:' in (select prosrc from pg_proc
                                     where oid = to_regprocedure('public.event_web_fill_customer(uuid,uuid)'))) > 0, false) as m511_in \gset
\if :m511_in
\else
\ir ../../../supabase/511_a_form_puts_no_email_on_an_existing_customer.sql
\endif
set local lock_timeout = '10s';
set local statement_timeout = '120s';
create function pg_temp.check(ok boolean, msg text) returns void language plpgsql as
$f$ begin if ok is distinct from true then raise exception 'FAIL: %', msg; end if; raise notice 'PASS  %', msg; end $f$;
create temp table s511(k text primary key, id uuid not null);
create function pg_temp.id(p text) returns uuid language sql as $f$ select id from s511 where k = p $f$;
create temp table r511(k text primary key, v text);
create function pg_temp.r(p text) returns text language sql as $f$ select v from r511 where k = p $f$;
create function pg_temp.err(q text) returns text language plpgsql as
$f$ begin execute q; return 'ok'; exception when others then return sqlerrm; end $f$;
-- A portal login, as the browser sends it; from_link: the session was opened from an emailed link just now.
create function pg_temp.as_login(p_who text, p_from_link boolean default false) returns void language plpgsql as $f$
declare v uuid := pg_temp.id(p_who);
begin
  perform set_config('request.jwt.claim.sub', v::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform set_config('request.jwt.claims', (jsonb_build_object('sub', v, 'role', 'authenticated')
    || case when p_from_link then jsonb_build_object('amr', jsonb_build_array(jsonb_build_object('method', 'magiclink',
              'timestamp', extract(epoch from clock_timestamp())::bigint))) else '{}'::jsonb end)::text, true);
  -- 531 (security audit of 17 Nov 2026, M6): an emailed link no longer verifies an email; the
  -- affiliate types the code from the verify email. Where 531 is in, a session from the link is
  -- one that has typed that code, so the checks after it read the same.
  if p_from_link and to_regprocedure('public.confirm_affiliate_email_code(text)') is not null then
    perform public.confirm_affiliate_email_code(public.affiliate_email_code_issue(v)->>'code');
  end if;
end $f$;
create function pg_temp.as_server() returns void language sql as
$f$ select set_config('request.jwt.claim.sub', '', true), set_config('request.jwt.claim.role', '', true),
           set_config('request.jwt.claims', '', true) $f$;
-- The QR form as the public page sends it, signed out; the reply (or the error) under 'qr:<key>'.
create function pg_temp.qr(p_key text, p_first text, p_last text, p_phone text, p_email text) returns void language plpgsql as $f$
declare r jsonb; e text; src text := pg_temp.id('src')::text;   -- read before the role changes
begin
  begin
    perform set_config('request.jwt.claims', '{"role":"anon"}', true);
    execute 'set local role anon';
    r := public.submit_health_survey('s511-token', jsonb_build_object('first_name', p_first, 'last_name', p_last, 'phone', p_phone,
           'email', p_email, 'signature_data', 'data:image/png;base64,AAAA', 'source_option_id', src,
           'sex', 'female', 'date_of_birth', '1980-02-03', 'occupation', 'Tester'), null, null);
    execute 'reset role';
    perform set_config('request.jwt.claims', '', true);
  exception when others then e := sqlerrm;
  end;
  insert into r511 values ('qr:' || p_key, coalesce(r::text, 'ERROR: ' || e)) on conflict (k) do update set v = excluded.v;
end $f$;
create function pg_temp.form(p_key text) returns public.health_surveys language sql as
$f$ select s from public.health_surveys s where s.id = (pg_temp.r('qr:' || p_key)::jsonb ->> 'survey_id')::uuid $f$;
create function pg_temp.email(p_cust text) returns text language sql as
$f$ select email from public.customers where id = pg_temp.id(p_cust) $f$;
-- What a form fills besides the email.
create function pg_temp.rest(p_cust text) returns text language sql as
$f$ select concat_ws('|', occupation, date_of_birth, gender, source_option_id = pg_temp.id('src'))
      from public.customers where id = pg_temp.id(p_cust) $f$;
-- One person registering for the event on the website: a registration and its person row; the person's id under 'p:<key>'.
create function pg_temp.person(p_key text, p_first text, p_last text, p_phone text, p_email text, p_match text,
                               p_customer uuid, p_candidate uuid) returns void language plpgsql as $f$
declare r uuid; p uuid; h text := md5('s511' || p_key);
begin
  insert into public.event_registrations(event_id, registration_id, people_count, people_md5)
  values (pg_temp.id('ev'), 'REG-' || to_char(public.sg_today(), 'YYYYMMDD') || '-' || upper(substr(h, 1, 8)), 1, h)
  returning id into r;
  insert into public.event_registration_people(registration_ref, event_id, position, first_name, last_name, full_name, phone, phone_norm,
         days, match, upgrade_token, email, customer_id, hold_reason, candidate_customer_ids)
  values (r, pg_temp.id('ev'), 1, p_first, p_last, p_first || ' ' || p_last, p_phone, public.normalize_customer_phone(p_phone),
          array[public.sg_today()], p_match, 'vip_' || translate(substr(h || md5(h), 1, 26), '0189', 'wxyz'), p_email, p_customer,
          case when p_candidate is not null then 'phone_in_use' end,
          case when p_candidate is not null then array[p_candidate] else '{}'::uuid[] end)
  returning id into p;
  insert into s511 values ('p:' || p_key, p);
end $f$;

-- 524 (18 Nov 2026) changed submit_health_survey again (a form it refused waits for staff); 511's
-- rule stands in it, so its AFTER is accepted too. So is 530's (19 Nov 2026: limits, and a form for
-- an existing customer waits for staff, who attach it; the form itself fills nothing then).
create function pg_temp.m530() returns boolean language sql stable as
$f$ select position('-- 530 (security audit' in pg_get_functiondef('public.submit_health_survey(text,jsonb,jsonb,text)'::regprocedure)) > 0 $f$;
select pg_temp.check(md5(pg_get_functiondef('public.submit_health_survey(text,jsonb,jsonb,text)'::regprocedure))
                       in ('ddc02ed5fa82aacde5f031d6d367b300', 'a65183cdcb48f2dd883a47c1c7aad7f3', '6441159a66f5ca4424848710c90f2576')
    and md5(pg_get_functiondef('public.attach_held_health_survey(uuid,uuid,text)'::regprocedure)) = '55b632c7e9289cb267516a26af97387b'
    and md5(pg_get_functiondef('public.event_web_fill_customer(uuid,uuid)'::regprocedure)) = 'ca9957a62467c9f9ea574de86c8fd1bb',
  'P0 511 is installed (the three functions are its AFTER versions; submit_health_survey 511''s, 524''s or 530''s)');
select pg_temp.check(not exists (select 1 from public.customers
                                  where public.normalize_customer_phone(phone) between '+61491570510' and '+61491570529'),
  'P0 no customer uses the test phones +61 491 570 510 to 529 (the checks below assume so)');

-- Fixtures. The customers' created_at is a month back: a record made in the same transaction
-- as a login's account would count as the login's own (affiliate_login_link_proof, 'own_record').
do $$
declare own uuid := gen_random_uuid(); u1 uuid := gen_random_uuid(); u2 uuid := gen_random_uuid();
        c uuid; st uuid; x uuid;
begin
  insert into auth.users(id, email, email_confirmed_at, raw_user_meta_data, raw_app_meta_data) values
    (own, 's511-owner@example.com', now(), '{}', '{}'),
    (u1, 's511-other@example.com', now(), '{}', '{"affiliate_email_unverified": true}'),
    (u2, 's511-new@example.com', now(), '{}', '{"affiliate_email_unverified": true}');
  insert into public.profiles(id, full_name, email, role, is_active) values (own, 'S511 Owner', 's511-owner@example.com', 'owner', true);
  insert into s511 values ('own', own), ('u1', u1), ('u2', u2);
  insert into public.stores(name, code) values ('S511 Test Store', 'S511T') returning id into st; insert into s511 values ('store', st);
  insert into public.customer_source_options(label) values ('S511 Walk-in') returning id into x; insert into s511 values ('src', x);
  insert into public.customer_source_options(label) values ('S511 Event') returning id into x; insert into s511 values ('evsrc', x);
  insert into public.survey_links(token, store_id) values ('s511-token', st);
  insert into public.events(name) values ('S511 Event') returning id into x; insert into s511 values ('ev', x);
  insert into public.event_web_settings(event_id, code, store_id, acting_profile_id, source_option_id, source_details)
  values (pg_temp.id('ev'), 'S511-EV', st, own, pg_temp.id('evsrc'), 'S511 details');
  insert into public.event_stores(event_id, store_id) values (pg_temp.id('ev'), st);
  insert into public.customers(full_name, phone, created_at) values ('Vera Blankmail', '+61491570511', now() - interval '30 days')
    returning id into c; insert into s511 values ('vera', c);
  insert into public.customers(full_name, phone, created_at) values ('Hilda Heldform', '+61491570512', now() - interval '30 days')
    returning id into c; insert into s511 values ('hilda', c);
  insert into public.customers(full_name, phone, created_at) values ('Rita Registers', '+61491570513', now() - interval '30 days')
    returning id into c; insert into s511 values ('rita', c);
  insert into public.customers(full_name, phone, created_at) values ('Lena Linked', '+61491570514', now() - interval '30 days')
    returning id into c; insert into s511 values ('lena', c);
  insert into public.customers(full_name, phone, email, created_at)
    values ('Kora Keptmail', '+61491570515', 's511-kept@example.com', now() - interval '30 days')
    returning id into c; insert into s511 values ('kora', c);
  insert into public.customers(full_name, phone, email, created_at)
    values ('Sela Spaced', '+61491570516', ' s511-spaced@example.com ', now() - interval '30 days')
    returning id into c; insert into s511 values ('sela', c);
  -- a friend under Vera: what her portal would show
  set local session_replication_role = replica;
  insert into public.customers(full_name, phone, referred_by, referred_at)
    values ('S511 Friend', '+61491570517', pg_temp.id('vera'), now()) returning id into c;
  set local session_replication_role = origin;
  insert into s511 values ('friend', c);
end $$;

-- 1. the QR form, signed out, with her name and phone and an email of the sender's own
select pg_temp.qr('vera', 'Vera', 'Blankmail', '+61491570511', 's511-other@example.com');
select pg_temp.check(pg_temp.r('qr:vera') not like 'ERROR:%' and pg_temp.r('qr:vera')::jsonb -> 'success' = 'true',
  '1 the form goes through: ' || left(pg_temp.r('qr:vera'), 120));
-- 530: found by her phone and name, the form waits for staff with her (existing_customer) and
-- fills nothing; staff attach it (the server here), and the checks below are of that.
select pg_temp.check(not pg_temp.m530()
    or ((pg_temp.form('vera')).customer_id is null and pg_temp.email('vera') is null and pg_temp.rest('vera') = ''
        and exists (select 1 from public.health_survey_holds h where h.survey_id = (pg_temp.form('vera')).id
                      and h.reason = 'existing_customer' and h.candidate_customer_ids = array[pg_temp.id('vera')])),
  '1 (530) it waits for staff with her, and her record is as it was: ' || coalesce(pg_temp.rest('vera'), 'null'));
insert into r511 select 'attach_vera', pg_temp.err(format('select public.attach_held_health_survey(%L, %L, %L)',
    (pg_temp.form('vera')).id, pg_temp.id('vera'), 'S511 check: her phone and name')) where pg_temp.m530();
select pg_temp.check(pg_temp.email('vera') is null, '1 her record keeps no email');
select pg_temp.check(pg_temp.rest('vera') = 'Tester|1980-02-03|female|t',
  '1 it still takes the occupation, date of birth, sex and source (530: once staff attach it): ' || coalesce(pg_temp.rest('vera'), 'null'));
select pg_temp.check((pg_temp.form('vera')).email = 's511-other@example.com' and (pg_temp.form('vera')).customer_id = pg_temp.id('vera'),
  '1 the form keeps the email typed and is her survey (530: once staff attach it)');

-- 2. a login with that email joins her on the phone and verifies its own inbox
select pg_temp.as_login('u1');
select public.complete_affiliate_onboarding('Vera', 'Blankmail', '+61491570511', true) as joined \gset
select pg_temp.check((:'joined'::jsonb->>'customer_id')::uuid = pg_temp.id('vera') and (:'joined'::jsonb->>'new_customer') = 'false',
  '2 the sign-up still joins the customer who holds the phone, at once (437)');
select pg_temp.check((select count(*) from public.affiliate_signup_matches m
                       where m.auth_user_id = pg_temp.id('u1') and m.status = 'open' and m.fresh_customer_id = pg_temp.id('vera')) = 1,
  '2 the join is listed for an Owner or Manager (508)');
select pg_temp.as_login('u1', true);
select pg_temp.check((public.confirm_affiliate_email()->>'verified') = 'true', '2 the login verifies its own inbox');
select pg_temp.check(public.affiliate_login_link_proof(pg_temp.id('u1'), pg_temp.id('vera')) is null,
  '2 with its inbox verified the link is still not proven: her record has no email of the login''s');
select pg_temp.check(public.affiliate_portal_record_id() = '00000000-0000-0000-0000-000000000000'
    and (public.affiliate_portal_me()->>'link_proven') = 'false'
    and (public.affiliate_portal_me()->>'direct_referrals')::int = 0,
  '2 the portal''s record is the nil id; "me" says not proven and counts no referral');
select pg_temp.check(jsonb_array_length(public.affiliate_portal_network()->'tier1') = 0
    and public.affiliate_portal_network()::text not like '%S511 Friend%'
    and public.affiliate_portal_network()::text not like '%491570517%'
    and public.affiliate_portal_purchases() = '[]'::jsonb and public.affiliate_portal_payouts() = '[]'::jsonb,
  '2 the network, purchases and payouts come back empty: the friend under her is not shown');
select pg_temp.check((public.affiliate_portal_details()->>'link_proven') = 'false'
    and public.affiliate_portal_details()->>'route' = 'staff'
    and public.affiliate_portal_details()->>'email' = 's511-other@example.com',
  '2 "details" says not proven, gives the login''s own email, and sends a change of details to staff');

-- 3. an Owner's Same person still proves a link
select pg_temp.as_login('own');
select pg_temp.check((public.confirm_affiliate_signup_same_person(
    (select m.id from public.affiliate_signup_matches m where m.auth_user_id = pg_temp.id('u1') and m.status = 'open'),
    'S511 check: called her on the phone on file')->>'ok') = 'true', '3 an Owner says Same person');
select pg_temp.as_login('u1');
select pg_temp.check(public.affiliate_login_link_proof(pg_temp.id('u1'), pg_temp.id('vera')) = 'same_person'
    and public.affiliate_portal_record_id() = pg_temp.id('vera')
    and jsonb_array_length(public.affiliate_portal_network()->'tier1') = 1,
  '3 the link is proven by that decision, and the portal shows her record and the friend');
select pg_temp.as_server();

-- 4. someone new: the form makes the customer, with the email typed
select pg_temp.qr('new', 'Nell', 'Newcomer', '+61491570520', 's511-new@example.com');
select pg_temp.check((select c.email = 's511-new@example.com' and c.full_name = 'Nell Newcomer'
                        from public.customers c where c.id = (pg_temp.form('new')).customer_id),
  '4 someone new: the form makes a customer with the email typed (as before)');
insert into s511 select 'nell', (pg_temp.form('new')).customer_id;
update public.customers set created_at = now() - interval '30 days' where id = pg_temp.id('nell');
select pg_temp.as_login('u2');
select public.complete_affiliate_onboarding('Nell', 'Newcomer', '+61491570520', true) as joined2 \gset
select pg_temp.check((:'joined2'::jsonb->>'customer_id')::uuid = pg_temp.id('nell'), '4 a login with that email joins the customer the form made');
select pg_temp.as_login('u2', true);
select pg_temp.check((public.confirm_affiliate_email()->>'verified') = 'true', '4 it verifies its own inbox');
select pg_temp.check(public.affiliate_login_link_proof(pg_temp.id('u2'), pg_temp.id('nell')) = 'verified_email',
  '4 and is proven by the email, which came with the customer that form made (as before)');
select pg_temp.as_server();

-- 5. staff attach a held QR form (another name on Hilda's phone)
select pg_temp.qr('held', 'Otha', 'Name', '+61491570512', 's511-heldform@example.com');
select pg_temp.check(pg_temp.r('qr:held') not like 'ERROR:%' and (pg_temp.form('held')).customer_id is null
    and exists (select 1 from public.health_survey_holds h where h.survey_id = (pg_temp.form('held')).id and h.resolved_at is null),
  '5 a form under another name on her phone waits for staff: ' || left(pg_temp.r('qr:held'), 120));
select pg_temp.as_login('own');
insert into r511 select 'attach', pg_temp.err(format('select public.attach_held_health_survey(%L, %L, %L)',
    (pg_temp.form('held')).id, pg_temp.id('hilda'), 'S511 check: saw her card at the counter'));
select pg_temp.as_server();
select pg_temp.check(pg_temp.r('attach') = 'ok' and pg_temp.email('hilda') is null and pg_temp.rest('hilda') = 'Tester|1980-02-03|female|t',
  '5 staff attaching it leave her email empty and fill her other details: ' || pg_temp.r('attach'));
select pg_temp.check((pg_temp.form('held')).email = 's511-heldform@example.com' and (pg_temp.form('held')).customer_id = pg_temp.id('hilda'),
  '5 the form keeps the email typed and is now her survey');

-- 6. the event website's registration, as its server (the fill it calls for a customer it matched)
select pg_temp.person('rita', 'Rita', 'Registers', '+61491570513', ' s511-reg@example.com ', 'exact', pg_temp.id('rita'), null);
select public.event_web_fill_customer(pg_temp.id('rita'), pg_temp.id('p:rita'));
select pg_temp.check(pg_temp.email('rita') is null
    and (select c.source_option_id = pg_temp.id('evsrc') and c.source_details = 'S511 details' from public.customers c where c.id = pg_temp.id('rita')),
  '6 a registration leaves her email empty and still fills the source the event names');
select pg_temp.check((select email from public.event_registration_people where id = pg_temp.id('p:rita')) = ' s511-reg@example.com ',
  '6 the registration keeps the email typed');
select pg_temp.person('sela', 'Sela', 'Spaced', '+61491570516', 's511-reg2@example.com', 'exact', pg_temp.id('sela'), null);
select public.event_web_fill_customer(pg_temp.id('sela'), pg_temp.id('p:sela'));
select pg_temp.check(pg_temp.email('sela') = ' s511-spaced@example.com '
    and (select source_option_id from public.customers where id = pg_temp.id('sela')) = pg_temp.id('evsrc'),
  '6 an email already there stays exactly as it is (not replaced, not trimmed) when the source is filled');

-- 7. staff link a held registration (another name on Lena's phone)
select pg_temp.person('lena', 'Otha', 'Name', '+61491570514', 's511-link@example.com', 'held', null, pg_temp.id('lena'));
select pg_temp.as_login('own');
insert into r511 select 'link', pg_temp.err(format('select public.event_registration_attach(%L, %L, %L)',
    pg_temp.id('p:lena'), pg_temp.id('lena'), 'S511 check: called her'));
select pg_temp.as_server();
select pg_temp.check(pg_temp.r('link') = 'ok' and pg_temp.email('lena') is null
    and (select source_option_id from public.customers where id = pg_temp.id('lena')) = pg_temp.id('evsrc'),
  '7 staff linking a held registration leave her email empty and still fill the source: ' || pg_temp.r('link'));
select pg_temp.check((select email from public.event_registration_people where id = pg_temp.id('p:lena')) = 's511-link@example.com',
  '7 the held registration keeps the email typed');

-- 8. a customer's own email is never replaced
select pg_temp.qr('kora', 'Kora', 'Keptmail', '+61491570515', 's511-kora-other@example.com');
select pg_temp.check(pg_temp.r('qr:kora') not like 'ERROR:%' and pg_temp.email('kora') = 's511-kept@example.com',
  '8 a customer''s own email stays after a form with another one');

-- 9. a registration that makes a customer gives it the email typed (the website's server acts as
--    the profile the event's settings name, as event_web_call sets it)
select pg_temp.person('nora', 'Nora', 'Newreg', '+61491570521', 's511-newreg@example.com', 'new_customer', null, null);
select pg_temp.as_login('own');
select public.event_web_new_customer(pg_temp.id('p:nora')) as made \gset
select pg_temp.as_server();
select pg_temp.check((select c.email = 's511-newreg@example.com' and c.full_name = 'Nora Newreg'
                        from public.customers c where c.id = (:'made'::jsonb->>'customer_id')::uuid),
  '9 a registration that makes a customer gives it the email typed (as before)');

-- 10. grants
select pg_temp.check(has_function_privilege('anon', 'public.submit_health_survey(text,jsonb,jsonb,text)', 'execute')
    and not has_function_privilege('anon', 'public.event_web_fill_customer(uuid,uuid)', 'execute')
    and not has_function_privilege('authenticated', 'public.event_web_fill_customer(uuid,uuid)', 'execute')
    and not has_function_privilege('anon', 'public.attach_held_health_survey(uuid,uuid,text)', 'execute')
    and has_function_privilege('authenticated', 'public.attach_held_health_survey(uuid,uuid,text)', 'execute'),
  '10 the QR form stays a signed-out endpoint, the registration''s fill the server''s, attaching a signed-in one');
rollback;
