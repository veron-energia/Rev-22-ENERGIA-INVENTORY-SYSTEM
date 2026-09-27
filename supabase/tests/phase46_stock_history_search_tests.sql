-- STOCK USE IN HISTORY + SEARCHABLE MOVEMENTS
begin;

do $t$
declare
  v_o uuid := gen_random_uuid(); v_emi uuid := gen_random_uuid();
  v_store uuid; v_wh uuid; v_p1 uuid; v_p2 uuid; v_n integer; v_row record;
begin
  insert into auth.users(id,email) values (v_o,'sh-o@x.com'),(v_emi,'sh-e@x.com');
  insert into public.profiles(id,full_name,email,role,is_active) values
    (v_o,'SH Owner','sh-o@x.com','owner',true),(v_emi,'Emi Tester','sh-e@x.com','staff',true);
  perform set_config('request.jwt.claims', json_build_object('sub',v_o::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_o::text, true);
  insert into public.stores(name,code,country_code) values ('Energia Rev 22 (Adelphi)','SHS','SG') returning id into v_store;
  insert into public.warehouses(name,code) values ('Warehouse 0906 (Goods)','SHW') returning id into v_wh;
  insert into public.user_store_assignments(user_id,store_id) values (v_emi,v_store);
  insert into public.products(name,sku,product_type) values ('Energia Corset ver 3.0','P00201','own') returning id into v_p1;
  insert into public.products(name,sku,product_type) values ('Miracle Water Filter','P00110','own') returning id into v_p2;
  insert into public.store_inventory(store_id,product_id,current_qty) values (v_store,v_p1,50),(v_store,v_p2,20);
  insert into public.warehouse_inventory(warehouse_id,product_id,current_qty) values (v_wh,v_p1,100);

  -- ===== 1. A STOCK USE NOW APPEARS IN THE HISTORY =====
  select count(*) into v_n from public.stock_movements where product_id = v_p1;
  perform public.record_stock_use('store', v_store, v_p1, 2, 'Demo unit', 'roadshow tester');
  if (select count(*) from public.stock_movements where product_id = v_p1) <> v_n + 1 then
    raise exception 'FAIL 1: recording a use should write a stock movement'; end if;
  raise notice 'PASS 1: recording a stock use now appears in Stock Movement History';

  -- ===== 2. IT CARRIES THE REASON AND THE USE NUMBER =====
  select * into v_row from public.search_stock_movements('Demo unit');
  if v_row.id is null then raise exception 'FAIL 2: the use should be findable by its reason'; end if;
  if v_row.notes not like '%roadshow tester%' then
    raise exception 'FAIL 2: the note should be carried, got %', v_row.notes; end if;
  if v_row.quantity <> 2 then raise exception 'FAIL 2: quantity should be 2'; end if;
  raise notice 'PASS 2: the movement carries the use number, reason and note';

  -- ===== 3. AND THE STOCK ACTUALLY WENT DOWN =====
  if (select current_qty from public.store_inventory where store_id=v_store and product_id=v_p1) <> 48 then
    raise exception 'FAIL 3: store stock should be 50-2=48'; end if;
  raise notice 'PASS 3: the stock itself is reduced, and the two agree';

  -- ===== 4. SEARCH BY PRODUCT NAME =====
  select count(*) into v_n from public.search_stock_movements('Corset');
  if v_n < 1 then raise exception 'FAIL 4: search by product name found nothing'; end if;
  raise notice 'PASS 4: searchable by product name';

  -- ===== 5. SEARCH BY SKU =====
  select count(*) into v_n from public.search_stock_movements('P00201');
  if v_n < 1 then raise exception 'FAIL 5: search by SKU found nothing'; end if;
  raise notice 'PASS 5: searchable by product SKU';

  -- ===== 6. SEARCH BY STORE NAME =====
  select count(*) into v_n from public.search_stock_movements('Adelphi');
  if v_n < 1 then raise exception 'FAIL 6: search by store name found nothing'; end if;
  raise notice 'PASS 6: searchable by store name';

  -- ===== 7. SEARCH BY WAREHOUSE NAME =====
  perform public.record_stock_use('warehouse', v_wh, v_p1, 1, 'Warehouse tester', null);
  select count(*) into v_n from public.search_stock_movements('Warehouse 0906');
  if v_n < 1 then raise exception 'FAIL 7: search by warehouse name found nothing'; end if;
  raise notice 'PASS 7: searchable by warehouse name';

  -- ===== 8. SEARCH BY THE PERSON WHO DID IT =====
  perform set_config('request.jwt.claim.sub', v_emi::text, true);
  perform public.record_stock_use('store', v_store, v_p2, 1, 'Emi demo', null);
  perform set_config('request.jwt.claim.sub', v_o::text, true);
  select count(*) into v_n from public.search_stock_movements('Emi');
  if v_n < 1 then raise exception 'FAIL 8: search by staff name found nothing'; end if;
  select count(*) into v_n from public.search_stock_movements('SH Owner');
  if v_n < 1 then raise exception 'FAIL 8: search by owner name found nothing'; end if;
  raise notice 'PASS 8: searchable by the staff or owner who made the change';

  -- ===== 9. SEARCH IS CASE-INSENSITIVE AND PARTIAL =====
  select count(*) into v_n from public.search_stock_movements('corset');
  if v_n < 1 then raise exception 'FAIL 9: search should be case-insensitive'; end if;
  raise notice 'PASS 9: search is case-insensitive and matches partial words';

  -- ===== 10. AN UNRELATED TERM FINDS NOTHING =====
  select count(*) into v_n from public.search_stock_movements('zzz-no-such-thing');
  if v_n <> 0 then raise exception 'FAIL 10: an unrelated term should find nothing, got %', v_n; end if;
  raise notice 'PASS 10: an unrelated term returns nothing rather than everything';

  -- ===== 11. THE TOTAL COUNT SUPPORTS PAGING =====
  select total_count into v_n from public.search_stock_movements(null, null, null, null, 1, 0);
  if v_n < 3 then raise exception 'FAIL 11: the total should count all matches, got %', v_n; end if;
  raise notice 'PASS 11: the total count is returned for paging (%)', v_n;

  raise notice '=== STOCK USE IN HISTORY + SEARCH VERIFIED ===';
end $t$;

rollback;
