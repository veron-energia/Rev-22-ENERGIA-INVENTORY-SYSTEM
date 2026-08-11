-- =====================================================================
-- ENERGIA — EVERY PART OF A SUBMISSION IS CORRECTABLE
--
-- update_survey_particulars() covered only the name, contact, date of birth,
-- sex and occupation. Three things were left uneditable, and one was wrong:
--
--   * AGE was never recalculated. Correcting a date of birth from 1985 to 1986
--     left the age showing 41, so the two disagreed on screen.
--   * "How did you hear about us?" could not be corrected.
--   * The DECLARATIONS (medical condition, alcohol, smoking, treatment) could
--     not be corrected.
--   * The SYMPTOM checklist could not be corrected.
--
-- Age is now derived from the date of birth rather than stored independently,
-- which is the only way the two can never disagree again.
--
-- Additive and idempotent. Run AFTER 103.
-- =====================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------
-- Age from a date of birth, in store time.
-- ---------------------------------------------------------------------
create or replace function public.age_from_dob(p_dob date)
returns integer language sql immutable as $function$
  select case when p_dob is null then null
              else extract(year from age(current_date, p_dob))::integer end
$function$;

-- Existing rows where the two already disagree are brought into line.
update public.health_surveys
   set age = public.age_from_dob(date_of_birth)
 where date_of_birth is not null
   and coalesce(age, -1) is distinct from public.age_from_dob(date_of_birth);

-- And kept in line from here on, whichever way the row is written.
create or replace function public.trg_sync_survey_age()
returns trigger language plpgsql as $function$
begin
  if new.date_of_birth is not null then
    new.age := public.age_from_dob(new.date_of_birth);
  end if;
  return new;
end $function$;

drop trigger if exists sync_survey_age on public.health_surveys;
create trigger sync_survey_age before insert or update on public.health_surveys
  for each row execute function public.trg_sync_survey_age();


-- ---------------------------------------------------------------------
-- The survey's source was treated as a PERMANENT SNAPSHOT: a deliberate
-- decision, since the survey records what the customer declared at the time.
--
-- Correcting it is now allowed for an OWNER or MANAGER only. Staff and any
-- automated path still cannot change it, so the snapshot stays protected
-- against accidental or silent overwriting.
-- ---------------------------------------------------------------------
do $patch$
declare v_def text; v_new text; v_old_line text; v_new_line text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'trg_health_survey_guard';
  if v_def is null then raise notice 'survey guard not present'; return; end if;
  if position('is_owner_or_manager() and old.source_option_id' in v_def) > 0 then
    raise notice 'the survey guard already allows an authorised correction'; return;
  end if;

  v_old_line := '    if old.source_option_id is not null and new.source_option_id is distinct from old.source_option_id then';
  v_new_line := '    if not public.is_owner_or_manager() and old.source_option_id is not null and new.source_option_id is distinct from old.source_option_id then';
  v_new := replace(v_def, v_old_line, v_new_line);

  -- The guard checks the snapshot TWICE: once on source_option_id and again on
  -- source_label. Both have to allow the authorised correction, or the second
  -- refuses what the first permitted.
  v_new := replace(v_new,
    '    if old.source_label is not null and new.source_label is distinct from old.source_label then',
    '    if not public.is_owner_or_manager() and old.source_label is not null and new.source_label is distinct from old.source_label then');

  if position('is_owner_or_manager() and old.source_option_id' in v_new) = 0 then
    raise exception 'Could not relax the survey source guard';
  end if;
  execute v_new;
  raise notice 'the survey source may now be corrected by an Owner or Manager';
end $patch$;

-- ---------------------------------------------------------------------
-- The full correction. The old signature is dropped first, or existing calls
-- become ambiguous.
-- ---------------------------------------------------------------------
drop function if exists public.update_survey_particulars(
  uuid, text, text, text, text, date, text, text, text);

create or replace function public.update_survey_particulars(
  p_survey_id uuid,
  p_first_name text default null, p_last_name text default null,
  p_phone text default null, p_email text default null,
  p_date_of_birth date default null, p_sex text default null,
  p_occupation text default null, p_others_text text default null,
  -- How they heard about us
  p_source_option_id uuid default null, p_source_details text default null,
  -- Declarations
  p_has_medical_condition boolean default null, p_drinks_alcohol boolean default null,
  p_smokes boolean default null, p_on_treatment boolean default null,
  p_treatment_list text default null,
  -- The symptom checklist: an array of health_symptom_options ids, each
  -- optionally with a duration. Passing null leaves the symptoms untouched;
  -- passing an empty array clears them.
  p_symptoms jsonb default null)
returns void language plpgsql security definer set search_path to 'public' as $function$
declare v_cust uuid; v_full text; v_s jsonb; v_label text;
begin
  if not public.is_owner_or_manager() then
    raise exception 'Only an Owner or Manager can edit a submission'; end if;

  v_full := public.join_person_name(p_first_name, p_last_name);
  if v_full is null then raise exception 'A first name is required'; end if;

  if p_source_option_id is not null then
    select label into v_label from public.customer_source_options where id = p_source_option_id;
    if v_label is null then raise exception 'That source is not available'; end if;
  end if;

  update public.health_surveys set
    first_name = nullif(trim(p_first_name),''),
    last_name  = nullif(trim(p_last_name),''),
    full_name  = v_full,
    phone      = nullif(trim(p_phone),''),
    email      = nullif(trim(p_email),''),
    date_of_birth = coalesce(p_date_of_birth, date_of_birth),
    -- age follows date_of_birth by trigger; never set independently.
    sex        = coalesce(nullif(trim(p_sex),''), sex),
    occupation = nullif(trim(p_occupation),''),
    others_text = nullif(trim(p_others_text),''),
    source_option_id = coalesce(p_source_option_id, source_option_id),
    source_label = coalesce(v_label, source_label),
    source_details = coalesce(nullif(trim(p_source_details),''), source_details),
    has_medical_condition = coalesce(p_has_medical_condition, has_medical_condition),
    drinks_alcohol = coalesce(p_drinks_alcohol, drinks_alcohol),
    smokes = coalesce(p_smokes, smokes),
    on_treatment = coalesce(p_on_treatment, on_treatment),
    treatment_list = case when p_on_treatment is false then null
                          else coalesce(nullif(trim(p_treatment_list),''), treatment_list) end
  where id = p_survey_id
  returning customer_id into v_cust;

  if not found then raise exception 'Submission not found'; end if;

  -- Symptoms are replaced wholesale when supplied, so unticking works.
  if p_symptoms is not null then
    delete from public.health_survey_symptoms where survey_id = p_survey_id;
    for v_s in select * from jsonb_array_elements(p_symptoms) loop
      insert into public.health_survey_symptoms (survey_id, option_id, duration_text)
      values (p_survey_id, (v_s->>'option_id')::uuid, nullif(trim(v_s->>'duration_text'),''))
      on conflict do nothing;
    end loop;
  end if;

  -- Keep the customer record aligned with the corrected submission.
  if v_cust is not null then
    update public.customers set
      first_name = nullif(trim(p_first_name),''),
      last_name  = nullif(trim(p_last_name),''),
      full_name  = v_full,
      email      = coalesce(nullif(trim(p_email),''), email),
      date_of_birth = coalesce(p_date_of_birth, date_of_birth),
      occupation = coalesce(nullif(trim(p_occupation),''), occupation),
      source_option_id = coalesce(p_source_option_id, source_option_id),
      source_label = coalesce(v_label, source_label),
      source_details = coalesce(nullif(trim(p_source_details),''), source_details)
    where id = v_cust;
  end if;

  perform public.write_audit_ex('health_surveys', p_survey_id, 'survey_particulars_edited', null,
    jsonb_build_object('name', v_full, 'symptoms_replaced', p_symptoms is not null),
    'survey', null, null);
end $function$;

notify pgrst, 'reload schema';
