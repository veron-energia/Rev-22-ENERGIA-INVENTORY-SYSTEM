begin;
do $$
declare o uuid:=gen_random_uuid(); st uuid; c uuid; pm uuid; pa uuid; pb uuid; inv uuid; ia uuid; ib uuid; pay uuid; rid uuid;
 x jsonb; r jsonb;
begin
 insert into auth.users(id,email) values(o,'report-dates@tests.invalid');
 insert into profiles(id,full_name,email,role) values(o,'Report Owner','report-dates@tests.invalid','owner');
 perform set_config('request.jwt.claim.sub',o::text,true);
 insert into stores(name,code,country_code) values('Report Dates','RD','SG') returning id into st;
 insert into customers(full_name,phone) values('Report Customer','+6591238721') returning id into c;
 insert into payment_methods(name) values('Report Cash') returning id into pm;
 insert into products(name,sku,product_type) values('Report A','RD-A','own') returning id into pa;
 insert into products(name,sku,product_type) values('Report B','RD-B','own') returning id into pb;
 insert into store_inventory(store_id,product_id,current_qty) values(st,pa,10),(st,pb,10);
 perform set_product_prices(st,pa,100,100,'available'); perform set_product_prices(st,pb,100,100,'available');
 inv:=create_invoice_with_details(st,c,jsonb_build_array(jsonb_build_object('kind','product','product_id',pa,'quantity',1),
  jsonb_build_object('kind','product','product_id',pb,'quantity',1)),jsonb_build_object('business_date','2020-01-10','manual_discount',20));
 -- Paid on 20 January against a 10 January invoice: the money belongs to the
 -- day it was received (292). Both fall in the same month here, so the monthly
 -- figure is unchanged; the daily attribution is what moved.
 perform record_invoice_payment(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',50,'payment_date','2020-01-20')),gen_random_uuid());
 if invoice_received_sales_amount(inv)<>50 or _aff_settled_spend(c)<>50 then raise exception 'Affiliate summary reported billed instead of received'; end if;
 if sales_between('2020-01-01','2020-01-31',st)<>50 then raise exception 'Partial receipts missing from the month they were received'; end if;
 if sales_between('2020-01-20','2020-01-20',st)<>50 then raise exception 'Partial receipt not attributed to the date it was received'; end if;
 if sales_between('2020-01-10','2020-01-10',st)<>0 then raise exception 'Receipt still reported on the invoice date'; end if;
 if (select count(*) from report_pricing() where invoice_id=inv and paid_date='2020-01-10')<>2 then raise exception 'Pricing report missed partial invoice/business date'; end if;
 if not exists(select 1 from report_discounts() where invoice_id=inv and paid_date='2020-01-10' and total_discount=20) then raise exception 'Discount report missed partial invoice/business date'; end if;
 perform record_invoice_payment(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',130,'payment_date','2020-01-25')),gen_random_uuid());
 select id into ia from invoice_items where invoice_id=inv and product_id=pa;
 select id into ib from invoice_items where invoice_id=inv and product_id=pb;
 select id into pay from invoice_payments where invoice_id=inv and amount=50;
 perform refund_invoice_recorded(inv,jsonb_build_array(jsonb_build_object('invoice_item_id',ia,'amount',30)),
  jsonb_build_array(jsonb_build_object('payment_id',pay,'amount',30)),
  (select jsonb_build_array(jsonb_build_object('movement_id',id,'not_returned_quantity',1)) from stock_movements where invoice_id=inv and product_id=pa and movement_type='store_sale'),
  'Product A partial refund today',gen_random_uuid());
 if sales_between('2020-01-01','2020-01-31',st)<>180 or sales_between(sg_today(),sg_today(),st)<>-30 then raise exception 'Refund moved back to invoice date'; end if;
 if _aff_settled_spend(c)<>150 then raise exception 'Affiliate summary omitted actual refund'; end if;
 if (select amount from report_sales_reconciliation(st,'2020-01-01','2020-01-31') where channel='invoice_sales')<>180 then raise exception 'Reconciliation date mismatch'; end if;
 r:=dashboard_sales('all',null,null,st);
 if (r->>'sales')::numeric<>150 or (r->>'items_sold')::numeric<>2 or (r->>'discount_total')::numeric<>20 then raise exception 'All-time dashboard lost nullable-bound metrics: %',r; end if;
 x:=jsonb_build_array(jsonb_build_object('invoice_item_id',ia,'kind','product','product_id',pa,'quantity',1),jsonb_build_object('invoice_item_id',ib,'kind','product','product_id',pb,'quantity',1));
 -- Correcting the invoice date is a document change. Money stays on the dates
 -- it was received and refunded on, which is the whole point of 292.
 perform correct_invoice(inv,x,'{"business_date":"2020-02-10"}','Correct invoice business date',gen_random_uuid());
 if sales_between('2020-01-01','2020-01-31',st)<>180 then raise exception 'Correcting the invoice date moved receipts out of the month they arrived'; end if;
 if sales_between('2020-02-01','2020-02-29',st)<>0 then raise exception 'Correcting the invoice date pulled receipts into February'; end if;
 if sales_between(sg_today(),sg_today(),st)<>-30 then raise exception 'Refund moved off the refund date'; end if;
 perform cancel_invoice_recorded(inv,'Cancel after partial refund',gen_random_uuid());
 -- 294: a cancelled invoice is not a sale, so its held receipts leave Sales.
 -- The money itself is untouched and is surfaced for follow-up instead of
 -- disappearing quietly.
 if sales_between(null,null,st)<>0 then raise exception 'Cancellation left its receipts in Sales'; end if;
 if (select coalesce(sum(retained),0) from report_cancelled_retained_receipts(st))<>150 then
  raise exception 'Money held on a cancelled invoice was not reported'; end if;
 -- Affiliate settled spend deliberately does NOT follow. It measures what the
 -- customer actually paid the business and drives commission and tiers, so it
 -- is not changed by a reporting rule about Sales.
 if _aff_settled_spend(c)<>150 then raise exception 'Cancellation changed affiliate settled spend'; end if;
 raise notice 'PASS: partial receipts, affiliate spend, invoice-date detail reports, date moves, refund-date reductions, cancellation and all-time dashboard metrics';
end $$;
rollback;
