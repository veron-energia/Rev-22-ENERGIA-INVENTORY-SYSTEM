begin;
do $$
declare o uuid:=gen_random_uuid(); st uuid; buyer uuid; referrer uuid; affiliate uuid; product uuid; package uuid; method uuid;
 inv uuid; product_line uuid; package_line uuid; payment uuid; benefit uuid; stock uuid; payout uuid; request uuid;
 product_refund jsonb; source_refund jsonb; stock_refund jsonb; items jsonb; before_paid jsonb; before_payout jsonb;
 before_commissions jsonb; result jsonb; n integer; fake uuid; sale uuid;
begin
 insert into auth.users(id,email) values(o,'commission-refund@tests.invalid');
 insert into profiles(id,full_name,email,role) values(o,'Commission Refund Owner','commission-refund@tests.invalid','owner');
 perform set_config('request.jwt.claim.sub',o::text,true);
 insert into stores(name,code,country_code) values('Commission Refund Tests','CRB','SG') returning id into st;
 insert into customers(full_name,phone) values('Commission Buyer','+6591238870') returning id into buyer;
 insert into customers(full_name,phone) values('Commission Referrer','+6591238871') returning id into referrer;
 insert into customer_affiliates(customer_id,status) values(referrer,'active') returning id into affiliate;
 insert into payment_methods(name) values('Commission Refund Cash') returning id into method;
 update app_settings set commission_tier1_own_rate=15,commission_tier1_third_rate=4.5 where id=true;
 insert into products(name,sku,product_type) values('Commission Product','CRB-P','own') returning id into product;
 insert into store_inventory(store_id,product_id,current_qty) values(st,product,100);
 perform set_product_prices(st,product,100,100,'available');
 insert into credit_packages(name,customer_price,paid_credit_amount,allow_product,grants_reward)
  values('Commission Package',100,100,true,false) returning id into package;
 insert into credit_package_stores(package_id,store_id) values(package,st);

 -- Same invoice, different original sources: only the product is refunded.
 inv:=create_invoice(st,buyer,affiliate,jsonb_build_array(
  jsonb_build_object('kind','product','product_id',product,'quantity',1),
  jsonb_build_object('kind','credit_package','credit_package_id',package,'quantity',1)));
 perform record_invoice_payment(inv,jsonb_build_array(jsonb_build_object('payment_method_id',method,'amount',200)),gen_random_uuid());
 select id into product_line from invoice_items where invoice_id=inv and line_kind='product';
 select id into package_line from invoice_items where invoice_id=inv and line_kind='credit_package';
 select id into payment from invoice_payments where invoice_id=inv;
 select id into stock from stock_movements where invoice_id=inv and movement_type::text='store_sale';
 if (select coalesce(sum(commission_amount),0) from commissions where invoice_id=inv and tier='tier1' and status in ('earned','blocked'))<>19.50 then
  raise exception 'Initial commission must be 15 product plus 4.50 package'; end if;
 insert into commission_payouts(payout_month,referrer_customer_id,total_tier1,total_amount,payment_method_id,paid_by)
  values(date_trunc('month',current_date)::date,referrer,19.50,19.50,method,o) returning id into payout;
 update commissions set status='paid',payout_id=payout where invoice_id=inv and tier='tier1';
 select jsonb_agg(to_jsonb(c) order by c.id) into before_paid from commissions c where payout_id=payout;
 select to_jsonb(p) into before_payout from commission_payouts p where id=payout;
 request:=gen_random_uuid();
 product_refund:=jsonb_build_array(jsonb_build_object('invoice_item_id',product_line,'amount',100));
 source_refund:=jsonb_build_array(jsonb_build_object('payment_id',payment,'amount',100));
 stock_refund:=jsonb_build_array(jsonb_build_object('movement_id',stock,'not_returned_quantity',1));
 result:=refund_invoice_recorded(inv,product_refund,source_refund,stock_refund,'Refund product only',request);
 if (select coalesce(sum(commission_amount),0) from commissions where invoice_id=inv and tier='tier1' and status in ('earned','blocked','paid'))<>4.50 then
  raise exception 'Product refund reduced an unrelated package or retained product commission'; end if;
 if (select coalesce(sum(commission_amount),0) from commissions where invoice_id=inv and tier='tier1' and status in ('earned','blocked') and adjusts_commission_id is null and invoice_item_id is null)<>4.50 then
  raise exception 'Package did not retain its exact original external paid basis'; end if;
 if before_paid is distinct from (select jsonb_agg(to_jsonb(c) order by c.id) from commissions c where payout_id=payout)
  or before_payout is distinct from (select to_jsonb(p) from commission_payouts p where id=payout) then raise exception 'Recorded payout history changed'; end if;
 if (select coalesce(sum(commission_amount),0) from commissions where invoice_id=inv and status='earned' and adjusts_commission_id is not null)<>-19.50 then
  raise exception 'Paid commission offsets were not retained separately'; end if;
 select count(*) into n from commissions where invoice_id=inv;
 perform refund_invoice_recorded(inv,product_refund,source_refund,stock_refund,'Refund product only',request);
 if (select count(*) from commissions where invoice_id=inv)<>n then raise exception 'Refund retry duplicated commission rows'; end if;
 select jsonb_agg(to_jsonb(c) order by c.id) into before_commissions from commissions c where invoice_id=inv;
 select jsonb_agg(jsonb_build_object('invoice_item_id',it.id,'kind',it.line_kind,'product_id',it.product_id,
  'credit_package_id',it.credit_package_id,'quantity',it.quantity,'unit_price',it.unit_price) order by it.id)
  into items from invoice_items it where it.invoice_id=inv;
 perform correct_invoice(inv,items,'{}','Unchanged commission invoice',gen_random_uuid());
 if before_commissions is distinct from (select jsonb_agg(to_jsonb(c) order by c.id) from commissions c where invoice_id=inv) then raise exception 'No-op invoice correction changed commissions'; end if;
 perform reconcile_invoice_commissions(inv,'Repeat commission calculation');
 if (select coalesce(sum(commission_amount),0) from commissions where invoice_id=inv and tier='tier1' and status in ('earned','blocked','paid'))<>4.50 then
  raise exception 'Repeated recalculation accumulated future payout offsets'; end if;
 if before_paid is distinct from (select jsonb_agg(to_jsonb(c) order by c.id) from commissions c where payout_id=payout) then raise exception 'Repeated recalculation changed original paid rows'; end if;
 raise notice 'PASS: product-only refund retains package basis, original paid rows and payout; retry/no-op and repeat calculation do not accumulate commissions';

 -- The reverse direction: refund the package benefit, retain the product.
 -- A numeric sale rate remains authoritative under mandatory classification243.
 update credit_packages set tier1_rate=7 where id=package;
 inv:=create_invoice(st,buyer,affiliate,jsonb_build_array(
  jsonb_build_object('kind','product','product_id',product,'quantity',1),
  jsonb_build_object('kind','credit_package','credit_package_id',package,'quantity',1)));
 perform record_invoice_payment(inv,jsonb_build_array(jsonb_build_object('payment_method_id',method,'amount',200)),gen_random_uuid());
 select id into package_line from invoice_items where invoice_id=inv and line_kind='credit_package';
 select id into product_line from invoice_items where invoice_id=inv and line_kind='product';
 select id into payment from invoice_payments where invoice_id=inv;
 select id into benefit from invoice_benefit_values where invoice_item_id=package_line;
 select id into sale from credit_package_sales where invoice_id=inv;
 if benefit is null then raise exception 'Fixture package has no original benefit evidence'; end if;
 update credit_package_sales set classification_snapshot='own' where id=sale;
 perform reconcile_invoice_commissions(inv,'Verify existing package rules');
 if (select coalesce(sum(commission_amount),0) from commissions where invoice_id=inv and tier='tier1' and status in ('earned','blocked'))<>22 then
  raise exception 'Numeric package rate snapshot was lost'; end if;
 if exists(select 1 from commissions where invoice_id=inv and tier='tier1' and invoice_item_id is null and status in ('earned','blocked') and product_type<>'third_party') then
  raise exception 'Mandatory package classification243 was lost'; end if;
 perform refund_invoice_recorded(inv,jsonb_build_array(jsonb_build_object('invoice_item_id',package_line,'amount',100,
  'benefits',jsonb_build_array(jsonb_build_object('benefit_id',benefit,'amount',100)))),
  jsonb_build_array(jsonb_build_object('payment_id',payment,'amount',100)),'[]','Refund package only',gen_random_uuid());
 if (select coalesce(sum(commission_amount),0) from commissions where invoice_id=inv and tier='tier1' and status in ('earned','blocked'))<>15 then
  raise exception 'Package refund reduced an unrelated product or retained refunded package commission'; end if;
 if (select external_paid from credit_package_sales where id=sale)<>100 then raise exception 'Original package external-paid evidence was rewritten'; end if;

 -- Bad historical source evidence blocks the whole recalculation before any
 -- active earning or paid-offset row can be replaced.
 select jsonb_agg(to_jsonb(c) order by c.id) into before_commissions from commissions c where invoice_id=inv;
 insert into invoice_refunds(invoice_id,payment_id,amount,reason,kind,refunded_by,request_id,outcome)
 values(inv,payment,1,'Historical unmapped refund','allocated',o,gen_random_uuid(),jsonb_build_object('lines',jsonb_build_array(
  jsonb_build_object('invoice_item_id',package_line,'amount',1,'benefits',jsonb_build_array(jsonb_build_object('benefit_id',gen_random_uuid(),'amount',1)))))) returning id into fake;
 begin
  perform reconcile_invoice_commissions(inv,'Must review missing original source');
  raise exception 'Missing original source was accepted';
 exception when others then if sqlerrm not like 'Commission review required:%' then raise; end if; end;
 if before_commissions is distinct from (select jsonb_agg(to_jsonb(c) order by c.id) from commissions c where invoice_id=inv) then raise exception 'Failed historical review partially replaced commissions'; end if;
 delete from invoice_refunds where id=fake;
 raise notice 'PASS: package-only refund retains product basis; original numeric rates, mandatory classification and source evidence are preserved; unresolved history rolls back safely';
end $$;
rollback;
