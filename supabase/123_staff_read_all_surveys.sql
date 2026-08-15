-- =====================================================================
-- ENERGIA — STAFF COULD ONLY SEE SURVEYS FROM THEIR OWN STORE
--
-- Migration 122 let staff EDIT a survey, but they still could not see most of
-- them, because the read policy is store-scoped:
--
--     read surveys | SELECT | (is_manager_or_above() OR user_has_store_access(store_id))
--
-- user_has_store_access() requires an exact store assignment, so a staff member
-- saw only surveys taken at a store they are assigned to. Verified: of three
-- surveys — one at their store, one at another store, one with no store — a
-- staff member saw exactly ONE.
--
-- Two ways that leaves surveys invisible:
--   * a submission from another store or a roadshow link;
--   * a survey with NO store at all, which the column permits.
--
-- Reading is opened to any signed-in user, matching how the same personal
-- details are already treated elsewhere: public.customers and
-- public.consultant_notes are both readable by any authenticated user, and a
-- survey is about a customer the whole team serves.
--
-- WHAT DOES NOT CHANGE:
--   * WRITING. The update policy stays Owner/Manager-only, and edits continue
--     to go through update_survey_particulars(), which validates its input and
--     records who made the change. Migration 105 established that widening
--     table-level writes is the thing to avoid.
--   * The SOURCE SNAPSHOT stays Owner/Manager-only.
--   * survey_links stay store-scoped: those create QR codes for a specific
--     store, which is genuinely a per-store concern.
--
-- Additive and idempotent. Run AFTER 122.
-- =====================================================================

set check_function_bodies = off;

drop policy if exists "read surveys" on public.health_surveys;
create policy "read surveys" on public.health_surveys
  for select to authenticated using (true);

-- The symptom rows behind a survey must be readable too, or the detail view
-- shows a submission with an empty checklist.
do $$
begin
  if exists (select 1 from pg_policies where schemaname='public'
              and tablename='health_survey_symptoms' and cmd='SELECT') then
    drop policy if exists "read survey symptoms" on public.health_survey_symptoms;
  end if;
  if not exists (select 1 from pg_policies where schemaname='public'
                  and tablename='health_survey_symptoms' and policyname='read survey symptoms') then
    create policy "read survey symptoms" on public.health_survey_symptoms
      for select to authenticated using (true);
  end if;
exception when undefined_table then
  raise notice 'health_survey_symptoms not present — skipped';
end $$;

-- Confirm the write side is untouched: this migration widens READING only.
do $$
declare v_qual text;
begin
  select qual into v_qual from pg_policies
   where schemaname='public' and tablename='health_surveys' and cmd='UPDATE';
  if v_qual is null or position('is_owner_or_manager' in v_qual) = 0 then
    raise exception 'The survey update policy is no longer Owner/Manager-only — check this';
  end if;
  raise notice 'Confirmed: direct writes to health_surveys remain Owner/Manager-only';
end $$;

notify pgrst, 'reload schema';
