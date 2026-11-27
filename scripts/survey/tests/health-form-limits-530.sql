-- The QR health form limits each sender, each link and each phone, holds a form for an existing
-- customer for staff, dates it the day it arrives, and refuses odd input (530; security audit of
-- 17 Nov 2026, M4; the user, 19 Nov 2026).
--
-- Every form is sent as the public page sends it: signed out (the anon role), through
-- submit_health_survey, with the request headers PostgREST hands over (request.headers); a
-- sender is the address in cf-connecting-ip.
--
--   H  "Hold for staff": a form whose phone and name match a customer with no survey (Ann), whose
--      phone and email match one under another name (Ben, 468), or whose customer has a
--      consultant's record they have not signed (Cal, 419 Q10), waits under To match
--      (existing_customer) with that customer as the only candidate, with no customer; nothing
--      is copied onto the customer, no record is signed; the audit row says it was held. A
--      customer with a survey waits as before (customer_has_survey). Someone new (no match, phone
--      and email not in use) is still made a customer by the form, with the form's details.
--      Staff see each in To match with its reason and candidate.
--   A  Staff attach (attach_held_health_survey, unchanged): Ann's and Ben's forms take them as
--      their customer and fill their EMPTY date of birth, gender, occupation and source (never
--      the name, phone or email); Cal's form signs his consultant's record (its answers, the
--      day). Their holds are resolved as attached.
--   L  "10 per connection + 60 per link": one sender's 11th form in an hour is refused
--      (SURVEY_BUSY), nothing kept; another sender is not; x-forwarded-for changes nothing; one
--      IPv6 /64 is one sender; ::ffff:a.b.c.d is a.b.c.d; the key is 529's for the same address;
--      an hour later the sender may send again. One link's 61st form in an hour is refused, from
--      any sender; another link is not; an hour later it takes forms again.
--   D  "3 a day per phone": the 4th form of a Singapore day under one phone (counting forms kept
--      through any link) keeps nothing (no form, hold or audit row) and is answered
--      {"success": true} (no survey number); dropped tries count for the sender's 10; a form
--      the day before does not count, nor a consultant's record a form was signed into.
--   T  "Day it arrives": signed_date is the Singapore date the form arrives, whatever was sent.
--   E  A link's event name wins over the one typed; a link without one keeps the one typed.
--   I  ip_address and device_info (form and audit row) are the request's cf-connecting-ip and
--      user-agent (control characters out, at most 250 characters), never the payload's; none
--      without the headers.
--   C  Every cap and format, both ways: name, email, occupation, event, source details,
--      treatments, others, durations, control characters, sex, age, date of birth, symptoms
--      (active, once, at most as many as the active options), signature (PNG, 100,000), PDF
--      (%PDF-, 4,500,000), the payload; each refusal raises SURVEY_INPUT(<field>) and keeps and
--      counts nothing.
--   R  No raw address in the tries table (a 64-character salted hash or nothing); the table and
--      the helper are the owner's alone.
--   G  530's md5s, grants and relied-on functions.
--   U  scripts/survey/undo-530.sql puts everything back (the reasons check too when no hold has
--      the new reason; left widened otherwise); undo-524 and undo-529 refuse cleanly while 530 is
--      in; 530 runs again after the undo.
--   M  530 a second time changes nothing (when this file installs it).
--
-- Disposable local database only; everything is rolled back. Every name and email is invented
-- (T530Sample, @example.invalid); phones are the fictional +61 491 570 5nn-7nn range; addresses
-- are from the documentation ranges (192.0.2.0/24, 198.51.100.0/24, 203.0.113.0/24,
-- 2001:db8::/32). Run it on a copy of production as it is (after 529): it applies 530 twice;
-- with -v skip_install=1 where 530 is already in; with -v control=1 on a copy WITHOUT 530 (it
-- does not install it, skips G, U and M, and fails on the checks 530 makes pass; see the end).
-- Every check runs, then the file fails if any did.
--   psql -X -v ON_ERROR_STOP=1 -f scripts/survey/tests/health-form-limits-530.sql
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
\if :{?control}
do $$ begin
  if position('-- 530 (security audit' in pg_get_functiondef('public.submit_health_survey(text,jsonb,jsonb,text)'::regprocedure)) > 0 then
    raise exception 'control: 530 is in on this copy; run -v control=1 on a copy without it'; end if;
end $$;
\elif :{?skip_install}
\else
select position('-- 530 (security audit' in pg_get_functiondef('public.submit_health_survey(text,jsonb,jsonb,text)'::regprocedure)) > 0 as m530_in \gset
\if :m530_in
\else
\ir ../../../supabase/530_the_health_form_has_limits_and_holds_existing_customers.sql
\endif
create temp table m530 as
  select p.oid::regprocedure::text as fn, md5(pg_get_functiondef(p.oid)) as md5, p.proacl::text as acl
    from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p');
create temp table m530t as
  select (select string_agg(column_name || ' ' || data_type || ' ' || is_nullable, ',' order by ordinal_position)
            from information_schema.columns where table_schema = 'public' and table_name = 'health_survey_tries') as cols,
         (select string_agg(pg_get_indexdef(indexrelid), ',' order by pg_get_indexdef(indexrelid))
            from pg_index where indrelid = 'public.health_survey_tries'::regclass) as idx,
         (select pg_get_constraintdef(c.oid) from pg_constraint c
           where c.conrelid = 'public.health_survey_holds'::regclass and c.conname = 'health_survey_holds_reason_check') as reasons,
         obj_description('public.referral_sender_salt'::regclass, 'pg_class') as salt_comment;
-- A second run changes nothing (checked in M).
\ir ../../../supabase/530_the_health_form_has_limits_and_holds_existing_customers.sql
\endif
set local lock_timeout = '10s';
set local statement_timeout = '600s';
create temp table failed(n serial, msg text);
create function pg_temp.check(ok boolean, msg text) returns void language plpgsql as
$$begin
  if ok is distinct from true then insert into failed(msg) values (msg); raise notice 'FAIL  %', msg;
  else raise notice 'PASS  %', msg; end if;
end$$;
create temp table fx(k text primary key, v uuid);
create temp table tx(k text primary key, v text);
create function pg_temp.fx(key text) returns uuid language sql as $$ select v from fx where k = key $$;
create function pg_temp.tx(key text) returns text language sql as $$ select v from tx where k = key $$;
create function pg_temp.put(key text, val text) returns void language sql as
$$ insert into tx values (key, val) on conflict (k) do update set v = excluded.v $$;
-- Fictional phones: +61 491 570 5nn to 7nn.
create function pg_temp.ph(n int) returns text language sql as $$ select '+61491570' || n::text $$;
create function pg_temp.mail(key text) returns text language sql as
$$ select 't530-' || lower(key) || '-' || pg_temp.tx('sfx') || '@example.invalid' $$;
create function pg_temp.token(key text) returns text language sql as $$ select 't530-' || key || '-' || pg_temp.tx('sfx') $$;
-- Request headers as PostgREST hands them over.
create function pg_temp.hdr(ip text, ua text default null, xff text default null) returns text language sql as
$$ select jsonb_strip_nulls(jsonb_build_object('cf-connecting-ip', ip, 'user-agent', ua, 'x-forwarded-for', xff))::text $$;
-- The sender key 529 keeps for an address (IPv4) or a /64 ('net::/64'): sha256 of the secret salt
-- and the address. Read here as the database owner; never printed.
create function pg_temp.key(k text) returns text language plpgsql as
$$declare v text; begin
  execute 'select salt from public.referral_sender_salt where id' into v;
  return encode(sha256(convert_to(v || '|' || k, 'UTF8')), 'hex');
end$$;
-- request_sender() as the owner, with these headers (or its error).
create function pg_temp.sender(headers text) returns text language plpgsql as
$$declare v text; begin
  perform set_config('request.headers', coalesce(headers, ''), true);
  begin
    execute 'select coalesce(host(address), ''-'') || '' '' || coalesce(sender_key, ''-'') from public.request_sender()' into v;
  exception when others then v := 'ERROR: ' || sqlerrm;
  end;
  perform set_config('request.headers', '', true);
  return v;
end$$;
-- The tries of this file's links (-1 where there is no tries table: a copy without 530).
create function pg_temp.tries(p_sender text default null, p_outcome text default null, p_link text default null) returns int language plpgsql as
$$declare v int; begin
  if to_regclass('public.health_survey_tries') is null then return -1; end if;
  execute 'select count(*)::int from public.health_survey_tries t
            where t.survey_link_id in (select v from fx where k like ''link:%'')
              and ($1 is null or t.sender_key = $1) and ($2 is null or t.outcome = $2)
              and ($3 is null or t.survey_link_id = (select v from fx where k = ''link:'' || $3))'
    into v using p_sender, p_outcome, p_link;
  return v;
end$$;
-- Moves this file's tries back in time (to test the hour), for one sender or one link.
create function pg_temp.age_tries(p_sender text, p_link text, p_by interval) returns void language plpgsql as
$$begin
  if to_regclass('public.health_survey_tries') is null then return; end if;
  execute 'update public.health_survey_tries t set created_at = t.created_at - $3
            where t.survey_link_id in (select v from fx where k like ''link:%'')
              and ($1 is null or t.sender_key = $1)
              and ($2 is null or t.survey_link_id = (select v from fx where k = ''link:'' || $2))'
    using p_sender, p_link, p_by;
end$$;

-- A form's answers as the page sends them; p_extra replaces or adds keys. Every form says it
-- was signed on 1 January 2020 and comes from 10.0.0.1 on 'payload-device': none of it is kept.
create function pg_temp.form(first text, phone text, email text, p_extra jsonb default '{}') returns jsonb language sql as
$$ select jsonb_build_object('first_name', first, 'last_name', 'T530Sample', 'full_name', first || ' T530Sample',
     'phone', phone, 'email', email,
     'signature_data', 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUg==', 'source_option_id', pg_temp.fx('src'),
     'source_details', '', 'sex', 'female', 'date_of_birth', '1980-05-06', 'age', '46', 'occupation', 'T530 Tester',
     'event_name', '', 'has_medical_condition', false, 'drinks_alcohol', true, 'smokes', false, 'on_treatment', false,
     'treatment_list', '', 'others_text', '',
     'consent_newsletter_email', false, 'consent_marketing_email', false, 'consent_marketing_sms', false,
     'consent_marketing_phone', false,
     'signed_date', '2020-01-01', 'ip_address', '10.0.0.1', 'device_info', 'payload-device') || p_extra $$;
create function pg_temp.pdf() returns text language sql as $$ select 'JVBERi0xLjQKJcfsj6IKMSAwIG9iago=' $$;
-- Sends a form as the page does: signed out, with these headers (null: none). Keeps the reply
-- (or {"error": message}) under 'r:<tag>'.
create function pg_temp.send(tag text, headers text, link text, payload jsonb, symptoms jsonb default '[]'::jsonb,
                             pdf text default 'JVBERi0xLjQKJcfsj6IKMSAwIG9iago=') returns jsonb language plpgsql as
$$declare r jsonb; v_token text := pg_temp.token(link); begin
  perform set_config('request.headers', coalesce(headers, ''), true);
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  execute 'set local role anon';
  begin
    r := public.submit_health_survey(v_token, payload, symptoms, pdf);
  exception when others then r := jsonb_build_object('error', sqlerrm);
  end;
  execute 'reset role';
  perform set_config('request.headers', '', true);
  perform set_config('request.jwt.claims', '', true);
  perform pg_temp.put('r:' || tag, r::text);
  return r;
end$$;
create function pg_temp.a(tag text) returns jsonb language sql as $$ select pg_temp.tx('r:' || tag)::jsonb $$;
create function pg_temp.err(tag text) returns text language sql as $$ select pg_temp.a(tag)->>'error' $$;
-- The reply a kept form gets, as before 530: success, today's survey number, the survey's id.
create function pg_temp.kept(tag text) returns boolean language sql as
$$ select coalesce((pg_temp.a(tag) - 'survey_no' - 'survey_id') = '{"success": true}'::jsonb
                   and pg_temp.a(tag)->>'survey_no' ~ ('^HS-' || to_char(now() at time zone 'Asia/Singapore', 'YYYYMMDD') || '-[0-9a-f]{6}$')
                   and exists (select 1 from public.health_surveys s where s.id = (pg_temp.a(tag)->>'survey_id')::uuid), false) $$;
create function pg_temp.refused(tag text, prefix text) returns boolean language sql as
$$ select coalesce(position(prefix in pg_temp.err(tag)) = 1, false) $$;
create function pg_temp.survey(tag text) returns public.health_surveys language sql as
$$ select s from public.health_surveys s where s.id = (pg_temp.a(tag)->>'survey_id')::uuid $$;
create function pg_temp.hold(tag text) returns public.health_survey_holds language sql as
$$ select h from public.health_survey_holds h where h.survey_id = (pg_temp.a(tag)->>'survey_id')::uuid $$;
create function pg_temp.audit(tag text) returns public.audit_logs language sql as
$$ select l from public.audit_logs l where l.action = 'health_survey_submitted' and l.record_id = (pg_temp.a(tag)->>'survey_id')::uuid $$;
create function pg_temp.forms_on(p text) returns int language sql as
$$ select count(*)::int from public.health_surveys s where s.phone = p $$;
create function pg_temp.record(cust text) returns text language sql as
$$ select to_jsonb(c)::text from public.customers c where c.id = pg_temp.fx(cust) $$;
-- One statement as a signed-in login: its first column as text, or 'ERROR: <message>'.
create function pg_temp.as_login(p_who text, q text) returns text language plpgsql as $f$
declare v text; u uuid := pg_temp.fx(p_who);
begin
  perform set_config('request.jwt.claim.sub', u::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', u, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  execute q into v;
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  return coalesce(v, 'ok');
exception when others then
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  return 'ERROR: ' || sqlerrm;
end $f$;
create function pg_temp.listed(p_who text, tag text) returns jsonb language sql as
$$ select e from jsonb_array_elements(nullif(pg_temp.as_login(p_who, 'select public.health_survey_holds_list()::text'), 'ok')::jsonb) e
    where (e->>'survey_id')::uuid = (pg_temp.a(tag)->>'survey_id')::uuid $$;
-- A count of everything a refused or dropped form could have kept, to compare before and after.
create function pg_temp.kept_all() returns text language sql as
$$ select (select count(*) from public.health_surveys)::text || '/' || (select count(*) from public.health_survey_holds)::text
          || '/' || (select count(*) from public.audit_logs where table_name = 'health_surveys')::text
          || '/' || (select count(*) from public.customers)::text || '/' || (select count(*) from public.health_survey_pdfs)::text
          || '/' || pg_temp.tries()::text $$;

-- ═════ P0 Fixtures ═════
do $$ begin insert into tx values ('sfx', lower(substr(md5(random()::text || clock_timestamp()::text), 1, 6))); end $$;
select pg_temp.check(not exists (select 1 from public.customers c where public.normalize_customer_phone(c.phone) ~ '^\+61491570[5-7][0-9][0-9]$')
    and not exists (select 1 from public.health_surveys s where s.phone ~ '^\+61491570[5-7][0-9][0-9]$'),
  'P0 no customer and no survey uses the test phones (+61491570500..799)');
do $$
declare sfx text := pg_temp.tx('sfx'); k text; u uuid; c uuid;
begin
  foreach k in array array['o', 'm', 's'] loop
    u := gen_random_uuid(); insert into fx values (k, u);
    insert into auth.users(id, email, email_confirmed_at) values (u, 't530-' || k || '-' || sfx || '@example.invalid', now());
  end loop;
  insert into public.profiles(id, full_name, email, role, is_active) values
    (pg_temp.fx('o'), 'T530 Owner',   't530-o-' || sfx || '@example.invalid', 'owner', true),
    (pg_temp.fx('m'), 'T530 Manager', 't530-m-' || sfx || '@example.invalid', 'manager', true),
    (pg_temp.fx('s'), 'T530 Staff',   't530-s-' || sfx || '@example.invalid', 'staff', true);
  insert into public.stores(name, code) values ('T530 Sample Store', 'T530' || sfx) returning id into c; insert into fx values ('store', c);
  insert into public.customer_source_options(label) values ('T530 Walk-in ' || sfx) returning id into c; insert into fx values ('src', c);
  insert into public.customer_source_options(label) values ('T530 Event ' || sfx) returning id into c; insert into fx values ('src_event', c);
  -- Links: one plain (A), one for an event (B, its source the event's), one for the link's limit (C),
  -- one for the caps (D).
  insert into public.survey_links(token, store_id) values (pg_temp.token('A'), pg_temp.fx('store')) returning id into c;
  insert into fx values ('link:A', c);
  insert into public.survey_links(token, store_id, event_name, source_option_id)
  values (pg_temp.token('B'), pg_temp.fx('store'), 'T530 Expo ' || sfx, pg_temp.fx('src_event')) returning id into c;
  insert into fx values ('link:B', c);
  insert into public.survey_links(token, store_id) values (pg_temp.token('C'), pg_temp.fx('store')) returning id into c;
  insert into fx values ('link:C', c);
  insert into public.survey_links(token, store_id) values (pg_temp.token('D'), pg_temp.fx('store')) returning id into c;
  insert into fx values ('link:D', c);
  -- Symptom options: three this file adds, and one switched off.
  insert into public.health_symptom_options(category, label, sort_order, is_active) values ('Pain', 'T530 Ache ' || sfx, 9001, true) returning id into c;
  insert into fx values ('sym1', c);
  insert into public.health_symptom_options(category, label, sort_order, is_active) values ('Sleep', 'T530 Wake ' || sfx, 9002, true) returning id into c;
  insert into fx values ('sym2', c);
  insert into public.health_symptom_options(category, label, sort_order, is_active) values ('Stress', 'T530 Worry ' || sfx, 9003, true) returning id into c;
  insert into fx values ('sym3', c);
  insert into public.health_symptom_options(category, label, sort_order, is_active) values ('Pain', 'T530 Old ' || sfx, 9004, false) returning id into c;
  insert into fx values ('symOff', c);
  -- Customers on file, their details empty: Ann (no survey), Ben (no survey), Cal (a
  -- consultant's record he has not signed), Dan (a signed survey).
  insert into public.customers(full_name, phone, email) values ('Ann T530Sample', pg_temp.ph(501), pg_temp.mail('ann')) returning id into c;
  insert into fx values ('cAnn', c);
  insert into public.customers(full_name, phone, email) values ('Ben T530Sample', pg_temp.ph(502), pg_temp.mail('ben')) returning id into c;
  insert into fx values ('cBen', c);
  insert into public.customers(full_name, phone, email) values ('Cal T530Sample', pg_temp.ph(503), pg_temp.mail('cal')) returning id into c;
  insert into fx values ('cCal', c);
  insert into public.health_surveys(survey_no, full_name, customer_id, phone, source, store_id, created_by)
  values ('HS-T530C-' || sfx, 'Cal T530Sample', c, pg_temp.ph(503), 'consultant', pg_temp.fx('store'), pg_temp.fx('s'))
  returning id into u; insert into fx values ('recCal', u);
  insert into public.customers(full_name, phone, email) values ('Dan T530Sample', pg_temp.ph(504), pg_temp.mail('dan')) returning id into c;
  insert into fx values ('cDan', c);
  insert into public.health_surveys(survey_no, full_name, customer_id, phone, source, store_id, signature_data)
  values ('HS-T530D-' || sfx, 'Dan T530Sample', c, pg_temp.ph(504), 'public_form', pg_temp.fx('store'), 'data:image/png;base64,AAAA');
end $$;
insert into tx select 'rec:' || k, pg_temp.record(k) from unnest(array['cAnn', 'cBen', 'cCal', 'cDan']) k;
insert into tx select 'recCal', to_jsonb(s)::text from public.health_surveys s where s.id = pg_temp.fx('recCal');
select pg_temp.check((select count(*) from public.health_symptom_options where is_active) >= 3,
  'P0 (setup) the active symptom options include this file''s three');

-- ═════ H Hold for staff ═════
select pg_temp.send('ann', pg_temp.hdr('192.0.2.11'), 'A', pg_temp.form('Ann', pg_temp.ph(501), pg_temp.mail('ann-typed'),
         '{"sex": "female", "occupation": "Ann typed this"}'),
         jsonb_build_array(jsonb_build_object('option_id', pg_temp.fx('sym1'), 'duration_text', '2 weeks')));
select pg_temp.check(pg_temp.kept('ann')
    and (pg_temp.survey('ann')).customer_id is null
    and (pg_temp.hold('ann')).reason = 'existing_customer' and (pg_temp.hold('ann')).resolved_at is null
    and (pg_temp.hold('ann')).candidate_customer_ids = array[pg_temp.fx('cAnn')]
    and (pg_temp.hold('ann')).typed_full_name = 'Ann T530Sample' and (pg_temp.hold('ann')).typed_phone = pg_temp.ph(501),
  'H1 phone and name of a customer with no survey (Ann): kept with no customer, waiting (existing_customer) with Ann the only candidate: ' || pg_temp.tx('r:ann'));
select pg_temp.check(pg_temp.record('cAnn') = pg_temp.tx('rec:cAnn')
    and not exists (select 1 from public.health_surveys where customer_id = pg_temp.fx('cAnn')),
  'H2 nothing is copied onto Ann (her date of birth, gender, occupation and source stay empty; the record is unchanged) and she has no survey');
select pg_temp.check((pg_temp.audit('ann')).new_data @> '{"held_for_staff": true, "hold_reason": "existing_customer", "customer_matched": false, "customer_created": false, "name_match": "exact", "signed_into_record": false}'::jsonb
    and (pg_temp.audit('ann')).new_data->>'customer_id' is null,
  'H3 the audit row says the form was held for staff (existing_customer), matched by the name, nobody attached or made');
select pg_temp.send('ben', pg_temp.hdr('192.0.2.12'), 'A', pg_temp.form('Bo', pg_temp.ph(502), pg_temp.mail('ben'),
         '{"last_name": "Otherperson", "full_name": "Bo Otherperson", "occupation": "Bo typed this"}'));
select pg_temp.check(pg_temp.kept('ben') and (pg_temp.survey('ben')).customer_id is null
    and (pg_temp.hold('ben')).reason = 'existing_customer' and (pg_temp.hold('ben')).candidate_customer_ids = array[pg_temp.fx('cBen')]
    and (pg_temp.survey('ben')).full_name = 'Bo Otherperson'
    and (pg_temp.audit('ben')).new_data->>'name_match' = 'phone_and_email'
    and pg_temp.record('cBen') = pg_temp.tx('rec:cBen'),
  'H4 phone and email of a customer under another name (Ben, 468): held the same way with Ben the candidate, the name typed kept on the form, nothing copied onto Ben: ' || pg_temp.tx('r:ben'));
select pg_temp.send('cal', pg_temp.hdr('192.0.2.13'), 'A', pg_temp.form('Cal', pg_temp.ph(503), pg_temp.mail('cal')),
         jsonb_build_array(jsonb_build_object('option_id', pg_temp.fx('sym2'), 'duration_text', '1 month')));
select pg_temp.check(pg_temp.kept('cal') and (pg_temp.survey('cal')).customer_id is null
    and (pg_temp.hold('cal')).reason = 'existing_customer' and (pg_temp.hold('cal')).candidate_customer_ids = array[pg_temp.fx('cCal')]
    and (select to_jsonb(s)::text from public.health_surveys s where s.id = pg_temp.fx('recCal')) = pg_temp.tx('recCal')
    and not exists (select 1 from public.health_survey_symptoms y where y.survey_id = pg_temp.fx('recCal'))
    and pg_temp.record('cCal') = pg_temp.tx('rec:cCal')
    and (pg_temp.audit('cal')).new_data @> '{"signed_into_record": false}'::jsonb,
  'H5 a customer with a consultant''s record he has not signed (Cal, 419 Q10): held with Cal the candidate; the record is not signed or changed, no symptoms put in it, nothing copied onto Cal');
select pg_temp.send('dan', pg_temp.hdr('192.0.2.14'), 'A', pg_temp.form('Dan', pg_temp.ph(504), pg_temp.mail('dan')));
select pg_temp.check(pg_temp.kept('dan') and (pg_temp.survey('dan')).customer_id is null
    and (pg_temp.hold('dan')).reason = 'customer_has_survey' and (pg_temp.hold('dan')).candidate_customer_ids = array[pg_temp.fx('cDan')]
    and pg_temp.record('cDan') = pg_temp.tx('rec:cDan'),
  'H6 a customer who has a survey (Dan): waits as before (customer_has_survey)');
select pg_temp.send('nia', pg_temp.hdr('192.0.2.15'), 'A', pg_temp.form('Nia', pg_temp.ph(505), pg_temp.mail('nia'),
         '{"sex": "female", "date_of_birth": "1975-03-04", "occupation": "Nia''s job"}'));
select pg_temp.check(pg_temp.kept('nia') and pg_temp.hold('nia') is null
    and exists (select 1 from public.customers c where c.id = (pg_temp.survey('nia')).customer_id
                  and c.full_name = 'Nia T530Sample' and c.phone = pg_temp.ph(505) and c.email = pg_temp.mail('nia')
                  and c.date_of_birth = '1975-03-04' and c.gender = 'female' and c.occupation = 'Nia''s job'
                  and c.source_option_id = pg_temp.fx('src'))
    and (pg_temp.audit('nia')).new_data @> '{"customer_created": true, "held_for_staff": false}'::jsonb,
  'H7 someone new (phone and email not in use): the form makes the customer, with its details, as before');
select pg_temp.check(pg_temp.listed('s', 'ann')->>'reason' = 'existing_customer'
    and (select array_agg(c->>'customer_id') from jsonb_array_elements(pg_temp.listed('s', 'ann')->'candidates') c) = array[pg_temp.fx('cAnn')::text]
    and pg_temp.listed('s', 'cal')->>'reason' = 'existing_customer'
    and (pg_temp.listed('s', 'cal')->'candidates'->0->>'survey_takes_form')::boolean,
  'H8 Staff see the forms in To match with the reason existing_customer and the customer as the candidate (Cal''s record takes the form)');
select pg_temp.send('ann2', pg_temp.hdr('192.0.2.11'), 'A', pg_temp.form('Ann', pg_temp.ph(501), pg_temp.mail('ann-typed')));
select pg_temp.check(pg_temp.kept('ann2') and (pg_temp.survey('ann2')).customer_id is null
    and (pg_temp.hold('ann2')).reason = 'repeat_form' and (pg_temp.hold('ann2')).candidate_customer_ids = array[pg_temp.fx('cAnn')]
    and pg_temp.record('cAnn') = pg_temp.tx('rec:cAnn'),
  'H9 Ann''s form sent again while the first waits: waits too (repeat_form, 524) with Ann, nothing copied');

-- ═════ A Staff attach ═════
select pg_temp.put('att:ann', pg_temp.as_login('s', format('select public.attach_held_health_survey(%L, %L, %L)::text',
  pg_temp.a('ann')->>'survey_id', pg_temp.fx('cAnn'), 'Checked her phone and name at the counter')));
select pg_temp.check(pg_temp.tx('att:ann') like '{"ok": true%'
    and (pg_temp.survey('ann')).customer_id = pg_temp.fx('cAnn')
    and (pg_temp.hold('ann')).resolution = 'attached' and (pg_temp.hold('ann')).resolved_customer_id = pg_temp.fx('cAnn')
    and exists (select 1 from public.customers c where c.id = pg_temp.fx('cAnn') and c.date_of_birth = '1980-05-06'
                  and c.gender = 'female' and c.occupation = 'Ann typed this' and c.source_option_id = pg_temp.fx('src')
                  and c.full_name = 'Ann T530Sample' and c.phone = pg_temp.ph(501) and c.email = pg_temp.mail('ann')),
  'A1 Staff attach Ann''s form: it is hers; her EMPTY date of birth, gender, occupation and source are filled from it; her name, phone and email stay: ' || pg_temp.tx('att:ann'));
select pg_temp.put('att:ben', pg_temp.as_login('s', format('select public.attach_held_health_survey(%L, %L, %L)::text',
  pg_temp.a('ben')->>'survey_id', pg_temp.fx('cBen'), 'Ben confirmed the email is his')));
select pg_temp.check(pg_temp.tx('att:ben') like '{"ok": true%' and (pg_temp.survey('ben')).customer_id = pg_temp.fx('cBen')
    and (pg_temp.survey('ben')).full_name = 'Ben T530Sample'
    and exists (select 1 from public.customers c where c.id = pg_temp.fx('cBen') and c.occupation = 'Bo typed this'
                  and c.full_name = 'Ben T530Sample' and c.email = pg_temp.mail('ben')),
  'A2 Staff attach Ben''s form (phone and email): it is his and takes his name; his empty details are filled: ' || pg_temp.tx('att:ben'));
select pg_temp.put('att:cal', pg_temp.as_login('s', format('select public.attach_held_health_survey(%L, %L, %L)::text',
  pg_temp.a('cal')->>'survey_id', pg_temp.fx('cCal'), 'Cal signed at the counter')));
select pg_temp.check(pg_temp.tx('att:cal') like '{"ok": true%'
    and (pg_temp.tx('att:cal')::jsonb)->>'signed_into_survey_no' = 'HS-T530C-' || pg_temp.tx('sfx')
    and exists (select 1 from public.health_surveys s where s.id = pg_temp.fx('recCal') and s.signature_data is not null
                  and s.signed_date = public.sg_today() and s.drinks_alcohol)
    and exists (select 1 from public.health_survey_symptoms y where y.survey_id = pg_temp.fx('recCal') and y.option_id = pg_temp.fx('sym2'))
    and (pg_temp.survey('cal')).customer_id is null and (pg_temp.hold('cal')).resolution = 'attached',
  'A3 Staff attach Cal''s form: his consultant''s record is signed with its answers and symptoms (dated the day the form arrived); the form stays with no customer, marked attached: ' || pg_temp.tx('att:cal'));

-- ═════ L Limits per sender and per link ═════
-- One sender (203.0.113.10): ten forms through link A, each someone new; the 11th refused.
do $$ begin
  for i in 1 .. 10 loop
    perform pg_temp.send('s1-' || i, pg_temp.hdr('203.0.113.10'), 'A', pg_temp.form('Sen' || i, pg_temp.ph(700 + i), pg_temp.mail('sen' || i)));
  end loop;
end $$;
select pg_temp.put('before:s1-11', pg_temp.kept_all());
select pg_temp.send('s1-11', pg_temp.hdr('203.0.113.10'), 'A', pg_temp.form('Sen11', pg_temp.ph(711), pg_temp.mail('sen11')));
select pg_temp.check((select bool_and(pg_temp.kept('s1-' || i)) from generate_series(1, 10) i)
    and pg_temp.tries(pg_temp.key('203.0.113.10'), 'kept') = 10,
  'L1 one sender''s first 10 forms in an hour are kept, each counted under the sender''s salted key');
select pg_temp.check(pg_temp.refused('s1-11', 'SURVEY_BUSY: Many forms have been sent from this connection in the last hour. Please try again later')
    and pg_temp.kept_all() = pg_temp.tx('before:s1-11') and pg_temp.forms_on(pg_temp.ph(711)) = 0,
  'L2 its 11th is refused (SURVEY_BUSY, try again later), and nothing is kept or counted: ' || pg_temp.tx('r:s1-11'));
select pg_temp.send('s1-xff', pg_temp.hdr('203.0.113.10', null, '198.51.100.99'), 'A', pg_temp.form('Sen12', pg_temp.ph(712), pg_temp.mail('sen12')));
select pg_temp.send('s2', pg_temp.hdr('203.0.113.20', null, '203.0.113.10'), 'A', pg_temp.form('Sen13', pg_temp.ph(713), pg_temp.mail('sen13')));
select pg_temp.send('xff-only', '{"x-forwarded-for":"203.0.113.10"}', 'A', pg_temp.form('Sen14', pg_temp.ph(714), pg_temp.mail('sen14')));
select pg_temp.check(pg_temp.refused('s1-xff', 'SURVEY_BUSY:') and pg_temp.kept('s2') and pg_temp.kept('xff-only')
    and pg_temp.tries(pg_temp.key('203.0.113.20')) = 1 and pg_temp.tries(pg_temp.key('203.0.113.10')) = 10
    and pg_temp.tries(pg_temp.key('198.51.100.99')) = 0,
  'L3 x-forwarded-for changes nothing: beside the limited address it is still refused; another sender is not limited, even naming the limited address in it; alone it makes no sender (no sender''s limit)');
select pg_temp.check(pg_temp.sender(pg_temp.hdr('2001:db8:a:b::1')) = '2001:db8:a:b::1 ' || pg_temp.key('2001:db8:a:b::/64')
    and split_part(pg_temp.sender(pg_temp.hdr('2001:0DB8:000A:000B:ffff::9')), ' ', 2) = pg_temp.key('2001:db8:a:b::/64')
    and split_part(pg_temp.sender(pg_temp.hdr('2001:db8:a:c::1')), ' ', 2) <> pg_temp.key('2001:db8:a:b::/64')
    and pg_temp.sender(pg_temp.hdr('::ffff:192.0.2.77')) = '192.0.2.77 ' || pg_temp.key('192.0.2.77')
    and pg_temp.sender(pg_temp.hdr(' 192.0.2.78 ')) = '192.0.2.78 ' || pg_temp.key('192.0.2.78')
    and pg_temp.sender(pg_temp.hdr('192.0.2.0/24')) = '- -' and pg_temp.sender(pg_temp.hdr('not an address')) = '- -'
    and pg_temp.sender(null) = '- -' and pg_temp.sender('{"x-forwarded-for":"192.0.2.1"}') = '- -',
  'L4 request_sender: an IPv6 address is its /64 (another address in it, written another way, is the same sender; another /64 is not); ::ffff:a.b.c.d is a.b.c.d; a padded address is the address; a network, junk, no header or x-forwarded-for alone: no sender');
do $$ declare v_ok boolean := false; begin
  if to_regprocedure('public.request_sender()') is not null then
    perform set_config('request.headers', pg_temp.hdr('2001:db8:5:6::7'), true);
    perform public.affiliate_referral_signup('T530NOLINK' || pg_temp.tx('sfx'), 'Kim', 'T530Sample', pg_temp.ph(599), null, null);
    v_ok := (select e.sender_key from public.referral_signup_events e where e.referral_code = 'T530NOLINK' || pg_temp.tx('sfx'))
            = (select sender_key from public.request_sender());
    perform set_config('request.headers', '', true);
  end if;
  perform pg_temp.put('same529', v_ok::text);
end $$;
select pg_temp.check(pg_temp.tx('same529') = 'true',
  'L5 one sender has one key on both public forms: request_sender''s key is the one 529''s referral sign-up records for the same address');
select pg_temp.age_tries(pg_temp.key('203.0.113.10'), null, interval '61 minutes');
select pg_temp.send('s1-later', pg_temp.hdr('203.0.113.10'), 'A', pg_temp.form('Sen15', pg_temp.ph(715), pg_temp.mail('sen15')));
select pg_temp.check(pg_temp.kept('s1-later'),
  'L6 an hour later the sender may send again (only the last hour counts)');
-- One link (C): sixty forms in an hour, from no sender (only the link's limit applies); the 61st refused.
do $$ begin
  for i in 1 .. 60 loop
    perform pg_temp.send('c-' || i, null, 'C', pg_temp.form('Lin' || i, pg_temp.ph(600 + i), pg_temp.mail('lin' || i)));
  end loop;
end $$;
select pg_temp.put('before:c-61', pg_temp.kept_all());
select pg_temp.send('c-61', null, 'C', pg_temp.form('Lin61', pg_temp.ph(661), pg_temp.mail('lin61')));
select pg_temp.send('c-62', pg_temp.hdr('203.0.113.30'), 'C', pg_temp.form('Lin62', pg_temp.ph(662), pg_temp.mail('lin62')));
select pg_temp.send('a-other', pg_temp.hdr('203.0.113.30'), 'A', pg_temp.form('Lin63', pg_temp.ph(663), pg_temp.mail('lin63')));
select pg_temp.check((select bool_and(pg_temp.kept('c-' || i)) from generate_series(1, 60) i) and pg_temp.tries(null, null, 'C') = 60,
  'L7 one link takes 60 forms in an hour');
select pg_temp.check(pg_temp.refused('c-61', 'SURVEY_BUSY: This form link has received many forms in the last hour. Please try again later')
    and pg_temp.refused('c-62', 'SURVEY_BUSY: This form link')
    and pg_temp.forms_on(pg_temp.ph(661)) = 0 and pg_temp.forms_on(pg_temp.ph(662)) = 0
    and pg_temp.kept('a-other') and pg_temp.tries(null, null, 'C') = 60,
  'L8 its 61st is refused (SURVEY_BUSY), from no sender or a fresh one, nothing kept; another link is not limited: ' || pg_temp.tx('r:c-61'));
select pg_temp.age_tries(null, 'C', interval '61 minutes');
select pg_temp.send('c-later', null, 'C', pg_temp.form('Lin64', pg_temp.ph(664), pg_temp.mail('lin64')));
select pg_temp.check(pg_temp.kept('c-later'), 'L9 an hour later the link takes forms again');

-- ═════ D 3 a day per phone ═════
-- Sender 203.0.113.40 sends Pat's form three times (two through A, one through B, the event's).
select pg_temp.send('p1', pg_temp.hdr('203.0.113.40'), 'A', pg_temp.form('Pat', pg_temp.ph(530), pg_temp.mail('pat')));
select pg_temp.send('p2', pg_temp.hdr('203.0.113.40'), 'B', pg_temp.form('Pat', pg_temp.ph(530), pg_temp.mail('pat')));
select pg_temp.send('p3', pg_temp.hdr('203.0.113.40'), 'A', pg_temp.form('Pat', pg_temp.ph(530), pg_temp.mail('pat')));
select pg_temp.put('before:p4', pg_temp.kept_all());
select pg_temp.send('p4', pg_temp.hdr('203.0.113.40'), 'A', pg_temp.form('Pat', pg_temp.ph(530), pg_temp.mail('pat')));
select pg_temp.check(pg_temp.kept('p1') and pg_temp.kept('p2') and pg_temp.kept('p3') and pg_temp.forms_on(pg_temp.ph(530)) = 3,
  'D1 three forms under one phone in a day are kept, through any link');
select pg_temp.check(pg_temp.a('p4') = '{"success": true}'::jsonb and pg_temp.forms_on(pg_temp.ph(530)) = 3
    and split_part(pg_temp.kept_all(), '/', 1) = split_part(pg_temp.tx('before:p4'), '/', 1)
    and split_part(pg_temp.kept_all(), '/', 2) = split_part(pg_temp.tx('before:p4'), '/', 2)
    and split_part(pg_temp.kept_all(), '/', 3) = split_part(pg_temp.tx('before:p4'), '/', 3)
    and split_part(pg_temp.kept_all(), '/', 4) = split_part(pg_temp.tx('before:p4'), '/', 4)
    and split_part(pg_temp.kept_all(), '/', 5) = split_part(pg_temp.tx('before:p4'), '/', 5)
    and pg_temp.tries(pg_temp.key('203.0.113.40'), 'dropped') = 1,
  'D2 the 4th of the day keeps nothing (no form, hold, audit row, customer or PDF) and is answered {"success": true}, no survey number; the try is counted (dropped): ' || pg_temp.tx('r:p4'));
do $$ begin
  for i in 5 .. 10 loop
    perform pg_temp.send('p' || i, pg_temp.hdr('203.0.113.40'), 'B', pg_temp.form('Pat', pg_temp.ph(530), pg_temp.mail('pat')));
  end loop;
end $$;
select pg_temp.send('p11', pg_temp.hdr('203.0.113.40'), 'A', pg_temp.form('Quin', pg_temp.ph(531), pg_temp.mail('quin')));
select pg_temp.check((select bool_and(pg_temp.a('p' || i) = '{"success": true}'::jsonb) from generate_series(5, 10) i)
    and pg_temp.tries(pg_temp.key('203.0.113.40'), 'dropped') = 7 and pg_temp.tries(pg_temp.key('203.0.113.40')) = 10
    and pg_temp.refused('p11', 'SURVEY_BUSY: Many forms have been sent from this connection'),
  'D3 dropped tries count toward the sender''s 10 an hour: after 3 kept and 7 dropped, its next form (someone else''s) is refused');
update public.health_surveys set submitted_at = submitted_at - interval '1 day' where phone = pg_temp.ph(530);
select pg_temp.send('p12', pg_temp.hdr('203.0.113.41'), 'A', pg_temp.form('Pat', pg_temp.ph(530), pg_temp.mail('pat')));
select pg_temp.check(pg_temp.kept('p12') and pg_temp.forms_on(pg_temp.ph(530)) = 4,
  'D4 forms of an earlier Singapore day do not count: a new day''s form is kept');
-- Cal's phone: his form today, and his consultant's record it went into when staff attached it (A3).
select pg_temp.send('cal2', pg_temp.hdr('203.0.113.42'), 'A', pg_temp.form('Cal', pg_temp.ph(503), pg_temp.mail('cal')));
select pg_temp.send('cal3', pg_temp.hdr('203.0.113.42'), 'A', pg_temp.form('Cal', pg_temp.ph(503), pg_temp.mail('cal')));
select pg_temp.send('cal4', pg_temp.hdr('203.0.113.42'), 'A', pg_temp.form('Cal', pg_temp.ph(503), pg_temp.mail('cal')));
select pg_temp.check(pg_temp.kept('cal2') and pg_temp.kept('cal3') and pg_temp.a('cal4') = '{"success": true}'::jsonb
    and (select survey_link_id is not null and signature_data is not null from public.health_surveys where id = pg_temp.fx('recCal')),
  'D5 a consultant''s record a form was signed into is not counted again: with his one form of today, two more are kept, the next dropped');

-- ═════ T Day it arrives ═════
select pg_temp.check((select bool_and((pg_temp.survey(t)).signed_date = public.sg_today()) from unnest(array['nia', 'ann', 'dan', 'p1', 'c-1', 's1-1']) t),
  'T1 every form sent with signed_date 2020-01-01 is dated the Singapore day it arrived');
select pg_temp.send('t2', pg_temp.hdr('192.0.2.30'), 'A', pg_temp.form('Tess', pg_temp.ph(532), pg_temp.mail('tess')) - 'signed_date');
select pg_temp.check((pg_temp.survey('t2')).signed_date = public.sg_today(), 'T2 a form with no signed_date: the same');

-- ═════ E Event name ═════
select pg_temp.send('e1', pg_temp.hdr('192.0.2.31'), 'B', pg_temp.form('Eve', pg_temp.ph(533), pg_temp.mail('eve'), '{"event_name": "Some Other Event"}'));
select pg_temp.send('e2', pg_temp.hdr('192.0.2.32'), 'A', pg_temp.form('Eli', pg_temp.ph(534), pg_temp.mail('eli'), '{"event_name": "Typed Event"}'));
select pg_temp.check((pg_temp.survey('e1')).event_name = 'T530 Expo ' || pg_temp.tx('sfx')
    and (pg_temp.survey('e1')).source_option_id = pg_temp.fx('src_event')
    and (pg_temp.survey('e2')).event_name = 'Typed Event',
  'E1 a link''s event name wins over the one typed; a link with none keeps the one typed');

-- ═════ I Address and device ═════
select pg_temp.send('i1', pg_temp.hdr('192.0.2.44', 'T530Agent/1.0 ' || chr(1) || 'x', '198.51.100.7'), 'A',
         pg_temp.form('Ivy', pg_temp.ph(535), pg_temp.mail('ivy')), '[]'::jsonb, '');
select pg_temp.send('i2', pg_temp.hdr('2001:db8:44::5', repeat('U', 300)), 'A', pg_temp.form('Ida', pg_temp.ph(536), pg_temp.mail('ida')));
select pg_temp.send('i3', null, 'A', pg_temp.form('Isa', pg_temp.ph(537), pg_temp.mail('isa')));
select pg_temp.check((pg_temp.survey('i1')).ip_address = '192.0.2.44' and (pg_temp.survey('i1')).device_info = 'T530Agent/1.0  x'
    and (pg_temp.audit('i1')).ip_address = '192.0.2.44' and (pg_temp.audit('i1')).device_info = 'T530Agent/1.0  x'
    and exists (select 1 from public.audit_logs l where l.action = 'signed_pdf_missing' and l.record_id = (pg_temp.a('i1')->>'survey_id')::uuid
                  and l.ip_address = '192.0.2.44' and l.device_info = 'T530Agent/1.0  x'),
  'I1 the form and its audit rows keep the request''s cf-connecting-ip and user-agent (its control character taken out), not the payload''s 10.0.0.1 / payload-device or x-forwarded-for');
select pg_temp.check((pg_temp.survey('i2')).ip_address = '2001:db8:44::5' and (pg_temp.survey('i2')).device_info = repeat('U', 250)
    and (pg_temp.survey('i3')).ip_address is null and (pg_temp.survey('i3')).device_info is null
    and (pg_temp.audit('i3')).ip_address is null and (pg_temp.audit('i3')).device_info is null,
  'I2 an IPv6 address is kept as sent; a user-agent is cut to 250 characters; without the headers, none (the payload''s are never kept)');

-- ═════ C Caps and formats, both ways ═════
-- Each accepted case is a new person (its own phone); each refused one keeps and counts nothing.
create temp table cases(n serial, tag text, ok boolean, field text, payload jsonb, symptoms jsonb default '[]'::jsonb, pdf text default 'JVBERi0xLjQKJcfsj6IKMSAwIG9iago=');
insert into cases(tag, ok, field, payload, symptoms, pdf) values
  ('name100',   true,  null, jsonb_build_object('first_name', repeat('N', 49), 'last_name', repeat('M', 50)), '[]', pg_temp.pdf()),
  ('name101',   false, 'first_name', jsonb_build_object('first_name', repeat('N', 50), 'last_name', repeat('M', 50)), '[]', pg_temp.pdf()),
  ('namectl',   false, 'first_name', jsonb_build_object('first_name', 'Ne' || chr(7) || 'd'), '[]', pg_temp.pdf()),
  ('lastctl',   false, 'first_name', jsonb_build_object('last_name', 'T530' || chr(27) || 'x'), '[]', pg_temp.pdf()),
  ('email254',  true,  null, jsonb_build_object('email', repeat('e', 254 - length('@example.invalid')) || '@example.invalid'), '[]', pg_temp.pdf()),
  ('email255',  false, 'email', jsonb_build_object('email', repeat('e', 255 - length('@example.invalid')) || '@example.invalid'), '[]', pg_temp.pdf()),
  ('emailctl',  false, 'email', jsonb_build_object('email', 'e' || chr(1) || 'x@example.invalid'), '[]', pg_temp.pdf()),
  ('occ100',    true,  null, jsonb_build_object('occupation', repeat('o', 100)), '[]', pg_temp.pdf()),
  ('occ101',    false, 'occupation', jsonb_build_object('occupation', repeat('o', 101)), '[]', pg_temp.pdf()),
  ('occctl',    false, 'occupation', jsonb_build_object('occupation', 'o' || chr(9) || 'o'), '[]', pg_temp.pdf()),
  ('event100',  true,  null, jsonb_build_object('event_name', repeat('v', 100)), '[]', pg_temp.pdf()),
  ('event101',  false, 'event_name', jsonb_build_object('event_name', repeat('v', 101)), '[]', pg_temp.pdf()),
  ('eventctl',  false, 'event_name', jsonb_build_object('event_name', 'v' || chr(10) || 'v'), '[]', pg_temp.pdf()),
  ('det200',    true,  null, jsonb_build_object('source_details', repeat('d', 200)), '[]', pg_temp.pdf()),
  ('det201',    false, 'source_details', jsonb_build_object('source_details', repeat('d', 201)), '[]', pg_temp.pdf()),
  ('detctl',    false, 'source_details', jsonb_build_object('source_details', 'd' || chr(13) || 'd'), '[]', pg_temp.pdf()),
  ('treat1000', true,  null, jsonb_build_object('on_treatment', true, 'treatment_list', repeat('t', 1000)), '[]', pg_temp.pdf()),
  ('treat1001', false, 'treatment_list', jsonb_build_object('on_treatment', true, 'treatment_list', repeat('t', 1001)), '[]', pg_temp.pdf()),
  ('treatctl',  false, 'treatment_list', jsonb_build_object('treatment_list', 't' || chr(127) || 't'), '[]', pg_temp.pdf()),
  ('oth1000',   true,  null, jsonb_build_object('others_text', repeat('x', 1000)), '[]', pg_temp.pdf()),
  ('oth1001',   false, 'others_text', jsonb_build_object('others_text', repeat('x', 1001)), '[]', pg_temp.pdf()),
  ('othctl',    false, 'others_text', jsonb_build_object('others_text', 'x' || chr(155) || 'x'), '[]', pg_temp.pdf()),
  ('sexother',  true,  null, jsonb_build_object('sex', 'other'), '[]', pg_temp.pdf()),
  ('sexblank',  true,  null, jsonb_build_object('sex', ''), '[]', pg_temp.pdf()),
  ('sexodd',    false, 'sex', jsonb_build_object('sex', 'robot'), '[]', pg_temp.pdf()),
  ('age0',      true,  null, jsonb_build_object('age', '0', 'date_of_birth', ''), '[]', pg_temp.pdf()),
  ('age120',    true,  null, jsonb_build_object('age', 120, 'date_of_birth', ''), '[]', pg_temp.pdf()),
  ('age121',    false, 'age', jsonb_build_object('age', '121', 'date_of_birth', ''), '[]', pg_temp.pdf()),
  ('ageneg',    false, 'age', jsonb_build_object('age', '-1', 'date_of_birth', ''), '[]', pg_temp.pdf()),
  ('ageword',   false, 'age', jsonb_build_object('age', 'forty', 'date_of_birth', ''), '[]', pg_temp.pdf()),
  ('dob1900',   true,  null, jsonb_build_object('date_of_birth', '1900-01-01', 'age', ''), '[]', pg_temp.pdf()),
  ('dobtoday',  true,  null, jsonb_build_object('date_of_birth', public.sg_today()::text, 'age', ''), '[]', pg_temp.pdf()),
  ('dob1899',   false, 'date_of_birth', jsonb_build_object('date_of_birth', '1899-12-31', 'age', ''), '[]', pg_temp.pdf()),
  ('dobtmrw',   false, 'date_of_birth', jsonb_build_object('date_of_birth', (public.sg_today() + 1)::text, 'age', ''), '[]', pg_temp.pdf()),
  ('dobfake',   false, 'date_of_birth', jsonb_build_object('date_of_birth', '2023-02-30', 'age', ''), '[]', pg_temp.pdf()),
  ('dobword',   false, 'date_of_birth', jsonb_build_object('date_of_birth', 'yesterday', 'age', ''), '[]', pg_temp.pdf()),
  ('symall',    true,  null, '{}'::jsonb, (select jsonb_agg(jsonb_build_object('option_id', o.id, 'duration_text', repeat('w', 60)))
                                             from public.health_symptom_options o where o.is_active), pg_temp.pdf()),
  ('symnull',   true,  null, '{}'::jsonb, null, pg_temp.pdf()),
  ('symmore',   false, 'symptoms', '{}'::jsonb, (select jsonb_agg(jsonb_build_object('option_id', o.id)) from public.health_symptom_options o where o.is_active)
                                                 || jsonb_build_array(jsonb_build_object('option_id', pg_temp.fx('sym1'))), pg_temp.pdf()),
  ('symtwice',  false, 'symptoms', '{}'::jsonb, jsonb_build_array(jsonb_build_object('option_id', pg_temp.fx('sym1')), jsonb_build_object('option_id', pg_temp.fx('sym1'))), pg_temp.pdf()),
  ('symoff',    false, 'symptoms', '{}'::jsonb, jsonb_build_array(jsonb_build_object('option_id', pg_temp.fx('symOff'))), pg_temp.pdf()),
  ('symunk',    false, 'symptoms', '{}'::jsonb, jsonb_build_array(jsonb_build_object('option_id', gen_random_uuid())), pg_temp.pdf()),
  ('symjunk',   false, 'symptoms', '{}'::jsonb, '["not an option"]'::jsonb, pg_temp.pdf()),
  ('symobj',    false, 'symptoms', '{}'::jsonb, '{"option_id": "x"}'::jsonb, pg_temp.pdf()),
  ('dur61',     false, 'symptoms', '{}'::jsonb, jsonb_build_array(jsonb_build_object('option_id', pg_temp.fx('sym1'), 'duration_text', repeat('w', 61))), pg_temp.pdf()),
  ('durctl',    false, 'symptoms', '{}'::jsonb, jsonb_build_array(jsonb_build_object('option_id', pg_temp.fx('sym1'), 'duration_text', 'w' || chr(8))), pg_temp.pdf()),
  ('sig100k',   true,  null, jsonb_build_object('signature_data', 'data:image/png;base64,' || repeat('A', 100000 - length('data:image/png;base64,'))), '[]', pg_temp.pdf()),
  ('sig100k1',  false, 'signature_data', jsonb_build_object('signature_data', 'data:image/png;base64,' || repeat('A', 100001 - length('data:image/png;base64,'))), '[]', pg_temp.pdf()),
  ('sigjpeg',   false, 'signature_data', jsonb_build_object('signature_data', 'data:image/jpeg;base64,AAAA'), '[]', pg_temp.pdf()),
  ('sigtext',   false, 'signature_data', jsonb_build_object('signature_data', 'I agree'), '[]', pg_temp.pdf()),
  ('sigodd',    false, 'signature_data', jsonb_build_object('signature_data', 'data:image/png;base64,AA<script>'), '[]', pg_temp.pdf()),
  ('pdfmax',    true,  null, '{}'::jsonb, '[]', 'JVBERi0' || repeat('A', 4500000 - 7)),
  ('pdfmax1',   false, 'signature_data', '{}'::jsonb, '[]', 'JVBERi0' || repeat('A', 4500001 - 7)),
  ('pdfnot',    false, 'form', '{}'::jsonb, '[]', 'iVBORw0KGgo='),
  ('pdfodd',    false, 'form', '{}'::jsonb, '[]', 'JVBERi0x LjQK'),
  ('pdfnone',   true,  null, '{}'::jsonb, '[]', null),
  ('payload',   false, 'form', jsonb_build_object('junk', repeat('j', 150001)), '[]', pg_temp.pdf());
do $$ declare c record; b text; begin
  for c in select * from cases order by n loop
    b := pg_temp.kept_all();
    perform pg_temp.send('c:' || c.tag, pg_temp.hdr('198.51.100.' || (c.n % 200 + 20)::text), 'D',
                         pg_temp.form('Cap' || c.n, pg_temp.ph(540 + c.n), pg_temp.mail('cap' || c.n), c.payload), c.symptoms, c.pdf);
    perform pg_temp.put('same:' || c.tag, (pg_temp.kept_all() = b)::text);
  end loop;
end $$;
select pg_temp.check(pg_temp.kept('c:' || c.tag) and pg_temp.hold('c:' || c.tag) is null,
  'C ' || c.tag || ': accepted (a new customer made): ' || left(coalesce(pg_temp.tx('r:c:' || c.tag), ''), 120))
  from cases c where c.ok order by c.n;
select pg_temp.check(pg_temp.refused('c:' || c.tag, 'SURVEY_INPUT(' || c.field || '): ') and pg_temp.tx('same:' || c.tag) = 'true',
  'C ' || c.tag || ': refused (SURVEY_INPUT(' || c.field || ')), nothing kept or counted: ' || left(coalesce(pg_temp.tx('r:c:' || c.tag), ''), 160))
  from cases c where not c.ok order by c.n;
select pg_temp.check((pg_temp.survey('c:name100')).full_name = repeat('N', 49) || ' ' || repeat('M', 50)
    and (select count(*) from public.health_survey_symptoms y where y.survey_id = (pg_temp.a('c:symall')->>'survey_id')::uuid)
        = (select count(*) from public.health_symptom_options where is_active)
    and (select byte_size from public.health_survey_pdfs p where p.survey_id = (pg_temp.a('c:pdfmax')->>'survey_id')::uuid) = 4500000
    and (pg_temp.survey('c:pdfnone')).pdf_url is null,
  'C the accepted values are kept as sent (the longest name, every active symptom, the largest PDF; no PDF: none stored, as before)');

-- ═════ R No raw address; the owner's alone ═════
do $$ declare v boolean := false; begin
  if to_regclass('public.health_survey_tries') is not null then
    execute $q$select pg_temp.tries() > 100
      and (select count(*) from public.health_survey_tries t
            where t.survey_link_id in (select v from fx where k like 'link:%')
              and (to_jsonb(t)::text ~ '203\.0\.113|198\.51\.100|192\.0\.2\.|2001:db8' or t.sender_key !~ '^[0-9a-f]{64}$')) = 0
      and not exists (select 1 from public.health_survey_tries t, unnest(array['203.0.113.10', '203.0.113.40', '192.0.2.44', '2001:db8:44::/64']) a(k)
                       where t.sender_key in (encode(sha256(convert_to(a.k, 'UTF8')), 'hex'), encode(sha256(convert_to('|' || a.k, 'UTF8')), 'hex')))$q$
      into v;
  end if;
  perform pg_temp.put('r1', v::text);
end $$;
select pg_temp.check((select string_agg(column_name || ' ' || data_type, ',' order by ordinal_position)
                        from information_schema.columns where table_schema = 'public' and table_name = 'health_survey_tries')
        = 'id uuid,created_at timestamp with time zone,survey_link_id uuid,sender_key text,outcome text'
    and pg_temp.tx('r1') = 'true',
  'R1 the tries hold no address and no phone: a time, the link, the outcome and a 64-character salted hash (never the unsalted hash of an address)');
create function pg_temp.as_role(p_role text, q text) returns text language plpgsql as $f$
declare v text; begin
  perform set_config('request.jwt.claims', json_build_object('role', p_role)::text, true);
  execute format('set local role %I', p_role);
  begin
    execute q into v;
  exception when others then v := sqlstate;
  end;
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  return v;
end $f$;
select pg_temp.check(pg_temp.as_role('anon', 'select count(*)::text from public.health_survey_tries') = '42501'
    and pg_temp.as_role('authenticated', 'select count(*)::text from public.health_survey_tries') = '42501'
    and pg_temp.as_role('service_role', 'select count(*)::text from public.health_survey_tries') = '42501'
    and pg_temp.as_role('anon', 'select sender_key from public.request_sender()') = '42501'
    and pg_temp.as_role('authenticated', 'select sender_key from public.request_sender()') = '42501'
    and pg_temp.as_role('service_role', 'select sender_key from public.request_sender()') = '42501'
    and (select relrowsecurity from pg_class where oid = to_regclass('public.health_survey_tries'))
    and not exists (select 1 from pg_policy where polrelid = to_regclass('public.health_survey_tries')),
  'R2 the tries table and request_sender are the owner''s alone: the anon key, a login and the service role can neither read the one nor call the other; row level security on, no policy');
select pg_temp.check(has_function_privilege('anon', 'public.submit_health_survey(text,jsonb,jsonb,text)', 'execute')
    and (select string_agg(x::text, ',' order by x::text) from pg_proc p, unnest(p.proacl) x
          where p.oid = 'public.submit_health_survey(text,jsonb,jsonb,text)'::regprocedure)
        = 'anon=X/postgres,authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
  'R3 the form is still callable signed out; its grants are as before');

-- ═════ G 530's versions ═════
\if :{?control}
\else
select pg_temp.check(md5(pg_get_functiondef('public.submit_health_survey(text,jsonb,jsonb,text)'::regprocedure)) = '6441159a66f5ca4424848710c90f2576'
    and md5(pg_get_functiondef('public.request_sender()'::regprocedure)) = '6a399f5c3c62123def01e0f2fc764234'
    and position('-- 530 (security audit' in pg_get_functiondef('public.submit_health_survey(text,jsonb,jsonb,text)'::regprocedure)) > 0
    and md5(pg_get_functiondef('public.affiliate_referral_signup(text,text,text,text,text,text)'::regprocedure)) = '00d528c6f4cc9240b2cf2f82ea2bd487'
    and md5(pg_get_functiondef('public.attach_held_health_survey(uuid,uuid,text)'::regprocedure)) = '55b632c7e9289cb267516a26af97387b'
    and md5(pg_get_functiondef('public.health_survey_sign_into_record(uuid,health_surveys,jsonb,text)'::regprocedure)) = 'ac2bbd3742f3b4364b289ddd29715215'
    and (select pg_get_constraintdef(c.oid) from pg_constraint c
          where c.conrelid = 'public.health_survey_holds'::regclass and c.conname = 'health_survey_holds_reason_check') like '%''existing_customer''::text]%'
    and obj_description('public.referral_sender_salt'::regclass, 'pg_class') like '%530''s request_sender%'
    and (select count(*) from public.referral_sender_salt) = 1,
  'G1 530''s AFTER md5 and marker, the helper''s md5, 529''s sign-up and the staff paths unchanged, the new reason allowed, the salt kept (its comment names both forms)');

-- ═════ U Undo, the older undos, and 530 again ═════
\set ON_ERROR_STOP off
savepoint u524;
\ir ../undo-524.sql
rollback to savepoint u524;
release savepoint u524;
select pg_temp.put('u524', :'LAST_ERROR_MESSAGE');
savepoint u529;
\ir ../../affiliate-signup/undo-529.sql
rollback to savepoint u529;
release savepoint u529;
select pg_temp.put('u529', :'LAST_ERROR_MESSAGE');
\set ON_ERROR_STOP on
select pg_temp.check(pg_temp.tx('u524') like 'UNDO 524: public.submit_health_survey(text,jsonb,jsonb,text) is not 524''s version%'
    and pg_temp.tx('u529') like 'UNDO 529: 530 is in%'
    and md5(pg_get_functiondef('public.submit_health_survey(text,jsonb,jsonb,text)'::regprocedure)) = '6441159a66f5ca4424848710c90f2576'
    and to_regclass('public.referral_sender_salt') is not null,
  'U1 while 530 is in, undo-524 and undo-529 refuse cleanly and change nothing: ' || pg_temp.tx('u524') || ' / ' || pg_temp.tx('u529'));
-- With no hold of the new reason, the reasons go back to the nine (tried in a savepoint).
savepoint u530a;
delete from public.health_surveys s using public.health_survey_holds h where h.survey_id = s.id and h.reason = 'existing_customer';
\ir ../undo-530.sql
-- (Kept in a psql variable: the rollback to the savepoint takes back anything written in it.)
select (select pg_get_constraintdef(c.oid) from pg_constraint c
         where c.conrelid = 'public.health_survey_holds'::regclass and c.conname = 'health_survey_holds_reason_check') as u530a_check \gset
rollback to savepoint u530a;
release savepoint u530a;
select pg_temp.put('u530a', :'u530a_check');
\ir ../undo-530.sql
select pg_temp.check(md5(pg_get_functiondef('public.submit_health_survey(text,jsonb,jsonb,text)'::regprocedure)) = 'a65183cdcb48f2dd883a47c1c7aad7f3'
    and to_regprocedure('public.request_sender()') is null and to_regclass('public.health_survey_tries') is null
    and obj_description('public.referral_sender_salt'::regclass, 'pg_class') like '529: the secret salt of referral_signup_events.sender_key%'
    and (select string_agg(x::text, ',' order by x::text) from pg_proc p, unnest(p.proacl) x
          where p.oid = 'public.submit_health_survey(text,jsonb,jsonb,text)'::regprocedure)
        = 'anon=X/postgres,authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres'
    and pg_temp.tx('u530a') not like '%existing_customer%'
    and (select pg_get_constraintdef(c.oid) from pg_constraint c
          where c.conrelid = 'public.health_survey_holds'::regclass and c.conname = 'health_survey_holds_reason_check') like '%''existing_customer''::text]%',
  'U2 undo-530 puts the form back (its BEFORE md5) with its grants, drops the helper and the tries, puts the salt''s comment back; the reasons go back to the nine when no hold has the new one, and stay widened when one does');
select pg_temp.send('u3', pg_temp.hdr('192.0.2.90'), 'A', pg_temp.form('Una', pg_temp.ph(570), pg_temp.mail('una'), '{"occupation": "Una job"}'));
select pg_temp.send('u3b', pg_temp.hdr('192.0.2.90'), 'A', pg_temp.form('Una', pg_temp.ph(570), pg_temp.mail('una2')));
select pg_temp.check(pg_temp.kept('u3') and (pg_temp.survey('u3b')).signed_date = '2020-01-01' and (pg_temp.survey('u3b')).ip_address = '10.0.0.1',
  'U3 after the undo the form is as before 530 (the payload''s date and address are kept again)');
\ir ../../../supabase/530_the_health_form_has_limits_and_holds_existing_customers.sql
select pg_temp.send('u4', pg_temp.hdr('192.0.2.91'), 'A', pg_temp.form('Uri', pg_temp.ph(571), pg_temp.mail('uri')));
select pg_temp.check(md5(pg_get_functiondef('public.submit_health_survey(text,jsonb,jsonb,text)'::regprocedure)) = '6441159a66f5ca4424848710c90f2576'
    and md5(pg_get_functiondef('public.request_sender()'::regprocedure)) = '6a399f5c3c62123def01e0f2fc764234'
    and pg_temp.kept('u4') and (pg_temp.survey('u4')).signed_date = public.sg_today() and pg_temp.tries(pg_temp.key('192.0.2.91')) = 1,
  'U4 530 again after the undo (over the widened reasons): its versions, and the form counted again');

-- ═════ M 530 twice ═════
\if :{?skip_install}
\else
select pg_temp.check(not exists (select 1 from m530 m
                                   full join (select p.oid::regprocedure::text as fn, md5(pg_get_functiondef(p.oid)) as md5, p.proacl::text as acl
                                                from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p')) n
                                     on n.fn = m.fn
                                  where m.fn is null or n.fn is null or m.md5 <> n.md5 or m.acl is distinct from n.acl)
    and (select cols from m530t) = (select string_agg(column_name || ' ' || data_type || ' ' || is_nullable, ',' order by ordinal_position)
                                      from information_schema.columns where table_schema = 'public' and table_name = 'health_survey_tries')
    and (select idx from m530t) = (select string_agg(pg_get_indexdef(indexrelid), ',' order by pg_get_indexdef(indexrelid))
                                     from pg_index where indrelid = 'public.health_survey_tries'::regclass)
    and (select reasons from m530t) = (select pg_get_constraintdef(c.oid) from pg_constraint c
                                         where c.conrelid = 'public.health_survey_holds'::regclass and c.conname = 'health_survey_holds_reason_check')
    and (select salt_comment from m530t) = obj_description('public.referral_sender_salt'::regclass, 'pg_class'),
  'M1 running 530 a second time (and the undo and 530 again) left every function, its rights, the tries table, the reasons and the salt''s comment as 530 made them');
\endif
\endif

-- With -v control=1 (a copy without 530) exactly these fail (run 19 Nov 2026 on a copy of
-- production after 529: 27 pass, 67 fail; G, U and M are skipped), the fault 530 closes: H1-H5,
-- H8, H9 (the form attaches itself to the customer found and fills their details, or signs the
-- consultant's record), L1-L5, L7, L8 (no limit per sender or per link, no sender), D1-D5 (no
-- day's limit per phone), T1 (the payload's date), E1 (the typed event wins), I1, I2 (the
-- payload's address and device), each of the 39 refused C cases (taken as sent, or refused with
-- a raw database error) and R1, R2 (no tries table, no helper). These follow from them: A1-A3
-- (nothing waits for staff to attach). These pass either way: P0, H6, H7 (as before 530), L6, L9
-- and T2 (they hold on a form with no limit too), the accepted C cases and R3.
do $$ declare v_failed int; begin
  select count(*) into v_failed from failed;
  if v_failed > 0 then raise exception '% check(s) failed: %', v_failed, (select string_agg(msg, '; ' order by n) from failed); end if;
  raise notice 'All 530 checks passed.';
end $$;
rollback;
