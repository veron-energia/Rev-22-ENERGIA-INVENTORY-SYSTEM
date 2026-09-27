-- STAFF READ THE SPECIAL CATALOGUE; WRITES STAY OWNER/MANAGER-ONLY
-- Seeded as superuser, then read as `authenticated` with RLS enforced, which is
-- the only way this bug shows up.
begin;
do $t$
declare v_o uuid := gen_random_uuid(); v_stf uuid := gen_random_uuid();
        v_store uuid; v_sp uuid; v_wh uuid;
begin
  insert into auth.users(id,email) values (v_o,'srd-o@x.com'),(v_stf,'srd-s@x.com');
  insert into public.profiles(id,full_name,email,role,is_active) values
    (v_o,'SRD Owner','srd-o@x.com','owner',true),(v_stf,'SRD Staff','srd-s@x.com','staff',true);
  perform set_config('request.jwt.claim.sub', v_o::text, true);
  insert into public.stores(name,code,country_code) values ('SRD Store','SRDS','SG') returning id into v_store;
  insert into public.user_store_assignments(user_id,store_id) values (v_stf,v_store);
  insert into public.warehouses(name,code) values ('SRD WH','SRDW') returning id into v_wh;
  insert into public.special_products(name,sku,sale_price,rate_day,late_fee_per_day)
    values ('SRD Machine','SRD-1',300,50,10) returning id into v_sp;
  insert into public.special_product_stock(special_product_id,warehouse_id,current_qty)
    values (v_sp,v_wh,5);
  create temporary table _srd on commit drop as select v_stf as stf, v_sp as sp;
  grant all on _srd to authenticated;
end $t$;

set local role authenticated;
select set_config('request.jwt.claim.sub', (select stf::text from _srd), true);
do $chk$
declare v_n integer;
begin
  select count(*) into v_n from public.special_products where is_active;
  if v_n < 1 then raise exception 'FAIL: staff must be able to see the special product catalogue'; end if;
  raise notice 'PASS: staff can see the special product catalogue (% row(s))', v_n;

  select count(*) into v_n from public.special_product_stock;
  if v_n < 1 then raise exception 'FAIL: staff must be able to see special product stock'; end if;
  raise notice 'PASS: staff can see special product stock';
end $chk$;
-- Reading is widened; WRITING must still be refused. The refusal is caught and
-- turned into an assertion, so a genuine failure (the write SUCCEEDING) is what
-- makes this suite fail, rather than the expected RLS error.
do $chk$
declare v_blocked boolean := false; v_price numeric;
begin
  begin
    insert into public.special_products(name,sku,sale_price) values ('Sneaky','SNK-1',1);
  exception when others then v_blocked := true;
  end;
  if not v_blocked then raise exception 'FAIL: staff must not be able to add a special product'; end if;
  raise notice 'PASS: staff cannot add a special product';

  update public.special_products set sale_price = 1 where id = (select sp from _srd);
  select sale_price into v_price from public.special_products where id = (select sp from _srd);
  if v_price <> 300 then raise exception 'FAIL: staff must not be able to change the price, got %', v_price; end if;
  raise notice 'PASS: staff cannot change a special product price';
end $chk$;
reset role;
rollback;
