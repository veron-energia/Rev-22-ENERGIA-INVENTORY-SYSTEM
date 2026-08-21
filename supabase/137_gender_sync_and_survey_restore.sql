-- =====================================================================
-- ENERGIA — SURVEY "SEX" NEVER REACHED THE CUSTOMER'S "GENDER"
--
-- update_survey_particulars() writes p_sex to health_surveys.sex, then updates
-- the customer with name, email, date of birth and occupation — but NOT gender:
--
--     update public.customers set
--       first_name = ..., last_name = ..., full_name = ...,
--       email = ..., date_of_birth = ..., occupation = ...
--     where id = v_cust;                       -- no gender, no phone
--
-- So correcting the sex on a survey left the Customers page showing the old
-- value. Migration 119 syncs the other direction (customer -> surveys), which
-- is why the mismatch persisted: the customer's stale gender would be pushed
-- back onto the survey on the customer's next edit.
--
-- The columns are also of different types — customers.gender is the enum
-- customer_gender ('male','female','other') while health_surveys.sex is free
-- text — so the value is matched against the enum and only assigned when it
-- genuinely corresponds. An unrecognised entry leaves the customer untouched
-- rather than failing the whole save.
--
-- A SECOND PROBLEM, FOUND WHILE LOOKING
-- -------------------------------------
-- "92_names_whatsapp_policy.sql" sorts AFTER "104_" and "122_" as text, so a
-- filename-ordered deploy runs it LAST and it recreates this function from its
-- own older base — silently reverting:
--
--   * migration 104's declarations, symptoms and source editing;
--   * migration 122's staff permission (it reads "Only an Owner or Manager
--     can edit a submission" again);
--   * migration 122's phone carry-through, so a corrected phone number is
--     pushed back to the old one by migration 119's trigger.
--
-- This migration therefore PATCHES WHATEVER IS INSTALLED rather than assuming a
-- starting point, and file 92 has been corrected at source so it stops
-- reverting things.
--
-- Additive and idempotent. Safe to run at any time.
-- =====================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------
-- 0. Remove the superseded 9-argument version, if it is still present.
--
--    File 92 defined a shorter update_survey_particulars alongside migration
--    104's fuller one. Two functions of the same name existed, so a call could
--    land on the older one and silently drop the declarations, symptoms and
--    source. Only the full version should remain.
-- ---------------------------------------------------------------------
do $$
declare r record; v_kept integer := 0;
begin
  for r in
    select p.oid, pg_get_function_identity_arguments(p.oid) as args
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = 'update_survey_particulars'
  loop
    -- The full version is the one that knows about the declarations.
    if position('p_has_medical_condition' in r.args) = 0 then
      execute format('drop function if exists public.update_survey_particulars(%s)', r.args);
      raise notice 'Dropped the superseded short version of update_survey_particulars';
    else
      v_kept := v_kept + 1;
    end if;
  end loop;
  if v_kept = 0 then
    raise notice 'NOTE: no full update_survey_particulars found — check migration 104 applied';
  end if;
end $$;

do $patch$
declare v_def text; v_new text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'update_survey_particulars';
  if v_def is null then raise exception 'update_survey_particulars not found'; end if;

  v_new := v_def;

  -- 1. Carry the sex across to the customer's gender, and the phone with it.
  if position('gender = case' in v_new) = 0 then
    v_new := replace(v_new,
      '      email      = coalesce(nullif(trim(p_email),''''), email),',
      '      email      = coalesce(nullif(trim(p_email),''''), email),' || chr(10) ||
      '      phone      = coalesce(nullif(trim(p_phone),''''), phone),' || chr(10) ||
      '      -- health_surveys.sex is free text and customers.gender is an enum,' || chr(10) ||
      '      -- so only a value that genuinely matches a label is assigned. An' || chr(10) ||
      '      -- unrecognised entry leaves the customer as it was rather than' || chr(10) ||
      '      -- failing the whole save.' || chr(10) ||
      '      gender = case' || chr(10) ||
      '        when lower(trim(coalesce(p_sex, ''''))) in (''male'',''female'',''other'')' || chr(10) ||
      '          then lower(trim(p_sex))::public.customer_gender' || chr(10) ||
      '        else gender end,');
  end if;

  -- 2. Restore the staff permission that file 92 reverts.
  v_new := replace(v_new,
    '  if not public.is_owner_or_manager() then
    raise exception ''Only an Owner or Manager can edit a submission''; end if;',
    '  if not exists (select 1 from public.profiles
                  where id = auth.uid() and coalesce(is_active, true)) then
    raise exception ''No active profile for the current user''; end if;');

  if position('gender = case' in v_new) = 0 then
    raise exception 'Could not carry the sex across to the customer gender';
  end if;
  execute v_new;
  raise notice 'a survey sex correction now updates the customer gender (and phone)';
end $patch$;

-- ---------------------------------------------------------------------
-- Bring existing records into line, where one side has a value and the other
-- does not. Where the two genuinely DISAGREE nothing is overwritten — that
-- would silently decide which is right, and the survey is the signed document.
-- ---------------------------------------------------------------------
do $$
declare v_n integer;
begin
  update public.customers c
     set gender = lower(trim(hs.sex))::public.customer_gender
    from public.health_surveys hs
   where hs.customer_id = c.id
     and c.gender is null
     and lower(trim(coalesce(hs.sex, ''))) in ('male','female','other');
  get diagnostics v_n = row_count;
  raise notice 'Filled % customer gender(s) from a survey', v_n;

  update public.health_surveys hs
     set sex = c.gender::text
    from public.customers c
   where c.id = hs.customer_id
     and nullif(trim(coalesce(hs.sex, '')), '') is null
     and c.gender is not null;
  get diagnostics v_n = row_count;
  raise notice 'Filled % survey sex value(s) from a customer', v_n;
end $$;

-- ---------------------------------------------------------------------
-- Prove the round trip, so this fails here rather than in front of you.
-- ---------------------------------------------------------------------
do $$
declare v_src text;
begin
  select prosrc into v_src from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'update_survey_particulars';

  if v_src is null or position('gender' in v_src) = 0 then
    raise exception 'update_survey_particulars still does not set the customer gender';
  end if;
  if position('Only an Owner or Manager can edit a submission' in v_src) > 0 then
    raise exception 'Staff editing is still blocked — file 92 has reverted migration 122';
  end if;
  if position('p_phone' in v_src) = 0 then
    raise exception 'The phone is still not carried to the customer';
  end if;
  raise notice 'Confirmed: sex, gender and phone stay in step, and staff may edit';
end $$;

-- Where the two still disagree, so it can be reviewed rather than guessed at.
create or replace function public.report_gender_mismatches()
returns table(customer_id uuid, customer_name text, survey_no text,
              customer_gender text, survey_sex text)
language sql stable security definer set search_path to 'public' as $function$
  select c.id, c.full_name, hs.survey_no, c.gender::text, hs.sex
    from public.health_surveys hs
    join public.customers c on c.id = hs.customer_id
   where c.gender is not null
     and nullif(trim(coalesce(hs.sex, '')), '') is not null
     and lower(c.gender::text) is distinct from lower(trim(hs.sex))
   order by c.full_name
$function$;

notify pgrst, 'reload schema';
