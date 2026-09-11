begin;
create function pg_temp.check(ok boolean,message text) returns void language plpgsql as $$begin if ok is distinct from true then raise exception 'FAIL: %',message;end if;end$$;
do $$
declare o uuid:=gen_random_uuid(); st uuid; buyer uuid; ref uuid; affiliate uuid; product uuid; method uuid; inv uuid; item uuid; receipt uuid; movement uuid; p1 uuid; p2 uuid;
 commission_month date; original jsonb; result jsonb; balance_before numeric; payout_before numeric; entries_before integer;
begin
 insert into auth.users(id,email) values(o,'partial-invoice@tests.invalid');
 insert into profiles(id,full_name,email,role) values(o,'Partial Invoice Owner','partial-invoice@tests.invalid','owner');
 perform set_config('request.jwt.claim.sub',o::text,true);
 insert into stores(name,code,country_code) values('Partial Invoice Tests','PIT','SG') returning id into st;
 insert into customers(full_name,phone) values('Partial Buyer','+6591118861') returning id into buyer;
 insert into customers(full_name,phone) values('Partial Referrer','+6591118862') returning id into ref;
 insert into customer_affiliates(customer_id,status) values(ref,'active') returning id into affiliate;
 insert into affiliate_accounts(auth_user_id,customer_id,affiliate_id) values(o,ref,affiliate);
 insert into payment_methods(name) values('Partial Invoice Cash') returning id into method;
 update app_settings set commission_tier1_own_rate=15 where id=true;
 insert into products(name,sku,product_type) values('Partial Commission Product','PCP','own') returning id into product;
 insert into store_inventory(store_id,product_id,current_qty) values(st,product,100);
 perform set_product_prices(st,product,100,100,'available');
 inv:=create_invoice(st,buyer,affiliate,jsonb_build_array(jsonb_build_object('kind','product','product_id',product,'quantity',3)));
 perform record_invoice_payment(inv,jsonb_build_array(jsonb_build_object('payment_method_id',method,'amount',300)),gen_random_uuid());
 select date_trunc('month',invoice_paid_date)::date into commission_month from commissions where invoice_id=inv and tier='tier1';
 select id into item from invoice_items where invoice_id=inv;
 select id into receipt from invoice_payments where invoice_id=inv;
 select id into movement from stock_movements where invoice_id=inv and movement_type='store_sale';
 result:=record_affiliate_payout(ref,commission_month,20,method,sg_today(),'Partial commission',null,gen_random_uuid());p1:=(result->>'id')::uuid;
 select jsonb_agg(to_jsonb(c) order by id) into original from commissions c where payout_id=p1;
 perform pg_temp.check((affiliate_portal_earnings()->'summary'->>'paid')::numeric=20 and (affiliate_portal_earnings()->'summary'->>'unpaid')::numeric=25,'portal partial totals');
 perform pg_temp.check(affiliate_portal_purchases()->0->>'status'='partially_paid','portal partial purchase status');
 perform pg_temp.check((select balance=25 from affiliate_month_balances() where referrer=ref and month=commission_month),'45 earned / 20 paid / 25 remaining');
 perform refund_invoice_recorded(inv,jsonb_build_array(jsonb_build_object('invoice_item_id',item,'amount',100)),
  jsonb_build_array(jsonb_build_object('payment_id',receipt,'amount',100)),
  jsonb_build_array(jsonb_build_object('movement_id',movement,'sellable_quantity',1)),'Return one unit',gen_random_uuid());
 perform pg_temp.check((select balance=10 and paid=20 and earned+adjustments=30 from affiliate_month_balances() where referrer=ref and month=commission_month),'refund after partial payout preserves correct economic balance');
 perform pg_temp.check(original=(select jsonb_agg(to_jsonb(c) order by id) from commissions c where payout_id=p1),'paid anchor and invoice IDs retained');
 perform reconcile_invoice_commissions(inv,'Repeat calculation after partial payout');
 perform pg_temp.check((select balance=10 from affiliate_month_balances() where referrer=ref and month=commission_month),'repeat reconciliation does not double reverse');
 result:=record_affiliate_payout(ref,commission_month,10,method,sg_today(),null,null,gen_random_uuid());p2:=(result->>'id')::uuid;
 perform pg_temp.check(not exists(select 1 from commission_payout_allocations a join commissions c on c.id=a.commission_id where a.payout_id=p2 and c.payout_id=p1),'new payout does not allocate the refunded original anchor');
 perform pg_temp.check((select balance=0 from affiliate_month_balances() where referrer=ref and month=commission_month),'remaining payout after refund clears exact balance');
 -- Real audited correction after two payments; no lines or payout cash rewritten.
 perform correct_invoice(inv,jsonb_build_array(jsonb_build_object('invoice_item_id',item,'kind','product','product_id',product,'quantity',3)),
  '{"notes":"Corrected delivery note"}','Delivery details verified',gen_random_uuid());
 perform pg_temp.check((select balance=0 and paid=30 from affiliate_month_balances() where referrer=ref and month=commission_month),'audited invoice correction preserves cash and balance');
 perform cancel_invoice_recorded(inv,'Cancel remaining delivery',gen_random_uuid());
 perform pg_temp.check((select balance=-30 and paid=30 and earned+adjustments=0 from affiliate_month_balances() where referrer=ref and month=commission_month),'cancel after full effective payout leaves signed adjustment, not payable money');
 begin perform record_affiliate_payout(ref,commission_month,1,method,sg_today(),null,null,gen_random_uuid());raise exception 'Overpaid balance accepted';exception when others then if sqlerrm not like '%remaining payable balance%' then raise;end if;end;
 perform correct_affiliate_payout(p1,1,5,method,sg_today(),null,null,'Receipt proves only five was paid',gen_random_uuid());
 perform pg_temp.check((select balance=-15 and paid=15 from affiliate_month_balances() where referrer=ref and month=commission_month),'correcting payment after adjustment releases only difference');
 perform reconcile_invoice_commissions(inv,'Repeat cancelled calculation');
 perform pg_temp.check((select balance=-15 and paid=15 from affiliate_month_balances() where referrer=ref and month=commission_month),'later recalculation preserves corrected cash and anchors');
 perform pg_temp.check((affiliate_portal_earnings()->'summary'->>'paid')::numeric=15 and (affiliate_portal_earnings()->'summary'->>'unpaid')::numeric=-15,'portal preserves effective payment and signed adjustment');
 perform pg_temp.check((affiliate_portal_purchases()->0->>'your_commission')::numeric=0,'portal purchase excludes superseded reversals');
 perform affiliate_portal_network(); perform affiliate_portal_payouts();
 raise notice 'PASS: real refund, correction, cancellation and repeat commission reconciliation after partial/full payouts';
end$$;
rollback;
