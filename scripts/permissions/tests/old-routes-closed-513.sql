-- The old invoice and transfer routes are closed to logins (513).
--
-- Signed-in logins can no longer call create_invoice, update_invoice or the
-- one-off repair_create_invoice_package_branches(); New Invoice and Edit
-- Invoice still work through the pages' routes, run here as a real signed-in
-- login (the authenticated role, row rules on). Staff can no longer choose
-- where stock comes from with create_transfer_request; they ask with
-- create_staff_transfer_request, as the Transfers page does, and everyone
-- else uses create_transfer_request as before.
--
--   sh scripts/invoices/local-sql.sh -f scripts/permissions/tests/old-routes-closed-513.sql
-- 513 is installed here when it is not in yet. Disposable local database only;
-- everything is rolled back. Made-up records only (L513, @example.invalid).
\set ON_ERROR_STOP on
begin;
-- 540 (security audit of 17 Nov 2026, M13: "Stock only") changed functions this file pins; it
-- changes nothing an Owner, a Manager or Staff are answered. Where it is in, its UNDO goes first
-- (this run only, rolled back with everything here).
select to_regprocedure('public.inventory_manager_guard(text)') is not null as t540_in \gset
\if :t540_in
-- 547 (goods collected for special, consignment and rental items): where it is in, its UNDO goes
-- first of all, before 546's.
select to_regprocedure('public.invoice_special_collect_internal(uuid,uuid,jsonb)') is not null as t547_in \gset
\if :t547_in
select set_config('energia.undo547_test_only', 'on', true) \g /dev/null
\ir ../../special/undo-547.sql
\endif
-- 546 (security audit of 17 Nov 2026, L15): where it is in, its UNDO goes first of all.
select coalesce('search_path=public, pg_temp' = any (proconfig), false) as t546_in
  from pg_proc where oid = 'public.current_user_role()'::regprocedure \gset
\if :t546_in
select set_config('energia.undo546_skip_body_check', 'on', true) \g /dev/null
\ir ../undo-546.sql
\endif
-- 541, 542 (security audit of 17 Nov 2026, Lows): where they are in, their UNDOs go first, as 540's needs.
select to_regprocedure('public.invoice_line_holds_stock(uuid,uuid)') is not null as t542_in,
       position('541 (security audit' in pg_get_functiondef('public.record_document_send(text,text,text,uuid,uuid,text,text,text,text)'::regprocedure)) > 0 as t541_in \gset
\if :t542_in
\ir ../../invoice-actions/undo-542.sql
\endif
\if :t541_in
\ir ../undo-541.sql
\endif
\ir ../../customers/undo-540.sql
\endif
select position('513:' in pg_get_functiondef('public.create_transfer_request(text,text,uuid,text,uuid,jsonb,text)'::regprocedure)) > 0 as m513_in \gset
\if :m513_in
\else
\ir ../../../supabase/513_old_invoice_and_transfer_routes_are_closed.sql
\endif
-- A second run changes nothing, while what 513 relies on is as it found it. 516 (17 Nov
-- 2026) changes create_invoice_with_details, and 513 then rightly refuses to run again.
select md5(pg_get_functiondef('public.create_invoice_with_details(uuid,uuid,jsonb,jsonb)'::regprocedure))
       = '0ac29c7aa909dd756ec572645ca86448' as m513_rerun \gset
\if :m513_rerun
\ir ../../../supabase/513_old_invoice_and_transfer_routes_are_closed.sql
\endif

create function pg_temp.check(ok boolean, msg text) returns void language plpgsql as
$f$ begin if ok is distinct from true then raise exception 'FAIL: %', msg; end if; raise notice 'PASS  %', msg; end $f$;
create temp table l513(k text primary key, id uuid not null);
create function pg_temp.fx(p_k text) returns uuid language sql as $f$ select id from l513 where k = p_k $f$;
-- Runs one statement as a signed-in login (the authenticated role, row rules on) and
-- answers its first column as text, or 'ERR <sqlstate> <message>'. Nothing it did is kept
-- on an error.
create function pg_temp.as_login(p_who text, q text) returns text language plpgsql as $f$
declare v text; u uuid := pg_temp.fx(p_who);
begin
  perform set_config('request.jwt.claim.sub', u::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', u, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  execute q into v;
  execute 'reset role';
  return coalesce(v, 'ok');
exception when others then return 'ERR ' || sqlstate || ' ' || sqlerrm;
end $f$;

\set staff_refused 'ERR 42501 Staff ask for stock with New Transfer on the Transfers page; an Owner or Manager chooses where it comes from.'

do $$
declare own uuid := gen_random_uuid(); mgr uuid := gen_random_uuid(); im uuid := gen_random_uuid(); stf uuid := gen_random_uuid();
        sa uuid; sb uuid; wh uuid; prod uuid; cust uuid;
begin
  insert into auth.users(id, email, email_confirmed_at) values
    (own, 'l513-owner@example.invalid', now()), (mgr, 'l513-manager@example.invalid', now()),
    (im, 'l513-invman@example.invalid', now()), (stf, 'l513-staff@example.invalid', now());
  insert into public.profiles(id, full_name, email, role, is_active) values
    (own, 'L513 Owner', 'l513-owner@example.invalid', 'owner', true),
    (mgr, 'L513 Manager', 'l513-manager@example.invalid', 'manager', true),
    (im, 'L513 Inventory Manager', 'l513-invman@example.invalid', 'inventory_manager', true),
    (stf, 'L513 Staff', 'l513-staff@example.invalid', 'staff', true);
  perform set_config('request.jwt.claim.sub', own::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', own, 'role', 'authenticated')::text, true);
  insert into public.stores(name, code, country_code) values ('L513 Store A', 'L513A', 'SG') returning id into sa;
  insert into public.stores(name, code, country_code) values ('L513 Store B', 'L513B', 'SG') returning id into sb;
  insert into public.warehouses(name, code) values ('L513 Warehouse', 'L513W') returning id into wh;
  insert into public.user_store_assignments(user_id, store_id) values (stf, sa), (mgr, sa), (im, sa);
  insert into public.products(name, sku) values ('L513 Item', 'L513-1') returning id into prod;
  insert into public.store_inventory(store_id, product_id, current_qty) values (sa, prod, 10), (sb, prod, 10);
  insert into public.warehouse_inventory(warehouse_id, product_id, current_qty) values (wh, prod, 10);
  perform public.set_product_prices(sa, prod, 50, 50, 'available');
  perform public.set_product_prices(sb, prod, 50, 50, 'available');
  insert into public.customers(full_name, phone) values ('L513 Customer', '+61491570513') returning id into cust;
  insert into l513 values ('owner', own), ('manager', mgr), ('invman', im), ('staff', stf),
    ('sa', sa), ('sb', sb), ('wh', wh), ('prod', prod), ('cust', cust);
end $$;

-- 1. Rights
select pg_temp.check(not has_function_privilege('authenticated', to_regprocedure('public.' || f), 'execute')
                     and not has_function_privilege('anon', to_regprocedure('public.' || f), 'execute')
                     and has_function_privilege('service_role', to_regprocedure('public.' || f), 'execute'),
  '1a signed-in logins and anon cannot call ' || f || '; the service role can')
  from unnest(array['create_invoice(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb)',
                    'update_invoice(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb,text)',
                    'repair_create_invoice_package_branches()']) f;
select pg_temp.check(has_function_privilege('authenticated', to_regprocedure('public.' || f), 'execute')
                     and not has_function_privilege('anon', to_regprocedure('public.' || f), 'execute'),
  '1b signed-in logins still call ' || f)
  from unnest(array['create_invoice_with_details(uuid,uuid,jsonb,jsonb)', 'correct_invoice(uuid,jsonb,jsonb,text,uuid)',
                    'create_transfer_request(text,text,uuid,text,uuid,jsonb,text)', 'create_staff_transfer_request(jsonb,text,uuid)']) f;

-- 2. The old invoice routes, called by a login, are refused before they run
select pg_temp.check(v like 'ERR 42501 permission denied for function create_invoice%',
  '2a an Owner calling create_invoice directly is refused: ' || v)
  from pg_temp.as_login('owner', format($q$select public.create_invoice(%L, %L, null,
         jsonb_build_array(jsonb_build_object('kind', 'product', 'product_id', %L, 'quantity', 1)), 0, null, null, '{}'::jsonb)::text$q$,
         pg_temp.fx('sa'), pg_temp.fx('cust'), pg_temp.fx('prod'))) v;
select pg_temp.check(v like 'ERR 42501 permission denied for function update_invoice%',
  '2b Staff calling update_invoice directly are refused: ' || v)
  from pg_temp.as_login('staff', format($q$select public.update_invoice(%L, %L, null, '[]'::jsonb, 0, null, null, '{}'::jsonb, 'x')::text$q$,
         gen_random_uuid(), pg_temp.fx('cust'))) v;
select pg_temp.check(v like 'ERR 42501 permission denied for function repair_create_invoice_package_branches%',
  '2c an Owner calling the repair is refused: ' || v)
  from pg_temp.as_login('owner', 'select public.repair_create_invoice_package_branches()::text') v;
select pg_temp.check(not exists (select 1 from public.invoices where customer_id = pg_temp.fx('cust')), '2d and no invoice was made');

-- 3. New Invoice and Edit Invoice still work through the pages' routes, as a login
select pg_temp.check(v ~ '^[0-9a-f-]{36}$', '3a Staff make an invoice with New Invoice (create_invoice_with_details): ' || v)
  from pg_temp.as_login('staff', format($q$select public.create_invoice_with_details(%L, %L,
         jsonb_build_array(jsonb_build_object('kind', 'product', 'product_id', %L, 'quantity', 1)),
         jsonb_build_object('business_date', public.sg_today()))::text$q$,
         pg_temp.fx('sa'), pg_temp.fx('cust'), pg_temp.fx('prod'))) v;
insert into l513 select 'inv', id from public.invoices where customer_id = pg_temp.fx('cust');
select pg_temp.check((select count(*) from public.invoice_items where invoice_id = pg_temp.fx('inv') and quantity = 1) = 1
                     and (select store_id = pg_temp.fx('sa') and created_by = pg_temp.fx('staff') from public.invoices where id = pg_temp.fx('inv')),
  '3b with its one line, at their store, made by them');
select pg_temp.check(v = 'ok', '3c Staff change it with Edit Invoice (correct_invoice): ' || v)
  from pg_temp.as_login('staff', format($q$select null::text from public.correct_invoice(%L,
         jsonb_build_array(jsonb_build_object('invoice_item_id', %L, 'kind', 'product', 'product_id', %L, 'quantity', 2)),
         '{}'::jsonb, null, gen_random_uuid())$q$,
         pg_temp.fx('inv'), (select id from public.invoice_items where invoice_id = pg_temp.fx('inv')), pg_temp.fx('prod'))) v;
select pg_temp.check((select quantity from public.invoice_items where invoice_id = pg_temp.fx('inv')) = 2, '3d the line now has 2');

-- 4. Transfers
select pg_temp.check(v = :'staff_refused', '4a Staff choosing a warehouse as the source are refused: ' || v)
  from pg_temp.as_login('staff', format($q$select public.create_transfer_request('warehouse_to_store', 'warehouse', %L, 'store', %L,
         jsonb_build_array(jsonb_build_object('product_id', %L, 'quantity', 1)), 'L513 staff')::text$q$,
         pg_temp.fx('wh'), pg_temp.fx('sa'), pg_temp.fx('prod'))) v;
select pg_temp.check(v = :'staff_refused', '4b Staff moving stock between stores themselves are refused: ' || v)
  from pg_temp.as_login('staff', format($q$select public.create_transfer_request('store_to_store', 'store', %L, 'store', %L,
         jsonb_build_array(jsonb_build_object('product_id', %L, 'quantity', 1)), 'L513 staff')::text$q$,
         pg_temp.fx('sa'), pg_temp.fx('sb'), pg_temp.fx('prod'))) v;
select pg_temp.check(v like '%choose Store → Warehouse%', '4c the checks of the two ends keep their own messages for Staff: ' || v)
  from pg_temp.as_login('staff', format($q$select public.create_transfer_request('store_to_store', 'store', %L, 'warehouse', %L,
         jsonb_build_array(jsonb_build_object('product_id', %L, 'quantity', 1)), null)::text$q$,
         pg_temp.fx('sa'), pg_temp.fx('wh'), pg_temp.fx('prod'))) v;
select pg_temp.check(v like '%"success": true%', '4d Staff ask for stock with New Transfer (create_staff_transfer_request): ' || v)
  from pg_temp.as_login('staff', format($q$select public.create_staff_transfer_request(
         jsonb_build_array(jsonb_build_object('product_id', %L, 'quantity', 1)), 'L513 staff ask', %L)::text$q$,
         pg_temp.fx('prod'), pg_temp.fx('sa'))) v;
select pg_temp.check((select count(*) from public.transfer_requests where requested_by = pg_temp.fx('staff')) = 1
                     and (select dest_id = pg_temp.fx('sa') and status = 'pending' from public.transfer_requests where requested_by = pg_temp.fx('staff')),
  '4e only that request was saved for Staff, pending, into their store');
select pg_temp.check(v like '%"success": true%', '4f ' || w || ' still sends stock from the warehouse with create_transfer_request: ' || v)
  from unnest(array['owner', 'manager', 'invman']) w,
       lateral pg_temp.as_login(w, format($q$select public.create_transfer_request('warehouse_to_store', 'warehouse', %L, 'store', %L,
         jsonb_build_array(jsonb_build_object('product_id', %L, 'quantity', 1)), %L)::text$q$,
         pg_temp.fx('wh'), pg_temp.fx('sa'), pg_temp.fx('prod'), 'L513 ' || w)) v;

-- 5. The functions
select pg_temp.check(md5(pg_get_functiondef('public.create_transfer_request(text,text,uuid,text,uuid,jsonb,text)'::regprocedure)) = 'ab4312ec8850847b9058d07776cb1d15',
  '5a create_transfer_request is 513''s');
-- (create_invoice_with_details: or 516's AFTER, 17 Nov 2026: it refuses a negative manual discount;
-- or 518's, 18 Nov 2026: and one that is not a number)
select pg_temp.check(md5(pg_get_functiondef(to_regprocedure('public.' || x.f))) = any (string_to_array(x.m, '|')), '5b unchanged: ' || x.f)
  from (values ('create_invoice_with_details(uuid,uuid,jsonb,jsonb)', '0ac29c7aa909dd756ec572645ca86448|7c37ac1d841d2c0c2a9cf9b54c563ead|0d60261bf337a1716dab9307b2f52fea'),
               ('correct_invoice(uuid,jsonb,jsonb,text,uuid)', 'cea93a5dd73d429f6437f4c9a8fcaa52|aaf592490eb5d13ca2ccb0544f48f647'),  -- or 528's (19 Nov 2026)
               ('create_staff_transfer_request(jsonb,text,uuid)', 'cc32ec91b2e223c67da957dd792af12e'),
               ('create_invoice(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb)', '42f00d595a40df157d28a7ea88fbe7ad'),
               ('update_invoice(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb,text)', '62734e08fe4de2d3af0e1e1dfa268f5b')) x(f, m);
rollback;
