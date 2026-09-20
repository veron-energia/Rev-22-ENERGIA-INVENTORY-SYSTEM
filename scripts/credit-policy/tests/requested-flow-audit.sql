-- Acceptance audit, 2026-09-15. Disposable local database only; always rollback.
begin;
do $$
declare o uuid:=gen_random_uuid(); st uuid; a uuid; b uuid; c uuid; pm uuid;
 cp uuid; pb uuid; v uuid; inv uuid; inv2 uuid; it uuid; lot uuid; bonus uuid;
 svc uuid; product uuid; third uuid; paidpm uuid; bonuspm uuid; spend uuid;
 payload jsonb; result jsonb; e uuid; before_other numeric; message text;
begin
 insert into auth.users(id,email) values(o,'requested-audit@tests.invalid');
 insert into profiles(id,full_name,email,role) values(o,'Audit Owner','requested-audit@tests.invalid','owner');
 perform set_config('request.jwt.claim.sub',o::text,true);
 insert into stores(name,code,country_code) values('Requested Audit','RQA','SG') returning id into st;
 insert into customers(full_name,phone) values('Audit A','+6598987101') returning id into a;
 insert into customers(full_name,phone) values('Audit B','+6598987102') returning id into b;
 insert into customers(full_name,phone) values('Audit C','+6598987103') returning id into c;
 insert into payment_methods(name) values('Audit Cash') returning id into pm;
 select id into paidpm from payment_methods where wallet_category='paid' and is_system limit 1;
 select id into bonuspm from payment_methods where wallet_category='bonus' and is_system limit 1;
 insert into credit_packages(name,customer_price,paid_credit_amount,bonus_enabled,bonus_mode,bonus_value,allow_product,allow_therapy,effective_from)
 values('Audit Package',500,500,true,'fixed',200,true,true,current_date) returning id into cp;
 insert into credit_package_stores(package_id,store_id) values(cp,st);
 inv:=create_invoice(st,a,null,jsonb_build_array(jsonb_build_object('kind','credit_package','credit_package_id',cp,'quantity',1)));
 perform record_invoice_payment(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',500)),gen_random_uuid());
 select id into it from invoice_items where invoice_id=inv;
 inv2:=create_invoice(st,c,null,jsonb_build_array(jsonb_build_object('kind','credit_package','credit_package_id',cp,'quantity',1)));
 perform record_invoice_payment(inv2,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',500)),gen_random_uuid());
 select sum(remaining_amount) into before_other from customer_credit_lots where customer_id=c;
 -- Real payment checks with sufficient balances, rolled back before reassignment.
 begin
  svc:=(upsert_therapy_service(null,'RQA-S','Audit Service',50,30,'per_hours',1,5,null,true,null)->>'id')::uuid;
  perform set_therapy_service_store(svc,st,true,null);
  insert into products(name,sku,product_type) values('Audit Own','RQA-O','own') returning id into product;
  insert into products(name,sku,product_type) values('Audit Third','RQA-T','third_party') returning id into third;
  insert into store_inventory(store_id,product_id,current_qty) values(st,product,10),(st,third,10);
  perform set_product_prices(st,product,50,50,'available');
  perform set_product_prices(st,third,50,50,'available');
  spend:=create_invoice(st,a,null,jsonb_build_array(jsonb_build_object('kind','therapy','therapy_service_id',svc,'quantity',1)));
  begin
   perform record_invoice_payment(spend,jsonb_build_array(jsonb_build_object('payment_method_id',bonuspm,'amount',50)),gen_random_uuid());
   raise exception 'FAIL: Bonus credit purchased service therapy';
  exception when others then if sqlerrm not like '%eligible credit%' then raise; end if; end;
  perform record_invoice_payment(spend,jsonb_build_array(jsonb_build_object('payment_method_id',paidpm,'amount',50)),gen_random_uuid());
  foreach product in array array[product,third] loop
   spend:=create_invoice(st,a,null,jsonb_build_array(jsonb_build_object('kind','product','product_id',product,'quantity',1)));
   begin
    perform record_invoice_payment(spend,jsonb_build_array(jsonb_build_object('payment_method_id',paidpm,'amount',50)),gen_random_uuid());
    raise exception 'FAIL: Paid credit purchased a product';
   exception when others then if sqlerrm not like '%eligible credit%' then raise; end if; end;
   perform record_invoice_payment(spend,jsonb_build_array(jsonb_build_object('payment_method_id',bonuspm,'amount',50)),gen_random_uuid());
  end loop;
  -- coalesce: sum() over no rows is NULL, NULL <> n is NULL, and PL/pgSQL
  -- takes the false branch on NULL — so this assertion used to pass on
  -- exactly the regression it guards.
  if coalesce((select sum(remaining_amount) from customer_credit_lots where customer_id=a and category='paid'), -1)<>450
   or coalesce((select sum(remaining_amount) from customer_credit_lots where customer_id=a and category='bonus'), -1)<>100 then
   raise exception 'FAIL: Payment balances incorrect'; end if;
  raise notice 'PASS: Paid buys service therapy, rejects both product types; bonus buys both product types, rejects therapy while sufficient balance exists; balances correct';
  raise exception using errcode='PZ001',message='Rollback successful payment cases before customer audit';
 exception when sqlstate 'PZ001' then null; end;
 payload:=jsonb_build_array(jsonb_build_object('invoice_item_id',it,'kind','credit_package','credit_package_id',cp,'quantity',1));
 begin
  result:=correct_invoice(inv,payload,jsonb_build_object('customer_id',b),'Acceptance audit: change customer',gen_random_uuid());
  raise notice 'CUSTOMER CHANGE: accepted; invoice customer changed=%; A balance=%; B balance=%; unrelated C balance=% (expected %)',
    (select customer_id=b from invoices where id=inv),
    (select coalesce(sum(remaining_amount),0) from customer_credit_lots where customer_id=a),
    (select coalesce(sum(remaining_amount),0) from customer_credit_lots where customer_id=b),
    (select coalesce(sum(remaining_amount),0) from customer_credit_lots where customer_id=c),before_other;
 exception when others then
  raise notice 'CUSTOMER CHANGE REFUSED: %',sqlerrm;
 end;
 -- Exercise the explicit recipient-review route if ordinary correction refused.
 if (select customer_id from invoices where id=inv)=a then
  begin
   result:=correct_invoice(inv,payload,jsonb_build_object('customer_id',b,'preserve_issued_recipients',true),'Acceptance audit: reviewed customer change',gen_random_uuid());
   raise notice 'REVIEWED CUSTOMER CHANGE: accepted; A balance=%; B balance=%; unrelated C balance=% (expected %)',
    (select coalesce(sum(remaining_amount),0) from customer_credit_lots where customer_id=a),
    (select coalesce(sum(remaining_amount),0) from customer_credit_lots where customer_id=b),
    (select coalesce(sum(remaining_amount),0) from customer_credit_lots where customer_id=c),before_other;
  exception when others then raise notice 'REVIEWED CUSTOMER CHANGE REFUSED: %',sqlerrm; end;
 end if;
 select id into lot from customer_credit_lots where customer_id=b and category='paid' and remaining_amount>0 limit 1;
 if lot is not null then
  raise notice 'MOVED PAID CREDIT: therapy eligibility=% (expected true)',credit_lot_allows_category(lot,'therapy_session');
 end if;

 insert into vouchers(name,code,voucher_kind,qty_type,selling_price,is_active,reward_eligible)
 values('Audit Voucher','RQA-V','normal','limited',50,true,true) returning id into v;
 insert into voucher_store_stock(voucher_id,store_id,current_qty) values(v,st,100);
 insert into premium_bundles(name,customer_payment_amount,paid_credit_amount,bonus_credit_amount,grants_reward,free_voucher_qty)
 values('Audit Bundle',200,150,50,true,10) returning id into pb;
 insert into premium_bundle_stores(bundle_id,store_id) values(pb,st);
 insert into premium_bundle_vouchers(bundle_id,voucher_id) values(pb,v);
 begin
  spend:=create_invoice(st,a,null,jsonb_build_array(jsonb_build_object('kind','premium_bundle','premium_bundle_id',pb,'quantity',1,'voucher_selection','[]'::jsonb)));
  perform record_invoice_payment(spend,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',200)),gen_random_uuid());
  select id into e from therapy_entitlements where claim_source_invoice_id=spend;
  if e is null then raise exception 'No deferred entitlement created'; end if;
  result:=claim_entitlement_vouchers(e,jsonb_build_array(jsonb_build_object('voucher_id',v,'quantity',3)),'Collect later');
  if (result->'state'->>'remaining')::int<>7 then raise exception 'Expected 7 remaining: %',result; end if;
  raise notice 'PASS: Premium Bundle bought without selecting vouchers; later collected 3, 7 remain';
 exception when others then raise notice 'FAIL: Premium Bundle buy now / choose later: %',sqlerrm; end;
end $$;
rollback;
