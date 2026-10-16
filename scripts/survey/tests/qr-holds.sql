-- The QR health survey holds a form it is unsure about for staff, rather than
-- make a second customer (433).
--
-- The owner's decision, 16 Oct 2026: "Apply the same fix to the QR health
-- survey", then "A: hold for staff" (a form attaches by itself only on phone +
-- name; when only the phone or only the email belongs to a customer, it waits
-- for staff with no customer) and "Any staff" may match a waiting form or make
-- a new customer from it.
--
--   Q1 Exact phone + name: attached, as before. The reply says only success,
--      survey_no and survey_id: never whether a customer was found or made.
--   Q2 The name with the same words (432's rule): attached, and the form
--      carries the customer's name (the name typed is in the Audit Log).
--   Q3 A family member on a phone a customer has: held (phone_in_use) for
--      that customer, with the name, phone and email typed; no customer is
--      made. The reply is the same as any other.
--   Q4 Another phone, but the same Gmail inbox as a customer: held
--      (email_in_use).
--   Q5 The same phone and email, a name written differently: held
--      (phone_and_email_in_use), for that one customer.
--   Q6 A name that matches several customers on the phone: held
--      (several_name_matches) for all of them; it used to be refused.
--   Q7 A new person (phone and email no customer has): a new customer, as
--      before.
--   Q8 Sending the form again while it waits: HEALTH_SURVEY_ALREADY_EXISTS,
--      also with the name's words in another order.
--   Q9 A phone 3 customers share: held, where it failed with
--      CUSTOMER_PHONE_LIMIT.
--   Q10 An old record whose phone cannot be read, but could be this one, and
--      the same name: refused as before (AMBIGUOUS_CUSTOMER_MATCH); such old
--      phones do not count as anyone's.
--   Q11 A customer who gets the form's email after it was held is listed as
--      one it may belong to.
--   L  Staff list the waiting forms with what was typed and the customers
--      each may belong to (phone, email, name, survey); an inventory manager
--      and a login with no staff profile cannot.
--   A  Staff attach a form, with a note: the customer's empty details are
--      filled from it (never the name or phone), the form carries the
--      customer's name and keeps the phone and email typed, it now counts as
--      a visit, it leaves the list, and the Audit Log has it with what was
--      typed. A customer with a one-word name keeps it. Saving the form's
--      details afterwards does not rename the customer. Sending the form
--      again is refused as a second survey, also once a merge moved it to
--      another record; once its customer is deleted it is not.
--      Staff may attach to a customer not listed. Refused: no note, a
--      customer with a survey already, a deleted customer, a form already
--      dealt with, an inventory manager.
--   C  Staff make a new customer from a form (the family member): attached
--      to them; on a full phone it is refused and nothing changes.
--   X  An Owner or Manager closes a form with a reason (not staff, not
--      without one): it leaves the list, is kept with no customer, and the
--      person may send it again.
--   K  Unchanged: a customer who already has a survey is refused as before;
--      the submission's Audit Log row says whether it was held, why and how
--      the name matched.
--   N  Signed out (role anon): a form is held as above; anon cannot list,
--      attach, make, close or read the waiting forms.
--   T  The TikTok no-show run (a rehearsal) leaves out a lead whose form,
--      from a new phone and a customer's email, waits for staff that day, and
--      still once an Owner or Manager closed it.
--   G  Grants. M  433 installs itself here twice; the second run changes
--      nothing, and the functions are the tested ones.
--
-- Every check runs, then the file fails if any did. Disposable database only;
-- everything is rolled back. Needs 432; it installs 433 itself (a second run
-- is a no-op, so it also runs where 433 is applied). Every name, phone and
-- email below is invented; the phones are +65 8433 01xx.
\set ON_ERROR_STOP on
begin;
\ir ../../../supabase/433_qr_survey_holds_unsure_forms_for_staff.sql
create temp table m433 as
  select p.oid::regprocedure::text as fn, md5(pg_get_functiondef(p.oid)) as md5
    from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f';
\ir ../../../supabase/433_qr_survey_holds_unsure_forms_for_staff.sql
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
-- Signed in as the login: its id, and the role every browser request carries
-- (require_active_staff lets a call with neither through, as the server's).
create function pg_temp.as_user(key text) returns void language sql as
$$ select set_config('request.jwt.claim.sub', coalesce(pg_temp.fx(key)::text, ''), true),
          set_config('request.jwt.claim.role', 'authenticated', true) $$;
create function pg_temp.err(q text) returns text language plpgsql as
$$begin execute q; return 'ok'; exception when others then return sqlerrm; end$$;
-- A QR form as the public page sends it; keeps the reply (or the error) under
-- 'sub:<key>' and the survey under 'hs:<key>'.
create function pg_temp.submit(key text, name text, phone text, email text) returns void language plpgsql as
$$declare r jsonb; begin
  r := public.submit_health_survey(pg_temp.tx('token'),
         jsonb_build_object('full_name', name, 'phone', phone, 'email', email,
                            'signature_data', 'data:image/png;base64,AAAA', 'source_option_id', pg_temp.fx('src'),
                            'sex', 'female', 'date_of_birth', '1980-02-03', 'occupation', 'Tester'),
         null, null);
  insert into tx values ('sub:' || key, r::text) on conflict (k) do update set v = excluded.v;
  insert into fx values ('hs:' || key, (r->>'survey_id')::uuid) on conflict (k) do update set v = excluded.v;
exception when others then
  insert into tx values ('sub:' || key, 'ERROR: ' || sqlerrm) on conflict (k) do update set v = excluded.v;
end$$;
create function pg_temp.reply(key text) returns jsonb language sql as
$$ select case when pg_temp.tx('sub:' || key) like 'ERROR:%' then null else pg_temp.tx('sub:' || key)::jsonb end $$;
create function pg_temp.survey_customer(key text) returns uuid language sql as
$$ select customer_id from public.health_surveys where id = pg_temp.fx('hs:' || key) $$;
create function pg_temp.hold(key text) returns public.health_survey_holds language sql as
$$ select h from public.health_survey_holds h where h.survey_id = pg_temp.fx('hs:' || key) $$;
create function pg_temp.on_phone(p text) returns int language sql as
$$ select count(*)::int from public.customers c where c.deleted_at is null and public.normalize_customer_phone(c.phone) = p $$;
-- The list as the signed-in user sees it, and one form's entry in it.
create function pg_temp.listed(key text) returns jsonb language sql as
$$ select e from jsonb_array_elements(public.health_survey_holds_list()) e where (e->>'survey_id')::uuid = pg_temp.fx('hs:' || key) $$;
create function pg_temp.candidate(key text, cust text) returns jsonb language sql as
$$ select c from jsonb_array_elements(pg_temp.listed(key)->'candidates') c where (c->>'customer_id')::uuid = pg_temp.fx(cust) $$;
create function pg_temp.attach(key text, cust text, note text default 'Checked her IC at the counter') returns text language sql as
$$ select pg_temp.err(format('select public.attach_held_health_survey(%L, %L, %L)', pg_temp.fx('hs:' || key), pg_temp.fx(cust), note)) $$;
create function pg_temp.make(key text, note text default 'Daughter of the customer on this phone') returns text language sql as
$$ select pg_temp.err(format('select public.create_customer_from_held_survey(%L, %L)', pg_temp.fx('hs:' || key), note)) $$;
create function pg_temp.close(key text, reason text default 'Sent twice') returns text language sql as
$$ select pg_temp.err(format('select public.close_held_health_survey(%L, %L)', pg_temp.fx('hs:' || key), reason)) $$;
create function pg_temp.visits(key text) returns int language sql as
$$ select count(*)::int from public.customer_centre_visit_days() v where v.survey_id = pg_temp.fx('hs:' || key) $$;

select pg_temp.check(to_regclass('public.health_survey_holds') is not null
    and position('433:' in (select prosrc from pg_proc where oid = to_regprocedure('public.submit_health_survey(text,jsonb,jsonb,text)'))) > 0
    and to_regprocedure('public.customer_names_match(text,text)') is not null,
  'P0 432 and 433 are installed');
select pg_temp.check(not exists (select 1 from public.customers where public.normalize_customer_phone(phone) like '+65843301__'),
  'P0 no customer uses the test phones +65 8433 01xx (the checks below assume so)');

-- ═════ Fixtures ═════
do $$
declare sfx text := lower(substr(md5(random()::text || clock_timestamp()::text), 1, 6)); k text; u uuid; c uuid;
begin
  insert into tx values ('sfx', sfx), ('token', 's433-' || sfx);
  foreach k in array array['o', 'm', 's', 'im', 'aff', 'ad'] loop
    u := gen_random_uuid(); insert into fx values (k, u);
    insert into auth.users(id, email, email_confirmed_at) values (u, 's433-' || k || '-' || sfx || '@tests.invalid', now());
  end loop;
  insert into profiles(id, full_name, email, role) values
    (pg_temp.fx('o'),  'S433 Owner',     's433-o-'  || sfx || '@tests.invalid', 'owner'),
    (pg_temp.fx('m'),  'S433 Manager',   's433-m-'  || sfx || '@tests.invalid', 'manager'),
    (pg_temp.fx('s'),  'S433 Staff',     's433-s-'  || sfx || '@tests.invalid', 'staff'),
    (pg_temp.fx('im'), 'S433 Inventory', 's433-im-' || sfx || '@tests.invalid', 'inventory_manager'),
    (pg_temp.fx('ad'), 'S433 Admin',     's433-ad-' || sfx || '@tests.invalid', 'admin');
  insert into stores(name, code) values ('S433 Test Store', 'S433' || sfx) returning id into c; insert into fx values ('store', c);
  insert into customer_source_options(label) values ('S433 Walk-in ' || sfx) returning id into c; insert into fx values ('src', c);
  insert into survey_links(token, store_id) values ('s433-' || sfx, pg_temp.fx('store')) returning id into c; insert into fx values ('link', c);

  insert into customers(full_name, phone, email) values ('Ann Lee Testtan', '+6584330101', 's433-ann-' || sfx || '@tests.invalid')
    returning id into c; insert into fx values ('c1', c);
  insert into customers(full_name, phone) values ('Mei Ling (Orchard) Testwong', '+6584330102') returning id into c; insert into fx values ('c2', c);
  insert into customers(full_name, phone, email) values ('Bee Hoon Testkoh', '+6584330103', 's433-bee-' || sfx || '@tests.invalid')
    returning id into c; insert into fx values ('c3', c);
  insert into customers(full_name, phone, email) values ('Siti Testgmail', '+6584330104', 's433sitigmail' || sfx || '@gmail.com')
    returning id into c; insert into fx values ('c4', c);
  insert into customers(full_name, phone, email) values ('Siew Lan (Office) Testchua', '+6584330105', 's433-siew-' || sfx || '@tests.invalid')
    returning id into c; insert into fx values ('c5', c);
  insert into customers(full_name, phone) values ('Pei Qi Testng', '+6584330106') returning id into c; insert into fx values ('c6a', c);
  insert into customers(full_name, phone) values ('Testng Pei Qi', '+6584330106') returning id into c; insert into fx values ('c6b', c);
  insert into customers(full_name, phone) values ('Fa One Testfull', '+6584330109') returning id into c; insert into fx values ('c9a', c);
  insert into customers(full_name, phone) values ('Fa Two Testfull', '+6584330109') returning id into c; insert into fx values ('c9b', c);
  insert into customers(full_name, phone) values ('Fa Three Testfull', '+6584330109') returning id into c; insert into fx values ('c9c', c);
  insert into customers(full_name, phone) values ('Del Testgone', '+6584330110') returning id into c; insert into fx values ('cDel', c);
  update customers set deleted_at = now() where id = c;
  -- Q11: one customer on the phone; another gets the form's email later.
  insert into customers(full_name, phone) values ('Mo Testlive', '+6584330111') returning id into c; insert into fx values ('c11', c);
  -- T: the customer whose email the TikTok lead's form gives.
  insert into customers(full_name, phone, email) values ('Rae Testshow', '+6584330121', 's433-rae-' || sfx || '@tests.invalid')
    returning id into c; insert into fx values ('cNS', c);
  -- A: a customer with no survey, not listed for any form.
  insert into customers(full_name, phone) values ('Out Testpick', '+6584330122') returning id into c; insert into fx values ('cOut', c);
  -- A: a customer with a one-word name.
  insert into customers(full_name, phone) values ('Annx', '+6584330123') returning id into c; insert into fx values ('c1w', c);
  -- A: the record another is merged into.
  insert into customers(full_name, phone) values ('Keep Testmerge', '+6584330124') returning id into c; insert into fx values ('cKeep', c);
end $$;
-- Q10: an old import whose phone cannot be read as one number (today's
-- check refuses such a phone, so it is written as old imports were).
alter table customers disable trigger zz_normalize_current_customer_phone;
do $$ declare c uuid; begin
  insert into customers(full_name, phone) values ('Lee Testlegacy', '84330160') returning id into c; insert into fx values ('c10', c);
end $$;
alter table customers enable trigger zz_normalize_current_customer_phone;
select pg_temp.check(public.normalize_customer_phone('84330160') is null
    and (public.inspect_customer_phone('84330160')->'candidates') ? '+6584330160',
  'P0 (setup) the old phone cannot be read as one number, but could be +65 8433 0160');
insert into tx values ('customers_before', (select count(*) from customers)::text);

-- ═════ Q1-Q2 Attached by themselves ═════
select pg_temp.submit('q1', 'Ann Lee Testtan', '+65 8433 0101', 's433-ann-' || pg_temp.tx('sfx') || '@tests.invalid');
select pg_temp.check(pg_temp.survey_customer('q1') = pg_temp.fx('c1') and pg_temp.hold('q1') is null
    and (pg_temp.reply('q1') - 'survey_no' - 'survey_id') = '{"success": true}'::jsonb,
  'Q1 exact phone and name: attached to the customer, as before; the reply says nothing about customers: ' || pg_temp.tx('sub:q1'));
select pg_temp.submit('q2', 'Testwong Meiling', '+65 8433 0102', 's433-mei-' || pg_temp.tx('sfx') || '@tests.invalid');
select pg_temp.check(pg_temp.survey_customer('q2') = pg_temp.fx('c2') and pg_temp.on_phone('+6584330102') = 1,
  'Q2 "Testwong Meiling" for "Mei Ling (Orchard) Testwong": attached by the same words, no second customer');
select pg_temp.check((select full_name from health_surveys where id = pg_temp.fx('hs:q2')) = 'Mei Ling (Orchard) Testwong'
    and (select new_data->>'typed_name' = 'Testwong Meiling' and new_data->>'name_match' = 'same_words'
           from audit_logs where action = 'health_survey_submitted' and record_id = pg_temp.fx('hs:q2')),
  'Q2 the form carries the customer''s name; the name typed is in the Audit Log');

-- ═════ Q3-Q6, Q9 Held for staff ═════
select pg_temp.submit('q3', 'Ah Kow Testkoh', '+65 8433 0103', 's433-ahkow-' || pg_temp.tx('sfx') || '@tests.invalid');
select pg_temp.check((pg_temp.reply('q3') - 'survey_no' - 'survey_id') = '{"success": true}'::jsonb
    and pg_temp.reply('q3')->>'survey_no' like 'HS-%',
  'Q3 a family member on a customer''s phone gets the same reply as anyone: ' || pg_temp.tx('sub:q3'));
select pg_temp.check(pg_temp.survey_customer('q3') is null and pg_temp.on_phone('+6584330103') = 1
    and (pg_temp.hold('q3')).reason = 'phone_in_use' and (pg_temp.hold('q3')).candidate_customer_ids = array[pg_temp.fx('c3')]
    and (pg_temp.hold('q3')).resolved_at is null
    and (pg_temp.hold('q3')).typed_full_name = 'Ah Kow Testkoh' and (pg_temp.hold('q3')).typed_phone = '+6584330103'
    and (pg_temp.hold('q3')).typed_email = 's433-ahkow-' || pg_temp.tx('sfx') || '@tests.invalid',
  'Q3 the form is kept with no customer and held (phone_in_use) for the customer with the phone, with what was typed; no customer made');
select pg_temp.submit('q4', 'Siti Rahmah Testgmail', '+65 8433 0114', 's433.siti.gmail' || pg_temp.tx('sfx') || '@gmail.com');
select pg_temp.check(pg_temp.survey_customer('q4') is null and pg_temp.on_phone('+6584330114') = 0
    and (pg_temp.hold('q4')).reason = 'email_in_use' and (pg_temp.hold('q4')).candidate_customer_ids = array[pg_temp.fx('c4')],
  'Q4 another phone but the same Gmail inbox (with dots): held (email_in_use), no customer made');
select pg_temp.submit('q5', 'Siew Laan Testchua', '+65 8433 0105', 's433-siew-' || pg_temp.tx('sfx') || '@tests.invalid');
select pg_temp.check(pg_temp.survey_customer('q5') is null and pg_temp.on_phone('+6584330105') = 1
    and (pg_temp.hold('q5')).reason = 'phone_and_email_in_use' and (pg_temp.hold('q5')).candidate_customer_ids = array[pg_temp.fx('c5')],
  'Q5 the same phone and email, the name spelt differently: held (phone_and_email_in_use) for that customer');
select pg_temp.submit('q6', 'Qi Pei Testng', '+65 8433 0106', 's433-qp-' || pg_temp.tx('sfx') || '@tests.invalid');
select pg_temp.check(pg_temp.survey_customer('q6') is null and (pg_temp.hold('q6')).reason = 'several_name_matches'
    and (select array_agg(x order by x) from unnest((pg_temp.hold('q6')).candidate_customer_ids) x)
        = (select array_agg(x order by x) from unnest(array[pg_temp.fx('c6a'), pg_temp.fx('c6b')]) x),
  'Q6 a name matching two customers on the phone is held (several_name_matches) for both, not refused: ' || pg_temp.tx('sub:q6'));
select pg_temp.submit('q9', 'Fa Four Testfull', '+65 8433 0109', 's433-fa4-' || pg_temp.tx('sfx') || '@tests.invalid');
select pg_temp.check(pg_temp.survey_customer('q9') is null and (pg_temp.hold('q9')).reason = 'phone_in_use'
    and cardinality((pg_temp.hold('q9')).candidate_customer_ids) = 3 and pg_temp.on_phone('+6584330109') = 3,
  'Q9 a phone 3 customers share: held for the three, not refused with CUSTOMER_PHONE_LIMIT: ' || pg_temp.tx('sub:q9'));

-- ═════ Q7 A new person ═════
select pg_temp.submit('q7', 'Nia Testnew', '+65 8433 0107', 's433-nia-' || pg_temp.tx('sfx') || '@tests.invalid');
select pg_temp.check(pg_temp.survey_customer('q7') is not null and pg_temp.on_phone('+6584330107') = 1
    and (select full_name from customers where id = pg_temp.survey_customer('q7')) = 'Nia Testnew' and pg_temp.hold('q7') is null,
  'Q7 a phone and email no customer has: a new customer, as before');

-- ═════ Q10 An old record whose phone cannot be read ═════
select pg_temp.submit('q10', 'Lee Testlegacy', '+65 8433 0160', 's433-lee-' || pg_temp.tx('sfx') || '@tests.invalid');
select pg_temp.check(pg_temp.tx('sub:q10') like 'ERROR: AMBIGUOUS_CUSTOMER_MATCH%' and pg_temp.on_phone('+6584330160') = 0,
  'Q10 the same name beside an old record whose phone could be this one: refused as before: ' || pg_temp.tx('sub:q10'));

-- ═════ Q11 Who has the phone or email now ═════
select pg_temp.submit('q11', 'Kai Testlive', '+65 8433 0111', 's433-kai-' || pg_temp.tx('sfx') || '@tests.invalid');
select pg_temp.check((pg_temp.hold('q11')).reason = 'phone_in_use' and (pg_temp.hold('q11')).candidate_customer_ids = array[pg_temp.fx('c11')],
  'Q11 (setup) held for the one customer with the phone');
do $$ declare c uuid; begin
  insert into customers(full_name, phone, email) values ('Kai Testlive Pos', '+6584330112', 's433-kai-' || pg_temp.tx('sfx') || '@tests.invalid')
    returning id into c; insert into fx values ('c11pos', c);
end $$;

-- ═════ Q8 Sending it again while it waits ═════
select pg_temp.submit('q8', 'Ah Kow Testkoh', '+65 8433 0103', 's433-ahkow-' || pg_temp.tx('sfx') || '@tests.invalid');
select pg_temp.submit('q8b', 'Testkoh Ah Kow', '+65 8433 0103', 's433-ahkow-' || pg_temp.tx('sfx') || '@tests.invalid');
select pg_temp.check(pg_temp.tx('sub:q8') like 'ERROR: HEALTH_SURVEY_ALREADY_EXISTS%' and pg_temp.tx('sub:q8b') like 'ERROR: HEALTH_SURVEY_ALREADY_EXISTS%'
    and (select count(*) from health_survey_holds h join health_surveys s on s.id = h.survey_id
          where public.normalize_customer_phone(s.phone) = '+6584330103') = 1,
  'Q8 the same person again while the form waits (also with the words in another order): HEALTH_SURVEY_ALREADY_EXISTS, no second form');

-- ═════ K Unchanged ═════
select pg_temp.submit('k1', 'Ann Lee Testtan', '+65 8433 0101', 's433-ann-' || pg_temp.tx('sfx') || '@tests.invalid');
select pg_temp.check(pg_temp.tx('sub:k1') like 'ERROR: HEALTH_SURVEY_ALREADY_EXISTS%',
  'K a customer who already has a survey is refused as before');
select pg_temp.check(
    (select count(*) = 4 and bool_and(case l.record_id
                       when pg_temp.fx('hs:q1') then (l.new_data->>'held_for_staff')::boolean = false and l.new_data->>'name_match' = 'exact'
                       when pg_temp.fx('hs:q2') then (l.new_data->>'held_for_staff')::boolean = false and l.new_data->>'name_match' = 'same_words'
                       when pg_temp.fx('hs:q3') then (l.new_data->>'held_for_staff')::boolean and l.new_data->>'hold_reason' = 'phone_in_use'
                                                    and not (l.new_data->>'customer_created')::boolean
                       when pg_temp.fx('hs:q7') then (l.new_data->>'customer_created')::boolean and l.new_data->>'hold_reason' is null end)
       from audit_logs l
      where l.action = 'health_survey_submitted'
        and l.record_id in (pg_temp.fx('hs:q1'), pg_temp.fx('hs:q2'), pg_temp.fx('hs:q3'), pg_temp.fx('hs:q7'))),
  'K the submission''s Audit Log row says whether it was held, why, and how the name matched');

-- ═════ L The list ═════
select pg_temp.as_user('s');
select pg_temp.check(pg_temp.listed('q3') is not null and pg_temp.listed('q4') is not null and pg_temp.listed('q5') is not null
    and pg_temp.listed('q6') is not null and pg_temp.listed('q9') is not null
    and pg_temp.listed('q1') is null and pg_temp.listed('q7') is null,
  'L staff see the waiting forms, and only those');
select pg_temp.check(pg_temp.listed('q5')->>'full_name' = 'Siew Laan Testchua' and pg_temp.listed('q5')->>'reason' = 'phone_and_email_in_use'
    and pg_temp.listed('q5')->>'phone' = '+6584330105' and pg_temp.listed('q5')->>'date_of_birth' = '1980-02-03'
    and pg_temp.listed('q5')->>'store_name' = 'S433 Test Store'
    and (pg_temp.candidate('q5', 'c5')->>'phone_matches')::boolean and (pg_temp.candidate('q5', 'c5')->>'email_matches')::boolean
    and not (pg_temp.candidate('q5', 'c5')->>'name_matches')::boolean and pg_temp.candidate('q5', 'c5')->>'survey_no' is null,
  'L each form shows what was typed and, per customer, whether the phone, the email and the name match, and any survey');
select pg_temp.check(not (pg_temp.candidate('q4', 'c4')->>'phone_matches')::boolean and (pg_temp.candidate('q4', 'c4')->>'email_matches')::boolean
    and (pg_temp.candidate('q6', 'c6a')->>'name_matches')::boolean and (pg_temp.candidate('q6', 'c6b')->>'name_matches')::boolean
    and jsonb_array_length(pg_temp.listed('q9')->'candidates') = 3,
  'L the email-only form shows the email match; the several-names form shows both names matching');
select pg_temp.check(pg_temp.candidate('q11', 'c11') is not null and (pg_temp.candidate('q11', 'c11pos')->>'email_matches')::boolean
    and jsonb_array_length(pg_temp.listed('q11')->'candidates') = 2,
  'L a customer who got the form''s email after it was held is listed too');
select pg_temp.as_user('ad');
select pg_temp.check(pg_temp.listed('q3') is not null, 'L an Admin may list them');
select pg_temp.as_user('im');
select pg_temp.check(pg_temp.err('select public.health_survey_holds_list()') = 'Your role cannot do this.',
  'L an inventory manager cannot list them');
select pg_temp.as_user('aff');
select pg_temp.check(pg_temp.err('select public.health_survey_holds_list()') = 'Only active Energia staff can do this.',
  'L a login with no staff profile cannot list them');

-- ═════ A Attach ═════
select pg_temp.as_user('s');
insert into tx values ('q5_visits_before', pg_temp.visits('q5')::text);
select pg_temp.check(pg_temp.attach('q5', 'c5', '  ') = 'Add a short note on how you confirmed this is the same person.'
    and pg_temp.survey_customer('q5') is null,
  'A a note is required');
select pg_temp.check(pg_temp.attach('q5', 'c5') = 'ok', 'A staff attach the spelling-variant form to the customer');
select pg_temp.check(pg_temp.survey_customer('q5') = pg_temp.fx('c5') and (pg_temp.hold('q5')).resolution = 'attached'
    and (pg_temp.hold('q5')).resolved_by = pg_temp.fx('s') and (pg_temp.hold('q5')).resolved_customer_id = pg_temp.fx('c5')
    and (pg_temp.hold('q5')).resolution_note = 'Checked her IC at the counter',
  'A the form is the customer''s now, and the hold records who, when and why');
select pg_temp.check((select full_name = 'Siew Lan (Office) Testchua' and phone = '+6584330105'
                         and date_of_birth = '1980-02-03' and gender = 'female' and occupation = 'Tester'
                         and source_option_id = pg_temp.fx('src') and email = 's433-siew-' || pg_temp.tx('sfx') || '@tests.invalid'
                        from customers where id = pg_temp.fx('c5')),
  'A the customer''s empty details are filled from the form, never the name or phone');
select pg_temp.check((select full_name = 'Siew Lan (Office) Testchua' and phone = '+6584330105'
                         and email = 's433-siew-' || pg_temp.tx('sfx') || '@tests.invalid'
                        from health_surveys where id = pg_temp.fx('hs:q5'))
    and (select old_data->>'typed_name' = 'Siew Laan Testchua' and old_data->>'typed_phone' = '+6584330105'
           from audit_logs where action = 'health_survey_matched' and record_id = pg_temp.fx('hs:q5')),
  'A the form carries the customer''s name and keeps the phone and email typed; the Audit Log has what was typed');
-- Edit details on the attached form, as the Surveys page saves it: the form's
-- own values, with only the date of birth changed.
insert into tx values ('edit_q5', pg_temp.err(format(
  'select public.update_survey_particulars(%L, %L, %L, %L, %L, %L::date, %L, %L, %L, %L::uuid, %L, null, null, null, null, null, null)',
  pg_temp.fx('hs:q5'),
  (select first_name from health_surveys where id = pg_temp.fx('hs:q5')),
  (select last_name from health_surveys where id = pg_temp.fx('hs:q5')),
  (select phone from health_surveys where id = pg_temp.fx('hs:q5')),
  (select email from health_surveys where id = pg_temp.fx('hs:q5')),
  '1980-02-04', 'female', 'Tester', null, pg_temp.fx('src'), null)));
select pg_temp.check(pg_temp.tx('edit_q5') = 'ok'
    and (select full_name from customers where id = pg_temp.fx('c5')) = 'Siew Lan (Office) Testchua'
    and (select date_of_birth from customers where id = pg_temp.fx('c5')) = '1980-02-04',
  'A saving the attached form''s details does not rename the customer: ' || pg_temp.tx('edit_q5'));
select pg_temp.submit('q5again', 'Siew Laan Testchua', '+65 8433 0105', 's433-siew-' || pg_temp.tx('sfx') || '@tests.invalid');
select pg_temp.check(pg_temp.tx('sub:q5again') like 'ERROR: HEALTH_SURVEY_ALREADY_EXISTS%',
  'A sending the form again after staff attached it: refused as a second survey, not held again: ' || pg_temp.tx('sub:q5again'));
select pg_temp.check(pg_temp.tx('q5_visits_before')::int = 0 and pg_temp.visits('q5') = 1,
  'A the form counts as a visit only once it is attached');
select pg_temp.check(pg_temp.listed('q5') is null
    and exists (select 1 from audit_logs where table_name = 'health_surveys' and record_id = pg_temp.fx('hs:q5')
                  and action = 'health_survey_matched' and changed_by = pg_temp.fx('s') and actor_role = 'staff'
                  and module = 'health_survey' and reason = 'Checked her IC at the counter'
                  and (new_data->>'customer_id')::uuid = pg_temp.fx('c5') and (new_data->>'suggested_customer')::boolean),
  'A it leaves the list, and the Audit Log records the match');
select pg_temp.check(pg_temp.attach('q5', 'c5') = 'This form has already been dealt with.'
    and pg_temp.attach('q4', 'c1') like 'This customer already has a health survey (HS-%). A customer can have only one.'
    and pg_temp.attach('q4', 'cDel') = 'Customer not found.'
    and pg_temp.survey_customer('q4') is null,
  'A refused: a form already attached, a customer with a survey already, a deleted customer');
select pg_temp.as_user('im');
select pg_temp.check(pg_temp.attach('q4', 'c4') = 'Your role cannot do this.' and pg_temp.survey_customer('q4') is null,
  'A an inventory manager cannot attach');
select pg_temp.as_user('o');
insert into tx values ('attach_q4', pg_temp.attach('q4', 'c4', 'Same Gmail inbox; she confirmed her old number'));
select pg_temp.check(pg_temp.tx('attach_q4') = 'ok'
    and pg_temp.survey_customer('q4') = pg_temp.fx('c4')
    and (select phone from customers where id = pg_temp.fx('c4')) = '+6584330104',
  'A an Owner attaches the email-only form; the customer''s phone stays theirs');

select pg_temp.submit('q1w', 'Anniex Testlee', '+65 8433 0123', 's433-anniex-' || pg_temp.tx('sfx') || '@tests.invalid');
insert into tx values ('attach_q1w', pg_temp.attach('q1w', 'c1w'));
select pg_temp.check(pg_temp.tx('attach_q1w') = 'ok'
    and (select full_name = 'Annx' and first_name = 'Annx' and last_name is null from health_surveys where id = pg_temp.fx('hs:q1w')),
  'A a customer with a one-word name: the form takes it as it is, not mixed with the surname typed');
insert into tx values ('edit_q1w', pg_temp.err(format(
  'select public.update_survey_particulars(%L, %L, %L, %L, %L, %L::date, %L, %L, %L, %L::uuid, %L, null, null, null, null, null, null)',
  pg_temp.fx('hs:q1w'),
  (select first_name from health_surveys where id = pg_temp.fx('hs:q1w')),
  (select last_name from health_surveys where id = pg_temp.fx('hs:q1w')),
  (select phone from health_surveys where id = pg_temp.fx('hs:q1w')),
  (select email from health_surveys where id = pg_temp.fx('hs:q1w')),
  '1980-02-03', 'female', 'Tester', null, pg_temp.fx('src'), null)));
select pg_temp.check(pg_temp.tx('edit_q1w') = 'ok' and (select full_name from customers where id = pg_temp.fx('c1w')) = 'Annx',
  'A saving that form''s details leaves the customer''s one-word name alone: ' || pg_temp.tx('edit_q1w'));
insert into tx values ('attach_q6', pg_temp.attach('q6', 'cOut', 'She is not either of the two; her own record was made at the counter'));
select pg_temp.check(pg_temp.tx('attach_q6') = 'ok' and pg_temp.survey_customer('q6') = pg_temp.fx('cOut')
    and not ((select new_data from audit_logs where action = 'health_survey_matched' and record_id = pg_temp.fx('hs:q6'))->>'suggested_customer')::boolean,
  'A staff may attach a form to a customer it was not held for; the Audit Log says so');

-- ═════ C Make a new customer from a form ═════
select pg_temp.as_user('s');
select pg_temp.check(pg_temp.make('q3') = 'ok', 'C staff make a customer from the family member''s form');
select pg_temp.check(pg_temp.on_phone('+6584330103') = 2
    and (select full_name = 'Ah Kow Testkoh' and email = 's433-ahkow-' || pg_temp.tx('sfx') || '@tests.invalid'
                and date_of_birth = '1980-02-03' and source_option_id = pg_temp.fx('src')
           from customers where id = pg_temp.survey_customer('q3'))
    and pg_temp.survey_customer('q3') <> pg_temp.fx('c3') and (pg_temp.hold('q3')).resolution = 'created'
    and exists (select 1 from audit_logs where record_id = pg_temp.fx('hs:q3') and action = 'health_survey_customer_created'
                  and changed_by = pg_temp.fx('s')),
  'C the new customer has the form''s details and the form; the phone''s first customer is untouched');
select pg_temp.check(pg_temp.make('q9') like '%CUSTOMER_PHONE_LIMIT%' and pg_temp.survey_customer('q9') is null
    and (pg_temp.hold('q9')).resolved_at is null and pg_temp.on_phone('+6584330109') = 3,
  'C on a phone 3 customers share, no fourth is made, and the form still waits: ' || pg_temp.make('q9'));

-- A merge of the customer made from the family member's form into another
-- record moves the form there (as merge_customer_records does) and retires
-- the customer: sending the same form again is still refused.
update health_surveys set customer_id = pg_temp.fx('cKeep') where id = pg_temp.fx('hs:q3');
update customers set deleted_at = now() where id = (select resolved_customer_id from health_survey_holds where survey_id = pg_temp.fx('hs:q3'));
select pg_temp.submit('q3again', 'Ah Kow Testkoh', '+65 8433 0103', 's433-ahkow-' || pg_temp.tx('sfx') || '@tests.invalid');
select pg_temp.check(pg_temp.tx('sub:q3again') like 'ERROR: HEALTH_SURVEY_ALREADY_EXISTS%',
  'A once a merge moved the form to the kept record, sending it again is still refused: ' || pg_temp.tx('sub:q3again'));
-- The customer the Owner attached the email-only form to is deleted: the
-- form is no longer anyone's, and the person may send it again.
update customers set deleted_at = now() where id = pg_temp.fx('c4');
select pg_temp.submit('q4again', 'Siti Rahmah Testgmail', '+65 8433 0114', 's433.siti.gmail' || pg_temp.tx('sfx') || '@gmail.com');
select pg_temp.check(pg_temp.reply('q4again') is not null,
  'A once the customer of an attached form is deleted, the person may send it again: ' || pg_temp.tx('sub:q4again'));

-- ═════ X Close ═════
select pg_temp.check(pg_temp.close('q9') = 'Your role cannot do this.', 'X staff cannot close a form');
select pg_temp.as_user('m');
select pg_temp.check(pg_temp.close('q9', ' ') = 'A reason is required.', 'X a reason is required');
insert into tx values ('close_q9', pg_temp.close('q9'));
select pg_temp.check(pg_temp.tx('close_q9') = 'ok' and (pg_temp.hold('q9')).resolution = 'closed'
    and pg_temp.survey_customer('q9') is null and exists (select 1 from health_surveys where id = pg_temp.fx('hs:q9'))
    and pg_temp.listed('q9') is null
    and exists (select 1 from audit_logs where record_id = pg_temp.fx('hs:q9') and action = 'health_survey_hold_closed'
                  and actor_role = 'manager' and reason = 'Sent twice'),
  'X a Manager closes it: off the list, kept with no customer, in the Audit Log');
select pg_temp.submit('q9again', 'Fa Four Testfull', '+65 8433 0109', 's433-fa4-' || pg_temp.tx('sfx') || '@tests.invalid');
select pg_temp.check(pg_temp.reply('q9again') is not null and (pg_temp.hold('q9again')).reason = 'phone_in_use',
  'X the person may send the form again; it waits again: ' || pg_temp.tx('sub:q9again'));

-- ═════ N Signed out ═════
-- The helpers live in this session's temporary schema, which a signed-out
-- role cannot use: what they give is read first, then the role is switched.
do $$
declare r jsonb; v_list text; v_attach text; v_read text; v_token text := pg_temp.tx('token'); v_src uuid := pg_temp.fx('src');
        v_survey uuid; v_cust uuid := pg_temp.fx('c3'); v_sfx text := pg_temp.tx('sfx');
begin
  execute 'set local role anon';
  r := public.submit_health_survey(v_token,
         jsonb_build_object('full_name', 'Lin Testanon', 'phone', '+65 8433 0103', 'email', 's433-lin-' || v_sfx || '@tests.invalid',
                            'signature_data', 'data:image/png;base64,AAAA', 'source_option_id', v_src),
         null, null);
  begin perform public.health_survey_holds_list(); v_list := 'callable';
  exception when insufficient_privilege then v_list := 'refused'; end;
  begin perform public.attach_held_health_survey((r->>'survey_id')::uuid, v_cust, 'x'); v_attach := 'callable';
  exception when insufficient_privilege then v_attach := 'refused'; end;
  begin perform 1 from public.health_survey_holds; v_read := 'readable';
  exception when insufficient_privilege then v_read := 'refused'; end;
  execute 'reset role';
  insert into tx values ('anon_reply', r::text), ('anon_list', v_list), ('anon_attach', v_attach), ('anon_read', v_read);
  insert into fx values ('hs:anon', (r->>'survey_id')::uuid);
end $$;
select pg_temp.check((pg_temp.tx('anon_reply')::jsonb->>'success')::boolean and (pg_temp.hold('anon')).reason = 'phone_in_use'
    and pg_temp.survey_customer('anon') is null,
  'N signed out, a form on a customer''s phone is held as above: ' || pg_temp.tx('anon_reply'));
select pg_temp.check(pg_temp.tx('anon_list') = 'refused' and pg_temp.tx('anon_attach') = 'refused' and pg_temp.tx('anon_read') = 'refused',
  'N signed out, nobody can list, attach or read the waiting forms');

-- ═════ T The TikTok no-show run ═════
do $$ begin
  insert into tx values ('ns_day', ((now() - interval '2 hours') at time zone 'Asia/Singapore')::date::text);
  insert into ads_leads(lead_id, first_name, last_name, email, phone_e164, phone_status)
  values ('s433-lead-' || pg_temp.tx('sfx'), 'Rae', 'Testlead', 's433-raelead-' || pg_temp.tx('sfx') || '@tests.invalid',
          public.ads_normalize_phone('+6584330120'), 'valid');   -- the engine keeps phones as 65..., no plus
  insert into ads_appointments(calendar_id, event_id, lead_id, starts_at, status)
  values ('s433-cal', 's433-ev-' || pg_temp.tx('sfx'), 's433-lead-' || pg_temp.tx('sfx'), now() - interval '2 hours', 'active');
end $$;
create function pg_temp.no_show_count() returns int language sql as
$$ select (public.ads_rpc_no_show_run(null, null, null,
             json_build_object('dry_run', true, 'skip_present_check', true, 'test_phone', '+6584330120',
                               'day', pg_temp.tx('ns_day'))::text)->>'count')::int $$;
insert into tx values ('ns_before', pg_temp.no_show_count()::text);
select pg_temp.submit('qT', 'Rae Testshow', '+65 8433 0120', 's433-rae-' || pg_temp.tx('sfx') || '@tests.invalid');
select pg_temp.check((pg_temp.hold('qT')).reason = 'email_in_use' and pg_temp.survey_customer('qT') is null,
  'T (setup) the lead''s form, from a new phone and a customer''s email, waits for staff');
insert into tx values ('ns_after', pg_temp.no_show_count()::text);
select pg_temp.check(pg_temp.tx('ns_before') = '1' and pg_temp.tx('ns_after') = '0',
  'T the no-show run would message the lead before the form came (' || pg_temp.tx('ns_before') || '), and not once it waits for staff ('
  || pg_temp.tx('ns_after') || ')');
select pg_temp.as_user('m');
insert into tx values ('close_qT', pg_temp.close('qT', 'Her old record has a survey already'));
insert into tx values ('ns_closed', pg_temp.no_show_count()::text);
select pg_temp.check(pg_temp.tx('close_qT') = 'ok' and pg_temp.tx('ns_closed') = '0',
  'T once a Manager closed the form, the person still came: not messaged (' || pg_temp.tx('ns_closed') || ')');
select pg_temp.as_user('o');

-- ═════ What the form made ═════
select pg_temp.check((select count(*) from customers) = pg_temp.tx('customers_before')::int + 4,
  'Only Q7 (a new person), C (made by staff), the test''s own later customer (Q11) and the form sent again once its customer was deleted added customers: no form made one it was unsure about');

-- ═════ G Grants ═════
select pg_temp.check(bool_and(has_function_privilege('authenticated', f, 'execute') and not has_function_privilege('anon', f, 'execute')),
  'G the four new functions: signed-in users (each checks the caller), not anon')
  from unnest(array['public.health_survey_holds_list()', 'public.attach_held_health_survey(uuid,uuid,text)',
                    'public.create_customer_from_held_survey(uuid,text)', 'public.close_held_health_survey(uuid,text)']) f;
select pg_temp.check(has_function_privilege('anon', 'public.submit_health_survey(text,jsonb,jsonb,text)', 'execute')
    and not has_table_privilege('anon', 'public.health_survey_holds', 'select,insert,update,delete')
    and not has_table_privilege('authenticated', 'public.health_survey_holds', 'select,insert,update,delete')
    and (select relrowsecurity from pg_class where oid = 'public.health_survey_holds'::regclass),
  'G the form stays callable signed out; the waiting list''s table is no client''s');

-- ═════ M The tested versions ═════
select pg_temp.check(not exists (select 1 from m433 m
                                   left join pg_proc p on p.oid::regprocedure::text = m.fn and p.pronamespace = 'public'::regnamespace
                                  where p.oid is null or md5(pg_get_functiondef(p.oid)) <> m.md5)
    and (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f') = (select count(*) from m433),
  'M running 433 a second time changed no function');
select pg_temp.check(bool_and(md5(pg_get_functiondef(to_regprocedure(fn))) = ok),
  'M the functions are 433''s AFTER versions')
  from (values ('public.submit_health_survey(text,jsonb,jsonb,text)',     '5a3f27a0b9a0bed619ac0c82c8c52aab'),
               ('public.ads_rpc_no_show_run(text,text,text,text)',      'b0499ec3ab207e66e8c56e2f01ba3978'),
               ('public.health_survey_holds_list()',                    'c3f50d90ba0509935681e4446bcbb21b'),
               ('public.attach_held_health_survey(uuid,uuid,text)',     '104370324b701192ba9710d515cc388f'),
               ('public.create_customer_from_held_survey(uuid,text)',   'd503d8b599f90768c8d909b91cd453e1'),
               ('public.close_held_health_survey(uuid,text)',           'ee4789b1d716e4fbf498a5f38e722735')) t(fn, ok);

do $$ declare v_failed int; begin
  select count(*) into v_failed from failed;
  if v_failed > 0 then raise exception '% check(s) failed: %', v_failed, (select string_agg(msg, '; ' order by n) from failed); end if;
  raise notice 'All qr-holds checks passed.';
end $$;
rollback;
