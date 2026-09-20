-- Warehouse stock needs the warehouse permission (345).
--
-- record_stock_use checked store access for a store write-off and nothing at
-- all for a warehouse one, while running as a definer that bypasses the
-- table's own write policy. Any signed-in member of staff could write off any
-- quantity from any warehouse.
--
-- This drives the real function as a shop-floor staff member and as a manager.
--
-- Disposable database only; everything is rolled back.
\set ON_ERROR_STOP on
begin;
do $$
declare
  mgr uuid := gen_random_uuid();
  staff uuid := gen_random_uuid();
  st uuid; wh uuid; prod uuid; v_qty int; v_msg text;
begin
  insert into auth.users(id,email) values (mgr,'ws-mgr@tests.invalid'), (staff,'ws-staff@tests.invalid');
  insert into profiles(id,full_name,email,role,is_active) values
    (mgr,'WS Manager','ws-mgr@tests.invalid','manager',true),
    (staff,'WS Staff','ws-staff@tests.invalid','staff',true);
  perform set_config('request.jwt.claim.sub', mgr::text, true);

  insert into stores(name,code,country_code) values ('WS Store','WSS','SG') returning id into st;
  insert into warehouses(name,code) values ('WS Warehouse','WSW') returning id into wh;
  insert into products(name,sku) values ('WS Item','WS-1') returning id into prod;
  insert into warehouse_inventory(warehouse_id,product_id,current_qty) values (wh,prod,100);
  insert into store_inventory(store_id,product_id,current_qty) values (st,prod,100);
  insert into user_store_assignments(user_id,store_id) values (staff,st);

  -- A shop-floor staff member must not be able to spend warehouse stock.
  perform set_config('request.jwt.claim.sub', staff::text, true);
  begin
    perform record_stock_use('warehouse', wh, prod, 40, 'taking warehouse stock');
    raise exception 'FAIL: a staff member wrote off 40 units of warehouse stock';
  exception when others then
    get stacked diagnostics v_msg = message_text;
    if v_msg like 'FAIL:%' then raise; end if;
    if v_msg not like '%permission%' and v_msg not like '%No access%' then
      raise exception 'FAIL: refused for the wrong reason (%)', v_msg; end if;
  end;

  select current_qty into v_qty from warehouse_inventory where warehouse_id = wh and product_id = prod;
  if v_qty <> 100 then
    raise exception 'FAIL: the refused write-off still moved warehouse stock (% left)', v_qty; end if;

  -- The same person must still be able to do their own job at their own store.
  perform record_stock_use('store', st, prod, 5, 'damaged on the shop floor');
  select current_qty into v_qty from store_inventory where store_id = st and product_id = prod;
  if v_qty <> 95 then
    raise exception 'FAIL: a staff member could not write off stock at their own store (% left)', v_qty; end if;

  -- And a manager still can use warehouse stock.
  perform set_config('request.jwt.claim.sub', mgr::text, true);
  perform record_stock_use('warehouse', wh, prod, 10, 'used for an event');
  select current_qty into v_qty from warehouse_inventory where warehouse_id = wh and product_id = prod;
  if v_qty <> 90 then
    raise exception 'FAIL: a manager could not use warehouse stock (% left)', v_qty; end if;

  raise notice 'PASS: warehouse write-offs need the warehouse permission; a staff member keeps their own store work and a manager keeps the warehouse';
end $$;
rollback;
