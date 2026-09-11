-- Money is reported on the day it was received, and a payment can be backdated.
--
-- Covers the reported case directly: an invoice raised last month and paid this
-- month must put the money in THIS month.
-- Disposable database only; everything is rolled back.
begin;
do $$
declare o uuid:=gen_random_uuid(); st uuid; c uuid; pm uuid; p uuid;
 inv uuid; inv2 uuid; nodate uuid; n numeric; d date;
begin
 insert into auth.users(id,email) values(o,'pd-owner@tests.invalid');
 insert into profiles(id,full_name,email,role) values(o,'Owner','pd-owner@tests.invalid','owner');
 perform set_config('request.jwt.claim.sub',o::text,true);
 insert into stores(name,code,country_code) values('PD Store','PDS','SG') returning id into st;
 insert into customers(full_name,phone) values('PD Buyer','+6598007777') returning id into c;
 insert into payment_methods(name,is_active) values('PD Cash',true) returning id into pm;
 insert into products(name,sku,product_type) values('PD Item','PDI','own') returning id into p;
 insert into store_inventory(store_id,product_id,current_qty) values(st,p,100);
 perform set_product_prices(st,p,300,300,'available');

 -- ---------------------------------------------------------------
 -- 1. Raised last month, paid today: the money belongs to today.
 -- ---------------------------------------------------------------
 inv:=create_invoice_with_details(st,c,jsonb_build_array(jsonb_build_object('kind','product','product_id',p,'quantity',1)),
   jsonb_build_object('business_date','2026-08-15'));
 perform record_invoice_payment(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',300)),gen_random_uuid());
 select sales_date into d from invoice_sales_ledger() where invoice_id=inv and event_kind='receipt';
 if d<>(now() at time zone 'Asia/Singapore')::date then
  raise exception 'Money was reported on % instead of the day it arrived', d; end if;
 if exists(select 1 from invoice_sales_ledger() where invoice_id=inv and sales_date='2026-08-15') then
  raise exception 'Money is still being reported on the invoice date'; end if;

 -- ---------------------------------------------------------------
 -- 2. A payment can be recorded on the day it actually happened.
 -- ---------------------------------------------------------------
 inv2:=create_invoice_with_details(st,c,jsonb_build_array(jsonb_build_object('kind','product','product_id',p,'quantity',1)),
   jsonb_build_object('business_date','2026-08-20'));
 perform record_invoice_payment(inv2,jsonb_build_array(jsonb_build_object(
   'payment_method_id',pm,'amount',300,'payment_date','2026-09-02')),gen_random_uuid());
 select sales_date into d from invoice_sales_ledger() where invoice_id=inv2 and event_kind='receipt';
 if d<>'2026-09-02' then raise exception 'A backdated payment reported on % instead of 2026-09-02', d; end if;
 if (select (effective_at at time zone 'Asia/Singapore')::date from invoice_payments where invoice_id=inv2)<>'2026-09-02' then
  raise exception 'The receipt date was not stored'; end if;

 -- A future date is refused. A fresh invoice: inv2 is already settled.
 declare future_inv uuid;
 begin
  future_inv:=create_invoice_with_details(st,c,jsonb_build_array(jsonb_build_object('kind','product','product_id',p,'quantity',1)),
    jsonb_build_object('business_date','2026-08-21'));
  begin
   perform record_invoice_payment(future_inv,jsonb_build_array(jsonb_build_object(
     'payment_method_id',pm,'amount',300,'payment_date',((now() at time zone 'Asia/Singapore')::date+5)::text)),gen_random_uuid());
   raise exception 'A future payment date was accepted';
  exception when others then
   if sqlerrm like 'A future payment date was accepted' then raise; end if;
   if sqlerrm not like '%cannot be dated in the future%' then raise; end if; end;
 end;

 -- ---------------------------------------------------------------
 -- 3. An invoice with no business date still reports its money.
 -- ---------------------------------------------------------------
 nodate:=create_invoice_with_details(st,c,jsonb_build_array(jsonb_build_object('kind','product','product_id',p,'quantity',1)),
   jsonb_build_object('business_date','2026-08-25'));
 perform record_invoice_payment(nodate,jsonb_build_array(jsonb_build_object(
   'payment_method_id',pm,'amount',300,'payment_date','2026-09-03')),gen_random_uuid());
 update invoices set business_date=null where id=nodate;   -- the historical shape
 select coalesce(sum(amount),0) into n from invoice_sales_ledger() where invoice_id=nodate;
 if n<>300 then raise exception 'An invoice without a business date reported % instead of its receipts', n; end if;
 if (select invoice_received_sales_amount(nodate)) is null then
  raise exception 'Received amount is still hidden when the invoice date is unknown'; end if;

 -- ---------------------------------------------------------------
 -- 4. Only what was received, and a refund still lands on its own date.
 -- ---------------------------------------------------------------
 declare part uuid; pay uuid; it uuid;
 begin
  perform set_product_prices(st,p,300,300,'available');
  part:=create_invoice_with_details(st,c,jsonb_build_array(jsonb_build_object('kind','product','product_id',p,'quantity',1)),
    jsonb_build_object('business_date','2026-08-28'));
  perform record_invoice_payment(part,jsonb_build_array(jsonb_build_object(
    'payment_method_id',pm,'amount',150,'payment_date','2026-09-04')),gen_random_uuid());
  select coalesce(sum(amount),0) into n from invoice_sales_ledger() where invoice_id=part;
  if n<>150 then raise exception 'A S$300 invoice with S$150 received reported %', n; end if;
  select sales_date into d from invoice_sales_ledger() where invoice_id=part and event_kind='receipt';
  if d<>'2026-09-04' then raise exception 'The part payment reported on % instead of its own date', d; end if;

  select id into it from invoice_items where invoice_id=part;
  select id into pay from invoice_payments where invoice_id=part;
  perform refund_invoice_recorded(part,jsonb_build_array(jsonb_build_object('invoice_item_id',it,'amount',50)),
    jsonb_build_array(jsonb_build_object('payment_id',pay,'amount',50)),
    (select jsonb_build_array(jsonb_build_object('movement_id',id,'sellable_quantity',1))
       from stock_movements where invoice_id=part and movement_type='store_sale' limit 1),
    'Partial return',gen_random_uuid());
  select sales_date into d from invoice_sales_ledger() where invoice_id=part and event_kind='refund';
  if d<>(now() at time zone 'Asia/Singapore')::date then
   raise exception 'The refund moved off the refund date to %', d; end if;
  select coalesce(sum(amount),0) into n from invoice_sales_ledger() where invoice_id=part;
  if n<>100 then raise exception 'Net after a S$50 refund was % instead of 100', n; end if;
 end;

 raise notice 'PASS: received money is reported on the day it arrived, not the invoice date; payments can be backdated and a future date is refused; an invoice with no business date still reports its receipts; only received amounts count and refunds stay on the refund date';
end $$;
rollback;
