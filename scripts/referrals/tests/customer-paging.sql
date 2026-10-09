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
-- Disposable local database only; everything is rolled back. The migration is
-- applied inside this transaction, so run the file on its own:
--   psql -v ON_ERROR_STOP=1 -f scripts/referrals/tests/customer-paging.sql
-- On a local database that has drifted from production (search_customers is
-- 398/404's), pass a file that installs production's functions, run right
-- after the begin below:
--   psql -v ON_ERROR_STOP=1 -v prelude=/path/to/prod_prelude.sql -f ...
-- Every name and phone here is invented.
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '10s';
\if :{?prelude}
\i :prelude
\endif

\ir ../../../supabase/409_refund_requests_refund_due_customer_order.sql

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

rollback;
