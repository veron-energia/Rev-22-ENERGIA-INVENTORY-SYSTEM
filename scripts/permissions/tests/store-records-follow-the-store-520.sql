-- A store's operations and TikTok records are read by its own staff (520).
--
-- Stores A and B, each with rentals, special sales, stock uses, voucher stock and
-- a TikTok import (its batch, rows, order state and SKU alias). Each login reads
-- the tables straight through the API's rules (the authenticated role, row rules
-- on), as a page does: Staff and the Inventory Manager of store A see store A's
-- rows and none of store B's, except a rental or special sale whose stock comes
-- from store A; a Manager of store A, and the Owner, see both. The affiliate
-- totals of the Reports page are an Owner's, Admin's or Manager's. Customer and
-- price tables are unchanged.
--
--   sh scripts/invoices/local-sql.sh -f scripts/permissions/tests/store-records-follow-the-store-520.sql
-- 520 is installed here when it is not in yet. Disposable local database only;
-- everything is rolled back. Made-up records only (L520, @example.invalid).
\set ON_ERROR_STOP on
begin;
-- 540 (security audit of 17 Nov 2026, M13: "Stock only") changed the read rules this file pins
-- (rentals, special_sales and others); it changes nothing an Owner, a Manager or Staff are answered.
-- Where it is in, its UNDO goes first (this run only, rolled back with everything here).
select to_regprocedure('public.inventory_manager_guard(text)') is not null as t540_in \gset
\if :t540_in
\ir ../../customers/undo-540.sql
\endif
select (select pg_get_expr(p.polqual, p.polrelid) from pg_policy p
         where p.polrelid = 'public.voucher_store_stock'::regclass and p.polname = 'read voucher stock') like '%is_manager_or_above%' as m520_in \gset
\if :m520_in
\else
\ir ../../../supabase/520_store_records_follow_the_store.sql
\endif
-- A second run changes nothing.
\ir ../../../supabase/520_store_records_follow_the_store.sql

create function pg_temp.check(ok boolean, msg text) returns void language plpgsql as
$f$ begin if ok is distinct from true then raise exception 'FAIL: %', msg; end if; raise notice 'PASS  %', msg; end $f$;
create temp table l520(k text primary key, id uuid not null);
create function pg_temp.fx(p_k text) returns uuid language sql as $f$ select id from l520 where k = p_k $f$;
-- One statement as a signed-in login: its first column as text, or 'ERR <sqlstate> <message>'.
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
-- How many of the made-up rows of a store a login reads in a table: "A/B".
create function pg_temp.seen(p_who text, p_table text) returns text language sql as
$f$ select pg_temp.as_login(p_who, format('select count(*) filter (where store_id = %L)::text || ''/'' || count(*) filter (where store_id = %L)::text from public.%I where store_id in (%L, %L)',
     pg_temp.fx('sa'), pg_temp.fx('sb'), p_table, pg_temp.fx('sa'), pg_temp.fx('sb'))) $f$;

do $$
declare own uuid := gen_random_uuid(); mgr uuid := gen_random_uuid(); im uuid := gen_random_uuid(); stf uuid := gen_random_uuid();
        sa uuid; sb uuid; p uuid; sp uuid; v uuid; cust uuid; b uuid; k text; s uuid;
        sfx constant text := lower(substr(md5(gen_random_uuid()::text), 1, 6));
begin
  insert into auth.users(id, email, email_confirmed_at) values
    (own, 'l520-owner@example.invalid', now()), (mgr, 'l520-manager@example.invalid', now()),
    (im, 'l520-invman@example.invalid', now()), (stf, 'l520-staff@example.invalid', now());
  insert into public.profiles(id, full_name, email, role, is_active) values
    (own, 'L520 Owner', 'l520-owner@example.invalid', 'owner', true),
    (mgr, 'L520 Manager', 'l520-manager@example.invalid', 'manager', true),
    (im, 'L520 Inventory Manager', 'l520-invman@example.invalid', 'inventory_manager', true),
    (stf, 'L520 Staff', 'l520-staff@example.invalid', 'staff', true);
  perform set_config('request.jwt.claim.sub', own::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', own, 'role', 'authenticated')::text, true);
  insert into public.stores(name, code, country_code) values ('L520 Store A ' || sfx, 'L520A' || sfx, 'SG') returning id into sa;
  insert into public.stores(name, code, country_code) values ('L520 Store B ' || sfx, 'L520B' || sfx, 'SG') returning id into sb;
  -- Staff, the Inventory Manager and the Manager all work at store A only.
  insert into public.user_store_assignments(user_id, store_id) values (stf, sa), (im, sa), (mgr, sa);
  insert into public.products(name, sku) values ('L520 Soap ' || sfx, 'L520P' || sfx) returning id into p;
  insert into public.store_inventory(store_id, product_id, current_qty) values (sa, p, 20), (sb, p, 20);
  perform public.set_product_prices(sa, p, 50, 50, 'available');
  perform public.set_product_prices(sb, p, 50, 50, 'available');
  insert into public.special_products(name, sku, product_id) values ('L520 Chair ' || sfx, 'L520S' || sfx, p) returning id into sp;
  insert into public.vouchers(name, code, voucher_kind, qty_type, selling_price, is_active)
    values ('L520 Voucher ' || sfx, 'L520V' || sfx, 'normal', 'limited', 30, true) returning id into v;
  insert into public.customers(full_name, phone) values ('L520 Customer', '+61491570520') returning id into cust;
  insert into l520 values ('owner', own), ('manager', mgr), ('invman', im), ('staff', stf), ('sa', sa), ('sb', sb);
  foreach k in array array['a', 'b'] loop
    s := case k when 'a' then sa else sb end;
    insert into public.voucher_store_stock(voucher_id, store_id, current_qty) values (v, s, 5);
    insert into public.stock_uses(location_type, store_id, product_id, quantity, reason) values ('store', s, p, 1, 'L520 tester');
    insert into public.rentals(rental_no, special_product_id, customer_id, quantity, rate_type, periods, start_date, expected_return_date, store_id, source_store_id)
      values ('L520R' || k || sfx, sp, cust, 1, 'day', 1, current_date, current_date + 1, s, s);
    insert into public.special_sales(sale_no, special_product_id, quantity, store_id, source_store_id)
      values ('L520S' || k || sfx, sp, 1, s, s);
    insert into public.tiktok_sku_aliases(store_id, seller_sku, target_kind, target_id, created_by)
      values (s, 'L520-SOAP-' || k || '-' || sfx, 'product', p, own);
    b := public.stage_tiktok_orders(s, 'L520 ' || k || '.csv', null, jsonb_build_array(jsonb_build_object(
           'order_id', 'L520-' || k || '-' || sfx, 'seller_sku', 'L520-SOAP-' || k || '-' || sfx, 'quantity', '1',
           'order_status', 'L520 To ship ' || sfx, 'product_name', 'L520 soap')));
    insert into l520 values ('batch_' || k, b);
  end loop;
  -- A rental and a special sale at store B whose stock comes from store A.
  insert into public.rentals(rental_no, special_product_id, customer_id, quantity, rate_type, periods, start_date, expected_return_date, store_id, source_store_id)
    values ('L520RX' || sfx, sp, cust, 1, 'day', 1, current_date, current_date + 1, sb, sa);
  insert into public.special_sales(sale_no, special_product_id, quantity, store_id, source_store_id)
    values ('L520SX' || sfx, sp, 1, sb, sa);
end $$;

-- 1. Staff and the Inventory Manager of store A: store A's rows, none of store B's
select pg_temp.check(pg_temp.seen(w, t) = '1/0', '1a ' || w || ' of store A reads ' || t || ': ' || pg_temp.seen(w, t))
  from unnest(array['staff', 'invman']) w, unnest(array['voucher_store_stock', 'stock_uses', 'tiktok_import_batches', 'tiktok_order_rows', 'tiktok_sku_aliases']) t;
-- A rental or special sale: its own store's, and store A's stock lent to store B.
select pg_temp.check(pg_temp.seen(w, t) = '1/1', '1b ' || w || ' of store A reads ' || t || ' at A, and at B with stock from A: ' || pg_temp.seen(w, t))
  from unnest(array['staff', 'invman']) w, unnest(array['rentals', 'special_sales']) t;
select pg_temp.check(pg_temp.as_login('staff', format('select count(*)::text from public.rentals where store_id = %L and source_store_id = %L', pg_temp.fx('sb'), pg_temp.fx('sb'))) = '0',
  '1c but not a rental of store B from store B''s own stock');

-- 2. A Manager of store A, and the Owner: every store
select pg_temp.check(pg_temp.seen(w, t) in ('1/1', '1/2'), '2a ' || w || ' reads ' || t || ' at both stores: ' || pg_temp.seen(w, t))
  from unnest(array['manager', 'owner']) w,
       unnest(array['voucher_store_stock', 'stock_uses', 'tiktok_import_batches', 'tiktok_order_rows', 'tiktok_sku_aliases', 'rentals', 'special_sales']) t;

-- 3. Customer and price tables are unchanged: Staff of store A still read store B's prices
select pg_temp.check(pg_temp.seen('staff', 'store_product_prices') = '1/1', '3a Staff of store A still read store B''s product prices: ' || pg_temp.seen('staff', 'store_product_prices'));

-- 4. The Reports page's affiliate totals: an Owner's, Admin's or Manager's
select pg_temp.check(pg_temp.as_login(w, 'select count(*)::text from public.report_affiliates()') = 'ERR 42501 Your role cannot do this.',
  '4a ' || w || ' is refused the affiliate totals')
  from unnest(array['staff', 'invman']) w;
select pg_temp.check(pg_temp.as_login(w, 'select count(*)::text from public.report_affiliates()') !~ '^ERR', '4b ' || w || ' still reads them')
  from unnest(array['manager', 'owner']) w;

-- 5. The rules and the function
select pg_temp.check(pg_get_expr(p.polqual, p.polrelid) like '%is_manager_or_above%current_user_store_ids%'
                     and p.polcmd = 'r' and p.polroles = array['authenticated'::regrole::oid],
  '5a ' || p.polrelid::regclass::text || ': "' || p.polname || '" lets an Owner, Admin or Manager, or the store''s own staff, read')
  from pg_policy p
 where (p.polrelid::regclass::text, p.polname) in (('rentals', 'read rentals'), ('special_sales', 'read special sales'),
        ('stock_uses', 'read stock uses'), ('voucher_store_stock', 'read voucher stock'), ('tiktok_corrections', 'read tiktok_corrections'),
        ('tiktok_import_batches', 'read tiktok_import_batches'), ('tiktok_order_rows', 'read tiktok_order_rows'),
        ('tiktok_order_state', 'read tiktok_order_state'), ('tiktok_physical_returns', 'read tiktok_physical_returns'),
        ('tiktok_settlement_rows', 'read tiktok_settlement_rows'), ('tiktok_voucher_sales', 'read tiktok_voucher_sales'),
        ('tiktok_sku_aliases', 'read tiktok_sku_aliases'));
select pg_temp.check((select count(*) from pg_policy p
                       where p.polname in ('read rentals', 'read special sales', 'read stock uses', 'read voucher stock', 'read tiktok_corrections',
                                           'read tiktok_import_batches', 'read tiktok_order_rows', 'read tiktok_order_state', 'read tiktok_physical_returns',
                                           'read tiktok_settlement_rows', 'read tiktok_voucher_sales', 'read tiktok_sku_aliases')
                         and pg_get_expr(p.polqual, p.polrelid) like '%is_manager_or_above%current_user_store_ids%') = 12,
  '5c all twelve rules are 520''s');
select pg_temp.check(md5(pg_get_functiondef('public.report_affiliates()'::regprocedure)) = '5e69835b8ecdfaab0a86aa25da04acc4'
                     and has_function_privilege('authenticated', 'public.report_affiliates()', 'execute'),
  '5b report_affiliates is 520''s, its rights as before');
rollback;
