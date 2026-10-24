-- The QR health survey attaches a form whose phone and email are one
-- customer's at once (468); one for a customer who already has a survey
-- waits quietly for staff.
--
-- The Owner, 24 Oct 2026: "if the customer phone number and the email is the
-- same match them at once should not ask to match. If more than one customer,
-- ask to attach and there should be a delete option ... If the customer has
-- only the same phone number, it should be ask. If the customer has only the
-- same email, it should be asked."
--
-- The Owner's later answers the same day: A (a form found only by the phone
-- and the email, for a customer who already has a survey, waits quietly),
-- B (such a form fills none of the customer's details), C (the public
-- page's words; not here) and D (namesakes; below).
--
--   S1 One customer in use has the phone and the email: the form is theirs at
--      once under another name (the phone typed with spaces, the email in
--      capitals; a Gmail address with dots, a +tag and googlemail.com), also
--      when another customer shares the phone only and another the email
--      only. The form carries the customer's name parts and keeps the phone
--      and email typed; the customer's name and phone stay; it counts as a
--      visit; the reply says nothing about customers; the Audit Log says
--      phone_and_email. Signed out too.
--   B  Such a form fills none of the customer's empty details (date of birth,
--      sex, occupation, email, how they heard); the form keeps what was
--      typed. A phone and name match fills them, as today (also among
--      namesakes, where the email picks one). A consultant's record taking
--      such a form fills none either.
--   S2 Phone + name first: the name as typed, or the same words, picks its
--      customer even when another customer has the phone and the email. When
--      the name matches several on the phone: one customer in use with the
--      phone and the email, and one of them, takes the form; two of them with
--      it, and the form waits (several_name_matches); only a customer of
--      another name with it, and the form waits for the namesakes (open
--      choice, D); a namesake and a customer of another name both with it (S3),
--      and the form waits for all three, the two with both shown as such.
--      A form waiting on the phone and email under another name does not stop
--      a customer's own form by name (a twin, a household member).
--   S3 Two customers in use with the phone and the email (also a Gmail
--      spelling): the form waits (phone_and_email_in_use) with both; the list
--      shows each with the phone and the email matching. Staff cannot delete
--      either; a Manager typing another name is refused; a Manager deletes
--      one (the app's delete_customer); the list shows it retired and the
--      other still with both; staff attach the form to the other.
--   S4 Only the phone: waits (phone_in_use). Only the email: waits
--      (email_in_use). Neither: a new customer. A deleted customer with both
--      does not count. An old record whose phone cannot be read, with the
--      email: waits (email_in_use), as 433 treats such phones.
--   A  A customer found ONLY by the phone and the email who already has a
--      survey: the form is not refused; it waits (phone_and_email_customer_
--      has_survey) with that customer and no customer of its own, the reply
--      as any other; the Audit Log says why. Sent again, also under the same
--      name: waits again, never refused. Staff cannot attach it to them (one
--      survey), can make a new customer from it; a Manager can close it. An
--      old survey with no customer with the phone and the name typed: waits
--      too. A phone and name match (also the same words, also a namesake
--      the email picks) is still refused (HEALTH_SURVEY_ALREADY_EXISTS).
--      One whose survey is a consultant's record they have not signed: the
--      form goes into it (419).
--   O  A stranger's two forms with a phone (or an email, also as Gmail
--      spellings) and a throwaway email (or phone), under two names: the
--      second waits alike whether the phone or email is a customer's or
--      nobody's, with the same reply, so the reply tells nothing (433's rule).
--   K  No form made a customer it was unsure about.
--   G  Grants. M  468 installs itself here twice (unless -v skip_install=1,
--      where it is in); the second run changes nothing; the function and the
--      reason check are the tested ones.
--
-- Every check runs, then the file fails if any did. Disposable database only;
-- everything is rolled back. Needs 419, 433 and production as of 24 Oct 2026
-- (head 463).
-- Every name, phone and email below is invented: phones from the ACMA's
-- fictional range (+61 491 570 5xx), emails @example.invalid, and Gmail
-- addresses with a random suffix (nothing is ever sent).
--   psql -v ON_ERROR_STOP=1 [-v skip_install=1] -f scripts/survey/tests/to-match-468.sql
\set ON_ERROR_STOP on
begin;
\if :{?skip_install}
create temp table m468 as
  select p.oid::regprocedure::text as fn, md5(pg_get_functiondef(p.oid)) as md5
    from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f'
  union all
  select 'constraint ' || c.conrelid::regclass::text || ' ' || c.conname, md5(pg_get_constraintdef(c.oid))
    from pg_constraint c where c.conrelid = 'public.health_survey_holds'::regclass;
\else
\ir ../../../supabase/468_qr_survey_phone_and_email_match.sql
create temp table m468 as
  select p.oid::regprocedure::text as fn, md5(pg_get_functiondef(p.oid)) as md5
    from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f'
  union all
  select 'constraint ' || c.conrelid::regclass::text || ' ' || c.conname, md5(pg_get_constraintdef(c.oid))
    from pg_constraint c where c.conrelid = 'public.health_survey_holds'::regclass;
\ir ../../../supabase/468_qr_survey_phone_and_email_match.sql
\endif
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
$$ select set_config('request.jwt.claim.sub', coalesce(pg_temp.fx(key)::text, ''), true),
          set_config('request.jwt.claim.role', 'authenticated', true) $$;
create function pg_temp.as_server() returns void language sql as
$$ select set_config('request.jwt.claim.sub', '', true), set_config('request.jwt.claim.role', '', true) $$;
create function pg_temp.err(q text) returns text language plpgsql as
$$begin execute q; return 'ok'; exception when others then return sqlerrm; end$$;
create function pg_temp.mail(local text) returns text language sql as
$$ select 'z468-' || local || '-' || pg_temp.tx('sfx') || '@example.invalid' $$;
-- A QR form as the public page sends it (first and last name apart, as since
-- 419); keeps the reply (or the error) under 'sub:<key>' and the survey under
-- 'hs:<key>'.
create function pg_temp.submit(key text, first text, last text, phone text, email text) returns void language plpgsql as
$$declare r jsonb; begin
  r := public.submit_health_survey(pg_temp.tx('token'),
         jsonb_build_object('first_name', first, 'last_name', last, 'phone', phone, 'email', email,
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
create function pg_temp.survey(key text) returns public.health_surveys language sql as
$$ select s from public.health_surveys s where s.id = pg_temp.fx('hs:' || key) $$;
create function pg_temp.survey_customer(key text) returns uuid language sql as
$$ select customer_id from public.health_surveys where id = pg_temp.fx('hs:' || key) $$;
create function pg_temp.hold(key text) returns public.health_survey_holds language sql as
$$ select h from public.health_survey_holds h where h.survey_id = pg_temp.fx('hs:' || key) $$;
create function pg_temp.held_for(key text) returns uuid[] language sql as
$$ select array_agg(x order by x) from unnest((pg_temp.hold(key)).candidate_customer_ids) x $$;
create function pg_temp.ids(variadic keys text[]) returns uuid[] language sql as
$$ select array_agg(pg_temp.fx(k) order by pg_temp.fx(k)) from unnest(keys) k $$;
create function pg_temp.submitted(key text) returns jsonb language sql as
$$ select new_data from public.audit_logs where action = 'health_survey_submitted' and record_id = pg_temp.fx('hs:' || key) $$;
create function pg_temp.listed(key text) returns jsonb language sql as
$$ select e from jsonb_array_elements(public.health_survey_holds_list()) e where (e->>'survey_id')::uuid = pg_temp.fx('hs:' || key) $$;
create function pg_temp.candidate(key text, cust text) returns jsonb language sql as
$$ select c from jsonb_array_elements(pg_temp.listed(key)->'candidates') c where (c->>'customer_id')::uuid = pg_temp.fx(cust) $$;
create function pg_temp.attach(key text, cust text, note text default 'Checked her IC at the counter') returns text language sql as
$$ select pg_temp.err(format('select public.attach_held_health_survey(%L, %L, %L)', pg_temp.fx('hs:' || key), pg_temp.fx(cust), note)) $$;
create function pg_temp.del(cust text, typed text, reason text default 'Duplicate record of the same person') returns text language sql as
$$ select pg_temp.err(format('select public.delete_customer(%L, %L, %L)', pg_temp.fx(cust), typed, reason)) $$;
create function pg_temp.visits(key text) returns int language sql as
$$ select count(*)::int from public.customer_centre_visit_days() v where v.survey_id = pg_temp.fx('hs:' || key) $$;
-- B: the details a form fills on its customer, as they are now.
create function pg_temp.details(cust text) returns text language sql as
$$ select concat_ws('|', email, date_of_birth, gender, occupation, source_option_id, source_label, source_details)
     from customers where id = pg_temp.fx(cust) $$;
create function pg_temp.make(key text) returns text language sql as
$$ select pg_temp.err(format('select public.create_customer_from_held_survey(%L, %L)', pg_temp.fx('hs:' || key), 'A family member')) $$;
create function pg_temp.close_form(key text) returns text language sql as
$$ select pg_temp.err(format('select public.close_held_health_survey(%L, %L)', pg_temp.fx('hs:' || key), 'The same person again')) $$;

select pg_temp.check(md5(pg_get_functiondef('public.submit_health_survey(text,jsonb,jsonb,text)'::regprocedure))
                     = '014a970de2e5dee64e4027459cac5280'
    and (select md5(pg_get_constraintdef(oid)) from pg_constraint
          where conrelid = 'public.health_survey_holds'::regclass and conname = 'health_survey_holds_reason_check')
        = '378c1861f7ffacb38d2e6e8c69e45cc8',
  'P0 468 is installed (submit_health_survey and the reason check are its AFTER versions)');
select pg_temp.check(not exists (select 1 from public.customers where public.normalize_customer_phone(phone) like '+614915705__')
    and not exists (select 1 from public.health_surveys where public.normalize_customer_phone(phone) like '+614915705__'),
  'P0 no customer or survey uses the test phones +61 491 570 5xx (the checks below assume so)');

-- ═════ Fixtures ═════
do $$
declare sfx text := lower(substr(md5(random()::text || clock_timestamp()::text), 1, 6)); k text; u uuid; c uuid;
begin
  insert into tx values ('sfx', sfx), ('token', 'z468-' || sfx);
  foreach k in array array['o', 'm', 's', 'im'] loop
    u := gen_random_uuid(); insert into fx values (k, u);
    insert into auth.users(id, email, email_confirmed_at) values (u, 'z468-' || k || '-' || sfx || '@example.invalid', now());
  end loop;
  insert into profiles(id, full_name, email, role) values
    (pg_temp.fx('o'),  'Z468 Owner',     'z468-o-'  || sfx || '@example.invalid', 'owner'),
    (pg_temp.fx('m'),  'Z468 Manager',   'z468-m-'  || sfx || '@example.invalid', 'manager'),
    (pg_temp.fx('s'),  'Z468 Staff',     'z468-s-'  || sfx || '@example.invalid', 'staff'),
    (pg_temp.fx('im'), 'Z468 Inventory', 'z468-im-' || sfx || '@example.invalid', 'inventory_manager');
  insert into stores(name, code) values ('Z468 Test Store', 'Z468' || sfx) returning id into c; insert into fx values ('store', c);
  insert into customer_source_options(label) values ('Z468 Walk-in ' || sfx) returning id into c; insert into fx values ('src', c);
  insert into survey_links(token, store_id) values ('z468-' || sfx, pg_temp.fx('store'));

  -- S1: Ana has the phone and the email; Ben shares the phone only; Cara has
  -- the email only, on another phone.
  insert into customers(full_name, phone, email) values ('Ana Testone', '+61491570501', pg_temp.mail('ana')) returning id into c; insert into fx values ('cAna', c);
  insert into customers(full_name, phone) values ('Ben Testone', '+61491570501') returning id into c; insert into fx values ('cBen', c);
  insert into customers(full_name, phone, email) values ('Cara Testmail', '+61491570551', pg_temp.mail('ana')) returning id into c; insert into fx values ('cCara', c);
  -- S1 Gmail: the record has dots; the form a +tag and googlemail.com.
  insert into customers(full_name, phone, email) values ('Gina Testgmail', '+61491570502', 'z.468.gina.' || sfx || '@gmail.com')
    returning id into c; insert into fx values ('cGina', c);
  -- S2: Dee and Eve share a phone; Eve has the email the form gives.
  insert into customers(full_name, phone, email) values ('Dee Testprec', '+61491570503', pg_temp.mail('dee')) returning id into c; insert into fx values ('cDee', c);
  insert into customers(full_name, phone, email) values ('Eve Testprec', '+61491570503', pg_temp.mail('eve')) returning id into c; insert into fx values ('cEve', c);
  -- S2 namesakes: two Fays on a phone, one with the email.
  insert into customers(full_name, phone, email) values ('Fay Testtwin', '+61491570504', pg_temp.mail('fay')) returning id into c; insert into fx values ('cFay1', c);
  insert into customers(full_name, phone) values ('Fay Testtwin', '+61491570504') returning id into c; insert into fx values ('cFay2', c);
  -- S2 namesakes: two Guses, both with the email.
  insert into customers(full_name, phone, email) values ('Gus Testmany', '+61491570505', pg_temp.mail('gus')) returning id into c; insert into fx values ('cGus1', c);
  insert into customers(full_name, phone, email) values ('Gus Testmany', '+61491570505', pg_temp.mail('gus')) returning id into c; insert into fx values ('cGus2', c);
  -- S2 namesakes: two Hals with no email; Ida, on the phone, has the email.
  insert into customers(full_name, phone) values ('Hal Testother', '+61491570506') returning id into c; insert into fx values ('cHal1', c);
  insert into customers(full_name, phone) values ('Hal Testother', '+61491570506') returning id into c; insert into fx values ('cHal2', c);
  insert into customers(full_name, phone, email) values ('Ida Testother', '+61491570506', pg_temp.mail('ida')) returning id into c; insert into fx values ('cIda', c);
  -- S2/S3: two Faes on a phone, one with the email; Zed, of another name,
  -- has the phone and the email too.
  insert into customers(full_name, phone, email) values ('Fae Testboth', '+61491570517', pg_temp.mail('fae')) returning id into c; insert into fx values ('cFae1', c);
  insert into customers(full_name, phone) values ('Fae Testboth', '+61491570517') returning id into c; insert into fx values ('cFae2', c);
  insert into customers(full_name, phone, email) values ('Zed Testboth', '+61491570517', pg_temp.mail('fae')) returning id into c; insert into fx values ('cZed', c);
  -- S2 kept: Tara and Theo share a phone and an email; Uma's phone a
  -- household member uses with an email of their own.
  insert into customers(full_name, phone, email) values ('Tara Testtwin', '+61491570526', pg_temp.mail('tt')) returning id into c; insert into fx values ('cTara', c);
  insert into customers(full_name, phone, email) values ('Theo Testtwin', '+61491570526', pg_temp.mail('tt')) returning id into c; insert into fx values ('cTheo', c);
  insert into customers(full_name, phone, email) values ('Uma Testhouse', '+61491570527', pg_temp.mail('uma')) returning id into c; insert into fx values ('cUma', c);
  -- O: Oscar's phone, Olga's Gmail inbox (a stranger knows one of them).
  insert into customers(full_name, phone, email) values ('Oscar Testoracle', '+61491570521', pg_temp.mail('oscar')) returning id into c; insert into fx values ('cOscar', c);
  insert into customers(full_name, phone, email) values ('Olga Testoracle', '+61491570523', 'z.468.olga.' || sfx || '@gmail.com') returning id into c; insert into fx values ('cOlga', c);
  -- S3: Jo and Joanne, one person twice: the phone and the email both.
  insert into customers(full_name, phone, email) values ('Jo Testdup', '+61491570507', pg_temp.mail('jo')) returning id into c; insert into fx values ('cJo1', c);
  insert into customers(full_name, phone, email) values ('Joanne Testdup', '+61491570507', pg_temp.mail('jo')) returning id into c; insert into fx values ('cJo2', c);
  -- S3 Gmail: the same inbox spelt two ways.
  insert into customers(full_name, phone, email) values ('Kim Testdupg', '+61491570508', 'z468.kim.' || sfx || '@gmail.com') returning id into c; insert into fx values ('cKim1', c);
  insert into customers(full_name, phone, email) values ('Kimberly Testdupg', '+61491570508', 'z468kim' || sfx || '+old@gmail.com') returning id into c; insert into fx values ('cKim2', c);
  -- S4.
  insert into customers(full_name, phone, email) values ('Lee Testphone', '+61491570509', pg_temp.mail('lee')) returning id into c; insert into fx values ('cLee', c);
  insert into customers(full_name, phone, email) values ('Mia Testemail', '+61491570510', pg_temp.mail('mia')) returning id into c; insert into fx values ('cMia', c);
  insert into customers(full_name, phone, email) values ('Rex Testgone', '+61491570515', pg_temp.mail('rex')) returning id into c; insert into fx values ('cRex', c);
  update customers set deleted_at = now() where id = c;
  -- S5: Pia will have a signed QR survey; Quinn has a consultant's record she has not signed.
  insert into customers(full_name, phone, email) values ('Pia Testsurvey', '+61491570513', pg_temp.mail('pia')) returning id into c; insert into fx values ('cPia', c);
  insert into customers(full_name, phone, email) values ('Quinn Testcons', '+61491570514', pg_temp.mail('quinn')) returning id into c; insert into fx values ('cQuinn', c);
  insert into health_surveys(survey_no, full_name, customer_id, source, store_id)
  values ('HS-Z468-' || sfx, 'Quinn Testcons', c, 'consultant', pg_temp.fx('store')) returning id into u; insert into fx values ('hsQuinn', u);
  -- Signed out: Susan.
  insert into customers(full_name, phone, email) values ('Susan Testanon', '+61491570516', pg_temp.mail('sue')) returning id into c; insert into fx values ('cSue', c);
  -- A: two Gwens on a phone, one with the email (her first form, by name,
  -- gives her a survey).
  insert into customers(full_name, phone, email) values ('Gwen Testsame', '+61491570528', pg_temp.mail('gwen')) returning id into c; insert into fx values ('cGwen1', c);
  insert into customers(full_name, phone) values ('Gwen Testsame', '+61491570528') returning id into c; insert into fx values ('cGwen2', c);
  -- A: Vic has no survey, but an old survey with no customer has his phone
  -- and the name Val Testlegacy.
  insert into customers(full_name, phone, email) values ('Vic Testlegacy', '+61491570529', pg_temp.mail('vic')) returning id into c; insert into fx values ('cVic', c);
  insert into health_surveys(survey_no, full_name, phone, source, store_id)
  values ('HS-Z468V-' || sfx, 'Val Testlegacy', '+61491570529', 'public_form', pg_temp.fx('store')) returning id into u; insert into fx values ('hsVal', u);
end $$;
-- An old record whose phone cannot be read as one number, from the July
-- import (the phone policy is set aside to make it, as the import did).
alter table customers disable trigger zz_normalize_current_customer_phone;
do $$ declare c uuid; begin
  insert into customers(full_name, phone, email) values ('Ola Testlegacy', '0491570512', pg_temp.mail('ola')) returning id into c;
  insert into fx values ('cOla', c);
end $$;
alter table customers enable trigger zz_normalize_current_customer_phone;
select pg_temp.check(public.normalize_customer_phone('0491570512') is null,
  'P0 (setup) the old record''s phone cannot be read as one number');
select pg_temp.submit('pia0', 'Pia', 'Testsurvey', '+61491570513', pg_temp.mail('pia'));
select pg_temp.check(pg_temp.survey_customer('pia0') = pg_temp.fx('cPia'), 'P0 (setup) Pia''s own QR survey, by phone and name');
insert into tx values ('customers_before', (select count(*) from customers)::text);
insert into tx values ('details_ana', pg_temp.details('cAna')), ('details_quinn', pg_temp.details('cQuinn')),
                      ('details_pia', pg_temp.details('cPia')), ('details_ida', pg_temp.details('cIda')),
                      ('details_vic', pg_temp.details('cVic'));

-- ═════ S1 The phone and the email: one customer ═════
select pg_temp.submit('s1', 'Annie', 'Testone-Lee', '+61 491 570 501', upper(pg_temp.mail('ana')));
select pg_temp.check(pg_temp.survey_customer('s1') = pg_temp.fx('cAna') and pg_temp.hold('s1') is null
    and (pg_temp.reply('s1') - 'survey_no' - 'survey_id') = '{"success": true}'::jsonb,
  'S1 another name, the phone with spaces, the email in capitals: Ana''s at once, not held; the reply says nothing about customers: '
  || pg_temp.tx('sub:s1'));
select pg_temp.check((select full_name = 'Ana Testone' and first_name = 'Ana' and last_name = 'Testone'
                         and phone = '+61491570501' and email = upper(pg_temp.mail('ana'))
                         and date_of_birth = '1980-02-03' and sex = 'female' and occupation = 'Tester'
                         and source_option_id = pg_temp.fx('src')
                        from public.health_surveys where id = pg_temp.fx('hs:s1')),
  'S1/B the form carries Ana''s name parts and keeps what was typed: phone, email, date of birth, sex, occupation, how they heard');
select pg_temp.check((select full_name = 'Ana Testone' and phone = '+61491570501' and email = pg_temp.mail('ana')
                         and date_of_birth is null and gender is null and occupation is null and source_option_id is null
                         and source_label is null
                        from customers where id = pg_temp.fx('cAna'))
    and pg_temp.details('cAna') = pg_temp.tx('details_ana')
    and (select full_name = 'Ben Testone' and email is null from customers where id = pg_temp.fx('cBen'))
    and not exists (select 1 from health_surveys where customer_id in (pg_temp.fx('cBen'), pg_temp.fx('cCara'))),
  'B Ana keeps her name, phone and email, and none of her empty details is filled (date of birth, sex, occupation, how she heard); Ben (the phone only) and Cara (the email only) are untouched');
select pg_temp.check(pg_temp.submitted('s1')->>'name_match' = 'phone_and_email'
    and (pg_temp.submitted('s1')->>'phone_and_email_customers')::int = 1
    and (pg_temp.submitted('s1')->>'customer_matched')::boolean and not (pg_temp.submitted('s1')->>'held_for_staff')::boolean
    and pg_temp.submitted('s1')->>'typed_name' = 'Annie Testone-Lee',
  'S1 the Audit Log row: found by phone and email, one such customer, the name typed');
select pg_temp.check(pg_temp.visits('s1') = 1, 'S1 the form counts as Ana''s visit at once');
-- A: Ana now has a survey. The same phone and email under another name
-- (twice under one name): never refused; each waits with her, quietly.
select pg_temp.submit('s1again', 'Annie', 'Testone', '+61491570501', pg_temp.mail('ana'));
select pg_temp.submit('s1again2', 'Annie', 'Testone', '+61491570501', pg_temp.mail('ana'));
select pg_temp.check((select bool_and(pg_temp.survey_customer(k) is null
                                      and (pg_temp.hold(k)).reason = 'phone_and_email_customer_has_survey'
                                      and pg_temp.held_for(k) = pg_temp.ids('cAna')
                                      and (pg_temp.reply(k) - 'survey_no' - 'survey_id') = '{"success": true}'::jsonb
                                      and (pg_temp.survey(k)).full_name = 'Annie Testone'
                                      and (pg_temp.survey(k)).first_name = 'Annie')
                        from unnest(array['s1again', 's1again2']) k)
    and (select count(*) from health_surveys where customer_id = pg_temp.fx('cAna')) = 1
    and pg_temp.details('cAna') = pg_temp.tx('details_ana'),
  'A sending it again, twice under one name: not refused; each waits with Ana (phone_and_email_customer_has_survey), as typed, the reply as any other; Ana keeps one survey: '
  || pg_temp.tx('sub:s1again') || ' / ' || pg_temp.tx('sub:s1again2'));
select pg_temp.check(pg_temp.submitted('s1again')->>'name_match' = 'phone_and_email'
    and pg_temp.submitted('s1again')->>'hold_reason' = 'phone_and_email_customer_has_survey'
    and (pg_temp.submitted('s1again')->>'held_for_staff')::boolean and not (pg_temp.submitted('s1again')->>'customer_matched')::boolean
    and pg_temp.submitted('s1again')->>'customer_id' is null
    and (pg_temp.submitted('s1again')->>'phone_and_email_customers')::int = 1,
  'A the Audit Log row: found by phone and email, waits for staff with the reason, no customer');
select pg_temp.check(pg_temp.visits('s1again') = 0, 'A the waiting form counts as no visit');
select pg_temp.submit('s1g', 'Regina', 'Testgmail', '+61491570502', 'Z468Gina' || pg_temp.tx('sfx') || '+qr@GoogleMail.com');
select pg_temp.check(pg_temp.survey_customer('s1g') = pg_temp.fx('cGina') and pg_temp.hold('s1g') is null,
  'S1 Gmail: the record''s dotted address, the form''s +tag at googlemail.com: Gina''s at once: ' || pg_temp.tx('sub:s1g'));

-- ═════ S2 The name first ═════
select pg_temp.submit('s2', 'Dee', 'Testprec', '+61491570503', pg_temp.mail('eve'));
select pg_temp.check(pg_temp.survey_customer('s2') = pg_temp.fx('cDee')
    and pg_temp.submitted('s2')->>'name_match' = 'exact' and pg_temp.submitted('s2')->>'phone_and_email_customers' is null,
  'S2 the phone and Dee''s name, with Eve''s email: Dee''s (the name first), whatever the email: ' || pg_temp.tx('sub:s2'));
select pg_temp.check((select email = pg_temp.mail('dee') and date_of_birth = '1980-02-03' and occupation = 'Tester'
                         and gender = 'female' and source_option_id = pg_temp.fx('src')
                        from customers where id = pg_temp.fx('cDee')),
  'S2/B Dee keeps her own email; a phone and name match fills her empty details, as today');
select pg_temp.submit('s2fay', 'Fay', 'Testtwin', '+61491570504', pg_temp.mail('fay'));
select pg_temp.check(pg_temp.survey_customer('s2fay') = pg_temp.fx('cFay1') and pg_temp.hold('s2fay') is null
    and pg_temp.submitted('s2fay')->>'name_match' = 'exact' and (pg_temp.submitted('s2fay')->>'phone_and_email_customers')::int = 1,
  'S2 two Fays on the phone, one with the email: hers at once (the email decides among them): ' || pg_temp.tx('sub:s2fay'));
select pg_temp.check((select date_of_birth = '1980-02-03' and occupation = 'Tester' from customers where id = pg_temp.fx('cFay1')),
  'S2/B the Fay the email picked among namesakes: a name match, so her empty details are filled');
select pg_temp.submit('s2gus', 'Gus', 'Testmany', '+61491570505', pg_temp.mail('gus'));
select pg_temp.check(pg_temp.survey_customer('s2gus') is null and (pg_temp.hold('s2gus')).reason = 'several_name_matches'
    and pg_temp.held_for('s2gus') = pg_temp.ids('cGus1', 'cGus2')
    and (pg_temp.submitted('s2gus')->>'phone_and_email_customers')::int = 2,
  'S2 two Guses on the phone, both with the email: it waits for both (several_name_matches)');
select pg_temp.submit('s2hal', 'Hal', 'Testother', '+61491570506', pg_temp.mail('ida'));
select pg_temp.check(pg_temp.survey_customer('s2hal') is null and (pg_temp.hold('s2hal')).reason = 'several_name_matches'
    and pg_temp.held_for('s2hal') = pg_temp.ids('cHal1', 'cHal2')
    and (pg_temp.submitted('s2hal')->>'phone_and_email_customers')::int = 1
    and not exists (select 1 from health_surveys where customer_id = pg_temp.fx('cIda'))
    and pg_temp.details('cIda') = pg_temp.tx('details_ida')
    and (pg_temp.reply('s2hal') - 'survey_no' - 'survey_id') = '{"success": true}'::jsonb
    and pg_temp.submitted('s2hal')->>'name_match' = 'exact',
  'D two Hals on the phone and Ida, of another name, with the phone and the email: it waits for the Hals (several_name_matches), not given to Ida, her details untouched');
select pg_temp.submit('s2fae', 'Fae', 'Testboth', '+61491570517', pg_temp.mail('fae'));
select pg_temp.check(pg_temp.survey_customer('s2fae') is null and (pg_temp.hold('s2fae')).reason = 'several_name_matches'
    and pg_temp.held_for('s2fae') = pg_temp.ids('cFae1', 'cFae2', 'cZed')
    and (pg_temp.submitted('s2fae')->>'phone_and_email_customers')::int = 2
    and not exists (select 1 from health_surveys where customer_id in (pg_temp.fx('cFae1'), pg_temp.fx('cZed'))),
  'S3 two Faes on the phone, one with the email, and Zed of another name with both: not given to the Fae with the email; it waits for all three: '
  || pg_temp.tx('sub:s2fae'));

-- ═════ S3 Several with the phone and the email ═════
select pg_temp.submit('s3', 'Jody', 'Testdup', '+61491570507', pg_temp.mail('jo'));
select pg_temp.check(pg_temp.survey_customer('s3') is null and (pg_temp.hold('s3')).reason = 'phone_and_email_in_use'
    and pg_temp.held_for('s3') = pg_temp.ids('cJo1', 'cJo2')
    and (pg_temp.reply('s3') - 'survey_no' - 'survey_id') = '{"success": true}'::jsonb
    and (pg_temp.submitted('s3')->>'phone_and_email_customers')::int = 2 and pg_temp.submitted('s3')->>'name_match' is null,
  'S3 Jo and Joanne both have the phone and the email: it waits (phone_and_email_in_use) for both; the reply is as any other');
select pg_temp.submit('s3g', 'Kimmy', 'Testdupg', '+61491570508', 'z468kim' || pg_temp.tx('sfx') || '@googlemail.com');
select pg_temp.check(pg_temp.survey_customer('s3g') is null and (pg_temp.hold('s3g')).reason = 'phone_and_email_in_use'
    and pg_temp.held_for('s3g') = pg_temp.ids('cKim1', 'cKim2'),
  'S3 Gmail: one inbox spelt two ways on two records: it waits for both');
select pg_temp.as_user('s');
select pg_temp.check(pg_temp.listed('s3')->>'reason' = 'phone_and_email_in_use'
    and pg_temp.listed('s3')->>'full_name' = 'Jody Testdup' and pg_temp.listed('s3')->>'phone' = '+61491570507'
    and jsonb_array_length(pg_temp.listed('s3')->'candidates') = 2
    and (pg_temp.candidate('s3', 'cJo1')->>'phone_matches')::boolean and (pg_temp.candidate('s3', 'cJo1')->>'email_matches')::boolean
    and (pg_temp.candidate('s3', 'cJo2')->>'phone_matches')::boolean and (pg_temp.candidate('s3', 'cJo2')->>'email_matches')::boolean
    and not (pg_temp.candidate('s3', 'cJo2')->>'deleted')::boolean,
  'S3 the list: the form with both customers, each matching the phone and the email (the page offers Delete from these)');
select pg_temp.check((pg_temp.candidate('s2gus', 'cGus1')->>'email_matches')::boolean and (pg_temp.candidate('s2gus', 'cGus2')->>'email_matches')::boolean
    and (pg_temp.candidate('s2gus', 'cGus2')->>'name_matches')::boolean,
  'S3 the list: the two Guses, each with the phone, the email and the name');
select pg_temp.check((pg_temp.candidate('s2fae', 'cFae1')->>'phone_matches')::boolean and (pg_temp.candidate('s2fae', 'cFae1')->>'email_matches')::boolean
    and (pg_temp.candidate('s2fae', 'cZed')->>'phone_matches')::boolean and (pg_temp.candidate('s2fae', 'cZed')->>'email_matches')::boolean
    and not (pg_temp.candidate('s2fae', 'cZed')->>'name_matches')::boolean
    and (pg_temp.candidate('s2fae', 'cFae2')->>'phone_matches')::boolean and not (pg_temp.candidate('s2fae', 'cFae2')->>'email_matches')::boolean
    and (pg_temp.candidate('s2fae', 'cFae2')->>'name_matches')::boolean,
  'S3 the list: Fae with the email and Zed each with the phone and the email (the page offers Delete on these two), the other Fae with the phone and the name');
select pg_temp.check(pg_temp.del('cJo2', 'Joanne Testdup') = 'Only an Owner or Manager can delete a customer'
    and (select deleted_at is null from customers where id = pg_temp.fx('cJo2')),
  'S3 staff cannot delete either');
select pg_temp.as_user('m');
select pg_temp.check(pg_temp.del('cJo2', 'Jo Testdup') like 'The name you typed does not match%'
    and (select deleted_at is null from customers where id = pg_temp.fx('cJo2')),
  'S3 a Manager typing another name is refused');
insert into tx values ('del_jo2', pg_temp.del('cJo2', ' joanne  testdup '));
select pg_temp.check(pg_temp.tx('del_jo2') = 'ok' and (select deleted_at is not null from customers where id = pg_temp.fx('cJo2'))
    and exists (select 1 from audit_logs where record_id = pg_temp.fx('cJo2') and action = 'customer_deleted'
                  and new_data->>'reason' = 'Duplicate record of the same person'),
  'S3 a Manager deletes the duplicate, the name typed to confirm (the app''s delete_customer, audited): ' || pg_temp.tx('del_jo2'));
select pg_temp.as_user('s');
select pg_temp.check(pg_temp.listed('s3') is not null and (pg_temp.candidate('s3', 'cJo2')->>'deleted')::boolean
    and not (pg_temp.candidate('s3', 'cJo1')->>'deleted')::boolean
    and (pg_temp.candidate('s3', 'cJo1')->>'email_matches')::boolean,
  'S3 the form still waits; the list shows Joanne retired and Jo still with the phone and the email');
select pg_temp.check(pg_temp.attach('s3', 'cJo2') = 'Customer not found.', 'S3 the deleted record cannot take the form');
insert into tx values ('att_s3', pg_temp.attach('s3', 'cJo1'));
select pg_temp.check(pg_temp.tx('att_s3') = 'ok' and pg_temp.survey_customer('s3') = pg_temp.fx('cJo1')
    and (pg_temp.hold('s3')).resolution = 'attached' and pg_temp.listed('s3') is null
    and (select full_name from customers where id = pg_temp.fx('cJo1')) = 'Jo Testdup',
  'S3 staff attach it to Jo: hers, off the list, her name kept: ' || pg_temp.tx('att_s3'));
select pg_temp.as_server();
-- A and 433: Jo alone now has the phone and the email, and a survey (the form
-- staff attached). The same form again under the same name: refused, as 433
-- refuses a form sent before (it was held for another reason, then
-- attached). Under another name: found by the phone and the email, it
-- waits quietly (A).
select pg_temp.submit('s3again', 'Jody', 'Testdup', '+61491570507', pg_temp.mail('jo'));
select pg_temp.submit('s3other', 'Jodie', 'Testother', '+61491570507', pg_temp.mail('jo'));
select pg_temp.check(pg_temp.tx('sub:s3again') like 'ERROR: HEALTH_SURVEY_ALREADY_EXISTS%'
    and (pg_temp.hold('s3other')).reason = 'phone_and_email_customer_has_survey' and pg_temp.held_for('s3other') = pg_temp.ids('cJo1')
    and (pg_temp.reply('s3other') - 'survey_no' - 'survey_id') = '{"success": true}'::jsonb,
  'A/433 the attached form sent again under its name: refused as sent before; under another name: waits quietly with Jo: '
  || pg_temp.tx('sub:s3again') || ' / ' || pg_temp.tx('sub:s3other'));

-- ═════ S4 Only the phone, only the email, neither ═════
select pg_temp.submit('s4p', 'Leo', 'Testphone', '+61491570509', pg_temp.mail('leo'));
select pg_temp.check(pg_temp.survey_customer('s4p') is null and (pg_temp.hold('s4p')).reason = 'phone_in_use'
    and pg_temp.held_for('s4p') = pg_temp.ids('cLee') and (pg_temp.submitted('s4p')->>'phone_and_email_customers')::int = 0,
  'S4 only the phone is a customer''s: it waits (phone_in_use), as today');
select pg_temp.submit('s4e', 'Mya', 'Testemail', '+61491570560', pg_temp.mail('mia'));
select pg_temp.check(pg_temp.survey_customer('s4e') is null and (pg_temp.hold('s4e')).reason = 'email_in_use'
    and pg_temp.held_for('s4e') = pg_temp.ids('cMia'),
  'S4 only the email is a customer''s: it waits (email_in_use), as today');
select pg_temp.submit('s4n', 'Ned', 'Testnew', '+61491570511', pg_temp.mail('ned'));
select pg_temp.check(pg_temp.survey_customer('s4n') is not null and pg_temp.hold('s4n') is null
    and (select full_name from customers where id = pg_temp.survey_customer('s4n')) = 'Ned Testnew',
  'S4 neither: a new customer, as today');
select pg_temp.submit('s4d', 'Rexy', 'Testgone', '+61491570515', pg_temp.mail('rex'));
select pg_temp.check(pg_temp.survey_customer('s4d') is distinct from pg_temp.fx('cRex') and pg_temp.survey_customer('s4d') is not null
    and pg_temp.hold('s4d') is null,
  'S4 a deleted customer with the phone and the email does not count: a new customer');
select pg_temp.submit('s4l', 'Olivia', 'Testlegacy', '+61 491 570 512', pg_temp.mail('ola'));
select pg_temp.check(pg_temp.survey_customer('s4l') is null and (pg_temp.hold('s4l')).reason = 'email_in_use'
    and pg_temp.held_for('s4l') = pg_temp.ids('cOla'),
  'S4 an old record whose phone cannot be read, with the email: it waits (email_in_use), as 433 treats such phones: ' || pg_temp.tx('sub:s4l'));

-- ═════ A A survey already ═════
select pg_temp.submit('s5', 'Pia', 'Testsurvey-Tan', '+61491570513', pg_temp.mail('pia'));
select pg_temp.check(pg_temp.survey_customer('s5') is null and pg_temp.fx('hs:s5') is not null
    and (pg_temp.hold('s5')).reason = 'phone_and_email_customer_has_survey'
    and pg_temp.held_for('s5') = pg_temp.ids('cPia')
    and (pg_temp.reply('s5') - 'survey_no' - 'survey_id') = '{"success": true}'::jsonb
    and (select count(*) from health_surveys where customer_id = pg_temp.fx('cPia')) = 1
    and pg_temp.details('cPia') = pg_temp.tx('details_pia'),
  'A Pia''s phone and email under another name: she has a survey, so it is not refused: it waits quietly with her, the reply as any other; her details untouched: '
  || pg_temp.tx('sub:s5'));
select pg_temp.submit('s5own', 'Pia', 'Testsurvey', '+61491570513', pg_temp.mail('pia'));
select pg_temp.submit('s5words', 'Testsurvey', 'Pia', '+61491570513', 'z468-other-' || pg_temp.tx('sfx') || '@example.invalid');
select pg_temp.check(pg_temp.tx('sub:s5own') like 'ERROR: HEALTH_SURVEY_ALREADY_EXISTS%'
    and pg_temp.tx('sub:s5words') like 'ERROR: HEALTH_SURVEY_ALREADY_EXISTS%',
  'A by the phone and Pia''s name (as typed, or the same words in another order, any email): still refused: '
  || pg_temp.tx('sub:s5own') || ' / ' || pg_temp.tx('sub:s5words'));
select pg_temp.submit('gw0', 'Gwen', 'Testsame', '+61491570528', pg_temp.mail('gwen'));
select pg_temp.submit('gw1', 'Gwen', 'Testsame', '+61491570528', pg_temp.mail('gwen'));
select pg_temp.check(pg_temp.survey_customer('gw0') = pg_temp.fx('cGwen1') and pg_temp.tx('sub:gw1') like 'ERROR: HEALTH_SURVEY_ALREADY_EXISTS%',
  'A two Gwens on the phone, the email picks one: her form is hers; sent again by name: refused (a name match): ' || pg_temp.tx('sub:gw1'));
select pg_temp.submit('vic', 'Val', 'Testlegacy', '+61491570529', pg_temp.mail('vic'));
select pg_temp.check(pg_temp.survey_customer('vic') is null and (pg_temp.hold('vic')).reason = 'phone_and_email_customer_has_survey'
    and pg_temp.held_for('vic') = pg_temp.ids('cVic')
    and (pg_temp.reply('vic') - 'survey_no' - 'survey_id') = '{"success": true}'::jsonb
    and pg_temp.details('cVic') = pg_temp.tx('details_vic')
    and (select customer_id is null from health_surveys where id = pg_temp.fx('hsVal')),
  'A Vic''s phone and email under the name of an old survey with no customer on his phone: not refused; it waits with him: ' || pg_temp.tx('sub:vic'));
select pg_temp.as_user('s');
select pg_temp.check(pg_temp.listed('s5')->>'reason' = 'phone_and_email_customer_has_survey'
    and pg_temp.listed('s5')->>'full_name' = 'Pia Testsurvey-Tan'
    and (pg_temp.candidate('s5', 'cPia')->>'phone_matches')::boolean and (pg_temp.candidate('s5', 'cPia')->>'email_matches')::boolean
    and pg_temp.candidate('s5', 'cPia')->>'survey_no' = (pg_temp.survey('pia0')).survey_no
    and not coalesce((pg_temp.candidate('s5', 'cPia')->>'survey_takes_form')::boolean, false),
  'A the list: the form, its reason, and Pia with the phone, the email and her survey');
select pg_temp.check(pg_temp.attach('s5', 'cPia') like 'This customer already has a health survey (%). A customer can have only one.'
    and pg_temp.survey_customer('s5') is null,
  'A staff cannot attach it to Pia (one survey per customer): ' || pg_temp.attach('s5', 'cPia'));
insert into tx values ('make_s5', pg_temp.make('s5'));
select pg_temp.check(pg_temp.tx('make_s5') = 'ok'
    and (select full_name = 'Pia Testsurvey-Tan' and phone = '+61491570513' from customers where id = pg_temp.survey_customer('s5'))
    and (pg_temp.hold('s5')).resolution = 'created' and pg_temp.listed('s5') is null,
  'A staff make a new customer from it (a family member): theirs, off the list: ' || pg_temp.tx('make_s5'));
insert into tx values ('close_staff', pg_temp.close_form('s1again2'));
select pg_temp.check(pg_temp.tx('close_staff') = 'Your role cannot do this.' and (pg_temp.hold('s1again2')).resolved_at is null,
  'A staff cannot close it: ' || pg_temp.tx('close_staff'));
select pg_temp.as_user('m');
insert into tx values ('close_s1again2', pg_temp.close_form('s1again2'));
select pg_temp.check(pg_temp.tx('close_s1again2') = 'ok' and (pg_temp.hold('s1again2')).resolution = 'closed'
    and pg_temp.survey_customer('s1again2') is null,
  'A a Manager closes the extra one (the same person again): ' || pg_temp.tx('close_s1again2'));
select pg_temp.as_server();
select pg_temp.submit('s5c', 'Quin', 'Testcons', '+61491570514', pg_temp.mail('quinn'));
select pg_temp.check((pg_temp.reply('s5c')->>'survey_id')::uuid = pg_temp.fx('hsQuinn')
    and (select customer_id = pg_temp.fx('cQuinn') and signature_data is not null and full_name = 'Quinn Testcons'
           and date_of_birth = '1980-02-03' and occupation = 'Tester'
           from health_surveys where id = pg_temp.fx('hsQuinn'))
    and (select count(*) from health_surveys where customer_id = pg_temp.fx('cQuinn')) = 1
    and pg_temp.hold('s5c') is null
    and pg_temp.details('cQuinn') = pg_temp.tx('details_quinn'),
  'A/B Quinn''s phone and email: her consultant''s record she had not signed takes the form (419) with what was typed, her name kept; none of her own details filled: '
  || pg_temp.tx('sub:s5c'));

-- ═════ S2 kept: a waiting form does not stop a customer's own form by name ═════
select pg_temp.submit('s2tw0', 'Tee', 'Vee', '+61491570526', pg_temp.mail('tt'));
select pg_temp.submit('s2tw', 'Theo', 'Testtwin', '+61491570526', pg_temp.mail('tt'));
select pg_temp.check((pg_temp.hold('s2tw0')).reason = 'phone_and_email_in_use' and pg_temp.survey_customer('s2tw') = pg_temp.fx('cTheo')
    and pg_temp.hold('s2tw') is null,
  'S2 Tara and Theo share the phone and the email; a form under a nickname waits; Theo''s own form by name is his at once: ' || pg_temp.tx('sub:s2tw'));
select pg_temp.submit('s2hh0', 'Ula', 'Testother', '+61491570527', pg_temp.mail('house'));
select pg_temp.submit('s2hh', 'Uma', 'Testhouse', '+61491570527', pg_temp.mail('house'));
select pg_temp.check((pg_temp.hold('s2hh0')).reason = 'phone_in_use' and pg_temp.survey_customer('s2hh') = pg_temp.fx('cUma')
    and pg_temp.hold('s2hh') is null,
  'S2 a household member''s form on Uma''s phone with a new email waits; Uma''s own form by name with that email is hers at once: ' || pg_temp.tx('sub:s2hh'));

-- ═════ O A stranger's two forms tell nothing ═════
-- Each pair: the same phone and email, two names. o1 Oscar's phone; o2 a
-- phone nobody has; o3 Olga's Gmail inbox (spelt two other ways); o4 a Gmail
-- inbox nobody has.
select pg_temp.submit('o1a', 'Pat', 'Probeone', '+61491570521', pg_temp.mail('probe1'));
select pg_temp.submit('o1b', 'Pam', 'Probetwo', '+61491570521', pg_temp.mail('probe1'));
select pg_temp.submit('o2a', 'Pat', 'Probeone', '+61491570522', pg_temp.mail('probe2'));
select pg_temp.submit('o2b', 'Pam', 'Probetwo', '+61491570522', pg_temp.mail('probe2'));
select pg_temp.submit('o3a', 'Pat', 'Probeone', '+61491570524', 'z468olga' || pg_temp.tx('sfx') || '+a@googlemail.com');
select pg_temp.submit('o3b', 'Pam', 'Probetwo', '+61491570524', 'Z468.OLGA.' || upper(pg_temp.tx('sfx')) || '@gmail.com');
select pg_temp.submit('o4a', 'Pat', 'Probeone', '+61491570525', 'z.468.nobody.' || pg_temp.tx('sfx') || '@gmail.com');
select pg_temp.submit('o4b', 'Pam', 'Probetwo', '+61491570525', 'z468nobody' || pg_temp.tx('sfx') || '+b@googlemail.com');
select pg_temp.check((pg_temp.hold('o1a')).reason = 'phone_in_use' and (pg_temp.hold('o3a')).reason = 'email_in_use'
    and pg_temp.survey_customer('o2a') is not null and pg_temp.survey_customer('o4a') is not null
    and (select bool_and((pg_temp.reply(k) - 'survey_no' - 'survey_id') = '{"success": true}'::jsonb) from unnest(array['o1a', 'o2a', 'o3a', 'o4a']) k),
  'O the first form of each pair: the same reply; two wait (a customer''s phone, a customer''s inbox), two made a customer');
select pg_temp.check((select bool_and((pg_temp.reply(k) - 'survey_no' - 'survey_id') = '{"success": true}'::jsonb
                                      and pg_temp.survey_customer(k) is null and (pg_temp.hold(k)).survey_id is not null)
                        from unnest(array['o1b', 'o2b', 'o3b', 'o4b']) k)
    and (pg_temp.hold('o1b')).reason = 'phone_in_use' and (pg_temp.hold('o3b')).reason = 'email_in_use'
    and (pg_temp.hold('o2b')).reason = 'phone_and_email_customer_has_survey' and pg_temp.held_for('o2b') = array[pg_temp.survey_customer('o2a')]
    and (pg_temp.hold('o4b')).reason = 'phone_and_email_customer_has_survey' and pg_temp.held_for('o4b') = array[pg_temp.survey_customer('o4a')],
  'O the second form under another name: waits alike, with the same reply, whether the phone or the email is a customer''s or nobody''s (433''s rule): '
  || pg_temp.tx('sub:o1b') || ' / ' || pg_temp.tx('sub:o2b') || ' / ' || pg_temp.tx('sub:o3b') || ' / ' || pg_temp.tx('sub:o4b'));

-- ═════ Signed out ═════
do $$
declare r jsonb; v_token text := pg_temp.tx('token'); v_src uuid := pg_temp.fx('src'); v_mail text := pg_temp.mail('sue');
begin
  execute 'set local role anon';
  r := public.submit_health_survey(v_token,
         jsonb_build_object('first_name', 'Sue', 'last_name', 'Testanon', 'phone', '+61491570516', 'email', v_mail,
                            'signature_data', 'data:image/png;base64,AAAA', 'source_option_id', v_src),
         null, null);
  execute 'reset role';
  insert into tx values ('sub:anon', r::text);
  insert into fx values ('hs:anon', (r->>'survey_id')::uuid);
end $$;
select pg_temp.check(pg_temp.survey_customer('anon') = pg_temp.fx('cSue') and pg_temp.hold('anon') is null,
  'S1 signed out (anon), as the QR page sends it: Susan''s at once: ' || pg_temp.tx('sub:anon'));

-- ═════ K What the forms made ═════
select pg_temp.check((select count(*) from customers) = pg_temp.tx('customers_before')::int + 5,
  'K only the new person (Ned), the one beside a deleted record (Rexy), the first forms on a phone and an inbox nobody has (O) and staff''s new customer from a waiting form (A) made customers');

-- ═════ G Grants ═════
select pg_temp.check(has_function_privilege('anon', 'public.submit_health_survey(text,jsonb,jsonb,text)', 'execute')
    and has_function_privilege('authenticated', 'public.submit_health_survey(text,jsonb,jsonb,text)', 'execute')
    and has_function_privilege('service_role', 'public.submit_health_survey(text,jsonb,jsonb,text)', 'execute'),
  'G the form stays callable signed out, signed in and by the server');
select pg_temp.check(bool_and(has_function_privilege('authenticated', f, 'execute') and not has_function_privilege('anon', f, 'execute')),
  'G the list, attach and delete: signed-in users (each checks the caller), not anon')
  from unnest(array['public.health_survey_holds_list()', 'public.attach_held_health_survey(uuid,uuid,text)',
                    'public.delete_customer(uuid,text,text)']) f;
select pg_temp.check(not has_table_privilege('anon', 'public.health_survey_holds', 'select,insert,update,delete')
    and not has_table_privilege('authenticated', 'public.health_survey_holds', 'select,insert,update,delete'),
  'G the waiting list''s table is no client''s');

-- ═════ M The tested version ═════
select pg_temp.check(not exists (select 1 from m468 m
                                   left join pg_proc p on p.oid::regprocedure::text = m.fn and p.pronamespace = 'public'::regnamespace
                                  where m.fn not like 'constraint %' and (p.oid is null or md5(pg_get_functiondef(p.oid)) <> m.md5))
    and (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f')
        = (select count(*) from m468 where fn not like 'constraint %'),
  'M running 468 a second time changed no function (with skip_install: nothing changed during the checks)');
select pg_temp.check(not exists (select 1 from m468 m
                                   left join pg_constraint c on 'constraint ' || c.conrelid::regclass::text || ' ' || c.conname = m.fn
                                  where m.fn like 'constraint %' and (c.oid is null or md5(pg_get_constraintdef(c.oid)) <> m.md5))
    and (select count(*) from pg_constraint where conrelid = 'public.health_survey_holds'::regclass)
        = (select count(*) from m468 where fn like 'constraint %'),
  'M running 468 a second time changed no constraint of health_survey_holds');
select pg_temp.check(md5(pg_get_functiondef('public.submit_health_survey(text,jsonb,jsonb,text)'::regprocedure))
                     = '014a970de2e5dee64e4027459cac5280'
    and (select md5(pg_get_constraintdef(oid)) from pg_constraint
          where conrelid = 'public.health_survey_holds'::regclass and conname = 'health_survey_holds_reason_check')
        = '378c1861f7ffacb38d2e6e8c69e45cc8',
  'M submit_health_survey and the reason check are 468''s AFTER versions');

do $$ declare v_failed int; begin
  select count(*) into v_failed from failed;
  if v_failed > 0 then raise exception '% check(s) failed: %', v_failed, (select string_agg(msg, '; ' order by n) from failed); end if;
  raise notice 'All to-match-468 checks passed.';
end $$;
rollback;
