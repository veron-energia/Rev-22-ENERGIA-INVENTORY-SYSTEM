-- Settlement identity, association, coverage and lifecycle.
--
-- Each of these reproduced a real defect in migration 304 before 307 fixed it:
--   A two receipts written in one statement share a created_at, so ordering by
--     it linked the WRONG payment, and an out-of-range index was ignored;
--   B business-field matching merged two legitimate identical portions and
--     accepted an altered payload under the same request id;
--   C a 1000 invoice accumulated 1500 of arrangements;
--   D a cancelled invoice accepted new terms.
-- Disposable database only; everything is rolled back.
begin;
do $$
declare own uuid:=gen_random_uuid();
 st uuid; c uuid; m1 uuid; m2 uuid; wallet uuid; p uuid;
 inv uuid; inv2 uuid; r jsonb; b jsonb; rid uuid; n int;
 v_linked uuid; v_beta uuid; arr uuid;
begin
 insert into auth.users(id,email) values(own,'si-own@tests.invalid');
 insert into profiles(id,full_name,email,role) values(own,'Owner','si-own@tests.invalid','owner');
 perform set_config('request.jwt.claim.sub',own::text,true);
 insert into stores(name,code,country_code) values('SI Store','SIS','SG') returning id into st;
 insert into customers(full_name,phone) values('SI Buyer','+6598905001') returning id into c;
 insert into payment_methods(name,is_active) values('SI Alpha',true) returning id into m1;
 insert into payment_methods(name,is_active) values('SI Beta',true) returning id into m2;
 insert into payment_methods(name,is_active,is_wallet_credit) values('SI Wallet',true,true) returning id into wallet;
 insert into products(name,sku,product_type) values('SI Item','SII','own') returning id into p;
 insert into store_inventory(store_id,product_id,current_qty) values(st,p,200);
 perform set_product_prices(st,p,1000,1000,'available');

 -- ================= A. receipt association =================
 inv:=create_invoice_with_details(st,c,jsonb_build_array(jsonb_build_object('kind','product','product_id',p,'quantity',1)),
   jsonb_build_object('business_date',sg_today()::text));
 r:=record_invoice_settlement(inv,jsonb_build_object(
   'receipts',jsonb_build_array(
     jsonb_build_object('key','r1','payment_method_id',m1,'amount',10),
     jsonb_build_object('key','r2','payment_method_id',m2,'amount',20)),
   'arrangements',jsonb_build_array(jsonb_build_object(
     'key','a1','category','provider_funded','method_id',m2,'months',6,
     'covered_amount',900,'receipt_key','r2'))),gen_random_uuid());
 select id into v_beta from invoice_payments where invoice_id=inv and payment_method_id=m2;
 select payment_id into v_linked from invoice_payment_arrangements where invoice_id=inv and portion_key='a1';
 if v_linked is distinct from v_beta then
  raise exception 'The arrangement linked the wrong receipt (got %, expected the Beta one %)',v_linked,v_beta; end if;
 -- the two receipts really do share a timestamp, which is what broke 304
 if (select count(distinct created_at) from invoice_payments where invoice_id=inv)<>1 then
  raise exception 'Fixture no longer reproduces identical receipt timestamps'; end if;
 -- an unknown reference is refused, not silently dropped
 begin
  perform record_invoice_settlement(inv,jsonb_build_object('arrangements',jsonb_build_array(
    jsonb_build_object('key','bad','category','in_house','method_id',m1,'months',6,
      'covered_amount',10,'receipt_key','nope'))),gen_random_uuid());
  raise exception 'An unknown receipt reference was accepted';
 exception when others then
  if sqlerrm like 'An unknown receipt%' then raise; end if;
  if sqlerrm not like '%not in this request%' then raise; end if; end;
 -- a receipt with no key is refused
 begin
  perform record_invoice_settlement(inv,jsonb_build_object('receipts',jsonb_build_array(
    jsonb_build_object('payment_method_id',m1,'amount',1))),gen_random_uuid());
  raise exception 'A receipt without a key was accepted';
 exception when others then
  if sqlerrm like 'A receipt without%' then raise; end if;
  if sqlerrm not like '%needs a key%' then raise; end if; end;

 -- ================= B. request identity =================
 inv2:=create_invoice_with_details(st,c,jsonb_build_array(jsonb_build_object('kind','product','product_id',p,'quantity',1)),
   jsonb_build_object('business_date',sg_today()::text));
 -- two legitimate identical portions must BOTH be recorded
 r:=record_invoice_settlement(inv2,jsonb_build_object('arrangements',jsonb_build_array(
   jsonb_build_object('key','p1','category','in_house','method_id',m1,'months',6,'covered_amount',100),
   jsonb_build_object('key','p2','category','in_house','method_id',m1,'months',6,'covered_amount',100))),
   gen_random_uuid());
 select count(*) into n from invoice_payment_arrangements where invoice_id=inv2;
 if n<>2 then raise exception 'Two identical legitimate portions collapsed into %',n; end if;

 -- replaying the SAME request writes nothing more and returns the same picture
 rid:=gen_random_uuid();
 r:=record_invoice_settlement(inv2,jsonb_build_object('arrangements',jsonb_build_array(
   jsonb_build_object('key','p3','category','in_house','method_id',m1,'months',12,'covered_amount',50))),rid);
 b:=record_invoice_settlement(inv2,jsonb_build_object('arrangements',jsonb_build_array(
   jsonb_build_object('key','p3','category','in_house','method_id',m1,'months',12,'covered_amount',50))),rid);
 if (b->>'arrangements_recorded')::int<>0 then
  raise exception 'A replayed request wrote again'; end if;
 if (select count(*) from invoice_payment_arrangements where invoice_id=inv2)<>3 then
  raise exception 'A replayed request duplicated a portion'; end if;
 -- the same identity with DIFFERENT terms must fail loudly
 begin
  perform record_invoice_settlement(inv2,jsonb_build_object('arrangements',jsonb_build_array(
    jsonb_build_object('key','p3','category','in_house','method_id',m1,'months',24,'covered_amount',500))),rid);
  raise exception 'An altered payload was accepted under the same request id';
 exception when others then
  if sqlerrm like 'An altered payload%' then raise; end if;
  if sqlerrm not like '%different details%' then raise; end if; end;

 -- ================= C. coverage against what is owed =================
 -- 250 already arranged on a 1000 invoice; 900 more must not fit.
 begin
  perform record_invoice_settlement(inv2,jsonb_build_object('arrangements',jsonb_build_array(
    jsonb_build_object('key','big','category','in_house','method_id',m1,'months',6,'covered_amount',900))),gen_random_uuid());
  raise exception 'Coverage beyond what is owed was accepted';
 exception when others then
  if sqlerrm like 'Coverage beyond%' then raise; end if;
  if sqlerrm not like '%still owed%' then raise; end if; end;
 -- but the remaining 750 fits exactly
 r:=record_invoice_settlement(inv2,jsonb_build_object('arrangements',jsonb_build_array(
   jsonb_build_object('key','rest','category','in_house','method_id',m1,'months',6,'covered_amount',750))),gen_random_uuid());
 if (r->>'instalment_covered')::numeric<>1000 then
  raise exception 'Coverage should now total 1000, got %',r->>'instalment_covered'; end if;

 -- ================= §4. later receipts under one arrangement =================
 select id into arr from invoice_payment_arrangements where invoice_id=inv2 and portion_key='rest';
 r:=record_invoice_settlement(inv2,jsonb_build_object(
   'receipts',jsonb_build_array(jsonb_build_object('key','m1','payment_method_id',m1,'amount',200)),
   'arrangements',jsonb_build_array(jsonb_build_object('arrangement_id',arr,'receipt_key','m1'))),
   gen_random_uuid());
 if (r->>'receipts_linked')::int<>1 then
  raise exception 'The later receipt was not linked to its arrangement'; end if;
 if (select count(*) from invoice_payment_arrangements where invoice_id=inv2)<>4 then
  raise exception 'A later receipt created another arrangement instead of joining one'; end if;
 -- a second receipt joins the SAME arrangement
 r:=record_invoice_settlement(inv2,jsonb_build_object(
   'receipts',jsonb_build_array(jsonb_build_object('key','m2','payment_method_id',m1,'amount',300)),
   'arrangements',jsonb_build_array(jsonb_build_object('arrangement_id',arr,'receipt_key','m2'))),
   gen_random_uuid());
 b:=invoice_arrangement_balances(inv2);
 select (q->>'received_allocated')::numeric into n
   from jsonb_array_elements(b->'arrangements') q where (q->>'arrangement_id')::uuid=arr;
 if n<>500 then raise exception 'The arrangement should have collected 500, got %',n; end if;
 select (q->>'remaining')::numeric into n
   from jsonb_array_elements(b->'arrangements') q where (q->>'arrangement_id')::uuid=arr;
 if n<>250 then raise exception 'The arrangement should have 250 left, got %',n; end if;
 -- the linked deposit is not counted twice
 if (b->>'instalment_received')::numeric<>500 then
  raise exception 'Allocated receipts totalled %, expected 500',b->>'instalment_received'; end if;
 if (b->>'money_received')::numeric<>500 then
  raise exception 'Money received totalled %, expected 500',b->>'money_received'; end if;

 -- ================= D. lifecycle and permissions =================
 begin
  perform record_invoice_settlement(inv2,jsonb_build_object('arrangements',jsonb_build_array(
    jsonb_build_object('key','w','category','in_house','method_id',wallet,'months',6,'covered_amount',10))),gen_random_uuid());
  raise exception 'Wallet credit was accepted as an instalment channel';
 exception when others then
  if sqlerrm like 'Wallet credit was accepted%' then raise; end if;
  if sqlerrm not like '%Wallet credit cannot%' then raise; end if; end;

 perform cancel_invoice_recorded(inv2,'Cancelled',gen_random_uuid());
 begin
  perform record_invoice_settlement(inv2,jsonb_build_object('arrangements',jsonb_build_array(
    jsonb_build_object('key','after','category','in_house','method_id',m1,'months',6,'covered_amount',10))),gen_random_uuid());
  raise exception 'A cancelled invoice accepted a new arrangement';
 exception when others then
  if sqlerrm like 'A cancelled invoice accepted%' then raise; end if;
  if sqlerrm not like '%cannot take a new instalment%' then raise; end if; end;

 raise notice 'PASS: receipts are linked by key even when their timestamps are identical and bad references are refused; two identical portions are both kept while a replay writes nothing and an altered payload under the same id fails; coverage is measured against what is still owed; later receipts join an existing arrangement without duplicating it or double counting the deposit; wallet credit and cancelled invoices are refused';
end $$;
rollback;
