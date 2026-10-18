-- A multi-line Stock In is saved once, all or nothing (420, STOCK-5).
--
--   * every line of the form is added in one go, or none is: a line that
--     fails (here: a stock count that would overflow) leaves nothing added;
--   * a retry of the same form (same request id, same person, warehouse,
--     lines, reason, note and reference) adds nothing again and answers with
--     the same movements; a changed form under the same id, or another
--     person's id, is refused;
--   * only live products go in, into an open warehouse, and the switched-off
--     or deleted ones are named before anything is added;
--   * whole quantities from 1 to 999,999 (as on the page), each product once,
--     a reason;
--   * the warehouse stock permission (Owner, Manager, Inventory Manager) as
--     before: Staff and Admins are refused;
--   * the replay record is the server's: no signed-in login reads it.
--
-- Needs migration 420. Disposable database only; everything is rolled back.
-- Fixture names carry "SINX"; emails end in @sig.invalid; nothing real is read.
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
  own uuid; mgr uuid; inv uuid; stf uuid; adm uuid;
  w uuid; wclosed uuid; p1 uuid; p2 uuid; plo uuid; phi uuid; pdel uuid;
  rid uuid := gen_random_uuid(); r text; j jsonb; first jsonb; n_moves int; q1 int; q2 int;
begin
  perform set_config('request.jwt.claims', '', true);
  insert into auth.users (id, email)
  select gen_random_uuid(), 'sinx-' || k || '@sig.invalid' from unnest(array['owner','manager','invman','staff','admin']) k;
  select id into own from auth.users where email = 'sinx-owner@sig.invalid';
  select id into mgr from auth.users where email = 'sinx-manager@sig.invalid';
  select id into inv from auth.users where email = 'sinx-invman@sig.invalid';
  select id into stf from auth.users where email = 'sinx-staff@sig.invalid';
  select id into adm from auth.users where email = 'sinx-admin@sig.invalid';
  insert into public.profiles (id, full_name, email, role, is_active)
  select u.id, 'SINX ' || x.role, u.email, x.role::public.user_role, true
    from auth.users u join (values (own, 'owner'), (mgr, 'manager'), (inv, 'inventory_manager'), (stf, 'staff'),
                                   (adm, 'admin')) x(id, role) on x.id = u.id;
  insert into public.warehouses (name, code) values ('SINX Warehouse', 'SINX-W') returning id into w;
  insert into public.warehouses (name, code, is_active) values ('SINX Closed', 'SINX-C', false) returning id into wclosed;
  insert into public.products (name, sku) values ('SINX Mat', 'SINX-1') returning id into p1;
  insert into public.products (name, sku) values ('SINX Lamp', 'SINX-2') returning id into p2;
  insert into public.products (name, sku, deleted_at, is_active) values ('SINX Gone', 'SINX-3', now(), false) returning id into pdel;
  -- Two products in id order, the second nearly full, for the all-or-nothing case.
  insert into public.products (name, sku) values ('SINX A', 'SINX-A'), ('SINX B', 'SINX-B');
  select min(id::text)::uuid, max(id::text)::uuid into plo, phi from public.products where sku in ('SINX-A', 'SINX-B');
  insert into public.warehouse_inventory (warehouse_id, product_id, current_qty) values (w, phi, 2147483640);

  -- ── 1. Two lines in one go, then the same form again ───────────────────
  j := jsonb_build_array(jsonb_build_object('product_id', p1, 'quantity', 3), jsonb_build_object('product_id', p2, 'quantity', 4));
  r := pg_temp.try_as(inv, format($q$select public.warehouse_stock_ins(%L, %L, 'Supplier delivery', 'Box 2', 'DO-1', %L)::text$q$, w, j, rid));
  perform pg_temp.expect(r, 'ok:%"replayed": false%', 'an Inventory Manager adds two lines');
  first := substr(r, 4)::jsonb;
  select count(*) into n_moves from public.stock_movements where to_warehouse_id = w and movement_type = 'warehouse_stock_in';
  if n_moves <> 2
     or (select current_qty from public.warehouse_inventory where warehouse_id = w and product_id = p1) <> 3
     or (select current_qty from public.warehouse_inventory where warehouse_id = w and product_id = p2) <> 4 then
    raise exception 'FAIL: the two lines were not added once each'; end if;
  if (select notes from public.stock_movements where to_warehouse_id = w and product_id = p1) <> 'Supplier delivery — Box 2 (ref: DO-1)' then
    raise exception 'FAIL: the movement does not carry the reason, note and reference as before'; end if;
  r := pg_temp.try_as(inv, format($q$select public.warehouse_stock_ins(%L, %L, 'Supplier delivery', 'Box 2', 'DO-1', %L)::text$q$, w, j, rid));
  perform pg_temp.expect(r, 'ok:%"replayed": true%', 'the same form sent again');
  if (select array_agg(x ->> 'movement_id' order by x ->> 'product_id') from jsonb_array_elements(substr(r, 4)::jsonb -> 'lines') x)
     is distinct from (select array_agg(x ->> 'movement_id' order by x ->> 'product_id') from jsonb_array_elements(first -> 'lines') x) then
    raise exception 'FAIL: the replay did not answer with the same movements'; end if;
  if (select count(*) from public.stock_movements where to_warehouse_id = w and movement_type = 'warehouse_stock_in') <> 2
     or (select current_qty from public.warehouse_inventory where warehouse_id = w and product_id = p1) <> 3 then
    raise exception 'FAIL: the replay added stock again'; end if;
  -- Lines sent in another order are the same form.
  perform pg_temp.expect(pg_temp.try_as(inv, format($q$select public.warehouse_stock_ins(%L, %L, 'Supplier delivery', 'Box 2', 'DO-1', %L)::text$q$,
      w, jsonb_build_array(j -> 1, j -> 0), rid)), 'ok:%"replayed": true%', 'the same lines in another order');
  -- A changed form, another person, another warehouse: refused.
  perform pg_temp.expect(pg_temp.try_as(inv, format($q$select public.warehouse_stock_ins(%L, %L, 'Supplier delivery', 'Box 2', 'DO-1', %L)::text$q$,
      w, jsonb_build_array(jsonb_build_object('product_id', p1, 'quantity', 5)), rid)),
    'P0001:This form was already saved, and has been changed since%', 'a changed form under the same id');
  perform pg_temp.expect(pg_temp.try_as(inv, format($q$select public.warehouse_stock_ins(%L, %L, 'Supplier delivery', null, 'DO-1', %L)::text$q$, w, j, rid)),
    'P0001:This form was already saved, and has been changed since%', 'a note taken off');
  perform pg_temp.expect(pg_temp.try_as(mgr, format($q$select public.warehouse_stock_ins(%L, %L, 'Supplier delivery', 'Box 2', 'DO-1', %L)::text$q$, w, j, rid)),
    'P0001:This form was already used for another stock-in.%', 'another person''s form id');

  -- ── 2. All or nothing ───────────────────────────────────────────────────
  -- plo sorts first and goes in; phi would pass the largest whole number.
  perform pg_temp.expect(pg_temp.try_as(own, format($q$select public.warehouse_stock_ins(%L, %L, 'Delivery', null, null, %L)::text$q$,
      w, jsonb_build_array(jsonb_build_object('product_id', plo, 'quantity', 5), jsonb_build_object('product_id', phi, 'quantity', 100)),
      gen_random_uuid())), '22003:%', 'a line that fails');
  if exists (select 1 from public.warehouse_inventory where warehouse_id = w and product_id = plo)
     or (select current_qty from public.warehouse_inventory where warehouse_id = w and product_id = phi) <> 2147483640
     or exists (select 1 from public.stock_movements where product_id in (plo, phi)) then
    raise exception 'FAIL: a failed form still added its earlier line'; end if;

  -- ── 3. Only live products, into an open warehouse ───────────────────────
  select current_qty into q1 from public.warehouse_inventory where warehouse_id = w and product_id = p1;
  perform pg_temp.expect(pg_temp.try_as(mgr, format($q$select public.warehouse_stock_ins(%L, %L, 'Delivery')::text$q$,
      w, jsonb_build_array(jsonb_build_object('product_id', p1, 'quantity', 1), jsonb_build_object('product_id', pdel, 'quantity', 1)))),
    'P0001:Nothing was added. Switched off or deleted: SINX Gone.%', 'a deleted product is named, nothing added');
  if (select current_qty from public.warehouse_inventory where warehouse_id = w and product_id = p1) <> q1 then
    raise exception 'FAIL: a refused form still added stock'; end if;
  perform pg_temp.expect(pg_temp.try_as(mgr, format($q$select public.warehouse_stock_in(%L, %L, 1, 'Delivery')::text$q$, w, pdel)),
    'P0001:This product is switched off or deleted, so no stock can be added to it.%', 'the single stock-in refuses a deleted product');
  perform pg_temp.expect(pg_temp.try_as(mgr, format($q$select public.warehouse_stock_ins(%L, %L, 'Delivery')::text$q$,
      wclosed, jsonb_build_array(jsonb_build_object('product_id', p1, 'quantity', 1)))),
    'P0001:This warehouse is closed or deleted, so it cannot take stock', 'a closed warehouse');

  -- ── 4. The form's own rules ─────────────────────────────────────────────
  foreach r in array array[
      jsonb_build_array(jsonb_build_object('product_id', p1, 'quantity', 0))::text || '|Every product needs a whole quantity greater than zero',
      jsonb_build_array(jsonb_build_object('product_id', p1, 'quantity', 1.5))::text || '|Every product needs a whole quantity greater than zero',
      jsonb_build_array(jsonb_build_object('product_id', p1, 'quantity', -2))::text || '|Every product needs a whole quantity greater than zero',
      jsonb_build_array(jsonb_build_object('product_id', p1, 'quantity', 1000000))::text || '|A quantity can be at most 999,999',
      jsonb_build_array(jsonb_build_object('product_id', p1, 'quantity', 1), jsonb_build_object('product_id', p1, 'quantity', 2))::text || '|The same product is listed more than once',
      jsonb_build_array(jsonb_build_object('quantity', 2))::text || '|Every line needs a product',
      '[]|Add at least one product with a quantity'] loop
    perform pg_temp.expect(pg_temp.try_as(inv, format($q$select public.warehouse_stock_ins(%L, %L, 'Delivery')::text$q$, w, split_part(r, '|', 1))),
      'P0001:' || split_part(r, '|', 2), 'the form''s rules: ' || r);
  end loop;
  perform pg_temp.expect(pg_temp.try_as(inv, format($q$select public.warehouse_stock_ins(%L, %L, '  ')::text$q$, w, j)),
    'P0001:A reason for stock-in is required', 'a reason is required');
  -- 999,999 is the most one line takes, as on the page.
  select current_qty into q2 from public.warehouse_inventory where warehouse_id = w and product_id = p2;
  perform pg_temp.expect(pg_temp.try_as(inv, format($q$select public.warehouse_stock_ins(%L, %L, 'Delivery')::text$q$,
      w, jsonb_build_array(jsonb_build_object('product_id', p2, 'quantity', 999999)))), 'ok:%', 'a line of 999,999');
  if (select current_qty from public.warehouse_inventory where warehouse_id = w and product_id = p2) <> q2 + 999999 then
    raise exception 'FAIL: a line of 999,999 was not added'; end if;

  -- ── 5. Who ──────────────────────────────────────────────────────────────
  perform pg_temp.expect(pg_temp.try_as(stf, format($q$select public.warehouse_stock_ins(%L, %L, 'Delivery')::text$q$, w, j)),
    'P0001:Not authorized to add warehouse stock', 'Staff cannot add warehouse stock');
  perform pg_temp.expect(pg_temp.try_as(adm, format($q$select public.warehouse_stock_ins(%L, %L, 'Delivery')::text$q$, w, j)),
    'P0001:Not authorized to add warehouse stock', 'an Admin looks but does not add');
  perform pg_temp.expect(pg_temp.try_as(gen_random_uuid(), format($q$select public.warehouse_stock_ins(%L, %L, 'Delivery')::text$q$, w, j)),
    '42501:%', 'a login with no profile');
  perform set_config('request.jwt.claims', '', true);
  perform set_config('energia.profile_privilege_change', 'on', true);
  update public.profiles set is_active = false where id = stf;
  perform set_config('energia.profile_privilege_change', '', true);
  perform pg_temp.expect(pg_temp.try_as(stf, format($q$select public.warehouse_stock_in(%L, %L, 1, 'Delivery')::text$q$, w, p1)),
    '42501:%', 'a deactivated login is refused by the single stock-in too');
  foreach r in array array[
      'select count(*)::text from public.warehouse_stock_in_batches',
      format('insert into public.warehouse_stock_in_batches (request_id, warehouse_id, reason, lines, movement_ids) values (gen_random_uuid(), %L, ''x'', ''[]'', ''{}'') returning 1', w)] loop
    perform pg_temp.expect(pg_temp.try_as(own, r), '42501:%', 'an Owner reached the replay record: ' || r);
  end loop;
  -- The server (no request) is not a login, but has no warehouse permission
  -- either, as before.
  perform pg_temp.expect(pg_temp.try_as(null, format($q$select public.warehouse_stock_ins(%L, %L, 'Delivery')::text$q$, w, j)),
    'P0001:Not authorized to add warehouse stock', 'the server as before');

  raise notice 'PASS: a multi-line Stock In is added once and whole; the same form again adds nothing and answers with its movements; a changed form, another person''s id, a deleted product, a closed warehouse, bad lines and roles without the warehouse permission are refused; the replay record is the server''s';
end $$;
rollback;
