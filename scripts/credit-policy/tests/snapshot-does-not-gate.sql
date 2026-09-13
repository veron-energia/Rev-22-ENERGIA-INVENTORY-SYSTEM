-- A package's OLD category snapshot must not overrule the Owner's rules.
--
-- 94 froze each package's allow_* flags onto every lot it granted, so that
-- editing the package could not change what issued credit may buy. The rules
-- added in 309 are required to do exactly that, and the two were ANDed: the
-- snapshot could only ever narrow the Owner's decision.
--
-- The package here is voucher-only — which is what 94's backfill produced for
-- every package that had nothing ticked. Its paid credit is worth 100, the
-- default rule says it may buy an individual therapy session, and before the
-- fix the snapshot said "voucher only" and the customer could spend nothing.
--
-- Disposable database only; everything is rolled back.
begin;
do $$
declare own uuid:=gen_random_uuid(); st uuid; c uuid; pm uuid; wpm_paid uuid; wpm_bonus uuid;
 cp uuid; inv uuid; spend uuid; svc uuid; own_p uuid; v1 uuid;
 paid_lot uuid; bonus_lot uuid;
begin
 insert into auth.users(id,email) values(own,'sg-own@tests.invalid');
 insert into profiles(id,full_name,email,role) values(own,'Owner','sg-own@tests.invalid','owner');
 perform set_config('request.jwt.claim.sub',own::text,true);
 insert into stores(name,code,country_code) values('SG Store','SGS','SG') returning id into st;
 insert into customers(full_name,phone) values('SG Buyer','+6598912001') returning id into c;
 insert into payment_methods(name) values('SG Cash') returning id into pm;
 select id into wpm_paid  from payment_methods where wallet_category='paid'  and is_system limit 1;
 select id into wpm_bonus from payment_methods where wallet_category='bonus' and is_system limit 1;

 insert into products(name,sku,product_type) values('SG Own','SG-OWN','own') returning id into own_p;
 insert into store_inventory(store_id,product_id,current_qty) values(st,own_p,50);
 perform set_product_prices(st,own_p,50,50,'available');
 svc:=(upsert_therapy_service(null,'SG-PR','SG Session',50,30,'per_hours',1,5,null,true,null)->>'id')::uuid;
 perform set_therapy_service_store(svc,st,true,null);

 -- Voucher-only, exactly as 94's backfill leaves an unconfigured package.
 insert into credit_packages(name,customer_price,paid_credit_amount,bonus_enabled,bonus_mode,bonus_value,
                             allow_voucher,effective_from)
   values('SG Voucher-only',100,100,true,'fixed',50,true,current_date) returning id into cp;
 insert into credit_package_stores(package_id,store_id) values(cp,st);

 inv:=create_invoice(st,c,null,jsonb_build_array(jsonb_build_object('kind','credit_package','credit_package_id',cp,'quantity',1)));
 perform pay_invoice(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',100)));
 select id into paid_lot  from customer_credit_lots where customer_id=c and category='paid'  and source_type='credit_package';
 select id into bonus_lot from customer_credit_lots where customer_id=c and category='bonus' and source_type='credit_package';

 -- The snapshot really is the restrictive one; this is not a vacuous test.
 if credit_lot_allows((select usage_restrictions from customer_credit_lots where id=paid_lot),'therapy',null) then
  raise exception 'Fixture is wrong: the snapshot was expected to forbid therapy'; end if;

 -- ---- the Owner's rule decides, not the snapshot ---------------------------
 if not credit_lot_allows_category(paid_lot,'therapy_session') then
  raise exception 'The default rule should let paid credit buy a therapy session'; end if;

 spend:=create_invoice(st,c,null,jsonb_build_array(jsonb_build_object('kind','therapy','therapy_service_id',svc,'quantity',1)));
 perform record_invoice_payment(spend,jsonb_build_array(jsonb_build_object('payment_method_id',wpm_paid,'amount',50)),gen_random_uuid());
 if (select remaining_amount from customer_credit_lots where id=paid_lot)<>50 then
  raise exception 'Paid credit did not fund the therapy session; the snapshot is still gating'; end if;

 -- Bonus credit may buy an own-brand product by default, likewise.
 spend:=create_invoice(st,c,null,jsonb_build_array(jsonb_build_object('kind','product','product_id',own_p,'quantity',1)));
 perform record_invoice_payment(spend,jsonb_build_array(jsonb_build_object('payment_method_id',wpm_bonus,'amount',50)),gen_random_uuid());
 if (select remaining_amount from customer_credit_lots where id=bonus_lot)<>0 then
  raise exception 'Bonus credit did not fund the own-brand product'; end if;

 -- ---- and it still narrows where the rules say no --------------------------
 -- Paid credit must not buy a product, whatever the snapshot allowed.
 spend:=create_invoice(st,c,null,jsonb_build_array(jsonb_build_object('kind','product','product_id',own_p,'quantity',1)));
 begin
  perform record_invoice_payment(spend,jsonb_build_array(jsonb_build_object('payment_method_id',wpm_paid,'amount',50)),gen_random_uuid());
  raise exception 'Paid credit bought a product against the rules';
 exception when others then if sqlerrm not like '%eligible credit%' then raise; end if; end;

 raise notice 'snapshot-does-not-gate: OK';
end $$;
rollback;
