-- Exclusive disposable database. Every fixture and simulated historical date rolls back.
begin;
grant usage on schema public,auth to authenticated;
grant select on public.stock_movements,public.warehouse_inventory,public.store_inventory,public.transfer_requests,public.transfer_request_lines,public.transfer_line_sources,public.transfer_request_revisions to authenticated;
create temp table stock_test_ids(key text primary key,id uuid);grant select on stock_test_ids to authenticated;
do $$
declare own uuid:=gen_random_uuid(); staff uuid:=gen_random_uuid(); empty_staff uuid:=gen_random_uuid(); other uuid:=gen_random_uuid(); a uuid; b uuid; c uuid; wh uuid; p uuid; p2 uuid; r uuid; line uuid; x jsonb; all_filters jsonb;
begin
 insert into auth.users(id,email) values(own,'stock-owner@test.invalid'),(staff,'stock-staff@test.invalid'),(empty_staff,'stock-empty@test.invalid'),(other,'stock-other@test.invalid');
 insert into profiles(id,full_name,email,role) values(own,'History Owner','stock-owner@test.invalid','owner'),(staff,'Assigned Staff','stock-staff@test.invalid','staff'),(empty_staff,'Unassigned Staff','stock-empty@test.invalid','staff'),(other,'Different Actor','stock-other@test.invalid','staff');
 perform set_config('request.jwt.claim.sub',own::text,true);
 insert into stores(name,code,country_code) values('Authorized Alpha','H-A','SG') returning id into a;
 insert into stores(name,code,country_code) values('Counterpart Beta','H-B','SG') returning id into b;
 insert into stores(name,code,country_code) values('Authorized Gamma','H-C','SG') returning id into c;
 insert into warehouses(name,code) values('Counterpart Warehouse','H-W') returning id into wh;
 insert into user_store_assignments(user_id,store_id) values(staff,a),(staff,c),(other,b);
 insert into products(name,sku,product_type) values('Searchable Socks','H-SOCK','own') returning id into p;
 insert into products(name,sku,product_type) values('Searchable Gloves','H-GLOVE','own') returning id into p2;
 perform set_product_prices(a,p,10,10,'available');perform set_product_prices(b,p,10,10,'available');perform set_product_prices(c,p,10,10,'available');
 insert into store_inventory(store_id,product_id,current_qty) values(a,p,20),(b,p,30),(c,p,10);
 insert into warehouse_inventory(warehouse_id,product_id,current_qty) values(wh,p,50);
 insert into stock_test_ids values('owner',own),('staff',staff),('empty',empty_staff),('a',a),('b',b),('c',c),('wh',wh),('p',p),('p2',p2),('other',other);
 -- Older-than-5000 result; same timestamp ties must still paginate by unique ID.
 insert into stock_movements(product_id,movement_type,from_store_id,to_store_id,quantity,notes,created_by,created_at,stock_history_recorded_at)
 values(p,'store_to_store',b,a,7,'Unique historical needle',other,'2020-02-03 05:00:00+00',null);
 insert into stock_movements(product_id,movement_type,to_store_id,quantity,notes,created_by,stock_history_recorded_at)
 select p,'inventory_adjustment',a,1,'Recent searchable rows '||n,own,now() from generate_series(1,5105) n;
 insert into stock_movements(product_id,movement_type,to_store_id,quantity,notes,created_by) values(p2,'inventory_adjustment',c,2,'Other assigned store',other);
 insert into stock_movements(product_id,movement_type,to_store_id,quantity,notes,created_by) values(p,'inventory_adjustment',b,999,'PRIVATE COUNTERPART ONLY',other);
 perform set_config('request.jwt.claim.sub',staff::text,true);
 r:=(create_staff_transfer_request(jsonb_build_array(jsonb_build_object('kind','product','product_id',p,'quantity',4)),'Requester original note',a)->>'id')::uuid;
 insert into stock_test_ids values('request',r);
 select id into line from transfer_request_lines where transfer_request_id=r;
 perform set_config('request.jwt.claim.sub',own::text,true);
 if (stock_transfer_details(r)->'notes')::text not like '%Requester original note%' then raise exception 'Owner review cannot see request note';end if;
 perform review_and_dispatch_transfer(r,jsonb_build_array(jsonb_build_object('line_id',line,'kind','product','product_id',p,'approved_quantity',4,'sources',jsonb_build_array(jsonb_build_object('source_type','warehouse','source_id',wh,'quantity',4)))),'Owner dispatch note');
 all_filters:=jsonb_build_object('from',sg_today(),'to',sg_today(),'products',jsonb_build_array(p),'locations',jsonb_build_array('store:'||a));
 x:=stock_history_table(all_filters);
 if ((x->'rows'->0)->>'in_transit_incoming')::int<>4 then raise exception 'Dispatch not counted as incoming transit: %',x;end if;
 if (select current_qty from store_inventory where store_id=a and product_id=p)<>20 then raise exception 'Dispatch added destination stock';end if;
 perform set_config('request.jwt.claim.sub',staff::text,true);
 if (stock_transfer_details(r)->'notes')::text not like '%Owner dispatch note%' then raise exception 'Receiving staff cannot see dispatch note';end if;
 perform receive_transfer(r,jsonb_build_array(jsonb_build_object('line_id',line,'received_quantity',3,'reason','One missing')),'Staff receipt discrepancy',false);
 perform set_config('request.jwt.claim.sub',own::text,true);
 perform resolve_transfer_discrepancy(r,jsonb_build_array(jsonb_build_object('line_id',line,'resolution','correct_source','reason','One remained at source')),'Owner resolution note');
 if (select note from transfer_requests where id=r)<>'Requester original note' then raise exception 'Approver overwrote requester note';end if;
 x:=stock_transfer_details(r);
 if (x->'notes')::text not like '%Staff receipt discrepancy%' or (x->'notes')::text not like '%One remained at source%' or (x->'notes')::text not like '%One missing%' then raise exception 'Shared notes omitted original receipt or resolution: %',x;end if;
 if (select count(*) from jsonb_array_elements(x->'notes') n where n->>'text'='Staff receipt discrepancy')<>1 then raise exception 'Duplicated receipt field/audit note';end if;
 if (stock_history_table(all_filters)->'rows'->0->>'in_transit_incoming')::int<>0 then raise exception 'Received transfer still in transit';end if;
 -- Complete observed baseline/deltas reconcile, independent of displayed history.
 update stock_history_observation set started_at=(sg_today()-1)::timestamp at time zone 'Asia/Singapore';
 x:=stock_history_table(all_filters);
 if (x->'rows'->0->>'opening_balance')::int+(x->'rows'->0->>'inbound')::int-(x->'rows'->0->>'outbound')::int<>(x->'rows'->0->>'closing_balance')::int then raise exception 'Observed stock equation failed: %',x;end if;
 if (x->'rows'->0->>'closing_balance')::int<>23 then raise exception 'Actual closing balance incorrect: %',x;end if;
 x:=stock_history_table(all_filters||jsonb_build_object('people',jsonb_build_array(other)));
 if (x->'rows'->0->>'closing_balance')::int<>23 or (x->'rows'->0->>'inbound')::int<>0 or (x->'rows'->0->>'other_movement_net')::int<>23 then raise exception 'Person filter corrupted actual balances: %',x;end if;
 x:=stock_history_table(all_filters||'{"from":"2000-01-01","to":"2000-01-02"}');
 if x->'rows'->0->>'opening_balance' is not null or x->'rows'->0->>'closing_balance' is not null or x->'rows'->0->>'warning' not like '%unknown%' then raise exception 'Invented historical balances: %',x;end if;
 raise notice 'PASS: exact transfer lifecycle, request/dispatch/receipt/resolution notes, observed balances, filtered reconciliation and unknown historical evidence';
end $$;
-- Exercise the real application role; definer functions must not bypass scope.
set local role authenticated;
select set_config('request.jwt.claim.sub',(select id::text from stock_test_ids where key='staff'),true);
do $$
declare f jsonb:=jsonb_build_object('from','1900-01-01','to',sg_today()); x jsonb; y jsonb; a uuid; b uuid; p uuid; count_rows int; term text; offset_rows int:=0; ids text[]:='{}'; cutoff timestamptz;
begin
 select id into a from stock_test_ids where key='a'; select id into b from stock_test_ids where key='b';select id into p from stock_test_ids where key='p';
 if exists(select 1 from stock_movements where notes='PRIVATE COUNTERPART ONLY') or exists(select 1 from warehouse_inventory) or exists(select 1 from store_inventory where store_id=b) then raise exception 'Direct table API leaked unauthorized balances/history';end if;
 if not exists(select 1 from stock_movements where notes='Unique historical needle') then raise exception 'Another actor assigned-store movement hidden';end if;
 if exists(select 1 from location_available_qty('store',b,p)) then raise exception 'Availability RPC leaked counterpart balance';end if;
 x:=stock_history_options('locations');
 if (x->>'total')::int<>2 or (x->'rows')::text like '%Counterpart%' then raise exception 'Filter options leaked counterpart';end if;
 x:=stock_history_page(f||'{"search":"Unique historical needle"}');
 if (x->>'total')::int<>1 or x->'rows'->0->>'from_name'<>'Counterpart Beta' then raise exception 'Old search/counterpart label failed: %',x;end if;
 if (stock_history_page(f||'{"search":"03/02/2020"}')->>'total')::int<>1 or (stock_history_page(f||'{"search":"2020-02-03"}')->>'total')::int<>1 then raise exception 'Date search lost supported formats';end if;
 foreach term in array array['Searchable Socks','H-SOCK','Counterpart Beta','Authorized Alpha','Different Actor','store_to_store','Store → Store','Unique historical needle','7'] loop
  if stock_history_page(jsonb_build_object('from','2020-02-03','to','2020-02-03','search',term))->>'total' is distinct from '1' then raise exception 'Search field lost: %',term;end if;
 end loop;
 if (stock_history_page(f||jsonb_build_object('products',jsonb_build_array(p),'locations',jsonb_build_array('store:'||a),'types',jsonb_build_array('store_to_store'),'people',jsonb_build_array((select id from stock_test_ids where key='other'))))->>'total')::int<>1 then raise exception 'Filters did not combine AND/OR correctly';end if;
 x:=stock_history_page(f,100,0);y:=stock_history_page(f,100,100,(x->>'as_of')::timestamptz);
 if exists(select 1 from jsonb_array_elements(x->'rows') l join jsonb_array_elements(y->'rows') r on l->>'id'=r->>'id') then raise exception 'Pagination duplicated tied-date movements';end if;
 cutoff:=(x->>'as_of')::timestamptz;count_rows:=(x->>'total')::int;
 loop
  y:=stock_history_page(f,1000,offset_rows,cutoff);
  if (y->>'total')::int<>count_rows then raise exception 'Paged count changed';end if;
  ids:=ids||array(select n->>'id' from jsonb_array_elements(y->'rows') n);
  offset_rows:=offset_rows+jsonb_array_length(y->'rows');exit when offset_rows>=count_rows;
  if jsonb_array_length(y->'rows')=0 then raise exception 'Empty page before full count';end if;
 end loop;
 if cardinality(ids)<>count_rows or (select count(distinct v) from unnest(ids) v)<>count_rows or count_rows<5105 then raise exception 'Full permission-scoped export paging omitted or duplicated records';end if;
 if (stock_history_page(f||'{"search":"Other assigned store"}')->>'total')::int<>1 then raise exception 'Multiple assignments missing';end if;
 begin perform stock_history_table(f||jsonb_build_object('locations',jsonb_build_array('store:'||b)));raise exception 'Unauthorized location accepted';exception when others then if sqlerrm not like '%no longer available%' then raise;end if;end;
 if (select count(*) from search_stock_movements('PRIVATE COUNTERPART ONLY'))<>0 then raise exception 'Legacy search leaked unauthorized record';end if;
 if (select count(*) from transfer_request_revisions)<>0 then raise exception 'Raw revision leaked other source legs';end if;
 if (stock_transfer_details((select id from stock_test_ids where key='request'))->'notes')::text not like '%One remained at source%' then raise exception 'Staff cannot see resolution';end if;
 raise notice 'PASS: actual authenticated role, all actors, multiple assignments, counterpart names without balances, old search, direct APIs, counts, filter scope and stable paging';
end $$;
select set_config('request.jwt.claim.sub',(select id::text from stock_test_ids where key='empty'),true);
do $$ declare f jsonb:=jsonb_build_object('from','1900-01-01','to',sg_today());x jsonb;begin
 x:=stock_history_page(f);if (x->>'has_access')::boolean or (x->>'total')::int<>0 then raise exception 'Unassigned staff received company history';end if;
 if (stock_history_options('people')->>'total')::int<>0 or (stock_history_table(f)->>'total')::int<>0 then raise exception 'Unassigned staff received filters or summary';end if;
 begin perform stock_transfer_details((select id from stock_test_ids where key='request'));raise exception 'Unauthorized notes returned';exception when others then if sqlerrm not like '%not available%' then raise;end if;end;
 raise notice 'PASS: no-assignment state, empty counts/options/balances and inaccessible notes';
end $$;
reset role;
do $$ declare own uuid; role_name text; role_user uuid;begin
 select id into own from stock_test_ids where key='owner';
 perform set_config('request.jwt.claim.sub',own::text,true);
 foreach role_name in array array['owner','admin','manager','inventory_manager'] loop
  perform set_config('request.jwt.claim.sub',own::text,true);role_user:=gen_random_uuid();
  insert into auth.users(id,email) values(role_user,'history-'||role_name||'@test.invalid');
  insert into profiles(id,full_name,email,role) values(role_user,'Role access fixture','history-'||role_name||'@test.invalid',role_name::user_role);
  perform set_config('request.jwt.claim.sub',role_user::text,true);
  if stock_history_page(jsonb_build_object('from','1900-01-01','to',sg_today(),'search','PRIVATE COUNTERPART ONLY'))->>'total' is distinct from '1'
   or stock_history_options('locations')->>'total' is distinct from '4' then raise exception 'Established management read scope lost for %',role_name;end if;
 end loop;
 raise notice 'PASS: Owner, Admin, Manager and Inventory Manager retain global report and filter access';
end $$;
rollback;
