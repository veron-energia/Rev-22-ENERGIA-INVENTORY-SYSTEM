-- An Inventory Manager's TikTok work, and each login's stock alert, keep to their stores (521).
--
-- Stores A and B, each with a staged TikTok order file (an unmatched SKU), a product and a
-- voucher below zero, and a data-removal log row. Staff, an Inventory Manager and a Manager
-- work at store A only. Each login calls the functions as a page does (the authenticated
-- role): an Inventory Manager imports and maps SKUs at store A and is refused at store B, as
-- Staff are, and reads store A's in the TikTok reports; a Manager and the Owner work at and
-- read both. The negative-stock alert lists each login's stores (every store for a Manager
-- and the Owner), and the Dashboard's count follows it. The data-removal log is read by the
-- Manager and the Owner, not by Staff or the Inventory Manager.
--
--   sh scripts/invoices/local-sql.sh -f scripts/permissions/tests/tiktok-and-alerts-follow-the-store-521.sql
-- 521 is installed here when it is not in yet. Disposable local database only;
-- everything is rolled back. Made-up records only (L521, @example.invalid).
\set ON_ERROR_STOP on
begin;
select position('521:' in pg_get_functiondef('public.tiktok_access_check(uuid)'::regprocedure)) > 0 as m521_in \gset
\if :m521_in
\else
\ir ../../../supabase/521_tiktok_imports_and_alerts_follow_the_store.sql
\endif
-- A second run changes nothing.
\ir ../../../supabase/521_tiktok_imports_and_alerts_follow_the_store.sql

create function pg_temp.check(ok boolean, msg text) returns void language plpgsql as
$f$ begin if ok is distinct from true then raise exception 'FAIL: %', msg; end if; raise notice 'PASS  %', msg; end $f$;
create temp table l521(k text primary key, v text not null);
create function pg_temp.fx(p_k text) returns text language sql as $f$ select v from l521 where k = p_k $f$;
-- One statement as a signed-in login: its first column as text, or 'ERR <sqlstate> <message>'.
create function pg_temp.as_login(p_who text, q text) returns text language plpgsql as $f$
declare v text; u uuid := pg_temp.fx(p_who)::uuid;
begin
  perform set_config('request.jwt.claim.sub', u::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', u, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  execute q into v;
  execute 'reset role';
  return coalesce(v, 'ok');
exception when others then return 'ERR ' || sqlstate || ' ' || sqlerrm;
end $f$;
-- How many of a query's rows name store A and store B: "A/B".
create function pg_temp.by_store(p_who text, p_from text) returns text language sql as
$f$ select pg_temp.as_login(p_who, format('select count(*) filter (where store_name = %L)::text || ''/'' || count(*) filter (where store_name = %L)::text from %s',
     pg_temp.fx('name_a'), pg_temp.fx('name_b'), p_from)) $f$;
-- A one-row TikTok order file, in a status of its own that takes no stock.
create function pg_temp.order_file(p_order text, p_sku text) returns text language sql as
$f$ select jsonb_build_array(jsonb_build_object('order_id', p_order, 'seller_sku', p_sku, 'quantity', '1',
     'order_status', 'L521 To ship ' || pg_temp.fx('sfx'), 'product_name', 'L521 soap'))::text $f$;

do $$
declare own uuid := gen_random_uuid(); mgr uuid := gen_random_uuid(); im uuid := gen_random_uuid(); stf uuid := gen_random_uuid();
        sa uuid; sb uuid; p uuid; v uuid; k text; s uuid;
        sfx constant text := lower(substr(md5(gen_random_uuid()::text), 1, 6));
begin
  insert into auth.users(id, email, email_confirmed_at) values
    (own, 'l521-owner@example.invalid', now()), (mgr, 'l521-manager@example.invalid', now()),
    (im, 'l521-invman@example.invalid', now()), (stf, 'l521-staff@example.invalid', now());
  insert into public.profiles(id, full_name, email, role, is_active) values
    (own, 'L521 Owner', 'l521-owner@example.invalid', 'owner', true),
    (mgr, 'L521 Manager', 'l521-manager@example.invalid', 'manager', true),
    (im, 'L521 Inventory Manager', 'l521-invman@example.invalid', 'inventory_manager', true),
    (stf, 'L521 Staff', 'l521-staff@example.invalid', 'staff', true);
  perform set_config('request.jwt.claim.sub', own::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', own, 'role', 'authenticated')::text, true);
  insert into public.stores(name, code, country_code) values ('L521 Store A ' || sfx, 'L521A' || sfx, 'SG') returning id into sa;
  insert into public.stores(name, code, country_code) values ('L521 Store B ' || sfx, 'L521B' || sfx, 'SG') returning id into sb;
  -- Staff, the Inventory Manager and the Manager all work at store A only.
  insert into public.user_store_assignments(user_id, store_id) values (stf, sa), (im, sa), (mgr, sa);
  insert into public.products(name, sku) values ('L521 Soap ' || sfx, 'L521P' || sfx) returning id into p;
  insert into public.vouchers(name, code, voucher_kind, qty_type, selling_price, is_active)
    values ('L521 Voucher ' || sfx, 'L521V' || sfx, 'normal', 'limited', 30, true) returning id into v;
  -- Below zero at both stores (as only a confirmed TikTok sale may leave them).
  perform set_config('energia.tiktok_negative', 'allow', true);
  insert into public.store_inventory(store_id, product_id, current_qty) values (sa, p, -2), (sb, p, -3);
  insert into public.voucher_store_stock(voucher_id, store_id, current_qty) values (v, sa, -1), (v, sb, -4);
  perform set_config('energia.tiktok_negative', '', true);
  insert into l521 values ('owner', own::text), ('manager', mgr::text), ('invman', im::text), ('staff', stf::text),
    ('sa', sa::text), ('sb', sb::text), ('p', p::text), ('sfx', sfx),
    ('name_a', 'L521 Store A ' || sfx), ('name_b', 'L521 Store B ' || sfx);
  insert into public.tiktok_status_mappings(status_label, status_norm, action, marks_shipped)
    values ('L521 To ship ' || sfx, public.tiktok_norm_status('L521 To ship ' || sfx), 'none', false);
  foreach k in array array['a', 'b'] loop
    s := case k when 'a' then sa else sb end;
    -- A staged order file whose SKU is not mapped yet.
    perform public.stage_tiktok_orders(s, 'L521 setup ' || k || '.csv', null,
      pg_temp.order_file('L521-' || k || '-' || sfx, 'L521-NEW-' || k || '-' || sfx)::jsonb);
    insert into public.data_removal_reconciliation(category, store_id, note) values ('L521 removal', s, 'L521 ' || sfx);
  end loop;
end $$;

-- 0. What is there to read
select pg_temp.check(pg_temp.by_store('owner', 'public.report_tiktok_imports(null, null, null) where file_name like ''L521 setup%''') = '1/1',
  '0 the Owner sees a staged file at each store');

-- 1. The TikTok reports: an Inventory Manager reads their own stores, as Staff do
select pg_temp.check(pg_temp.by_store(w, 'public.report_tiktok_imports(null, null, null) where file_name like ''L521 setup%''') = x,
  '1a ' || w || ' of store A reads the import list: ' || pg_temp.by_store(w, 'public.report_tiktok_imports(null, null, null) where file_name like ''L521 setup%'''))
  from (values ('invman', '1/0'), ('staff', '1/0'), ('manager', '1/1'), ('owner', '1/1')) t(w, x);
select pg_temp.check(pg_temp.by_store('invman', format('public.report_tiktok_imports(%L, null, null) where file_name like ''L521 setup%%''', pg_temp.fx('sb'))) = '0/0',
  '1b the Inventory Manager asking for store B''s imports gets none');
select pg_temp.check(pg_temp.by_store(w, 'public.report_tiktok_unmatched_skus(null) where seller_sku like ''L521-NEW-%''') = x,
  '1c ' || w || ' reads the unmatched SKUs: ' || pg_temp.by_store(w, 'public.report_tiktok_unmatched_skus(null) where seller_sku like ''L521-NEW-%'''))
  from (values ('invman', '1/0'), ('staff', '1/0'), ('manager', '1/1'), ('owner', '1/1')) t(w, x);
select pg_temp.check(position('inventory_manager' in d) = 0
                     and (length(d) - length(replace(d, '-- 521: an Inventory Manager, their stores', ''))) / length('-- 521: an Inventory Manager, their stores') = x.n,
  '1d ' || x.f || ' no longer lets an Inventory Manager read every store (' || x.n || ' place(s))')
  from (values ('report_tiktok_import_discrepancies(uuid)', 1), ('report_tiktok_imports(uuid,date,date)', 1),
               ('report_tiktok_orders_by_status(uuid)', 1), ('report_tiktok_qty_sold(uuid,date,date)', 1),
               ('report_tiktok_recon_exceptions(uuid)', 3), ('report_tiktok_settlement(uuid,date,date)', 1),
               ('report_tiktok_settlement_by_store(date,date)', 1), ('report_tiktok_settlement_daily(uuid,date,date)', 1),
               ('report_tiktok_stock_activity(uuid,date,date)', 2), ('report_tiktok_unmatched_skus(uuid)', 1),
               ('tiktok_left_out_settlement(uuid,date,date)', 1), ('tiktok_settlement_eligible(uuid)', 1),
               ('tiktok_settlement_totals(integer,integer,uuid)', 1)) x(f, n),
       lateral (select pg_get_functiondef(to_regprocedure('public.' || x.f)) d) y;

-- 2. An Inventory Manager imports, and maps a SKU, at their own store only (as Staff)
select pg_temp.check(r !~ '^ERR', '2a the Inventory Manager of store A stages an order file at store A: ' || r)
  from pg_temp.as_login('invman', format('select public.stage_tiktok_orders(%L, ''L521 im a.csv'', null, %L::jsonb)::text',
         pg_temp.fx('sa'), pg_temp.order_file('L521-IM-A-' || pg_temp.fx('sfx'), 'L521-IM-A-' || pg_temp.fx('sfx')))) r;
select pg_temp.check(r = 'ERR P0001 You can only import TikTok sales for your assigned store',
  '2b ... and is refused at store B: ' || r)
  from pg_temp.as_login('invman', format('select public.stage_tiktok_orders(%L, ''L521 im b.csv'', null, %L::jsonb)::text',
         pg_temp.fx('sb'), pg_temp.order_file('L521-IM-B-' || pg_temp.fx('sfx'), 'L521-IM-B-' || pg_temp.fx('sfx')))) r;
select pg_temp.check(r = 'ERR P0001 You can only import TikTok sales for your assigned store',
  '2c ... and cannot map a SKU at store B: ' || r)
  from pg_temp.as_login('invman', format('select public.upsert_tiktok_sku_alias(%L, %L, ''product'', %L)::text',
         pg_temp.fx('sb'), 'L521-NEW-b-' || pg_temp.fx('sfx'), pg_temp.fx('p'))) r;
select pg_temp.check(r !~ '^ERR', '2d ... but maps one at store A: ' || r)
  from pg_temp.as_login('invman', format('select public.upsert_tiktok_sku_alias(%L, %L, ''product'', %L)::text',
         pg_temp.fx('sa'), 'L521-NEW-a-' || pg_temp.fx('sfx'), pg_temp.fx('p'))) r;
select pg_temp.check(r = 'ERR P0001 You can only import TikTok sales for your assigned store', '2e Staff of store A are refused at store B, as before: ' || r)
  from pg_temp.as_login('staff', format('select public.stage_tiktok_orders(%L, ''L521 staff b.csv'', null, %L::jsonb)::text',
         pg_temp.fx('sb'), pg_temp.order_file('L521-ST-B-' || pg_temp.fx('sfx'), 'L521-ST-B-' || pg_temp.fx('sfx')))) r;
select pg_temp.check(r !~ '^ERR', '2f the Manager of store A, and the Owner, still import at store B: ' || w || ' ' || r)
  from unnest(array['manager', 'owner']) w,
       lateral pg_temp.as_login(w, format('select public.stage_tiktok_orders(%L, %L, null, %L::jsonb)::text',
         pg_temp.fx('sb'), 'L521 ' || w || ' b.csv', pg_temp.order_file('L521-' || w || '-B-' || pg_temp.fx('sfx'), 'L521-' || w || '-B-' || pg_temp.fx('sfx')))) r;

-- 3. The negative-stock alert: each login's stores; every store for a Manager and the Owner
select pg_temp.check(pg_temp.by_store(w, 'public.tiktok_negative_stock_alerts()') = x,
  '3a ' || w || ' of store A sees the stock below zero at: ' || pg_temp.by_store(w, 'public.tiktok_negative_stock_alerts()'))
  from (values ('staff', '2/0'), ('invman', '2/0'), ('manager', '2/2'), ('owner', '2/2')) t(w, x);
select pg_temp.check(pg_temp.as_login('staff', $q$select public.dashboard_alerts_summary() #>> '{tiktok,negative_stock}'$q$) = '2',
  '3b the Dashboard''s count for Staff of store A is store A''s two');
select pg_temp.check(pg_temp.as_login('owner', $q$select public.dashboard_alerts_summary() #>> '{tiktok,negative_stock}'$q$)
                     = pg_temp.as_login('owner', 'select count(*)::text from public.tiktok_negative_stock_alerts()'),
  '3c the Owner''s count is every store''s, as the list');

-- 4. The data-removal log: the Manager and the Owner
select pg_temp.check(pg_temp.as_login(w, format('select count(*)::text from public.data_removal_reconciliation where note = %L', 'L521 ' || pg_temp.fx('sfx'))) = x,
  '4a ' || w || ' reads ' || x || ' of the two log rows')
  from (values ('staff', '0'), ('invman', '0'), ('manager', '2'), ('owner', '2')) t(w, x);

-- 5. The functions and the rule
select pg_temp.check(md5(pg_get_functiondef(to_regprocedure('public.' || x.f))) = x.m
                     and has_function_privilege('authenticated', to_regprocedure('public.' || x.f), 'execute') = x.auth,
  '5a ' || x.f || ' is 521''s, its rights as before')
  from (values ('tiktok_access_check(uuid)', '85e207b126a3296ccfdb12f27d46faae', false),
               ('tiktok_negative_stock_alerts()', '6abcf753a83a083724154164e6ac6ff0', true),
               ('report_tiktok_import_discrepancies(uuid)', 'da9b60005801ab3c281b130db6336d57', false),
               ('report_tiktok_imports(uuid,date,date)', '6026f74fe5007dca4cc68f02ceba5a15', true),
               ('report_tiktok_orders_by_status(uuid)', 'dd6299c859a71e13f9c54ea19e6f0064', true),
               ('report_tiktok_qty_sold(uuid,date,date)', 'c7173a37536b1350890341c9d7c1cacf', true),
               ('report_tiktok_recon_exceptions(uuid)', 'aef2f88ed10388b85388c501db195a1a', true),
               ('report_tiktok_settlement(uuid,date,date)', '99611f8408c14c1df194c410277b2ad0', true),
               ('report_tiktok_settlement_by_store(date,date)', 'd22c5abdae4879d345a4c4ca11572ac5', true),
               ('report_tiktok_settlement_daily(uuid,date,date)', 'f4fc891dc7ff361c8c6125082e8738aa', true),
               ('report_tiktok_stock_activity(uuid,date,date)', '9f0b953e3462e99ecea38dd6b2453e40', false),
               ('report_tiktok_unmatched_skus(uuid)', '3dbdb12ca4eef07b60b3f9610ff5ad90', true),
               ('tiktok_left_out_settlement(uuid,date,date)', '66ddb78ad59d87bd3881b23a500df068', true),
               ('tiktok_settlement_eligible(uuid)', '6f075978c47f735dae44e499e74b18b5', false),
               ('tiktok_settlement_totals(integer,integer,uuid)', '9bb45e064e1e9f2b468ec847564a39bb', true)) x(f, m, auth);
select pg_temp.check((select pg_get_expr(p.polqual, p.polrelid) = '( SELECT is_manager_or_above() AS is_manager_or_above)'
                             and p.polcmd = 'r' and p.polroles = array['authenticated'::regrole::oid]
                        from pg_policy p
                       where p.polrelid = 'public.data_removal_reconciliation'::regclass and p.polname = 'read data removal log')
                     and (select count(*) from pg_policy where polrelid = 'public.data_removal_reconciliation'::regclass) = 1,
  '5b the data-removal log''s one rule lets an Owner, Admin or Manager read');
rollback;
