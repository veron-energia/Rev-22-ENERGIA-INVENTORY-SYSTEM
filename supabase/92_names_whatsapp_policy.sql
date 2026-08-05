-- =====================================================================
-- ENERGIA — FIRST/LAST NAMES, SHOP WHATSAPP, STORE POLICY TEXT
--
--   1. Customers and health surveys gain first_name / last_name. Existing
--      names are split on the first space; a single word becomes the first
--      name, as requested.
--
--      full_name is KEPT and kept in sync by trigger. It is read by search,
--      invoices, commissions, reports and a dozen functions, so removing it
--      would be a far larger and riskier change than this warrants. Writing
--      either form keeps the other correct.
--
--   2. Stores gain whatsapp_phone (additional to phone) and policy_text for
--      the cancellation / exchange / refund wording printed on invoices.
--
-- Additive and idempotent. Run AFTER 91.
-- =====================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------
-- 1. The columns.
-- ---------------------------------------------------------------------
alter table public.customers      add column if not exists first_name text;
alter table public.customers      add column if not exists last_name  text;
alter table public.health_surveys add column if not exists first_name text;
alter table public.health_surveys add column if not exists last_name  text;

alter table public.stores add column if not exists whatsapp_phone text;
alter table public.stores add column if not exists policy_text text;

-- ---------------------------------------------------------------------
-- 2. Splitting and joining, used by both the backfill and the triggers.
-- ---------------------------------------------------------------------
create or replace function public.split_person_name(p_full text)
returns table(first_name text, last_name text)
language sql immutable as $function$
  select
    -- Everything before the first space is the first name; a single word is
    -- entirely the first name, with no last name.
    nullif(trim(split_part(trim(coalesce(p_full,'')), ' ', 1)), ''),
    nullif(trim(substr(trim(coalesce(p_full,'')),
                       strpos(trim(coalesce(p_full,'')) || ' ', ' ') + 1)), '')
$function$;

create or replace function public.join_person_name(p_first text, p_last text)
returns text language sql immutable as $function$
  select nullif(trim(concat_ws(' ', nullif(trim(coalesce(p_first,'')),''),
                                    nullif(trim(coalesce(p_last,'')),''))), '')
$function$;

-- ---------------------------------------------------------------------
-- 3. Backfill from the names already stored.
-- ---------------------------------------------------------------------
update public.customers c
   set first_name = nullif(trim(split_part(trim(c.full_name), ' ', 1)), ''),
       last_name  = nullif(trim(substr(trim(c.full_name),
                      strpos(trim(c.full_name) || ' ', ' ') + 1)), '')
 where c.first_name is null and c.last_name is null and coalesce(c.full_name,'') <> '';

update public.health_surveys h
   set first_name = nullif(trim(split_part(trim(h.full_name), ' ', 1)), ''),
       last_name  = nullif(trim(substr(trim(h.full_name),
                      strpos(trim(h.full_name) || ' ', ' ') + 1)), '')
 where h.first_name is null and h.last_name is null and coalesce(h.full_name,'') <> '';

-- ---------------------------------------------------------------------
-- 4. Keep the two forms in agreement, whichever is written.
-- ---------------------------------------------------------------------
create or replace function public.trg_sync_person_name()
returns trigger language plpgsql as $function$
declare v_split record;
begin
  -- First/last supplied (or changed): they win, and full_name follows.
  if (tg_op = 'INSERT' and (new.first_name is not null or new.last_name is not null))
     or (tg_op = 'UPDATE' and (new.first_name is distinct from old.first_name
                            or new.last_name  is distinct from old.last_name)) then
    new.full_name := coalesce(public.join_person_name(new.first_name, new.last_name), new.full_name);

  -- Only full_name supplied or changed: split it back out.
  elsif coalesce(new.full_name,'') <> '' then
    select * into v_split from public.split_person_name(new.full_name);
    new.first_name := v_split.first_name;
    new.last_name  := v_split.last_name;
  end if;
  return new;
end $function$;

drop trigger if exists sync_customer_name on public.customers;
create trigger sync_customer_name before insert or update on public.customers
  for each row execute function public.trg_sync_person_name();

drop trigger if exists sync_survey_name on public.health_surveys;
create trigger sync_survey_name before insert or update on public.health_surveys
  for each row execute function public.trg_sync_person_name();

-- ---------------------------------------------------------------------
-- 5. Store contact and policy setters.
-- ---------------------------------------------------------------------
create or replace function public.set_store_policy_text(p_store_id uuid, p_text text)
returns void language plpgsql security definer set search_path to 'public' as $function$
begin
  if not public.is_owner_or_manager() then
    raise exception 'Only an Owner or Manager can edit the store policy'; end if;
  update public.stores set policy_text = nullif(trim(coalesce(p_text,'')),'') where id = p_store_id;
end $function$;

-- ---------------------------------------------------------------------
-- 6. How a customer is described on an invoice:
--    "First Last (Referrer, Source)". A missing referrer prints as a dash so
--    the two slots stay readable.
-- ---------------------------------------------------------------------
create or replace function public.customer_bill_to(p_customer_id uuid)
returns text language sql stable security definer set search_path to 'public' as $function$
  select case
    when c.id is null then '—'
    else coalesce(public.join_person_name(c.first_name, c.last_name), c.full_name, '—')
         || ' (' || coalesce(nullif(trim(r.full_name), ''), '—')
         || ', ' || coalesce(nullif(trim(c.source_label), ''),
                             nullif(trim(so.label), ''), '—') || ')'
  end
  from public.customers c
  left join public.customers r on r.id = c.referred_by
  left join public.customer_source_options so on so.id = c.source_option_id
  where c.id = p_customer_id
$function$;

-- ---------------------------------------------------------------------
-- 7. Correcting a submission. A customer filling the form on a phone at a
--    roadshow will mistype things; an Owner or Manager can fix the record
--    without asking them to submit again. The linked customer is updated in
--    step, so the two do not drift apart.
-- ---------------------------------------------------------------------
create or replace function public.update_survey_particulars(
  p_survey_id uuid,
  p_first_name text default null, p_last_name text default null,
  p_phone text default null, p_email text default null,
  p_date_of_birth date default null, p_sex text default null,
  p_occupation text default null, p_others_text text default null)
returns void language plpgsql security definer set search_path to 'public' as $function$
declare v_cust uuid; v_full text;
begin
  if not public.is_owner_or_manager() then
    raise exception 'Only an Owner or Manager can edit a submission'; end if;

  v_full := public.join_person_name(p_first_name, p_last_name);
  if v_full is null then raise exception 'A first name is required'; end if;

  update public.health_surveys set
    first_name = nullif(trim(p_first_name),''),
    last_name  = nullif(trim(p_last_name),''),
    full_name  = v_full,
    phone      = nullif(trim(p_phone),''),
    email      = nullif(trim(p_email),''),
    date_of_birth = coalesce(p_date_of_birth, date_of_birth),
    sex        = coalesce(nullif(trim(p_sex),''), sex),
    occupation = nullif(trim(p_occupation),''),
    others_text = nullif(trim(p_others_text),'')
  where id = p_survey_id
  returning customer_id into v_cust;

  if not found then raise exception 'Submission not found'; end if;

  -- Keep the customer record aligned with the corrected submission.
  if v_cust is not null then
    update public.customers set
      first_name = nullif(trim(p_first_name),''),
      last_name  = nullif(trim(p_last_name),''),
      full_name  = v_full,
      email      = coalesce(nullif(trim(p_email),''), email),
      date_of_birth = coalesce(p_date_of_birth, date_of_birth),
      occupation = coalesce(nullif(trim(p_occupation),''), occupation)
    where id = v_cust;
  end if;

  perform public.write_audit_ex('health_surveys', p_survey_id, 'survey_particulars_edited', null,
    jsonb_build_object('name', v_full), 'survey', null, null);
end $function$;

notify pgrst, 'reload schema';
