-- Only an Owner or Manager makes a credit package, premium bundle, voucher or
-- therapy line free of charge (507).
--
-- A line of these kinds made free still gives its credit, voucher or sessions
-- (355), so making it free is the same as giving value away. Here:
--   1 Make FOC (apply_line_foc): Staff are refused on a credit package, a
--     premium bundle, a voucher and a therapy line, and the line stays charged.
--   2 An Owner and a Manager are not stopped by the new test.
--   3 Staff make a product line free as before.
--   4 New Invoice (create_invoice): Staff are refused a voucher or therapy line
--     sent free (by foc_quantity or is_foc); a product line free is saved; a
--     Manager saves a voucher line free.
--   5 Edit Invoice (update_invoice, so update_invoice_internal): on the
--     Manager's invoice with a free voucher line, Staff change the product line
--     and the free voucher line is kept as it is; Staff are refused adding a new
--     free voucher line or changing the free voucher line; a Manager may.
--
--   psql (disposable copy) -f scripts/invoices/tests/foc-credit-lines-507.sql
--   sh scripts/invoices/local-sql.sh -f scripts/invoices/tests/foc-credit-lines-507.sql
-- 507 is installed here when it is not in yet. Disposable local database only;
-- everything is rolled back. Made-up records only (F507, @example.invalid).
-- The fixture's credit lines are product lines whose kind is changed with the
-- triggers off: only the kind matters to the test under review.
\set ON_ERROR_STOP on
begin;
select position('507:' in pg_get_functiondef('public.apply_line_foc(uuid,integer,uuid,text)'::regprocedure)) > 0 as m507_in \gset
\if :m507_in
\else
\ir ../../../supabase/507_only_an_owner_or_manager_gives_credit_away_free.sql
\endif
create function pg_temp.check(ok boolean, msg text) returns void language plpgsql as
$f$ begin if ok is distinct from true then raise exception 'FAIL: %', msg; end if; raise notice 'PASS  %', msg; end $f$;
create temp table f507(k text primary key, id uuid not null);
create function pg_temp.fx(p_k text) returns uuid language sql as $f$ select id from f507 where k = p_k $f$;
create function pg_temp.as_user(p_who text) returns void language plpgsql as $f$
begin
  perform set_config('request.jwt.claim.sub', pg_temp.fx(p_who)::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', pg_temp.fx(p_who), 'role', 'authenticated')::text, true);
end $f$;
-- Run a statement; answer 'ok' or the refusal's SQLSTATE and words.
create function pg_temp.try(q text) returns text language plpgsql as $f$
begin execute q; return 'ok'; exception when others then return sqlstate || ' ' || sqlerrm; end $f$;
create function pg_temp.lines(inv uuid) returns jsonb language sql as
$f$ select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('invoice_item_id', id, 'kind', line_kind::text,
     'product_id', product_id, 'voucher_id', voucher_id, 'therapy_service_id', therapy_service_id,
     'quantity', quantity, 'unit_price', unit_price,
     'foc_quantity', nullif(foc_quantity, 0), 'foc_reason', foc_reason)) order by line_kind, id)
     from public.invoice_items where invoice_id = inv $f$;

\set refused '42501 Only an Owner or Manager can make a Credit Package, Premium Bundle, voucher or therapy line free of charge.'

do $$
declare own uuid := gen_random_uuid(); mgr uuid := gen_random_uuid(); stf uuid := gen_random_uuid();
        st uuid; cust uuid; prod uuid; vch uuid; ts uuid; inv uuid; inv2 uuid; l_pkg uuid; l_bun uuid; l_prod uuid;
begin
  insert into auth.users(id, email, email_confirmed_at) values
    (own, 'f507-owner@example.invalid', now()), (mgr, 'f507-manager@example.invalid', now()), (stf, 'f507-staff@example.invalid', now());
  insert into public.profiles(id, full_name, email, role, is_active) values
    (own, 'F507 Owner', 'f507-owner@example.invalid', 'owner', true),
    (mgr, 'F507 Manager', 'f507-manager@example.invalid', 'manager', true),
    (stf, 'F507 Staff', 'f507-staff@example.invalid', 'staff', true);
  perform set_config('request.jwt.claim.sub', own::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', own, 'role', 'authenticated')::text, true);
  insert into public.stores(name, code, country_code) values ('F507 Store', 'F507', 'SG') returning id into st;
  insert into public.user_store_assignments(user_id, store_id) values (stf, st), (mgr, st);
  insert into public.customers(full_name, phone) values ('F507 Customer', '+61491570507') returning id into cust;
  insert into public.products(name, sku) values ('F507 Item', 'F507-1') returning id into prod;
  insert into public.store_inventory(store_id, product_id, current_qty) values (st, prod, 10);
  perform public.set_product_prices(st, prod, 50, 50, 'available');
  insert into public.vouchers(name, code, voucher_kind, selling_price, qty_type)
    values ('F507 Voucher', 'F507V', 'normal', 40, 'limited') returning id into vch;
  insert into public.voucher_store_stock(voucher_id, store_id, current_qty) values (vch, st, 20);
  insert into public.voucher_store_prices(voucher_id, store_id, selling_price, available_at_store) values (vch, st, 40, true);
  insert into public.therapy_services(service_code, name, standard_price, duration_minutes, is_active)
    values ('F507S', 'F507 Session', 30, 30, true) returning id into ts;
  insert into public.therapy_service_stores(service_id, store_id) values (ts, st);

  -- An unpaid invoice by the Owner: three product lines (two become a credit
  -- package and a premium bundle line), a voucher line and a therapy line.
  inv := public.create_invoice(st, cust, null, jsonb_build_array(
    jsonb_build_object('kind','product','product_id',prod,'quantity',1),
    jsonb_build_object('kind','product','product_id',prod,'quantity',1),
    jsonb_build_object('kind','product','product_id',prod,'quantity',1)));
  select (array_agg(id order by id))[1], (array_agg(id order by id))[2], (array_agg(id order by id))[3]
    into l_pkg, l_bun, l_prod from public.invoice_items where invoice_id = inv;
  set local session_replication_role = replica;
  update public.invoice_items set line_kind = 'credit_package' where id = l_pkg;
  update public.invoice_items set line_kind = 'premium_bundle' where id = l_bun;
  set local session_replication_role = origin;
  inv2 := public.create_invoice(st, cust, null, jsonb_build_array(
    jsonb_build_object('kind','voucher','voucher_id',vch,'quantity',1),
    jsonb_build_object('kind','therapy','therapy_service_id',ts,'quantity',1)));
  insert into f507 values ('own', own), ('mgr', mgr), ('stf', stf), ('pkg', l_pkg), ('bun', l_bun), ('prod', l_prod),
    ('st', st), ('cust', cust), ('prodid', prod), ('vch', vch), ('ts', ts),
    ('vline', (select id from public.invoice_items where invoice_id = inv2 and line_kind = 'voucher')),
    ('tline', (select id from public.invoice_items where invoice_id = inv2 and line_kind = 'therapy'));
end $$;

-- Make FOC as a login.
create function pg_temp.foc(p_who text, p_line text) returns text language plpgsql as $f$
begin
  perform pg_temp.as_user(p_who);
  return pg_temp.try(format('select public.apply_line_foc(%L, null, null, %L)', pg_temp.fx(p_line), 'F507 check'));
end $f$;

-- 1 Make FOC: Staff are refused on each of the four kinds.
select pg_temp.check(pg_temp.foc('stf', 'pkg') = :'refused', '1 Staff are refused Make FOC on a Credit Package line');
select pg_temp.check(pg_temp.foc('stf', 'bun') = :'refused', '1 Staff are refused Make FOC on a Premium Bundle line');
select pg_temp.check(pg_temp.foc('stf', 'vline') = :'refused', '1 Staff are refused Make FOC on a voucher line');
select pg_temp.check(pg_temp.foc('stf', 'tline') = :'refused', '1 Staff are refused Make FOC on a therapy line');
select pg_temp.check((select bool_and(coalesce(foc_quantity, 0) = 0) from public.invoice_items
                       where id in (pg_temp.fx('pkg'), pg_temp.fx('bun'), pg_temp.fx('vline'), pg_temp.fx('tline'))),
  '1 and none of those lines is free');

-- 2 An Owner and a Manager pass the new test (the rest of Make FOC decides).
select pg_temp.check(pg_temp.foc('mgr', 'pkg') not like '%Only an Owner or Manager can make%',
  '2 a Manager is not stopped by the new test on a Credit Package line (answer: ' || pg_temp.foc('mgr', 'pkg') || ')');
select pg_temp.check(pg_temp.foc('own', 'bun') not like '%Only an Owner or Manager can make%',
  '2 an Owner is not stopped by the new test on a Premium Bundle line (answer: ' || pg_temp.foc('own', 'bun') || ')');
select pg_temp.check(pg_temp.foc('mgr', 'vline') = 'ok', '2 a Manager makes a voucher line free');
select pg_temp.check(pg_temp.foc('own', 'tline') = 'ok', '2 an Owner makes a therapy line free');

-- 3 Staff make a product line free as before.
select pg_temp.check(pg_temp.foc('stf', 'prod') = 'ok', '3 Staff make a product line free as before');

-- 4 New Invoice.
create function pg_temp.new_inv(p_who text, p_items jsonb) returns text language plpgsql as $f$
begin
  perform pg_temp.as_user(p_who);
  return pg_temp.try(format('select public.create_invoice(%L, %L, null, %L::jsonb)', pg_temp.fx('st'), pg_temp.fx('cust'), p_items));
end $f$;
select pg_temp.check(pg_temp.new_inv('stf', jsonb_build_array(
    jsonb_build_object('kind','voucher','voucher_id',pg_temp.fx('vch'),'quantity',2,'foc_quantity',1,'foc_reason','F507 gift'))) = :'refused',
  '4 Staff are refused a new invoice with a voucher line partly free');
select pg_temp.check(pg_temp.new_inv('stf', jsonb_build_array(
    jsonb_build_object('kind','product','product_id',pg_temp.fx('prodid'),'quantity',1),
    jsonb_build_object('kind','therapy','therapy_service_id',pg_temp.fx('ts'),'quantity',1,'is_foc',true,'foc_reason','F507 gift'))) = :'refused',
  '4 Staff are refused a new invoice with a therapy line free (is_foc)');
select pg_temp.check(pg_temp.new_inv('stf', jsonb_build_array(
    jsonb_build_object('kind','product','product_id',pg_temp.fx('prodid'),'quantity',1,'is_foc',true,'foc_reason','F507 gift'),
    jsonb_build_object('kind','voucher','voucher_id',pg_temp.fx('vch'),'quantity',1))) = 'ok',
  '4 Staff save a new invoice with a product line free and a voucher line charged');
select pg_temp.check(pg_temp.new_inv('mgr', jsonb_build_array(
    jsonb_build_object('kind','product','product_id',pg_temp.fx('prodid'),'quantity',1),
    jsonb_build_object('kind','voucher','voucher_id',pg_temp.fx('vch'),'quantity',2,'foc_quantity',2,'foc_reason','F507 gift'))) = 'ok',
  '4 a Manager saves a new invoice with a voucher line free');

-- 5 Edit Invoice on the Manager's invoice (its free voucher line and a product line).
insert into f507 select 'inv5', i.id from public.invoices i join public.invoice_items ii on ii.invoice_id = i.id
 where ii.line_kind = 'voucher' and ii.foc_quantity = 2 and i.store_id = pg_temp.fx('st');
create function pg_temp.edit(p_who text, p_items jsonb) returns text language plpgsql as $f$
begin
  perform pg_temp.as_user(p_who);
  return pg_temp.try(format('select public.update_invoice(%L, %L, null, %L::jsonb, 0, null, null, %L::jsonb, %L)',
    pg_temp.fx('inv5'), pg_temp.fx('cust'), p_items, '[]', 'F507 edit'));
end $f$;
-- lines(inv5): [product, voucher] (ordered by kind)
select pg_temp.check(pg_temp.edit('stf', jsonb_set(pg_temp.lines(pg_temp.fx('inv5')), '{0,quantity}', '2')) = 'ok',
  '5 Staff change the product line; the free voucher line kept as it is passes');
select pg_temp.check((select foc_quantity = 2 from public.invoice_items where invoice_id = pg_temp.fx('inv5') and line_kind = 'voucher'),
  '5 and the voucher line is still free');
select pg_temp.check(pg_temp.edit('stf', pg_temp.lines(pg_temp.fx('inv5')) || jsonb_build_array(
    jsonb_build_object('kind','voucher','voucher_id',pg_temp.fx('vch'),'quantity',1,'foc_quantity',1,'foc_reason','F507 gift'))) = :'refused',
  '5 Staff are refused adding a new free voucher line');
select pg_temp.check(pg_temp.edit('stf', jsonb_set(jsonb_set(pg_temp.lines(pg_temp.fx('inv5')), '{1,quantity}', '3'), '{1,foc_quantity}', '3')) = :'refused',
  '5 Staff are refused changing the free voucher line');
select pg_temp.check(pg_temp.edit('stf', jsonb_set(pg_temp.lines(pg_temp.fx('inv5')), '{1}', (pg_temp.lines(pg_temp.fx('inv5'))->1) - 'foc_quantity' - 'foc_reason')) = 'ok',
  '5 Staff may take the FOC off the voucher line (it is charged again)');
select pg_temp.check((select coalesce(foc_quantity, 0) = 0 from public.invoice_items where invoice_id = pg_temp.fx('inv5') and line_kind = 'voucher'),
  '5 and the voucher line is charged');
select pg_temp.check(pg_temp.edit('mgr', jsonb_set(pg_temp.lines(pg_temp.fx('inv5')), '{1}', (pg_temp.lines(pg_temp.fx('inv5'))->1) || '{"foc_quantity":1,"foc_reason":"F507 gift"}')) = 'ok',
  '5 a Manager makes the voucher line free in Edit Invoice');
rollback;
