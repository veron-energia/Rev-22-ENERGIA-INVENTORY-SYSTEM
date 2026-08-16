-- =====================================================================
-- ENERGIA — FIRST NAME AND LAST NAME WERE BLANK IN THE CUSTOMER EXPORT
--
-- customers.first_name and customers.last_name have existed since migration 92,
-- but search_customers() — which feeds both the Customers list and its exports
-- — never returned them. The Special Export offered the columns and they came
-- out empty, because the data was simply not in the rows the page had.
--
-- Both are added to the result. The function is otherwise unchanged: same
-- arguments, same filtering, same ordering, same total_count for paging.
--
-- Anything already reading this function keeps working — the new columns are
-- appended, so a caller selecting by name is unaffected.
--
-- Additive and idempotent. Run AFTER 124.
-- =====================================================================

set check_function_bodies = off;

do $patch$
declare v_def text; v_new text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'search_customers';
  if v_def is null then raise exception 'search_customers not found'; end if;
  if position('first_name text' in v_def) > 0 then
    raise notice 'search_customers already returns the name parts'; return;
  end if;

  -- Declare the two new output columns, appended after full_name so they read
  -- naturally, and select them from the same row.
  v_new := replace(v_def,
    'TABLE(id uuid, full_name text,',
    'TABLE(id uuid, full_name text, first_name text, last_name text,');

  if v_new = v_def then
    -- The signature may be formatted across lines; try the newline form.
    v_new := replace(v_def,
      'TABLE(id uuid, full_name text' || chr(10),
      'TABLE(id uuid, full_name text, first_name text, last_name text' || chr(10));
  end if;
  if v_new = v_def then
    raise exception 'Could not add the name columns to the result type';
  end if;

  -- The body selects from an inner "matched" subquery that already does
  -- "select c.*", so both columns are present there — only the OUTER select
  -- list omits them.
  v_new := replace(v_new, 'select m.id, m.full_name,', 'select m.id, m.full_name, m.first_name, m.last_name,');
  if position('m.first_name' in v_new) = 0 then
    raise exception 'Could not add the name columns to the outer select';
  end if;

  -- The result type changes, so the old one must go first. Dropped by its
  -- actual identity rather than a guessed argument list, which is how the first
  -- attempt failed: p_source is text, not uuid.
  execute 'drop function if exists public.search_customers('
        || (select pg_get_function_identity_arguments(p.oid)
              from pg_proc p join pg_namespace n on n.oid = p.pronamespace
             where n.nspname = 'public' and p.proname = 'search_customers'
             limit 1) || ')';
  execute v_new;
  raise notice 'search_customers now returns first_name and last_name';
end $patch$;

notify pgrst, 'reload schema';
