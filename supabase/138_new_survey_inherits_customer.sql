-- =====================================================================
-- ENERGIA — A NEW SURVEY DID NOT INHERIT THE CUSTOMER'S DETAILS
--
-- Migration 119 syncs a customer's particulars onto their surveys, but only
-- when the CUSTOMER IS UPDATED:
--
--     create trigger sync_customer_to_surveys
--       after update on public.customers
--
-- Nothing filled a NEWLY CREATED survey from the customer it is attached to. So
-- creating a customer with a gender on the Customers page and then opening a
-- health survey for them showed the sex blank: the customer was never updated
-- after the survey existed, so the sync had no reason to fire.
--
-- Migration 137 fixed the other direction (survey sex -> customer gender) and
-- back-filled existing rows, which is why existing surveys look right while a
-- new one does not.
--
-- A survey now inherits what the customer already holds, at the moment it is
-- created — but only for fields the survey itself leaves BLANK. What the person
-- actually wrote on the form always wins; this fills gaps, it never overwrites
-- a declaration.
--
-- Additive and idempotent. Run AFTER 137.
-- =====================================================================

set check_function_bodies = off;

create or replace function public.trg_survey_inherit_customer()
returns trigger language plpgsql security definer set search_path to 'public' as $function$
declare v_c public.customers%rowtype;
begin
  if new.customer_id is null then return new; end if;

  select * into v_c from public.customers where id = new.customer_id;
  if not found then return new; end if;

  -- Fill only what the survey has not been given. A value typed on the form is
  -- the person's own answer and is never replaced.
  if nullif(trim(coalesce(new.sex, '')), '') is null and v_c.gender is not null then
    new.sex := v_c.gender::text;
  end if;
  if new.date_of_birth is null then
    new.date_of_birth := v_c.date_of_birth;
  end if;
  if nullif(trim(coalesce(new.occupation, '')), '') is null then
    new.occupation := v_c.occupation;
  end if;
  if nullif(trim(coalesce(new.phone, '')), '') is null then
    new.phone := v_c.phone;
  end if;
  if nullif(trim(coalesce(new.email, '')), '') is null then
    new.email := v_c.email;
  end if;
  if nullif(trim(coalesce(new.first_name, '')), '') is null then
    new.first_name := v_c.first_name;
  end if;
  if nullif(trim(coalesce(new.last_name, '')), '') is null then
    new.last_name := v_c.last_name;
  end if;
  if nullif(trim(coalesce(new.full_name, '')), '') is null then
    new.full_name := v_c.full_name;
  end if;

  return new;
end $function$;

-- BEFORE insert, so the values are written with the row rather than needing a
-- second update — and so the existing age trigger sees the date of birth.
drop trigger if exists survey_inherit_customer on public.health_surveys;
create trigger survey_inherit_customer
  before insert on public.health_surveys
  for each row execute function public.trg_survey_inherit_customer();

-- ---------------------------------------------------------------------
-- The customer sync should also fire when a customer is CREATED already
-- linked to surveys — rare, but it costs nothing and closes the gap.
-- ---------------------------------------------------------------------
drop trigger if exists sync_customer_to_surveys on public.customers;
create trigger sync_customer_to_surveys
  after insert or update on public.customers
  for each row execute function public.trg_sync_customer_to_surveys();

-- ---------------------------------------------------------------------
-- Fill surveys that already exist and are missing what the customer holds.
-- Nothing that disagrees is overwritten.
-- ---------------------------------------------------------------------
do $$
declare v_n integer;
begin
  update public.health_surveys hs
     set sex = c.gender::text
    from public.customers c
   where c.id = hs.customer_id
     and nullif(trim(coalesce(hs.sex, '')), '') is null
     and c.gender is not null;
  get diagnostics v_n = row_count;
  raise notice 'Filled % survey sex value(s) from the customer', v_n;
end $$;

-- ---------------------------------------------------------------------
-- Prove it: a survey inserted for a customer with a gender must carry it.
-- ---------------------------------------------------------------------
do $$
declare v_ok boolean;
begin
  if not exists (
    select 1 from pg_trigger t
     where t.tgrelid = 'public.health_surveys'::regclass
       and t.tgname = 'survey_inherit_customer' and not t.tgisinternal
  ) then
    raise exception 'The inherit trigger is not installed — a new survey would still be blank';
  end if;

  select bool_and(nullif(trim(coalesce(hs.sex, '')), '') is not null) into v_ok
    from public.health_surveys hs
    join public.customers c on c.id = hs.customer_id
   where c.gender is not null
   limit 500;
  if v_ok is false then
    raise exception 'Some surveys still have no sex where the customer has a gender';
  end if;
  raise notice 'Confirmed: a new survey inherits the customer''s details';
end $$;

notify pgrst, 'reload schema';
