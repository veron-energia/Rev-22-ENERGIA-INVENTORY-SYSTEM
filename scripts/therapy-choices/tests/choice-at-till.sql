-- Choosing the benefit while the invoice is being prepared, or not at all.
--
-- The choice made at the till is an INTENT on the line. Nothing is issued and
-- nothing starts when it is recorded: the units do not exist until the invoice
-- is paid, and the intent is then applied through the same checks a later
-- choice goes through. "Choose later" is the absence of an intent.
--
-- Disposable database only; everything is rolled back.
begin;
do $$
declare own uuid:=gen_random_uuid(); st uuid; c uuid; pm uuid; pkg uuid; inv uuid;
 v1 uuid; v2 uuid; svc uuid; r jsonb; n int; u_t uuid; u_v uuid; u_l uuid;
begin
 insert into auth.users(id,email) values(own,'cat@tests.invalid');
 insert into profiles(id,full_name,email,role) values(own,'Owner','cat@tests.invalid','owner');
 perform set_config('request.jwt.claim.sub',own::text,true);
 insert into stores(name,code,country_code) values('CAT Store','CAT','SG') returning id into st;
 insert into customers(full_name,phone) values('CAT Buyer','+6598923001') returning id into c;
 insert into payment_methods(name) values('CAT Cash') returning id into pm;
 insert into vouchers(name,code,voucher_kind,qty_type,selling_price,is_active)
  values('CAT Facial','CATF','normal','limited',50,true) returning id into v1;
 insert into vouchers(name,code,voucher_kind,qty_type,selling_price,is_active)
  values('CAT Massage','CATM','normal','limited',50,true) returning id into v2;
 insert into voucher_store_stock(voucher_id,store_id,current_qty) values(v1,st,50),(v2,st,50);
 svc:=(upsert_therapy_service(null,'CAT-PR','CAT Session',50,30,'per_hours',1,5,null,true,null)->>'id')::uuid;
 perform set_therapy_service_store(svc,st,true,null);
 pkg:=upsert_therapy_package_choice(null,'Package C','PKG-C3',null,true,1,10,array[v1,v2],array[svc]);
 insert into unlimited_therapy_store_prices(package_id,store_id,selling_price,available_at_store)
  values(pkg,st,500,true);

 -- Three units: one says therapy, one says vouchers, one chooses later.
 inv:=create_invoice(st,c,null,jsonb_build_array(
   jsonb_build_object('kind','therapy','therapy_package_id',pkg,'quantity',1,'therapy_benefit_intent','unlimited'),
   jsonb_build_object('kind','therapy','therapy_package_id',pkg,'quantity',1,'therapy_benefit_intent','voucher'),
   jsonb_build_object('kind','therapy','therapy_package_id',pkg,'quantity',1)));

 -- ---- before payment, nothing exists at all -------------------------------
 select count(*) into n from purchased_therapy_entitlements where invoice_id=inv;
 if n<>0 then raise exception 'Units were created before the invoice was paid'; end if;
 select count(*) into n from therapy_entitlements where claim_source_invoice_id=inv;
 if n<>0 then raise exception 'A voucher allowance was created before payment'; end if;
 -- the intent is on the line, and only that
 select count(*) into n from invoice_items where invoice_id=inv and therapy_benefit_intent is not null;
 if n<>2 then raise exception 'Expected two lines carrying an intent, got %', n; end if;

 perform pay_invoice(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',1500)));

 -- ---- after payment the intents are honoured ------------------------------
 select purchased_id into u_t from purchased_therapy_units(st,c)
  where benefit_choice='unlimited';
 select purchased_id into u_v from purchased_therapy_units(st,c)
  where benefit_choice='voucher';
 select purchased_id into u_l from purchased_therapy_units(st,c)
  where choice_pending;
 if u_t is null or u_v is null or u_l is null then
  raise exception 'Expected one therapy unit, one voucher unit and one still pending'; end if;

 -- choosing at the till still does not start therapy
 r:=purchased_therapy_unit_state(u_t);
 if (r->>'status')<>'pending_activation' or (r->>'activation_date') is not null then
  raise exception 'The till choice started the therapy'; end if;

 -- the voucher unit has an allowance, unclaimed
 r:=purchased_therapy_unit_state(u_v);
 if (r->'vouchers'->>'entitled')::int<>10 or (r->'vouchers'->>'claimed')::int<>0 then
  raise exception 'The voucher allowance is wrong at the till'; end if;
 -- and no voucher has been issued to the customer yet
 select count(*) into n from customer_reward_vouchers
  where entitlement_id=(r->>'voucher_entitlement_id')::uuid;
 if n<>0 then raise exception 'Vouchers were issued before being claimed'; end if;

 -- the "choose later" unit is pending and offers both
 r:=purchased_therapy_unit_state(u_l);
 if not (r->>'choice_pending')::boolean then raise exception 'The choose-later unit is not pending'; end if;
 if jsonb_array_length(r->'offered_choices')<>2 then
  raise exception 'The choose-later unit lost its options'; end if;
 -- and it is not counted as anything yet
 if (r->>'voucher_entitlement_id') is not null then
  raise exception 'A pending unit already has an allowance'; end if;

 -- it can still be chosen afterwards, in the Purchased area
 r:=choose_therapy_benefit(u_l,'voucher',gen_random_uuid(),'chosen later');
 if (r->'state'->'vouchers'->>'entitled')::int<>10 then
  raise exception 'Choosing later did not create the allowance'; end if;

 -- ---- an intent the package never offered is not forced -------------------
 -- A voucher-only package with an 'unlimited' intent must stay as it was sold.
 declare pkg2 uuid; inv2 uuid; u2 uuid; begin
  pkg2:=upsert_unlimited_therapy_package(null,'Voucher only',1,null,true,'voucher',5,v1);
  insert into unlimited_therapy_store_prices(package_id,store_id,selling_price,available_at_store)
   values(pkg2,st,200,true);
  inv2:=create_invoice(st,c,null,jsonb_build_array(jsonb_build_object(
    'kind','therapy','therapy_package_id',pkg2,'quantity',1,'therapy_benefit_intent','unlimited')));
  perform pay_invoice(inv2,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',200)));
  select id into u2 from purchased_therapy_entitlements where invoice_id=inv2;
  if (select benefit_choice from purchased_therapy_entitlements where id=u2)<>'voucher' then
   raise exception 'An impossible intent overrode what the package grants'; end if;
 end;

 raise notice 'PASS: the till choice is an intent that issues nothing before payment, is honoured once units exist, leaves choose-later pending and choosable afterwards, and is ignored when the package never offered it';
end $$;
rollback;
