-- STAFF MAY FLAG A PRODUCT AS IMPORTANT
begin;

do $t$
declare v_o uuid := gen_random_uuid(); v_stf uuid := gen_random_uuid();
        v_store uuid; v_p1 uuid; v_p2 uuid; v_n integer; v_row record;
begin
  insert into auth.users(id,email) values (v_o,'im-o@x.com'),(v_stf,'im-s@x.com');
  insert into public.profiles(id,full_name,email,role,is_active) values
    (v_o,'IM Owner','im-o@x.com','owner',true),(v_stf,'IM Staff','im-s@x.com','staff',true);
  perform set_config('request.jwt.claims', json_build_object('sub',v_o::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_o::text, true);
  insert into public.stores(name,code,country_code) values ('IM Store','IMS','SG') returning id into v_store;
  insert into public.user_store_assignments(user_id,store_id) values (v_stf,v_store);
  insert into public.products(name,sku,product_type) values ('IM Fast Mover','IM-1','own') returning id into v_p1;
  insert into public.products(name,sku,product_type) values ('IM Slow Mover','IM-2','own') returning id into v_p2;
  insert into public.store_inventory(store_id,product_id,current_qty) values (v_store,v_p1,50),(v_store,v_p2,3);

  -- ===== 1. STAFF CAN MARK A PRODUCT IMPORTANT =====
  perform set_config('request.jwt.claim.sub', v_stf::text, true);
  perform public.set_product_important(v_p1, true);
  if not (select is_important from public.products where id=v_p1) then
    raise exception 'FAIL 1: staff should be able to mark a product important'; end if;
  raise notice 'PASS 1: a staff member can mark a product as important';

  -- ===== 2. AND UNMARK IT =====
  perform public.set_product_important(v_p1, false);
  if (select is_important from public.products where id=v_p1) then
    raise exception 'FAIL 2: staff should be able to unmark it'; end if;
  perform public.set_product_important(v_p1, true);
  raise notice 'PASS 2: and can unmark it again';

  -- (Test 3 — that this grants no wider editing — is checked separately below
  --  as the `authenticated` role, because running here as the superuser
  --  bypasses RLS entirely and would prove nothing.)

  -- ===== 4. THE STORE LIST CARRIES THE FLAG, IMPORTANT FIRST =====
  select * into v_row from public.store_stock_with_flags(v_store) limit 1;
  if v_row.product_id <> v_p1 or not v_row.is_important then
    raise exception 'FAIL 4: important products should sort first, got % (important=%)',
      v_row.name, v_row.is_important; end if;
  select count(*) into v_n from public.store_stock_with_flags(v_store) where is_important;
  if v_n <> 1 then raise exception 'FAIL 4: exactly 1 important product expected, got %', v_n; end if;
  raise notice 'PASS 4: the store list carries the flag and sorts important products first';

  -- ===== 5. QUANTITIES COME THROUGH =====
  select * into v_row from public.store_stock_with_flags(v_store) where product_id = v_p1;
  if v_row.current_qty <> 50 then
    raise exception 'FAIL 5: the quantity should be 50, got %', v_row.current_qty; end if;
  raise notice 'PASS 5: store quantities come through with the flag';

  -- ===== 6. A MISSING PRODUCT IS REFUSED =====
  begin
    perform public.set_product_important(gen_random_uuid(), true);
    raise exception 'FAIL 6: an unknown product must be refused';
  exception when others then
    if sqlerrm like '%Product not found%' then null; else raise; end if;
  end;
  raise notice 'PASS 6: marking an unknown product is refused';

  raise notice '=== IMPORTANT FLAG VERIFIED ===';
end $t$;

rollback;

-- Run as `authenticated` with RLS enforced: the only way a privilege claim
-- means anything.
begin;
do $t$
declare v_o uuid := gen_random_uuid(); v_stf uuid := gen_random_uuid(); v_p uuid;
begin
  insert into auth.users(id,email) values (v_o,'i2o@x.com'),(v_stf,'i2s@x.com');
  insert into public.profiles(id,full_name,email,role,is_active) values
    (v_o,'I2 Owner','i2o@x.com','owner',true),(v_stf,'I2 Staff','i2s@x.com','staff',true);
  perform set_config('request.jwt.claim.sub', v_o::text, true);
  insert into public.products(name,sku,product_type) values ('I2 Prod','I2-1','own') returning id into v_p;
  create temporary table _i2 on commit drop as select v_stf as stf, v_p as prod;
  grant all on _i2 to authenticated;
end $t$;

set local role authenticated;
select set_config('request.jwt.claim.sub', (select stf::text from _i2), true);

-- Staff CAN flag importance...
select public.set_product_important((select prod from _i2), true) is null as flag_ok;
select 'is_important now: '||is_important::text from public.products where id=(select prod from _i2);

-- ...but CANNOT rename the product.
update public.products set name = 'Renamed by staff' where id = (select prod from _i2);
select 'name after rename attempt: '||name from public.products where id=(select prod from _i2);
reset role;
rollback;
