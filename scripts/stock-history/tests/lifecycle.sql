-- Only run in the disposable Stock History database. All fixtures roll back.
begin;
grant usage on schema public,auth to authenticated;
grant select on public.stock_movements,public.store_inventory,public.warehouse_inventory,public.transfer_requests,public.transfer_request_lines,public.transfer_line_sources to authenticated;
create temp table history_lifecycle_ids(key text primary key,id uuid);
grant select on history_lifecycle_ids to authenticated;
do $$
declare own uuid:=gen_random_uuid(); staff uuid:=gen_random_uuid(); a uuid; b uuid; dest uuid; p uuid; p2 uuid; r uuid; l uuid; l2 uuid;
 f jsonb; x jsonb; y jsonb; day0 date:=sg_today()-2; dispatch_at timestamptz; receipt_at timestamptz;
begin
 insert into auth.users(id,email) values(own,'lifecycle-owner@test.invalid'),(staff,'lifecycle-staff@test.invalid');
 insert into profiles(id,full_name,email,role) values(own,'Lifecycle Owner','lifecycle-owner@test.invalid','owner'),(staff,'Source Staff','lifecycle-staff@test.invalid','staff');
 perform set_config('request.jwt.claim.sub',own::text,true);
 insert into stores(name,code,country_code) values('Own Source','HL-A','SG') returning id into a;
 insert into stores(name,code,country_code) values('Private Source','HL-B','SG') returning id into b;
 insert into stores(name,code,country_code) values('Counterpart Destination','HL-D','SG') returning id into dest;
 insert into user_store_assignments(user_id,store_id) values(staff,a);
 insert into products(name,sku,product_type) values('Split Product','HL-P','own') returning id into p;
 insert into products(name,sku,product_type) values('Other Leg Product','HL-Q','own') returning id into p2;
 insert into store_inventory(store_id,product_id,current_qty) values(a,p,100),(b,p,100),(dest,p,0),(a,p2,100),(b,p2,100);
 perform set_product_prices(dest,p,10,10,'available');perform set_product_prices(dest,p2,10,10,'available');
 -- Place the fixture's independently observed initialization before the range.
 update stock_history_observation set started_at=(day0-2)::timestamp at time zone 'Asia/Singapore';
 update stock_history_inventory_changes set occurred_at=(day0-1)::timestamp at time zone 'Asia/Singapore' where product_id in (p,p2);
 r:=(create_transfer_request('store_to_store','store',a,'store',dest,jsonb_build_array(
  jsonb_build_object('product_id',p,'quantity',5),jsonb_build_object('product_id',p2,'quantity',4)),'Shared split request')->>'id')::uuid;
 select id into l from transfer_request_lines where transfer_request_id=r and product_id=p;
 select id into l2 from transfer_request_lines where transfer_request_id=r and product_id=p2;
 perform review_and_dispatch_transfer(r,jsonb_build_array(
  jsonb_build_object('line_id',l,'kind','product','product_id',p,'approved_quantity',5,'sources',jsonb_build_array(
   jsonb_build_object('source_type','store','source_id',a,'quantity',2),jsonb_build_object('source_type','store','source_id',b,'quantity',3))),
  jsonb_build_object('line_id',l2,'kind','product','product_id',p2,'approved_quantity',4,'sources',jsonb_build_array(
   jsonb_build_object('source_type','store','source_id',b,'quantity',4)))),'Shared split dispatch');
 dispatch_at:=((day0+1)::timestamp at time zone 'Asia/Singapore')-interval '1 second';
 receipt_at:=(day0+1)::timestamp at time zone 'Asia/Singapore';
 update stock_movements set stock_history_recorded_at=dispatch_at where transfer_request_id=r;
 update stock_history_inventory_changes set occurred_at=dispatch_at where product_id in (p,p2) and delta<0;
 update transfer_requests set dispatched_at=dispatch_at where id=r;
 perform receive_transfer(r,jsonb_build_array(jsonb_build_object('line_id',l,'received_quantity',5),jsonb_build_object('line_id',l2,'received_quantity',4)),'Shared receipt',false);
 update stock_movements set stock_history_recorded_at=receipt_at where transfer_request_id=r and movement_type='transfer_receipt';
 update stock_history_inventory_changes set occurred_at=receipt_at where location_key='store:'||dest and product_id in (p,p2);
 update transfer_requests set received_at=receipt_at where id=r;
 f:=jsonb_build_object('from',day0,'to',day0,'products',jsonb_build_array(p),'locations',jsonb_build_array('store:'||a));
 x:=stock_history_table(f)->'rows'->0;
 if x->>'opening_balance' is distinct from '100' or x->>'outbound' is distinct from '2' or x->>'inbound' is distinct from '0'
  or x->>'closing_balance' is distinct from '98' or x->>'in_transit_outgoing' is distinct from '2' then raise exception 'Dispatch/source/as-of transit failed: %',x;end if;
 x:=stock_history_table(f||jsonb_build_object('locations',jsonb_build_array('store:'||dest)))->'rows'->0;
 if x->>'opening_balance' is distinct from '0' or x->>'inbound' is distinct from '0' or x->>'closing_balance' is distinct from '0'
  or x->>'in_transit_incoming' is distinct from '5' then raise exception 'Dispatch prematurely counted destination receipt: %',x;end if;
 x:=stock_history_table(f||jsonb_build_object('from',day0+1,'to',day0+1,'locations',jsonb_build_array('store:'||dest)))->'rows'->0;
 if x->>'opening_balance' is distinct from '0' or x->>'inbound' is distinct from '5' or x->>'closing_balance' is distinct from '5'
  or x->>'in_transit_incoming' is distinct from '0' then raise exception 'Midnight receipt counted in wrong Singapore period: %',x;end if;
 x:=stock_history_page(f||jsonb_build_object('products',jsonb_build_array(p,p2),'locations',jsonb_build_array('store:'||a,'store:'||b),
  'people',jsonb_build_array(own,staff),'types',jsonb_build_array('transfer_dispatch','transfer_receipt'),'search','Split Product'));
 if x->>'total' is distinct from '2' then raise exception 'Multiple values OR, fields AND or readable search failed: %',x;end if;
 insert into history_lifecycle_ids values('owner',own),('staff',staff),('a',a),('b',b),('dest',dest),('p',p),('p2',p2),('request',r),('line',l),('otherline',l2);
 raise notice 'PASS: real split dispatch and receipt, SG midnight, cross-period actual balances, end-date incoming/outgoing transit, OR-within/AND-across filters';
end $$;
set local role authenticated;
select set_config('request.jwt.claim.sub',(select id::text from history_lifecycle_ids where key='staff'),true);
do $$ declare r uuid; x jsonb; f jsonb:=jsonb_build_object('from',sg_today()-2,'to',sg_today());begin
 select id into r from history_lifecycle_ids where key='request';
 x:=stock_transfer_details(r);
 if jsonb_array_length(x->'lines')<>1 or x->'lines'->0->>'quantity' is distinct from '2'
  or jsonb_array_length(x->'lines'->0->'sources')<>1 or x::text like '%Private Source%' or x::text like '%Other Leg Product%' then raise exception 'Split details exposed unrelated leg: %',x;end if;
 if x->>'destination' is distinct from 'Counterpart Destination' or (x->'notes')::text not like '%Shared receipt%' then raise exception 'Authorized counterpart context missing';end if;
 if exists(select 1 from transfer_request_lines where transfer_request_id=r) then raise exception 'Raw API exposed whole-line allocation totals to source-only staff';end if;
 if (select count(*) from transfer_line_sources where line_id=(select id from history_lifecycle_ids where key='line'))<>1 then raise exception 'Raw sources API scope incorrect';end if;
 x:=stock_history_page(f);if x->>'total' is distinct from '1' or x->'rows'->0->>'quantity' is distinct from '2' then raise exception 'Source staff saw other split movements or counts: %',x;end if;
 x:=stock_history_table(f);
 if exists(select 1 from jsonb_array_elements(x->'rows') q where q->>'location_key'<>'store:'||(select id from history_lifecycle_ids where key='a')) then raise exception 'Summary/export leaked counterpart balance';end if;
 if exists(select 1 from report_transfers_in_transit()) or exists(select 1 from report_transfer_discrepancies()) or exists(select 1 from report_multi_source_stock_drift())
  or exists(select 1 from report_transfer_stock_integrity()) or exists(select 1 from report_transfer_receipts(sg_today()-10,sg_today())) or exists(select 1 from report_transfers_overdue(0)) then raise exception 'Legacy report exposed company data to staff';end if;
 if has_function_privilege(current_user,'public.stock_private_report_transfer_stock_integrity()','execute') then raise exception 'Private report callable by staff';end if;
 raise notice 'PASS: actual authenticated split-source scope for details, lines, quantities, notes, balances, counts, export queries and legacy report APIs';
end $$;
reset role;
-- Real pending edits and rejection retain request text, edit text and reasons.
do $$ declare own uuid; a uuid; p uuid; r uuid; x jsonb; wh uuid;begin
 select id into own from history_lifecycle_ids where key='owner';select id into a from history_lifecycle_ids where key='a';select id into p from history_lifecycle_ids where key='p';
 perform set_config('request.jwt.claim.sub',own::text,true);
 perform set_product_prices(a,p,10,10,'available');
 insert into warehouses(name,code) values('Legacy sourced warehouse','HL-W') returning id into wh;
 insert into warehouse_inventory(warehouse_id,product_id,current_qty) values(wh,p,20);
 perform set_config('request.jwt.claim.sub',(select id::text from history_lifecycle_ids where key='staff'),true);
 r:=(create_transfer_request('warehouse_to_store','warehouse',wh,'store',a,jsonb_build_array(jsonb_build_object('product_id',p,'quantity',1)),'Legacy sourced request')->>'id')::uuid;
 perform edit_transfer_request(r,(select version from transfer_requests where id=r),'Authorized legacy edit',p_lines=>jsonb_build_array(jsonb_build_object('product_id',p,'quantity',2)));
 begin
  perform edit_transfer_request(r,(select version from transfer_requests where id=r),'Too much',p_lines=>jsonb_build_array(jsonb_build_object('product_id',p,'quantity',1000)));
  raise exception 'Excessive request accepted';
 exception when others then if sqlerrm<>'Insufficient stock at the requested source. Ask a manager to review the allocation.' then raise;end if;end;
 r:=(create_staff_transfer_request(jsonb_build_array(jsonb_build_object('kind','product','product_id',p,'quantity',1)),'Original unchanged history',a)->>'id')::uuid;
 perform edit_transfer_request(r,(select version from transfer_requests where id=r),'Changed delivery plan',p_note=>'New request text');
 perform set_config('request.jwt.claim.sub',own::text,true);
 perform reject_transfer(r,'Delivery no longer required');
 x:=stock_transfer_details(r);
 if (x->'notes')::text not like '%Original unchanged history%' or (x->'notes')::text not like '%Changed delivery plan%'
  or (x->'notes')::text not like '%New request text%' or (x->'notes')::text not like '%Delivery no longer required%' then raise exception 'Edit/rejection history incomplete: %',x;end if;
 if (select count(*) from jsonb_array_elements(x->'notes') n where n->>'text' like '%Changed delivery plan%')<>1 then raise exception 'Edit audit duplicated by revision';end if;
 -- Simulate a legacy field with no reliable receipt author/time.
 update transfer_requests set receipt_note='Historical unattributed note',received_at=null,received_by=null where id=r;
 x:=stock_transfer_details(r);
 if not exists(select 1 from jsonb_array_elements(x->'notes') n where n->>'text'='Historical unattributed note' and n->>'author'='Author unavailable' and n->>'at' is null) then raise exception 'Invented historical attribution';end if;
 raise notice 'PASS: original request, edited request, edit reason and rejection history; deduplication and honest missing attribution';
end $$;
-- Existing sale/refund/cancellation writers feed observed sellable balances.
do $$ declare own uuid; a uuid; p uuid; c uuid; pm uuid; inv uuid; item uuid; payment uuid; sale uuid; adjustment uuid; f jsonb; x jsonb; y jsonb; before_in bigint; baseline bigint;
begin
 select id into own from history_lifecycle_ids where key='owner';select id into a from history_lifecycle_ids where key='a';
 perform set_config('request.jwt.claim.sub',own::text,true);
 insert into products(name,sku,product_type) values('Sellable Reporting','HL-SELL','own') returning id into p;
 insert into store_inventory(store_id,product_id,current_qty) values(a,p,100);
 update stock_history_inventory_changes set occurred_at=(sg_today()-1)::timestamp at time zone 'Asia/Singapore' where product_id=p;
 perform set_product_prices(a,p,10,10,'available');
 insert into customers(full_name,phone) values('History Customer','+6591237769') returning id into c;
 insert into payment_methods(name) values('History Cash') returning id into pm;
 inv:=create_invoice_with_details(a,c,jsonb_build_array(jsonb_build_object('kind','product','product_id',p,'quantity',10)),jsonb_build_object('business_date',sg_today()));
 perform pay_invoice(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',100)));
 select id into item from invoice_items where invoice_id=inv;select id into payment from invoice_payments where invoice_id=inv;
 select id into sale from stock_movements where invoice_id=inv and movement_type='store_sale';
 f:=jsonb_build_object('from',sg_today(),'to',sg_today(),'products',jsonb_build_array(p),'locations',jsonb_build_array('store:'||a));
 x:=stock_history_table(f)->'rows'->0;
 if x->>'opening_balance' is distinct from '100' or x->>'outbound' is distinct from '10' or x->>'closing_balance' is distinct from '90' then raise exception 'Sale report failed: %',x;end if;
 perform refund_invoice_recorded(inv,jsonb_build_array(jsonb_build_object('invoice_item_id',item,'amount',30)),
  jsonb_build_array(jsonb_build_object('payment_id',payment,'amount',30)),jsonb_build_array(jsonb_build_object('movement_id',sale,'sellable_quantity',1,'damaged_quantity',1,'not_returned_quantity',1)),
  'One sellable, one damaged, one not returned',gen_random_uuid());
 x:=stock_history_table(f)->'rows'->0;
 if x->>'inbound' is distinct from '1' or x->>'closing_balance' is distinct from '91' then raise exception 'Damaged/not-returned counted as sellable: %',x;end if;
 y:=stock_history_table(f||'{"types":["invoice_refund_return"]}')->'rows'->0;
 if y->>'inbound' is distinct from '1' or y->>'outbound' is distinct from '0' or y->>'opening_balance' is distinct from '100'
  or y->>'closing_balance' is distinct from '91' or y->>'other_movement_net' is distinct from '-10' then raise exception 'Filtered returns changed actual balances: %',y;end if;
 perform cancel_invoice_recorded(inv,'Cancel undelivered remainder',gen_random_uuid());
 perform record_stock_use('store',a,p,2,'Demonstration','Do not sell');
 adjustment:=request_inventory_adjustment('store',a,p,99,'Positive adjustment');perform resolve_inventory_adjustment(adjustment,true,'Verified count');
 adjustment:=request_inventory_adjustment('store',a,p,98,'Negative adjustment');perform resolve_inventory_adjustment(adjustment,true,'Verified count');
 x:=stock_history_table(f)->'rows'->0;
 if x->>'opening_balance' is distinct from '100' or x->>'inbound' is distinct from '11' or x->>'outbound' is distinct from '13'
  or x->>'closing_balance' is distinct from '98' or coalesce(x->>'warning','')<>'' then raise exception 'Sellable cancellation, stock use or adjustment reconciliation failed: %',x;end if;
 y:=stock_history_table(f||'{"search":"Stock use"}')->'rows'->0;
 if y->>'outbound' is distinct from '2' or y->>'closing_balance' is distinct from '98' or y->>'other_movement_net' is distinct from '0' then raise exception 'Text-filtered reconciliation failed: %',y;end if;
 -- Current evidence drift invalidates exact balances; it never repairs stock.
 delete from stock_history_inventory_changes where product_id=p and delta=-1;
 x:=stock_history_table(f)->'rows'->0;
 if x->>'opening_balance' is not null or x->>'closing_balance' is not null or x->>'warning' not like '%differs from the observation evidence%' then raise exception 'Missing observation evidence presented as exact balance: %',x;end if;
 if (select current_qty from store_inventory where store_id=a and product_id=p)<>98 then raise exception 'Reporting changed inventory';end if;
 raise notice 'PASS: actual sales, confirmed sellable refunds, damaged/not-returned exclusion, cancellation, stock use, positive/negative adjustments, filtered totals, drift flag without stock repair';
end $$;
do $$ declare p uuid; a uuid; own uuid; f jsonb; before_page jsonb; after_page jsonb; x jsonb;begin
 select id into p from history_lifecycle_ids where key='p';select id into a from history_lifecycle_ids where key='a';select id into own from history_lifecycle_ids where key='owner';
 perform set_config('request.jwt.claim.sub',own::text,true);
 f:=jsonb_build_object('from',sg_today(),'to',sg_today(),'products',jsonb_build_array(p),'locations',jsonb_build_array('store:'||a));
 before_page:=stock_history_page(f);
 insert into stock_movements(product_id,movement_type,from_store_id,quantity,notes,created_by,created_at)
 values(p,'transfer_dispatch',a,1,'Unlinked diagnostic fixture',own,'2000-01-01 00:00:00+00');
 after_page:=stock_history_page(f,100,0,(before_page->>'as_of')::timestamptz);
 if before_page->>'total' is distinct from after_page->>'total' then raise exception 'New backdated document changed frozen report paging';end if;
 if stock_history_page(f||'{"search":"Unlinked diagnostic fixture"}')->>'total' is distinct from '1' then raise exception 'New movement did not use actual record date';end if;
 x:=stock_history_table(f)->'rows'->0;
 if x->>'warning' not like '%no exact transfer link%' or x->>'warning' not like '%differ from linked movement totals%' then raise exception 'Unlinked/unrecorded effect not flagged: %',x;end if;
 raise notice 'PASS: stable cutoff excludes later inserts, actual record date handles backdated documents, unlinked and inventory-to-movement gaps are flagged';
end $$;
rollback;
