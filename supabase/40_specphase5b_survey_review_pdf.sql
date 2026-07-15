-- =====================================================================
-- ENERGIA — NEW SPEC PHASE 5B: Staff review, acidity test, remarks, PDF
--
-- PDF DESIGN NOTE (important):
-- The PDF is generated in the browser at submission and passed INTO the
-- submit function, which stores it. It is deliberately NOT uploaded to a
-- storage bucket: that would require granting anonymous users write access
-- to storage, letting anyone with the public QR link upload arbitrary
-- files. Passing it through the existing SECURITY DEFINER function means
-- a PDF can only be written as part of a valid, duplicate-checked
-- submission — no new anonymous privileges at all.
--
-- The stored PDF is the CUSTOMER-SIGNED record: identity, declarations,
-- symptoms, consent and signature, frozen at the moment of signing. Staff
-- notes added later (acidity, health goals, remarks) are internal and do
-- not alter that signed artifact — they print via a separate consultation
-- sheet. Regenerating a consent record after the fact would defeat its
-- purpose.
--
-- Additive + idempotent. Run AFTER 39_specphase5a_health_survey.sql.
-- =====================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------
-- 1. Health Goals — the printed form's "Consultant to guide in
--    prioritizing Health Goals" box. Staff-filled, not customer-filled.
-- ---------------------------------------------------------------------
alter table public.health_surveys add column if not exists health_goals text;

-- ---------------------------------------------------------------------
-- 2. Signed PDF, kept out of the main table to keep it lean.
-- ---------------------------------------------------------------------
create table if not exists public.health_survey_pdfs (
  survey_id uuid primary key references public.health_surveys(id) on delete cascade,
  pdf_base64 text not null,
  byte_size integer,
  generated_at timestamptz not null default now()
);

alter table public.health_survey_pdfs enable row level security;
drop policy if exists "read survey pdfs" on public.health_survey_pdfs;
create policy "read survey pdfs" on public.health_survey_pdfs for select to authenticated
  using (exists (select 1 from public.health_surveys s where s.id = survey_id
    and (public.is_manager_or_above() or public.user_has_store_access(s.store_id))));
-- No anon policy: the PDF is written by the SECURITY DEFINER submit function only.

-- ---------------------------------------------------------------------
-- 3. Replace submit_health_survey with a 4-arg version that also stores
--    the signed PDF. The 3-arg version is dropped so PostgREST has no
--    ambiguous overload to resolve.
-- ---------------------------------------------------------------------
drop function if exists public.submit_health_survey(text, jsonb, jsonb);

create or replace function public.submit_health_survey(
  p_token text,
  p_payload jsonb,
  p_symptoms jsonb,
  p_pdf_base64 text default null
) returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_l public.survey_links%rowtype;
  v_phone text; v_name text; v_email text; v_cust_id uuid; v_id uuid; v_no text;
  v_sym jsonb; v_sex text; v_gender customer_gender;
begin
  select * into v_l from public.survey_links where token = p_token;
  if not found then raise exception 'This survey link is not recognised.'; end if;
  if not v_l.is_active then raise exception 'This survey link has been deactivated.'; end if;
  if v_l.expires_at is not null and v_l.expires_at < now() then
    raise exception 'This survey link has expired.'; end if;

  v_name  := nullif(trim(p_payload->>'full_name'), '');
  v_phone := nullif(trim(p_payload->>'phone'), '');
  v_email := nullif(trim(p_payload->>'email'), '');
  if v_name is null then raise exception 'Name is required.'; end if;
  if v_phone is null then raise exception 'Mobile number is required.'; end if;
  if nullif(p_payload->>'signature_data','') is null then raise exception 'Signature is required.'; end if;

  if exists (select 1 from public.customers where phone = v_phone) then
    raise exception 'DUPLICATE_PHONE'; end if;
  if exists (select 1 from public.health_surveys where phone = v_phone) then
    raise exception 'DUPLICATE_PHONE'; end if;

  v_sex := nullif(p_payload->>'sex','');
  v_gender := case when v_sex in ('male','female') then v_sex::customer_gender else null end;
  insert into public.customers (full_name, phone, email, date_of_birth, gender, occupation)
  values (v_name, v_phone, v_email,
          nullif(p_payload->>'date_of_birth','')::date, v_gender,
          nullif(trim(p_payload->>'occupation'), ''))
  returning id into v_cust_id;

  v_no := 'HS-' || to_char(now() at time zone 'Asia/Singapore','YYYYMMDD') || '-' || substr(gen_random_uuid()::text,1,6);

  insert into public.health_surveys (
    survey_no, store_id, survey_link_id, customer_id, event_name,
    full_name, date_of_birth, age, sex, phone, email, occupation,
    has_medical_condition, drinks_alcohol, smokes, on_treatment, treatment_list, others_text,
    consent_newsletter_email, consent_marketing_email, consent_marketing_sms, consent_marketing_phone,
    signature_data, signed_date, ip_address, device_info)
  values (
    v_no, v_l.store_id, v_l.id, v_cust_id, coalesce(nullif(trim(p_payload->>'event_name'),''), v_l.event_name),
    v_name, nullif(p_payload->>'date_of_birth','')::date, nullif(p_payload->>'age','')::integer,
    v_sex, v_phone, v_email, nullif(trim(p_payload->>'occupation'),''),
    (p_payload->>'has_medical_condition')::boolean, (p_payload->>'drinks_alcohol')::boolean,
    (p_payload->>'smokes')::boolean, (p_payload->>'on_treatment')::boolean,
    nullif(trim(p_payload->>'treatment_list'),''), nullif(trim(p_payload->>'others_text'),''),
    coalesce((p_payload->>'consent_newsletter_email')::boolean, false),
    coalesce((p_payload->>'consent_marketing_email')::boolean, false),
    coalesce((p_payload->>'consent_marketing_sms')::boolean, false),
    coalesce((p_payload->>'consent_marketing_phone')::boolean, false),
    p_payload->>'signature_data',
    coalesce(nullif(p_payload->>'signed_date','')::date, public.sg_today()),
    nullif(p_payload->>'ip_address',''), nullif(p_payload->>'device_info',''))
  returning id into v_id;

  if p_symptoms is not null then
    for v_sym in select * from jsonb_array_elements(p_symptoms) loop
      insert into public.health_survey_symptoms (survey_id, option_id, duration_text)
      values (v_id, (v_sym->>'option_id')::uuid, nullif(trim(v_sym->>'duration_text'),''))
      on conflict do nothing;
    end loop;
  end if;

  -- Store the signed PDF (guard against an oversized payload).
  if p_pdf_base64 is not null and length(p_pdf_base64) > 0 then
    if length(p_pdf_base64) > 8000000 then raise exception 'The signed document is too large.'; end if;
    insert into public.health_survey_pdfs (survey_id, pdf_base64, byte_size)
    values (v_id, p_pdf_base64, length(p_pdf_base64));
    update public.health_surveys set pdf_url = 'stored' where id = v_id;
  end if;

  insert into public.audit_logs (table_name, record_id, action, new_data, module, store_id, ip_address, device_info)
  values ('health_surveys', v_id, 'health_survey_submitted',
          jsonb_build_object('survey_no', v_no, 'customer_id', v_cust_id, 'source', 'public_qr',
                             'pdf_stored', (p_pdf_base64 is not null and length(coalesce(p_pdf_base64,'')) > 0)),
          'surveys', v_l.store_id, nullif(p_payload->>'ip_address',''), nullif(p_payload->>'device_info',''));

  return jsonb_build_object('success', true, 'survey_no', v_no, 'customer_created', true);
end $$;

grant execute on function public.submit_health_survey(text, jsonb, jsonb, text) to anon;

-- ---------------------------------------------------------------------
-- 4. Staff review: acidity test, health goals, remarks. Audited.
--    Staff may review surveys for stores they can access.
-- ---------------------------------------------------------------------
create or replace function public.review_health_survey(
  p_survey_id uuid,
  p_acidity text default null,
  p_health_goals text default null,
  p_condition text default null,
  p_recommendation text default null
) returns void language plpgsql security definer set search_path = public as $$
declare v_s public.health_surveys%rowtype; v_role user_role;
begin
  v_role := public.current_user_role();
  if v_role is null then raise exception 'No profile for current user'; end if;
  if v_role = 'inventory_manager' then raise exception 'You do not have access to health survey data'; end if;

  select * into v_s from public.health_surveys where id = p_survey_id;
  if not found then raise exception 'Survey not found'; end if;
  if not (public.is_manager_or_above() or public.user_has_store_access(v_s.store_id)) then
    raise exception 'You do not have access to this survey'; end if;
  if p_acidity is not null and p_acidity not in ('red','green','blue') then
    raise exception 'Acidity result must be Red, Green or Blue'; end if;

  update public.health_surveys set
    acidity_result = p_acidity,
    health_goals = nullif(trim(coalesce(p_health_goals,'')), ''),
    remarks_condition = nullif(trim(coalesce(p_condition,'')), ''),
    remarks_recommendation = nullif(trim(coalesce(p_recommendation,'')), ''),
    reviewed_by = auth.uid(),
    reviewed_at = now()
  where id = p_survey_id;

  perform public.write_audit_ex('health_surveys', p_survey_id, 'health_survey_reviewed',
    jsonb_build_object('acidity', v_s.acidity_result, 'condition', v_s.remarks_condition,
                       'recommendation', v_s.remarks_recommendation, 'health_goals', v_s.health_goals),
    jsonb_build_object('acidity', p_acidity, 'condition', p_condition,
                       'recommendation', p_recommendation, 'health_goals', p_health_goals),
    'surveys', null, v_s.store_id);
end $$;

-- ---------------------------------------------------------------------
-- 5. One call for the staff detail view: survey + symptoms + pdf flag.
-- ---------------------------------------------------------------------
create or replace function public.health_survey_detail(p_survey_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_s public.health_surveys%rowtype; v_syms jsonb;
begin
  select * into v_s from public.health_surveys where id = p_survey_id;
  if not found then return jsonb_build_object('found', false); end if;
  if public.current_user_role() = 'inventory_manager'
     or not (public.is_manager_or_above() or public.user_has_store_access(v_s.store_id)) then
    raise exception 'You do not have access to this survey'; end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'category', o.category, 'label', o.label, 'duration_text', x.duration_text)
         order by o.category, o.sort_order), '[]'::jsonb)
    into v_syms
  from public.health_survey_symptoms x
  join public.health_symptom_options o on o.id = x.option_id
  where x.survey_id = p_survey_id;

  return jsonb_build_object(
    'found', true,
    'survey', to_jsonb(v_s),
    'symptoms', v_syms,
    'has_pdf', exists (select 1 from public.health_survey_pdfs p where p.survey_id = p_survey_id),
    'reviewer', (select full_name from public.profiles where id = v_s.reviewed_by));
end $$;

notify pgrst, 'reload schema';
