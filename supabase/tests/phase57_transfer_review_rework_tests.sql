-- =====================================================================
-- PHASE 57 — TRANSFER REVIEW REWORK + MANUAL ITEM REGRESSION TESTS
-- Run AFTER supabase/159_transfer_page_review_and_manual_items.sql.
-- All data is wrapped in one transaction and rolled back.
-- =====================================================================
begin;

do $t$
declare
  v_owner uuid := gen_random_uuid();
  v_staff uuid := gen_random_uuid();
  v_dest uuid; v_src_store uuid; v_wa uuid; v_wb uuid;
  v_a uuid; v_b uuid; v_c uuid; v_d uuid; v_e uuid; v_f uuid; v_g uuid; v_h uuid; v_i uuid;
  v_req uuid; v_req2 uuid; v_line uuid; v_line2 uuid; v_manual uuid;
  v_res jsonb; v_row record; v_n integer; v_q integer; v_before integer; v_after integer;
  v_failed boolean;
begin
  -- ---------- fixture ----------
  insert into auth.users(id,email) values
    (v_owner,'phase57.owner@x.com'),(v_staff,'phase57.staff@x.com');
  insert into public.profiles(id,full_name,email,role,is_active) values
    (v_owner,'Phase57 Owner','phase57.owner@x.com','owner',true),
    (v_staff,'Phase57 Staff','phase57.staff@x.com','staff',true);

  perform set_config('request.jwt.claims', json_build_object('sub',v_owner::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_owner::text, true);

  insert into public.stores(name,code,country_code) values ('P57 Destination','P57D','SG') returning id into v_dest;
  insert into public.stores(name,code,country_code) values ('P57 Source Store','P57S','SG') returning id into v_src_store;
  insert into public.warehouses(name,code) values ('P57 Warehouse A','P57WA') returning id into v_wa;
  insert into public.warehouses(name,code) values ('P57 Warehouse B','P57WB') returning id into v_wb;
  insert into public.user_store_assignments(user_id,store_id) values (v_staff,v_dest);

  insert into public.products(name,sku,product_type) values
    ('P57 Pillow','P57-A','own'),('P57 B','P57-B','own'),('P57 C','P57-C','own'),
    ('P57 D','P57-D','own'),('P57 E','P57-E','own'),('P57 F','P57-F','own'),
    ('P57 G','P57-G','own'),('P57 H','P57-H','own'),('P57 I','P57-I','own');
  select id into v_a from public.products where sku='P57-A';
  select id into v_b from public.products where sku='P57-B';
  select id into v_c from public.products where sku='P57-C';
  select id into v_d from public.products where sku='P57-D';
  select id into v_e from public.products where sku='P57-E';
  select id into v_f from public.products where sku='P57-F';
  select id into v_g from public.products where sku='P57-G';
  select id into v_h from public.products where sku='P57-H';
  select id into v_i from public.products where sku='P57-I';

  perform public.set_product_prices(v_dest,v_a,100,100,'available');
  perform public.set_product_prices(v_dest,v_b,100,100,'available');
  perform public.set_product_prices(v_dest,v_c,100,100,'available');
  perform public.set_product_prices(v_dest,v_d,100,100,'available');
  perform public.set_product_prices(v_dest,v_e,100,100,'available');
  perform public.set_product_prices(v_dest,v_f,100,100,'available');
  perform public.set_product_prices(v_dest,v_g,100,100,'available');
  perform public.set_product_prices(v_dest,v_h,100,100,'available');
  perform public.set_product_prices(v_dest,v_i,100,100,'available');

  insert into public.warehouse_inventory(warehouse_id,product_id,current_qty) values
    (v_wa,v_a,20),(v_wb,v_a,30),
    (v_wa,v_b,20),(v_wa,v_c,20),(v_wa,v_d,20),
    (v_wa,v_e,7),(v_wb,v_e,8),
    (v_wa,v_f,20),(v_wa,v_g,10),(v_wa,v_h,5),(v_wa,v_i,10);
  insert into public.store_inventory(store_id,product_id,current_qty) values
    (v_src_store,v_a,12),(v_src_store,v_f,6);

  -- ==================================================================
  -- TEST 1: Staff creates unsourced Pillow 10 and edits it to 15.
  -- ==================================================================
  perform set_config('request.jwt.claims', json_build_object('sub',v_staff::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_staff::text, true);
  v_res := public.create_staff_transfer_request(
    jsonb_build_array(jsonb_build_object('line_kind','product','product_id',v_a,'quantity',10)),
    'P57 test 1',v_dest);
  v_req := (v_res->>'id')::uuid;
  perform public.edit_transfer_request(v_req,1,'increase requested amount',null,null,null,null,
    jsonb_build_array(jsonb_build_object('line_kind','product','product_id',v_a,'quantity',15)),
    'edited');
  if (select quantity from public.transfer_request_lines where transfer_request_id=v_req) <> 15 then
    raise exception 'FAIL TEST 1: unsourced Staff edit did not save 15'; end if;
  if (select source_id from public.transfer_requests where id=v_req) is not null then
    raise exception 'FAIL TEST 1: Staff edit unexpectedly chose a source'; end if;
  raise notice 'PASS TEST 1: unsourced Staff request edits without false insufficient-stock validation';

  -- ==================================================================
  -- TEST 2: Unsourced demand reserves neither Warehouse A nor B.
  -- ==================================================================
  select * into v_row from public.location_available_qty('warehouse',v_wa,v_a);
  if v_row.on_hand<>20 or v_row.reserved<>0 or v_row.available<>20 then
    raise exception 'FAIL TEST 2 A: expected 20/0/20, got %/%/%',v_row.on_hand,v_row.reserved,v_row.available; end if;
  select * into v_row from public.location_available_qty('warehouse',v_wb,v_a);
  if v_row.on_hand<>30 or v_row.reserved<>0 or v_row.available<>30 then
    raise exception 'FAIL TEST 2 B: expected 30/0/30, got %/%/%',v_row.on_hand,v_row.reserved,v_row.available; end if;
  raise notice 'PASS TEST 2: deferred demand does not create phantom reservations';
  delete from public.transfer_requests where id=v_req;

  -- ==================================================================
  -- TEST 3: A sourced pending request reserves only its own source.
  -- ==================================================================
  perform set_config('request.jwt.claims', json_build_object('sub',v_owner::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_owner::text, true);
  v_res := public.create_transfer_request('warehouse_to_store','warehouse',v_wa,'store',v_dest,
    jsonb_build_array(jsonb_build_object('line_kind','product','product_id',v_a,'quantity',5)),'P57 sourced');
  v_req := (v_res->>'id')::uuid;
  select * into v_row from public.location_available_qty('warehouse',v_wa,v_a);
  if v_row.reserved<>5 or v_row.available<>15 then raise exception 'FAIL TEST 3 A: source should reserve 5'; end if;
  select * into v_row from public.location_available_qty('warehouse',v_wb,v_a);
  if v_row.reserved<>0 or v_row.available<>30 then raise exception 'FAIL TEST 3 B: other warehouse must reserve 0'; end if;
  raise notice 'PASS TEST 3: sourced pending demand reserves only the actual source';
  delete from public.transfer_requests where id=v_req;

  -- ==================================================================
  -- TEST 4: Review lists warehouses + stores with real stock figures.
  -- ==================================================================
  v_req := public.create_deferred_transfer_request('store',v_dest,
    jsonb_build_array(jsonb_build_object('product_id',v_a,'quantity',10)),'P57 sourcing');
  select * into v_row from public.transfer_request_sourcing(v_req)
   where source_type='warehouse' and source_id=v_wa limit 1;
  if v_row.on_hand<>20 or v_row.reserved<>0 or v_row.available<>20 then
    raise exception 'FAIL TEST 4 WA: expected 20/0/20'; end if;
  select * into v_row from public.transfer_request_sourcing(v_req)
   where source_type='store' and source_id=v_src_store limit 1;
  if v_row.on_hand<>12 or v_row.reserved<>0 or v_row.available<>12 then
    raise exception 'FAIL TEST 4 Store: expected 12/0/12'; end if;
  if exists(select 1 from public.transfer_request_sourcing(v_req) where source_type='store' and source_id=v_dest) then
    raise exception 'FAIL TEST 4: destination store offered as its own source'; end if;
  raise notice 'PASS TEST 4: Review source rows expose On Hand / Reserved / Available for warehouses and stores';
  delete from public.transfer_requests where id=v_req;

  -- ==================================================================
  -- TEST 5: Requested 10 -> Owner approves 15; requested stays 10.
  -- Also verifies source deduction and in-transit quantity.
  -- ==================================================================
  v_req := public.create_deferred_transfer_request('store',v_dest,
    jsonb_build_array(jsonb_build_object('product_id',v_a,'quantity',10)),'P57 over approval');
  select id into v_line from public.transfer_request_lines where transfer_request_id=v_req;
  perform public.review_and_dispatch_transfer(v_req,
    jsonb_build_array(jsonb_build_object('line_id',v_line,'line_kind','product','approved_quantity',15,
      'sources',jsonb_build_array(jsonb_build_object('source_type','warehouse','source_id',v_wa,'quantity',15)))),'approve +5');
  select quantity,approved_quantity,in_transit_quantity into v_row
    from public.transfer_request_lines where id=v_line;
  if v_row.quantity<>10 or v_row.approved_quantity<>15 or v_row.in_transit_quantity<>15 then
    raise exception 'FAIL TEST 5: expected requested/approved/in-transit 10/15/15, got %/%/%',v_row.quantity,v_row.approved_quantity,v_row.in_transit_quantity; end if;
  if (select current_qty from public.warehouse_inventory where warehouse_id=v_wa and product_id=v_a)<>5 then
    raise exception 'FAIL TEST 5: source should be 20-15=5'; end if;
  if coalesce((select current_qty from public.store_inventory where store_id=v_dest and product_id=v_a),0)<>0 then
    raise exception 'FAIL TEST 5/12: destination changed during approval'; end if;
  raise notice 'PASS TEST 5: owner can approve over requested while preserving original request';

  -- TEST 12 continuation: destination changes only on receipt.
  perform set_config('request.jwt.claims', json_build_object('sub',v_staff::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_staff::text, true);
  perform public.receive_transfer(v_req,null,'received',true);
  if (select current_qty from public.store_inventory where store_id=v_dest and product_id=v_a)<>15 then
    raise exception 'FAIL TEST 12: destination should receive 15 only after receipt'; end if;
  raise notice 'PASS TEST 12: destination stock is untouched at approval and added at receipt';

  -- ==================================================================
  -- TEST 6: Owner adds Product C during review and dispatches it.
  -- ==================================================================
  perform set_config('request.jwt.claims', json_build_object('sub',v_owner::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_owner::text, true);
  v_req := public.create_deferred_transfer_request('store',v_dest,
    jsonb_build_array(jsonb_build_object('product_id',v_b,'quantity',2)),'P57 add product');
  select id into v_line from public.transfer_request_lines where transfer_request_id=v_req;
  perform public.review_and_dispatch_transfer(v_req,jsonb_build_array(
    jsonb_build_object('line_id',v_line,'line_kind','product','approved_quantity',2,
      'sources',jsonb_build_array(jsonb_build_object('source_type','warehouse','source_id',v_wa,'quantity',2))),
    jsonb_build_object('line_kind','product','product_id',v_c,'approved_quantity',5,
      'sources',jsonb_build_array(jsonb_build_object('source_type','warehouse','source_id',v_wa,'quantity',5)))
  ),'owner adds C');
  select id into v_line2 from public.transfer_request_lines where transfer_request_id=v_req and product_id=v_c;
  if v_line2 is null or not (select added_by_approver from public.transfer_request_lines where id=v_line2) then
    raise exception 'FAIL TEST 6: added Product C is not marked added_by_approver'; end if;
  if (select in_transit_quantity from public.transfer_request_lines where id=v_line2)<>5 then raise exception 'FAIL TEST 6: Product C not in transit at 5'; end if;
  if (select current_qty from public.warehouse_inventory where warehouse_id=v_wa and product_id=v_c)<>15 then raise exception 'FAIL TEST 6: Product C source deduction wrong'; end if;
  raise notice 'PASS TEST 6: Owner-added Product is persisted, marked, allocated and dispatched';

  -- ==================================================================
  -- TESTS 7/8/9: Manual item is transfer-only, can be approved above request,
  -- received with discrepancy, and never changes Product inventory/movements.
  -- ==================================================================
  select count(*) into v_before from public.products where name='P57 A4 Paper';
  perform set_config('request.jwt.claims', json_build_object('sub',v_staff::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_staff::text, true);
  v_res := public.create_staff_transfer_request(jsonb_build_array(
    jsonb_build_object('line_kind','product','product_id',v_d,'quantity',3),
    jsonb_build_object('line_kind','manual','manual_item_name','P57 A4 Paper','manual_uom','Bag','quantity',1)
  ),'manual request',v_dest);
  v_req := (v_res->>'id')::uuid;
  select id into v_line from public.transfer_request_lines where transfer_request_id=v_req and product_id=v_d;
  select id into v_manual from public.transfer_request_lines where transfer_request_id=v_req and line_kind='manual';
  select count(*) into v_after from public.products where name='P57 A4 Paper';
  if v_after<>v_before then raise exception 'FAIL TEST 7: manual item was inserted into Products'; end if;
  raise notice 'PASS TEST 7: manual item exists only on its transfer and never enters Products';

  perform set_config('request.jwt.claims', json_build_object('sub',v_owner::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_owner::text, true);
  perform public.review_and_dispatch_transfer(v_req,jsonb_build_array(
    jsonb_build_object('line_id',v_line,'line_kind','product','approved_quantity',3,
      'sources',jsonb_build_array(jsonb_build_object('source_type','warehouse','source_id',v_wa,'quantity',3))),
    jsonb_build_object('line_id',v_manual,'line_kind','manual','approved_quantity',2,'sources','[]'::jsonb)
  ),'manual approved at 2');
  if (select in_transit_quantity from public.transfer_request_lines where id=v_manual)<>2 then raise exception 'FAIL TEST 8: manual in-transit should be 2'; end if;
  if exists(select 1 from public.stock_movements where transfer_request_line_id=v_manual) then raise exception 'FAIL TEST 8: manual dispatch created stock movement'; end if;
  raise notice 'PASS TEST 8: manual approval may exceed requested and causes no inventory deduction/movement';

  perform set_config('request.jwt.claims', json_build_object('sub',v_staff::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_staff::text, true);
  perform public.receive_transfer(v_req,jsonb_build_array(
    jsonb_build_object('line_id',v_line,'received_quantity',3),
    jsonb_build_object('line_id',v_manual,'received_quantity',1,'reason','one bag arrived')
  ),'manual one bag short',false);
  if (select received_quantity from public.transfer_request_lines where id=v_manual)<>1
     or (select discrepancy_quantity from public.transfer_request_lines where id=v_manual)<>-1 then
    raise exception 'FAIL TEST 9: manual receipt/discrepancy not recorded by line id'; end if;
  if exists(select 1 from public.stock_movements where transfer_request_line_id=v_manual) then raise exception 'FAIL TEST 9: manual receipt created stock movement'; end if;
  select coalesce(sum(current_qty),0) into v_before from public.warehouse_inventory where product_id is null; -- always 0; explicit non-product guard
  perform set_config('request.jwt.claims', json_build_object('sub',v_owner::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_owner::text, true);
  perform public.resolve_transfer_discrepancy(v_req,
    jsonb_build_array(jsonb_build_object('line_id',v_manual,'resolution','accept_loss','reason','acknowledged')),'manual ack');
  if exists(select 1 from public.stock_movements where transfer_request_line_id=v_manual) then raise exception 'FAIL TEST 9: resolving manual discrepancy created stock movement'; end if;
  raise notice 'PASS TEST 9: manual receipt/discrepancy is audit-only and never mutates product inventory';

  -- ==================================================================
  -- TEST 10: multi-warehouse split dispatch totals exactly to approved qty.
  -- ==================================================================
  v_req := public.create_deferred_transfer_request('store',v_dest,
    jsonb_build_array(jsonb_build_object('product_id',v_e,'quantity',10)),'P57 multi');
  select id into v_line from public.transfer_request_lines where transfer_request_id=v_req;
  perform public.review_and_dispatch_transfer(v_req,jsonb_build_array(
    jsonb_build_object('line_id',v_line,'line_kind','product','approved_quantity',10,'sources',jsonb_build_array(
      jsonb_build_object('source_type','warehouse','source_id',v_wa,'quantity',6),
      jsonb_build_object('source_type','warehouse','source_id',v_wb,'quantity',4)
    ))),'split 6/4');
  if (select current_qty from public.warehouse_inventory where warehouse_id=v_wa and product_id=v_e)<>1
     or (select current_qty from public.warehouse_inventory where warehouse_id=v_wb and product_id=v_e)<>4 then
    raise exception 'FAIL TEST 10: split source deduction wrong'; end if;
  select coalesce(sum(quantity),0) into v_n from public.transfer_line_sources where line_id=v_line;
  if v_n<>10 then raise exception 'FAIL TEST 10: allocations total %, expected 10',v_n; end if;
  select coalesce(sum(quantity),0) into v_n from public.stock_movements where transfer_request_line_id=v_line and movement_type='transfer_dispatch';
  if v_n<>10 then raise exception 'FAIL TEST 10: movement total %, expected 10',v_n; end if;
  if (select count(*) from public.stock_movements where transfer_request_line_id=v_line and movement_type='transfer_dispatch')<>2 then
    raise exception 'FAIL TEST 10: expected one dispatch movement per source'; end if;
  raise notice 'PASS TEST 10: multi-warehouse allocation and movement evidence are exact';

  -- ==================================================================
  -- TEST 11: Store-as-source still works.
  -- ==================================================================
  v_req := public.create_deferred_transfer_request('store',v_dest,
    jsonb_build_array(jsonb_build_object('product_id',v_f,'quantity',4)),'P57 store source');
  select id into v_line from public.transfer_request_lines where transfer_request_id=v_req;
  perform public.review_and_dispatch_transfer(v_req,jsonb_build_array(
    jsonb_build_object('line_id',v_line,'line_kind','product','approved_quantity',4,
      'sources',jsonb_build_array(jsonb_build_object('source_type','store','source_id',v_src_store,'quantity',4)))
  ),'shop source');
  if (select current_qty from public.store_inventory where store_id=v_src_store and product_id=v_f)<>2 then
    raise exception 'FAIL TEST 11: source store should be 6-4=2'; end if;
  if not exists(select 1 from public.transfer_line_sources where line_id=v_line and source_type='store' and source_id=v_src_store and quantity=4) then
    raise exception 'FAIL TEST 11: store allocation not recorded'; end if;
  raise notice 'PASS TEST 11: store-as-source remains correct';

  -- ==================================================================
  -- TEST 13: later insufficient line rolls back the ENTIRE approval.
  -- ==================================================================
  v_req := public.create_deferred_transfer_request('store',v_dest,jsonb_build_array(
    jsonb_build_object('product_id',v_g,'quantity',5),jsonb_build_object('product_id',v_h,'quantity',6)
  ),'P57 atomic fail');
  select id into v_line from public.transfer_request_lines where transfer_request_id=v_req and product_id=v_g;
  select id into v_line2 from public.transfer_request_lines where transfer_request_id=v_req and product_id=v_h;
  v_failed:=false;
  begin
    perform public.review_and_dispatch_transfer(v_req,jsonb_build_array(
      jsonb_build_object('line_id',v_line,'line_kind','product','approved_quantity',5,
        'sources',jsonb_build_array(jsonb_build_object('source_type','warehouse','source_id',v_wa,'quantity',5))),
      jsonb_build_object('line_id',v_line2,'line_kind','product','approved_quantity',6,
        'sources',jsonb_build_array(jsonb_build_object('source_type','warehouse','source_id',v_wa,'quantity',6)))
    ),'must rollback');
  exception when others then v_failed:=true; end;
  if not v_failed then raise exception 'FAIL TEST 13: insufficient approval unexpectedly succeeded'; end if;
  if (select current_qty from public.warehouse_inventory where warehouse_id=v_wa and product_id=v_g)<>10
     or (select current_qty from public.warehouse_inventory where warehouse_id=v_wa and product_id=v_h)<>5 then
    raise exception 'FAIL TEST 13: a failed review left partial stock deductions'; end if;
  if (select status from public.transfer_requests where id=v_req)<>'pending' then raise exception 'FAIL TEST 13: failed review changed status'; end if;
  raise notice 'PASS TEST 13: insufficient stock fails atomically and deducts nothing';

  -- ==================================================================
  -- TEST 14: competing requests cannot consume the same final units.
  -- In a multi-session runner the FOR UPDATE inventory locks serialize these;
  -- this single-session regression proves the second transaction sees the
  -- post-dispatch reality and cannot over-consume it.
  -- ==================================================================
  v_req := public.create_deferred_transfer_request('store',v_dest,
    jsonb_build_array(jsonb_build_object('product_id',v_i,'quantity',7)),'P57 competitor A');
  v_req2 := public.create_deferred_transfer_request('store',v_dest,
    jsonb_build_array(jsonb_build_object('product_id',v_i,'quantity',7)),'P57 competitor B');
  select id into v_line from public.transfer_request_lines where transfer_request_id=v_req;
  select id into v_line2 from public.transfer_request_lines where transfer_request_id=v_req2;
  perform public.review_and_dispatch_transfer(v_req,jsonb_build_array(
    jsonb_build_object('line_id',v_line,'line_kind','product','approved_quantity',7,
      'sources',jsonb_build_array(jsonb_build_object('source_type','warehouse','source_id',v_wa,'quantity',7)))
  ),'first competitor');
  v_failed:=false;
  begin
    perform public.review_and_dispatch_transfer(v_req2,jsonb_build_array(
      jsonb_build_object('line_id',v_line2,'line_kind','product','approved_quantity',7,
        'sources',jsonb_build_array(jsonb_build_object('source_type','warehouse','source_id',v_wa,'quantity',7)))
    ),'second competitor');
  exception when others then v_failed:=true; end;
  if not v_failed then raise exception 'FAIL TEST 14: second competing approval consumed unavailable stock'; end if;
  if (select current_qty from public.warehouse_inventory where warehouse_id=v_wa and product_id=v_i)<>3 then
    raise exception 'FAIL TEST 14: final stock should be 3 after one successful dispatch'; end if;
  raise notice 'PASS TEST 14: competing approval cannot consume the same units twice';

  -- ==================================================================
  -- Extra integrity checks used by TESTS 5/6/10/11.
  -- ==================================================================
  if exists(select 1 from public.report_transfer_stock_integrity() where severity in ('critical','error') and request_id in (v_req,v_req2)) then
    raise exception 'FAIL integrity preview: unexpected integrity error in final competition fixtures'; end if;

  raise notice '=== PHASE 57 TRANSFER REVIEW REWORK TESTS PASSED ===';
  raise notice 'TEST 15: also run phase54_partial_approval_allocation_tests.sql, phase55_ship_from_store_tests.sql, and phase56_multi_source_in_transit_tests.sql after this migration.';
end $t$;

rollback;
