-- =====================================================================
-- ENERGIA — SPEC PHASE 5D: Consultant section becomes Owner/Manager only
--
-- Your decision: Staff may SEE the consultant section (acidity, health
-- goals, remarks, attachments) but may no longer add or edit anything in
-- it. Only Owner and Manager can write.
--
-- This is enforced in the DATABASE, not just the UI — hiding a button
-- does not stop anyone who can call the API. Read access is unchanged:
-- Staff still see their own store's surveys; Inventory Manager still sees
-- no health data at all.
--
-- NOTE: 'admin' is NOT included. is_owner_or_manager() = owner + manager
-- exactly, which is what you asked for — but it does mean an Admin gets
-- view-only here. Say the word if Admin should be able to edit too.
--
-- Additive + idempotent. Run AFTER 41_specphase5c_survey_attachments.sql.
-- =====================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------
-- 1. Review (acidity / health goals / remarks) -> Owner + Manager only.
-- ---------------------------------------------------------------------
create or replace function public.review_health_survey(
  p_survey_id uuid,
  p_acidity text default null,
  p_health_goals text default null,
  p_condition text default null,
  p_recommendation text default null
) returns void language plpgsql security definer set search_path = public as $$
declare v_s public.health_surveys%rowtype;
begin
  if not public.is_owner_or_manager() then
    raise exception 'Only an Owner or Manager can complete the consultant section';
  end if;

  select * into v_s from public.health_surveys where id = p_survey_id;
  if not found then raise exception 'Survey not found'; end if;
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

-- Staff could previously UPDATE health_surveys directly via RLS. Close that,
-- so the RPC above is the only write path.
drop policy if exists "update surveys" on public.health_surveys;
create policy "update surveys" on public.health_surveys for update to authenticated
  using (public.is_owner_or_manager()) with check (public.is_owner_or_manager());

-- ---------------------------------------------------------------------
-- 2. Attachments: add -> Owner + Manager only.
-- ---------------------------------------------------------------------
create or replace function public.add_survey_attachment(
  p_survey_id uuid, p_path text, p_file_name text,
  p_mime text default null, p_size integer default null, p_caption text default null
) returns uuid language plpgsql security definer set search_path = public as $$
declare v_s public.health_surveys%rowtype; v_id uuid;
begin
  if not public.is_owner_or_manager() then
    raise exception 'Only an Owner or Manager can add files to a survey';
  end if;
  select * into v_s from public.health_surveys where id = p_survey_id;
  if not found then raise exception 'Survey not found'; end if;
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
-- 3. Attachments: remove -> Owner + Manager only (no more "own uploads",
--    since Staff can no longer upload at all).
-- ---------------------------------------------------------------------
create or replace function public.delete_survey_attachment(p_id uuid)
returns text language plpgsql security definer set search_path = public as $$
declare v_a public.health_survey_attachments%rowtype; v_s public.health_surveys%rowtype;
begin
  if not public.is_owner_or_manager() then
    raise exception 'Only an Owner or Manager can remove files from a survey';
  end if;
  select * into v_a from public.health_survey_attachments where id = p_id;
  if not found then raise exception 'Attachment not found'; end if;
  select * into v_s from public.health_surveys where id = v_a.survey_id;

  delete from public.health_survey_attachments where id = p_id;
  perform public.write_audit_ex('health_survey_attachments', p_id, 'survey_attachment_removed',
    jsonb_build_object('file_name', v_a.file_name, 'survey_no', v_s.survey_no), null,
    'surveys', null, v_s.store_id);
  return v_a.storage_path;
end $$;

-- ---------------------------------------------------------------------
-- 4. Storage: uploading / deleting objects -> Owner + Manager only.
--    Reading is unchanged (store-scoped staff, never inventory_manager).
-- ---------------------------------------------------------------------
drop policy if exists "survey-attachments write" on storage.objects;
create policy "survey-attachments write" on storage.objects for insert to authenticated
  with check (bucket_id = 'survey-attachments' and public.is_owner_or_manager());

drop policy if exists "survey-attachments delete" on storage.objects;
create policy "survey-attachments delete" on storage.objects for delete to authenticated
  using (bucket_id = 'survey-attachments' and public.is_owner_or_manager());

drop policy if exists "survey-attachments update" on storage.objects;
create policy "survey-attachments update" on storage.objects for update to authenticated
  using (bucket_id = 'survey-attachments' and public.is_owner_or_manager());

notify pgrst, 'reload schema';
