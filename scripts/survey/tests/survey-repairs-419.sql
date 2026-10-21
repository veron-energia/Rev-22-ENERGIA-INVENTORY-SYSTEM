-- The health survey tidy-ups of Q8 a, b and c (scripts/repairs/survey-repairs-419.sql).
--
--   a  "No" to all four questions, saved by the old Edit details, goes back
--      to Not answered; answers set since 419, and signed ones, stay.
--   b  A consultant survey with no store gets Energia Rev 22 (Adelphi).
--   c  A review blanked by a second Save Review is put back from the
--      history; one an Owner cleared on purpose stays empty.
--   Each change has its audit row naming the Owner; a second run changes
--   nothing; it refuses without an Owner, or when the counts are not the
--   ones it was told.
--
-- Disposable database only; everything is rolled back. It needs 419 (pass
-- -v mig=<419 file> where it is not applied). Every name, phone and email is
-- invented: phones from the ACMA's fictional range, emails @example.com.
--   psql -v ON_ERROR_STOP=1 [-v mig=<419 file>] -f scripts/survey/tests/survey-repairs-419.sql
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '10s';
\if :{?mig}
\i :mig
\endif
create temp table failed(n serial, msg text);
create function pg_temp.check(ok boolean, msg text) returns void language plpgsql as
$$begin
  if ok is distinct from true then insert into failed(msg) values (msg); raise notice 'FAIL  %', msg;
  else raise notice 'PASS  %', msg; end if;
end$$;
create temp table fx(k text primary key, v uuid);
create function pg_temp.fx(key text) returns uuid language sql stable as $$ select v from fx where k = key $$;
create function pg_temp.err(q text) returns text language plpgsql as
$$begin execute q; return 'ok'; exception when others then return sqlerrm; end$$;

select pg_temp.check(not exists (select 1 from public.health_surveys)
                       and not exists (select 1 from public.audit_logs where action in ('survey_declarations_reset', 'survey_store_set', 'survey_review_restored')),
  'P0 an empty test database (the counts below are the fixtures'')');

do $$
declare sfx text := lower(substr(md5(random()::text), 1, 6)); u uuid; c uuid; s uuid; st uuid;
begin
  u := gen_random_uuid(); insert into fx values ('owner', u);
  insert into auth.users(id, email) values (u, 'r419-owner-' || sfx || '@example.com');
  insert into public.profiles(id, full_name, email, role) values (u, 'R419 Owner', 'r419-owner-' || sfx || '@example.com', 'owner');
  select id into st from public.stores where name = 'Energia Rev 22 (Adelphi)' and deleted_at is null;
  if st is null then
    insert into public.stores(name, code, country_code) values ('Energia Rev 22 (Adelphi)', 'R419A' || sfx, 'SG') returning id into st;
  end if;
  insert into fx values ('adelphi', st);
  insert into public.stores(name, code, country_code) values ('R419 Van', 'R419V' || sfx, 'SG') returning id into c;
  insert into fx values ('van', c);

  -- a1: the old Edit details saved four "No"s.
  insert into public.customers(first_name, last_name, phone) values ('Ada', 'Testrep', '+61491578957') returning id into c;
  insert into public.health_surveys(survey_no, store_id, customer_id, source, full_name, phone, email, submitted_at,
                                    has_medical_condition, drinks_alcohol, smokes, on_treatment)
  values ('HS-R419-A1-' || sfx, pg_temp.fx('van'), c, 'consultant', 'Ada Testrep', '+61491578957', 'ada@example.com', now(), false, false, false, false)
  returning id into s; insert into fx values ('a1', s);
  insert into public.audit_logs(table_name, record_id, action, new_data) values ('health_surveys', s, 'survey_particulars_edited',
    '{"name": "Ada Testrep", "symptoms_replaced": true}');
  -- a2: the same, but "No" chosen since in 419's Edit details.
  insert into public.customers(first_name, last_name, phone) values ('Bo', 'Testrep', '+61491579212') returning id into c;
  insert into public.health_surveys(survey_no, store_id, customer_id, source, full_name, phone, email, submitted_at,
                                    has_medical_condition, drinks_alcohol, smokes, on_treatment)
  values ('HS-R419-A2-' || sfx, pg_temp.fx('van'), c, 'consultant', 'Bo Testrep', '+61491579212', 'bo@example.com', now(), false, false, false, false)
  returning id into s; insert into fx values ('a2', s);
  insert into public.audit_logs(table_name, record_id, action, new_data) values
    ('health_surveys', s, 'survey_particulars_edited', '{"name": "Bo Testrep", "symptoms_replaced": false}'),
    ('health_surveys', s, 'survey_particulars_edited', '{"smokes": false, "name": "Bo Testrep"}');
  -- a3: four "No"s the customer signed.
  insert into public.customers(first_name, last_name, phone) values ('Cy', 'Testrep', '+61491579455') returning id into c;
  insert into public.health_surveys(survey_no, store_id, customer_id, source, full_name, phone, email, submitted_at, signature_data,
                                    has_medical_condition, drinks_alcohol, smokes, on_treatment)
  values ('HS-R419-A3-' || sfx, pg_temp.fx('van'), c, 'consultant', 'Cy Testrep', '+61491579455', 'cy@example.com', now(), 'data:image/png;base64,AA',
          false, false, false, false)
  returning id into s; insert into fx values ('a3', s);
  insert into public.audit_logs(table_name, record_id, action, new_data) values ('health_surveys', s, 'survey_particulars_edited',
    '{"name": "Cy Testrep", "symptoms_replaced": true}');
  -- b1: a consultant survey with no store.
  insert into public.customers(first_name, last_name, phone) values ('Di', 'Testrep', '+61491579760') returning id into c;
  insert into public.health_surveys(survey_no, store_id, customer_id, source, full_name, phone, email, submitted_at)
  values ('HS-R419-B1-' || sfx, null, c, 'consultant', 'Di Testrep', '+61491579760', 'di@example.com', now())
  returning id into s; insert into fx values ('b1', s);
  -- c1: a review blanked by a second Save Review.
  insert into public.customers(first_name, last_name, phone) values ('Ed', 'Testrep', '+61491570006') returning id into c;
  insert into public.health_surveys(survey_no, store_id, customer_id, source, full_name, phone, email, submitted_at, acidity_result)
  values ('HS-R419-C1-' || sfx, pg_temp.fx('van'), c, 'public_form', 'Ed Testrep', '+61491570006', 'ed@example.com', now(), 'green')
  returning id into s; insert into fx values ('c1', s);
  insert into public.audit_logs(table_name, record_id, action, old_data, new_data, created_at) values
    ('health_surveys', s, 'health_survey_reviewed', '{"acidity": null, "condition": null, "recommendation": null, "health_goals": null}',
     '{"acidity": "green", "condition": "First", "recommendation": "Rest", "health_goals": "Sleep"}', now() - interval '2 days'),
    ('health_surveys', s, 'health_survey_reviewed', '{"acidity": "green", "condition": "First", "recommendation": "Rest", "health_goals": "Sleep"}',
     '{"acidity": "green", "condition": "Tight back", "recommendation": "Rest more", "health_goals": "Sleep"}', now() - interval '1 day'),
    ('health_surveys', s, 'health_survey_reviewed', '{"acidity": "green", "condition": "Tight back", "recommendation": "Rest more", "health_goals": "Sleep"}',
     '{"acidity": "green", "condition": null, "recommendation": null, "health_goals": null}', now() - interval '1 hour');
  -- c2: a review an Owner cleared on purpose (419's p_clear).
  insert into public.customers(first_name, last_name, phone) values ('Fi', 'Testrep', '+61491570156') returning id into c;
  insert into public.health_surveys(survey_no, store_id, customer_id, source, full_name, phone, email, submitted_at)
  values ('HS-R419-C2-' || sfx, pg_temp.fx('van'), c, 'public_form', 'Fi Testrep', '+61491570156', 'fi@example.com', now())
  returning id into s; insert into fx values ('c2', s);
  insert into public.audit_logs(table_name, record_id, action, old_data, new_data) values
    ('health_surveys', s, 'health_survey_reviewed', '{"condition": "Old", "recommendation": null, "health_goals": null}',
     '{"condition": null, "recommendation": null, "health_goals": null, "cleared": true}');
end $$;

-- Refused: no Owner named; counts other than the ones found. Each refusal is
-- caught by a savepoint, so the checks go on.
\set ON_ERROR_STOP off
savepoint no_owner;
select set_config('energia.repair419_owner', '', true);
\ir ../../repairs/survey-repairs-419.sql
rollback to savepoint no_owner;
savepoint wrong_counts;
select set_config('energia.repair419_owner', pg_temp.fx('owner')::text, true);
select set_config('energia.repair419_expected', '{2,1,1}', true);
\ir ../../repairs/survey-repairs-419.sql
rollback to savepoint wrong_counts;
\set ON_ERROR_STOP on
select set_config('energia.repair419_owner', pg_temp.fx('owner')::text, true);
select pg_temp.check((select has_medical_condition from public.health_surveys where id = pg_temp.fx('a1')) is false
    and (select store_id from public.health_surveys where id = pg_temp.fx('b1')) is null
    and not exists (select 1 from public.audit_logs where action in ('survey_declarations_reset', 'survey_store_set', 'survey_review_restored')),
  'R1 refused without an Owner, and with counts other than the ones found: nothing changed');

select set_config('energia.repair419_expected', '{1,1,1}', true);
\ir ../../repairs/survey-repairs-419.sql
select pg_temp.check((select has_medical_condition is null and drinks_alcohol is null and smokes is null and on_treatment is null
                        from public.health_surveys where id = pg_temp.fx('a1'))
    and exists (select 1 from public.audit_logs where record_id = pg_temp.fx('a1') and action = 'survey_declarations_reset'
                  and changed_by = pg_temp.fx('owner') and reason like 'Reset to Not answered%'
                  and old_data->'smokes' = 'false'::jsonb and new_data->'smokes' = 'null'::jsonb),
  'Ra the old Edit details'' "No"s are Not answered again, recorded with the Owner');
select pg_temp.check((select smokes from public.health_surveys where id = pg_temp.fx('a2')) is false
    and (select smokes from public.health_surveys where id = pg_temp.fx('a3')) is false,
  'Ra answers chosen in 419''s Edit details, and signed ones, stay');
select pg_temp.check((select store_id from public.health_surveys where id = pg_temp.fx('b1')) = pg_temp.fx('adelphi')
    and exists (select 1 from public.audit_logs where record_id = pg_temp.fx('b1') and action = 'survey_store_set'
                  and new_data->>'store_id' = pg_temp.fx('adelphi')::text),
  'Rb the consultant survey with no store is Adelphi''s, recorded');
select pg_temp.check((select remarks_condition = 'Tight back' and remarks_recommendation = 'Rest more' and health_goals = 'Sleep'
                        from public.health_surveys where id = pg_temp.fx('c1'))
    and exists (select 1 from public.audit_logs where record_id = pg_temp.fx('c1') and action = 'survey_review_restored'
                  and new_data->>'condition' = 'Tight back'),
  'Rc the blanked review is back as it was just before it was blanked');
select pg_temp.check((select remarks_condition from public.health_surveys where id = pg_temp.fx('c2')) is null,
  'Rc a review cleared on purpose stays empty');
create temp table r419_rows as select count(*) as n from public.audit_logs
 where action in ('survey_declarations_reset', 'survey_store_set', 'survey_review_restored');
\ir ../../repairs/survey-repairs-419.sql
select pg_temp.check((select n from r419_rows) = 3
    and (select count(*) from public.audit_logs where action in ('survey_declarations_reset', 'survey_store_set', 'survey_review_restored')) = 3,
  'R2 one audit row per change; a second run changes nothing');

do $$
declare v_n int; v_m text;
begin
  select count(*), string_agg(msg, E'\n' order by n) into v_n, v_m from failed;
  if v_n > 0 then raise exception '% check(s) failed:%', v_n, E'\n' || v_m; end if;
  raise notice 'all checks passed';
end $$;
rollback;
