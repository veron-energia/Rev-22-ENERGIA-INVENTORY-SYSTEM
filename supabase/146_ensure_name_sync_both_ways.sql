-- =====================================================================
-- ENERGIA — MAKE THE NAME SYNC SELF-SUFFICIENT
--
-- Names not syncing in EITHER direction points at something structural rather
-- than at the logic, and the most likely candidate is simply that the trigger
-- carrying customer -> survey is not installed. It is created only by
-- migrations 119 and 138; if neither was applied, that direction cannot work at
-- all, however correct everything else is.
--
-- Rather than depend on those having run, this migration installs what the sync
-- needs, on its own:
--
--   * the customer -> survey trigger function and its trigger;
--   * a check that the survey -> customer path is present (that lives inside
--     update_survey_particulars, which migration 104 provides);
--   * a one-time reconciliation for records that have drifted apart.
--
-- It does NOT overwrite anything that is already correct: the function is
-- replaced with the same known-good body, and the trigger is recreated to the
-- same definition.
--
-- Additive and idempotent.
-- =====================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------
-- 1. Customer -> their surveys.
-- ---------------------------------------------------------------------
create or replace function public.trg_sync_customer_to_surveys()
returns trigger language plpgsql security definer set search_path to 'public' as $function$
declare v_n integer;
begin
  -- Only when something worth carrying has actually changed.
  if new.date_of_birth is not distinct from old.date_of_birth
     and new.gender     is not distinct from old.gender
     and new.full_name  is not distinct from old.full_name
     and new.first_name is not distinct from old.first_name
     and new.last_name  is not distinct from old.last_name
     and new.email      is not distinct from old.email
     and new.phone      is not distinct from old.phone
     and new.occupation is not distinct from old.occupation then
    return new;
  end if;

  update public.health_surveys hs set
    -- coalesce keeps the survey's own value where the customer's is blank, so
    -- a half-filled customer record never wipes a completed submission.
    date_of_birth = coalesce(new.date_of_birth, hs.date_of_birth),
    sex           = coalesce(nullif(trim(coalesce(new.gender::text, '')), ''), hs.sex),
    first_name    = coalesce(nullif(trim(coalesce(new.first_name, '')), ''), hs.first_name),
    last_name     = case
                      when nullif(trim(coalesce(new.last_name, '')), '') is not null
                        then new.last_name else hs.last_name end,
    full_name     = coalesce(nullif(trim(coalesce(new.full_name, '')), ''), hs.full_name),
    email         = coalesce(nullif(trim(coalesce(new.email, '')), ''), hs.email),
    phone         = coalesce(nullif(trim(coalesce(new.phone, '')), ''), hs.phone),
    occupation    = coalesce(nullif(trim(coalesce(new.occupation, '')), ''), hs.occupation)
  where hs.customer_id = new.id;

  get diagnostics v_n = row_count;
  return new;
end $function$;

drop trigger if exists sync_customer_to_surveys on public.customers;
create trigger sync_customer_to_surveys
  after insert or update on public.customers
  for each row execute function public.trg_sync_customer_to_surveys();

-- ---------------------------------------------------------------------
-- 2. Is the other direction present at all?
--
--    Survey -> customer happens inside update_survey_particulars(). If that is
--    missing, or is the older short version that cannot carry the parts, say so
--    plainly rather than leave it to be discovered.
-- ---------------------------------------------------------------------
do $$
declare v_full integer; v_any integer;
begin
  select count(*) into v_any
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'update_survey_particulars';

  select count(*) into v_full
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'update_survey_particulars'
     and p.prosrc like '%update public.customers%';

  if v_any = 0 then
    raise exception 'update_survey_particulars is missing — apply migration 104';
  end if;
  if v_full = 0 then
    raise exception 'update_survey_particulars does not update the customer — apply migration 104';
  end if;
  if v_any > 1 then
    raise notice 'NOTE: % versions of update_survey_particulars exist. A call can land on the wrong one.', v_any;
  end if;
  raise notice 'Confirmed: survey -> customer is present';
end $$;

-- ---------------------------------------------------------------------
-- 3. Reconcile what has already drifted.
--
--    Only where one side is BLANK and the other has a value. Where the two hold
--    DIFFERENT names, nothing is overwritten — that would silently decide which
--    is right, and the survey is the signed document.
-- ---------------------------------------------------------------------
do $$
declare v_n integer;
begin
  update public.health_surveys hs
     set first_name = c.first_name,
         last_name  = coalesce(hs.last_name, c.last_name),
         full_name  = coalesce(nullif(trim(coalesce(hs.full_name, '')), ''), c.full_name)
    from public.customers c
   where c.id = hs.customer_id
     and nullif(trim(coalesce(hs.first_name, '')), '') is null
     and nullif(trim(coalesce(c.first_name, '')), '') is not null;
  get diagnostics v_n = row_count;
  raise notice 'Filled % survey name(s) from the customer', v_n;

  update public.customers c
     set first_name = hs.first_name,
         last_name  = coalesce(c.last_name, hs.last_name)
    from public.health_surveys hs
   where hs.customer_id = c.id
     and nullif(trim(coalesce(c.first_name, '')), '') is null
     and nullif(trim(coalesce(hs.first_name, '')), '') is not null;
  get diagnostics v_n = row_count;
  raise notice 'Filled % customer name(s) from a survey', v_n;
end $$;

-- ---------------------------------------------------------------------
-- 4. Where the two still hold different names, so it can be seen.
-- ---------------------------------------------------------------------
create or replace function public.report_name_mismatches()
returns table(customer_id uuid, survey_no text,
              customer_name text, survey_name text)
language sql stable security definer set search_path to 'public' as $function$
  select c.id, hs.survey_no,
         coalesce(c.first_name, '-') || ' / ' || coalesce(c.last_name, '-'),
         coalesce(hs.first_name, '-') || ' / ' || coalesce(hs.last_name, '-')
    from public.health_surveys hs
    join public.customers c on c.id = hs.customer_id
   where coalesce(c.first_name, '') is distinct from coalesce(hs.first_name, '')
      or coalesce(c.last_name, '')  is distinct from coalesce(hs.last_name, '')
   order by c.full_name
$function$;

do $$
declare v_n integer;
begin
  select count(*) into v_n from public.report_name_mismatches();
  if v_n > 0 then
    raise notice 'NOTE: % pair(s) still hold different names — see report_name_mismatches()', v_n;
  else
    raise notice 'Confirmed: every customer and survey pair now agrees';
  end if;
end $$;

notify pgrst, 'reload schema';
