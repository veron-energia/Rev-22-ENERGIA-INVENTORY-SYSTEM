-- =====================================================================
-- ENERGIA — THE NAME COLUMNS WERE BEING OVERWRITTEN BY AN OLDER MIGRATION
--
-- Migration 125 added first_name and last_name to search_customers(). It was
-- correct, and my clean-room test passed — but the export was still blank.
--
-- The cause is FILE ORDERING. `83_customer_search_performance.sql` also defines
-- search_customers(), and sorted as text:
--
--     120_… 121_… 122_… 123_… 124_… 125_… 83_customer_search_performance.sql
--
-- "83_" sorts AFTER "125_", so any deploy that applies migrations in filename
-- order runs 83 LAST and restores the older definition, without the name
-- columns. My verification used a numerically-ordered list, which is why it
-- passed while the real deployment did not.
--
-- This migration is written so ordering cannot matter: rather than replacing
-- the function wholesale, it INSPECTS whatever definition is currently in place
-- and adds the two columns if they are missing. Re-running it after 83 — or in
-- any order at all — produces the same result.
--
-- Additive and idempotent. Safe to run at any point after 83.
-- =====================================================================

set check_function_bodies = off;

do $patch$
declare v_def text; v_new text; v_args text;
begin
  select pg_get_functiondef(p.oid), pg_get_function_identity_arguments(p.oid)
    into v_def, v_args
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'search_customers'
   limit 1;

  if v_def is null then
    raise notice 'search_customers is not present — nothing to patch';
    return;
  end if;
  if position('first_name' in v_def) > 0 then
    raise notice 'search_customers already returns the name parts';
    return;
  end if;

  -- Add the two output columns after full_name in the RETURNS TABLE list.
  v_new := replace(v_def,
    'TABLE(id uuid, full_name text,',
    'TABLE(id uuid, full_name text, first_name text, last_name text,');
  if v_new = v_def then
    v_new := replace(v_def,
      'TABLE(id uuid, full_name text' || chr(10),
      'TABLE(id uuid, full_name text, first_name text, last_name text' || chr(10));
  end if;
  if v_new = v_def then
    raise exception 'Could not add the name columns to the result type of search_customers';
  end if;

  -- And to the outer select list. The inner subquery already does "select c.*",
  -- so both values are available there.
  v_new := replace(v_new, 'select m.id, m.full_name,',
                          'select m.id, m.full_name, m.first_name, m.last_name,');
  if position('m.first_name' in v_new) = 0 then
    raise exception 'Could not add the name columns to the select list of search_customers';
  end if;

  -- Dropped by its real identity, not a guessed argument list.
  execute 'drop function if exists public.search_customers(' || v_args || ')';
  execute v_new;
  raise notice 'search_customers now returns first_name and last_name';
end $patch$;

-- ---------------------------------------------------------------------
-- Fail loudly if this is ever undone again.
--
-- A silent regression is what made this take two attempts: the function looked
-- right when I checked it, because I checked it in a database built in a
-- different order from the one that actually runs.
-- ---------------------------------------------------------------------
do $$
begin
  if not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = 'search_customers'
       and pg_get_function_result(p.oid) like '%first_name%'
  ) then
    raise exception 'search_customers does not return first_name — it has been overwritten again';
  end if;
  raise notice 'Confirmed: search_customers returns the name parts';
end $$;

notify pgrst, 'reload schema';
