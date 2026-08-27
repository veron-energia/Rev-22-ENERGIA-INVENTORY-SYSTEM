-- =====================================================================
-- ENERGIA — A SURVEY NAME EDIT WAS BEING RE-SPLIT AND UNDONE
--
--   Stored:  first "Janet Wan Leng (MOM)"   last "Koh"
--   Typed:   first "Janet Wan Leng"         last "(MOM) Koh"
--   Saved:   first "Janet"                  last "Wan Leng (MOM) Koh"
--
-- The deliberate split was thrown away and the name re-split from scratch.
--
-- WHY
--
-- trg_sync_person_name() runs BEFORE insert or update on both tables:
--
--     if parts supplied or changed then
--       full_name := join(first, last);
--     elsif coalesce(new.full_name,'') <> '' then      <-- the fault
--       first_name, last_name := split(full_name);
--     end if;
--
-- The elsif has no test that full_name CHANGED. It fires on any update where
-- the parts happen to be unchanged — which is exactly what happens on the
-- second write:
--
--   1. update_survey_particulars writes the survey with the new parts.
--      Parts changed, so full_name is rebuilt. Correct.
--   2. It then writes the same values to the customer.
--   3. The customer's AFTER trigger echoes those values BACK onto the survey.
--      The parts are now IDENTICAL to what step 1 stored, so the first branch
--      does not fire — and the elsif re-splits full_name instead.
--
-- "Janet Wan Leng (MOM) Koh" splits at the first space, giving "Janet" and the
-- rest. The user's own split is destroyed by an echo of their own edit.
--
-- This is why the Customers page works and the survey does not: editing a
-- customer is a single write, so nothing echoes back over it.
--
-- THE FIX: split only when full_name has ACTUALLY CHANGED and the parts have
-- not. A row being rewritten with the same values is left alone.
--
-- Additive and idempotent.
-- =====================================================================

set check_function_bodies = off;

create or replace function public.trg_sync_person_name()
returns trigger language plpgsql as $function$
declare v_split record;
begin
  -- Parts supplied or changed: they win, and the whole follows from them.
  if (tg_op = 'INSERT' and (new.first_name is not null or new.last_name is not null))
     or (tg_op = 'UPDATE' and (new.first_name is distinct from old.first_name
                            or new.last_name  is distinct from old.last_name)) then
    new.full_name := coalesce(public.join_person_name(new.first_name, new.last_name),
                              new.full_name);

  -- Only the WHOLE name changed: split it back out.
  --
  -- The "is distinct from old.full_name" test is the fix. Without it this fired
  -- on every update whose parts happened to be unchanged — including the echo
  -- of an edit that had just set them deliberately — and re-split a name the
  -- person had divided on purpose.
  elsif (tg_op = 'INSERT'
         or new.full_name is distinct from old.full_name)
        and coalesce(new.full_name, '') <> '' then
    select * into v_split from public.split_person_name(new.full_name);
    new.first_name := v_split.first_name;
    new.last_name  := v_split.last_name;
  end if;

  return new;
end $function$;

-- Both triggers use this function; recreated so neither is left on an old one.
drop trigger if exists sync_customer_name on public.customers;
create trigger sync_customer_name before insert or update on public.customers
  for each row execute function public.trg_sync_person_name();

drop trigger if exists sync_survey_name on public.health_surveys;
create trigger sync_survey_name before insert or update on public.health_surveys
  for each row execute function public.trg_sync_person_name();

-- ---------------------------------------------------------------------
-- Confirm the guard is in place, so this cannot silently be the old version.
-- ---------------------------------------------------------------------
do $$
declare v_src text;
begin
  select prosrc into v_src from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'trg_sync_person_name';
  if v_src is null then
    raise exception 'trg_sync_person_name is missing';
  end if;
  if position('new.full_name is distinct from old.full_name' in v_src) = 0 then
    raise exception 'The re-split guard is not present — a name edit would still be undone';
  end if;
  raise notice 'Confirmed: a name is only re-split when the whole name itself changed';
end $$;

-- ---------------------------------------------------------------------
-- Names that were re-split by this before it was fixed cannot be recovered
-- automatically — the original division is not recorded anywhere. This lists
-- the ones most likely affected: a first name with no space where the full name
-- has several, which is what re-splitting always produces.
-- ---------------------------------------------------------------------
create or replace function public.report_possibly_resplit_names()
returns table(kind text, id uuid, reference text, first_name text, last_name text)
language sql stable security definer set search_path to 'public' as $function$
  select 'survey', hs.id, hs.survey_no, hs.first_name, hs.last_name
    from public.health_surveys hs
   where hs.full_name like '% % %'
     and hs.first_name not like '% %'
  union all
  select 'customer', c.id, c.full_name, c.first_name, c.last_name
    from public.customers c
   where c.deleted_at is null
     and c.full_name like '% % %'
     and c.first_name not like '% %'
   order by 1, 3
$function$;

notify pgrst, 'reload schema';
