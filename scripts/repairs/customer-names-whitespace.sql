-- CUSTOMERS-17 repair: remove the double spaces from the customer names
-- imported on 27 Jul 2026 (the Owner, 9 Oct 2026, Q8 A, part d).
--
-- On 9 Oct 2026, 30 customers (all imported on 27 Jul 2026, none deleted, none
-- with a health survey) had a name with two or more spaces in a row, so a
-- search typed with one space missed them. For every one of them, the name
-- parts tidied (trimmed, runs of spaces made one) join to the whole name
-- tidied, and the whole name tidied splits back into those parts, so the
-- tidy-up changes spacing only, never which word is the first name.
--
-- What it does, in one statement (atomic):
--   * refuses unless the names to tidy are exactly the 30 read that day (or
--     none, when it has already run), each passing the check above;
--   * sets first_name, last_name and full_name to their tidied forms (the
--     name trigger keeps them together; the survey sync has nothing to carry);
--   * writes one audit row per customer, 'customer_name_tidied', with the
--     old and new name parts, the reason and the Owner who approved it;
--   * checks that no name with a double space is left, and prints counts only.
--
-- Run it once, after 418, as the database owner (the SQL editor, the MCP
-- execute_sql tool, or psql as postgres), with c_owner set below to the
-- profile id of the Owner who approved it. A second run changes nothing.
-- Nothing is printed but counts. Expected on production (9 Oct 2026): 30
-- tidied.
--
-- To check afterwards (counts only):
--   select count(*) from public.customers where full_name ~ '\s{2,}' or first_name ~ '\s{2,}' or last_name ~ '\s{2,}';   -- 0
--   select count(*) from public.audit_logs where action = 'customer_name_tidied';                                         -- 30

do $repair$
declare
  c_owner constant uuid := null;   -- the approving Owner's profile id: fill in before running
  c_expected constant int := 30;
  c_reason constant text := 'Double spaces removed from an imported name (the Owner, 9 Oct 2026, Q8 d)';
  v_path text := current_setting('search_path');
  v_claims text := current_setting('request.jwt.claims', true);
  r record; n int := 0; n_bad int;
begin
  perform set_config('search_path', 'public', true);
  if c_owner is null or not exists (select 1 from public.profiles p where p.id = c_owner and p.role = 'owner'
                                       and p.is_active and p.deleted_at is null) then
    raise exception 'names repair: set c_owner to the approving Owner''s profile id (an active Owner); nothing was changed'; end if;

  drop table if exists pg_temp.names_to_tidy;
  create temp table names_to_tidy on commit drop as
  select c.id, c.first_name, c.last_name, c.full_name,
         nullif(regexp_replace(btrim(coalesce(c.first_name, '')), '\s+', ' ', 'g'), '') as tidy_first,
         nullif(regexp_replace(btrim(coalesce(c.last_name, '')), '\s+', ' ', 'g'), '') as tidy_last,
         regexp_replace(btrim(c.full_name), '\s+', ' ', 'g') as tidy_full
    from public.customers c
   where c.full_name ~ '\s{2,}' or c.first_name ~ '\s{2,}' or c.last_name ~ '\s{2,}';
  select count(*) into n from names_to_tidy;
  if n = 0 then
    raise notice 'names repair: no name has a double space; nothing to do';
    perform set_config('search_path', v_path, true);
    return;
  end if;
  if n <> c_expected then
    raise exception 'names repair: % names have a double space, not the % read on 9 Oct 2026. Re-read them before running; nothing was changed', n, c_expected; end if;
  select count(*) into n_bad from names_to_tidy t
   where t.tidy_full is distinct from public.join_person_name(t.tidy_first, t.tidy_last)
      or (select s.first_name from public.split_person_name(t.tidy_full) s) is distinct from t.tidy_first
      or (select s.last_name from public.split_person_name(t.tidy_full) s) is distinct from t.tidy_last;
  if n_bad > 0 then
    raise exception 'names repair: % names would change more than their spacing; nothing was changed', n_bad; end if;

  -- The audit rows name the approving Owner.
  perform set_config('request.jwt.claims', json_build_object('sub', c_owner, 'role', 'authenticated')::text, true);
  for r in select * from names_to_tidy order by id loop
    update public.customers c
       set first_name = r.tidy_first, last_name = r.tidy_last, full_name = r.tidy_full
     where c.id = r.id;
    perform public.write_audit_ex('customers', r.id, 'customer_name_tidied',
      jsonb_build_object('first_name', r.first_name, 'last_name', r.last_name, 'full_name', r.full_name),
      jsonb_build_object('first_name', r.tidy_first, 'last_name', r.tidy_last, 'full_name', r.tidy_full),
      'customers', c_reason, null::uuid);
  end loop;
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);

  select count(*) into n_bad from public.customers c join names_to_tidy t on t.id = c.id
   where c.full_name is distinct from t.tidy_full or c.first_name is distinct from t.tidy_first
      or c.last_name is distinct from t.tidy_last;
  if n_bad > 0 or exists (select 1 from public.customers c
                           where c.full_name ~ '\s{2,}' or c.first_name ~ '\s{2,}' or c.last_name ~ '\s{2,}') then
    raise exception 'names repair: the names are not as expected afterwards; nothing was changed'; end if;
  raise notice 'names repair: % names tidied, % audit rows written', c_expected, c_expected;
  perform set_config('search_path', v_path, true);
end $repair$;
