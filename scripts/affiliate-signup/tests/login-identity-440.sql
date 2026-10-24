-- What an affiliate login signed up with, kept where she cannot edit it, and
-- the no-self-referral checks that read it (440; the Owner's answers of 21
-- Oct 2026, A, B and C).
--
--   O  The copy is written when the affiliate account is made or joined, once:
--      O1 a new customer (a phone no one has): the name and phone as typed on
--         the page, the login's email at that moment (in lower case), from
--         'arguments';
--      O2 a phone join (437's rule 7) under another name: the name typed, not
--         the record's; the record joined;
--      O3 a fresh record (the phone shared under other names, listed);
--      O4 the details from the account (the page sent none): 'user_metadata';
--      O5 a second press with other details: "already", nothing written, the
--         copy as it was;
--      O6 a sign-up refused (a staff login, a rejected claim, no details, an
--         unconfirmed login): no copy.
--   B  The backfill (only when this suite installs 440: these logins are
--      made before it): every login with an affiliate account gets one copy
--      ('backfill') from its metadata and email as they were; a metadata with
--      only full_name gives that name; none gives the email alone; a login
--      with a pending claim and no account gets one; one with only a
--      rejected claim, or nothing, gets none; the second run adds none; a
--      backfilled login that edits its metadata is still herself at /r/;
--      B7 an affiliate account left with no copy after 440 went in (what a
--      sign-up still running 437's text during the apply leaves, or one made
--      by hand): not compared until the next run of 440, which copies it
--      ('backfill', from its metadata and email then) and nothing else (a
--      pending claim made after the first run is not copied; no function
--      changes); /r/ then knows her by her login's name and phone; a run
--      after that changes nothing.
--   U  Nobody can change it: updateUser-style edits of her metadata and her
--      email leave every copy as it was; signed in for real (authenticated)
--      or signed out (anon) she can neither read, add, change nor delete a
--      row, nor call the helper; the service role only reads; even the
--      owner's UPDATE is refused (SIGNUP_DETAILS_KEPT); the client-callable
--      functions she has (sign-up again, verify her email) change nothing;
--      the sign-up is the only function that writes the table, and only it
--      and the helper name it; deleting a login takes its rows.
--   R  /r/<code> (affiliate_referral_signup, called with the anon role): an
--      affiliate whose record staff changed away from what her login signed
--      up with: her record, as before; her login's name (also in another
--      order), its phone, its email inbox (in other case): each "You cannot
--      refer yourself.", the very answer her record gives, nothing written
--      (since 442: each told what someone already registered is told, the
--      very answer her record gives, and one event per try, 'self', or
--      'self_known' for her record, which the sign-up limits count; still no
--      customer and no referral); a
--      family member who shares nothing is referred as before; someone on her
--      record's phone under another name: 425's check, as before; after she
--      edits her metadata and her email, her login's name is still her and
--      what she edited in is someone else; a referrer with no login: as
--      before; the rule-7 family case (her login on her mother's record): she
--      is herself on her own mobile; a login an Owner unlinked is not the
--      record's any more, and its next sign-in adds a second copy, the first
--      kept; after 437's Link the copy follows the login to the customer it
--      was linked to.
--   S  (with 439 in) The seminar website reads the copy: her login's name on a
--      new phone with her login email is held as herself after she edited her
--      metadata; the name and phone she edited in are someone else, referred
--      at once; someone else on her login's sign-up phone or email (on no
--      record) waits for a check, and on her new auth email does not; her
--      login's name is herself. Without 439: skipped (NOTE), and 436's two
--      functions are untouched.
--   G  Grants, md5s and the table.
--   M  440 twice changes nothing; its self-test left no row (when this suite
--      installs it; B7 runs it twice more).
--
-- Disposable database only; everything is rolled back. Needs 436 (the event
-- website), 437 and 438 as production has them (440 refuses before 437); 439
-- optional. Run from the repository root:
--   psql -X -v ON_ERROR_STOP=1 -f scripts/affiliate-signup/tests/login-identity-440.sql
-- (with -v nomig=1 on a database where 440 is applied, to skip installing it;
-- the backfill part then has nothing to check and says so).
-- Every name, phone and email below is invented: ACMA fictional mobile
-- numbers (+61491570xxx) and @example.com addresses.
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
create function pg_temp.as_service() returns void language sql as
$$ select set_config('request.jwt.claim.sub', '', true), set_config('request.jwt.claim.role', 'service_role', true),
          set_config('request.jwt.claims', '', true) $$;
create function pg_temp.err(q text) returns text language plpgsql as
$$begin execute q; return 'ok'; exception when others then return sqlstate || ' ' || sqlerrm; end$$;
create function pg_temp.mail(tag text) returns text language sql as
$$ select 't440-' || lower(tag) || '-' || pg_temp.tx('sfx') || '@example.com' $$;
-- A login, as the sign-up function makes it (confirmed, marked unverified), with the metadata given.
create function pg_temp.login(key text, meta jsonb default '{}'::jsonb, email text default null) returns uuid language plpgsql as
$$declare u uuid := gen_random_uuid(); begin
  insert into auth.users(id, email, email_confirmed_at, raw_app_meta_data, raw_user_meta_data)
  values (u, coalesce(email, pg_temp.mail(key)), now(), '{"provider": "email", "affiliate_email_unverified": true}'::jsonb, meta);
  perform pg_temp.putx(key, u);
  return u;
end$$;
-- The sign-up the pages run, as the login. Keeps the answer (or the error) under 'onb:<login>'.
create function pg_temp.onboard(key text, first text, last text, phone text) returns jsonb language plpgsql as
$$declare r jsonb; begin
  perform pg_temp.as_user(key);
  begin
    r := public.complete_affiliate_onboarding(first, last, phone, true);
  exception when others then r := jsonb_build_object('error', sqlstate || ' ' || sqlerrm);
  end;
  perform pg_temp.put('onb:' || key, r::text);
  return r;
end$$;
create function pg_temp.ans(key text) returns jsonb language sql as $$ select pg_temp.tx('onb:' || key)::jsonb $$;
create function pg_temp.account(key text) returns uuid language sql as
$$ select id from public.affiliate_accounts where auth_user_id = pg_temp.fx(key) $$;
-- /r/<code>, as the page calls it: the anon key. Keeps the answer under 'ref:<tag>'.
create function pg_temp.ref(tag text, code text, first text, last text, phone text, email text) returns jsonb language plpgsql as
$$declare r jsonb; begin
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.role', 'anon', true);
  perform set_config('request.jwt.claims', '', true);
  execute 'set local role anon';
  begin
    r := public.affiliate_referral_signup(code, first, last, phone, email, null);
  exception when others then r := jsonb_build_object('error', sqlstate || ' ' || sqlerrm);
  end;
  execute 'reset role';
  perform pg_temp.put('ref:' || tag, r::text);
  return r;
end$$;
create function pg_temp.r(tag text) returns jsonb language sql as $$ select pg_temp.tx('ref:' || tag)::jsonb $$;
create function pg_temp.on_phone(p text) returns int language sql as
$$ select count(*)::int from public.customers c where c.deleted_at is null and public.normalize_customer_phone(c.phone) = p $$;
create function pg_temp.events_on(p text) returns int language sql as
$$ select count(*)::int from public.referral_signup_events where normalized_phone = p $$;
-- The customer a referral sign-up made on a phone (one each here; everything in this
-- transaction has the same created_at, so it is found through its event).
create function pg_temp.made_on(p text) returns public.customers language sql as
$$ select c.* from public.referral_signup_events e join public.customers c on c.id = e.new_customer_id
    where e.normalized_phone = p and e.new_customer_id is not null limit 1 $$;
-- What a self match answers: "You cannot refer yourself." (425, 440), or, once 442 is in, word for
-- word what someone already registered is told (442: the Owner, 21 Oct 2026: a vaguer answer, and
-- the try counted, as a 'self' event, by the sign-up limits).
create function pg_temp.has442() returns boolean language sql as
$$ select strpos(pg_get_functiondef('public.affiliate_referral_signup(text,text,text,text,text,text)'::regprocedure), '442:') > 0 $$;
create function pg_temp.self_answer() returns jsonb language sql as
$$ select case when pg_temp.has442()
               then jsonb_build_object('ok', true, 'outcome', 'already_registered', 'message',
                      'This phone number is already registered with Energia, so no new registration was created. Nothing about your existing record has changed.')
               else jsonb_build_object('ok', false, 'message', 'You cannot refer yourself.') end $$;

-- ═════ P0 ═════
do $$ begin insert into tx values ('sfx', lower(substr(md5(random()::text || clock_timestamp()::text), 1, 6))); end $$;
select pg_temp.check(not exists (select 1 from public.customers c
                                  where public.normalize_customer_phone(c.phone) like '+6149157050_'
                                     or public.normalize_customer_phone(c.phone) like '+6149157051_'
                                     or public.normalize_customer_phone(c.phone) like '+6149157052_'
                                     or public.normalize_customer_phone(c.phone) like '+6149157053_'
                                     or public.normalize_customer_phone(c.phone) like '+6149157054_'),
  'P0 no customer uses the test phones (+61491570500..549; the checks below assume so)');

-- Staff, and the customers the pre-440 logins sit on.
do $$
declare k text; u uuid; c uuid; a uuid;
begin
  foreach k in array array['o', 's'] loop
    u := gen_random_uuid(); insert into fx values (k, u);
    insert into auth.users(id, email, email_confirmed_at) values (u, pg_temp.mail('staff-' || k), now());
  end loop;
  insert into profiles(id, full_name, email, role) values
    (pg_temp.fx('o'), 'T440 Owner', pg_temp.mail('staff-o'), 'owner'),
    (pg_temp.fx('s'), 'T440 Staff', pg_temp.mail('staff-s'), 'staff');
end $$;
select pg_temp.as_user('o');

-- ═════ B, before 440: logins as production has them ═════
\if :{?nomig}
select pg_temp.check(to_regclass('public.affiliate_signup_identities') is not null
    and to_regprocedure('public.affiliate_login_signup_details(uuid)') is not null,
  'P1 440 is installed (nomig)');
do $$ begin raise notice 'NOTE  B (the backfill) is skipped: 440 was installed before this suite, so there is nothing made before it to check'; end $$;
\else
select pg_temp.check(to_regclass('public.affiliate_signup_identities') is null,
  'P1 440 is not installed yet (this suite installs it; use -v nomig=1 where it is)');
do $$
declare c uuid; a uuid; sfx text := pg_temp.tx('sfx');
begin
  -- An affiliate login with its account, its metadata as the sign-up stored it (its email in mixed case).
  perform pg_temp.login('bAcc', jsonb_build_object('first_name', 'Bea', 'last_name', 'Testbackfill', 'phone', '+61491570530'),
                        'T440-BAcc-' || sfx || '@Example.com');
  insert into customers(full_name, phone) values ('Beatrice Testrecord', '+61491570531') returning id into c;
  insert into customer_affiliates(customer_id, status, activated_at, referral_code) values (c, 'active', now(), upper('T440B' || sfx))
    returning id into a;
  insert into affiliate_accounts(auth_user_id, customer_id, affiliate_id, status) values (pg_temp.fx('bAcc'), c, a, 'claimed');
  insert into fx values ('cBacc', c); insert into tx values ('code_bacc', upper('T440B' || sfx));
  -- One whose metadata has only full_name; one with none.
  perform pg_temp.login('bFull', jsonb_build_object('full_name', 'Fen Testfullname', 'phone', '+61491570532'));
  insert into customers(full_name, phone) values ('Fen Testfullname', '+61491570532') returning id into c;
  insert into customer_affiliates(customer_id, status, activated_at, referral_code) values (c, 'active', now(), upper('T440F' || sfx))
    returning id into a;
  insert into affiliate_accounts(auth_user_id, customer_id, affiliate_id, status) values (pg_temp.fx('bFull'), c, a, 'claimed');
  perform pg_temp.login('bNone', '{}'::jsonb);
  insert into customers(full_name, phone) values ('Nel Testnone', '+61491570533') returning id into c;
  insert into customer_affiliates(customer_id, status, activated_at, referral_code) values (c, 'active', now(), upper('T440N' || sfx))
    returning id into a;
  insert into affiliate_accounts(auth_user_id, customer_id, affiliate_id, status) values (pg_temp.fx('bNone'), c, a, 'claimed');
  -- A login with a pending claim from before 437, and no account yet.
  perform pg_temp.login('bPend', jsonb_build_object('first_name', 'Pen', 'last_name', 'Testpending', 'phone', '+61491570534'));
  insert into affiliate_account_claims(auth_user_id, entered_phone, entered_name, verified_email, status)
  values (pg_temp.fx('bPend'), '+61491570534', 'Pen Testpending', pg_temp.mail('bPend'), 'pending');
  -- A login whose only claim was rejected; a login with nothing.
  perform pg_temp.login('bRej', jsonb_build_object('first_name', 'Rex', 'last_name', 'Testrejected', 'phone', '+61491570536'));
  insert into affiliate_account_claims(auth_user_id, entered_phone, entered_name, status, rejected_at, rejection_reason)
  values (pg_temp.fx('bRej'), '+61491570536', 'Rex Testrejected', 'rejected', now(), 'T440 test');
  perform pg_temp.login('bLone', jsonb_build_object('first_name', 'Lou', 'last_name', 'Testlone', 'phone', '+61491570537'));
end $$;
create temp table fp440 as select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.oid::regprocedure::text)) fp
  from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p');
\ir ../../../supabase/440_affiliate_login_signup_identity_and_self_referral.sql
update fp440 set fp = (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.oid::regprocedure::text))
  from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p'));
create temp table snap440 as
  select coalesce(jsonb_agg(to_jsonb(i) order by i.id), '[]'::jsonb) s from public.affiliate_signup_identities i;
\ir ../../../supabase/440_affiliate_login_signup_identity_and_self_referral.sql
select pg_temp.check((select fp from fp440) = (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.oid::regprocedure::text))
    from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p'))
    and (select s from snap440) = (select coalesce(jsonb_agg(to_jsonb(i) order by i.id), '[]'::jsonb) from public.affiliate_signup_identities i),
  'M1 a second run of 440 changes no function and writes no copy');
select pg_temp.check(not exists (select 1 from auth.users where email like '440-check-%')
    and not exists (select 1 from customers where full_name like '440 Check%' or full_name like 'Someone Else%'),
  'M2 440''s self-test left no row');
\endif
select pg_temp.as_user('o');

-- What the checks read of the copies (the table is there now).
create function pg_temp.copies(key text) returns int language sql as
$$ select count(*)::int from public.affiliate_signup_identities where auth_user_id = pg_temp.fx(key) $$;
create function pg_temp.copy(key text) returns public.affiliate_signup_identities language sql as
$$ select * from public.affiliate_signup_identities where auth_user_id = pg_temp.fx(key) order by created_at desc, id limit 1 $$;
-- Every row of every copy, to compare before and after.
create function pg_temp.snapshot() returns jsonb language sql as
$$ select coalesce(jsonb_agg(to_jsonb(i) order by i.id), '[]'::jsonb) from public.affiliate_signup_identities i $$;

\if :{?nomig}
\else
-- ═════ B The backfill ═════

select pg_temp.check(pg_temp.copies('bAcc') = 1
    and (pg_temp.copy('bAcc')).source = 'backfill'
    and (pg_temp.copy('bAcc')).first_name = 'Bea' and (pg_temp.copy('bAcc')).last_name = 'Testbackfill'
    and (pg_temp.copy('bAcc')).full_name = 'Bea Testbackfill' and (pg_temp.copy('bAcc')).phone = '+61491570530'
    and (pg_temp.copy('bAcc')).email = lower('T440-BAcc-' || pg_temp.tx('sfx') || '@Example.com')
    and (pg_temp.copy('bAcc')).name_from = 'user_metadata' and (pg_temp.copy('bAcc')).phone_from = 'user_metadata'
    and (pg_temp.copy('bAcc')).affiliate_account_id = pg_temp.account('bAcc')
    and (pg_temp.copy('bAcc')).customer_id = pg_temp.fx('cBacc'),
  'B1 a login with an affiliate account: one copy, ''backfill'', from its metadata (not its record''s name or phone) and its email in lower case');
select pg_temp.check((pg_temp.copy('bFull')).full_name = 'Fen Testfullname' and (pg_temp.copy('bFull')).first_name is null
    and (pg_temp.copy('bFull')).phone = '+61491570532'
    and (pg_temp.copy('bNone')).full_name is null and (pg_temp.copy('bNone')).phone is null
    and (pg_temp.copy('bNone')).name_from is null and (pg_temp.copy('bNone')).phone_from is null
    and (pg_temp.copy('bNone')).email = pg_temp.mail('bNone'),
  'B2 metadata with only full_name gives that name; none gives the email alone');
select pg_temp.check(pg_temp.copies('bPend') = 1 and (pg_temp.copy('bPend')).affiliate_account_id is null
    and (pg_temp.copy('bPend')).customer_id is null and (pg_temp.copy('bPend')).full_name = 'Pen Testpending',
  'B3 a login with a pending claim and no account yet: one copy (for a claim staff resolve later)');
select pg_temp.check(pg_temp.copies('bRej') = 0 and pg_temp.copies('bLone') = 0
    and pg_temp.copies('o') = 0 and pg_temp.copies('s') = 0,
  'B4 a login with only a rejected claim, one with nothing, and staff logins: no copy');
select pg_temp.check(not exists (select 1 from public.affiliate_accounts a
                                  where not exists (select 1 from public.affiliate_signup_identities i where i.auth_user_id = a.auth_user_id)),
  'B5 every login with an affiliate account has a copy');
-- The backfilled login edits her metadata (updateUser); her code's /r/ still knows her.
update auth.users set raw_user_meta_data = raw_user_meta_data || jsonb_build_object('first_name', 'Bo', 'last_name', 'Otheredit', 'phone', '+61491570538')
 where id = pg_temp.fx('bAcc');
select pg_temp.ref('b6a', pg_temp.tx('code_bacc'), 'Bea', 'Testbackfill', '+61491570535', pg_temp.mail('b6a'));
select pg_temp.ref('b6b', pg_temp.tx('code_bacc'), 'Kim', 'Friend', '+61491570530', pg_temp.mail('b6b'));
select pg_temp.ref('b6c', pg_temp.tx('code_bacc'), 'Bo', 'Otheredit', '+61491570538', pg_temp.mail('b6c'));
select pg_temp.check(pg_temp.r('b6a') = pg_temp.self_answer()
    and pg_temp.r('b6b') = pg_temp.self_answer()
    and pg_temp.r('b6c')->>'outcome' = 'registered'
    and (pg_temp.made_on('+61491570538')).referred_by = pg_temp.fx('cBacc'),
  'B6 a backfilled login that edits her metadata: her backfilled name and phone are still herself at /r/; what she edited in is someone else, referred: '
  || pg_temp.r('b6a')::text || ' ' || pg_temp.r('b6b')::text || ' ' || pg_temp.r('b6c')::text);

-- ═════ B7 A later run copies an account left with no copy ═════
-- What a sign-up still running 437's text while 440 went in leaves behind (as does an account
-- made by hand): an affiliate account and no copy. Her record's name and phone are not her
-- login's, so only her login's copy could make her "herself". And a login with only a pending
-- claim, made after 440 first ran (only the first run copies those).
do $$
declare c uuid; a uuid; sfx text := pg_temp.tx('sfx');
begin
  perform pg_temp.login('bLate', jsonb_build_object('first_name', 'Lia', 'last_name', 'Testlate', 'phone', '+61491570546'),
                        'T440-BLate-' || sfx || '@Example.com');
  insert into customers(full_name, phone) values ('Lilian Testrecordlate', '+61491570547') returning id into c;
  insert into customer_affiliates(customer_id, status, activated_at, referral_code) values (c, 'active', now(), upper('T440L' || sfx))
    returning id into a;
  insert into affiliate_accounts(auth_user_id, customer_id, affiliate_id, status) values (pg_temp.fx('bLate'), c, a, 'claimed');
  insert into fx values ('cLate', c); insert into tx values ('code_late', upper('T440L' || sfx));
  perform pg_temp.login('bPend2', jsonb_build_object('first_name', 'Pia', 'last_name', 'Testpendlate', 'phone', '+61491570549'));
  insert into affiliate_account_claims(auth_user_id, entered_phone, entered_name, verified_email, status)
  values (pg_temp.fx('bPend2'), '+61491570549', 'Pia Testpendlate', pg_temp.mail('bPend2'), 'pending');
end $$;
select pg_temp.ref('b7a', pg_temp.tx('code_late'), 'Lia', 'Testlate', '+61491570548', pg_temp.mail('b7a'));
select pg_temp.check(pg_temp.copies('bLate') = 0
    and (select count(*) from public.affiliate_login_signup_details(pg_temp.fx('cLate'))) = 0
    and pg_temp.r('b7a')->>'outcome' = 'registered',
  'B7 (before) an affiliate account with no copy: her login is not compared (her login''s name is registered as her referral): '
  || pg_temp.r('b7a')::text);
do $$ begin insert into tx values ('snap_b7', pg_temp.snapshot()::text); end $$;
\ir ../../../supabase/440_affiliate_login_signup_identity_and_self_referral.sql
select pg_temp.check(pg_temp.copies('bLate') = 1
    and (pg_temp.copy('bLate')).source = 'backfill'
    and (pg_temp.copy('bLate')).first_name = 'Lia' and (pg_temp.copy('bLate')).last_name = 'Testlate'
    and (pg_temp.copy('bLate')).full_name = 'Lia Testlate' and (pg_temp.copy('bLate')).phone = '+61491570546'
    and (pg_temp.copy('bLate')).email = lower('T440-BLate-' || pg_temp.tx('sfx') || '@Example.com')
    and (pg_temp.copy('bLate')).name_from = 'user_metadata' and (pg_temp.copy('bLate')).phone_from = 'user_metadata'
    and (pg_temp.copy('bLate')).affiliate_account_id = pg_temp.account('bLate')
    and (pg_temp.copy('bLate')).customer_id = pg_temp.fx('cLate'),
  'B7 the next run of 440 copies it: ''backfill'', from its metadata and its email (lower case) as they are then');
select pg_temp.check(pg_temp.copies('bPend2') = 0
    and (select coalesce(jsonb_agg(e order by e->>'id'), '[]'::jsonb) from jsonb_array_elements(pg_temp.snapshot()) e
          where (e->>'auth_user_id')::uuid <> pg_temp.fx('bLate'))
        = (select coalesce(jsonb_agg(e order by e->>'id'), '[]'::jsonb) from jsonb_array_elements(pg_temp.tx('snap_b7')::jsonb) e)
    and (select fp from fp440) = (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.oid::regprocedure::text))
          from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p'))
    and not exists (select 1 from public.affiliate_accounts a
                     where not exists (select 1 from public.affiliate_signup_identities i where i.auth_user_id = a.auth_user_id)),
  'B7 and nothing else: a pending claim made after the first run is not copied, every other copy is as it was, no function changes, every affiliate login has a copy');
select pg_temp.ref('b7b', pg_temp.tx('code_late'), 'Lia', 'Testlate', '+61491570527', pg_temp.mail('b7b'));
select pg_temp.ref('b7c', pg_temp.tx('code_late'), 'Max', 'Friend', '+61 491 570 546', pg_temp.mail('b7c'));
select pg_temp.check(pg_temp.r('b7b') = pg_temp.self_answer()
    and pg_temp.r('b7c') = pg_temp.self_answer()
    and pg_temp.on_phone('+61491570527') = 0,
  'B7 then /r/ knows her: her login''s name, and its phone, are herself: ' || pg_temp.r('b7b')::text || ' ' || pg_temp.r('b7c')::text);
do $$ begin insert into tx values ('snap_b7b', pg_temp.snapshot()::text); end $$;
\ir ../../../supabase/440_affiliate_login_signup_identity_and_self_referral.sql
select pg_temp.check(pg_temp.snapshot() = pg_temp.tx('snap_b7b')::jsonb
    and (select fp from fp440) = (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.oid::regprocedure::text))
          from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p'))
    and not exists (select 1 from auth.users where email like '440-check-%')
    and not exists (select 1 from customers where full_name like '440 Check%' or full_name like 'Someone Else%'),
  'B7 a run after that adds no copy and changes nothing; the self-tests of all four runs left no row');
\endif

-- ═════ O The copy at sign-up ═════
do $$ begin
  perform pg_temp.login('lNew', '{}'::jsonb, 'T440-New-' || pg_temp.tx('sfx') || '@Example.COM');
  perform pg_temp.login('lJoin', '{}'::jsonb);
  perform pg_temp.login('lFresh', '{}'::jsonb);
  perform pg_temp.login('lMeta', jsonb_build_object('first_name', 'Meg', 'last_name', 'Testmeta', 'phone', '+61491570504'));
  perform pg_temp.login('lRej', '{}'::jsonb);
  perform pg_temp.login('lNoDet', '{}'::jsonb);
  perform pg_temp.login('lUnc', '{}'::jsonb);
  update auth.users set email_confirmed_at = null where id = pg_temp.fx('lUnc');
  insert into affiliate_account_claims(auth_user_id, entered_phone, status, rejected_at, rejection_reason)
  values (pg_temp.fx('lRej'), '+61491570507', 'rejected', now(), 'T440 test');
end $$;
select pg_temp.as_user('o');
do $$ declare c uuid; begin
  insert into customers(full_name, phone) values ('Siew Mei Testkin', '+61491570502') returning id into c; insert into fx values ('cMum', c);
  insert into customers(full_name, phone) values ('Ann Testshare', '+61491570503') returning id into c; insert into fx values ('cShareA', c);
  insert into customers(full_name, phone) values ('Bo Testshare', '+61491570503') returning id into c; insert into fx values ('cShareB', c);
end $$;
select pg_temp.onboard('lNew', 'Nia', 'Testnew', '+61 491 570 501');
select pg_temp.check(pg_temp.ans('lNew')->>'status' = 'active' and (pg_temp.ans('lNew')->>'new_customer')::boolean
    and pg_temp.copies('lNew') = 1
    and (pg_temp.copy('lNew')).source = 'onboarding'
    and (pg_temp.copy('lNew')).first_name = 'Nia' and (pg_temp.copy('lNew')).last_name = 'Testnew'
    and (pg_temp.copy('lNew')).full_name = 'Nia Testnew' and (pg_temp.copy('lNew')).phone = '+61 491 570 501'
    and (pg_temp.copy('lNew')).email = lower('T440-New-' || pg_temp.tx('sfx') || '@Example.COM')
    and (pg_temp.copy('lNew')).name_from = 'arguments' and (pg_temp.copy('lNew')).phone_from = 'arguments'
    and (pg_temp.copy('lNew')).customer_id = (pg_temp.ans('lNew')->>'customer_id')::uuid
    and (pg_temp.copy('lNew')).affiliate_account_id = pg_temp.account('lNew'),
  'O1 a new customer: one copy, the name and phone as typed, the login''s email at that moment (lower case): ' || pg_temp.tx('onb:lNew'));
select pg_temp.onboard('lJoin', 'Rachel', 'Testkin', '+61491570502');
select pg_temp.check((pg_temp.ans('lJoin')->>'customer_id')::uuid = pg_temp.fx('cMum') and not (pg_temp.ans('lJoin')->>'new_customer')::boolean
    and pg_temp.copies('lJoin') = 1 and (pg_temp.copy('lJoin')).full_name = 'Rachel Testkin'
    and (pg_temp.copy('lJoin')).phone = '+61491570502' and (pg_temp.copy('lJoin')).email = pg_temp.mail('lJoin')
    and (pg_temp.copy('lJoin')).customer_id = pg_temp.fx('cMum')
    and exists (select 1 from affiliate_signup_matches m where m.auth_user_id = pg_temp.fx('lJoin') and m.reason = 'phone_other_name'),
  'O2 a phone join (rule 7) under another name: the copy keeps the name typed (Rachel), not the record''s (Siew Mei), and names the record joined');
select pg_temp.onboard('lFresh', 'Fred', 'Testfresh', '+61491570503');
select pg_temp.check((pg_temp.ans('lFresh')->>'new_customer')::boolean
    and exists (select 1 from affiliate_signup_matches m where m.auth_user_id = pg_temp.fx('lFresh') and m.reason = 'shared_phone')
    and pg_temp.copies('lFresh') = 1 and (pg_temp.copy('lFresh')).full_name = 'Fred Testfresh'
    and (pg_temp.copy('lFresh')).customer_id = (pg_temp.ans('lFresh')->>'customer_id')::uuid,
  'O3 a fresh record (the phone shared under other names, listed for staff): one copy, on the fresh record');
select pg_temp.onboard('lMeta', null, null, null);
select pg_temp.check(pg_temp.ans('lMeta')->>'status' = 'active' and pg_temp.copies('lMeta') = 1
    and (pg_temp.copy('lMeta')).full_name = 'Meg Testmeta' and (pg_temp.copy('lMeta')).phone = '+61491570504'
    and (pg_temp.copy('lMeta')).name_from = 'user_metadata' and (pg_temp.copy('lMeta')).phone_from = 'user_metadata',
  'O4 details from the account (the page sent none): copied from what the sign-up used, marked user_metadata');
do $$ begin insert into tx values ('snap_o5', pg_temp.snapshot()::text); end $$;
select pg_temp.onboard('lNew', 'Nora', 'Otherdetails', '+61491570505');
select pg_temp.onboard('lMeta', 'Mo', 'Otherdetails', '+61491570505');
select pg_temp.check((pg_temp.ans('lNew')->>'already')::boolean and (pg_temp.ans('lMeta')->>'already')::boolean
    and pg_temp.snapshot() = pg_temp.tx('snap_o5')::jsonb,
  'O5 a second press with other details: "already", nothing written, every copy as it was');
select pg_temp.onboard('s', 'Sam', 'Teststaff', '+61491570506');
select pg_temp.onboard('lRej', 'Rae', 'Testrej', '+61491570507');
select pg_temp.onboard('lNoDet', null, null, null);
select pg_temp.onboard('lUnc', 'Una', 'Testunconfirmed', '+61491570508');
select pg_temp.check(pg_temp.ans('s')->>'error' like '%STAFF_ACCOUNT%' and pg_temp.ans('lRej')->>'status' = 'rejected'
    and pg_temp.ans('lNoDet')->>'error' like '%DETAILS_REQUIRED%' and pg_temp.ans('lUnc')->>'error' like '%verify your email%'
    and pg_temp.copies('s') = 0 and pg_temp.copies('lRej') = 0 and pg_temp.copies('lNoDet') = 0 and pg_temp.copies('lUnc') = 0,
  'O6 a sign-up refused (staff, rejected claim, no details, unconfirmed): no copy');

-- ═════ U Nobody can change it ═════
do $$ begin insert into tx values ('snap_u', pg_temp.snapshot()::text); end $$;
-- What supabase.auth.updateUser does with { data } (and, once confirmed, { email }).
update auth.users set raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb)
         || jsonb_build_object('first_name', 'Edited', 'last_name', 'Byher', 'full_name', 'Edited Byher', 'phone', '+61491570509'),
       email = 'edited-' || email
 where id in (pg_temp.fx('lNew'), pg_temp.fx('lJoin'), pg_temp.fx('lMeta'));
select pg_temp.check(pg_temp.snapshot() = pg_temp.tx('snap_u')::jsonb
    and (select d.full_name from public.affiliate_login_signup_details(pg_temp.fx('cMum')) d) = 'Rachel Testkin'
    and (select d.email from public.affiliate_login_signup_details(pg_temp.fx('cMum')) d) = pg_temp.mail('lJoin'),
  'U1 updateUser-style edits of her metadata and her email leave every copy, and what the helper gives, as they were');
do $$
declare v_role text; q text; v text; c uuid := pg_temp.fx('cMum'); u uuid := pg_temp.fx('lJoin');
begin
  foreach v_role in array array['authenticated', 'anon', 'service_role'] loop
    v := '';
    perform set_config('request.jwt.claim.sub', case when v_role = 'authenticated' then u::text else '' end, true);
    perform set_config('request.jwt.claim.role', v_role, true);
    execute format('set local role %I', v_role);
    foreach q in array array[
        'select count(*) from public.affiliate_signup_identities',
        format('insert into public.affiliate_signup_identities(auth_user_id, source, full_name) values (%L, ''backfill'', ''Forged Name'')', u),
        format('update public.affiliate_signup_identities set full_name = ''Forged Name'' where auth_user_id = %L', u),
        format('delete from public.affiliate_signup_identities where auth_user_id = %L', u),
        format('select count(*) from public.affiliate_login_signup_details(%L)', c)] loop
      begin
        execute q; v := v || 'allowed ';
      exception when insufficient_privilege then v := v || 'refused ';
      end;
    end loop;
    execute 'reset role';
    insert into tx values ('u2_' || v_role, v);
  end loop;
end $$;
select pg_temp.as_user('o');
select pg_temp.check(pg_temp.tx('u2_authenticated') = 'refused refused refused refused refused ',
  'U2 signed in for real (authenticated): read, add, change, delete and the helper are all refused: ' || pg_temp.tx('u2_authenticated'));
select pg_temp.check(pg_temp.tx('u2_anon') = 'refused refused refused refused refused ',
  'U2 signed out (anon): all refused: ' || pg_temp.tx('u2_anon'));
select pg_temp.check(pg_temp.tx('u2_service_role') = 'allowed refused refused refused allowed ',
  'U2 the service role (the Edge Functions'' key) reads, and cannot add, change or delete: ' || pg_temp.tx('u2_service_role'));
select pg_temp.put('u3', pg_temp.err(format('update public.affiliate_signup_identities set full_name = %L where auth_user_id = %L',
                                            'Forged Name', pg_temp.fx('lJoin'))));
select pg_temp.check(pg_temp.tx('u3') like '42501 SIGNUP_DETAILS_KEPT%' and pg_temp.snapshot() = pg_temp.tx('snap_u')::jsonb,
  'U3 even the owner''s own server code cannot rewrite a copy: ' || pg_temp.tx('u3'));
-- The functions she may call herself: sign-up again; verify her email from an emailed link.
select pg_temp.onboard('lJoin', 'Forged', 'Name', '+61491570509');
do $$ declare r jsonb; begin
  perform set_config('request.jwt.claim.sub', pg_temp.fx('lJoin')::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform set_config('request.jwt.claims', jsonb_build_object('sub', pg_temp.fx('lJoin'), 'role', 'authenticated',
    'amr', jsonb_build_array(jsonb_build_object('method', 'magiclink', 'timestamp', floor(extract(epoch from now()))::bigint)))::text, true);
  execute 'set local role authenticated';
  r := public.confirm_affiliate_email();
  execute 'reset role';
  insert into tx values ('u4_confirm', r::text);
end $$;
select pg_temp.as_user('o');
select pg_temp.check((pg_temp.ans('lJoin')->>'already')::boolean and (pg_temp.tx('u4_confirm')::jsonb->>'verified')::boolean
    and pg_temp.snapshot() = pg_temp.tx('snap_u')::jsonb,
  'U4 what she may call herself (sign-up again with other details, verify her email) changes no copy');
select pg_temp.check((select array_agg(p.proname::text order by p.proname) from pg_proc p
                        where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p')
                          and pg_get_functiondef(p.oid) ~ '(insert\s+into|update|delete\s+from|truncate)\s+(public\.)?affiliate_signup_identities')
                     = array['complete_affiliate_onboarding']::text[]
    and (select array_agg(p.proname::text order by p.proname) from pg_proc p
          where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p')
            and pg_get_functiondef(p.oid) ~ 'affiliate_signup_identities\M')
        = array['affiliate_login_signup_details', 'complete_affiliate_onboarding']::text[]
    and (select pg_get_functiondef(to_regprocedure('public.complete_affiliate_onboarding(text,text,text,boolean)')) ~
         'returning \* into v_acct;\n\n  -- 440[^\n]*\n(  --[^\n]*\n)*  insert into public\.affiliate_signup_identities'),
  'U5 only the sign-up writes the table (an insert, straight after it makes the account), and only it and the helper name it');
select pg_temp.check((select string_agg(p.proname, ',' order by p.proname) from pg_proc p
                        where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p')
                          and pg_get_functiondef(p.oid) ~ 'affiliate_login_signup_details\('
                          and p.proname <> 'affiliate_login_signup_details')
                     in ('affiliate_referral_signup', 'affiliate_referral_signup,event_web_affiliate_contact,event_web_check_self_referral',
                         -- 466: the sign-up function's existing-affiliate check reads the copy through it too
                         'affiliate_referral_signup,affiliate_signup_existing',
                         'affiliate_referral_signup,affiliate_signup_existing,event_web_affiliate_contact,event_web_check_self_referral'),
  'U5 the helper is read by the /r/ sign-up and, with 439, its two checks, and with 466 the sign-up''s existing-affiliate check; by nothing else');
do $$ declare u uuid; r jsonb; begin
  u := pg_temp.login('lGone', '{}'::jsonb);
  r := pg_temp.onboard('lGone', 'Gus', 'Testgone', '+61491570539');
  perform pg_temp.as_user('o');
  insert into tx values ('u6_before', pg_temp.copies('lGone')::text);
  delete from auth.users where id = u;
  insert into tx values ('u6_after', (select count(*) from public.affiliate_signup_identities where auth_user_id = u)::text);
end $$;
select pg_temp.check(pg_temp.tx('u6_before') = '1' and pg_temp.tx('u6_after') = '0',
  'U6 a login deleted in Supabase takes its copy with it');

-- ═════ R /r/<code> ═════
-- Gina signs up (a new customer); staff then change her record's name, phone and email,
-- so her record and what her login signed up with share nothing.
do $$ begin
  perform pg_temp.login('lGina', '{}'::jsonb);
  perform pg_temp.login('lUn', '{}'::jsonb);
end $$;
select pg_temp.onboard('lGina', 'Gina', 'Testlogin', '+61491570510');
select pg_temp.as_user('o');
do $$ begin
  insert into fx values ('cGina', (pg_temp.ans('lGina')->>'customer_id')::uuid);
  insert into tx values ('code_gina', pg_temp.ans('lGina')->>'referral_code');
  update customers set full_name = 'Georgina Testrecord', phone = '+61491570511', email = null where id = pg_temp.fx('cGina');
end $$;
select pg_temp.ref('r0', pg_temp.tx('code_gina'), 'Georgina', 'Testrecord', '+61491570511', pg_temp.mail('r0'));
select pg_temp.check(pg_temp.r('r0') = pg_temp.self_answer(),
  'R0 her record through her own link: herself, as before (425; since 442 told what someone already registered is told): ' || pg_temp.r('r0')::text);
select pg_temp.ref('r1', pg_temp.tx('code_gina'), 'Gina', 'Testlogin', '+61491570513', pg_temp.mail('r1'));
select pg_temp.ref('r1b', pg_temp.tx('code_gina'), 'TESTLOGIN', 'gina', '+61491570517', pg_temp.mail('r1b'));
select pg_temp.ref('r2', pg_temp.tx('code_gina'), 'Kurt', 'Friend', '+61 491 570 510', pg_temp.mail('r2'));
select pg_temp.ref('r3', pg_temp.tx('code_gina'), 'Lia', 'Friend', '+61491570516', upper(pg_temp.mail('lGina')));
select pg_temp.check(pg_temp.r('r1') = pg_temp.r('r0'),
  'R1 her login''s name on a new phone and email: herself, the very answer her record gives (before 440: registered as her referral): ' || pg_temp.r('r1')::text);
select pg_temp.check(pg_temp.r('r1b') = pg_temp.r('r0'),
  'R1 the same words in another order and case: herself: ' || pg_temp.r('r1b')::text);
select pg_temp.check(pg_temp.r('r2') = pg_temp.r('r0'),
  'R2 her login''s phone (typed another way) under another name: herself (the Owner''s B: the phone alone): ' || pg_temp.r('r2')::text);
select pg_temp.check(pg_temp.r('r3') = pg_temp.r('r0'),
  'R3 her login''s email inbox (in capitals) under another name on another phone: herself (the email alone): ' || pg_temp.r('r3')::text);
select pg_temp.check(pg_temp.on_phone('+61491570513') + pg_temp.on_phone('+61491570517') + pg_temp.on_phone('+61491570510')
                       + pg_temp.on_phone('+61491570516') = 0
    and (select count(*) from referral_signup_events
          where normalized_phone in ('+61491570513', '+61491570517', '+61491570510', '+61491570516', '+61491570511')
            and outcome not in ('self', 'self_known')) = 0
    and (select count(*) from referral_signup_events
          where normalized_phone in ('+61491570513', '+61491570517', '+61491570510', '+61491570516')
            and outcome = 'self' and new_customer_id is null and referrer_customer_id = pg_temp.fx('cGina'))
        = case when pg_temp.has442() then 4 else 0 end
    and (select count(*) from referral_signup_events
          where normalized_phone = '+61491570511'
            and outcome = 'self_known' and new_customer_id is null and referrer_customer_id = pg_temp.fx('cGina'))
        = case when pg_temp.has442() then 1 else 0 end
    and not exists (select 1 from customers c where c.referred_by = pg_temp.fx('cGina')),
  'R1-3 as for her record: no customer, no referral, no referral event (before 442 no event at all; since 442 one event per try, which the phone''s limit counts: ''self'' for each of her login''s, which the link''s limit counts too, ''self_known'' for her record, which is on file)');
select pg_temp.ref('r4', pg_temp.tx('code_gina'), 'Tom', 'Testfamily', '+61491570514', pg_temp.mail('r4'));
select pg_temp.check(pg_temp.r('r4') = jsonb_build_object('ok', true, 'outcome', 'registered', 'message', 'Registration successful.',
                                                          'affiliate_label', pg_temp.r('r4')->>'affiliate_label')
    and (pg_temp.made_on('+61491570514')).referred_by = pg_temp.fx('cGina')
    and exists (select 1 from referral_signup_events e where e.normalized_phone = '+61491570514' and e.outcome = 'created'),
  'R4 a family member who shares nothing with her record or her login: registered and referred, as before: ' || pg_temp.r('r4')::text);
select pg_temp.ref('r5', pg_temp.tx('code_gina'), 'Hal', 'Testhousehold', '+61491570511', pg_temp.mail('r5'));
select pg_temp.check(pg_temp.r('r5')->>'outcome' = 'registered'
    and (pg_temp.made_on('+61491570511')).referred_by = pg_temp.fx('cGina')
    and exists (select 1 from referral_signup_checks k where k.customer_id = (pg_temp.made_on('+61491570511')).id
                  and k.referrer_customer_id = pg_temp.fx('cGina') and k.phone_shared_with = array[pg_temp.fx('cGina')]),
  'R5 someone on her RECORD''s phone under another name: 425''s rule, unchanged (registered, a check for staff)');
-- She edits her metadata and (once confirmed) her email.
update auth.users set raw_user_meta_data = jsonb_build_object('first_name', 'Zara', 'last_name', 'Edited', 'phone', '+61491570512'),
                      email = pg_temp.mail('gina-new')
 where id = pg_temp.fx('lGina');
select pg_temp.ref('r6a', pg_temp.tx('code_gina'), 'Gina', 'Testlogin', '+61491570515', pg_temp.mail('r6a'));
select pg_temp.ref('r6c', pg_temp.tx('code_gina'), 'Lee', 'Friend', '+61491570518', pg_temp.mail('lGina'));
select pg_temp.ref('r6b', pg_temp.tx('code_gina'), 'Zara', 'Edited', '+61491570512', pg_temp.mail('gina-new'));
select pg_temp.check(pg_temp.r('r6a') = pg_temp.r('r0') and pg_temp.r('r6c') = pg_temp.r('r0')
    and pg_temp.r('r6b')->>'outcome' = 'registered' and (pg_temp.made_on('+61491570512')).referred_by = pg_temp.fx('cGina'),
  'R6 after she edits her metadata and her email: her login''s name, and the email it signed up with, are still herself; the name, phone and new email she edited in are someone else (registered): '
  || pg_temp.r('r6a')::text || ' ' || pg_temp.r('r6c')::text || ' ' || pg_temp.r('r6b')::text);
-- A referrer with no login: as before.
do $$ declare c uuid; begin
  insert into customers(full_name, phone) values ('Pam Testplain', '+61491570520') returning id into c; insert into fx values ('cPlain', c);
  insert into customer_affiliates(customer_id, status, activated_at, referral_code) values (c, 'active', now(), upper('T440P' || pg_temp.tx('sfx')));
  insert into tx values ('code_plain', upper('T440P' || pg_temp.tx('sfx')));
end $$;
select pg_temp.ref('r7a', pg_temp.tx('code_plain'), 'Pam', 'Testplain', '+61491570520', null);
select pg_temp.ref('r7b', pg_temp.tx('code_plain'), 'Ivy', 'Stranger', '+61491570521', pg_temp.mail('r7b'));
select pg_temp.check(pg_temp.r('r7a') = pg_temp.r('r0') and pg_temp.r('r7b')->>'outcome' = 'registered'
    and (pg_temp.made_on('+61491570521')).referred_by = pg_temp.fx('cPlain'),
  'R7 a referrer with no login: herself on her record, a stranger registered, as before');
-- The rule-7 family case: Rachel's login sits on her mother's record (O2).
select pg_temp.ref('r8a', pg_temp.ans('lJoin')->>'referral_code', 'Rachel', 'Testkin', '+61491570522', pg_temp.mail('r8a'));
select pg_temp.ref('r8b', pg_temp.ans('lJoin')->>'referral_code', 'Siew Mei', 'Testkin', '+61491570502', null);
select pg_temp.check(pg_temp.r('r8a') = pg_temp.r('r0') and pg_temp.r('r8b') = pg_temp.r('r0')
    and pg_temp.on_phone('+61491570522') = 0,
  'R8 Rachel through her mother''s record''s link (her login is on it) on her own mobile: herself (before 440: her mother''s referral); the mother: herself, as before');
-- A login an Owner unlinks: not the record's any more; its next sign-in adds a second copy, the first kept.
select pg_temp.onboard('lUn', 'Una', 'Testunlink', '+61491570523');
select pg_temp.as_user('o');
do $$ begin
  insert into fx values ('cUn', (pg_temp.ans('lUn')->>'customer_id')::uuid);
  insert into tx values ('code_un', pg_temp.ans('lUn')->>'referral_code');
  -- The record's own name and phone change, so only the login could make her "herself".
  update customers set full_name = 'Unity Testrecord', phone = '+61491570525' where id = pg_temp.fx('cUn');
  perform public.unlink_affiliate_account(pg_temp.fx('cUn'), 'T440: someone else');
end $$;
select pg_temp.ref('r9', pg_temp.tx('code_un'), 'Una', 'Testunlink', '+61491570524', pg_temp.mail('r9'));
select pg_temp.onboard('lUn', 'Una', 'Testunlink', '+61491570523');
select pg_temp.check(pg_temp.r('r9')->>'outcome' = 'registered'
    and (select count(*) from public.affiliate_login_signup_details(pg_temp.fx('cUn'))) = 0
    and pg_temp.ans('lUn')->>'status' = 'active' and (pg_temp.ans('lUn')->>'customer_id')::uuid <> pg_temp.fx('cUn')
    and pg_temp.copies('lUn') = 2
    and (select count(*) from public.affiliate_login_signup_details((pg_temp.ans('lUn')->>'customer_id')::uuid)) = 2,
  'R9 a login an Owner unlinked: its old record no longer knows it (registered); its next sign-in (a record of its own) adds a second copy, and the helper gives both');

-- 437's Link: Fred's fresh record (O3) joined into the customer already there. His login, and so
-- his copy, now belong to that customer; through its link his sign-up name is himself.
do $$ declare r jsonb; begin
  perform pg_temp.as_user('o');
  r := public.link_affiliate_signup((select id from affiliate_signup_matches where auth_user_id = pg_temp.fx('lFresh') and status = 'open'),
                                    pg_temp.fx('cShareA'), 'T440: the same person', gen_random_uuid(), false);
  insert into tx values ('r10_link', r::text);
end $$;
select pg_temp.ref('r10', (select referral_code from customer_affiliates where customer_id = pg_temp.fx('cShareA') and deleted_at is null),
                   'Fred', 'Testfresh', '+61491570526', pg_temp.mail('r10'));
select pg_temp.check((pg_temp.tx('r10_link')::jsonb->>'ok')::boolean
    and (select customer_id from affiliate_accounts where auth_user_id = pg_temp.fx('lFresh')) = pg_temp.fx('cShareA')
    and (select d.full_name from public.affiliate_login_signup_details(pg_temp.fx('cShareA')) d) = 'Fred Testfresh'
    and (pg_temp.copy('lFresh')).customer_id = (pg_temp.ans('lFresh')->>'customer_id')::uuid
    and pg_temp.r('r10') = pg_temp.r('r0'),
  'R10 after 437''s Link the copy follows the login to the customer (the row still names the fresh record it was made on); his sign-up name is himself there: '
  || pg_temp.tx('r10_link') || ' ' || coalesce(pg_temp.r('r10')::text, 'none'));

-- ═════ S The seminar website (439) ═════
select to_regprocedure('public.event_web_kept_customer(uuid)') is not null as has_439,
       to_regprocedure('public.event_web_call(text,uuid,text,jsonb)') is not null as has_436 \gset
\if :has_439
select pg_temp.check(md5(pg_get_functiondef('public.event_web_affiliate_contact(uuid)'::regprocedure)) = '3c81727e93dc5b73ca1d8833d95f75bb'
    and md5(pg_get_functiondef('public.event_web_check_self_referral(uuid,uuid)'::regprocedure)) = '2a5ab36c3d878197c21221a9a1ff193f',
  'S0 with 439 in, its two login checks are 440''s (if 439 went in after 440, they are still 439''s: run 440 again)');
create function pg_temp.d(n int) returns date language sql as $$ select public.sg_today() + n $$;
create function pg_temp.bid(prefix text, tag text) returns text language sql as
$$ select prefix || '-' || to_char(public.sg_today(), 'YYYYMMDD') || '-' || upper(substr(md5(pg_temp.tx('sfx') || prefix || tag), 1, 8)) $$;
create function pg_temp.call(kind text, typ text, body jsonb, req uuid default gen_random_uuid()) returns jsonb
language plpgsql as $$
declare v jsonb; v_sub text := current_setting('request.jwt.claim.sub', true); v_role text := current_setting('request.jwt.claim.role', true);
begin
  perform pg_temp.as_service();
  v := public.event_web_call(pg_temp.tx('hash:' || kind), case when typ in ('event_info','referral_info','person','sync') then null else req end,
                             typ, jsonb_build_object('type', typ, 'event', pg_temp.tx('code')) || body);
  perform set_config('request.jwt.claim.sub', coalesce(v_sub, ''), true);
  perform set_config('request.jwt.claim.role', coalesce(v_role, ''), true);
  return v;
end $$;
create function pg_temp.reg1(tag text, first text, last text, phone text, email text, code text) returns uuid language plpgsql as $$
declare v jsonb;
begin
  v := pg_temp.call('live', 'register', jsonb_build_object('registration', jsonb_build_object(
         'registration_id', pg_temp.bid('REG', tag), 'submitted_at', now(), 'referral_code', code,
         'people', jsonb_build_array(jsonb_build_object('position', 1, 'first_name', first, 'last_name', last, 'phone', phone,
                                                         'email', email, 'days', to_jsonb(array[pg_temp.d(7)]), 'vip', false)))));
  perform pg_temp.put('reg:' || tag, v::text);
  perform pg_temp.putx('p_' || tag, (v->'people'->0->>'person_id')::uuid);
  return (v->'people'->0->>'person_id')::uuid;
end $$;
create function pg_temp.pp(tag text) returns public.event_registration_people language sql as
$$ select * from public.event_registration_people where id = pg_temp.fx('p_' || tag) $$;
do $$
declare sfx text := upper(pg_temp.tx('sfx')); u uuid; k text; st uuid; ev uuid; src uuid; pm uuid; v1 uuid; v2 uuid;
begin
  foreach k in array array['acting', 'manager'] loop
    u := gen_random_uuid();
    insert into auth.users(id, email) values (u, pg_temp.mail('staff-' || k));
    insert into profiles(id, full_name, email, role, is_active)
    values (u, 'T440 ' || initcap(k), pg_temp.mail('staff-' || k), case k when 'acting' then 'owner' else 'manager' end::user_role, true);
    insert into fx values (k, u);
  end loop;
  insert into app_settings(id) values (true) on conflict (id) do nothing;
  perform pg_temp.as_user('o');
  insert into stores(name, code, country_code) values ('T440 Van ' || sfx, 'T440V' || sfx, 'SG') returning id into st;
  insert into fx values ('van', st);
  insert into user_store_assignments(user_id, store_id) values (pg_temp.fx('manager'), st);
  ev := public.event_save(jsonb_build_object('name', 'T440 Health Seminar ' || sfx,
    'daily_start', '09:00', 'daily_end', '19:00',
    'days', jsonb_build_array(jsonb_build_object('day', pg_temp.d(7)), jsonb_build_object('day', pg_temp.d(8))),
    'store_ids', jsonb_build_array(st),
    'options', jsonb_build_array(jsonb_build_object('name', 'VIP', 'days_count', 2, 'price', 72))));
  insert into fx values ('ev', ev), ('vip', (select id from public.event_ticket_options where event_id = ev));
  insert into customer_source_options(label, is_active, requires_details, sort_order)
  values ('T440 Event ' || sfx, true, true, 9999) returning id into src;
  foreach k in array array['HitPay (online)', 'PayNow', 'Bank Transfer'] loop
    pm := null;
    select id into pm from public.payment_methods where lower(btrim(name)) = lower(k) and deleted_at is null order by created_at limit 1;
    if pm is null then insert into public.payment_methods(name, is_active) values (k, true) returning id into pm;
    else update public.payment_methods set is_active = true where id = pm; end if;
    insert into fx values (case k when 'PayNow' then 'paynow' when 'Bank Transfer' then 'bank' else 'hitpay' end, pm);
  end loop;
  insert into vouchers(name, code, voucher_kind, discount_amount, qty_type, selling_price, is_active)
  values ('T440 $72 discount Voucher', 'T440SAVE72' || sfx, 'fixed_discount', 72, 'unlimited', 72, true) returning id into v1;
  insert into vouchers(name, code, voucher_kind, qty_type, selling_price, is_active)
  values ('T440 3-in-1 Vouchers', 'T440-3IN1' || sfx, 'normal', 'unlimited', 216, true) returning id into v2;
  insert into voucher_store_prices(voucher_id, store_id, selling_price, available_at_store) values (v1, st, 72, true), (v2, st, 216, true);
  perform public.event_web_settings_save(ev, jsonb_build_object('code', 'T440-' || sfx, 'mode', 'live', 'venue', null,
     'store_id', st, 'acting_profile_id', pg_temp.fx('acting'), 'vip_option_id', pg_temp.fx('vip'),
     'vip_voucher_ids', jsonb_build_array(v1, v2), 'gift_product_ids', '[]'::jsonb,
     'hitpay_payment_method_id', pg_temp.fx('hitpay'), 'paynow_payment_method_id', pg_temp.fx('paynow'),
     'bank_payment_method_id', pg_temp.fx('bank'), 'source_option_id', src,
     'source_details', 'Health Seminar (website)', 'sync_url', 'https://healthtalk.example.com/api/app/sync'));
  insert into tx values ('code', 'T440-' || sfx);
end $$;
do $$ declare r jsonb; begin
  perform pg_temp.as_user('o');
  r := public.event_web_key_create(pg_temp.fx('ev'), 'live', 'Vercel production');
  insert into tx values ('hash:live', encode(extensions.digest(r->>'key', 'sha256'), 'hex'));
end $$;
select pg_temp.check((pg_temp.call('live', 'event_info', '{}')->>'ok')::boolean, 'S0 the fixture event answers event_info');
-- Rachel's login joins her mother's record on the household phone (rule 7); then she edits her metadata.
do $$ begin perform pg_temp.login('lRach', '{}'::jsonb); end $$;
select pg_temp.as_user('o');
do $$ declare c uuid; begin
  insert into customers(full_name, phone) values ('Siew Lan Testmum', '+61491570540') returning id into c; insert into fx values ('cMum2', c);
end $$;
select pg_temp.onboard('lRach', 'Rachel', 'Testmum', '+61491570540');
update auth.users set raw_user_meta_data = jsonb_build_object('first_name', 'Zed', 'last_name', 'Edited', 'phone', '+61491570541')
 where id = pg_temp.fx('lRach');
select pg_temp.as_service();
select pg_temp.reg1('s1', 'Rachel', 'Testmum', '+61491570542', pg_temp.mail('lRach'), pg_temp.ans('lRach')->>'referral_code');
select pg_temp.reg1('s2', 'Zed', 'Edited', '+61491570541', pg_temp.mail('s2'), pg_temp.ans('lRach')->>'referral_code');
select pg_temp.check((pg_temp.ans('lRach')->>'customer_id')::uuid = pg_temp.fx('cMum2')
    and (pg_temp.pp('s1')).match = 'held' and (pg_temp.pp('s1')).hold_reason = 'affiliate_name'
    and (pg_temp.pp('s1')).referral_outcome = 'self' and (pg_temp.pp('s1')).referral_self_by = array['name', 'email']
    and pg_temp.on_phone('+61491570542') = 0
    and exists (select 1 from audit_logs l where l.record_id = pg_temp.fx('p_s1') and l.action = 'event_registration_self_referral'
                  and l.new_data->>'name_from' = 'login'),
  'S1 Rachel (her login on her mother''s record), after editing her metadata, registers on her own mobile with her login email: held as herself by her login''s copy (name and email): '
  || coalesce(pg_temp.tx('reg:s1'), 'none'));
select pg_temp.check((pg_temp.pp('s2')).match = 'new_customer' and (pg_temp.pp('s2')).referral_outcome = 'created'
    and (pg_temp.pp('s2')).referral_self_by is null and public.event_web_affiliate_contact(pg_temp.fx('p_s2')) is null
    and (select referred_by from customers where id = (pg_temp.pp('s2')).customer_id) = pg_temp.fx('cMum2'),
  'S2 the name and phone she edited into her metadata are someone else: a new customer, referred at once (before 440, with 439: herself)');
-- Gina (R): her record shares nothing with her login, and she changes her auth email again
-- (R6 made a customer with the one before).
update auth.users set email = pg_temp.mail('gina-newer') where id = pg_temp.fx('lGina');
select pg_temp.reg1('s3', 'Otto', 'Friend', '+61491570510', pg_temp.mail('s3'), pg_temp.tx('code_gina'));
select pg_temp.reg1('s4', 'Pia', 'Friend', '+61491570543', pg_temp.mail('lGina'), pg_temp.tx('code_gina'));
select pg_temp.reg1('s5', 'Quin', 'Friend', '+61491570544', pg_temp.mail('gina-newer'), pg_temp.tx('code_gina'));
select pg_temp.reg1('s6', 'Gina', 'Testlogin', '+61491570545', pg_temp.mail('s6'), pg_temp.tx('code_gina'));
select pg_temp.check((pg_temp.pp('s3')).referral_outcome = 'check_waiting' and public.event_web_affiliate_contact(pg_temp.fx('p_s3')) = array['phone']
    and (select referred_by from customers where id = (pg_temp.pp('s3')).customer_id) is null,
  'S3 someone else on the phone her login signed up with (on no record): a check, not referred at once (439''s A, now from the copy)');
select pg_temp.check((pg_temp.pp('s4')).referral_outcome = 'check_waiting' and public.event_web_affiliate_contact(pg_temp.fx('p_s4')) = array['email'],
  'S4 someone else on the email her login signed up with, after she changed it: a check (the copy''s email)');
select pg_temp.check((pg_temp.pp('s5')).referral_outcome = 'created' and public.event_web_affiliate_contact(pg_temp.fx('p_s5')) is null
    and (select referred_by from customers where id = (pg_temp.pp('s5')).customer_id) = pg_temp.fx('cGina'),
  'S5 someone on her NEW auth email: not hers (before 440, with 439: a check)');
select pg_temp.check((pg_temp.pp('s6')).hold_reason = 'affiliate_name' and (pg_temp.pp('s6')).referral_outcome = 'self'
    and (pg_temp.pp('s6')).referral_self_by = array['name'],
  'S6 her login''s name (the copy''s) on a new phone and email: held as herself');
\else
\if :has_436
select pg_temp.check(md5(pg_get_functiondef('public.event_web_affiliate_contact(uuid)'::regprocedure)) = '2e36126ac19182665357e2a934252db6'
    and md5(pg_get_functiondef('public.event_web_check_self_referral(uuid,uuid)'::regprocedure)) = '7c13dd04c230ddedf201db59244bdaff',
  'S0 without 439, 436''s two checks are untouched (440''s C was skipped)');
\endif
do $$ begin raise notice 'NOTE  S (the seminar website) is skipped: 439 is not installed'; end $$;
\endif

-- ═════ G Grants, md5s and the table ═════
select pg_temp.check(not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('authenticated', p.oid, 'execute')
    and has_function_privilege('service_role', p.oid, 'execute'),
  'G1 ' || p.oid::regprocedure::text || ' is the service role''s alone')
  from pg_proc p where p.oid in (to_regprocedure('public.affiliate_login_signup_details(uuid)'),
                                 to_regprocedure('public.trg_affiliate_signup_identity_kept()'));
select pg_temp.check(not has_function_privilege('anon', 'public.complete_affiliate_onboarding(text,text,text,boolean)', 'execute')
    and has_function_privilege('authenticated', 'public.complete_affiliate_onboarding(text,text,text,boolean)', 'execute')
    and has_function_privilege('anon', 'public.affiliate_referral_signup(text,text,text,text,text,text)', 'execute')
    and has_function_privilege('authenticated', 'public.affiliate_referral_signup(text,text,text,text,text,text)', 'execute'),
  'G2 the sign-up stays the signed-in login''s; /r/ stays the anon key''s');
select pg_temp.check(md5(pg_get_functiondef('public.complete_affiliate_onboarding(text,text,text,boolean)'::regprocedure)) = '43084deab54968eacaf1793c470fd08f'
    and md5(pg_get_functiondef('public.affiliate_referral_signup(text,text,text,text,text,text)'::regprocedure))
          in ('a3deac154f5144cffb34fab871f076c6', 'c76573912de0a4ded29e81e5c56c96d3')
    and md5(pg_get_functiondef('public.affiliate_login_signup_details(uuid)'::regprocedure)) = '71e6d6f9ab2b474450b5c00f60f14bb4'
    and md5(pg_get_functiondef('public.trg_affiliate_signup_identity_kept()'::regprocedure)) = 'b8c77a682d1a99783bfa708471c9f27e',
  'G3 the functions have 440''s AFTER md5s (affiliate_referral_signup: 440''s, or 442''s built on it)');
select pg_temp.check((select relrowsecurity from pg_class where oid = 'public.affiliate_signup_identities'::regclass)
    and not exists (select 1 from pg_policy where polrelid = 'public.affiliate_signup_identities'::regclass)
    and (select relacl::text from pg_class where oid = 'public.affiliate_signup_identities'::regclass) = '{postgres=arwdDxtm/postgres,service_role=r/postgres}'
    and exists (select 1 from pg_trigger where tgrelid = 'public.affiliate_signup_identities'::regclass
                  and tgname = 'affiliate_signup_identities_kept' and tgenabled = 'O'),
  'G4 the table: row level security on, no policy, the service role may read it, nobody else holds anything; its UPDATE trigger is on');

do $$
declare n int; m text;
begin
  select count(*), string_agg(msg, E'\n  ') into n, m from failed;
  if n > 0 then raise exception E'login-identity-440: % check(s) failed:\n  %', n, m; end if;
  raise notice 'login-identity-440: all checks passed';
end $$;
rollback;
