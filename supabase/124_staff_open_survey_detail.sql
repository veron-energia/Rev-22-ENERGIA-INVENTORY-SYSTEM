-- =====================================================================
-- ENERGIA — "NOT FOUND" WHEN STAFF OPENED A SURVEY
--
-- Migration 123 opened the RLS read policy, so staff could see every survey in
-- the LIST. Opening one still failed, because the detail modal does not read
-- the table — it calls health_survey_detail(), which carries its OWN copy of
-- the store-access check:
--
--     if public.current_user_role() = 'inventory_manager'
--        or not (public.is_manager_or_above() or public.user_has_store_access(v_s.store_id)) then
--       raise exception 'You do not have access to this survey';
--
-- It is SECURITY DEFINER, so relaxing the table policy did nothing for it. A
-- staff member opening a survey from any store they are not assigned to got an
-- error the screen reported as "not found".
--
-- Reproduced before fixing: a staff member assigned to store A, opening a
-- survey taken at store B, raised "You do not have access to this survey".
--
-- The check is now aligned with the read policy: any signed-in, active user may
-- open a survey, matching the list they can already see. Inventory managers
-- remain excluded, as before — they have no reason to read customer health
-- declarations.
--
-- WHAT STAYS OWNER/MANAGER-ONLY, deliberately and unchanged:
--   * review_health_survey() — recording a consultation review;
--   * add_consultant_note() — adding a consultant note;
--   * the SOURCE SNAPSHOT on an edit;
--   * direct writes to health_surveys.
--
-- So staff can view a submission and correct the particulars, but the clinical
-- review and notes remain with those responsible for them.
--
-- Additive and idempotent. Run AFTER 123.
-- =====================================================================

set check_function_bodies = off;

do $patch$
declare v_def text; v_new text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'health_survey_detail';
  if v_def is null then raise exception 'health_survey_detail not found'; end if;
  if position('No active profile' in v_def) > 0 then
    raise notice 'health_survey_detail already allows staff'; return;
  end if;

  v_new := replace(v_def,
    '  if public.current_user_role() = ''inventory_manager''
     or not (public.is_manager_or_above() or public.user_has_store_access(v_s.store_id)) then
    raise exception ''You do not have access to this survey''; end if;',
    '  -- Any signed-in, active user may open a survey, matching the list they
  -- can already see. Inventory managers stay excluded: stock is their remit,
  -- not customer health declarations.
  if public.current_user_role() = ''inventory_manager'' then
    raise exception ''You do not have access to this survey''; end if;
  if not exists (select 1 from public.profiles
                  where id = auth.uid() and coalesce(is_active, true)) then
    raise exception ''No active profile for the current user''; end if;');

  if position('No active profile' in v_new) = 0 then
    raise exception 'Could not widen health_survey_detail';
  end if;
  execute v_new;
  raise notice 'staff may now open a survey from any store';
end $patch$;

-- ---------------------------------------------------------------------
-- Confirm the clinical actions are still restricted. If either of these ever
-- stops being Owner/Manager-only, this migration should fail rather than let
-- the change pass unnoticed.
-- ---------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                  where n.nspname='public' and p.proname='review_health_survey'
                    and p.prosrc like '%is_owner_or_manager%') then
    raise exception 'review_health_survey is no longer Owner/Manager-only';
  end if;
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                  where n.nspname='public' and p.proname='add_consultant_note'
                    and p.prosrc like '%is_owner_or_manager%') then
    raise exception 'add_consultant_note is no longer Owner/Manager-only';
  end if;
  raise notice 'Confirmed: reviews and consultant notes remain Owner/Manager-only';
end $$;

notify pgrst, 'reload schema';
