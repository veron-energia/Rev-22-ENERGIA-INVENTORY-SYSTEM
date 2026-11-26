-- TikTok order amounts and prices are numbers (519).
--
-- A TikTok order file with "NaN" or "Infinity" in a row's subtotals or refund,
-- staged by a real signed-in Staff login (the authenticated role) as the
-- Import page sends it, keeps those amounts as missing, as an empty cell; the
-- row stages and confirms as before. Numbers stay numbers. A NaN price, set as
-- the Products page sets it by an Owner, is refused, and so is NaN written
-- straight into the other tables 519 checks, the repeating therapy voucher's
-- hours among them.
--
--   sh scripts/invoices/local-sql.sh -f scripts/tiktok/tests/amounts-are-numbers-519.sql
-- 519 is installed here when it is not in yet (518 must be in). Disposable local database
-- only; everything is rolled back. Made-up records only (L519, @example.invalid).
\set ON_ERROR_STOP on
begin;
select position('519:' in pg_get_functiondef('public.stage_tiktok_orders(uuid,text,text,jsonb)'::regprocedure)) > 0 as m519_in \gset
\if :m519_in
\else
\ir ../../../supabase/519_tiktok_amounts_and_prices_are_numbers.sql
\endif
-- A second run changes nothing. (541, security audit L19, changes stage_tiktok_orders after 519, so
-- 519 no longer recognises it: the second run only where 541 is not in.)
select position('541 (security audit' in pg_get_functiondef('public.stage_tiktok_orders(uuid,text,text,jsonb)'::regprocedure)) > 0 as m541_in \gset
\if :m541_in
\else
\ir ../../../supabase/519_tiktok_amounts_and_prices_are_numbers.sql
\endif

create function pg_temp.check(ok boolean, msg text) returns void language plpgsql as
$f$ begin if ok is distinct from true then raise exception 'FAIL: %', msg; end if; raise notice 'PASS  %', msg; end $f$;
create temp table l519(k text primary key, id uuid not null);
create temp table l519t(k text primary key, v text);
create function pg_temp.fx(p_k text) returns uuid language sql as $f$ select id from l519 where k = p_k $f$;
create function pg_temp.tx(p_k text) returns text language sql as $f$ select v from l519t where k = p_k $f$;
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
-- Runs one statement as the database itself; 'ok' or 'ERR <sqlstate> <message>'.
create function pg_temp.try(q text) returns text language plpgsql as
$f$ begin execute q; return 'ok'; exception when others then return 'ERR ' || sqlstate || ' ' || sqlerrm; end $f$;
-- A file of one order row, as the Import page sends it.
create function pg_temp.stage(p_order text, p_before text, p_after text, p_refund text) returns text language sql as
$f$ select format($q$select public.stage_tiktok_orders(%L, 'L519 orders.csv', null, %L::jsonb)::text$q$,
     pg_temp.fx('store'), jsonb_build_array(jsonb_build_object(
       'order_id', p_order, 'seller_sku', pg_temp.tx('sku'), 'quantity', '1', 'order_status', pg_temp.tx('shipped'),
       'product_name', 'L519 soap', 'sku_subtotal_before', p_before, 'sku_subtotal_after', p_after, 'refund_amount', p_refund))) $f$;
create function pg_temp.row_of(p_batch text) returns text language sql as
$f$ select coalesce(sku_subtotal_before::text, '-') || ' ' || coalesce(sku_subtotal_after::text, '-') || ' ' || coalesce(refund_amount::text, '-')
            || ' ' || coalesce(financial_delta::text, '-') || ' ' || staging_status || ' ' || stock_delta
     from public.tiktok_order_rows where batch_id::text = pg_temp.tx(p_batch) $f$;
create function pg_temp.qty() returns int language sql as
$f$ select current_qty from public.store_inventory where store_id = pg_temp.fx('store') and product_id = pg_temp.fx('soap') $f$;

do $$
declare own uuid := gen_random_uuid(); stf uuid := gen_random_uuid(); st uuid; p uuid; v uuid; cp uuid;
        sfx constant text := lower(substr(md5(gen_random_uuid()::text), 1, 6));
begin
  insert into auth.users(id, email, email_confirmed_at) values
    (own, 'l519-owner@example.invalid', now()), (stf, 'l519-staff@example.invalid', now());
  insert into public.profiles(id, full_name, email, role, is_active) values
    (own, 'L519 Owner', 'l519-owner@example.invalid', 'owner', true),
    (stf, 'L519 Staff', 'l519-staff@example.invalid', 'staff', true);
  perform set_config('request.jwt.claim.sub', own::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', own, 'role', 'authenticated')::text, true);
  insert into public.stores(name, code, country_code) values ('L519 Store ' || sfx, 'L519' || sfx, 'SG') returning id into st;
  insert into public.user_store_assignments(user_id, store_id) values (stf, st);
  insert into public.products(name, sku) values ('L519 Soap ' || sfx, 'L519P' || sfx) returning id into p;
  insert into public.store_inventory(store_id, product_id, current_qty) values (st, p, 20);
  perform public.set_product_prices(st, p, 50, 50, 'available');
  insert into public.vouchers(name, code, voucher_kind, qty_type, selling_price, is_active)
    values ('L519 Voucher ' || sfx, 'L519V' || sfx, 'normal', 'limited', 30, true) returning id into v;
  insert into public.credit_packages(name, customer_price, paid_credit_amount, grants_reward, reward_qualifying_amount,
                                     allow_voucher, allow_therapy, effective_from)
    values ('L519 Package ' || sfx, 994, 994, false, 994, true, true, current_date) returning id into cp;
  -- A therapy voucher used at most once every 4 hours.
  insert into public.therapy_voucher_definitions(voucher_id, validity_kind, repeat_kind, repeat_max_per_period, repeat_interval_hours)
    values (v, 'none', 'per_hours', 1, 4);
  insert into l519 values ('owner', own), ('staff', stf), ('store', st), ('soap', p), ('voucher', v), ('package', cp);
  insert into l519t values ('sku', 'L519-SOAP-' || sfx), ('shipped', 'L519 Shipped ' || sfx), ('sfx', sfx);
  insert into public.tiktok_sku_aliases(store_id, seller_sku, target_kind, target_id, created_by)
    values (st, pg_temp.tx('sku'), 'product', p, own);
  insert into public.tiktok_status_mappings(status_label, status_norm, action, marks_shipped)
    values (pg_temp.tx('shipped'), public.tiktok_norm_status(pg_temp.tx('shipped')), 'deduct', true);
end $$;

-- 1. TikTok order files, staged by a Staff login of the store
insert into l519t select 'b_nan', pg_temp.as_login('staff', pg_temp.stage('L519-' || pg_temp.tx('sfx') || '-1', 'NaN', 'NaN', 'Infinity'));
select pg_temp.check(pg_temp.tx('b_nan') ~ '^[0-9a-f-]{36}$' and pg_temp.row_of('b_nan') = '- - - - New — Will Deduct 1',
  '1a "NaN" and "Infinity" amounts stage as missing, as an empty cell, and the row still deducts one: '
    || coalesce(pg_temp.row_of('b_nan'), pg_temp.tx('b_nan')));
insert into l519t select 'b_empty', pg_temp.as_login('staff', pg_temp.stage('L519-' || pg_temp.tx('sfx') || '-2', '', '', ''));
select pg_temp.check(split_part(pg_temp.row_of('b_nan'), ' ', 5) = split_part(pg_temp.row_of('b_empty'), ' ', 5),
  '1b exactly as empty cells stage: ' || pg_temp.row_of('b_empty'));
insert into l519t select 'b_num', pg_temp.as_login('staff', pg_temp.stage('L519-' || pg_temp.tx('sfx') || '-3', '12.50', '10.00', '0'));
select pg_temp.check(pg_temp.row_of('b_num') = '12.50 10.00 0.00 - New — Will Deduct 1', '1c numbers stay numbers: ' || pg_temp.row_of('b_num'));
-- (The call is its own statement: a statement does not see what a function it calls wrote.)
insert into l519t select 'confirm', pg_temp.as_login('owner', format('select public.confirm_tiktok_batch(%L, null, false, null)::text', pg_temp.tx('b_nan')));
select pg_temp.check(pg_temp.tx('confirm') not like 'ERR%' and pg_temp.qty() = 19
                     and (select confirmed and sku_subtotal_after is null from public.tiktok_order_rows where batch_id = pg_temp.tx('b_nan')::uuid),
  '1d confirmed, the row takes its one from stock and keeps the amounts missing: ' || left(pg_temp.tx('confirm'), 80));
-- A new version of the confirmed order with "NaN": its financial difference is a number.
insert into l519t select 'b_v2', pg_temp.as_login('staff', pg_temp.stage('L519-' || pg_temp.tx('sfx') || '-1', 'NaN', 'NaN', 'NaN'));
select pg_temp.check((select financial_delta is not null and financial_delta::text <> 'NaN' and version_no = 2
                        from public.tiktok_order_rows where batch_id = pg_temp.tx('b_v2')::uuid),
  '1e a later version with "NaN" has a financial difference that is a number: ' || pg_temp.row_of('b_v2'));

-- 2. Prices: an Owner on the Products page, and straight writes to the other tables
select pg_temp.check(v like 'ERR 23514 %store_product_prices_amounts_are_numbers%'
                     and (select selling_price from public.store_product_prices where store_id = pg_temp.fx('store') and product_id = pg_temp.fx('soap')) = 50,
  '2a an Owner setting a product price of "NaN" is refused, the price as it was: ' || v)
  from pg_temp.as_login('owner', format($q$select public.set_product_prices(%L, %L, 'NaN', 'NaN', 'available')::text$q$,
                                       pg_temp.fx('store'), pg_temp.fx('soap'))) v;
select pg_temp.check(v like 'ERR 23514 %voucher_store_prices_amounts_are_numbers%', '2b and a voucher price of "NaN": ' || v)
  from pg_temp.as_login('owner', format($q$select public.set_voucher_prices(%L, %L, 'NaN', 'NaN', true)::text$q$,
                                       pg_temp.fx('voucher'), pg_temp.fx('store'))) v;
select pg_temp.check(pg_temp.try(format('update public.%I set %I = %L where id = %L', x.t, x.c, 'NaN', pg_temp.fx(x.k)))
                       like 'ERR 23514 %' || x.t || '_amounts_are_numbers%',
  '2c the database itself refuses NaN in ' || x.t || '.' || x.c)
  from (values ('products', 'default_cost_price', 'soap'), ('stores', 'gst_rate', 'store'),
               ('vouchers', 'selling_price', 'voucher'), ('credit_packages', 'customer_price', 'package')) x(t, c, k);
select pg_temp.check(pg_temp.try(format('update public.tiktok_order_rows set sku_subtotal_after = %L where batch_id = %L', 'NaN', pg_temp.tx('b_num')))
                       like 'ERR 23514 %tiktok_order_rows_amounts_are_numbers%',
  '2d and in a TikTok order row');
-- (its own check, repeat_interval_hours > 0, lets NaN through)
select pg_temp.check(pg_temp.try(format('update public.therapy_voucher_definitions set repeat_interval_hours = %L where voucher_id = %L', 'NaN', pg_temp.fx('voucher')))
                       like 'ERR 23514 %therapy_voucher_definitions_amounts_are_numbers%',
  '2e and as the hours between a repeating therapy voucher''s uses');

-- 3. The checks and the function
select pg_temp.check(count(*) = 17
                     and bool_and(c.convalidated
                                  and (select bool_and(strpos(pg_get_constraintdef(c.oid), '(' || ic.column_name || ')::text') > 0)
                                         from information_schema.columns ic
                                        where ic.table_schema = 'public' and ic.table_name = c.conrelid::regclass::text and ic.data_type = 'numeric')),
  '3a seventeen checks, validated, each naming every amount in its table')
  from pg_constraint c
 where c.connamespace = 'public'::regnamespace and c.conname like '%\_amounts\_are\_numbers'
   and c.conrelid::regclass::text = any (array['tiktok_order_rows', 'store_product_prices', 'promotion_store_prices', 'promotions',
         'voucher_store_prices', 'vouchers', 'therapy_service_stores', 'therapy_services', 'unlimited_therapy_store_prices',
         'special_products', 'credit_packages', 'premium_bundles', 'event_ticket_options', 'events', 'products', 'stores',
         'therapy_voucher_definitions']);
select pg_temp.check(md5(pg_get_functiondef('public.stage_tiktok_orders(uuid,text,text,jsonb)'::regprocedure)) in ('ac4c840689c50433504377aa63664188', '086b5958fa3d0e7c40cd5f333602cb53')  -- 519's, or 541's
                     and has_function_privilege('authenticated', 'public.stage_tiktok_orders(uuid,text,text,jsonb)', 'execute')
                     and not has_function_privilege('anon', 'public.stage_tiktok_orders(uuid,text,text,jsonb)', 'execute'),
  '3b stage_tiktok_orders is 519''s, its rights as before');
rollback;
