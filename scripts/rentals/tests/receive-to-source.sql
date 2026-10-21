-- 417 (audit finding INVOICES-AFTER-7): a rental still with the customer when
-- its invoice is cancelled goes back where it came from.
--
-- Before 417 receive_returned_rental wrote warehouse stock only, so a rental
-- released from a store (production: RNT-2026-0004 and RNT-2026-0006) could
-- only be received into a warehouse, and nothing on screen could reach it
-- once the invoice was cancelled. Now, as Return on the Special page puts a
-- rental back (rental_put_back_stock):
--   * good, with no warehouse named: back where it came from, the store it
--     was released from (store stock and a movement into the store) or its
--     warehouse; another active warehouse when one is named;
--   * damaged or lost: resolved, never back on sale;
--   * once only, by any route; an Owner or Manager only; and only a rental
--     cancelled with its invoice while it was out (a running rental comes
--     back with Return on the Special page);
--   * invoice_rentals_awaiting_return names each one's invoice line and where
--     it came from, so a refund receives only the rentals on its own lines.
--
-- Needs 417. Disposable database only; everything is rolled back. Every name,
-- phone and number here is invented (@sig.invalid).
\set ON_ERROR_STOP on
begin;

create temp table t417r(k text primary key, id uuid);
create function pg_temp.t417r_id(p_k text) returns uuid language sql as $f$ select id from t417r where k = p_k $f$;
create function pg_temp.t417r_as(p_k text) returns void language plpgsql as $f$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', pg_temp.t417r_id(p_k), 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', pg_temp.t417r_id(p_k)::text, true);
end $f$;
create function pg_temp.t417r_refused(p_label text, p_sql text, p_like text) returns void language plpgsql as $f$
begin
  begin
    execute p_sql;
  exception when others then
    if sqlerrm not like '%' || p_like || '%' then
      raise exception 'FAIL %: refused, but with "%" (expected "%")', p_label, sqlerrm, p_like; end if;
    return;
  end;
  raise exception 'FAIL %: was not refused', p_label;
end $f$;
-- Stock of the fixture machine at the store it is released from, and at each warehouse.
create function pg_temp.t417r_store() returns int language sql as $f$
  select coalesce((select current_qty from store_inventory where store_id = pg_temp.t417r_id('store_b') and product_id = pg_temp.t417r_id('product')), 0) $f$;
create function pg_temp.t417r_wh(p_k text) returns int language sql as $f$
  select coalesce((select current_qty from warehouse_inventory where warehouse_id = pg_temp.t417r_id(p_k) and product_id = pg_temp.t417r_id('product')), 0) $f$;

do $$
declare o uuid := gen_random_uuid(); m uuid := gen_random_uuid(); s uuid := gen_random_uuid();
  sa uuid; sb uuid; wh uuid; wh2 uuid; whx uuid; c uuid; pm uuid; p uuid; p2 uuid; sp uuid;
begin
  insert into auth.users(id, email) values (o, 't417r-owner@sig.invalid'), (m, 't417r-manager@sig.invalid'), (s, 't417r-staff@sig.invalid');
  insert into profiles(id, full_name, email, role, is_active) values
    (o, 'T417R Owner', 't417r-owner@sig.invalid', 'owner', true),
    (m, 'T417R Manager', 't417r-manager@sig.invalid', 'manager', true),
    (s, 'T417R Staff', 't417r-staff@sig.invalid', 'staff', true);
  insert into t417r values ('owner', o), ('manager', m), ('staff', s);
  perform pg_temp.t417r_as('owner');
  insert into stores(name, code, country_code) values ('T417R Store A', 'T417RA', 'SG') returning id into sa;
  insert into stores(name, code, country_code) values ('T417R Store B', 'T417RB', 'SG') returning id into sb;
  insert into warehouses(name, code) values ('T417R Warehouse', 'T417RW') returning id into wh;
  insert into warehouses(name, code) values ('T417R Overflow', 'T417RO') returning id into wh2;
  insert into warehouses(name, code, is_active) values ('T417R Closed', 'T417RX', false) returning id into whx;
  insert into user_store_assignments(user_id, store_id) values (m, sa), (s, sa);
  insert into customers(full_name, phone) values ('T417R Buyer', '+61491571266') returning id into c;
  insert into payment_methods(name, is_active) values ('T417R Cash', true) returning id into pm;
  insert into products(name, sku, product_type) values ('T417R Machine', 'T417R-M', 'own') returning id into p;
  insert into products(name, sku, product_type) values ('T417R Strap', 'T417R-S', 'own') returning id into p2;
  insert into warehouse_inventory(warehouse_id, product_id, current_qty) values (wh, p, 10);
  insert into store_inventory(store_id, product_id, current_qty) values (sb, p, 4), (sa, p2, 10);
  perform set_product_prices(sa, p2, 20, 20, 'available');
  sp := upsert_special_product_from_product(null, p, 300, 30, null, null, null, 0);
  insert into t417r values ('store_a', sa), ('store_b', sb), ('warehouse', wh), ('overflow', wh2), ('closed', whx),
    ('customer', c), ('cash', pm), ('product', p), ('strap', p2), ('special', sp);
end $$;

-- A paid invoice of one two-day rental (and a strap, when asked), the rental
-- released from Store B or the warehouse; returns the rental.
create function pg_temp.t417r_out(p_where text, p_with_strap boolean default false) returns uuid language plpgsql as $f$
declare v_inv uuid; v_r uuid; v_items jsonb;
begin
  perform pg_temp.t417r_as('owner');
  v_items := jsonb_build_array(jsonb_build_object('kind', 'rental', 'special_product_id', pg_temp.t417r_id('special'),
      'quantity', 1, 'rental_rate_type', 'day', 'rental_periods', 2));
  if p_with_strap then
    v_items := v_items || jsonb_build_array(jsonb_build_object('kind', 'product', 'product_id', pg_temp.t417r_id('strap'), 'quantity', 1));
  end if;
  v_inv := create_invoice(pg_temp.t417r_id('store_a'), pg_temp.t417r_id('customer'), null, v_items);
  perform pay_invoice(v_inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.t417r_id('cash'),
    'amount', invoice_charge_total(v_inv))));
  select id into v_r from rentals where invoice_id = v_inv;
  perform fulfil_special_doc('rental', v_r, pg_temp.t417r_id(case when p_where = 'store' then 'store_b' else 'warehouse' end), p_where);
  return v_r;
end $f$;
-- Its invoice cancelled while the item is still with the customer.
create function pg_temp.t417r_cancel(p_rental uuid) returns void language plpgsql as $f$
begin
  perform pg_temp.t417r_as('owner');
  perform cancel_invoice_recorded((select invoice_id from rentals where id = p_rental), 'Customer cancelled', gen_random_uuid());
  if not rental_awaiting_return(p_rental) then raise exception 'Fixture: the cancelled rental is not waiting to come back'; end if;
end $f$;
create function pg_temp.t417r_moves(p_rental uuid) returns int language sql as $f$
  select count(*)::int from stock_movements
   where movement_type::text = 'invoice_cancel_return' and product_id = pg_temp.t417r_id('product')
     and notes like '%' || (select rental_no from rentals where id = p_rental) || '%' $f$;

-- ===== 1. From a store: back into that store =====
do $$
declare r uuid; st0 int; wh0 int; aw jsonb; x jsonb;
begin
  r := pg_temp.t417r_out('store');
  st0 := pg_temp.t417r_store(); wh0 := pg_temp.t417r_wh('warehouse');
  perform pg_temp.t417r_cancel(r);
  if pg_temp.t417r_store() <> st0 or pg_temp.t417r_moves(r) <> 0 then
    raise exception 'FAIL 1: cancelling put the item back before it came back'; end if;
  perform pg_temp.t417r_as('manager');
  aw := invoice_rentals_awaiting_return((select invoice_id from rentals where id = r));
  -- "is distinct from", so a key that is missing fails the check too.
  if jsonb_array_length(aw) <> 1
     or aw->0->>'invoice_item_id' is distinct from (select invoice_item_id::text from rentals where id = r)
     or aw->0->>'source_type' is distinct from 'store' or aw->0->>'source_name' is distinct from 'T417R Store B'
     or aw->0->>'default_warehouse_id' is not null then
    raise exception 'FAIL 1: the invoice does not say what is out, on which line and from where: %', aw; end if;
  perform pg_temp.t417r_as('staff');
  perform pg_temp.t417r_refused('1 staff', format('select receive_returned_rental(%L, null, ''good'', ''Back'', null)', r),
    'Only an Owner or Manager can receive a returned rental');
  perform pg_temp.t417r_as('manager');
  perform pg_temp.t417r_refused('1 no note', format('select receive_returned_rental(%L, null, ''good'', '' '', null)', r), 'A note is required');
  x := receive_returned_rental(r, null, 'good', 'Collected from the customer', gen_random_uuid());
  if pg_temp.t417r_store() <> st0 + 1 or pg_temp.t417r_wh('warehouse') <> wh0 then
    raise exception 'FAIL 1: a store release did not go back to its store (store % -> %, warehouse % -> %)',
      st0, pg_temp.t417r_store(), wh0, pg_temp.t417r_wh('warehouse'); end if;
  if pg_temp.t417r_moves(r) <> 1 or not exists (select 1 from stock_movements where movement_type::text = 'invoice_cancel_return'
        and to_store_id = pg_temp.t417r_id('store_b') and product_id = pg_temp.t417r_id('product') and quantity = 1) then
    raise exception 'FAIL 1: no single stock movement into the store'; end if;
  if (x->>'returned_quantity')::int <> 1 or x->>'location_type' <> 'store' or x->>'location_name' <> 'T417R Store B'
     or not (x->>'made_available')::boolean then raise exception 'FAIL 1: it answered %', x; end if;
  if (select (status::text, stock_returned, return_condition::text) from rentals where id = r)
       is distinct from ('cancelled'::text, true, 'good'::text) then
    raise exception 'FAIL 1: the rental reads %', (select to_jsonb(q) - 'notes' from rentals q where id = r); end if;
  if not exists (select 1 from audit_logs where record_id = r and action = 'rental_received'
                  and new_data->>'location_type' = 'store' and (new_data->>'returned_quantity')::int = 1) then
    raise exception 'FAIL 1: not audited'; end if;
  -- Once only, by any route.
  if not (receive_returned_rental(r, null, 'good', 'Again', null)->>'already_returned')::boolean
     or pg_temp.t417r_store() <> st0 + 1 or pg_temp.t417r_moves(r) <> 1 then
    raise exception 'FAIL 1: received twice'; end if;
  if rental_awaiting_return(r) or jsonb_array_length(invoice_rentals_awaiting_return((select invoice_id from rentals where id = r))) <> 0 then
    raise exception 'FAIL 1: a received rental still reads as out'; end if;
  raise notice 'PASS 1: a rental released from a store and cancelled while out goes back into that store once, with one movement, audited; Owner or Manager only, with a note; the invoice names its line and where it came from';
end $$;

-- ===== 2. From the warehouse, to another warehouse, damaged, lost =====
do $$
declare r uuid; st0 int; wh0 int; ov0 int; aw jsonb;
begin
  -- From the warehouse: back into it.
  r := pg_temp.t417r_out('warehouse');
  perform pg_temp.t417r_cancel(r);
  wh0 := pg_temp.t417r_wh('warehouse'); st0 := pg_temp.t417r_store();
  perform pg_temp.t417r_as('owner');
  aw := invoice_rentals_awaiting_return((select invoice_id from rentals where id = r));
  if jsonb_array_length(aw) <> 1
     or aw->0->>'invoice_item_id' is distinct from (select invoice_item_id::text from rentals where id = r)
     or aw->0->>'source_type' is distinct from 'warehouse' or aw->0->>'source_name' is distinct from 'T417R Warehouse'
     or aw->0->>'default_warehouse_id' is distinct from pg_temp.t417r_id('warehouse')::text then
    raise exception 'FAIL 2a: the invoice does not say what is out, on which line and from which warehouse: %', aw; end if;
  perform receive_returned_rental(r, null, 'good', 'Back', null);
  if pg_temp.t417r_wh('warehouse') <> wh0 + 1 or pg_temp.t417r_store() <> st0 or pg_temp.t417r_moves(r) <> 1 then
    raise exception 'FAIL 2a: a warehouse release did not go back to its warehouse once'; end if;

  -- From a store, but the person sends it to another warehouse.
  r := pg_temp.t417r_out('store');
  perform pg_temp.t417r_cancel(r);
  st0 := pg_temp.t417r_store(); ov0 := pg_temp.t417r_wh('overflow');
  perform pg_temp.t417r_refused('2b closed warehouse', format('select receive_returned_rental(%L, %L, ''good'', ''Back'', null)',
    r, pg_temp.t417r_id('closed')), 'Choose an active warehouse to receive this item');
  if (receive_returned_rental(r, pg_temp.t417r_id('overflow'), 'good', 'Sent to overflow', null)->>'location_type') <> 'warehouse'
     or pg_temp.t417r_wh('overflow') <> ov0 + 1 or pg_temp.t417r_store() <> st0 then
    raise exception 'FAIL 2b: a chosen warehouse was not used'; end if;

  -- Damaged and lost: resolved, never back on sale.
  r := pg_temp.t417r_out('store');
  perform pg_temp.t417r_cancel(r);
  st0 := pg_temp.t417r_store(); wh0 := pg_temp.t417r_wh('warehouse');
  if (receive_returned_rental(r, null, 'damaged', 'Came back cracked', null)->>'made_available')::boolean
     or pg_temp.t417r_store() <> st0 or pg_temp.t417r_wh('warehouse') <> wh0 or pg_temp.t417r_moves(r) <> 0
     or not (select stock_returned from rentals where id = r) then
    raise exception 'FAIL 2c: a damaged rental moved stock or stayed out'; end if;
  r := pg_temp.t417r_out('warehouse');
  perform pg_temp.t417r_cancel(r);
  wh0 := pg_temp.t417r_wh('warehouse');
  perform pg_temp.t417r_refused('2d unknown condition', format('select receive_returned_rental(%L, null, ''melted'', ''x'', null)', r),
    'Record the condition as good, damaged or lost');
  perform receive_returned_rental(r, null, 'lost', 'Never came back', null);
  if pg_temp.t417r_wh('warehouse') <> wh0 or (select return_condition::text from rentals where id = r) <> 'lost' then
    raise exception 'FAIL 2d: a lost rental moved stock'; end if;
  raise notice 'PASS 2: from the warehouse back into it; another active warehouse when named (a closed one refused); damaged and lost resolved with no stock moved';
end $$;

-- ===== 3. Only a rental cancelled while out; a refund of another line leaves it =====
do $$
declare r uuid; inv uuid; strap_line uuid;
begin
  -- Still running: it comes back with Return on the Special page.
  r := pg_temp.t417r_out('store', true);
  inv := (select invoice_id from rentals where id = r);
  perform pg_temp.t417r_as('owner');
  perform pg_temp.t417r_refused('3 running', format('select receive_returned_rental(%L, null, ''good'', ''Back'', null)', r),
    'is not waiting to come back from a cancelled invoice');
  -- A refund of the strap line alone leaves the rental running and nothing to receive.
  select id into strap_line from invoice_items where invoice_id = inv and line_kind = 'product';
  perform refund_invoice_recorded(inv, jsonb_build_array(jsonb_build_object('invoice_item_id', strap_line, 'amount', 20)),
    jsonb_build_array(jsonb_build_object('payment_id', (select id from invoice_payments where invoice_id = inv limit 1), 'amount', 20)),
    jsonb_build_array(jsonb_build_object('movement_id', (select id from stock_movements where invoice_id = inv and movement_type::text = 'store_sale' limit 1),
      'sellable_quantity', 1, 'damaged_quantity', 0, 'not_returned_quantity', 0)), 'Strap back', gen_random_uuid());
  if (select status::text from rentals where id = r) <> 'active' or jsonb_array_length(invoice_rentals_awaiting_return(inv)) <> 0 then
    raise exception 'FAIL 3: a refund of another line touched the rental'; end if;
  raise notice 'PASS 3: a running rental is not received here (Return on the Special page does it); a refund of another line leaves it running with nothing to receive';
end $$;

rollback;
