-- Affiliate sign-up goes straight in (437; the Owner's decisions of 20 Oct
-- 2026, AFF-SIGNUP-1..8, the Owner's answers on Link, AFF-SIGNUP-12..14, and
-- those of 21 Oct 2026, AFF-SIGNUP-16..18).
--
--   J1 One customer has the phone: the login joins them on the phone alone,
--      whatever name and email it typed (7). The email is not verified.
--      Under a name that is not theirs it is also listed "may be someone
--      else" (18).
--   J2 Two share the phone: the one whose name has the same words is joined
--      (8); the name exactly as typed comes first.
--   J3 Two share it and the name is someone else's: a fresh record, listed
--      for staff ('shared_phone') with both; the person is told nothing.
--   J4 Two share it under the very same name: a fresh record, listed.
--   J5 The phone is then full (3): a fresh record is refused by the phone
--      rule, nothing is left behind, and another phone works.
--   J6 No one has the phone: a fresh record, not listed; a phone only a
--      deleted customer had is the same.
--   J7 No one has the phone but a customer has the same inbox: fresh,
--      listed ('email_match'); one with a name of the same words: fresh,
--      listed ('name_match').
--   J8 Only a customer whose stored 8-digit number could be this one (SG or
--      MY): fresh, listed ('phone_unconfirmed').
--   S1 A customer an Owner unlinked a login from (378), or an Owner or
--      Manager rejected a claim for (379): never joined by itself; fresh,
--      listed ('protected_customer').
--   S2 A customer who already has a portal login: fresh, listed
--      ('customer_has_login'). One whose affiliate record was removed: fresh,
--      listed ('affiliate_removed').
--   S3 A staff login is refused (STAFF_ACCOUNT), nothing written.
--   S4 A login with a rejected claim stays rejected, even on a phone and an
--      email no one has; nothing is created.
--   S5 A login that is not confirmed is refused (the backstop).
--   D  A second press answers "already" and changes nothing: one account,
--      one customer, one list entry, one audit row.
--   C  A stuck login with a pending claim, details from the account: let in
--      by the new rules, its claim closed ('resolved', 437) and whom it
--      suggested listed with a fresh record.
--   E  The app's own "email verified": unverified for a login the sign-up
--      function or the repair confirmed (app_metadata marker); verified for
--      a login Supabase confirmed by its own link (no marker), or a session
--      from an emailed link; confirm_affiliate_email() verifies only from an
--      emailed link in the last 30 minutes, once, with an audit row;
--      affiliate_email_verification_needed answers the sign-up function.
--   L  The list and the link (6): Staff and Admin are refused, a Manager and
--      an Owner see the entries with how each candidate matches and why one
--      cannot be linked; a link merges the fresh record into the customer
--      (merge_customer_records): the login, the affiliate record and its
--      code, and the referral made meanwhile move; the fresh record is
--      retired; the entry leaves the list; audit rows; a retry with the same
--      request id is "replayed"; a customer not listed, one with a login and
--      a second link are refused; Keep separate needs a reason.
--   W  A customer with an affiliate record of their own (an Owner unlinked
--      the login that had it): linked, they keep their record and its code,
--      the login moves onto it and the fresh record's unused one is retired;
--      refused, and said on the list, while the fresh record has a referral
--      (a decision about money), or when the customer's record was removed.
--   K  (AFF-SIGNUP-14) The list gives the new record's code and each
--      customer's own: linked to a customer with one, the new code is
--      retired (AFF-SIGNUP-9) and no longer finds anyone (no alias).
--   V  An email verified, then the login unlinked by an Owner: the account
--      made at its next sign-in is verified still (the login keeps it).
--   T  (AFF-SIGNUP-13) Twin records: a sign-up with the very same phone and a
--      name of the same words as a customer who already has an affiliate
--      login still goes straight in, on a fresh record; the list flags the
--      entry and that customer (twin), and not a customer with the phone but
--      another name, nor two such records with no login. The list gives the
--      twin's own code and the new record's, which the page names so the
--      Owner unlinks the right one of the two rows with that name. The fix:
--      an Owner unlinks the wrong login, the flag goes, and the sign-up is
--      linked.
--   P  (AFF-SIGNUP-12) The phone and email on Link: the email they signed up
--      with is copied onto a customer with none (with the Customers page's
--      audit row); not when the customer has one or another customer in use
--      has it (the answer says so; a Gmail address written another way is
--      the same inbox, on the list too); a deleted customer with it does not
--      count. An email Staff save after the list was read is kept (the
--      customer has one now), and is the link's audit row's "before".
--      Ticked, the customer's phone becomes the one they signed up with
--      through update_customer (phone history, the reason, the audit row),
--      taking the place the retired fresh record leaves on a phone 3
--      customers hold; refused by the phone rule (3 others hold it), the
--      whole link is refused and nothing changes, and unticked it then goes
--      through on the same request id; so too for a customer with a code of
--      her own, whose new code (retired just before the merge) is still
--      there after the refusal. Unticked (the default) the customer keeps
--      their phone. The link's audit row says what was copied and changed;
--      a replay with the same request id is "replayed" and changes nothing.
--   PB (AFF-SIGNUP-16) The phone box's default, from the list: ticked when
--      the email cannot be copied (the customer keeps their own; another
--      customer has it), or when a QR health form (433) or, with 436 in, a
--      seminar registration held with the fresh record as a candidate waits
--      under To match (a test one, one attached or one sorted out does not
--      count); unticked otherwise; no box for the same phone. Without 436
--      the seminar count is null and the list still works (a NOTE says the
--      seminar part was skipped).
--   EL (AFF-SIGNUP-17) Link earns what the fresh record's paid invoices
--      missed: a product, a seminar VIP and a product with a part refund,
--      paid on the fresh record with no commission, earn tier 1 for the
--      customer's referrer and tier 2 as the engine has it (blocked: the
--      upline has no affiliate record), the refund taken off, all dated
--      the Link day (not the day paid); a credit package, a premium bundle,
--      and a product with a package earn in full, exactly what payment
--      earns on the same sale to a customer with that referrer (the package
--      and bundle functions too), dated the Link day; one already
--      commissioned (another affiliate's code) is left alone; one through
--      her own code, and a package whose invoice names no affiliate on
--      purpose, earn nothing (none due); one the engine refuses keeps no
--      rows and is named, the link standing; one not paid earns nothing;
--      the answer and the audit row list them; a replay earns nothing more
--      and answers what the link did (the same commission lists, email and
--      phone); afterwards the engine's own reconcile (a part refund) dates
--      what it earns again by the day the invoice was paid, as for any
--      invoice; a customer with no referrer: nothing.
--   FJ (AFF-SIGNUP-18) A phone-only join under another name: the outcome of
--      the sign-up as before (joined, told nothing), listed
--      'phone_other_name' (kind may_be_someone_else, the name typed and the
--      record's, no candidates); Link and Keep separate refused; Same person
--      (Owner or Manager, a note) closes it, audited, once; the same words
--      in another order are not listed; someone else: an Owner unlinks the
--      login, the entry leaves the list, and the next sign-in gives a record
--      of their own, the stale entry gone.
--   I  A login the sign-up made, its email not verified, is never given to a
--      staff invitation for that address (login_in_use), even when its
--      metadata says it was invited, and gets no profile when the invitation
--      was cancelled meanwhile; an ordinary login is provisioned as before.
--   A  Every join and fresh record writes one 'affiliate_portal_claimed' row
--      with the rule and the reason it is listed.
--   U  Signed in for real (role authenticated): sign-up works; the helpers
--      cannot be called; the list table is closed.
--   M  437 installs here twice; the second run changes nothing; it left no
--      self-test row.
--
-- Disposable database only; everything is rolled back. Needs 430 (437
-- refuses to run before it). Run from the repository root:
--   psql -X -v ON_ERROR_STOP=1 -f scripts/affiliate-signup/tests/straight-in-437.sql
-- (with -v nomig=1 on a database where 437 is applied, to skip installing it).
-- Every name, phone and email below is invented: ACMA fictional numbers
-- (+614915xxxxx), one Singapore test number for the 8-digit case, and
-- @example.com addresses.
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '10s';
set local statement_timeout = '120s';
\if :{?nomig}
\else
\ir ../../../supabase/437_affiliate_signup_straight_in.sql
create temp table fp1 as select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.oid::regprocedure::text)) fp
  from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p');
\ir ../../../supabase/437_affiliate_signup_straight_in.sql
\endif

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
-- Signed in as a login, with no session claims or with an "amr" entry of the
-- given method, opened the given time ago.
create function pg_temp.as_user(key text, amr text default null, ago interval default '0 seconds') returns void language plpgsql as
$$begin
  perform set_config('request.jwt.claim.sub', coalesce(pg_temp.fx(key)::text, ''), true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform set_config('request.jwt.claims', case when amr is null then '' else
    jsonb_build_object('sub', pg_temp.fx(key), 'role', 'authenticated',
      'amr', jsonb_build_array(jsonb_build_object('method', amr, 'timestamp', floor(extract(epoch from now() - ago))::bigint)))::text end, true);
end$$;
create function pg_temp.err(q text) returns text language plpgsql as
$$begin execute q; return null; exception when others then return sqlstate || ' ' || sqlerrm; end$$;
create function pg_temp.mail(login text) returns text language sql as $$ select email from auth.users where id = pg_temp.fx(login) $$;
create function pg_temp.linked_to(login text) returns uuid language sql as
$$ select customer_id from public.affiliate_accounts where auth_user_id = pg_temp.fx(login) $$;
create function pg_temp.on_phone(p text) returns int language sql as
$$ select count(*)::int from public.customers c where c.deleted_at is null and public.normalize_customer_phone(c.phone) = p $$;
create function pg_temp.entry(login text) returns public.affiliate_signup_matches language sql as
$$ select * from public.affiliate_signup_matches where auth_user_id = pg_temp.fx(login) order by created_at desc limit 1 $$;
create function pg_temp.claimed(login text) returns jsonb language sql as
$$ select l.new_data from audit_logs l join affiliate_accounts a on a.id = l.record_id
    where l.table_name = 'affiliate_accounts' and l.action = 'affiliate_portal_claimed' and a.auth_user_id = pg_temp.fx(login) $$;
create function pg_temp.claimed_rows(login text) returns int language sql as
$$ select count(*)::int from audit_logs where action = 'affiliate_portal_claimed' and new_data->>'auth_user_id' = pg_temp.fx(login)::text $$;
-- The sign-up the pages run, as the login. Keeps the answer (or the error)
-- under 'onb:<login>'.
create function pg_temp.onboard(login text, first text, last text, phone text) returns text language plpgsql as
$$declare r jsonb; begin
  perform pg_temp.as_user(login);
  r := public.complete_affiliate_onboarding(first, last, phone, true);
  insert into tx values ('onb:' || login, r::text) on conflict (k) do update set v = excluded.v;
  return coalesce(r->>'status', '?');
exception when others then
  insert into tx values ('onb:' || login, 'ERROR: ' || sqlerrm) on conflict (k) do update set v = excluded.v;
  return 'ERROR: ' || sqlerrm;
end$$;
-- An entry of a list kept under a key, and one of its candidates.
create function pg_temp.listed(list text, login text) returns jsonb language sql as
$$ select e from jsonb_array_elements(pg_temp.tx(list)::jsonb) e where (e->>'match_id')::uuid = (pg_temp.entry(login)).id $$;
create function pg_temp.cand(list text, login text, cust text) returns jsonb language sql as
$$ select c from jsonb_array_elements(pg_temp.listed(list, login)->'candidates') c where (c->>'customer_id')::uuid = pg_temp.fx(cust) $$;
create function pg_temp.ans(login text) returns jsonb language sql as
$$ select case when pg_temp.tx('onb:' || login) like 'ERROR:%' then jsonb_build_object('error', pg_temp.tx('onb:' || login))
               else pg_temp.tx('onb:' || login)::jsonb end $$;

select pg_temp.check(position('437:' in (select prosrc from pg_proc where oid = to_regprocedure('public.complete_affiliate_onboarding(text,text,text,boolean)'))) > 0
    and to_regclass('public.affiliate_signup_matches') is not null
    and exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'affiliate_accounts' and column_name = 'email_verified_at'),
  'P0 437 is installed');
select pg_temp.check(not exists (select 1 from public.customers
                                  where public.normalize_customer_phone(phone) in ('+61491570737', '+61491572983', '+61491573770', '+61491573087',
                                    '+61491574118', '+61491574632', '+61491575254', '+61491575789', '+61491576398', '+61491576801',
                                    '+61491577426', '+61491577644', '+61491570156', '+61491570157', '+61491570158', '+61491570159',
                                    '+61491578148', '+61491578888', '+61491579212', '+61491579760', '+61491579455', '+6584370150',
                                    '+61491570006', '+61491572549', '+61491570401', '+61491570402', '+61491570403',
                                    '+61491570404', '+61491570405', '+61491570406', '+61491570407', '+61491570408',
                                    '+61491570409', '+61491578401', '+61491578402', '+61491578403', '+61491578404',
                                    '+61491570410', '+61491570411', '+61491570412', '+61491578405', '+61491578406',
                                    '+61491578407', '+61491578408', '+61491578409', '+61491578410', '+61491578411',
                                    '+61491578412', '+61491578413', '+61491578414', '+61491578415', '+61491578416',
                                    '+61491578417', '+61491578418', '+61491578419', '+61491578420', '+61491578421',
                                    '+61491578422', '+61491578423', '+61491578424', '+61491578425')
                                     or phone = '84370150'),
  'P0 no customer uses the test phones (the checks below assume so)');

-- ═════ Fixtures ═════
do $$
declare sfx text := lower(substr(md5(random()::text || clock_timestamp()::text), 1, 6)); k text; u uuid;
begin
  insert into tx values ('sfx', sfx);
  -- Staff.
  foreach k in array array['o', 'm', 's', 'a'] loop
    u := gen_random_uuid(); insert into fx values (k, u);
    insert into auth.users(id, email, email_confirmed_at) values (u, 't437-' || k || '-' || sfx || '@example.com', now());
  end loop;
  insert into profiles(id, full_name, email, role) values
    (pg_temp.fx('o'), 'T437 Owner',   't437-o-' || sfx || '@example.com', 'owner'),
    (pg_temp.fx('m'), 'T437 Manager', 't437-m-' || sfx || '@example.com', 'manager'),
    (pg_temp.fx('s'), 'T437 Staff',   't437-s-' || sfx || '@example.com', 'staff'),
    (pg_temp.fx('a'), 'T437 Admin',   't437-a-' || sfx || '@example.com', 'admin');
  -- Affiliate logins made by the sign-up function (confirmed, marked
  -- unverified), with the details it stores.
  foreach k in array array['lSolo', 'lBea', 'lDan', 'lDuo', 'lEve', 'lNeo', 'lOld9', 'lMia', 'lNam', 'lMay', 'lPat',
                           'lRae', 'lHas', 'lRem', 'lRej', 'lStk', 'lStk2', 'lLink', 'lU', 'lOther', 'lWes1', 'lWes2',
                           'lTia', 'lGra', 'lHal', 'lKim', 'lLeo', 'lMoe', 'lUma', 'lZoe', 'lVik', 'lWyn',
                           'lQra', 'lErn', 'lNor', 'lFam', 'lSam', 'lFam2'] loop
    u := gen_random_uuid(); insert into fx values (k, u);
    insert into auth.users(id, email, email_confirmed_at, raw_app_meta_data, raw_user_meta_data)
    values (u, 't437-' || lower(k) || '-' || sfx || '@example.com', now(),
            '{"provider": "email", "affiliate_email_unverified": true}'::jsonb, '{}'::jsonb);
  end loop;
  -- A login from before 437, confirmed by Supabase's own email link (no
  -- marker); one never confirmed.
  u := gen_random_uuid(); insert into fx values ('lOld', u);
  insert into auth.users(id, email, email_confirmed_at, raw_app_meta_data) values
    (u, 't437-lold-' || sfx || '@example.com', now() - interval '3 days', '{"provider": "email"}'::jsonb);
  u := gen_random_uuid(); insert into fx values ('lUnc', u);
  insert into auth.users(id, email, email_confirmed_at, raw_app_meta_data) values
    (u, 't437-lunc-' || sfx || '@example.com', null, '{"provider": "email"}'::jsonb);
  -- An old login with an affiliate account on cHas, and one an Owner will unlink.
  foreach k in array array['lHasOld', 'lPatOld', 'lTiaOld'] loop
    u := gen_random_uuid(); insert into fx values (k, u);
    insert into auth.users(id, email, email_confirmed_at) values (u, 't437-' || lower(k) || '-' || sfx || '@example.com', now());
  end loop;
  -- The stuck logins keep the details they signed up with.
  update auth.users set raw_user_meta_data = jsonb_build_object('first_name', 'Stu', 'last_name', 'Teststuck', 'phone', '+61491577644')
   where id = pg_temp.fx('lStk');
  update auth.users set raw_user_meta_data = jsonb_build_object('first_name', 'Sid', 'last_name', 'Testsidney', 'phone', '+61491570156')
   where id = pg_temp.fx('lStk2');
end $$;

select pg_temp.as_user('o');
do $$
declare c uuid; sfx text := pg_temp.tx('sfx');
begin
  -- J1: one customer has the phone.
  insert into customers(full_name, phone, email) values ('Ada Testsolo', '+61491570737', 't437-ada-' || sfx || '@example.com')
    returning id into c; insert into fx values ('cSolo', c);
  -- J2/J3: two share a phone.
  insert into customers(full_name, phone) values ('Bea Lin Testshare', '+61491572983') returning id into c; insert into fx values ('cBea', c);
  insert into customers(full_name, phone) values ('Cal Testshare', '+61491572983') returning id into c; insert into fx values ('cCal', c);
  -- J4: two share a phone under the same name.
  insert into customers(full_name, phone) values ('Duo Testtwin', '+61491570158') returning id into c; insert into fx values ('cDuo1', c);
  insert into customers(full_name, phone) values ('Duo Testtwin', '+61491570158') returning id into c; insert into fx values ('cDuo2', c);
  -- J6: only a deleted customer had this phone.
  insert into customers(full_name, phone) values ('Old Testgone', '+61491570157') returning id into c; insert into fx values ('cGone', c);
  update customers set deleted_at = now() where id = c;
  -- J7: the same inbox; a name with the same words.
  insert into customers(full_name, phone, email) values ('Mia Testmail', '+61491573087', pg_temp.mail('lMia'))
    returning id into c; insert into fx values ('cMail', c);
  insert into customers(full_name, phone) values ('Ong Mei Ling (Testorchard)', '+61491574632') returning id into c; insert into fx values ('cName', c);
  -- S1: protected customers.
  insert into customers(full_name, phone) values ('Pat Testprot', '+61491575789') returning id into c; insert into fx values ('cPat', c);
  insert into customers(full_name, phone) values ('Rae Testrej', '+61491576398') returning id into c; insert into fx values ('cRae', c);
  -- S2: a customer with a portal login; one whose affiliate record was removed.
  insert into customers(full_name, phone) values ('Han Testhas', '+61491576801') returning id into c; insert into fx values ('cHas', c);
  insert into customers(full_name, phone) values ('Rem Testremoved', '+61491570159') returning id into c; insert into fx values ('cRem', c);
  -- W: a customer with an affiliate record of their own, whose login an
  -- Owner unlinks below.
  insert into customers(full_name, phone) values ('Wes Testown', '+61491570006') returning id into c; insert into fx values ('cWes', c);
  -- C: the stuck logins' customers.
  insert into customers(full_name, phone) values ('Stu Teststuck', '+61491577644') returning id into c; insert into fx values ('cStk', c);
  insert into customers(full_name, phone) values ('Sam Testsidney', '+61491570156') returning id into c; insert into fx values ('cSid1', c);
  insert into customers(full_name, phone) values ('Sue Testsidney', '+61491570156') returning id into c; insert into fx values ('cSid2', c);
  insert into customers(full_name, phone) values ('Sid Testelsewhere', '+61491579760') returning id into c; insert into fx values ('cSidOld', c);
end $$;
-- J8: a legacy record whose 8-digit number could be Singapore or Malaysia
-- (the phone rules would refuse it today, so it is written as old data was).
do $$ declare c uuid; begin
  set local session_replication_role = replica;
  insert into customers(full_name, phone) values ('May Testlegacy', '84370150') returning id into c;
  set local session_replication_role = origin;
  insert into fx values ('cMay', c);
end $$;
-- S2: cHas has an affiliate record and a portal login; cRem had one, removed.
do $$ declare a uuid; begin
  insert into customer_affiliates(customer_id, status, activated_at, referral_code) values (pg_temp.fx('cHas'), 'active', now(), 'T437HAS')
    returning id into a;
  insert into affiliate_accounts(auth_user_id, customer_id, affiliate_id, status) values (pg_temp.fx('lHasOld'), pg_temp.fx('cHas'), a, 'claimed');
  insert into customer_affiliates(customer_id, status, activated_at, referral_code, deleted_at) values
    (pg_temp.fx('cRem'), 'soft_deleted', now() - interval '9 days', 'T437REM', now() - interval '2 days');
  -- S1: cPat had a login, which an Owner unlinks below.
  insert into customer_affiliates(customer_id, status, activated_at, referral_code) values (pg_temp.fx('cPat'), 'active', now(), 'T437PAT')
    returning id into a;
  insert into affiliate_accounts(auth_user_id, customer_id, affiliate_id, status) values (pg_temp.fx('lPatOld'), pg_temp.fx('cPat'), a, 'claimed');
  -- W: Wes is an affiliate with no login yet.
  insert into customer_affiliates(customer_id, status, activated_at, referral_code) values (pg_temp.fx('cWes'), 'active', now(), 'T437WES');
end $$;
select pg_temp.as_user('o');
insert into tx values ('unlink_pat', coalesce(pg_temp.err(format('select public.unlink_affiliate_account(%L, %L)', pg_temp.fx('cPat'), 'T437 wrong customer')), 'ok'));
select pg_temp.check(pg_temp.tx('unlink_pat') = 'ok' and not exists (select 1 from affiliate_accounts where customer_id = pg_temp.fx('cPat')),
  'S1 setup: an Owner unlinked the login from Pat (378): ' || pg_temp.tx('unlink_pat'));
-- S1: a claim suggesting Rae, rejected by a Manager (379).
insert into affiliate_account_claims(auth_user_id, entered_phone, verified_email, candidate_customer_id, entered_name)
  values (pg_temp.fx('lOther'), '+61491576398', pg_temp.mail('lOther'), pg_temp.fx('cRae'), 'Rae Other');
insert into fx select 'kOther', id from affiliate_account_claims where auth_user_id = pg_temp.fx('lOther');
select pg_temp.as_user('m');
select pg_temp.check(pg_temp.err(format('select public.reject_affiliate_account_claim(%L, %L)', pg_temp.fx('kOther'), 'T437 not the customer')) is null,
  'S1 setup: a Manager rejected a claim that suggested Rae (379)');
-- S4: a login with a rejected claim.
insert into affiliate_account_claims(auth_user_id, entered_phone, verified_email, entered_name, status, rejected_at, rejection_reason)
  values (pg_temp.fx('lRej'), '+61491577426', pg_temp.mail('lRej'), 'Rej Testrejected', 'rejected', now(), 'T437');
-- C: the stuck logins' pending claims (from before 437).
insert into affiliate_account_claims(auth_user_id, entered_phone, verified_email, candidate_customer_id, entered_name)
  values (pg_temp.fx('lStk'), '+61491577644', pg_temp.mail('lStk'), pg_temp.fx('cStk'), 'Stu Teststuck'),
         (pg_temp.fx('lStk2'), '+61491570156', pg_temp.mail('lStk2'), pg_temp.fx('cSidOld'), 'Sid Testsidney');
insert into tx values ('customers_before', (select count(*) from customers)::text);

-- ═════ J1 One customer has the phone: joined on the phone alone ═════
select pg_temp.onboard('lSolo', 'Totally', 'Different', '+61 491 570 737');
select pg_temp.check(pg_temp.ans('lSolo')->>'status' = 'active' and pg_temp.linked_to('lSolo') = pg_temp.fx('cSolo')
    and (pg_temp.ans('lSolo')->>'customer_id')::uuid = pg_temp.fx('cSolo')
    and not (pg_temp.ans('lSolo')->>'new_customer')::boolean and pg_temp.on_phone('+61491570737') = 1,
  'J1 the login joins the one customer with the phone, whatever name and email it typed: ' || pg_temp.ans('lSolo')::text);
select pg_temp.check(exists (select 1 from customer_affiliates where customer_id = pg_temp.fx('cSolo') and referral_code is not null and deleted_at is null)
    and (pg_temp.entry('lSolo')).reason = 'phone_other_name' and (pg_temp.entry('lSolo')).fresh_customer_id = pg_temp.fx('cSolo')
    and (pg_temp.entry('lSolo')).entered_name = 'Totally Different' and (pg_temp.entry('lSolo')).candidate_ids = '{}'::uuid[],
  'J1 F18 the customer becomes an affiliate with a referral code; the name typed is not theirs, so it is listed "may be someone else" (AFF-SIGNUP-18)');
select pg_temp.check(not (pg_temp.ans('lSolo')->>'email_verified')::boolean
    and (select email_verified_at from affiliate_accounts where auth_user_id = pg_temp.fx('lSolo')) is null,
  'J1 E the email is not verified yet (the sign-up function confirmed the login)');
select pg_temp.check(pg_temp.claimed('lSolo')->>'rule' = 'phone' and not (pg_temp.claimed('lSolo')->>'new_customer')::boolean
    and pg_temp.claimed('lSolo')->>'listed_for_staff' = 'phone_other_name'
    and (pg_temp.claimed('lSolo')->>'match_id')::uuid = (pg_temp.entry('lSolo')).id and (pg_temp.claimed('lSolo')->>'version')::int = 437,
  'J1 A the audit row says the phone joined them, and that it is listed: ' || coalesce(pg_temp.claimed('lSolo')::text, '<none>'));

-- ═════ J2 Two share the phone; the name with the same words is joined ═════
select pg_temp.onboard('lBea', 'Testshare', 'Bea Lin', '+61491572983');
select pg_temp.check(pg_temp.ans('lBea')->>'status' = 'active' and pg_temp.linked_to('lBea') = pg_temp.fx('cBea')
    and pg_temp.claimed('lBea')->>'rule' = 'phone_and_same_words' and pg_temp.entry('lBea') is null,
  'J2 two customers share the phone: the one whose name has the same words is joined: ' || pg_temp.ans('lBea')::text);

-- ═════ J3 Two share it, another name: fresh, listed ═════
select pg_temp.onboard('lDan', 'Dan', 'Testshare', '+61491572983');
select pg_temp.check(pg_temp.ans('lDan')->>'status' = 'active' and (pg_temp.ans('lDan')->>'new_customer')::boolean
    and pg_temp.linked_to('lDan') not in (pg_temp.fx('cBea'), pg_temp.fx('cCal'))
    and pg_temp.on_phone('+61491572983') = 3
    and exists (select 1 from customers c where c.id = pg_temp.linked_to('lDan') and c.full_name = 'Dan Testshare'
                  and c.email = pg_temp.mail('lDan')),
  'J3 a third person on the shared phone gets a fresh record with their own name, email and the phone');
insert into fx values ('cDan', pg_temp.linked_to('lDan'));
select pg_temp.check((pg_temp.entry('lDan')).reason = 'shared_phone' and (pg_temp.entry('lDan')).status = 'open'
    and (pg_temp.entry('lDan')).fresh_customer_id = pg_temp.fx('cDan')
    and (pg_temp.entry('lDan')).candidate_ids @> array[pg_temp.fx('cBea'), pg_temp.fx('cCal')],
  'J3 it is listed for staff as shared_phone, with both customers who have the phone');
select pg_temp.check(not (pg_temp.ans('lDan')::text ~* 'Bea|Cal|shared|candidate|reason'),
  'J3 the person is told nothing about the other customers: ' || pg_temp.ans('lDan')::text);
select pg_temp.check(pg_temp.claimed('lDan')->>'rule' = 'fresh' and pg_temp.claimed('lDan')->>'listed_for_staff' = 'shared_phone'
    and (pg_temp.claimed('lDan')->>'match_id')::uuid = (pg_temp.entry('lDan')).id,
  'J3 A the audit row says a fresh record was made and why it is listed');

-- ═════ J4 Two share it under the same name: fresh, listed ═════
select pg_temp.onboard('lDuo', 'Duo', 'Testtwin', '+61491570158');
select pg_temp.check(pg_temp.ans('lDuo')->>'status' = 'active' and (pg_temp.ans('lDuo')->>'new_customer')::boolean
    and (pg_temp.entry('lDuo')).reason = 'shared_phone'
    and (pg_temp.entry('lDuo')).candidate_ids @> array[pg_temp.fx('cDuo1'), pg_temp.fx('cDuo2')],
  'J4 two customers with the phone and the very same name: neither is picked; a fresh record, listed');

-- ═════ J5 The phone is full ═════
select pg_temp.onboard('lEve', 'Eve', 'Testshare', '+61491572983');
select pg_temp.check(pg_temp.ans('lEve')->>'error' like '%CUSTOMER_PHONE_LIMIT%' and pg_temp.linked_to('lEve') is null
    and pg_temp.entry('lEve') is null and pg_temp.on_phone('+61491572983') = 3
    and not exists (select 1 from customers where full_name = 'Eve Testshare'),
  'J5 a fresh record on a phone 3 customers have is refused by the phone rule, and nothing is left behind: ' || coalesce(pg_temp.ans('lEve')::text, ''));
select pg_temp.onboard('lEve', 'Eve', 'Testshare', '+61491577426');
select pg_temp.check(pg_temp.ans('lEve')->>'status' = 'active' and (pg_temp.ans('lEve')->>'new_customer')::boolean,
  'J5 with another phone the person gets in');

-- ═════ J6 No one has the phone ═════
select pg_temp.onboard('lNeo', 'Neo', 'Testnew', '+61491573770');
select pg_temp.check(pg_temp.ans('lNeo')->>'status' = 'active' and (pg_temp.ans('lNeo')->>'new_customer')::boolean
    and pg_temp.entry('lNeo') is null and pg_temp.claimed('lNeo')->>'rule' = 'fresh'
    and pg_temp.claimed('lNeo')->>'listed_for_staff' is null,
  'J6 a phone no one has: a new customer, not listed');
select pg_temp.onboard('lOld9', 'Ola', 'Testnine', '+61491570157');
select pg_temp.check(pg_temp.ans('lOld9')->>'status' = 'active' and (pg_temp.ans('lOld9')->>'new_customer')::boolean
    and pg_temp.entry('lOld9') is null,
  'J6 a phone only a deleted customer had: a new customer, not listed');

-- ═════ J7 The same inbox; the same words ═════
select pg_temp.onboard('lMia', 'Mia', 'Testmail', '+61491574118');
select pg_temp.check(pg_temp.ans('lMia')->>'status' = 'active' and (pg_temp.ans('lMia')->>'new_customer')::boolean
    and pg_temp.linked_to('lMia') <> pg_temp.fx('cMail')
    and (pg_temp.entry('lMia')).reason = 'email_match' and (pg_temp.entry('lMia')).candidate_ids = array[pg_temp.fx('cMail')],
  'J7 a new phone, but a customer has the same inbox: a fresh record, listed as email_match');
select pg_temp.onboard('lNam', 'Mei Ling', 'Ong', '+61491575254');
select pg_temp.check(pg_temp.ans('lNam')->>'status' = 'active' and (pg_temp.ans('lNam')->>'new_customer')::boolean
    and (pg_temp.entry('lNam')).reason = 'name_match' and (pg_temp.entry('lNam')).candidate_ids = array[pg_temp.fx('cName')],
  'J7 a new phone, but a customer''s name has the same words: a fresh record, listed as name_match');

-- ═════ J8 Only a stored number that could be this one ═════
select pg_temp.onboard('lMay', 'May', 'Testlegacy', '+65 8437 0150');
select pg_temp.check(pg_temp.ans('lMay')->>'status' = 'active' and (pg_temp.ans('lMay')->>'new_customer')::boolean
    and pg_temp.linked_to('lMay') <> pg_temp.fx('cMay')
    and (pg_temp.entry('lMay')).reason = 'phone_unconfirmed' and pg_temp.fx('cMay') = any ((pg_temp.entry('lMay')).candidate_ids),
  'J8 only a legacy 8-digit number that could be this phone: not joined on it; a fresh record, listed (phone_unconfirmed)');

-- ═════ S1 Protected customers ═════
select pg_temp.onboard('lPat', 'Pat', 'Testprot', '+61491575789');
select pg_temp.check(pg_temp.ans('lPat')->>'status' = 'active' and (pg_temp.ans('lPat')->>'new_customer')::boolean
    and pg_temp.linked_to('lPat') <> pg_temp.fx('cPat') and (pg_temp.entry('lPat')).reason = 'protected_customer'
    and (pg_temp.entry('lPat')).candidate_ids = array[pg_temp.fx('cPat')],
  'S1 the one customer with the phone had a login unlinked by an Owner (378): not joined; fresh, listed (protected_customer)');
select pg_temp.onboard('lRae', 'Rae', 'Testrej', '+61491576398');
select pg_temp.check(pg_temp.ans('lRae')->>'status' = 'active' and (pg_temp.ans('lRae')->>'new_customer')::boolean
    and pg_temp.linked_to('lRae') <> pg_temp.fx('cRae') and (pg_temp.entry('lRae')).reason = 'protected_customer',
  'S1 the one customer with the phone had a claim rejected by a Manager (379): not joined; fresh, listed (protected_customer)');

-- ═════ S2 A customer who has a login; a removed affiliate record ═════
select pg_temp.onboard('lHas', 'Han', 'Testhas', '+61491576801');
select pg_temp.check(pg_temp.ans('lHas')->>'status' = 'active' and (pg_temp.ans('lHas')->>'new_customer')::boolean
    and pg_temp.linked_to('lHas') <> pg_temp.fx('cHas') and pg_temp.linked_to('lHasOld') = pg_temp.fx('cHas')
    and (pg_temp.entry('lHas')).reason = 'customer_has_login',
  'S2 the customer with the phone already has a portal login: no second one; fresh, listed (customer_has_login)');
select pg_temp.onboard('lRem', 'Rem', 'Testremoved', '+61491570159');
select pg_temp.check(pg_temp.ans('lRem')->>'status' = 'active' and (pg_temp.ans('lRem')->>'new_customer')::boolean
    and pg_temp.linked_to('lRem') <> pg_temp.fx('cRem') and (pg_temp.entry('lRem')).reason = 'affiliate_removed',
  'S2 the customer whose affiliate record was removed: not joined; fresh, listed (affiliate_removed)');

-- ═════ W setup: Wes's first login joins him on the phone, an Owner unlinks it ═════
select pg_temp.onboard('lWes1', 'Some', 'Stranger', '+61491570006');
select pg_temp.check(pg_temp.linked_to('lWes1') = pg_temp.fx('cWes') and pg_temp.ans('lWes1')->>'referral_code' = 'T437WES',
  'W setup: a login typing Wes''s phone joins Wes and his own affiliate record (7): ' || pg_temp.ans('lWes1')::text);
select pg_temp.as_user('o');
insert into tx values ('unlink_wes', coalesce(pg_temp.err(format('select public.unlink_affiliate_account(%L, %L)', pg_temp.fx('cWes'), 'T437 not Wes')), 'ok'));
select pg_temp.onboard('lWes2', 'Wes', 'Testown', '+61491570006');
select pg_temp.check(pg_temp.tx('unlink_wes') = 'ok' and (pg_temp.ans('lWes2')->>'new_customer')::boolean
    and (pg_temp.entry('lWes2')).reason = 'protected_customer' and (pg_temp.entry('lWes2')).candidate_ids = array[pg_temp.fx('cWes')]
    and (select count(*) from customer_affiliates where customer_id = pg_temp.fx('cWes') and deleted_at is null) = 1,
  'W setup: an Owner unlinked it; the real Wes signs up and gets a fresh record, listed (protected_customer); Wes keeps his affiliate record');
insert into fx values ('cWesFresh', pg_temp.linked_to('lWes2'));

-- ═════ S3 A staff login ═════
insert into tx values ('rows_s3', (select (select count(*) from customers) + (select count(*) from affiliate_accounts)
  + (select count(*) from affiliate_signup_matches) + (select count(*) from customer_affiliates))::text);
select pg_temp.onboard('s', 'Staff', 'Member', '+61491579212');
select pg_temp.check(pg_temp.ans('s')->>'error' like '%STAFF_ACCOUNT%'
    and (select (select count(*) from customers) + (select count(*) from affiliate_accounts)
          + (select count(*) from affiliate_signup_matches) + (select count(*) from customer_affiliates))::text = pg_temp.tx('rows_s3'),
  'S3 a staff login is refused and nothing is written');

-- ═════ S4 A login with a rejected claim ═════
select pg_temp.onboard('lRej', 'Rej', 'Testrejected', '+61491579455');
select pg_temp.check(pg_temp.ans('lRej')->>'status' = 'rejected' and pg_temp.linked_to('lRej') is null
    and pg_temp.on_phone('+61491579455') = 0 and pg_temp.entry('lRej') is null,
  'S4 a login with a rejected claim stays rejected, even on a phone and email no one has; nothing is created');

-- ═════ S5 A login that is not confirmed ═════
select pg_temp.onboard('lUnc', 'Una', 'Testunconfirmed', '+61491579212');
select pg_temp.check(pg_temp.ans('lUnc')->>'error' like '%verify your email%' and pg_temp.linked_to('lUnc') is null,
  'S5 a login Supabase has not confirmed is refused (it could not sign in anyway)');

-- ═════ D A second press ═════
insert into tx values ('rows_d', (select (select count(*) from customers) + (select count(*) from affiliate_accounts)
  + (select count(*) from affiliate_signup_matches) + (select count(*) from customer_affiliates))::text);
select pg_temp.onboard('lSolo', 'Totally', 'Different', '+61491570737');
select pg_temp.onboard('lDan', 'Dan', 'Testshare', '+61491572983');
select pg_temp.check((pg_temp.ans('lSolo')->>'already')::boolean and (pg_temp.ans('lSolo')->>'customer_id')::uuid = pg_temp.fx('cSolo')
    and (pg_temp.ans('lDan')->>'already')::boolean and (pg_temp.ans('lDan')->>'customer_id')::uuid = pg_temp.fx('cDan')
    and (select (select count(*) from customers) + (select count(*) from affiliate_accounts)
          + (select count(*) from affiliate_signup_matches) + (select count(*) from customer_affiliates))::text = pg_temp.tx('rows_d')
    and pg_temp.claimed_rows('lSolo') = 1 and pg_temp.claimed_rows('lDan') = 1,
  'D a second press answers "already" with the same customer; no second record, account, entry or audit row');

-- ═════ C Stuck logins with pending claims ═════
select pg_temp.onboard('lStk', null, null, null);
select pg_temp.check(pg_temp.ans('lStk')->>'status' = 'active' and pg_temp.linked_to('lStk') = pg_temp.fx('cStk')
    and (select status = 'resolved' and resolution_note like '437:%' and resolved_at is not null
           from affiliate_account_claims where auth_user_id = pg_temp.fx('lStk'))
    and not exists (select 1 from affiliate_account_claims where auth_user_id = pg_temp.fx('lStk') and status = 'pending')
    and (pg_temp.claimed('lStk')->>'claims_closed')::int = 1,
  'C a stuck login with a pending claim signs in: the details it signed up with join the customer with its phone, and the claim is closed: ' || pg_temp.ans('lStk')::text);
select pg_temp.onboard('lStk2', '', '', '');
select pg_temp.check(pg_temp.ans('lStk2')->>'status' = 'active' and (pg_temp.ans('lStk2')->>'new_customer')::boolean
    and (pg_temp.entry('lStk2')).reason = 'shared_phone'
    and (pg_temp.entry('lStk2')).candidate_ids @> array[pg_temp.fx('cSid1'), pg_temp.fx('cSid2'), pg_temp.fx('cSidOld')]
    and (select status from affiliate_account_claims where auth_user_id = pg_temp.fx('lStk2')) = 'resolved',
  'C a stuck login on a shared phone gets a fresh record, listed with the sharers and whom its claim suggested; the claim is closed');

-- ═════ E The email ═════
select pg_temp.onboard('lOld', 'Olu', 'Testold', '+61491578148');
select pg_temp.check((pg_temp.ans('lOld')->>'email_verified')::boolean
    and (select email_verified_at from affiliate_accounts where auth_user_id = pg_temp.fx('lOld'))
        = (select email_confirmed_at from auth.users where id = pg_temp.fx('lOld')),
  'E a login Supabase confirmed by its own email link (before 437) counts as verified, from the day it was confirmed');
select pg_temp.as_user('lLink', 'magiclink', '2 minutes');
select pg_temp.check((public.complete_affiliate_onboarding('Lin', 'Testlink', '+61491578888', true)->>'email_verified')::boolean,
  'E a sign-up whose session came from an emailed link is verified at once');
select pg_temp.check(public.affiliate_email_verification_needed(pg_temp.mail('lSolo'))
    and public.affiliate_email_verification_needed(upper(' ' || pg_temp.mail('lSolo') || ' '))
    and not public.affiliate_email_verification_needed(pg_temp.mail('lOld'))
    and not public.affiliate_email_verification_needed('t437-nobody@example.com')
    and not public.affiliate_email_verification_needed(pg_temp.mail('lRej')),
  'E affiliate_email_verification_needed: yes for an affiliate not verified; no for one verified, no login, or no affiliate account');
select pg_temp.as_user('lSolo');
select pg_temp.check(public.confirm_affiliate_email() = '{"reason": "not_from_email_link", "verified": false}'::jsonb,
  'E a password session does not verify the email');
select pg_temp.as_user('lSolo', 'password', '1 minute');
select pg_temp.check(not (public.confirm_affiliate_email()->>'verified')::boolean, 'E nor does an amr of "password"');
select pg_temp.as_user('lSolo', 'magiclink', '45 minutes');
select pg_temp.check(public.confirm_affiliate_email()->>'reason' = 'not_from_email_link',
  'E a sign-in link opened more than 30 minutes ago does not verify it');
select pg_temp.as_user('lSolo', 'magiclink', '3 minutes');
insert into tx values ('confirm1', public.confirm_affiliate_email()::text);
select pg_temp.check((pg_temp.tx('confirm1')::jsonb->>'verified')::boolean and not (pg_temp.tx('confirm1')::jsonb->>'already')::boolean
    and (select email_verified_at is not null from affiliate_accounts where auth_user_id = pg_temp.fx('lSolo'))
    and (select count(*) from audit_logs l join affiliate_accounts a on a.id = l.record_id
          where l.action = 'affiliate_email_verified' and a.auth_user_id = pg_temp.fx('lSolo')) = 1
    and not public.affiliate_email_verification_needed(pg_temp.mail('lSolo')),
  'E the Account page''s sign-in link, opened 3 minutes ago, verifies the email, with one audit row');
select pg_temp.check((public.confirm_affiliate_email()->>'already')::boolean
    and (select count(*) from audit_logs l join affiliate_accounts a on a.id = l.record_id
          where l.action = 'affiliate_email_verified' and a.auth_user_id = pg_temp.fx('lSolo')) = 1,
  'E a second open answers "already" and writes nothing');
select pg_temp.as_user('lNeo', 'recovery', '5 minutes');
select pg_temp.check((public.confirm_affiliate_email()->>'verified')::boolean, 'E a password-reset link proves the mailbox too');
select pg_temp.as_user('lRej', 'magiclink', '1 minute');
select pg_temp.check(public.confirm_affiliate_email() = '{"reason": "not_affiliate", "verified": false}'::jsonb,
  'E a login with no affiliate account is told so, and nothing is written');

-- ═════ L The list and the link ═════
-- A referral the fresh record (Dan) made meanwhile.
do $$ declare c uuid; begin
  insert into customers(full_name, phone, referred_by) values ('Ref Testfriend', '+61491579212', pg_temp.fx('cDan')) returning id into c;
  insert into fx values ('cFriend', c);
end $$;
insert into tx values ('dan_code', (select ca.referral_code from customer_affiliates ca join affiliate_accounts a on a.affiliate_id = ca.id
                                     where a.auth_user_id = pg_temp.fx('lDan')));
select pg_temp.as_user('s');
select pg_temp.check(pg_temp.err('select public.affiliate_signup_matches_open()') like '42501%'
    and pg_temp.err(format('select public.link_affiliate_signup(%L, %L, null, gen_random_uuid())', (pg_temp.entry('lDan')).id, pg_temp.fx('cCal'))) like '42501%'
    and pg_temp.err(format('select public.keep_affiliate_signup_separate(%L, %L)', (pg_temp.entry('lDan')).id, 'T437')) like '42501%',
  'L Staff are refused the list, the link and Keep separate (42501)');
select pg_temp.as_user('a');
select pg_temp.check(pg_temp.err('select public.affiliate_signup_matches_open()') like '42501%'
    and pg_temp.err(format('select public.link_affiliate_signup(%L, %L, null, gen_random_uuid())', (pg_temp.entry('lDan')).id, pg_temp.fx('cCal'))) like '42501%',
  'L an Admin is refused too (Owner or Manager only)');
select pg_temp.as_user('lSolo');
select pg_temp.check(pg_temp.err('select public.affiliate_signup_matches_open()') like '42501%',
  'L an affiliate login is refused the list');
select pg_temp.as_user('m');
insert into tx values ('list_m', public.affiliate_signup_matches_open()::text);
select pg_temp.check(exists (select 1 from jsonb_array_elements(pg_temp.tx('list_m')::jsonb) e
                              where (e->>'match_id')::uuid = (pg_temp.entry('lDan')).id and e->>'reason' = 'shared_phone'
                                and (e->>'customer_id')::uuid = pg_temp.fx('cDan') and e->>'login_email' = pg_temp.mail('lDan')
                                and (e->>'referrals')::int = 1 and e->>'referral_code' = pg_temp.tx('dan_code')),
  'L a Manager sees the entry: the fresh record, its login email, its code and the referral made meanwhile');
select pg_temp.check((select bool_and(case (c->>'customer_id')::uuid
                                        when pg_temp.fx('cBea') then c->'matched_by' ? 'phone' and (c->>'has_login')::boolean
                                                                     and c->>'problem' = 'This customer already has an affiliate login.'
                                        when pg_temp.fx('cCal') then c->'matched_by' = '["phone"]'::jsonb and not (c->>'has_login')::boolean
                                                                     and c->>'problem' is null
                                        else false end) and count(*) = 2
                        from jsonb_array_elements(pg_temp.tx('list_m')::jsonb) e, jsonb_array_elements(e->'candidates') c
                       where (e->>'match_id')::uuid = (pg_temp.entry('lDan')).id),
  'L each candidate says how it matches and why it cannot be linked (Bea now has a login; Cal can be linked)');
select pg_temp.check((select bool_or(c->'matched_by' ? 'name') from jsonb_array_elements(pg_temp.tx('list_m')::jsonb) e,
                        jsonb_array_elements(e->'candidates') c where (e->>'match_id')::uuid = (pg_temp.entry('lNam')).id)
    and (select bool_or((c->>'protected')::boolean) from jsonb_array_elements(pg_temp.tx('list_m')::jsonb) e,
                        jsonb_array_elements(e->'candidates') c where (e->>'match_id')::uuid = (pg_temp.entry('lPat')).id)
    and (select bool_or(c->'matched_by' ? 'email') from jsonb_array_elements(pg_temp.tx('list_m')::jsonb) e,
                        jsonb_array_elements(e->'candidates') c where (e->>'match_id')::uuid = (pg_temp.entry('lMia')).id)
    and not exists (select 1 from jsonb_array_elements(pg_temp.tx('list_m')::jsonb) e where (e->>'customer_id')::uuid = pg_temp.fx('cBea'))
    and (select e->>'kind' = 'may_be_someone_else' and e->'candidates' = '[]'::jsonb
           from jsonb_array_elements(pg_temp.tx('list_m')::jsonb) e where (e->>'customer_id')::uuid = pg_temp.fx('cSolo')),
  'L the name, email and protected flags show; a customer joined under a name of the same words (Bea) is not listed, and one joined under another name (Ada) only as "may be someone else", with no one to link');
-- Refusals.
select pg_temp.check(public.link_affiliate_signup((pg_temp.entry('lDan')).id, pg_temp.fx('cBea'), null, gen_random_uuid())->>'message'
      = 'This customer already has an affiliate login.',
  'L a customer with a portal login is refused');
select pg_temp.check(public.link_affiliate_signup((pg_temp.entry('lDan')).id, pg_temp.fx('cStk'), null, gen_random_uuid())->>'message'
      = 'Link only to a customer listed for this sign-up.',
  'L a customer not listed for the sign-up is refused');
select pg_temp.check(pg_temp.err(format('select public.link_affiliate_signup(%L, %L, null, null)', (pg_temp.entry('lDan')).id, pg_temp.fx('cCal'))) like '%request id%',
  'L a link needs a request id');
-- The link.
insert into fx values ('req1', gen_random_uuid());
insert into tx values ('link1', public.link_affiliate_signup((pg_temp.entry('lDan')).id, pg_temp.fx('cCal'), 'Same person, checked by phone', pg_temp.fx('req1'))::text);
select pg_temp.check((pg_temp.tx('link1')::jsonb->>'ok')::boolean and (pg_temp.tx('link1')::jsonb->>'customer_id')::uuid = pg_temp.fx('cCal'),
  'L a Manager links the sign-up to Cal: ' || pg_temp.tx('link1'));
select pg_temp.check(pg_temp.linked_to('lDan') = pg_temp.fx('cCal')
    and (select referral_code from customer_affiliates where customer_id = pg_temp.fx('cCal')) = pg_temp.tx('dan_code')
    and (select a.affiliate_id = ca.id from affiliate_accounts a join customer_affiliates ca on ca.customer_id = pg_temp.fx('cCal')
          where a.auth_user_id = pg_temp.fx('lDan'))
    and (select referred_by from customers where id = pg_temp.fx('cFriend')) = pg_temp.fx('cCal')
    and (select deleted_at is not null from customers where id = pg_temp.fx('cDan')),
  'L the login, the affiliate record with its code, and the referral made meanwhile now belong to Cal; the fresh record is retired');
select pg_temp.check((select email = pg_temp.mail('lDan') and phone = '+61491572983' from customers where id = pg_temp.fx('cCal'))
    and pg_temp.tx('link1')::jsonb->>'email_copied' = pg_temp.mail('lDan')
    and not (pg_temp.tx('link1')::jsonb->>'phone_changed')::boolean
    and exists (select 1 from audit_logs where action = 'customer_updated' and record_id = pg_temp.fx('cCal')
                  and new_data->>'email' = pg_temp.mail('lDan') and old_data ? 'email' and not (new_data ? 'phone')),
  'L P Cal had no email: the one Dan signed up with is copied onto him, as the Customers page changes it (its audit row); the box unticked, his phone is not touched');
select pg_temp.check((pg_temp.entry('lDan')).status = 'linked' and (pg_temp.entry('lDan')).linked_customer_id = pg_temp.fx('cCal')
    and (pg_temp.entry('lDan')).decided_by = pg_temp.fx('m') and (pg_temp.entry('lDan')).fresh_customer_id = pg_temp.fx('cDan')
    and exists (select 1 from audit_logs where action = 'affiliate_signup_linked' and record_id = (pg_temp.entry('lDan')).id
                  and changed_by = pg_temp.fx('m') and actor_role = 'manager' and module = 'affiliate'
                  and reason = 'Same person, checked by phone' and (new_data->>'customer_id')::uuid = pg_temp.fx('cCal'))
    and exists (select 1 from audit_logs where action = 'customers_merged' and record_id = pg_temp.fx('cCal')
                  and (new_data->>'merged_from')::uuid = pg_temp.fx('cDan') and new_data->>'request_id' = pg_temp.fx('req1')::text),
  'L the entry is linked, still naming the fresh record; the link and the merge each have an audit row');
select pg_temp.check(not exists (select 1 from jsonb_array_elements(public.affiliate_signup_matches_open()) e
                                  where (e->>'match_id')::uuid = (pg_temp.entry('lDan')).id),
  'L the linked sign-up leaves the list');
select pg_temp.check((public.link_affiliate_signup((pg_temp.entry('lDan')).id, pg_temp.fx('cCal'), null, pg_temp.fx('req1'))->>'replayed')::boolean
    and public.link_affiliate_signup((pg_temp.entry('lDan')).id, pg_temp.fx('cCal'), null, gen_random_uuid())->>'message' like 'This sign-up was linked%',
  'L a retry with the same request id is replayed; another link is refused');
select pg_temp.onboard('lDan', 'Dan', 'Testshare', '+61491572983');
select pg_temp.check((pg_temp.ans('lDan')->>'already')::boolean and (pg_temp.ans('lDan')->>'customer_id')::uuid = pg_temp.fx('cCal'),
  'L signing in again, the affiliate lands on Cal''s record');
-- Keep separate.
select pg_temp.as_user('o');
select pg_temp.check(pg_temp.err(format('select public.keep_affiliate_signup_separate(%L, %L)', (pg_temp.entry('lNam')).id, '  ')) like '%Say why%',
  'L Keep separate needs a reason');
insert into tx values ('keep1', public.keep_affiliate_signup_separate((pg_temp.entry('lNam')).id, 'A different Mei Ling')::text);
select pg_temp.check((pg_temp.tx('keep1')::jsonb->>'ok')::boolean
    and (pg_temp.entry('lNam')).status = 'kept_separate' and (pg_temp.entry('lNam')).decided_by = pg_temp.fx('o')
    and pg_temp.linked_to('lNam') = (pg_temp.entry('lNam')).fresh_customer_id
    and exists (select 1 from audit_logs where action = 'affiliate_signup_kept_separate' and record_id = (pg_temp.entry('lNam')).id
                  and actor_role = 'owner' and reason = 'A different Mei Ling')
    and not exists (select 1 from jsonb_array_elements(public.affiliate_signup_matches_open()) e
                     where (e->>'match_id')::uuid = (pg_temp.entry('lNam')).id),
  'L an Owner keeps a sign-up separate, with a reason: it leaves the list, the affiliate stays on their record');
select pg_temp.check(public.keep_affiliate_signup_separate((pg_temp.entry('lNam')).id, 'again')->>'message' like 'This sign-up was kept%'
    and public.link_affiliate_signup((pg_temp.entry('lNam')).id, pg_temp.fx('cName'), null, gen_random_uuid())->>'message' like 'This sign-up was kept%',
  'L a sign-up kept separate cannot be linked or kept again');
-- ═════ W A customer with an affiliate record of their own ═════
-- Pat kept his record (T437PAT) after an Owner unlinked his old login; the
-- fresh record lPat signed up on has done nothing yet. Wes's fresh record
-- has a referral. Rem's record was removed.
do $$ declare c uuid; begin
  insert into customers(full_name, phone, referred_by) values ('Wes Testfriend', '+61491572549', pg_temp.fx('cWesFresh')) returning id into c;
  insert into fx values ('cWesFriend', c);
end $$;
insert into tx values ('pat_fresh_code', (select ca.referral_code from customer_affiliates ca join affiliate_accounts a on a.affiliate_id = ca.id
                                           where a.auth_user_id = pg_temp.fx('lPat')));
insert into tx values ('pat_fresh_aff', (select affiliate_id::text from affiliate_accounts where auth_user_id = pg_temp.fx('lPat')));
insert into tx values ('list_o', public.affiliate_signup_matches_open()::text);
select pg_temp.check((select c->>'problem' is null and c->>'own_referral_code' = 'T437PAT' and (c->>'protected')::boolean
                        from jsonb_array_elements(pg_temp.tx('list_o')::jsonb) e, jsonb_array_elements(e->'candidates') c
                       where (e->>'match_id')::uuid = (pg_temp.entry('lPat')).id and (c->>'customer_id')::uuid = pg_temp.fx('cPat')),
  'W the list shows Pat as linkable, with his own referral code and the Protected flag');
select pg_temp.check((select c->>'problem' like 'This customer already has an affiliate record of their own, and the new record already has referrals.%'
                        from jsonb_array_elements(pg_temp.tx('list_o')::jsonb) e, jsonb_array_elements(e->'candidates') c
                       where (e->>'match_id')::uuid = (pg_temp.entry('lWes2')).id and (c->>'customer_id')::uuid = pg_temp.fx('cWes'))
    and (select c->>'problem' like 'This customer''s affiliate record was removed%'
           from jsonb_array_elements(pg_temp.tx('list_o')::jsonb) e, jsonb_array_elements(e->'candidates') c
          where (e->>'match_id')::uuid = (pg_temp.entry('lRem')).id and (c->>'customer_id')::uuid = pg_temp.fx('cRem')),
  'W the list says why Wes (the new record has a referral) and Rem (record removed) cannot be linked');
-- K (AFF-SIGNUP-14): what the Link box needs to warn that links shared with
-- the new code will stop crediting anyone: the new record's code and the
-- customer's own.
select pg_temp.check(pg_temp.listed('list_o', 'lPat')->>'referral_code' = pg_temp.tx('pat_fresh_code')
    and pg_temp.cand('list_o', 'lPat', 'cPat')->>'own_referral_code' = 'T437PAT'
    and (pg_temp.cand('list_o', 'lPat', 'cPat')->>'retires_new_code')::boolean
    and pg_temp.listed('list_o', 'lRae')->>'referral_code' is not null
    and pg_temp.cand('list_o', 'lRae', 'cRae')->>'own_referral_code' is null
    and not (pg_temp.cand('list_o', 'lRae', 'cRae')->>'retires_new_code')::boolean,
  'K the list gives the new record''s code and each customer''s own: linked to Pat, the new code is retired; to Rae (none), it moves with the login');
select pg_temp.check(public.link_affiliate_signup((pg_temp.entry('lWes2')).id, pg_temp.fx('cWes'), null, gen_random_uuid())->>'message'
      like 'This customer already has an affiliate record of their own, and the new record already has referrals. Which referral code%'
    and pg_temp.linked_to('lWes2') = pg_temp.fx('cWesFresh') and (pg_temp.entry('lWes2')).status = 'open'
    and (select count(*) from customer_affiliates where customer_id in (pg_temp.fx('cWes'), pg_temp.fx('cWesFresh')) and deleted_at is null) = 2,
  'W a fresh record with a referral is not linked to a customer with an affiliate record of their own; nothing changes');
select pg_temp.check(public.link_affiliate_signup((pg_temp.entry('lRem')).id, pg_temp.fx('cRem'), null, gen_random_uuid())->>'message'
      like 'This customer''s affiliate record was removed%',
  'W a customer whose affiliate record was removed is refused');
insert into fx values ('req_pat', gen_random_uuid());
insert into tx values ('link_pat', public.link_affiliate_signup((pg_temp.entry('lPat')).id, pg_temp.fx('cPat'), 'Same person, Owner checked', pg_temp.fx('req_pat'))::text);
select pg_temp.check((pg_temp.tx('link_pat')::jsonb->>'ok')::boolean and (pg_temp.tx('link_pat')::jsonb->>'kept_own_affiliate')::boolean,
  'W an Owner links the sign-up to Pat, who has an affiliate record of his own: ' || pg_temp.tx('link_pat'));
select pg_temp.check(pg_temp.linked_to('lPat') = pg_temp.fx('cPat')
    and (select ca.customer_id = pg_temp.fx('cPat') and ca.referral_code = 'T437PAT'
           from affiliate_accounts a join customer_affiliates ca on ca.id = a.affiliate_id where a.auth_user_id = pg_temp.fx('lPat'))
    and not exists (select 1 from customer_affiliates where id = pg_temp.tx('pat_fresh_aff')::uuid)
    and not exists (select 1 from customer_affiliates where referral_code = pg_temp.tx('pat_fresh_code'))
    and (select count(*) from customer_affiliates where customer_id = pg_temp.fx('cPat')) = 1
    and (select deleted_at is not null from customers where id = (pg_temp.entry('lPat')).fresh_customer_id),
  'W the login moves onto Pat''s own affiliate record and code; the fresh record''s unused one is gone; the fresh record is retired');
select pg_temp.check(exists (select 1 from audit_logs where action = 'affiliate_signup_linked' and record_id = (pg_temp.entry('lPat')).id
                               and actor_role = 'owner' and new_data->>'referral_code_kept' = 'T437PAT'
                               and new_data->>'referral_code_retired' = pg_temp.tx('pat_fresh_code')
                               and new_data->>'affiliate_id_before' = pg_temp.tx('pat_fresh_aff')
                               and (new_data->>'affiliate_id')::uuid = (select id from customer_affiliates where customer_id = pg_temp.fx('cPat')))
    and exists (select 1 from audit_logs where action = 'customers_merged' and record_id = pg_temp.fx('cPat')
                  and new_data->>'request_id' = pg_temp.fx('req_pat')::text),
  'W the link''s audit row names the affiliate record before and after, the code kept and the code retired; the merge has its own');
select pg_temp.onboard('lPat', 'Pat', 'Testprot', '+61491575789');
select pg_temp.check((pg_temp.ans('lPat')->>'already')::boolean and (pg_temp.ans('lPat')->>'customer_id')::uuid = pg_temp.fx('cPat')
    and pg_temp.ans('lPat')->>'referral_code' = 'T437PAT',
  'W signing in again, the affiliate lands on Pat''s record with his code');
select pg_temp.check(public.public_affiliate_referral_info(pg_temp.tx('pat_fresh_code')) = '{"valid": false}'::jsonb
    and (public.public_affiliate_referral_info('T437PAT')->>'valid')::boolean,
  'K the retired code finds no one now (no alias; codes are looked up as before), and Pat''s own still does');
select pg_temp.as_user('o');
-- An Owner may link a protected customer (the protection stops sign-up and staff, not Owners and Managers).
insert into tx values ('link_rae', public.link_affiliate_signup((pg_temp.entry('lRae')).id, pg_temp.fx('cRae'), null, gen_random_uuid())::text);
select pg_temp.check((pg_temp.tx('link_rae')::jsonb->>'ok')::boolean and pg_temp.linked_to('lRae') = pg_temp.fx('cRae'),
  'L an Owner links a sign-up to a customer protected by a rejection (379)');

-- An Owner unlinks Mia's login from her fresh record (378). Her next sign-in
-- does not join that record by itself (it is protected now): a fresh record
-- again, listed once, the stale entry gone.
select pg_temp.as_user('o');
insert into tx values ('mia_fresh', pg_temp.linked_to('lMia')::text);
insert into tx values ('unlink_mia', coalesce(pg_temp.err(format('select public.unlink_affiliate_account(%L, %L)',
  pg_temp.linked_to('lMia'), 'T437 wrong record')), 'ok'));
select pg_temp.onboard('lMia', 'Mia', 'Testmail', '+61491574118');
select pg_temp.check(pg_temp.tx('unlink_mia') = 'ok' and pg_temp.ans('lMia')->>'status' = 'active'
    and (select count(*) from affiliate_signup_matches where auth_user_id = pg_temp.fx('lMia') and status = 'open') = 1
    and (pg_temp.entry('lMia')).fresh_customer_id = pg_temp.linked_to('lMia')
    and pg_temp.linked_to('lMia') <> pg_temp.tx('mia_fresh')::uuid
    and (pg_temp.entry('lMia')).reason = 'protected_customer'
    and pg_temp.tx('mia_fresh')::uuid = any ((pg_temp.entry('lMia')).candidate_ids),
  'L a login an Owner unlinked from its fresh record gets a fresh record again at its next sign-in, listed once: ' || pg_temp.ans('lMia')::text);

-- ═════ V A verified email survives an unlink ═════
-- Neo verified his email from a password-reset link (E above). An Owner
-- unlinks his login from its record; his next sign-in makes a new account,
-- which starts verified.
select pg_temp.check((select raw_app_meta_data ? 'affiliate_email_verified_at' and not (raw_app_meta_data ? 'affiliate_email_unverified')
                        from auth.users where id = pg_temp.fx('lNeo')),
  'V verifying the email is kept on the login too (app_metadata), and its "unverified" mark goes');
select pg_temp.as_user('o');
insert into tx values ('unlink_neo', coalesce(pg_temp.err(format('select public.unlink_affiliate_account(%L, %L)',
  pg_temp.linked_to('lNeo'), 'T437 wrong record')), 'ok'));
select pg_temp.onboard('lNeo', 'Neo', 'Testnew', '+61491573770');
select pg_temp.check(pg_temp.tx('unlink_neo') = 'ok' and pg_temp.ans('lNeo')->>'status' = 'active'
    and not (pg_temp.ans('lNeo')->>'already')::boolean and (pg_temp.ans('lNeo')->>'email_verified')::boolean
    and (select email_verified_at from affiliate_accounts where auth_user_id = pg_temp.fx('lNeo'))
        = (select (raw_app_meta_data->>'affiliate_email_verified_at')::timestamptz from auth.users where id = pg_temp.fx('lNeo'))
    and not public.affiliate_email_verification_needed(pg_temp.mail('lNeo')),
  'V after an Owner unlinks the login, its next sign-in makes an account that is verified still, from the same date: ' || pg_temp.ans('lNeo')::text);
-- A login confirmed by the sign-up whose first session came from an emailed
-- link (lLink, E above) is marked on the login too.
select pg_temp.check((select raw_app_meta_data ? 'affiliate_email_verified_at' and not (raw_app_meta_data ? 'affiliate_email_unverified')
                        from auth.users where id = pg_temp.fx('lLink')),
  'V a sign-up verified by its own emailed-link session is kept on the login too');

-- ═════ T Twin records (AFF-SIGNUP-13) ═════
-- Han signed up (S2) with the very same name and phone as Han Testhas, whose
-- record already has a login (lHasOld). Tia's record has a login too; she
-- signs up with her names the other way round.
do $$ declare c uuid; a uuid; begin
  insert into customers(full_name, phone) values ('Tia Lim Testtwin', '+61491578404') returning id into c; insert into fx values ('cTia', c);
  insert into customer_affiliates(customer_id, status, activated_at, referral_code) values (c, 'active', now(), 'T437TIA') returning id into a;
  insert into affiliate_accounts(auth_user_id, customer_id, affiliate_id, status) values (pg_temp.fx('lTiaOld'), c, a, 'claimed');
end $$;
select pg_temp.onboard('lTia', 'Lim Tia', 'Testtwin', '+61491578404');
select pg_temp.check(pg_temp.ans('lTia')->>'status' = 'active' and (pg_temp.ans('lTia')->>'new_customer')::boolean
    and not (pg_temp.ans('lTia')->>'already')::boolean and pg_temp.linked_to('lTiaOld') = pg_temp.fx('cTia')
    and (pg_temp.entry('lTia')).reason = 'customer_has_login'
    and not (pg_temp.ans('lTia')::text ~* 'twin|Testtwin'),
  'T a sign-up with the phone, and a name of the same words, of a customer who has a login still goes straight in, on a fresh record, listed; the person is told nothing: ' || pg_temp.ans('lTia')::text);
select pg_temp.as_user('m');
insert into tx values ('list_t', public.affiliate_signup_matches_open()::text);
select pg_temp.check((pg_temp.listed('list_t', 'lHas')->>'twin')::boolean
    and (pg_temp.listed('list_t', 'lHas')->>'twin_customer_id')::uuid = pg_temp.fx('cHas')
    and (pg_temp.cand('list_t', 'lHas', 'cHas')->>'twin')::boolean
    and (pg_temp.cand('list_t', 'lHas', 'cHas')->>'has_login')::boolean,
  'T the list flags Han''s entry as the twin of Han Testhas (the very same name and phone; he has a login)');
-- Both rows the Affiliates list then shows are named Han Testhas: the page
-- names the one to unlink by its code (the twin's own) and the one not to
-- (the new record's).
select pg_temp.check(pg_temp.cand('list_t', 'lHas', 'cHas')->>'own_referral_code' = 'T437HAS'
    and pg_temp.listed('list_t', 'lHas')->>'referral_code' = (select ca.referral_code from customer_affiliates ca
                                                               join affiliate_accounts a on a.affiliate_id = ca.id
                                                              where a.auth_user_id = pg_temp.fx('lHas'))
    and pg_temp.listed('list_t', 'lHas')->>'referral_code' <> 'T437HAS',
  'T the list gives the twin''s own code (T437HAS) and the new record''s, so the page can name the row to unlink');
select pg_temp.check((pg_temp.listed('list_t', 'lTia')->>'twin')::boolean
    and (pg_temp.listed('list_t', 'lTia')->>'twin_customer_id')::uuid = pg_temp.fx('cTia')
    and (pg_temp.cand('list_t', 'lTia', 'cTia')->>'twin')::boolean,
  'T and Tia''s: the same words in another order are the same name');
select pg_temp.check(not (pg_temp.listed('list_t', 'lDuo')->>'twin')::boolean
    and pg_temp.listed('list_t', 'lDuo')->>'twin_customer_id' is null
    and not (pg_temp.cand('list_t', 'lDuo', 'cDuo1')->>'twin')::boolean
    and not (pg_temp.listed('list_t', 'lStk2')->>'twin')::boolean,
  'T two customers with the very same name and phone but no login are not flagged (they can be linked)');
select pg_temp.check(not (pg_temp.listed('list_m', 'lDan')->>'twin')::boolean
    and (pg_temp.cand('list_m', 'lDan', 'cBea')->>'has_login')::boolean
    and not (pg_temp.cand('list_m', 'lDan', 'cBea')->>'twin')::boolean,
  'T a customer with the phone and a login but another name (Bea, for Dan) is not a twin');
-- The fix: an Owner unlinks the wrong login from Han Testhas, then links the
-- sign-up to him.
select pg_temp.as_user('o');
insert into tx values ('unlink_has', coalesce(pg_temp.err(format('select public.unlink_affiliate_account(%L, %L)',
  pg_temp.fx('cHas'), 'T437 the login is someone else''s')), 'ok'));
insert into tx values ('list_t2', public.affiliate_signup_matches_open()::text);
select pg_temp.check(pg_temp.tx('unlink_has') = 'ok' and not (pg_temp.listed('list_t2', 'lHas')->>'twin')::boolean
    and pg_temp.cand('list_t2', 'lHas', 'cHas')->>'problem' is null
    and (pg_temp.cand('list_t2', 'lHas', 'cHas')->>'protected')::boolean,
  'T an Owner unlinks the wrong login from Han Testhas: the flag goes, and he can be linked (protected now)');
insert into tx values ('link_has', public.link_affiliate_signup((pg_temp.entry('lHas')).id, pg_temp.fx('cHas'), 'T437 the same person',
  gen_random_uuid(), false)::text);
select pg_temp.check((pg_temp.tx('link_has')::jsonb->>'ok')::boolean and pg_temp.linked_to('lHas') = pg_temp.fx('cHas')
    and (select count(*) from customers where deleted_at is null and full_name = 'Han Testhas' and phone = '+61491576801') = 1,
  'T then the sign-up is linked to him: one Han Testhas on the phone again: ' || pg_temp.tx('link_has'));

-- ═════ P The phone and email on Link (AFF-SIGNUP-12) ═════
do $$ declare c uuid; sfx text := pg_temp.tx('sfx'); begin
  -- Gra: an old phone and no email; she signs up with her new phone.
  insert into customers(full_name, phone) values ('Gra Testoldphone', '+61491570401') returning id into c; insert into fx values ('cGra', c);
  -- Hal signs up on a phone two others hold (his fresh record makes 3).
  insert into customers(full_name, phone) values ('Hal Testfull', '+61491570403') returning id into c; insert into fx values ('cHal', c);
  insert into customers(full_name, phone) values ('Ivy Testfull', '+61491570404'), ('Jon Testfull', '+61491570404');
  -- Kim: no email; 3 others come to hold the phone she signs up with.
  insert into customers(full_name, phone) values ('Kim Testrefuse', '+61491570405') returning id into c; insert into fx values ('cKim', c);
  -- Leo has an email of his own.
  insert into customers(full_name, phone, email) values ('Leo Testhasmail', '+61491570408', 't437-leo-own-' || sfx || '@example.com')
    returning id into c; insert into fx values ('cLeo', c);
  -- Moe has none, but another customer has the inbox Moe signs up with
  -- (written in capitals: the same inbox).
  insert into customers(full_name, phone) values ('Moe Testinuse', '+61491578401') returning id into c; insert into fx values ('cMoe', c);
  insert into customers(full_name, phone, email) values ('Nia Testother', '+61491578403', upper(pg_temp.mail('lMoe')))
    returning id into c; insert into fx values ('cMoeX', c);
end $$;
select pg_temp.onboard('lGra', 'Gra', 'Testoldphone', '+61491570402');
select pg_temp.onboard('lHal', 'Hal', 'Testfull', '+61491570404');
select pg_temp.onboard('lKim', 'Kim', 'Testrefuse', '+61491570406');
select pg_temp.onboard('lLeo', 'Leo', 'Testhasmail', '+61491570409');
select pg_temp.onboard('lMoe', 'Moe', 'Testinuse', '+61491578402');
select pg_temp.check((pg_temp.entry('lGra')).reason = 'name_match' and pg_temp.fx('cGra') = any ((pg_temp.entry('lGra')).candidate_ids)
    and (pg_temp.entry('lHal')).reason = 'shared_phone' and pg_temp.fx('cHal') = any ((pg_temp.entry('lHal')).candidate_ids)
    and pg_temp.on_phone('+61491570404') = 3
    and (pg_temp.entry('lKim')).reason = 'name_match' and (pg_temp.entry('lLeo')).reason = 'name_match'
    and (pg_temp.entry('lMoe')).reason = 'email_match'
    and (pg_temp.entry('lMoe')).candidate_ids @> array[pg_temp.fx('cMoe'), pg_temp.fx('cMoeX')],
  'P setup: each signs up on a fresh record, listed with the customer they are');
select pg_temp.as_user('m');
insert into tx values ('list_p', public.affiliate_signup_matches_open()::text);
select pg_temp.check(pg_temp.listed('list_p', 'lGra')->>'entered_phone' = '+61491570402'
    and pg_temp.cand('list_p', 'lGra', 'cGra')->>'phone' = '+61491570401'
    and pg_temp.listed('list_p', 'lGra')->>'login_email' = pg_temp.mail('lGra')
    and pg_temp.cand('list_p', 'lGra', 'cGra')->>'email_on_link' = 'copy'
    and pg_temp.cand('list_p', 'lLeo', 'cLeo')->>'email_on_link' = 'keep_own'
    and pg_temp.cand('list_p', 'lMoe', 'cMoe')->>'email_on_link' = 'in_use'
    and pg_temp.cand('list_p', 'lMoe', 'cMoeX')->>'email_on_link' = 'keep_own',
  'P the list gives both phones, and what Link would do with the email (copy it, keep their own, or leave it: in use)');

-- Ticked: Gra's phone becomes the one she signed up with; her email is copied.
select pg_temp.as_user('o');
insert into tx values ('gra_hist', (select count(*) from customer_phone_history where customer_id = pg_temp.fx('cGra'))::text);
insert into fx values ('req_gra', gen_random_uuid());
insert into tx values ('link_gra', public.link_affiliate_signup((pg_temp.entry('lGra')).id, pg_temp.fx('cGra'), 'Same person, new phone',
  pg_temp.fx('req_gra'), true)::text);
select pg_temp.check((pg_temp.tx('link_gra')::jsonb->>'ok')::boolean and (pg_temp.tx('link_gra')::jsonb->>'phone_changed')::boolean
    and pg_temp.tx('link_gra')::jsonb->>'phone' = '+61491570402'
    and pg_temp.tx('link_gra')::jsonb->>'email_copied' = pg_temp.mail('lGra')
    and (select phone = '+61491570402' and email = pg_temp.mail('lGra') from customers where id = pg_temp.fx('cGra'))
    and pg_temp.on_phone('+61491570402') = 1 and pg_temp.on_phone('+61491570401') = 0
    and pg_temp.linked_to('lGra') = pg_temp.fx('cGra'),
  'P ticked: Gra''s phone becomes the one she signed up with, and the email she signed up with is copied onto her: ' || pg_temp.tx('link_gra'));
select pg_temp.check((select count(*) from customer_phone_history where customer_id = pg_temp.fx('cGra')) = pg_temp.tx('gra_hist')::int + 1
    and exists (select 1 from customer_phone_history h where h.customer_id = pg_temp.fx('cGra') and h.phone = '+61491570401'
                  and h.changed_by = pg_temp.fx('o')
                  and h.reason = 'Affiliate sign-up linked to the customer already there (Affiliates page): Same person, new phone')
    and exists (select 1 from audit_logs l where l.action = 'customer_updated' and l.record_id = pg_temp.fx('cGra')
                  and l.old_data->>'phone' = '+61491570401' and l.new_data->>'phone' = '+61491570402'
                  and l.old_data ? 'email' and l.new_data->>'email' = pg_temp.mail('lGra')
                  and l.changed_by = pg_temp.fx('o') and l.reason like 'Affiliate sign-up linked%'),
  'P the phone changed the Customers page''s way (update_customer): one phone history row with the old phone and the reason, and its audit row');
select pg_temp.check(exists (select 1 from audit_logs where action = 'affiliate_signup_linked' and record_id = (pg_temp.entry('lGra')).id
                               and old_data->>'customer_phone' = '+61491570401' and old_data->>'customer_email' is null
                               and new_data->>'customer_phone' = '+61491570402' and new_data->>'customer_email' = pg_temp.mail('lGra')
                               and (new_data->>'use_signup_phone')::boolean and (new_data->>'phone_changed')::boolean
                               and (new_data->>'email_copied')::boolean and new_data->>'email_not_copied' is null),
  'P the link''s audit row says the phone was changed and the email copied, with both before and after');
insert into tx values ('gra_counts', (select count(*) from customer_phone_history where customer_id = pg_temp.fx('cGra'))
  || '/' || (select count(*) from audit_logs where record_id in (pg_temp.fx('cGra'), (pg_temp.entry('lGra')).id))
  || '/' || (select count(*) from customers where deleted_at is null));
select pg_temp.check((public.link_affiliate_signup((pg_temp.entry('lGra')).id, pg_temp.fx('cGra'), 'Same person, new phone',
                        pg_temp.fx('req_gra'), true)->>'replayed')::boolean
    and (select count(*) from customer_phone_history where customer_id = pg_temp.fx('cGra'))
        || '/' || (select count(*) from audit_logs where record_id in (pg_temp.fx('cGra'), (pg_temp.entry('lGra')).id))
        || '/' || (select count(*) from customers where deleted_at is null) = pg_temp.tx('gra_counts')
    and (select phone from customers where id = pg_temp.fx('cGra')) = '+61491570402',
  'P a replay with the same request id answers "replayed" and changes nothing');

-- Ticked on a phone 3 customers hold, the fresh record one of them: the
-- merge retires it first, so Hal takes its place.
insert into tx values ('link_hal', public.link_affiliate_signup((pg_temp.entry('lHal')).id, pg_temp.fx('cHal'), null, gen_random_uuid(), true)::text);
select pg_temp.check((pg_temp.tx('link_hal')::jsonb->>'ok')::boolean
    and (select phone from customers where id = pg_temp.fx('cHal')) = '+61491570404'
    and pg_temp.on_phone('+61491570404') = 3 and pg_temp.on_phone('+61491570403') = 0,
  'P ticked on a phone 3 customers hold with the fresh record: the retired record''s place passes to Hal: ' || pg_temp.tx('link_hal'));

-- After Kim signed up, staff put another number on her fresh record; then 3
-- others came to hold the one she signed up with.
select pg_temp.as_user('s');
select pg_temp.check(pg_temp.err(format('select public.update_customer(%L, %L::jsonb, %L, null)', pg_temp.linked_to('lKim'),
         '{"phone": "+61491570407"}', 'T437 she gave another number')) is null,
  'P setup: Staff change the phone on Kim''s fresh record');
insert into customers(full_name, phone) values ('Pia Testthree', '+61491570406'), ('Quin Testthree', '+61491570406'), ('Rob Testthree', '+61491570406');
select pg_temp.as_user('o');
create function pg_temp.kim_state() returns text language sql as
$$ select concat_ws('|', k.phone, coalesce(k.email, '-'), f.phone, f.deleted_at is null, (pg_temp.entry('lKim')).status,
                    (select count(*) from customer_phone_history where customer_id in (k.id, f.id)),
                    (select count(*) from audit_logs where record_id in (k.id, f.id, (pg_temp.entry('lKim')).id)),
                    (select count(*) from customer_affiliates where customer_id in (k.id, f.id)),
                    (select a.customer_id from affiliate_accounts a where a.auth_user_id = pg_temp.fx('lKim')))
     from customers k, customers f where k.id = pg_temp.fx('cKim') and f.id = (pg_temp.entry('lKim')).fresh_customer_id $$;
insert into tx values ('kim_before', pg_temp.kim_state());
insert into fx values ('req_kim', gen_random_uuid());
insert into tx values ('link_kim', public.link_affiliate_signup((pg_temp.entry('lKim')).id, pg_temp.fx('cKim'), null, pg_temp.fx('req_kim'), true)::text);
select pg_temp.check(not (pg_temp.tx('link_kim')::jsonb->>'ok')::boolean and (pg_temp.tx('link_kim')::jsonb->>'phone_refused')::boolean
    and pg_temp.tx('link_kim')::jsonb->>'message' = 'The phone they signed up with, +61491570406, already belongs to 3 customers, so it cannot become Kim Testrefuse''s phone. Nothing was linked or changed. Untick "use the phone they signed up with" and link again.',
  'P ticked, but 3 others hold the phone she signed up with: the whole link is refused, and staff are told to untick it: ' || pg_temp.tx('link_kim'));
select pg_temp.check(pg_temp.kim_state() = pg_temp.tx('kim_before') and pg_temp.on_phone('+61491570406') = 3
    and not exists (select 1 from audit_logs where action = 'customers_merged' and record_id = pg_temp.fx('cKim')),
  'P nothing was changed: Kim''s phone and email, the fresh record, the entry, the phone history, the audit log, the affiliate records and the login are as before: ' || pg_temp.kim_state());
insert into tx values ('link_kim2', public.link_affiliate_signup((pg_temp.entry('lKim')).id, pg_temp.fx('cKim'), null, pg_temp.fx('req_kim'), false)::text);
select pg_temp.check((pg_temp.tx('link_kim2')::jsonb->>'ok')::boolean and (pg_temp.tx('link_kim2')::jsonb->>'replayed') is null
    and not (pg_temp.tx('link_kim2')::jsonb->>'phone_changed')::boolean
    and (select phone = '+61491570405' and email = pg_temp.mail('lKim') from customers where id = pg_temp.fx('cKim'))
    and pg_temp.linked_to('lKim') = pg_temp.fx('cKim'),
  'P unticked, the same request then goes through: Kim keeps her phone and gets the email she signed up with: ' || pg_temp.tx('link_kim2'));

-- The same refusal for a customer with a code of her own: the new record's
-- code, retired just before the merge, must come back with it. Uma has an
-- affiliate record and code (T437UMA) and no login; she signs up on another
-- phone, Staff then move her fresh record to a third, and 3 others come to
-- hold the one she signed up with.
do $$ declare c uuid; begin
  insert into customers(full_name, phone) values ('Uma Testowncode', '+61491570410') returning id into c; insert into fx values ('cUma', c);
  insert into customer_affiliates(customer_id, status, activated_at, referral_code) values (c, 'active', now(), 'T437UMA');
end $$;
select pg_temp.onboard('lUma', 'Uma', 'Testowncode', '+61491570411');
select pg_temp.check((pg_temp.entry('lUma')).reason = 'name_match' and pg_temp.fx('cUma') = any ((pg_temp.entry('lUma')).candidate_ids),
  'P setup: Uma signs up on a fresh record, listed with her');
select pg_temp.as_user('s');
select pg_temp.check(pg_temp.err(format('select public.update_customer(%L, %L::jsonb, %L, null)', pg_temp.linked_to('lUma'),
         '{"phone": "+61491570412"}', 'T437 she gave another number')) is null,
  'P setup: Staff change the phone on Uma''s fresh record');
insert into customers(full_name, phone) values ('Sal Testfour', '+61491570411'), ('Tom Testfour', '+61491570411'), ('Val Testfour', '+61491570411');
select pg_temp.as_user('o');
insert into tx values ('uma_code', (select ca.referral_code from customer_affiliates ca join affiliate_accounts a on a.affiliate_id = ca.id
                                     where a.auth_user_id = pg_temp.fx('lUma')));
insert into tx values ('uma_aff', (select affiliate_id::text from affiliate_accounts where auth_user_id = pg_temp.fx('lUma')));
insert into tx values ('list_uma', public.affiliate_signup_matches_open()::text);
select pg_temp.check(pg_temp.cand('list_uma', 'lUma', 'cUma')->>'problem' is null
    and pg_temp.cand('list_uma', 'lUma', 'cUma')->>'own_referral_code' = 'T437UMA'
    and (pg_temp.cand('list_uma', 'lUma', 'cUma')->>'retires_new_code')::boolean
    and pg_temp.listed('list_uma', 'lUma')->>'referral_code' = pg_temp.tx('uma_code'),
  'P setup: the list shows Uma as linkable, with her own code; linked, the new one (' || pg_temp.tx('uma_code') || ') is retired');
create function pg_temp.uma_state() returns text language sql as
$$ select concat_ws('|', k.phone, coalesce(k.email, '-'), f.phone, f.deleted_at is null, (pg_temp.entry('lUma')).status,
                    (select count(*) from customer_phone_history where customer_id in (k.id, f.id)),
                    (select count(*) from audit_logs where record_id in (k.id, f.id, (pg_temp.entry('lUma')).id)),
                    (select string_agg(ca.customer_id || ':' || ca.referral_code, ',' order by ca.referral_code)
                       from customer_affiliates ca where ca.customer_id in (k.id, f.id)),
                    (select a.customer_id || ':' || a.affiliate_id from affiliate_accounts a where a.auth_user_id = pg_temp.fx('lUma')))
     from customers k, customers f where k.id = pg_temp.fx('cUma') and f.id = (pg_temp.entry('lUma')).fresh_customer_id $$;
insert into tx values ('uma_before', pg_temp.uma_state());
insert into fx values ('req_uma', gen_random_uuid());
insert into tx values ('link_uma', public.link_affiliate_signup((pg_temp.entry('lUma')).id, pg_temp.fx('cUma'), null, pg_temp.fx('req_uma'), true)::text);
select pg_temp.check(not (pg_temp.tx('link_uma')::jsonb->>'ok')::boolean and (pg_temp.tx('link_uma')::jsonb->>'phone_refused')::boolean,
  'P ticked, Uma (a code of her own), 3 others on the phone she signed up with: the whole link is refused: ' || pg_temp.tx('link_uma'));
select pg_temp.check(pg_temp.uma_state() = pg_temp.tx('uma_before')
    and (select affiliate_id::text from affiliate_accounts where auth_user_id = pg_temp.fx('lUma')) = pg_temp.tx('uma_aff')
    and exists (select 1 from customer_affiliates where id = pg_temp.tx('uma_aff')::uuid and referral_code = pg_temp.tx('uma_code')
                  and customer_id = (pg_temp.entry('lUma')).fresh_customer_id and deleted_at is null)
    and (public.public_affiliate_referral_info(pg_temp.tx('uma_code'))->>'valid')::boolean
    and (select phone from customers where id = pg_temp.fx('cUma')) = '+61491570410'
    and not exists (select 1 from audit_logs where action = 'customers_merged' and record_id = pg_temp.fx('cUma'))
    and (pg_temp.entry('lUma')).status = 'open',
  'P nothing half done: the new record''s affiliate record and code are still there and still find her, the login is on it as before, Uma''s phone is as it was, no merge, the entry is open: ' || pg_temp.uma_state());
insert into tx values ('link_uma2', public.link_affiliate_signup((pg_temp.entry('lUma')).id, pg_temp.fx('cUma'), null, pg_temp.fx('req_uma'), false)::text);
select pg_temp.check((pg_temp.tx('link_uma2')::jsonb->>'ok')::boolean and (pg_temp.tx('link_uma2')::jsonb->>'replayed') is null
    and (pg_temp.tx('link_uma2')::jsonb->>'kept_own_affiliate')::boolean
    and (select ca.customer_id = pg_temp.fx('cUma') and ca.referral_code = 'T437UMA'
           from affiliate_accounts a join customer_affiliates ca on ca.id = a.affiliate_id where a.auth_user_id = pg_temp.fx('lUma'))
    and pg_temp.linked_to('lUma') = pg_temp.fx('cUma')
    and not exists (select 1 from customer_affiliates where referral_code = pg_temp.tx('uma_code'))
    and public.public_affiliate_referral_info(pg_temp.tx('uma_code')) = '{"valid": false}'::jsonb
    and (select phone = '+61491570410' and email = pg_temp.mail('lUma') from customers where id = pg_temp.fx('cUma')),
  'P unticked, the same request then goes through: the login moves onto Uma''s own record and code, the new code is retired, she keeps her phone: ' || pg_temp.tx('link_uma2'));

-- Leo has an email of his own: it stays. The box is left unticked (the
-- page's default; the argument's too).
insert into tx values ('link_leo', public.link_affiliate_signup((pg_temp.entry('lLeo')).id, pg_temp.fx('cLeo'), null, gen_random_uuid())::text);
select pg_temp.check((pg_temp.tx('link_leo')::jsonb->>'ok')::boolean and pg_temp.tx('link_leo')::jsonb->>'email_copied' is null
    and pg_temp.tx('link_leo')::jsonb->>'email_not_copied' = 'customer_has_email'
    and pg_temp.tx('link_leo')::jsonb->'notes' = '[]'::jsonb
    and (select email = 't437-leo-own-' || pg_temp.tx('sfx') || '@example.com' and phone = '+61491570408' from customers where id = pg_temp.fx('cLeo'))
    and not exists (select 1 from audit_logs where action = 'customer_updated' and record_id = pg_temp.fx('cLeo'))
    and exists (select 1 from audit_logs where action = 'affiliate_signup_linked' and record_id = (pg_temp.entry('lLeo')).id
                  and not (new_data->>'email_copied')::boolean and new_data->>'email_not_copied' = 'customer_has_email'
                  and not (new_data->>'use_signup_phone')::boolean and not (new_data->>'phone_changed')::boolean),
  'P Leo has an email of his own: it stays, and nothing on him is changed: ' || pg_temp.tx('link_leo'));
-- Another customer in use has the inbox Moe signed up with: it is left.
insert into tx values ('link_moe', public.link_affiliate_signup((pg_temp.entry('lMoe')).id, pg_temp.fx('cMoe'), null, gen_random_uuid(), false)::text);
select pg_temp.check((pg_temp.tx('link_moe')::jsonb->>'ok')::boolean and pg_temp.tx('link_moe')::jsonb->>'email_not_copied' = 'in_use'
    and pg_temp.tx('link_moe')::jsonb->'notes' = jsonb_build_array('The email they signed up with, ' || pg_temp.mail('lMoe')
                                                                   || ', was not copied onto Moe Testinuse: another customer already has it.')
    and (select email from customers where id = pg_temp.fx('cMoe')) is null
    and (select email from customers where id = pg_temp.fx('cMoeX')) = upper(pg_temp.mail('lMoe'))
    and exists (select 1 from audit_logs where action = 'affiliate_signup_linked' and record_id = (pg_temp.entry('lMoe')).id
                  and new_data->>'email_not_copied' = 'in_use' and not (new_data->>'email_copied')::boolean),
  'P another customer in use has the inbox Moe signed up with: it is not copied onto him, and the answer and the audit row say so: ' || pg_temp.tx('link_moe'));

-- Only a customer in use counts: a deleted one with the inbox Zoe signs up
-- with (in capitals) does not stop the copy. Vik has no email when the list
-- is read; Staff then save one on him, and Link keeps it. Wyn signs up with
-- a Gmail address another customer has written another way (capitals, the
-- dots left out, a +tag, googlemail.com): the same inbox, so it is left.
do $$ declare c uuid; sfx text := pg_temp.tx('sfx'); begin
  update auth.users set email = 't437.wyn.' || sfx || '@gmail.com' where id = pg_temp.fx('lWyn');
  insert into customers(full_name, phone) values ('Wyn Testgmail', '+61491578410') returning id into c; insert into fx values ('cWyn', c);
  insert into customers(full_name, phone, email) values ('Xan Testgmail', '+61491578412', 'T437Wyn' || upper(sfx) || '+shop@GoogleMail.com')
    returning id into c; insert into fx values ('cWynX', c);
  insert into customers(full_name, phone) values ('Zoe Testdelmail', '+61491578405') returning id into c; insert into fx values ('cZoe', c);
  insert into customers(full_name, phone, email) values ('Zed Testgone', '+61491578407', upper(pg_temp.mail('lZoe')))
    returning id into c; insert into fx values ('cZoeX', c);
  update customers set deleted_at = now() where id = c;
  insert into customers(full_name, phone) values ('Vik Testlater', '+61491578408') returning id into c; insert into fx values ('cVik', c);
end $$;
select pg_temp.onboard('lZoe', 'Zoe', 'Testdelmail', '+61491578406');
select pg_temp.onboard('lVik', 'Vik', 'Testlater', '+61491578409');
select pg_temp.onboard('lWyn', 'Wyn', 'Testgmail', '+61491578411');
select pg_temp.as_user('m');
insert into tx values ('list_p2', public.affiliate_signup_matches_open()::text);
select pg_temp.check((pg_temp.entry('lWyn')).reason = 'email_match'
    and (pg_temp.entry('lWyn')).candidate_ids @> array[pg_temp.fx('cWyn'), pg_temp.fx('cWynX')]
    and pg_temp.cand('list_p2', 'lWyn', 'cWyn')->>'email_on_link' = 'in_use'
    and pg_temp.cand('list_p2', 'lWyn', 'cWynX')->>'email_on_link' = 'keep_own',
  'P a Gmail address written another way (capitals, no dots, a +tag, googlemail.com) is the same inbox: the list says Wyn''s will be left');
select pg_temp.check((pg_temp.entry('lZoe')).reason = 'name_match' and (pg_temp.entry('lZoe')).candidate_ids = array[pg_temp.fx('cZoe')]
    and pg_temp.cand('list_p2', 'lZoe', 'cZoe')->>'email_on_link' = 'copy'
    and pg_temp.cand('list_p2', 'lZoe', 'cZoeX') is null
    and pg_temp.cand('list_p2', 'lVik', 'cVik')->>'email_on_link' = 'copy',
  'P a deleted customer with the inbox Zoe signed up with is not listed, and the list says her email will be copied; Vik''s too');
select pg_temp.as_user('o');
insert into tx values ('link_zoe', public.link_affiliate_signup((pg_temp.entry('lZoe')).id, pg_temp.fx('cZoe'), null, gen_random_uuid(), false)::text);
select pg_temp.check((pg_temp.tx('link_zoe')::jsonb->>'ok')::boolean and pg_temp.tx('link_zoe')::jsonb->>'email_copied' = pg_temp.mail('lZoe')
    and pg_temp.tx('link_zoe')::jsonb->>'email_not_copied' is null and pg_temp.tx('link_zoe')::jsonb->'notes' = '[]'::jsonb
    and (select email from customers where id = pg_temp.fx('cZoe')) = pg_temp.mail('lZoe')
    and exists (select 1 from audit_logs where action = 'affiliate_signup_linked' and record_id = (pg_temp.entry('lZoe')).id
                  and (new_data->>'email_copied')::boolean and new_data->>'email_not_copied' is null),
  'P only a customer in use counts: a deleted one with that inbox does not stop the copy onto Zoe: ' || pg_temp.tx('link_zoe'));
select pg_temp.as_user('s');
select pg_temp.check(pg_temp.err(format('select public.update_customer(%L, %L::jsonb, %L, null)', pg_temp.fx('cVik'),
         jsonb_build_object('email', 't437-vik-own-' || pg_temp.tx('sfx') || '@example.com'), 'T437 he gave his email')) is null,
  'P setup: after the list was read, Staff save an email on Vik');
select pg_temp.as_user('o');
insert into tx values ('link_vik', public.link_affiliate_signup((pg_temp.entry('lVik')).id, pg_temp.fx('cVik'), null, gen_random_uuid(), false)::text);
select pg_temp.check((pg_temp.tx('link_vik')::jsonb->>'ok')::boolean and pg_temp.tx('link_vik')::jsonb->>'email_copied' is null
    and pg_temp.tx('link_vik')::jsonb->>'email_not_copied' = 'customer_has_email'
    and (select email from customers where id = pg_temp.fx('cVik')) = 't437-vik-own-' || pg_temp.tx('sfx') || '@example.com'
    and exists (select 1 from audit_logs where action = 'affiliate_signup_linked' and record_id = (pg_temp.entry('lVik')).id
                  and old_data->>'customer_email' = 't437-vik-own-' || pg_temp.tx('sfx') || '@example.com'
                  and new_data->>'customer_email' = 't437-vik-own-' || pg_temp.tx('sfx') || '@example.com'
                  and not (new_data->>'email_copied')::boolean and new_data->>'email_not_copied' = 'customer_has_email'),
  'P the email Staff saved after the list was read is kept (the customer has one now), and the link''s audit row has it as before and after: ' || pg_temp.tx('link_vik'));

insert into tx values ('link_wyn', public.link_affiliate_signup((pg_temp.entry('lWyn')).id, pg_temp.fx('cWyn'), null, gen_random_uuid(), false)::text);
select pg_temp.check((pg_temp.tx('link_wyn')::jsonb->>'ok')::boolean and pg_temp.tx('link_wyn')::jsonb->>'email_not_copied' = 'in_use'
    and (select email from customers where id = pg_temp.fx('cWyn')) is null,
  'P and Link leaves it, as the list said: ' || pg_temp.tx('link_wyn'));

-- ═════ PB The phone box's default (AFF-SIGNUP-16) ═════
-- The P list above, read before those links: Leo keeps his own email and Moe's
-- is in use, so the box starts ticked; Gra's is copied and nothing of hers
-- waits, so it starts unticked; Cal has the very phone Dan signed up with.
select pg_temp.check((pg_temp.cand('list_p', 'lLeo', 'cLeo')->>'use_signup_phone_default')::boolean
    and pg_temp.cand('list_p', 'lLeo', 'cLeo')->'use_signup_phone_why' = '["email_keep_own"]'::jsonb
    and (pg_temp.cand('list_p', 'lMoe', 'cMoe')->>'use_signup_phone_default')::boolean
    and pg_temp.cand('list_p', 'lMoe', 'cMoe')->'use_signup_phone_why' = '["email_in_use"]'::jsonb,
  'PB the email cannot be copied (Leo keeps his own; another customer has Moe''s): the box starts ticked, and the list says why');
select pg_temp.check(not (pg_temp.cand('list_p', 'lGra', 'cGra')->>'use_signup_phone_default')::boolean
    and pg_temp.cand('list_p', 'lGra', 'cGra')->'use_signup_phone_why' = '[]'::jsonb
    and (pg_temp.listed('list_p', 'lGra')->'waiting'->>'qr')::int = 0
    and (pg_temp.listed('list_p', 'lGra')->'waiting'->>'seminar') is not distinct from
        case when to_regclass('public.event_registration_people') is not null then '0' end,
  'PB the email is copied and nothing waits under To match (Gra): unticked: ' || (pg_temp.listed('list_p', 'lGra')->'waiting')::text);
select pg_temp.check(not (pg_temp.cand('list_m', 'lDan', 'cCal')->>'use_signup_phone_default')::boolean
    and pg_temp.cand('list_m', 'lDan', 'cCal')->'use_signup_phone_why' = '["same_phone"]'::jsonb,
  'PB the customer has the phone they signed up with already (Cal): nothing to tick');
-- Qra signs up on a new phone; a QR health form of hers (433) and, with 436
-- in, a seminar registration wait under To match with her fresh record as
-- a candidate.
do $$ declare c uuid; begin
  insert into customers(full_name, phone) values ('Qra Testwaiting', '+61491578413') returning id into c; insert into fx values ('cQra', c);
end $$;
select pg_temp.onboard('lQra', 'Qra', 'Testwaiting', '+61491578414');
select pg_temp.check((pg_temp.entry('lQra')).reason = 'name_match' and (pg_temp.entry('lQra')).candidate_ids = array[pg_temp.fx('cQra')],
  'PB setup: Qra signs up on a fresh record, listed with the customer she is');
insert into fx values ('cQraFresh', pg_temp.linked_to('lQra'));
select pg_temp.as_user('m');
insert into tx values ('list_q0', public.affiliate_signup_matches_open()::text);
select pg_temp.check(not (pg_temp.cand('list_q0', 'lQra', 'cQra')->>'use_signup_phone_default')::boolean
    and pg_temp.cand('list_q0', 'lQra', 'cQra')->>'email_on_link' = 'copy'
    and (pg_temp.listed('list_q0', 'lQra')->'waiting'->>'qr')::int = 0,
  'PB before anything waits: unticked');
do $$ declare sv uuid; begin
  insert into health_surveys(survey_no, full_name, phone) values ('T437-SV-' || pg_temp.tx('sfx') || '-1', 'Qra Testwaiting', '+61491578414')
    returning id into sv;
  insert into health_survey_holds(survey_id, reason, candidate_customer_ids, typed_full_name, typed_phone)
    values (sv, 'phone_in_use', array[pg_temp.fx('cQraFresh'), pg_temp.fx('cQra')], 'Qra Testwaiting', '+61491578414');
  -- One already sorted out does not count.
  insert into health_surveys(survey_no, full_name, phone) values ('T437-SV-' || pg_temp.tx('sfx') || '-2', 'Qra Testwaiting', '+61491578414')
    returning id into sv;
  insert into health_survey_holds(survey_id, reason, candidate_customer_ids, typed_full_name, typed_phone, resolved_at, resolution)
    values (sv, 'phone_in_use', array[pg_temp.fx('cQraFresh')], 'Qra Testwaiting', '+61491578414', now(), 'closed');
end $$;
insert into tx values ('list_q1', public.affiliate_signup_matches_open()::text);
select pg_temp.check((pg_temp.cand('list_q1', 'lQra', 'cQra')->>'use_signup_phone_default')::boolean
    and pg_temp.cand('list_q1', 'lQra', 'cQra')->'use_signup_phone_why' = '["waiting_qr"]'::jsonb
    and (pg_temp.listed('list_q1', 'lQra')->'waiting'->>'qr')::int = 1,
  'PB a QR health form held with her fresh record as a candidate waits under To match: ticked (waiting_qr), 1 waiting (the one sorted out does not count): '
  || (pg_temp.listed('list_q1', 'lQra')->'waiting')::text);
do $$
declare ev uuid; rg uuid; n int; sfx text := pg_temp.tx('sfx');
begin
  if to_regclass('public.event_registration_people') is null then
    insert into tx values ('sem_installed', 'no');
    raise notice 'NOTE  PB seminar holds: 436 is not installed here, so the seminar part is skipped (the list gives seminar null)';
    return;
  end if;
  insert into tx values ('sem_installed', 'yes');
  insert into events(name) values ('T437 Seminar ' || sfx) returning id into ev;
  insert into event_days(event_id, day) values (ev, current_date + 30);
  execute $q$insert into public.event_registrations(event_id, registration_id, people_count, people_md5)
            values ($1, 'REG-20261021-' || upper(substr(md5(random()::text), 1, 8)), 3, md5('t437')) returning id$q$ into rg using ev;
  -- Held with her fresh record as a candidate; a test registration and one
  -- already attached do not count.
  execute $q$insert into public.event_registration_people(registration_ref, event_id, position, first_name, full_name, phone, phone_norm,
               days, match, hold_reason, candidate_customer_ids, upgrade_token, is_test)
            select $1, $2, x.pos, 'Qra', 'Qra Testwaiting', '+61491578414', '+61491578414', array[current_date + 30], x.mt,
                   case when x.mt = 'held' then 'phone_in_use' end, array[$3],
                   'vip_' || translate(substr(md5(random()::text) || md5(random()::text), 1, 26), '01890', 'abcde'), x.test
              from (values (1, 'held', false), (2, 'held', true), (3, 'staff_attached', false)) x(pos, mt, test)$q$
    using rg, ev, pg_temp.fx('cQraFresh');
end $$;
insert into tx values ('list_q2', public.affiliate_signup_matches_open()::text);
select pg_temp.check(case when pg_temp.tx('sem_installed') = 'yes'
         then (pg_temp.listed('list_q2', 'lQra')->'waiting'->>'seminar')::int = 1
              and pg_temp.cand('list_q2', 'lQra', 'cQra')->'use_signup_phone_why' = '["waiting_seminar", "waiting_qr"]'::jsonb
              and (pg_temp.cand('list_q2', 'lQra', 'cQra')->>'use_signup_phone_default')::boolean
         else pg_temp.listed('list_q2', 'lQra')->'waiting'->'seminar' = 'null'::jsonb
              and pg_temp.cand('list_q2', 'lQra', 'cQra')->'use_signup_phone_why' = '["waiting_qr"]'::jsonb end,
  'PB with 436 in, a seminar registration held with her fresh record as a candidate counts (not a test one, nor one attached): '
  || 'ticked (waiting_seminar); without 436 the seminar count is null: ' || (pg_temp.listed('list_q2', 'lQra')->'waiting')::text);
select pg_temp.check(pg_temp.err('select public.affiliate_signup_matches_open()') is null,
  'PB the list reads 436''s table only by name: it works with and without 436 (here: ' || pg_temp.tx('sem_installed') || ')');

-- ═════ EL Link earns the commission the fresh record's paid invoices missed (AFF-SIGNUP-17) ═════
-- Erin is a customer referred by Una (an affiliate), whom Ula referred (Ula
-- has no affiliate record, so her tier 2 is blocked, as the engine has it).
-- Erin signs up on a new phone and gets a fresh record; on it she buys, and
-- pays for, a product, a seminar VIP, a product she gets S$40 back on, a
-- product through another affiliate's code (Oth's: commission at once), one
-- through her own new code, one the engine will refuse, and one she has not
-- paid for; and a credit package, a premium bundle, a product with a
-- package, and a package whose invoice names no affiliate on purpose (Oth's
-- code taken off before payment). None but Oth's earned anything: the fresh
-- record has no referrer. Cora, whom Una referred, buys the same package,
-- bundle and product with a package: what payment earns her referrer is
-- what Link must earn Erin's.
select pg_temp.as_user('o');
do $$
declare st uuid; pm uuid; pr uuid; ev uuid; opt uuid; c uuid; a uuid; cp uuid; pb uuid; sfx text := pg_temp.tx('sfx');
begin
  -- The commission rates as the engine reads them (production has this row;
  -- a bare local database may not): 15% tier 1, 5% of it tier 2; packages
  -- and bundles (third-party sales) 4.5% tier 1, 5% of it tier 2.
  insert into app_settings(id, commission_tier1_own_rate, commission_tier2_own_rate, commission_tier1_third_rate, commission_tier2_third_rate)
    values (true, 15, 5, 4.5, 5)
    on conflict (id) do update set commission_tier1_own_rate = 15, commission_tier2_own_rate = 5,
                                   commission_tier1_third_rate = 4.5, commission_tier2_third_rate = 5;
  insert into stores(name, code, country_code) values ('T437 Store ' || sfx, 'T437' || sfx, 'SG') returning id into st; insert into fx values ('st', st);
  insert into payment_methods(name) values ('T437 Cash ' || sfx) returning id into pm; insert into fx values ('pm', pm);
  insert into products(name, sku, product_type) values ('T437 Product ' || sfx, 'T437P' || sfx, 'own') returning id into pr; insert into fx values ('pr', pr);
  insert into store_inventory(store_id, product_id, current_qty) values (st, pr, 100);
  perform set_product_prices(st, pr, 100, 100, 'available');
  insert into events(name) values ('T437 Health Seminar ' || sfx) returning id into ev;
  insert into event_days(event_id, day) values (ev, current_date + 30), (ev, current_date + 31);
  insert into event_stores(event_id, store_id) values (ev, st);
  insert into event_ticket_options(event_id, name, days_count, price) values (ev, 'VIP', 2, 72) returning id into opt; insert into fx values ('vip', opt);
  insert into credit_packages(name, customer_price, paid_credit_amount, allow_product, allow_therapy)
    values ('T437 Package ' || sfx, 1000, 1000, true, true) returning id into cp; insert into fx values ('pkg', cp);
  insert into credit_package_stores(package_id, store_id) values (cp, st);
  insert into premium_bundles(name, customer_payment_amount, paid_credit_amount, bonus_credit_amount, free_voucher_qty, grants_reward)
    values ('T437 Bundle ' || sfx, 2000, 2000, 200, 0, false) returning id into pb; insert into fx values ('bundle', pb);
  insert into premium_bundle_stores(bundle_id, store_id) values (pb, st);
  insert into customers(full_name, phone) values ('Ula Testtop', '+61491578422') returning id into c; insert into fx values ('cUp', c);
  insert into customers(full_name, phone, referred_by) values ('Una Testupline', '+61491578423', pg_temp.fx('cUp')) returning id into c;
  insert into fx values ('cRef', c);
  insert into customer_affiliates(customer_id, status, activated_at, referral_code) values (c, 'active', now(), 'T437UNA');
  insert into customers(full_name, phone, referred_by) values ('Erin Testearn', '+61491578415', pg_temp.fx('cRef')) returning id into c;
  insert into fx values ('cErn', c);
  insert into customers(full_name, phone) values ('Oth Testother', '+61491578424') returning id into c; insert into fx values ('cOth', c);
  insert into customer_affiliates(customer_id, status, activated_at, referral_code) values (c, 'active', now(), 'T437OTH') returning id into a;
  insert into fx values ('affOth', a);
  -- Noor: a customer with no referrer, and her own sign-up later.
  insert into customers(full_name, phone) values ('Noor Testnoref', '+61491578417') returning id into c; insert into fx values ('cNor', c);
  -- Cora: Una referred her; her own purchases are the control.
  insert into customers(full_name, phone, referred_by) values ('Cora Testcontrol', '+61491578425', pg_temp.fx('cRef')) returning id into c;
  insert into fx values ('cCora', c);
end $$;
select pg_temp.onboard('lErn', 'Erin', 'Testearn', '+61491578416');
select pg_temp.onboard('lNor', 'Noor', 'Testnoref', '+61491578418');
select pg_temp.check((pg_temp.entry('lErn')).reason = 'name_match' and (pg_temp.entry('lErn')).candidate_ids = array[pg_temp.fx('cErn')]
    and (pg_temp.entry('lNor')).reason = 'name_match' and (pg_temp.entry('lNor')).candidate_ids = array[pg_temp.fx('cNor')],
  'EL setup: Erin and Noor sign up on fresh records, listed with the customers they are');
insert into fx values ('cErnFresh', pg_temp.linked_to('lErn')), ('cNorFresh', pg_temp.linked_to('lNor'));
insert into fx values ('affErnFresh', (select affiliate_id from affiliate_accounts where auth_user_id = pg_temp.fx('lErn')));
select pg_temp.as_user('o');
create function pg_temp.pay(inv uuid) returns uuid language plpgsql as
$$begin
  perform public.record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.fx('pm'),
    'amount', (select total_amount from invoices where id = inv))), gen_random_uuid());
  return inv;
end$$;
create function pg_temp.sale(who text, what text, aff uuid, pay boolean) returns uuid language plpgsql as
$$declare inv uuid;
  v_product jsonb := jsonb_build_object('kind', 'product', 'product_id', pg_temp.fx('pr'), 'quantity', 1);
  v_pkg jsonb := jsonb_build_object('kind', 'credit_package', 'credit_package_id', pg_temp.fx('pkg'), 'quantity', 1);
begin
  inv := public.create_invoice(pg_temp.fx('st'), pg_temp.fx(who), aff,
           case what when 'vip' then jsonb_build_array(jsonb_build_object('kind', 'event_ticket', 'event_ticket_option_id', pg_temp.fx('vip'),
                                         'quantity', 1, 'attendees', jsonb_build_array(jsonb_build_object('name', 'Erin Testearn'))))
                     when 'pkg' then jsonb_build_array(v_pkg)
                     when 'mixed' then jsonb_build_array(v_product, v_pkg)
                     when 'bundle' then jsonb_build_array(jsonb_build_object('kind', 'premium_bundle', 'premium_bundle_id', pg_temp.fx('bundle'),
                                         'quantity', 1, 'voucher_selection', '[]'::jsonb))
                     else jsonb_build_array(v_product) end);
  if pay then perform pg_temp.pay(inv); end if;
  return inv;
end$$;
insert into fx values ('invA', pg_temp.sale('cErnFresh', 'product', null, true)),
                      ('invB', pg_temp.sale('cErnFresh', 'vip', null, true)),
                      ('invC', pg_temp.sale('cErnFresh', 'product', null, true)),
                      ('invD', pg_temp.sale('cErnFresh', 'product', pg_temp.fx('affOth'), true)),
                      ('invF', pg_temp.sale('cErnFresh', 'product', pg_temp.fx('affErnFresh'), true)),
                      ('invG', pg_temp.sale('cErnFresh', 'product', null, true)),
                      ('invU', pg_temp.sale('cErnFresh', 'product', null, false)),
                      ('invN', pg_temp.sale('cNorFresh', 'product', null, true)),
                      ('invP', pg_temp.sale('cErnFresh', 'pkg', null, true)),
                      ('invQ', pg_temp.sale('cErnFresh', 'mixed', null, true)),
                      ('invR', pg_temp.sale('cErnFresh', 'bundle', null, true)),
                      ('invX', pg_temp.sale('cErnFresh', 'pkg', pg_temp.fx('affOth'), false)),
                      ('ctlP', pg_temp.sale('cCora', 'pkg', null, true)),
                      ('ctlQ', pg_temp.sale('cCora', 'mixed', null, true)),
                      ('ctlR', pg_temp.sale('cCora', 'bundle', null, true));
-- X: Oth's code taken off on purpose before it is paid.
select public.set_invoice_affiliate(pg_temp.fx('invX'), null);
select pg_temp.pay(pg_temp.fx('invX'));
-- One invoice's commission rows as payment or Link left them, to compare.
create function pg_temp.crows(p_inv text) returns jsonb language sql as
$$ select coalesce(jsonb_agg(jsonb_build_object('tier', c.tier, 'referrer', c.referrer_customer_id, 'status', c.status,
                                                'product_type', c.product_type, 'line_amount', c.line_amount, 'rate', c.rate,
                                                'amount', c.commission_amount, 'block_reason', c.block_reason)
                             order by c.tier, c.product_type, c.line_amount, c.commission_amount), '[]'::jsonb)
     from commissions c where c.invoice_id = pg_temp.fx(p_inv) $$;
-- A paid a month ago (the engine would date it then); S$40 back on C.
update invoices set paid_at = timestamptz '2026-09-15 10:00+08' where id = pg_temp.fx('invA');
do $$ declare it uuid; pay uuid; mv uuid; begin
  select id into it from invoice_items where invoice_id = pg_temp.fx('invC');
  select id into pay from invoice_payments where invoice_id = pg_temp.fx('invC');
  select id into mv from stock_movements where invoice_id = pg_temp.fx('invC') and movement_type = 'store_sale';
  perform public.refund_invoice_recorded(pg_temp.fx('invC'), jsonb_build_array(jsonb_build_object('invoice_item_id', it, 'amount', 40)),
    jsonb_build_array(jsonb_build_object('payment_id', pay, 'amount', 40)),
    jsonb_build_array(jsonb_build_object('movement_id', mv, 'not_returned_quantity', 1)), 'T437 part refund', gen_random_uuid());
end $$;
create temp table d_rows as select * from commissions where invoice_id = pg_temp.fx('invD');
select pg_temp.check((select status::text from invoices where id = pg_temp.fx('invC')) = 'paid'
    and (select status::text from invoices where id = pg_temp.fx('invU')) <> 'paid'
    and not exists (select 1 from commissions where invoice_id in (pg_temp.fx('invA'), pg_temp.fx('invB'), pg_temp.fx('invC'),
                                                                  pg_temp.fx('invF'), pg_temp.fx('invG'), pg_temp.fx('invU'), pg_temp.fx('invN'),
                                                                  pg_temp.fx('invP'), pg_temp.fx('invQ'), pg_temp.fx('invR'), pg_temp.fx('invX')))
    and (select count(*) from d_rows) = 1
    and (select referrer_customer_id = pg_temp.fx('cOth') and commission_amount = 15 from d_rows)
    and (select bool_and(status::text = 'paid') from invoices where id in (pg_temp.fx('invP'), pg_temp.fx('invQ'), pg_temp.fx('invR'), pg_temp.fx('invX')))
    and (select affiliate_selection_explicit and affiliate_id is null from invoices where id = pg_temp.fx('invX'))
    and (select count(*) from credit_package_sales where invoice_id in (pg_temp.fx('invP'), pg_temp.fx('invQ'), pg_temp.fx('invX'))
           and customer_id = pg_temp.fx('cErnFresh')) = 3
    and (select count(*) from premium_bundle_sales where invoice_id = pg_temp.fx('invR') and customer_id = pg_temp.fx('cErnFresh')) = 1,
  'EL setup: on the fresh record (no referrer) only the sale through Oth''s code earned commission; C stays paid after its part refund; '
  || 'the package, bundle and package-with-product invoices are paid, X with its affiliate taken off on purpose');
-- What payment earns on the same sales to Cora, whom Una referred: tier 1
-- 4.5% of the package (S$45.00) or bundle (S$90.00) for Una and tier 2 5% of
-- it for Ula (the package and bundle functions write tier 2 as earned), and
-- for the product with a package also the product's S$15.00 and S$0.75
-- (blocked).
select pg_temp.check(pg_temp.crows('ctlP') @> jsonb_build_array(
        jsonb_build_object('tier', 'tier1', 'referrer', pg_temp.fx('cRef'), 'amount', 45.00, 'line_amount', 1000.00, 'status', 'earned'),
        jsonb_build_object('tier', 'tier2', 'referrer', pg_temp.fx('cUp'), 'amount', 2.25, 'status', 'earned'))
    and jsonb_array_length(pg_temp.crows('ctlP')) = 2
    and pg_temp.crows('ctlR') @> jsonb_build_array(
        jsonb_build_object('tier', 'tier1', 'referrer', pg_temp.fx('cRef'), 'amount', 90.00, 'line_amount', 2000.00, 'status', 'earned'))
    and jsonb_array_length(pg_temp.crows('ctlR')) = 2
    and pg_temp.crows('ctlQ') @> jsonb_build_array(
        jsonb_build_object('tier', 'tier1', 'referrer', pg_temp.fx('cRef'), 'amount', 45.00, 'status', 'earned'),
        jsonb_build_object('tier', 'tier1', 'referrer', pg_temp.fx('cRef'), 'amount', 15.00, 'status', 'earned'),
        jsonb_build_object('tier', 'tier2', 'referrer', pg_temp.fx('cUp'), 'amount', 0.75, 'status', 'blocked'))
    and jsonb_array_length(pg_temp.crows('ctlQ')) = 4,
  'EL control: payment earns Cora''s referrer the package S$45.00, the bundle S$90.00, and the product with a package S$15.00 + S$45.00 (tier 2 as the engine has it): '
  || pg_temp.crows('ctlP')::text || ' ' || pg_temp.crows('ctlR')::text || ' ' || pg_temp.crows('ctlQ')::text);
-- The engine refuses G (a stand-in for any refusal), until the link is done.
create function public.t437_refuse_commission() returns trigger language plpgsql as
$f$begin
  if new.invoice_id::text = current_setting('t437.refuse_invoice', true) then raise exception 'T437 commission refused'; end if;
  return new;
end$f$;
create trigger t437_refuse_commission before insert on commissions for each row execute function public.t437_refuse_commission();
select set_config('t437.refuse_invoice', pg_temp.fx('invG')::text, true);
insert into fx values ('req_ern', gen_random_uuid());
insert into tx values ('link_ern', public.link_affiliate_signup((pg_temp.entry('lErn')).id, pg_temp.fx('cErn'), 'T437 the same Erin',
  pg_temp.fx('req_ern'), false)::text);
drop trigger t437_refuse_commission on commissions;
drop function public.t437_refuse_commission();
select pg_temp.check((pg_temp.tx('link_ern')::jsonb->>'ok')::boolean and pg_temp.linked_to('lErn') = pg_temp.fx('cErn')
    and (select deleted_at is not null from customers where id = pg_temp.fx('cErnFresh'))
    and (select count(*) from invoices where customer_id = pg_temp.fx('cErn')) = 11,
  'EL the link goes through: the login and all 11 invoices are on Erin, the fresh record retired: ' || pg_temp.tx('link_ern'));
create function pg_temp.crow(p_inv text, p_tier text) returns public.commissions language sql as
$$ select * from commissions where invoice_id = pg_temp.fx(p_inv) and tier::text = p_tier $$;
select pg_temp.check((pg_temp.crow('invA', 'tier1')).referrer_customer_id = pg_temp.fx('cRef')
    and (pg_temp.crow('invA', 'tier1')).commission_amount = 15.00 and (pg_temp.crow('invA', 'tier1')).status::text = 'earned'
    and (pg_temp.crow('invA', 'tier1')).buyer_customer_id = pg_temp.fx('cErn')
    and (pg_temp.crow('invA', 'tier2')).referrer_customer_id = pg_temp.fx('cUp')
    and (pg_temp.crow('invA', 'tier2')).commission_amount = 0.75 and (pg_temp.crow('invA', 'tier2')).status::text = 'blocked'
    and (pg_temp.crow('invA', 'tier2')).block_reason = 'Affiliate Not Activated'
    and (select count(*) from commissions where invoice_id = pg_temp.fx('invA')) = 2,
  'EL A (S$100): Una earns tier 1 S$15.00; Ula''s tier 2 S$0.75 is blocked (no affiliate record), as the engine has it');
select pg_temp.check((select bool_and(invoice_paid_date = sg_today()) from commissions where invoice_id = pg_temp.fx('invA'))
    and (select (paid_at at time zone 'Asia/Singapore')::date from invoices where id = pg_temp.fx('invA')) = date '2026-09-15',
  'EL A is dated the Link day in Singapore (' || sg_today() || '), not the day it was paid (15 Sep 2026)');
select pg_temp.check((pg_temp.crow('invB', 'tier1')).commission_amount = 10.80 and (pg_temp.crow('invB', 'tier1')).referrer_customer_id = pg_temp.fx('cRef')
    and (pg_temp.crow('invB', 'tier2')).commission_amount = 0.54 and (pg_temp.crow('invB', 'tier2')).status::text = 'blocked'
    and (select bool_and(invoice_paid_date = sg_today()) from commissions where invoice_id = pg_temp.fx('invB')),
  'EL B (the S$72 seminar VIP): tier 1 S$10.80, tier 2 S$0.54 blocked, dated the Link day');
select pg_temp.check((pg_temp.crow('invC', 'tier1')).commission_amount = 9.00 and (pg_temp.crow('invC', 'tier1')).line_amount = 60.00
    and (pg_temp.crow('invC', 'tier2')).commission_amount = 0.45
    and (select bool_and(invoice_paid_date = sg_today()) from commissions where invoice_id = pg_temp.fx('invC')),
  'EL C (S$100, S$40 refunded before the link): the refund is taken off as the engine''s refund step does: tier 1 S$9.00 on S$60, tier 2 S$0.45');
select pg_temp.check((select count(*) from commissions where invoice_id = pg_temp.fx('invD')) = 1
    and (select c.id = d.id and c.commission_amount = d.commission_amount and c.invoice_paid_date = d.invoice_paid_date
               and c.referrer_customer_id = d.referrer_customer_id and c.status = d.status
           from commissions c, d_rows d where c.invoice_id = pg_temp.fx('invD')),
  'EL D (already commissioned, through Oth''s code) is left alone: the same row, amount and date');
select pg_temp.check(not exists (select 1 from commissions where invoice_id in (pg_temp.fx('invF'), pg_temp.fx('invG'), pg_temp.fx('invU'), pg_temp.fx('invX'))),
  'EL F (through her own code: a customer never earns on her own purchase), X (a package whose invoice names no affiliate on purpose), '
  || 'G (refused) and U (not paid) earn nothing');
-- The package, the bundle and the product with a package earn in full:
-- exactly what payment earned on Cora's same sales, dated the Link day.
select pg_temp.check(pg_temp.crows('invP') = pg_temp.crows('ctlP')
    and (select bool_and(invoice_paid_date = sg_today() and buyer_customer_id = pg_temp.fx('cErn')) from commissions where invoice_id = pg_temp.fx('invP')),
  'EL P (a S$1,000 credit package): what payment earns, tier 1 S$45.00 for Una and tier 2 for Ula, dated the Link day: ' || pg_temp.crows('invP')::text);
select pg_temp.check(pg_temp.crows('invR') = pg_temp.crows('ctlR')
    and (select bool_and(invoice_paid_date = sg_today() and buyer_customer_id = pg_temp.fx('cErn')) from commissions where invoice_id = pg_temp.fx('invR')),
  'EL R (a S$2,000 premium bundle): what payment earns, tier 1 S$90.00, dated the Link day: ' || pg_temp.crows('invR')::text);
select pg_temp.check(pg_temp.crows('invQ') = pg_temp.crows('ctlQ') and jsonb_array_length(pg_temp.crows('invQ')) = 4
    and (select bool_and(invoice_paid_date = sg_today()) from commissions where invoice_id = pg_temp.fx('invQ')),
  'EL Q (a product with a package): both parts earn, S$15.00 + S$45.00 tier 1, as payment earns them, dated the Link day: ' || pg_temp.crows('invQ')::text);
select pg_temp.check(jsonb_array_length(pg_temp.tx('link_ern')::jsonb->'commission_earned') = 6
    and (select array_agg(e->>'invoice_id' order by e->>'invoice_id') from jsonb_array_elements(pg_temp.tx('link_ern')::jsonb->'commission_earned') e)
        = (select array_agg(x::text order by x::text) from unnest(array[pg_temp.fx('invA'), pg_temp.fx('invB'), pg_temp.fx('invC'),
                                                                        pg_temp.fx('invP'), pg_temp.fx('invQ'), pg_temp.fx('invR')]) x)
    and (select (e->>'amount')::numeric from jsonb_array_elements(pg_temp.tx('link_ern')::jsonb->'commission_earned') e
          where (e->>'invoice_id')::uuid = pg_temp.fx('invQ'))
        = (select sum(commission_amount) from commissions where invoice_id = pg_temp.fx('ctlQ') and status::text = 'earned')
    and (select (e->>'amount')::numeric from jsonb_array_elements(pg_temp.tx('link_ern')::jsonb->'commission_earned') e
          where (e->>'invoice_id')::uuid = pg_temp.fx('invP'))
        = (select sum(commission_amount) from commissions where invoice_id = pg_temp.fx('ctlP') and status::text = 'earned')
    and (select bool_and((e->>'dated')::date = sg_today()) from jsonb_array_elements(pg_temp.tx('link_ern')::jsonb->'commission_earned') e)
    and (select (e->>'amount')::numeric from jsonb_array_elements(pg_temp.tx('link_ern')::jsonb->'commission_earned') e
          where (e->>'invoice_id')::uuid = pg_temp.fx('invB')) = 10.80
    and (select e->'rows' @> jsonb_build_array(jsonb_build_object('tier', 'tier1', 'referrer_name', 'Una Testupline', 'amount', 15.00, 'status', 'earned'),
                                               jsonb_build_object('tier', 'tier2', 'referrer_name', 'Ula Testtop', 'amount', 0.75, 'status', 'blocked',
                                                                  'block_reason', 'Affiliate Not Activated'))
           from jsonb_array_elements(pg_temp.tx('link_ern')::jsonb->'commission_earned') e where (e->>'invoice_id')::uuid = pg_temp.fx('invA'))
    and (pg_temp.tx('link_ern')::jsonb->>'commission_dated')::date = sg_today(),
  'EL the answer lists the invoices earned (A, B, C, P, Q, R) with each tier''s referrer and amount, dated the Link day');
select pg_temp.check((select jsonb_agg(jsonb_build_object('i', e->>'invoice_id', 'why', e->>'why', 'msg', e->>'message') order by e->>'invoice_id')
                        from jsonb_array_elements(pg_temp.tx('link_ern')::jsonb->'commission_not_earned') e)
      = (select jsonb_agg(jsonb_build_object('i', x.i::text, 'why', x.why, 'msg', x.msg) order by x.i::text)
           from (values (pg_temp.fx('invF'), 'none_due', null), (pg_temp.fx('invG'), 'refused', 'T437 commission refused'),
                        (pg_temp.fx('invX'), 'none_due', null)) x(i, why, msg)),
  'EL and names those not earned: F and X (none due by the engine''s rules) and G (refused, with why); D and U are not listed: '
  || (pg_temp.tx('link_ern')::jsonb->'commission_not_earned')::text);
select pg_temp.check(exists (select 1 from audit_logs where action = 'affiliate_signup_linked' and record_id = (pg_temp.entry('lErn')).id
                               and new_data->'commission_earned' = pg_temp.tx('link_ern')::jsonb->'commission_earned'
                               and new_data->'commission_not_earned' = pg_temp.tx('link_ern')::jsonb->'commission_not_earned'
                               and (new_data->>'referrer_customer_id')::uuid = pg_temp.fx('cRef')
                               and (new_data->>'commission_dated')::date = sg_today()),
  'EL the link''s audit row lists the same invoices and amounts');
insert into tx values ('ern_counts', (select count(*) || '/' || sum(commission_amount) from commissions
                                       where invoice_id in (select id from invoices where customer_id = pg_temp.fx('cErn'))));
insert into tx values ('replay_ern', public.link_affiliate_signup((pg_temp.entry('lErn')).id, pg_temp.fx('cErn'), 'T437 the same Erin',
                        pg_temp.fx('req_ern'), false)::text);
select pg_temp.check((pg_temp.tx('replay_ern')::jsonb->>'replayed')::boolean
    and (select count(*) || '/' || sum(commission_amount) from commissions
          where invoice_id in (select id from invoices where customer_id = pg_temp.fx('cErn'))) = pg_temp.tx('ern_counts')
    and not exists (select 1 from commissions where invoice_id = pg_temp.fx('invG'))
    and (select count(*) from audit_logs where action = 'affiliate_signup_linked' and record_id = (pg_temp.entry('lErn')).id) = 1,
  'EL a replay with the same request id earns nothing more (' || pg_temp.tx('ern_counts') || ') and writes no second audit row');
-- After a lost answer, the replay says what the link did (read back from
-- its audit row), so the page can show it: the same commission lists, the
-- email copied and the phone.
select pg_temp.check((pg_temp.tx('replay_ern')::jsonb->>'ok')::boolean
    and pg_temp.tx('replay_ern')::jsonb->'commission_earned' = pg_temp.tx('link_ern')::jsonb->'commission_earned'
    and pg_temp.tx('replay_ern')::jsonb->'commission_not_earned' = pg_temp.tx('link_ern')::jsonb->'commission_not_earned'
    and pg_temp.tx('replay_ern')::jsonb->'commission_dated' = pg_temp.tx('link_ern')::jsonb->'commission_dated'
    and pg_temp.tx('replay_ern')::jsonb->'email_copied' = pg_temp.tx('link_ern')::jsonb->'email_copied'
    and pg_temp.tx('link_ern')::jsonb->>'email_copied' = pg_temp.mail('lErn')
    and pg_temp.tx('replay_ern')::jsonb->'email_not_copied' = pg_temp.tx('link_ern')::jsonb->'email_not_copied'
    and pg_temp.tx('replay_ern')::jsonb->'phone_changed' = pg_temp.tx('link_ern')::jsonb->'phone_changed'
    and pg_temp.tx('replay_ern')::jsonb->'phone' = pg_temp.tx('link_ern')::jsonb->'phone'
    and pg_temp.tx('replay_ern')::jsonb->'notes' = pg_temp.tx('link_ern')::jsonb->'notes'
    and pg_temp.tx('replay_ern')::jsonb->'kept_own_affiliate' = pg_temp.tx('link_ern')::jsonb->'kept_own_affiliate'
    and (pg_temp.tx('replay_ern')::jsonb->>'customer_id')::uuid = pg_temp.fx('cErn')
    and (pg_temp.tx('replay_ern')::jsonb->>'retired')::uuid = pg_temp.fx('cErnFresh'),
  'EL the replay answers what the link did: the same commission lists, date, email and phone: ' || pg_temp.tx('replay_ern'));
-- Later the engine works A out again (a part refund of S$40, through
-- reconcile_invoice_commissions): the Link-day rows are reversed and what it
-- earns again is dated by the day A was paid (15 Sep 2026), as for any
-- invoice. The total is right.
do $$ declare it uuid; pay uuid; mv uuid; begin
  select id into it from invoice_items where invoice_id = pg_temp.fx('invA');
  select id into pay from invoice_payments where invoice_id = pg_temp.fx('invA');
  select id into mv from stock_movements where invoice_id = pg_temp.fx('invA') and movement_type = 'store_sale';
  perform public.refund_invoice_recorded(pg_temp.fx('invA'), jsonb_build_array(jsonb_build_object('invoice_item_id', it, 'amount', 40)),
    jsonb_build_array(jsonb_build_object('payment_id', pay, 'amount', 40)),
    jsonb_build_array(jsonb_build_object('movement_id', mv, 'not_returned_quantity', 1)), 'T437 part refund after the link', gen_random_uuid());
end $$;
select pg_temp.check((select count(*) from commissions where invoice_id = pg_temp.fx('invA') and status::text = 'reversed'
                        and invoice_paid_date = sg_today()) = 2
    and exists (select 1 from commissions where invoice_id = pg_temp.fx('invA') and tier::text = 'tier1' and status::text = 'earned'
                  and commission_amount = 9.00 and line_amount = 60.00 and referrer_customer_id = pg_temp.fx('cRef')
                  and invoice_paid_date = date '2026-09-15')
    and (select sum(commission_amount) from commissions where invoice_id = pg_temp.fx('invA') and status::text = 'earned' and tier::text = 'tier1') = 9.00,
  'EL afterwards a part refund on A (the engine''s reconcile) reverses the Link-day rows and dates what it earns again by A''s paid day, 15 Sep 2026 (S$9.00)');
-- The engine's own later work on an invoice Link earned (a correction, a
-- refund: reconcile_invoice_commissions) finds rows there, as for any
-- invoice: Link never earns an invoice twice.
-- Noor has no referrer: Link moves her paid invoice and earns nothing.
insert into tx values ('link_nor', public.link_affiliate_signup((pg_temp.entry('lNor')).id, pg_temp.fx('cNor'), null, gen_random_uuid(), false)::text);
select pg_temp.check((pg_temp.tx('link_nor')::jsonb->>'ok')::boolean
    and (select customer_id from invoices where id = pg_temp.fx('invN')) = pg_temp.fx('cNor')
    and not exists (select 1 from commissions where invoice_id = pg_temp.fx('invN'))
    and pg_temp.tx('link_nor')::jsonb->'commission_earned' = '[]'::jsonb
    and pg_temp.tx('link_nor')::jsonb->'commission_not_earned' = '[]'::jsonb
    and pg_temp.tx('link_nor')::jsonb->'commission_dated' = 'null'::jsonb,
  'EL a customer with no referrer (Noor): her paid invoice moves and earns nothing: ' || pg_temp.tx('link_nor'));

-- ═════ FJ A phone-only join under another name (AFF-SIGNUP-18) ═════
-- Rina signs up on her mother's phone, the only customer with it: she is let
-- into the mother's account (7, unchanged), and the list says she may be
-- someone else. Sam signs up on his own phone under his name the other way
-- round: not listed. Ravi on his father's phone: an Owner unlinks the login,
-- and Ravi's next sign-in gives him a record of his own.
do $$ declare c uuid; begin
  insert into customers(full_name, phone) values ('Siew Lan Testfam', '+61491578419') returning id into c; insert into fx values ('cFam', c);
  insert into customers(full_name, phone) values ('Sam Lee Testsame', '+61491578420') returning id into c; insert into fx values ('cSam', c);
  insert into customers(full_name, phone) values ('Kumar Testfather', '+61491578421') returning id into c; insert into fx values ('cFam2', c);
end $$;
select pg_temp.onboard('lFam', 'Rina', 'Testfam', '+61491578419');
select pg_temp.check(pg_temp.ans('lFam')->>'status' = 'active' and (pg_temp.ans('lFam')->>'customer_id')::uuid = pg_temp.fx('cFam')
    and not (pg_temp.ans('lFam')->>'new_customer')::boolean and pg_temp.linked_to('lFam') = pg_temp.fx('cFam')
    and pg_temp.claimed('lFam')->>'rule' = 'phone' and pg_temp.on_phone('+61491578419') = 1
    and not (pg_temp.ans('lFam')::text ~* 'other|listed|Siew|match'),
  'FJ the sign-up''s outcome is as before: joined to the one customer with the phone, no new record, and the person is told nothing: ' || pg_temp.ans('lFam')::text);
select pg_temp.check((pg_temp.entry('lFam')).reason = 'phone_other_name' and (pg_temp.entry('lFam')).status = 'open'
    and (pg_temp.entry('lFam')).fresh_customer_id = pg_temp.fx('cFam') and (pg_temp.entry('lFam')).entered_name = 'Rina Testfam'
    and (pg_temp.entry('lFam')).entered_phone = '+61491578419' and (pg_temp.entry('lFam')).candidate_ids = '{}'::uuid[]
    and pg_temp.claimed('lFam')->>'listed_for_staff' = 'phone_other_name',
  'FJ the typed name is not the record''s: an entry ''phone_other_name'' names the customer joined and the name typed; the audit row says so');
select pg_temp.onboard('lSam', 'Testsame', 'Sam Lee', '+61491578420');
select pg_temp.check(pg_temp.linked_to('lSam') = pg_temp.fx('cSam') and pg_temp.claimed('lSam')->>'rule' = 'phone'
    and pg_temp.entry('lSam') is null and pg_temp.claimed('lSam')->>'listed_for_staff' is null,
  'FJ the same words in another order (Sam): joined on the phone, not listed');
select pg_temp.onboard('lFam2', 'Ravi', 'Testson', '+61491578421');
select pg_temp.as_user('m');
insert into tx values ('list_f', public.affiliate_signup_matches_open()::text);
select pg_temp.check(pg_temp.listed('list_f', 'lFam')->>'kind' = 'may_be_someone_else'
    and pg_temp.listed('list_f', 'lFam')->>'reason' = 'phone_other_name'
    and pg_temp.listed('list_f', 'lFam')->>'entered_name' = 'Rina Testfam'
    and pg_temp.listed('list_f', 'lFam')->>'customer_name' = 'Siew Lan Testfam'
    and (pg_temp.listed('list_f', 'lFam')->>'customer_id')::uuid = pg_temp.fx('cFam')
    and pg_temp.listed('list_f', 'lFam')->>'login_email' = pg_temp.mail('lFam')
    and pg_temp.listed('list_f', 'lFam')->'candidates' = '[]'::jsonb
    and not (pg_temp.listed('list_f', 'lFam')->>'twin')::boolean
    and pg_temp.listed('list_f', 'lFam')->'waiting' = 'null'::jsonb
    and pg_temp.listed('list_f', 'lQra')->>'kind' = 'fresh_record',
  'FJ the list shows it as "may be someone else": the name typed and the record''s, and no customer to link');
insert into tx values ('fam_state', (select concat_ws('|', (pg_temp.entry('lFam')).status, pg_temp.linked_to('lFam'),
  (select count(*) from customers where deleted_at is null), (select count(*) from audit_logs where record_id = (pg_temp.entry('lFam')).id))));
select pg_temp.check(public.link_affiliate_signup((pg_temp.entry('lFam')).id, pg_temp.fx('cFam'), null, gen_random_uuid())->>'message'
      like 'This sign-up was joined to the customer on the phone alone, so there is no new record to link.%'
    and public.keep_affiliate_signup_separate((pg_temp.entry('lFam')).id, 'T437 someone else')->>'message'
      like 'This sign-up was joined to the customer on the phone alone, so there is no separate record to keep.%'
    and (select concat_ws('|', (pg_temp.entry('lFam')).status, pg_temp.linked_to('lFam'),
          (select count(*) from customers where deleted_at is null), (select count(*) from audit_logs where record_id = (pg_temp.entry('lFam')).id)))
        = pg_temp.tx('fam_state'),
  'FJ Link and Keep separate are refused for it, and change nothing');
select pg_temp.as_user('s');
select pg_temp.check(pg_temp.err(format('select public.confirm_affiliate_signup_same_person(%L, %L)', (pg_temp.entry('lFam')).id, 'T437')) like '42501%',
  'FJ Staff cannot answer Same person (42501)');
select pg_temp.as_user('m');
select pg_temp.check(pg_temp.err(format('select public.confirm_affiliate_signup_same_person(%L, %L)', (pg_temp.entry('lFam')).id, ' ')) like '%Say how%'
    and public.confirm_affiliate_signup_same_person((pg_temp.entry('lQra')).id, 'T437')->>'message' like 'Same person is only for%'
    and (pg_temp.entry('lQra')).status = 'open',
  'FJ Same person needs a note, and is only for a phone-only join (a fresh record''s entry is refused, unchanged)');
insert into tx values ('same1', public.confirm_affiliate_signup_same_person((pg_temp.entry('lFam')).id, 'T437 called them: Rina is her other name')::text);
select pg_temp.check((pg_temp.tx('same1')::jsonb->>'ok')::boolean
    and (pg_temp.entry('lFam')).status = 'same_person' and (pg_temp.entry('lFam')).decided_by = pg_temp.fx('m')
    and (pg_temp.entry('lFam')).decision_note = 'T437 called them: Rina is her other name'
    and pg_temp.linked_to('lFam') = pg_temp.fx('cFam')
    and exists (select 1 from audit_logs where action = 'affiliate_signup_same_person' and record_id = (pg_temp.entry('lFam')).id
                  and actor_role = 'manager' and module = 'affiliate' and reason = 'T437 called them: Rina is her other name'
                  and new_data->>'entered_name' = 'Rina Testfam' and new_data->>'customer_name' = 'Siew Lan Testfam')
    and not exists (select 1 from jsonb_array_elements(public.affiliate_signup_matches_open()) e
                     where (e->>'match_id')::uuid = (pg_temp.entry('lFam')).id),
  'FJ a Manager answers Same person with a note: the entry is closed (audited), the login stays on the record, and it leaves the list');
select pg_temp.check(public.confirm_affiliate_signup_same_person((pg_temp.entry('lFam')).id, 'again')->>'message' like 'This sign-up was checked already%',
  'FJ a second answer is refused');
-- Someone else: an Owner unlinks Ravi's login from his father's record.
select pg_temp.as_user('o');
insert into tx values ('fam2_entry', (pg_temp.entry('lFam2')).id::text);
select pg_temp.check((pg_temp.entry('lFam2')).reason = 'phone_other_name' and pg_temp.linked_to('lFam2') = pg_temp.fx('cFam2'),
  'FJ setup: Ravi is joined to his father''s record, listed "may be someone else"');
insert into tx values ('unlink_fam2', coalesce(pg_temp.err(format('select public.unlink_affiliate_account(%L, %L)', pg_temp.fx('cFam2'),
  'T437 it is his son')), 'ok'));
select pg_temp.check(pg_temp.tx('unlink_fam2') = 'ok'
    and not exists (select 1 from jsonb_array_elements(public.affiliate_signup_matches_open()) e
                     where e->>'match_id' = pg_temp.tx('fam2_entry')),
  'FJ an Owner unlinks the login (378): the entry leaves the list');
select pg_temp.onboard('lFam2', 'Ravi', 'Testson', '+61491578421');
select pg_temp.check(pg_temp.ans('lFam2')->>'status' = 'active' and (pg_temp.ans('lFam2')->>'new_customer')::boolean
    and pg_temp.linked_to('lFam2') <> pg_temp.fx('cFam2')
    and (select full_name from customers where id = pg_temp.linked_to('lFam2')) = 'Ravi Testson'
    and (pg_temp.entry('lFam2')).reason = 'protected_customer' and (pg_temp.entry('lFam2')).candidate_ids @> array[pg_temp.fx('cFam2')]
    and not exists (select 1 from affiliate_signup_matches where id = pg_temp.tx('fam2_entry')::uuid)
    and (select count(*) from affiliate_signup_matches where auth_user_id = pg_temp.fx('lFam2') and status = 'open') = 1,
  'FJ at his next sign-in Ravi gets a record of his own (listed with his father''s, protected now); the stale entry goes: ' || pg_temp.ans('lFam2')::text);

-- ═════ U Signed in for real ═════
do $$
declare r jsonb; v_out text := ''; q text; v_uid uuid := pg_temp.fx('lU');
begin
  perform set_config('request.jwt.claim.sub', v_uid::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform set_config('request.jwt.claims', '', true);
  execute 'set local role authenticated';
  r := public.complete_affiliate_onboarding('Uma', 'Testreal', '+61491579212', true);
  foreach q in array array['select public.affiliate_signup_candidates(null, null, null, null)',
                           'select public.affiliate_signup_match_kinds(null, null, null, null)',
                           'select public.affiliate_session_from_email_link()',
                           'select public.affiliate_email_verification_needed(null)',
                           'select public.affiliate_signup_fresh_history(null, null)',
                           'select count(*) from public.affiliate_signup_matches'] loop
    begin
      execute q;
      v_out := v_out || 'callable ';
    exception when insufficient_privilege then v_out := v_out || 'refused ';
    end;
  end loop;
  execute 'reset role';
  insert into tx values ('u_onb', r::text), ('u_out', v_out);
end $$;
select pg_temp.check(pg_temp.tx('u_onb')::jsonb->>'status' = 'active' and pg_temp.linked_to('lU') is not null,
  'U signed in for real (role authenticated), sign-up works: ' || pg_temp.tx('u_onb'));
select pg_temp.check(pg_temp.tx('u_out') = 'refused refused refused refused refused refused ',
  'U the helpers and the list table are closed to a signed-in login: ' || pg_temp.tx('u_out'));
select pg_temp.check(not has_function_privilege('anon', p.oid, 'execute'),
  'G anon cannot call ' || p.oid::regprocedure::text)
  from pg_proc p where p.pronamespace = 'public'::regnamespace
   and p.proname in ('affiliate_session_from_email_link', 'affiliate_signup_candidates', 'affiliate_signup_match_kinds',
                     'affiliate_email_verification_needed', 'confirm_affiliate_email', 'complete_affiliate_onboarding',
                     'affiliate_signup_fresh_history', 'invite_user_provisioned',
                     'affiliate_signup_matches_open', 'link_affiliate_signup', 'keep_affiliate_signup_separate',
                     'confirm_affiliate_signup_same_person');

-- ═════ I A sign-up login and a staff invitation ═════
-- Someone signs up as an affiliate on an address that is not theirs (437
-- confirms it at once), never finishes, and writes "invited_to" into their
-- own metadata. An Owner then invites that address as a Manager. The
-- server (admin-invite-user, with the service key) is offered that login.
do $$
declare sfx text := pg_temp.tx('sfx'); u uuid; k text;
begin
  foreach k in array array['lSq', 'lSq2', 'lPlain'] loop
    u := gen_random_uuid(); insert into fx values (k, u);
    insert into auth.users(id, email, email_confirmed_at, raw_app_meta_data, raw_user_meta_data)
    values (u, 't437-' || lower(k) || '-' || sfx || '@example.com', now(),
            case when k = 'lPlain' then '{"provider": "email"}'::jsonb
                 else '{"provider": "email", "affiliate_email_unverified": true}'::jsonb end,
            '{"invited_to": "energia_internal"}'::jsonb);
    insert into user_invitations(request_id, email, email_normalized, full_name, role, status, work_phone, personal_phone, personal_email, invited_by)
    values ('t437-inv-' || lower(k) || '-' || sfx, 't437-' || lower(k) || '-' || sfx || '@example.com',
            't437-' || lower(k) || '-' || sfx || '@example.com', 'T437 Invitee ' || k, 'manager', 'pending',
            '+61491579212', '+61491579455', 't437-personal-' || lower(k) || '@example.com', pg_temp.fx('o'))
    returning id into u;
    insert into fx values ('inv_' || k, u);
  end loop;
end $$;
-- As admin-invite-user calls it: the service key, no one signed in. (Each
-- answer is kept first, so the checks after it see what it wrote.)
select set_config('request.jwt.claims', '', true), set_config('request.jwt.claim.sub', '', true),
       set_config('request.jwt.claim.role', 'service_role', true);
insert into tx values ('prov_sq', public.invite_user_provisioned(pg_temp.fx('inv_lSq'), pg_temp.fx('lSq'))::text);
select pg_temp.check(pg_temp.tx('prov_sq')::jsonb->>'outcome' = 'login_in_use'
    and not exists (select 1 from profiles where id = pg_temp.fx('lSq'))
    and (select auth_user_id from user_invitations where id = pg_temp.fx('inv_lSq')) is null,
  'I a login the affiliate sign-up made, its email not verified, is not given to a staff invitation (login_in_use), and no profile is made');
select pg_temp.as_user('lSq');
select pg_temp.check(pg_temp.err('select public.require_active_staff(array[''owner'', ''manager''])') is not null,
  'I so it never becomes staff');
update user_invitations set status = 'cancelled', cancelled_at = now() where id = pg_temp.fx('inv_lSq2');
select set_config('request.jwt.claims', '', true), set_config('request.jwt.claim.sub', '', true),
       set_config('request.jwt.claim.role', 'service_role', true);
insert into tx values ('prov_sq2', public.invite_user_provisioned(pg_temp.fx('inv_lSq2'), pg_temp.fx('lSq2'))::text);
select pg_temp.check(pg_temp.tx('prov_sq2')::jsonb->>'outcome' = 'cancelled'
    and (select auth_user_id from user_invitations where id = pg_temp.fx('inv_lSq2')) = pg_temp.fx('lSq2')
    and not exists (select 1 from profiles where id = pg_temp.fx('lSq2')),
  'I the invitation cancelled while it was set up: such a login still gets no (cancelled) profile, which a later invitation could reuse');
insert into tx values ('prov_plain', public.invite_user_provisioned(pg_temp.fx('inv_lPlain'), pg_temp.fx('lPlain'))::text);
select pg_temp.check(pg_temp.tx('prov_plain')::jsonb->>'outcome' = 'provisioned'
    and exists (select 1 from profiles where id = pg_temp.fx('lPlain') and invitation_status = 'pending'),
  'I an ordinary login (no sign-up mark) is provisioned as before: ' || pg_temp.tx('prov_plain'));
insert into tx values ('prov_solo', public.invite_user_provisioned(pg_temp.fx('inv_lPlain'), pg_temp.fx('lSolo'))::text);
select pg_temp.check(pg_temp.tx('prov_solo')::jsonb->>'outcome' = 'login_in_use'
    and not exists (select 1 from profiles where id = pg_temp.fx('lSolo')),
  'I a verified affiliate''s login is still refused, as before (429)');

-- ═════ M 437 twice, and its self-test ═════
\if :{?nomig}
\else
select pg_temp.check((select fp from fp1) = (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.oid::regprocedure::text))
    from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p')),
  'M a second run of 437 changes no function');
\endif
select pg_temp.check(not exists (select 1 from auth.users where email like '437-check-%')
    and not exists (select 1 from customers where full_name like '437 Check%'),
  'M 437''s self-test left no row');

do $$
declare n int; m text;
begin
  select count(*), string_agg(msg, E'\n  ') into n, m from failed;
  if n > 0 then raise exception E'straight-in-437: % check(s) failed:\n  %', n, m; end if;
  raise notice 'straight-in-437: all checks passed';
end $$;
rollback;
