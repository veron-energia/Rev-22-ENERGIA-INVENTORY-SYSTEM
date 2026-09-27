-- STOCK MAY BE RELEASED AND TRANSFERRED FROM A STORE
begin;

do $t$
declare
  v_o uuid := gen_random_uuid(); v_s1 uuid; v_s2 uuid; v_wh uuid;
  v_p uuid; v_pm uuid; v_cust uuid; v_sp uuid; v_inv uuid; v_rent uuid;
  v_req uuid; v_line uuid; v_res jsonb; v_n integer; v_row record;
begin
  insert into auth.users(id,email) values (v_o,'sfs@x.com');
  insert into public.profiles(id,full_name,email,role,is_active) values (v_o,'SFS','sfs@x.com','owner',true);
  perform set_config('request.jwt.claims', json_build_object('sub',v_o::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_o::text, true);
  insert into public.stores(name,code,country_code) values ('SFS Shop','SFS1','SG') returning id into v_s1;
  insert into public.stores(name,code,country_code) values ('SFS Dest','SFS2','SG') returning id into v_s2;
  insert into public.warehouses(name,code) values ('SFS WH','SFSW') returning id into v_wh;
  insert into public.payment_methods(name) values ('SFS Cash') returning id into v_pm;
  insert into public.products(name,sku,product_type) values ('SFS Machine','SFS-1','own') returning id into v_p;
  -- Stock ONLY in the shop; the warehouse is empty.
  insert into public.store_inventory(store_id,product_id,current_qty) values (v_s1,v_p,8);
  insert into public.warehouse_inventory(warehouse_id,product_id,current_qty) values (v_wh,v_p,0);
  perform public.set_product_prices(v_s1, v_p, 1000, 1000, 'available');
  -- The destination store needs a price row before stock may be sent there.
  perform public.set_product_prices(v_s2, v_p, 1000, 1000, 'available');
  insert into public.customers(full_name,phone) values ('SFS Cust','+65SFS1') returning id into v_cust;
  v_sp := public.upsert_special_product_from_product(null, v_p, 1000, 100, null, null, null, 10);

  -- ===== 1. THE RELEASE PICKER OFFERS STORES AS WELL =====
  select count(*) into v_n from public.special_product_availability(v_sp) where location_type='store';
  if v_n < 1 then raise exception 'FAIL 1: stores should be offered as a source'; end if;
  select * into v_row from public.special_product_availability(v_sp)
   where location_type='store' and warehouse_id = v_s1;
  if v_row.on_hand <> 8 then raise exception 'FAIL 1: the shop should show 8 on hand, got %', v_row.on_hand; end if;
  raise notice 'PASS 1: the release picker offers stores alongside warehouses, with real figures';

  -- ===== 2. RELEASING FROM A STORE DEDUCTS STORE STOCK =====
  v_inv := public.create_invoice(v_s1, v_cust, null,
    jsonb_build_array(jsonb_build_object('kind','rental','special_product_id',v_sp,'quantity',2,
      'rental_rate_type','day','rental_periods',1)), 0, 'SFS');
  perform public.pay_invoice(v_inv, jsonb_build_array(jsonb_build_object('payment_method_id',v_pm,
    'amount',(select total_amount from public.invoices where id=v_inv))));
  select doc_id into v_rent from public.special_docs_awaiting_fulfilment() where doc_kind='rental';

  v_res := public.fulfil_special_doc('rental', v_rent, v_s1, 'store');
  if (select current_qty from public.store_inventory where store_id=v_s1 and product_id=v_p) <> 6 then
    raise exception 'FAIL 2: the shop should be 8-2=6, got %',
      (select current_qty from public.store_inventory where store_id=v_s1 and product_id=v_p); end if;
  raise notice 'PASS 2: releasing from a store takes the stock out of that store (8 -> 6)';

  -- ===== 3. THE MOVEMENT RECORDS THE STORE, NOT A WAREHOUSE =====
  select * into v_row from public.stock_movements
   where product_id=v_p and notes like '%Rental released%' order by created_at desc limit 1;
  if v_row.from_store_id <> v_s1 then
    raise exception 'FAIL 3: the movement should record the store it came from'; end if;
  if v_row.from_warehouse_id is not null then
    raise exception 'FAIL 3: it must not claim a warehouse'; end if;
  raise notice 'PASS 3: Stock History records the store it actually came from';

  -- ===== 4. TRANSFER SOURCING OFFERS THE STORE =====
  v_req := public.create_deferred_transfer_request('store', v_s2,
    jsonb_build_array(jsonb_build_object('product_id', v_p, 'quantity', 3)), 'SFS transfer');
  select count(*) into v_n from public.transfer_request_sourcing(v_req) where source_type='store';
  if v_n < 1 then raise exception 'FAIL 4: a store holding stock should be offered as a source'; end if;
  raise notice 'PASS 4: transfer approval offers stores as a source, not only warehouses';

  -- ===== 5. THE DESTINATION STORE IS NOT OFFERED TO ITSELF =====
  select count(*) into v_n from public.transfer_request_sourcing(v_req)
   where source_type='store' and warehouse_id = v_s2;
  if v_n <> 0 then raise exception 'FAIL 5: a store must not be able to ship to itself'; end if;
  raise notice 'PASS 5: the destination store is never offered as its own source';

  -- ===== 6. APPROVING FROM A STORE MOVES THE STOCK =====
  select line_id into v_line from public.transfer_request_sourcing(v_req) limit 1;
  v_res := public.approve_transfer_multi(v_req,
    jsonb_build_array(jsonb_build_object('product_id', v_p, 'quantity', 3)),
    'from the shop', null,
    jsonb_build_array(jsonb_build_object('line_id', v_line, 'sources',
      jsonb_build_array(jsonb_build_object('warehouse_id', v_s1, 'source_type', 'store', 'quantity', 3)))));
  if (select current_qty from public.store_inventory where store_id=v_s1 and product_id=v_p) <> 3 then
    raise exception 'FAIL 6: the source shop should be 6-3=3, got %',
      (select current_qty from public.store_inventory where store_id=v_s1 and product_id=v_p); end if;
  raise notice 'PASS 6: approving a transfer from a store deducts that store (6 -> 3)';

  -- ===== 7. IT IS RECORDED AS A STORE SOURCE =====
  select count(*) into v_n from public.transfer_line_sources
   where line_id = v_line and source_type = 'store' and source_id = v_s1;
  if v_n <> 1 then raise exception 'FAIL 7: the allocation should be recorded as a store source'; end if;
  raise notice 'PASS 7: the allocation is recorded with source_type = store';

  -- ===== 8. A WAREHOUSE SOURCE STILL WORKS =====
  update public.warehouse_inventory set current_qty = 10 where warehouse_id=v_wh and product_id=v_p;
  declare v_req2 uuid; v_line2 uuid; begin
    v_req2 := public.create_deferred_transfer_request('store', v_s2,
      jsonb_build_array(jsonb_build_object('product_id', v_p, 'quantity', 4)), 'SFS wh');
    select line_id into v_line2 from public.transfer_request_sourcing(v_req2) limit 1;
    perform public.approve_transfer_multi(v_req2,
      jsonb_build_array(jsonb_build_object('product_id', v_p, 'quantity', 4)),
      'from the warehouse', null,
      jsonb_build_array(jsonb_build_object('line_id', v_line2, 'sources',
        jsonb_build_array(jsonb_build_object('warehouse_id', v_wh, 'quantity', 4)))));
    if (select current_qty from public.warehouse_inventory where warehouse_id=v_wh and product_id=v_p) <> 6 then
      raise exception 'FAIL 8: the warehouse should be 10-4=6, got %',
        (select current_qty from public.warehouse_inventory where warehouse_id=v_wh and product_id=v_p); end if;
  end;
  raise notice 'PASS 8: a warehouse source still behaves exactly as before';

  raise notice '=== SHIPPING FROM A STORE VERIFIED ===';
end $t$;

rollback;
