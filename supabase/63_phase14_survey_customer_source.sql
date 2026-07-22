-- =====================================================================
-- ENERGIA — PHASE 14: MANDATORY CUSTOMER SOURCE + EMAIL IN HEALTH SURVEY
--
--  * Configurable customer-source options (Owner/Manager managed:
--    add / edit / reorder / activate–deactivate; used options can only be
--    soft-deactivated, never hard-deleted).
--  * New surveys: email AND source are mandatory; "Other" requires details.
--  * Existing surveys without email/source remain valid; edits can FILL
--    these fields in but can never blank them out.
--  * Source is stored twice, on purpose:
--      - health_surveys.source_label  = permanent submission snapshot
--      - customers.source_*           = current source (staff-correctable)
--    Correcting a customer's source never touches old surveys and is
--    audit-logged.
--  * The public survey exposes ONLY the option list (id/label/needs-details)
--    — never customers or affiliates. When "Affiliate/Referral" is chosen
--    the public user picks just the option; staff link the actual affiliate
--    later through the existing customer referred_by flow.
--
-- Additive + idempotent. Run AFTER 62.
-- =====================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------
-- 1. Configurable source options.
-- ---------------------------------------------------------------------
create table if not exists public.customer_source_options (
  id uuid primary key default gen_random_uuid(),
  label text not null unique,
  sort_order integer not null default 100,
  requires_details boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.customer_source_options enable row level security;
-- The PUBLIC survey needs the list, so anon may read it. It contains only
-- labels — no customer or affiliate data lives anywhere near this table.
drop policy if exists "read source options" on public.customer_source_options;
create policy "read source options" on public.customer_source_options
  for select to anon, authenticated using (true);

insert into public.customer_source_options (label, sort_order, requires_details) values
  ('TikTok', 10, false),
  ('Facebook', 20, false),
  ('Instagram', 30, false),
  ('Google', 40, false),
  ('WhatsApp', 50, false),
  ('Walk-in', 60, false),
  ('Roadshow/Event', 70, false),
  ('Friend or Family', 80, false),
  ('Existing Customer', 90, false),
  ('Affiliate/Referral', 100, false),
  ('Staff Referral', 110, false),
  ('Other', 120, true)
on conflict (label) do nothing;

-- ---------------------------------------------------------------------
-- 2. Columns: permanent snapshot on the survey, current source on the
--    customer.
-- ---------------------------------------------------------------------
alter table public.health_surveys add column if not exists source_option_id uuid references public.customer_source_options(id);
alter table public.health_surveys add column if not exists source_label text;
alter table public.health_surveys add column if not exists source_details text;

alter table public.customers add column if not exists source_option_id uuid references public.customer_source_options(id);
alter table public.customers add column if not exists source_label text;
alter table public.customers add column if not exists source_details text;
alter table public.customers add column if not exists source_updated_at timestamptz;
alter table public.customers add column if not exists source_updated_by uuid references public.profiles(id);
create index if not exists idx_customers_source on public.customers(source_option_id);

-- ---------------------------------------------------------------------
-- 3. Management (Owner/Manager only). No delete function exists; a guard
--    trigger blocks hard deletes of any option that has ever been used.
-- ---------------------------------------------------------------------
create or replace function public.upsert_customer_source_option(
  p_label text, p_sort_order integer default null,
  p_requires_details boolean default null, p_is_active boolean default null,
  p_id uuid default null
) returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if public.current_user_role() not in ('owner','manager') then
    raise exception 'Only Owners and Managers can manage customer-source options'; end if;
  if nullif(trim(p_label),'') is null then raise exception 'Label is required'; end if;

  if p_id is not null then
    update public.customer_source_options
       set label = trim(p_label),
           sort_order = coalesce(p_sort_order, sort_order),
           requires_details = coalesce(p_requires_details, requires_details),
           is_active = coalesce(p_is_active, is_active),
           updated_at = now()
     where id = p_id returning id into v_id;
    if v_id is null then raise exception 'Source option not found'; end if;
  else
    insert into public.customer_source_options (label, sort_order, requires_details, is_active)
    values (trim(p_label), coalesce(p_sort_order, 100), coalesce(p_requires_details,false), coalesce(p_is_active,true))
    on conflict (label) do update set sort_order = excluded.sort_order, updated_at = now()
    returning id into v_id;
  end if;

  perform public.write_audit('customer_source_options', v_id, 'source_option_upserted', null,
    jsonb_build_object('label', trim(p_label), 'sort_order', p_sort_order,
                       'requires_details', p_requires_details, 'is_active', p_is_active));
  return v_id;
end $$;

create or replace function public.set_customer_source_option_active(p_id uuid, p_active boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  if public.current_user_role() not in ('owner','manager') then
    raise exception 'Only Owners and Managers can manage customer-source options'; end if;
  update public.customer_source_options set is_active = p_active, updated_at = now() where id = p_id;
  if not found then raise exception 'Source option not found'; end if;
  perform public.write_audit('customer_source_options', p_id,
    case when p_active then 'source_option_activated' else 'source_option_deactivated' end, null, null);
end $$;

create or replace function public.reorder_customer_source_options(p_ids jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_i integer := 0;
begin
  if public.current_user_role() not in ('owner','manager') then
    raise exception 'Only Owners and Managers can manage customer-source options'; end if;
  for v_id in select (value#>>'{}')::uuid from jsonb_array_elements(p_ids) loop
    v_i := v_i + 10;
    update public.customer_source_options set sort_order = v_i, updated_at = now() where id = v_id;
  end loop;
  perform public.write_audit('customer_source_options', null, 'source_options_reordered', null,
    jsonb_build_object('order', p_ids));
end $$;

-- Used options must be soft-deactivated, never deleted.
create or replace function public.trg_protect_used_source_option() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if exists (select 1 from public.health_surveys where source_option_id = old.id)
     or exists (select 1 from public.customers where source_option_id = old.id) then
    raise exception 'This source option has been used — deactivate it instead of deleting it';
  end if;
  return old;
end $$;
drop trigger if exists protect_used_source_option on public.customer_source_options;
create trigger protect_used_source_option
  before delete on public.customer_source_options
  for each row execute function public.trg_protect_used_source_option();

-- ---------------------------------------------------------------------
-- 4. The list the public survey (and staff UI) reads. Anon-callable,
--    returns option data only.
-- ---------------------------------------------------------------------
create or replace function public.active_customer_source_options()
returns table (id uuid, label text, requires_details boolean, sort_order integer)
language sql stable security definer set search_path = public as $$
  select id, label, requires_details, sort_order
    from public.customer_source_options
   where is_active = true
   order by sort_order, label
$$;
grant execute on function public.active_customer_source_options() to anon;

-- ---------------------------------------------------------------------
-- 5. Guard trigger on health_surveys: mandatory fields can be filled in
--    on legacy rows, but never blanked out. New rows created through
--    submit_health_survey are fully validated there; this trigger is the
--    backstop for any future direct edit path.
-- ---------------------------------------------------------------------
create or replace function public.trg_health_survey_guard() returns trigger
language plpgsql as $$
begin
  if tg_op = 'UPDATE' then
    if nullif(trim(coalesce(new.email,'')),'') is null
       and nullif(trim(coalesce(old.email,'')),'') is not null then
      raise exception 'Email is mandatory on a health survey and cannot be removed';
    end if;
    if new.source_option_id is null and old.source_option_id is not null then
      raise exception 'Customer source is mandatory on a health survey and cannot be removed';
    end if;
    -- The submission snapshot is permanent once written.
    if old.source_option_id is not null and new.source_option_id is distinct from old.source_option_id then
      raise exception 'The survey''s source snapshot is permanent — correct the customer''s current source instead';
    end if;
    if old.source_label is not null and new.source_label is distinct from old.source_label then
      raise exception 'The survey''s source snapshot is permanent — correct the customer''s current source instead';
    end if;
  end if;
  return new;
end $$;
drop trigger if exists health_survey_guard on public.health_surveys;
create trigger health_survey_guard
  before update on public.health_surveys
  for each row execute function public.trg_health_survey_guard();

-- ---------------------------------------------------------------------
-- 6. submit_health_survey — re-issued with mandatory email + source.
--    Same signature; the payload gains source_option_id / source_details.
-- ---------------------------------------------------------------------
create or replace function public.submit_health_survey(p_token text, p_payload jsonb, p_symptoms jsonb, p_pdf_base64 text DEFAULT NULL::text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_l public.survey_links%rowtype;
  v_phone text; v_name text; v_email text; v_cust_id uuid; v_id uuid; v_no text;
  v_sym jsonb; v_sex text; v_gender customer_gender;
  v_src public.customer_source_options%rowtype;
  v_src_id uuid; v_src_details text;
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
  -- Phase 14: email is mandatory for every new survey.
  if v_email is null then raise exception 'Email is required.'; end if;
  if v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
    raise exception 'Please enter a valid email address.'; end if;
  if nullif(p_payload->>'signature_data','') is null then raise exception 'Signature is required.'; end if;

  -- Phase 14: customer source is mandatory; "details-required" options
  -- (e.g. Other) must say more. The public flow sees only the option list —
  -- an Affiliate/Referral pick is just the option; staff link the actual
  -- affiliate later.
  v_src_id := nullif(p_payload->>'source_option_id','')::uuid;
  v_src_details := nullif(trim(p_payload->>'source_details'), '');
  if v_src_id is null then raise exception 'Please tell us how you heard about us.'; end if;
  select * into v_src from public.customer_source_options where id = v_src_id and is_active = true;
  if not found then raise exception 'That source option is not available.'; end if;
  if v_src.requires_details and v_src_details is null then
    raise exception 'Please add a few details for "%".', v_src.label; end if;

  if exists (select 1 from public.customers where phone = v_phone) then
    raise exception 'DUPLICATE_PHONE'; end if;
  if exists (select 1 from public.health_surveys where phone = v_phone) then
    raise exception 'DUPLICATE_PHONE'; end if;

  v_sex := nullif(p_payload->>'sex','');
  v_gender := case when v_sex in ('male','female') then v_sex::customer_gender else null end;
  insert into public.customers (full_name, phone, email, date_of_birth, gender, occupation,
                                source_option_id, source_label, source_details, source_updated_at)
  values (v_name, v_phone, v_email,
          nullif(p_payload->>'date_of_birth','')::date, v_gender,
          nullif(trim(p_payload->>'occupation'), ''),
          v_src.id, v_src.label, v_src_details, now())
  returning id into v_cust_id;

  v_no := 'HS-' || to_char(now() at time zone 'Asia/Singapore','YYYYMMDD') || '-' || substr(gen_random_uuid()::text,1,6);

  insert into public.health_surveys (
    survey_no, store_id, survey_link_id, customer_id, event_name,
    full_name, date_of_birth, age, sex, phone, email, occupation,
    has_medical_condition, drinks_alcohol, smokes, on_treatment, treatment_list, others_text,
    consent_newsletter_email, consent_marketing_email, consent_marketing_sms, consent_marketing_phone,
    signature_data, signed_date, ip_address, device_info,
    source_option_id, source_label, source_details)
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
    nullif(p_payload->>'ip_address',''), nullif(p_payload->>'device_info',''),
    v_src.id, v_src.label, v_src_details)
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
                             'customer_source', v_src.label),
          'health_survey', v_l.store_id,
          nullif(p_payload->>'ip_address',''), nullif(p_payload->>'device_info',''));

  return jsonb_build_object('success', true, 'survey_no', v_no, 'survey_id', v_id);
end $$;

-- ---------------------------------------------------------------------
-- 7. Staff correction of a customer's CURRENT source. Old surveys keep
--    their snapshots; the change is audit-logged with before/after.
-- ---------------------------------------------------------------------
create or replace function public.set_customer_source(
  p_customer_id uuid, p_option_id uuid, p_details text default null, p_reason text default null
) returns void language plpgsql security definer set search_path = public as $$
declare v_c public.customers%rowtype; v_src public.customer_source_options%rowtype;
begin
  if public.current_user_role() is null or public.current_user_role() = 'inventory_manager' then
    raise exception 'You do not have permission to change customer sources'; end if;

  select * into v_c from public.customers where id = p_customer_id and deleted_at is null for update;
  if not found then raise exception 'Customer not found'; end if;

  select * into v_src from public.customer_source_options where id = p_option_id;
  if not found then raise exception 'Source option not found'; end if;
  if not v_src.is_active then raise exception 'That source option is deactivated'; end if;
  if v_src.requires_details and nullif(trim(coalesce(p_details,'')),'') is null then
    raise exception 'Please add a few details for "%".', v_src.label; end if;

  update public.customers
     set source_option_id = v_src.id,
         source_label = v_src.label,
         source_details = nullif(trim(coalesce(p_details,'')),''),
         source_updated_at = now(),
         source_updated_by = auth.uid()
   where id = p_customer_id;

  perform public.write_audit_ex('customers', p_customer_id, 'customer_source_changed',
    jsonb_build_object('source_label', v_c.source_label, 'source_details', v_c.source_details),
    jsonb_build_object('source_label', v_src.label, 'source_details', nullif(trim(coalesce(p_details,'')),'')),
    'customer', p_reason, null);
end $$;

-- ---------------------------------------------------------------------
-- 8. Reporting: current customer sources + survey snapshots by option.
-- ---------------------------------------------------------------------
create or replace function public.report_customer_sources(p_from date default null, p_to date default null)
returns table (source_label text, is_active boolean, customers_count bigint, surveys_count bigint)
language sql stable security definer set search_path = public as $$
  with opts as (
    select o.id, o.label, o.is_active, o.sort_order from public.customer_source_options o
  )
  select o.label,
         o.is_active,
         (select count(*) from public.customers c
           where c.source_option_id = o.id and c.deleted_at is null),
         (select count(*) from public.health_surveys s
           where s.source_option_id = o.id
             and (p_from is null or s.submitted_at::date >= p_from)
             and (p_to is null or s.submitted_at::date <= p_to))
    from opts o
   order by o.sort_order, o.label
$$;

notify pgrst, 'reload schema';
