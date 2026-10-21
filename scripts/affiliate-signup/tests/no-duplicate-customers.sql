-- Affiliate sign-up finds the customer already there, and parks a claim
-- rather than make a second record (432).
--
-- The owner's decision, 16 Oct 2026: "C: both" (a name with the same words
-- and an email reaching the same inbox match; a sign-up on a phone a
-- customer already has is parked, not created); a family member's own record
-- stays with an Owner or Manager, "as today"; and "Yes" to saving sign-up's
-- audit-log entry.
--
--   H  The rules: names with the same words in any order, neighbouring words
--      written together or apart, whatever the case and punctuation, and
--      without a note in brackets, match; a shorter or a different name does
--      not, nor one whose words are cut elsewhere, nor, with a patronymic
--      (bin, s/o ...), one in another order. Letters of any script stay
--      whole. A Gmail address with or without dots or a +tag, or at
--      googlemail.com, is one inbox; any other address is compared as written.
--   F1 A family member signs up on a phone one customer has: a pending claim
--      suggesting that customer, and no second record. Staff may link it to
--      them, but not to the family member's own record once someone adds it
--      (the phone is then shared); an Owner can, and the login lands there.
--   F2 Two customers share the phone and neither name matches: the claim
--      suggests no one, even one sharing most of the name, so staff link no
--      one; an Owner may.
--   F3 Three share it (the phone is full): parked, where it used to fail with
--      CUSTOMER_PHONE_LIMIT.
--   F4 The name reordered, on a record with no email: a claim suggesting
--      that record, which staff resolve.
--   F5 Reordered, written together and with a note in brackets, and the
--      record has the login's email: linked by itself.
--   F6 The same Gmail inbox, with dots, or with a +tag at googlemail.com:
--      linked by itself. An address elsewhere with dots is another address:
--      parked.
--   F7 The same Gmail inbox and a reordered, joined name: linked by itself.
--   F8 A new person on a phone no one has: one new customer.
--   F9 A phone only a deleted customer had: a new customer, as before.
--   F10 Name and email exactly as on the record: linked, as before; a second
--      call answers "already" and changes nothing.
--   F11 An exact name comes before a same-words one; two same-words names
--      on one phone suggest no one.
--   X1 A customer an Owner unlinked a login from (378): a same-words sign-up
--      with their email is parked, not linked; staff are refused, an Owner
--      links.
--   X2 A customer an Owner or Manager rejected a claim for (379): a sign-up
--      with their name and the same Gmail inbox is parked; staff are refused,
--      a Manager links.
--   X3 A login with a rejected claim, on a phone a customer has: told
--      "unsuccessful", nothing parked, nothing created.
--   X4 A staff member's rejection protects no one: a same-words sign-up
--      with the email is linked by itself.
--   R1 A login whose claim was rejected is never linked by itself, even when
--      its name and email now match a customer: it is told "unsuccessful".
--   R2 A customer who already has a portal login: a second login for the
--      same Gmail inbox is parked (customer_has_login), not refused with a
--      duplicate-key error; staff are told the customer has a login.
--   R3 The other reasons: email_on_another_record, email_on_several_records
--      (and email_only, in R1).
--   A  Every sign-up that links or creates writes one 'affiliate_portal_claimed'
--      row and every claim parked one 'affiliate_claim_parked' row with its
--      reason, with no one signed in recorded; a second call parks nothing
--      more; these rows count as no unlink or rejection.
--   S  A staff login still cannot sign up.
--   U  Signed in for real (role authenticated): sign-up works, and the new
--      functions cannot be called directly.
--   L  An audit row that cannot be saved does not stop a sign-up.
--   G  Grants: the new functions are no endpoint; sign-up's are unchanged.
--   M  432 installs itself here twice; the second run changes nothing, and
--      the functions are the tested ones (432's AFTER md5s).
--
-- Every check runs, then the file fails if any did. Disposable database only;
-- everything is rolled back. Needs 378 and 379; it installs 432 itself (a
-- second run is a no-op, so it also runs where 432 is applied). Every name,
-- phone and email below is invented; the phones are +65 8432 01xx.
\set ON_ERROR_STOP on
begin;
-- 437 replaced this sign-up (straight in, no claims; its own suite is
-- straight-in-437.sql). On a database with 437 the 432 sign-up is put back
-- for this transaction only, so 432's rules are still checked here.
\ir ../../affiliate-claims/tests/sign-up-before-437.sql
\ir ../../../supabase/432_affiliate_signup_no_duplicate_customers.sql
create temp table m432 as
  select p.oid::regprocedure::text as fn, md5(pg_get_functiondef(p.oid)) as md5
    from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f';
\ir ../../../supabase/432_affiliate_signup_no_duplicate_customers.sql
set local lock_timeout = '10s';
set local statement_timeout = '120s';
create temp table failed(n serial, msg text);
create function pg_temp.check(ok boolean, msg text) returns void language plpgsql as
$$begin
  if ok is distinct from true then insert into failed(msg) values (msg); raise notice 'FAIL  %', msg;
  else raise notice 'PASS  %', msg; end if;
end$$;
create temp table fx(k text primary key, v uuid);
create function pg_temp.fx(key text) returns uuid language sql as $$ select v from fx where k=key $$;
create temp table tx(k text primary key, v text);
create function pg_temp.tx(key text) returns text language sql as $$ select v from tx where k=key $$;
create function pg_temp.as_user(key text) returns void language sql as
$$ select set_config('request.jwt.claim.sub', coalesce(pg_temp.fx(key)::text, ''), true) $$;
create function pg_temp.err(q text) returns text language plpgsql as
$$begin execute q; return null; exception when others then return sqlerrm; end$$;
create function pg_temp.resolve(claim text, cust text, note text default 'Checked with the person by phone') returns text language sql as
$$ select coalesce(pg_temp.err(format('select public.resolve_affiliate_account_claim(%L, %L, %L)', pg_temp.fx(claim), pg_temp.fx(cust), note)), 'ok') $$;
create function pg_temp.link_check(claim text, cust text) returns jsonb language sql as
$$ select public.affiliate_claim_link_check(pg_temp.fx(claim), pg_temp.fx(cust)) $$;
create function pg_temp.linked_to(login text) returns uuid language sql as
$$ select customer_id from public.affiliate_accounts where auth_user_id = pg_temp.fx(login) $$;
create function pg_temp.candidate(claim text) returns uuid language sql as
$$ select candidate_customer_id from public.affiliate_account_claims where id = pg_temp.fx(claim) $$;
create function pg_temp.on_phone(p text) returns int language sql as
$$ select count(*)::int from public.customers c where c.deleted_at is null and public.normalize_customer_phone(c.phone) = p $$;
create function pg_temp.parked(claim text) returns jsonb language sql as
$$ select new_data from audit_logs where table_name = 'affiliate_account_claims' and record_id = pg_temp.fx(claim)
      and action = 'affiliate_claim_parked' $$;
create function pg_temp.parked_rows(login text) returns int language sql as
$$ select count(*)::int from audit_logs where action = 'affiliate_claim_parked' and new_data->>'auth_user_id' = pg_temp.fx(login)::text $$;
create function pg_temp.claimed(login text) returns jsonb language sql as
$$ select l.new_data from audit_logs l join affiliate_accounts a on a.id = l.record_id
    where l.table_name = 'affiliate_accounts' and l.action = 'affiliate_portal_claimed' and a.auth_user_id = pg_temp.fx(login) $$;
-- The sign-up the verify page runs, as the login. Keeps its answer under the
-- login's key ('onb:<login>') and the claim it parked (if any) under claim_key.
create function pg_temp.onboard(login text, first text, last text, phone text, claim_key text default null) returns text language plpgsql as
$$declare r jsonb; begin
  perform pg_temp.as_user(login);
  r := public.complete_affiliate_onboarding(first, last, phone, true);
  insert into tx values ('onb:' || login, r::text) on conflict (k) do update set v = excluded.v;
  if claim_key is not null then
    insert into fx select claim_key, id from public.affiliate_account_claims
     where auth_user_id = pg_temp.fx(login) and status = 'pending'
    on conflict (k) do update set v = excluded.v;
  end if;
  return coalesce(r->>'status', '?');
exception when others then
  insert into tx values ('onb:' || login, 'ERROR: ' || sqlerrm) on conflict (k) do update set v = excluded.v;
  return 'ERROR: ' || sqlerrm;
end$$;
-- The status of the login's last sign-up (or the error it raised).
create function pg_temp.status(login text) returns text language sql as
$$ select case when pg_temp.tx('onb:' || login) like 'ERROR:%' then pg_temp.tx('onb:' || login)
               else pg_temp.tx('onb:' || login)::jsonb->>'status' end $$;
insert into tx values ('pending_msg', 'We found an existing Energia customer record that needs identity verification. Please contact Energia to complete account linking.');
insert into tx values ('rejected_msg', 'Account verification was unsuccessful. Please contact Energia for assistance.');
insert into tx values ('shared_msg', 'Several customers share this phone. Only an Owner or Manager can link it to a customer other than the suggested one.');
insert into tx values ('unlinked_msg', 'An Owner unlinked a login from this customer before. Only an Owner or Manager can link a login to them.');
insert into tx values ('cust_rejected_msg', 'An Owner or Manager rejected a claim for this customer. Only an Owner or Manager can link a login to them.');

select pg_temp.check(position('432:' in (select prosrc from pg_proc where oid = to_regprocedure('public.complete_affiliate_onboarding(text,text,text,boolean)'))) > 0
    and to_regprocedure('public.customer_names_match(text,text)') is not null
    and to_regprocedure('public.customer_name_words(text)') is not null
    and to_regprocedure('public.customer_email_match_key(text)') is not null
    and position('379:' in (select prosrc from pg_proc where oid = to_regprocedure('public.affiliate_claim_link_check(uuid,uuid)'))) > 0,
  'P0 378, 379 and 432 are installed');
select pg_temp.check(not exists (select 1 from public.customers where public.normalize_customer_phone(phone) like '+65843201__'),
  'P0 no customer uses the test phones +65 8432 01xx (the checks below assume so)');

-- ═════ H The rules ═════
select pg_temp.check(bool_and(public.customer_names_match(a, b)) and bool_and(public.customer_names_match(b, a)),
  'H1 the same words match, either way round: ' || string_agg(a || ' = ' || b, '; '))
  from (values ('Ann Lee Koh', 'Koh Ann Lee'),
               ('Koh Meiling', 'Mei Ling Koh'),
               ('Ong Meiling', 'Mei Ling (Orchard) Ong'),
               ('Mei-Ling O''Brien', 'meiling obrien'),
               ('  ANN   lee koh ', 'Ann Lee Koh'),
               ('Ann Lee Koh', 'Ann Lee Koh (AFL 12)'),
               ('A C D E F G H', 'H G F E D C A'),
               ('O’Brien Ann', 'Ann OBrien'),
               ('Fatimah bint Ali', 'FATIMAH BINT ALI (Orchard)'),
               ('Muhammadali bin Ahmad', 'Muhammad Ali bin Ahmad'),
               ('Siti Binte Ahmad', 'SITI BINTE AHMAD (Orchard)'),
               ('रीमा Koh', 'Koh रीमा')) t(a, b);
select pg_temp.check(not bool_or(public.customer_names_match(a, b)) and not bool_or(public.customer_names_match(b, a)),
  'H2 a shorter, longer or different name does not match, nor does an empty one: ' || string_agg(coalesce(a, '<null>') || ' / ' || coalesce(b, '<null>'), '; '))
  from (values ('Ann Koh', 'Ann Lee Koh'),
               ('Ann', 'Ann Koh'),
               ('Ben Koh', 'Ann Koh'),
               ('Ann Kaur', 'Ann Kaur D/O Singh'),
               ('Ann Koh Ann Koh', 'Ann Koh'),
               ('', 'Ann Koh'),
               ('(note only)', '(note only)'),
               (null, 'Ann Koh'),
               ('A C D E F G H', 'AC D E F G H'),
               ('Anna Koh', 'Ann Akoh'),
               ('Li Mei Tan', 'Lim Ei Tan'),
               ('Kumar s/o Rajan', 'Rajan s/o Kumar'),
               ('Ali bin Muhammad', 'Muhammad bin Ali'),
               ('Siti binte Ahmad', 'Ahmad Siti binte'),
               ('Muhammad ibn Ali', 'Ali ibn Muhammad'),
               ('Ahmad B. Ali', 'Ali B. Ahmad'),
               ('Fatimah bint Ali', 'Ali bint Fatimah'),
               ('Lana anak Testjimbun', 'Testjimbun anak Lana'),
               ('Kumar son of Rajan', 'Rajan son of Kumar'),
               ('Kumar S/0 Rajan', 'Rajan S/0 Kumar'),
               ('रीमा', 'राम')) t(a, b);
select pg_temp.check(public.customer_email_match_key('Ann.Lee.Koh@Gmail.com') = 'annleekoh@gmail.com'
    and public.customer_email_match_key(' annleekoh+portal@googlemail.com ') = 'annleekoh@gmail.com'
    and public.customer_email_match_key('annleekoh@gmail.com') = 'annleekoh@gmail.com'
    and public.customer_email_match_key('Ann.Lee@Example.com') = 'ann.lee@example.com'
    and public.customer_email_match_key('annlee@example.com') <> public.customer_email_match_key('ann.lee@example.com')
    and public.customer_email_match_key('ann+x@example.com') = 'ann+x@example.com'
    and public.customer_email_match_key('') is null and public.customer_email_match_key(null) is null
    and public.customer_email_match_key('...@gmail.com') = '...@gmail.com',
  'H3 a Gmail inbox is one address with or without dots, a +tag or googlemail.com; any other address is as written');

-- ═════ Fixtures ═════
do $$
declare sfx text := lower(substr(md5(random()::text || clock_timestamp()::text), 1, 6)); k text; u uuid; e text;
begin
  insert into tx values ('sfx', sfx);
  foreach k in array array['o','m','s'] loop
    u := gen_random_uuid(); insert into fx values (k, u);
    insert into auth.users(id, email, email_confirmed_at) values (u, 's432-' || k || '-' || sfx || '@tests.invalid', now());
  end loop;
  insert into profiles(id, full_name, email, role) values
    (pg_temp.fx('o'), 'S432 Owner',   's432-o-' || sfx || '@tests.invalid', 'owner'),
    (pg_temp.fx('m'), 'S432 Manager', 's432-m-' || sfx || '@tests.invalid', 'manager'),
    (pg_temp.fx('s'), 'S432 Staff',   's432-s-' || sfx || '@tests.invalid', 'staff');
  -- Affiliate portal logins (no profiles row), each with its own email;
  -- the Gmail ones below are written as their tests need.
  foreach k in array array['lBen','lEva','lCai','lF4','lGek','lMei','lKai','lNew','lDel','lQi','lPei','lPei2',
                           'lRex1','lRex2','lSam1','lTia1','lTia2','lWei','lVic','lXan','lAuth','lNoAud'] loop
    u := gen_random_uuid(); insert into fx values (k, u);
    insert into auth.users(id, email, email_confirmed_at) values (u, 's432-' || lower(k) || '-' || sfx || '@tests.invalid', now());
  end loop;
  foreach e in array array['lHui:s432.hui.min' || sfx || '@gmail.com',
                           'lJia:S432.Jia.Hui' || sfx || '+portal@GoogleMail.com',
                           'lLyn:s432.lyn.chu' || sfx || '@gmail.com',
                           'lSam2:s432.sam.rej' || sfx || '@gmail.com',
                           'lUmaA:s432umalogin' || sfx || '@gmail.com',
                           'lUmaB:s432.uma.login' || sfx || '@gmail.com'] loop
    u := gen_random_uuid(); insert into fx values (split_part(e, ':', 1), u);
    insert into auth.users(id, email, email_confirmed_at) values (u, split_part(e, ':', 2), now());
  end loop;
end $$;
create function pg_temp.mail(login text) returns text language sql as $$ select email from auth.users where id = pg_temp.fx(login) $$;
select pg_temp.as_user('o');

do $$
declare c uuid; sfx text := pg_temp.tx('sfx');
begin
  -- F1: one customer has the phone.
  insert into customers(full_name, phone, email) values ('Ann Lee Testkoh', '+6584320101', 's432-cann-' || sfx || '@tests.invalid')
    returning id into c; insert into fx values ('cAnn', c);
  -- F2: two share it.
  insert into customers(full_name, phone) values ('Cai Wen Testlee', '+6584320102') returning id into c; insert into fx values ('cCai', c);
  insert into customers(full_name, phone) values ('Dai Wen Testlee', '+6584320102') returning id into c; insert into fx values ('cDai', c);
  -- F3: three share it (full).
  insert into customers(full_name, phone) values ('Fa One Testfull', '+6584320103') returning id into c; insert into fx values ('cF1', c);
  insert into customers(full_name, phone) values ('Fa Two Testfull', '+6584320103') returning id into c; insert into fx values ('cF2', c);
  insert into customers(full_name, phone) values ('Fa Three Testfull', '+6584320103') returning id into c; insert into fx values ('cF3', c);
  -- F4: no email on the record.
  insert into customers(full_name, phone) values ('Siew Ann Testong', '+6584320104') returning id into c; insert into fx values ('cGek', c);
  -- F5: the login's email, a note in brackets, given names apart.
  insert into customers(full_name, phone, email) values ('Mei Ling (Orchard) Testwong', '+6584320105', pg_temp.mail('lMei'))
    returning id into c; insert into fx values ('cMei', c);
  -- F6: the same Gmail inboxes, written without dots or tags.
  insert into customers(full_name, phone, email) values ('Hui Min Testtay', '+6584320106', 's432huimin' || sfx || '@gmail.com')
    returning id into c; insert into fx values ('cHui', c);
  insert into customers(full_name, phone, email) values ('Jia Hui Testgoh', '+6584320107', 's432jiahui' || sfx || '@gmail.com')
    returning id into c; insert into fx values ('cJia', c);
  -- F6: an address elsewhere, with a dot the login's does not have.
  insert into customers(full_name, phone, email) values ('Kai Testlim', '+6584320108', 's432-l.kai-' || sfx || '@tests.invalid')
    returning id into c; insert into fx values ('cKai', c);
  -- F7: the same Gmail inbox; the name has a note and its parts apart.
  insert into customers(full_name, phone, email) values ('Lyn Chu (Testnote) Testwee', '+6584320109', 's432lynchu' || sfx || '@gmail.com')
    returning id into c; insert into fx values ('cLyn', c);
  -- F9: only a deleted customer had this phone.
  insert into customers(full_name, phone) values ('Old Testdel', '+6584320111') returning id into c; insert into fx values ('cDel', c);
  update customers set deleted_at = now() where id = c;
  -- F10: name and email exactly as the login's.
  insert into customers(full_name, phone, email) values ('Qi Testexact', '+6584320112', pg_temp.mail('lQi'))
    returning id into c; insert into fx values ('cQi', c);
  -- F11: one exact and one same-words name on one phone.
  insert into customers(full_name, phone) values ('Pei Qi Testng', '+6584320113') returning id into c; insert into fx values ('cPei1', c);
  insert into customers(full_name, phone) values ('Testng Pei Qi', '+6584320113') returning id into c; insert into fx values ('cPei2', c);
  -- X1: the second login's email; an Owner will unlink the first login.
  insert into customers(full_name, phone, email) values ('Rex Testunl', '+6584320114', pg_temp.mail('lRex2'))
    returning id into c; insert into fx values ('cRex', c);
  -- X2: the second login's Gmail inbox, without dots.
  insert into customers(full_name, phone, email) values ('Sam Testrej', '+6584320115', 's432samrej' || sfx || '@gmail.com')
    returning id into c; insert into fx values ('cSam', c);
  -- X4: the second login's email.
  insert into customers(full_name, phone, email) values ('Tia Teststaff', '+6584320116', pg_temp.mail('lTia2'))
    returning id into c; insert into fx values ('cTia', c);
  -- R1: the login's email.
  insert into customers(full_name, phone, email) values ('Wei Testrejlink', '+6584320118', pg_temp.mail('lWei'))
    returning id into c; insert into fx values ('cWei', c);
  -- R2: the first login's Gmail address, as written.
  insert into customers(full_name, phone, email) values ('Uma Testlogin', '+6584320119', pg_temp.mail('lUmaA'))
    returning id into c; insert into fx values ('cUma', c);
  -- R3: the name on one record, the login's email on another.
  insert into customers(full_name, phone) values ('Vic Testother', '+6584320120') returning id into c; insert into fx values ('cVic', c);
  insert into customers(full_name, phone, email) values ('Zoe Testother', '+6584320121', pg_temp.mail('lVic'))
    returning id into c; insert into fx values ('cZoe', c);
  -- R3: the login's email on two records.
  insert into customers(full_name, phone, email) values ('Xan Testmany', '+6584320122', pg_temp.mail('lXan'))
    returning id into c; insert into fx values ('cXan1', c);
  insert into customers(full_name, phone, email) values ('Xan Other', '+6584320123', pg_temp.mail('lXan'))
    returning id into c; insert into fx values ('cXan2', c);
end $$;
insert into tx values ('customers_before', (select count(*) from customers)::text);
insert into tx values ('protection_rows_before', (select count(*) from audit_logs
  where action in ('affiliate_login_unlinked', 'affiliate_claim_rejected'))::text);

-- ═════ F1 A family member on a phone one customer has ═════
select pg_temp.onboard('lBen', 'Ben', 'Testkoh', '+65 8432 0101', 'kBen');
select pg_temp.check(pg_temp.status('lBen') = 'pending_verification'
    and (pg_temp.tx('onb:lBen')::jsonb->>'message') = pg_temp.tx('pending_msg'),
  'F1 a family member signing up on a phone a customer has is parked, with the usual message: ' || pg_temp.tx('onb:lBen'));
select pg_temp.check(pg_temp.candidate('kBen') = pg_temp.fx('cAnn') and pg_temp.on_phone('+6584320101') = 1
    and not exists (select 1 from customers where full_name = 'Ben Testkoh') and pg_temp.linked_to('lBen') is null,
  'F1 the claim suggests the customer who has the phone; no second record and no login link');
select pg_temp.check((pg_temp.parked('kBen')->>'reason') = 'phone_in_use'
    and (pg_temp.parked('kBen')->>'phone_holders')::int = 1 and (pg_temp.parked('kBen')->>'email_matches')::int = 0
    and pg_temp.parked('kBen')->>'name_match' is null
    and (pg_temp.parked('kBen')->>'candidate_customer_id')::uuid = pg_temp.fx('cAnn'),
  'F1 the Audit Log says why: phone_in_use, 1 customer on the phone, no name or email match');
select pg_temp.as_user('s');
select pg_temp.check((select r->>'problem' is null and (r->>'suggested_customer')::boolean from pg_temp.link_check('kBen', 'cAnn') r),
  'F1 staff may link it to the customer who has the phone, if it is the same person');
-- It is not: someone adds the family member's own record on the phone.
do $$ declare c uuid; begin
  insert into customers(full_name, phone) values ('Ben Testkoh', '+6584320101') returning id into c; insert into fx values ('cBen', c);
end $$;
select pg_temp.check(pg_temp.resolve('kBen', 'cBen') = pg_temp.tx('shared_msg') and pg_temp.linked_to('lBen') is null,
  'F1 staff cannot link the claim to the family member''s own record once the phone is shared: ' || pg_temp.resolve('kBen', 'cBen'));
select pg_temp.as_user('o');
select pg_temp.check(pg_temp.resolve('kBen', 'cBen') = 'ok' and pg_temp.linked_to('lBen') = pg_temp.fx('cBen')
    and (select count(*) from customers where full_name = 'Ben Testkoh' and deleted_at is null) = 1,
  'F1 an Owner links it to their own record: one record, and the login is on it');
select pg_temp.onboard('lBen', 'Ben', 'Testkoh', '+65 8432 0101');
select pg_temp.check(pg_temp.status('lBen') = 'active'
    and (pg_temp.tx('onb:lBen')::jsonb->>'customer_id')::uuid = pg_temp.fx('cBen'),
  'F1 signing in again, the person lands on their own record');

-- ═════ F2 Two customers share the phone ═════
select pg_temp.onboard('lEva', 'Eva', 'Testlee', '+65 8432 0102', 'kEva');
select pg_temp.check(pg_temp.status('lEva') = 'pending_verification'
    and pg_temp.candidate('kEva') is null and pg_temp.on_phone('+6584320102') = 2
    and (pg_temp.parked('kEva')->>'phone_holders')::int = 2 and (pg_temp.parked('kEva')->>'reason') = 'phone_in_use',
  'F2 a third person on a phone two share is parked, suggesting no one');
select pg_temp.as_user('s');
select pg_temp.check((select r->>'problem' from pg_temp.link_check('kEva', 'cCai') r) = pg_temp.tx('shared_msg')
    and (select r->>'problem' from pg_temp.link_check('kEva', 'cDai') r) = pg_temp.tx('shared_msg'),
  'F2 staff cannot link it to either of them');
select pg_temp.as_user('o');
select pg_temp.check((select r->>'problem' is null from pg_temp.link_check('kEva', 'cCai') r),
  'F2 an Owner may');
select pg_temp.onboard('lCai', 'Cai', 'Testlee', '+65 8432 0102', 'kCai');
select pg_temp.check(pg_temp.status('lCai') = 'pending_verification'
    and pg_temp.candidate('kCai') is null and pg_temp.on_phone('+6584320102') = 2
    and (pg_temp.parked('kCai')->>'reason') = 'phone_in_use',
  'F2 "Cai Testlee" shares most of "Cai Wen Testlee", but that is no name match: the claim suggests no one');
select pg_temp.as_user('s');
select pg_temp.check((select r->>'problem' from pg_temp.link_check('kCai', 'cCai') r) = pg_temp.tx('shared_msg'),
  'F2 so staff cannot link it to her either: the phone alone never lets them choose');
select pg_temp.as_user('o');

-- ═════ F3 The phone is full ═════
select pg_temp.check((select used from customer_phone_capacity where phone = '+6584320103') = 3,
  'F3 (setup) three customers share +65 8432 0103');
select pg_temp.onboard('lF4', 'Fa Four', 'Testfull', '+65 8432 0103', 'kF4');
select pg_temp.check(pg_temp.status('lF4') = 'pending_verification'
    and pg_temp.candidate('kF4') is null and (pg_temp.parked('kF4')->>'phone_holders')::int = 3
    and (select used from customer_phone_capacity where phone = '+6584320103') = 3 and pg_temp.on_phone('+6584320103') = 3,
  'F3 a fourth person is parked (it failed with CUSTOMER_PHONE_LIMIT), and the phone takes no fourth record: ' || pg_temp.tx('onb:lF4'));

-- ═════ F4 The name reordered, no email on the record ═════
select pg_temp.onboard('lGek', 'Testong', 'Siew Ann', '+65 8432 0104', 'kGek');
select pg_temp.check(pg_temp.status('lGek') = 'pending_verification'
    and pg_temp.candidate('kGek') = pg_temp.fx('cGek') and pg_temp.on_phone('+6584320104') = 1,
  'F4 "Testong Siew Ann" for "Siew Ann Testong", whose record has no email: a claim suggesting the record, no second one');
select pg_temp.check((pg_temp.parked('kGek')->>'reason') = 'email_not_on_record' and (pg_temp.parked('kGek')->>'name_match') = 'same_words',
  'F4 the Audit Log says the name matched by the same words and the email is not on the record');
select pg_temp.as_user('s');
select pg_temp.check(pg_temp.resolve('kGek', 'cGek') = 'ok' and pg_temp.linked_to('lGek') = pg_temp.fx('cGek'),
  'F4 staff resolve it to the record');
select pg_temp.as_user('o');

-- ═════ F5 Reordered, together, a note in brackets, and the email ═════
select pg_temp.onboard('lMei', 'Testwong', 'Meiling', '+65 8432 0105');
select pg_temp.check(pg_temp.status('lMei') = 'active'
    and pg_temp.linked_to('lMei') = pg_temp.fx('cMei') and pg_temp.on_phone('+6584320105') = 1
    and not exists (select 1 from affiliate_account_claims where auth_user_id = pg_temp.fx('lMei')),
  'F5 "Testwong Meiling" for "Mei Ling (Orchard) Testwong", with the email on the record: linked by itself, nothing parked');
select pg_temp.check((pg_temp.claimed('lMei')->>'new_customer')::boolean = false and pg_temp.claimed('lMei')->>'name_match' = 'same_words'
    and pg_temp.claimed('lMei')->>'email_match' = 'exact' and (pg_temp.claimed('lMei')->>'customer_id')::uuid = pg_temp.fx('cMei'),
  'F5 the Audit Log says how: the same words, the email exactly');

-- ═════ F6 The same Gmail inbox ═════
select pg_temp.onboard('lHui', 'Hui Min', 'Testtay', '+65 8432 0106');
select pg_temp.check(pg_temp.status('lHui') = 'active'
    and pg_temp.linked_to('lHui') = pg_temp.fx('cHui') and pg_temp.on_phone('+6584320106') = 1
    and pg_temp.claimed('lHui')->>'email_match' = 'same_inbox' and pg_temp.claimed('lHui')->>'name_match' = 'exact',
  'F6 a Gmail address with dots reaches the record''s inbox: linked by itself (email_match same_inbox)');
select pg_temp.onboard('lJia', 'Jia Hui', 'Testgoh', '+65 8432 0107');
select pg_temp.check(pg_temp.status('lJia') = 'active'
    and pg_temp.linked_to('lJia') = pg_temp.fx('cJia') and pg_temp.on_phone('+6584320107') = 1,
  'F6 so does one with dots, a +tag, capitals and googlemail.com');
select pg_temp.onboard('lKai', 'Kai', 'Testlim', '+65 8432 0108', 'kKai');
select pg_temp.check(pg_temp.status('lKai') = 'pending_verification'
    and pg_temp.candidate('kKai') = pg_temp.fx('cKai') and pg_temp.linked_to('lKai') is null
    and (pg_temp.parked('kKai')->>'reason') = 'email_not_on_record',
  'F6 elsewhere a dot makes another address: the exact name parks a claim suggesting the record, as before');

-- ═════ F7 The same Gmail inbox and a reordered, joined name ═════
select pg_temp.onboard('lLyn', 'Testwee', 'Lynchu', '+65 8432 0109');
select pg_temp.check(pg_temp.status('lLyn') = 'active'
    and pg_temp.linked_to('lLyn') = pg_temp.fx('cLyn') and pg_temp.on_phone('+6584320109') = 1
    and pg_temp.claimed('lLyn')->>'email_match' = 'same_inbox' and pg_temp.claimed('lLyn')->>'name_match' = 'same_words',
  'F7 "Testwee Lynchu" with a dotted Gmail for "Lyn Chu (Testnote) Testwee": linked by itself, no second record');

-- ═════ F8 / F9 New people ═════
select pg_temp.onboard('lNew', 'Nia', 'Testnew', '+65 8432 0110');
select pg_temp.check(pg_temp.status('lNew') = 'active'
    and pg_temp.on_phone('+6584320110') = 1
    and (select full_name from customers where id = pg_temp.linked_to('lNew')) = 'Nia Testnew'
    and (pg_temp.claimed('lNew')->>'new_customer')::boolean and pg_temp.claimed('lNew')->>'name_match' is null
    and pg_temp.claimed('lNew')->>'email_match' is null,
  'F8 a new person on a phone no one has: one new customer, recorded as new');
select pg_temp.onboard('lDel', 'Pam', 'Testdel', '+65 8432 0111');
select pg_temp.check(pg_temp.status('lDel') = 'active'
    and pg_temp.on_phone('+6584320111') = 1 and pg_temp.linked_to('lDel') <> pg_temp.fx('cDel')
    and (pg_temp.claimed('lDel')->>'new_customer')::boolean,
  'F9 a phone only a deleted customer had: a new customer, as before');

-- ═════ F10 Exactly as on the record ═════
select pg_temp.onboard('lQi', 'Qi', 'Testexact', '+65 8432 0112');
select pg_temp.check(pg_temp.status('lQi') = 'active'
    and pg_temp.linked_to('lQi') = pg_temp.fx('cQi')
    and pg_temp.claimed('lQi')->>'name_match' = 'exact' and pg_temp.claimed('lQi')->>'email_match' = 'exact',
  'F10 name and email exactly as on the record: linked, as before');
insert into tx values ('qi_rows', (select count(*) from audit_logs where action = 'affiliate_portal_claimed')::text);
select pg_temp.onboard('lQi', 'Qi', 'Testexact', '+65 8432 0112');
select pg_temp.check(pg_temp.status('lQi') = 'active'
    and (pg_temp.tx('onb:lQi')::jsonb->>'already')::boolean
    and (select count(*) from affiliate_accounts where auth_user_id = pg_temp.fx('lQi')) = 1
    and (select count(*) from audit_logs where action = 'affiliate_portal_claimed')::text = pg_temp.tx('qi_rows'),
  'F10 a second call answers "already" and writes nothing');

-- ═════ F11 Exact first; two same-words names suggest no one ═════
select pg_temp.onboard('lPei', 'Pei Qi', 'Testng', '+65 8432 0113', 'kPei');
select pg_temp.check(pg_temp.status('lPei') = 'pending_verification'
    and pg_temp.candidate('kPei') = pg_temp.fx('cPei1')
    and (pg_temp.parked('kPei')->>'name_match') = 'exact' and (pg_temp.parked('kPei')->>'reason') = 'email_not_on_record',
  'F11 "Pei Qi Testng" exactly, beside "Testng Pei Qi": the claim suggests the exact one');
select pg_temp.onboard('lPei2', 'Qi Pei', 'Testng', '+65 8432 0113', 'kPei2');
select pg_temp.check(pg_temp.status('lPei2') = 'pending_verification'
    and pg_temp.candidate('kPei2') is null
    and (pg_temp.parked('kPei2')->>'reason') = 'several_name_matches' and (pg_temp.parked('kPei2')->>'name_match') = 'same_words',
  'F11 "Qi Pei Testng" has the same words as both: parked, suggesting no one');

-- ═════ X1 A customer an Owner unlinked a login from (378) ═════
select pg_temp.onboard('lRex1', 'Rex', 'Testunl', '+65 8432 0114', 'kRex1');
select pg_temp.check(pg_temp.status('lRex1') = 'pending_verification',
  'X1 (setup) a first login signs up as the customer, whose email is another: a claim');
select pg_temp.as_user('o');
select pg_temp.check(pg_temp.resolve('kRex1', 'cRex') = 'ok' and pg_temp.linked_to('lRex1') = pg_temp.fx('cRex'),
  'X1 (setup) an Owner links it through the claim');
select pg_temp.check(pg_temp.err(format('select public.unlink_affiliate_account(%L, %L)', pg_temp.fx('cRex'), 'Wrong person')) is null
    and pg_temp.linked_to('lRex1') is null,
  'X1 (setup) an Owner unlinks it');
select pg_temp.onboard('lRex2', 'Testunl', 'Rex', '+65 8432 0114', 'kRex2');
select pg_temp.check(pg_temp.status('lRex2') = 'pending_verification'
    and pg_temp.linked_to('lRex2') is null and pg_temp.candidate('kRex2') = pg_temp.fx('cRex')
    and (pg_temp.parked('kRex2')->>'reason') = 'protected_customer',
  'X1 a same-words sign-up with the customer''s own email is parked, not linked: the customer is protected');
select pg_temp.as_user('s');
select pg_temp.check(pg_temp.resolve('kRex2', 'cRex') = pg_temp.tx('unlinked_msg') and pg_temp.linked_to('lRex2') is null,
  'X1 staff are refused: ' || pg_temp.resolve('kRex2', 'cRex'));
select pg_temp.as_user('o');
select pg_temp.check(pg_temp.resolve('kRex2', 'cRex') = 'ok' and pg_temp.linked_to('lRex2') = pg_temp.fx('cRex'),
  'X1 an Owner links it');

-- ═════ X2 A customer an Owner or Manager rejected a claim for (379) ═════
do $$ declare c uuid; begin
  insert into affiliate_account_claims(auth_user_id, entered_phone, verified_email, candidate_customer_id, entered_name)
    values (pg_temp.fx('lSam1'), '+6584320115', pg_temp.mail('lSam1'), pg_temp.fx('cSam'), 'Sam Testrej') returning id into c;
  insert into fx values ('kSam1', c);
end $$;
select pg_temp.as_user('m');
select pg_temp.check(pg_temp.err(format('select public.reject_affiliate_account_claim(%L, %L)', pg_temp.fx('kSam1'), 'Not the customer')) is null,
  'X2 (setup) a Manager rejects a claim suggesting the customer');
select pg_temp.onboard('lSam2', 'Sam', 'Testrej', '+65 8432 0115', 'kSam2');
select pg_temp.check(pg_temp.status('lSam2') = 'pending_verification'
    and pg_temp.linked_to('lSam2') is null and pg_temp.candidate('kSam2') = pg_temp.fx('cSam')
    and (pg_temp.parked('kSam2')->>'reason') = 'protected_customer',
  'X2 the name and the same Gmail inbox as the record: parked, not linked');
select pg_temp.as_user('s');
select pg_temp.check(pg_temp.resolve('kSam2', 'cSam') = pg_temp.tx('cust_rejected_msg'),
  'X2 staff are refused: ' || pg_temp.resolve('kSam2', 'cSam'));
select pg_temp.as_user('m');
select pg_temp.check(pg_temp.resolve('kSam2', 'cSam') = 'ok' and pg_temp.linked_to('lSam2') = pg_temp.fx('cSam'),
  'X2 a Manager links it');
select pg_temp.as_user('o');

-- ═════ X3 A login with a rejected claim, on a phone a customer has ═════
insert into tx values ('sam1_claims', (select count(*) from affiliate_account_claims where auth_user_id = pg_temp.fx('lSam1'))::text);
select pg_temp.onboard('lSam1', 'Zed', 'Testrej', '+65 8432 0115');
select pg_temp.check(pg_temp.status('lSam1') = 'rejected'
    and (pg_temp.tx('onb:lSam1')::jsonb->>'message') = pg_temp.tx('rejected_msg')
    and (select count(*) from affiliate_account_claims where auth_user_id = pg_temp.fx('lSam1'))::text = pg_temp.tx('sam1_claims')
    and pg_temp.on_phone('+6584320115') = 1 and pg_temp.parked_rows('lSam1') = 0,
  'X3 told "unsuccessful": nothing parked, nothing created');

-- ═════ X4 A staff member's rejection protects no one ═════
do $$ declare c uuid; begin
  insert into affiliate_account_claims(auth_user_id, entered_phone, verified_email, candidate_customer_id, entered_name)
    values (pg_temp.fx('lTia1'), '+6584320116', pg_temp.mail('lTia1'), pg_temp.fx('cTia'), 'Tia Teststaff') returning id into c;
  insert into fx values ('kTia1', c);
end $$;
select pg_temp.as_user('s');
select pg_temp.check(pg_temp.err(format('select public.reject_affiliate_account_claim(%L, %L)', pg_temp.fx('kTia1'), 'Not sure')) is null,
  'X4 (setup) a member of staff rejects a claim suggesting the customer');
select pg_temp.onboard('lTia2', 'Teststaff', 'Tia', '+65 8432 0116');
select pg_temp.check(pg_temp.status('lTia2') = 'active'
    and pg_temp.linked_to('lTia2') = pg_temp.fx('cTia'),
  'X4 a same-words sign-up with the email on the record is linked by itself, as before 432 for an exact one');
select pg_temp.as_user('o');

-- ═════ R1 A rejected login is never linked by itself ═════
select pg_temp.onboard('lWei', 'Someone', 'Testelse', '+65 8432 0118', 'kWei');
select pg_temp.check(pg_temp.status('lWei') = 'pending_verification' and pg_temp.candidate('kWei') is null
    and (pg_temp.parked('kWei')->>'reason') = 'email_only' and pg_temp.linked_to('lWei') is null,
  'R1 (setup) only the email matches a record: parked, suggesting no one (email_only)');
select pg_temp.as_user('m');
select pg_temp.check(pg_temp.err(format('select public.reject_affiliate_account_claim(%L, %L)', pg_temp.fx('kWei'), 'Could not verify')) is null,
  'R1 (setup) a Manager rejects it');
select pg_temp.onboard('lWei', 'Testrejlink', 'Wei', '+65 8432 0118');
select pg_temp.check(pg_temp.status('lWei') = 'rejected' and pg_temp.linked_to('lWei') is null
    and (select count(*) from affiliate_account_claims where auth_user_id = pg_temp.fx('lWei')) = 1,
  'R1 signing in again with the record''s name reordered, its email and phone: still "unsuccessful", not linked');
select pg_temp.onboard('lWei', 'Wei', 'Testrejlink', '+65 8432 0118');
select pg_temp.check(pg_temp.status('lWei') = 'rejected' and pg_temp.linked_to('lWei') is null,
  'R1 nor with the name exactly as on the record');
select pg_temp.as_user('o');

-- ═════ R2 A customer who already has a portal login ═════
select pg_temp.onboard('lUmaA', 'Uma', 'Testlogin', '+65 8432 0119');
select pg_temp.check(pg_temp.status('lUmaA') = 'active' and pg_temp.linked_to('lUmaA') = pg_temp.fx('cUma'),
  'R2 (setup) the first login, with the record''s Gmail address, is linked');
select pg_temp.onboard('lUmaB', 'Uma', 'Testlogin', '+65 8432 0119', 'kUmaB');
select pg_temp.check(pg_temp.status('lUmaB') = 'pending_verification' and pg_temp.linked_to('lUmaB') is null
    and pg_temp.candidate('kUmaB') = pg_temp.fx('cUma') and (pg_temp.parked('kUmaB')->>'reason') = 'customer_has_login'
    and pg_temp.linked_to('lUmaA') = pg_temp.fx('cUma'),
  'R2 a second login for the same Gmail inbox is parked (customer_has_login), not refused with an error: ' || pg_temp.tx('onb:lUmaB'));
select pg_temp.as_user('s');
select pg_temp.check((select (r->>'customer_has_login')::boolean and r->>'problem' like 'This customer already has an affiliate portal login.%'
                        from pg_temp.link_check('kUmaB', 'cUma') r),
  'R2 staff are told the customer already has a login');
select pg_temp.as_user('o');

-- ═════ R3 The other reasons ═════
select pg_temp.onboard('lVic', 'Vic', 'Testother', '+65 8432 0120', 'kVic');
select pg_temp.check(pg_temp.status('lVic') = 'pending_verification' and pg_temp.candidate('kVic') = pg_temp.fx('cVic')
    and (pg_temp.parked('kVic')->>'reason') = 'email_on_another_record' and (pg_temp.parked('kVic')->>'email_matches')::int = 1,
  'R3 the name on one record and the email on another: parked, suggesting the name''s (email_on_another_record)');
select pg_temp.onboard('lXan', 'Xan', 'Testmany', '+65 8432 0122', 'kXan');
select pg_temp.check(pg_temp.status('lXan') = 'pending_verification' and pg_temp.candidate('kXan') = pg_temp.fx('cXan1')
    and (pg_temp.parked('kXan')->>'reason') = 'email_on_several_records' and (pg_temp.parked('kXan')->>'email_matches')::int = 2,
  'R3 the email on two records: parked, suggesting the name''s (email_on_several_records)');

-- ═════ A The Audit Log ═════
select pg_temp.check((select count(*) = 0 from audit_logs l
                        where l.action in ('affiliate_portal_claimed', 'affiliate_claim_parked')
                          and l.new_data->>'auth_user_id' in (select v::text from fx where k like 'l%')
                          and (l.changed_by is not null or l.actor_role is not null or l.module is distinct from 'affiliate'))
    and (select count(*) from audit_logs l join affiliate_accounts a on a.id = l.record_id
          where l.action = 'affiliate_portal_claimed' and a.auth_user_id in (select v from fx where k like 'l%'))
      = (select count(*) from affiliate_accounts a where a.auth_user_id in (select v from fx where k like 'l%')
           and not exists (select 1 from affiliate_account_claims cl where cl.auth_user_id = a.auth_user_id and cl.status = 'resolved')),
  'A1 every sign-up that linked or created wrote one row, with no one signed in recorded and module affiliate');
select pg_temp.check((select count(*) from audit_logs where action = 'affiliate_claim_parked'
                        and record_id in (select id from affiliate_account_claims where auth_user_id in (select v from fx where k like 'l%')))
      = (select count(*) from affiliate_account_claims where auth_user_id in (select v from fx where k like 'l%') and entered_name is not null
           and id not in (pg_temp.fx('kSam1'), pg_temp.fx('kTia1'))),
  'A2 every claim sign-up parked has its row');
insert into tx values ('eva_rows', pg_temp.parked_rows('lEva')::text);
select pg_temp.onboard('lEva', 'Eva', 'Testlee', '+65 8432 0102');
select pg_temp.check(pg_temp.status('lEva') = 'pending_verification'
    and pg_temp.parked_rows('lEva')::text = pg_temp.tx('eva_rows')
    and (select count(*) from affiliate_account_claims where auth_user_id = pg_temp.fx('lEva')) = 1,
  'A2 signing in again with a claim pending parks nothing more');
select pg_temp.check((select count(*) from audit_logs where action in ('affiliate_login_unlinked', 'affiliate_claim_rejected'))
      = pg_temp.tx('protection_rows_before')::int + 4,
  'A3 the only unlink and rejection rows are the four X1, X2, X4 and R1 made: sign-up''s rows are neither');
select pg_temp.as_user('s');
select pg_temp.check((select not (r->>'customer_previously_unlinked')::boolean and not (r->>'customer_previously_rejected')::boolean
                        from pg_temp.link_check('kKai', 'cKai') r),
  'A3 after sign-up''s rows, staff still see the customer as unprotected');
select pg_temp.as_user('o');

-- ═════ S A staff login ═════
select pg_temp.onboard('s', 'S432', 'Staff', '+65 8432 0117');
select pg_temp.check(pg_temp.status('s') like 'ERROR: STAFF_ACCOUNT%'
    and pg_temp.on_phone('+6584320117') = 0
    and not exists (select 1 from affiliate_account_claims where auth_user_id = pg_temp.fx('s')),
  'S a staff login still cannot sign up, and nothing is written');
select pg_temp.as_user('o');

-- ═════ C What sign-up created ═════
select pg_temp.check((select count(*) from customers) = pg_temp.tx('customers_before')::int + 3,
  'C sign-up created two customers (F8, F9), and the family member''s record was added by hand (F1): nothing else');

-- ═════ U Signed in for real ═════
do $$
declare r jsonb; v_helper text;
begin
  perform set_config('request.jwt.claim.sub', pg_temp.fx('lAuth')::text, true);
  execute 'set local role authenticated';
  r := public.complete_affiliate_onboarding('Ira', 'Testauth', '+65 8432 0124', true);
  begin
    perform public.customer_names_match('Ann Koh', 'Koh Ann');
    v_helper := 'callable';
  exception when insufficient_privilege then v_helper := 'refused';
  end;
  execute 'reset role';
  insert into tx values ('auth_onb', r::text), ('auth_helper', v_helper);
end $$;
select pg_temp.check((pg_temp.tx('auth_onb')::jsonb->>'status') = 'active' and pg_temp.linked_to('lAuth') is not null
    and pg_temp.tx('auth_helper') = 'refused',
  'U as role authenticated, sign-up works and a new function cannot be called directly: ' || pg_temp.tx('auth_onb'));

-- ═════ L An audit row that cannot be saved ═════
alter table audit_logs add constraint s432_no_signup_rows
  check (action not in ('affiliate_portal_claimed', 'affiliate_claim_parked')) not valid;
select pg_temp.onboard('lNoAud', 'Jo', 'Testnoaudit', '+65 8432 0125');
alter table audit_logs drop constraint s432_no_signup_rows;
select pg_temp.check(pg_temp.status('lNoAud') = 'active' and pg_temp.linked_to('lNoAud') is not null
    and pg_temp.claimed('lNoAud') is null,
  'L when the audit row cannot be saved, the sign-up still completes (a warning in the log)');

-- ═════ G Grants ═════
select pg_temp.check(bool_and(not has_function_privilege('anon', f, 'execute') and not has_function_privilege('authenticated', f, 'execute')
                              and has_function_privilege('service_role', f, 'execute')),
  'G the new functions are no endpoint: the service role only')
  from unnest(array['public.customer_name_words(text)', 'public.customer_names_match(text,text)',
                    'public.customer_email_match_key(text)']) f;
select pg_temp.check(has_function_privilege('authenticated', 'public.complete_affiliate_onboarding(text,text,text,boolean)', 'execute')
    and not has_function_privilege('anon', 'public.complete_affiliate_onboarding(text,text,text,boolean)', 'execute'),
  'G sign-up keeps its grants: signed-in logins call it, anon does not');

-- ═════ M The tested versions ═════
select pg_temp.check(not exists (select 1 from m432 m
                                   left join pg_proc p on p.oid::regprocedure::text = m.fn and p.pronamespace = 'public'::regnamespace
                                  where p.oid is null or md5(pg_get_functiondef(p.oid)) <> m.md5)
    and (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f') = (select count(*) from m432),
  'M running 432 a second time changed no function');
select pg_temp.check(bool_and(md5(pg_get_functiondef(to_regprocedure(fn))) = ok),
  'M the functions are 432''s AFTER versions')
  from (values ('public.complete_affiliate_onboarding(text,text,text,boolean)', 'ff59dd1f8a6ca7397efea5880c6a87a7'),
               ('public.customer_name_words(text)',       'a7507abf0f15abd923dff59508b269c1'),
               ('public.customer_names_match(text,text)', 'ef1af52e4888cefb6037a2291f4e011d'),
               ('public.customer_email_match_key(text)',  'be468815c9626fff1728e2cfcd484b66')) t(fn, ok);

do $$ declare v_failed int; begin
  select count(*) into v_failed from failed;
  if v_failed > 0 then raise exception '% check(s) failed: %', v_failed, (select string_agg(msg, '; ' order by n) from failed); end if;
  raise notice 'All no-duplicate-customers checks passed.';
end $$;
rollback;
