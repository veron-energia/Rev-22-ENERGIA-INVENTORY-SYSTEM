-- Products, stores and warehouses: who edits them, deleting and restoring, and
-- who works at which store (420).
--
-- The Owner's answers of 9 Oct 2026:
--   Q12: the app refuses to delete a product, store or warehouse that still
--        holds stock (or has stock on the way: an open transfer, a loan, a
--        live promotion, a special product, a correction waiting for approval,
--        a rental not yet put back, one cancelled while still with the
--        customer included; for a warehouse also special stock).
--        Switching a product off is the
--        same (the audit's fix), and so is switching a store or warehouse off
--        (the Owner's later answer, 9 Oct 2026: not while it still holds
--        stock). A deleted one can be restored. Nothing is removed outright
--        any more.
--   Q13: an Inventory Manager handles product details (name, SKU, cost,
--        category, supplier) like an Owner or Manager; an Admin looks but does
--        not change. Managers put Staff and Inventory Managers on the stores
--        they work at; only an Owner changes a Manager's stores; nobody
--        changes their own. Store assignments go through assign_user_store.
-- And save_product saves a product and its category and supplier links
-- together, saying every refusal (STOCK-12a).
--
-- Needs migration 420. Disposable database only; everything is rolled back.
-- Fixture names carry "PRDX"; emails end in @sig.invalid; nothing real is read.
\set ON_ERROR_STOP on
begin;

create function pg_temp.try_as(p_who uuid, p_sql text) returns text language plpgsql as $f$
declare v text; s text; m text;
begin
  begin
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claim.role', '', true);
    if p_who is null then
      perform set_config('request.jwt.claims', '', true);
    else
      perform set_config('request.jwt.claims', json_build_object('sub', p_who, 'role', 'authenticated')::text, true);
      execute 'set local role authenticated';
    end if;
    execute p_sql into v;
    execute 'reset role';
    return 'ok:' || coalesce(v, '');
  exception when others then
    get stacked diagnostics s = returned_sqlstate, m = message_text;
    return s || ':' || m;
  end;
end $f$;

create function pg_temp.expect(p_got text, p_like text, p_label text) returns void language plpgsql as $f$
begin
  if p_got is null or p_got not like p_like then
    raise exception 'FAIL: %: expected % but got %', p_label, p_like, coalesce(p_got, '<null>');
  end if;
end $f$;

do $$
declare
  own uuid; adm uuid; mgr uuid; mgr2 uuid; inv uuid; stf uuid; gone uuid;
  sa uuid; sb uuid; s_stock uuid; s_tr uuid; s_loan uuid; s_adj uuid; s_ok uuid; s_shut uuid; s_rent uuid;
  w uuid; w_stock uuid; w_special uuid; w_ok uuid; w_rent uuid; cust uuid; rt uuid; rt_w uuid; rt_c uuid;
  p_stock uuid; p_tr uuid; p_loan uuid; p_promo uuid; p_ended uuid; p_special uuid; p_adj uuid; p_ok uuid; p_del uuid;
  c1 uuid; c2 uuid; c3 uuid; su1 uuid; br uuid; promo uuid; promo_old uuid; sp uuid; tr uuid;
  r text; v_new uuid;
begin
  perform set_config('request.jwt.claims', '', true);
  insert into auth.users (id, email)
  select gen_random_uuid(), 'prdx-' || k || '@sig.invalid'
    from unnest(array['owner','admin','manager','manager2','invman','staff','gone']) k;
  select id into own from auth.users where email = 'prdx-owner@sig.invalid';
  select id into adm from auth.users where email = 'prdx-admin@sig.invalid';
  select id into mgr from auth.users where email = 'prdx-manager@sig.invalid';
  select id into mgr2 from auth.users where email = 'prdx-manager2@sig.invalid';
  select id into inv from auth.users where email = 'prdx-invman@sig.invalid';
  select id into stf from auth.users where email = 'prdx-staff@sig.invalid';
  select id into gone from auth.users where email = 'prdx-gone@sig.invalid';
  insert into public.profiles (id, full_name, email, role, is_active)
  select u.id, 'PRDX ' || x.role, u.email, x.role::public.user_role, true
    from auth.users u join (values (own, 'owner'), (adm, 'admin'), (mgr, 'manager'), (mgr2, 'manager'),
                                   (inv, 'inventory_manager'), (stf, 'staff'), (gone, 'staff')) x(id, role) on x.id = u.id;
  update public.profiles set deleted_at = now() where id = gone;

  insert into public.stores (name, code, country_code) values ('PRDX Store A', 'PRDX-A', 'SG') returning id into sa;
  insert into public.stores (name, code, country_code) values ('PRDX Store B', 'PRDX-B', 'SG') returning id into sb;
  insert into public.stores (name, code, country_code) values ('PRDX Stocked Store', 'PRDX-S1', 'SG') returning id into s_stock;
  insert into public.stores (name, code, country_code) values ('PRDX Transfer Store', 'PRDX-S2', 'SG') returning id into s_tr;
  insert into public.stores (name, code, country_code) values ('PRDX Loan Store', 'PRDX-S3', 'SG') returning id into s_loan;
  insert into public.stores (name, code, country_code) values ('PRDX Count Store', 'PRDX-S4', 'SG') returning id into s_adj;
  insert into public.stores (name, code, country_code) values ('PRDX Empty Store', 'PRDX-S5', 'SG') returning id into s_ok;
  insert into public.stores (name, code, country_code, deleted_at, is_active) values ('PRDX Shut Store', 'PRDX-S6', 'SG', now(), false) returning id into s_shut;
  insert into public.stores (name, code, country_code) values ('PRDX Rental Store', 'PRDX-S7', 'SG') returning id into s_rent;
  insert into public.warehouses (name, code) values ('PRDX Warehouse', 'PRDX-W') returning id into w;
  insert into public.warehouses (name, code) values ('PRDX Stocked Warehouse', 'PRDX-W1') returning id into w_stock;
  insert into public.warehouses (name, code) values ('PRDX Special Warehouse', 'PRDX-W2') returning id into w_special;
  insert into public.warehouses (name, code) values ('PRDX Empty Warehouse', 'PRDX-W3') returning id into w_ok;
  insert into public.warehouses (name, code) values ('PRDX Rental Warehouse', 'PRDX-W4') returning id into w_rent;
  insert into public.user_store_assignments (user_id, store_id) values (mgr, sa), (stf, sa);

  insert into public.categories (name) values ('PRDX Cat 1') returning id into c1;
  insert into public.categories (name) values ('PRDX Cat 2') returning id into c2;
  insert into public.categories (name) values ('PRDX Cat 3') returning id into c3;
  insert into public.suppliers (name) values ('PRDX Supplier') returning id into su1;
  insert into public.brands (name) values ('PRDX Brand') returning id into br;

  insert into public.products (name, sku) values ('PRDX Stocked', 'PRDX-1') returning id into p_stock;
  insert into public.products (name, sku) values ('PRDX On Transfer', 'PRDX-2') returning id into p_tr;
  insert into public.products (name, sku) values ('PRDX Lent', 'PRDX-3') returning id into p_loan;
  insert into public.products (name, sku) values ('PRDX In Promo', 'PRDX-4') returning id into p_promo;
  insert into public.products (name, sku) values ('PRDX In Old Promo', 'PRDX-5') returning id into p_ended;
  insert into public.products (name, sku) values ('PRDX Special Base', 'PRDX-6') returning id into p_special;
  insert into public.products (name, sku) values ('PRDX Counted', 'PRDX-7') returning id into p_adj;
  insert into public.products (name, sku) values ('PRDX Clean', 'PRDX-8') returning id into p_ok;
  insert into public.products (name, sku, deleted_at, is_active) values ('PRDX Deleted', 'PRDX-9', now(), false) returning id into p_del;

  -- What stands in the way.
  insert into public.store_inventory (store_id, product_id, current_qty) values (sa, p_stock, 3), (s_stock, p_ok, 0), (s_stock, p_stock, 4), (s_loan, p_loan, 2);
  insert into public.warehouse_inventory (warehouse_id, product_id, current_qty) values (w_stock, p_stock, 6);
  insert into public.transfer_requests (transfer_type, dest_type, dest_id, status, requested_by)
    values ('warehouse_to_store', 'store', s_tr, 'pending', stf) returning id into tr;
  insert into public.transfer_request_lines (transfer_request_id, product_id, quantity) values (tr, p_tr, 2);
  perform set_config('request.jwt.claims', json_build_object('sub', own, 'role', 'authenticated')::text, true);
  perform public.lend_stock('store', s_loan, jsonb_build_array(jsonb_build_object('product_id', p_loan, 'quantity', 2)),
                            public.sg_today() + 3, null, 'PRDX Roadshow', 'Trial', null);
  perform set_config('request.jwt.claims', '', true);
  insert into public.promotions (name, code, start_date, end_date) values ('PRDX Promo', 'PRDX-PROMO', public.sg_today() - 1, public.sg_today() + 30)
    returning id into promo;
  insert into public.promotions (name, code, start_date, end_date) values ('PRDX Old Promo', 'PRDX-OLD', public.sg_today() - 60, public.sg_today() - 30)
    returning id into promo_old;
  insert into public.promotion_items (promotion_id, item_type, product_id) values (promo, 'product', p_promo), (promo_old, 'product', p_ended);
  insert into public.special_products (name, sku, product_id) values ('PRDX Special', 'PRDX-SP', p_special) returning id into sp;
  insert into public.special_product_stock (special_product_id, warehouse_id, current_qty) values (sp, w_special, 5);
  -- A rental released from a store with no stock left, and a rental of a
  -- warehouse with no stock: each comes back there (rental_put_back_stock).
  insert into public.customers (full_name, phone) values ('PRDX Renter', '+61491571491') returning id into cust;
  insert into public.rentals (rental_no, special_product_id, customer_id, quantity, rate_type, periods, start_date,
                              expected_return_date, status, fulfilled_at, source_store_id)
    values ('PRDX-R1', sp, cust, 1, 'day', 1, current_date, current_date + 7, 'active', now(), s_rent) returning id into rt;
  insert into public.rentals (rental_no, special_product_id, customer_id, quantity, rate_type, periods, start_date,
                              expected_return_date, status, warehouse_id)
    values ('PRDX-R2', sp, cust, 1, 'day', 1, current_date, current_date + 7, 'active', w_rent) returning id into rt_w;
  perform pg_temp.expect(pg_temp.try_as(own, format($q$select public.request_inventory_adjustment('store', %L, %L, 1, 'Found one')::text$q$, s_adj, p_adj)),
    'ok:%', 'a pending correction for the fixture');

  -- ── 1. Who edits products (Q13) ─────────────────────────────────────────
  r := pg_temp.try_as(inv, format($q$select public.save_product(null, %L, %L, %L)::text$q$,
    jsonb_build_object('name', ' PRDX New ', 'sku', 'PRDX-NEW', 'product_type', 'no_commission', 'default_cost_price', '12.50',
                       'brand_id', br, 'uom', '', 'is_active', true),
    array[c1, c2], array[su1]));
  perform pg_temp.expect(r, 'ok:%"created": true%', 'an Inventory Manager adds a product with its links');
  v_new := (substr(r, 4)::jsonb ->> 'product_id')::uuid;
  if not exists (select 1 from public.products p where p.id = v_new and p.name = 'PRDX New' and p.uom = 'pcs'
                  and p.default_cost_price = 12.50 and p.product_type = 'no_commission' and p.brand_id = br)
     or (select array_agg(category_id order by category_id) from public.product_categories where product_id = v_new)
        is distinct from (select array_agg(x order by x) from unnest(array[c1, c2]) x)
     or not exists (select 1 from public.product_suppliers where product_id = v_new and supplier_id = su1)
     or not exists (select 1 from public.audit_logs a where a.record_id = v_new and a.action = 'product_created' and a.changed_by = inv) then
    raise exception 'FAIL: the new product, its links or its audit row are not as sent'; end if;
  perform pg_temp.expect(pg_temp.try_as(mgr, format($q$select public.save_product(%L, %L, %L, null)::text$q$,
      v_new, jsonb_build_object('name', 'PRDX New Name'), array[c2, c3])), 'ok:%"created": false%', 'a Manager changes the name and the categories');
  if (select name from public.products where id = v_new) <> 'PRDX New Name'
     or (select default_cost_price from public.products where id = v_new) <> 12.50
     or (select array_agg(category_id order by category_id) from public.product_categories where product_id = v_new)
        is distinct from (select array_agg(x order by x) from unnest(array[c2, c3]) x)
     or not exists (select 1 from public.product_suppliers where product_id = v_new and supplier_id = su1) then
    raise exception 'FAIL: an edit lost what it did not send, or did not replace the categories'; end if;
  perform pg_temp.expect(pg_temp.try_as(adm, format($q$select public.save_product(%L, %L)::text$q$, v_new, jsonb_build_object('name', 'X'))),
    '42501:Only an Owner, Manager or Inventory Manager can add or change products.', 'an Admin looks but does not change');
  perform pg_temp.expect(pg_temp.try_as(stf, format($q$select public.save_product(null, %L)::text$q$, jsonb_build_object('name', 'X', 'sku', 'X'))),
    '42501:%', 'Staff cannot add products');
  -- Every refusal is said.
  perform pg_temp.expect(pg_temp.try_as(inv, format($q$select public.save_product(null, %L)::text$q$, jsonb_build_object('name', 'Dup', 'sku', 'PRDX-1'))),
    'P0001:That SKU already exists (PRDX Stocked). Use a unique product code.', 'a SKU in use');
  perform pg_temp.expect(pg_temp.try_as(inv, format($q$select public.save_product(null, %L)::text$q$, jsonb_build_object('name', 'Dup', 'sku', 'PRDX-9'))),
    'P0001:That SKU belongs to a deleted product (PRDX Deleted). Tick "Show deleted" and restore it instead.', 'a deleted product''s SKU');
  perform pg_temp.expect(pg_temp.try_as(inv, format($q$select public.save_product(%L, %L)::text$q$, v_new, jsonb_build_object('default_cost_price', '1.234'))),
    'P0001:Cost price must be 0 or more, with at most 2 decimal places.', 'a cost with three decimals');
  perform pg_temp.expect(pg_temp.try_as(inv, format($q$select public.save_product(%L, %L)::text$q$, v_new, jsonb_build_object('default_cost_price', '-1'))),
    'P0001:Cost price must be 0 or more%', 'a negative cost');
  perform pg_temp.expect(pg_temp.try_as(inv, format($q$select public.save_product(%L, %L)::text$q$, v_new, jsonb_build_object('brand_id', gen_random_uuid()))),
    'P0001:Choose a brand from the list.', 'a brand that does not exist');
  perform pg_temp.expect(pg_temp.try_as(inv, format($q$select public.save_product(%L, %L, %L)::text$q$, v_new, '{}'::jsonb, array[gen_random_uuid()])),
    'P0001:A chosen category no longer exists.%', 'a category that does not exist');
  -- A link to a category deleted since stays on a save (the page sends it
  -- back); a new link to a deleted category is refused.
  update public.categories set deleted_at = now() where id = c3;
  perform pg_temp.expect(pg_temp.try_as(inv, format($q$select public.save_product(%L, %L, %L)::text$q$, v_new, '{}'::jsonb, array[c2, c3])),
    'ok:%', 'a link to a category deleted since is kept');
  perform pg_temp.expect(pg_temp.try_as(inv, format($q$select public.save_product(null, %L, %L)::text$q$,
      jsonb_build_object('name', 'PRDX Newer', 'sku', 'PRDX-NEWER'), array[c3])),
    'P0001:A chosen category no longer exists.%', 'a new link to a deleted category');
  update public.categories set deleted_at = null where id = c3;
  perform pg_temp.expect(pg_temp.try_as(inv, format($q$select public.save_product(%L, %L)::text$q$, v_new, jsonb_build_object('name', '  '))),
    'P0001:Product name is required.', 'an empty name');
  perform pg_temp.expect(pg_temp.try_as(inv, format($q$select public.save_product(%L, %L)::text$q$, p_del, jsonb_build_object('name', 'Back'))),
    'P0001:This product is deleted. Restore it first.', 'editing a deleted product');
  -- The table rules match: Owner, Manager, Inventory Manager change products and
  -- their links; nobody removes a product outright.
  perform pg_temp.expect(pg_temp.try_as(inv, format($q$with u as (update public.products set barcode = 'PRDX-BC' where id = %L returning 1) select count(*)::text from u$q$, v_new)),
    'ok:1', 'an Inventory Manager edits a product directly, as the old page did');
  perform pg_temp.expect(pg_temp.try_as(adm, format($q$with u as (update public.products set barcode = 'x' where id = %L returning 1) select count(*)::text from u$q$, v_new)),
    'ok:0', 'an Admin''s direct edit changes nothing');
  perform pg_temp.expect(pg_temp.try_as(stf, format($q$with u as (update public.products set barcode = 'x' where id = %L returning 1) select count(*)::text from u$q$, v_new)),
    'ok:0', 'Staff''s direct edit changes nothing');
  perform pg_temp.expect(pg_temp.try_as(inv, format($q$insert into public.product_categories (product_id, category_id) values (%L, %L) returning 1$q$, v_new, c1)),
    'ok:1', 'an Inventory Manager ticks a category');
  perform pg_temp.expect(pg_temp.try_as(stf, format($q$insert into public.product_suppliers (product_id, supplier_id) values (%L, %L) returning 1$q$, p_ok, su1)),
    '42501:%', 'Staff cannot tick a supplier');
  perform pg_temp.expect(pg_temp.try_as(own, format($q$delete from public.products where id = %L returning 1$q$, p_ok)),
    '42501:%', 'an Owner cannot remove a product outright');

  -- ── 2. Deleting a product (Q12) ─────────────────────────────────────────
  perform pg_temp.expect(pg_temp.try_as(inv, format($q$select public.soft_delete_product(%L)::text$q$, p_stock)),
    'P0001:PRDX Stocked cannot be deleted yet. Still open: stock (4 at PRDX Stocked Store, 6 at PRDX Stocked Warehouse, 3 at PRDX Store A).',
    'a product with stock');
  perform pg_temp.expect(pg_temp.try_as(inv, format($q$select public.soft_delete_product(%L)::text$q$, p_tr)),
    'P0001:PRDX On Transfer cannot be deleted yet. Still open: 1 open transfer.', 'a product on an open transfer');
  perform pg_temp.expect(pg_temp.try_as(inv, format($q$select public.soft_delete_product(%L)::text$q$, p_loan)),
    'P0001:PRDX Lent cannot be deleted yet. Still open: stock out on loan (%).', 'a product out on loan');
  perform pg_temp.expect(pg_temp.try_as(inv, format($q$select public.soft_delete_product(%L)::text$q$, p_promo)),
    'P0001:PRDX In Promo cannot be deleted yet. Still open: a live promotion (PRDX Promo).', 'a product in a live promotion');
  perform pg_temp.expect(pg_temp.try_as(inv, format($q$select public.soft_delete_product(%L)::text$q$, p_special)),
    'P0001:PRDX Special Base cannot be deleted yet. Still open: a special product (PRDX Special).', 'a special product''s base');
  perform pg_temp.expect(pg_temp.try_as(inv, format($q$select public.soft_delete_product(%L)::text$q$, p_adj)),
    'P0001:PRDX Counted cannot be deleted yet. Still open: a stock correction waiting for approval.', 'a product with a pending correction');
  perform pg_temp.expect(pg_temp.try_as(inv, format($q$select public.soft_delete_product(%L)::text$q$, p_ended)),
    'ok:%"already": false%', 'a product only in an ended promotion');
  -- Switching off is the same, by save_product or directly.
  perform pg_temp.expect(pg_temp.try_as(inv, format($q$select public.save_product(%L, %L)::text$q$, p_stock, jsonb_build_object('is_active', false))),
    'P0001:PRDX Stocked cannot be switched off yet. Still open: stock (%', 'switching off a product with stock');
  perform pg_temp.expect(pg_temp.try_as(mgr, format($q$update public.products set is_active = false where id = %L returning 1$q$, p_stock)),
    'P0001:PRDX Stocked cannot be switched off yet.%', 'switching it off directly');
  perform pg_temp.expect(pg_temp.try_as(null, format($q$update public.products set deleted_at = now() where id = %L returning 1$q$, p_stock)),
    'P0001:PRDX Stocked cannot be deleted yet.%', 'deleting it from the SQL editor');
  -- A clean product: deleted, hidden, restored, with audit rows.
  perform pg_temp.expect(pg_temp.try_as(stf, format($q$select public.soft_delete_product(%L)::text$q$, p_ok)), '42501:%', 'Staff cannot delete products');
  perform pg_temp.expect(pg_temp.try_as(adm, format($q$select public.soft_delete_product(%L)::text$q$, p_ok)), '42501:%', 'an Admin cannot delete products');
  perform pg_temp.expect(pg_temp.try_as(mgr, format($q$select public.soft_delete_product(%L)::text$q$, p_ok)), 'ok:%"already": false%', 'a clean product is deleted');
  if not exists (select 1 from public.products where id = p_ok and deleted_at is not null and not is_active)
     or not exists (select 1 from public.audit_logs a where a.record_id = p_ok and a.action = 'product_deleted' and a.changed_by = mgr) then
    raise exception 'FAIL: the deleted product is not hidden, or has no audit row'; end if;
  perform pg_temp.expect(pg_temp.try_as(mgr, format($q$select public.soft_delete_product(%L)::text$q$, p_ok)), 'ok:%"already": true%', 'deleting it again');
  perform pg_temp.expect(pg_temp.try_as(stf, format($q$select public.restore_product(%L)::text$q$, p_ok)), '42501:%', 'Staff cannot restore');
  perform pg_temp.expect(pg_temp.try_as(inv, format($q$select public.restore_product(%L)::text$q$, p_ok)), 'ok:%"already": false%', 'an Inventory Manager restores it');
  if not exists (select 1 from public.products where id = p_ok and deleted_at is null and is_active)
     or not exists (select 1 from public.audit_logs a where a.record_id = p_ok and a.action = 'product_restored' and a.changed_by = inv) then
    raise exception 'FAIL: the restored product is not back, or has no audit row'; end if;
  -- Restoring is never stopped (a deleted product that still holds stock, as
  -- three did on 9 Oct 2026).
  insert into public.store_inventory (store_id, product_id, current_qty) values (sb, p_del, 13);
  perform pg_temp.expect(pg_temp.try_as(own, format($q$select public.restore_product(%L)::text$q$, p_del)), 'ok:%"already": false%', 'a deleted product with stock comes back');

  -- ── 3. Stores ───────────────────────────────────────────────────────────
  perform pg_temp.expect(pg_temp.try_as(own, format($q$select public.soft_delete_store(%L)::text$q$, s_stock)),
    'P0001:PRDX Stocked Store cannot be deleted yet. Still open: stock of 1 product (4 units).', 'a store with stock');
  perform pg_temp.expect(pg_temp.try_as(own, format($q$select public.soft_delete_store(%L)::text$q$, s_tr)),
    'P0001:PRDX Transfer Store cannot be deleted yet. Still open: 1 open transfer.', 'a store with an open transfer');
  perform pg_temp.expect(pg_temp.try_as(own, format($q$select public.soft_delete_store(%L)::text$q$, s_loan)),
    'P0001:PRDX Loan Store cannot be deleted yet. Still open: 1 open loan.', 'a store with an open loan');
  perform pg_temp.expect(pg_temp.try_as(own, format($q$select public.soft_delete_store(%L)::text$q$, s_adj)),
    'P0001:PRDX Count Store cannot be deleted yet. Still open: 1 stock correction waiting for approval.', 'a store with a pending correction');
  -- A rental released from the store and still out: its return lands there.
  perform pg_temp.expect(pg_temp.try_as(own, format($q$select public.soft_delete_store(%L)::text$q$, s_rent)),
    'P0001:PRDX Rental Store cannot be deleted yet. Still open: 1 open rental.', 'a store with a rental still out');
  -- Cancelled while still with the customer (as cancel_invoice_rentals leaves
  -- it): the item still comes back to this store, so it still counts.
  update public.rentals set status = 'cancelled' where id = rt;
  perform pg_temp.expect(pg_temp.try_as(own, format($q$select public.soft_delete_store(%L)::text$q$, s_rent)),
    'P0001:PRDX Rental Store cannot be deleted yet. Still open: 1 open rental.', 'a store with a rental cancelled while still out');
  perform pg_temp.expect(pg_temp.try_as(mgr, format($q$update public.stores set is_active = false where id = %L returning 1$q$, s_rent)),
    'P0001:PRDX Rental Store cannot be switched off yet. Still open: 1 open rental.', 'switching off a store with a rental cancelled while still out');
  -- A rental cancelled before it was released never left, so it does not count.
  insert into public.rentals (rental_no, special_product_id, customer_id, quantity, rate_type, periods, start_date,
                              expected_return_date, status, source_store_id)
    values ('PRDX-R3', sp, cust, 1, 'day', 1, current_date, current_date + 7, 'cancelled', s_rent) returning id into rt_c;
  -- Returned lost (nothing comes back): the store can go.
  update public.rentals set status = 'returned', returned_at = now(), stock_returned = false where id = rt;
  perform pg_temp.expect(pg_temp.try_as(own, format($q$select public.soft_delete_store(%L)::text$q$, s_rent)),
    'ok:%"already": false%', 'a store whose rental is closed');
  -- Switching a store or warehouse off (Active unticked) is checked the same
  -- way (the Owner, 9 Oct 2026): not while it holds stock or has stock on the
  -- way. The whole save is refused, as the Edit form sends it.
  perform pg_temp.expect(pg_temp.try_as(mgr, format($q$update public.stores set is_active = false, phone = '6000 0001' where id = %L returning 1$q$, s_stock)),
    'P0001:PRDX Stocked Store cannot be switched off yet. Still open: stock of 1 product (4 units).', 'switching a stocked store off from Edit');
  if (select is_active from public.stores where id = s_stock) is not true
     or (select phone from public.stores where id = s_stock) is not distinct from '6000 0001' then
    raise exception 'FAIL: a refused switch-off still changed the store'; end if;
  perform pg_temp.expect(pg_temp.try_as(own, format($q$update public.stores set is_active = false where id = %L returning 1$q$, s_tr)),
    'P0001:PRDX Transfer Store cannot be switched off yet. Still open: 1 open transfer.', 'switching off a store with an open transfer');
  perform pg_temp.expect(pg_temp.try_as(mgr, format($q$update public.stores set is_active = false where id = %L returning 1$q$, s_adj)),
    'P0001:PRDX Count Store cannot be switched off yet. Still open: 1 stock correction waiting for approval.', 'switching off a store with a waiting count');
  perform pg_temp.expect(pg_temp.try_as(null, format($q$update public.stores set is_active = false where id = %L returning 1$q$, s_loan)),
    'P0001:PRDX Loan Store cannot be switched off yet. Still open: 1 open loan.', 'switching it off from the SQL editor');
  perform pg_temp.expect(pg_temp.try_as(mgr, format($q$update public.warehouses set is_active = false where id = %L returning 1$q$, w_stock)),
    'P0001:PRDX Stocked Warehouse cannot be switched off yet. Still open: stock of 1 product (6 units).', 'switching a stocked warehouse off');
  perform pg_temp.expect(pg_temp.try_as(mgr, format($q$update public.warehouses set is_active = false where id = %L returning 1$q$, w_special)),
    'P0001:PRDX Special Warehouse cannot be switched off yet. Still open: special stock (5 units).', 'switching off a warehouse with special stock');
  -- An empty one is switched off and on again; editing a stocked one that
  -- stays on is not stopped.
  perform pg_temp.expect(pg_temp.try_as(mgr, format($q$with u as (update public.stores set is_active = false where id = %L returning 1) select count(*)::text from u$q$, s_ok)),
    'ok:1', 'an empty store is switched off');
  perform pg_temp.expect(pg_temp.try_as(mgr, format($q$with u as (update public.stores set is_active = true where id = %L returning 1) select count(*)::text from u$q$, s_ok)),
    'ok:1', 'and on again');
  perform pg_temp.expect(pg_temp.try_as(own, format($q$with u as (update public.warehouses set is_active = false where id = %L returning 1) select count(*)::text from u$q$, w_ok)),
    'ok:1', 'an empty warehouse is switched off');
  perform pg_temp.expect(pg_temp.try_as(own, format($q$with u as (update public.warehouses set is_active = true where id = %L returning 1) select count(*)::text from u$q$, w_ok)),
    'ok:1', 'and on again');
  perform pg_temp.expect(pg_temp.try_as(mgr, format($q$with u as (update public.stores set is_active = true, phone = '6000 0002' where id = %L returning 1) select count(*)::text from u$q$, s_stock)),
    'ok:1', 'a stocked store that stays on is edited as before');
  perform pg_temp.expect(pg_temp.try_as(own, format($q$delete from public.stores where id = %L returning 1$q$, s_ok)),
    '42501:%', 'an Owner cannot remove a store outright');
  perform pg_temp.expect(pg_temp.try_as(inv, format($q$select public.soft_delete_store(%L)::text$q$, s_ok)), '42501:%', 'an Inventory Manager cannot delete stores');
  perform pg_temp.expect(pg_temp.try_as(mgr, format($q$select public.soft_delete_store(%L)::text$q$, s_ok)), 'ok:%"already": false%', 'a Manager deletes an empty store');
  if not exists (select 1 from public.stores where id = s_ok and deleted_at is not null and not is_active)
     or not exists (select 1 from public.audit_logs a where a.record_id = s_ok and a.action = 'store_deleted') then
    raise exception 'FAIL: the deleted store is not hidden, or has no audit row'; end if;
  perform pg_temp.expect(pg_temp.try_as(stf, format($q$select public.restore_store(%L)::text$q$, s_ok)),
    '42501:Only an Owner or Manager can restore stores.', 'Staff cannot restore a store');
  perform pg_temp.expect(pg_temp.try_as(adm, format($q$select public.restore_store(%L)::text$q$, s_ok)),
    '42501:Only an Owner or Manager can restore stores.', 'an Admin cannot restore a store');
  perform pg_temp.expect(pg_temp.try_as(inv, format($q$select public.restore_store(%L)::text$q$, s_ok)),
    '42501:Only an Owner or Manager can restore stores.', 'an Inventory Manager cannot restore a store');
  perform pg_temp.expect(pg_temp.try_as(own, format($q$select public.restore_store(%L)::text$q$, s_ok)), 'ok:%"already": false%', 'an Owner restores it');
  if not exists (select 1 from public.stores where id = s_ok and deleted_at is null and is_active) then
    raise exception 'FAIL: the restored store is not back'; end if;
  perform pg_temp.expect(pg_temp.try_as(mgr, format($q$with u as (update public.stores set phone = '6000 0000' where id = %L returning 1) select count(*)::text from u$q$, s_ok)),
    'ok:1', 'a Manager still edits a store''s details');
  perform pg_temp.expect(pg_temp.try_as(own, $q$insert into public.stores (name, code, country_code) values ('PRDX New Store', 'PRDX-NEW', 'SG') returning 1$q$),
    'ok:1', 'an Owner still adds a store');

  -- ── 4. Warehouses ───────────────────────────────────────────────────────
  perform pg_temp.expect(pg_temp.try_as(own, format($q$select public.soft_delete_warehouse(%L)::text$q$, w_stock)),
    'P0001:PRDX Stocked Warehouse cannot be deleted yet. Still open: stock of 1 product (6 units).', 'a warehouse with stock');
  perform pg_temp.expect(pg_temp.try_as(own, format($q$select public.soft_delete_warehouse(%L)::text$q$, w_special)),
    'P0001:PRDX Special Warehouse cannot be deleted yet. Still open: special stock (5 units).', 'a warehouse with special stock');
  perform pg_temp.expect(pg_temp.try_as(own, format($q$select public.soft_delete_warehouse(%L)::text$q$, w_rent)),
    'P0001:PRDX Rental Warehouse cannot be deleted yet. Still open: 1 open rental.', 'a warehouse with a rental still out');
  -- An old-style warehouse rental, activated and then cancelled while still
  -- with the customer: it still comes back to this warehouse.
  update public.rentals set status = 'cancelled', activated_at = now() where id = rt_w;
  perform pg_temp.expect(pg_temp.try_as(own, format($q$select public.soft_delete_warehouse(%L)::text$q$, w_rent)),
    'P0001:PRDX Rental Warehouse cannot be deleted yet. Still open: 1 open rental.', 'a warehouse with a rental cancelled while still out');
  perform pg_temp.expect(pg_temp.try_as(mgr, format($q$update public.warehouses set is_active = false where id = %L returning 1$q$, w_rent)),
    'P0001:PRDX Rental Warehouse cannot be switched off yet. Still open: 1 open rental.', 'switching off a warehouse with a rental cancelled while still out');
  -- Already put back (stock_returned): nothing more comes back there.
  update public.rentals set stock_returned = true where id = rt_w;
  perform pg_temp.expect(pg_temp.try_as(own, format($q$select public.soft_delete_warehouse(%L)::text$q$, w_rent)),
    'ok:%"already": false%', 'a warehouse whose rental was put back');
  perform pg_temp.expect(pg_temp.try_as(own, format($q$delete from public.warehouses where id = %L returning 1$q$, w_ok)),
    '42501:%', 'an Owner cannot remove a warehouse outright');
  perform pg_temp.expect(pg_temp.try_as(stf, format($q$select public.soft_delete_warehouse(%L)::text$q$, w_ok)), '42501:%', 'Staff cannot delete warehouses');
  perform pg_temp.expect(pg_temp.try_as(mgr, format($q$select public.soft_delete_warehouse(%L)::text$q$, w_ok)), 'ok:%"already": false%', 'a Manager deletes an empty warehouse');
  perform pg_temp.expect(pg_temp.try_as(stf, format($q$select public.restore_warehouse(%L)::text$q$, w_ok)),
    '42501:Only an Owner or Manager can restore warehouses.', 'Staff cannot restore a warehouse');
  perform pg_temp.expect(pg_temp.try_as(adm, format($q$select public.restore_warehouse(%L)::text$q$, w_ok)),
    '42501:Only an Owner or Manager can restore warehouses.', 'an Admin cannot restore a warehouse');
  perform pg_temp.expect(pg_temp.try_as(inv, format($q$select public.restore_warehouse(%L)::text$q$, w_ok)),
    '42501:Only an Owner or Manager can restore warehouses.', 'an Inventory Manager cannot restore a warehouse');
  perform pg_temp.expect(pg_temp.try_as(mgr, format($q$select public.restore_warehouse(%L)::text$q$, w_ok)), 'ok:%"already": false%', 'a Manager restores it');
  if not exists (select 1 from public.warehouses where id = w_ok and deleted_at is null and is_active)
     or (select count(*) from public.audit_logs a where a.record_id = w_ok and a.action in ('warehouse_deleted', 'warehouse_restored')) <> 2 then
    raise exception 'FAIL: the warehouse did not come back, or has no audit rows'; end if;

  -- ── 5. Who works at which store (Q13; ADMIN-AUTH-15) ────────────────────
  perform pg_temp.expect(pg_temp.try_as(mgr, format($q$select public.assign_user_store(%L, %L, true)::text$q$, inv, sa)),
    'ok:%"changed": true%', 'a Manager puts an Inventory Manager on their store');
  perform pg_temp.expect(pg_temp.try_as(mgr, format($q$select public.assign_user_store(%L, %L, true)::text$q$, inv, sa)),
    'ok:%"changed": false%', 'asking again changes nothing');
  if (select count(*) from public.audit_logs a where a.record_id = inv and a.action = 'store_assigned') <> 1 then
    raise exception 'FAIL: the assignment left no audit row, or two'; end if;
  perform pg_temp.expect(pg_temp.try_as(mgr, format($q$select public.assign_user_store(%L, %L, true)::text$q$, inv, sb)),
    '42501:You can only put people on the stores you work at.', 'a Manager and a store they do not work at');
  perform pg_temp.expect(pg_temp.try_as(mgr, format($q$select public.assign_user_store(%L, %L, true)::text$q$, mgr2, sa)),
    '42501:Only an Owner can change a Manager''s stores.', 'a Manager and another Manager');
  perform pg_temp.expect(pg_temp.try_as(mgr, format($q$select public.assign_user_store(%L, %L, false)::text$q$, mgr, sa)),
    '42501:You cannot change your own stores. Ask an Owner.', 'a Manager and their own stores');
  perform pg_temp.expect(pg_temp.try_as(adm, format($q$select public.assign_user_store(%L, %L, true)::text$q$, mgr2, sb)),
    '42501:Only an Owner can change a Manager''s stores.', 'an Admin and a Manager');
  perform pg_temp.expect(pg_temp.try_as(stf, format($q$select public.assign_user_store(%L, %L, true)::text$q$, inv, sa)),
    '42501:%', 'Staff cannot put people on stores');
  perform pg_temp.expect(pg_temp.try_as(inv, format($q$select public.assign_user_store(%L, %L, true)::text$q$, stf, sa)),
    '42501:%', 'an Inventory Manager cannot put people on stores');
  perform pg_temp.expect(pg_temp.try_as(own, format($q$select public.assign_user_store(%L, %L, true)::text$q$, mgr2, sb)),
    'ok:%"changed": true%', 'an Owner puts a Manager on a store');
  perform pg_temp.expect(pg_temp.try_as(own, format($q$select public.assign_user_store(%L, %L, true)::text$q$, adm, sb)),
    'P0001:Owners and Admins work at every store, so they are not put on one', 'an Admin needs no store');
  perform pg_temp.expect(pg_temp.try_as(own, format($q$select public.assign_user_store(%L, %L, true)::text$q$, stf, s_shut)),
    'P0001:PRDX Shut Store is closed or deleted, so nobody can be put on it', 'a deleted store');
  perform pg_temp.expect(pg_temp.try_as(own, format($q$select public.assign_user_store(%L, %L, true)::text$q$, gone, sa)),
    'P0001:That person is not on the staff list', 'a removed profile');
  perform pg_temp.expect(pg_temp.try_as(own, format($q$insert into public.user_store_assignments (user_id, store_id) values (%L, %L) returning 1$q$, stf, sb)),
    '42501:%', 'an Owner cannot write an assignment directly');
  perform pg_temp.expect(pg_temp.try_as(mgr, format($q$delete from public.user_store_assignments where user_id = %L returning 1$q$, stf)),
    '42501:%', 'a Manager cannot delete an assignment directly');
  -- Taking Staff off a store takes their access to its stock with it.
  perform pg_temp.expect(pg_temp.try_as(stf, format($q$select count(*)::text from public.store_inventory where store_id = %L$q$, sa)), 'ok:1', 'Staff read their store');
  perform pg_temp.expect(pg_temp.try_as(mgr, format($q$select public.assign_user_store(%L, %L, false)::text$q$, stf, sa)),
    'ok:%"changed": true%', 'a Manager takes Staff off their store');
  perform pg_temp.expect(pg_temp.try_as(stf, format($q$select count(*)::text from public.store_inventory where store_id = %L$q$, sa)), 'ok:0', 'Staff no longer read it');

  raise notice 'PASS: Owners, Managers and Inventory Managers add and edit products with their links in one save, every refusal said, Admins and Staff not; a product, store or warehouse holding stock or with stock on the way is neither deleted nor switched off (a rental still out included, one cancelled while still out too), on every path, and a clean one is deleted and restored with audit rows, restored by an Owner or Manager only; nothing is removed outright; Managers put Staff and Inventory Managers on their own stores only, an Owner changes a Manager''s stores, nobody their own, and assignments go through the server only';
end $$;
rollback;
