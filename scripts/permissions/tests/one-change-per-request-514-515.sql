-- A repeated request changes stock once (514), and the old routes are closed (515).
--
-- Add stock on the Vouchers and Special pages, Apply Correction on the TikTok
-- Import page and Collect on the voucher hand-over window, each called as a
-- real signed-in login (the authenticated role, row rules on), as the pages
-- call them: the same request id twice changes things once and gives the first
-- answer back; a new id changes them again; the id with other details, or from
-- another login, is refused; no id is refused; a request that failed keeps
-- nothing. The old signatures without an id, and record_stock_use, are closed
-- to logins; record_stock_uses, which calls record_stock_use, still works.
--
--   sh scripts/invoices/local-sql.sh -f scripts/permissions/tests/one-change-per-request-514-515.sql
-- 514 and 515 are installed here when they are not in yet. Disposable local database only;
-- everything is rolled back. Made-up records only (L514, @example.invalid).
\set ON_ERROR_STOP on
begin;
-- 540 (security audit of 17 Nov 2026, M13: "Stock only") changed functions this file pins; it
-- changes nothing an Owner, a Manager or Staff are answered. Where it is in, its UNDO goes first
-- (this run only, rolled back with everything here).
select to_regprocedure('public.inventory_manager_guard(text)') is not null as t540_in \gset
\if :t540_in
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
select to_regprocedure('public.voucher_stock_in(uuid,uuid,integer,text,uuid)') is not null as m514_in \gset
\if :m514_in
\else
\ir ../../../supabase/514_a_repeated_request_changes_stock_once.sql
\endif
select has_function_privilege('authenticated', 'public.voucher_stock_in(uuid,uuid,integer,text)', 'execute') as m515_out \gset
\if :m515_out
\ir ../../../supabase/515_the_old_stock_routes_are_closed.sql
\endif
-- A second run of each changes nothing.
\ir ../../../supabase/514_a_repeated_request_changes_stock_once.sql
\ir ../../../supabase/515_the_old_stock_routes_are_closed.sql

create function pg_temp.check(ok boolean, msg text) returns void language plpgsql as
$f$ begin if ok is distinct from true then raise exception 'FAIL: %', msg; end if; raise notice 'PASS  %', msg; end $f$;
create temp table l514(k text primary key, id uuid not null);
create temp table l514t(k text primary key, v text);
create function pg_temp.fx(p_k text) returns uuid language sql as $f$ select id from l514 where k = p_k $f$;
create function pg_temp.tx(p_k text) returns text language sql as $f$ select v from l514t where k = p_k $f$;
-- Runs one statement as a signed-in login and answers its first column as text, or
-- 'ERR <sqlstate> <message>'. Nothing it did is kept on an error.
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
create function pg_temp.vqty() returns int language sql as
$f$ select current_qty from public.voucher_store_stock where voucher_id = pg_temp.fx('voucher') and store_id = pg_temp.fx('store') $f$;
create function pg_temp.wqty() returns int language sql as
$f$ select current_qty from public.warehouse_inventory where warehouse_id = pg_temp.fx('wh') and product_id = pg_temp.fx('prod') $f$;
-- The four calls as the pages send them.
create function pg_temp.vsi(qty int, req uuid) returns text language sql as
$f$ select format($q$select public.voucher_stock_in(p_voucher_id => %L, p_store_id => %L, p_quantity => %s, p_note => null, p_request_id => %L)::text$q$,
                  pg_temp.fx('voucher'), pg_temp.fx('store'), qty, req) $f$;
create function pg_temp.ssi(qty int, req uuid) returns text language sql as
$f$ select format($q$select public.special_stock_in(p_special_product_id => %L, p_warehouse_id => %L, p_quantity => %s, p_note => null, p_request_id => %L)::text$q$,
                  pg_temp.fx('special'), pg_temp.fx('wh'), qty, req) $f$;
create function pg_temp.ctr(delta int, req uuid) returns text language sql as
$f$ select format($q$select public.correct_tiktok_row(p_row_id => %L, p_qty_delta => %s, p_reason => 'L514 count', p_request_id => %L)::text$q$,
                  pg_temp.fx('tt_row'), delta, req) $f$;
create function pg_temp.cev(qty int, req uuid) returns text language sql as
$f$ select format($q$select public.claim_entitlement_vouchers(p_entitlement_id => %L, p_selections => %L::jsonb, p_note => null, p_request_id => %L)::text$q$,
                  pg_temp.fx('ent'), jsonb_build_array(jsonb_build_object('voucher_id', pg_temp.fx('voucher'), 'quantity', qty)), req) $f$;

\set required 'ERR 22023 REQUEST_ID_REQUIRED: This window is out of date. Reload the page and try again.'
\set reused 'ERR 22023 REQUEST_ID_REUSED: This request was already used for another change. Close the window and open it again.'

-- ═════ Fixtures (made up) ═════
do $$
declare own uuid := gen_random_uuid(); mgr uuid := gen_random_uuid(); stf uuid := gen_random_uuid(); nobody uuid := gen_random_uuid();
        sfx constant text := lower(substr(md5(gen_random_uuid()::text), 1, 6));
        st uuid; wh uuid; prod uuid; sp uuid; v uuid; cust uuid; pm uuid; cp uuid; inv uuid; ent uuid; b uuid; r uuid;
begin
  insert into auth.users(id, email, email_confirmed_at) values
    (own, 'l514-owner@example.invalid', now()), (mgr, 'l514-manager@example.invalid', now()),
    (stf, 'l514-staff@example.invalid', now()), (nobody, 'l514-nobody@example.invalid', now());
  insert into public.profiles(id, full_name, email, role, is_active) values
    (own, 'L514 Owner', 'l514-owner@example.invalid', 'owner', true),
    (mgr, 'L514 Manager', 'l514-manager@example.invalid', 'manager', true),
    (stf, 'L514 Staff', 'l514-staff@example.invalid', 'staff', true);
  perform set_config('request.jwt.claim.sub', own::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', own, 'role', 'authenticated')::text, true);
  insert into public.stores(name, code, country_code) values ('L514 Store ' || sfx, 'L514' || sfx, 'SG') returning id into st;
  insert into public.warehouses(name, code) values ('L514 Warehouse ' || sfx, 'L514W' || sfx) returning id into wh;
  insert into public.user_store_assignments(user_id, store_id) values (stf, st), (mgr, st);
  insert into public.products(name, sku) values ('L514 Soap ' || sfx, 'L514P' || sfx) returning id into prod;
  insert into public.store_inventory(store_id, product_id, current_qty) values (st, prod, 20);
  insert into public.warehouse_inventory(warehouse_id, product_id, current_qty) values (wh, prod, 10);
  insert into public.special_products(name, sku, product_id) values ('L514 Special ' || sfx, 'L514S' || sfx, prod) returning id into sp;
  -- A voucher reward: a credit package sold and paid gives a voucher entitlement.
  insert into public.vouchers(name, code, voucher_kind, qty_type, selling_price, is_active)
    values ('L514 Facial ' || sfx, 'L514V' || sfx, 'normal', 'limited', 50, true) returning id into v;
  insert into public.voucher_store_stock(voucher_id, store_id, current_qty) values (v, st, 50);
  insert into public.customers(full_name, phone) values ('L514 Buyer', '+61491570514') returning id into cust;
  insert into public.payment_methods(name) values ('L514 Cash ' || sfx) returning id into pm;
  insert into public.credit_packages(name, customer_price, paid_credit_amount, grants_reward,
                                     reward_qualifying_amount, allow_voucher, allow_therapy, effective_from)
    values ('L514 Package ' || sfx, 994, 994, true, 994, true, true, current_date) returning id into cp;
  insert into public.credit_package_stores(package_id, store_id) values (cp, st);
  insert into public.credit_package_vouchers(package_id, voucher_id) values (cp, v);
  inv := public.create_invoice(st, cust, null, jsonb_build_array(jsonb_build_object(
           'kind', 'credit_package', 'credit_package_id', cp, 'quantity', 1)));
  perform public.pay_invoice(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pm, 'amount', 994)));
  select id into ent from public.therapy_entitlements
   where customer_id = cust and entitlement_kind = 'voucher' and claim_source_invoice_id = inv;
  if ent is null then raise exception 'FIXTURE: the package gave no voucher entitlement'; end if;
  if (public.entitlement_voucher_state(ent)->>'remaining')::int < 3 then
    raise exception 'FIXTURE: the entitlement has fewer than 3 vouchers to hand over'; end if;
  -- A confirmed TikTok order row for the soap.
  insert into public.tiktok_sku_aliases(store_id, seller_sku, target_kind, target_id, created_by)
    values (st, 'L514-SOAP-' || sfx, 'product', prod, own);
  insert into public.tiktok_status_mappings(status_label, status_norm, action, marks_shipped)
    values ('L514 Shipped ' || sfx, public.tiktok_norm_status('L514 Shipped ' || sfx), 'deduct', true);
  b := public.stage_tiktok_orders(st, 'L514 ' || sfx || '.csv', null, jsonb_build_array(jsonb_build_object(
         'order_id', 'L514-' || sfx || '-1', 'seller_sku', 'L514-SOAP-' || sfx, 'quantity', '1',
         'order_status', 'L514 Shipped ' || sfx, 'product_name', 'L514 soap')));
  perform public.confirm_tiktok_batch(b, null, false, null);
  select id into r from public.tiktok_order_rows where batch_id = b and confirmed and matched_kind is not null;
  if r is null then raise exception 'FIXTURE: no confirmed TikTok row to correct'; end if;
  insert into l514 values ('owner', own), ('manager', mgr), ('staff', stf), ('nobody', nobody), ('store', st), ('wh', wh),
    ('prod', prod), ('special', sp), ('voucher', v), ('ent', ent), ('tt_batch', b), ('tt_row', r),
    ('r1', gen_random_uuid()), ('r2', gen_random_uuid()), ('r3', gen_random_uuid()), ('r4', gen_random_uuid()),
    ('r5', gen_random_uuid()), ('r6', gen_random_uuid()), ('r7', gen_random_uuid()), ('r8', gen_random_uuid()),
    ('r9', gen_random_uuid()), ('r10', gen_random_uuid()), ('r11', gen_random_uuid());
end $$;

-- 1. Rights
select pg_temp.check(not has_function_privilege('authenticated', to_regprocedure('public.' || f), 'execute')
                     and not has_function_privilege('anon', to_regprocedure('public.' || f), 'execute')
                     and has_function_privilege('service_role', to_regprocedure('public.' || f), 'execute'),
  '1a only the server calls ' || f)
  from unnest(array['voucher_stock_in(uuid,uuid,integer,text)', 'special_stock_in(uuid,uuid,integer,text)',
                    'correct_tiktok_row(uuid,integer,text)', 'claim_entitlement_vouchers(uuid,jsonb,text)',
                    'record_stock_use(text,uuid,uuid,integer,text,text)',
                    'request_reply_first(text,uuid,text)', 'request_reply_keep(text,uuid,text,jsonb)']) f;
select pg_temp.check(has_function_privilege('authenticated', to_regprocedure('public.' || f), 'execute')
                     and not has_function_privilege('anon', to_regprocedure('public.' || f), 'execute'),
  '1b signed-in logins call ' || f)
  from unnest(array['voucher_stock_in(uuid,uuid,integer,text,uuid)', 'special_stock_in(uuid,uuid,integer,text,uuid)',
                    'correct_tiktok_row(uuid,integer,text,uuid)', 'claim_entitlement_vouchers(uuid,jsonb,text,uuid)',
                    'record_stock_uses(text,uuid,jsonb,text,text,uuid)']) f;
select pg_temp.check((select relrowsecurity from pg_class where oid = 'public.request_replies'::regclass)
                     and not has_table_privilege('authenticated', 'public.request_replies', 'select')
                     and not has_table_privilege('authenticated', 'public.request_replies', 'insert')
                     and not has_table_privilege('anon', 'public.request_replies', 'select'),
  '1c request_replies: row security on, and no login can read or write it');
select pg_temp.check(v like 'ERR 42501 permission denied for function voucher_stock_in%',
  '1d a login calling the old voucher_stock_in without an id is refused: ' || v)
  from pg_temp.as_login('owner', format('select public.voucher_stock_in(%L, %L, 5, null)::text', pg_temp.fx('voucher'), pg_temp.fx('store'))) v;
select pg_temp.check(v like 'ERR 42501%', '1e a login with no staff profile is refused the new one: ' || v)
  from pg_temp.as_login('nobody', pg_temp.vsi(5, pg_temp.fx('r11'))) v;

-- 2. Add stock on the Vouchers page
select pg_temp.check(pg_temp.vqty() = 50, '2a the voucher starts at 50');
insert into l514t select 'v1', pg_temp.as_login('owner', pg_temp.vsi(5, pg_temp.fx('r1')));
insert into l514t select 'v2', pg_temp.as_login('owner', pg_temp.vsi(5, pg_temp.fx('r1')));
select pg_temp.check(pg_temp.tx('v1') = '{"success": true}' and pg_temp.tx('v2') = pg_temp.tx('v1') and pg_temp.vqty() = 55,
  '2b the same request twice adds 5 once (55) and answers the same: ' || pg_temp.tx('v1') || ' / ' || pg_temp.tx('v2'));
insert into l514t select 'v3', pg_temp.as_login('owner', pg_temp.vsi(5, pg_temp.fx('r2')));
select pg_temp.check(pg_temp.tx('v3') = '{"success": true}' and pg_temp.vqty() = 60, '2c a new request adds 5 again (60)');
select pg_temp.check(v = :'reused' and pg_temp.vqty() = 60, '2d the first id with another quantity is refused: ' || v)
  from pg_temp.as_login('owner', pg_temp.vsi(6, pg_temp.fx('r1'))) v;
select pg_temp.check(v = :'reused' and pg_temp.vqty() = 60, '2e the first id from another login is refused: ' || v)
  from pg_temp.as_login('manager', pg_temp.vsi(5, pg_temp.fx('r1'))) v;
select pg_temp.check(v = :'required' and pg_temp.vqty() = 60, '2f no id is refused: ' || v)
  from pg_temp.as_login('owner', pg_temp.vsi(5, null)) v;
select pg_temp.check(v like 'ERR % Quantity must be greater than zero%' and pg_temp.vqty() = 60,
  '2g a request that fails changes nothing: ' || v)
  from pg_temp.as_login('owner', pg_temp.vsi(0, pg_temp.fx('r3'))) v;
insert into l514t select 'v4', pg_temp.as_login('owner', pg_temp.vsi(3, pg_temp.fx('r3')));
select pg_temp.check(pg_temp.tx('v4') = '{"success": true}' and pg_temp.vqty() = 63, '2h and its id can be sent again with a good quantity (63)');
select pg_temp.check(v like 'ERR % Only Owner or Manager can add voucher stock%' and pg_temp.vqty() = 63,
  '2i Staff are still refused by the work itself: ' || v)
  from pg_temp.as_login('staff', pg_temp.vsi(5, pg_temp.fx('r4'))) v;

-- 3. Add stock on the Special page
select pg_temp.check(pg_temp.wqty() = 10, '3a the warehouse starts at 10');
insert into l514t select 's1', pg_temp.as_login('manager', pg_temp.ssi(4, pg_temp.fx('r5')));
insert into l514t select 's2', pg_temp.as_login('manager', pg_temp.ssi(4, pg_temp.fx('r5')));
select pg_temp.check((pg_temp.tx('s1')::jsonb)->>'quantity_after' = '14' and pg_temp.tx('s2') = pg_temp.tx('s1') and pg_temp.wqty() = 14
                     and (select count(*) from public.stock_movements where product_id = pg_temp.fx('prod') and to_warehouse_id = pg_temp.fx('wh')
                            and movement_type = 'warehouse_stock_in') = 1,
  '3b the same request twice adds 4 once (14), with one stock movement, and answers the same: ' || pg_temp.tx('s2'));
insert into l514t select 's3', pg_temp.as_login('manager', pg_temp.ssi(4, pg_temp.fx('r6')));
select pg_temp.check(pg_temp.tx('s3') like '%"quantity_after": 18%' and pg_temp.wqty() = 18, '3c a new request adds 4 again (18)');

-- 4. Apply Correction on the TikTok Import page
insert into l514t select 't0', (select count(*) from public.tiktok_import_batches)::text;
insert into l514t select 't1', pg_temp.as_login('owner', pg_temp.ctr(-1, pg_temp.fx('r7')));
insert into l514t select 't2', pg_temp.as_login('owner', pg_temp.ctr(-1, pg_temp.fx('r7')));
select pg_temp.check(pg_temp.tx('t1') = '{"success": true}' and pg_temp.tx('t2') = pg_temp.tx('t1')
                     and (select count(*) from public.tiktok_import_batches) = pg_temp.tx('t0')::int + 1
                     and (select count(*) from public.tiktok_corrections c where c.order_row_id = pg_temp.fx('tt_row')) = 1,
  '4a the same correction twice makes one correction batch: ' || pg_temp.tx('t1') || ' / ' || pg_temp.tx('t2'));

-- 5. Collect on the voucher hand-over window (Staff of the store)
insert into l514t select 'c1', pg_temp.as_login('staff', pg_temp.cev(1, pg_temp.fx('r8')));
insert into l514t select 'c2', pg_temp.as_login('staff', pg_temp.cev(1, pg_temp.fx('r8')));
select pg_temp.check((pg_temp.tx('c1')::jsonb)->>'success' = 'true' and pg_temp.tx('c2') = pg_temp.tx('c1')
                     and (select count(*) from public.voucher_claims where entitlement_id = pg_temp.fx('ent')) = 1,
  '5a the same hand-over twice hands one voucher over, and answers with the same document: ' || pg_temp.tx('c2'));
-- (Each call is its own statement: a statement does not see what a function it calls wrote.)
insert into l514t select 'c3', pg_temp.as_login('staff', pg_temp.cev(1, pg_temp.fx('r9')));
select pg_temp.check((pg_temp.tx('c3')::jsonb)->>'success' = 'true'
                     and (pg_temp.tx('c3')::jsonb)->>'claim_id' <> (pg_temp.tx('c1')::jsonb)->>'claim_id'
                     and (select count(*) from public.voucher_claims where entitlement_id = pg_temp.fx('ent')) = 2,
  '5b a new hand-over is a second claim');

-- 6. record_stock_uses, which calls record_stock_use with its owner's rights, still works
insert into l514t select 'u0', (select current_qty from public.store_inventory where store_id = pg_temp.fx('store') and product_id = pg_temp.fx('prod'))::text;
insert into l514t select 'u1', pg_temp.as_login('staff', format($q$select public.record_stock_uses('store', %L,
         jsonb_build_array(jsonb_build_object('product_id', %L, 'quantity', 1)), 'L514 tester', null, %L)::text$q$,
         pg_temp.fx('store'), pg_temp.fx('prod'), pg_temp.fx('r10')));
select pg_temp.check(pg_temp.tx('u1') not like 'ERR%'
                     and (select current_qty from public.store_inventory where store_id = pg_temp.fx('store') and product_id = pg_temp.fx('prod'))
                         = pg_temp.tx('u0')::int - 1,
  '6a Staff record a stock use at their store as the page does (one taken off): ' || left(pg_temp.tx('u1'), 120));

-- 7. The functions
select pg_temp.check(md5(pg_get_functiondef(to_regprocedure('public.' || x.f))) = x.m, '7a ' || x.f || ' is as tested')
  from (values ('voucher_stock_in(uuid,uuid,integer,text,uuid)', '724182e6c425f8522baaa54360523f16'),
               ('special_stock_in(uuid,uuid,integer,text,uuid)', '807eebea43ef139b82b9933e92b17d07'),
               ('correct_tiktok_row(uuid,integer,text,uuid)', '95c00f51cd8ff31abd1f58918d5043ca'),
               ('claim_entitlement_vouchers(uuid,jsonb,text,uuid)', 'ceccabc80c3015aec2172de0f6cbde65'),
               ('request_reply_first(text,uuid,text)', '96ce4a8c58d277dae7f7288c6dc8516d'),
               ('request_reply_keep(text,uuid,text,jsonb)', 'b33ea076cb723bceceae161d3bcd702d'),
               ('voucher_stock_in(uuid,uuid,integer,text)', '56c7d10cf8266f6cc4ec4d1e8aae6e69'),
               ('special_stock_in(uuid,uuid,integer,text)', 'ca2e27a7b55af096a20db61b3953f7dd'),
               ('correct_tiktok_row(uuid,integer,text)', '9aae10ba9e12e372756a2abf7d383e41'),
               ('claim_entitlement_vouchers(uuid,jsonb,text)', '5a2e078df74a2763b6975bb939847b7a'),
               ('record_stock_use(text,uuid,uuid,integer,text,text)', 'db278faba262b0a3801944cd821a62fd')) x(f, m);
rollback;
