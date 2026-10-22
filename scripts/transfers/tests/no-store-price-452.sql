-- A transfer into a store no longer needs the store to have a price for the product (452).
--
-- The owner, 22 Oct 2026 (change list item 11): "A transfer must work even when the destination store has
-- no price for the product." No reminder after receipt. Selling still needs a price: create_invoice
-- already refuses an unpriced product, and is not changed.
--
--   R  Before 452 (only where this file installs it): an Owner's Warehouse -> Store request for a product
--      with no price at the store is refused ("Cannot transfer to this store — missing prices").
--   G  assert_transfer_prices_ok has 452's AFTER md5 and is still the service role's alone; its five
--      callers, receive_transfer, create_invoice, product_price_for and transfer_price_blockers are
--      unchanged.
--   W  An Owner's Warehouse -> Store request for an unpriced product: created, reviewed and dispatched (the
--      warehouse goes down), received in full (the store holds it; movements recorded).
--   S  Store -> Store into a store with no price for it: created, dispatched, received.
--   T  A Staff request (create_staff_transfer_request) for an unpriced product; Review adds another unpriced
--      product; dispatched; received by the staff member at their store, one line short with a reason.
--   E  An edit moving a priced request to a store with no price for the product; dispatched and received.
--   D  create_deferred_transfer_request (the service role's) into a store with no price for the product.
--   K  The other rules still hold for an unpriced product: not enough stock at the source, the same product
--      twice, Staff into a store they are not assigned to, Staff from another store.
--   I  Selling: create_invoice at a store with no price for the product is still refused, at the store the
--      transfer reached and at the one with no price list at all; once a price is set (set_product_prices,
--      the Price List page's call), it goes through.
--   M  452 twice changes nothing; its first run changes only assert_transfer_prices_ok; its self-test leaves
--      no row (when this file installs it).
--
-- Disposable local database only; everything is rolled back. Every name and email is invented (NPX
-- fixtures, @example.com); the customer's phone is one of ACMA's fictional mobile numbers. It installs 452
-- twice (run with -v skip_install=1 where 452 is already installed). Every check runs, then the file fails
-- if any did.
--   psql -X -v ON_ERROR_STOP=1 -f scripts/transfers/tests/no-store-price-452.sql
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '10s';
set local statement_timeout = '300s';
create temp table failed(n serial, msg text);
create function pg_temp.check(ok boolean, msg text) returns void language plpgsql as
$$begin
  if ok is distinct from true then insert into failed(msg) values (msg); raise notice 'FAIL  %', msg;
  else raise notice 'PASS  %', msg; end if;
end$$;
create temp table fx(k text primary key, v uuid);
create temp table tx(k text primary key, v text);
create function pg_temp.fx(key text) returns uuid language sql as $$ select v from fx where k = key $$;
create function pg_temp.tx(key text) returns text language sql as $$ select v from tx where k = key $$;
create function pg_temp.put(key text, val text) returns void language sql as
$$ insert into tx values (key, val) on conflict (k) do update set v = excluded.v $$;
create function pg_temp.putx(key text, val uuid) returns void language sql as
$$ insert into fx values (key, val) on conflict (k) do update set v = excluded.v $$;
create function pg_temp.as_user(key text) returns void language sql as
$$ select set_config('request.jwt.claims', '', true),
          set_config('request.jwt.claim.sub', coalesce(pg_temp.fx(key)::text, ''), true),
          set_config('request.jwt.claim.role', 'authenticated', true) $$;
create function pg_temp.as_service() returns void language sql as
$$ select set_config('request.jwt.claims', '', true), set_config('request.jwt.claim.sub', '', true),
          set_config('request.jwt.claim.role', 'service_role', true) $$;
-- The error a call raises, or 'ok'; what it wrote is undone when it fails.
create function pg_temp.err(q text) returns text language plpgsql as
$$begin execute q; return 'ok'; exception when others then return sqlerrm; end$$;
create function pg_temp.row_counts() returns jsonb language plpgsql as
$$declare r record; n bigint; v jsonb := '{}'::jsonb;
begin
  for r in select c.oid::regclass::text as t from pg_class c join pg_namespace s on s.oid = c.relnamespace
            where s.nspname in ('public', 'auth') and c.relkind = 'r' order by 1 loop
    execute format('select count(*) from %s', r.t) into n;
    v := v || jsonb_build_object(r.t, n);
  end loop;
  return v;
end$$;
create function pg_temp.fn_md5s() returns table(fn text, md5 text) language plpgsql as
$$begin
  perform set_config('search_path', 'public', true);
  return query select p.oid::regprocedure::text, md5(pg_get_functiondef(p.oid))
                 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f';
end$$;
create function pg_temp.md5_of(sig text) returns text language plpgsql as
$$declare v text; v_path text := current_setting('search_path');
begin
  perform set_config('search_path', 'public', true);
  v := md5(pg_get_functiondef(to_regprocedure('public.' || sig)));
  perform set_config('search_path', v_path, true);
  return v;
end$$;
create function pg_temp.qty_store(s text, p text) returns int language sql as
$$ select coalesce((select current_qty from public.store_inventory where store_id = pg_temp.fx(s) and product_id = pg_temp.fx(p)), 0) $$;
create function pg_temp.qty_wh(w text, p text) returns int language sql as
$$ select coalesce((select current_qty from public.warehouse_inventory where warehouse_id = pg_temp.fx(w) and product_id = pg_temp.fx(p)), 0) $$;
create function pg_temp.status(r text) returns text language sql as
$$ select status::text from public.transfer_requests where id = pg_temp.fx(r) $$;
create function pg_temp.line_of(r text, p text) returns uuid language sql as
$$ select id from public.transfer_request_lines where transfer_request_id = pg_temp.fx(r) and product_id = pg_temp.fx(p) $$;
-- An unpriced product has no price row at the store at all; one priced has an active one.
create function pg_temp.priced(s text, p text) returns boolean language sql as
$$ select exists (select 1 from public.store_product_prices where store_id = pg_temp.fx(s) and product_id = pg_temp.fx(p)) $$;

-- ── fixtures ───────────────────────────────────────────────────────────────
do $$
declare t text := lower(substr(md5(random()::text), 1, 6)); v_id uuid; v_phone text;
begin
  perform pg_temp.put('sfx', t);
  insert into auth.users (id, email) values (gen_random_uuid(), 'npx-owner-' || t || '@example.com') returning id into v_id;
  perform pg_temp.putx('owner', v_id);
  insert into public.profiles (id, full_name, email, role, is_active) values (v_id, 'NPX Owner', 'npx-owner-' || t || '@example.com', 'owner', true);
  insert into auth.users (id, email) values (gen_random_uuid(), 'npx-staff-' || t || '@example.com') returning id into v_id;
  perform pg_temp.putx('staff', v_id);
  insert into public.profiles (id, full_name, email, role, is_active) values (v_id, 'NPX Staff', 'npx-staff-' || t || '@example.com', 'staff', true);
  -- Store A has a price list (Q only); store B has none at all.
  insert into public.stores (name, code, country_code) values ('NPX Store A ' || t, 'NPXA' || t, 'SG') returning id into v_id;
  perform pg_temp.putx('sa', v_id);
  insert into public.stores (name, code, country_code) values ('NPX Store B ' || t, 'NPXB' || t, 'SG') returning id into v_id;
  perform pg_temp.putx('sb', v_id);
  insert into public.user_store_assignments (user_id, store_id) values (pg_temp.fx('staff'), pg_temp.fx('sa'));
  insert into public.warehouses (name, code) values ('NPX WH ' || t, 'NPXW' || t) returning id into v_id;
  perform pg_temp.putx('w', v_id);
  insert into public.products (name, sku, product_type) values ('NPX Pillow', 'NPX-P-' || t, 'own') returning id into v_id;
  perform pg_temp.putx('p', v_id);   -- no price anywhere
  insert into public.products (name, sku, product_type) values ('NPX Mat', 'NPX-M-' || t, 'own') returning id into v_id;
  perform pg_temp.putx('m', v_id);   -- no price anywhere (added during Review)
  insert into public.products (name, sku, product_type) values ('NPX Cup', 'NPX-C-' || t, 'own') returning id into v_id;
  perform pg_temp.putx('q', v_id);   -- priced at store A only
  insert into public.warehouse_inventory (warehouse_id, product_id, current_qty)
  values (pg_temp.fx('w'), pg_temp.fx('p'), 20), (pg_temp.fx('w'), pg_temp.fx('m'), 10), (pg_temp.fx('w'), pg_temp.fx('q'), 10);
  select p into v_phone from unnest(array['+61491570737', '+61491572983', '+61491573770', '+61491570006']) p
   where not exists (select 1 from public.customers c where public.normalize_customer_phone(c.phone) = p)
   order by p limit 1;
  insert into public.customers (full_name, phone) values ('NPX Test Customer', v_phone) returning id into v_id;
  perform pg_temp.putx('cust', v_id);
  perform pg_temp.as_user('owner');
  perform public.set_product_prices(pg_temp.fx('sa'), pg_temp.fx('q'), 12, 12, 'available');
end $$;
select pg_temp.check(not pg_temp.priced('sa', 'p') and not pg_temp.priced('sb', 'p') and not pg_temp.priced('sa', 'm')
    and pg_temp.priced('sa', 'q') and not pg_temp.priced('sb', 'q')
    and not exists (select 1 from store_product_prices where store_id = pg_temp.fx('sb')),
  'F the fixture: Pillow and Mat have no price anywhere, Cup only at store A, store B has no price list');

-- ═════ R Before 452, and installing it ═════
\if :{?skip_install}
\else
select pg_temp.as_user('owner');
select pg_temp.put('r1', pg_temp.err(format(
  $q$select public.create_transfer_request('warehouse_to_store','warehouse',%L,'store',%L,
       jsonb_build_array(jsonb_build_object('line_kind','product','product_id',%L,'quantity',2)),null)$q$,
  pg_temp.fx('w'), pg_temp.fx('sa'), pg_temp.fx('p'))));
select pg_temp.check(pg_temp.md5_of('assert_transfer_prices_ok(uuid,uuid[])') = '9eb52cd482756e9f3355ddd8066da86d'
    and pg_temp.tx('r1') like 'Cannot transfer to this store — missing prices: NPX Pillow (no price row for this store)%',
  'R1 before 452 an Owner''s Warehouse -> Store request for a product with no price at the store is refused: ' || pg_temp.tx('r1'));
select pg_temp.as_service();
create temp table b452 as select * from pg_temp.fn_md5s();
create temp table r452 as select pg_temp.row_counts() as before;
\ir ../../../supabase/452_transfers_need_no_store_price.sql
create temp table m452 as select * from pg_temp.fn_md5s();
alter table r452 add column after1 jsonb;
update r452 set after1 = pg_temp.row_counts();
\ir ../../../supabase/452_transfers_need_no_store_price.sql
\endif

-- ═════ G The function, its grant, and what it leaves alone ═════
select pg_temp.check(pg_temp.md5_of('assert_transfer_prices_ok(uuid,uuid[])') = '5ffab5ce54c8456886b6a77f5663218a',
  'G1 assert_transfer_prices_ok has 452''s AFTER md5');
select pg_temp.check((select array_agg(x::text order by x::text) from pg_proc p, unnest(p.proacl) x
                       where p.oid = 'public.assert_transfer_prices_ok(uuid,uuid[])'::regprocedure)
                     = array['postgres=X/postgres', 'service_role=X/postgres']
    and not has_function_privilege('anon', 'public.assert_transfer_prices_ok(uuid,uuid[])', 'execute')
    and not has_function_privilege('authenticated', 'public.assert_transfer_prices_ok(uuid,uuid[])', 'execute')
    and has_function_privilege('service_role', 'public.assert_transfer_prices_ok(uuid,uuid[])', 'execute'),
  'G2 it is still the service role''s alone (not anon''s, not signed-in staff''s)');
select pg_temp.check((select bool_and(pg_temp.md5_of(x.f) = x.m) from (values
      ('create_transfer_request(text,text,uuid,text,uuid,jsonb,text)', '99d7e65385165464fb6e4395f4d4c25f'),
      ('create_staff_transfer_request(jsonb,text,uuid)', 'cc32ec91b2e223c67da957dd792af12e'),
      ('edit_transfer_request(uuid,integer,text,location_type,uuid,location_type,uuid,jsonb,text)', 'd9cec0b343afaea0171952cbcda80b61'),
      ('review_and_dispatch_transfer(uuid,jsonb,text)', '6db84d9ecca1d40b4858b4291401fbc0'),
      ('create_deferred_transfer_request(location_type,uuid,jsonb,text)', '17a3ab718ac521d0fbd89e73c00d3f9e'),
      ('receive_transfer(uuid,jsonb,text,boolean)', '04be775f33e550da46a7ed8054b359ce'),
      ('create_invoice(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb)', '80c80d386a5241e63b353e35e13ef250'),
      ('product_price_for(uuid,uuid,boolean)', 'c6ece3be741f0b3849c9f5679c27a400'),
      ('transfer_price_blockers(uuid,uuid[])', '7dd980fb589febbd5f94d3382731fd50')) x(f, m)),
  'G3 its five callers, receive_transfer, create_invoice, product_price_for and transfer_price_blockers are unchanged');
select pg_temp.check((select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'assert_transfer_prices_ok') = 1
    and (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace
          and p.prosrc like '%assert_transfer_prices_ok%' and p.proname <> 'assert_transfer_prices_ok') = 5,
  'G4 one assert_transfer_prices_ok, still called by the five transfer functions');

-- ═════ W Warehouse -> Store, no price at the store ═════
select pg_temp.as_user('owner');
select pg_temp.put('w1', pg_temp.err(format(
  $q$select pg_temp.putx('rw', (public.create_transfer_request('warehouse_to_store','warehouse',%L,'store',%L,
       jsonb_build_array(jsonb_build_object('line_kind','product','product_id',%L,'quantity',4)),'NPX first stock')->>'id')::uuid)$q$,
  pg_temp.fx('w'), pg_temp.fx('sa'), pg_temp.fx('p'))));
select pg_temp.check(pg_temp.tx('w1') = 'ok' and pg_temp.status('rw') = 'pending'
    and (select (dest_type::text, dest_id, transfer_type) from transfer_requests where id = pg_temp.fx('rw'))
        = ('store'::text, pg_temp.fx('sa'), 'warehouse_to_store'::text),
  'W1 an Owner''s Warehouse -> Store request for a product with no price at the store is created: ' || pg_temp.tx('w1'));
select pg_temp.put('w2', pg_temp.err(format(
  $q$select public.review_and_dispatch_transfer(%L, jsonb_build_array(jsonb_build_object('line_id',%L,'approved_quantity',4,
       'sources',jsonb_build_array(jsonb_build_object('source_type','warehouse','source_id',%L,'quantity',4)))),'NPX dispatched')$q$,
  pg_temp.fx('rw'), pg_temp.line_of('rw', 'p'), pg_temp.fx('w'))));
select pg_temp.check(pg_temp.tx('w2') = 'ok' and pg_temp.status('rw') = 'in_transit'
    and pg_temp.qty_wh('w', 'p') = 16 and pg_temp.qty_store('sa', 'p') = 0,
  'W2 it is reviewed and dispatched: the warehouse goes down to 16, nothing at the store yet: ' || pg_temp.tx('w2'));
select pg_temp.put('w3', pg_temp.err(format($q$select public.receive_transfer(%L, null, 'NPX arrived', true)$q$, pg_temp.fx('rw'))));
select pg_temp.check(pg_temp.tx('w3') = 'ok' and pg_temp.status('rw') = 'received' and pg_temp.qty_store('sa', 'p') = 4
    and (select count(*) from stock_movements where transfer_request_id = pg_temp.fx('rw') and movement_type = 'transfer_dispatch') = 1
    and (select count(*) from stock_movements where transfer_request_id = pg_temp.fx('rw') and movement_type = 'transfer_receipt'
           and to_store_id = pg_temp.fx('sa') and quantity = 4) = 1
    and not pg_temp.priced('sa', 'p'),
  'W3 it is received in full: the store holds 4 (dispatch and receipt movements), and still has no price for it: ' || pg_temp.tx('w3'));

-- ═════ S Store -> Store into the store with no price list ═════
select pg_temp.put('s1', pg_temp.err(format(
  $q$select pg_temp.putx('rs', (public.create_transfer_request('store_to_store','store',%L,'store',%L,
       jsonb_build_array(jsonb_build_object('line_kind','product','product_id',%L,'quantity',1)),null)->>'id')::uuid)$q$,
  pg_temp.fx('sa'), pg_temp.fx('sb'), pg_temp.fx('p'))));
select pg_temp.put('s2', pg_temp.err(format(
  $q$select public.review_and_dispatch_transfer(%L, jsonb_build_array(jsonb_build_object('line_id',%L,'approved_quantity',1,
       'sources',jsonb_build_array(jsonb_build_object('source_type','store','source_id',%L,'quantity',1)))),null)$q$,
  pg_temp.fx('rs'), pg_temp.line_of('rs', 'p'), pg_temp.fx('sa'))));
select pg_temp.put('s3', pg_temp.err(format($q$select public.receive_transfer(%L, null, null, true)$q$, pg_temp.fx('rs'))));
select pg_temp.check(pg_temp.tx('s1') = 'ok' and pg_temp.tx('s2') = 'ok' and pg_temp.tx('s3') = 'ok'
    and pg_temp.status('rs') = 'received' and pg_temp.qty_store('sa', 'p') = 3 and pg_temp.qty_store('sb', 'p') = 1,
  format('S1 Store -> Store into a store with no price list: created, dispatched, received (A 3, B 1): %s / %s / %s',
         pg_temp.tx('s1'), pg_temp.tx('s2'), pg_temp.tx('s3')));

-- ═════ T A Staff request, a product added during Review, received by staff ═════
select pg_temp.as_user('staff');
select pg_temp.put('t1', pg_temp.err(format(
  $q$select pg_temp.putx('rt', (public.create_staff_transfer_request(
       jsonb_build_array(jsonb_build_object('line_kind','product','product_id',%L,'quantity',3)),'NPX shelf is empty',%L)->>'id')::uuid)$q$,
  pg_temp.fx('p'), pg_temp.fx('sa'))));
select pg_temp.check(pg_temp.tx('t1') = 'ok' and pg_temp.status('rt') = 'pending'
    and (select (source_id, dest_id) from transfer_requests where id = pg_temp.fx('rt')) = (null::uuid, pg_temp.fx('sa')),
  'T1 a Staff request into their store for a product with no price there is created (source left to Review): ' || pg_temp.tx('t1'));
select pg_temp.as_user('owner');
select pg_temp.put('t2', pg_temp.err(format(
  $q$select public.review_and_dispatch_transfer(%L, jsonb_build_array(
       jsonb_build_object('line_id',%L,'approved_quantity',3,
         'sources',jsonb_build_array(jsonb_build_object('source_type','warehouse','source_id',%L,'quantity',3))),
       jsonb_build_object('line_kind','product','product_id',%L,'approved_quantity',2,
         'sources',jsonb_build_array(jsonb_build_object('source_type','warehouse','source_id',%L,'quantity',2)))),'NPX with a mat')$q$,
  pg_temp.fx('rt'), pg_temp.line_of('rt', 'p'), pg_temp.fx('w'), pg_temp.fx('m'), pg_temp.fx('w'))));
select pg_temp.check(pg_temp.tx('t2') = 'ok' and pg_temp.status('rt') = 'in_transit'
    and pg_temp.qty_wh('w', 'p') = 13 and pg_temp.qty_wh('w', 'm') = 8
    and (select added_by_approver from transfer_request_lines where id = pg_temp.line_of('rt', 'm')),
  'T2 Review dispatches it and adds another product with no price at the store (Pillow 13, Mat 8 left): ' || pg_temp.tx('t2'));
select pg_temp.as_user('staff');
select pg_temp.put('t3', pg_temp.err(format(
  $q$select public.receive_transfer(%L, jsonb_build_array(
       jsonb_build_object('line_id',%L,'received_quantity',3),
       jsonb_build_object('line_id',%L,'received_quantity',1,'reason','NPX one torn')),'NPX one mat torn',false)$q$,
  pg_temp.fx('rt'), pg_temp.line_of('rt', 'p'), pg_temp.line_of('rt', 'm'))));
select pg_temp.check(pg_temp.tx('t3') = 'ok' and pg_temp.status('rt') = 'received_with_discrepancy'
    and pg_temp.qty_store('sa', 'p') = 6 and pg_temp.qty_store('sa', 'm') = 1
    and (select discrepancy_quantity from transfer_request_lines where id = pg_temp.line_of('rt', 'm')) = -1,
  'T3 the staff member receives it at their store, one Mat short with a reason (Pillow 6, Mat 1): ' || pg_temp.tx('t3'));

-- ═════ E An edit to a store with no price for the product ═════
select pg_temp.as_user('owner');
select pg_temp.put('e1', pg_temp.err(format(
  $q$select pg_temp.putx('re', (public.create_transfer_request('warehouse_to_store','warehouse',%L,'store',%L,
       jsonb_build_array(jsonb_build_object('line_kind','product','product_id',%L,'quantity',2)),null)->>'id')::uuid)$q$,
  pg_temp.fx('w'), pg_temp.fx('sa'), pg_temp.fx('q'))));
select pg_temp.put('e2', pg_temp.err(format(
  $q$select public.edit_transfer_request(%L, 1, 'NPX goes to B instead', null, null, 'store'::location_type, %L,
       jsonb_build_array(jsonb_build_object('line_kind','product','product_id',%L,'quantity',2),
                         jsonb_build_object('line_kind','product','product_id',%L,'quantity',1)), null)$q$,
  pg_temp.fx('re'), pg_temp.fx('sb'), pg_temp.fx('q'), pg_temp.fx('p'))));
select pg_temp.check(pg_temp.tx('e1') = 'ok' and pg_temp.tx('e2') = 'ok'
    and (select (dest_id, version) from transfer_requests where id = pg_temp.fx('re')) = (pg_temp.fx('sb'), 2)
    and (select count(*) from transfer_request_lines where transfer_request_id = pg_temp.fx('re')) = 2,
  format('E1 a request for a product priced at A is edited to go to B (no price list) with another unpriced line: %s / %s',
         pg_temp.tx('e1'), pg_temp.tx('e2')));
select pg_temp.put('e3', pg_temp.err(format(
  $q$select public.review_and_dispatch_transfer(%L, jsonb_build_array(
       jsonb_build_object('line_id',%L,'approved_quantity',2,'sources',jsonb_build_array(jsonb_build_object('source_type','warehouse','source_id',%L,'quantity',2))),
       jsonb_build_object('line_id',%L,'approved_quantity',1,'sources',jsonb_build_array(jsonb_build_object('source_type','warehouse','source_id',%L,'quantity',1)))),null)$q$,
  pg_temp.fx('re'), pg_temp.line_of('re', 'q'), pg_temp.fx('w'), pg_temp.line_of('re', 'p'), pg_temp.fx('w'))));
select pg_temp.put('e4', pg_temp.err(format($q$select public.receive_transfer(%L, null, null, true)$q$, pg_temp.fx('re'))));
select pg_temp.check(pg_temp.tx('e3') = 'ok' and pg_temp.tx('e4') = 'ok' and pg_temp.status('re') = 'received'
    and pg_temp.qty_store('sb', 'q') = 2 and pg_temp.qty_store('sb', 'p') = 2,
  format('E2 the edited request is dispatched and received at B (Cup 2, Pillow 2): %s / %s', pg_temp.tx('e3'), pg_temp.tx('e4')));

-- ═════ D The deferred request (the service role's) ═════
select pg_temp.put('d1', pg_temp.err(format(
  $q$select pg_temp.putx('rd', public.create_deferred_transfer_request('store'::location_type, %L,
       jsonb_build_array(jsonb_build_object('product_id',%L,'quantity',1)), 'NPX deferred'))$q$,
  pg_temp.fx('sb'), pg_temp.fx('m'))));
select pg_temp.check(pg_temp.tx('d1') = 'ok' and pg_temp.status('rd') = 'pending',
  'D1 create_deferred_transfer_request into a store with no price for the product is created: ' || pg_temp.tx('d1'));

-- ═════ K The other rules still hold for an unpriced product ═════
select pg_temp.put('k1', pg_temp.err(format(
  $q$select public.create_transfer_request('warehouse_to_store','warehouse',%L,'store',%L,
       jsonb_build_array(jsonb_build_object('line_kind','product','product_id',%L,'quantity',500)),null)$q$,
  pg_temp.fx('w'), pg_temp.fx('sb'), pg_temp.fx('p'))));
select pg_temp.put('k2', pg_temp.err(format(
  $q$select public.create_transfer_request('warehouse_to_store','warehouse',%L,'store',%L,
       jsonb_build_array(jsonb_build_object('line_kind','product','product_id',%L,'quantity',1),
                         jsonb_build_object('line_kind','product','product_id',%L,'quantity',1)),null)$q$,
  pg_temp.fx('w'), pg_temp.fx('sb'), pg_temp.fx('p'), pg_temp.fx('p'))));
select pg_temp.as_user('staff');
select pg_temp.put('k3', pg_temp.err(format(
  $q$select public.create_staff_transfer_request(jsonb_build_array(jsonb_build_object('line_kind','product','product_id',%L,'quantity',1)),null,%L)$q$,
  pg_temp.fx('p'), pg_temp.fx('sb'))));
select pg_temp.put('k4', pg_temp.err(format(
  $q$select public.create_transfer_request('store_to_store','store',%L,'store',%L,
       jsonb_build_array(jsonb_build_object('line_kind','product','product_id',%L,'quantity',1)),null)$q$,
  pg_temp.fx('sb'), pg_temp.fx('sa'), pg_temp.fx('p'))));
select pg_temp.check(pg_temp.tx('k1') like 'Insufficient available stock at source for "NPX Pillow"%'
    and pg_temp.tx('k2') = 'The same product cannot appear twice in one transfer'
    and pg_temp.tx('k3') = 'You are not assigned to that store.'
    and pg_temp.tx('k4') = 'Staff can only transfer from their assigned store',
  format('K1 still refused: too little stock (%s), the same product twice (%s), Staff into a store not theirs (%s), Staff from one (%s)',
         pg_temp.tx('k1'), pg_temp.tx('k2'), pg_temp.tx('k3'), pg_temp.tx('k4')));

-- ═════ I Selling still needs a price ═════
select pg_temp.as_user('owner');
select pg_temp.put('i1', pg_temp.err(format(
  $q$select public.create_invoice(%L, %L, null, jsonb_build_array(jsonb_build_object('kind','product','product_id',%L,'quantity',1)))$q$,
  pg_temp.fx('sa'), pg_temp.fx('cust'), pg_temp.fx('p'))));
select pg_temp.put('i2', pg_temp.err(format(
  $q$select public.create_invoice(%L, %L, null, jsonb_build_array(jsonb_build_object('kind','product','product_id',%L,'quantity',1)))$q$,
  pg_temp.fx('sb'), pg_temp.fx('cust'), pg_temp.fx('q'))));
select pg_temp.check(pg_temp.tx('i1') = 'No price set for "NPX Pillow" in this store'
    and pg_temp.tx('i2') = 'No price set for "NPX Cup" in this store'
    and (select count(*) from invoices where customer_id = pg_temp.fx('cust')) = 0,
  format('I1 an invoice for a product the store holds by transfer but has no price for is refused, at A (%s) and at B (%s)',
         pg_temp.tx('i1'), pg_temp.tx('i2')));
select pg_temp.put('i3', pg_temp.err(format(
  $q$select public.set_product_prices(%L, %L, 25, 25, 'available')$q$, pg_temp.fx('sa'), pg_temp.fx('p'))));
select pg_temp.put('i4', pg_temp.err(format(
  $q$select pg_temp.putx('inv', public.create_invoice(%L, %L, null, jsonb_build_array(jsonb_build_object('kind','product','product_id',%L,'quantity',1))))$q$,
  pg_temp.fx('sa'), pg_temp.fx('cust'), pg_temp.fx('p'))));
select pg_temp.check(pg_temp.tx('i3') = 'ok' and pg_temp.tx('i4') = 'ok'
    and (select (store_id, customer_id) from invoices where id = pg_temp.fx('inv')) = (pg_temp.fx('sa'), pg_temp.fx('cust'))
    and (select unit_price from invoice_items where invoice_id = pg_temp.fx('inv')) = 25,
  format('I2 once a price is set at A (the Price List''s set_product_prices), the invoice goes through at S$25: %s / %s',
         pg_temp.tx('i3'), pg_temp.tx('i4')));

-- ═════ M 452 twice ═════
\if :{?skip_install}
\else
select pg_temp.check(not exists (select 1 from m452 m left join pg_temp.fn_md5s() f on f.fn = m.fn where f.fn is null or f.md5 <> m.md5)
    and (select count(*) from pg_temp.fn_md5s()) = (select count(*) from m452),
  'M1 running 452 a second time changed no function');
select pg_temp.check((select coalesce(array_agg(m.fn order by m.fn), '{}') from m452 m left join b452 b on b.fn = m.fn
                       where b.fn is null or b.md5 <> m.md5) = array['assert_transfer_prices_ok(uuid,uuid[])']
    and (select count(*) from m452) = (select count(*) from b452),
  'M2 its first run changed assert_transfer_prices_ok alone (no function added or dropped)');
select pg_temp.check((select before = after1 from r452),
  'M3 452''s self-test left no row (every table of public and auth counts the same before and after it)');
\endif

do $$ declare v_failed int; begin
  select count(*) into v_failed from failed;
  if v_failed > 0 then raise exception '% check(s) failed: %', v_failed, (select string_agg(msg, '; ' order by n) from failed); end if;
  raise notice 'All 452 checks passed.';
end $$;
rollback;
