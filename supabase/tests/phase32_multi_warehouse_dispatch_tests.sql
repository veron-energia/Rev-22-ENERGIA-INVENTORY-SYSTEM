-- =====================================================================
-- MULTI-WAREHOUSE DISPATCH — stock must leave the allocated warehouses
-- =====================================================================
begin;

do $t$
declare
  v_o uuid := gen_random_uuid(); v_store uuid; v_wA uuid; v_wB uuid; v_wC uuid;
  v_p1 uuid; v_p2 uuid; v_req uuid; v_l1 uuid; v_l2 uuid; v_res jsonb; v_n integer;
begin
  insert into auth.users(id,email) values (v_o,'f98@x.com');
  insert into public.profiles(id,full_name,email,role) values (v_o,'F98','f98@x.com','owner');
  perform set_config('request.jwt.claims', json_build_object('sub',v_o::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_o::text, true);
  insert into public.stores(name,code,country_code) values ('F98 Store','F98S','SG') returning id into v_store;
  insert into public.warehouses(name,code) values ('F98 Main','F98A') returning id into v_wA;
  insert into public.warehouses(name,code) values ('F98 Second','F98B') returning id into v_wB;
  insert into public.warehouses(name,code) values ('F98 Third','F98C') returning id into v_wC;

  insert into public.products(name,sku,product_type) values ('F98 Corset','F98-1','own') returning id into v_p1;
  insert into public.products(name,sku,product_type) values ('F98 Flat','F98-2','own') returning id into v_p2;
  perform public.set_product_prices(v_store, v_p1, 100, 100, 'available');
  perform public.set_product_prices(v_store, v_p2, 100, 100, 'available');
  -- Mirrors the screenshots: Main 90, Second 100, Third 100.
  insert into public.warehouse_inventory(warehouse_id,product_id,current_qty) values
    (v_wA,v_p1,90), (v_wB,v_p1,0),  (v_wC,v_p1,0),
    (v_wA,v_p2,90), (v_wB,v_p2,100),(v_wC,v_p2,100);

  v_req := public.create_deferred_transfer_request('store', v_store,
    jsonb_build_array(
      jsonb_build_object('product_id', v_p1, 'quantity', 10),
      jsonb_build_object('product_id', v_p2, 'quantity', 10)), 'F98');
  select id into v_l1 from public.transfer_request_lines where transfer_request_id=v_req and product_id=v_p1;
  select id into v_l2 from public.transfer_request_lines where transfer_request_id=v_req and product_id=v_p2;

  -- Exactly the approval in the screenshot: Corset 10 from Main;
  -- Flat 5 from Second + 3 from Third + 2 from Main.
  v_res := public.approve_transfer_multi(v_req, null, 'F98 split', null,
    jsonb_build_array(
      jsonb_build_object('line_id', v_l1, 'sources',
        jsonb_build_array(jsonb_build_object('warehouse_id', v_wA, 'quantity', 10))),
      jsonb_build_object('line_id', v_l2, 'sources',
        jsonb_build_array(
          jsonb_build_object('warehouse_id', v_wB, 'quantity', 5),
          jsonb_build_object('warehouse_id', v_wC, 'quantity', 3),
          jsonb_build_object('warehouse_id', v_wA, 'quantity', 2)))));

  -- ===== Stock must come out of the RIGHT warehouses =====
  select current_qty into v_n from public.warehouse_inventory where warehouse_id=v_wA and product_id=v_p1;
  if v_n <> 80 then raise exception 'FAIL: Main Corset should be 90-10=80, got %', v_n; end if;

  select current_qty into v_n from public.warehouse_inventory where warehouse_id=v_wB and product_id=v_p2;
  if v_n <> 95 then raise exception 'FAIL: Second Flat should be 100-5=95, got %', v_n; end if;
  select current_qty into v_n from public.warehouse_inventory where warehouse_id=v_wC and product_id=v_p2;
  if v_n <> 97 then raise exception 'FAIL: Third Flat should be 100-3=97, got %', v_n; end if;
  select current_qty into v_n from public.warehouse_inventory where warehouse_id=v_wA and product_id=v_p2;
  if v_n <> 88 then raise exception 'FAIL: Main Flat should be 90-2=88, got %', v_n; end if;
  raise notice 'PASS: each warehouse gives up exactly its allocation (80 / 95 / 97 / 88)';

  -- ===== Stock History must show every warehouse, not just one =====
  select count(distinct from_warehouse_id) into v_n from public.stock_movements
   where product_id = v_p2 and notes like 'F98 split%';
  if v_n <> 3 then raise exception 'FAIL: Flat should show 3 dispatch legs, got %', v_n; end if;
  select count(*) into v_n from public.stock_movements
   where product_id = v_p2 and from_warehouse_id = v_wB and quantity = 5 and notes like 'F98 split%';
  if v_n <> 1 then raise exception 'FAIL: a 5-unit leg from Second is missing'; end if;
  raise notice 'PASS: Stock History records one dispatch leg per warehouse, with the right quantities';

  -- ===== Totals still balance =====
  select coalesce(sum(quantity),0) into v_n from public.stock_movements where notes like 'F98 split%';
  if v_n <> 20 then raise exception 'FAIL: 20 units should have been dispatched in total, got %', v_n; end if;
  raise notice 'PASS: the total dispatched matches the approved quantities';

  -- ===== The transfer proceeds normally =====
  if (select status from public.transfer_requests where id=v_req)::text <> 'in_transit' then
    raise exception 'FAIL: the request should be in transit'; end if;
  if not (v_res->>'multi_source')::boolean or (v_res->>'units_dispatched')::int <> 20 then
    raise exception 'FAIL: the result should report a 20-unit multi-source dispatch'; end if;
  raise notice 'PASS: the request moves to In Transit and reports the split correctly';

  -- ===== Receipt still works, adding stock at the destination =====
  perform public.receive_transfer(v_req, null, 'F98 received', true);
  select current_qty into v_n from public.store_inventory where store_id=v_store and product_id=v_p2;
  if v_n <> 10 then raise exception 'FAIL: the store should receive all 10 Flat, got %', v_n; end if;
  raise notice 'PASS: the destination still receives the full quantity on receipt';

  raise notice '=== MULTI-WAREHOUSE DISPATCH FIX VERIFIED ===';
end $t$;

rollback;

-- Drift report for transfers dispatched before the fix.
begin;

do $t$
declare
  v_o uuid := gen_random_uuid(); v_store uuid; v_wA uuid; v_wB uuid;
  v_p uuid; v_req uuid; v_l uuid; v_n integer; v_row record;
begin
  insert into auth.users(id,email) values (v_o,'drift@x.com');
  insert into public.profiles(id,full_name,email,role) values (v_o,'DR','drift@x.com','owner');
  perform set_config('request.jwt.claim.sub', v_o::text, true);
  insert into public.stores(name,code,country_code) values ('DR Store','DRS','SG') returning id into v_store;
  insert into public.warehouses(name,code) values ('DR Main','DRA') returning id into v_wA;
  insert into public.warehouses(name,code) values ('DR Second','DRB') returning id into v_wB;
  insert into public.products(name,sku,product_type) values ('DR Prod','DR-1','own') returning id into v_p;
  perform public.set_product_prices(v_store, v_p, 100, 100, 'available');
  insert into public.warehouse_inventory(warehouse_id,product_id,current_qty) values (v_wA,v_p,50),(v_wB,v_p,50);

  v_req := public.create_deferred_transfer_request('store', v_store,
    jsonb_build_array(jsonb_build_object('product_id', v_p, 'quantity', 10)), 'DR');
  select id into v_l from public.transfer_request_lines where transfer_request_id=v_req;

  -- Simulate the OLD broken dispatch: allocations say 6 + 4, but all 10 were
  -- taken from Main and one movement logged.
  insert into public.transfer_line_sources(line_id, source_type, source_id, quantity)
    values (v_l,'warehouse',v_wA,6), (v_l,'warehouse',v_wB,4);
  update public.transfer_request_lines set approved_quantity = 10 where id = v_l;
  update public.warehouse_inventory set current_qty = current_qty - 10
    where warehouse_id = v_wA and product_id = v_p;
  update public.transfer_requests set status='in_transit', dispatched_at = now(),
    source_type='warehouse', source_id=v_wA where id = v_req;
  insert into public.stock_movements(product_id, movement_type, from_warehouse_id, to_store_id,
    quantity, notes, created_by)
  values (v_p, 'warehouse_to_store', v_wA, v_store, 10, 'old broken dispatch', v_o);

  -- The report should find both sides of the discrepancy.
  select count(*) into v_n from public.report_multi_source_stock_drift() where request_id = v_req;
  if v_n <> 2 then raise exception 'FAIL: the report should flag 2 warehouses, got %', v_n; end if;

  select * into v_row from public.report_multi_source_stock_drift()
   where request_id = v_req and warehouse_id = v_wA;
  if v_row.correction <> -4 then
    raise exception 'FAIL: Main over-gave 4, correction should be -4, got %', v_row.correction; end if;
  select * into v_row from public.report_multi_source_stock_drift()
   where request_id = v_req and warehouse_id = v_wB;
  if v_row.correction <> 4 then
    raise exception 'FAIL: Second under-gave 4, correction should be +4, got %', v_row.correction; end if;
  raise notice 'PASS: the drift report names each warehouse and the exact correction (Main +4 back, Second -4)';
  raise notice '=== DRIFT REPORT VERIFIED ===';
end $t$;

rollback;
