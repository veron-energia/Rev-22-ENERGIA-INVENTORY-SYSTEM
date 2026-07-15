-- =====================================================================
-- ENERGIA — NEW SPEC PHASE 5A: Health & Wellness Survey (public capture)
--
-- Modelled directly on the printed Energia "Health & Wellness Survey Form"
-- (Rev 22 Pte Ltd), not invented.
--
-- Your decisions:
--   * Public access via a per-store QR TOKEN in the URL. Anonymous users get
--     NO table access at all — they may only execute two SECURITY DEFINER
--     functions (read link info, submit). A leaked QR can add a survey; it
--     can never read anyone's health data.
--   * Duplicate phone is BLOCKED (survey is for new customers only).
--   * A customer record is created automatically on submission.
--   * Customer signature only.
--   * PDF: 5B (auto-generated at submission from then on).
--
-- 5A = schema + public form + submission + duplicate handling.
-- 5B = staff review, acidity test, remarks, PDF.
--
-- Additive + idempotent. Run AFTER 38_specphase4c_invoice_therapy_display.sql.
-- =====================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------
-- 1. Public survey links (one QR per store / event).
-- ---------------------------------------------------------------------
create table if not exists public.survey_links (
  id uuid primary key default gen_random_uuid(),
  token text not null unique,
  store_id uuid not null references public.stores(id),
  event_name text,
  is_active boolean not null default true,
  expires_at timestamptz,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now()
);
create index if not exists idx_survey_links_token on public.survey_links(token);

-- ---------------------------------------------------------------------
-- 2. Symptom catalogue — the exact tick-boxes on the printed form.
--    Kept as data (not hardcoded) so the list can grow without a migration.
-- ---------------------------------------------------------------------
create table if not exists public.health_symptom_options (
  id uuid primary key default gen_random_uuid(),
  category text not null,
  label text not null,
  sort_order integer not null default 0,
  is_active boolean not null default true,
  unique (category, label)
);

insert into public.health_symptom_options (category, label, sort_order)
select v.cat, v.lbl, v.ord from (values
  -- Pain
  ('Pain','Headache / Migraine',1), ('Pain','Stiff Neck',2), ('Pain','Shoulder Pain',3),
  ('Pain','Backache',4), ('Pain','Knee Pain',5), ('Pain','Feet Pain',6),
  ('Pain','Menstrual Cramp',7), ('Pain','Joint Pain',8), ('Pain','Trigger Finger',9),
  ('Pain','Carpal Tunnel Syndrome',10),
  -- Sleep
  ('Sleep','Difficulty Dozing Off',1), ('Sleep','Interrupted Sleep',2), ('Sleep','Wake Up Tired',3),
  ('Sleep','Wake Up Too Early',4), ('Sleep','Fatigue',5),
  -- Stress
  ('Stress','Depression',1), ('Stress','Anxiety',2), ('Stress','Forgetfulness',3),
  ('Stress','Easily Irritated',4),
  -- Immune System & Other Health Issues
  ('Immune System & Other Health Issues','Frequent Cough & Cold',1),
  ('Immune System & Other Health Issues','Allergy',2),
  ('Immune System & Other Health Issues','Hypertension',3),
  ('Immune System & Other Health Issues','Diabetes',4),
  ('Immune System & Other Health Issues','Cholesterol',5),
  ('Immune System & Other Health Issues','Uric Acid',6),
  ('Immune System & Other Health Issues','Obesity',7),
  ('Immune System & Other Health Issues','Menopause',8),
  ('Immune System & Other Health Issues','Digestive Problem',9),
  ('Immune System & Other Health Issues','Asthma',10),
  ('Immune System & Other Health Issues','Cold Hand / Cold Feet',11),
  ('Immune System & Other Health Issues','Numbness',12)
) as v(cat,lbl,ord)
where not exists (
  select 1 from public.health_symptom_options o where o.category = v.cat and o.label = v.lbl);

-- ---------------------------------------------------------------------
-- 3. Surveys.
-- ---------------------------------------------------------------------
create table if not exists public.health_surveys (
  id uuid primary key default gen_random_uuid(),
  survey_no text not null unique,
  store_id uuid not null references public.stores(id),
  survey_link_id uuid references public.survey_links(id),
  customer_id uuid references public.customers(id),
  event_name text,

  -- Identity (as printed on the form)
  full_name text not null,
  date_of_birth date,
  age integer,
  sex text check (sex in ('male','female')),
  phone text not null,
  email text,
  occupation text,

  -- Declarations
  has_medical_condition boolean,
  drinks_alcohol boolean,
  smokes boolean,
  on_treatment boolean,
  treatment_list text,
  others_text text,

  -- PDPA consent (form's Privacy Policy block)
  consent_newsletter_email boolean not null default false,
  consent_marketing_email boolean not null default false,
  consent_marketing_sms boolean not null default false,
  consent_marketing_phone boolean not null default false,

  -- Signature
  signature_data text,           -- base64 PNG drawn by the customer
  signed_date date,

  -- Staff section (Phase 5B)
  acidity_result text check (acidity_result in ('red','green','blue')),
  remarks_condition text,
  remarks_recommendation text,
  reviewed_by uuid references public.profiles(id),
  reviewed_at timestamptz,
  pdf_url text,

  submitted_at timestamptz not null default now(),
  ip_address text,
  device_info text
);
create index if not exists idx_hs_store on public.health_surveys(store_id);
create index if not exists idx_hs_phone on public.health_surveys(phone);
create index if not exists idx_hs_customer on public.health_surveys(customer_id);

create table if not exists public.health_survey_symptoms (
  id uuid primary key default gen_random_uuid(),
  survey_id uuid not null references public.health_surveys(id) on delete cascade,
  option_id uuid not null references public.health_symptom_options(id),
  duration_text text,
  unique (survey_id, option_id)
);
create index if not exists idx_hss_survey on public.health_survey_symptoms(survey_id);

-- ---------------------------------------------------------------------
-- 4. RLS. Health data is sensitive: NO anonymous read anywhere.
--    Staff see surveys for stores they can access; Owner/Manager see all.
-- ---------------------------------------------------------------------
alter table public.survey_links enable row level security;
alter table public.health_surveys enable row level security;
alter table public.health_survey_symptoms enable row level security;
alter table public.health_symptom_options enable row level security;

drop policy if exists "read survey links" on public.survey_links;
create policy "read survey links" on public.survey_links for select to authenticated
  using (public.is_manager_or_above() or public.user_has_store_access(store_id));
drop policy if exists "write survey links" on public.survey_links;
create policy "write survey links" on public.survey_links for all to authenticated
  using (public.is_owner_or_manager()) with check (public.is_owner_or_manager());

drop policy if exists "read surveys" on public.health_surveys;
create policy "read surveys" on public.health_surveys for select to authenticated
  using (public.is_manager_or_above() or public.user_has_store_access(store_id));
drop policy if exists "update surveys" on public.health_surveys;
create policy "update surveys" on public.health_surveys for update to authenticated
  using (public.is_manager_or_above() or public.user_has_store_access(store_id))
  with check (public.is_manager_or_above() or public.user_has_store_access(store_id));

drop policy if exists "read survey symptoms" on public.health_survey_symptoms;
create policy "read survey symptoms" on public.health_survey_symptoms for select to authenticated
  using (exists (select 1 from public.health_surveys s where s.id = survey_id
    and (public.is_manager_or_above() or public.user_has_store_access(s.store_id))));

-- Symptom labels are not sensitive; the public form needs them.
drop policy if exists "read symptom options" on public.health_symptom_options;
create policy "read symptom options" on public.health_symptom_options for select to public using (true);
drop policy if exists "write symptom options" on public.health_symptom_options;
create policy "write symptom options" on public.health_symptom_options for all to authenticated
  using (public.is_owner_or_manager()) with check (public.is_owner_or_manager());

-- ---------------------------------------------------------------------
-- 5. Public: what a QR token points at. No table access is granted —
--    anonymous users may only run this function.
-- ---------------------------------------------------------------------
create or replace function public.survey_link_info(p_token text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_l public.survey_links%rowtype; v_store public.stores%rowtype;
begin
  select * into v_l from public.survey_links where token = p_token;
  if not found then return jsonb_build_object('valid', false, 'reason', 'This survey link is not recognised.'); end if;
  if not v_l.is_active then return jsonb_build_object('valid', false, 'reason', 'This survey link has been deactivated.'); end if;
  if v_l.expires_at is not null and v_l.expires_at < now() then
    return jsonb_build_object('valid', false, 'reason', 'This survey link has expired.'); end if;
  select * into v_store from public.stores where id = v_l.store_id;
  return jsonb_build_object('valid', true, 'store_name', v_store.name, 'event_name', v_l.event_name);
end $$;

-- ---------------------------------------------------------------------
-- 6. Public: submit a survey. Creates the customer. Blocks duplicates.
--    SECURITY DEFINER so anonymous users never touch tables directly.
-- ---------------------------------------------------------------------
create or replace function public.submit_health_survey(
  p_token text,
  p_payload jsonb,      -- identity + declarations + consents + signature
  p_symptoms jsonb      -- [{option_id, duration_text}]
) returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_l public.survey_links%rowtype;
  v_phone text; v_name text; v_email text; v_cust_id uuid; v_id uuid; v_no text;
  v_sym jsonb; v_sex text; v_gender customer_gender;
begin
  -- Validate the link.
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

  -- Duplicate phone -> blocked. This form is for new customers only.
  if exists (select 1 from public.customers where phone = v_phone) then
    raise exception 'DUPLICATE_PHONE'; end if;
  if exists (select 1 from public.health_surveys where phone = v_phone) then
    raise exception 'DUPLICATE_PHONE'; end if;

  -- Auto-create the customer.
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

  -- Ticked symptoms + their durations.
  if p_symptoms is not null then
    for v_sym in select * from jsonb_array_elements(p_symptoms) loop
      insert into public.health_survey_symptoms (survey_id, option_id, duration_text)
      values (v_id, (v_sym->>'option_id')::uuid, nullif(trim(v_sym->>'duration_text'),''))
      on conflict do nothing;
    end loop;
  end if;

  -- Audited without auth.uid() (anonymous submission).
  insert into public.audit_logs (table_name, record_id, action, new_data, module, store_id, ip_address, device_info)
  values ('health_surveys', v_id, 'health_survey_submitted',
          jsonb_build_object('survey_no', v_no, 'customer_id', v_cust_id, 'source', 'public_qr'),
          'surveys', v_l.store_id, nullif(p_payload->>'ip_address',''), nullif(p_payload->>'device_info',''));

  return jsonb_build_object('success', true, 'survey_no', v_no, 'customer_created', true);
end $$;

-- ---------------------------------------------------------------------
-- 7. Grant ONLY these two functions to anonymous visitors.
-- ---------------------------------------------------------------------
grant execute on function public.survey_link_info(text) to anon;
grant execute on function public.submit_health_survey(text, jsonb, jsonb) to anon;
grant select on public.health_symptom_options to anon;

notify pgrst, 'reload schema';
