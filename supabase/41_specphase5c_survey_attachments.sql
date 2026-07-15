-- =====================================================================
-- ENERGIA — SPEC PHASE 5C: Consultant attachments (files / images)
--
-- SECURITY NOTE — why this bucket is different from 'store-assets':
-- 'store-assets' is PUBLIC because store logos must render inside a
-- printed invoice via a plain <img> tag. These attachments hang off a
-- health record, so the bucket is PRIVATE: files are reachable only via
-- short-lived signed URLs, and only by staff who can already see that
-- survey's store. Inventory Manager is excluded from health data here as
-- everywhere else.
--
-- Store scoping is enforced from the object PATH: {store_id}/{survey_id}/{file}
-- so a staff member cannot read another store's attachment even with a
-- direct path.
--
-- Additive + idempotent. Run AFTER 40_specphase5b_survey_review_pdf.sql.
-- =====================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------
-- 1. Attachment records.
-- ---------------------------------------------------------------------
create table if not exists public.health_survey_attachments (
  id uuid primary key default gen_random_uuid(),
  survey_id uuid not null references public.health_surveys(id) on delete cascade,
  storage_path text not null unique,
  file_name text not null,
  mime_type text,
  byte_size integer,
  caption text,
  uploaded_by uuid references public.profiles(id),
  uploaded_at timestamptz not null default now()
);
create index if not exists idx_hsa_survey on public.health_survey_attachments(survey_id);

alter table public.health_survey_attachments enable row level security;

drop policy if exists "read survey attachments" on public.health_survey_attachments;
create policy "read survey attachments" on public.health_survey_attachments for select to authenticated
  using (
    public.current_user_role() <> 'inventory_manager'
    and exists (select 1 from public.health_surveys s where s.id = survey_id
      and (public.is_manager_or_above() or public.user_has_store_access(s.store_id))));

-- ---------------------------------------------------------------------
-- 2. Private bucket. NOTE: public = false (unlike store-assets).
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('survey-attachments', 'survey-attachments', false)
on conflict (id) do update set public = false;

-- Resolve the store from the object path safely (never raises on a bad path).
create or replace function public.survey_attachment_store(p_name text)
returns uuid language plpgsql immutable as $$
declare v text;
begin
  v := (storage.foldername(p_name))[1];
  if v is null or v = '' then return null; end if;
  return v::uuid;
exception when others then return null;
end $$;

-- Read: staff who can access that store. No anon. No inventory_manager.
drop policy if exists "survey-attachments read" on storage.objects;
create policy "survey-attachments read" on storage.objects for select to authenticated
  using (bucket_id = 'survey-attachments'
    and public.current_user_role() <> 'inventory_manager'
    and (public.is_manager_or_above()
         or public.user_has_store_access(public.survey_attachment_store(name))));

-- Upload: same rule.
drop policy if exists "survey-attachments write" on storage.objects;
create policy "survey-attachments write" on storage.objects for insert to authenticated
  with check (bucket_id = 'survey-attachments'
    and public.current_user_role() <> 'inventory_manager'
    and (public.is_manager_or_above()
         or public.user_has_store_access(public.survey_attachment_store(name))));

-- Delete: Owner/Manager anything; anyone else only what they uploaded.
drop policy if exists "survey-attachments delete" on storage.objects;
create policy "survey-attachments delete" on storage.objects for delete to authenticated
  using (bucket_id = 'survey-attachments'
    and (public.is_owner_or_manager() or owner = auth.uid()));

-- ---------------------------------------------------------------------
-- 3. Record an attachment (after the file lands in storage). Audited.
-- ---------------------------------------------------------------------
create or replace function public.add_survey_attachment(
  p_survey_id uuid, p_path text, p_file_name text,
  p_mime text default null, p_size integer default null, p_caption text default null
) returns uuid language plpgsql security definer set search_path = public as $$
declare v_s public.health_surveys%rowtype; v_id uuid;
begin
  if public.current_user_role() = 'inventory_manager' then
    raise exception 'You do not have access to health survey data'; end if;
  select * into v_s from public.health_surveys where id = p_survey_id;
  if not found then raise exception 'Survey not found'; end if;
  if not (public.is_manager_or_above() or public.user_has_store_access(v_s.store_id)) then
    raise exception 'You do not have access to this survey'; end if;
  if coalesce(p_size, 0) > 10485760 then raise exception 'Files must be 10 MB or smaller.'; end if;

  insert into public.health_survey_attachments
    (survey_id, storage_path, file_name, mime_type, byte_size, caption, uploaded_by)
  values (p_survey_id, p_path, p_file_name, p_mime, p_size, nullif(trim(coalesce(p_caption,'')),''), auth.uid())
  returning id into v_id;

  perform public.write_audit_ex('health_survey_attachments', v_id, 'survey_attachment_added',
    null, jsonb_build_object('survey_no', v_s.survey_no, 'file_name', p_file_name, 'bytes', p_size),
    'surveys', null, v_s.store_id);
  return v_id;
end $$;

-- ---------------------------------------------------------------------
-- 4. Remove an attachment record; returns the path so the caller can
--    delete the object. Owner/Manager anything; others their own.
-- ---------------------------------------------------------------------
create or replace function public.delete_survey_attachment(p_id uuid)
returns text language plpgsql security definer set search_path = public as $$
declare v_a public.health_survey_attachments%rowtype; v_s public.health_surveys%rowtype;
begin
  select * into v_a from public.health_survey_attachments where id = p_id;
  if not found then raise exception 'Attachment not found'; end if;
  select * into v_s from public.health_surveys where id = v_a.survey_id;

  if public.current_user_role() = 'inventory_manager' then
    raise exception 'You do not have access to health survey data'; end if;
  if not (public.is_manager_or_above() or public.user_has_store_access(v_s.store_id)) then
    raise exception 'You do not have access to this survey'; end if;
  if not (public.is_owner_or_manager() or v_a.uploaded_by = auth.uid()) then
    raise exception 'You can only remove attachments you uploaded'; end if;

  delete from public.health_survey_attachments where id = p_id;
  perform public.write_audit_ex('health_survey_attachments', p_id, 'survey_attachment_removed',
    jsonb_build_object('file_name', v_a.file_name, 'survey_no', v_s.survey_no), null,
    'surveys', null, v_s.store_id);
  return v_a.storage_path;
end $$;

-- ---------------------------------------------------------------------
-- 5. Include attachments in the staff detail payload.
-- ---------------------------------------------------------------------
create or replace function public.health_survey_detail(p_survey_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_s public.health_surveys%rowtype; v_syms jsonb; v_atts jsonb;
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

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', a.id, 'storage_path', a.storage_path, 'file_name', a.file_name,
           'mime_type', a.mime_type, 'byte_size', a.byte_size, 'caption', a.caption,
           'uploaded_at', a.uploaded_at, 'uploaded_by', a.uploaded_by,
           'uploaded_by_name', (select full_name from public.profiles p where p.id = a.uploaded_by))
         order by a.uploaded_at), '[]'::jsonb)
    into v_atts
  from public.health_survey_attachments a where a.survey_id = p_survey_id;

  return jsonb_build_object(
    'found', true,
    'survey', to_jsonb(v_s),
    'symptoms', v_syms,
    'attachments', v_atts,
    'has_pdf', exists (select 1 from public.health_survey_pdfs p where p.survey_id = p_survey_id),
    'reviewer', (select full_name from public.profiles where id = v_s.reviewed_by));
end $$;

notify pgrst, 'reload schema';
