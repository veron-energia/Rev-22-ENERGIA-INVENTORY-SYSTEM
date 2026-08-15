-- =====================================================================
-- ENERGIA — STAFF MAY VIEW AND EDIT A HEALTH SURVEY
--
-- Reading was already open to staff at the survey's store:
--
--     read surveys | SELECT | (is_manager_or_above() OR user_has_store_access(store_id))
--
-- Editing was not. Two things blocked it:
--
--   1. update_survey_particulars() refused anyone who is not an Owner or
--      Manager;
--   2. the "update surveys" RLS policy is is_owner_or_manager().
--
-- Staff are the people sitting with the customer when a phone number or date of
-- birth turns out to be wrong, so they should be able to correct it.
--
-- WHAT STAYS RESTRICTED, deliberately:
--
--   * the SOURCE SNAPSHOT — how the customer heard about us. Already
--     Owner/Manager-only, and left that way: it feeds attribution reporting,
--     and the existing guard enforces it.
--   * the SIGNATURE and submitted_at, which are never editable by anyone.
--   * DELETING a survey.
--
-- The RLS policy is NOT widened. Editing continues to go only through
-- update_survey_particulars(), which is SECURITY DEFINER, validates its input
-- and writes an audit entry naming who made the change. Opening the table to
-- direct UPDATE would allow any column to be rewritten from the browser, which
-- migration 105 established is exactly what we do not want.
--
-- Additive and idempotent. Run AFTER 121.
-- =====================================================================

set check_function_bodies = off;

do $patch$
declare v_def text; v_new text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'update_survey_particulars';
  if v_def is null then raise exception 'update_survey_particulars not found'; end if;
  if position('No active profile' in v_def) > 0 then
    raise notice 'update_survey_particulars already allows staff'; return;
  end if;

  -- Any signed-in, active user may correct a submission. The role is captured
  -- so the audit entry says who did it and in what capacity.
  v_new := replace(v_def,
    '  if not public.is_owner_or_manager() then
    raise exception ''Only an Owner or Manager can edit a submission''; end if;',
    '  if not exists (select 1 from public.profiles
                  where id = auth.uid() and coalesce(is_active, true)) then
    raise exception ''No active profile for the current user''; end if;');

  if position('No active profile' in v_new) = 0 then
    raise exception 'Could not widen update_survey_particulars';
  end if;
  execute v_new;
  raise notice 'staff may now correct a health survey submission';
end $patch$;

-- ---------------------------------------------------------------------
-- The source snapshot stays Owner/Manager-only.
--
-- The guard already enforces this, but it is worth restating: with staff now
-- able to edit, that check is doing real work rather than being belt-and-braces
-- behind a function that already refused them.
-- ---------------------------------------------------------------------
do $$
begin
  if not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = 'trg_health_survey_guard'
       and p.prosrc like '%is_owner_or_manager()%'
  ) then
    raise exception 'The survey guard no longer protects the source snapshot — check migration 104';
  end if;
  raise notice 'Confirmed: the source snapshot remains Owner/Manager-only';
end $$;

notify pgrst, 'reload schema';

-- ---------------------------------------------------------------------
-- A PHONE CORRECTION WAS BEING UNDONE.
--
-- update_survey_particulars() writes the phone to the survey but NOT to the
-- customer. Since migration 119 the customer now syncs back to its surveys, so
-- the sequence was:
--
--   1. the survey's phone is corrected to the new number;
--   2. the customer row is updated (name, email, dob… but not phone);
--   3. migration 119's trigger fires and pushes the customer's OLD phone back
--      onto the survey.
--
-- The correction was silently reverted, with no error. Found because a staff
-- edit appeared to save the name but not the phone.
--
-- The fix carries the phone through to the customer as well, so both records
-- hold the corrected number and the sync has nothing stale to push back.
-- ---------------------------------------------------------------------
do $patch$
declare v_def text; v_new text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'update_survey_particulars';
  if v_def is null then raise exception 'update_survey_particulars not found'; end if;
  if position('phone      = coalesce(nullif(trim(p_phone)' in v_def) > 0 then
    raise notice 'the customer update already carries the phone'; return;
  end if;

  v_new := replace(v_def,
    '      email      = coalesce(nullif(trim(p_email),''''), email),
      date_of_birth = coalesce(p_date_of_birth, date_of_birth),',
    '      email      = coalesce(nullif(trim(p_email),''''), email),
      phone      = coalesce(nullif(trim(p_phone),''''), phone),
      date_of_birth = coalesce(p_date_of_birth, date_of_birth),');

  if position('phone      = coalesce(nullif(trim(p_phone)' in v_new) = 0 then
    raise exception 'Could not carry the phone through to the customer';
  end if;
  execute v_new;
  raise notice 'a corrected phone number now reaches the customer record too';
end $patch$;

notify pgrst, 'reload schema';
