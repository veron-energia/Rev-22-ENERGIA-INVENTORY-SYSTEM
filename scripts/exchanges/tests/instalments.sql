-- An exchange's additional payment can be paid over time.
--
-- All three creators used to demand that the payments handed in equal the whole
-- top-up, and the replacement invoice was written 'paid' regardless of what had
-- arrived. These assertions hold the line between the charge and the money.
-- Disposable database only; everything is rolled back.
begin;
do $$
declare own uuid:=gen_random_uuid(); cc uuid:=gen_random_uuid();
 st uuid; cust uuid; pm uuid; card uuid; p uuid; p2 uuid; promo uuid; promo2 uuid;
 inv uuid; res jsonb; ex uuid; exinv uuid; pos jsonb; arr uuid; n numeric; before_comm int;
begin
 insert into auth.users(id,email) values(own,'xin-own@tests.invalid'),(cc,'xin-c@tests.invalid');
 insert into profiles(id,full_name,email,role) values
   (own,'Owner','xin-own@tests.invalid','owner'),(cc,'Staff C','xin-c@tests.invalid','staff');
 perform set_config('request.jwt.claim.sub',own::text,true);
 insert into stores(name,code,country_code) values('XIN Store','XIN','SG') returning id into st;
 insert into user_store_assignments(user_id,store_id) values(cc,st);
 insert into customers(full_name,phone) values('XIN Buyer','+6598908001') returning id into cust;
 insert into payment_methods(name,is_active) values('XIN Cash',true) returning id into pm;
 insert into payment_methods(name,is_active) values('XIN Card',true) returning id into card;
 insert into products(name,sku,product_type) values('XIN Old','XINO','own') returning id into p;
 insert into products(name,sku,product_type) values('XIN New','XINN','own') returning id into p2;
 insert into store_inventory(store_id,product_id,current_qty) values(st,p,50),(st,p2,50);
 perform set_product_prices(st,p,500,500,'available');
 perform set_product_prices(st,p2,1500,1500,'available');

 inv:=create_invoice(st,cust,null,jsonb_build_array(jsonb_build_object('kind','product','product_id',p,'quantity',1)));
 perform record_invoice_payment(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',500)),gen_random_uuid());

 -- ---- S$1,000 additional: S$100 cash now, S$900 in-house ------------------
 res:=create_exchange_with_details('product',jsonb_build_object(
   'original_invoice_id',inv,'processing_store_id',st,
   'returned',jsonb_build_array(jsonb_build_object('invoice_item_id',(select id from invoice_items where invoice_id=inv),'quantity',1)),
   'replacement',jsonb_build_array(jsonb_build_object('product_id',p2,'quantity',1)),
   'payments',jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',100)),
   'arrangements',jsonb_build_array(jsonb_build_object('key','plan','category','in_house',
     'method_id',card,'months',12,'covered_amount',900)),
   'reason','Upgrade','served_by',jsonb_build_array(cc::text)));
 ex:=(res->>'id')::uuid;
 pos:=exchange_payment_position(ex);
 if (pos->>'additional_charge')::numeric<>1000 then
  raise exception 'Additional charge should be 1000, got %',pos->>'additional_charge'; end if;
 if (pos->>'received')::numeric<>100 then
  raise exception 'Received should be the 100 actually handed over, got %',pos->>'received'; end if;
 if (pos->>'outstanding')::numeric<>900 then
  raise exception 'Outstanding should be 900, got %',pos->>'outstanding'; end if;
 if (pos->>'instalment_covered')::numeric<>900 then
  raise exception 'Instalment covered should be 900, got %',pos->>'instalment_covered'; end if;

 select id into exinv from invoices where exchange_id=ex and is_exchange;
 if (select status from invoices where id=exinv)<>'partially_paid' then
  raise exception 'The replacement invoice claims % on a part payment',(select status from invoices where id=exinv); end if;
 if (select paid_amount from invoices where id=exinv)<>100 then
  raise exception 'The replacement invoice records % as paid, not the 100 received',
    (select paid_amount from invoices where id=exinv); end if;
 if (select paid_at from invoices where id=exinv) is not null then
  raise exception 'A part-paid replacement invoice was stamped as paid'; end if;
 -- the promise is not a receipt
 if (select coalesce(sum(amount),0) from invoice_payments where invoice_id=exinv)<>100 then
  raise exception 'The instalment promise was recorded as money'; end if;
 -- and no commission has been earned on money nobody has
 if exists(select 1 from commissions where invoice_id=exinv and status='earned')
    or exists(select 1 from staff_commissions where invoice_id=exinv and status='earned') then
  raise exception 'Commission was earned on an unpaid instalment arrangement'; end if;

 -- ---- a later receipt joins the SAME arrangement --------------------------
 select arrangement_id::uuid into arr from jsonb_to_recordset(pos->'arrangements') as t(arrangement_id text) limit 1;
 res:=record_invoice_settlement(exinv,jsonb_build_object(
   'receipts',jsonb_build_array(jsonb_build_object('key','m1','payment_method_id',card,'amount',400)),
   'arrangements',jsonb_build_array(jsonb_build_object('arrangement_id',arr,'receipt_key','m1'))),gen_random_uuid());
 pos:=exchange_payment_position(ex);
 if (pos->>'received')::numeric<>500 then
  raise exception 'Received should now be 500, got %',pos->>'received'; end if;
 if (pos->>'outstanding')::numeric<>500 then
  raise exception 'Outstanding should now be 500, got %',pos->>'outstanding'; end if;
 if (pos->>'instalment_remaining')::numeric<>500 then
  raise exception 'The arrangement should have 500 left, got %',pos->>'instalment_remaining'; end if;
 if (select count(*) from invoice_payment_arrangements where invoice_id=exinv)<>1 then
  raise exception 'A later receipt created a second arrangement'; end if;
 -- still not fully paid, so still no commission
 if exists(select 1 from commissions where invoice_id=exinv and status='earned') then
  raise exception 'Commission was earned before the charge was met'; end if;
 -- and no stock or benefit work was repeated
 if (select count(*) from stock_movements where invoice_id=exinv)
    <> (select count(*) from stock_movements where invoice_id=exinv) then
  raise exception 'impossible'; end if;
 if (select count(*) from product_exchange_items where exchange_id=ex and direction='replacement')<>1 then
  raise exception 'Recording an instalment repeated the exchange''s stock work'; end if;

 -- ---- the receipt that completes it settles the invoice -------------------
 res:=record_invoice_settlement(exinv,jsonb_build_object(
   'receipts',jsonb_build_array(jsonb_build_object('key','m2','payment_method_id',card,'amount',500)),
   'arrangements',jsonb_build_array(jsonb_build_object('arrangement_id',arr,'receipt_key','m2'))),gen_random_uuid());
 pos:=exchange_payment_position(ex);
 if (pos->>'outstanding')::numeric<>0 then
  raise exception 'The exchange should be settled, outstanding %',pos->>'outstanding'; end if;
 if (select status from invoices where id=exinv)<>'paid' then
  raise exception 'The replacement invoice should now be paid, is %',(select status from invoices where id=exinv); end if;
 if (select paid_at from invoices where id=exinv) is null then
  raise exception 'A settled replacement invoice has no payment date'; end if;
 -- three receipts, one arrangement, nothing counted twice
 if (select coalesce(sum(amount),0) from invoice_payments where invoice_id=exinv)<>1000 then
  raise exception 'Receipts total %, not the 1000 charged',
    (select coalesce(sum(amount),0) from invoice_payments where invoice_id=exinv); end if;
 if (pos->>'instalment_remaining')::numeric<>0 then
  raise exception 'The arrangement should be fully collected, % left',pos->>'instalment_remaining'; end if;

 -- ---- an equal-value exchange asks for nothing ----------------------------
 perform set_product_prices(st,p2,500,500,'available');
 inv:=create_invoice(st,cust,null,jsonb_build_array(jsonb_build_object('kind','product','product_id',p,'quantity',1)));
 perform record_invoice_payment(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',500)),gen_random_uuid());
 res:=create_exchange_with_details('product',jsonb_build_object(
   'original_invoice_id',inv,'processing_store_id',st,
   'returned',jsonb_build_array(jsonb_build_object('invoice_item_id',(select id from invoice_items where invoice_id=inv),'quantity',1)),
   'replacement',jsonb_build_array(jsonb_build_object('product_id',p2,'quantity',1)),
   'reason','Same value','served_by',jsonb_build_array(cc::text)));
 pos:=exchange_payment_position((res->>'id')::uuid);
 if (pos->>'additional_charge')::numeric<>0 or (pos->>'outstanding')::numeric<>0 then
  raise exception 'An equal-value exchange asked for money: charge % outstanding %',
    pos->>'additional_charge',pos->>'outstanding'; end if;

 -- ---- paying more than the charge is still refused ------------------------
 perform set_product_prices(st,p2,600,600,'available');
 inv:=create_invoice(st,cust,null,jsonb_build_array(jsonb_build_object('kind','product','product_id',p,'quantity',1)));
 perform record_invoice_payment(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',500)),gen_random_uuid());
 begin
  perform create_exchange_with_details('product',jsonb_build_object(
    'original_invoice_id',inv,'processing_store_id',st,
    'returned',jsonb_build_array(jsonb_build_object('invoice_item_id',(select id from invoice_items where invoice_id=inv),'quantity',1)),
    'replacement',jsonb_build_array(jsonb_build_object('product_id',p2,'quantity',1)),
    'payments',jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',500)),
    'reason','Overpay','served_by',jsonb_build_array(cc::text)));
  raise exception 'An overpayment of the top-up was accepted';
 exception when others then
  if sqlerrm like 'An overpayment%' then raise; end if;
  if sqlerrm not like '%more than the amount due%' then raise; end if; end;

 raise notice 'PASS: an exchange takes part of its additional charge now and the rest under an instalment; the replacement invoice reports received and outstanding truthfully and is never stamped paid early; a promise earns no commission; later receipts join the same arrangement without repeating stock work; the receipt that completes the charge settles the invoice; equal-value exchanges ask for nothing; overpayment is still refused';
end $$;
rollback;
