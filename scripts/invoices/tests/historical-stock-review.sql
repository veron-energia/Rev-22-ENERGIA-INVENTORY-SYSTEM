-- Changing the store on an invoice that predates stock snapshots.
--
-- Reproduces the reported failure, then walks the review path that resolves it,
-- and holds the line where evidence genuinely is not on record.
-- Disposable database only; everything is rolled back.
begin;
do $$
declare o uuid:=gen_random_uuid(); mgr uuid:=gen_random_uuid(); staff uuid:=gen_random_uuid();
 st uuid; st2 uuid; c uuid; pm uuid; v uuid; p uuid; promo uuid;
 inv uuid; pinv uuid; x jsonb; r jsonb; it uuid; n integer;
begin
 insert into auth.users(id,email) values(o,'hs-owner@tests.invalid'),(staff,'hs-staff@tests.invalid');
 insert into profiles(id,full_name,email,role) values
   (o,'Owner','hs-owner@tests.invalid','owner'),(staff,'Staff','hs-staff@tests.invalid','staff');
 perform set_config('request.jwt.claim.sub',o::text,true);
 insert into stores(name,code,country_code) values('HS Origin','HSO','SG') returning id into st;
 insert into stores(name,code,country_code) values('HS Dest','HSD','SG') returning id into st2;
 insert into user_store_assignments(user_id,store_id) values(staff,st),(staff,st2);
 insert into customers(full_name,phone) values('HS Buyer','+6597770001') returning id into c;
 insert into payment_methods(name,is_active) values('HS Cash',true) returning id into pm;
 insert into vouchers(name,code,voucher_kind,selling_price,qty_type)
   values('HS Voucher','HSV','normal',40,'limited') returning id into v;
 insert into voucher_store_stock(voucher_id,store_id,current_qty) values(v,st,10),(v,st2,10);
 insert into voucher_store_prices(voucher_id,store_id,selling_price,available_at_store)
   values(v,st,40,true),(v,st2,40,true);

 -- ---------------------------------------------------------------
 -- 1. The reported failure, on a voucher invoice with no snapshot.
 -- ---------------------------------------------------------------
 inv:=create_invoice(st,c,null,jsonb_build_array(jsonb_build_object('kind','voucher','voucher_id',v,'quantity',1)));
 perform pay_invoice(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',40)));
 update invoices set stock_snapshot_version=null where id=inv;
 delete from invoice_stock_components where invoice_item_id in (select id from invoice_items where invoice_id=inv);
 x:=(select jsonb_agg(jsonb_build_object('invoice_item_id',id,'kind',line_kind::text,'voucher_id',voucher_id,
      'quantity',quantity,'unit_price',unit_price)) from invoice_items where invoice_id=inv);
 begin
  perform correct_invoice(inv,x,jsonb_build_object('store_id',st2),'Move store',gen_random_uuid());
  raise exception 'Store change succeeded without a snapshot';
 exception when others then
  if sqlerrm like 'Store change succeeded%' then raise; end if;
  if sqlerrm not like '%Historical component snapshots need review%' then
   raise exception 'Unexpected refusal: %', sqlerrm; end if; end;

 -- Metadata still corrects, exactly as the message promises.
 perform correct_invoice(inv,x,'{"notes":"Metadata only"}','Note',gen_random_uuid());

 -- The pre-177 defect this uncovered: required stock used to raise a type
 -- error for any invoice with no snapshot.
 select count(*) into n from invoice_required_stock(inv);
 if n<1 then raise exception 'Required stock returned nothing for a historical invoice'; end if;

 -- ---------------------------------------------------------------
 -- 2. The preview says what is wrong before anyone saves.
 -- ---------------------------------------------------------------
 r:=invoice_store_change_preview(inv,st2);
 if not (r->>'review_required')::boolean then raise exception 'Preview did not flag the review'; end if;
 if not (r->>'blocked')::boolean then raise exception 'Preview did not mark the change blocked'; end if;
 if r->'from_store'->>'id'<>st::text or r->'to_store'->>'id'<>st2::text then
  raise exception 'Preview named the wrong stores'; end if;

 -- ---------------------------------------------------------------
 -- 3. Evidence, review and resumption.
 -- ---------------------------------------------------------------
 if (select evidence_status from invoice_stock_component_evidence(inv) limit 1)<>'reconstructable' then
  raise exception 'A voucher line should be reconstructable from its own record'; end if;

 -- Staff cannot rebuild.
 perform set_config('request.jwt.claim.sub',staff::text,true);
 begin
  perform rebuild_invoice_stock_components(inv,'Trying','[]'::jsonb,gen_random_uuid());
  raise exception 'Staff rebuilt a historical snapshot';
 exception when others then
  if sqlerrm like 'Staff rebuilt%' then raise; end if;
  if sqlerrm not like '%Owner or Manager%' then raise; end if; end;
 perform set_config('request.jwt.claim.sub',o::text,true);

 -- A reason is required.
 begin
  perform rebuild_invoice_stock_components(inv,'   ','[]'::jsonb,gen_random_uuid());
  raise exception 'Rebuild accepted without a reason';
 exception when others then
  if sqlerrm like 'Rebuild accepted%' then raise; end if;
  if sqlerrm not like '%reason is required%' then raise; end if; end;

 r:=rebuild_invoice_stock_components(inv,'Reviewed against the original record','[]'::jsonb,gen_random_uuid());
 if (r->>'component_rows')::int<>1 then raise exception 'Rebuild recorded the wrong number of components'; end if;
 if (select stock_snapshot_version from invoices where id=inv) is null then
  raise exception 'Rebuild left the invoice without a snapshot version'; end if;
 if not exists(select 1 from invoice_stock_component_rebuilds where invoice_id=inv) then
  raise exception 'Rebuild was not recorded with its provenance'; end if;
 if not exists(select 1 from audit_logs where table_name='invoices' and action='stock_components_rebuilt') then
  raise exception 'Rebuild was not audited'; end if;

 -- The correction now goes through the ordinary protected path.
 perform correct_invoice(inv,x,jsonb_build_object('store_id',st2),'Move store after review',gen_random_uuid());
 if (select store_id from invoices where id=inv)<>st2 then raise exception 'Store did not change after review'; end if;
 -- Saved price and payment history survive it.
 if (select unit_price from invoice_items where invoice_id=inv)<>40 then
  raise exception 'Store correction repriced the line'; end if;
 if (select count(*) from invoice_payments where invoice_id=inv)<>1 then
  raise exception 'Store correction disturbed the payment history'; end if;

 -- Rebuilding again is a no-op, and a replayed request returns its first result.
 r:=rebuild_invoice_stock_components(inv,'Again','[]'::jsonb,gen_random_uuid());
 if not coalesce((r->>'unchanged')::boolean,false) then raise exception 'Second rebuild was not a no-op'; end if;

 -- ---------------------------------------------------------------
 -- 4. A promotion whose fixed contents are not on record.
 -- ---------------------------------------------------------------
 insert into products(name,sku,product_type) values('HS Product','HSP','own') returning id into p;
 insert into store_inventory(store_id,product_id,current_qty) values(st,p,20),(st2,p,20);
 perform set_product_prices(st,p,30,30,'available');
 perform set_product_prices(st2,p,30,30,'available');
 insert into promotions(name,code,promo_type,fixed_price,is_active) values('HS Promo','HSPR','bundle',30,true) returning id into promo;
 insert into promotion_items(promotion_id,item_type,product_id,quantity) values(promo,'product',p,1);
 insert into promotion_store_prices(promotion_id,store_id,selling_price,available_at_store) values(promo,st,30,true),(promo,st2,30,true);
 pinv:=create_invoice(st,c,null,jsonb_build_array(jsonb_build_object('kind','promotion','promotion_id',promo,'quantity',1)));
 perform pay_invoice(pinv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',30)));
 update invoices set stock_snapshot_version=null where id=pinv;
 delete from invoice_stock_components where invoice_item_id in (select id from invoice_items where invoice_id=pinv);

 select invoice_item_id into it from invoice_stock_component_evidence(pinv) limit 1;
 if (select evidence_status from invoice_stock_component_evidence(pinv) limit 1)<>'needs_confirmation' then
  raise exception 'A promotion with fixed contents should need confirmation, not silent reconstruction'; end if;

 -- Without confirmation it refuses, naming the line.
 begin
  perform rebuild_invoice_stock_components(pinv,'No confirmation','[]'::jsonb,gen_random_uuid());
  raise exception 'Promotion rebuilt without confirming its historical contents';
 exception when others then
  if sqlerrm like 'Promotion rebuilt%' then raise; end if;
  if sqlerrm not like '%still need evidence%' then raise; end if; end;

 -- With explicit confirmation it proceeds.
 r:=rebuild_invoice_stock_components(pinv,'Reviewed against the paper record',
      jsonb_build_array(jsonb_build_object('invoice_item_id',it,'confirmed',true)),gen_random_uuid());
 if (r->>'component_rows')::int<1 then raise exception 'Confirmed promotion rebuilt no components'; end if;
 if (select jsonb_array_length(confirmed_lines) from invoice_stock_component_rebuilds where invoice_id=pinv)<>1 then
  raise exception 'The confirmation was not recorded'; end if;

 x:=(select jsonb_agg(jsonb_build_object('invoice_item_id',id,'kind',line_kind::text,'promotion_id',promotion_id,
      'quantity',quantity,'unit_price',unit_price)) from invoice_items where invoice_id=pinv);
 perform correct_invoice(pinv,x,jsonb_build_object('store_id',st2),'Move store after review',gen_random_uuid());
 if (select store_id from invoices where id=pinv)<>st2 then raise exception 'Promotion invoice store did not change'; end if;

 -- ---------------------------------------------------------------
 -- 5. A line nothing on record answers stays refused, and says which.
 -- ---------------------------------------------------------------
 declare
  gpromo uuid; ginv uuid; gitem uuid; gstatus text; gmissing text;
 begin
  -- A promotion with no stock contents today and no recorded choices: there is
  -- simply no evidence of what it consumed.
  insert into promotions(name,code,promo_type,fixed_price,is_active)
   values('HS Empty Promo','HSEP','bundle',25,true) returning id into gpromo;
  insert into promotion_store_prices(promotion_id,store_id,selling_price,available_at_store)
   values(gpromo,st,25,true),(gpromo,st2,25,true);
  ginv:=create_invoice(st,c,null,jsonb_build_array(jsonb_build_object('kind','promotion','promotion_id',gpromo,'quantity',1)));
  perform pay_invoice(ginv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',25)));
  update invoices set stock_snapshot_version=null where id=ginv;
  delete from invoice_stock_components where invoice_item_id in (select id from invoice_items where invoice_id=ginv);

  select invoice_item_id, evidence_status, missing into gitem, gstatus, gmissing
    from invoice_stock_component_evidence(ginv) limit 1;
  if gstatus<>'missing' then
   raise exception 'A promotion with no contents and no choices should read as missing, not %', gstatus; end if;
  if gmissing is null then raise exception 'A missing line must say what is missing'; end if;

  -- It cannot be confirmed away: there is nothing to confirm.
  begin
   perform rebuild_invoice_stock_components(ginv,'Try anyway',
     jsonb_build_array(jsonb_build_object('invoice_item_id',gitem,'confirmed',true)),gen_random_uuid());
   raise exception 'A line with no evidence was rebuilt on a confirmation alone';
  exception when others then
   if sqlerrm like 'A line with no evidence%' then raise; end if;
   if sqlerrm not like '%still need evidence%' then raise; end if; end;

  if (select stock_snapshot_version from invoices where id=ginv) is not null then
   raise exception 'A refused rebuild still stamped the invoice'; end if;
  if exists(select 1 from invoice_stock_component_rebuilds where invoice_id=ginv) then
   raise exception 'A refused rebuild left a provenance row behind'; end if;

  -- And the store change stays refused.
  begin
   perform correct_invoice(ginv,(select jsonb_agg(jsonb_build_object('invoice_item_id',id,'kind',line_kind::text,
     'promotion_id',promotion_id,'quantity',quantity,'unit_price',unit_price)) from invoice_items where invoice_id=ginv),
     jsonb_build_object('store_id',st2),'Move store',gen_random_uuid());
   raise exception 'Store changed with no stock evidence at all';
  exception when others then
   if sqlerrm like 'Store changed with no stock%' then raise; end if;
   if sqlerrm not like '%Historical component snapshots need review%' then raise; end if; end;
 end;

 raise notice 'PASS: the reported store-change refusal reproduces; required stock works for historical invoices; evidence is reported per line; a reconstructable line rebuilds and the correction resumes; a promotion needs explicit confirmation; prices and payments survive; a line with no evidence at all stays refused and writes nothing';
end $$;
rollback;
