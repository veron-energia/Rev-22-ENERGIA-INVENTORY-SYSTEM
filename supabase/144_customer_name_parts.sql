-- =====================================================================
-- ENERGIA — THE CUSTOMER NAME IS NOW HELD AS PARTS, LIKE THE SURVEY
--
-- The Customers form only ever wrote full_name. first_name and last_name were
-- populated once, by migration 92's backfill, and never again — so every
-- customer created since has had them empty.
--
-- That is why the name never fully synced: migration 119 pushes the customer's
-- parts onto their surveys, but with
--
--     first_name = coalesce(nullif(trim(coalesce(new.first_name,'')),''), hs.first_name)
--
-- an empty part leaves the survey's own value alone. Nothing was overwritten —
-- nothing was carried across either.
--
-- The form now takes a first and last name, exactly as the survey does, and
-- derives full_name from them. This migration deals with the records already
-- created without parts, and keeps full_name derived from here on.
--
-- Additive and idempotent.
-- =====================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------
-- 1. Fill in the parts for anyone still missing them.
--
--    Same rule migration 92 used, so a customer split then and a customer split
--    now end up the same: first word is the first name, the rest is the last.
--    "Ann" alone gives a first name and no last name, which is correct.
-- ---------------------------------------------------------------------
do $$
declare v_n integer;
begin
  update public.customers c
     set first_name = nullif(trim(split_part(trim(c.full_name), ' ', 1)), ''),
         last_name  = nullif(trim(substr(trim(c.full_name),
                        strpos(trim(c.full_name) || ' ', ' ') + 1)), '')
   where c.first_name is null
     and c.last_name is null
     and coalesce(c.full_name, '') <> ''
     and c.deleted_at is null;
  get diagnostics v_n = row_count;
  raise notice 'Split % customer name(s) into parts', v_n;

  -- And the same for any survey still holding only a whole name.
  update public.health_surveys h
     set first_name = nullif(trim(split_part(trim(h.full_name), ' ', 1)), ''),
         last_name  = nullif(trim(substr(trim(h.full_name),
                        strpos(trim(h.full_name) || ' ', ' ') + 1)), '')
   where h.first_name is null
     and h.last_name is null
     and coalesce(h.full_name, '') <> '';
  get diagnostics v_n = row_count;
  raise notice 'Split % survey name(s) into parts', v_n;
end $$;

-- ---------------------------------------------------------------------
-- 2. Keep full_name derived, so the parts and the whole cannot disagree.
--
--    Anything writing the parts gets a matching full_name automatically, and
--    anything still writing only a full_name keeps working — its parts are
--    filled in from it.
-- ---------------------------------------------------------------------
create or replace function public.trg_customer_name_parts()
returns trigger language plpgsql set search_path to 'public' as $function$
begin
  -- Parts supplied: the whole follows from them.
  if nullif(trim(coalesce(new.first_name, '')), '') is not null
     or nullif(trim(coalesce(new.last_name, '')), '') is not null then
    new.full_name := public.join_person_name(new.first_name, new.last_name);

  -- Only a whole name supplied: split it, the same way as everywhere else.
  elsif nullif(trim(coalesce(new.full_name, '')), '') is not null then
    new.first_name := nullif(trim(split_part(trim(new.full_name), ' ', 1)), '');
    new.last_name  := nullif(trim(substr(trim(new.full_name),
                        strpos(trim(new.full_name) || ' ', ' ') + 1)), '');
  end if;

  return new;
end $function$;

drop trigger if exists customer_name_parts on public.customers;
create trigger customer_name_parts
  before insert or update on public.customers
  for each row execute function public.trg_customer_name_parts();

-- ---------------------------------------------------------------------
-- 3. Anyone still without a first name, so it can be seen rather than guessed.
-- ---------------------------------------------------------------------
create or replace function public.report_customers_without_name_parts()
returns table(customer_id uuid, full_name text, phone text)
language sql stable security definer set search_path to 'public' as $function$
  select c.id, c.full_name, c.phone
    from public.customers c
   where c.deleted_at is null
     and nullif(trim(coalesce(c.first_name, '')), '') is null
   order by c.full_name
$function$;

do $$
declare v_n integer;
begin
  select count(*) into v_n from public.report_customers_without_name_parts();
  if v_n > 0 then
    raise notice 'NOTE: % customer(s) still have no first name — see report_customers_without_name_parts()', v_n;
  else
    raise notice 'Confirmed: every customer has their name held as parts';
  end if;
end $$;

notify pgrst, 'reload schema';
