-- =====================================================================
-- ENERGIA — CONSULTANT SURVEYS FOR EXISTING CUSTOMERS
--
-- Health Surveys only ever held submissions from the public QR form, so a
-- consultant had nowhere to record findings for a customer already on file.
--
--   1. A survey can now be created by staff for an existing customer, not only
--      by public submission. One survey per customer, editable thereafter.
--   2. A per-customer remarks log, so consultation notes accumulate over time
--      without overwriting the single survey.
--
-- Additive and idempotent. Run AFTER 88.
-- =====================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------
-- 1. Where a survey came from, and one survey per customer.
-- ---------------------------------------------------------------------
alter table public.health_surveys add column if not exists created_by uuid references public.profiles(id);
alter table public.health_surveys add column if not exists source text not null default 'public_form';
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'health_surveys_source_check') then
    alter table public.health_surveys
      add constraint health_surveys_source_check check (source in ('public_form','consultant'));
  end if;
end $$;

-- One survey per customer. Rows with no customer (anonymous public forms) are
-- unaffected. If duplicates already exist, keep the most recent.
do $$
declare v_dupes integer;
begin
  select count(*) into v_dupes from (
    select customer_id from public.health_surveys
     where customer_id is not null group by customer_id having count(*) > 1) d;
  if v_dupes > 0 then
    raise notice 'Found % customer(s) with several surveys — keeping the latest of each', v_dupes;
    delete from public.health_surveys hs
     where hs.customer_id is not null
       and hs.id <> (select h2.id from public.health_surveys h2
                      where h2.customer_id = hs.customer_id
                      order by coalesce(h2.submitted_at, now()) desc, h2.id desc limit 1);
  end if;
end $$;

create unique index if not exists uq_health_survey_customer
  on public.health_surveys (customer_id) where customer_id is not null;

-- ---------------------------------------------------------------------
-- 2. A remarks log per customer — many entries over time.
-- ---------------------------------------------------------------------
create table if not exists public.customer_remarks (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.customers(id),
  survey_id uuid references public.health_surveys(id),
  remark text not null,
  remark_type text not null default 'consultation'
    check (remark_type in ('consultation','recommendation','follow_up','other')),
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now()
);
create index if not exists idx_customer_remarks on public.customer_remarks (customer_id, created_at desc);
alter table public.customer_remarks enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where schemaname='public'
                  and tablename='customer_remarks' and policyname='read customer remarks') then
    create policy "read customer remarks" on public.customer_remarks
      for select to authenticated using (true);
  end if;
end $$;

create or replace function public.add_customer_remark(
  p_customer_id uuid, p_remark text,
  p_remark_type text default 'consultation', p_survey_id uuid default null)
returns uuid language plpgsql security definer set search_path to 'public' as $function$
declare v_id uuid;
begin
  if p_customer_id is null then raise exception 'A customer is required'; end if;
  if coalesce(trim(p_remark),'') = '' then raise exception 'The remark cannot be empty'; end if;
  insert into public.customer_remarks (customer_id, survey_id, remark, remark_type, created_by)
  values (p_customer_id, p_survey_id, trim(p_remark),
          coalesce(nullif(trim(p_remark_type),''),'consultation'), auth.uid())
  returning id into v_id;
  return v_id;
end $function$;

-- ---------------------------------------------------------------------
-- 3. Start or update a consultant survey for an existing customer.
--    Copies the customer's details so the consultant does not retype them.
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
declare c public.customers%rowtype; v_id uuid; v_no text;
begin
  select * into c from public.customers where id = p_customer_id;
  if not found then raise exception 'Customer not found'; end if;

  select id into v_id from public.health_surveys where customer_id = p_customer_id;

  if v_id is null then
    v_no := 'HS-' || to_char(now(), 'YYYYMMDD') || '-' || substr(md5(random()::text), 1, 6);
    insert into public.health_surveys (
      survey_no, store_id, customer_id, source, created_by,
      full_name, phone, email, date_of_birth, occupation,
      has_medical_condition, drinks_alcohol, smokes, on_treatment, treatment_list,
      acidity_result, remarks_condition, remarks_recommendation, health_goals,
      submitted_at, reviewed_by, reviewed_at)
    values (v_no, p_store_id, p_customer_id, 'consultant', auth.uid(),
      c.full_name, c.phone, c.email, c.date_of_birth, c.occupation,
      p_has_medical_condition, p_drinks_alcohol, p_smokes, p_on_treatment, p_treatment_list,
      p_acidity_result, p_remarks_condition, p_remarks_recommendation, p_health_goals,
      now(), auth.uid(), now())
    returning id into v_id;
  else
    -- Only overwrite what was actually supplied, so a partial edit does not
    -- wipe fields the consultant left alone.
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
      store_id = coalesce(p_store_id, store_id),
      reviewed_by = auth.uid(), reviewed_at = now()
    where id = v_id;
  end if;

  perform public.write_audit_ex('health_surveys', v_id, 'consultant_survey_saved', null,
    jsonb_build_object('customer', p_customer_id), 'survey', null, p_store_id);
  return v_id;
end $function$;

-- ---------------------------------------------------------------------
-- 4. One row per customer for the Health Surveys list, whether or not they
--    have a survey yet.
-- ---------------------------------------------------------------------
create or replace function public.customer_survey_overview(
  p_query text default null, p_filter text default 'all',
  p_limit integer default 50, p_offset integer default 0)
returns table(
  customer_id uuid, full_name text, phone text, email text,
  survey_id uuid, survey_no text, source text,
  remarks_condition text, remarks_recommendation text,
  submitted_at timestamptz, reviewed_at timestamptz,
  remark_count bigint, last_remark_at timestamptz,
  total_count bigint)
language sql stable security definer set search_path to 'public' as $function$
  with base as (
    select c.id, c.full_name, c.phone, c.email,
           hs.id as survey_id, hs.survey_no, hs.source,
           hs.remarks_condition, hs.remarks_recommendation,
           hs.submitted_at, hs.reviewed_at,
           (select count(*) from public.customer_remarks r where r.customer_id = c.id) as remark_count,
           (select max(r.created_at) from public.customer_remarks r where r.customer_id = c.id) as last_remark_at
      from public.customers c
      left join public.health_surveys hs on hs.customer_id = c.id
     where c.deleted_at is null
       and (nullif(trim(coalesce(p_query,'')),'') is null
            or c.full_name ilike '%' || trim(p_query) || '%'
            or c.phone     ilike '%' || trim(p_query) || '%'
            or c.email     ilike '%' || trim(p_query) || '%'
            or hs.survey_no ilike '%' || trim(p_query) || '%')
  ),
  filtered as (
    select * from base
     where case coalesce(p_filter,'all')
             when 'with_survey' then survey_id is not null
             when 'no_survey'   then survey_id is null
             when 'with_remarks' then remark_count > 0
             else true end
  )
  select f.id, f.full_name, f.phone, f.email, f.survey_id, f.survey_no, f.source,
         f.remarks_condition, f.remarks_recommendation, f.submitted_at, f.reviewed_at,
         f.remark_count, f.last_remark_at,
         count(*) over () as total_count
    from filtered f
   order by (f.survey_id is null), coalesce(f.last_remark_at, f.submitted_at) desc nulls last, f.full_name
   limit greatest(coalesce(p_limit,50),1)
  offset greatest(coalesce(p_offset,0),0)
$function$;

notify pgrst, 'reload schema';
