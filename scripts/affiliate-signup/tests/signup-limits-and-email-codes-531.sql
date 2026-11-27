-- Affiliate sign-up limits, the sign-in emails' budgets, the email code and the welcome WhatsApp
-- (531; security audit of 17 Nov 2026, M6; the user, 20 Nov 2026).
--
--   L  The limit rows: ('signup','ip') 10 an hour; ('signup','all') 30 an hour; ('send','all')
--      60, ('send_staff','all') 20 and ('email_day','email') 5 in 24 hours; the others as 200.
--   R  auth_email_reserve, bucket by bucket: a sign-up's buckets; a connection's 10 sign-ups;
--      the address's day (5 resends and resets in 24 hours, older ones not counted, a sign-up
--      not counted in it); a full limit for all sign-ups refuses and inserts nothing; a full 60
--      (or 20) does not stop a resend or reset at reserve; the null-connection path; the pause
--      first.
--   T  auth_email_take: only 'signup' or 'send' (never 'send_staff'), the address keys and the
--      login only with 'send'; 30 sign-ups, the 31st refused; a non-staff login, a null login,
--      an inactive or deleted staff profile draw on the 60, an active staff login on the 20; a
--      full 60 does not stop a staff send, a full 20 not a non-staff send; the login's own
--      address and a recipient's address, each at 5, refuse with either budget and insert
--      nothing; the recipient equal to the login's address is counted once; an address to look
--      up (a reset, before its link is made): unknown -> no_login, nothing counted; a staff
--      login's address -> the 20; an affiliate's -> the 60; a full budget refuses naming it; no
--      address's day added; with 'signup' or with a login -> a 531 error.
--   C  affiliate_email_code_issue: 'none' for no login, null, a login with no account, a staff
--      login, a disabled account, an already verified one; issued: 6 digits, the login's
--      address, 900 seconds, only a hash kept (the sha256 of the login and the code, not the
--      code), earlier codes retired.
--   F  confirm_affiliate_email_code: no caller raises; invalid; no_code (none, used, retired,
--      dead after 5 tries, staff, no account, disabled); wrong_code with tries_left and the 5th
--      too_many_tries; expired; the login's email changed after the code (another address, and
--      491's login_email_changed_at with the same address back); right -> verified, the login
--      copy and the audit entry as confirm_affiliate_email wrote, the code used; again ->
--      already.
--   E  confirm_affiliate_email(): use_code and nothing changed; verified and not an affiliate
--      as before.
--   O  complete_affiliate_onboarding, a new account: not verified by Supabase's own confirmation,
--      nor by a session from a magic link or a reset link (and no verified date written on the
--      login); verified from the date the server keeps on the login (378's carry-over); the code
--      then verifies an unverified one.
--   W  The WhatsApp name: a record there 24 hours or more before the login gives its name (24
--      hours exactly too); one made an hour before, or after the login, gives 'there'; typed
--      metadata never; 'reactivated' alike.
--   D  At most 30 welcomes in 24 hours: the 31st is kept skipped ('daily_limit'), its key taken;
--      an older one falls out of the window; skipped and expired ones are not counted, failed ones
--      (to be retried, or timed out and maybe gone) are: 30 failed, then the next is skipped;
--      'reactivated' is neither counted nor limited; the lock is held. (Two at once at 29 giving
--      exactly 30 needs two connections: welcome-limit-race-531.sh.)
--   G  The grants of every new or changed function; the codes table the owner's alone.
--   M  531 a second time changes nothing (when this file installs it).
--   U  scripts/affiliate-signup/undo-531.sql refuses, changing nothing, while another function or
--      a view uses 531's new functions or its table; otherwise it restores the public functions'
--      fingerprint; 531 again makes them as 531 did. (Two refusals are provoked on purpose: psql
--      prints their "ERROR:  undo-531: ..." lines.)
--
-- Disposable local database only; everything is rolled back. Every name and email is invented
-- (@example.invalid); phones are the fictional +61 491 570 6nn range. Run it on a copy of
-- production after 529 (530 or not): it applies 531 twice; with -v skip_install=1 where 531 is
-- already in. Where public.auth_email_limits has no rows (the local schema copies), the rows of
-- supabase/200_auth_email_delivery.sql are put in first, as production has them.
-- Every check runs, then the file fails if any did.
--   psql -X -v ON_ERROR_STOP=1 -f scripts/affiliate-signup/tests/signup-limits-and-email-codes-531.sql
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
insert into public.auth_email_limits (action, scope, max_attempts, window_seconds)
select * from (values ('signup','email',3,900), ('signup','ip',30,3600), ('resend','email',3,900),
                      ('resend','ip',30,3600), ('recovery','email',5,3600), ('recovery','ip',60,3600),
                      ('combined','ip',60,3600)) v(a, s, m, w)
 where not exists (select 1 from public.auth_email_limits)
on conflict do nothing;
create temp table fp0 as
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.oid::regprocedure::text)) || ' ' || count(*) as fp
    from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p');
select position('-- 531 (security audit' in pg_get_functiondef('public.auth_email_reserve(text,text,text)'::regprocedure)) > 0 as had531 \gset
\if :{?skip_install}
\elif :had531
\echo 531 is already in: run with -v skip_install=1
select 1/0;
\else
\ir ../../../supabase/531_the_affiliate_sign_up_limits_and_email_codes.sql
create temp table m531 as
  select p.oid::regprocedure::text as fn, md5(pg_get_functiondef(p.oid)) as md5, p.proacl::text as acl
    from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p');
create temp table m531t as
  select (select string_agg(column_name || ' ' || data_type || ' ' || is_nullable, ',' order by ordinal_position)
            from information_schema.columns where table_schema = 'public' and table_name = 'affiliate_email_codes') as cols,
         (select string_agg(pg_get_indexdef(indexrelid), ',' order by pg_get_indexdef(indexrelid))
            from pg_index where indrelid = 'public.affiliate_email_codes'::regclass) as idx,
         (select string_agg(conname || ' ' || pg_get_constraintdef(oid), ',' order by conname)
            from pg_constraint where conrelid in ('public.affiliate_email_codes'::regclass, 'public.auth_email_limits'::regclass)) as con,
         (select relacl::text from pg_class where oid = 'public.affiliate_email_codes'::regclass) as acl,
         (select string_agg(action || '/' || scope || '=' || max_attempts || ':' || window_seconds, ',' order by action, scope)
            from public.auth_email_limits) as lim;
\ir ../../../supabase/531_the_affiliate_sign_up_limits_and_email_codes.sql
\endif
set local lock_timeout = '10s';
set local statement_timeout = '300s';
create temp table failed(n serial, msg text);
create temp table ran(n serial);
create function pg_temp.check(ok boolean, msg text) returns void language plpgsql as
$$begin
  insert into ran default values;
  if ok is distinct from true then insert into failed(msg) values (msg); raise notice 'FAIL  %', msg;
  else raise notice 'PASS  %', msg; end if;
end$$;
create temp table fx(k text primary key, v uuid);
create temp table tx(k text primary key, v text);
create function pg_temp.fx(key text) returns uuid language sql as $$ select v from fx where k = key $$;
create function pg_temp.tx(key text) returns text language sql as $$ select v from tx where k = key $$;
create function pg_temp.put(key text, val text) returns void language sql as
$$ insert into tx values (key, val) on conflict (k) do update set v = excluded.v $$;
create function pg_temp.ph(n int) returns text language sql as $$ select '+61491570' || (600 + n)::text $$;
create function pg_temp.ev(a text, s text, k text) returns int language sql as
$$ select count(*)::int from public.auth_email_rate_events e where e.action = a and e.scope = s and e.key_hash = k $$;
create function pg_temp.evall() returns int language sql as $$ select count(*)::int from public.auth_email_rate_events $$;
-- An error as text, or the answer.
create function pg_temp.try(q text) returns jsonb language plpgsql as
$$declare r jsonb; begin
  begin execute q into r; exception when others then r := jsonb_build_object('error', sqlstate || ' ' || sqlerrm); end;
  return r;
end$$;
-- A call made by a signed-in login (null: signed out, as the authenticated role with no subject).
create function pg_temp.as_login(uid uuid, q text) returns jsonb language plpgsql as
$$declare r jsonb; begin
  perform set_config('request.jwt.claim.sub', coalesce(uid::text, ''), true);
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  begin
    execute 'set local role authenticated';
    execute q into r;
  exception when others then r := jsonb_build_object('error', sqlstate || ' ' || sqlerrm);
  end;
  execute 'reset role';
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.role', '', true);
  return r;
end$$;
-- A login (auth.users) with an email, made at a time, with typed sign-up metadata.
create function pg_temp.login(key text, made timestamptz default now(), meta jsonb default '{}'::jsonb) returns uuid language plpgsql as
$$declare u uuid := gen_random_uuid(); begin
  insert into auth.users(id, email, email_confirmed_at, created_at, raw_user_meta_data, raw_app_meta_data)
    values (u, 't531-' || lower(key) || '@example.invalid', now(), made, meta, '{"affiliate_email_unverified": true}'::jsonb);
  insert into fx values (key, u);
  return u;
end$$;
-- An affiliate: a customer made at a time, an active affiliate record, and the login's account.
create function pg_temp.affiliate(key text, first text, cust_made timestamptz, n int, login_made timestamptz default now(),
                                  meta jsonb default '{}'::jsonb, verified boolean default false, status text default 'claimed')
  returns uuid language plpgsql as
$$declare u uuid; c uuid; a uuid; begin
  u := pg_temp.login(key, login_made, meta);
  insert into public.customers(first_name, last_name, full_name, phone, created_at)
    values (first, 'Test' || key, first || ' Test' || key, pg_temp.ph(n), cust_made) returning id into c;
  insert into public.customer_affiliates(customer_id, status, activated_at, referral_code)
    values (c, 'active', now(), public.generate_affiliate_referral_code()) returning id into a;
  insert into public.affiliate_accounts(auth_user_id, customer_id, affiliate_id, status, email_verified_at)
    values (u, c, a, status, case when verified then now() - interval '1 day' end);
  insert into fx values ('c:' || key, c), ('a:' || key, a) on conflict (k) do nothing;
  return u;
end$$;

select pg_temp.check(not exists (select 1 from public.customers where public.normalize_customer_phone(phone) like '+614915706__'),
  '0 no customer uses the test phones +61 491 570 6nn (the checks below assume so)');

-- ═════ L the limit rows ═════
select pg_temp.check((select string_agg(action || '/' || scope || '=' || max_attempts || ':' || window_seconds, ',' order by action, scope)
                        from public.auth_email_limits)
    = 'combined/ip=60:3600,email_day/email=5:86400,recovery/email=5:3600,recovery/ip=60:3600,resend/email=3:900,resend/ip=30:3600,'
      || 'send/all=60:86400,send_staff/all=20:86400,signup/all=30:3600,signup/email=3:900,signup/ip=10:3600',
  'L1 the limit rows: signup/ip 10 an hour, signup/all 30 an hour, send/all 60, send_staff/all 20, email_day/email 5 in 24 hours; the rest as 200');
select pg_temp.check(pg_temp.try($q$insert into public.auth_email_limits values ('send_all','all',1,1)$q$) ? 'error'
    and pg_temp.try($q$insert into public.auth_email_limits values ('send','everyone',1,1)$q$) ? 'error',
  'L2 the checks still refuse an action or a scope 531 did not add');

-- ═════ R auth_email_reserve ═════
delete from public.auth_email_rate_events;
delete from public.auth_email_pauses;
select pg_temp.check(public.auth_email_reserve('signup', 'r-e1', 'r-ip1') = '{"allowed": true, "retry_after_seconds": 0}'::jsonb
    and pg_temp.ev('signup','email','r-e1') = 1 and pg_temp.ev('signup','ip','r-ip1') = 1 and pg_temp.ev('combined','ip','r-ip1') = 1
    and pg_temp.ev('email_day','email','r-e1') = 0 and pg_temp.ev('signup','all','all') = 0 and pg_temp.evall() = 3,
  'R1 a sign-up: its address, its connection and the connection''s total counted; not the address''s day, never the limit for all');
do $$ declare i int; r jsonb; begin
  for i in 2 .. 10 loop r := public.auth_email_reserve('signup', 'r-e' || i, 'r-ip1'); end loop;
  perform pg_temp.put('r2', public.auth_email_reserve('signup', 'r-e11', 'r-ip1')::text);
end $$;
select pg_temp.check(pg_temp.tx('r2')::jsonb = '{"allowed": false, "retry_after_seconds": 3600, "scope": "ip", "action": "signup"}'::jsonb
    and pg_temp.ev('signup','ip','r-ip1') = 10 and pg_temp.ev('signup','email','r-e11') = 0,
  'R2 a connection gets 10 sign-ups an hour; the 11th is refused by its connection and counts nothing: ' || pg_temp.tx('r2'));
-- The address's day: 3 resends (the resend limit is 3 in 15 minutes) and 2 resets, then refused.
do $$ declare r jsonb; begin
  r := public.auth_email_reserve('resend', 'r-day', 'r-ip2');
  r := public.auth_email_reserve('resend', 'r-day', 'r-ip2');
  r := public.auth_email_reserve('resend', 'r-day', null);
  r := public.auth_email_reserve('recovery', 'r-day', 'r-ip3');
  perform pg_temp.put('r3a', public.auth_email_reserve('recovery', 'r-day', 'r-ip4')::text);
  perform pg_temp.put('r3', public.auth_email_reserve('recovery', 'r-day', 'r-ip5')::text);
end $$;
select pg_temp.check(pg_temp.tx('r3a')::jsonb ->> 'allowed' = 'true'
    and pg_temp.tx('r3')::jsonb = '{"allowed": false, "retry_after_seconds": 86400, "scope": "email", "action": "email_day"}'::jsonb
    and pg_temp.ev('email_day','email','r-day') = 5 and pg_temp.ev('recovery','email','r-day') = 2
    and pg_temp.ev('recovery','ip','r-ip5') = 0,
  'R3 an address gets 5 resends and resets together in 24 hours (the null-connection call too); the 6th is refused by its day and counts nothing: ' || pg_temp.tx('r3'));
insert into public.auth_email_rate_events (action, scope, key_hash, occurred_at)
select 'email_day', 'email', 'r-old', now() - interval '25 hours' from generate_series(1, 5)
union all select 'email_day', 'email', 'r-aged', now() - interval '20 hours' from generate_series(1, 5);
select pg_temp.check(public.auth_email_reserve('recovery', 'r-old', null) ->> 'allowed' = 'true'
    and public.auth_email_reserve('recovery', 'r-aged', null) = '{"allowed": false, "retry_after_seconds": 14400, "scope": "email", "action": "email_day"}'::jsonb,
  'R4 the day is the last 24 hours: 5 from 25 hours ago do not count; 5 from 20 hours ago refuse for 4 more hours');
select pg_temp.check(public.auth_email_reserve('signup', 'r-day', 'r-ip6') ->> 'allowed' = 'true'
    and pg_temp.ev('signup','email','r-day') = 1,
  'R5 a sign-up is not counted in or stopped by the address''s day');
-- The limit for all sign-ups: 30 logins made in the last hour (an older one not counted).
insert into public.auth_email_rate_events (action, scope, key_hash, occurred_at)
select 'signup', 'all', 'all', now() - interval '30 minutes' from generate_series(1, 29)
union all select 'signup', 'all', 'all', now() - interval '61 minutes';
create temp table r6 as select pg_temp.evall() n;
select pg_temp.check(public.auth_email_reserve('signup', 'r-g1', 'r-ip7') ->> 'allowed' = 'true',
  'R6 29 logins made in the last hour (and one older): a sign-up is let through');
insert into public.auth_email_rate_events (action, scope, key_hash, occurred_at) values ('signup', 'all', 'all', now() - interval '10 minutes');
delete from r6; insert into r6 select pg_temp.evall();
select pg_temp.check(public.auth_email_reserve('signup', 'r-g2', 'r-ip8') = '{"allowed": false, "retry_after_seconds": 1800, "scope": "all", "action": "signup"}'::jsonb
    and public.auth_email_reserve('signup', 'r-g3', null) ->> 'scope' = 'all'
    and pg_temp.evall() = (select n from r6),
  'R7 30 logins made in the last hour: a sign-up is refused (scope all, action signup), with or without a connection, and nothing is counted');
insert into public.auth_email_rate_events (action, scope, key_hash)
select 'send', 'all', 'all' from generate_series(1, 60) union all select 'send_staff', 'all', 'all' from generate_series(1, 20);
select pg_temp.check(public.auth_email_reserve('recovery', 'r-s1', 'r-ip9') = '{"allowed": true, "retry_after_seconds": 0}'::jsonb
    and public.auth_email_reserve('resend', 'r-s2', null) = '{"allowed": true, "retry_after_seconds": 0}'::jsonb
    and pg_temp.ev('send','all','all') = 60 and pg_temp.ev('send_staff','all','all') = 20,
  'R8 a full 60 and a full 20 do not stop a resend or a reset at reserve (taken when sent), and reserve counts in neither');
insert into public.auth_email_pauses (action, reason) values ('signup', 'T531 pause');
select pg_temp.check(pg_temp.try($q$select public.auth_email_reserve('signup', 'r-p', 'r-ipp')$q$)->>'error' like '%AUTH_EMAIL_PAUSED: signup%',
  'R9 a paused sign-up is still refused first (405)');
delete from public.auth_email_pauses;
select pg_temp.check(pg_temp.try($q$select public.auth_email_reserve('magic_link', 'k', null)$q$)->>'error' like '%AUTH_EMAIL_UNKNOWN_ACTION%'
    and pg_temp.try($q$select public.auth_email_reserve('signup', '', null)$q$)->>'error' like '%AUTH_EMAIL_MISSING_EMAIL_KEY%',
  'R10 an unknown action and a missing address key raise as before');

-- ═════ T auth_email_take ═════
delete from public.auth_email_rate_events;
select pg_temp.login('tStaff');
insert into public.profiles (id, full_name, email, role, is_active, invitation_status)
  values (pg_temp.fx('tStaff'), 'T531 Staff', 't531-tstaff@example.invalid', 'staff', true, 'accepted');
select pg_temp.login('tOff');
insert into public.profiles (id, full_name, email, role, is_active, invitation_status)
  values (pg_temp.fx('tOff'), 'T531 Off', 't531-toff@example.invalid', 'staff', false, 'accepted');
select pg_temp.login('tGone');
insert into public.profiles (id, full_name, email, role, is_active, invitation_status, deleted_at)
  values (pg_temp.fx('tGone'), 'T531 Gone', 't531-tgone@example.invalid', 'staff', true, 'accepted', now());
select pg_temp.login('tPend');
insert into public.profiles (id, full_name, email, role, is_active, invitation_status)
  values (pg_temp.fx('tPend'), 'T531 Pend', 't531-tpend@example.invalid', 'staff', true, 'pending');
select pg_temp.login('tAff');
select pg_temp.check(pg_temp.try($q$select public.auth_email_take('send_staff')$q$)->>'error' like '%531: auth_email_take takes%'
    and pg_temp.try($q$select public.auth_email_take('recovery')$q$)->>'error' like '%531:%'
    and pg_temp.try($q$select public.auth_email_take(null)$q$)->>'error' like '%531:%'
    and pg_temp.try($q$select public.auth_email_take('signup', 'h')$q$)->>'error' like '%531:%'
    and pg_temp.try($q$select public.auth_email_take('signup', null, gen_random_uuid())$q$)->>'error' like '%531:%'
    and pg_temp.try($q$select public.auth_email_take('signup', null, null, 'h')$q$)->>'error' like '%531:%'
    and pg_temp.try($q$select public.auth_email_take('send', ' ')$q$)->>'error' like '%531:%'
    and pg_temp.evall() = 0,
  'T1 only ''signup'' or ''send'' (never ''send_staff''), the address keys and the login only with ''send''; refused with a 531 error, nothing counted');
do $$ declare i int; r jsonb; begin
  for i in 1 .. 30 loop r := public.auth_email_take('signup');
    if r <> '{"allowed": true, "retry_after_seconds": 0}'::jsonb then perform pg_temp.put('t2bad', r::text); end if; end loop;
  perform pg_temp.put('t2', public.auth_email_take('signup')::text);
end $$;
select pg_temp.check(pg_temp.tx('t2bad') is null
    and pg_temp.tx('t2')::jsonb = '{"allowed": false, "retry_after_seconds": 3600, "scope": "all", "action": "signup"}'::jsonb
    and pg_temp.ev('signup','all','all') = 30 and pg_temp.evall() = 30,
  'T2 30 logins made an hour are each counted; the 31st is refused (all, signup) and counts nothing: ' || pg_temp.tx('t2'));
select pg_temp.check(public.auth_email_reserve('signup', 't-e', 't-ip')->>'scope' = 'all',
  'T3 and reserve then refuses the next sign-up');
delete from public.auth_email_rate_events;
-- Non-staff sends: a null login, an affiliate login, inactive, deleted and pending staff profiles.
do $$ declare i int; r jsonb; v uuid; begin
  for i in 1 .. 12 loop
    v := case i % 6 when 0 then null when 1 then pg_temp.fx('tAff') when 2 then pg_temp.fx('tOff')
                    when 3 then pg_temp.fx('tGone') when 4 then pg_temp.fx('tPend') else gen_random_uuid() end;
    r := public.auth_email_take('send', null, v);
    if r ->> 'allowed' <> 'true' then perform pg_temp.put('t4bad', r::text); end if;
  end loop;
end $$;
select pg_temp.check(pg_temp.tx('t4bad') is null and pg_temp.ev('send','all','all') = 12 and pg_temp.ev('send_staff','all','all') = 0,
  'T4 sends for no login, an affiliate login, an unknown login, and inactive, deleted or pending staff profiles draw on the 60, not the 20');
do $$ declare i int; r jsonb; begin
  for i in 1 .. 20 loop r := public.auth_email_take('send', null, pg_temp.fx('tStaff'));
    if r ->> 'allowed' <> 'true' then perform pg_temp.put('t5bad', r::text); end if; end loop;
  perform pg_temp.put('t5', public.auth_email_take('send', null, pg_temp.fx('tStaff'))::text);
end $$;
select pg_temp.check(pg_temp.tx('t5bad') is null and pg_temp.ev('send_staff','all','all') = 20 and pg_temp.ev('send','all','all') = 12
    and pg_temp.tx('t5')::jsonb = '{"allowed": false, "retry_after_seconds": 86400, "scope": "all", "action": "send_staff"}'::jsonb,
  'T5 an active staff login''s sends draw on the 20, not the 60; the 21st is refused (all, send_staff): ' || pg_temp.tx('t5'));
select pg_temp.check(public.auth_email_take('send', null, pg_temp.fx('tAff')) ->> 'allowed' = 'true'
    and public.auth_email_take('send') ->> 'allowed' = 'true' and pg_temp.ev('send','all','all') = 14,
  'T6 a full 20 does not stop a non-staff send');
insert into public.auth_email_rate_events (action, scope, key_hash) select 'send', 'all', 'all' from generate_series(1, 46);
delete from public.auth_email_rate_events where action = 'send_staff' and id in
  (select id from public.auth_email_rate_events where action = 'send_staff' order by id limit 1);
select pg_temp.check(public.auth_email_take('send') = '{"allowed": false, "retry_after_seconds": 86400, "scope": "all", "action": "send"}'::jsonb
    and public.auth_email_take('send', null, pg_temp.fx('tAff')) ->> 'action' = 'send'
    and public.auth_email_take('send', null, pg_temp.fx('tStaff')) = '{"allowed": true, "retry_after_seconds": 0}'::jsonb
    and pg_temp.ev('send','all','all') = 60 and pg_temp.ev('send_staff','all','all') = 20,
  'T7 a full 60 refuses a non-staff send (all, send) but not a staff send, which takes the 20''s last place');
-- The address's day at take, with either budget.
delete from public.auth_email_rate_events;
insert into public.auth_email_rate_events (action, scope, key_hash) select 'email_day', 'email', 't-own5' from generate_series(1, 5);
insert into public.auth_email_rate_events (action, scope, key_hash) select 'email_day', 'email', 't-rcpt5' from generate_series(1, 5);
insert into public.auth_email_rate_events (action, scope, key_hash) select 'email_day', 'email', 't-own4' from generate_series(1, 4);
create temp table t8 as select pg_temp.evall() n;
select pg_temp.check(public.auth_email_take('send', 't-own5') = '{"allowed": false, "retry_after_seconds": 86400, "scope": "email", "action": "email_day"}'::jsonb
    and public.auth_email_take('send', 't-own5', pg_temp.fx('tStaff')) ->> 'action' = 'email_day'
    and public.auth_email_take('send', 't-own5', pg_temp.fx('tAff')) ->> 'action' = 'email_day'
    and pg_temp.evall() = (select n from t8),
  'T8 the login''s own address at 5 refuses (email, email_day) with the 60 and with the 20, and nothing is counted');
select pg_temp.check(public.auth_email_take('send', 't-own4', pg_temp.fx('tAff'), 't-rcpt5')
      = '{"allowed": false, "retry_after_seconds": 86400, "scope": "email", "action": "email_day"}'::jsonb
    and public.auth_email_take('send', 't-own4', pg_temp.fx('tStaff'), 't-rcpt5') ->> 'action' = 'email_day'
    and public.auth_email_take('send', null, null, 't-rcpt5') ->> 'action' = 'email_day'
    and pg_temp.evall() = (select n from t8),
  'T9 a recipient''s address at 5 refuses though the login''s own address (4) and the budgets have room, and nothing is counted');
select pg_temp.check(public.auth_email_take('send', 't-own4', pg_temp.fx('tAff'), 't-new') = '{"allowed": true, "retry_after_seconds": 0}'::jsonb
    and pg_temp.ev('email_day','email','t-own4') = 5 and pg_temp.ev('email_day','email','t-new') = 1 and pg_temp.ev('send','all','all') = 1
    and pg_temp.evall() = (select n from t8) + 3,
  'T10 with room everywhere: the budget, the login''s address and the recipient''s are each counted once');
select pg_temp.check(public.auth_email_take('send', 't-same', pg_temp.fx('tStaff'), 't-same') ->> 'allowed' = 'true'
    and pg_temp.ev('email_day','email','t-same') = 1 and pg_temp.ev('send_staff','all','all') = 1,
  'T11 a recipient equal to the login''s address is counted once; a staff send on the 20');
select pg_temp.check(public.auth_email_take('send', 't-own4') ->> 'action' = 'email_day',
  'T12 and that address, now at 5, is refused by its day');
-- An address to look up (a reset takes its place before its link is made).
delete from public.auth_email_rate_events;
select pg_temp.check(public.auth_email_take('send', null, null, null, 't531-nobody@example.invalid')
      = '{"allowed": false, "retry_after_seconds": 0, "scope": "email", "action": "no_login"}'::jsonb
    and public.auth_email_take('send', null, null, null, '') ->> 'action' = 'no_login'
    and pg_temp.evall() = 0,
  'T13 an address with no login: no_login, nothing counted');
select pg_temp.check(public.auth_email_take('send', null, null, null, '  T531-TSTAFF@example.invalid ') = '{"allowed": true, "retry_after_seconds": 0}'::jsonb
    and pg_temp.ev('send_staff','all','all') = 1 and pg_temp.ev('send','all','all') = 0
    and public.auth_email_take('send', null, null, null, 't531-taff@example.invalid') = '{"allowed": true, "retry_after_seconds": 0}'::jsonb
    and pg_temp.ev('send','all','all') = 1 and pg_temp.ev('send_staff','all','all') = 1
    and public.auth_email_take('send', null, null, null, 't531-toff@example.invalid') ->> 'allowed' = 'true'
    and pg_temp.ev('send','all','all') = 2
    and pg_temp.evall() = 3,
  'T14 a staff login''s address (any case, spaces round it) draws on the 20, an affiliate''s and an inactive staff profile''s on the 60; no address''s day is added');
insert into public.auth_email_rate_events (action, scope, key_hash) select 'send', 'all', 'all' from generate_series(1, 58);
insert into public.auth_email_rate_events (action, scope, key_hash) select 'send_staff', 'all', 'all' from generate_series(1, 19);
create temp table t15 as select pg_temp.evall() n;
select pg_temp.check(public.auth_email_take('send', null, null, null, 't531-taff@example.invalid')
      = '{"allowed": false, "retry_after_seconds": 86400, "scope": "all", "action": "send"}'::jsonb
    and public.auth_email_take('send', null, null, null, 't531-tstaff@example.invalid')
      = '{"allowed": false, "retry_after_seconds": 86400, "scope": "all", "action": "send_staff"}'::jsonb
    and pg_temp.evall() = (select n from t15),
  'T15 a full 60 refuses an affiliate''s address (all, send), a full 20 a staff address (all, send_staff); nothing counted');
select pg_temp.login('tOld2');
update auth.users set email = 'T531-Twin@example.invalid', created_at = now() - interval '2 days' where id = pg_temp.fx('tOld2');
insert into public.profiles (id, full_name, email, role, is_active, invitation_status)
  values (pg_temp.fx('tOld2'), 'T531 Twin', 't531-twin-p@example.invalid', 'staff', true, 'accepted');
delete from public.auth_email_rate_events;
select pg_temp.check(public.auth_email_take('send', null, null, null, 't531-twin@example.invalid') ->> 'allowed' = 'true'
    and pg_temp.ev('send_staff','all','all') = 1,
  'T16 the login is found as auth_email_user_state finds it (an address stored in capitals, typed in lower case)');
select pg_temp.check(pg_temp.try($q$select public.auth_email_take('signup', null, null, null, 't531-taff@example.invalid')$q$)->>'error' like '%531: auth_email_take takes an address to look up%'
    and pg_temp.try(format('select public.auth_email_take(%L, null, %L, null, %L)', 'send', pg_temp.fx('tAff'), 't531-taff@example.invalid'))->>'error' like '%531: auth_email_take takes an address to look up%'
    and pg_temp.ev('send_staff','all','all') = 1 and pg_temp.evall() = 1,
  'T17 an address to look up with ''signup'', or together with a login: a 531 error');

-- ═════ C affiliate_email_code_issue ═════
select pg_temp.affiliate('cA', 'Ada', now() - interval '3 days', 1);
select pg_temp.affiliate('cB', 'Bea', now() - interval '3 days', 2, verified := true);
select pg_temp.affiliate('cD', 'Dee', now() - interval '3 days', 3, status := 'disabled');
select pg_temp.affiliate('cS', 'Sam', now() - interval '3 days', 4);
insert into public.profiles (id, full_name, email, role, is_active, invitation_status)
  values (pg_temp.fx('cS'), 'T531 Sam', 't531-cs@example.invalid', 'staff', true, 'accepted');
select pg_temp.login('cN');
select pg_temp.affiliate('cE', 'Eve', now() - interval '3 days', 5);
update auth.users set email = null where id = pg_temp.fx('cE');
-- (Each answer is kept first: a query does not see what the functions it calls write.)
select pg_temp.put('c1', jsonb_build_array(public.affiliate_email_code_issue(null), public.affiliate_email_code_issue(gen_random_uuid()),
    public.affiliate_email_code_issue(pg_temp.fx('cN')), public.affiliate_email_code_issue(pg_temp.fx('cB')),
    public.affiliate_email_code_issue(pg_temp.fx('cD')), public.affiliate_email_code_issue(pg_temp.fx('cS')),
    public.affiliate_email_code_issue(pg_temp.fx('cE')))::text);
select pg_temp.check((select bool_and(x = '{"status": "none"}'::jsonb) and count(*) = 7 from jsonb_array_elements(pg_temp.tx('c1')::jsonb) x)
    and not exists (select 1 from public.affiliate_email_codes c join fx on fx.v = c.auth_user_id),
  'C1 none, alike, for no login, an unknown login, a login with no account, a verified one, a disabled account, a staff login and a login with no address; no code made');
select pg_temp.put('c2', public.affiliate_email_code_issue(pg_temp.fx('cA'))::text);
select pg_temp.check(pg_temp.tx('c2')::jsonb ->> 'status' = 'issued'
    and pg_temp.tx('c2')::jsonb ->> 'code' ~ '^[0-9]{6}$'
    and pg_temp.tx('c2')::jsonb ->> 'email' = 't531-ca@example.invalid'
    and pg_temp.tx('c2')::jsonb -> 'expires_in_seconds' = '900'::jsonb
    and (select count(*) from jsonb_object_keys(pg_temp.tx('c2')::jsonb)) = 4,
  'C2 issued: status, a 6-digit code, the login''s address, 900 seconds');
select pg_temp.check((select count(*) = 1
                             and bool_and(c.code_hash = encode(sha256(convert_to(c.auth_user_id::text || ':' || (pg_temp.tx('c2')::jsonb ->> 'code'), 'UTF8')), 'hex'))
                             and bool_and(c.code_hash <> pg_temp.tx('c2')::jsonb ->> 'code')
                             and bool_and(c.code_hash <> encode(sha256(convert_to(pg_temp.tx('c2')::jsonb ->> 'code', 'UTF8')), 'hex'))
                             and bool_and(c.email <> pg_temp.tx('c2')::jsonb ->> 'code')
                             and bool_and(c.email = 't531-ca@example.invalid' and c.tries = 0 and c.used_at is null and c.retired_at is null
                                          and c.expires_at - c.created_at = interval '15 minutes')
                        from public.affiliate_email_codes c where c.auth_user_id = pg_temp.fx('cA')),
  'C3 kept: only the sha256 of the login and the code (not the code, not its plain hash), the address, 15 minutes, no tries');
select pg_temp.put('c4', public.affiliate_email_code_issue(pg_temp.fx('cA'))::text);
select pg_temp.check((select count(*) filter (where retired_at is null) = 1 and count(*) = 2
                             and bool_and(retired_at is not null or code_hash = encode(sha256(convert_to(auth_user_id::text || ':' || (pg_temp.tx('c4')::jsonb ->> 'code'), 'UTF8')), 'hex'))
                        from public.affiliate_email_codes where auth_user_id = pg_temp.fx('cA')),
  'C4 a new code retires the earlier one; one live code, the newest');
do $$ declare i int; s text := ''; r jsonb; begin
  for i in 1 .. 40 loop
    r := public.affiliate_email_code_issue(pg_temp.fx('cB'));  -- none: verified
  end loop;
  for i in 1 .. 40 loop s := s || (public.affiliate_email_code_issue(pg_temp.fx('cA'))->>'code') || ','; end loop;
  perform pg_temp.put('c5', s);
end $$;
select pg_temp.check((select count(distinct x) >= 38 and bool_and(x ~ '^[0-9]{6}$')
                        from unnest(string_to_array(rtrim(pg_temp.tx('c5'), ','), ',')) x)
    and (select count(*) filter (where retired_at is null) from public.affiliate_email_codes where auth_user_id = pg_temp.fx('cA')) = 1,
  'C5 40 codes in a row: 6 digits each, (nearly) all different, one live');

-- ═════ F confirm_affiliate_email_code ═════
select pg_temp.check(pg_temp.as_login(null, $q$select public.confirm_affiliate_email_code('123456')$q$)->>'error' like '42501 %',
  'F1 no caller: raised (not authenticated)');
select pg_temp.put('codeA', public.affiliate_email_code_issue(pg_temp.fx('cA'))->>'code');
create function pg_temp.conf(key text, code text) returns jsonb language sql as
$$ select pg_temp.as_login(pg_temp.fx(key), format('select public.confirm_affiliate_email_code(%L)', code)) $$;
create function pg_temp.wrong(c text) returns text language sql as
$$ select lpad(((c::int + 1) % 1000000)::text, 6, '0') $$;
select pg_temp.check(pg_temp.conf('cA', '12345') = '{"verified": false, "reason": "invalid"}'::jsonb
    and pg_temp.conf('cA', '1234567') = '{"verified": false, "reason": "invalid"}'::jsonb
    and pg_temp.conf('cA', 'abcdef') = '{"verified": false, "reason": "invalid"}'::jsonb
    and pg_temp.conf('cA', ' 123456') = '{"verified": false, "reason": "invalid"}'::jsonb
    and pg_temp.conf('cA', null) = '{"verified": false, "reason": "invalid"}'::jsonb
    and (select tries from public.affiliate_email_codes where auth_user_id = pg_temp.fx('cA') and retired_at is null) = 0,
  'F2 not six digits: invalid, and no try counted');
select pg_temp.put('f3a', pg_temp.conf('cA', pg_temp.wrong(pg_temp.tx('codeA')))::text);
select pg_temp.put('f3b', pg_temp.conf('cA', pg_temp.wrong(pg_temp.tx('codeA')))::text);
select pg_temp.put('f3c', pg_temp.conf('cA', pg_temp.wrong(pg_temp.tx('codeA')))::text);
select pg_temp.put('f3d', pg_temp.conf('cA', pg_temp.wrong(pg_temp.tx('codeA')))::text);
select pg_temp.check(pg_temp.tx('f3a')::jsonb = '{"verified": false, "reason": "wrong_code", "tries_left": 4}'::jsonb
    and pg_temp.tx('f3b')::jsonb ->> 'tries_left' = '3' and pg_temp.tx('f3c')::jsonb ->> 'tries_left' = '2'
    and pg_temp.tx('f3d')::jsonb = '{"verified": false, "reason": "wrong_code", "tries_left": 1}'::jsonb,
  'F3 a wrong code: wrong_code, with 4, 3, 2, 1 tries left');
select pg_temp.put('f4a', pg_temp.conf('cA', pg_temp.wrong(pg_temp.tx('codeA')))::text);
select pg_temp.put('f4b', pg_temp.conf('cA', pg_temp.tx('codeA'))::text);
select pg_temp.check(pg_temp.tx('f4a')::jsonb = '{"verified": false, "reason": "too_many_tries"}'::jsonb
    and pg_temp.tx('f4b')::jsonb = '{"verified": false, "reason": "no_code"}'::jsonb
    and (select email_verified_at from public.affiliate_accounts where auth_user_id = pg_temp.fx('cA')) is null
    and (select tries from public.affiliate_email_codes where auth_user_id = pg_temp.fx('cA') and retired_at is null) = 5,
  'F4 the 5th wrong code ends it (too_many_tries); then even the right code gets no_code, and nothing is verified');
select pg_temp.put('codeA', public.affiliate_email_code_issue(pg_temp.fx('cA'))->>'code');
select pg_temp.put('codeA2', public.affiliate_email_code_issue(pg_temp.fx('cA'))->>'code');
select pg_temp.check(pg_temp.tx('codeA') = pg_temp.tx('codeA2')
    or pg_temp.conf('cA', pg_temp.tx('codeA')) = '{"verified": false, "reason": "wrong_code", "tries_left": 4}'::jsonb,
  'F5 a retired code (an earlier email''s) is a wrong code for the newest one');
update public.affiliate_email_codes set expires_at = clock_timestamp() - interval '1 second'
 where auth_user_id = pg_temp.fx('cA') and retired_at is null;
select pg_temp.check(pg_temp.conf('cA', pg_temp.tx('codeA2')) = '{"verified": false, "reason": "expired"}'::jsonb
    and (select email_verified_at from public.affiliate_accounts where auth_user_id = pg_temp.fx('cA')) is null,
  'F6 the newest code ended (15 minutes): expired, even with the right code');
-- The login's email changes after the code: another address, then the same address back (491).
select pg_temp.put('codeA', public.affiliate_email_code_issue(pg_temp.fx('cA'))->>'code');
update auth.users set email = 't531-ca-new@example.invalid' where id = pg_temp.fx('cA');
select pg_temp.check(pg_temp.conf('cA', pg_temp.tx('codeA')) = '{"verified": false, "reason": "no_code"}'::jsonb,
  'F7 the login''s email changed to another address after the code: the code is void (no_code)');
update auth.users set email = 't531-ca@example.invalid' where id = pg_temp.fx('cA');
update public.affiliate_accounts set login_email_changed_at = clock_timestamp() where auth_user_id = pg_temp.fx('cA');
select pg_temp.check(pg_temp.conf('cA', pg_temp.tx('codeA')) = '{"verified": false, "reason": "no_code"}'::jsonb
    and (select email_verified_at from public.affiliate_accounts where auth_user_id = pg_temp.fx('cA')) is null,
  'F8 changed and back to the same address: a code from before login_email_changed_at is void (no_code)');
select pg_temp.put('codeA', public.affiliate_email_code_issue(pg_temp.fx('cA'))->>'code');
create temp table f9 as select (select count(*) from public.audit_logs where record_id = (select id from public.affiliate_accounts where auth_user_id = pg_temp.fx('cA'))
                                   and action = 'affiliate_email_verified') n;
select pg_temp.put('f9', pg_temp.conf('cA', pg_temp.tx('codeA'))::text);
select pg_temp.check(pg_temp.tx('f9')::jsonb = '{"verified": true}'::jsonb
    and (select a.email_verified_at is not null and a.updated_at = a.email_verified_at
           from public.affiliate_accounts a where a.auth_user_id = pg_temp.fx('cA'))
    and (select used_at is not null from public.affiliate_email_codes where auth_user_id = pg_temp.fx('cA') and retired_at is null)
    and (select not (u.raw_app_meta_data ? 'affiliate_email_unverified')
                and (u.raw_app_meta_data ->> 'affiliate_email_verified_at')::timestamptz
                    = (select email_verified_at from public.affiliate_accounts where auth_user_id = u.id)
           from auth.users u where u.id = pg_temp.fx('cA')),
  'F9 the right code: verified; the account''s email_verified_at, the login''s copy (app_metadata) and the code''s used_at are set: ' || pg_temp.tx('f9'));
select pg_temp.check((select count(*) = (select n from f9) + 1
                             and bool_and(l.table_name = 'affiliate_accounts' and l.module = 'affiliate'
                                          and l.old_data = '{"email_verified_at": null}'::jsonb
                                          and l.new_data = jsonb_build_object('auth_user_id', pg_temp.fx('cA'), 'customer_id', pg_temp.fx('c:cA'),
                                                                              'email_verified_at', a.email_verified_at))
                        from public.audit_logs l join public.affiliate_accounts a on a.id = l.record_id
                       where a.auth_user_id = pg_temp.fx('cA') and l.action = 'affiliate_email_verified'),
  'F10 one audit entry, the same as confirm_affiliate_email wrote (affiliate_email_verified, its old and new data)');
select pg_temp.check(pg_temp.conf('cA', pg_temp.tx('codeA')) = '{"verified": true, "already": true}'::jsonb
    and pg_temp.conf('cA', 'nonsense') = '{"verified": true, "already": true}'::jsonb
    and public.affiliate_email_code_issue(pg_temp.fx('cA')) = '{"status": "none"}'::jsonb,
  'F11 a second confirm: already (whatever is typed); and no new code for a verified login');
update public.affiliate_accounts set email_verified_at = null where auth_user_id = pg_temp.fx('cA');
select pg_temp.check(pg_temp.conf('cA', pg_temp.tx('codeA')) = '{"verified": false, "reason": "no_code"}'::jsonb,
  'F12 a used code never verifies again (no_code)');
select pg_temp.affiliate('cF', 'Fay', now() - interval '3 days', 6);
select pg_temp.put('codeD', coalesce(public.affiliate_email_code_issue(pg_temp.fx('cF'))->>'code', ''));
update public.affiliate_accounts set status = 'disabled' where auth_user_id = pg_temp.fx('cF');
select pg_temp.check(pg_temp.conf('cF', pg_temp.tx('codeD')) = '{"verified": false, "reason": "no_code"}'::jsonb
    and pg_temp.conf('cS', '123456') = '{"verified": false, "reason": "no_code"}'::jsonb
    and pg_temp.conf('cN', '123456') = '{"verified": false, "reason": "no_code"}'::jsonb
    and pg_temp.conf('cB', '123456') = '{"verified": true, "already": true}'::jsonb
    and (select tries from public.affiliate_email_codes where auth_user_id = pg_temp.fx('cF')) = 0,
  'F13 a disabled account (with its right code), a staff login and a login with no account: no_code; a verified one: already');
select pg_temp.affiliate('cG', 'Gil', now() - interval '3 days', 7);
select pg_temp.check(pg_temp.conf('cG', '123456') = '{"verified": false, "reason": "no_code"}'::jsonb,
  'F14 an affiliate with no code at all: no_code');
select pg_temp.check(pg_get_functiondef('public.confirm_affiliate_email_code(text)'::regprocedure) ~ 'for update;'
    and (select count(*) from regexp_matches(pg_get_functiondef('public.confirm_affiliate_email_code(text)'::regprocedure), 'for update', 'g')) = 2,
  'F15 the account and the code row are read for update (two tries at once are counted one after the other)');

-- ═════ E confirm_affiliate_email() ═════
select pg_temp.affiliate('eA', 'Eli', now() - interval '3 days', 8);
create temp table e1 as
  select (select to_jsonb(a) from public.affiliate_accounts a where a.auth_user_id = pg_temp.fx('eA')) acct,
         (select raw_app_meta_data from auth.users where id = pg_temp.fx('eA')) meta,
         (select count(*) from public.audit_logs) logs;
-- As if the session came from an emailed link (amr magiclink, now), which verified before 531.
create function pg_temp.as_link(uid uuid, q text) returns jsonb language plpgsql as
$$declare r jsonb; begin
  perform set_config('request.jwt.claim.sub', uid::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated', 'session_id', gen_random_uuid(),
    'amr', json_build_array(json_build_object('method', 'magiclink', 'timestamp', extract(epoch from now())::bigint)))::text, true);
  begin
    execute 'set local role authenticated';
    execute q into r;
  exception when others then r := jsonb_build_object('error', sqlstate || ' ' || sqlerrm);
  end;
  execute 'reset role';
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
  return r;
end$$;
select pg_temp.put('e1a', pg_temp.as_link(pg_temp.fx('eA'), 'select public.confirm_affiliate_email()')::text);
select pg_temp.put('e1b', pg_temp.as_login(pg_temp.fx('eA'), 'select public.confirm_affiliate_email()')::text);
select pg_temp.check(pg_temp.tx('e1a')::jsonb = '{"verified": false, "reason": "use_code"}'::jsonb
    and pg_temp.tx('e1b')::jsonb = '{"verified": false, "reason": "use_code"}'::jsonb
    and (select to_jsonb(a) from public.affiliate_accounts a where a.auth_user_id = pg_temp.fx('eA')) = (select acct from e1)
    and (select raw_app_meta_data from auth.users where id = pg_temp.fx('eA')) = (select meta from e1)
    and (select count(*) from public.audit_logs) = (select logs from e1),
  'E1 confirm_affiliate_email: use_code, from an emailed link''s session too; the account, the login and the audit log unchanged');
select pg_temp.check(pg_temp.as_login(pg_temp.fx('cB'), 'select public.confirm_affiliate_email()') ->> 'already' = 'true'
    and pg_temp.as_login(pg_temp.fx('cB'), 'select public.confirm_affiliate_email()') ? 'verified_at'
    and pg_temp.as_login(pg_temp.fx('cN'), 'select public.confirm_affiliate_email()') = '{"verified": false, "reason": "not_affiliate"}'::jsonb
    and pg_temp.as_login(null, 'select public.confirm_affiliate_email()') ->> 'error' like '42501 %',
  'E2 a verified login and a login with no account are answered as before; no caller raised as before');

-- ═════ O the sign-up's new account ═════
-- A session of a login opened with an emailed link (amr magiclink or recovery, a minute ago).
create function pg_temp.as_amr(uid uuid, method text, q text) returns jsonb language plpgsql as
$$declare r jsonb; begin
  perform set_config('request.jwt.claim.sub', uid::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated',
    'amr', json_build_array(json_build_object('method', method, 'timestamp', extract(epoch from now())::bigint - 60)))::text, true);
  begin
    execute 'set local role authenticated';
    execute q into r;
  exception when others then r := jsonb_build_object('error', sqlstate || ' ' || sqlerrm);
  end;
  execute 'reset role';
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.role', '', true);
  perform set_config('request.jwt.claims', '', true);
  return r;
end$$;
select pg_temp.login('oConf');   -- Supabase confirmed it (email_confirmed_at), no server mark at all
update auth.users set raw_app_meta_data = '{}'::jsonb where id = pg_temp.fx('oConf');
select pg_temp.login('oReset');  -- made by the sign-up function (affiliate_email_unverified)
select pg_temp.login('oCarry');  -- an account an Owner unlinked: the server kept its verified date
update auth.users set raw_app_meta_data = '{"affiliate_email_verified_at": "2026-11-01T10:00:00+00:00"}'::jsonb where id = pg_temp.fx('oCarry');
select pg_temp.put('o1', pg_temp.as_amr(pg_temp.fx('oConf'), 'magiclink',
  $q$select public.complete_affiliate_onboarding('Ola', 'Testconf', '+61491570640', true)$q$)::text);
select pg_temp.put('o2', pg_temp.as_amr(pg_temp.fx('oReset'), 'recovery',
  $q$select public.complete_affiliate_onboarding('Rio', 'Testreset', '+61491570641', true)$q$)::text);
select pg_temp.put('o3', pg_temp.as_amr(pg_temp.fx('oCarry'), 'password',
  $q$select public.complete_affiliate_onboarding('Cai', 'Testcarry', '+61491570642', true)$q$)::text);
select pg_temp.check(pg_temp.tx('o1')::jsonb ->> 'status' = 'active' and pg_temp.tx('o1')::jsonb -> 'email_verified' = 'false'::jsonb
    and (select email_verified_at is null from public.affiliate_accounts where auth_user_id = pg_temp.fx('oConf'))
    and (select not (raw_app_meta_data ? 'affiliate_email_verified_at') from auth.users where id = pg_temp.fx('oConf')),
  'O1 a login Supabase confirmed, signing up from a magic link''s session: a new account, not verified, and no verified date written on the login: ' || pg_temp.tx('o1'));
select pg_temp.check(pg_temp.tx('o2')::jsonb ->> 'status' = 'active' and pg_temp.tx('o2')::jsonb -> 'email_verified' = 'false'::jsonb
    and (select email_verified_at is null from public.affiliate_accounts where auth_user_id = pg_temp.fx('oReset'))
    and (select not (raw_app_meta_data ? 'affiliate_email_verified_at') and raw_app_meta_data ? 'affiliate_email_unverified'
           from auth.users where id = pg_temp.fx('oReset')),
  'O2 a login the sign-up made, signing up from a reset link''s session: not verified, the login unchanged: ' || pg_temp.tx('o2'));
select pg_temp.check(pg_temp.tx('o3')::jsonb -> 'email_verified' = 'true'::jsonb
    and (select email_verified_at = '2026-11-01T10:00:00+00:00'::timestamptz from public.affiliate_accounts where auth_user_id = pg_temp.fx('oCarry')),
  'O3 a login carrying the server''s verified date (378''s unlink): verified, from that date');
select pg_temp.put('o4c', public.affiliate_email_code_issue(pg_temp.fx('oReset'))->>'code');
select pg_temp.put('o4', pg_temp.conf('oReset', pg_temp.tx('o4c'))::text);
select pg_temp.check(pg_temp.tx('o4')::jsonb = '{"verified": true}'::jsonb
    and (select email_verified_at is not null from public.affiliate_accounts where auth_user_id = pg_temp.fx('oReset')),
  'O4 the code from the verify email then verifies it');
select pg_temp.check(pg_temp.as_amr(pg_temp.fx('oConf'), 'magiclink',
      $q$select public.complete_affiliate_onboarding('Ola', 'Testconf', '+61491570640', true)$q$) -> 'email_verified' = 'false'::jsonb,
  'O5 signing up again from a link (already onboarded) is answered as before and verifies nothing');

-- ═════ W the WhatsApp name ═════
delete from public.affiliate_whatsapp_outbox;
create function pg_temp.wa(key text, kind text default 'welcome') returns public.affiliate_whatsapp_outbox language sql as
$$ select o from public.affiliate_whatsapp_outbox o where o.auth_user_id = pg_temp.fx(key) and o.kind = $2 order by o.id desc limit 1 $$;
-- The sign-up typed 'Typed' (metadata); the record says 'Olive' etc.
select pg_temp.affiliate('wOld', 'Olive', now() - interval '3 days', 20, now(), '{"first_name": "Typed", "phone": "+61491570620"}');
select pg_temp.affiliate('wDay', 'Dora', now() - interval '24 hours', 21, now(), '{"first_name": "Typed"}');
select pg_temp.affiliate('wHour', 'Hugo', now() - interval '1 hour', 22, now(), '{"first_name": "Typed"}');
select pg_temp.affiliate('wNew', 'Nell', now(), 23, now() - interval '10 minutes', '{"first_name": "Typed"}');
select pg_temp.affiliate('wSame', 'Sue', now() - interval '23 hours 59 minutes', 24, now(), '{"first_name": "Typed"}');
select pg_temp.check((pg_temp.wa('wOld')).first_name = 'Olive' and (pg_temp.wa('wOld')).message like 'Hi Olive, welcome to the Energia affiliate programme!%'
    and (pg_temp.wa('wOld')).status = 'queued',
  'W1 a record there 3 days before the login: its first name (Hi Olive), not the typed one: ' || coalesce((pg_temp.wa('wOld')).first_name, 'null'));
select pg_temp.check((pg_temp.wa('wDay')).first_name = 'Dora',
  'W2 a record there exactly 24 hours before the login: its name');
select pg_temp.check((pg_temp.wa('wHour')).first_name is null and (pg_temp.wa('wHour')).message like 'Hi there, welcome%'
    and (pg_temp.wa('wSame')).first_name is null,
  'W3 a record made an hour (or 23 h 59 min) before the login: Hi there, not its name, nor the typed one');
select pg_temp.check((pg_temp.wa('wNew')).first_name is null and (pg_temp.wa('wNew')).message like 'Hi there, welcome%',
  'W4 a record made after the login (the sign-up''s fresh record): Hi there');
select pg_temp.check(not exists (select 1 from public.affiliate_whatsapp_outbox where first_name = 'Typed' or message like '%Typed%'),
  'W5 the typed sign-up name is never used');
select public.affiliate_whatsapp_enqueue('reactivated', pg_temp.fx('wOld'), pg_temp.fx('c:wOld'), pg_temp.fx('a:wOld'), 'T531-re-old');
select public.affiliate_whatsapp_enqueue('reactivated', pg_temp.fx('wHour'), pg_temp.fx('c:wHour'), pg_temp.fx('a:wHour'), 'T531-re-hour');
select pg_temp.check((pg_temp.wa('wOld', 'reactivated')).message like 'Hi Olive, your Energia affiliate account is active again.%'
    and (pg_temp.wa('wHour', 'reactivated')).message like 'Hi there, your Energia affiliate account is active again.%',
  'W6 ''reactivated'' follows the same rule');
update public.customers set first_name = '+61491570621', full_name = 'https://x.invalid (T531)' where id = pg_temp.fx('c:wDay');
select public.affiliate_whatsapp_enqueue('reactivated', pg_temp.fx('wDay'), pg_temp.fx('c:wDay'), pg_temp.fx('a:wDay'), 'T531-re-day');
select pg_temp.check((pg_temp.wa('wDay', 'reactivated')).first_name is null,
  'W7 an old record''s name that does not look like a name is still passed over (Hi there)');

-- ═════ D at most 30 welcomes a day ═════
delete from public.affiliate_whatsapp_outbox;
insert into public.affiliate_whatsapp_outbox (kind, idempotency_key, phone_e164, wa_country_code, wa_number, message, status, created_at)
select 'welcome', 'T531-fill-' || i, '+61491570699', '61', '491570699', 'T531', case when i <= 27 then 'queued' when i = 28 then 'sending' else 'sent' end,
       now() - interval '1 hour'
  from generate_series(1, 29) i;
insert into public.affiliate_whatsapp_outbox (kind, idempotency_key, status, skip_reason, created_at)
select 'welcome', 'T531-other-' || i, s, 'T531', now() - interval '1 hour'
  from generate_series(1, 2) i, lateral (select (array['skipped', 'expired'])[i] s) x;
insert into public.affiliate_whatsapp_outbox (kind, idempotency_key, phone_e164, wa_country_code, wa_number, message, status, created_at)
values ('welcome', 'T531-old', '+61491570699', '61', '491570699', 'T531', 'sent', now() - interval '25 hours');
select pg_temp.affiliate('d30', 'Thea', now() - interval '3 days', 30);
select pg_temp.check((pg_temp.wa('d30')).status = 'queued' and (pg_temp.wa('d30')).skip_reason is null,
  'D1 29 welcomes queued, being sent or sent in 24 hours (skipped, expired and older ones not counted): the 30th is queued');
select pg_temp.check(exists (select 1 from pg_locks l where l.locktype = 'advisory' and l.pid = pg_backend_pid()
                               and ((l.classid::bigint << 32) | l.objid::bigint) = hashtextextended('affiliate-whatsapp-welcome-day', 0)),
  'D2 the welcomes'' lock is held to the end of the transaction');
select pg_temp.affiliate('d31', 'Tina', now() - interval '3 days', 31);
select pg_temp.check((pg_temp.wa('d31')).status = 'skipped' and (pg_temp.wa('d31')).skip_reason = 'daily_limit'
    and (pg_temp.wa('d31')).idempotency_key = 'welcome:' || pg_temp.fx('d31'),
  'D3 the 31st in 24 hours is kept skipped (daily_limit), nothing to send, its key taken');
select pg_temp.put('d4', coalesce(public.affiliate_whatsapp_enqueue('welcome', pg_temp.fx('d31'), pg_temp.fx('c:d31'), pg_temp.fx('a:d31'), 'welcome:' || pg_temp.fx('d31'))::text, 'null'));
select pg_temp.check(pg_temp.tx('d4') = 'null'
    and (select count(*) from public.affiliate_whatsapp_outbox where auth_user_id = pg_temp.fx('d31')) = 1,
  'D4 asked again with its key: nothing added (a skipped welcome is never sent later)');
select public.affiliate_whatsapp_enqueue('reactivated', pg_temp.fx('d31'), pg_temp.fx('c:d31'), pg_temp.fx('a:d31'), 'T531-re-d31');
select pg_temp.check((pg_temp.wa('d31', 'reactivated')).status = 'queued'
    and (select count(*) from public.affiliate_whatsapp_outbox
          where kind = 'welcome' and status not in ('skipped', 'expired') and created_at > now() - interval '24 hours') = 30,
  'D5 ''reactivated'' is not limited (queued at 30 welcomes) and not counted (still 30)');
update public.affiliate_whatsapp_outbox set created_at = now() - interval '24 hours 1 second' where idempotency_key = 'T531-fill-1';
select pg_temp.affiliate('d32', 'Tess', now() - interval '3 days', 32);
select pg_temp.affiliate('d33', 'Tara', now() - interval '3 days', 33);
select pg_temp.check((pg_temp.wa('d32')).status = 'queued' and (pg_temp.wa('d33')).skip_reason = 'daily_limit',
  'D6 one falls out of the 24 hours: the next welcome is queued, the one after is skipped again');
select pg_temp.affiliate('d34', 'Tove', now() - interval '3 days', 34);
update public.customer_affiliates set manually_suspended = true where id = pg_temp.fx('a:d34');
select public.affiliate_whatsapp_enqueue('welcome', pg_temp.fx('d34'), pg_temp.fx('c:d34'), pg_temp.fx('a:d34'), 'T531-welcome-d34b');
select pg_temp.check((select skip_reason from public.affiliate_whatsapp_outbox where idempotency_key = 'T531-welcome-d34b') = 'affiliate_suspended',
  'D7 a welcome skipped for another reason keeps that reason');
-- Failed welcomes count: one to be retried, one whose answer timed out (it may have gone).
delete from public.affiliate_whatsapp_outbox;
insert into public.affiliate_whatsapp_outbox (kind, idempotency_key, status, skip_reason, last_error, attempts, created_at)
select 'welcome', 'T531-failed-' || i, 'failed', null, case when i % 2 = 0 then 'timeout' else 'HTTP 500' end, 1, now() - interval '2 hours'
  from generate_series(1, 30) i;
select pg_temp.affiliate('d35', 'Tamsin', now() - interval '3 days', 35);
select pg_temp.check((pg_temp.wa('d35')).status = 'skipped' and (pg_temp.wa('d35')).skip_reason = 'daily_limit',
  'D8 30 failed welcomes in 24 hours (retries due, answers timed out): the 31st is skipped (daily_limit)');

-- ═════ G grants ═════
create function pg_temp.acl(f text) returns text language sql as
$$ select coalesce(string_agg(x::text, ',' order by x::text), '') from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure(f) $$;
select pg_temp.check(pg_temp.acl('public.auth_email_take(text,text,uuid,text,text)') = 'postgres=X/postgres,service_role=X/postgres'
    and pg_temp.acl('public.affiliate_email_code_issue(uuid)') = 'postgres=X/postgres,service_role=X/postgres'
    and pg_temp.acl('public.confirm_affiliate_email_code(text)') = 'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres'
    and pg_temp.acl('public.auth_email_reserve(text,text,text)') = 'postgres=X/postgres,service_role=X/postgres'
    and pg_temp.acl('public.confirm_affiliate_email()') = 'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres'
    and pg_temp.acl('public.affiliate_whatsapp_enqueue(text,uuid,uuid,uuid,text)') = 'postgres=X/postgres,service_role=X/postgres'
    and pg_temp.acl('public.complete_affiliate_onboarding(text,text,text,boolean)') = 'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres'
    and not has_function_privilege('anon', 'public.auth_email_take(text,text,uuid,text,text)', 'execute')
    and not has_function_privilege('authenticated', 'public.auth_email_take(text,text,uuid,text,text)', 'execute')
    and not has_function_privilege('anon', 'public.affiliate_email_code_issue(uuid)', 'execute')
    and not has_function_privilege('authenticated', 'public.affiliate_email_code_issue(uuid)', 'execute')
    and not has_function_privilege('anon', 'public.confirm_affiliate_email_code(text)', 'execute')
    and (select bool_and(p.prosecdef and p.proconfig = '{search_path=public}') from pg_proc p
          where p.oid in ('public.auth_email_take(text,text,uuid,text,text)'::regprocedure, 'public.affiliate_email_code_issue(uuid)'::regprocedure,
                          'public.confirm_affiliate_email_code(text)'::regprocedure)),
  'G1 grants: take and issue the service role''s alone, confirm-code also signed-in logins; the four changed functions as before; all run as the owner with search_path public');
select pg_temp.check(pg_temp.as_login(pg_temp.fx('cG'), $q$select public.affiliate_email_code_issue(auth.uid())$q$)->>'error' like '42501 %'
    and pg_temp.as_login(pg_temp.fx('cG'), $q$select public.auth_email_take('send')$q$)->>'error' like '42501 %'
    and pg_temp.as_login(pg_temp.fx('cG'), $q$select to_jsonb(count(*)) from public.affiliate_email_codes$q$)->>'error' like '42501 %',
  'G2 a signed-in login cannot issue itself a code, take a place, or read the codes table');
select pg_temp.check((select relrowsecurity from pg_class where oid = 'public.affiliate_email_codes'::regclass)
    and not exists (select 1 from pg_policy where polrelid = 'public.affiliate_email_codes'::regclass)
    and (select relacl::text from pg_class where oid = 'public.affiliate_email_codes'::regclass) = '{postgres=arwdDxtm/postgres}'
    and not has_table_privilege('service_role', 'public.affiliate_email_codes', 'select'),
  'G3 the codes table: row level security on, no policy, the owner''s alone');
select pg_temp.check(position('-- 531 (security audit' in pg_get_functiondef('public.auth_email_reserve(text,text,text)'::regprocedure)) > 0
    and position('-- 531 (security audit' in pg_get_functiondef('public.confirm_affiliate_email()'::regprocedure)) > 0
    and position('-- 531 (security audit' in pg_get_functiondef('public.affiliate_whatsapp_enqueue(text,uuid,uuid,uuid,text)'::regprocedure)) > 0
    and position('-- 531 (security audit' in pg_get_functiondef('public.complete_affiliate_onboarding(text,text,text,boolean)'::regprocedure)) > 0,
  'G4 each patched function carries the marker the older suites branch on');

-- ═════ M 531 twice ═════
\if :{?skip_install}
\else
select pg_temp.check(not exists (select 1 from m531 m
                                   full join (select p.oid::regprocedure::text as fn, md5(pg_get_functiondef(p.oid)) as md5, p.proacl::text as acl
                                                from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p')) n
                                     on n.fn = m.fn
                                  where m.fn is null or n.fn is null or m.md5 <> n.md5 or m.acl is distinct from n.acl)
    and (select cols from m531t) = (select string_agg(column_name || ' ' || data_type || ' ' || is_nullable, ',' order by ordinal_position)
                                      from information_schema.columns where table_schema = 'public' and table_name = 'affiliate_email_codes')
    and (select idx from m531t) = (select string_agg(pg_get_indexdef(indexrelid), ',' order by pg_get_indexdef(indexrelid))
                                     from pg_index where indrelid = 'public.affiliate_email_codes'::regclass)
    and (select con from m531t) = (select string_agg(conname || ' ' || pg_get_constraintdef(oid), ',' order by conname)
                                     from pg_constraint where conrelid in ('public.affiliate_email_codes'::regclass, 'public.auth_email_limits'::regclass))
    and (select acl from m531t) = (select relacl::text from pg_class where oid = 'public.affiliate_email_codes'::regclass),
  'M1 running 531 a second time left every function, its grants, the codes table and the limits'' checks as 531 made them');
\endif

-- ═════ U the undo ═════
-- 537 (the affiliate WhatsApp as two messages) relies on 531's affiliate_whatsapp_enqueue and
-- replaces 394's affiliate_whatsapp_message, which 531 pins, so 531 cannot be put back over it.
-- Where 537 is in, it is undone first (scripts/affiliate-whatsapp/undo-537.sql, rolled back with
-- the rest of this file), and the undo below is 531's alone. Where it is not, nothing changes.
select md5(pg_get_functiondef('public.affiliate_whatsapp_message(text,text,text,text)'::regprocedure))
         = '9b7caba24a3cec3e7dc66becfae7ed4b' as had537 \gset
\if :had537
\ir ../../affiliate-whatsapp/undo-537.sql
\endif
create temp table fp531 as
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.oid::regprocedure::text)) || ' ' || count(*) as fp
    from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p');
delete from public.auth_email_rate_events;
-- A function of someone else's that calls one of 531's: the undo refuses and changes nothing.
savepoint u0;
create function public.t531_caller() returns jsonb language sql as $f$ select public.auth_email_take('signup') $f$;
\set ON_ERROR_STOP off
\ir ../undo-531.sql
\set ON_ERROR_STOP on
rollback to savepoint u0;
select :'LAST_ERROR_MESSAGE' as u0_error \gset
select pg_temp.check(:'u0_error' like 'undo-531: another function or view uses%'
    and (select fp from fp531) = (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.oid::regprocedure::text)) || ' ' || count(*)
                                    from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p')),
  'U0 a function that calls auth_email_take: undo-531 refuses and changes nothing: ' || :'u0_error');
savepoint u0v;
create view public.t531_codes_seen as select count(*) as n from public.affiliate_email_codes;
\set ON_ERROR_STOP off
\ir ../undo-531.sql
\set ON_ERROR_STOP on
rollback to savepoint u0v;
select :'LAST_ERROR_MESSAGE' as u0v_error \gset
select pg_temp.check(:'u0v_error' like 'undo-531: another function or view uses%' and to_regclass('public.affiliate_email_codes') is not null,
  'U0b a view that reads the codes table: undo-531 refuses too: ' || :'u0v_error');
\ir ../undo-531.sql
select pg_temp.check(md5(pg_get_functiondef('public.auth_email_reserve(text,text,text)'::regprocedure)) = 'e391dd051d05f0661c7924f24e04a1b2'
    and md5(pg_get_functiondef('public.confirm_affiliate_email()'::regprocedure)) = '8a0a7036312cf5dc22dd2beb82b3ce09'
    and md5(pg_get_functiondef('public.affiliate_whatsapp_enqueue(text,uuid,uuid,uuid,text)'::regprocedure)) = 'c88ad74525019c20254a6927f4a802a3'
    and md5(pg_get_functiondef('public.complete_affiliate_onboarding(text,text,text,boolean)'::regprocedure)) = '0dd12d4c9cef8b86bb1bcc02a5344927'
    and to_regclass('public.affiliate_email_codes') is null
    and to_regprocedure('public.auth_email_take(text,text,uuid,text,text)') is null
    and (select string_agg(action || '/' || scope || '=' || max_attempts, ',' order by action, scope) from public.auth_email_limits)
        = 'combined/ip=60,recovery/email=5,recovery/ip=60,resend/email=3,resend/ip=30,signup/email=3,signup/ip=30',
  'U1 undo-531 puts the four functions back (their BEFORE md5s), drops the new ones and the codes table, and puts the limit rows back');
\if :{?skip_install}
select pg_temp.check(true, 'U2 (skip_install: the fingerprint before 531 is not known here)');
\else
select pg_temp.check((select fp from fp0) = (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.oid::regprocedure::text)) || ' ' || count(*)
                                               from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p')),
  'U2 after the undo the public functions'' fingerprint is the one before 531: ' || (select fp from fp0));
\endif
\ir ../../../supabase/531_the_affiliate_sign_up_limits_and_email_codes.sql
select pg_temp.check((select fp from fp531) = (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.oid::regprocedure::text)) || ' ' || count(*)
                                                 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p')),
  'U3 531 again after the undo: the fingerprint 531 made: ' || (select fp from fp531));

do $$ declare v_failed int; begin
  select count(*) into v_failed from failed;
  if v_failed > 0 then raise exception '% check(s) failed: %', v_failed, (select string_agg(msg, '; ' order by n) from failed); end if;
  raise notice 'All 531 checks passed (% checks).', (select count(*) from ran);
end $$;
rollback;
