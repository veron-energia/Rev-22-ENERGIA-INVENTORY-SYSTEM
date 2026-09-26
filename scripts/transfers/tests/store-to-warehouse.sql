-- Transfers work again, and a store can return stock to a warehouse (364).
--
--   * one create_transfer_request remains (two with the same parameter names
--     made the API refuse every owner transfer);
--   * a store-to-warehouse return: Owner or Manager only, from a store to a
--     warehouse, with a reason an edit cannot blank; sourced only from its
--     own store; dispatched (stock leaves the store) and received at the
--     warehouse (stock arrives); an edit cannot turn it into anything else;
--   * no other label, at creation or by an edit, can move store stock to a
--     warehouse, and a request must say whether each end is a store or a
--     warehouse, so the return rules cannot be sidestepped;
--   * transfers into a warehouse no longer fail on the audit row
--     (warehouse-to-warehouse dispatch and receipt complete);
--   * store-to-store is unchanged.
--
-- Disposable database only; everything is rolled back.
begin;
do $$
declare own uuid:=gen_random_uuid(); stf uuid:=gen_random_uuid(); tag text:=substr(md5(random()::text),1,6);
 sa uuid; sb uuid; w1 uuid; w2 uuid; p uuid; r uuid; r2 uuid; r3 uuid; l uuid; n int; x record; v int;
begin
 insert into auth.users(id,email) values(own,'s2w-o-'||tag||'@tests.invalid'),(stf,'s2w-s-'||tag||'@tests.invalid');
 insert into profiles(id,full_name,email,role) values(own,'Owner','s2w-o-'||tag||'@tests.invalid','owner'),(stf,'Staff','s2w-s-'||tag||'@tests.invalid','staff');
 insert into stores(name,code,country_code) values('S2W Store A '||tag,'S2WA'||tag,'SG') returning id into sa;
 insert into stores(name,code,country_code) values('S2W Store B '||tag,'S2WB'||tag,'SG') returning id into sb;
 insert into user_store_assignments(user_id,store_id) values(stf,sa);
 insert into warehouses(name,code) values('S2W WH 1 '||tag,'S2W1'||tag) returning id into w1;
 insert into warehouses(name,code) values('S2W WH 2 '||tag,'S2W2'||tag) returning id into w2;
 insert into products(name,sku,product_type) values('S2W Pillow','S2W-P-'||tag,'own') returning id into p;
 insert into store_inventory(store_id,product_id,current_qty) values(sa,p,20),(sb,p,20);

 if (select count(*) from pg_proc where proname='create_transfer_request' and pronamespace='public'::regnamespace)<>1 then
  raise exception 'More than one create_transfer_request: the API cannot choose'; end if;

 -- ---- who may return, and how --------------------------------------------------
 perform set_config('request.jwt.claim.sub',stf::text,true);
 begin
  perform create_transfer_request('store_to_warehouse','store',sa,'warehouse',w1,jsonb_build_array(jsonb_build_object('product_id',p,'quantity',5)),'overstock');
  raise exception 'Staff created a return';
 exception when others then if sqlerrm not like '%Only an Owner or Manager can return stock%' then raise; end if; end;
 -- nor under another label
 begin
  perform create_transfer_request('store_to_store','store',sa,'warehouse',w1,jsonb_build_array(jsonb_build_object('product_id',p,'quantity',5)),null);
  raise exception 'Staff sent store stock to a warehouse under another label';
 exception when others then if sqlerrm not like '%choose Store → Warehouse%' then raise; end if; end;
 -- nor by leaving the location type blank, which used to skip every location
 -- check, staff store access included (store B is not the staff member's)
 begin
  perform create_transfer_request('store_to_store',null,sb,'warehouse',w1,jsonb_build_array(jsonb_build_object('product_id',p,'quantity',5)),null);
  raise exception 'Staff raised a transfer from an unassigned store by leaving its type blank';
 exception when others then if sqlerrm not like '%store or a warehouse%' then raise; end if; end;
 perform set_config('request.jwt.claim.sub',own::text,true);
 perform set_product_prices(sb,p,10,10,'available');
 begin
  perform create_transfer_request('store_to_warehouse','store',sa,'warehouse',w1,jsonb_build_array(jsonb_build_object('product_id',p,'quantity',5)),'  ');
  raise exception 'A return without a reason was accepted';
 exception when others then if sqlerrm not like '%reason for returning%' then raise; end if; end;
 begin
  perform create_transfer_request('store_to_warehouse','warehouse',w2,'warehouse',w1,jsonb_build_array(jsonb_build_object('product_id',p,'quantity',5)),'wrong way');
  raise exception 'A return from a warehouse was accepted';
 exception when others then if sqlerrm not like '%must go from a store to a warehouse%' then raise; end if; end;
 begin
  perform create_transfer_request('store_to_warehouse',null,w2,'warehouse',w1,jsonb_build_array(jsonb_build_object('line_kind','manual','manual_item_name','Box','manual_uom','pc','quantity',1)),'no source type');
  raise exception 'A return with no source type was accepted';
 exception when others then if sqlerrm not like '%store or a warehouse%' then raise; end if; end;
 begin
  perform create_transfer_request('store_to_warehouse','store',sa,'warehouse',w1,jsonb_build_array(jsonb_build_object('product_id',p,'quantity',5)),E'\t\n ');
  raise exception 'A return whose reason is only tabs and line breaks was accepted';
 exception when others then if sqlerrm not like '%reason for returning%' then raise; end if; end;
 begin
  perform create_transfer_request('warehouse_to_warehouse','store',sa,'warehouse',w1,jsonb_build_array(jsonb_build_object('product_id',p,'quantity',5)),null);
  raise exception 'An Owner sent store stock to a warehouse under another label, without a reason';
 exception when others then if sqlerrm not like '%choose Store → Warehouse%' then raise; end if; end;

 r:=(create_transfer_request('store_to_warehouse','store',sa,'warehouse',w1,jsonb_build_array(jsonb_build_object('product_id',p,'quantity',5)),'End of roadshow')->>'id')::uuid;
 select id into l from transfer_request_lines where transfer_request_id=r;
 if (select (transfer_type, status::text, source_type::text, dest_type::text) from transfer_requests where id=r)
    is distinct from ('store_to_warehouse'::text,'pending'::text,'store'::text,'warehouse'::text) then raise exception 'Return not saved as requested'; end if;

 -- review offers only the returning store
 select count(*) into n from transfer_request_sourcing(r);
 if n<>1 or (select source_id from transfer_request_sourcing(r) limit 1)<>sa then
  raise exception 'Review offered sources other than the returning store: %', (select jsonb_agg(source_name) from transfer_request_sourcing(r)); end if;
 if exists (select 1 from transfer_product_sourcing(r,p) where source_id<>sa) then raise exception 'Added-product sourcing offered another location'; end if;

 -- an edit cannot turn it into something else
 begin
  perform edit_transfer_request(r,null,'redirect','store'::location_type,sa,'store'::location_type,sb,null,null);
  raise exception 'A return was edited into a store transfer';
 exception when others then if sqlerrm not like '%must stay from a store to a warehouse%' then raise; end if; end;
 begin
  perform edit_transfer_request(r,null,'tidy','store'::location_type,sa,'warehouse'::location_type,w1,null,'   ');
  raise exception 'An edit blanked the reason for a return';
 exception when others then if sqlerrm not like '%reason for returning%' then raise; end if; end;
 begin
  perform edit_transfer_request(r,null,'tidy',null,null,null,null,null,E'\t');
  raise exception 'An edit replaced the reason for a return with a tab';
 exception when others then if sqlerrm not like '%reason for returning%' then raise; end if; end;

 -- dispatch only from the returning store
 begin
  perform review_and_dispatch_transfer(r,jsonb_build_array(jsonb_build_object('line_id',l,'kind','product','product_id',p,'approved_quantity',5,
    'sources',jsonb_build_array(jsonb_build_object('source_type','store','source_id',sb,'quantity',5)))),'from the wrong store');
  raise exception 'A return was dispatched from another store';
 exception when others then if sqlerrm not like '%only take stock from the store it was requested from%' then raise; end if; end;
 perform review_and_dispatch_transfer(r,jsonb_build_array(jsonb_build_object('line_id',l,'kind','product','product_id',p,'approved_quantity',5,
    'sources',jsonb_build_array(jsonb_build_object('source_type','store','source_id',sa,'quantity',5)))),'approved');
 if (select current_qty from store_inventory where store_id=sa and product_id=p)<>15 then raise exception 'Stock did not leave the store on dispatch'; end if;
 if (select status::text from transfer_requests where id=r)<>'in_transit' then raise exception 'Return not in transit'; end if;
 if coalesce((select current_qty from warehouse_inventory where warehouse_id=w1 and product_id=p),0)<>0 then raise exception 'Stock arrived before receipt'; end if;
 if (select store_id from audit_logs where record_id=r and action='transfer_reviewed_and_dispatched' order by created_at desc limit 1)<>sa then
  raise exception 'The dispatch audit row does not name the returning store'; end if;

 -- received at the warehouse, all of it as stock
 perform receive_transfer(r,null,'arrived',true);
 if (select current_qty from warehouse_inventory where warehouse_id=w1 and product_id=p)<>5 then raise exception 'Returned stock did not arrive at the warehouse'; end if;
 if (select status::text from transfer_requests where id=r)<>'received' then raise exception 'Return not received'; end if;

 -- ---- warehouse to warehouse completes (the audit row used to fail) ------------
 r2:=(create_transfer_request('warehouse_to_warehouse','warehouse',w1,'warehouse',w2,jsonb_build_array(jsonb_build_object('product_id',p,'quantity',2)),'rebalance')->>'id')::uuid;
 select id into l from transfer_request_lines where transfer_request_id=r2;
 perform review_and_dispatch_transfer(r2,jsonb_build_array(jsonb_build_object('line_id',l,'kind','product','product_id',p,'approved_quantity',2,
    'sources',jsonb_build_array(jsonb_build_object('source_type','warehouse','source_id',w1,'quantity',2)))),'ok');
 perform receive_transfer(r2,null,'ok',true);
 if (select current_qty from warehouse_inventory where warehouse_id=w2 and product_id=p)<>2 then raise exception 'Warehouse-to-warehouse did not complete'; end if;

 -- ---- store to store is unchanged -------------------------------------------------
 r3:=(create_transfer_request('store_to_store','store',sa,'store',sb,jsonb_build_array(jsonb_build_object('product_id',p,'quantity',1)),null)->>'id')::uuid;
 if r3 is null then raise exception 'Store-to-store could not be created'; end if;
 begin
  perform edit_transfer_request(r3,null,'redirect','store'::location_type,sa,'warehouse'::location_type,w1,null,null);
  raise exception 'A store transfer was edited into a move to a warehouse without the return rules';
 exception when others then if sqlerrm not like '%raise a Store → Warehouse return%' then raise; end if; end;
 select count(*) into n from transfer_request_sourcing(r3);
 if n<2 then raise exception 'Store-to-store review lost its other sources'; end if;

 raise notice 'PASS: one create_transfer_request; returns are Owner/Manager-only, store-to-warehouse, with a reason (not blankable), the only way to move store stock to a warehouse, sourced and dispatched only from their store, uneditable into anything else, and received into the warehouse; warehouse-to-warehouse completes; store-to-store unchanged';
end $$;
rollback;
