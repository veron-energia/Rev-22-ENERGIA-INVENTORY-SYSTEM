-- A self match on /r/<code> gets a vaguer answer and is counted by the
-- sign-up limits (442; the Owner, 21 Oct 2026: "Go live now, fix it next").
--
--   A  The answer: a sign-up that is the referrer herself (her record, her
--      login's sign-up name, phone or email inbox, as 440 has it) is told
--      exactly what someone already registered is told: the full JSON is the
--      same as a real "already registered" (someone else on file, through
--      the same link and through another), word for word, and nothing in it
--      (or in the function) says "yourself". A referrer with no login: the
--      same.
--   W  What is written: one event per try, 'self' where a new customer would
--      have been made, 'self_known' on details already on file (her record)
--      (the code as the link reads it, her record as the referrer, the phone
--      typed, no customer); no customer, no check, nobody referred.
--   N  Never a referral: her portal (dashboard, network, me, campaign
--      progress, referral info), the staff views (directory, admin
--      directory, referrer list, downline, downline visits, profile stats),
--      the promotion report and its friends, and the pending checks are the
--      same before and after her tries; the only functions that read
--      referral_signup_events are 442's and 436's two event-website
--      functions, which never name 'self' or 'self_known' (the website's
--      per-link count reads 'created' and 'phone_shared' only).
--   S  Staff see it, the caller does not: an Audit Log entry on her record
--      per try (the event, what matched, the phone, name and email typed,
--      the code),
--      whoever calls: signed out ("System"), signed in as her own login
--      (write_audit_ex would fail there: her login is no member of staff),
--      or a Manager at the counter (named); a Manager finds it on the Audit
--      Log page (audit_log_page); Owners and Managers read the 'self'
--      events, staff, her own login and the anon key read none, nor the
--      Audit Log.
--   L  The limits now count self tries: three tries on one phone in ten
--      minutes refuse the fourth, a self try or a genuine sign-up on that
--      phone, with the very answer a sign-up gets ("Too many ..."), writing
--      nothing; older tries do not count. Someone else already registered
--      on that phone is still told "already registered" (never limited, as
--      before). Twenty self tries through one link in an hour (or self tries
--      and new customers together) refuse the next new friend, and the next
--      self try, with the link's answer, and a 'link_limit' event; another
--      link still registers; older tries do not count. At the link's limit,
--      details on file with her login's email and with another email get
--      the same "already registered" (never limited), and neither counts.
--   D  Details on file (the review of 21 Oct 2026): someone on file typed
--      with her login's email, and with another email, past the phone's
--      three tries: each the same "already registered" (never limited, as
--      anyone on file), 'self_known' with its entry for hers, 'duplicate'
--      for the other; her own record past its phone's three tries: the same;
--      the link's count is untouched.
--   C  A phone 3 customers have (the review): her login's email, her login's
--      name and other guesses under names not on file there all get the
--      very CUSTOMER_PHONE_LIMIT error, however many, writing nothing (no
--      event, no entry); someone on file there with her email: "already
--      registered", 'self_known'.
--   X  What 442 still tells (its NOT COVERED, first item): on details nobody
--      has on file, her login's email is "already registered" and another
--      email is registered (a customer referred by her); both count in the
--      link's limit.
--   G  A genuine referral is unchanged: a new friend (the exact answer, with
--      the referrer's label), someone on her record's phone under another
--      name (425's check), someone already registered, a link that is not
--      accepting, the honeypot.
--   M  442 installs (from 440's AFTER), a second run changes nothing, its
--      self-test leaves no row, the grants are as they were; it refuses an
--      unknown version of the function and, while an affiliate login has no
--      sign-up copy, refuses to patch; 440 cannot be run after it.
--
-- Disposable database only; everything is rolled back. Needs 440 (and what
-- it needs) as production has it. Run from the repository root:
--   psql -X -v ON_ERROR_STOP=1 -f scripts/affiliate-signup/tests/referral-self-442.sql
-- (with -v nomig=1 on a database where 442 is applied, to skip installing it;
-- M's refusals then need 442's BEFORE text, which only the install has, and
-- are skipped with a note).
-- Every name, phone and email below is invented: ACMA fictional mobile
-- numbers (+61491570600..+61491570729) and @example.com addresses.
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '10s';
set local statement_timeout = '300s';

create temp table failed(n serial, msg text);
create function pg_temp.check(ok boolean, msg text) returns void language plpgsql as
$$begin
  if ok is distinct from true then insert into failed(msg) values (msg); raise notice 'FAIL  %', msg;
  else raise notice 'PASS  %', msg; end if;
end$$;
create temp table fx(k text primary key, v uuid);
create function pg_temp.fx(key text) returns uuid language sql as $$ select v from fx where k = key $$;
create temp table tx(k text primary key, v text);
create function pg_temp.tx(key text) returns text language sql as $$ select v from tx where k = key $$;
create function pg_temp.put(key text, val text) returns void language sql as
$$ insert into tx values (key, val) on conflict (k) do update set v = excluded.v $$;
create function pg_temp.putx(key text, val uuid) returns void language sql as
$$ insert into fx values (key, val) on conflict (k) do update set v = excluded.v $$;
create function pg_temp.as_user(key text) returns void language sql as
$$ select set_config('request.jwt.claim.sub', coalesce(pg_temp.fx(key)::text, ''), true),
          set_config('request.jwt.claim.role', 'authenticated', true),
          set_config('request.jwt.claims', '', true) $$;
create function pg_temp.err(q text) returns text language plpgsql as
$$begin execute q; return 'ok'; exception when others then return sqlstate || ' ' || sqlerrm; end$$;
create function pg_temp.mail(tag text) returns text language sql as
$$ select 't442-' || lower(tag) || '-' || pg_temp.tx('sfx') || '@example.com' $$;
create function pg_temp.fp() returns text language sql as
$$ select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.oid::regprocedure::text)) || ' ' || count(*)
     from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p') $$;
create function pg_temp.md5_now() returns text language sql as
$$ select md5(pg_get_functiondef('public.affiliate_referral_signup(text,text,text,text,text,text)'::regprocedure)) $$;
-- A login, as the sign-up function makes it (confirmed, marked unverified).
create function pg_temp.login(key text) returns uuid language plpgsql as
$$declare u uuid := gen_random_uuid(); begin
  insert into auth.users(id, email, email_confirmed_at, raw_app_meta_data, raw_user_meta_data)
  values (u, pg_temp.mail(key), now(), '{"provider": "email", "affiliate_email_unverified": true}'::jsonb, '{}'::jsonb);
  perform pg_temp.putx(key, u);
  return u;
end$$;
-- The affiliate sign-up the pages run, as the login.
create function pg_temp.onboard(key text, first text, last text, phone text) returns jsonb language plpgsql as
$$declare r jsonb; begin
  perform pg_temp.as_user(key);
  r := public.complete_affiliate_onboarding(first, last, phone, true);
  perform pg_temp.put('onb:' || key, r::text);
  return r;
end$$;
-- /r/<code>, as the page calls it: signed out (the anon key), or signed in as
-- a login (who = a key of fx). Keeps the answer (or the error) under 'ref:<tag>'.
create function pg_temp.ref(tag text, code text, first text, last text, phone text, email text,
                            who text default null, honeypot text default null) returns jsonb language plpgsql as
$$declare r jsonb; begin
  perform set_config('request.jwt.claim.sub', coalesce(pg_temp.fx(who)::text, ''), true);
  perform set_config('request.jwt.claim.role', case when who is null then 'anon' else 'authenticated' end, true);
  perform set_config('request.jwt.claims', '', true);
  execute case when who is null then 'set local role anon' else 'set local role authenticated' end;
  begin
    r := public.affiliate_referral_signup(code, first, last, phone, email, honeypot);
  exception when others then r := jsonb_build_object('error', sqlstate || ' ' || sqlerrm);
  end;
  execute 'reset role';
  perform pg_temp.put('ref:' || tag, r::text);
  return r;
end$$;
create function pg_temp.r(tag text) returns jsonb language sql as $$ select pg_temp.tx('ref:' || tag)::jsonb $$;
create function pg_temp.on_phone(p text) returns int language sql as
$$ select count(*)::int from public.customers c where c.deleted_at is null and public.normalize_customer_phone(c.phone) = p $$;
create function pg_temp.events(p text, o text default null) returns int language sql as
$$ select count(*)::int from public.referral_signup_events where normalized_phone = p and (o is null or outcome = o) $$;
create function pg_temp.audits(cust uuid) returns int language sql as
$$ select count(*)::int from public.audit_logs where action = 'referral_self_signup_refused' and record_id = cust $$;
-- The Audit Log entry for the self try with this phone (and name): null unless there is exactly one.
create function pg_temp.audit_on(p text, nm text default null) returns public.audit_logs language sql as
$$ select l.* from public.audit_logs l
    where l.action = 'referral_self_signup_refused' and l.new_data->>'phone' = p and (nm is null or l.new_data->>'name' = nm)
      and (select count(*) from public.audit_logs x where x.action = 'referral_self_signup_refused' and x.new_data->>'phone' = p
             and (nm is null or x.new_data->>'name' = nm)) = 1 $$;

-- The answers, as the function gives them elsewhere.
create function pg_temp.known() returns jsonb language sql as
$$ select jsonb_build_object('ok', true, 'outcome', 'already_registered', 'message',
     'This phone number is already registered with Energia, so no new registration was created. Nothing about your existing record has changed.') $$;
create function pg_temp.too_many() returns jsonb language sql as
$$ select jsonb_build_object('ok', false, 'message', 'Too many registration attempts for this phone number. Please wait 10 minutes or contact Energia.') $$;
create function pg_temp.link_full() returns jsonb language sql as
$$ select jsonb_build_object('ok', false, 'message', 'This referral link has had many registrations in the last hour. Please try again later or contact Energia.') $$;

-- ═════ P0 ═════
do $$ begin insert into tx values ('sfx', lower(substr(md5(random()::text || clock_timestamp()::text), 1, 6))); end $$;
select pg_temp.check(not exists (select 1 from public.customers c
                                  where public.normalize_customer_phone(c.phone) like '+614915706__'
                                     or public.normalize_customer_phone(c.phone) like '+614915707__')
    and not exists (select 1 from public.referral_signup_events e
                     where e.normalized_phone like '+614915706__' or e.normalized_phone like '+614915707__'),
  'P0 no customer and no sign-up event uses the test phones (+61491570600..799; the checks below assume so)');

-- ═════ M Install ═════
create temp table m442(before_def text, before_acl text, fp_before text, n_events int, n_audit int, n_users int, n_cust int);
insert into m442 select pg_get_functiondef('public.affiliate_referral_signup(text,text,text,text,text,text)'::regprocedure),
                        (select proacl::text from pg_proc where oid = 'public.affiliate_referral_signup(text,text,text,text,text,text)'::regprocedure),
                        pg_temp.fp(), (select count(*) from public.referral_signup_events), (select count(*) from public.audit_logs),
                        (select count(*) from auth.users), (select count(*) from public.customers);
\if :{?nomig}
select pg_temp.check(pg_temp.md5_now() = 'c76573912de0a4ded29e81e5c56c96d3', 'M0 442 is installed (nomig)');
\else
select pg_temp.check(pg_temp.md5_now() = 'a3deac154f5144cffb34fab871f076c6',
  'M0 affiliate_referral_signup is 440''s AFTER (this suite installs 442; use -v nomig=1 where it is in)');
\ir ../../../supabase/442_referral_self_refusal_vague_and_rate_limited.sql
do $$ begin insert into tx values ('fp1', pg_temp.fp()); end $$;
\ir ../../../supabase/442_referral_self_refusal_vague_and_rate_limited.sql
select pg_temp.check(pg_temp.md5_now() = 'c76573912de0a4ded29e81e5c56c96d3'
    and pg_temp.fp() = pg_temp.tx('fp1')
    and pg_temp.fp() <> (select fp_before from m442)
    and split_part(pg_temp.fp(), ' ', 2) = split_part((select fp_before from m442), ' ', 2),
  'M1 442 installs (its AFTER md5; no function added or dropped) and a second run changes nothing: ' || pg_temp.fp());
select pg_temp.check((select n_events from m442) = (select count(*) from public.referral_signup_events)
    and (select n_audit from m442) = (select count(*) from public.audit_logs)
    and (select n_users from m442) = (select count(*) from auth.users)
    and (select n_cust from m442) = (select count(*) from public.customers)
    and not exists (select 1 from auth.users where email like '442-check-%'),
  'M2 its self-tests (two runs) left no event, no Audit Log entry, no login and no customer');
\endif
select pg_temp.check((select proacl::text from pg_proc where oid = 'public.affiliate_referral_signup(text,text,text,text,text,text)'::regprocedure)
                       = (select before_acl from m442)
    and has_function_privilege('anon', 'public.affiliate_referral_signup(text,text,text,text,text,text)', 'execute')
    and has_function_privilege('authenticated', 'public.affiliate_referral_signup(text,text,text,text,text,text)', 'execute'),
  'M3 the grants are as they were: the page (anon) and signed-in visitors may call it');

-- ═════ Fixtures ═════
do $$
declare k text;
begin
  foreach k in array array['o', 'm', 's'] loop
    perform pg_temp.login('staff-' || k);
    insert into fx values (k, pg_temp.fx('staff-' || k));
  end loop;
  insert into profiles(id, full_name, email, role, is_active, invitation_status) values
    (pg_temp.fx('o'), 'T442 Owner', pg_temp.mail('staff-o'), 'owner', true, 'accepted'),
    (pg_temp.fx('m'), 'T442 Manager', pg_temp.mail('staff-m'), 'manager', true, 'accepted'),
    (pg_temp.fx('s'), 'T442 Staff', pg_temp.mail('staff-s'), 'staff', true, 'accepted');
  perform pg_temp.login('lG');
  perform pg_temp.login('lQ');
  perform pg_temp.login('lV');
end $$;
-- Gina signs up as an affiliate (a new customer); staff then change her record's name, phone and
-- email, so her record and what her login signed up with share nothing (as in 440's R).
select pg_temp.onboard('lG', 'Gina', 'Testlogin', '+61491570600');
select pg_temp.onboard('lQ', 'Quinn', 'Testlink', '+61491570604');
-- Vera: an affiliate whose record is what her login signed up with (D, C and X use her link).
select pg_temp.onboard('lV', 'Vera', 'Testvault', '+61491570607');
select pg_temp.as_user('o');
do $$ declare c uuid; begin
  insert into fx values ('cG', (pg_temp.tx('onb:lG')::jsonb->>'customer_id')::uuid),
                        ('cQ', (pg_temp.tx('onb:lQ')::jsonb->>'customer_id')::uuid),
                        ('cV', (pg_temp.tx('onb:lV')::jsonb->>'customer_id')::uuid);
  insert into tx values ('code_g', pg_temp.tx('onb:lG')::jsonb->>'referral_code'),
                        ('code_q', pg_temp.tx('onb:lQ')::jsonb->>'referral_code'),
                        ('code_v', pg_temp.tx('onb:lV')::jsonb->>'referral_code');
  update customers set full_name = 'Georgina Testrecord', phone = '+61491570601', email = null where id = pg_temp.fx('cG');
  -- Pam and Rita: referrers with no login. Ann: on file, referred by nobody.
  insert into customers(full_name, phone) values ('Pam Testplain', '+61491570602') returning id into c; insert into fx values ('cP', c);
  insert into customer_affiliates(customer_id, status, activated_at, referral_code)
  values (c, 'active', now() - interval '30 days', upper('T442P' || pg_temp.tx('sfx')));
  insert into tx values ('code_p', upper('T442P' || pg_temp.tx('sfx')));
  insert into customers(full_name, phone) values ('Rita Testother', '+61491570605') returning id into c; insert into fx values ('cR', c);
  insert into customer_affiliates(customer_id, status, activated_at, referral_code)
  values (c, 'active', now() - interval '30 days', upper('T442R' || pg_temp.tx('sfx')));
  insert into tx values ('code_r', upper('T442R' || pg_temp.tx('sfx')));
  insert into customers(full_name, phone) values ('Ann Testknown', '+61491570603') returning id into c; insert into fx values ('cA', c);
  -- A referral promotion running now.
  insert into fx values ('camp', gen_random_uuid());
  insert into referral_campaigns(id, code, title, reward_reason, starts_on, ends_on, tiers)
  values (pg_temp.fx('camp'), 'T442-PROMO-' || pg_temp.tx('sfx'), 'T442 promotion', 'T442 reward',
          public.sg_today() - 5, public.sg_today() + 5, array[1, 3]);
end $$;
-- One genuine friend through Gina's link before her tries, so the views have something to show.
select pg_temp.ref('f0', pg_temp.tx('code_g'), 'Fay', 'Testfriend', '+61491570606', pg_temp.mail('f0'));
select pg_temp.check(pg_temp.tx('onb:lG')::jsonb->>'status' = 'active' and pg_temp.tx('onb:lQ')::jsonb->>'status' = 'active'
    and pg_temp.tx('onb:lV')::jsonb->>'status' = 'active'
    and pg_temp.r('f0')->>'outcome' = 'registered'
    and exists (select 1 from customers c where c.referred_by = pg_temp.fx('cG') and c.phone = '+61491570606'),
  'F0 fixtures: Gina, Quinn and Vera are affiliates (each with her sign-up copy), Fay is Gina''s referral');

-- Everything that shows a referral, as staff and as Gina's portal read it.
create function pg_temp.views() returns jsonb language plpgsql as
$$declare r jsonb; begin
  perform pg_temp.as_user('o');
  r := jsonb_build_object(
    'admin_directory', public.affiliate_admin_directory(),
    'directory', (select jsonb_agg(to_jsonb(d) order by d.customer_id) from public.affiliate_directory() d
                   where d.customer_id in (pg_temp.fx('cG'), pg_temp.fx('cP'), pg_temp.fx('cQ'))),
    'referrer_list', (select jsonb_agg(to_jsonb(l) order by l.customer_id) from public.referrer_list() l
                       where l.customer_id in (pg_temp.fx('cG'), pg_temp.fx('cP'), pg_temp.fx('cQ'))),
    'downline', (select jsonb_agg(to_jsonb(d) order by d.customer_id) from public.referrer_downline(pg_temp.fx('cG')) d),
    'downline_visits', public.customer_downline_visits(pg_temp.fx('cG')),
    'profile_stats', public.customer_profile_stats(pg_temp.fx('cG')),
    'campaign_report', public.referral_campaign_report('T442-PROMO-' || pg_temp.tx('sfx')),
    'campaign_friends', (select jsonb_agg(to_jsonb(f) order by f.friend_customer_id)
                          from public.referral_campaign_friends(pg_temp.fx('camp')) f),
    'checks_pending', public.referral_signup_checks_pending(),
    'referred', (select jsonb_agg(c.id order by c.id) from customers c
                  where c.referred_by in (pg_temp.fx('cG'), pg_temp.fx('cP'), pg_temp.fx('cQ'))),
    'checks', (select count(*) from referral_signup_checks),
    'customers', (select count(*) from customers));
  perform pg_temp.as_user('lG');
  r := r || jsonb_build_object(
    'portal_dashboard', public.affiliate_portal_dashboard(),
    'portal_network', public.affiliate_portal_network(),
    'portal_me', public.affiliate_portal_me(),
    'portal_campaign', public.affiliate_portal_campaign_progress(),
    'portal_referral_info', public.affiliate_portal_referral_info());
  perform pg_temp.as_user('o');
  return r;
end$$;
do $$ begin insert into tx values ('views0', pg_temp.views()::text); end $$;

-- ═════ A The answer ═════
select pg_temp.ref('a1', pg_temp.tx('code_g'), 'Georgina', 'Testrecord', '+61491570601', null);
select pg_temp.ref('a2', pg_temp.tx('code_g'), 'Gina', 'Testlogin', '+61491570610', pg_temp.mail('a2'));
select pg_temp.ref('a2b', pg_temp.tx('code_g'), 'TESTLOGIN', 'gina', '+61491570611', null);
select pg_temp.ref('a3', pg_temp.tx('code_g'), 'Kurt', 'Friend', '+61 491 570 600', pg_temp.mail('a3'));
select pg_temp.ref('a4', pg_temp.tx('code_g'), 'Lia', 'Friend', '+61491570612', upper(pg_temp.mail('lG')));
select pg_temp.ref('a5', '  ' || pg_temp.tx('code_g') || ' ', 'Gina', 'Testlogin', '+61491570600', pg_temp.mail('lG'));
select pg_temp.ref('a6', pg_temp.tx('code_p'), 'Testplain', 'Pam', '+61491570602', null);
select pg_temp.check(pg_temp.r('a1') = pg_temp.known(),
  'A1 her record through her own link: told what someone already registered is told, as anyone on file is (before 442: "You cannot refer yourself."): ' || pg_temp.r('a1')::text);
select pg_temp.check(pg_temp.r('a2') = pg_temp.known() and pg_temp.r('a2b') = pg_temp.known(),
  'A2 her login''s sign-up name on a new phone (also in another order and case): the same answer');
select pg_temp.check(pg_temp.r('a3') = pg_temp.known(), 'A3 her login''s phone (typed another way) under another name: the same answer');
select pg_temp.check(pg_temp.r('a4') = pg_temp.known(), 'A4 her login''s email inbox (in capitals) under another name on another phone: the same answer');
select pg_temp.check(pg_temp.r('a5') = pg_temp.known(), 'A5 all of them at once, the code typed with spaces around it: the same answer');
select pg_temp.check(pg_temp.r('a6') = pg_temp.known(), 'A6 a referrer with no login, on her record (her name in another order): the same answer');
do $$ begin insert into tx values ('views1', pg_temp.views()::text); end $$;
-- Someone else already on file, through her link and through another: the same JSON, word for word.
select pg_temp.ref('a7', pg_temp.tx('code_g'), 'Ann', 'Testknown', '+61491570603', null);
select pg_temp.ref('a7b', pg_temp.tx('code_p'), 'Testknown', 'Ann', '+61491570603', pg_temp.mail('a7b'));
select pg_temp.check(pg_temp.r('a7') = pg_temp.r('a1') and pg_temp.r('a7b') = pg_temp.r('a1')
    and pg_temp.events('+61491570603', 'duplicate') = 2,
  'A7 someone already registered (a real duplicate), through her link and through another, gets the very same JSON as each of her tries: '
  || pg_temp.r('a7')::text);
select pg_temp.check(not exists (select 1 from tx where k like 'ref:a%' and (v ilike '%yourself%' or v ilike '%affiliate%' or v ilike '%referr%'))
    and strpos(pg_get_functiondef('public.affiliate_referral_signup(text,text,text,text,text,text)'::regprocedure), 'refer yourself') = 0
    and (select bool_and(jsonb_typeof(v::jsonb) = 'object' and (select array_agg(x order by x) from jsonb_object_keys(v::jsonb) x)
                         = array['message', 'ok', 'outcome']) from tx where k like 'ref:a%'),
  'A8 nothing in any answer (nor in the function) speaks of herself, the affiliate or the referrer; each is ok, outcome and message only');

-- ═════ W What is written ═════
select pg_temp.check((select count(*) from referral_signup_events where outcome = 'self') = 5
    and (select count(*) from referral_signup_events where outcome = 'self_known') = 2
    and (select count(*) from referral_signup_events e
          where e.outcome = 'self' and e.referrer_customer_id = pg_temp.fx('cG') and e.referral_code = pg_temp.tx('code_g')
            and e.new_customer_id is null
            and e.normalized_phone in ('+61491570610', '+61491570611', '+61491570600', '+61491570612')) = 5
    and pg_temp.events('+61491570600', 'self') = 2
    and exists (select 1 from referral_signup_events e where e.outcome = 'self_known' and e.referrer_customer_id = pg_temp.fx('cG')
                  and e.normalized_phone = '+61491570601' and e.referral_code = pg_temp.tx('code_g') and e.new_customer_id is null)
    and pg_temp.events('+61491570601') = 1
    and exists (select 1 from referral_signup_events e where e.outcome = 'self_known' and e.referrer_customer_id = pg_temp.fx('cP')
                  and e.normalized_phone = '+61491570602' and e.referral_code = pg_temp.tx('code_p') and e.new_customer_id is null),
  'W1 one event per try: ''self'' where a new customer would have been made, ''self_known'' on her record (details on file, in place of ''duplicate''): the code as the link reads it (without the spaces), her record as the referrer, the phone, no customer');
select pg_temp.check(pg_temp.on_phone('+61491570610') + pg_temp.on_phone('+61491570611') + pg_temp.on_phone('+61491570612') = 0
    and pg_temp.on_phone('+61491570600') = 0 and pg_temp.on_phone('+61491570601') = 1 and pg_temp.on_phone('+61491570602') = 1
    and (pg_temp.tx('views1')::jsonb->>'customers') = (pg_temp.tx('views0')::jsonb->>'customers')
    and (pg_temp.tx('views1')::jsonb->>'checks') = (pg_temp.tx('views0')::jsonb->>'checks'),
  'W2 her tries made no customer and no check, and referred nobody');

-- ═════ N Never a referral ═════
select pg_temp.check(pg_temp.tx('views1')::jsonb - k = pg_temp.tx('views0')::jsonb - k,
  'N1 ' || k || ' is the same before and after her tries')
  from jsonb_object_keys(pg_temp.tx('views0')::jsonb) k;
select pg_temp.check(pg_temp.tx('views1')::jsonb = pg_temp.tx('views0')::jsonb,
  'N1 every view of referrals (her portal, the staff views, the promotion, the checks) is as it was');
select pg_temp.check((select array_agg(p.oid::regprocedure::text order by p.oid::regprocedure::text)
                        from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
                       where p.prosrc ilike '%referral_signup_events%' and ns.nspname not like 'pg\_temp\_%')
                     = array['affiliate_referral_signup(text,text,text,text,text,text)', 'event_web_apply_referral(uuid,uuid)',
                             'event_web_new_customer(uuid)']
    and not exists (select 1 from pg_depend dp join pg_rewrite rw on rw.oid = dp.objid
                     where dp.classid = 'pg_rewrite'::regclass and dp.refobjid = 'public.referral_signup_events'::regclass
                       and rw.ev_class <> 'public.referral_signup_events'::regclass)
    -- The event website only writes events, but for one count (its per-link limit), which reads
    -- 'created' and 'phone_shared' alone. (Its own answer for the affiliate herself is also
    -- called 'self'; it is never an event.)
    and strpos((select prosrc from pg_proc where oid = 'public.event_web_apply_referral(uuid,uuid)'::regprocedure),
               'from public.referral_signup_events') = 0
    and (select (length(prosrc) - length(replace(prosrc, 'from public.referral_signup_events', '')))
                / length('from public.referral_signup_events')
           from pg_proc where oid = 'public.event_web_new_customer(uuid)'::regprocedure) = 1
    and strpos((select prosrc from pg_proc where oid = 'public.event_web_new_customer(uuid)'::regprocedure),
               E'from public.referral_signup_events e\n           where e.referrer_customer_id = r.referrer_customer_id and e.outcome in (''created'', ''phone_shared'')') > 0
    and not exists (select 1 from pg_proc p, regexp_matches(p.prosrc, 'insert into public\.referral_signup_events[^;]*''self''', 'g') m
                     where p.oid in ('public.event_web_new_customer(uuid)'::regprocedure, 'public.event_web_apply_referral(uuid,uuid)'::regprocedure))
    and not exists (select 1 from pg_proc p where p.prosrc ilike '%self_known%'
                       and p.oid <> 'public.affiliate_referral_signup(text,text,text,text,text,text)'::regprocedure
                       and p.pronamespace <> pg_my_temp_schema()),
  'N2 the only readers of referral_signup_events are 442''s function and 436''s two event-website functions (no view); the website reads it once, its per-link count of created and phone_shared, and never writes ''self''; no other function names ''self_known''');

-- ═════ S Staff see it; the caller does not ═════
select pg_temp.check(pg_temp.audits(pg_temp.fx('cG')) = 6 and pg_temp.audits(pg_temp.fx('cP')) = 1
    and (select bool_and(l.table_name = 'customers' and l.module = 'affiliate' and l.changed_by is null and l.actor_role is null
                         and l.new_data->>'signed_in_login' is null and l.new_data->>'source' = 'affiliate_link')
           from audit_logs l where l.action = 'referral_self_signup_refused'),
  'S1 an Audit Log entry on her record for each try (System: nobody signed in), in the affiliate module');
select pg_temp.check((pg_temp.audit_on('+61491570601')).new_data = jsonb_build_object('referral_code', pg_temp.tx('code_g'),
         'source', 'affiliate_link', 'outcome', 'self_known', 'matched', jsonb_build_array('record'), 'phone', '+61491570601',
         'name', 'Georgina Testrecord', 'email', null, 'signed_in_login', null)
    and (pg_temp.audit_on('+61491570610')).new_data->'matched' = '["login_name"]'
    and (pg_temp.audit_on('+61491570610')).new_data->>'outcome' = 'self'
    and (pg_temp.audit_on('+61491570610')).new_data->>'email' = pg_temp.mail('a2')
    and (pg_temp.audit_on('+61491570600', 'Gina Testlogin')).new_data->'matched' = '["login_name", "login_phone", "login_email"]'
    and (pg_temp.audit_on('+61491570600', 'Kurt Friend')).new_data->'matched' = '["login_phone"]'
    and (pg_temp.audit_on('+61491570612')).new_data->'matched' = '["login_email"]'
    and (pg_temp.audit_on('+61491570612')).new_data->>'email' = lower(pg_temp.mail('lG'))
    and (pg_temp.audit_on('+61491570602')).record_id = pg_temp.fx('cP'),
  'S2 each entry says the event (''self'' or ''self_known''), what matched (her record, her login''s name, phone, email inbox) and what was typed: '
  || (pg_temp.audit_on('+61491570600', 'Gina Testlogin')).new_data::text);
-- Gina signed in on her phone tries her own link; a Manager at the counter types her login's phone.
select pg_temp.ref('s3', pg_temp.tx('code_g'), 'Gina', 'Testlogin', '+61491570613', null, 'lG');
select pg_temp.ref('s4', pg_temp.tx('code_g'), 'Mia', 'Testcounter', '+61491570600', null, 'm');
select pg_temp.as_user('lG');
select pg_temp.check(pg_temp.r('s3') = pg_temp.known() and pg_temp.events('+61491570613', 'self') = 1
    and (pg_temp.audit_on('+61491570613')).changed_by is null
    and (pg_temp.audit_on('+61491570613')).new_data->>'signed_in_login' = pg_temp.fx('lG')::text
    and pg_temp.err('select public.write_audit_ex(''customers'', null, ''t442'', null, null)') like '23503 %',
  'S3 signed in as her own login: the same answer, recorded (her login named in it; write_audit_ex would fail for her: '
  || pg_temp.err('select public.write_audit_ex(''customers'', null, ''t442'', null, null)') || ')');
select pg_temp.as_user('o');
select pg_temp.check(pg_temp.r('s4') = pg_temp.known()
    and (select l.changed_by = pg_temp.fx('m') and l.actor_role = 'manager' and l.new_data->'matched' = '["login_phone"]'
           from audit_logs l where l.action = 'referral_self_signup_refused' and l.new_data->>'name' = 'Mia Testcounter'),
  'S4 a Manager at the counter: the same answer, the entry names her');
select pg_temp.as_user('m');
do $$ begin insert into tx values ('page', public.audit_log_page(null, null, null, null, null, 'referral_self_signup_refused', 50, 0, null, false)::text); end $$;
select pg_temp.check((pg_temp.tx('page')::jsonb->>'total')::int = 9
    and (select count(*) from jsonb_array_elements(pg_temp.tx('page')::jsonb->'rows') e
          where e->>'action' = 'referral_self_signup_refused' and e->>'record_id' = pg_temp.fx('cG')::text
            and e->>'actor_name' = 'System') = 7,
  'S5 a Manager finds the entries on the Audit Log page (audit_log_page), signed-out ones as System: ' || (pg_temp.tx('page')::jsonb->>'total'));
-- Who can read the events and the entries through the API (row level security).
create function pg_temp.read_as(who text, q text) returns text language plpgsql as
$$declare n bigint; begin
  perform set_config('request.jwt.claim.sub', coalesce(pg_temp.fx(who)::text, ''), true);
  perform set_config('request.jwt.claim.role', case when who is null then 'anon' else 'authenticated' end, true);
  execute case when who is null then 'set local role anon' else 'set local role authenticated' end;
  begin execute q into n; exception when others then execute 'reset role'; return sqlstate; end;
  execute 'reset role';
  return n::text;
end$$;
select pg_temp.check(pg_temp.read_as('o', 'select count(*) from public.referral_signup_events where outcome in (''self'', ''self_known'')') = '9'
    and pg_temp.read_as('m', 'select count(*) from public.referral_signup_events where outcome in (''self'', ''self_known'')') = '9'
    and pg_temp.read_as('s', 'select count(*) from public.referral_signup_events where outcome in (''self'', ''self_known'')') = '0'
    and pg_temp.read_as('lG', 'select count(*) from public.referral_signup_events where outcome in (''self'', ''self_known'')') = '0'
    and pg_temp.read_as(null, 'select count(*) from public.referral_signup_events where outcome in (''self'', ''self_known'')') in ('0', '42501')
    and pg_temp.read_as('m', 'select count(*) from public.audit_logs where action = ''referral_self_signup_refused''') = '9'
    and pg_temp.read_as('s', 'select count(*) from public.audit_logs where action = ''referral_self_signup_refused''') = '0'
    and pg_temp.read_as('lG', 'select count(*) from public.audit_logs where action = ''referral_self_signup_refused''') = '0'
    and pg_temp.read_as(null, 'select count(*) from public.audit_logs where action = ''referral_self_signup_refused''') in ('0', '42501'),
  'S6 Owners and Managers read the self events and entries; staff and her own login read none, the anon key is refused (42501) or reads none (events: '
  || (select string_agg(coalesce(w, 'anon') || ' ' || pg_temp.read_as(w, 'select count(*) from public.referral_signup_events where outcome in (''self'', ''self_known'')'), ', ')
        from unnest(array['o', 'm', 's', 'lG', null]) w)
  || '; Audit Log: '
  || (select string_agg(coalesce(w, 'anon') || ' ' || pg_temp.read_as(w, 'select count(*) from public.audit_logs where action = ''referral_self_signup_refused'''), ', ')
        from unnest(array['o', 'm', 's', 'lG', null]) w) || ')');
select pg_temp.as_user('o');

-- ═════ G A genuine referral is unchanged ═════
select pg_temp.ref('g1', pg_temp.tx('code_p'), 'Tom', 'Testfamily', '+61491570640', pg_temp.mail('g1'));
select pg_temp.check(pg_temp.r('g1') = jsonb_build_object('ok', true, 'outcome', 'registered', 'message', 'Registration successful.',
                                                          'affiliate_label', 'Pam Testplain')
    and exists (select 1 from customers c where c.phone = '+61491570640' and c.referred_by = pg_temp.fx('cP')
                  and c.referral_source = 'affiliate_link' and c.referral_code_used = pg_temp.tx('code_p') and c.email = pg_temp.mail('g1'))
    and pg_temp.events('+61491570640', 'created') = 1
    and exists (select 1 from audit_logs l join customers c on c.id = l.record_id
                 where c.phone = '+61491570640' and l.action = 'referral_registered'),
  'G1 a new friend: registered with the referrer''s label, referred, a ''created'' event, the usual Audit Log entry: ' || pg_temp.r('g1')::text);
select pg_temp.ref('g2', pg_temp.tx('code_p'), 'Hal', 'Testhousehold', '+61491570602', null);
select pg_temp.check(pg_temp.r('g2')->>'outcome' = 'registered'
    and pg_temp.events('+61491570602', 'phone_shared') = 1
    and exists (select 1 from referral_signup_checks k join customers c on c.id = k.customer_id
                 where c.full_name = 'Hal Testhousehold' and k.status = 'pending' and k.phone_shared_with = array[pg_temp.fx('cP')]),
  'G2 someone on her record''s phone under another name: registered and checked by staff (425), as before');
select pg_temp.ref('g3', pg_temp.tx('code_p'), 'Ann', 'Testknown', '+61491570603', null);
select pg_temp.check(pg_temp.r('g3') = pg_temp.known() and pg_temp.events('+61491570603', 'duplicate') = 3
    and (select referred_by from customers where id = pg_temp.fx('cA')) is null,
  'G3 someone already registered: told so, a ''duplicate'' event, her referrer untouched, as before');
update customer_affiliates set manually_suspended = true where customer_id = pg_temp.fx('cR');
select pg_temp.ref('g4', pg_temp.tx('code_r'), 'Ivy', 'Testoff', '+61491570641', null);
select pg_temp.ref('g4b', pg_temp.tx('code_r'), 'Rita', 'Testother', '+61491570605', null);
select pg_temp.check(pg_temp.r('g4') = jsonb_build_object('ok', false, 'message',
                       'This referral link is not accepting new registrations right now. Please contact Energia.')
    and pg_temp.r('g4b') = pg_temp.r('g4') and pg_temp.events('+61491570641', 'rejected') = 1
    and pg_temp.events('+61491570605', 'rejected') = 1 and pg_temp.events('+61491570605', 'self') = 0,
  'G4 a link that is not accepting: refused as before, for anyone (the referrer too: the link is checked first)');
update customer_affiliates set manually_suspended = false where customer_id = pg_temp.fx('cR');
select pg_temp.ref('g5', pg_temp.tx('code_g'), 'Bot', 'Testbot', '+61491570642', null, null, 'filled');
select pg_temp.check(pg_temp.r('g5') = jsonb_build_object('ok', true, 'outcome', 'registered')
    and pg_temp.on_phone('+61491570642') = 0
    and exists (select 1 from referral_signup_events where outcome = 'honeypot' and referral_code = pg_temp.tx('code_g')),
  'G5 the honeypot: answered as before, nothing made');
select pg_temp.ref('g6', pg_temp.tx('code_g'), 'Tia', 'Testfamily', '+61491570643', null);
select pg_temp.check(pg_temp.r('g6')->>'outcome' = 'registered'
    and exists (select 1 from customers c where c.phone = '+61491570643' and c.referred_by = pg_temp.fx('cG')),
  'G6 a friend who shares nothing with Gina, through her link: registered and referred, as before');

-- ═════ L The limits ═════
-- L1 The phone's: three tries on one phone in ten minutes.
select pg_temp.ref('l1a', pg_temp.tx('code_g'), 'Gina', 'Testlogin', '+61491570620', null);
select pg_temp.ref('l1b', pg_temp.tx('code_g'), 'Gina', 'Testlogin', '+61491570620', null);
select pg_temp.ref('l1c', pg_temp.tx('code_g'), 'Gina', 'Testlogin', '+61491570620', null);
select pg_temp.ref('l1d', pg_temp.tx('code_g'), 'Gina', 'Testlogin', '+61491570620', null);
select pg_temp.ref('l1e', pg_temp.tx('code_g'), 'Sam', 'Testnewcomer', '+61491570620', null);
select pg_temp.ref('l1f', pg_temp.tx('code_g'), 'Sam', 'Testnewcomer', '+61491570621', null);
select pg_temp.check(pg_temp.r('l1a') = pg_temp.known() and pg_temp.r('l1b') = pg_temp.known() and pg_temp.r('l1c') = pg_temp.known()
    and pg_temp.r('l1d') = pg_temp.too_many() and pg_temp.events('+61491570620') = 3,
  'L1 three self tries on one phone: each told "already registered"; the fourth is refused by the phone''s limit, writing nothing: ' || pg_temp.r('l1d')::text);
select pg_temp.check(pg_temp.r('l1e') = pg_temp.r('l1d') and pg_temp.on_phone('+61491570620') = 0
    and pg_temp.r('l1f')->>'outcome' = 'registered',
  'L1 a genuine sign-up on that phone is refused too, with the very same answer, and nothing is made (before 442 her tries wrote nothing, so it was registered); on another phone it registers');
update referral_signup_events set created_at = created_at - interval '11 minutes' where normalized_phone = '+61491570620';
select pg_temp.ref('l1g', pg_temp.tx('code_g'), 'Gina', 'Testlogin', '+61491570620', null);
select pg_temp.check(pg_temp.r('l1g') = pg_temp.known() and pg_temp.events('+61491570620', 'self') = 4,
  'L1 tries older than ten minutes do not count: her next try is counted and answered as before');
-- Someone already on file is never limited (as before): three self tries (Gina's login email) on
-- the phone of a customer on file, then that customer, then a fourth self try.
select pg_temp.ref('l1h', pg_temp.tx('code_g'), 'Xa', 'Testprobe', '+61491570622', pg_temp.mail('lG'));
select pg_temp.ref('l1i', pg_temp.tx('code_g'), 'Xb', 'Testprobe', '+61491570622', pg_temp.mail('lG'));
select pg_temp.ref('l1j', pg_temp.tx('code_g'), 'Xc', 'Testprobe', '+61491570622', pg_temp.mail('lG'));
do $$ begin insert into customers(full_name, phone) values ('Ola Testonfile', '+61491570622'); end $$;
select pg_temp.ref('l1k', pg_temp.tx('code_g'), 'Ola', 'Testonfile', '+61491570622', null);
select pg_temp.ref('l1l', pg_temp.tx('code_g'), 'Xd', 'Testprobe', '+61491570622', pg_temp.mail('lG'));
select pg_temp.check(pg_temp.r('l1h') = pg_temp.known() and pg_temp.r('l1j') = pg_temp.known()
    and pg_temp.r('l1k') = pg_temp.known() and pg_temp.r('l1l') = pg_temp.too_many(),
  'L1 someone on file on that phone is still told "already registered" (never limited, as before); a fourth self try is refused');

-- L2 The link's: twenty self tries through Quinn's link in an hour refuse the next new friend.
do $$
declare i int; r jsonb; n int := 0;
begin
  for i in 0 .. 19 loop
    r := pg_temp.ref('l2_' || i, pg_temp.tx('code_q'), 'Guest' || i, 'Testprobe', '+614915707' || lpad(i::text, 2, '0'), pg_temp.mail('lQ'));
    if r = pg_temp.known() then n := n + 1; end if;
  end loop;
  insert into tx values ('l2_known', n::text);
end $$;
select pg_temp.ref('l2a', pg_temp.tx('code_q'), 'Nina', 'Testfriend', '+61491570720', null);
select pg_temp.ref('l2b', pg_temp.tx('code_q'), 'Guest21', 'Testprobe', '+61491570721', pg_temp.mail('lQ'));
select pg_temp.ref('l2c', pg_temp.tx('code_r'), 'Nina', 'Testfriend', '+61491570722', null);
select pg_temp.check(pg_temp.tx('l2_known')::int = 20
    and (select count(*) from referral_signup_events where referrer_customer_id = pg_temp.fx('cQ') and outcome = 'self'
           and normalized_phone like '+614915707__') = 20,
  'L2 twenty self tries through one link, each on its own phone: each told "already registered", each counted');
select pg_temp.check(pg_temp.r('l2a') = pg_temp.link_full() and pg_temp.on_phone('+61491570720') = 0
    and pg_temp.events('+61491570720', 'link_limit') = 1,
  'L2 the next new friend through that link is refused by the link''s limit, nothing made, a ''link_limit'' event (before 442: registered): ' || pg_temp.r('l2a')::text);
select pg_temp.check(pg_temp.r('l2b') = pg_temp.r('l2a') and pg_temp.events('+61491570721', 'link_limit') = 1
    and pg_temp.events('+61491570721', 'self') = 0 and pg_temp.audits(pg_temp.fx('cQ')) = 20,
  'L2 and so is the next self try, with the very same answer (a ''link_limit'' event, no ''self'' event, no entry)');
-- At the link's limit: someone on file (Ann) typed with Quinn's login email, and with another email.
select pg_temp.ref('l2e', pg_temp.tx('code_q'), 'Ann', 'Testknown', '+61491570603', pg_temp.mail('lQ'));
select pg_temp.ref('l2f', pg_temp.tx('code_q'), 'Ann', 'Testknown', '+61491570603', pg_temp.mail('l2f'));
select pg_temp.check(pg_temp.r('l2e') = pg_temp.known() and pg_temp.r('l2f') = pg_temp.known()
    and pg_temp.events('+61491570603', 'link_limit') = 0
    and (select count(*) from referral_signup_events where normalized_phone = '+61491570603' and outcome = 'self_known'
           and referrer_customer_id = pg_temp.fx('cQ')) = 1
    and pg_temp.audits(pg_temp.fx('cQ')) = 21
    and (select count(*) from referral_signup_events where referrer_customer_id = pg_temp.fx('cQ')
           and outcome in ('created', 'phone_shared', 'self') and created_at > now() - interval '1 hour') = 20,
  'L2 at the link''s limit, details on file with her login''s email and with another email: the same "already registered" (never limited), ''self_known'' with its entry for hers; neither counts for the link (before the review her email was limited)');
select pg_temp.check(pg_temp.r('l2c')->>'outcome' = 'registered', 'L2 another link still registers');
update referral_signup_events set created_at = created_at - interval '61 minutes'
 where referrer_customer_id = pg_temp.fx('cQ') and outcome = 'self';
select pg_temp.ref('l2d', pg_temp.tx('code_q'), 'Nina', 'Testfriend', '+61491570723', null);
select pg_temp.check(pg_temp.r('l2d')->>'outcome' = 'registered', 'L2 tries older than an hour do not count: a new friend registers');
-- L3 Self tries and new customers count together: Gina's link, filled to 19 with new customers.
do $$ declare k int; begin
  select count(*) into k from referral_signup_events
   where referrer_customer_id = pg_temp.fx('cG') and outcome in ('created', 'phone_shared', 'self') and created_at > now() - interval '1 hour';
  insert into tx values ('l3_before', k::text);
  insert into referral_signup_events(referral_code, referrer_customer_id, normalized_phone, outcome)
  select pg_temp.tx('code_g'), pg_temp.fx('cG'), null, 'created' from generate_series(1, 19 - k);
end $$;
select pg_temp.ref('l3a', pg_temp.tx('code_g'), 'Gina', 'Testlogin', '+61491570630', null);
select pg_temp.ref('l3b', pg_temp.tx('code_g'), 'Ned', 'Testfriend', '+61491570631', null);
select pg_temp.check(pg_temp.r('l3a') = pg_temp.known() and pg_temp.r('l3b') = pg_temp.link_full()
    and pg_temp.on_phone('+61491570631') = 0,
  'L3 with 19 new customers and self tries in the hour (' || pg_temp.tx('l3_before') || ' of them real), a self try is the 20th; the next new friend is refused');

-- How many tries Vera's link has had in the hour, as its limit counts them.
create function pg_temp.vera_link() returns int language sql as
$$ select count(*)::int from public.referral_signup_events where referrer_customer_id = pg_temp.fx('cV')
     and outcome in ('created', 'phone_shared', 'self') and created_at > now() - interval '1 hour' $$;

-- ═════ D Details on file ═════
-- Dora is on file. Through Vera's link: Dora's name and phone with Vera's login email (hers), and
-- with other emails (not hers), in turn, past the phone's three tries in ten minutes.
do $$ begin insert into customers(full_name, phone) values ('Dora Testonfile', '+61491570665'); end $$;
select pg_temp.ref('d1', pg_temp.tx('code_v'), 'Dora', 'Testonfile', '+61491570665', pg_temp.mail('lV'));
select pg_temp.ref('d2', pg_temp.tx('code_v'), 'Dora', 'Testonfile', '+61491570665', pg_temp.mail('d2'));
select pg_temp.ref('d3', pg_temp.tx('code_v'), 'Dora', 'Testonfile', '+61491570665', pg_temp.mail('d3'));
select pg_temp.ref('d4', pg_temp.tx('code_v'), 'Dora', 'Testonfile', '+61491570665', pg_temp.mail('lV'));
select pg_temp.ref('d5', pg_temp.tx('code_v'), 'Testonfile', 'Dora', '+61491570665', upper(pg_temp.mail('lV')));
select pg_temp.ref('d6', pg_temp.tx('code_v'), 'Dora', 'Testonfile', '+61491570665', pg_temp.mail('d6'));
select pg_temp.check((select bool_and(pg_temp.r(t) = pg_temp.known()) from unnest(array['d1', 'd2', 'd3', 'd4', 'd5', 'd6']) t),
  'D1 someone on file typed with her login''s email, and with other emails, in turn: each the very same "already registered", the 4th to 6th too (past the phone''s three tries; before the review hers got "Too many" there): '
  || pg_temp.r('d4')::text);
select pg_temp.check(pg_temp.events('+61491570665', 'self_known') = 3 and pg_temp.events('+61491570665', 'duplicate') = 3
    and pg_temp.events('+61491570665') = 6
    and (select count(*) from audit_logs l where l.action = 'referral_self_signup_refused' and l.record_id = pg_temp.fx('cV')
           and l.new_data->>'phone' = '+61491570665' and l.new_data->>'outcome' = 'self_known'
           and l.new_data->'matched' = '["login_email"]') = 3
    and (select count(*) from audit_logs l where l.action = 'referral_self_signup_refused' and l.new_data->>'phone' = '+61491570665') = 3
    and pg_temp.vera_link() = 0
    and (select referred_by from customers where phone = '+61491570665') is null,
  'D2 hers are recorded (''self_known'', each with its entry), the others are ''duplicate'' (no entry); the link''s count is untouched, Dora''s referrer too');
-- Vera's own record (her name and phone, which her login also signed up with), four times.
select pg_temp.ref('d7a', pg_temp.tx('code_v'), 'Vera', 'Testvault', '+61491570607', null);
select pg_temp.ref('d7b', pg_temp.tx('code_v'), 'Testvault', 'Vera', '+61491570607', null);
select pg_temp.ref('d7c', pg_temp.tx('code_v'), 'Vera', 'Testvault', '+61491570607', null);
select pg_temp.ref('d7d', pg_temp.tx('code_v'), 'Vera', 'Testvault', '+61491570607', null);
select pg_temp.check((select bool_and(pg_temp.r(t) = pg_temp.known()) from unnest(array['d7a', 'd7b', 'd7c', 'd7d']) t)
    and pg_temp.events('+61491570607', 'self_known') = 4 and pg_temp.events('+61491570607') = 4
    and (select bool_and(l.new_data->'matched' = '["record", "login_name", "login_phone"]')
           from audit_logs l where l.action = 'referral_self_signup_refused' and l.new_data->>'phone' = '+61491570607')
    and pg_temp.vera_link() = 0,
  'D3 her own record, four times: each "already registered" (never limited, as anyone on file), ''self_known'', recorded');

-- ═════ C A phone 3 customers have ═════
do $$ begin
  insert into customers(full_name, phone) values ('Cora Testfull', '+61491570660');
  insert into customers(full_name, phone) values ('Cody Testfull', '+61491570660');
  insert into customers(full_name, phone) values ('Cara Testfull', '+61491570660');
end $$;
select pg_temp.ref('c1', pg_temp.tx('code_v'), 'Probe', 'Testperson', '+61491570660', pg_temp.mail('lV'));
select pg_temp.ref('c2', pg_temp.tx('code_v'), 'Probe', 'Testperson', '+61491570660', pg_temp.mail('c2'));
select pg_temp.ref('c3', pg_temp.tx('code_v'), 'Testvault', 'Vera', '+61491570660', null);
select pg_temp.ref('c4', pg_temp.tx('code_v'), 'Wrong', 'Testname', '+61491570660', null);
do $$
declare i int; n int := 0;
begin
  for i in 1 .. 30 loop
    if pg_temp.ref('c5_' || i, pg_temp.tx('code_v'), 'Probe', 'Testperson', '+61491570660',
                   case when i % 10 = 0 then pg_temp.mail('lV') else pg_temp.mail('c5-' || i) end) = pg_temp.r('c2') then
      n := n + 1; end if;
  end loop;
  insert into tx values ('c5_same', n::text);
end $$;
select pg_temp.check(pg_temp.r('c1')->>'error' like 'P0001 CUSTOMER_PHONE_LIMIT:%'
    and pg_temp.r('c1') = pg_temp.r('c2') and pg_temp.r('c3') = pg_temp.r('c2') and pg_temp.r('c4') = pg_temp.r('c2')
    and pg_temp.tx('c5_same') = '30',
  'C1 her login''s email, her login''s name, and other guesses, under names not on file there: the very same error, every time (30 more, 3 of them hers; before the review hers got "already registered"): '
  || coalesce(pg_temp.r('c1')->>'error', pg_temp.r('c1')::text, 'no answer'));
select pg_temp.check(pg_temp.events('+61491570660') = 0
    and not exists (select 1 from audit_logs l where l.action = 'referral_self_signup_refused' and l.new_data->>'phone' = '+61491570660')
    and pg_temp.on_phone('+61491570660') = 3 and pg_temp.vera_link() = 0,
  'C2 none of them wrote anything: no event, no Audit Log entry, no customer; the link''s count is untouched');
select pg_temp.ref('c6', pg_temp.tx('code_v'), 'Cora', 'Testfull', '+61491570660', pg_temp.mail('lV'));
select pg_temp.check(pg_temp.r('c6') = pg_temp.known() and pg_temp.events('+61491570660', 'self_known') = 1,
  'C3 someone on file there typed with her login''s email: "already registered", as anyone on file, ''self_known''');

-- ═════ X What 442 still tells ═════
-- On details nobody has on file (a phone no customer has), her login's email and another email.
select pg_temp.ref('x1', pg_temp.tx('code_v'), 'Zed', 'Testmadeup', '+61491570670', pg_temp.mail('lV'));
select pg_temp.ref('x2', pg_temp.tx('code_v'), 'Zed', 'Testmadeup', '+61491570671', pg_temp.mail('x2'));
select pg_temp.check(pg_temp.r('x1') = pg_temp.known()
    and pg_temp.r('x2') = jsonb_build_object('ok', true, 'outcome', 'registered', 'message', 'Registration successful.',
                                             'affiliate_label', 'Vera Testvault')
    and pg_temp.events('+61491570670', 'self') = 1 and pg_temp.on_phone('+61491570670') = 0
    and exists (select 1 from customers c where c.phone = '+61491570671' and c.referred_by = pg_temp.fx('cV'))
    and pg_temp.vera_link() = 2,
  'X1 the one thing 442 does not hide (its NOT COVERED, first item; the Owner''s choice): on a phone no customer has, her login''s email is "already registered", another email is registered and made a customer referred by her; both count in the link''s limit');

-- ═════ M Refusals ═════
\if :{?nomig}
do $$ begin raise notice 'NOTE  M4-M6 are skipped: 442 was installed before this suite, so its BEFORE text is not at hand'; end $$;
\else
create function pg_temp.put_before(variant text default null) returns void language plpgsql as
$$begin
  execute case when variant is null then (select before_def from m442)
               else replace((select before_def from m442), '-- 425: the customers in use', '-- 425:  the customers in use') end;
end$$;
\set ON_ERROR_STOP off
-- M4 An affiliate login with no sign-up copy (an account made by hand): 442 refuses to patch.
savepoint m4;
select pg_temp.put_before();
do $$ declare c uuid; a uuid; u uuid := pg_temp.login('lHand'); begin
  insert into customers(full_name, phone) values ('Hana Testhand', '+61491570650') returning id into c;
  insert into customer_affiliates(customer_id, status, activated_at, referral_code) values (c, 'active', now(), upper('T442H' || pg_temp.tx('sfx')))
    returning id into a;
  insert into affiliate_accounts(auth_user_id, customer_id, affiliate_id, status) values (u, c, a, 'claimed');
end $$;
\ir ../../../supabase/442_referral_self_refusal_vague_and_rate_limited.sql
\set m4_failed :ERROR
\set m4_msg :LAST_ERROR_MESSAGE
rollback to savepoint m4;
-- M5 Another version of the function (a comment changed): refused.
savepoint m5;
select pg_temp.put_before('changed');
\ir ../../../supabase/442_referral_self_refusal_vague_and_rate_limited.sql
\set m5_failed :ERROR
\set m5_msg :LAST_ERROR_MESSAGE
rollback to savepoint m5;
-- M6 440 cannot be run after 442 (its guard of affiliate_referral_signup).
savepoint m6;
\ir ../../../supabase/440_affiliate_login_signup_identity_and_self_referral.sql
\set m6_failed :ERROR
\set m6_msg :LAST_ERROR_MESSAGE
rollback to savepoint m6;
\set ON_ERROR_STOP on
select pg_temp.check(:'m4_failed' = 'true' and :'m4_msg' like '442: 1 affiliate login(s) have no sign-up copy. Run 440 once more first%'
    and pg_temp.md5_now() = 'c76573912de0a4ded29e81e5c56c96d3',
  'M4 while an affiliate login has no sign-up copy, 442 refuses to patch (run 440 first): ' || :'m4_msg');
select pg_temp.check(:'m5_failed' = 'true' and :'m5_msg' like '442: public.affiliate_referral_signup(text,text,text,text,text,text) is not the version this was tested against%',
  'M5 another version of the function is refused: ' || :'m5_msg');
select pg_temp.check(:'m6_failed' = 'true' and :'m6_msg' like '440: public.affiliate_referral_signup(text,text,text,text,text,text) is not the version this was tested against%',
  'M6 440 refuses to run after 442: ' || :'m6_msg');
\endif

do $$
declare n int; m text;
begin
  select count(*), string_agg(msg, E'\n  ') into n, m from failed;
  if n > 0 then raise exception E'referral-self-442: % check(s) failed:\n  %', n, m; end if;
  raise notice 'referral-self-442: all checks passed';
end $$;
rollback;
