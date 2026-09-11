-- Disposable local database only. Every fixture is rolled back.
begin;
do $$
declare o uuid:=gen_random_uuid(); staff uuid:=gen_random_uuid(); st uuid; c uuid; p uuid; pm uuid; inv uuid; item uuid; f uuid;
 x jsonb; r jsonb; before_item jsonb; before_stock bigint; status_text text; pay1 uuid; pay2 uuid; rid uuid;
 orig public.invoice_payments%rowtype; n numeric; movement uuid; b uuid; pkg uuid; cp_inv uuid; cp_item uuid; lot uuid; walletpm uuid; spend uuid; wp uuid; svc uuid; cashpay uuid;
begin
 insert into auth.users(id,email) values(o,'invoice-owner@tests.invalid'),(staff,'invoice-staff@tests.invalid');
 insert into profiles(id,full_name,email,role) values(o,'Owner','invoice-owner@tests.invalid','owner'),(staff,'Staff','invoice-staff@tests.invalid','staff');
 perform set_config('request.jwt.claim.sub',o::text,true);
 insert into stores(name,code,country_code) values('Invoice Test','IVT','SG') returning id into st;
 insert into user_store_assignments(user_id,store_id) values(staff,st);
 update app_settings set staff_commission_rate=5 where id=true;
 insert into customers(full_name,phone) values('Invoice Test','+6591237770') returning id into c;
 insert into products(name,sku,product_type) values('Snapshot Product','IVTS','own') returning id into p;
 insert into store_inventory(store_id,product_id,current_qty) values(st,p,100);
 perform set_product_prices(st,p,100,100,'available');
 insert into payment_methods(name) values('Test Cash') returning id into pm;
 inv:=create_invoice_with_details(st,c,jsonb_build_array(jsonb_build_object('kind','product','product_id',p,'quantity',10)),
   jsonb_build_object('business_date','2020-01-02','instalment_category','in_house','instalment_method_id',pm,'instalment_months',6));
 if invoice_net_sales(inv)<>0 then raise exception 'Unpaid invoice counted as sales'; end if;
 -- Received money is reported on the day it arrived (292), not the invoice
 -- date. The payment is dated explicitly so the assertion states the rule
 -- rather than depending on when the test happens to run.
 r:=record_invoice_payment(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',200,'payment_date','2020-01-09')),gen_random_uuid());
 if invoice_net_sales_between(inv,'2020-01-09','2020-01-09')<>200 then raise exception 'Partial receipt not on the date it was received'; end if;
 if invoice_net_sales_between(inv,'2020-01-02','2020-01-02')<>0 then raise exception 'Receipt still reported on the invoice date'; end if;
 select id into pay1 from invoice_payments where invoice_id=inv;
 rid:=gen_random_uuid();
 perform record_invoice_payment(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',800,'payment_date','2020-01-09')),rid);
 perform record_invoice_payment(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',800,'payment_date','2020-01-09')),rid);
 if invoice_net_received(inv)<>1000 then raise exception 'Payment retry was counted twice'; end if;
 select id into pay2 from invoice_payments where invoice_id=inv and amount=800;
 select id,to_jsonb(i) into item,before_item from invoice_items i where invoice_id=inv;
 x:=jsonb_build_array(jsonb_build_object('invoice_item_id',item,'kind','product','product_id',p,'quantity',10));
 select count(*) into before_stock from stock_movements where invoice_id=inv;
 r:=correct_invoice(inv,x,'{}','Unchanged');
 if r->>'unchanged' is distinct from 'true' then raise exception 'No-op not detected: %',r; end if;
 if before_item is distinct from (select to_jsonb(i) from invoice_items i where id=item) or before_stock<>(select count(*) from stock_movements where invoice_id=inv) then raise exception 'No-op altered invoice lines or stock'; end if;
 update staff_commissions set status='paid',payout_id=gen_random_uuid() where invoice_id=inv and status='earned';
 r:=correct_invoice(inv,x,'{"manual_discount":200,"business_date":"2020-01-03"}','Discount correction');
 if (r->>'refund_due')::numeric is distinct from 200 then raise exception 'Expected refund due 200: %',r; end if;
 -- Since 292 the invoice's own date no longer decides where money is reported;
 -- the receipt date does. Correcting the business date is a document change and
 -- must leave the sales figures exactly where the payments put them.
 if invoice_net_sales_between(inv,'2020-01-09','2020-01-09')<>1000 then raise exception 'The dated receipts left the day they were received'; end if;
 if invoice_net_sales_between(inv,'2020-01-02','2020-01-02')<>0
  or invoice_net_sales_between(inv,'2020-01-03','2020-01-03')<>0 then
  raise exception 'Money is still being reported on the invoice date'; end if;
 if invoice_net_sales_between(inv,null,null)<>1000 then raise exception 'Total received changed when the invoice date was corrected'; end if;
 select sum(commission_amount) into n from staff_commissions where invoice_id=inv and status='earned';
 if n is distinct from -10 then raise exception 'Paid-out commission adjustment expected -10, got %',n; end if;
 select * into orig from invoice_payments where id=pay1;
 r:=correct_invoice_payment(pay1,100,'2020-02-01',pm,'Original receipt amount/date mistake',gen_random_uuid());
 if invoice_net_received(inv)<>900 or (select amount from invoice_payments where id=pay1)<>orig.amount
  or (select created_at from invoice_payments where id=pay1)<>orig.created_at then raise exception 'Payment correction rewrote original or wrong net'; end if;
 if exists(select 1 from invoice_refunds where invoice_id=inv) then raise exception 'Bookkeeping correction created a customer refund'; end if;
 pay1:=(r->>'replacement_id')::uuid;
 rid:=gen_random_uuid();
 r:=refund_invoice_recorded(inv,'[{"invoice_item_id":null,"amount":100}]',jsonb_build_array(jsonb_build_object('payment_id',pay1,'amount',100)),'[]','Pay correction excess returned',rid);
 perform refund_invoice_recorded(inv,'[{"invoice_item_id":null,"amount":100}]',jsonb_build_array(jsonb_build_object('payment_id',pay1,'amount',100)),'[]','Pay correction excess returned',rid);
 if invoice_net_received(inv)<>800 then raise exception 'Refund retry changed net twice'; end if;
 select id into movement from stock_movements where invoice_id=inv and movement_type='store_sale' limit 1;
 r:=refund_invoice_recorded(inv,jsonb_build_array(jsonb_build_object('invoice_item_id',item,'amount',80)),
  jsonb_build_array(jsonb_build_object('payment_id',pay2,'amount',80)),
  jsonb_build_array(jsonb_build_object('movement_id',movement,'sellable_quantity',1)),'One unit returned sellable',gen_random_uuid());
 if (select current_qty from store_inventory where store_id=st and product_id=p)<>91 then raise exception 'Sellable return did not restore exactly one'; end if;
 if invoice_net_sales_between(inv,current_date,current_date)<>-180 then raise exception 'Refund reductions not on refund date'; end if;
 perform set_config('request.jwt.claim.sub',staff::text,true);
 begin
  perform correct_invoice(inv,x,'{"manual_discount":0}','Unauthorized');
  raise exception 'Unauthorized correction accepted';
 exception when others then if sqlerrm not like '%Owner or Manager%' then raise; end if; end;
 perform set_config('request.jwt.claim.sub',o::text,true);
 raise notice 'PASS: payment/ledger retries, net corrections, paid-out commission adjustment, source caps, stock returns, dates, instalments and authorization';

 -- Resolved damaged/not-returned quantities never become available at cancellation.
 perform refund_invoice_recorded(inv,jsonb_build_array(jsonb_build_object('invoice_item_id',item,'amount',160)),
  jsonb_build_array(jsonb_build_object('payment_id',pay2,'amount',160)),
  jsonb_build_array(jsonb_build_object('movement_id',movement,'damaged_quantity',1,'not_returned_quantity',1)),
  'One damaged and one not returned',gen_random_uuid());
 if (invoice_financial_position(inv)->>'outstanding')::numeric<>0 then raise exception 'Product refund created artificial debt'; end if;
 rid:=gen_random_uuid();
 perform cancel_invoice_recorded(inv,'Cancel remaining delivery',rid);
 perform cancel_invoice_recorded(inv,'Cancel remaining delivery',rid);
 if (select current_qty from store_inventory where store_id=st and product_id=p)<>98 then raise exception 'Cancellation restocked damaged/not-returned goods or repeated returns'; end if;
 if not (invoice_reopen_preview(inv)->>'can_reopen')::boolean then raise exception 'Reopening with an explicit replacement plan was blocked'; end if;
 if (select sum((s->>'quantity')::int) from jsonb_array_elements(invoice_reopen_preview(inv)->'stock_to_issue') s)<>9 then raise exception 'Reopening did not preview replacement of damaged units'; end if;
 -- Simple cancellation and full refund/reopen, with settlement replay.
 inv:=create_invoice_with_details(st,c,jsonb_build_array(jsonb_build_object('kind','product','product_id',p,'quantity',1)), '{"business_date":"2020-01-02"}');
 perform pay_invoice(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',100)));
 perform cancel_invoice_recorded(inv,'Cancel before collection',gen_random_uuid());
 rid:=gen_random_uuid();
 perform reopen_invoice(inv,'Customer continues purchase',rid);
 perform reopen_invoice(inv,'Customer continues purchase',rid);
 if (select current_qty from store_inventory where store_id=st and product_id=p)<>97 then raise exception 'Reopen duplicated stock'; end if;
 select id into pay1 from invoice_payments where invoice_id=inv;
 select id into item from invoice_items where invoice_id=inv;
 select id into movement from stock_movements where invoice_id=inv and movement_type='store_sale' and not exists(select 1 from stock_movements r where r.reversed_sale_id=stock_movements.id) limit 1;
 perform refund_invoice_recorded(inv,jsonb_build_array(jsonb_build_object('invoice_item_id',item,'amount',100)),
  jsonb_build_array(jsonb_build_object('payment_id',pay1,'amount',100)),
  jsonb_build_array(jsonb_build_object('movement_id',movement,'sellable_quantity',1)),'Returned unused',gen_random_uuid());
 if (select status::text from invoices where id=inv)<>'refunded' then raise exception 'Full refund did not close invoice'; end if;
 perform reopen_invoice(inv,'Repurchase after return',gen_random_uuid());
 if (select status::text from invoices where id=inv)<>'unpaid' then raise exception 'Refunded money counted as reopened settlement'; end if;
 perform record_invoice_payment(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',100)),gen_random_uuid());
 if (select current_qty from store_inventory where store_id=st and product_id=p)<>97 then raise exception 'Reopened payment did not issue exactly one'; end if;
 raise notice 'PASS: cancellation preserves damaged/non-returned stock; cancel/reopen retries; full refund and new settlement';

 -- FOC historical reason and price preservation.
 select id into f from foc_reasons where code='staff_welfare';
 inv:=create_invoice(st,c,null,jsonb_build_array(jsonb_build_object('kind','product','product_id',p,'quantity',2,'foc_quantity',1,'foc_reason_id',f,'foc_reason','Saved note')));
 perform pay_invoice(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',100)));
 select id,to_jsonb(i) into item,before_item from invoice_items i where invoice_id=inv;
 x:=jsonb_build_array(jsonb_build_object('invoice_item_id',item,'kind','product','product_id',p,'quantity',2,'foc_quantity',1,'foc_reason_id',f,'foc_reason','Staff Welfare — Saved note'));
 update foc_reasons set is_active=false where id=f;
 perform set_product_prices(st,p,999,999,'available');
 r:=correct_invoice(inv,x,'{}','Unchanged');
 if r->>'unchanged' is distinct from 'true' then raise exception 'Historical FOC no-op not detected'; end if;
 r:=correct_invoice(inv,x,'{"notes":"Unrelated note","service_staff":[]}','Unrelated metadata');
 if before_item is distinct from (select to_jsonb(i) from invoice_items i where id=item) then raise exception 'FOC/price snapshot changed'; end if;
 foreach status_text in array array['cancelled','refunded','refund_requested','cancellation_requested','completed_foc','partially_paid','paid','unpaid','draft'] loop
  update invoices set status=status_text::invoice_status where id=inv;
  r:=correct_invoice(inv,x,jsonb_build_object('notes','Note for '||status_text),'Status coverage');
  if status_text in ('cancelled','refunded','refund_requested','cancellation_requested') and r->>'status'<>status_text then raise exception 'Reactivated %',status_text; end if;
 end loop;
 raise notice 'PASS: saved inactive FOC reason, historical price, stable invoice_item_id, metadata edits across nine statuses';
 -- Paid 100 grants 120. Spend 60, then only 50 may be refunded.
 perform set_product_prices(st,p,100,100,'available');
 -- 'own' is no longer a permitted classification (243 made the third-party rate
 -- mandatory for package sales). The classification is incidental to what this
 -- block tests, which is proportional refund of a part-used package.
 -- allow_therapy as well as allow_product. Two independent gates now decide
 -- what package credit may buy: the per-package permissions this package was
 -- sold with, AND the mandatory matrix from 242. A package permitting only
 -- products can no longer spend its PAID credit at all -- the matrix forbids
 -- products from that balance -- so the package itself has to permit therapy.
 insert into credit_packages(name,customer_price,paid_credit_amount,commission_classification,allow_product,allow_therapy) values('Refund Package',100,120,'third_party',true,true) returning id into pkg;
 insert into credit_package_stores(package_id,store_id) values(pkg,st);
 cp_inv:=create_invoice(st,c,null,jsonb_build_array(jsonb_build_object('kind','credit_package','credit_package_id',pkg,'quantity',1)));
 perform pay_invoice(cp_inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',100)));
 select id into cp_item from invoice_items where invoice_id=cp_inv;
 select id,lot_id into b,lot from invoice_benefit_values where invoice_item_id=cp_item;
 if b is null then raise exception 'New credit benefit paid value not recorded'; end if;
 select id into walletpm from payment_methods where wallet_category='paid' and is_system limit 1;
 -- The spend is a THERAPY SESSION, not a product, and that is the point.
 -- Credit-package paid credit may fund therapy sessions and therapy-session
 -- vouchers and nothing else (242). This block used to spend it on a product,
 -- which the matrix now refuses -- correctly. Buying a session keeps every
 -- assertion below intact and makes this the place where the invoice refund
 -- lifecycle and the therapy-service rules are exercised together.
 --
 -- Stock is not part of this block's purpose; sellable, damaged and
 -- not-returned refunds are asserted above at the product invoices.
 svc:=(upsert_therapy_service(null,'RGN-PR','Regression Session',100,30,'per_hours',1,5,null,true,null)->>'id')::uuid;
 perform set_therapy_service_store(svc,st,true,null);
 spend:=create_invoice(st,c,null,jsonb_build_array(jsonb_build_object('kind','therapy','therapy_service_id',svc,'quantity',1)));
 perform record_invoice_payment(spend,jsonb_build_array(jsonb_build_object('payment_method_id',walletpm,'amount',60),jsonb_build_object('payment_method_id',pm,'amount',40)),gen_random_uuid());
 if (select remaining_amount from customer_credit_lots where id=lot)<>60 then raise exception 'Wallet did not use exact originating lot'; end if;
 select id into wp from invoice_payments where invoice_id=spend and payment_method_id=walletpm;
 if not exists(select 1 from invoice_line_credit_allocations where payment_id=wp and lot_id=lot) then raise exception 'Wallet payment source was not linked'; end if;
 r:=correct_invoice_payment(wp,60,'2020-03-01',walletpm,'Correct wallet receipt date',gen_random_uuid());
 wp:=(r->>'replacement_id')::uuid;
 if (select remaining_amount from customer_credit_lots where id=lot)<>60 then raise exception 'Wallet payment correction duplicated or lost credit'; end if;
 select id into pay1 from invoice_payments where invoice_id=cp_inv;
 begin
  perform refund_invoice_recorded(cp_inv,jsonb_build_array(jsonb_build_object('invoice_item_id',cp_item,'amount',51,'benefits',jsonb_build_array(jsonb_build_object('benefit_id',b,'amount',51)))),
   jsonb_build_array(jsonb_build_object('payment_id',pay1,'amount',51)),'[]','Too much',gen_random_uuid());
  raise exception 'Bonus over-refund accepted';
 exception when others then if sqlerrm not like '%unused paid value%' then raise; end if; end;
 perform refund_invoice_recorded(cp_inv,jsonb_build_array(jsonb_build_object('invoice_item_id',cp_item,'amount',50,'benefits',jsonb_build_array(jsonb_build_object('benefit_id',b,'amount',50)))),
  jsonb_build_array(jsonb_build_object('payment_id',pay1,'amount',50)),'[]','Unused half refunded',gen_random_uuid());
 if (select remaining_amount from customer_credit_lots where id=lot)<>0 then raise exception 'Refunded unused credit remains spendable'; end if;
 if (select status::text from invoices where id=cp_inv)='refunded' then raise exception 'Partly consumed package presented as fully refunded'; end if;
 select id into item from invoice_items where invoice_id=spend;
 select id into cashpay from invoice_payments where invoice_id=spend and payment_method_id=pm;
 -- A part refund of a session is refused: 252 requires whole sessions at their
 -- original paid value. Assert that, then refund the session properly.
 begin
  perform refund_invoice_recorded(spend,jsonb_build_array(jsonb_build_object('invoice_item_id',item,'amount',30)),
   jsonb_build_array(jsonb_build_object('payment_id',wp,'amount',30)),'[]','Part of a session',gen_random_uuid());
  raise exception 'Part-refund of a therapy session accepted';
 exception when others then if sqlerrm not like '%whole unused therapy sessions%' then raise; end if; end;
 perform refund_invoice_recorded(spend,jsonb_build_array(jsonb_build_object('invoice_item_id',item,'amount',100)),
  jsonb_build_array(jsonb_build_object('payment_id',wp,'amount',60),jsonb_build_object('payment_id',cashpay,'amount',40)),
  '[]','Session returned',gen_random_uuid());
 -- The credit half goes back to the lot it came from, in its original category.
 if (select remaining_amount from customer_credit_lots where id=lot)<>60 then raise exception 'Credit refund did not return to origin'; end if;
 if (select sum(credit_returned) from invoice_refunds where invoice_id=spend)<>60 then raise exception 'Wallet return classified as cash'; end if;
 -- And the entitlement it bought is reconciled, not left standing.
 if (select quantity_refunded from customer_therapy_sessions where invoice_item_id=item)<>1 then
  raise exception 'Refunded session still counted as purchased'; end if;
 if exists(select 1 from customer_therapy_session_balance(c) where service_id=svc) then
  raise exception 'Refunded session still available to the customer'; end if;
 raise notice 'PASS: 100 paid / 120 credit / 60 unused => maximum refund 50; package paid credit funds a therapy session, part-refund of a session refused, whole refund returns to the originating lot and reconciles the entitlement';

end $$;
rollback;
