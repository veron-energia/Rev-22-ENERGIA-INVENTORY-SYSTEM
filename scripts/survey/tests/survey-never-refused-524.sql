-- The QR health survey never refuses a form for whom it names: it is kept and waits for
-- staff (524).
--
-- The user, 18 Nov 2026 ("Accept and hold for staff"; security audit of 17 Nov 2026, L9):
-- the form used to refuse, so anyone with a survey link could learn from a phone and a name
-- that (1) a form had been sent under them before, (2) that customer has a health survey,
-- (3) an older survey with no customer has them, (4) an old customer of that name has a phone
-- that cannot be read but could be this one. Now each is accepted with the reply any
-- form gets, kept with no customer, and waits in To match for staff. Every form below is
-- sent signed out (the role anon), as the public page sends it.
--
--   1 Sent again: a form under a phone and name that sent one before, which waits (held for
--     the customer with the phone) or was made into a customer, waits (repeat_form) with the
--     customers of those earlier forms; also with the name's words in another order. The same
--     name on a phone nobody has makes a customer; the replies have the same shape.
--   2 A customer with a survey: by the phone and name, the form waits (customer_has_survey)
--     with that customer, who keeps their one survey and every detail as it was; also when the
--     survey is an old one with no customer under their phone and name. A customer with no
--     survey is attached, their empty details filled, as before; the replies have the same
--     shape.
--   3 An old survey with no customer has the phone and name, and no customer does: the form
--     waits (legacy_survey_same_details) with no one, and no customer is made. A new person
--     makes a customer, as before; the replies have the same shape.
--   4 An old customer with this name has a phone that cannot be read as one number but could be
--     this one (as July's import left some; require_resolved_customer_identity, which refused):
--     the form waits (unreadable_phone_same_name) with that old record and the customer who has
--     this phone and name, ahead of attaching to the latter; no customer is made or changed.
--     Staff attach it to the old record.
--   L Staff see each in To match with its reason and the customers it may belong to; the
--     submission's Audit Log row says it was held and why.
--   S Staff deal with them as with any form: attach (refused for a customer who has a survey,
--     not for one who has none), make a new customer from one, and an Owner or Manager (not
--     Staff) closes one.
--   K No customer who was there before changed, and none got a second survey.
--   G The form stays callable signed out; its grants are as before.
--   M 524 installs itself here when it is not in (a second run changes nothing); the function
--     and the reason check are the tested ones.
--
--   sh scripts/invoices/local-sql.sh -f scripts/survey/tests/survey-never-refused-524.sql
--   (-v skip_install=1: run on the database as it is, 524 neither installed nor run again; on a
--   database without 524 the checks then fail, as the control.)
-- Every check runs, then the file fails if any did. Disposable local database only;
-- everything is rolled back. Made-up records only (L524Sample, +61 491 570 24x, @example.invalid;
-- case 4 needs a Singapore-or-Malaysia national number of 8 digits: it is made up at run time,
-- a random 8xxxxxxx that no customer of the database has, so no such number is written here).
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
\if :{?skip_install}
\else
select position('524:' in pg_get_functiondef('public.submit_health_survey(text,jsonb,jsonb,text)'::regprocedure)) > 0 as m524_in \gset
\if :m524_in
\else
\ir ../../../supabase/524_a_survey_form_is_never_refused_for_who_it_names.sql
\endif
create temp table m524 as
  select 'fn' as k, md5(pg_get_functiondef('public.submit_health_survey(text,jsonb,jsonb,text)'::regprocedure)) as v
  union all
  select 'acl', (select coalesce(string_agg(x::text, ',' order by x::text), '') from pg_proc p, unnest(p.proacl) x
                  where p.oid = 'public.submit_health_survey(text,jsonb,jsonb,text)'::regprocedure)
  union all
  select 'check', pg_get_constraintdef(c.oid) from pg_constraint c
   where c.conrelid = 'public.health_survey_holds'::regclass and c.conname = 'health_survey_holds_reason_check';
-- A second run changes nothing.
\ir ../../../supabase/524_a_survey_form_is_never_refused_for_who_it_names.sql
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
create function pg_temp.fx(key text) returns uuid language sql as $$ select v from fx where k = key $$;
create temp table tx(k text primary key, v text);
create function pg_temp.tx(key text) returns text language sql as $$ select v from tx where k = key $$;
create function pg_temp.mail(local text) returns text language sql as
$$ select 'l524-' || local || '-' || pg_temp.tx('sfx') || '@example.invalid' $$;
-- A QR form as the public page sends it, signed out (the role anon): the reply (or the error)
-- under 'sub:<key>', the survey under 'hs:<key>'.
create function pg_temp.submit(key text, first text, last text, phone text, email text) returns void language plpgsql as
$$declare r jsonb; v_token text := pg_temp.tx('token'); v_src uuid := pg_temp.fx('src');
begin
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  execute 'set local role anon';
  r := public.submit_health_survey(v_token,
         jsonb_build_object('first_name', first, 'last_name', last, 'phone', phone, 'email', email,
                            'signature_data', 'data:image/png;base64,AAAA', 'source_option_id', v_src,
                            'sex', 'female', 'date_of_birth', '1981-06-07', 'occupation', 'L524 Tester'),
         null, null);
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  insert into tx values ('sub:' || key, r::text) on conflict (k) do update set v = excluded.v;
  insert into fx values ('hs:' || key, (r->>'survey_id')::uuid) on conflict (k) do update set v = excluded.v;
exception when others then
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  insert into tx values ('sub:' || key, 'ERROR: ' || sqlerrm) on conflict (k) do update set v = excluded.v;
end$$;
-- 530 (security audit of 17 Nov 2026, M4; the user, 19 Nov 2026): where 530 is in, a form found by
-- its phone and name for a customer with no survey waits for staff too (existing_customer), nothing
-- filled (case 2's Gia; staff then attach it); and at most 3 forms a Singapore day are kept under one
-- phone, so where a phone gets more here its earlier forms are moved to the day before
-- (earlier_day). scripts/survey/tests/health-form-limits-530.sql checks 530 whole.
create function pg_temp.m530() returns boolean language sql stable as
$$ select position('-- 530 (security audit' in pg_get_functiondef('public.submit_health_survey(text,jsonb,jsonb,text)'::regprocedure)) > 0 $$;
create function pg_temp.earlier_day(p text) returns void language sql as
$$ update public.health_surveys set submitted_at = submitted_at - interval '1 day'
    where pg_temp.m530() and public.normalize_customer_phone(phone) = p $$;
create function pg_temp.reply(key text) returns jsonb language sql as
$$ select case when pg_temp.tx('sub:' || key) like 'ERROR:%' then null else pg_temp.tx('sub:' || key)::jsonb end $$;
-- The reply any form gets: success, a survey number of today's form, the survey's id; nothing else.
create function pg_temp.plain_reply(key text) returns boolean language sql as
$$ select coalesce((pg_temp.reply(key) - 'survey_no' - 'survey_id') = '{"success": true}'::jsonb
                   and pg_temp.reply(key)->>'survey_no' ~ ('^HS-' || to_char(now() at time zone 'Asia/Singapore', 'YYYYMMDD') || '-[0-9a-f]{6}$')
                   and (pg_temp.reply(key)->>'survey_id')::uuid is not null, false) $$;
create function pg_temp.survey(key text) returns public.health_surveys language sql as
$$ select s from public.health_surveys s where s.id = pg_temp.fx('hs:' || key) $$;
create function pg_temp.hold(key text) returns public.health_survey_holds language sql as
$$ select h from public.health_survey_holds h where h.survey_id = pg_temp.fx('hs:' || key) $$;
create function pg_temp.ids(variadic keys text[]) returns uuid[] language sql as
$$ select coalesce(array_agg(pg_temp.fx(k) order by pg_temp.fx(k)), '{}'::uuid[]) from unnest(keys) k $$;
-- Held as 524 holds it: no customer, waiting with this reason for exactly these customers, the
-- name, phone and email as typed.
create function pg_temp.held(key text, p_reason text, p_for uuid[], p_name text, p_phone text, p_email text) returns boolean language sql as
$$ select coalesce((pg_temp.survey(key)).customer_id is null
                   and (pg_temp.hold(key)).reason = p_reason and (pg_temp.hold(key)).resolved_at is null
                   and (select coalesce(array_agg(x order by x), '{}'::uuid[]) from unnest((pg_temp.hold(key)).candidate_customer_ids) x) = p_for
                   and (pg_temp.hold(key)).typed_full_name = p_name and (pg_temp.hold(key)).typed_phone = p_phone
                   and (pg_temp.hold(key)).typed_email = p_email
                   and (pg_temp.survey(key)).full_name = p_name and (pg_temp.survey(key)).email = p_email, false) $$;
create function pg_temp.on_phone(p text) returns int language sql as
$$ select count(*)::int from public.customers c where c.deleted_at is null and public.normalize_customer_phone(c.phone) = p $$;
create function pg_temp.surveys_of(cust text) returns int language sql as
$$ select count(*)::int from public.health_surveys where customer_id = pg_temp.fx(cust) $$;
create function pg_temp.submitted(key text) returns jsonb language sql as
$$ select new_data from public.audit_logs where action = 'health_survey_submitted' and record_id = pg_temp.fx('hs:' || key) $$;
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
  return coalesce(v, 'ok');
exception when others then
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  return 'ERROR: ' || sqlerrm;
end $f$;
-- The form's entry in To match, as a login sees it.
create function pg_temp.listed(p_who text, key text) returns jsonb language sql as
$$ select e from jsonb_array_elements(nullif(pg_temp.as_login(p_who, 'select public.health_survey_holds_list()::text'), 'ok')::jsonb) e
    where (e->>'survey_id')::uuid = pg_temp.fx('hs:' || key) $$;
-- A statement's error message, or 'ok'.
create function pg_temp.err524(q text) returns text language plpgsql as
$$begin execute q; return 'ok'; exception when others then return sqlerrm; end$$;
-- The details a form fills on a customer, and the whole record, as they are now.
create function pg_temp.record(cust text) returns text language sql as
$$ select to_jsonb(c)::text from public.customers c where c.id = pg_temp.fx(cust) $$;

select pg_temp.check(position('524:' in pg_get_functiondef('public.submit_health_survey(text,jsonb,jsonb,text)'::regprocedure)) > 0,
  'P0 524 is in (submit_health_survey has its marker)');
-- Case 4's 8-digit number, made up now: a mobile-looking 8xxxxxxx that no customer here has, and
-- that the phone rules read as +65 when it has the code, and as maybe-this-one when it has not.
insert into tx select 'sg8', n
  from (select '8' || lpad(floor(random() * 10000000)::int::text, 7, '0') n from generate_series(1, 200)) x
 where not exists (select 1 from public.customers c where regexp_replace(c.phone, '\D', '', 'g') like '%' || x.n)
   and public.normalize_customer_phone('+65' || x.n) is not null
   and public.normalize_customer_phone(x.n) is null
   and (public.inspect_customer_phone(x.n)->'candidates') ? ('+65' || x.n)
 limit 1;
select pg_temp.check(not exists (select 1 from public.customers where public.normalize_customer_phone(phone) like '+6149157024_')
    and not exists (select 1 from public.health_surveys where public.normalize_customer_phone(phone) like '+6149157024_')
    and not exists (select 1 from public.customers
                     where public.normalize_customer_phone(phone) = '+65' || pg_temp.tx('sg8') or regexp_replace(phone, '\D', '', 'g') like '%' || pg_temp.tx('sg8')),
  'P0 no customer or survey uses the test phones +61 491 570 24x or case 4''s made-up 8-digit number (the checks below assume so)');

-- ═════ Fixtures ═════
do $$
declare sfx text := lower(substr(md5(random()::text || clock_timestamp()::text), 1, 6)); k text; u uuid; c uuid;
begin
  insert into tx values ('sfx', sfx), ('token', 'l524-' || sfx);
  foreach k in array array['o', 'm', 's'] loop
    u := gen_random_uuid(); insert into fx values (k, u);
    insert into auth.users(id, email, email_confirmed_at) values (u, 'l524-' || k || '-' || sfx || '@example.invalid', now());
  end loop;
  insert into public.profiles(id, full_name, email, role, is_active) values
    (pg_temp.fx('o'), 'L524 Owner',   'l524-o-' || sfx || '@example.invalid', 'owner', true),
    (pg_temp.fx('m'), 'L524 Manager', 'l524-m-' || sfx || '@example.invalid', 'manager', true),
    (pg_temp.fx('s'), 'L524 Staff',   'l524-s-' || sfx || '@example.invalid', 'staff', true);
  insert into public.stores(name, code) values ('L524 Sample Store', 'L524' || sfx) returning id into c; insert into fx values ('store', c);
  insert into public.customer_source_options(label) values ('L524 Walk-in ' || sfx) returning id into c; insert into fx values ('src', c);
  insert into public.survey_links(token, store_id) values ('l524-' || sfx, pg_temp.fx('store'));

  -- 1: Ola has the phone the person (Rhea) types, under her own name.
  insert into public.customers(full_name, phone, email) values ('Ola L524Sample', '+61491570240', pg_temp.mail('ola'))
    returning id into c; insert into fx values ('cOla', c);
  -- 2: Bea has a signed survey, and empty details. Dee has no survey, but an old survey with no
  -- customer has her phone and name. Gia has no survey and empty details.
  insert into public.customers(full_name, phone, email) values ('Bea L524Sample', '+61491570242', pg_temp.mail('bea'))
    returning id into c; insert into fx values ('cBea', c);
  insert into public.health_surveys(survey_no, full_name, customer_id, phone, source, store_id, signature_data)
  values ('HS-L524B-' || sfx, 'Bea L524Sample', c, '+61491570242', 'public_form', pg_temp.fx('store'), 'data:image/png;base64,AAAA')
  returning id into u; insert into fx values ('hsBea', u);
  insert into public.customers(full_name, phone, email) values ('Dee L524Sample', '+61491570243', pg_temp.mail('dee'))
    returning id into c; insert into fx values ('cDee', c);
  insert into public.health_surveys(survey_no, full_name, phone, source, store_id)
  values ('HS-L524D-' || sfx, 'Dee L524Sample', '+61491570243', 'public_form', pg_temp.fx('store'));
  insert into public.customers(full_name, phone, email) values ('Gia L524Sample', '+61491570245', pg_temp.mail('gia'))
    returning id into c; insert into fx values ('cGia', c);
  -- 3: an old survey with no customer has Eli's phone and name; no customer has either.
  insert into public.health_surveys(survey_no, full_name, phone, source, store_id)
  values ('HS-L524E-' || sfx, 'Eli L524Sample', '+61491570246', 'public_form', pg_temp.fx('store'));
end $$;
-- 4: an old record of Uma's, its phone as July's import left it (8 digits: Singapore or Malaysia?;
-- the phone rule is set aside to make it, as the import did), and Uma with the phone readable.
alter table public.customers disable trigger zz_normalize_current_customer_phone;
do $$ declare c uuid; begin
  insert into public.customers(full_name, phone) values ('Uma L524Sample', pg_temp.tx('sg8')) returning id into c; insert into fx values ('cUmaOld', c);
end $$;
alter table public.customers enable trigger zz_normalize_current_customer_phone;
do $$ declare c uuid; begin
  insert into public.customers(full_name, phone, email) values ('Uma L524Sample', '+65' || pg_temp.tx('sg8'), pg_temp.mail('uma')) returning id into c; insert into fx values ('cUma', c);
end $$;
select pg_temp.check(pg_temp.tx('sg8') ~ '^8[0-9]{7}$'
    and public.normalize_customer_phone(pg_temp.tx('sg8')) is null
    and (public.inspect_customer_phone(pg_temp.tx('sg8'))->'candidates') ? ('+65' || pg_temp.tx('sg8'))
    and pg_temp.err524(format('select public.require_resolved_customer_identity(%L, ''Uma L524Sample'')', '+65' || pg_temp.tx('sg8'))) = 'AMBIGUOUS_CUSTOMER_MATCH',
  'P0 (setup) the old record''s phone cannot be read as one number, but could be the same number with +65, and the identity check refuses that name on it');
insert into tx select 'rec:' || k, pg_temp.record(k) from unnest(array['cOla', 'cBea', 'cDee', 'cGia', 'cUmaOld', 'cUma']) k;

-- ═════ 1 Sent again ═════
-- Rhea's first form: her phone is Ola's, under another name: it waits for Ola (433, as before).
select pg_temp.submit('r1', 'Rhea', 'L524Sample', '+61 491 570 240', pg_temp.mail('rhea'));
select pg_temp.check(pg_temp.held('r1', 'phone_in_use', pg_temp.ids('cOla'), 'Rhea L524Sample', '+61491570240', pg_temp.mail('rhea')),
  '1 (setup) Rhea''s first form waits for Ola, whose phone it is (phone_in_use), as before: ' || pg_temp.tx('sub:r1'));
-- Sent again while it waits: no longer refused.
select pg_temp.submit('r2', 'Rhea', 'L524Sample', '+61491570240', pg_temp.mail('rhea2'));
select pg_temp.submit('u1', 'Rhea', 'L524Sample', '+61491570241', pg_temp.mail('rhea3'));
select pg_temp.check(pg_temp.plain_reply('r2') and pg_temp.plain_reply('u1')
    and pg_temp.held('r2', 'repeat_form', pg_temp.ids('cOla'), 'Rhea L524Sample', '+61491570240', pg_temp.mail('rhea2'))
    and pg_temp.hold('u1') is null and (pg_temp.survey('u1')).customer_id is not null and pg_temp.on_phone('+61491570241') = 1,
  '1 sent again while the first waits: the reply any form gets, kept with no customer, waiting (repeat_form) for Ola, as the first; '
  || 'the same name on a phone nobody has: a new customer, the same reply: ' || pg_temp.tx('sub:r2') || ' / ' || pg_temp.tx('sub:u1'));
-- Staff make Rhea a customer from her first form; then she sends it again, also with the
-- name's words in another order.
insert into tx values ('make_r1', pg_temp.as_login('s', format('select public.create_customer_from_held_survey(%L, %L)::text',
                                                              pg_temp.fx('hs:r1'), 'Rhea herself, Ola''s lodger')));
insert into fx values ('cRhea', (pg_temp.survey('r1')).customer_id);
-- 530: r1 and r2 were kept today under this phone; r3 and r4 make four, so those two go to the day before.
select pg_temp.earlier_day('+61491570240');
select pg_temp.submit('r3', 'Rhea', 'L524Sample', '+61491570240', pg_temp.mail('rhea'));
select pg_temp.submit('r4', 'L524Sample', 'Rhea', '+61491570240', pg_temp.mail('rhea'));
select pg_temp.check(pg_temp.tx('make_r1') !~ '^ERROR' and pg_temp.fx('cRhea') is not null
    and pg_temp.plain_reply('r3') and pg_temp.plain_reply('r4')
    and pg_temp.held('r3', 'repeat_form', pg_temp.ids('cOla', 'cRhea'), 'Rhea L524Sample', '+61491570240', pg_temp.mail('rhea'))
    and pg_temp.held('r4', 'repeat_form', pg_temp.ids('cOla', 'cRhea'), 'L524Sample Rhea', '+61491570240', pg_temp.mail('rhea'))
    and pg_temp.surveys_of('cRhea') = 1,
  '1 once staff made her a customer from it: sent again (also the words in another order) it waits (repeat_form) for her and for Ola '
  || '(for whom the second still waits); she keeps her one survey: ' || pg_temp.tx('make_r1') || ' / ' || pg_temp.tx('sub:r3'));

-- ═════ 2 A customer with a survey ═════
select pg_temp.submit('b1', 'Bea', 'L524Sample', '+61491570242', pg_temp.mail('bea-new'));
select pg_temp.submit('d1', 'Dee', 'L524Sample', '+61491570243', pg_temp.mail('dee'));
select pg_temp.submit('g1', 'Gia', 'L524Sample', '+61491570245', pg_temp.mail('gia'));
select pg_temp.check(pg_temp.plain_reply('b1') and pg_temp.plain_reply('g1')
    and pg_temp.held('b1', 'customer_has_survey', pg_temp.ids('cBea'), 'Bea L524Sample', '+61491570242', pg_temp.mail('bea-new'))
    and (pg_temp.survey('b1')).date_of_birth = '1981-06-07' and (pg_temp.survey('b1')).occupation = 'L524 Tester'
    and pg_temp.surveys_of('cBea') = 1 and pg_temp.record('cBea') = pg_temp.tx('rec:cBea'),
  '2 Bea (a signed survey) by her phone and name: the reply any form gets, kept with no customer, waiting (customer_has_survey) '
  || 'for her with what was typed; she keeps her one survey and her record is unchanged (no empty detail filled): ' || pg_temp.tx('sub:b1'));
select pg_temp.check(pg_temp.plain_reply('d1')
    and pg_temp.held('d1', 'customer_has_survey', pg_temp.ids('cDee'), 'Dee L524Sample', '+61491570243', pg_temp.mail('dee'))
    and pg_temp.surveys_of('cDee') = 0 and pg_temp.record('cDee') = pg_temp.tx('rec:cDee'),
  '2 Dee, whose phone and name an old survey with no customer has: waits (customer_has_survey) for her; her record unchanged: ' || pg_temp.tx('sub:d1'));
-- 530: Gia's form waits for staff (existing_customer), nothing filled; staff attach it, which fills them.
select pg_temp.check(not pg_temp.m530()
    or (pg_temp.held('g1', 'existing_customer', pg_temp.ids('cGia'), 'Gia L524Sample', '+61491570245', pg_temp.mail('gia'))
        and pg_temp.record('cGia') = pg_temp.tx('rec:cGia')),
  '2 (530) Gia (no survey) by her phone and name: waits for staff with her (existing_customer), her record unchanged: ' || pg_temp.tx('sub:g1'));
insert into tx select 'att_g1', pg_temp.as_login('s', format('select public.attach_held_health_survey(%L, %L, %L)::text',
                                                             pg_temp.fx('hs:g1'), pg_temp.fx('cGia'), 'Her phone and name'))
 where pg_temp.m530();
select pg_temp.check(pg_temp.hold('g1') is null is distinct from pg_temp.m530() and (pg_temp.survey('g1')).customer_id = pg_temp.fx('cGia')
    and (select date_of_birth = '1981-06-07' and occupation = 'L524 Tester' and source_option_id = pg_temp.fx('src') and email = pg_temp.mail('gia')
           from public.customers where id = pg_temp.fx('cGia')),
  '2 Gia (no survey) by her phone and name: hers at once, her empty details filled, as before (530: once staff attach it); the same reply: ' || pg_temp.tx('sub:g1'));
select pg_temp.check((pg_temp.submitted('b1')->>'held_for_staff')::boolean and pg_temp.submitted('b1')->>'hold_reason' = 'customer_has_survey'
    and pg_temp.submitted('b1')->>'customer_id' is null and not (pg_temp.submitted('b1')->>'customer_matched')::boolean
    and pg_temp.submitted('r2')->>'hold_reason' = 'repeat_form',
  'L the submission''s Audit Log row says it was held for staff and why, with no customer: ' || coalesce((pg_temp.submitted('b1'))::text, 'no row'));

-- ═════ 3 An old survey with no customer ═════
select pg_temp.submit('e1', 'Eli', 'L524Sample', '+61491570246', pg_temp.mail('eli'));
select pg_temp.submit('n1', 'Fin', 'L524Sample', '+61491570247', pg_temp.mail('fin'));
select pg_temp.check(pg_temp.plain_reply('e1') and pg_temp.plain_reply('n1')
    and pg_temp.held('e1', 'legacy_survey_same_details', '{}'::uuid[], 'Eli L524Sample', '+61491570246', pg_temp.mail('eli'))
    and pg_temp.on_phone('+61491570246') = 0
    and pg_temp.hold('n1') is null and pg_temp.on_phone('+61491570247') = 1
    and (select full_name from public.customers where id = (pg_temp.survey('n1')).customer_id) = 'Fin L524Sample',
  '3 an old survey with no customer has Eli''s phone and name: the reply any form gets, waiting (legacy_survey_same_details) for no one, '
  || 'no customer made; a new person (Fin): a customer, as before, the same reply: ' || pg_temp.tx('sub:e1') || ' / ' || pg_temp.tx('sub:n1'));
-- ═════ 4 An old record whose phone cannot be read ═════
select pg_temp.submit('x1', 'Uma', 'L524Sample', '+65 ' || substr(pg_temp.tx('sg8'), 1, 4) || ' ' || substr(pg_temp.tx('sg8'), 5), pg_temp.mail('uma-form'));
select pg_temp.submit('n2', 'Uma', 'L524Sample', '+61491570248', pg_temp.mail('uma-new'));
select pg_temp.check(pg_temp.plain_reply('x1') and pg_temp.plain_reply('n2')
    and pg_temp.held('x1', 'unreadable_phone_same_name', pg_temp.ids('cUmaOld', 'cUma'), 'Uma L524Sample', '+65' || pg_temp.tx('sg8'), pg_temp.mail('uma-form'))
    and pg_temp.on_phone('+65' || pg_temp.tx('sg8')) = 1 and pg_temp.surveys_of('cUma') = 0 and pg_temp.surveys_of('cUmaOld') = 0
    and pg_temp.record('cUma') = pg_temp.tx('rec:cUma') and pg_temp.record('cUmaOld') = pg_temp.tx('rec:cUmaOld')
    and pg_temp.submitted('x1')->>'hold_reason' = 'unreadable_phone_same_name'
    and pg_temp.hold('n2') is null and (pg_temp.survey('n2')).customer_id is not null,
  '4 beside an old record of that name whose phone cannot be read but could be this one: the reply any form gets, kept with no customer, '
  || 'waiting (unreadable_phone_same_name) for the old record and for Uma (whose phone and name it is: not attached to her), no customer '
  || 'made or changed; the same name on a phone nobody has: a new customer, the same reply (before 524: refused): '
  || pg_temp.tx('sub:x1') || ' / ' || pg_temp.tx('sub:n2'));
select pg_temp.check((select bool_and(pg_temp.reply(k) ?& array['success', 'survey_no', 'survey_id'] and (select count(*) from jsonb_object_keys(pg_temp.reply(k))) = 3)
                        from unnest(array['r2', 'r3', 'r4', 'u1', 'b1', 'd1', 'g1', 'e1', 'n1', 'x1', 'n2']) k),
  '1-4 every reply, known person or not, has exactly success, survey_no and survey_id');

-- ═════ K What the forms changed, before staff deal with them ═════
select pg_temp.check((select bool_and(pg_temp.record(k) = pg_temp.tx('rec:' || k)) from unnest(array['cOla', 'cBea', 'cDee', 'cUmaOld', 'cUma']) k)
    and pg_temp.surveys_of('cOla') = 0 and pg_temp.surveys_of('cBea') = 1 and pg_temp.surveys_of('cDee') = 0,
  'K no customer a held form waits for changed (Ola, Bea, Dee, both Umas: every field as before), and none got a survey from a held form');

-- ═════ L To match ═════
select pg_temp.check(pg_temp.listed('s', 'r2')->>'reason' = 'repeat_form'
    and pg_temp.listed('s', 'b1')->>'reason' = 'customer_has_survey'
    and pg_temp.listed('s', 'e1')->>'reason' = 'legacy_survey_same_details'
    and pg_temp.listed('s', 'x1')->>'reason' = 'unreadable_phone_same_name'
    and (select count(*) from jsonb_array_elements(pg_temp.listed('s', 'x1')->'candidates') c
          where (c->>'customer_id')::uuid in (pg_temp.fx('cUmaOld'), pg_temp.fx('cUma'))) = 2
    and (select c->>'survey_no' from jsonb_array_elements(pg_temp.listed('s', 'b1')->'candidates') c
          where (c->>'customer_id')::uuid = pg_temp.fx('cBea')) = 'HS-L524B-' || pg_temp.tx('sfx')
    and (select bool_or((c->>'customer_id')::uuid = pg_temp.fx('cOla')) from jsonb_array_elements(pg_temp.listed('s', 'r2')->'candidates') c)
    and jsonb_array_length(pg_temp.listed('s', 'e1')->'candidates') = 0
    and pg_temp.listed('s', 'r1') is null,
  'L Staff see the four in To match with their reasons and whom each may be (Bea with her survey; both Uma records); Eli''s with no one; the form made into a customer is gone');

-- ═════ S Staff deal with them ═════
insert into tx values ('att_b1', pg_temp.as_login('s', format('select public.attach_held_health_survey(%L, %L, %L)::text',
                                                             pg_temp.fx('hs:b1'), pg_temp.fx('cBea'), 'Checked her IC')));
insert into tx values ('att_r2', pg_temp.as_login('s', format('select public.attach_held_health_survey(%L, %L, %L)::text',
                                                             pg_temp.fx('hs:r2'), pg_temp.fx('cOla'), 'She is Ola after all')));
select pg_temp.check(pg_temp.tx('att_b1') like '%This customer already has a health survey (HS-L524B-%). A customer can have only one.'
    and (pg_temp.survey('b1')).customer_id is null and (pg_temp.hold('b1')).resolved_at is null
    and pg_temp.tx('att_r2') !~ '^ERROR' and (pg_temp.survey('r2')).customer_id = pg_temp.fx('cOla')
    and (pg_temp.hold('r2')).resolution = 'attached' and (pg_temp.hold('r2')).resolved_customer_id = pg_temp.fx('cOla'),
  'S attach: refused for Bea, who has a survey (the form still waits); a form sent again attaches to Ola, who has none: '
  || pg_temp.tx('att_b1') || ' / ' || pg_temp.tx('att_r2'));
insert into tx values ('att_x1', pg_temp.as_login('s', format('select public.attach_held_health_survey(%L, %L, %L)::text',
                                                             pg_temp.fx('hs:x1'), pg_temp.fx('cUmaOld'), 'Her old record; phone confirmed')));
select pg_temp.check(pg_temp.tx('att_x1') !~ '^ERROR' and (pg_temp.survey('x1')).customer_id = pg_temp.fx('cUmaOld')
    and (pg_temp.hold('x1')).resolution = 'attached',
  'S attach the form beside the old record to that record: hers: ' || pg_temp.tx('att_x1'));
insert into tx values ('make_e1', pg_temp.as_login('s', format('select public.create_customer_from_held_survey(%L, %L)::text',
                                                              pg_temp.fx('hs:e1'), 'New to us; the old survey is someone else''s')));
select pg_temp.check(pg_temp.tx('make_e1') !~ '^ERROR'
    and (select c.full_name = 'Eli L524Sample' and c.first_name = 'Eli' and c.last_name = 'L524Sample' and c.phone = '+61491570246'
               and c.email = pg_temp.mail('eli')
           from public.customers c where c.id = (pg_temp.survey('e1')).customer_id)
    and (pg_temp.hold('e1')).resolution = 'created',
  'S make a new customer from Eli''s form: made with what he typed, the form his: ' || pg_temp.tx('make_e1'));
insert into tx values ('close_d1_s', pg_temp.as_login('s', format('select public.close_held_health_survey(%L, %L)::text', pg_temp.fx('hs:d1'), 'Same person')));
insert into tx values ('close_d1_m', pg_temp.as_login('m', format('select public.close_held_health_survey(%L, %L)::text', pg_temp.fx('hs:d1'), 'Same person as the old survey')));
insert into tx values ('close_b1_o', pg_temp.as_login('o', format('select public.close_held_health_survey(%L, %L)::text', pg_temp.fx('hs:b1'), 'Bea again')));
select pg_temp.check(pg_temp.tx('close_d1_s') like 'ERROR:%' and pg_temp.tx('close_d1_m') !~ '^ERROR' and pg_temp.tx('close_b1_o') !~ '^ERROR'
    and (pg_temp.hold('d1')).resolution = 'closed' and (pg_temp.survey('d1')).customer_id is null
    and (pg_temp.hold('b1')).resolution = 'closed' and (pg_temp.survey('b1')).customer_id is null
    and pg_temp.listed('s', 'd1') is null and pg_temp.listed('s', 'b1') is null,
  'S close: refused for Staff; a Manager and an Owner close them, kept with no customer, off the list: '
  || pg_temp.tx('close_d1_s') || ' / ' || pg_temp.tx('close_d1_m'));

-- ═════ K What the forms changed, after staff dealt with them ═════
select pg_temp.check((select bool_and(pg_temp.record(k) = pg_temp.tx('rec:' || k)) from unnest(array['cBea', 'cDee']) k)
    and pg_temp.surveys_of('cBea') = 1 and pg_temp.surveys_of('cDee') = 0,
  'K Bea and Dee, whose forms were refused attaching or closed: their records as before, Bea her one survey, Dee none');

-- ═════ G Grants, M the tested version ═════
select pg_temp.check(has_function_privilege('anon', 'public.submit_health_survey(text,jsonb,jsonb,text)', 'execute')
    and has_function_privilege('authenticated', 'public.submit_health_survey(text,jsonb,jsonb,text)', 'execute')
    and has_function_privilege('service_role', 'public.submit_health_survey(text,jsonb,jsonb,text)', 'execute')
    and (select coalesce(string_agg(x::text, ',' order by x::text), '') from pg_proc p, unnest(p.proacl) x
          where p.oid = 'public.submit_health_survey(text,jsonb,jsonb,text)'::regprocedure)
        = 'anon=X/postgres,authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
  'G the form stays callable signed out, signed in and by the server; its grants are as before');
select pg_temp.check(md5(pg_get_functiondef('public.submit_health_survey(text,jsonb,jsonb,text)'::regprocedure))
        = case when pg_temp.m530() then '6441159a66f5ca4424848710c90f2576' else 'a65183cdcb48f2dd883a47c1c7aad7f3' end
    and (select pg_get_constraintdef(c.oid) from pg_constraint c
          where c.conrelid = 'public.health_survey_holds'::regclass and c.conname = 'health_survey_holds_reason_check')
        = 'CHECK ((reason = ANY (ARRAY[''phone_in_use''::text, ''email_in_use''::text, ''phone_and_email_in_use''::text, ''several_name_matches''::text, ''phone_and_email_customer_has_survey''::text, ''repeat_form''::text, ''customer_has_survey''::text, ''legacy_survey_same_details''::text, ''unreadable_phone_same_name''::text'
          || case when pg_temp.m530() then ', ''existing_customer''::text' else '' end || '])))',
  'M submit_health_survey is 524''s AFTER version, the reason check 524''s (530''s, each, where 530 is in)');
\if :{?skip_install}
\else
select pg_temp.check((select v from m524 where k = 'fn') = md5(pg_get_functiondef('public.submit_health_survey(text,jsonb,jsonb,text)'::regprocedure))
    and (select v from m524 where k = 'acl') = (select coalesce(string_agg(x::text, ',' order by x::text), '') from pg_proc p, unnest(p.proacl) x
                                                 where p.oid = 'public.submit_health_survey(text,jsonb,jsonb,text)'::regprocedure)
    and (select v from m524 where k = 'check') = (select pg_get_constraintdef(c.oid) from pg_constraint c
                                                   where c.conrelid = 'public.health_survey_holds'::regclass and c.conname = 'health_survey_holds_reason_check'),
  'M running 524 a second time changed nothing (the function, its grants, the reason check)');
\endif

do $$ declare v_failed int; begin
  select count(*) into v_failed from failed;
  if v_failed > 0 then raise exception '% check(s) failed: %', v_failed, (select string_agg(msg, '; ' order by n) from failed); end if;
  raise notice 'All survey-never-refused-524 checks passed.';
end $$;
rollback;
