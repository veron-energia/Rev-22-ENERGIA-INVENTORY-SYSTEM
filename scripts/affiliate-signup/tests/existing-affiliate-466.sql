-- An affiliate sign-up with the email or phone of an existing affiliate is sent
-- to Sign in, and nothing is made (466; the Owner, 24 Oct 2026). What the
-- sign-up function (auth-signup-request) asks before it makes a login:
-- affiliate_signup_existing(phone, email, name, request id).
--
--   E  Email: an affiliate's login email (in other case): 'email', login_email,
--      no hint; her record's email, the email she signed up with after she
--      changed her login email: 'email', not login_email, the masked login
--      email; a staff login's email, or a sign-up never finished (a login
--      with no affiliate account), with or without an affiliate's phone:
--      nothing (the sign-up function's own email_in_use answers it) and no
--      Audit Log row; the email first when both match. A Gmail login spelt
--      another way (dots, a +tag, googlemail), an affiliate's or staff's
--      alike: nothing (a new email; the answers are the same); her record's
--      Gmail address typed as it is, though a login has that inbox spelt
--      otherwise: 'email'; a record's Gmail inbox no login has, spelt
--      another way: 'email'.
--   P  Phone: the phone an affiliate signed up with (440's copy) and the phone
--      on her record, after staff changed it; in other forms (+65, spaces,
--      no country code, 00 for +), as the app normalises; a legacy 8-digit
--      number that could be Singapore or Malaysia, by either reading (h);
--      one affiliate: the hint; two affiliates on one phone: no hint.
--   D  A closed, suspended, banned, not yet verified affiliate still counts (d).
--   N  Not an affiliate: a customer with no login, a customer with an
--      affiliate record and no login, a phone and email nobody has: nothing,
--      and the sign-up goes on as before (437's rule 7 joins their record).
--   H  A household phone (i): a customer of her own on an affiliate's phone,
--      with no login, typing her record's name (in any case or word order):
--      nothing, no Audit Log row, and her sign-up then joins her own record
--      (437's 8); with no name, a stranger's name, the affiliate's own name,
--      the name of a deleted record, or an affiliate's sign-up name that
--      staff changed on her record but that a second record of hers holds:
--      phone, as anyone else; an affiliate's email still comes first.
--   K  The mask: first character, "•••", @, the whole domain; a
--      one-character part: "•••@domain"; a login email stored in capitals is
--      shown in lower case; a domain the page would not show (a letter
--      outside a-z): no hint, and the Audit Log says none was shown.
--   A  The Audit Log: one row per affiliate matched by what was answered, on
--      her record, as "System", with what matched and the sign-up function's
--      request id; Owners see it on the Audit Log page (module affiliate).
--      None when nothing is told.
--   Z  Nothing is made by any call: no login, customer, affiliate record,
--      account, claim, list entry or copy; only Audit Log rows.
--   G  Grants: the service role's alone; a signed-in or signed-out caller is
--      refused.
--   M  466 twice changes nothing; its self-test left no row (when this suite
--      installs it).
--
-- Disposable database only; everything is rolled back. Needs 437 and 440 as
-- production has them. Run from the repository root:
--   psql -X -v ON_ERROR_STOP=1 -f scripts/affiliate-signup/tests/existing-affiliate-466.sql
-- (with -v skip_install=1 on a database where 466 is applied, to skip
-- installing it).
-- Every name, phone and email below is invented: ACMA fictional mobile numbers
-- (+61491570470..489), two Singapore-format test numbers no customer holds,
-- @example.com addresses and random @gmail.com test addresses.
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
create function pg_temp.mail(tag text) returns text language sql as
$$ select 't466-' || lower(tag) || '-' || pg_temp.tx('sfx') || '@example.com' $$;
-- A login, as the sign-up function makes it (confirmed, marked unverified).
create function pg_temp.login(key text, email text default null, meta jsonb default '{}'::jsonb) returns uuid language plpgsql as
$$declare u uuid := gen_random_uuid(); begin
  insert into auth.users(id, email, email_confirmed_at, raw_app_meta_data, raw_user_meta_data)
  values (u, coalesce(email, pg_temp.mail(key)), now(), '{"provider": "email", "affiliate_email_unverified": true}'::jsonb, meta);
  perform pg_temp.putx(key, u);
  return u;
end$$;
-- The sign-up the pages run, as the login (437/440, unchanged by 466).
create function pg_temp.onboard(key text, first text, last text, phone text) returns jsonb language plpgsql as
$$declare r jsonb; begin
  perform pg_temp.as_user(key);
  begin
    r := public.complete_affiliate_onboarding(first, last, phone, true);
  exception when others then r := jsonb_build_object('error', sqlstate || ' ' || sqlerrm);
  end;
  perform pg_temp.put('onb:' || key, r::text);
  perform pg_temp.as_user('o');
  return r;
end$$;
create function pg_temp.ans(key text) returns jsonb language sql as $$ select pg_temp.tx('onb:' || key)::jsonb $$;
create function pg_temp.cust(key text) returns uuid language sql as $$ select (pg_temp.ans(key)->>'customer_id')::uuid $$;
create function pg_temp.account(key text) returns uuid language sql as
$$ select id from public.affiliate_accounts where auth_user_id = pg_temp.fx(key) $$;
-- What the sign-up function asks (with the service key). Keeps the answer under 'ex:<tag>',
-- and the Audit Log rows that call wrote in exlog (every row of the action already there is
-- marked 'pre' first, so a call's rows are the new ones).
create temp table exlog(tag text, id uuid primary key);
create function pg_temp.ex(tag text, phone text, email text, name text default null) returns jsonb language plpgsql as
$$declare r jsonb; q uuid := gen_random_uuid(); begin
  perform pg_temp.put('email:' || tag, email);
  perform pg_temp.put('req:' || tag, q::text);
  insert into exlog select 'pre', l.id from public.audit_logs l
   where l.action = 'affiliate_signup_sent_to_sign_in' and not exists (select 1 from exlog x where x.id = l.id);
  perform pg_temp.as_service();
  begin
    r := public.affiliate_signup_existing(phone, email, name, q);
  exception when others then r := jsonb_build_object('error', sqlstate || ' ' || sqlerrm);
  end;
  perform pg_temp.put('ex:' || tag, r::text);
  insert into exlog select tag, l.id from public.audit_logs l
   where l.action = 'affiliate_signup_sent_to_sign_in' and not exists (select 1 from exlog x where x.id = l.id);
  perform pg_temp.as_user('o');
  return r;
end$$;
create function pg_temp.e(tag text) returns jsonb language sql as $$ select pg_temp.tx('ex:' || tag)::jsonb $$;
create function pg_temp.logs(tag text) returns int language sql as $$ select count(*)::int from exlog where exlog.tag = $1 $$;
-- The answer the sign-up function reads: what matched, login email or not, the hint, how many.
create function pg_temp.is(tag text, matched text, login_email boolean, hint text, n int) returns boolean language sql as
$$ select pg_temp.e(tag) = jsonb_build_object('matched', matched, 'login_email', login_email, 'email_hint', hint, 'affiliates', n) $$;
create function pg_temp.nothing(tag text) returns boolean language sql as
$$ select pg_temp.is(tag, null, false, null, 0) and pg_temp.logs(tag) = 0 $$;
-- The Audit Log row a call wrote on an affiliate's record.
create function pg_temp.logrow(tag text, key text) returns public.audit_logs language sql as
$$ select l.* from exlog x join public.audit_logs l on l.id = x.id
    where x.tag = $1 and (l.new_data->>'auth_user_id')::uuid = pg_temp.fx(key) $$;
-- What a sign-up could make, counted.
create function pg_temp.made() returns jsonb language sql as
$$ select jsonb_build_object('users', (select count(*) from auth.users), 'customers', (select count(*) from public.customers),
     'affiliates', (select count(*) from public.customer_affiliates), 'accounts', (select count(*) from public.affiliate_accounts),
     'claims', (select count(*) from public.affiliate_account_claims), 'matches', (select count(*) from public.affiliate_signup_matches),
     'copies', (select count(*) from public.affiliate_signup_identities)) $$;

-- ═════ P0, and 466 ═════
do $$ begin insert into tx values ('sfx', lower(substr(md5(random()::text || clock_timestamp()::text), 1, 6))); end $$;
select pg_temp.check(not exists (select 1 from public.customers c
                                  where public.normalize_customer_phone(c.phone) like '+6149157047_'
                                     or public.normalize_customer_phone(c.phone) like '+6149157048_'
                                     or public.normalize_customer_phone(c.phone) in ('+6591230466', '+6584370466', '+6084370466')
                                     or (public.inspect_customer_phone(c.phone)->'candidates') ?| array['+6591230466', '+6584370466', '+6084370466'])
    and not exists (select 1 from public.affiliate_signup_identities i
                     where public.normalize_customer_phone(i.phone) like '+6149157047_'
                        or public.normalize_customer_phone(i.phone) like '+6149157048_'
                        or public.normalize_customer_phone(i.phone) in ('+6591230466', '+6584370466', '+6084370466')),
  'P0 no customer or sign-up copy uses the test phones (+61491570470..489, +6591230466, 84370466; the checks assume so)');

\if :{?skip_install}
select pg_temp.check(to_regprocedure('public.affiliate_signup_existing(text,text,text,uuid)') is not null, 'P1 466 is installed (skip_install)');
\else
select pg_temp.check(to_regprocedure('public.affiliate_signup_existing(text,text,text,uuid)') is null,
  'P1 466 is not installed yet (this suite installs it; use -v skip_install=1 where it is)');
\ir ../../../supabase/466_existing_affiliate_sent_to_sign_in.sql
create temp table fp466 as select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.oid::regprocedure::text)) fp
  from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p');
\ir ../../../supabase/466_existing_affiliate_sent_to_sign_in.sql
select pg_temp.check((select fp from fp466) = (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.oid::regprocedure::text))
    from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p')),
  'M1 a second run of 466 changes no function');
select pg_temp.check(not exists (select 1 from auth.users where email like 'z466-check-%')
    and not exists (select 1 from public.customers where full_name like '466 Check%' or email like 'z466-record-%')
    and not exists (select 1 from public.audit_logs where action = 'affiliate_signup_sent_to_sign_in'
                      and new_data->>'email' like '%z466-check-%'),
  'M2 466''s self-test left no row');
\endif
select pg_temp.check(md5(pg_get_functiondef('public.affiliate_signup_existing(text,text,text,uuid)'::regprocedure)) = '27e3b1ad5a583bc6421d783b5a7db45a',
  'M3 affiliate_signup_existing has 466''s AFTER md5');

-- ═════ Fixtures ═════
-- Staff, and a member of staff's login.
do $$
declare k text; u uuid;
begin
  foreach k in array array['o', 's'] loop
    u := gen_random_uuid(); insert into fx values (k, u);
    insert into auth.users(id, email, email_confirmed_at) values (u, pg_temp.mail('staff-' || k), now());
  end loop;
  insert into profiles(id, full_name, email, role) values
    (pg_temp.fx('o'), 'T466 Owner', pg_temp.mail('staff-o'), 'owner'),
    (pg_temp.fx('s'), 'T466 Staff', pg_temp.mail('staff-s'), 'staff');
end $$;
select pg_temp.as_user('o');

-- Ava: an affiliate through the real sign-up (a new customer), then staff change her record's phone and email.
select pg_temp.login('lAva');
select pg_temp.onboard('lAva', 'Ava', 'Testaffiliate', '+61 491 570 471');
update public.customers set phone = '+61491570472', email = pg_temp.mail('ava-record') where id = pg_temp.cust('lAva');
-- Bo: an affiliate whose account is closed: record suspended, account disabled, login banned, email not verified.
select pg_temp.login('lBo', 'b.Test-Bo-' || pg_temp.tx('sfx') || '@Example.COM');
select pg_temp.onboard('lBo', 'Bo', 'Testclosed', '+61491570473');
update public.customer_affiliates set manually_suspended = true, status = 'suspended_manual', suspended_at = now(),
       suspend_reason = 'T466 test' where customer_id = pg_temp.cust('lBo');
update public.affiliate_accounts set status = 'disabled' where auth_user_id = pg_temp.fx('lBo');
update public.customers set is_active = false where id = pg_temp.cust('lBo');
update auth.users set banned_until = now() + interval '100 years' where id = pg_temp.fx('lBo');
-- Cy and Di: two affiliates on one household phone (Di's sign-up gets a fresh record: Cy's has a login).
select pg_temp.login('lCy', 'x@t466-' || pg_temp.tx('sfx') || '.example.com');
select pg_temp.onboard('lCy', 'Cy', 'Testhousehold', '+61491570474');
select pg_temp.login('lDi');
select pg_temp.onboard('lDi', 'Di', 'Testhousehold', '+61491570474');
-- Gus: changed his login email after signing up (his record and copy keep the old one).
select pg_temp.login('lGus', pg_temp.mail('gus'));
select pg_temp.onboard('lGus', 'Gus', 'Testmoved', '+61491570476');
update auth.users set email = 'g.new-' || pg_temp.tx('sfx') || '@example.com' where id = pg_temp.fx('lGus');
-- Gem: a Gmail login; staff wrote her record's email without the dots (the same inbox).
select pg_temp.login('lGem', 's466.gem.' || pg_temp.tx('sfx') || '@gmail.com');
select pg_temp.onboard('lGem', 'Gem', 'Testgmail', '+61491570477');
update public.customers set email = 's466gem' || pg_temp.tx('sfx') || '@gmail.com' where id = pg_temp.cust('lGem');
-- A member of staff with a Gmail login.
do $$ declare u uuid := gen_random_uuid(); begin
  insert into fx values ('sg', u);
  insert into auth.users(id, email, email_confirmed_at) values (u, 's466.staff.' || pg_temp.tx('sfx') || '@gmail.com', now());
  insert into profiles(id, full_name, email, role) values (u, 'T466 Gmailstaff', 's466.staff.' || pg_temp.tx('sfx') || '@gmail.com', 'staff');
end $$;
-- Sia: signed up with a Singapore-format number; her record holds it without the country code.
select pg_temp.login('lSia');
select pg_temp.onboard('lSia', 'Sia', 'Testsg', '+6591230466');
do $$ begin
  set local session_replication_role = replica;
  update public.customers set phone = '91230466' where id = pg_temp.cust('lSia');
  set local session_replication_role = origin;
end $$;
-- May: her record holds a legacy 8-digit number that could be Singapore or Malaysia.
select pg_temp.login('lMay');
select pg_temp.onboard('lMay', 'May', 'Testlegacy', '+61491570478');
do $$ begin
  set local session_replication_role = replica;
  update public.customers set phone = '84370466' where id = pg_temp.cust('lMay');
  set local session_replication_role = origin;
end $$;
-- Not affiliates: Nia, a customer with no login; Ed, a customer with an affiliate record and no login;
-- Stu, a login whose sign-up never finished (no affiliate account), with a phone in its metadata.
do $$ declare c uuid; begin
  insert into customers(full_name, phone, email) values ('Nia Testcustomer', '+61491570480', pg_temp.mail('nia-record')) returning id into c;
  insert into fx values ('cNia', c);
  insert into customers(full_name, phone) values ('Ed Testrecordonly', '+61491570481') returning id into c;
  insert into fx values ('cEd', c);
  insert into customer_affiliates(customer_id, status, activated_at, referral_code) values (c, 'active', now(), upper('T466E' || pg_temp.tx('sfx')));
end $$;
select pg_temp.login('lStu', null, jsonb_build_object('first_name', 'Stu', 'last_name', 'Teststuck', 'phone', '+61491570482'));
-- A household phone (i): Ivy, an affiliate; Jo, her sister, a customer of her own on it with no login;
-- Lu, a deleted record on it.
select pg_temp.login('lIvy');
select pg_temp.onboard('lIvy', 'Ivy', 'Testhome', '+61491570483');
update public.customers set email = pg_temp.mail('ivy-record') where id = pg_temp.cust('lIvy');
do $$ declare c uuid; begin
  insert into customers(full_name, phone) values ('Jo Ann Testhome', '+61491570483') returning id into c;
  insert into fx values ('cJo', c);
  insert into customers(full_name, phone) values ('Lu Testhome', '+61491570483') returning id into c;
  insert into fx values ('cLu', c);
  update customers set deleted_at = now() where id = c;
end $$;
-- Kai: an affiliate whose record staff renamed (his sign-up copy keeps "Kai Testtwin"), with a second
-- record of his under that name on his phone, no login.
select pg_temp.login('lKai');
select pg_temp.onboard('lKai', 'Kai', 'Testtwin', '+61491570484');
update public.customers set full_name = 'Kaiden Testtwin' where id = pg_temp.cust('lKai');
insert into customers(full_name, phone) values ('Kai Testtwin', '+61491570484');
-- ... and staff put a Gmail address on Kai's record that no login has.
update public.customers set email = 's466.kai.' || pg_temp.tx('sfx') || '@gmail.com' where id = pg_temp.cust('lKai');
-- Uma: her login email moved to a domain with a letter outside a-z (the page would not show its mask).
select pg_temp.login('lUma');
select pg_temp.onboard('lUma', 'Uma', 'Testidn', '+61491570485');
update auth.users set email = 'u.test-uma-' || pg_temp.tx('sfx') || '@t466-ü.example.com' where id = pg_temp.fx('lUma');

select pg_temp.check(pg_temp.ans('lAva')->>'status' = 'active' and (pg_temp.ans('lAva')->>'new_customer')::boolean
    and pg_temp.ans('lBo')->>'status' = 'active' and pg_temp.ans('lCy')->>'status' = 'active'
    and pg_temp.ans('lDi')->>'status' = 'active' and pg_temp.cust('lDi') <> pg_temp.cust('lCy')
    and pg_temp.ans('lGus')->>'status' = 'active' and pg_temp.ans('lGem')->>'status' = 'active'
    and pg_temp.ans('lSia')->>'status' = 'active' and pg_temp.ans('lMay')->>'status' = 'active'
    and pg_temp.ans('lIvy')->>'status' = 'active' and (pg_temp.ans('lIvy')->>'new_customer')::boolean
    and pg_temp.ans('lKai')->>'status' = 'active' and (pg_temp.ans('lKai')->>'new_customer')::boolean
    and pg_temp.ans('lUma')->>'status' = 'active'
    and (select deleted_at from customers where id = pg_temp.fx('cLu')) is not null
    and public.normalize_customer_phone((select phone from customers where id = pg_temp.cust('lSia'))) = '+6591230466'
    and public.normalize_customer_phone((select phone from customers where id = pg_temp.cust('lMay'))) is null
    and (select phone from affiliate_signup_identities where auth_user_id = pg_temp.fx('lAva')) = '+61 491 570 471',
  'F0 the fixtures: eleven affiliates through the real sign-up (Di on a fresh record beside Cy), as described: '
  || coalesce(pg_temp.tx('onb:lAva'), '') || ' ' || coalesce(pg_temp.tx('onb:lDi'), ''));

create temp table made0 as select pg_temp.made() m;

-- ═════ E Email ═════
select pg_temp.ex('e1', '+61491570489', upper(pg_temp.mail('lAva')));
select pg_temp.check(pg_temp.is('e1', 'email', true, null, 1) and pg_temp.logs('e1') = 1,
  'E1 Ava''s login email, in capitals, with a phone nobody has: email, her login email itself, no hint (the page fills it in): '
  || pg_temp.tx('ex:e1'));
select pg_temp.ex('e2', '+61491570489', pg_temp.mail('ava-record'));
select pg_temp.check(pg_temp.is('e2', 'email', false, 't•••@example.com', 1) and pg_temp.logs('e2') = 1,
  'E2 the email staff put on Ava''s record: email, not her login''s, with her masked login email: ' || pg_temp.tx('ex:e2'));
select pg_temp.ex('e3', '+61491570489', pg_temp.mail('gus'));
select pg_temp.check(pg_temp.is('e3', 'email', false, 'g•••@example.com', 1)
    and (pg_temp.logrow('e3', 'lGus')).new_data->'matched' = '["signup_email", "record_email"]'::jsonb,
  'E3 the email Gus signed up with, after he changed his login email: email (his copy and his record), the hint of his NEW login email: '
  || pg_temp.tx('ex:e3'));
select pg_temp.ex('e4', '+61491570489', 's466gem' || pg_temp.tx('sfx') || '+join@googlemail.com');
select pg_temp.ex('e4s', '+61491570489', 's466staff' || pg_temp.tx('sfx') || '+join@googlemail.com');
select pg_temp.ex('e4t', '+61491570489', 'S466.Staff.' || pg_temp.tx('sfx') || '@gmail.com');
select pg_temp.check(pg_temp.nothing('e4') and pg_temp.nothing('e4s') and pg_temp.nothing('e4t')
    and pg_temp.e('e4') = pg_temp.e('e4s'),
  'E4 Gem''s Gmail login spelt another way (no dots, a +tag, googlemail), and a staff Gmail login spelt the same way: '
  || 'nothing for both (a new email; the answer does not tell an affiliate''s login from staff''s), no Audit Log row; '
  || 'the staff address itself: nothing (email_in_use): ' || pg_temp.tx('ex:e4') || ' ' || pg_temp.tx('ex:e4s'));
select pg_temp.ex('e4r', '+61491570489', 's466gem' || pg_temp.tx('sfx') || '@gmail.com');
select pg_temp.check(pg_temp.is('e4r', 'email', false, 's•••@gmail.com', 1)
    and (pg_temp.logrow('e4r', 'lGem')).new_data->'matched' = '["record_email"]'::jsonb,
  'E4r the Gmail address on Gem''s record, typed as it is (her login has that inbox with dots): email, her record''s, with the hint: '
  || pg_temp.tx('ex:e4r'));
select pg_temp.ex('e4k', '+61491570489', 's466kai' || pg_temp.tx('sfx') || '+x@googlemail.com');
select pg_temp.check(pg_temp.is('e4k', 'email', false, 't•••@example.com', 1)
    and (pg_temp.logrow('e4k', 'lKai')).new_data->'matched' = '["record_email"]'::jsonb,
  'E4k a Gmail inbox on Kai''s record that no login has, spelt another way: email (by inbox), with his hint: ' || pg_temp.tx('ex:e4k'));
select pg_temp.ex('e5', '+61491570489', pg_temp.mail('staff-s'));
select pg_temp.check(pg_temp.nothing('e5'),
  'E5 a staff login''s email: nothing here (the sign-up function''s email_in_use answers it), no Audit Log row');
select pg_temp.ex('e6', '+61491570471', ' ' || pg_temp.mail('staff-s') || ' ');
select pg_temp.check(pg_temp.nothing('e6'),
  'E6 a staff login''s email with Ava''s phone: still nothing here (email_in_use; nothing of Ava is told, so nothing logged)');
select pg_temp.ex('e7', '+61491570471', pg_temp.mail('lStu'));
select pg_temp.check(pg_temp.nothing('e7'),
  'E7 the email of a sign-up never finished (a login, no affiliate account), with Ava''s phone: nothing here (email_in_use)');
select pg_temp.ex('e8', '+61491570473', pg_temp.mail('ava-record'));
select pg_temp.check(pg_temp.is('e8', 'email', false, 't•••@example.com', 1) and pg_temp.logs('e8') = 1
    and (pg_temp.logrow('e8', 'lAva')).new_data->>'answered' = 'email',
  'E8 Ava''s record email with Bo''s phone: the email first (Ava''s hint); only Ava is logged (Bo''s phone was not told)');

-- ═════ P Phone ═════
select pg_temp.ex('p1', '+61491570471', pg_temp.mail('new-p1'), 'Pat Testnew');
select pg_temp.check(pg_temp.is('p1', 'phone', false, 't•••@example.com', 1)
    and (pg_temp.logrow('p1', 'lAva')).new_data->'matched' = '["signup_phone"]'::jsonb,
  'P1 the phone Ava signed up with (staff changed her record''s since), another email: phone, with her masked login email: ' || pg_temp.tx('ex:p1'));
select pg_temp.ex('p2', '+61491570472', pg_temp.mail('new-p2'));
select pg_temp.check(pg_temp.is('p2', 'phone', false, 't•••@example.com', 1)
    and (pg_temp.logrow('p2', 'lAva')).new_data->'matched' = '["record_phone"]'::jsonb,
  'P2 the phone on Ava''s record now: phone, with the hint');
select pg_temp.ex('p3a', '+61 491 570 471', pg_temp.mail('new-p3'));
select pg_temp.ex('p3b', '+61-491-570-472', pg_temp.mail('new-p3'));
select pg_temp.ex('p3c', '0061 491-570-472', pg_temp.mail('new-p3'));
select pg_temp.ex('p3d', '(+61) 491 570 471', pg_temp.mail('new-p3'));
select pg_temp.check(pg_temp.is('p3a', 'phone', false, 't•••@example.com', 1) and pg_temp.is('p3b', 'phone', false, 't•••@example.com', 1)
    and pg_temp.is('p3c', 'phone', false, 't•••@example.com', 1) and pg_temp.is('p3d', 'phone', false, 't•••@example.com', 1),
  'P3 Ava''s phones typed with spaces, with dashes, with 00 for +, with brackets: each the same phone');
select pg_temp.ex('p4a', '+65 9123 0466', pg_temp.mail('new-p4'));
select pg_temp.ex('p4b', '91230466', pg_temp.mail('new-p4'));
select pg_temp.ex('p4c', '6591230466', pg_temp.mail('new-p4'));
select pg_temp.ex('p4d', '0065 9123-0466', pg_temp.mail('new-p4'));
select pg_temp.check(pg_temp.is('p4a', 'phone', false, 't•••@example.com', 1) and pg_temp.is('p4b', 'phone', false, 't•••@example.com', 1)
    and pg_temp.is('p4c', 'phone', false, 't•••@example.com', 1) and pg_temp.is('p4d', 'phone', false, 't•••@example.com', 1)
    and (pg_temp.logrow('p4b', 'lSia')).new_data->'matched' = '["signup_phone", "record_phone"]'::jsonb
    and (pg_temp.logrow('p4b', 'lSia')).new_data->>'phone' = '+6591230466',
  'P4 Sia''s Singapore number (her record holds it with no country code): +65 with spaces, no country code, 65 without +, 00 65: each her phone, the record''s and the copy''s');
select pg_temp.ex('p5a', '+6584370466', pg_temp.mail('new-p5'));
select pg_temp.ex('p5b', '+6084370466', pg_temp.mail('new-p5'));
select pg_temp.check(pg_temp.is('p5a', 'phone', false, 't•••@example.com', 1) and pg_temp.is('p5b', 'phone', false, 't•••@example.com', 1)
    and (pg_temp.logrow('p5a', 'lMay')).new_data->'matched' = '["record_phone_unconfirmed"]'::jsonb,
  'P5 May''s legacy 8-digit record number, by its Singapore reading and by its Malaysia reading: her phone (h)');
select pg_temp.ex('p6', '+61491570474', pg_temp.mail('new-p6'));
select pg_temp.check(pg_temp.is('p6', 'phone', false, null, 2) and pg_temp.logs('p6') = 2
    and (pg_temp.logrow('p6', 'lCy')).record_id = pg_temp.cust('lCy') and (pg_temp.logrow('p6', 'lDi')).record_id = pg_temp.cust('lDi'),
  'P6 the household phone two affiliates have: phone, no hint (a), one Audit Log row on each one''s record');

-- ═════ D Closed, suspended, banned, not verified ═════
select pg_temp.ex('d1', '+61491570473', pg_temp.mail('new-d1'));
select pg_temp.ex('d3', '+61491570489', 'B.TEST-BO-' || pg_temp.tx('sfx') || '@example.com');
select pg_temp.check(pg_temp.is('d1', 'phone', false, 'b•••@example.com', 1) and pg_temp.is('d3', 'email', true, null, 1)
    and (select email_verified_at from affiliate_accounts where auth_user_id = pg_temp.fx('lBo')) is null,
  'D1 Bo (record suspended, account disabled, login banned, email not verified): still an affiliate, by phone (hint in lower case) and by login email: '
  || pg_temp.tx('ex:d1') || ' ' || pg_temp.tx('ex:d3'));

-- ═════ N Not affiliates ═════
select pg_temp.ex('n1', '+61491570480', pg_temp.mail('new-n1'));
select pg_temp.ex('n2', '+61491570489', pg_temp.mail('nia-record'));
select pg_temp.ex('n3', '+61491570481', pg_temp.mail('new-n3'));
select pg_temp.ex('n4', '+61491570482', pg_temp.mail('new-n4'));
select pg_temp.ex('n5', '+61491570489', pg_temp.mail('nobody'));
select pg_temp.check(pg_temp.nothing('n1') and pg_temp.nothing('n2') and pg_temp.nothing('n3') and pg_temp.nothing('n4') and pg_temp.nothing('n5'),
  'N1 Nia''s phone and her email (a customer, no login), Ed''s phone (an affiliate record, no login), Stu''s metadata phone (no account), a phone and email nobody has: nothing, no Audit Log row');
-- ... and they sign up as before: the phone joins their record (437's rule 7).
select pg_temp.login('lNia', pg_temp.mail('new-n1'));
select pg_temp.onboard('lNia', 'Nia', 'Testcustomer', '+61491570480');
select pg_temp.login('lEd', pg_temp.mail('new-n3'));
select pg_temp.onboard('lEd', 'Ed', 'Testrecordonly', '+61491570481');
select pg_temp.check(pg_temp.cust('lNia') = pg_temp.fx('cNia') and not (pg_temp.ans('lNia')->>'new_customer')::boolean
    and pg_temp.cust('lEd') = pg_temp.fx('cEd') and not (pg_temp.ans('lEd')->>'new_customer')::boolean
    and pg_temp.ans('lEd')->>'referral_code' = upper('T466E' || pg_temp.tx('sfx')),
  'N2 Nia and Ed then sign up as before: each joined to their own record on the phone (Ed keeps his affiliate code): '
  || pg_temp.tx('onb:lNia') || ' ' || pg_temp.tx('onb:lEd'));
select pg_temp.ex('n6', '+61491570480', pg_temp.mail('new-n6'));
select pg_temp.check(pg_temp.is('n6', 'phone', false, 't•••@example.com', 1),
  'N3 once Nia is an affiliate, her phone is an affiliate''s: phone, with her hint');

-- ═════ H A household phone (i) ═════
select pg_temp.ex('h1a', '+61491570483', pg_temp.mail('new-jo'), 'Jo Ann Testhome');
select pg_temp.ex('h1b', '+61 491 570 483', pg_temp.mail('new-jo'), '  TESTHOME  jo ann ');
select pg_temp.ex('h1c', '+61491570483', pg_temp.mail('new-jo'), 'Joann Testhome');
select pg_temp.check(pg_temp.nothing('h1a') and pg_temp.nothing('h1b') and pg_temp.nothing('h1c'),
  'H1 Jo (a customer of her own on Ivy''s phone, no login) under her record''s name, as typed, in capitals and another order, with words written together: nothing, no Audit Log row: '
  || pg_temp.tx('ex:h1a') || ' ' || pg_temp.tx('ex:h1b') || ' ' || pg_temp.tx('ex:h1c'));
select pg_temp.ex('h2a', '+61491570483', pg_temp.mail('new-h2'));
select pg_temp.ex('h2b', '+61491570483', pg_temp.mail('new-h2'), '   ');
select pg_temp.ex('h2c', '+61491570483', pg_temp.mail('new-h2'), 'Cara Testother');
select pg_temp.ex('h2d', '+61491570483', pg_temp.mail('new-h2'), 'ivy testhome');
select pg_temp.ex('h2e', '+61491570483', pg_temp.mail('new-h2'), 'Lu Testhome');
select pg_temp.ex('h2f', '+61491570483', pg_temp.mail('new-h2'), 'Jo Testhome');
select pg_temp.check(pg_temp.is('h2a', 'phone', false, 't•••@example.com', 1) and pg_temp.is('h2b', 'phone', false, 't•••@example.com', 1)
    and pg_temp.is('h2c', 'phone', false, 't•••@example.com', 1) and pg_temp.is('h2d', 'phone', false, 't•••@example.com', 1)
    and pg_temp.is('h2e', 'phone', false, 't•••@example.com', 1) and pg_temp.is('h2f', 'phone', false, 't•••@example.com', 1)
    and pg_temp.logs('h2a') = 1 and pg_temp.logs('h2d') = 1
    and (pg_temp.logrow('h2d', 'lIvy')).new_data->>'name' = 'ivy testhome'
    and (pg_temp.logrow('h2a', 'lIvy')).new_data ? 'name' and (pg_temp.logrow('h2a', 'lIvy')).new_data->>'name' is null,
  'H2 Ivy''s phone with no name, a blank name, a stranger''s name (no record on it), Ivy''s own name, the deleted record''s name, a name that is only part of Jo''s: phone, with Ivy''s hint, logged with the name typed');
select pg_temp.ex('h3', '+61491570484', pg_temp.mail('new-h3'), 'Kai Testtwin');
select pg_temp.ex('h3b', '+61491570484', pg_temp.mail('new-h3'), 'Kaiden Testtwin');
select pg_temp.check(pg_temp.is('h3', 'phone', false, 't•••@example.com', 1) and pg_temp.is('h3b', 'phone', false, 't•••@example.com', 1),
  'H3 Kai again on his phone under the name he signed up with (staff renamed his record; a second record of his holds that name, no login), and under his record''s name: phone (sent to Sign in): '
  || pg_temp.tx('ex:h3'));
select pg_temp.ex('h4', '+61491570483', pg_temp.mail('ivy-record'), 'Jo Ann Testhome');
select pg_temp.check(pg_temp.is('h4', 'email', false, 't•••@example.com', 1),
  'H4 Jo''s name with Ivy''s record email: the email first (Ivy''s hint)');
-- ... and Jo then signs up as before: 437 joins her own record, by phone and name.
select pg_temp.login('lJo', pg_temp.mail('new-jo'));
select pg_temp.onboard('lJo', 'Jo Ann', 'Testhome', '+61491570483');
select pg_temp.check(pg_temp.cust('lJo') = pg_temp.fx('cJo') and not (pg_temp.ans('lJo')->>'new_customer')::boolean
    and pg_temp.cust('lJo') <> pg_temp.cust('lIvy')
    and not exists (select 1 from affiliate_signup_matches m where m.auth_user_id = pg_temp.fx('lJo')),
  'H5 Jo then signs up as before: joined to her own record (437''s 8), nothing listed for staff: ' || pg_temp.tx('onb:lJo'));
select pg_temp.ex('h6', '+61491570483', pg_temp.mail('new-h6'), 'Jo Ann Testhome');
select pg_temp.check(pg_temp.is('h6', 'phone', false, null, 2) and pg_temp.logs('h6') = 2,
  'H6 once Jo is an affiliate, her name on the phone is an affiliate''s too: phone, two affiliates, no hint');

-- ═════ K The mask ═════
do $$ begin
  -- Cy alone on a phone of her own (her record's phone changed): a one-character part.
  update public.customers set phone = '+61491570475' where id = pg_temp.cust('lCy');
end $$;
select pg_temp.ex('k3', '+61491570475', pg_temp.mail('new-k3'));
select pg_temp.check(pg_temp.is('k3', 'phone', false, '•••@t466-' || pg_temp.tx('sfx') || '.example.com', 1)
    and pg_temp.is('d1', 'phone', false, 'b•••@example.com', 1)
    and pg_temp.e('p4a')->>'email_hint' = 't•••@example.com',
  'K1 the mask: a one-character part gives "•••@" and the whole domain (subdomains kept); a login email stored in capitals is shown in lower case; otherwise the first character, •••, @, the domain: '
  || pg_temp.tx('ex:k3'));
select pg_temp.ex('k4', '+61491570485', pg_temp.mail('new-k4'));
select pg_temp.check(pg_temp.is('k4', 'phone', false, null, 1)
    and (pg_temp.logrow('k4', 'lUma')).new_data->>'email_hint_shown' = 'false',
  'K3 Uma''s login domain has a letter outside a-z: no hint (the page would not show it), and the Audit Log says none was shown: '
  || pg_temp.tx('ex:k4'));
select pg_temp.check(position(pg_temp.mail('lAva') in pg_temp.tx('ex:p1')) = 0 and position('lava' in pg_temp.tx('ex:p1')) = 0 and position('test-bo' in lower(pg_temp.tx('ex:d1'))) = 0,
  'K2 the answer never carries the login email itself');

-- ═════ A The Audit Log ═════
select pg_temp.check((pg_temp.logrow('p1', 'lAva')).table_name = 'customers'
    and (pg_temp.logrow('p1', 'lAva')).record_id = pg_temp.cust('lAva')
    and (pg_temp.logrow('p1', 'lAva')).module = 'affiliate'
    and (pg_temp.logrow('p1', 'lAva')).changed_by is null
    and (pg_temp.logrow('p1', 'lAva')).new_data - 'matched' = jsonb_build_object('answered', 'phone',
          'affiliate_account_id', pg_temp.account('lAva'), 'auth_user_id', pg_temp.fx('lAva'), 'phone', '+61491570471',
          'email', pg_temp.mail('new-p1'), 'name', 'Pat Testnew', 'email_hint_shown', true, 'affiliates_matched', 1,
          'source', 'affiliate_join', 'request_id', pg_temp.tx('req:p1'), 'version', 466),
  'A1 the row: on Ava''s record (customers), module affiliate, as System, with what was answered and matched, her account and login, the phone, email and name typed, the hint shown, the request id: '
  || coalesce((pg_temp.logrow('p1', 'lAva')).new_data::text, 'none'));
select pg_temp.check((pg_temp.logrow('e1', 'lAva')).new_data->'matched' = '["login_email", "signup_email"]'::jsonb
    and (pg_temp.logrow('e1', 'lAva')).new_data->>'email_hint_shown' = 'false'
    and (pg_temp.logrow('e1', 'lAva')).new_data->>'email' = pg_temp.mail('lAva'),
  'A2 her login email typed: logged too, with what matched (her login and her copy; staff changed her record''s email)');
select pg_temp.check((select (public.audit_log_page(p_module => 'affiliate', p_text => pg_temp.account('lAva')::text, p_limit => 100)->>'total')::int) >= 8
    and (select r->>'actor_name' from jsonb_array_elements(public.audit_log_page(p_module => 'affiliate',
           p_text => pg_temp.account('lAva')::text, p_limit => 1)->'rows') r) = 'System',
  'A3 an Owner sees the rows on the Audit Log page (module affiliate), as System');

-- ═════ Z Nothing is made ═════
select pg_temp.check((select m from made0) - 'users' - 'customers' - 'accounts' - 'copies' - 'affiliates'
      = pg_temp.made() - 'users' - 'customers' - 'accounts' - 'copies' - 'affiliates'
    and ((pg_temp.made()->>'users')::int - ((select m from made0)->>'users')::int) = 3
    and ((pg_temp.made()->>'accounts')::int - ((select m from made0)->>'accounts')::int) = 3
    and ((pg_temp.made()->>'copies')::int - ((select m from made0)->>'copies')::int) = 3
    and ((pg_temp.made()->>'customers')::int - ((select m from made0)->>'customers')::int) = 0
    and ((pg_temp.made()->>'affiliates')::int - ((select m from made0)->>'affiliates')::int) = 2,
  'Z1 the calls made nothing: since the fixtures, only Nia''s, Ed''s and Jo''s own sign-ups (3 logins, 3 accounts, 3 copies, Nia''s and Jo''s affiliate records; no customer, claim or list entry): '
  || (select m::text from made0) || ' -> ' || pg_temp.made()::text);

-- ═════ G Grants ═════
select pg_temp.check(not has_function_privilege('anon', 'public.affiliate_signup_existing(text,text,text,uuid)', 'execute')
    and not has_function_privilege('authenticated', 'public.affiliate_signup_existing(text,text,text,uuid)', 'execute')
    and not has_function_privilege('public', 'public.affiliate_signup_existing(text,text,text,uuid)', 'execute')
    and has_function_privilege('service_role', 'public.affiliate_signup_existing(text,text,text,uuid)', 'execute')
    and (select prosecdef from pg_proc where oid = 'public.affiliate_signup_existing(text,text,text,uuid)'::regprocedure)
    and (select proconfig from pg_proc where oid = 'public.affiliate_signup_existing(text,text,text,uuid)'::regprocedure) = array['search_path=public'],
  'G1 affiliate_signup_existing is the service role''s alone (security definer, search_path public)');
do $$
declare v text; w text;
begin
  perform pg_temp.as_user('lAva');
  execute 'set local role authenticated';
  begin perform public.affiliate_signup_existing('+61491570472', 'x@example.com'); v := 'ok';
  exception when others then v := sqlstate; end;
  execute 'reset role';
  perform set_config('request.jwt.claim.sub', '', true); perform set_config('request.jwt.claim.role', 'anon', true);
  execute 'set local role anon';
  begin perform public.affiliate_signup_existing('+61491570472', 'x@example.com'); w := 'ok';
  exception when others then w := sqlstate; end;
  execute 'reset role';
  perform pg_temp.put('g2', v || ' ' || w);
end $$;
select pg_temp.as_user('o');
select pg_temp.check(pg_temp.tx('g2') = '42501 42501', 'G2 a signed-in login and the anon key are refused (42501): ' || pg_temp.tx('g2'));

do $$
declare n int; m text;
begin
  select count(*), string_agg(msg, E'\n  ') into n, m from failed;
  if n > 0 then raise exception E'existing-affiliate-466: % check(s) failed:\n  %', n, m; end if;
  raise notice 'existing-affiliate-466: all checks passed';
end $$;
rollback;
