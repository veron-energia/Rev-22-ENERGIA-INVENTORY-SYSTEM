-- 409: the Customers list, its two Excel exports and the Surveys customer list
-- page through one fixed order.
--
-- On production (9 Oct 2026) 12,748 of the 12,936 customers share one of 32
-- import timestamps. search_customers ordered by created_at alone, so each
-- OFFSET page was any slice of a tie: the export's pages of 1,000 gave 12,936
-- rows but 12,810 customers, and twenty screen pages of 50 gave 675 customers.
-- The rule (approved 9 Oct 2026): newest first, then by id, so every page and
-- every export is one slice of one list. customer_survey_overview ends its
-- order on the customer and the survey for the same reason (names repeat).
--
-- This pages through the whole list at the export's page size, the screen's,
-- and an odd one, and checks every customer comes exactly once, in that order.
--
-- 418 (CUSTOMERS-11): a phone typed with spaces, dashes, brackets or "+65"
-- finds the customer in both lists (section 3). Phones are stored as
-- +<digits>; a search made only of phone characters, with 4 digits or more,
-- matches on its digits, an old phone in the history too, and "+65" with 8
-- digits also finds a number stored as the 8 digits alone. A search with
-- letters is matched as typed, as before.
--
-- Disposable local database only; everything is rolled back. The migrations
-- (409, then 418) are applied inside this transaction, so run the file on its
-- own against a database with production's schema (406 to 414 in; 418
-- refuses without 414):
--   psql -v ON_ERROR_STOP=1 -f scripts/referrals/tests/customer-paging.sql
-- On a local database that has drifted from production (search_customers is
-- 398/404's, or 414 is not in), pass a file that installs production's
-- functions, run right after the begin below:
--   psql -v ON_ERROR_STOP=1 -v prelude=/path/to/prod_prelude.sql -f ...
-- Every name and phone here is invented.
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '10s';
\if :{?prelude}
\i :prelude
\endif

-- 409 is applied only where it is not in yet: on a database at production
-- after 410, 409's own guards refuse (410 changed functions it reads).
select to_regprocedure('public.cancelled_invoice_used_value(uuid)') is not null as t409_in \gset
\if :t409_in
\else
\ir ../../../supabase/409_refund_requests_refund_due_customer_order.sql
\endif
-- 418 is applied only where it is not in yet: once 419 is in, 418's own
-- guards refuse a second run (419 changed customer_survey_overview), as in
-- rls-policies.sql.
select to_regprocedure('public.update_customer(uuid,jsonb,text,timestamptz)') is not null as t418_in \gset
\if :t418_in
\else
\ir ../../../supabase/418_customer_edits_audited_and_phone_search.sql
\endif

-- ===== 1. Fixture: 999 customers on three import timestamps =====
create temp table t409p(k text primary key, id uuid);
do $$
declare stf uuid := gen_random_uuid();
begin
  insert into auth.users(id, email) values (stf, 't409p-stf@tests.invalid');
  insert into profiles(id, full_name, email, role) values (stf, 'T409P Staff', 't409p-stf@tests.invalid', 'staff');
  insert into t409p values ('stf', stf);
  -- Half of them share one name, so the survey list's name order ties too.
  insert into customers(full_name, phone, created_at)
  select case when n % 2 = 0 then 'T409 Paging Same Name' else 'T409 Paging ' || lpad(n::text, 3, '0') end,
         '+6591400' || lpad(n::text, 3, '0'),
         case when n <= 500 then timestamptz '2026-07-01 10:00:00+08'
              when n <= 900 then timestamptz '2026-07-02 10:00:00+08'
              else timestamptz '2026-07-03 10:00:00+08' end
    from generate_series(1, 999) n;
  if (select count(*) from customers where full_name like 'T409 Paging%' and deleted_at is null) <> 999 then
    raise exception 'Fixture: expected 999 customers'; end if;
  raise notice 'Fixture: 999 customers on 3 timestamps (500, 400 and 99), 500 of them with one name';
end $$;

-- ===== 2. Paging =====
do $$
declare v_size int; v_query text; v_off int; v_got uuid[]; v_page uuid[]; v_total bigint; v_ref uuid[];
  v_sgot text[]; v_spage text[]; v_sref text[];
begin
  perform set_config('request.jwt.claim.sub', (select id from t409p where k = 'stf')::text, true);
  foreach v_query in array array['T409 Paging', ''] loop
    -- The order the list promises, read straight from the table.
    select array_agg(c.id order by c.created_at desc, c.id desc) into v_ref
      from customers c
     where c.deleted_at is null
       and (v_query = '' or c.full_name ilike '%' || v_query || '%' or c.phone ilike '%' || v_query || '%'
            or c.email ilike '%' || v_query || '%' or c.notes ilike '%' || v_query || '%'
            or exists (select 1 from customer_phone_history h where h.customer_id = c.id and h.phone ilike '%' || v_query || '%'));
    foreach v_size in array array[1000, 50, 7] loop
      v_got := '{}'; v_off := 0; v_total := null;
      loop
        select array_agg(s.id order by s.ord), max(s.total_count) into v_page, v_total
          from (select x.id, x.total_count, row_number() over () as ord
                  from search_customers(nullif(v_query, ''), null, v_size, v_off) x) s;
        exit when v_page is null;
        v_got := v_got || v_page;
        exit when array_length(v_page, 1) < v_size;
        v_off := v_off + v_size;
      end loop;
      if array_length(v_got, 1) is distinct from array_length(v_ref, 1)
         or (select count(distinct u) from unnest(v_got) u) <> array_length(v_ref, 1) then
        raise exception 'FAIL 2: search "%" in pages of %: % rows, % customers, % expected', v_query, v_size,
          array_length(v_got, 1), (select count(distinct u) from unnest(v_got) u), array_length(v_ref, 1); end if;
      if v_got <> v_ref then
        raise exception 'FAIL 2: search "%" in pages of % is not newest first, then by id', v_query, v_size; end if;
    end loop;
  end loop;
  raise notice 'PASS 2: search_customers, paged at 1000 (the exports), 50 (the screen) and 7, gives every customer exactly once, newest first then by id, for a search and for the whole list';

  -- The Surveys customer list, in the order it promises: those with a survey
  -- first, latest first, then by name, then by customer and survey.
  select array_agg(c.id::text order by (hs.id is null), hs.submitted_at desc nulls last, c.full_name, c.id, hs.id)
    into v_sref
    from customers c left join health_surveys hs on hs.customer_id = c.id
   where c.deleted_at is null and c.full_name ilike '%T409 Paging%';
  if array_length(v_sref, 1) <> 999 then
    raise exception 'Fixture: the survey list should hold the 999 customers once each, not %', array_length(v_sref, 1); end if;
  foreach v_size in array array[50, 7] loop
    v_sgot := '{}'; v_off := 0;
    loop
      select array_agg(s.customer_id::text order by s.ord) into v_spage
        from (select x.customer_id, row_number() over () as ord
                from customer_survey_overview('T409 Paging', 'all', v_size, v_off) x) s;
      exit when v_spage is null;
      v_sgot := v_sgot || v_spage;
      exit when array_length(v_spage, 1) < v_size;
      v_off := v_off + v_size;
    end loop;
    if array_length(v_sgot, 1) <> 999 or (select count(distinct u) from unnest(v_sgot) u) <> 999 then
      raise exception 'FAIL 2: the survey list in pages of %: % rows, % customers', v_size,
        array_length(v_sgot, 1), (select count(distinct u) from unnest(v_sgot) u); end if;
    if v_sgot <> v_sref then
      raise exception 'FAIL 2: the survey list in pages of % is not by name, then by customer', v_size; end if;
  end loop;
  raise notice 'PASS 2: customer_survey_overview, paged at 50 and 7, gives every customer exactly once, by name then by customer, though 500 share one name';
end $$;

-- ===== 3. Phone search on the digits (418) =====
do $$
declare v_plain uuid; v_bare uuid; v_moved uuid; v_my uuid; v_term text; v_found text[]; v_survey text[];
begin
  -- Four customers: one stored the usual way; one stored as the 8 digits
  -- alone (an import from before the phone rules; the triggers are skipped
  -- to write it as it was then); one whose old number is in the history;
  -- one on a Malaysian number.
  insert into customers(full_name, phone) values ('T418 Phone Plain', '+6591418501') returning id into v_plain;
  insert into customers(full_name, phone) values ('T418 Phone Moved', '+6591418503') returning id into v_moved;
  insert into customer_phone_history(customer_id, phone, reason) values (v_moved, '+65 9141 8599', 'Fixture: old number');
  -- An older number kept as the 8 digits alone (no trigger tidies history rows).
  insert into customer_phone_history(customer_id, phone, reason) values (v_moved, '91418598', 'Fixture: old number kept as 8 digits');
  insert into customers(full_name, phone) values ('T418 Phone Malaysia', '+60123418504') returning id into v_my;
  set local session_replication_role = replica;
  insert into customers(full_name, phone) values ('T418 Phone Bare', '91418502') returning id into v_bare;
  set local session_replication_role = origin;
  insert into t409p values ('plain', v_plain), ('bare', v_bare), ('moved', v_moved), ('my', v_my);
  perform set_config('request.jwt.claim.sub', (select id from t409p where k = 'stf')::text, true);

  for v_term, v_found in select * from (values
    -- as typed: the digits alone, with spaces, with +65, dashes, brackets, a dot
    ('91418501', array['plain']), ('9141 8501', array['plain']), ('+65 9141 8501', array['plain']),
    ('+65-9141-8501', array['plain']), ('(+65) 9141 8501', array['plain']), ('+659141.8501', array['plain']),
    ('6591418501', array['plain']), (' 8501 ', array['plain']),
    -- a number stored without +65, typed with it or without
    ('+65 9141 8502', array['bare']), ('9141 8502', array['bare']),
    -- an old number in the history, typed differently from how it was kept
    ('91418599', array['moved']), ('+6591418599', array['moved']),
    -- an old number kept without +65, typed with it
    ('+65 9141 8598', array['moved']),
    -- another country's number with spaces
    ('+60 12-341 8504', array['my']), ('012 341 8504', array['my']),
    -- the current number of the moved customer still finds them
    ('9141 8503', array['moved'])) x(term, keys)
  loop
    select array_agg(k order by k) into v_survey from t409p
     where k = any (v_found) ;
    if (select array_agg(t.k order by t.k) from t409p t
          join search_customers(v_term, null, 50, 0) s on s.id = t.id
         where t.k in ('plain', 'bare', 'moved', 'my')) is distinct from v_survey then
      raise exception 'FAIL 3: search_customers("%") found %, expected %', v_term,
        (select array_agg(t.k order by t.k) from t409p t join search_customers(v_term, null, 50, 0) s on s.id = t.id
          where t.k in ('plain', 'bare', 'moved', 'my')), v_survey; end if;
  end loop;

  -- A record id finds its customer (the phone review list names customers
  -- with no customer number by it), upper case or lower.
  if (select array_agg(s.id) from search_customers(upper(v_bare::text), null, 50, 0) s) is distinct from array[v_bare] then
    raise exception 'FAIL 3: a record id did not find its customer alone'; end if;
  -- Letters keep the search as typed: no phone matches on digits within text.
  if exists (select 1 from search_customers('T418 Phone 8501x', null, 50, 0)) then
    raise exception 'FAIL 3: a search with letters matched on its digits'; end if;
  -- Fewer than 4 digits: only what the text matches as typed.
  if (select count(*) from search_customers('85 0', null, 50, 0) s where s.id in (v_plain, v_bare, v_moved, v_my)) <> 0 then
    raise exception 'FAIL 3: a search of 3 digits with a space matched on its digits'; end if;

  -- The Surveys customer list, on the current number.
  foreach v_term in array array['9141 8501', '+65 9141 8501', '(+65) 9141-8501'] loop
    if not exists (select 1 from customer_survey_overview(v_term, 'all', 50, 0) o where o.customer_id = v_plain) then
      raise exception 'FAIL 3: customer_survey_overview("%") did not find the customer', v_term; end if;
  end loop;
  if not exists (select 1 from customer_survey_overview('+65 9141 8502', 'all', 50, 0) o where o.customer_id = v_bare) then
    raise exception 'FAIL 3: customer_survey_overview did not find a number stored without +65'; end if;
  if exists (select 1 from customer_survey_overview('T418 8501', 'all', 50, 0)) then
    raise exception 'FAIL 3: customer_survey_overview matched digits inside a search with letters'; end if;
  raise notice 'PASS 3: a phone typed with spaces, dashes, brackets or +65 finds the customer in both lists, an old number and a number stored without +65 too; a record id finds its customer; a search with letters is matched as typed';
end $$;

rollback;
