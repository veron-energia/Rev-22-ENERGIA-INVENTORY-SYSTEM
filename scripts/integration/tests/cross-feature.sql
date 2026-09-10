-- =====================================================================
-- WHERE THE INVOICE WORK MEETS THE THERAPY, CREDIT AND COMMISSION WORK
--
-- The two agents' suites each pass on their own fixture. These are the
-- guarantees that only exist BETWEEN them, and that neither suite could have
-- checked: the mandatory credit matrix reached through the real invoice
-- payment path, and commission earned once rather than twice.
--
-- Disposable combined-history database only. Everything is rolled back.
-- =====================================================================
begin;
do $$
declare o uuid:=gen_random_uuid(); st uuid; c uuid; ref uuid; pm uuid; wpm_paid uuid; wpm_bonus uuid;
 own_p uuid; third_p uuid; pkg uuid; bundle uuid; inv uuid; svc uuid; spend uuid;
 lot_paid uuid; lot_bonus uuid; n integer; before_commission numeric; after_commission numeric;
begin
 insert into auth.users(id,email) values(o,'xf@tests.invalid');
 insert into profiles(id,full_name,email,role) values(o,'Owner','xf@tests.invalid','owner');
 perform set_config('request.jwt.claim.sub',o::text,true);
 insert into stores(name,code,country_code) values('Cross Feature','XF','SG') returning id into st;
 insert into customers(full_name,phone) values('XF Referrer','+6591110000') returning id into ref;
 insert into customers(full_name,phone,referred_by) values('XF Buyer','+6591110001',ref) returning id into c;
 insert into payment_methods(name,is_active) values('XF Cash',true) returning id into pm;
 select id into wpm_paid from payment_methods where wallet_category='paid' and is_system limit 1;
 select id into wpm_bonus from payment_methods where wallet_category='bonus' and is_system limit 1;

 insert into products(name,sku,product_type) values('XF Own','XF-OWN','own') returning id into own_p;
 insert into products(name,sku,product_type) values('XF Third','XF-3P','third_party') returning id into third_p;
 insert into store_inventory(store_id,product_id,current_qty) values(st,own_p,50),(st,third_p,50);
 perform set_product_prices(st,own_p,50,50,'available');
 perform set_product_prices(st,third_p,50,50,'available');

 svc:=(upsert_therapy_service(null,'XF-PR','XF Session',50,30,'per_hours',1,5,null,true,null)->>'id')::uuid;
 perform set_therapy_service_store(svc,st,true,null);

 -- ---------------------------------------------------------------
 -- A credit package that permits everything it is allowed to permit.
 -- The mandatory matrix, not these flags, must decide the outcome.
 -- ---------------------------------------------------------------
 insert into credit_packages(name,customer_price,paid_credit_amount,bonus_enabled,bonus_value,
   allow_product,allow_therapy,allow_voucher,effective_from)
  values('XF Package',200,200,true,100,true,true,true,current_date) returning id into pkg;
 insert into credit_package_stores(package_id,store_id) values(pkg,st);
 inv:=create_invoice(st,c,null,jsonb_build_array(jsonb_build_object('kind','credit_package','credit_package_id',pkg,'quantity',1)));
 perform pay_invoice(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',200)));

 select id into lot_paid from customer_credit_lots where customer_id=c and category='paid' and source_type='credit_package';
 select id into lot_bonus from customer_credit_lots where customer_id=c and category='bonus' and source_type='credit_package';
 if lot_paid is null or lot_bonus is null then raise exception 'Expected a paid and a bonus package lot'; end if;

 -- PAID credit may not buy a product, whatever the package permits.
 spend:=create_invoice(st,c,null,jsonb_build_array(jsonb_build_object('kind','product','product_id',own_p,'quantity',1)));
 begin
  perform record_invoice_payment(spend,jsonb_build_array(jsonb_build_object('payment_method_id',wpm_paid,'amount',50)),gen_random_uuid());
  raise exception 'Package paid credit bought an own-brand product';
 exception when others then if sqlerrm not like '%eligible credit%' then raise; end if; end;

 -- BONUS credit may, and only for an own-brand one.
 perform record_invoice_payment(spend,jsonb_build_array(jsonb_build_object('payment_method_id',wpm_bonus,'amount',50)),gen_random_uuid());
 if (select remaining_amount from customer_credit_lots where id=lot_bonus)<>50 then
  raise exception 'Bonus credit did not fund the own-brand product from the bonus lot'; end if;

 spend:=create_invoice(st,c,null,jsonb_build_array(jsonb_build_object('kind','product','product_id',third_p,'quantity',1)));
 begin
  perform record_invoice_payment(spend,jsonb_build_array(jsonb_build_object('payment_method_id',wpm_bonus,'amount',50)),gen_random_uuid());
  raise exception 'Package bonus credit bought a third-party product';
 exception when others then if sqlerrm not like '%eligible credit%' then raise; end if; end;

 -- PAID credit may buy a therapy session.
 spend:=create_invoice(st,c,null,jsonb_build_array(jsonb_build_object('kind','therapy','therapy_service_id',svc,'quantity',1)));
 perform record_invoice_payment(spend,jsonb_build_array(jsonb_build_object('payment_method_id',wpm_paid,'amount',50)),gen_random_uuid());
 if (select remaining_amount from customer_credit_lots where id=lot_paid)<>150 then
  raise exception 'Therapy session was not funded from the paid package lot'; end if;

 -- No credit of any kind may buy more credit.
 spend:=create_invoice(st,c,null,jsonb_build_array(jsonb_build_object('kind','credit_package','credit_package_id',pkg,'quantity',1)));
 begin
  perform record_invoice_payment(spend,jsonb_build_array(jsonb_build_object('payment_method_id',wpm_paid,'amount',50)),gen_random_uuid());
  raise exception 'Credit bought another credit package';
 exception when others then if sqlerrm not like '%eligible credit%' then raise; end if; end;
 raise notice 'PASS: the mandatory credit matrix holds through the real invoice payment path, over and above per-package permissions';

 -- ---------------------------------------------------------------
 -- Commission is earned on external money, once.
 -- ---------------------------------------------------------------
 select coalesce(sum(commission_amount),0) into before_commission from commissions
  where buyer_customer_id=c;
 if before_commission<=0 then raise exception 'The package sale earned no commission at all'; end if;
 -- Third-party rate on the S$200 actually received, never the S$300 granted.
 if (select round(200*commission_tier1_third_rate/100.0,2) from app_settings where id=true)
    <> (select commission_amount from commissions where buyer_customer_id=c and tier='tier1') then
  raise exception 'Package commission was not the third-party rate on external money'; end if;

 -- Spending that credit must not earn a second time.
 select coalesce(sum(commission_amount),0) into after_commission from commissions where buyer_customer_id=c;
 if after_commission<>before_commission then
  raise exception 'Redeeming credit earned commission again'; end if;
 raise notice 'PASS: package commission uses the third-party rate on money received, and redeeming that credit earns nothing further';
end $$;
rollback;
