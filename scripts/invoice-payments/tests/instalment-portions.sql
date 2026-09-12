-- Instalments attach to a payment portion, not to the whole invoice.
--
-- Before 304 an invoice carried ONE arrangement in three columns, so
-- "S$100 cash now, S$900 over twelve months" could not be recorded: the
-- arrangement was imposed on the whole invoice including the part paid
-- outright. These assertions hold the line between a promise and a receipt.
-- Disposable database only; everything is rolled back.
begin;
do $$
declare own uuid:=gen_random_uuid();
 st uuid; c uuid; cash uuid; card uuid; wallet uuid; p uuid;
 inv uuid; legacy uuid; r jsonb; s jsonb; n int; rid uuid;
begin
 insert into auth.users(id,email) values(own,'ip-own@tests.invalid');
 insert into profiles(id,full_name,email,role) values(own,'Owner','ip-own@tests.invalid','owner');
 perform set_config('request.jwt.claim.sub',own::text,true);
 insert into stores(name,code,country_code) values('IP Store','IPS','SG') returning id into st;
 insert into customers(full_name,phone) values('IP Buyer','+6598899001') returning id into c;
 insert into payment_methods(name,is_active) values('IP Cash',true) returning id into cash;
 insert into payment_methods(name,is_active) values('IP Master Card',true) returning id into card;
 insert into payment_methods(name,is_active,is_wallet_credit) values('IP Wallet',true,true) returning id into wallet;
 insert into products(name,sku,product_type) values('IP Item','IPI','own') returning id into p;
 insert into store_inventory(store_id,product_id,current_qty) values(st,p,200);
 perform set_product_prices(st,p,1000,1000,'available');

 -- ---- S$100 cash plus S$900 over twelve months ---------------------------
 inv:=create_invoice_with_details(st,c,jsonb_build_array(jsonb_build_object('kind','product','product_id',p,'quantity',1)),
   jsonb_build_object('business_date',sg_today()::text));
 rid:=gen_random_uuid();
 r:=record_invoice_settlement(inv,jsonb_build_object(
   'receipts',jsonb_build_array(jsonb_build_object('key','cash','payment_method_id',cash,'amount',100)),
   'arrangements',jsonb_build_array(jsonb_build_object('key','plan','category','in_house','method_id',card,'months',12,'covered_amount',900))),rid);

 if (r->>'money_received')::numeric<>100 then
  raise exception 'Money received should be the 100 actually taken, got %',r->>'money_received'; end if;
 if (r->>'remaining_due')::numeric<>900 then
  raise exception 'Remaining due should be 900, got %',r->>'remaining_due'; end if;
 if (r->>'instalment_covered')::numeric<>900 then
  raise exception 'Instalment covered should be 900, got %',r->>'instalment_covered'; end if;
 -- A promise is not a receipt.
 if (select status from invoices where id=inv)='paid' then
  raise exception 'An instalment arrangement marked the invoice fully paid'; end if;
 if (select count(*) from invoice_payments where invoice_id=inv)<>1 then
  raise exception 'The arrangement created a payment row for money nobody received'; end if;
 -- The underlying method is the real one, never a synthetic "Instalment".
 if (r#>>'{arrangements,0,method_id}')::uuid<>card then
  raise exception 'The arrangement lost the real payment method'; end if;
 if jsonb_array_length(r#>'{arrangements,0,receipts}')<>0 then
  raise exception 'An arrangement with nothing received was linked to a payment'; end if;
 if (r#>>'{arrangements,0,received_allocated}')::numeric<>0 then
  raise exception 'An arrangement with nothing received reported money against it'; end if;
 if (r#>>'{arrangements,0,remaining}')::numeric<>900 then
  raise exception 'The arrangement should still have 900 to collect, got %',r#>>'{arrangements,0,remaining}'; end if;
 -- The cash portion keeps its own method and carries no instalment terms.
 if (select payment_method_id from invoice_payments where invoice_id=inv)<>cash then
  raise exception 'The cash portion was rewritten to the instalment method'; end if;

 -- ---- replaying the same request adds nothing ----------------------------
 r:=record_invoice_settlement(inv,jsonb_build_object(
   'receipts',jsonb_build_array(jsonb_build_object('key','cash','payment_method_id',cash,'amount',100)),
   'arrangements',jsonb_build_array(jsonb_build_object('key','plan','category','in_house','method_id',card,'months',12,'covered_amount',900))),rid);
 if jsonb_array_length((invoice_instalment_summary(inv))->'arrangements')<>1 then
  raise exception 'A replayed request duplicated the arrangement'; end if;
 if (select count(*) from invoice_payments where invoice_id=inv)<>1 then
  raise exception 'A replayed request duplicated the payment'; end if;

 -- ---- provider-funded: money really arrives, and is linked ---------------
 inv:=create_invoice_with_details(st,c,jsonb_build_array(jsonb_build_object('kind','product','product_id',p,'quantity',1)),
   jsonb_build_object('business_date',sg_today()::text));
 r:=record_invoice_settlement(inv,jsonb_build_object(
   'receipts',jsonb_build_array(jsonb_build_object('key','prov','payment_method_id',card,'amount',1000)),
   'arrangements',jsonb_build_array(jsonb_build_object('key','plan','category','provider_funded','method_id',card,'months',6,
     'covered_amount',1000,'receipt_key','prov'))),gen_random_uuid());
 if (r->>'money_received')::numeric<>1000 then
  raise exception 'A provider settlement is money received, got %',r->>'money_received'; end if;
 if (select status from invoices where id=inv)<>'paid' then
  raise exception 'A provider-funded invoice settled in full should be paid'; end if;
 if jsonb_array_length(r#>'{arrangements,0,receipts}')<>1 then
  raise exception 'The provider settlement was not linked to its arrangement'; end if;
 if (r#>>'{arrangements,0,received_allocated}')::numeric<>1000 then
  raise exception 'The arrangement does not report what was received under it'; end if;
 if (r#>>'{arrangements,0,remaining}')::numeric<>0 then
  raise exception 'A fully settled arrangement should have nothing left, got %',r#>>'{arrangements,0,remaining}'; end if;

 -- ---- every preset duration, and a custom one ----------------------------
 foreach n in array array[3,6,9,12,18] loop
  inv:=create_invoice_with_details(st,c,jsonb_build_array(jsonb_build_object('kind','product','product_id',p,'quantity',1)),
    jsonb_build_object('business_date',sg_today()::text));
  r:=record_invoice_settlement(inv,jsonb_build_object('arrangements',
    jsonb_build_array(jsonb_build_object('key','p'||n,'category','in_house','method_id',card,'months',n,'covered_amount',1000))),gen_random_uuid());
  if (r#>>'{arrangements,0,months}')::int<>n then
   raise exception '% months was not recorded, got %',n,r#>>'{arrangements,0,months}'; end if;
  if (select status from invoices where id=inv)='paid' then
   raise exception 'An arrangement alone marked a % month invoice paid',n; end if;
 end loop;

 -- ---- invalid input is refused, field by field ---------------------------
 inv:=create_invoice_with_details(st,c,jsonb_build_array(jsonb_build_object('kind','product','product_id',p,'quantity',1)),
   jsonb_build_object('business_date',sg_today()::text));
 begin
  perform record_invoice_settlement(inv,jsonb_build_object('arrangements',
    jsonb_build_array(jsonb_build_object('key','k','category','in_house','method_id',card,'months',0,'covered_amount',100))),gen_random_uuid());
  raise exception 'Zero months was accepted';
 exception when others then if sqlerrm not like '%positive whole number of months%' then raise; end if; end;
 begin
  perform record_invoice_settlement(inv,jsonb_build_object('arrangements',
    jsonb_build_array(jsonb_build_object('key','k','category','in_house','months',6,'covered_amount',100))),gen_random_uuid());
  raise exception 'A missing underlying method was accepted';
 exception when others then if sqlerrm not like '%money actually comes through%' then raise; end if; end;
 begin
  perform record_invoice_settlement(inv,jsonb_build_object('arrangements',
    jsonb_build_array(jsonb_build_object('key','k','category','something','method_id',card,'months',6,'covered_amount',100))),gen_random_uuid());
  raise exception 'An unknown category was accepted';
 exception when others then if sqlerrm not like '%in-house or provider-funded%' then raise; end if; end;
 -- Wallet credit is not an instalment channel.
 begin
  perform record_invoice_settlement(inv,jsonb_build_object('arrangements',
    jsonb_build_array(jsonb_build_object('key','k','category','in_house','method_id',wallet,'months',6,'covered_amount',100))),gen_random_uuid());
  raise exception 'Wallet credit was accepted as the underlying instalment method';
 exception when others then if sqlerrm not like '%Wallet credit cannot%' then raise; end if; end;
 -- Nothing at all is not a settlement.
 begin
  perform record_invoice_settlement(inv,'{}'::jsonb,gen_random_uuid());
  raise exception 'An empty settlement was accepted';
 exception when others then if sqlerrm not like '%Record a payment%' then raise; end if; end;
 -- and none of those refusals left anything behind
 if (select count(*) from invoice_payment_arrangements where invoice_id=inv)<>0 then
  raise exception 'A refused arrangement was still written'; end if;
 if (select count(*) from invoice_payments where invoice_id=inv)<>0 then
  raise exception 'A refused settlement recorded a payment'; end if;

 -- ---- a pre-304 invoice keeps showing its own terms ----------------------
 legacy:=create_invoice_with_details(st,c,jsonb_build_array(jsonb_build_object('kind','product','product_id',p,'quantity',1)),
   jsonb_build_object('business_date',sg_today()::text));
 update invoices set instalment_category='in_house',instalment_method_id=card,instalment_months=24 where id=legacy;
 s:=invoice_instalment_summary(legacy);
 if s->'legacy_arrangement' is null then
  raise exception 'A historical arrangement stopped being displayed'; end if;
 if (s#>>'{legacy_arrangement,months}')::int<>24 then
  raise exception 'The historical terms were rewritten, got %',s#>>'{legacy_arrangement,months}'; end if;
 if (s#>>'{legacy_arrangement,scope}')<>'whole invoice' then
  raise exception 'A historical arrangement was given a payment-level scope it never had'; end if;
 if jsonb_array_length(s->'arrangements')<>0 then
  raise exception 'A payment-level association was fabricated for a historical arrangement'; end if;

 raise notice 'PASS: cash and instalment portions coexist on one invoice; a promise is never counted as a receipt nor marks the invoice paid; the real underlying method is kept; provider settlements are money and are linked; every preset and a custom duration record; invalid fields are refused individually and leave nothing behind; historical invoice-level terms still display and are not fabricated onto payments';
end $$;
rollback;
