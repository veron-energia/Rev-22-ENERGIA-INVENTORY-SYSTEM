-- 419: Health Surveys, the survey's Edit details, the public QR form and who
-- may read health data.
--
--   S  Start survey (CUSTOMERS-M1, CUSTOMERS-2): a new survey belongs to the
--      store chosen (staff must work there; a Manager reaches every store, as
--      the page offers), else the caller's one store;
--      otherwise "Choose the store". An existing survey changes only in the
--      fields sent, and only an Owner's or Manager's finding marks it
--      reviewed. Inventory Managers are refused.
--   D  Edit details (update_survey_particulars_v2; CUSTOMERS-4, Q9): only
--      the fields sent change; "Not answered" can be saved; a missing date
--      of birth may be filled by staff, a filled one changed only by an
--      Owner or Manager with a reason; a customer's new phone needs a reason;
--      the source is an Owner's or Manager's; the old and new values are in
--      the audit row; a deleted customer's survey is not edited; the old
--      update_survey_particulars is gone.
--   R  Save Review (CUSTOMERS-K1): emptied boxes do not blank a saved review
--      unless p_clear; a save that changes nothing writes nothing.
--   Q  The QR form (Q10, CUSTOMERS-8, -12, -16): a customer's unsigned
--      consultant record takes their signed form, keeping the consultant's
--      work (an empty one becomes a QR form); a held form staff attach does
--      the same; names typed in two parts are kept; an event link's source is
--      recorded; a missing signed PDF is flagged; the customer's consents
--      are written; a held form put into a record counts once in Customer
--      Sources.
--   A  Survey files (CUSTOMERS-M1): only a file in storage, in the survey's
--      folder, with storage's size and type; the bucket has limits.
--   P  Read rules (CUSTOMERS-M2): Inventory Managers read no health data,
--      neither through the tables nor through the Health Surveys list;
--      staff of another store do not get a store's signed PDF (CUSTOMERS-14).
--   G  Grants.
--
-- Disposable database only; everything is rolled back. It needs production's
-- schema with 418 and 433 applied. Pass the migration to test with
-- -v mig=supabase/419_health_surveys_qr_form_and_read_rules.sql (it is run
-- twice; the second run must change nothing). Without it, the checks run
-- against the database as it is, and fail where 419 is missing.
--   psql -v ON_ERROR_STOP=1 [-v prelude=<418 file>] -v mig=<419 file> -f scripts/survey/tests/health-surveys-419.sql
-- Every name, phone and email is invented: phones from the ACMA's fictional
-- range (+61 491 57x xxx), emails @example.com.
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '10s';
set local statement_timeout = '300s';
\if :{?prelude}
\i :prelude
\endif
create temp table fp419(k text primary key, v text);
\if :{?mig}
\i :mig
insert into fp419 select 'after1', md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.oid::regprocedure::text))
  from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f';
\i :mig
insert into fp419 select 'after2', md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.oid::regprocedure::text))
  from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f';
\endif

create temp table failed(n serial, msg text);
create function pg_temp.check(ok boolean, msg text) returns void language plpgsql as
$$begin
  if ok is distinct from true then insert into failed(msg) values (msg); raise notice 'FAIL  %', msg;
  else raise notice 'PASS  %', msg; end if;
end$$;
create temp table fx(k text primary key, v uuid);
create function pg_temp.fx(key text) returns uuid language sql stable as $$ select v from fx where k = key $$;
create temp table tx(k text primary key, v text);
create function pg_temp.tx(key text) returns text language sql stable as $$ select v from tx where k = key $$;

-- Run p_sql as p_who: 'ok' and the result, or the SQLSTATE and the message.
-- p_who is a login key (the role authenticated, as a signed-in browser),
-- 'anon' or 'server' (no login). An error undoes only that call.
create function pg_temp.try(p_who text, p_sql text) returns text language plpgsql as $f$
declare v_out text; v_state text; v_msg text;
begin
  begin
    if p_who = 'server' then
      perform set_config('request.jwt.claims', '', true);
    elsif p_who = 'anon' then
      perform set_config('request.jwt.claims', '{"role":"anon"}', true);
      execute 'set local role anon';
    else
      perform set_config('request.jwt.claims',
        json_build_object('sub', pg_temp.fx(p_who), 'role', 'authenticated')::text, true);
      execute 'set local role authenticated';
    end if;
    execute p_sql into v_out;
    execute 'reset role';
    perform set_config('request.jwt.claims', '', true);
    return 'ok' || chr(9) || coalesce(v_out, '');
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
    execute 'reset role';
    perform set_config('request.jwt.claims', '', true);
    return v_state || chr(9) || v_msg;
  end;
end $f$;
create function pg_temp.state(v text) returns text language sql immutable as $$ select split_part(v, chr(9), 1) $$;
create function pg_temp.msg(v text) returns text language sql immutable as $$ select split_part(v, chr(9), 2) $$;
create function pg_temp.sql(p text) returns text language plpgsql stable as $f$
declare r record;
begin
  for r in select k, v from fx where v is not null loop p := replace(p, '@' || r.k || '@', quote_literal(r.v) || '::uuid'); end loop;
  return p;
end $f$;
create function pg_temp.run(p_who text, p_sql text) returns text language sql as $$ select pg_temp.try(p_who, pg_temp.sql(p_sql)) $$;
-- A QR form as the public page sends it (419's page: first and last name).
create function pg_temp.form(p_first text, p_last text, p_phone text, p_email text, p_extra jsonb default '{}')
  returns jsonb language sql stable as
$$ select jsonb_build_object('first_name', p_first, 'last_name', p_last,
                             'full_name', public.join_person_name(p_first, p_last),
                             'phone', p_phone, 'email', p_email, 'signature_data', 'data:image/png;base64,AAAA',
                             'source_option_id', pg_temp.fx('src'), 'sex', 'female', 'date_of_birth', '1979-03-04',
                             'occupation', 'Tester', 'has_medical_condition', false, 'drinks_alcohol', false,
                             'smokes', true, 'on_treatment', false) || p_extra $$;
create function pg_temp.submit(p_token text, p_payload jsonb, p_symptoms jsonb default '[]', p_pdf text default null)
  returns text language sql as
$$ select pg_temp.try('anon', format('select public.submit_health_survey(%L, %L::jsonb, %L::jsonb, %L)::text',
                                     p_token, p_payload, p_symptoms, p_pdf)) $$;
create function pg_temp.visit(p_survey uuid) returns date language sql stable as
$$ select v.visit_on from public.customer_centre_visit_days() v where v.survey_id = p_survey $$;
create function pg_temp.audits(p_survey uuid, p_action text) returns int language sql stable as
$$ select count(*)::int from public.audit_logs a where a.record_id = p_survey and a.action = p_action $$;

select pg_temp.check(to_regprocedure('public.update_survey_particulars_v2(uuid,jsonb,text)') is not null
    and to_regprocedure('public.can_view_health_data()') is not null,
  'P0 419 is installed');
select pg_temp.check(not exists (select 1 from public.customers where phone like '+6149157%'),
  'P0 no customer uses the fictional test phones (the checks below assume so)');
\if :{?mig}
select pg_temp.check((select v from fp419 where k = 'after1') = (select v from fp419 where k = 'after2'),
  'M the migration run a second time changes nothing');
\endif

-- ═════ Fixtures ═════
do $$
declare sfx text := lower(substr(md5(random()::text || clock_timestamp()::text), 1, 6)); k text; u uuid; c uuid;
begin
  insert into tx values ('sfx', sfx);
  foreach k in array array['o', 'm', 'm1', 'ad', 's1', 's2', 'sb', 'im'] loop
    u := gen_random_uuid(); insert into fx values (k, u);
    insert into auth.users(id, email) values (u, 't419-' || k || '-' || sfx || '@example.com');
  end loop;
  insert into public.profiles(id, full_name, email, role) values
    (pg_temp.fx('o'),  'T419 Owner',     't419-o-'  || sfx || '@example.com', 'owner'),
    (pg_temp.fx('m'),  'T419 Manager',   't419-m-'  || sfx || '@example.com', 'manager'),
    (pg_temp.fx('m1'), 'T419 Manager A', 't419-m1-' || sfx || '@example.com', 'manager'),
    (pg_temp.fx('ad'), 'T419 Admin',     't419-ad-' || sfx || '@example.com', 'admin'),
    (pg_temp.fx('s1'), 'T419 Staff A',   't419-s1-' || sfx || '@example.com', 'staff'),
    (pg_temp.fx('s2'), 'T419 Staff AB',  't419-s2-' || sfx || '@example.com', 'staff'),
    (pg_temp.fx('sb'), 'T419 Staff B',   't419-sb-' || sfx || '@example.com', 'staff'),
    (pg_temp.fx('im'), 'T419 Inventory', 't419-im-' || sfx || '@example.com', 'inventory_manager');
  insert into public.stores(name, code, country_code) values ('T419 Store A', 'T419A' || sfx, 'SG') returning id into c;
  insert into fx values ('store_a', c);
  insert into public.stores(name, code, country_code) values ('T419 Store B', 'T419B' || sfx, 'SG') returning id into c;
  insert into fx values ('store_b', c);
  insert into public.user_store_assignments(user_id, store_id) values
    (pg_temp.fx('m'), pg_temp.fx('store_a')), (pg_temp.fx('m'), pg_temp.fx('store_b')),
    (pg_temp.fx('m1'), pg_temp.fx('store_a')),
    (pg_temp.fx('s1'), pg_temp.fx('store_a')),
    (pg_temp.fx('s2'), pg_temp.fx('store_a')), (pg_temp.fx('s2'), pg_temp.fx('store_b')),
    (pg_temp.fx('sb'), pg_temp.fx('store_b')), (pg_temp.fx('im'), pg_temp.fx('store_a'));
  insert into public.customer_source_options(label) values ('T419 Walk-in ' || sfx) returning id into c; insert into fx values ('src', c);
  insert into public.customer_source_options(label) values ('T419 Event Name ' || sfx) returning id into c; insert into fx values ('src_event', c);
  insert into public.customer_source_options(label) values ('T419 RoadShow ' || sfx) returning id into c; insert into fx values ('src_road', c);
  insert into public.customer_source_options(label, is_active) values ('T419 Old ' || sfx, false) returning id into c; insert into fx values ('src_off', c);
  insert into public.survey_links(token, store_id) values ('t419-centre-' || sfx, pg_temp.fx('store_a')) returning id into c;
  insert into fx values ('link', c); insert into tx values ('token', 't419-centre-' || sfx);
  insert into public.survey_links(token, store_id, event_name, source_option_id)
  values ('t419-road-' || sfx, pg_temp.fx('store_b'), 'T419 Fair', pg_temp.fx('src_road')) returning id into c;
  insert into fx values ('link_road', c); insert into tx values ('token_road', 't419-road-' || sfx);
  insert into public.survey_links(token, store_id, event_name)
  values ('t419-oldevent-' || sfx, pg_temp.fx('store_b'), 'T419 Old Fair') returning id into c;
  insert into fx values ('link_oldevent', c); insert into tx values ('token_oldevent', 't419-oldevent-' || sfx);
  insert into public.survey_links(token, store_id, event_name, source_option_id)
  values ('t419-offevent-' || sfx, pg_temp.fx('store_b'), 'T419 Off Fair', pg_temp.fx('src_off')) returning id into c;
  insert into fx values ('link_offevent', c); insert into tx values ('token_offevent', 't419-offevent-' || sfx);
  insert into public.health_symptom_options(category, label) values ('Pain', 'T419 Back ' || sfx) returning id into c;
  insert into fx values ('sym1', c);
  insert into public.health_symptom_options(category, label) values ('Sleep', 'T419 Sleep ' || sfx) returning id into c;
  insert into fx values ('sym2', c);

  -- Customers, each on a fictional phone.
  insert into public.customers(first_name, last_name, phone, email, date_of_birth) values
    ('Alda', 'Testone', '+61491570156', 't419-alda-' || sfx || '@example.com', null) returning id into c; insert into fx values ('c_start', c);
  insert into public.customers(first_name, last_name, phone, email, date_of_birth) values
    ('Bea', 'Testtwo', '+61491570157', 't419-bea-' || sfx || '@example.com', date '1981-05-06') returning id into c; insert into fx values ('c_edit', c);
  insert into public.customers(first_name, last_name, phone, email) values
    ('Cleo', 'Testthree', '+61491570737', 't419-cleo-' || sfx || '@example.com') returning id into c; insert into fx values ('c_empty', c);
  insert into public.customers(first_name, last_name, phone, email) values
    ('Dina', 'Testfour', '+61491571266', 't419-dina-' || sfx || '@example.com') returning id into c; insert into fx values ('c_worked', c);
  insert into public.customers(first_name, last_name, phone, email) values
    ('Esme', 'Testfive', '+61491571491', 't419-esme-' || sfx || '@example.com') returning id into c; insert into fx values ('c_signed', c);
  insert into public.customers(first_name, last_name, phone, email) values
    ('Fay', 'Testsix', '+61491571804', 't419-fay-' || sfx || '@example.com') returning id into c; insert into fx values ('c_held', c);
  insert into public.customers(first_name, last_name, phone, email) values
    ('Gia', 'Testseven', '+61491572549', 't419-gia-' || sfx || '@example.com') returning id into c; insert into fx values ('c_del', c);
  insert into public.customers(first_name, last_name, phone, email) values
    ('Hana', 'Testeight', '+61491572665', 't419-hana-' || sfx || '@example.com') returning id into c; insert into fx values ('c_two', c);
  insert into public.customers(first_name, last_name, phone, email) values
    ('Ida', 'Testnine', '+61491572983', 't419-ida-' || sfx || '@example.com') returning id into c; insert into fx values ('c_pdf', c);
  insert into public.customers(first_name, last_name, phone, email) values
    ('Jo', 'Testten', '+61491577644', 't419-jo-' || sfx || '@example.com') returning id into c; insert into fx values ('c_mgr', c);
end $$;

-- ═════ S Start survey ═════
insert into tx values ('s1', pg_temp.run('o', 'select public.upsert_consultant_survey(@c_start@)::text'));
select pg_temp.check(pg_temp.msg(pg_temp.tx('s1')) = 'Choose the store for this survey.'
    and not exists (select 1 from health_surveys where customer_id = pg_temp.fx('c_start')),
  'S1 an Owner (no store of their own, two stores open) must choose the store; nothing is made: ' || pg_temp.tx('s1'));
insert into tx values ('s2', pg_temp.run('s2', 'select public.upsert_consultant_survey(@c_start@)::text'));
select pg_temp.check(pg_temp.msg(pg_temp.tx('s2')) = 'Choose the store for this survey.',
  'S2 staff at two stores must choose too: ' || pg_temp.tx('s2'));
insert into tx values ('s3', pg_temp.run('sb', 'select public.upsert_consultant_survey(@c_start@, p_store_id => @store_a@)::text'));
select pg_temp.check(pg_temp.state(pg_temp.tx('s3')) = '42501',
  'S3 staff cannot start a survey at a store they do not work at: ' || pg_temp.tx('s3'));
insert into tx values ('s4', pg_temp.run('s1', 'select public.upsert_consultant_survey(@c_start@)::text'));
insert into fx select 'hs_start', pg_temp.msg(pg_temp.tx('s4'))::uuid where pg_temp.state(pg_temp.tx('s4')) = 'ok';
select pg_temp.check(pg_temp.state(pg_temp.tx('s4')) = 'ok'
    and (select store_id = pg_temp.fx('store_a') and reviewed_at is null and source = 'consultant'
           from health_surveys where id = pg_temp.fx('hs_start')),
  'S4 staff at one store start a survey there, not marked reviewed: ' || pg_temp.tx('s4'));
insert into tx values ('s5n', (select count(*)::text from audit_logs where record_id = pg_temp.fx('hs_start')));
insert into tx values ('s5', pg_temp.run('s2', 'select public.upsert_consultant_survey(@c_start@, p_store_id => @store_b@)::text'));
select pg_temp.check(pg_temp.msg(pg_temp.tx('s5')) = pg_temp.fx('hs_start')::text
    and (select store_id = pg_temp.fx('store_a') and reviewed_at is null from health_surveys where id = pg_temp.fx('hs_start'))
    and (select count(*)::text from audit_logs where record_id = pg_temp.fx('hs_start')) = pg_temp.tx('s5n'),
  'S5 calling again with nothing in it changes nothing: not reviewed, the store kept, no history row');
insert into tx values ('s6', pg_temp.run('s1', 'select public.upsert_consultant_survey(@c_start@, ''A finding'')::text'));
select pg_temp.check(pg_temp.state(pg_temp.tx('s6')) = '42501', 'S6 staff cannot write a finding: ' || pg_temp.tx('s6'));
insert into tx values ('s7', pg_temp.run('m', 'select public.upsert_consultant_survey(@c_start@, ''Stiff neck'')::text'));
select pg_temp.check(pg_temp.state(pg_temp.tx('s7')) = 'ok'
    and (select remarks_condition = 'Stiff neck' and reviewed_by = pg_temp.fx('m') and reviewed_at is not null
           from health_surveys where id = pg_temp.fx('hs_start'))
    and exists (select 1 from audit_logs where record_id = pg_temp.fx('hs_start') and action = 'consultant_survey_saved'
                  and old_data ? 'remarks_condition' and new_data->>'remarks_condition' = 'Stiff neck'),
  'S7 a Manager''s finding is saved, marks it reviewed and is in the history with its old value');
insert into tx values ('s8', pg_temp.run('im', 'select public.upsert_consultant_survey(@c_two@, p_store_id => @store_a@)::text'));
select pg_temp.check(pg_temp.state(pg_temp.tx('s8')) = '42501', 'S8 an Inventory Manager cannot start a survey: ' || pg_temp.tx('s8'));
-- A survey with no store yet gets the store passed; one with a store keeps it.
update health_surveys set store_id = null where id = pg_temp.fx('hs_start');
insert into tx values ('s9', pg_temp.run('o', 'select public.upsert_consultant_survey(@c_start@, p_store_id => @store_b@)::text'));
select pg_temp.check(pg_temp.state(pg_temp.tx('s9')) = 'ok'
    and (select store_id from health_surveys where id = pg_temp.fx('hs_start')) = pg_temp.fx('store_b'),
  'S9 a survey with no store is given the store chosen: ' || pg_temp.tx('s9'));
insert into tx values ('s10', pg_temp.run('o', 'select public.upsert_consultant_survey(@c_start@, ''x'', p_acidity_result => ''purple'')::text'));
select pg_temp.check(pg_temp.msg(pg_temp.tx('s10')) = 'Acidity result must be Red, Green or Blue', 'S10 a wrong acidity is refused');
-- S11 A Manager who works at store A only starts a survey at store B: the
-- page offers Managers every store, so the server takes it too.
insert into tx values ('s11', pg_temp.run('m1', 'select public.upsert_consultant_survey(@c_mgr@, p_store_id => @store_b@)::text'));
select pg_temp.check(pg_temp.state(pg_temp.tx('s11')) = 'ok'
    and (select store_id from health_surveys where customer_id = pg_temp.fx('c_mgr')) = pg_temp.fx('store_b')
    and pg_temp.state(pg_temp.run('sb', 'select public.upsert_consultant_survey(@c_mgr@, p_store_id => @store_a@)::text')) = '42501',
  'S11 a Manager of one store starts a survey at another store; staff still cannot: ' || pg_temp.tx('s11'));

-- ═════ D Edit details ═════
insert into tx values ('d0', pg_temp.run('s1', 'select public.upsert_consultant_survey(@c_edit@)::text'));
insert into fx select 'hs_edit', pg_temp.msg(pg_temp.tx('d0'))::uuid where pg_temp.state(pg_temp.tx('d0')) = 'ok';
create function pg_temp.edit(p_who text, p_changes jsonb, p_reason text default null) returns text language sql as
$$ select pg_temp.try(p_who, format('select public.update_survey_particulars_v2(%L, %L::jsonb, %L)::text',
                                    pg_temp.fx('hs_edit'), p_changes, p_reason)) $$;
insert into tx values ('d1', pg_temp.edit('s1', '{"smokes": false}'));
select pg_temp.check(pg_temp.state(pg_temp.tx('d1')) = 'ok'
    and (select smokes is false and has_medical_condition is null and drinks_alcohol is null and on_treatment is null
           from health_surveys where id = pg_temp.fx('hs_edit')),
  'D1 one answer saved: the others stay Not answered: ' || pg_temp.tx('d1'));
select pg_temp.check(exists (select 1 from audit_logs where record_id = pg_temp.fx('hs_edit') and action = 'survey_particulars_edited'
                                and changed_by = pg_temp.fx('s1') and old_data = '{"smokes": null}'::jsonb
                                and new_data->'smokes' = 'false'::jsonb and not (new_data ? 'drinks_alcohol')),
  'D1 the history holds the old and new value of the answer changed, and nothing else');
insert into tx values ('d2', pg_temp.edit('s1', '{"smokes": null, "on_treatment": true, "treatment_list": "Physio"}'));
select pg_temp.check(pg_temp.state(pg_temp.tx('d2')) = 'ok'
    and (select smokes is null and on_treatment and treatment_list = 'Physio' from health_surveys where id = pg_temp.fx('hs_edit')),
  'D2 "Not answered" can be saved over an answer: ' || pg_temp.tx('d2'));
insert into tx values ('d2b', pg_temp.edit('s1', '{"on_treatment": false}'));
select pg_temp.check((select on_treatment is false and treatment_list is null from health_surveys where id = pg_temp.fx('hs_edit')),
  'D2 No to treatment clears the list, as before');
insert into tx values ('d3n', (select count(*)::text from audit_logs where record_id = pg_temp.fx('hs_edit')));
insert into tx values ('d3', pg_temp.edit('s1', '{"on_treatment": false, "occupation": "Tester"}'));
select pg_temp.check(pg_temp.state(pg_temp.tx('d3')) = 'ok'
    and (select count(*)::int from audit_logs where record_id = pg_temp.fx('hs_edit')) = pg_temp.tx('d3n')::int + 1
    and exists (select 1 from audit_logs where record_id = pg_temp.fx('hs_edit') and action = 'survey_particulars_edited'
                  and new_data->>'occupation' = 'Tester' and not (new_data ? 'on_treatment')),
  'D3 a field sent with its present value is not a change');
insert into tx values ('d4', pg_temp.edit('s1', '{"date_of_birth": "1981-05-07"}', 'Typo'));
select pg_temp.check(pg_temp.state(pg_temp.tx('d4')) = '42501'
    and (select date_of_birth from customers where id = pg_temp.fx('c_edit')) = '1981-05-06'
    and (select date_of_birth from health_surveys where id = pg_temp.fx('hs_edit')) = '1981-05-06',
  'D4 staff cannot change a date of birth already filled in (Q9): ' || pg_temp.tx('d4'));
insert into tx values ('d5', pg_temp.edit('o', '{"date_of_birth": "1981-05-07"}'));
select pg_temp.check(pg_temp.msg(pg_temp.tx('d5')) like 'A reason is required%', 'D5 an Owner needs a reason: ' || pg_temp.tx('d5'));
insert into tx values ('d6', pg_temp.edit('o', '{"date_of_birth": "1981-05-07"}', 'Checked her IC'));
select pg_temp.check(pg_temp.state(pg_temp.tx('d6')) = 'ok'
    and (select date_of_birth from customers where id = pg_temp.fx('c_edit')) = '1981-05-07'
    and (select date_of_birth from health_surveys where id = pg_temp.fx('hs_edit')) = '1981-05-07'
    and exists (select 1 from audit_logs where record_id = pg_temp.fx('hs_edit') and action = 'survey_particulars_edited'
                  and reason = 'Checked her IC' and old_data->>'date_of_birth' = '1981-05-06'
                  and old_data->'customer'->>'date_of_birth' = '1981-05-06'
                  and new_data->'customer'->>'date_of_birth' = '1981-05-07'),
  'D6 an Owner with a reason changes it on the survey and the customer; both old dates are in the history');
-- Staff fill in a missing date of birth.
insert into tx values ('d7', pg_temp.run('s1', 'select public.upsert_consultant_survey(@c_two@)::text'));
insert into fx select 'hs_two', pg_temp.msg(pg_temp.tx('d7'))::uuid where pg_temp.state(pg_temp.tx('d7')) = 'ok';
insert into tx values ('d8', pg_temp.try('s1', format('select public.update_survey_particulars_v2(%L, %L::jsonb, null)::text',
                                                     pg_temp.fx('hs_two'), '{"date_of_birth": "1990-02-03", "sex": "other"}')));
select pg_temp.check(pg_temp.state(pg_temp.tx('d8')) = 'ok'
    and (select date_of_birth = '1990-02-03' and gender = 'other' from customers where id = pg_temp.fx('c_two'))
    and (select sex from health_surveys where id = pg_temp.fx('hs_two')) = 'other',
  'D8 staff fill in a missing date of birth; Other is saved as the sex: ' || pg_temp.tx('d8'));
insert into tx values ('d9', pg_temp.edit('s1', '{"phone": "+61491573087"}'));
select pg_temp.check(pg_temp.msg(pg_temp.tx('d9')) like 'A reason is required to change a customer''s phone number%'
    and (select phone from customers where id = pg_temp.fx('c_edit')) = '+61491570157',
  'D9 a new phone for the customer needs a reason: ' || pg_temp.tx('d9'));
insert into tx values ('d10', pg_temp.edit('s1', '{"phone": "+61 491 573 087"}', 'New number'));
select pg_temp.check(pg_temp.state(pg_temp.tx('d10')) = 'ok'
    and (select phone from customers where id = pg_temp.fx('c_edit')) = '+61491573087'
    and exists (select 1 from customer_phone_history h where h.customer_id = pg_temp.fx('c_edit')
                  and h.phone = '+61491570157' and h.reason = 'New number'),
  'D10 with a reason, the customer gets the new phone and the history keeps the reason: ' || pg_temp.tx('d10'));
insert into tx values ('d11', pg_temp.edit('s1', jsonb_build_object('source_option_id', pg_temp.fx('src'))));
select pg_temp.check(pg_temp.state(pg_temp.tx('d11')) = '42501', 'D11 staff cannot set how the customer heard about us: ' || pg_temp.tx('d11'));
insert into tx values ('d12', pg_temp.edit('m', jsonb_build_object('source_option_id', pg_temp.fx('src'), 'source_details', 'Window')));
select pg_temp.check(pg_temp.state(pg_temp.tx('d12')) = 'ok'
    and (select source_option_id = pg_temp.fx('src') and source_details = 'Window' from health_surveys where id = pg_temp.fx('hs_edit'))
    and (select source_option_id from customers where id = pg_temp.fx('c_edit')) = pg_temp.fx('src'),
  'D12 a Manager sets it, on the survey and the customer: ' || pg_temp.tx('d12'));
insert into tx values ('d13', pg_temp.edit('s1', jsonb_build_object('symptoms', jsonb_build_array(
  jsonb_build_object('option_id', pg_temp.fx('sym1'), 'duration_text', '2 weeks')))));
insert into tx values ('d13b', pg_temp.edit('s1', '{"occupation": "Baker"}'));
select pg_temp.check(pg_temp.state(pg_temp.tx('d13')) = 'ok'
    and (select count(*) from health_survey_symptoms where survey_id = pg_temp.fx('hs_edit')) = 1
    and exists (select 1 from health_survey_symptoms where survey_id = pg_temp.fx('hs_edit') and option_id = pg_temp.fx('sym1')
                  and duration_text = '2 weeks'),
  'D13 symptoms sent replace the list; an edit without them leaves it alone');
insert into tx values ('d14', pg_temp.edit('s1', '{"first_name": "Bea Mae", "last_name": "Testtwo"}'));
select pg_temp.check(pg_temp.state(pg_temp.tx('d14')) = 'ok'
    and (select full_name = 'Bea Mae Testtwo' and first_name = 'Bea Mae' from customers where id = pg_temp.fx('c_edit'))
    and (select full_name from health_surveys where id = pg_temp.fx('hs_edit')) = 'Bea Mae Testtwo',
  'D14 a name changed on the survey goes onto the customer, as before');
select pg_temp.check(pg_temp.msg(pg_temp.edit('s1', '{"first_name": " "}')) = 'A first name is required'
    and pg_temp.msg(pg_temp.edit('s1', '{"is_referrer": true}')) = 'The field "is_referrer" cannot be changed here'
    and pg_temp.msg(pg_temp.edit('s1', '{"smokes": "no"}')) = 'Each declaration must be Yes, No or Not answered'
    and pg_temp.msg(pg_temp.edit('s1', '{"sex": "x"}')) = 'Sex must be Female, Male or Other'
    and pg_temp.msg(pg_temp.edit('s1', '{"email": null}')) = 'Email is mandatory on a health survey and cannot be removed',
  'D15 refused: an empty first name, a field not on the form, a declaration in words, a wrong sex, removing the email');
select pg_temp.check(pg_temp.state(pg_temp.edit('im', '{"smokes": true}')) = '42501'
    and pg_temp.state(pg_temp.edit('anon', '{"smokes": true}')) in ('42501', '42883'),
  'D16 an Inventory Manager and a signed-out visitor cannot edit');
update customers set deleted_at = now() where id = pg_temp.fx('c_edit');
select pg_temp.check(pg_temp.msg(pg_temp.edit('o', '{"smokes": true}')) like 'That customer has been deleted%',
  'D17 a deleted customer''s survey is not edited');
update customers set deleted_at = null where id = pg_temp.fx('c_edit');
select pg_temp.check(to_regprocedure('public.update_survey_particulars(uuid,text,text,text,text,date,text,text,text,uuid,text,boolean,boolean,boolean,boolean,text,jsonb)') is null
    and (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname like 'update_survey_particulars%') = 1,
  'D18 the old update_survey_particulars is gone; one Edit details function is left');

-- ═════ R Save Review ═════
create function pg_temp.review(p_who text, p_goals text, p_cond text, p_rec text, p_clear boolean default false) returns text language sql as
$$ select pg_temp.try(p_who, format('select public.review_health_survey(%L, %L, %L, %L, %L, %L)::text',
                                    pg_temp.fx('hs_two'), 'blue', p_goals, p_cond, p_rec, p_clear)) $$;
insert into tx values ('r1', pg_temp.review('o', 'Sleep', 'Tight back', 'Rest'));
insert into tx values ('r1n', pg_temp.audits(pg_temp.fx('hs_two'), 'health_survey_reviewed')::text);
insert into tx values ('r2', pg_temp.review('o', '', ' ', null));
select pg_temp.check(pg_temp.state(pg_temp.tx('r1')) = 'ok'
    and pg_temp.msg(pg_temp.tx('r2')) like 'Nothing to save%'
    and (select remarks_condition = 'Tight back' and remarks_recommendation = 'Rest' and health_goals = 'Sleep'
           from health_surveys where id = pg_temp.fx('hs_two'))
    and pg_temp.audits(pg_temp.fx('hs_two'), 'health_survey_reviewed') = pg_temp.tx('r1n')::int,
  'R1 Save Review pressed again with the boxes emptied keeps the saved review (K1): ' || pg_temp.tx('r2'));
insert into tx values ('r3', pg_temp.review('o', 'Sleep', 'Tight back', 'Rest'));
select pg_temp.check(pg_temp.state(pg_temp.tx('r3')) = 'ok'
    and pg_temp.audits(pg_temp.fx('hs_two'), 'health_survey_reviewed') = pg_temp.tx('r1n')::int,
  'R2 the same review saved again writes nothing');
insert into tx values ('r4', pg_temp.review('m', 'Sleep', 'Better', 'Rest'));
select pg_temp.check(pg_temp.state(pg_temp.tx('r4')) = 'ok'
    and (select remarks_condition from health_surveys where id = pg_temp.fx('hs_two')) = 'Better',
  'R3 a Manager changes one box; the others stay');
insert into tx values ('r5', pg_temp.review('o', null, null, null, true));
select pg_temp.check(pg_temp.state(pg_temp.tx('r5')) = 'ok'
    and (select remarks_condition is null and health_goals is null from health_surveys where id = pg_temp.fx('hs_two'))
    and exists (select 1 from audit_logs where record_id = pg_temp.fx('hs_two') and action = 'health_survey_reviewed'
                  and (new_data->>'cleared')::boolean and old_data->>'condition' = 'Better'),
  'R4 asked to clear (p_clear), the review is emptied, and the history says so');
select pg_temp.check(pg_temp.state(pg_temp.review('s1', 'x', 'y', 'z')) = '42501'
    and pg_temp.state(pg_temp.review('im', 'x', 'y', 'z')) = '42501',
  'R5 staff and Inventory Managers cannot save a review');

-- ═════ Q The QR form ═════
-- Q1 An empty consultant record (opened before 419) takes the form; it is a
-- QR form now: dated today, a visit by the centre's link.
insert into health_surveys(survey_no, store_id, customer_id, source, full_name, phone, email, submitted_at)
select 'HS-T419-EMPTY-' || pg_temp.tx('sfx'), pg_temp.fx('store_a'), c.id, 'consultant', c.full_name, c.phone, c.email,
       now() - interval '40 days'
  from customers c where c.id = pg_temp.fx('c_empty');
insert into fx select 'hs_empty', id from health_surveys where customer_id = pg_temp.fx('c_empty');
select pg_temp.check(pg_temp.visit(pg_temp.fx('hs_empty')) is null, 'Q1 (setup) the empty record is no visit');
insert into tx values ('q1', pg_temp.submit(pg_temp.tx('token'),
  pg_temp.form('Cleo', 'Testthree', '+61 491 570 737', 't419-cleo-' || pg_temp.tx('sfx') || '@example.com'),
  jsonb_build_array(jsonb_build_object('option_id', pg_temp.fx('sym2'), 'duration_text', '1 year')), 'UERGREFUQQ=='));
select pg_temp.check(pg_temp.state(pg_temp.tx('q1')) = 'ok'
    and (pg_temp.msg(pg_temp.tx('q1'))::jsonb->>'survey_id')::uuid = pg_temp.fx('hs_empty')
    and (pg_temp.msg(pg_temp.tx('q1'))::jsonb->>'survey_no') = 'HS-T419-EMPTY-' || pg_temp.tx('sfx')
    and (select count(*) from health_surveys where customer_id = pg_temp.fx('c_empty')) = 1,
  'Q1 a customer with an empty consultant record fills in the QR form: it goes into that record (Q10): ' || pg_temp.tx('q1'));
select pg_temp.check((select signature_data is not null and source = 'public_form' and survey_link_id = pg_temp.fx('link')
                         and submitted_at > now() - interval '1 minute' and smokes and has_medical_condition is false
                         and pdf_url = 'stored' and source_option_id = pg_temp.fx('src')
                        from health_surveys where id = pg_temp.fx('hs_empty'))
    and exists (select 1 from health_survey_pdfs where survey_id = pg_temp.fx('hs_empty'))
    and exists (select 1 from health_survey_symptoms where survey_id = pg_temp.fx('hs_empty') and option_id = pg_temp.fx('sym2'))
    and pg_temp.visit(pg_temp.fx('hs_empty')) = public.sg_today()
    and exists (select 1 from audit_logs where record_id = pg_temp.fx('hs_empty') and action = 'health_survey_signed_by_customer'
                  and (new_data->>'record_was_empty')::boolean and old_data->>'source' = 'consultant')
    and exists (select 1 from audit_logs where record_id = pg_temp.fx('hs_empty') and action = 'health_survey_submitted'
                  and (new_data->>'signed_into_record')::boolean),
  'Q1 the empty record becomes the QR form it now is: signed, dated today, its answers, symptoms and PDF, a visit today');
-- Q2 A record with the consultant's work keeps it; the customer's answers win.
insert into tx values ('q2a', pg_temp.run('o', 'select public.upsert_consultant_survey(@c_worked@, ''Old injury'', p_store_id => @store_a@, p_smokes => false, p_drinks_alcohol => true)::text'));
insert into fx select 'hs_worked', pg_temp.msg(pg_temp.tx('q2a'))::uuid where pg_temp.state(pg_temp.tx('q2a')) = 'ok';
update health_surveys set submitted_at = now() - interval '30 days', reviewed_at = now() - interval '30 days' where id = pg_temp.fx('hs_worked');
update audit_logs set created_at = now() - interval '30 days' where record_id = pg_temp.fx('hs_worked');
insert into consultant_notes(survey_id, customer_id, remarks_condition, created_by, created_at)
values (pg_temp.fx('hs_worked'), pg_temp.fx('c_worked'), 'Note kept', pg_temp.fx('o'), now() - interval '30 days');
insert into health_survey_attachments(survey_id, storage_path, file_name, uploaded_at)
values (pg_temp.fx('hs_worked'), pg_temp.fx('store_a') || '/' || pg_temp.fx('hs_worked') || '/t419.pdf', 't419.pdf', now() - interval '30 days');
insert into tx values ('q2visit', pg_temp.visit(pg_temp.fx('hs_worked'))::text);
insert into tx values ('q2', pg_temp.submit(pg_temp.tx('token'),
  pg_temp.form('Dina', 'Testfour', '+61491571266', 't419-dina-' || pg_temp.tx('sfx') || '@example.com', '{"drinks_alcohol": null, "consent_marketing_sms": true}')));
select pg_temp.check(pg_temp.state(pg_temp.tx('q2')) = 'ok'
    and (pg_temp.msg(pg_temp.tx('q2'))::jsonb->>'survey_id')::uuid = pg_temp.fx('hs_worked')
    and (select source = 'consultant' and signature_data is not null and remarks_condition = 'Old injury'
                and smokes is true and drinks_alcohol is true and submitted_at < now() - interval '29 days'
                and consent_marketing_sms is true and consent_marketing_email is false
           from health_surveys where id = pg_temp.fx('hs_worked'))
    and exists (select 1 from consultant_notes where survey_id = pg_temp.fx('hs_worked') and remarks_condition = 'Note kept')
    and exists (select 1 from health_survey_attachments where survey_id = pg_temp.fx('hs_worked'))
    and pg_temp.visit(pg_temp.fx('hs_worked'))::text = pg_temp.tx('q2visit')
    and exists (select 1 from audit_logs where record_id = pg_temp.fx('hs_worked') and action = 'health_survey_signed_by_customer'
                  and not (new_data->>'record_was_empty')::boolean and old_data->'smokes' = 'false'::jsonb
                  and old_data->'consent_marketing_sms' = 'false'::jsonb and new_data->'consent_marketing_sms' = 'true'::jsonb),
  'Q2 into a record with the consultant''s work: findings, note and file kept, the customer''s answers and consents win, one left blank keeps the record''s, the visit date stays: ' || pg_temp.tx('q2'));
select pg_temp.check(pg_temp.submit(pg_temp.tx('token'),
    pg_temp.form('Dina', 'Testfour', '+61491571266', 't419-dina-' || pg_temp.tx('sfx') || '@example.com')) like '%HEALTH_SURVEY_ALREADY_EXISTS%',
  'Q3 once signed, a second form is refused as before');
-- Q4 A customer whose survey is a signed QR form: refused as before.
insert into tx values ('q4a', pg_temp.submit(pg_temp.tx('token'),
  pg_temp.form('Esme', 'Testfive', '+61491571491', 't419-esme-' || pg_temp.tx('sfx') || '@example.com')));
select pg_temp.check(pg_temp.state(pg_temp.tx('q4a')) = 'ok'
    and pg_temp.submit(pg_temp.tx('token'),
          pg_temp.form('Esme', 'Testfive', '+61491571491', 't419-esme-' || pg_temp.tx('sfx') || '@example.com')) like '%HEALTH_SURVEY_ALREADY_EXISTS%',
  'Q4 a customer with a signed survey is refused a second, as before');
-- Q5 A new person: the name parts as typed (CUSTOMERS-8).
insert into tx values ('q5', pg_temp.submit(pg_temp.tx('token'),
  pg_temp.form('Mary Ann', 'Tan Testlee', '+61491573770', 't419-mary-' || pg_temp.tx('sfx') || '@example.com')));
insert into fx select 'hs_mary', (pg_temp.msg(pg_temp.tx('q5'))::jsonb->>'survey_id')::uuid where pg_temp.state(pg_temp.tx('q5')) = 'ok';
select pg_temp.check((select c.first_name = 'Mary Ann' and c.last_name = 'Tan Testlee' and c.full_name = 'Mary Ann Tan Testlee'
                        from health_surveys s join customers c on c.id = s.customer_id where s.id = pg_temp.fx('hs_mary'))
    and (select first_name = 'Mary Ann' and last_name = 'Tan Testlee' from health_surveys where id = pg_temp.fx('hs_mary')),
  'Q5 "Mary Ann" + "Tan Testlee" makes a customer with that first and last name, not split at the first space: ' || pg_temp.tx('q5'));
insert into tx values ('q5b', pg_temp.submit(pg_temp.tx('token'),
  pg_temp.form('Old', 'Page Testpage', '+61491574118', 't419-old-' || pg_temp.tx('sfx') || '@example.com') - 'first_name' - 'last_name'));
select pg_temp.check((select c.first_name = 'Old' and c.last_name = 'Page Testpage'
                        from health_surveys s join customers c on c.id = s.customer_id
                       where s.id = (pg_temp.msg(pg_temp.tx('q5b'))::jsonb->>'survey_id')::uuid),
  'Q5 a page from before 419 (whole name only) is split as before: ' || pg_temp.tx('q5b'));
-- Q6 An event link with a source: the link's source and the event name.
insert into tx values ('q6', pg_temp.submit(pg_temp.tx('token_road'),
  pg_temp.form('Rae', 'Testroad', '+61491574632', 't419-rae-' || pg_temp.tx('sfx') || '@example.com',
               jsonb_build_object('source_option_id', pg_temp.fx('src'), 'source_details', 'typed'))));
select pg_temp.check((select source_option_id = pg_temp.fx('src_road') and source_details = 'T419 Fair' and event_name = 'T419 Fair'
                        from health_surveys where id = (pg_temp.msg(pg_temp.tx('q6'))::jsonb->>'survey_id')::uuid),
  'Q6 an event link that names RoadShow records RoadShow and the event, whatever the page sent (CUSTOMERS-12): ' || pg_temp.tx('q6'));
insert into tx values ('q6b', pg_temp.submit(pg_temp.tx('token_road'),
  pg_temp.form('Sol', 'Testroad', '+61491575254', 't419-sol-' || pg_temp.tx('sfx') || '@example.com') - 'source_option_id'));
select pg_temp.check(pg_temp.state(pg_temp.tx('q6b')) = 'ok', 'Q6 the page may skip the question on such a link: ' || pg_temp.tx('q6b'));
insert into tx values ('q7', pg_temp.submit(pg_temp.tx('token_oldevent'),
  pg_temp.form('Tia', 'Testold', '+61491575789', 't419-tia-' || pg_temp.tx('sfx') || '@example.com',
               jsonb_build_object('source_option_id', pg_temp.fx('src_event'), 'source_details', 'T419 Old Fair'))));
insert into tx values ('q7b', pg_temp.submit(pg_temp.tx('token_offevent'),
  pg_temp.form('Uma', 'Testoff', '+61491576398', 't419-uma-' || pg_temp.tx('sfx') || '@example.com',
               jsonb_build_object('source_option_id', pg_temp.fx('src_event')))));
select pg_temp.check((select source_option_id from health_surveys where id = (pg_temp.msg(pg_temp.tx('q7'))::jsonb->>'survey_id')::uuid) = pg_temp.fx('src_event')
    and (select source_option_id from health_surveys where id = (pg_temp.msg(pg_temp.tx('q7b'))::jsonb->>'survey_id')::uuid) = pg_temp.fx('src_event'),
  'Q7 an older event link, or one whose source was switched off, keeps the page''s answer');
select pg_temp.check((public.survey_link_info(pg_temp.tx('token_road'))->>'source_option_id')::uuid = pg_temp.fx('src_road')
    and public.survey_link_info(pg_temp.tx('token_road'))->>'source_label' like 'T419 RoadShow%'
    and public.survey_link_info(pg_temp.tx('token'))->>'source_option_id' is null
    and public.survey_link_info(pg_temp.tx('token_offevent'))->>'source_option_id' is null,
  'Q8 the link tells the page its source, when it has one still offered');
select pg_temp.check(exists (select 1 from audit_logs where record_id = pg_temp.fx('hs_mary') and action = 'signed_pdf_missing')
    and not exists (select 1 from audit_logs where record_id = pg_temp.fx('hs_empty') and action = 'signed_pdf_missing'),
  'Q9 a form that came without its signed PDF is flagged in the history (CUSTOMERS-16)');
insert into tx values ('q9b', pg_temp.submit(pg_temp.tx('token'),
  pg_temp.form('Vee', 'Testpdf', '+61491576801', 't419-vee-' || pg_temp.tx('sfx') || '@example.com', '{"pdf_error": "Font not loaded"}')));
select pg_temp.check(exists (select 1 from audit_logs where action = 'signed_pdf_missing' and new_data->>'reason' = 'Font not loaded'
                               and record_id = (pg_temp.msg(pg_temp.tx('q9b'))::jsonb->>'survey_id')::uuid),
  'Q9 with the page''s reason');

-- Q10 A held form staff attach goes into the customer's unsigned record.
insert into tx values ('q10a', pg_temp.run('s1', 'select public.upsert_consultant_survey(@c_held@)::text'));
insert into fx select 'hs_heldinto', pg_temp.msg(pg_temp.tx('q10a'))::uuid where pg_temp.state(pg_temp.tx('q10a')) = 'ok';
insert into tx values ('q10b', pg_temp.submit(pg_temp.tx('token'),
  pg_temp.form('Faye', 'Testsix', '+61491571804', 't419-faye-' || pg_temp.tx('sfx') || '@example.com'),
  jsonb_build_array(jsonb_build_object('option_id', pg_temp.fx('sym1'))), 'UERGSEVMRA=='));
insert into fx select 'hs_held', (pg_temp.msg(pg_temp.tx('q10b'))::jsonb->>'survey_id')::uuid where pg_temp.state(pg_temp.tx('q10b')) = 'ok';
select pg_temp.check((select customer_id is null from health_surveys where id = pg_temp.fx('hs_held'))
    and exists (select 1 from health_survey_holds where survey_id = pg_temp.fx('hs_held') and resolved_at is null),
  'Q10 (setup) "Faye" on Fay''s phone is held for staff, as 433 does: ' || pg_temp.tx('q10b'));
insert into tx values ('q10list', pg_temp.run('s1', 'select public.health_survey_holds_list()::text'));
select pg_temp.check(exists (select 1 from jsonb_array_elements(pg_temp.msg(pg_temp.tx('q10list'))::jsonb) f,
                                         jsonb_array_elements(f->'candidates') c
                              where (f->>'survey_id')::uuid = pg_temp.fx('hs_held')
                                and (c->>'customer_id')::uuid = pg_temp.fx('c_held')
                                and (c->>'survey_takes_form')::boolean and c->>'survey_no' is not null),
  'Q10 the list says the customer''s survey can take the form');
create function pg_temp.walkins() returns text language sql as
$$ select pg_temp.msg(pg_temp.try('o', format('select surveys_count::text from public.report_customer_sources(null, null) where source_label = %L',
                                               'T419 Walk-in ' || pg_temp.tx('sfx')))) $$;
insert into tx values ('q10src', pg_temp.walkins());
insert into tx values ('q10', pg_temp.try('s1', format('select public.attach_held_health_survey(%L, %L, %L)::text',
                                                      pg_temp.fx('hs_held'), pg_temp.fx('c_held'), 'Checked her IC')));
select pg_temp.check(pg_temp.state(pg_temp.tx('q10')) = 'ok'
    and (pg_temp.msg(pg_temp.tx('q10'))::jsonb->>'signed_into_survey_no')
        = (select survey_no from health_surveys where id = pg_temp.fx('hs_heldinto'))
    and (select signature_data is not null and smokes is true and source = 'public_form'
                and submitted_at = (select submitted_at from health_surveys where id = pg_temp.fx('hs_held'))
           from health_surveys where id = pg_temp.fx('hs_heldinto'))
    and exists (select 1 from health_survey_pdfs where survey_id = pg_temp.fx('hs_heldinto') and pdf_base64 = 'UERGSEVMRA==')
    and exists (select 1 from health_survey_symptoms where survey_id = pg_temp.fx('hs_heldinto') and option_id = pg_temp.fx('sym1'))
    and (select customer_id is null from health_surveys where id = pg_temp.fx('hs_held'))
    and exists (select 1 from health_survey_holds where survey_id = pg_temp.fx('hs_held') and resolution = 'attached'
                  and resolved_customer_id = pg_temp.fx('c_held'))
    and (select count(*) from health_surveys where customer_id = pg_temp.fx('c_held')) = 1
    and exists (select 1 from audit_logs where record_id = pg_temp.fx('hs_held') and action = 'health_survey_matched'
                  and new_data->>'signed_into_survey_no' is not null),
  'Q10 staff attach it: its answers, symptoms and PDF go into her record, the form is kept as sent, the hold says attached: ' || pg_temp.tx('q10'));
select pg_temp.check(pg_temp.tx('q10src') ~ '^[0-9]+$' and pg_temp.walkins() = pg_temp.tx('q10src')
    and (select source_option_id from health_surveys where id = pg_temp.fx('hs_heldinto')) = pg_temp.fx('src'),
  'Q10 Customer Sources counts the form once: her record takes its source, the form kept as sent is not counted again: '
    || pg_temp.tx('q10src') || ' -> ' || pg_temp.walkins());
select pg_temp.check(pg_temp.submit(pg_temp.tx('token'),
    pg_temp.form('Faye', 'Testsix', '+61491571804', 't419-faye-' || pg_temp.tx('sfx') || '@example.com')) like '%HEALTH_SURVEY_ALREADY_EXISTS%',
  'Q11 she sends the form again: refused, not held again');
-- Q12 Attaching to a customer whose survey is signed: refused as before.
insert into tx values ('q12a', pg_temp.submit(pg_temp.tx('token'),
  pg_temp.form('Ezme', 'Testfive', '+61491571491', 't419-ezme-' || pg_temp.tx('sfx') || '@example.com')));
select pg_temp.check(pg_temp.try('s1', format('select public.attach_held_health_survey(%L, %L, %L)::text',
                                              (pg_temp.msg(pg_temp.tx('q12a'))::jsonb->>'survey_id')::uuid, pg_temp.fx('c_signed'), 'Same person'))
                     like '%This customer already has a health survey (HS-%). A customer can have only one.',
  'Q12 a customer whose survey is signed cannot take a held form: ' || pg_temp.tx('q12a'));
-- Q13 A new customer from a held form keeps the name parts typed.
insert into tx values ('q13a', pg_temp.submit(pg_temp.tx('token'),
  pg_temp.form('Ann Marie', 'Testsix', '+61491571804', 't419-annmarie-' || pg_temp.tx('sfx') || '@example.com')));
insert into tx values ('q13', pg_temp.try('s1', format('select public.create_customer_from_held_survey(%L, %L)::text',
                                                      (pg_temp.msg(pg_temp.tx('q13a'))::jsonb->>'survey_id')::uuid, 'Her daughter')));
select pg_temp.check((select first_name = 'Ann Marie' and last_name = 'Testsix' from customers
                       where id = (pg_temp.msg(pg_temp.tx('q13'))::jsonb->>'customer_id')::uuid),
  'Q13 a customer made from a held form keeps "Ann Marie" as the first name: ' || pg_temp.tx('q13'));
select pg_temp.check(pg_temp.state(pg_temp.try('anon', format('select public.health_survey_sign_into_record(%L, null, null, null)::text',
                                                              pg_temp.fx('hs_two')))) = '42501'
    and pg_temp.state(pg_temp.try('o', format('select public.health_survey_sign_into_record(%L, null, null, null)::text',
                                              pg_temp.fx('hs_two')))) = '42501',
  'Q14 nobody calls the internal sign-into-record step directly');
select pg_temp.check(pg_temp.try('server', format('select public.health_survey_sign_into_record(%L, h, ''[]''::jsonb, null)::text from public.health_surveys h where h.id = %L',
                                                  pg_temp.fx('hs_worked'), pg_temp.fx('hs_worked'))) like '%HEALTH_SURVEY_ALREADY_EXISTS%',
  'Q14b the sign-into-record step itself refuses a signed record');

-- ═════ A Survey files ═════
insert into storage.objects(bucket_id, name, metadata) values
  ('survey-attachments', pg_temp.fx('store_b') || '/' || pg_temp.fx('hs_start') || '/a.pdf', '{"size": 2048, "mimetype": "application/pdf"}'),
  ('survey-attachments', pg_temp.fx('store_b') || '/' || pg_temp.fx('hs_start') || '/big.pdf', '{"size": 10485761, "mimetype": "application/pdf"}'),
  ('survey-attachments', pg_temp.fx('store_b') || '/' || pg_temp.fx('hs_two') || '/other.pdf', '{"size": 10, "mimetype": "application/pdf"}');
create function pg_temp.attach_file(p_who text, p_survey uuid, p_path text) returns text language sql as
$$ select pg_temp.try(p_who, format('select public.add_survey_attachment(%L, %L, %L, %L, %L, null)::text',
                                    p_survey, p_path, 'file.pdf', 'image/png', 5)) $$;
insert into tx values ('a1', pg_temp.attach_file('o', pg_temp.fx('hs_start'), pg_temp.fx('store_b') || '/' || pg_temp.fx('hs_start') || '/a.pdf'));
select pg_temp.check(pg_temp.state(pg_temp.tx('a1')) = 'ok'
    and (select byte_size = 2048 and mime_type = 'application/pdf' from health_survey_attachments
          where id = pg_temp.msg(pg_temp.tx('a1'))::uuid),
  'A1 a file in storage is recorded with storage''s size and type, not the browser''s: ' || pg_temp.tx('a1'));
select pg_temp.check(pg_temp.msg(pg_temp.attach_file('o', pg_temp.fx('hs_start'), pg_temp.fx('store_b') || '/' || pg_temp.fx('hs_start') || '/a.pdf'))
                       = pg_temp.msg(pg_temp.tx('a1')),
  'A2 the same file sent twice is recorded once');
select pg_temp.check(pg_temp.msg(pg_temp.attach_file('o', pg_temp.fx('hs_start'), pg_temp.fx('store_b') || '/' || pg_temp.fx('hs_start') || '/none.pdf'))
                       = 'That file is not in storage. Upload it again.'
    and pg_temp.msg(pg_temp.attach_file('o', pg_temp.fx('hs_start'), pg_temp.fx('store_b') || '/' || pg_temp.fx('hs_two') || '/other.pdf'))
                       = 'That file is not in this survey''s folder. Upload it again.'
    and pg_temp.msg(pg_temp.attach_file('o', pg_temp.fx('hs_start'), pg_temp.fx('store_b') || '/' || pg_temp.fx('hs_start') || '/x/../a.pdf'))
                       = 'That file is not in this survey''s folder. Upload it again.'
    and pg_temp.msg(pg_temp.attach_file('o', pg_temp.fx('hs_start'), pg_temp.fx('store_b') || '/' || pg_temp.fx('hs_start') || '/big.pdf'))
                       = 'Files must be 10 MB or smaller.',
  'A3 refused: a file not in storage, another survey''s file, a path out of the folder, a file over 10 MB');
select pg_temp.check(pg_temp.state(pg_temp.attach_file('s1', pg_temp.fx('hs_start'), pg_temp.fx('store_b') || '/' || pg_temp.fx('hs_start') || '/a.pdf')) = '42501',
  'A4 staff cannot add files, as before');
update health_surveys set store_id = null where id = pg_temp.fx('hs_two');
insert into storage.objects(bucket_id, name, metadata)
values ('survey-attachments', 'null/' || pg_temp.fx('hs_two') || '/n.png', '{"size": 99, "mimetype": "image/png"}');
select pg_temp.check(pg_temp.state(pg_temp.attach_file('m', pg_temp.fx('hs_two'), 'null/' || pg_temp.fx('hs_two') || '/n.png')) = 'ok',
  'A5 a survey with no store yet takes files in its null/ folder');
select pg_temp.check(exists (select 1 from storage.buckets where id = 'survey-attachments' and file_size_limit = 10485760
                               and 'application/pdf' = any (allowed_mime_types) and 'image/*' = any (allowed_mime_types)),
  'A6 the survey files bucket takes 10 MB at most, of the types the page offers');

-- ═════ P Who reads health data ═════
insert into health_survey_pdfs(survey_id, pdf_base64) values (pg_temp.fx('hs_start'), 'UERG')
on conflict (survey_id) do nothing;
insert into customer_remarks(customer_id, survey_id, remark, created_by) values (pg_temp.fx('c_start'), pg_temp.fx('hs_start'), 'T419 remark', pg_temp.fx('o'));
insert into consultant_notes(survey_id, customer_id, remarks_condition, created_by) values (pg_temp.fx('hs_start'), pg_temp.fx('c_start'), 'T419 note', pg_temp.fx('o'));
create function pg_temp.seen(p_who text) returns text language sql as
$$ select pg_temp.msg(pg_temp.run(p_who, 'select concat_ws('','',
      (select count(*) from public.health_surveys where id = @hs_start@),
      (select count(*) from public.health_survey_symptoms where survey_id = @hs_edit@),
      (select count(*) from public.consultant_notes where survey_id = @hs_start@),
      (select count(*) from public.customer_remarks where survey_id = @hs_start@),
      (select count(*) from public.health_survey_pdfs where survey_id = @hs_start@))')) $$;
select pg_temp.check(pg_temp.seen('im') = '0,0,0,0,0', 'P1 an Inventory Manager reads no health data (CUSTOMERS-M2): ' || pg_temp.seen('im'));
select pg_temp.check(pg_temp.state(pg_temp.run('im', 'select count(*)::text from public.customer_survey_overview(null, ''all'', 50, 0)')) = '42501'
    and pg_temp.msg(pg_temp.run('s1', 'select string_agg(remarks_condition, '','') from public.customer_survey_overview(''Alda Testone'', ''all'', 50, 0)')) = 'Stiff neck',
  'P1b an Inventory Manager gets no survey list or findings from customer_survey_overview; staff still do');
select pg_temp.check(pg_temp.seen('sb') = '1,1,1,1,1' and pg_temp.seen('o') = '1,1,1,1,1' and pg_temp.seen('m') = '1,1,1,1,1',
  'P2 staff of the survey''s store, Owners and Managers read it all: ' || pg_temp.seen('sb'));
select pg_temp.check(pg_temp.seen('s1') = '1,1,1,1,0', 'P3 staff of another store read the survey but not its signed PDF: ' || pg_temp.seen('s1'));
select pg_temp.check((pg_temp.msg(pg_temp.run('s1', 'select public.health_survey_detail(@hs_start@)::text'))::jsonb->>'has_pdf')::boolean = false
    and (pg_temp.msg(pg_temp.run('s1', 'select public.health_survey_detail(@hs_start@)::text'))::jsonb->>'pdf_other_store')::boolean
    and (pg_temp.msg(pg_temp.run('sb', 'select public.health_survey_detail(@hs_start@)::text'))::jsonb->>'has_pdf')::boolean,
  'P4 the survey window offers the PDF only to those who may open it, and says why to the others (CUSTOMERS-14)');
select pg_temp.check(pg_temp.state(pg_temp.run('im', 'select public.health_survey_detail(@hs_start@)::text')) = '42501'
    and pg_temp.state(pg_temp.run('anon', 'select public.health_survey_detail(@hs_start@)::text')) = '42501',
  'P5 an Inventory Manager and a signed-out visitor cannot open a survey');

-- ═════ X The server's name diagnostic ═════
select pg_temp.check(exists (select 1 from public.diagnose_survey_name_edit((select survey_no from health_surveys where id = pg_temp.fx('hs_edit'))) d
                              where d.step = '8. VERDICT' and d.value like 'DATABASE IS FINE%')
    and (select full_name from customers where id = pg_temp.fx('c_edit')) = 'Bea Mae Testtwo',
  'X the server''s name diagnostic calls 419''s Edit details, still works, and changes nothing');

-- ═════ G Grants ═════
select pg_temp.check(not has_function_privilege('anon', 'public.can_view_health_data()', 'execute')
    and has_function_privilege('authenticated', 'public.can_view_health_data()', 'execute')
    and has_function_privilege('authenticated', 'public.update_survey_particulars_v2(uuid,jsonb,text)', 'execute')
    and not has_function_privilege('anon', 'public.update_survey_particulars_v2(uuid,jsonb,text)', 'execute')
    and has_function_privilege('authenticated', 'public.review_health_survey(uuid,text,text,text,text,boolean)', 'execute')
    and to_regprocedure('public.review_health_survey(uuid,text,text,text,text)') is null
    and not has_function_privilege('authenticated', 'public.health_survey_sign_into_record(uuid,health_surveys,jsonb,text)', 'execute')
    and has_function_privilege('anon', 'public.submit_health_survey(text,jsonb,jsonb,text)', 'execute')
    and has_function_privilege('anon', 'public.survey_link_info(text)', 'execute'),
  'G the new functions are signed-in users'' (the internal one the server''s); the public form stays open');

do $$
declare v_n int; v_m text;
begin
  select count(*), string_agg(msg, E'\n' order by n) into v_n, v_m from failed;
  if v_n > 0 then raise exception '% check(s) failed:%', v_n, E'\n' || v_m; end if;
  raise notice 'all checks passed';
end $$;
rollback;
