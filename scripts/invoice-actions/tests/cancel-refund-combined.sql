-- Cancellation and refund together, and apart.
--
-- 295 derived a FRESH refund plan during execution and then overwrote the
-- refund's result with the cancellation's, so an approver confirmed a plan
-- describing no money while money moved, and was told only about the
-- cancellation. It also collected stock conditions and discarded them, leaving
-- restore_invoice_stock() to put every outstanding unit back as sellable.
-- Disposable database only; everything is rolled back.
begin;
do $$
declare own uuid:=gen_random_uuid(); stf uuid:=gen_random_uuid();
 st uuid; c uuid; pm uuid; p uuid; inv uuid; req jsonb; res jsonb; plan jsonb;
 it uuid; pay uuid; mv jsonb; s text; q int; n numeric; mvid uuid;
begin
 insert into auth.users(id,email) values(own,'cr-own@tests.invalid'),(stf,'cr-stf@tests.invalid');
 insert into profiles(id,full_name,email,role) values
   (own,'Owner','cr-own@tests.invalid','owner'),(stf,'Staff','cr-stf@tests.invalid','staff');
 perform set_config('request.jwt.claim.sub',own::text,true);
 insert into stores(name,code,country_code) values('CR Store','CRS','SG') returning id into st;
 insert into user_store_assignments(user_id,store_id) values(stf,st);
 insert into customers(full_name,phone) values('CR Buyer','+6598886001') returning id into c;
 insert into payment_methods(name,is_active) values('CR PayNow',true) returning id into pm;
 insert into products(name,sku,product_type) values('CR Item','CRI','own') returning id into p;
 insert into store_inventory(store_id,product_id,current_qty) values(st,p,100);
 perform set_product_prices(st,p,100,100,'available');

 -- ---- 1. UNPAID cancellation records no money ---------------------------
 inv:=create_invoice_with_details(st,c,jsonb_build_array(jsonb_build_object('kind','product','product_id',p,'quantity',1)),
   jsonb_build_object('business_date',sg_today()::text));
 plan:=invoice_action_plan(inv,'cancel');
 if (plan->>'refund_due')::numeric<>0 then raise exception 'Unpaid cancellation shows money due: %',plan->>'refund_due'; end if;
 perform set_config('request.jwt.claim.sub',stf::text,true);
 req:=request_invoice_action_v2(inv,'cancel','[]'::jsonb,'Raised by mistake',null,gen_random_uuid());
 perform set_config('request.jwt.claim.sub',own::text,true);
 select movement_id into mvid from jsonb_to_recordset(invoice_action_plan(inv,'cancel')->'stock') as t(movement_id uuid) limit 1;
 res:=resolve_invoice_action_v2((req->>'request_id')::uuid,true,'Agreed',null,'[]'::jsonb,
   jsonb_build_array(jsonb_build_object('movement_id',mvid,'sellable_quantity',1,'damaged_quantity',0,'not_returned_quantity',0)),false);
 if coalesce((res->>'refund_recorded')::boolean,false) then raise exception 'An unpaid cancellation claimed a refund'; end if;
 if exists(select 1 from invoice_refunds where invoice_id=inv) then raise exception 'An unpaid cancellation wrote a refund row'; end if;
 if (select status from invoices where id=inv)<>'cancelled' then raise exception 'Not cancelled'; end if;
 if (select current_qty from store_inventory where store_id=st and product_id=p)<>100 then
  raise exception 'Goods returned once and only once: expected 100, got %',(select current_qty from store_inventory where store_id=st and product_id=p); end if;

 -- ---- 2. PAID cancellation, money returned now ---------------------------
 inv:=create_invoice_with_details(st,c,jsonb_build_array(jsonb_build_object('kind','product','product_id',p,'quantity',2)),
   jsonb_build_object('business_date',sg_today()::text));
 perform record_invoice_payment(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',200)),gen_random_uuid());
 plan:=invoice_action_plan(inv,'cancel');
 -- The reviewed plan must describe the money, not hide it.
 if (plan->>'refund_due')::numeric<>200 then raise exception 'Cancel plan must show the 200 due, got %',plan->>'refund_due'; end if;
 if jsonb_array_length(plan->'sources')=0 then raise exception 'Cancel plan must show how the money goes back'; end if;
 if jsonb_array_length(plan->'lines')=0 then raise exception 'Cancel plan must show the lines it covers'; end if;
 perform set_config('request.jwt.claim.sub',stf::text,true);
 req:=request_invoice_action_v2(inv,'cancel','[]'::jsonb,'Customer pulled out',null,gen_random_uuid());
 perform set_config('request.jwt.claim.sub',own::text,true);
 select movement_id into mvid from jsonb_to_recordset(plan->'stock') as t(movement_id uuid) limit 1;
 res:=resolve_invoice_action_v2((req->>'request_id')::uuid,true,'Refunded at the counter',null,'[]'::jsonb,
   jsonb_build_array(jsonb_build_object('movement_id',mvid,'sellable_quantity',2,'damaged_quantity',0,'not_returned_quantity',0)),true);
 -- BOTH outcomes come back, separately.
 if not coalesce((res->>'refund_recorded')::boolean,false) then raise exception 'The refund was not reported'; end if;
 if (res->>'refunded_amount')::numeric<>200 then raise exception 'Expected 200 refunded, got %',res->>'refunded_amount'; end if;
 if res->'cancellation' is null then raise exception 'The cancellation was not reported'; end if;
 if res->'refund' is null then raise exception 'The refund result was overwritten by the cancellation'; end if;
 if (select status from invoices where id=inv)<>'cancelled' then raise exception 'Not cancelled'; end if;
 if (select count(*) from invoice_refunds where invoice_id=inv)=0 then raise exception 'No refund row written'; end if;
 if (select current_qty from store_inventory where store_id=st and product_id=p)<>100 then
  raise exception 'Stock returned twice or not at all: %',(select current_qty from store_inventory where store_id=st and product_id=p); end if;

 -- ---- 3. Cancellation leaving REFUND DUE, paid later ---------------------
 inv:=create_invoice_with_details(st,c,jsonb_build_array(jsonb_build_object('kind','product','product_id',p,'quantity',1)),
   jsonb_build_object('business_date',sg_today()::text));
 perform record_invoice_payment(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',100)),gen_random_uuid());
 perform set_config('request.jwt.claim.sub',stf::text,true);
 req:=request_invoice_action_v2(inv,'cancel','[]'::jsonb,'Bank transfer to follow',null,gen_random_uuid());
 perform set_config('request.jwt.claim.sub',own::text,true);
 select movement_id into mvid from jsonb_to_recordset(invoice_action_plan(inv,'cancel')->'stock') as t(movement_id uuid) limit 1;
 res:=resolve_invoice_action_v2((req->>'request_id')::uuid,true,'Money goes back on Friday',null,'[]'::jsonb,
   jsonb_build_array(jsonb_build_object('movement_id',mvid,'sellable_quantity',1,'damaged_quantity',0,'not_returned_quantity',0)),false);
 if coalesce((res->>'refund_recorded')::boolean,false) then
  raise exception 'A refund was claimed when the money had not gone back'; end if;
 if (res->>'refund_still_due')::numeric<>100 then
  raise exception 'Refund due must be reported for follow-up, got %',res->>'refund_still_due'; end if;
 if exists(select 1 from invoice_refunds where invoice_id=inv) then
  raise exception 'Refund due wrote a refund row'; end if;
 -- the money is still visibly held, so the follow-up is not lost
 if (select (invoice_financial_position(inv)->>'refund_due')::numeric)<>100 then
  raise exception 'The invoice no longer shows the money owed back'; end if;

 -- ---- 4. Damaged goods during cancellation never return to sale ----------
 inv:=create_invoice_with_details(st,c,jsonb_build_array(jsonb_build_object('kind','product','product_id',p,'quantity',4)),
   jsonb_build_object('business_date',sg_today()::text));
 perform record_invoice_payment(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',400)),gen_random_uuid());
 q:=(select current_qty from store_inventory where store_id=st and product_id=p);
 perform set_config('request.jwt.claim.sub',stf::text,true);
 req:=request_invoice_action_v2(inv,'cancel','[]'::jsonb,'Two came back broken',null,gen_random_uuid());
 perform set_config('request.jwt.claim.sub',own::text,true);
 select movement_id into mvid from jsonb_to_recordset(invoice_action_plan(inv,'cancel')->'stock') as t(movement_id uuid) limit 1;
 res:=resolve_invoice_action_v2((req->>'request_id')::uuid,true,'Two broken, one kept',null,'[]'::jsonb,
   jsonb_build_array(jsonb_build_object('movement_id',mvid,'sellable_quantity',1,'damaged_quantity',2,'not_returned_quantity',1)),false);
 if (select current_qty from store_inventory where store_id=st and product_id=p)<>q+1 then
  raise exception 'Only the one good unit may return to sale: expected %, got %',q+1,
    (select current_qty from store_inventory where store_id=st and product_id=p); end if;
 if (select coalesce(sum(damaged_quantity),0) from invoice_stock_dispositions where invoice_id=inv)<>2 then
  raise exception 'Damaged units were not tracked separately'; end if;
 if (select coalesce(sum(not_returned_quantity),0) from invoice_stock_dispositions where invoice_id=inv)<>1 then
  raise exception 'Not-returned units were not tracked separately'; end if;

 -- ---- 5. Cancellation AFTER a partial refund -----------------------------
 inv:=create_invoice_with_details(st,c,jsonb_build_array(jsonb_build_object('kind','product','product_id',p,'quantity',3)),
   jsonb_build_object('business_date',sg_today()::text));
 perform record_invoice_payment(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',300)),gen_random_uuid());
 select id into it from invoice_items where invoice_id=inv;
 select id into pay from invoice_payments where invoice_id=inv;
 select jsonb_build_array(jsonb_build_object('movement_id',id,'sellable_quantity',1)) into mv
   from stock_movements where invoice_id=inv and movement_type='store_sale' limit 1;
 perform refund_invoice_recorded(inv,jsonb_build_array(jsonb_build_object('invoice_item_id',it,'amount',100)),
   jsonb_build_array(jsonb_build_object('payment_id',pay,'amount',100)),mv,'One returned early',gen_random_uuid());
 plan:=invoice_action_plan(inv,'cancel');
 if (plan->>'refund_due')::numeric<>200 then
  raise exception 'Cancellation after a partial refund must offer only the remaining 200, got %',plan->>'refund_due'; end if;
 perform set_config('request.jwt.claim.sub',stf::text,true);
 req:=request_invoice_action_v2(inv,'cancel','[]'::jsonb,'Rest cancelled',null,gen_random_uuid());
 perform set_config('request.jwt.claim.sub',own::text,true);
 select movement_id into mvid from jsonb_to_recordset(plan->'stock') as t(movement_id uuid) limit 1;
 res:=resolve_invoice_action_v2((req->>'request_id')::uuid,true,'Rest returned',null,'[]'::jsonb,
   jsonb_build_array(jsonb_build_object('movement_id',mvid,'sellable_quantity',2,'damaged_quantity',0,'not_returned_quantity',0)),true);
 if (res->>'refunded_amount')::numeric<>200 then
  raise exception 'Expected the remaining 200, got %',res->>'refunded_amount'; end if;
 n:=(select sum(amount) from invoice_refunds where invoice_id=inv);
 if n<>300 then raise exception 'Total refunded across both actions must be 300, got %',n; end if;
 if (select (invoice_financial_position(inv)->>'net_received')::numeric)<>0 then
  raise exception 'Money still shows as held after everything went back'; end if;

 raise notice 'PASS: unpaid cancellation writes no refund; the reviewed cancel plan describes the money; both outcomes are returned separately; refund due is reported for follow-up; damaged and unreturned goods stay out of sale; cancellation after a partial refund offers only what is left; stock returns exactly once';
end $$;
rollback;
