-- STOCK USE BACKFILL
begin;

do $t$
declare
  v_o uuid := gen_random_uuid(); v_store uuid; v_wh uuid; v_p uuid;
  v_n integer; v_before integer; v_row record; v_qty integer;
begin
  insert into auth.users(id,email) values (v_o,'bf@x.com');
  insert into public.profiles(id,full_name,email,role,is_active) values (v_o,'BF Owner','bf@x.com','owner',true);
  perform set_config('request.jwt.claims', json_build_object('sub',v_o::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_o::text, true);
  insert into public.stores(name,code,country_code) values ('BF Store','BFS','SG') returning id into v_store;
  insert into public.warehouses(name,code) values ('BF WH','BFW') returning id into v_wh;
  insert into public.products(name,sku,product_type) values ('BF Product','BF-1','own') returning id into v_p;
  insert into public.store_inventory(store_id,product_id,current_qty) values (v_store,v_p,100);

  -- Simulate a LEGACY use: the row exists and stock was already deducted, but
  -- no movement was ever written — exactly the state before migration 111.
  insert into public.stock_uses (use_no, location_type, store_id, product_id,
    quantity, reason, note, used_by, created_at)
  values ('USE-LEGACY-1', 'store', v_store, v_p, 3, 'Old demo unit', 'from last month',
    v_o, now() - interval '30 days');
  update public.store_inventory set current_qty = current_qty - 3
   where store_id = v_store and product_id = v_p;
  select current_qty into v_before from public.store_inventory
   where store_id = v_store and product_id = v_p;

  if exists (select 1 from public.stock_movements where notes like 'Stock use USE-LEGACY-1%') then
    raise exception 'SETUP: the legacy use should have no movement yet'; end if;

  -- ===== RUN THE BACKFILL (the migration's block, inline) =====
  insert into public.stock_movements
    (product_id, movement_type, from_store_id, from_warehouse_id, quantity, notes, created_by, created_at)
  select su.product_id, 'inventory_adjustment'::stock_movement_type,
    su.store_id, su.warehouse_id, su.quantity,
    'Stock use ' || su.use_no || ' — ' || coalesce(su.reason,'recorded use')
      || coalesce(' (' || nullif(trim(su.note),'') || ')', '') || ' [backfilled]',
    su.used_by, su.created_at
   from public.stock_uses su
  where not exists (select 1 from public.stock_movements sm
                     where sm.product_id = su.product_id
                       and sm.notes like 'Stock use ' || su.use_no || ' %');

  -- ===== 1. IT NOW APPEARS IN THE HISTORY =====
  select count(*) into v_n from public.stock_movements where notes like 'Stock use USE-LEGACY-1%';
  if v_n <> 1 then raise exception 'FAIL 1: the legacy use should now appear once, got %', v_n; end if;
  raise notice 'PASS 1: a past stock use now appears in Stock Movement History';

  -- ===== 2. THE STOCK IS NOT DEDUCTED AGAIN =====
  if (select current_qty from public.store_inventory where store_id=v_store and product_id=v_p) <> v_before then
    raise exception 'FAIL 2: the backfill must not touch the stock — it was already deducted'; end if;
  raise notice 'PASS 2: the stock figure is untouched — only the missing history line was added';

  -- ===== 3. IT SITS AT ITS ORIGINAL DATE =====
  select * into v_row from public.stock_movements where notes like 'Stock use USE-LEGACY-1%';
  if v_row.created_at::date <> (now() - interval '30 days')::date then
    raise exception 'FAIL 3: it should keep its original date, got %', v_row.created_at; end if;
  raise notice 'PASS 3: it sits at its original date, not today';

  -- ===== 4. THE REASON, NOTE AND PERSON ARE CARRIED =====
  if v_row.notes not like '%Old demo unit%' or v_row.notes not like '%from last month%' then
    raise exception 'FAIL 4: the reason and note should be carried, got %', v_row.notes; end if;
  if v_row.created_by <> v_o then raise exception 'FAIL 4: the person should be carried'; end if;
  if v_row.quantity <> 3 then raise exception 'FAIL 4: the quantity should be 3'; end if;
  raise notice 'PASS 4: reason, note, quantity and the person who did it are all carried';

  -- ===== 5. RUNNING IT AGAIN DOES NOT DUPLICATE =====
  insert into public.stock_movements
    (product_id, movement_type, from_store_id, from_warehouse_id, quantity, notes, created_by, created_at)
  select su.product_id, 'inventory_adjustment'::stock_movement_type,
    su.store_id, su.warehouse_id, su.quantity,
    'Stock use ' || su.use_no || ' — ' || coalesce(su.reason,'recorded use')
      || coalesce(' (' || nullif(trim(su.note),'') || ')', '') || ' [backfilled]',
    su.used_by, su.created_at
   from public.stock_uses su
  where not exists (select 1 from public.stock_movements sm
                     where sm.product_id = su.product_id
                       and sm.notes like 'Stock use ' || su.use_no || ' %');
  select count(*) into v_n from public.stock_movements where notes like 'Stock use USE-LEGACY-1%';
  if v_n <> 1 then raise exception 'FAIL 5: re-running must not duplicate, got % rows', v_n; end if;
  raise notice 'PASS 5: re-running the backfill does not duplicate anything';

  -- ===== 6. IT IS SEARCHABLE =====
  select count(*) into v_n from public.search_stock_movements('Old demo unit');
  if v_n < 1 then raise exception 'FAIL 6: the backfilled use should be searchable'; end if;
  raise notice 'PASS 6: the backfilled use is searchable like any other movement';

  raise notice '=== STOCK USE BACKFILL VERIFIED ===';
end $t$;

rollback;
