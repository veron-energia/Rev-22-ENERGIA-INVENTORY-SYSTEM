-- LOWERED AND EXCLUDED APPROVED QUANTITIES WITH PER-WAREHOUSE ALLOCATION
begin;

do $t$
declare
  v_o uuid := gen_random_uuid(); v_store uuid; v_w1 uuid; v_w2 uuid;
  v_p1 uuid; v_p2 uuid; v_req uuid; v_l1 uuid; v_l2 uuid; v_res jsonb; v_n integer;
begin
  insert into auth.users(id,email) values (v_o,'p54.tz@x.com');
  insert into public.profiles(id,full_name,email,role,is_active) values (v_o,'P54 TZ','p54.tz@x.com','owner',true);
  perform set_config('request.jwt.claims', json_build_object('sub',v_o::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_o::text, true);
  insert into public.stores(name,code,country_code) values ('P54 Store','P54S','SG') returning id into v_store;
  insert into public.warehouses(name,code) values ('P54 W1','P541') returning id into v_w1;
  insert into public.warehouses(name,code) values ('P54 W2','P542') returning id into v_w2;
  insert into public.products(name,sku,product_type) values ('P54 A','P54-1','own') returning id into v_p1;
  insert into public.products(name,sku,product_type) values ('P54 B','P54-2','own') returning id into v_p2;
  perform public.set_product_prices(v_store, v_p1, 100, 100, 'available');
  perform public.set_product_prices(v_store, v_p2, 100, 100, 'available');
  insert into public.warehouse_inventory(warehouse_id,product_id,current_qty) values
    (v_w1,v_p1,6),(v_w2,v_p1,9),(v_w1,v_p2,20);

  v_req := public.create_deferred_transfer_request('store', v_store,
    jsonb_build_array(
      jsonb_build_object('product_id', v_p1, 'quantity', 10),
      jsonb_build_object('product_id', v_p2, 'quantity', 4)), 'P54 TZ');
  select id into v_l1 from public.transfer_request_lines where transfer_request_id=v_req and product_id=v_p1;
  select id into v_l2 from public.transfer_request_lines where transfer_request_id=v_req and product_id=v_p2;

  -- Approve product A at a LOWERED 7, and EXCLUDE product B by setting 0.
  v_res := public.approve_transfer_multi(v_req,
    jsonb_build_array(
      jsonb_build_object('product_id', v_p1, 'quantity', 7),
      jsonb_build_object('product_id', v_p2, 'quantity', 0)),
    'lowered and excluded', null,
    jsonb_build_array(
      jsonb_build_object('line_id', v_l1, 'sources',
        jsonb_build_array(jsonb_build_object('warehouse_id', v_w2, 'quantity', 7))),
      jsonb_build_object('line_id', v_l2, 'sources', '[]'::jsonb)));

  -- Only 7 of A should have left, and none of B.
  if (select current_qty from public.warehouse_inventory where warehouse_id=v_w2 and product_id=v_p1) <> 2 then
    raise exception 'FAIL: W2 should be 9-7=2, got %',
      (select current_qty from public.warehouse_inventory where warehouse_id=v_w2 and product_id=v_p1); end if;
  if (select current_qty from public.warehouse_inventory where warehouse_id=v_w1 and product_id=v_p2) <> 20 then
    raise exception 'FAIL: the excluded product must not move'; end if;
  raise notice 'PASS: a lowered quantity ships 7 and an excluded line (0) ships nothing';

  select count(*) into v_n from public.transfer_line_sources where line_id = v_l2;
  if v_n <> 0 then raise exception 'FAIL: the excluded line should have no sources, got %', v_n; end if;
  raise notice 'PASS: the excluded line records no warehouse allocation';
  raise notice '=== LOWERED AND EXCLUDED QUANTITIES VERIFIED ===';
end $t$;

rollback;
