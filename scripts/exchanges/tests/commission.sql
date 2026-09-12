-- Commission on an exchange follows who served it, and only the top-up.
--
-- The basis was already right: both engines see the paid top-up only, so value
-- carried forward from the original purchase cannot earn a second commission.
-- What 306 fixes is WHO it lands on — it used to credit whoever created the
-- exchange record, which made the document's issuer the earner.
-- Disposable database only; everything is rolled back.
begin;
do $$
declare own uuid:=gen_random_uuid(); a uuid:=gen_random_uuid();
 cc uuid:=gen_random_uuid(); d uuid:=gen_random_uuid();
 st uuid; cust uuid; ref uuid; aff uuid; pm uuid; p uuid; p2 uuid;
 inv uuid; res jsonb; ex uuid; exinv uuid; n numeric; topup numeric;
begin
 insert into auth.users(id,email) values
   (own,'xc-own@tests.invalid'),(a,'xc-a@tests.invalid'),(cc,'xc-c@tests.invalid'),(d,'xc-d@tests.invalid');
 insert into profiles(id,full_name,email,role) values
   (own,'Owner','xc-own@tests.invalid','owner'),
   (a,'Staff A','xc-a@tests.invalid','staff'),
   (cc,'Staff C','xc-c@tests.invalid','staff'),(d,'Staff D','xc-d@tests.invalid','staff');
 perform set_config('request.jwt.claim.sub',own::text,true);
 insert into stores(name,code,country_code) values('XC Store','XCS','SG') returning id into st;
 insert into user_store_assignments(user_id,store_id) values(a,st),(cc,st),(d,st);
 insert into customers(full_name,phone) values('XC Buyer','+6598901001') returning id into cust;
 insert into customers(full_name,phone) values('XC Referrer','+6598901002') returning id into ref;
 insert into customer_affiliates(customer_id,status,activated_at,activated_by)
   values(ref,'active',now(),own) returning id into aff;
 insert into payment_methods(name,is_active) values('XC Cash',true) returning id into pm;
 insert into products(name,sku,product_type) values('XC Item','XCI','own') returning id into p;
 insert into products(name,sku,product_type) values('XC Better','XCB','own') returning id into p2;
 insert into store_inventory(store_id,product_id,current_qty) values(st,p,50),(st,p2,50);
 perform set_product_prices(st,p,100,100,'available');
 perform set_product_prices(st,p2,120,120,'available');   -- S$20 more

 -- Original sale served by Staff A.
 inv:=create_invoice(st,cust,null,jsonb_build_array(jsonb_build_object('kind','product','product_id',p,'quantity',1)),
   0,null,null,jsonb_build_array(a::text));
 perform record_invoice_payment(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',100)),gen_random_uuid());

 -- Exchange served by C and D, raised by the Owner, paying the S$20 difference.
 res:=create_exchange_with_details('product',jsonb_build_object(
   'original_invoice_id',inv,'processing_store_id',st,
   'returned',jsonb_build_array(jsonb_build_object(
     'invoice_item_id',(select id from invoice_items where invoice_id=inv),'quantity',1)),
   'replacement',jsonb_build_array(jsonb_build_object('product_id',p2,'quantity',1)),
   'payments',jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',20)),
   'reason','Upgrade',
   'served_by',jsonb_build_array(cc::text,d::text),
   'affiliate',jsonb_build_object('mode','set','id',aff)));
 ex:=(res->>'id')::uuid;
 topup:=(select topup_amount from product_exchanges where id=ex);
 if topup<>20 then raise exception 'Top-up should be the 20 difference, got %',topup; end if;

 select id into exinv from invoices where exchange_id=ex and is_exchange;
 if exinv is null then
  perform create_exchange_invoice(ex);
  select id into exinv from invoices where exchange_id=ex and is_exchange;
 end if;
 if exinv is null then raise exception 'No replacement invoice was created'; end if;

 -- ---- the replacement invoice is worth the TOP-UP, not the replacement ----
 if (select total_amount from invoices where id=exinv)<>20 then
  raise exception 'The replacement invoice totals %, not the 20 top-up — carried value would earn again',
    (select total_amount from invoices where id=exinv); end if;

 -- ---- it credits the people who served the exchange ----------------------
 if not exists(select 1 from invoice_service_staff where invoice_id=exinv and staff_id=cc)
    or not exists(select 1 from invoice_service_staff where invoice_id=exinv and staff_id=d) then
  raise exception 'The replacement invoice did not credit Staff C and D'; end if;
 -- not the person who typed it...
 if exists(select 1 from invoice_service_staff where invoice_id=exinv and staff_id=own) then
  raise exception 'The issuer was credited as service staff'; end if;
 -- ...and not the person who made the original sale.
 if exists(select 1 from invoice_service_staff where invoice_id=exinv and staff_id=a) then
  raise exception 'The original sale''s staff were credited for the exchange'; end if;

 -- ---- and the affiliate the exchange chose -------------------------------
 if (select affiliate_id from invoices where id=exinv) is distinct from aff then
  raise exception 'The exchange''s affiliate did not reach the replacement invoice (got %)',
    (select affiliate_id from invoices where id=exinv); end if;

 -- ---- commission is earned on the top-up only ----------------------------
 n:=(select coalesce(sum(line_amount),0) from commissions where invoice_id=exinv);
 if n>20 then
  raise exception 'Commission was earned on % — more than the 20 actually paid',n; end if;
 -- the original sale's own staff attribution is untouched
 if not exists(select 1 from invoice_service_staff where invoice_id=inv and staff_id=a) then
  raise exception 'The original sale lost its staff'; end if;
 if exists(select 1 from invoice_service_staff where invoice_id=inv and staff_id in (cc,d)) then
  raise exception 'The exchange''s staff were written onto the original sale'; end if;

 raise notice 'PASS: the replacement invoice is worth the top-up only, credits the staff who served the exchange rather than its issuer or the original seller, carries the exchange''s own affiliate, earns commission on no more than the money actually paid, and leaves the original sale''s attribution alone';
end $$;
rollback;
