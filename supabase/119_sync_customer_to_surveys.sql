-- =====================================================================
-- ENERGIA — CUSTOMER EDITS NOW FLOW BACK TO THEIR HEALTH SURVEYS
--
-- The sync only ran one way. update_survey_particulars() pushes a corrected
-- survey onto the customer record, but editing the CUSTOMER changed nothing on
-- their surveys — so a date of birth or gender corrected on the Customers page
-- still showed the old value on the survey.
--
-- Note the columns are named differently on each side: customers.gender and
-- health_surveys.sex. That is part of why they drifted.
--
-- WHAT IS SYNCED: the person's own particulars — name, contact, date of birth
-- and gender. These describe the person, so they should agree everywhere.
--
-- WHAT IS DELIBERATELY NOT SYNCED:
--   * the SOURCE — how they heard about us. That is already protected as a
--     permanent submission snapshot, and the existing guard would reject it.
--   * the DECLARATIONS and SYMPTOMS. Those are what the customer declared and
--     signed at the time; a later edit elsewhere must not rewrite them.
--   * the SIGNATURE and submission timestamp, for the same reason.
--
-- So the record of what was declared stays intact, while the details that
-- identify the person stay consistent.
--
-- Additive and idempotent. Run AFTER 118.
-- =====================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------
-- Push a customer's particulars onto their surveys.
--
-- Only fields that are actually present on the customer are pushed: a blank
-- customer field must not wipe a survey that has the value.
-- ---------------------------------------------------------------------
create or replace function public.trg_sync_customer_to_surveys()
returns trigger language plpgsql security definer set search_path to 'public' as $function$
declare v_n integer;
begin
  -- Only when something worth syncing actually changed.
  if new.date_of_birth is not distinct from old.date_of_birth
     and new.gender is not distinct from old.gender
     and new.full_name is not distinct from old.full_name
     and new.first_name is not distinct from old.first_name
     and new.last_name is not distinct from old.last_name
     and new.email is not distinct from old.email
     and new.phone is not distinct from old.phone
     and new.occupation is not distinct from old.occupation then
    return new;
  end if;

  update public.health_surveys hs set
    -- coalesce keeps the survey's value when the customer's is blank.
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
  if v_n > 0 then
    -- age follows date_of_birth by its own trigger, so it is never set here.
    perform public.write_audit_ex('customers', new.id, 'customer_synced_to_surveys', null,
      jsonb_build_object('surveys_updated', v_n,
        'date_of_birth', new.date_of_birth, 'gender', new.gender),
      'customers', null, null);
  end if;

  return new;
end $function$;

drop trigger if exists sync_customer_to_surveys on public.customers;
create trigger sync_customer_to_surveys
  after update on public.customers
  for each row execute function public.trg_sync_customer_to_surveys();

-- ---------------------------------------------------------------------
-- Bring existing records into line, where the survey is missing a value the
-- customer has. Nothing already on the survey is overwritten here: this only
-- fills gaps, so an existing disagreement is left for someone to resolve
-- deliberately rather than being silently decided in the customer's favour.
-- ---------------------------------------------------------------------
do $$
declare v_n integer;
begin
  update public.health_surveys hs
     set date_of_birth = c.date_of_birth
    from public.customers c
   where c.id = hs.customer_id
     and hs.date_of_birth is null
     and c.date_of_birth is not null;
  get diagnostics v_n = row_count;
  raise notice 'Filled % survey date(s) of birth from the customer record', v_n;

  update public.health_surveys hs
     set sex = c.gender::text
    from public.customers c
   where c.id = hs.customer_id
     and nullif(trim(coalesce(hs.sex, '')), '') is null
     and c.gender is not null;
  get diagnostics v_n = row_count;
  raise notice 'Filled % survey gender(s) from the customer record', v_n;
end $$;

-- ---------------------------------------------------------------------
-- Where the two still disagree, so it can be reviewed rather than guessed at.
-- ---------------------------------------------------------------------
create or replace function public.report_customer_survey_mismatches()
returns table(customer_id uuid, customer_name text, survey_no text,
              field text, customer_value text, survey_value text)
language sql stable security definer set search_path to 'public' as $function$
  select c.id, c.full_name, hs.survey_no, 'Date of birth',
         c.date_of_birth::text, hs.date_of_birth::text
    from public.health_surveys hs
    join public.customers c on c.id = hs.customer_id
   where c.date_of_birth is distinct from hs.date_of_birth
     and c.date_of_birth is not null and hs.date_of_birth is not null
  union all
  select c.id, c.full_name, hs.survey_no, 'Gender',
         c.gender::text, hs.sex
    from public.health_surveys hs
    join public.customers c on c.id = hs.customer_id
   where lower(trim(coalesce(c.gender::text, ''))) is distinct from lower(trim(coalesce(hs.sex, '')))
     and c.gender is not null
     and nullif(trim(coalesce(hs.sex, '')), '') is not null
   order by 2, 4
$function$;

notify pgrst, 'reload schema';
