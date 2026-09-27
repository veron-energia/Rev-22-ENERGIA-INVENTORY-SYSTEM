-- SPECIAL STOCK-IN LANDS IN THE SHARED WAREHOUSE POOL
begin;

do $t$
declare v_o uuid := gen_random_uuid(); v_w1 uuid; v_w2 uuid; v_prod uuid; v_sp uuid;
        v_res jsonb; v_n integer;
begin
  insert into auth.users(id,email) values (v_o,'si@x.com');
  insert into public.profiles(id,full_name,email,role,is_active) values (v_o,'SI','si@x.com','owner',true);
  perform set_config('request.jwt.claims', json_build_object('sub',v_o::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_o::text, true);
  insert into public.warehouses(name,code) values ('SI One','SI1') returning id into v_w1;
  insert into public.warehouses(name,code) values ('SI Two','SI2') returning id into v_w2;
  insert into public.products(name,sku,product_type) values ('SI Machine','SI-1','own') returning id into v_prod;
  v_sp := public.upsert_special_product_from_product(null, v_prod, 7094, 94, null, 994, null, 0);

  -- ===== Adding stock lands in the WAREHOUSE pool =====
  v_res := public.special_stock_in(v_sp, v_w1, 10, 'first delivery');
  if (v_res->>'quantity_after')::int <> 10 then
    raise exception 'FAIL: warehouse one should hold 10, got %', v_res->>'quantity_after'; end if;
  perform public.special_stock_in(v_sp, v_w2, 5, 'second delivery');

  select coalesce(sum(wi.current_qty),0) into v_n from public.warehouse_inventory wi
   where wi.product_id = v_prod;
  if v_n <> 15 then raise exception 'FAIL: total should be 10+5=15, got %', v_n; end if;
  raise notice 'PASS: stock added through the Stock button lands in warehouse inventory (10 + 5 = 15)';

  -- ===== And is the SAME pool a transfer would see =====
  select on_hand into v_n from public.warehouse_available_qty(v_w1, v_prod);
  if v_n <> 10 then raise exception 'FAIL: the transfer view should see 10, got %', v_n; end if;
  raise notice 'PASS: it is the same pool transfers and releases read (10 at warehouse one)';

  -- ===== It appears in Stock History =====
  select count(*) into v_n from public.stock_movements
   where product_id = v_prod and movement_type::text = 'warehouse_stock_in';
  if v_n <> 2 then raise exception 'FAIL: 2 stock-in movements expected, got %', v_n; end if;
  raise notice 'PASS: each addition is recorded in Stock History';

  -- ===== A special product with no linked product is refused, clearly =====
  declare v_orph uuid; begin
    insert into public.special_products(name,sku,sale_price) values ('SI Orphan','SI-X',10)
      returning id into v_orph;
    begin
      perform public.special_stock_in(v_orph, v_w1, 5, null);
      raise exception 'FAIL: an unlinked special product must be refused';
    exception when others then
      if sqlerrm like '%not linked to a warehouse product%' then null; else raise; end if;
    end;
  end;
  raise notice 'PASS: an unlinked special product is refused with an actionable message';

  raise notice '=== SPECIAL STOCK-IN VERIFIED ===';
end $t$;

rollback;
