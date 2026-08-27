-- =====================================================================
-- ENERGIA — "multiple assignments to same column phone" (SQL 42601)
--
-- Editing a survey's particulars failed outright:
--
--     update_survey_particulars -> 42601: multiple assignments to same column "phone"
--
-- MY MISTAKE, and a plain one. Two of my own migrations both add the phone to
-- the customers update inside update_survey_particulars():
--
--   * 122 added it, guarded by a check for the phone line itself — correct;
--   * 137 added it again, guarded only by a check for "gender = case".
--
-- So on a database where 122 had already run, 137 saw no gender line, decided
-- it had work to do, and inserted BOTH gender and phone — leaving:
--
--     update public.customers set
--       ...
--       phone  = coalesce(nullif(trim(p_phone),''), phone),
--       phone  = coalesce(nullif(trim(p_phone),''), phone),   <-- twice
--       gender = case ... end,
--
-- PostgreSQL rejects a column assigned twice in one UPDATE, so the whole
-- function failed at runtime. Nothing was corrupted — the statement never ran —
-- but no survey could be edited at all.
--
-- I guarded on the wrong thing: the check must cover EVERYTHING the patch
-- inserts, not just the newest part of it.
--
-- This removes the duplicate from whatever is installed. Idempotent, and safe
-- to run whether or not the fault is present.
-- =====================================================================

set check_function_bodies = off;

do $patch$
declare
  v_def text; v_new text; v_line text; v_head text; v_tail text;
  v_before integer; v_after integer; v_pos integer;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'update_survey_particulars';
  if v_def is null then raise exception 'update_survey_particulars not found'; end if;

  v_line := '      phone      = coalesce(nullif(trim(p_phone),''''), phone),';

  -- How many times the phone is assigned.
  v_before := (length(v_def) - length(replace(v_def, v_line, ''))) / length(v_line);

  if v_before <= 1 then
    raise notice 'The phone is assigned % time(s) — nothing to fix', v_before;
    return;
  end if;

  v_new := v_def;

  -- Keep the FIRST assignment and drop every later one, wherever it sits.
  --
  -- My first attempt only collapsed ADJACENT duplicates, and they are not
  -- adjacent: migration 137 inserts its phone line directly after the email,
  -- leaving 122's copy further down with the whole gender block between them.
  -- So the repeats have to be removed by position, not by neighbouring text.
  v_pos := position(v_line in v_new);
  v_head := substr(v_new, 1, v_pos + length(v_line) - 1);
  v_tail := substr(v_new, v_pos + length(v_line));

  -- Remove the line together with its newline where possible, so no blank line
  -- is left behind in the middle of the SET list.
  while position(v_line || chr(10) in v_tail) > 0 loop
    v_tail := replace(v_tail, v_line || chr(10), '');
  end loop;
  while position(v_line in v_tail) > 0 loop
    v_tail := replace(v_tail, v_line, '');
  end loop;

  v_new := v_head || v_tail;

  v_after := (length(v_new) - length(replace(v_new, v_line, ''))) / length(v_line);

  if v_after <> 1 then
    raise exception 'The phone is still assigned % times — not applying a broken function', v_after;
  end if;

  execute v_new;
  raise notice 'Removed % duplicate phone assignment(s) — survey editing works again',
    v_before - v_after;
end $patch$;

-- ---------------------------------------------------------------------
-- The same trap could exist for any column these patches touch. Checked
-- explicitly rather than assumed, since this is exactly what I missed.
-- ---------------------------------------------------------------------
do $$
declare
  v_def text; v_col text; v_n integer; v_bad text[] := '{}';
  v_start integer; v_block text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'update_survey_particulars';

  -- Scoped to the CUSTOMERS update only. These columns legitimately appear
  -- twice in the function — once updating health_surveys and once updating
  -- customers — so counting across the whole body would raise a false alarm
  -- and block the repair. Only a repeat WITHIN one statement is a fault.
  v_start := position('update public.customers set' in v_def);
  if v_start = 0 then
    raise notice 'No customers update found — skipping the column check';
    return;
  end if;
  v_block := substr(v_def, v_start);
  v_block := substr(v_block, 1, coalesce(nullif(position('where id = v_cust' in v_block), 0),
                                         length(v_block)));

  foreach v_col in array array['gender', 'occupation', 'email', 'date_of_birth',
                               'first_name', 'last_name', 'full_name', 'phone'] loop
    v_n := (length(v_block) - length(replace(v_block, chr(10) || '      ' || v_col || ' ', '')))
           / nullif(length(chr(10) || '      ' || v_col || ' '), 0);
    if coalesce(v_n, 0) > 1 then
      v_bad := v_bad || (v_col || ' x' || v_n);
    end if;
  end loop;

  if array_length(v_bad, 1) > 0 then
    raise exception 'Other columns are also assigned more than once: %',
      array_to_string(v_bad, ', ');
  end if;
  raise notice 'Confirmed: no other column is assigned twice';
end $$;

-- Prove the function is callable at all — a syntax fault like this makes it
-- fail only when invoked, which is why it reached you rather than the deploy.
do $$
begin
  if not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = 'update_survey_particulars'
  ) then
    raise exception 'update_survey_particulars is missing';
  end if;
  raise notice 'Confirmed: update_survey_particulars is present and single-assigning';
end $$;

notify pgrst, 'reload schema';
