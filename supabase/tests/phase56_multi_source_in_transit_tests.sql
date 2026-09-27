-- MULTI-SOURCE APPROVAL MARKS STOCK IN TRANSIT SO IT CAN BE RECEIVED
begin;

do $t$
declare
  v_o uuid := gen_random_uuid(); v_st uuid; v_w1 uuid; v_w2 uuid;
  v_p1 uuid; v_p2 uuid; v_req uuid; v_l1 uuid; v_l2 uuid; v_n integer; v_q integer;
begin
  insert into auth.users(id,email) values (v_o,'rc2@x.com');
  insert into public.profiles(id,full_name,email,role,is_active) values (v_o,'RC2','rc2@x.com','owner',true);
  perform set_config('request.jwt.claims', json_build_object('sub',v_o::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_o::text, true);
  insert into public.stores(name,code,country_code) values ('RC2 Store','RC2S','SG') returning id into v_st;
  insert into public.warehouses(name,code) values ('RC2 W1','RC21') returning id into v_w1;
  insert into public.warehouses(name,code) values ('RC2 W2','RC22') returning id into v_w2;
  insert into public.products(name,sku,product_type) values ('RC2 A','RC2-1','own') returning id into v_p1;
  insert into public.products(name,sku,product_type) values ('RC2 B','RC2-2','own') returning id into v_p2;
  insert into public.warehouse_inventory(warehouse_id,product_id,current_qty) values
    (v_w1,v_p1,10),(v_w2,v_p1,10),(v_w1,v_p2,10);
  perform public.set_product_prices(v_st, v_p1, 100, 100, 'available');
  perform public.set_product_prices(v_st, v_p2, 100, 100, 'available');

  v_req := public.create_deferred_transfer_request('store', v_st,
    jsonb_build_array(
      jsonb_build_object('product_id', v_p1, 'quantity', 10),
      jsonb_build_object('product_id', v_p2, 'quantity', 5)), 'RC2');
  select id into v_l1 from public.transfer_request_lines where transfer_request_id=v_req and product_id=v_p1;
  select id into v_l2 from public.transfer_request_lines where transfer_request_id=v_req and product_id=v_p2;

  -- Product A LOWERED to 6, split across two warehouses. Product B EXCLUDED.
  perform public.approve_transfer_multi(v_req,
    jsonb_build_array(
      jsonb_build_object('product_id', v_p1, 'quantity', 6),
      jsonb_build_object('product_id', v_p2, 'quantity', 0)),
    'partial + split', null,
    jsonb_build_array(
      jsonb_build_object('line_id', v_l1, 'sources', jsonb_build_array(
        jsonb_build_object('warehouse_id', v_w1, 'quantity', 4),
        jsonb_build_object('warehouse_id', v_w2, 'quantity', 2))),
      jsonb_build_object('line_id', v_l2, 'sources', '[]'::jsonb)));

  -- ===== 1. THE LOWERED LINE IS RECEIVABLE, AT THE APPROVED FIGURE =====
  select in_transit_quantity into v_q from public.transfer_request_lines where id=v_l1;
  if coalesce(v_q,0) <> 6 then
    raise exception 'FAIL 1: 6 should be in transit, got %', coalesce(v_q::text,'NULL'); end if;
  raise notice 'PASS 1: a lowered quantity is marked in transit at the approved figure (6)';

  -- ===== 2. IT MATCHES WHAT ACTUALLY SHIPPED =====
  select coalesce(sum(quantity),0) into v_n from public.transfer_line_sources where line_id=v_l1;
  if v_n <> v_q then
    raise exception 'FAIL 2: in transit (%) must equal what was dispatched (%)', v_q, v_n; end if;
  raise notice 'PASS 2: it equals the sum of the warehouse allocations (4 + 2)';

  -- ===== 3. THE EXCLUDED LINE IS NOT RECEIVABLE =====
  select coalesce(in_transit_quantity,0) into v_q from public.transfer_request_lines where id=v_l2;
  if v_q <> 0 then
    raise exception 'FAIL 3: an excluded line must not be in transit, got %', v_q; end if;
  raise notice 'PASS 3: a line excluded at 0 is not offered for receiving';

  -- ===== 4. THE RECEIVE SCREEN WOULD SHOW EXACTLY ONE LINE =====
  select count(*) into v_n from public.transfer_request_lines
   where transfer_request_id = v_req and coalesce(in_transit_quantity,0) > 0;
  if v_n <> 1 then raise exception 'FAIL 4: Receive should list exactly 1 line, got %', v_n; end if;
  raise notice 'PASS 4: the Receive screen lists exactly the one line that shipped';

  -- ===== 5. AND IT CAN ACTUALLY BE RECEIVED =====
  -- receive_transfer expects every line named, the excluded one at 0.
  perform public.receive_transfer(v_req,
    jsonb_build_array(
      jsonb_build_object('product_id', v_p1, 'received_quantity', 6),
      jsonb_build_object('product_id', v_p2, 'received_quantity', 0)), 'all arrived');
  if (select current_qty from public.store_inventory where store_id=v_st and product_id=v_p1) <> 6 then
    raise exception 'FAIL 5: the store should have received 6, got %',
      coalesce((select current_qty from public.store_inventory where store_id=v_st and product_id=v_p1)::text,'none'); end if;
  raise notice 'PASS 5: the goods can be received and land in the store (6)';

  -- ===== 6. A FULL (NON-PARTIAL) MULTI-SOURCE APPROVAL ALSO WORKS =====
  declare v_req2 uuid; v_l3 uuid; begin
    v_req2 := public.create_deferred_transfer_request('store', v_st,
      jsonb_build_array(jsonb_build_object('product_id', v_p2, 'quantity', 3)), 'RC2 full');
    select id into v_l3 from public.transfer_request_lines where transfer_request_id=v_req2;
    perform public.approve_transfer_multi(v_req2,
      jsonb_build_array(jsonb_build_object('product_id', v_p2, 'quantity', 3)),
      'full', null,
      jsonb_build_array(jsonb_build_object('line_id', v_l3, 'sources',
        jsonb_build_array(jsonb_build_object('warehouse_id', v_w1, 'quantity', 3)))));
    if coalesce((select in_transit_quantity from public.transfer_request_lines where id=v_l3),0) <> 3 then
      raise exception 'FAIL 6: a full multi-source approval should also be receivable'; end if;
  end;
  raise notice 'PASS 6: a full multi-source approval is receivable too — this was equally broken';

  raise notice '=== IN-TRANSIT AFTER MULTI-SOURCE APPROVAL VERIFIED ===';
end $t$;

rollback;
