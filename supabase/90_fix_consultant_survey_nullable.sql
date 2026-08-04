-- =====================================================================
-- ENERGIA — FIX: "Start survey" FAILED WITH A NOT-NULL VIOLATION
--
-- Pressing Start survey raised:
--   null value in column "store_id" of relation "health_surveys"
--
-- health_surveys was built for the public QR form, where the survey link
-- always carries a store. A consultant starting a survey from the customer
-- list has no link and no store in context, so store_id arrived null against
-- a NOT NULL column.
--
-- `phone` is NOT NULL for the same reason, and would have failed immediately
-- afterwards for every LEGACY-NO-PHONE-… customer.
--
-- Both are relaxed to allow null, since a consultant-created survey genuinely
-- may have neither. Public submissions still supply them as before.
-- upsert_consultant_survey also now falls back to a sensible default store.
--
-- Additive and idempotent. Run AFTER 89.
-- =====================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------
-- 1. A consultant survey may have no store and no phone.
-- ---------------------------------------------------------------------
alter table public.health_surveys alter column store_id drop not null;
alter table public.health_surveys alter column phone drop not null;

-- ---------------------------------------------------------------------
-- 2. Fall back to a store rather than storing null where one exists:
--    the caller's store if they have one, else the only active store.
-- ---------------------------------------------------------------------
create or replace function public.upsert_consultant_survey(
  p_customer_id uuid,
  p_remarks_condition text default null,
  p_remarks_recommendation text default null,
  p_acidity_result text default null,
  p_health_goals text default null,
  p_has_medical_condition boolean default null,
  p_drinks_alcohol boolean default null,
  p_smokes boolean default null,
  p_on_treatment boolean default null,
  p_treatment_list text default null,
  p_store_id uuid default null)
returns uuid language plpgsql security definer set search_path to 'public' as $function$
declare c public.customers%rowtype; v_id uuid; v_no text; v_store uuid;
begin
  select * into c from public.customers where id = p_customer_id;
  if not found then raise exception 'Customer not found'; end if;

  -- Prefer the store passed in; then the user's assigned store; then the only
  -- active store when there is exactly one. Null is acceptable if none apply.
  v_store := p_store_id;
  if v_store is null then
    select usa.store_id into v_store
      from public.user_store_assignments usa
     where usa.user_id = auth.uid()
     limit 1;
  end if;
  if v_store is null then
    select s.id into v_store from public.stores s
     where s.deleted_at is null and coalesce(s.is_active, true)
     limit 2;
    if (select count(*) from public.stores s
         where s.deleted_at is null and coalesce(s.is_active, true)) <> 1 then
      v_store := null;
    end if;
  end if;

  select id into v_id from public.health_surveys where customer_id = p_customer_id;

  if v_id is null then
    v_no := 'HS-' || to_char(now(), 'YYYYMMDD') || '-' || substr(md5(random()::text), 1, 6);
    insert into public.health_surveys (
      survey_no, store_id, customer_id, source, created_by,
      full_name, phone, email, date_of_birth, occupation,
      has_medical_condition, drinks_alcohol, smokes, on_treatment, treatment_list,
      acidity_result, remarks_condition, remarks_recommendation, health_goals,
      submitted_at)
    values (v_no, v_store, p_customer_id, 'consultant', auth.uid(),
      c.full_name,
      -- Legacy placeholder phones are not real numbers; store null instead.
      nullif(c.phone, '') , c.email, c.date_of_birth, c.occupation,
      p_has_medical_condition, p_drinks_alcohol, p_smokes, p_on_treatment, p_treatment_list,
      p_acidity_result, p_remarks_condition, p_remarks_recommendation, p_health_goals,
      now())
    returning id into v_id;
  else
    update public.health_surveys set
      remarks_condition = coalesce(p_remarks_condition, remarks_condition),
      remarks_recommendation = coalesce(p_remarks_recommendation, remarks_recommendation),
      acidity_result = coalesce(p_acidity_result, acidity_result),
      health_goals = coalesce(p_health_goals, health_goals),
      has_medical_condition = coalesce(p_has_medical_condition, has_medical_condition),
      drinks_alcohol = coalesce(p_drinks_alcohol, drinks_alcohol),
      smokes = coalesce(p_smokes, smokes),
      on_treatment = coalesce(p_on_treatment, on_treatment),
      treatment_list = coalesce(p_treatment_list, treatment_list),
      store_id = coalesce(p_store_id, store_id, v_store),
      reviewed_by = auth.uid(), reviewed_at = now()
    where id = v_id;
  end if;

  perform public.write_audit_ex('health_surveys', v_id, 'consultant_survey_saved', null,
    jsonb_build_object('customer', p_customer_id), 'survey', null, v_store);
  return v_id;
end $function$;

notify pgrst, 'reload schema';
