-- Stock corrections are checked against the live stock (420).
--
-- The Owner's rules of 9 Oct 2026 (Q11) and the audit's STOCK-2, -3, -4, -5:
--   * a correction asks for a whole counted total of 0 or more, for a live
--     product at an open place the person may count, and differs from the
--     system (a count that matches is refused, by name in a multi-line form);
--   * one correction per product and place waits at a time;
--   * approving stops with "Stock changed since this count (was X, now Y)"
--     when a sale, delivery or transfer moved that stock after the count, and
--     the request stays pending so it can be rejected;
--   * rejecting needs a reason, kept with the request for the person who
--     asked (the Owner's later answer, 9 Oct 2026);
--   * a request from before 420 whose count matched is approved with no
--     movement (a movement of 0 is not allowed);
--   * a multi-line form is sent once: all or nothing, a retry of the same form
--     answers with what was sent, a changed form under the same id is refused;
--   * the Approvals card reads the live number (Owner and Manager only);
--   * a place cannot be switched off while a correction waits there (nor
--     while it holds stock); one switched off past that check is not
--     corrected, and a closed place takes no new correction;
--   * nobody writes stock directly any more; who reads store stock does not
--     change: Owners, Admins and Managers every store, everyone else the
--     stores they work at (Store Stock lists a Manager's own stores only:
--     the page does that, the Owner's later answer, 9 Oct 2026).
--
-- Needs migration 420. Disposable database only; everything is rolled back.
-- Fixture names carry "ADJX"; emails end in @sig.invalid; nothing real is read.
\set ON_ERROR_STOP on
begin;

-- Run p_sql as p_who (a profile id; null = the server, no request) and say
-- what happened: 'ok:<result>' or '<SQLSTATE>:<message>'.
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
  own uuid; mgr uuid; inv uuid; stf uuid; adm uuid; mgra uuid;
  sa uuid; sb uuid; sc uuid; w uuid; w2 uuid; wdel uuid; p1 uuid; p2 uuid; p3 uuid; p4 uuid; pdead uuid;
  r text; req uuid; req2 uuid; rid uuid := gen_random_uuid(); j jsonb; n int;
begin
  perform set_config('request.jwt.claims', '', true);
  insert into auth.users (id, email)
  select gen_random_uuid(), 'adjx-' || k || '@sig.invalid' from unnest(array['owner','manager','invman','staff','admin','managera']) k;
  select id into own from auth.users where email = 'adjx-owner@sig.invalid';
  select id into mgr from auth.users where email = 'adjx-manager@sig.invalid';
  select id into inv from auth.users where email = 'adjx-invman@sig.invalid';
  select id into stf from auth.users where email = 'adjx-staff@sig.invalid';
  select id into adm from auth.users where email = 'adjx-admin@sig.invalid';
  select id into mgra from auth.users where email = 'adjx-managera@sig.invalid';
  insert into public.profiles (id, full_name, email, role, is_active)
  select u.id, 'ADJX ' || x.role, u.email, x.role::public.user_role, true
    from auth.users u join (values (own, 'owner'), (mgr, 'manager'), (inv, 'inventory_manager'), (stf, 'staff'),
                                   (adm, 'admin'), (mgra, 'manager')) x(id, role) on x.id = u.id;
  insert into public.stores (name, code, country_code) values ('ADJX Store A', 'ADJX-A', 'SG') returning id into sa;
  insert into public.stores (name, code, country_code) values ('ADJX Store B', 'ADJX-B', 'SG') returning id into sb;
  insert into public.stores (name, code, country_code) values ('ADJX Store C', 'ADJX-C', 'SG') returning id into sc;
  insert into public.warehouses (name, code) values ('ADJX Warehouse', 'ADJX-W') returning id into w;
  insert into public.warehouses (name, code) values ('ADJX Warehouse 2', 'ADJX-W2') returning id into w2;
  insert into public.warehouses (name, code, deleted_at, is_active) values ('ADJX Old Warehouse', 'ADJX-WD', now(), false) returning id into wdel;
  -- mgra is a Manager who works at Store A only.
  insert into public.user_store_assignments (user_id, store_id) values (stf, sa), (mgr, sa), (mgr, sb), (stf, sc), (mgra, sa);
  insert into public.products (name, sku) values ('ADJX Mat', 'ADJX-1') returning id into p1;
  insert into public.products (name, sku) values ('ADJX Lamp', 'ADJX-2') returning id into p2;
  insert into public.products (name, sku) values ('ADJX Salt', 'ADJX-3') returning id into p3;
  insert into public.products (name, sku) values ('ADJX Cup', 'ADJX-4') returning id into p4;
  insert into public.products (name, sku, is_active) values ('ADJX Retired', 'ADJX-5', false) returning id into pdead;
  insert into public.store_inventory (store_id, product_id, current_qty) values (sa, p1, 5), (sa, p2, 4), (sa, p3, 5), (sa, p4, 2), (sb, p1, 3), (sc, p1, 3);
  insert into public.warehouse_inventory (warehouse_id, product_id, current_qty) values (w2, p1, 4);

  -- ── 1. The count is checked against the live stock on approval (Q11) ────
  r := pg_temp.try_as(stf, format($q$select public.request_inventory_adjustment('store', %L, %L, 3, 'Count')::text$q$, sa, p1));
  perform pg_temp.expect(r, 'ok:%', 'Staff ask for 5 -> 3 at their store');
  req := substr(r, 4)::uuid;
  -- A delivery of 10 arrives (the server writes it, as a transfer receipt would).
  update public.store_inventory set current_qty = 15 where store_id = sa and product_id = p1;
  perform pg_temp.expect(pg_temp.try_as(stf, format($q$select count(*)::text from public.pending_adjustments_live()$q$)),
    '42501:%', 'Staff cannot read the Approvals card''s live numbers');
  perform pg_temp.expect(pg_temp.try_as(mgr, format($q$select live_qty || '/' || product_live || '/' || place_open from public.pending_adjustments_live() where request_id = %L$q$, req)),
    'ok:15/true/true', 'the Approvals card shows the live number');
  perform pg_temp.expect(pg_temp.try_as(stf, format($q$select public.resolve_inventory_adjustment(%L, true, null)::text$q$, req)),
    'P0001:Only Owner or Manager can approve adjustments', 'Staff cannot approve');
  perform pg_temp.expect(pg_temp.try_as(mgr, format($q$select public.resolve_inventory_adjustment(%L, true, null)::text$q$, req)),
    'P0001:Stock changed since this count (was 5, now 15). Reject this request and count again.', 'approval over a later delivery stops');
  if (select current_qty from public.store_inventory where store_id = sa and product_id = p1) <> 15
     or (select status::text from public.approval_requests where id = req) <> 'pending' then
    raise exception 'FAIL: the refused approval changed stock or the request'; end if;
  -- Rejecting it needs a reason; the reason is kept for the person who asked.
  perform pg_temp.expect(pg_temp.try_as(mgr, format($q$select public.resolve_inventory_adjustment(%L, false, null)::text$q$, req)),
    'P0001:Give a reason for rejecting this correction. The person who asked will see it.', 'a rejection with no reason');
  perform pg_temp.expect(pg_temp.try_as(mgr, format($q$select public.resolve_inventory_adjustment(%L, false, '   ')::text$q$, req)),
    'P0001:Give a reason for rejecting this correction.%', 'a rejection with a blank reason');
  perform pg_temp.expect(pg_temp.try_as(mgr, format($q$select public.resolve_inventory_adjustment(%L, false, E'\n\t \r\n')::text$q$, req)),
    'P0001:Give a reason for rejecting this correction.%', 'a rejection of only new lines and tabs');
  if (select status::text from public.approval_requests where id = req) <> 'pending' then
    raise exception 'FAIL: a rejection with no reason changed the request'; end if;
  perform pg_temp.expect(pg_temp.try_as(mgr, format($q$select public.resolve_inventory_adjustment(%L, false, E'\t Recount \n')::text$q$, req)),
    'ok:%"rejected"%', 'the stale request can be rejected');
  if (select response_note || '|' || rejection_reason || '|' || approved_by from public.approval_requests where id = req)
     is distinct from 'Recount|Recount|' || mgr then
    raise exception 'FAIL: the rejection''s reason is not kept as said'; end if;
  perform pg_temp.expect(pg_temp.try_as(stf, format($q$select response_note from public.approval_requests where id = %L$q$, req)),
    'ok:Recount', 'the person who asked reads the reason');

  -- ── 2. A correction that still matches is applied, with its movement ────
  r := pg_temp.try_as(stf, format($q$select public.request_inventory_adjustment('store', %L, %L, 12, 'Count')::text$q$, sa, p1));
  perform pg_temp.expect(r, 'ok:%', 'Staff ask for 15 -> 12');
  req := substr(r, 4)::uuid;
  perform pg_temp.expect(pg_temp.try_as(own, format($q$select public.resolve_inventory_adjustment(%L, true, 'Checked')::text$q$, req)),
    'ok:%"moved": 3%', 'an Owner approves 15 -> 12');
  if (select current_qty from public.store_inventory where store_id = sa and product_id = p1) <> 12
     or not exists (select 1 from public.stock_movements m where m.product_id = p1 and m.from_store_id = sa
                     and m.movement_type = 'inventory_adjustment' and m.quantity = 3) then
    raise exception 'FAIL: the approved correction did not set 12 with a movement of 3 out'; end if;

  -- ── 3. What a request may not be (STOCK-2, STOCK-4) ─────────────────────
  perform pg_temp.expect(pg_temp.try_as(stf, format($q$select public.request_inventory_adjustment('store', %L, %L, 12, 'Count')::text$q$, sa, p1)),
    'P0001:The count matches the system (12), so nothing needs adjusting', 'a matching count is refused');
  perform pg_temp.expect(pg_temp.try_as(stf, format($q$select public.request_inventory_adjustment('store', %L, %L, -1, 'Count')::text$q$, sa, p1)),
    'P0001:Adjusted quantity cannot be negative', 'a negative total is refused');
  perform pg_temp.expect(pg_temp.try_as(stf, format($q$select public.request_inventory_adjustment('store', %L, %L, null, 'Count')::text$q$, sa, p1)),
    'P0001:Enter the counted total', 'an empty total is refused');
  perform pg_temp.expect(pg_temp.try_as(stf, format($q$select public.request_inventory_adjustment('store', %L, %L, 1, 'Count')::text$q$, sb, p1)),
    'P0001:You can only adjust your assigned store', 'Staff cannot count another store');
  perform pg_temp.expect(pg_temp.try_as(stf, format($q$select public.request_inventory_adjustment('warehouse', %L, %L, 1, 'Count')::text$q$, w, p1)),
    'P0001:Not authorized to adjust warehouse stock', 'Staff cannot count a warehouse');
  perform pg_temp.expect(pg_temp.try_as(stf, format($q$select public.request_inventory_adjustment('store', %L, %L, 1, 'Count')::text$q$, sa, pdead)),
    'P0001:This product is switched off or deleted.%', 'a switched-off product cannot be corrected');
  r := pg_temp.try_as(stf, format($q$select public.request_inventory_adjustment('store', %L, %L, 1, 'Count')::text$q$, sa, p2));
  perform pg_temp.expect(r, 'ok:%', 'Staff ask for 4 -> 1');
  req2 := substr(r, 4)::uuid;
  perform pg_temp.expect(pg_temp.try_as(mgr, format($q$select public.request_inventory_adjustment('store', %L, %L, 2, 'Count')::text$q$, sa, p2)),
    'P0001:ADJX Lamp at ADJX Store A already has a correction waiting for approval.%', 'a second pending correction is refused');

  -- ── 4. A request from before 420 whose count matched closes cleanly ─────
  insert into public.approval_requests (request_type, status, requested_by, related_record_id, reason, payload)
  values ('adjustment', 'pending', stf, p4, 'Same',
          jsonb_build_object('location_type', 'store', 'location_id', sa, 'product_id', p4,
                             'current_qty', 2, 'new_qty', 2, 'difference', 0))
  returning id into req;
  select count(*) into n from public.stock_movements where product_id = p4;
  perform pg_temp.expect(pg_temp.try_as(mgr, format($q$select public.resolve_inventory_adjustment(%L, true, null)::text$q$, req)),
    'ok:%"moved": 0%', 'a legacy zero-difference request is approved');
  if (select count(*) from public.stock_movements where product_id = p4) <> n
     or (select current_qty from public.store_inventory where store_id = sa and product_id = p4) <> 2
     or (select status::text from public.approval_requests where id = req) <> 'approved' then
    raise exception 'FAIL: the zero-difference approval moved stock or stayed pending'; end if;
  -- A legacy request for a product switched off since: the approval stops.
  insert into public.approval_requests (request_type, status, requested_by, related_record_id, reason, payload)
  values ('adjustment', 'pending', stf, pdead, 'Old',
          jsonb_build_object('location_type', 'store', 'location_id', sa, 'product_id', pdead,
                             'current_qty', 0, 'new_qty', 1, 'difference', 1))
  returning id into req;
  perform pg_temp.expect(pg_temp.try_as(mgr, format($q$select public.resolve_inventory_adjustment(%L, true, null)::text$q$, req)),
    'P0001:This product was switched off or deleted after the count. Reject this request.', 'a switched-off product is not corrected');
  perform pg_temp.expect(pg_temp.try_as(mgr, format($q$select live_qty || '/' || product_live || '/' || place_open from public.pending_adjustments_live() where request_id = %L$q$, req)),
    'ok:0/false/true', 'the Approvals card says the product is no longer live');

  -- ── 5. A warehouse count with no stock row yet ──────────────────────────
  r := pg_temp.try_as(inv, format($q$select public.request_inventory_adjustment('warehouse', %L, %L, 7, 'Found')::text$q$, w, p3));
  perform pg_temp.expect(r, 'ok:%', 'an Inventory Manager asks for 0 -> 7 at the warehouse');
  perform pg_temp.expect(pg_temp.try_as(mgr, format($q$select public.resolve_inventory_adjustment(%L, true, null)::text$q$, substr(r, 4)::uuid)),
    'ok:%"moved": 7%', 'a Manager approves 0 -> 7');
  if (select current_qty from public.warehouse_inventory where warehouse_id = w and product_id = p3) <> 7 then
    raise exception 'FAIL: the warehouse correction did not set 7'; end if;

  -- ── 6. Several lines in one go (STOCK-5) ────────────────────────────────
  -- p1 is 12 (the count matches), p3 is 5 (counted 0).
  j := jsonb_build_array(jsonb_build_object('product_id', p1, 'new_qty', 12), jsonb_build_object('product_id', p3, 'new_qty', 0));
  r := pg_temp.try_as(stf, format($q$select public.request_inventory_adjustments('store', %L, %L, 'Month-end count', 'C-1', %L)::text$q$, sa, j, rid));
  perform pg_temp.expect(r, 'ok:%', 'a two-line count is sent');
  if jsonb_array_length(substr(r, 4)::jsonb -> 'requests') <> 1
     or substr(r, 4)::jsonb -> 'requests' -> 0 ->> 'product_id' <> p3::text
     or substr(r, 4)::jsonb -> 'unchanged' -> 0 ->> 'product_id' <> p1::text then
    raise exception 'FAIL: the matching line was not left out and named (%)', r; end if;
  req := (substr(r, 4)::jsonb -> 'requests' -> 0 ->> 'request_id')::uuid;
  perform pg_temp.expect(pg_temp.try_as(stf, format($q$select public.request_inventory_adjustments('store', %L, %L, 'Month-end count', 'C-1', %L)::text$q$, sa, j, rid)),
    format('ok:%%"replayed": true%%%s%%', req), 'the same form sent again answers with the same request');
  if (select count(*) from public.approval_requests where request_type = 'adjustment' and payload ->> 'request_id' = rid::text) <> 1 then
    raise exception 'FAIL: the retry made a second request'; end if;
  perform pg_temp.expect(pg_temp.try_as(stf, format($q$select public.request_inventory_adjustments('store', %L, %L, 'Month-end count', 'C-2', %L)::text$q$, sa, j, rid)),
    'P0001:This form was already sent, and has been changed since%', 'a changed form under the same id is refused');
  perform pg_temp.expect(pg_temp.try_as(mgr, format($q$select public.request_inventory_adjustments('store', %L, %L, 'Month-end count', 'C-1', %L)::text$q$, sa, j, rid)),
    'P0001:This form was already sent, and has been changed since%', 'another person''s form id is refused');
  -- Every line matches: nothing is sent, and the products are named.
  perform pg_temp.expect(pg_temp.try_as(stf, format($q$select public.request_inventory_adjustments('store', %L, %L, 'Count', null, %L)::text$q$,
      sa, jsonb_build_array(jsonb_build_object('product_id', p1, 'new_qty', 12)), gen_random_uuid())),
    'P0001:The count matches the system for every product (ADJX Mat (12)), so nothing needs adjusting', 'an all-matching form sends nothing');
  -- One bad line sends none (p4 counted 5, pdead is switched off).
  select count(*) into n from public.approval_requests where request_type = 'adjustment';
  perform pg_temp.expect(pg_temp.try_as(stf, format($q$select public.request_inventory_adjustments('store', %L, %L, 'Count', null, %L)::text$q$,
      sa, jsonb_build_array(jsonb_build_object('product_id', p4, 'new_qty', 5), jsonb_build_object('product_id', pdead, 'new_qty', 1)), gen_random_uuid())),
    'P0001:ADJX Retired: This product is switched off or deleted.%', 'a switched-off line is named');
  if (select count(*) from public.approval_requests where request_type = 'adjustment') <> n then
    raise exception 'FAIL: a refused form still sent a request'; end if;
  perform pg_temp.expect(pg_temp.try_as(stf, format($q$select public.request_inventory_adjustments('store', %L, %L, 'Count', null, null)::text$q$,
      sa, jsonb_build_array(jsonb_build_object('product_id', p4, 'new_qty', 2.5)))),
    'P0001:Every product needs a whole counted total of 0 or more', 'a decimal total is refused');
  perform pg_temp.expect(pg_temp.try_as(stf, format($q$select public.request_inventory_adjustments('store', %L, %L, 'Count', null, null)::text$q$,
      sa, jsonb_build_array(jsonb_build_object('product_id', p4, 'new_qty', 1), jsonb_build_object('product_id', p4, 'new_qty', 3)))),
    'P0001:The same product is listed more than once', 'a product twice is refused');
  perform pg_temp.expect(pg_temp.try_as(stf, format($q$select public.request_inventory_adjustments('store', %L, %L, 'Count', null, null)::text$q$,
      sb, jsonb_build_array(jsonb_build_object('product_id', p4, 'new_qty', 2)))),
    'P0001:You can only adjust your assigned store', 'another store''s stock is not answered');
  -- Approving the counted 0 sets 0 (the page asked for a second confirmation).
  perform pg_temp.expect(pg_temp.try_as(mgr, format($q$select public.resolve_inventory_adjustment(%L, true, null)::text$q$, req)),
    'ok:%"new_qty": 0%', 'a counted 0 is applied');

  -- ── 7. Nobody writes stock directly (STOCK-12b) ─────────────────────────
  foreach r in array array[
      format('update public.store_inventory set current_qty = 99 where store_id = %L returning 1', sa),
      format('insert into public.warehouse_inventory (warehouse_id, product_id, current_qty) values (%L, %L, 1) returning 1', w, p1),
      format('insert into public.stock_movements (product_id, movement_type, to_store_id, quantity) values (%L, ''inventory_adjustment'', %L, 1) returning 1', p1, sa),
      format('delete from public.store_inventory where store_id = %L returning 1', sa)] loop
    perform pg_temp.expect(pg_temp.try_as(own, r), '42501:%', 'an Owner wrote stock directly: ' || r);
    perform pg_temp.expect(pg_temp.try_as(mgr, r), '42501:%', 'a Manager wrote stock directly: ' || r);
    perform pg_temp.expect(pg_temp.try_as(inv, r), '42501:%', 'an Inventory Manager wrote stock directly: ' || r);
  end loop;
  -- Reading stays as it was.
  perform pg_temp.expect(pg_temp.try_as(stf, format($q$select count(*)::text from public.store_inventory where store_id = %L$q$, sa)),
    'ok:4', 'Staff still read their store''s stock');
  perform pg_temp.expect(pg_temp.try_as(stf, format($q$select count(*)::text from public.store_inventory where store_id = %L$q$, sb)),
    'ok:0', 'Staff still do not read another store''s stock');
  -- "write store inventory" (FOR ALL) also gave Owners, Admins and Managers
  -- every store's stock to read. Its read part stays ("managers read store
  -- inventory"): Reports, Transfers returns, Invoices, the Dashboard and other
  -- pages read other stores' stock for a Manager. Store Stock lists a
  -- Manager's own stores only; the page does that.
  perform pg_temp.expect(pg_temp.try_as(mgra, format($q$select count(*)::text from public.store_inventory where store_id = %L$q$, sb)),
    'ok:1', 'a Manager still reads a store they do not work at');
  perform pg_temp.expect(pg_temp.try_as(mgra, format($q$select count(*)::text from public.store_inventory where store_id = %L and current_qty > 0$q$, sb)),
    'ok:1', 'a Manager still reads a store''s stock to return from it (Transfers)');
  perform pg_temp.expect(pg_temp.try_as(mgra, format($q$select count(*)::text from public.store_inventory where store_id = %L$q$, sa)),
    'ok:4', 'a Manager reads the store they work at');
  perform pg_temp.expect(pg_temp.try_as(mgr, format($q$select count(*)::text from public.store_inventory where store_id = %L$q$, sb)),
    'ok:1', 'a Manager on two stores reads both');
  perform pg_temp.expect(pg_temp.try_as(adm, format($q$select count(*)::text from public.store_inventory where store_id = %L$q$, sb)),
    'ok:1', 'an Admin still reads every store');
  perform pg_temp.expect(pg_temp.try_as(own, format($q$select count(*)::text from public.store_inventory where store_id = %L$q$, sb)),
    'ok:1', 'an Owner still reads every store');
  perform pg_temp.expect(pg_temp.try_as(inv, format($q$select count(*)::text from public.store_inventory where store_id = %L$q$, sb)),
    'ok:0', 'an Inventory Manager still reads only the stores they work at');
  -- Counting is the stores they work at, for a Manager too (the page offers
  -- only those).
  perform pg_temp.expect(pg_temp.try_as(mgra, format($q$select public.request_inventory_adjustment('store', %L, %L, 1, 'Count')::text$q$, sb, p1)),
    'P0001:You can only adjust your assigned store', 'a Manager counts only the stores they work at');

  -- ── 8. A place closed after the count, or before it ─────────────────────
  r := pg_temp.try_as(stf, format($q$select public.request_inventory_adjustment('store', %L, %L, 1, 'Count')::text$q$, sc, p1));
  perform pg_temp.expect(r, 'ok:%', 'Staff ask for 3 -> 1 at Store C');
  req := substr(r, 4)::uuid;
  -- Store C cannot be switched off while it holds stock and the count waits
  -- (the Owner, 9 Oct 2026).
  perform pg_temp.expect(pg_temp.try_as(mgr, format($q$update public.stores set is_active = false where id = %L returning 1$q$, sc)),
    'P0001:ADJX Store C cannot be switched off yet. Still open: stock of 1 product (3 units); 1 stock correction waiting for approval.',
    'a store with stock and a waiting count is not switched off');
  -- Switched off past that check (the check turned off, as only the database
  -- owner could), the approval still stops.
  alter table public.stores disable trigger stores_retire_check;
  update public.stores set is_active = false where id = sc;
  alter table public.stores enable trigger stores_retire_check;
  perform pg_temp.expect(pg_temp.try_as(mgr, format($q$select live_qty || '/' || product_live || '/' || place_open from public.pending_adjustments_live() where request_id = %L$q$, req)),
    'ok:3/true/false', 'the Approvals card says the place is closed');
  perform pg_temp.expect(pg_temp.try_as(mgr, format($q$select public.resolve_inventory_adjustment(%L, true, null)::text$q$, req)),
    'P0001:This store was closed or deleted after the count. Reject this request.', 'a store closed after the count is not corrected');
  if (select current_qty from public.store_inventory where store_id = sc and product_id = p1) <> 3
     or (select status::text from public.approval_requests where id = req) <> 'pending' then
    raise exception 'FAIL: the refused approval at a closed store changed stock or the request'; end if;
  perform pg_temp.expect(pg_temp.try_as(stf, format($q$select public.request_inventory_adjustment('store', %L, %L, 1, 'Count')::text$q$, sc, p2)),
    'P0001:This store is closed or deleted, so its stock cannot be corrected', 'a closed store takes no new correction');
  r := pg_temp.try_as(inv, format($q$select public.request_inventory_adjustment('warehouse', %L, %L, 1, 'Count')::text$q$, w2, p1));
  perform pg_temp.expect(r, 'ok:%', 'an Inventory Manager asks for 4 -> 1 at Warehouse 2');
  req := substr(r, 4)::uuid;
  perform pg_temp.expect(pg_temp.try_as(mgr, format($q$update public.warehouses set is_active = false where id = %L returning 1$q$, w2)),
    'P0001:ADJX Warehouse 2 cannot be switched off yet. Still open: stock of 1 product (4 units); 1 stock correction waiting for approval.',
    'a warehouse with stock and a waiting count is not switched off');
  alter table public.warehouses disable trigger warehouses_retire_check;
  update public.warehouses set is_active = false where id = w2;
  alter table public.warehouses enable trigger warehouses_retire_check;
  perform pg_temp.expect(pg_temp.try_as(mgr, format($q$select public.resolve_inventory_adjustment(%L, true, null)::text$q$, req)),
    'P0001:This warehouse was closed or deleted after the count. Reject this request.', 'a warehouse closed after the count is not corrected');
  if (select current_qty from public.warehouse_inventory where warehouse_id = w2 and product_id = p1) <> 4 then
    raise exception 'FAIL: the refused approval at a closed warehouse changed stock'; end if;
  perform pg_temp.expect(pg_temp.try_as(inv, format($q$select public.request_inventory_adjustment('warehouse', %L, %L, 1, 'Count')::text$q$, wdel, p1)),
    'P0001:This warehouse is closed or deleted, so its stock cannot be corrected', 'a deleted warehouse takes no correction');
  perform pg_temp.expect(pg_temp.try_as(mgr, format($q$select public.resolve_inventory_adjustment(%L, false, 'Closed')::text$q$, req)),
    'ok:%"rejected"%', 'the request at the closed place can be rejected');

  raise notice 'PASS: approval stops when stock moved after the count, and applies a count that still matches; matching, negative, empty, decimal and duplicate counts, other places and switched-off products are refused; one correction per product and place; a legacy zero-difference request closes with no movement; a rejection needs a reason, kept for the person who asked; a multi-line count is sent once, all or nothing, matching lines named; the Approvals card reads the live number; nobody writes stock directly; Owners, Admins and Managers still read every store, Staff and Inventory Managers the stores they work at; a place with stock and a waiting count is not switched off, one switched off past that check is not corrected, and a closed place takes no correction';
end $$;
rollback;
