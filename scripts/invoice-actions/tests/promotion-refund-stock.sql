-- A promotion refunded or cancelled through Approvals lists the stock it took (361).
--
-- Before 361 the plan matched stock to a line's own product. A promotion line
-- names none, so its plan listed no stock, the approval window showed no
-- quantity fields, and the refund engine then refused the refund
-- ("Record the returned-and-sellable, damaged, or not-returned quantities").
--
-- Disposable database only; everything is rolled back.
begin;
do $$
declare own uuid:=gen_random_uuid(); tag text:=substr(md5(random()::text),1,6);
 st uuid; c uuid; pm uuid; pa uuid; pb uuid; pc uuid; promo uuid; child uuid;
 inv uuid; inv2 uuid; it2 uuid; plan jsonb; req jsonb; res jsonb; stock jsonb; n int; bad text;
begin
 insert into auth.users(id,email) values(own,'prs-'||tag||'@tests.invalid');
 insert into profiles(id,full_name,email,role) values(own,'Owner','prs-'||tag||'@tests.invalid','owner');
 perform set_config('request.jwt.claim.sub',own::text,true);
 insert into stores(name,code,country_code) values('PRS '||tag,'PRS'||tag,'SG') returning id into st;
 insert into customers(full_name,phone) values('PRS Buyer','+6598'||lpad((floor(random()*900000)+100000)::int::text,6,'0')) returning id into c;
 insert into payment_methods(name) values('PRS Visa '||tag) returning id into pm;
 insert into products(name,sku,product_type) values('PRS Mattress Pad','PRS-A-'||tag,'own') returning id into pa;
 insert into products(name,sku,product_type) values('PRS Pillow','PRS-B-'||tag,'own') returning id into pb;
 insert into products(name,sku,product_type) values('PRS Eye Mask','PRS-C-'||tag,'own') returning id into pc;
 insert into store_inventory(store_id,product_id,current_qty) values(st,pa,20),(st,pb,20),(st,pc,20);
 -- a sleeping-system package: two products, and a nested promotion holding a third
 insert into promotions(name,code) values('PRS Child '||tag,'PRS-CH-'||tag) returning id into child;
 insert into promotion_items(promotion_id,item_type,product_id,quantity) values(child,'product',pc,1);
 insert into promotions(name,code) values('PRS Sleeping System '||tag,'PRS-P-'||tag) returning id into promo;
 insert into promotion_items(promotion_id,item_type,product_id,quantity) values(promo,'product',pa,1),(promo,'product',pb,2);
 insert into promotion_items(promotion_id,item_type,child_promotion_id,quantity) values(promo,'promotion',child,1);
 insert into promotion_store_prices(promotion_id,store_id,selling_price) values(promo,st,3900);

 -- ---- the whole line refunded -----------------------------------------------
 inv:=create_invoice(st,c,null,jsonb_build_array(jsonb_build_object('kind','promotion','promotion_id',promo,'quantity',1)));
 perform record_invoice_payment(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',3900)),gen_random_uuid());
 select count(*) into n from stock_movements where invoice_id=inv and movement_type::text='store_sale';
 if n=0 then raise exception 'Fixture: the promotion took no stock'; end if;

 plan:=invoice_action_plan(inv,'refund_full');
 if jsonb_array_length(plan->'stock')<>n then
  raise exception 'The plan lists % stock rows for a promotion that took %: %', jsonb_array_length(plan->'stock'), n, plan->'stock'; end if;
 select string_agg(m.id::text, ',') into bad from stock_movements m
  where m.invoice_id=inv and m.movement_type::text='store_sale'
    and not exists (select 1 from jsonb_array_elements(plan->'stock') s
                     where s->>'movement_id'=m.id::text and (s->>'proposed_sellable')::int=m.quantity);
 if bad is not null then raise exception 'A movement is missing or not proposed back in full: %', bad; end if;

 -- the approver records the goods' condition and the refund goes through
 select jsonb_agg(jsonb_build_object('movement_id',s->>'movement_id',
          'sellable_quantity',(s->>'proposed_sellable')::int,'damaged_quantity',0,'not_returned_quantity',0))
   into stock from jsonb_array_elements(plan->'stock') s;
 req:=request_invoice_action_v2(inv,'refund_full','[]'::jsonb,'Changed her mind',null,gen_random_uuid());
 res:=resolve_invoice_action_v2((req->>'request_id')::uuid,true,'ok',null,'[]'::jsonb,stock,false);
 if res->>'status'<>'approved' then raise exception 'The promotion refund failed: %', res; end if;
 if (select count(*) from invoice_stock_dispositions d join stock_movements m on m.id=d.movement_id where m.invoice_id=inv)<>n then
  raise exception 'The goods'' condition was not recorded'; end if;
 if (select current_qty from store_inventory where store_id=st and product_id=pb)<>20 then
  raise exception 'The returned pillows did not go back into stock'; end if;

 -- ---- part of a line refunded -------------------------------------------------
 inv2:=create_invoice(st,c,null,jsonb_build_array(jsonb_build_object('kind','promotion','promotion_id',promo,'quantity',2)));
 perform record_invoice_payment(inv2,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',7800)),gen_random_uuid());
 select id into it2 from invoice_items where invoice_id=inv2;
 plan:=invoice_action_plan(inv2,'refund_partial',jsonb_build_array(jsonb_build_object('invoice_item_id',it2,'quantity',1)));
 select string_agg(m.id::text, ',') into bad from stock_movements m
  where m.invoice_id=inv2 and m.movement_type::text='store_sale'
    and not exists (select 1 from jsonb_array_elements(plan->'stock') s
                     where s->>'movement_id'=m.id::text and (s->>'proposed_sellable')::int=ceil(m.quantity/2.0)::int);
 if bad is not null then raise exception 'Refunding one of two packages did not propose half of each product: %', plan->'stock'; end if;

 -- ---- a cancellation now asks too ---------------------------------------------
 plan:=invoice_action_plan(inv2,'cancel');
 if jsonb_array_length(plan->'stock')=0 then raise exception 'Cancelling a promotion does not ask for the goods'' condition'; end if;

 raise notice 'PASS: a promotion line''s refund plan lists the stock of every product inside it (nested promotions included), each once, proposed back in full or in proportion; the approval records the goods'' condition and the refund goes through; cancelling asks for the condition too';
end $$;
rollback;
