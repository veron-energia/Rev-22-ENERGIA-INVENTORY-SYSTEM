-- Health survey tidy-ups (the Owner, 9 Oct 2026, Q8 A, parts a, b and c;
-- part d is B04's customer phones and names, part e leaves the 17 past
-- event-link forms as they are). Every change is recorded in the history;
-- nothing is deleted.
--
--   a. Consultant surveys showing "No" to all four health questions only
--      because someone pressed Save in Edit details (before 419 the window
--      saved every unanswered question as "No"): the four answers go back to
--      Not answered. Chosen: a consultant's survey the customer has not
--      signed, all four answers "No", saved by the old Edit details (its
--      audit row has no field values, only symptoms_replaced), and none of
--      the four set since by 419's Edit details, a consultant's save or the
--      customer's signed form. Two customers then stop counting as having
--      visited (9 Oct); neither was in the October promotion.
--   b. Consultant surveys with no store: Energia Rev 22 (Adelphi), where
--      every QR form has come from. Their files stay in the 'null' folder
--      (Owners and Managers read every folder).
--   c. Save Review pressed a second time with the boxes emptied blanked the
--      Goals, Condition and Recommendation of a review: they are put back
--      from the history (the old values of the Save Review row that blanked
--      them), on surveys where all three are still empty.
--
-- What it does, in one statement (atomic):
--   * refuses unless an active Owner is named (below) and each part finds
--     exactly the number read on 18 Oct 2026, or none (that part already
--     ran);
--   * makes the changes, and writes one audit row per survey per part
--     ('survey_declarations_reset', 'survey_store_set',
--     'survey_review_restored') with the old and new values, the reason and
--     the Owner who approved it;
--   * checks the result and prints counts only (never a name or a number).
--
-- Run it once, after 419, as the database owner (the SQL editor, the MCP
-- execute_sql tool, or psql as postgres), in one go with the line that names
-- the approving Owner first:
--   select set_config('energia.repair419_owner', '<the Owner''s profile id>', false);
-- If the counts have moved since 18 Oct (new surveys keep coming), read them
-- again with the queries below and pass them, in the order a, b, c:
--   select set_config('energia.repair419_expected', '{26,89,21}', false);
-- A second run changes nothing. Expected on production (18 Oct 2026):
-- a 26, b 89, c 21.
--
-- To check afterwards (counts only):
--   select count(*) from public.audit_logs where action = 'survey_declarations_reset';  -- a
--   select count(*) from public.health_surveys where source = 'consultant' and store_id is null;  -- 0
--   select count(*) from public.audit_logs where action = 'survey_review_restored';      -- c

do $repair$
declare
  c_store_name constant text := 'Energia Rev 22 (Adelphi)';
  c_reason_a constant text := 'Reset to Not answered: the "No" answers came from the old Edit details (the Owner, 9 Oct 2026, Q8 a)';
  c_reason_b constant text := 'Store set to Energia Rev 22 (Adelphi), where every QR form came from (the Owner, 9 Oct 2026, Q8 b)';
  c_reason_c constant text := 'Review put back from the history after a second Save Review blanked it (the Owner, 9 Oct 2026, Q8 c)';
  v_owner uuid := nullif(current_setting('energia.repair419_owner', true), '')::uuid;
  v_expected int[] := coalesce(nullif(current_setting('energia.repair419_expected', true), '')::int[], array[26, 89, 21]);
  v_path text := current_setting('search_path');
  v_claims text := current_setting('request.jwt.claims', true);
  v_store uuid; r record; n_a int; n_b int; n_c int; v_visits_before int; v_visits_after int; n int;
begin
  perform set_config('search_path', 'public', true);
  if v_owner is null or not exists (select 1 from public.profiles p where p.id = v_owner and p.role = 'owner'
                                       and p.is_active and p.deleted_at is null) then
    raise exception 'survey repairs: name the approving Owner first (energia.repair419_owner, an active Owner''s profile id); nothing was changed'; end if;
  if cardinality(v_expected) <> 3 then
    raise exception 'survey repairs: energia.repair419_expected must hold three counts (a, b, c); nothing was changed'; end if;
  if to_regprocedure('public.update_survey_particulars_v2(uuid,jsonb,text)') is null then
    raise exception 'survey repairs: run after 419 (the old Edit details would make more of part a); nothing was changed'; end if;
  select s.id into v_store from public.stores s where s.name = c_store_name and s.deleted_at is null;
  if (select count(*) from public.stores s where s.name = c_store_name and s.deleted_at is null) <> 1 then
    raise exception 'survey repairs: the store "%" is not there exactly once; nothing was changed', c_store_name; end if;

  -- ── What each part would change ─────────────────────────────────────────
  drop table if exists pg_temp.r419_a;
  create temp table r419_a on commit drop as
  select s.id, s.store_id from public.health_surveys s
   where s.source = 'consultant' and s.signature_data is null
     and s.has_medical_condition is false and s.drinks_alcohol is false and s.smokes is false and s.on_treatment is false
     and exists (select 1 from public.audit_logs a
                  where a.record_id = s.id and a.table_name = 'health_surveys' and a.action = 'survey_particulars_edited'
                    and a.new_data ? 'symptoms_replaced')
     and not exists (select 1 from public.audit_logs a
                      where a.record_id = s.id and a.table_name = 'health_surveys'
                        and a.action in ('survey_particulars_edited', 'consultant_survey_saved', 'health_survey_signed_by_customer')
                        and a.new_data ?| array['has_medical_condition', 'drinks_alcohol', 'smokes', 'on_treatment']);
  drop table if exists pg_temp.r419_b;
  create temp table r419_b on commit drop as
  select s.id from public.health_surveys s where s.source = 'consultant' and s.store_id is null;
  drop table if exists pg_temp.r419_c;
  create temp table r419_c on commit drop as
  select distinct on (s.id) s.id, s.store_id,
         nullif(btrim(a.old_data->>'health_goals'), '') as goals,
         nullif(btrim(a.old_data->>'condition'), '') as cond,
         nullif(btrim(a.old_data->>'recommendation'), '') as rec
    from public.health_surveys s
    join public.audit_logs a on a.record_id = s.id and a.table_name = 'health_surveys' and a.action = 'health_survey_reviewed'
   where nullif(btrim(s.health_goals), '') is null and nullif(btrim(s.remarks_condition), '') is null
     and nullif(btrim(s.remarks_recommendation), '') is null
     and coalesce(nullif(btrim(a.old_data->>'condition'), ''), nullif(btrim(a.old_data->>'recommendation'), ''),
                  nullif(btrim(a.old_data->>'health_goals'), '')) is not null
     and coalesce(nullif(btrim(a.new_data->>'condition'), ''), nullif(btrim(a.new_data->>'recommendation'), ''),
                  nullif(btrim(a.new_data->>'health_goals'), '')) is null
     and not coalesce((a.new_data->>'cleared')::boolean, false)
   order by s.id, a.created_at desc, a.id desc;
  select count(*) into n_a from r419_a;
  select count(*) into n_b from r419_b;
  select count(*) into n_c from r419_c;
  if (n_a <> 0 and n_a <> v_expected[1]) or (n_b <> 0 and n_b <> v_expected[2]) or (n_c <> 0 and n_c <> v_expected[3]) then
    raise exception 'survey repairs: found a %, b %, c %, not the % read on 18 Oct 2026. Re-read them (the queries in this file) and pass the counts; nothing was changed',
      n_a, n_b, n_c, v_expected; end if;
  if n_a + n_b + n_c = 0 then
    raise notice 'survey repairs: nothing left to do';
    perform set_config('search_path', v_path, true);
    return;
  end if;

  select count(*) into v_visits_before from public.customer_centre_visit_days();
  -- The audit rows name the approving Owner.
  perform set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);

  -- a. The four answers back to Not answered.
  for r in select * from r419_a order by id loop
    update public.health_surveys
       set has_medical_condition = null, drinks_alcohol = null, smokes = null, on_treatment = null
     where id = r.id;
    perform public.write_audit_ex('health_surveys', r.id, 'survey_declarations_reset',
      jsonb_build_object('has_medical_condition', false, 'drinks_alcohol', false, 'smokes', false, 'on_treatment', false),
      jsonb_build_object('has_medical_condition', null, 'drinks_alcohol', null, 'smokes', null, 'on_treatment', null),
      'survey', c_reason_a, r.store_id);
  end loop;
  -- b. The store.
  for r in select * from r419_b order by id loop
    update public.health_surveys set store_id = v_store where id = r.id and store_id is null;
    perform public.write_audit_ex('health_surveys', r.id, 'survey_store_set',
      jsonb_build_object('store_id', null), jsonb_build_object('store_id', v_store), 'survey', c_reason_b, v_store);
  end loop;
  -- c. The review's texts, as they were before they were blanked.
  for r in select * from r419_c order by id loop
    update public.health_surveys
       set health_goals = r.goals, remarks_condition = r.cond, remarks_recommendation = r.rec
     where id = r.id;
    perform public.write_audit_ex('health_surveys', r.id, 'survey_review_restored',
      jsonb_build_object('health_goals', null, 'condition', null, 'recommendation', null),
      jsonb_build_object('health_goals', r.goals, 'condition', r.cond, 'recommendation', r.rec),
      'survey', c_reason_c, coalesce(r.store_id, v_store));
  end loop;
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);

  -- ── Checks ──────────────────────────────────────────────────────────────
  select count(*) into n from public.health_surveys s join r419_a x on x.id = s.id
   where s.has_medical_condition is not null or s.drinks_alcohol is not null or s.smokes is not null or s.on_treatment is not null;
  if n > 0 then raise exception 'survey repairs: part a did not take; nothing was changed'; end if;
  if exists (select 1 from public.health_surveys where source = 'consultant' and store_id is null) then
    raise exception 'survey repairs: part b left a consultant survey with no store; nothing was changed'; end if;
  select count(*) into n from public.health_surveys s join r419_c x on x.id = s.id
   where s.health_goals is distinct from x.goals or s.remarks_condition is distinct from x.cond
      or s.remarks_recommendation is distinct from x.rec;
  if n > 0 then raise exception 'survey repairs: part c did not take; nothing was changed'; end if;
  select count(*) into v_visits_after from public.customer_centre_visit_days();
  raise notice 'survey repairs: a % answers reset, b % stores set, c % reviews put back; % audit rows; surveys counted as a visit % -> %',
    n_a, n_b, n_c, n_a + n_b + n_c, v_visits_before, v_visits_after;
  perform set_config('search_path', v_path, true);
end $repair$;
