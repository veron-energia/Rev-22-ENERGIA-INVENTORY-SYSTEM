-- Only an Owner or a Manager exports the customer list, once in the Audit Log per export; a
-- customer list gives anyone else at most 50 customers at a time; an Inventory Manager gets no
-- customer list (not even with a store); a colleague's login email, personal phone and personal
-- email are an Owner's, a Manager's and their own (539; security audit of 17 Nov 2026, M13; the
-- user, 25 Nov 2026). An Inventory Manager's invoice roads are 540's and its suite's.
--
-- Every call is made as the pages make it: a signed-in login (the authenticated role, its JWT)
-- reading a table or calling a function, the anon key, or the secret key (service_role). The logins: an Owner,
-- a Manager, Staff (two), an Inventory Manager, the old Admin role, and a login with no staff
-- profile.
--
--   B  (install mode) Before 539, as an Owner: search_customers' answers to ten searches (every
--      customer, a name, a page, a phone typed with spaces, an id, an email, a source, visited and
--      not visited, the default page size); after 539 the same searches give the same rows in
--      the same order (md5 of each answer). Before 539 Staff get 60 customers in one call, an
--      Inventory Manager reads them, and Staff read a colleague's personal email.
--   S  The search: an Owner and a Manager get all 60 in one call; Staff and an Admin get at most
--      50 a call (51 is refused with the sentence; a missing limit is 50; they page on to the
--      last 10); an Inventory Manager is refused at any size, and reads no customer row from the
--      table, by name or by id; Staff still read any customer from the table (the pickers' direct
--      reads stay); a login with no staff profile and the secret key get no rows, as before.
--   L  The other lists: therapy_customer_summary (the Therapy page) and customer_survey_overview
--      (Health Surveys) give Staff and an Admin at most 50 a call (51 refused), an Owner and a
--      Manager as before (the summary any size, the surveys 200); an Inventory Manager is refused
--      both and the invoice's affiliate picker, which Staff keep.
--   E  The export: an Owner's standard export and a Manager's Special Export give every customer
--      the search finds, in its order, without total_count, and each writes exactly one Audit Log
--      entry (who, role, module, table, the count, the filters, the export kind); Staff, an
--      Admin, an Inventory Manager, a login with no staff profile and the secret key are refused,
--      with the sentence, and write nothing; an unknown export kind is refused.
--   P  public.profiles: every login reads colleagues' names, roles, work phones and the other
--      columns as before; nobody reads email, personal_phone or personal_email from the table
--      (select * included, an Owner too); an Owner and a Manager read them through
--      user_admin_list, Staff and an Inventory Manager get no rows there, as before; each login
--      reads its own through my_profile_contact_details (a login with no profile and the secret
--      key: none). Updates as the Users & Roles page makes them (returning id and is_active) work
--      for an Owner and a Manager, and 532's audit trigger records each; Staff edit their own
--      phones; the update rules and the guard trigger refuse as before; returning * is refused.
--      anon reads nothing of public.profiles; an Admin gets user_admin_list with the three columns
--      empty but on their own row.
--   G  539's fixed parts: AFTER md5s and grants; the read rule; the grants on profiles; the
--      relied-on functions unchanged; installed here, only those functions changed.
--   U  scripts/customers/undo-539.sql puts everything back exactly; a second undo refuses; 539
--      again makes the same.
--   M  539 a second time refuses.
--
-- Disposable local database only; everything is rolled back. Every name and number is invented
-- (M539 ..., @example.invalid; phones +61 491 570 nnn). Run it on a copy of production without
-- 539 (after 538; it applies 539, then again); with -v skip_install=1 where 539 is in (B, U and M
-- skipped, G in part); with -v control=1 on a copy WITHOUT 539 (it skips B, G, U and M and fails
-- on exactly the checks 539 makes pass).
--   psql -X -v ON_ERROR_STOP=1 -f scripts/customers/tests/customer-list-and-staff-contacts-539.sql
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '10s';
set local statement_timeout = '600s';
create temp table fn0 as
  select p.oid::regprocedure::text as fn, md5(pg_get_functiondef(p.oid)) as md5, p.proacl::text as acl
    from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p');
create temp table acl0 as
  select (select relacl::text from pg_class where oid = 'public.profiles'::regclass) as prof_acl,
         (select string_agg(attname || '=' || coalesce(attacl::text, ''), ',' order by attnum) from pg_attribute
           where attrelid = 'public.profiles'::regclass and attnum > 0) as prof_attacl,
         (select pg_get_expr(polqual, polrelid) from pg_policy where polrelid = 'public.customers'::regclass and polname = 'read customers') as pol,
         (select pg_get_expr(polqual, polrelid) from pg_policy where polrelid = 'public.customer_phone_history'::regclass and polname = 'read phone history') as ph;
select to_regprocedure('public.export_customers(text,text,text,text,date,date,date,date)') is not null as had539 \gset
\if :{?control}
\if :had539
\echo control: 539 is in on this copy; run -v control=1 on a copy without it
select 1/0;
\endif
\set mode control
\elif :{?skip_install}
\if :had539
\else
\echo 539 is not in: run without -v skip_install
select 1/0;
\endif
\set mode skip
\elif :had539
\echo 539 is already in: run with -v skip_install=1
select 1/0;
\else
\set mode install
\endif
select :'mode' = 'install' as by_us, :'mode' = 'control' as is_control \gset

create temp table failed(n serial, msg text);
create function pg_temp.check(ok boolean, msg text) returns void language plpgsql as
$$begin
  if ok is distinct from true then insert into failed(msg) values (msg); raise notice 'FAIL  %', msg;
  else raise notice 'PASS  %', msg; end if;
end$$;
create temp table fx(k text primary key, v uuid);
create function pg_temp.fx(key text) returns uuid language sql as $$ select v from fx where k = key $$;
create function pg_temp.put(key text, val uuid) returns uuid language sql as
$$ insert into fx values (key, val) on conflict (k) do update set v = excluded.v returning v $$;
create temp table sfx as select lower(substr(md5(gen_random_uuid()::text), 1, 6)) as s, (floor(random() * 900))::int as ph;
create function pg_temp.sfx() returns text language sql as $$ select s from sfx $$;
create function pg_temp.ph(n int) returns text language sql as
$$ select '+61491570' || lpad((((select ph from sfx) + n) % 1000)::text, 3, '0') $$;
create function pg_temp.term() returns text language sql as $$ select 'M539 ' || pg_temp.sfx() $$;
create function pg_temp.s(key text) returns text language sql as $$
  select case key
    when 'im' then 'An Inventory Manager does not see the customer list.'
    when 'cap' then 'A search returns at most 50 customers at a time.'
    when 'export' then 'Only an Owner or a Manager can export the customer list.'
    when 'kind' then 'An export is the standard export or the Special Export.'
    when 'staff' then 'Only active Energia staff can do this.' end $$;
-- Runs q as a login (a key of fx), as the secret key ('service'), and returns 'ok:<value>' or
-- 'ERR <sqlstate> <message>'.
create function pg_temp.as_(who text, q text) returns text language plpgsql as $f$
declare v text; s text; m text;
begin
  begin
    if who = 'anon' then
      perform set_config('request.jwt.claim.sub', '', true);
      perform set_config('request.jwt.claim.role', 'anon', true);
      perform set_config('request.jwt.claims', '{"role":"anon"}', true);
      execute 'set local role anon';
    elsif who like 'pg:%' then
      -- As a server function runs it: the database owner, with the login's claims.
      perform set_config('request.jwt.claim.sub', pg_temp.fx(substr(who, 4))::text, true);
      perform set_config('request.jwt.claim.role', 'authenticated', true);
      perform set_config('request.jwt.claims', json_build_object('sub', pg_temp.fx(substr(who, 4)), 'role', 'authenticated')::text, true);
    elsif who = 'service' then
      perform set_config('request.jwt.claim.sub', '', true);
      perform set_config('request.jwt.claim.role', 'service_role', true);
      perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
      execute 'set local role service_role';
    else
      perform set_config('request.jwt.claim.sub', pg_temp.fx(who)::text, true);
      perform set_config('request.jwt.claim.role', 'authenticated', true);
      perform set_config('request.jwt.claims', json_build_object('sub', pg_temp.fx(who), 'role', 'authenticated')::text, true);
      execute 'set local role authenticated';
    end if;
    execute q into v;
    execute 'reset role';
    return 'ok:' || coalesce(v, '');
  exception when others then
    get stacked diagnostics s = returned_sqlstate, m = message_text;
    execute 'reset role';
    return 'ERR ' || s || ' ' || m;
  end;
end $f$;
create function pg_temp.refused(t text, sentence text) returns boolean language sql as
$$ select t = 'ERR 42501 ' || sentence $$;
-- The md5 of a search's answer, rows in order, as a login.
create function pg_temp.search_md5(who text, args text) returns text language sql as $$
  select pg_temp.as_(who, format('select md5(coalesce(string_agg(to_jsonb(s)::text, %L order by s.ordinality), %L)) '
                                 'from public.search_customers(%s) with ordinality s', '|', '', args)) $$;
create function pg_temp.exports(who text) returns bigint language sql as
$$ select count(*) from public.audit_logs where action = 'customers_exported' and changed_by is not distinct from pg_temp.fx(who) $$;

-- ═════ Fixtures (invented), as the database owner ═════
do $fx$
declare r record; u uuid; s text := pg_temp.sfx(); n int;
begin
  for r in select * from (values ('own', 'owner', 1), ('mgr', 'manager', 2), ('stf', 'staff', 3), ('stf2', 'staff', 4),
                                 ('invm', 'inventory_manager', 5), ('adm', 'admin', 6)) t(k, role, n) loop
    insert into auth.users(id, email, email_confirmed_at) values (gen_random_uuid(), 'm539-' || r.k || '-' || s || '@example.invalid', now()) returning id into u;
    insert into public.profiles(id, full_name, email, role, is_active, work_phone, personal_phone, personal_email)
    values (u, 'M539 ' || s || ' ' || r.k, 'm539-' || r.k || '-' || s || '@example.invalid', r.role::public.user_role, true,
            pg_temp.ph(900 + r.n), pg_temp.ph(950 + r.n), 'm539-' || r.k || '-home-' || s || '@example.invalid');
    perform pg_temp.put(r.k, u);
  end loop;
  -- A store where Staff and the Inventory Manager work (the IM's customer reads are refused even so).
  insert into public.app_settings(id) values (true) on conflict do nothing;
  insert into public.stores(name, code, country_code) values ('M539 Store ' || s, 'M539' || upper(substr(s, 1, 4)), 'SG') returning id into u;
  perform pg_temp.put('st', u);
  insert into public.user_store_assignments(user_id, store_id)
  select pg_temp.fx(k), u from unnest(array['mgr', 'stf', 'stf2', 'invm', 'adm']) k;
  -- A login with no staff profile (an affiliate's, say).
  insert into auth.users(id, email, email_confirmed_at) values (gen_random_uuid(), 'm539-aff-' || s || '@example.invalid', now()) returning id into u;
  perform pg_temp.put('aff', u);
  -- 60 customers, newest last made (so the list's order is by made, then id).
  for n in 1 .. 60 loop
    insert into public.customers(full_name, first_name, last_name, phone, email, notes, created_at)
    values ('M539 ' || s || ' ' || lpad(n::text, 2, '0'), 'M539', s || ' ' || lpad(n::text, 2, '0'), pg_temp.ph(n),
            'm539-c' || n || '-' || s || '@example.invalid', 'Made-up note ' || n, now() - make_interval(mins => n))
    returning id into u;
    perform pg_temp.put('c' || n, u);
  end loop;
  insert into public.customer_phone_history(customer_id, phone, reason) values (pg_temp.fx('c7'), pg_temp.ph(500), 'Made-up old number');
end $fx$;
select pg_temp.term() as term, pg_temp.fx('c7')::text as c7, pg_temp.ph(7) as ph7,
       'm539-c8-' || pg_temp.sfx() as em8 \gset
select regexp_replace(:'ph7', '^\+61(\d{3})(\d{3})(\d{3})$', '+61 \1 \2 \3') as ph7spaced \gset
create temp table searches(k text primary key, args text);
insert into searches values
  ('every customer',  'null, null, 100000, 0'),
  ('a name',          format('%L, null, 1000, 0', :'term')),
  ('a page',          format('%L, null, 20, 20', :'term')),
  ('a spaced phone',  format('%L, null, 1000, 0', :'ph7spaced')),
  ('an id',           format('%L, null, 1000, 0', :'c7')),
  ('an email',        format('%L, null, 1000, 0', :'em8')),
  ('no source',       format('%L, %L, 1000, 0', :'term', '__none')),
  ('visited',         format('%L, null, 1000, 0, %L', :'term', 'visited')),
  ('not visited',     format('%L, null, 1000, 0, %L', :'term', 'not_visited')),
  ('default size',    format('%L', :'term'));

-- ═════ B Before 539 (install mode only) ═════
\if :by_us
create temp table b539 as select k, pg_temp.search_md5('own', args) as v from searches;
select pg_temp.check((select bool_and(v like 'ok:%') from b539), 'B0 an Owner''s ten searches answer before 539');
select pg_temp.check(pg_temp.as_('stf', format('select count(*) from public.search_customers(%L, null, 1000, 0)', :'term')) = 'ok:60',
  'B1 before 539, Staff get all 60 customers in one call');
select pg_temp.check(pg_temp.as_('invm', format('select count(*) from public.customers where full_name like %L', :'term' || '%')) = 'ok:60',
  'B2 before 539, an Inventory Manager reads the customers');
select pg_temp.check(pg_temp.as_('stf', format('select personal_email from public.profiles where id = %L', pg_temp.fx('own'))) like 'ok:m539-own-home-%',
  'B3 before 539, Staff read an Owner''s personal email');
select pg_temp.check(pg_temp.as_('invm', format('select count(*) from public.customer_phone_history where customer_id = %L', pg_temp.fx('c7'))) = 'ok:1',
  'B6 before 539, an Inventory Manager reads a customer''s phone history');
select pg_temp.check(pg_temp.as_('anon', 'select count(*) from public.profiles') = 'ok:0', 'B7 before 539, anon holds SELECT on profiles (and reads no row)');
\ir ../../../supabase/539_customer_export_and_staff_contacts_for_owners_and_managers.sql
create temp table a539 as select k, pg_temp.search_md5('own', args) as v from searches;
select pg_temp.check((select count(*) from b539 b join a539 a using (k) where a.v = b.v) = 10,
  'B4 after 539, an Owner''s ten searches give the same rows in the same order: '
  || coalesce((select string_agg(k, ', ') from b539 b join a539 a using (k) where a.v is distinct from b.v), 'all ten'));
select pg_temp.check((select count(distinct v) from a539) >= 6, 'B5 the ten searches give at least six different answers (a name, a page, a phone, an id, an email, none)');
\else
\echo NOTE  B is skipped (539 is not installed by this file)
\endif
create temp table fn1 as
  select p.oid::regprocedure::text as fn, md5(pg_get_functiondef(p.oid)) as md5, p.proacl::text as acl
    from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p');

-- ═════ S The search ═════
select pg_temp.check(pg_temp.as_('own', format('select count(*) from public.search_customers(%L, null, 1000, 0)', :'term')) = 'ok:60',
  'S1 an Owner gets all 60 in one call');
select pg_temp.check(pg_temp.as_('mgr', format('select count(*) from public.search_customers(%L, null, 1000, 0)', :'term')) = 'ok:60',
  'S2 a Manager gets all 60 in one call');
select pg_temp.check(pg_temp.as_('own', 'select count(*) >= 60 from public.search_customers(null, null, 100000, 0)') = 'ok:true',
  'S3 an Owner still pages the whole list in one call');
select pg_temp.check(pg_temp.refused(pg_temp.as_('stf', format('select count(*) from public.search_customers(%L, null, 51, 0)', :'term')), pg_temp.s('cap')),
  'S4 Staff asking for 51 are refused: ' || pg_temp.as_('stf', format('select count(*) from public.search_customers(%L, null, 51, 0)', :'term')));
select pg_temp.check(pg_temp.refused(pg_temp.as_('stf', 'select count(*) from public.search_customers('''', null, 100000, 0)'), pg_temp.s('cap')),
  'S5 the audit''s check: Staff asking for 100000 are refused');
select pg_temp.check(pg_temp.as_('stf', format('select count(*) || ''/'' || min(total_count) from public.search_customers(%L, null, 50, 0)', :'term')) = 'ok:50/60',
  'S6 Staff get 50 a call, and the total: ' || pg_temp.as_('stf', format('select count(*) || ''/'' || min(total_count) from public.search_customers(%L, null, 50, 0)', :'term')));
select pg_temp.check(pg_temp.as_('stf', format('select count(*) from public.search_customers(%L, null, 50, 50)', :'term')) = 'ok:10',
  'S7 Staff page on to the last 10 (the decision: a Staff login can still page through the list)');
select pg_temp.check(pg_temp.as_('stf', format('select count(*) from public.search_customers(%L)', :'term')) = 'ok:50'
                     and pg_temp.as_('stf', format('select count(*) from public.search_customers(%L, null, null, 0)', :'term')) = 'ok:50',
  'S8 Staff with no page size, or a null one, get 50, as before');
select pg_temp.check(pg_temp.refused(pg_temp.as_('adm', format('select count(*) from public.search_customers(%L, null, 51, 0)', :'term')), pg_temp.s('cap'))
                     and pg_temp.as_('adm', format('select count(*) from public.search_customers(%L, null, 50, 0)', :'term')) = 'ok:50',
  'S9 an Admin is not an Owner or a Manager: at most 50 a call');
select pg_temp.check(pg_temp.refused(pg_temp.as_('invm', format('select count(*) from public.search_customers(%L, null, 50, 0)', :'term')), pg_temp.s('im'))
                     and pg_temp.refused(pg_temp.as_('invm', format('select count(*) from public.search_customers(%L, null, 1, 0)', :'term')), pg_temp.s('im')),
  'S10 an Inventory Manager is refused at any size: ' || pg_temp.as_('invm', format('select count(*) from public.search_customers(%L, null, 1, 0)', :'term')));
select pg_temp.check(pg_temp.as_('invm', format('select count(*) from public.customers where full_name like %L', :'term' || '%')) = 'ok:0'
                     and pg_temp.as_('invm', format('select count(*) from public.customers where id = %L', :'c7')) = 'ok:0',
  'S11 an Inventory Manager reads no customer row from the table, by name or by id');
select pg_temp.check(pg_temp.as_('stf', format('select full_name from public.customers where id = %L', :'c7')) = 'ok:' || :'term' || ' 07'
                     and pg_temp.as_('stf', format('select count(*) from public.customers where full_name like %L', :'term' || '%')) = 'ok:60'
                     and pg_temp.as_('adm', format('select count(*) from public.customers where id = %L', :'c7')) = 'ok:1'
                     and pg_temp.as_('mgr', format('select count(*) from public.customers where id = %L', :'c7')) = 'ok:1',
  'S12 Staff, an Admin and a Manager still read customers from the table (the pickers'' direct reads stay)');
select pg_temp.check(pg_temp.as_('aff', format('select count(*) from public.search_customers(%L, null, 50, 0)', :'term')) = 'ok:0'
                     and pg_temp.as_('aff', format('select count(*) from public.customers where id = %L', :'c7')) = 'ok:0',
  'S13 a login with no staff profile gets no rows, as before');
select pg_temp.check(pg_temp.as_('service', format('select count(*) from public.search_customers(%L, null, 1000, 0)', :'term')) = 'ok:0'
                     and pg_temp.as_('service', format('select count(*) from public.customers where id = %L', :'c7')) = 'ok:1',
  'S14 the secret key: search_customers gives it nothing (not a staff login), as before; the table is the server''s');
select pg_temp.check(pg_temp.as_('stf', format('select string_agg(full_name, %L order by created_at desc, id desc) from public.search_customers(%L, null, 50, 0)', ',', :'term'))
                     = 'ok:' || (select string_agg(:'term' || ' ' || lpad(n::text, 2, '0'), ',' order by n) from generate_series(1, 50) n),
  'S15 Staff''s 50 are the first 50 of the list''s order (newest first)');

select pg_temp.check(pg_temp.as_('invm', format('select count(*) from public.customer_phone_history where customer_id = %L', pg_temp.fx('c7'))) = 'ok:0'
                     and pg_temp.as_('invm', 'select count(*) from public.customer_phone_history h join public.customers c on c.id = h.customer_id where c.full_name like ''M539 %''') = 'ok:0',
  'S16 an Inventory Manager with a store reads no phone history');
select pg_temp.check(pg_temp.as_('stf', format('select count(*) from public.customer_phone_history where customer_id = %L', pg_temp.fx('c7'))) = 'ok:1'
                     and pg_temp.as_('mgr', format('select count(*) from public.customer_phone_history where customer_id = %L', pg_temp.fx('c7'))) = 'ok:1'
                     and pg_temp.as_('aff', format('select count(*) from public.customer_phone_history where customer_id = %L', pg_temp.fx('c7'))) = 'ok:0',
  'S17 Staff and a Manager still read it (the Customers page''s Profile); a login with no staff profile does not');

-- ═════ L The other lists ═════
select pg_temp.check(pg_temp.refused(pg_temp.as_('stf', format('select count(*) from public.therapy_customer_summary(%L, 51, 0, false)', :'term')), pg_temp.s('cap'))
                     and pg_temp.as_('stf', format('select count(*) from public.therapy_customer_summary(%L, 50, 0, false)', :'term')) like 'ok:%'
                     and pg_temp.refused(pg_temp.as_('adm', format('select count(*) from public.therapy_customer_summary(%L, 51, 0, false)', :'term')), pg_temp.s('cap')),
  'L1 the Therapy page''s customers: Staff and an Admin get at most 50 a call (51 refused): ' || pg_temp.as_('stf', format('select count(*) from public.therapy_customer_summary(%L, 51, 0, false)', :'term')));
select pg_temp.check(pg_temp.as_('own', 'select count(*) >= 0 from public.therapy_customer_summary(null, 100000, 0, false)') = 'ok:true'
                     and pg_temp.as_('mgr', 'select count(*) >= 0 from public.therapy_customer_summary(null, 1000, 0, false)') = 'ok:true',
  'L2 an Owner and a Manager ask the Therapy page''s customers for any size, as before');
select pg_temp.check(pg_temp.refused(pg_temp.as_('invm', format('select count(*) from public.therapy_customer_summary(%L, 10, 0, false)', :'term')), pg_temp.s('im')),
  'L3 an Inventory Manager gets no Therapy page customers: ' || pg_temp.as_('invm', format('select count(*) from public.therapy_customer_summary(%L, 10, 0, false)', :'term')));
select pg_temp.check(pg_temp.refused(pg_temp.as_('stf', format('select count(*) from public.customer_survey_overview(%L, %L, 51, 0)', :'term', 'all')), pg_temp.s('cap'))
                     and pg_temp.refused(pg_temp.as_('adm', format('select count(*) from public.customer_survey_overview(%L, %L, 51, 0)', :'term', 'all')), pg_temp.s('cap'))
                     and pg_temp.as_('stf', format('select count(*) from public.customer_survey_overview(%L, %L, 50, 0)', :'term', 'all')) = 'ok:50',
  'L4 Health Surveys'' customers: Staff and an Admin get at most 50 a call');
select pg_temp.check(pg_temp.as_('own', format('select count(*) from public.customer_survey_overview(%L, %L, 300, 0)', :'term', 'all')) = 'ok:60'
                     and pg_temp.as_('mgr', format('select count(*) from public.customer_survey_overview(%L, %L, 200, 0)', :'term', 'all')) = 'ok:60',
  'L5 an Owner and a Manager keep Health Surveys'' 200 a page (406)');
select pg_temp.check(pg_temp.as_('invm', format('select count(*) from public.customer_survey_overview(%L, %L, 10, 0)', :'term', 'all')) = 'ERR 42501 Your role cannot do this.',
  'L6 an Inventory Manager is still refused Health Surveys'' customers (419)');
select pg_temp.check(pg_temp.refused(pg_temp.as_('invm', 'select count(*) from public.active_affiliates_for_picker()'), pg_temp.s('im'))
                     and pg_temp.as_('stf', 'select count(*) >= 0 from public.active_affiliates_for_picker()') = 'ok:true'
                     and pg_temp.as_('own', 'select count(*) >= 0 from public.active_affiliates_for_picker()') = 'ok:true',
  'L7 the invoice''s affiliate picker: an Inventory Manager is refused; Staff and an Owner keep it');

-- ═════ E The export ═════
select pg_temp.exports('own') as e_own0, pg_temp.exports('mgr') as e_mgr0 \gset
select pg_temp.as_('own', format('select public.export_customers(%L, %L)::text', 'standard', :'term')) as e1 \gset
select pg_temp.check(:'e1' like 'ok:%' and (substr(:'e1', 4)::jsonb ->> 'customers') = '60' and jsonb_array_length(substr(:'e1', 4)::jsonb -> 'rows') = 60,
  'E1 an Owner''s standard export gives all 60: ' || left(:'e1', 120));
select pg_temp.check(:'e1' like 'ok:%'
                     and (select string_agg(r ->> 'id', ',' order by o) from jsonb_array_elements(substr(:'e1', 4)::jsonb -> 'rows') with ordinality x(r, o))
                       = (select string_agg(pg_temp.fx('c' || n)::text, ',' order by n) from generate_series(1, 60) n),
  'E2 in the list''s order (newest first, as the page''s search)');
select pg_temp.check(:'e1' like 'ok:%'
                     and not exists (select 1 from jsonb_array_elements(substr(:'e1', 4)::jsonb -> 'rows') r where r ? 'total_count' or r ? 'ordinality')
                     and (select count(*) from jsonb_object_keys(substr(:'e1', 4)::jsonb -> 'rows' -> 0)) = 20
                     and (substr(:'e1', 4)::jsonb -> 'rows' -> 0 ->> 'email') like 'm539-c1-%'
                     and (substr(:'e1', 4)::jsonb -> 'rows' -> 0 ? 'date_of_birth') and (substr(:'e1', 4)::jsonb -> 'rows' -> 0 ? 'is_referrer'),
  'E3 each row carries the search''s 20 columns but its total (the Special Export''s columns included)');
select pg_temp.check(pg_temp.exports('own') - :e_own0 = 1, 'E4 the Owner''s export wrote exactly one Audit Log entry');
select pg_temp.check(exists (select 1 from public.audit_logs a
                              where a.action = 'customers_exported' and a.changed_by = pg_temp.fx('own') and a.actor_role = 'owner'
                                and a.module = 'customers' and a.table_name = 'customers' and a.record_id is null and a.old_data is null
                                and a.created_at is not null and a.new_data = jsonb_build_object('export', 'standard', 'customers', 60,
                                  'filters', jsonb_build_object('search', :'term', 'source', null, 'visited', null, 'first_visit_from', null,
                                    'first_visit_to', null, 'created_from', null, 'created_to', null))),
  'E5 the entry says who (the Owner, as owner), when, how many (60), the export and the filters: '
  || coalesce((select new_data::text from public.audit_logs where action = 'customers_exported' and changed_by = pg_temp.fx('own') order by created_at desc limit 1), 'none'));
select pg_temp.as_('mgr', format('select public.export_customers(%L, %L, %L, %L, %L, %L, %L, %L)::text', 'special', :'term', '__none', 'not_visited',
                                 null, null, '2026-01-01', '2026-12-31')) as e2 \gset
select pg_temp.check(:'e2' like 'ok:%' and (substr(:'e2', 4)::jsonb ->> 'customers') = '60'
                     and pg_temp.exports('mgr') - :e_mgr0 = 1
                     and exists (select 1 from public.audit_logs a where a.action = 'customers_exported' and a.changed_by = pg_temp.fx('mgr')
                                   and a.actor_role = 'manager' and a.new_data ->> 'export' = 'special' and (a.new_data ->> 'customers')::int = 60
                                   and a.new_data -> 'filters' ->> 'source' = '__none' and a.new_data -> 'filters' ->> 'visited' = 'not_visited'
                                   and a.new_data -> 'filters' ->> 'created_from' = '2026-01-01' and a.new_data -> 'filters' ->> 'created_to' = '2026-12-31'),
  'E6 a Manager''s Special Export, with a source, not visited and the created dates: one entry with them: ' || left(:'e2', 80));
select pg_temp.as_('own', format('select (public.export_customers(%L, %L) ->> %L)', 'standard', :'term' || ' 0', 'customers')) as e3 \gset
select pg_temp.check(:'e3' = 'ok:9' and pg_temp.exports('own') - :e_own0 = 2,
  'E7 a second export is a second entry, with its own count (9 for "' || :'term' || ' 0"): ' || :'e3');
select pg_temp.exports('stf') + pg_temp.exports('adm') + pg_temp.exports('invm') + pg_temp.exports('aff')
       + (select count(*) from public.audit_logs where action = 'customers_exported' and changed_by is null) as e_others0 \gset
select pg_temp.check(pg_temp.refused(pg_temp.as_('stf', format('select public.export_customers(%L, %L)::text', 'standard', :'term')), pg_temp.s('export')),
  'E8 Staff are refused: ' || pg_temp.as_('stf', format('select public.export_customers(%L, %L)::text', 'standard', :'term')));
select pg_temp.check(pg_temp.refused(pg_temp.as_('adm', format('select public.export_customers(%L, %L)::text', 'special', :'term')), pg_temp.s('export')),
  'E9 an Admin is refused (Admin is excluded, as on the other Owner-level routes)');
select pg_temp.check(pg_temp.refused(pg_temp.as_('invm', format('select public.export_customers(%L, %L)::text', 'standard', :'term')), pg_temp.s('export')),
  'E10 an Inventory Manager is refused');
select pg_temp.check(pg_temp.refused(pg_temp.as_('aff', format('select public.export_customers(%L, %L)::text', 'standard', :'term')), pg_temp.s('staff')),
  'E11 a login with no staff profile is refused: ' || pg_temp.as_('aff', format('select public.export_customers(%L, %L)::text', 'standard', :'term')));
select pg_temp.check(pg_temp.refused(pg_temp.as_('service', format('select public.export_customers(%L, %L)::text', 'standard', :'term')), pg_temp.s('export')),
  'E12 the secret key is refused: ' || pg_temp.as_('service', format('select public.export_customers(%L, %L)::text', 'standard', :'term')));
select pg_temp.check(pg_temp.as_('own', format('select public.export_customers(%L, %L)::text', 'everything', :'term')) = 'ERR P0001 ' || pg_temp.s('kind')
                     and pg_temp.as_('own', format('select public.export_customers(null, %L)::text', :'term')) = 'ERR P0001 ' || pg_temp.s('kind')
                     and pg_temp.exports('own') - :e_own0 = 2,
  'E13 an unknown export kind is refused and writes nothing');
select pg_temp.check(pg_temp.exports('stf') + pg_temp.exports('adm') + pg_temp.exports('invm') + pg_temp.exports('aff')
                     + (select count(*) from public.audit_logs where action = 'customers_exported' and changed_by is null) = :e_others0,
  'E14 the refused exports wrote no Audit Log entry');
select pg_temp.check(pg_temp.as_('own', format('select public.export_customers(%L, %L)::text', 'standard', :'term' || ' nobody')) = 'ok:{"rows": [], "customers": 0}'
                     and pg_temp.exports('own') - :e_own0 = 3,
  'E15 an export that finds nobody is an empty file and still one entry');

-- ═════ P public.profiles ═════
select pg_temp.check(pg_temp.as_(w, format('select count(*) || ''/'' || count(work_phone) || ''/'' || count(full_name) from public.profiles where full_name like %L',
                                            'M539 ' || pg_temp.sfx() || '%')) = 'ok:6/6/6',
  'P1 ' || w || ' reads every colleague''s name, role and work phone')
  from unnest(array['own', 'mgr', 'stf', 'invm', 'adm']) w;
select pg_temp.check(pg_temp.as_(w, format('select %I from public.profiles where id = %L', c, pg_temp.fx('own'))) = 'ERR 42501 permission denied for table profiles',
  'P2 ' || w || ' reads no ' || c || ' from public.profiles (an Owner''s own too): ' || pg_temp.as_(w, format('select %I from public.profiles where id = %L', c, pg_temp.fx('own'))))
  from unnest(array['own', 'mgr', 'stf', 'invm', 'adm']) w, unnest(array['email', 'personal_phone', 'personal_email']) c;
select pg_temp.check(pg_temp.as_(w, 'select count(*) from (select * from public.profiles) x') = 'ERR 42501 permission denied for table profiles',
  'P3 ' || w || ': select * is refused')
  from unnest(array['own', 'stf']) w;
select pg_temp.check(pg_temp.as_(w, format('select count(*) from public.user_admin_list() where email like %L and personal_phone is not null and personal_email is not null',
                                            'm539-%-' || pg_temp.sfx() || '@example.invalid')) = 'ok:6',
  'P4 ' || w || ' reads every colleague''s login email, personal phone and personal email in user_admin_list')
  from unnest(array['own', 'mgr']) w;
select pg_temp.check(pg_temp.as_(w, 'select count(*) from public.user_admin_list()') = 'ok:0',
  'P5 ' || w || ' gets no rows from user_admin_list, as before')
  from unnest(array['stf', 'invm', 'aff']) w;
select pg_temp.check(pg_temp.as_(w, 'select string_agg(id || ''|'' || email || ''|'' || personal_phone || ''|'' || personal_email, '','') from public.my_profile_contact_details()')
                     = format('ok:%s|m539-%s-%s@example.invalid|%s|m539-%s-home-%s@example.invalid', pg_temp.fx(w), w, pg_temp.sfx(), pg_temp.ph(950 + n::int), w, pg_temp.sfx()),
  'P6 ' || w || ' reads their own login email, personal phone and personal email, and nobody else''s')
  from unnest(array['own', 'mgr', 'stf', 'stf2', 'invm', 'adm']) with ordinality t(w, n);
select pg_temp.check(pg_temp.refused(pg_temp.as_('aff', 'select count(*) from public.my_profile_contact_details()'), pg_temp.s('staff'))
                     and pg_temp.as_('service', 'select count(*) from public.my_profile_contact_details()') = 'ok:0',
  'P7 a login with no staff profile is refused my_profile_contact_details (406); the secret key gets no row');
select (select count(*) from public.audit_logs where record_id = pg_temp.fx('stf2')) as p_aud0 \gset
select pg_temp.as_('own', format('with u as (update public.profiles set full_name = %L, work_phone = %L, personal_phone = %L, personal_email = %L, updated_at = now() '
                                 'where id = %L and is_active = true returning id, is_active) select string_agg(id || %L || is_active, %L) from u',
                                 'M539 ' || pg_temp.sfx() || ' stf2 renamed', pg_temp.ph(990), pg_temp.ph(991), 'm539-stf2-new-' || pg_temp.sfx() || '@example.invalid',
                                 pg_temp.fx('stf2'), '/', ',')) as p8 \gset
select pg_temp.check(:'p8' = 'ok:' || pg_temp.fx('stf2') || '/true'
                     and (select personal_email from public.profiles where id = pg_temp.fx('stf2')) = 'm539-stf2-new-' || pg_temp.sfx() || '@example.invalid'
                     and (select count(*) from public.audit_logs where record_id = pg_temp.fx('stf2')) = :p_aud0 + 1,
  'P8 an Owner saves a colleague''s profile as the Users & Roles page does (returning id and is_active), and 532 records it: ' || :'p8');
select pg_temp.check(pg_temp.as_('mgr', format('with u as (update public.profiles set personal_phone = %L where id = %L returning id) select count(*) from u',
                                               pg_temp.ph(992), pg_temp.fx('stf2'))) = 'ok:1'
                     and pg_temp.as_('mgr', format('with u as (update public.profiles set work_phone = %L where id = %L returning id) select count(*) from u',
                                                   pg_temp.ph(993), pg_temp.fx('own'))) = 'ok:0',
  'P9 a Manager saves Staff''s phones, and still not an Owner''s (the update rule, as before)');
select pg_temp.check(pg_temp.as_('stf', format('with u as (update public.profiles set personal_phone = %L where id = %L returning id) select count(*) from u',
                                               pg_temp.ph(994), pg_temp.fx('stf'))) = 'ok:1'
                     and pg_temp.as_('stf', format('with u as (update public.profiles set work_phone = %L where id = %L returning id) select count(*) from u',
                                                   pg_temp.ph(995), pg_temp.fx('stf2'))) = 'ok:0'
                     and pg_temp.as_('stf', format('update public.profiles set role = %L where id = %L', 'manager', pg_temp.fx('stf'))) like 'ERR %',
  'P10 Staff save their own phones; not a colleague''s; and the guard still refuses their own role');
select pg_temp.check(pg_temp.as_('own', format('with u as (update public.profiles set work_phone = %L where id = %L returning *) select count(*) from u',
                                               pg_temp.ph(996), pg_temp.fx('stf2'))) = 'ERR 42501 permission denied for table profiles'
                     and pg_temp.as_('own', format('with u as (update public.profiles set work_phone = %L where id = %L returning personal_email) select count(*) from u',
                                                   pg_temp.ph(996), pg_temp.fx('stf2'))) = 'ERR 42501 permission denied for table profiles',
  'P11 an update asking for back a hidden column (returning *, returning personal_email) is refused whole');
select pg_temp.check(pg_temp.as_('service', format('select email from public.profiles where id = %L', pg_temp.fx('stf'))) = 'ok:m539-stf-' || pg_temp.sfx() || '@example.invalid',
  'P12 the secret key (the Edge Functions) still reads every column of public.profiles');
select pg_temp.check(pg_temp.as_('anon', 'select count(*) from public.profiles') = 'ERR 42501 permission denied for table profiles'
                     and pg_temp.as_('anon', 'select count(id) from public.profiles') = 'ERR 42501 permission denied for table profiles',
  'P13 anon reads nothing of public.profiles, not even a column: ' || pg_temp.as_('anon', 'select count(*) from public.profiles'));
select pg_temp.check(pg_temp.as_('adm', format('select count(*) || ''/'' || count(email) || ''/'' || count(personal_phone) || ''/'' || count(personal_email) from public.user_admin_list() where full_name like %L',
                                               'M539 ' || pg_temp.sfx() || '%')) = 'ok:6/1/1/1'
                     and pg_temp.as_('adm', format('select email from public.user_admin_list() where user_id = %L', pg_temp.fx('adm'))) = 'ok:m539-adm-' || pg_temp.sfx() || '@example.invalid',
  'P14 an Admin gets user_admin_list with the login email and personal contacts empty but on their own row: '
  || pg_temp.as_('adm', format('select count(*) || ''/'' || count(email) || ''/'' || count(personal_phone) || ''/'' || count(personal_email) from public.user_admin_list() where full_name like %L', 'M539 ' || pg_temp.sfx() || '%')));
select pg_temp.as_('mgr', format('with u as (update public.profiles set personal_phone = %L, personal_email = %L, updated_at = now() where id = %L and is_active = true returning id, is_active) select string_agg(id || %L || is_active, %L) from u',
                               pg_temp.ph(997), 'm539-stf2-mgr-' || pg_temp.sfx() || '@example.invalid', pg_temp.fx('stf2'), '/', ',')) as p15m,
       pg_temp.as_('stf', format('with u as (update public.profiles set personal_phone = %L, personal_email = %L, updated_at = now() where id = %L returning id, is_active) select string_agg(id || %L || is_active, %L) from u',
                               pg_temp.ph(998), 'm539-stf-self-' || pg_temp.sfx() || '@example.invalid', pg_temp.fx('stf'), '/', ',')) as p15s \gset
select pg_temp.check(:'p15m' = 'ok:' || pg_temp.fx('stf2') || '/true' and :'p15s' = 'ok:' || pg_temp.fx('stf') || '/true'
                     and (select personal_email from public.profiles where id = pg_temp.fx('stf2')) = 'm539-stf2-mgr-' || pg_temp.sfx() || '@example.invalid'
                     and (select personal_email from public.profiles where id = pg_temp.fx('stf')) = 'm539-stf-self-' || pg_temp.sfx() || '@example.invalid',
  'P15 the Users & Roles save (personal phone and email, returning id and is_active) works as a Manager for Staff and as the person themselves: ' || :'p15m' || ' | ' || :'p15s');

-- ═════ G 539's fixed parts ═════
\if :is_control
\echo NOTE  G, U and M are skipped (control)
\else
create temp table g539(fn text, after_md5 text, acl text);
insert into g539 values
  ('search_customers(text,text,integer,integer,text,date,date)', '25f9a33395ad17f7d6b8f63252bd34ab', 'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres'),
  ('therapy_customer_summary(text,integer,integer,boolean)', '93c046a23c15684aa88a67b2dd3f5c34', 'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres'),
  ('customer_survey_overview(text,text,integer,integer)', '42b98e0787c27efa66f4b32c0272c8dc', 'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres'),
  ('active_affiliates_for_picker()', 'a75fa8c401202112d4abf0b478b0e59a', 'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres'),
  ('user_admin_list()', 'ab6167ddfea14ecc4b1140ce4221a0d4', 'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres'),
  ('customer_list_guard(integer)', 'de5cfaa12b667a4df0d45721b9531141', 'postgres=X/postgres'),
  ('export_customers(text,text,text,text,date,date,date,date)', '1d0eb73a09a49a939f353582844c1fd5', 'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres'),
  ('my_profile_contact_details()', '6ae2834b13b1ab52653da4cf342b99df', 'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres');
select pg_temp.check(not exists (select 1 from g539 g where md5(pg_get_functiondef(to_regprocedure('public.' || g.fn))) is distinct from g.after_md5),
  'G1 the five patched functions and the three new ones are 539''s (AFTER md5s)');
select pg_temp.check(not exists (select 1 from g539 g where (select coalesce(string_agg(x::text, ',' order by x::text), '')
                                   from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || g.fn)) is distinct from g.acl)
                     and not has_function_privilege('anon', 'public.export_customers(text,text,text,text,date,date,date,date)', 'execute')
                     and not has_function_privilege('anon', 'public.my_profile_contact_details()', 'execute'),
  'G2 their grants: the page functions signed-in logins and the service role, not anon (the role tests are inside); the guard postgres''s alone');
select pg_temp.check((select pg_get_expr(polqual, polrelid) from pg_policy where polrelid = 'public.customers'::regclass and polname = 'read customers')
                     = '((deleted_at IS NULL) AND (( SELECT current_user_role() AS current_user_role) = ANY (ARRAY[''owner''::user_role, ''admin''::user_role, ''manager''::user_role, ''staff''::user_role])))'
                     and (select count(*) from pg_policy where polrelid = 'public.customers'::regclass and polcmd in ('r', '*')) = 1,
  'G3 the customers table''s one read rule names Owner, Admin, Manager and Staff');
select pg_temp.check((select pg_get_expr(polqual, polrelid) from pg_policy where polrelid = 'public.customer_phone_history'::regclass and polname = 'read phone history')
                     = '(( SELECT current_user_role() AS current_user_role) = ANY (ARRAY[''owner''::user_role, ''admin''::user_role, ''manager''::user_role, ''staff''::user_role]))'
                     and (select count(*) from pg_policy where polrelid = 'public.customer_phone_history'::regclass and polcmd in ('r', '*')) = 1,
  'G3b the phone history''s one read rule names the same four roles');
select pg_temp.check((select relacl::text from pg_class where oid = 'public.profiles'::regclass)
                       -- 543 (security audit L15): without TRUNCATE, REFERENCES and TRIGGER for anon and authenticated.
                       in ('{postgres=arwdDxtm/postgres,anon=awdDxtm/postgres,authenticated=awdDxtm/postgres,service_role=arwdDxtm/postgres}',
                           '{postgres=arwdDxtm/postgres,anon=awdm/postgres,authenticated=awdm/postgres,service_role=arwdDxtm/postgres}')
                     and not has_table_privilege('anon', 'public.profiles', 'select') and not has_any_column_privilege('anon', 'public.profiles', 'select')
                     and not has_table_privilege('authenticated', 'public.profiles', 'select')
                     and (select string_agg(attname, ',' order by attnum) from pg_attribute
                           where attrelid = 'public.profiles'::regclass and attnum > 0 and attacl::text = '{authenticated=r/postgres}')
                       = 'id,full_name,role,is_active,deleted_at,created_at,updated_at,work_phone,invitation_status'
                     and (select count(*) from pg_attribute where attrelid = 'public.profiles'::regclass and attnum > 0 and attacl is not null) = 9,
  'G4 public.profiles: no table-wide SELECT for signed-in logins or anon; signed-in logins read exactly nine columns; updates as the rules allow');
select pg_temp.check(md5(pg_get_functiondef('public.current_user_role()'::regprocedure)) = '519b0a33a3548f970c5d585b6e76a389'
    and md5(pg_get_functiondef('public.require_active_staff(text[])'::regprocedure)) = '877b3aa74cea559881979bb161c450e2'
    and md5(pg_get_functiondef('public.write_audit_ex(text,uuid,text,jsonb,jsonb,text,text,uuid,text,text)'::regprocedure)) = 'c705c733e213a27f0dc32d54322cc855'
    and md5(pg_get_functiondef('public.customer_centre_visits()'::regprocedure)) = 'c07a5a0cbbf52ba45e5dc911b20002da'
    and md5(pg_get_functiondef('public.trg_guard_profile_privileges()'::regprocedure)) = '7a45127fc3f23b627285a6c5f90dbb6d'
    and md5(pg_get_functiondef('public.trg_audit_direct_change()'::regprocedure)) = '5dcea97b6479d9bb6a53adfa9dfbcba4',
  'G5 the relied-on functions (the role and staff checks, the audit writer, first visits, the profile triggers) are unchanged');
\if :by_us
select pg_temp.check((select string_agg(coalesce(a.fn, b.fn), ', ' order by coalesce(a.fn, b.fn))
                        from fn0 a full join fn1 b using (fn) where a.md5 is distinct from b.md5 or a.acl is distinct from b.acl)
                     = (select string_agg(fn, ', ' order by fn) from g539),
  'G6 installed here, only the five patched functions and the three new ones changed');
-- ═════ U The undo, then 539 again ═════
savepoint u1;
\ir ../undo-539.sql
select pg_temp.check(not exists (select 1 from fn0 a full join (select p.oid::regprocedure::text as fn, md5(pg_get_functiondef(p.oid)) as md5, p.proacl::text as acl
                                                                   from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p')) b using (fn)
                                  where a.md5 is distinct from b.md5 or a.acl is distinct from b.acl)
                     and (select relacl::text from pg_class where oid = 'public.profiles'::regclass) = (select prof_acl from acl0)
                     and (select string_agg(attname || '=' || coalesce(attacl::text, ''), ',' order by attnum) from pg_attribute
                           where attrelid = 'public.profiles'::regclass and attnum > 0) = (select prof_attacl from acl0)
                     and (select pg_get_expr(polqual, polrelid) from pg_policy where polrelid = 'public.customers'::regclass and polname = 'read customers') = (select pol from acl0)
                     and (select pg_get_expr(polqual, polrelid) from pg_policy where polrelid = 'public.customer_phone_history'::regclass and polname = 'read phone history') = (select ph from acl0),
  'U1 undo-539 puts every function, grant, column grant and both read rules back exactly');
select pg_temp.check(pg_temp.as_('stf', format('select personal_email from public.profiles where id = %L', pg_temp.fx('own'))) like 'ok:m539-own-home-%'
                     and pg_temp.as_('stf', format('select count(*) from public.search_customers(%L, null, 1000, 0)', :'term')) = 'ok:60'
                     and pg_temp.as_('invm', format('select count(*) from public.customer_phone_history where customer_id = %L', pg_temp.fx('c7'))) = 'ok:1',
  'U2 after the undo, Staff read personal emails and the whole list again, and an Inventory Manager the phone history (as before 539)');
savepoint u2;
\set ON_ERROR_STOP off
\ir ../undo-539.sql
\set ON_ERROR_STOP on
rollback to savepoint u2;
select pg_temp.check(:'LAST_ERROR_MESSAGE' like 'undo 539: % is already its version of before 539%', 'U3 the undo a second time refuses: ' || :'LAST_ERROR_MESSAGE');
\ir ../../../supabase/539_customer_export_and_staff_contacts_for_owners_and_managers.sql
select pg_temp.check(not exists (select 1 from (select p.oid::regprocedure::text as fn, md5(pg_get_functiondef(p.oid)) as md5, p.proacl::text as acl
                                                  from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p')) a
                                  full join fn1 b using (fn) where a.md5 is distinct from b.md5 or a.acl is distinct from b.acl),
  'U4 539 after the undo makes exactly what it made the first time');
rollback to savepoint u1;
savepoint m1;
\set ON_ERROR_STOP off
\ir ../../../supabase/539_customer_export_and_staff_contacts_for_owners_and_managers.sql
\set ON_ERROR_STOP on
rollback to savepoint m1;
select pg_temp.check(:'LAST_ERROR_MESSAGE' like '539 is already in on this database%', 'M1 539 a second time refuses: ' || :'LAST_ERROR_MESSAGE');
\else
\echo NOTE  G6, U and M are skipped (539 was not installed by this file)
\endif
\endif

select count(*) as n_failed from failed \gset
\if :is_control
\echo control: :n_failed checks failed without 539 (each is one 539 makes pass)
select string_agg(split_part(msg, ' ', 1), ' ' order by n) as control_failed from failed \gset
\echo control failed: :control_failed
rollback;
\else
do $$ begin
  if (select count(*) from failed) > 0 then
    raise exception '% check(s) failed: %', (select count(*) from failed), (select string_agg(msg, E'\n' order by n) from failed);
  end if;
  raise notice 'ALL PASSED';
end $$;
rollback;
\endif
