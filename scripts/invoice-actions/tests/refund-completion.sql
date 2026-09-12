-- What the invoice is left saying after a refund.
--
-- Reported on INV-2026-0212: the dialog reported a S$15 refund, but the invoice
-- behind it still read Paid / net S$15 / refunded S$0. These assertions check
-- the STORED outcome first, so a display fix is never mistaken for a money fix,
-- and then that the figures a reopened invoice would read are the new ones.
-- Disposable database only; everything is rolled back.
begin;
do $$
declare own uuid:=gen_random_uuid(); stf uuid:=gen_random_uuid();
 st uuid; c uuid; pm uuid; p uuid; inv uuid; req jsonb; res jsonb; pos jsonb; mvid uuid;
begin
 insert into auth.users(id,email) values(own,'rc-own@tests.invalid'),(stf,'rc-stf@tests.invalid');
 insert into profiles(id,full_name,email,role) values
   (own,'Owner','rc-own@tests.invalid','owner'),(stf,'Staff','rc-stf@tests.invalid','staff');
 perform set_config('request.jwt.claim.sub',own::text,true);
 insert into stores(name,code,country_code) values('RC Store','RCS','SG') returning id into st;
 insert into user_store_assignments(user_id,store_id) values(stf,st);
 insert into customers(full_name,phone) values('RC Buyer','+6598897001') returning id into c;
 insert into payment_methods(name,is_active) values('RC PayNow',true) returning id into pm;
 insert into products(name,sku,product_type) values('RC Item','RCI','own') returning id into p;
 insert into store_inventory(store_id,product_id,current_qty) values(st,p,100);
 perform set_product_prices(st,p,15,15,'available');

 -- ---- the reported case: a S$15 invoice, fully refunded -------------------
 inv:=create_invoice_with_details(st,c,jsonb_build_array(jsonb_build_object('kind','product','product_id',p,'quantity',1)),
   jsonb_build_object('business_date',sg_today()::text));
 perform record_invoice_payment(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',15)),gen_random_uuid());
 pos:=invoice_financial_position(inv);
 if (pos->>'net_received')::numeric<>15 or pos->>'status'<>'paid' then
  raise exception 'Fixture is not a paid S$15 invoice: %',pos; end if;

 req:=request_invoice_action_v2(inv,'refund_full','[]'::jsonb,'Customer returned it',null,gen_random_uuid());
 select movement_id into mvid from jsonb_to_recordset(invoice_action_plan(inv,'refund_full')->'stock') as t(movement_id uuid) limit 1;
 res:=resolve_invoice_action_v2((req->>'request_id')::uuid,true,'Refunded at the counter',null,'[]'::jsonb,
   jsonb_build_array(jsonb_build_object('movement_id',mvid,'sellable_quantity',1,'damaged_quantity',0,'not_returned_quantity',0)),false);
 if (res->>'refunded_amount')::numeric<>15 then
  raise exception 'The action reported % refunded, not 15',res->>'refunded_amount'; end if;

 -- The STORED state must support what the dialog said. This is the check that
 -- distinguishes "the screen was stale" from "the money never moved".
 pos:=invoice_financial_position(inv);
 if pos->>'status'<>'refunded' then
  raise exception 'Stored status is % — a fully refunded invoice must not still read paid',pos->>'status'; end if;
 if (pos->>'net_received')::numeric<>0 then
  raise exception 'Stored net payments held is %, not 0',pos->>'net_received'; end if;
 if (pos->>'refunded')::numeric<>15 then
  raise exception 'Stored refunded total is %, not 15',pos->>'refunded'; end if;
 -- and the original payment is still there: totals are not made to look right
 -- by deleting history.
 if (select count(*) from invoice_payments where invoice_id=inv and entry_kind<>'correction_reversal')<1 then
  raise exception 'The original payment was erased to make the totals balance'; end if;
 if (select coalesce(sum(amount),0) from invoice_refunds where invoice_id=inv)<>15 then
  raise exception 'No refund row was written'; end if;

 -- ---- a PARTIAL refund must not read as fully refunded --------------------
 perform set_product_prices(st,p,100,100,'available');
 inv:=create_invoice_with_details(st,c,jsonb_build_array(jsonb_build_object('kind','product','product_id',p,'quantity',3)),
   jsonb_build_object('business_date',sg_today()::text));
 perform record_invoice_payment(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',300)),gen_random_uuid());
 req:=request_invoice_action_v2(inv,'refund_partial',
   jsonb_build_array(jsonb_build_object('invoice_item_id',(select id from invoice_items where invoice_id=inv),'quantity',1)),
   'One came back',null,gen_random_uuid());
 select movement_id into mvid from jsonb_to_recordset(
   invoice_action_plan(inv,'refund_partial',jsonb_build_array(jsonb_build_object('invoice_item_id',(select id from invoice_items where invoice_id=inv),'quantity',1)))->'stock')
   as t(movement_id uuid) limit 1;
 res:=resolve_invoice_action_v2((req->>'request_id')::uuid,true,'One refunded',null,'[]'::jsonb,
   jsonb_build_array(jsonb_build_object('movement_id',mvid,'sellable_quantity',1,'damaged_quantity',0,'not_returned_quantity',0)),false);
 pos:=invoice_financial_position(inv);
 if pos->>'status'='refunded' then
  raise exception 'A partial refund left the invoice reading fully refunded'; end if;
 if (pos->>'refunded')::numeric<>100 then
  raise exception 'Partial refund total is %, not 100',pos->>'refunded'; end if;
 if (pos->>'net_received')::numeric<>200 then
  raise exception 'Net payments held after a partial refund is %, not 200',pos->>'net_received'; end if;

 -- ---- cancellation shows Cancelled and what is still owed back ------------
 inv:=create_invoice_with_details(st,c,jsonb_build_array(jsonb_build_object('kind','product','product_id',p,'quantity',1)),
   jsonb_build_object('business_date',sg_today()::text));
 perform record_invoice_payment(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',100)),gen_random_uuid());
 req:=request_invoice_action_v2(inv,'cancel','[]'::jsonb,'Customer pulled out',null,gen_random_uuid());
 select movement_id into mvid from jsonb_to_recordset(invoice_action_plan(inv,'cancel')->'stock') as t(movement_id uuid) limit 1;
 res:=resolve_invoice_action_v2((req->>'request_id')::uuid,true,'Money follows on Friday',null,'[]'::jsonb,
   jsonb_build_array(jsonb_build_object('movement_id',mvid,'sellable_quantity',1,'damaged_quantity',0,'not_returned_quantity',0)),false);
 pos:=invoice_financial_position(inv);
 if pos->>'status'<>'cancelled' then raise exception 'Cancelled invoice reads %',pos->>'status'; end if;
 if (pos->>'refund_due')::numeric<>100 then
  raise exception 'A cancelled invoice holding money must show 100 refund due, got %',pos->>'refund_due'; end if;
 if (pos->>'refunded')::numeric<>0 then
  raise exception 'A refund was recorded when none was made'; end if;

 raise notice 'PASS: a full S$15 refund stores refunded / 0 held / 15 refunded with its payment history intact; a partial refund reports its real remaining balance and is not called fully refunded; a cancellation reads cancelled with the money still shown as due';
end $$;
rollback;
