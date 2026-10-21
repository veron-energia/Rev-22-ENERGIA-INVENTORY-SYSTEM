-- 418: an opening balance or a credit adjustment sent twice is recorded once
-- (CUSTOMERS-18).
--
-- The Customers page makes one request id when the Opening balance or the
-- Adjust window opens and sends it with every press of Confirm. A lost answer
-- followed by a second press then returns what the first call recorded,
-- rather than posting it again. The approver is the person entering it; the
-- caller can no longer name someone else (p_approved_by is gone). Each
-- function has one version, so the API never has two to choose from.
--
-- Disposable database only; everything is rolled back. The migration is
-- applied inside this transaction, so run the file on its own against a
-- database with production's schema (406 to 414 in; 418 refuses without
-- 414). On a copy of production from before 414, pass a file that applies
-- it (run right after the begin below):
--   psql -v ON_ERROR_STOP=1 [-v prelude=/path/to/414.sql] -f scripts/customers/tests/credit-request-ids.sql
-- Fixture names carry T418C, phones +659141 81xx, emails @sig.invalid.
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '10s';
\if :{?prelude}
\i :prelude
\endif
-- 418 is applied only where it is not in yet: once 419 is in, 418's own
-- guards refuse a second run (419 changed customer_survey_overview), as in
-- rls-policies.sql.
select to_regprocedure('public.update_customer(uuid,jsonb,text,timestamptz)') is not null as t418_in \gset
\if :t418_in
\else
\ir ../../../supabase/418_customer_edits_audited_and_phone_search.sql
\endif

create temp table t418c(k text primary key, id uuid not null);
create function pg_temp.id(p text) returns uuid language sql stable as $f$ select id from t418c where k = p $f$;
create function pg_temp.check(p_ok boolean, p_what text) returns void language plpgsql as $f$
begin
  if not coalesce(p_ok, false) then raise exception 'FAIL: %', p_what; end if;
end $f$;
create function pg_temp.try(p_who text, p_sql text) returns text language plpgsql as $f$
declare v_out text; v_state text; v_msg text;
begin
  begin
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claims',
      json_build_object('sub', pg_temp.id(p_who), 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    execute p_sql into v_out;
    execute 'reset role';
    return 'ok' || chr(9) || coalesce(v_out, '');
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
    return v_state || chr(9) || v_msg;
  end;
end $f$;
-- The value an 'ok' answer carried.
create function pg_temp.val(p text) returns text language sql immutable as $f$ select split_part(p, chr(9), 2) $f$;

-- ===== 1. One version of each, with p_request_id and no p_approved_by =====
do $$
declare v text;
begin
  select string_agg(p.oid::regprocedure::text || ' ' || array_to_string(p.proargnames, ','), '; ' order by 1) into v
    from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('add_legacy_credit', 'adjust_customer_credit');
  perform pg_temp.check(v = 'add_legacy_credit(uuid,text,numeric,date,uuid,text,text,date,uuid) p_customer_id,p_category,p_amount,p_original_purchase_date,p_store_id,p_reference_no,p_note,p_effective_date,p_request_id; '
                         || 'adjust_customer_credit(uuid,text,text,numeric,text,text,date,text,uuid,uuid) p_customer_id,p_category,p_direction,p_amount,p_reason,p_reference_no,p_effective_date,p_note,p_store_id,p_request_id',
                        '1 the credit functions are not one version each with p_request_id: ' || coalesce(v, '(none)'));
  perform pg_temp.check(not has_function_privilege('anon', 'public.add_legacy_credit(uuid,text,numeric,date,uuid,text,text,date,uuid)', 'execute')
                        and not has_function_privilege('anon', 'public.adjust_customer_credit(uuid,text,text,numeric,text,text,date,text,uuid,uuid)', 'execute')
                        and has_function_privilege('authenticated', 'public.add_legacy_credit(uuid,text,numeric,date,uuid,text,text,date,uuid)', 'execute')
                        and has_function_privilege('authenticated', 'public.adjust_customer_credit(uuid,text,text,numeric,text,text,date,text,uuid,uuid)', 'execute'),
                        '1 the grants are not staff''s only');
  -- Each takes a lock on the request id before it looks for it, so the same
  -- request sent twice at once returns the first entry instead of failing.
  perform pg_temp.check(pg_get_functiondef('public.add_legacy_credit(uuid,text,numeric,date,uuid,text,text,date,uuid)'::regprocedure)
                          ~ 'perform pg_advisory_xact_lock\(hashtextextended\(''customer-credit-entry:'' \|\| p_request_id::text, 0\)\);\s+select \* into v_seen from public\.customer_credit_entry_requests',
                        '1 add_legacy_credit does not lock the request id before it looks for it');
  perform pg_temp.check(pg_get_functiondef('public.adjust_customer_credit(uuid,text,text,numeric,text,text,date,text,uuid,uuid)'::regprocedure)
                          ~ 'perform pg_advisory_xact_lock\(hashtextextended\(''customer-credit-entry:'' \|\| p_request_id::text, 0\)\);\s+select \* into v_seen from public\.customer_credit_entry_requests',
                        '1 adjust_customer_credit does not lock the request id before it looks for it');
  raise notice 'PASS 1: add_legacy_credit and adjust_customer_credit have one version each, take p_request_id and no p_approved_by, lock the request id, and are staff''s';
end $$;

-- ===== Fixture =====
do $$
declare k text; v uuid; st uuid;
begin
  perform set_config('request.jwt.claims', '', true);
  foreach k in array array['owner', 'manager', 'staff', 'nostaff'] loop
    insert into auth.users(id, email) values (gen_random_uuid(), 't418c-' || k || '@sig.invalid') returning id into v;
    insert into t418c values (k, v);
  end loop;
  insert into public.profiles(id, full_name, email, role, is_active)
  select pg_temp.id(x.k), 'T418C ' || x.k, 't418c-' || x.k || '@sig.invalid', x.role::public.user_role, true
    from (values ('owner', 'owner'), ('manager', 'manager'), ('staff', 'staff')) x(k, role);
  insert into public.stores(name, code, country_code) values ('T418C Store', 'T418C', 'SG') returning id into st;
  insert into t418c values ('store', st);
  insert into public.customers(first_name, last_name, phone) values ('T418C', 'One', '+6591418101') returning id into v;
  insert into t418c values ('c1', v);
  insert into public.customers(first_name, last_name, phone) values ('T418C', 'Two', '+6591418102') returning id into v;
  insert into t418c values ('c2', v);
end $$;

-- ===== 2. Opening balance =====
do $$
declare v1 text; v2 text; rq uuid := gen_random_uuid(); sql text;
begin
  sql := format('select public.add_legacy_credit(%L::uuid, ''legacy'', 120, current_date - 400, %L::uuid, null, ''T418C opening'', null, %L::uuid)::text',
                pg_temp.id('c1'), pg_temp.id('store'), rq);
  v1 := pg_temp.try('manager', sql);
  v2 := pg_temp.try('manager', sql);
  perform pg_temp.check(v1 like 'ok%' and v1 = v2, '2a the repeat did not return the first balance: ' || v1 || ' / ' || v2);
  perform pg_temp.check((select count(*) from public.customer_credit_lots where customer_id = pg_temp.id('c1')) = 1
                        and (select count(*) from public.customer_credit_ledger where customer_id = pg_temp.id('c1')) = 1,
                        '2a an opening balance sent twice was recorded twice');
  perform pg_temp.check((select approved_by = pg_temp.id('manager') and created_by = pg_temp.id('manager')
                           from public.customer_credit_lots where id = pg_temp.val(v1)::uuid), '2b the approver is not the person entering it');
  perform pg_temp.check(exists (select 1 from public.customer_credit_entry_requests r where r.request_id = rq
                                  and r.entry_kind = 'opening_balance' and r.entry_id = pg_temp.val(v1)::uuid
                                  and r.customer_id = pg_temp.id('c1') and r.created_by = pg_temp.id('manager')),
                        '2c the request id was not kept');
  -- The same request id for another customer, or as an adjustment, is refused.
  v2 := pg_temp.try('manager', format('select public.add_legacy_credit(%L::uuid, ''legacy'', 120, current_date - 400, %L::uuid, null, ''T418C opening'', null, %L::uuid)::text',
                pg_temp.id('c2'), pg_temp.id('store'), rq));
  perform pg_temp.check(v2 like 'P0001%already used for another entry%', '2d a request id was reused for another customer: ' || v2);
  v2 := pg_temp.try('manager', format('select public.adjust_customer_credit(%L::uuid, ''paid'', ''increase'', 5, ''T418C'', null, null, null, %L::uuid, %L::uuid)::text',
                pg_temp.id('c1'), pg_temp.id('store'), rq));
  perform pg_temp.check(v2 like 'P0001%already used for another entry%', '2d an opening balance''s request id was reused for an adjustment: ' || v2);
  -- Without a request id, each call records (as before).
  sql := format('select public.add_legacy_credit(%L::uuid, ''paid'', 10, current_date - 10, %L::uuid, null, ''T418C no id'', null, null)::text',
                pg_temp.id('c2'), pg_temp.id('store'));
  v1 := pg_temp.try('owner', sql);
  v2 := pg_temp.try('owner', sql);
  perform pg_temp.check(v1 like 'ok%' and v2 like 'ok%' and v1 <> v2, '2e calls without a request id: ' || v1 || ' / ' || v2);
  perform pg_temp.check((select count(*) from public.customer_credit_lots where customer_id = pg_temp.id('c2')) = 2,
                        '2e calls without a request id were not each recorded');
  -- Staff and logins that are not staff: refused.
  v2 := pg_temp.try('staff', format('select public.add_legacy_credit(%L::uuid, ''paid'', 10, current_date, %L::uuid, null, ''x'', null, %L::uuid)::text',
                pg_temp.id('c1'), pg_temp.id('store'), gen_random_uuid()));
  perform pg_temp.check(v2 like 'P0001%Only an Owner or Manager%', '2f staff entered an opening balance: ' || v2);
  v2 := pg_temp.try('nostaff', format('select public.add_legacy_credit(%L::uuid, ''paid'', 10, current_date, %L::uuid, null, ''x'', null, %L::uuid)::text',
                pg_temp.id('c1'), pg_temp.id('store'), gen_random_uuid()));
  perform pg_temp.check(v2 like '42501%', '2f a login with no staff profile reached it: ' || v2);
  raise notice 'PASS 2: an opening balance sent twice with one request id is recorded once; the approver is the person entering it; a request id cannot be reused for another entry';
end $$;

-- ===== 3. Adjustments, up and down =====
do $$
declare v1 text; v2 text; rq uuid := gen_random_uuid(); sql text; n_lots int; n_adj int;
begin
  sql := format('select public.adjust_customer_credit(%L::uuid, ''paid'', ''increase'', 30, ''T418C top-up'', null, null, null, %L::uuid, %L::uuid)::text',
                pg_temp.id('c1'), pg_temp.id('store'), rq);
  v1 := pg_temp.try('owner', sql);
  v2 := pg_temp.try('owner', sql);
  perform pg_temp.check(v1 like 'ok%' and v1 = v2, '3a the repeated increase did not return the first: ' || v1 || ' / ' || v2);
  -- The same request id for another customer is refused, not answered with
  -- the first customer's adjustment.
  v2 := pg_temp.try('owner', format('select public.adjust_customer_credit(%L::uuid, ''paid'', ''increase'', 30, ''T418C top-up'', null, null, null, %L::uuid, %L::uuid)::text',
                pg_temp.id('c2'), pg_temp.id('store'), rq));
  perform pg_temp.check(v2 like 'P0001%already used for another entry%', '3a an adjustment''s request id was reused for another customer: ' || v2);
  select count(*) into n_adj from public.customer_credit_adjustments where customer_id = pg_temp.id('c1');
  select count(*) into n_lots from public.customer_credit_lots where customer_id = pg_temp.id('c1') and source_type = 'manual_adjustment';
  perform pg_temp.check(n_adj = 1 and n_lots = 1, format('3a an increase sent twice made %s adjustments and %s lots', n_adj, n_lots));
  perform pg_temp.check((select approved_by = pg_temp.id('owner') and created_by = pg_temp.id('owner')
                           from public.customer_credit_adjustments where id = pg_temp.val(v1)::uuid), '3b the approver is not the person entering it');

  rq := gen_random_uuid();
  sql := format('select public.adjust_customer_credit(%L::uuid, ''paid'', ''decrease'', 12.5, ''T418C correction'', null, null, null, %L::uuid, %L::uuid)::text',
                pg_temp.id('c1'), pg_temp.id('store'), rq);
  v1 := pg_temp.try('manager', sql);
  v2 := pg_temp.try('manager', sql);
  perform pg_temp.check(v1 like 'ok%' and v1 = v2, '3c the repeated decrease did not return the first: ' || v1 || ' / ' || v2);
  perform pg_temp.check((select count(*) from public.customer_credit_adjustments where customer_id = pg_temp.id('c1') and direction = 'decrease') = 1
                        and (select sum(remaining_amount) from public.customer_credit_lots where customer_id = pg_temp.id('c1') and category = 'paid') = 17.5,
                        '3c a decrease sent twice took the credit twice');
  v2 := pg_temp.try('staff', format('select public.adjust_customer_credit(%L::uuid, ''paid'', ''increase'', 5, ''x'', null, null, null, null, %L::uuid)::text',
                pg_temp.id('c1'), gen_random_uuid()));
  perform pg_temp.check(v2 like 'P0001%Only an Owner or Manager%', '3d staff adjusted credit: ' || v2);
  raise notice 'PASS 3: an adjustment sent twice with one request id, up or down, is recorded once, and its request id is refused for another customer; the approver is the person entering it';
end $$;

-- ===== 4. The request table is closed to every client =====
do $$
declare v text;
begin
  v := pg_temp.try('owner', 'select count(*)::text from public.customer_credit_entry_requests');
  perform pg_temp.check(v like '42501%', '4 an Owner''s login reads customer_credit_entry_requests: ' || v);
  raise notice 'PASS 4: customer_credit_entry_requests is read by no client role';
end $$;

rollback;
