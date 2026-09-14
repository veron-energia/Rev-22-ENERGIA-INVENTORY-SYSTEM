-- A package the customer chooses the benefit of.
--
-- Runs the whole path through the real invoice functions: a choice package is
-- configured, two units are bought on one line, each takes a different benefit,
-- and the terms each unit was sold with survive a later edit to the package.
--
-- Disposable database only; everything is rolled back.
begin;
do $$
declare own uuid:=gen_random_uuid(); st uuid; c uuid; pm uuid; pkg uuid; inv uuid;
 v1 uuid; v2 uuid; v3 uuid; svc uuid; u1 uuid; u2 uuid; r jsonb; n int; offer jsonb;
begin
 insert into auth.users(id,email) values(own,'tcp@tests.invalid');
 insert into profiles(id,full_name,email,role) values(own,'Owner','tcp@tests.invalid','owner');
 perform set_config('request.jwt.claim.sub',own::text,true);
 insert into stores(name,code,country_code) values('TCP Store','TCP','SG') returning id into st;
 insert into customers(full_name,phone) values('TCP Buyer','+6598921001') returning id into c;
 insert into payment_methods(name) values('TCP Cash') returning id into pm;
 insert into vouchers(name,code,voucher_kind,qty_type,selling_price,is_active)
  values('TCP Facial','TCPF','normal','limited',50,true) returning id into v1;
 insert into vouchers(name,code,voucher_kind,qty_type,selling_price,is_active)
  values('TCP Massage','TCPM','normal','limited',50,true) returning id into v2;
 insert into vouchers(name,code,voucher_kind,qty_type,selling_price,is_active)
  values('TCP Other','TCPO','normal','limited',50,true) returning id into v3;
 insert into voucher_store_stock(voucher_id,store_id,current_qty) values(v1,st,50),(v2,st,50),(v3,st,50);
 svc:=(upsert_therapy_service(null,'TCP-PR','TCP Session',50,30,'per_hours',1,5,null,true,null)->>'id')::uuid;
 perform set_therapy_service_store(svc,st,true,null);

 -- ---- configuring a choice package ----------------------------------------
 pkg:=upsert_therapy_package_choice(null,'Package C','PKG-C','One month or ten vouchers',
        true,1,10,array[v1,v2],array[svc]);
 offer:=therapy_package_offer(pkg);
 if not (offer->>'offers_choice')::boolean then raise exception 'Package C does not offer a choice'; end if;
 if offer->>'unlimited_label' <> 'Unlimited therapy — 1 calendar month' then
  raise exception 'Wrong therapy label: %', offer->>'unlimited_label'; end if;
 if offer->>'voucher_label' <> 'Vouchers — 10 vouchers' then
  raise exception 'Wrong voucher label: %', offer->>'voucher_label'; end if;
 if jsonb_array_length(offer->'eligible_vouchers')<>2 then
  raise exception 'Expected two eligible vouchers'; end if;

 -- a choice package needs both sides to be real
 begin
  perform upsert_therapy_package_choice(null,'Bad','BAD',null,true,1,0,array[v1],null);
  raise exception 'A choice package with no voucher allowance was accepted';
 exception when others then
  if sqlerrm not like '%how many vouchers%' then raise; end if; end;

 -- ---- buying two units on one line ----------------------------------------
 insert into unlimited_therapy_store_prices(package_id,store_id,selling_price,available_at_store)
  values(pkg,st,500,true);
 -- A therapy line is always quantity 1, so two units are two lines.
 inv:=create_invoice(st,c,null,jsonb_build_array(
        jsonb_build_object('kind','therapy','therapy_package_id',pkg,'quantity',1),
        jsonb_build_object('kind','therapy','therapy_package_id',pkg,'quantity',1)));
 perform pay_invoice(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',1000)));

 select count(*) into n from purchased_therapy_entitlements where invoice_id=inv;
 if n<>2 then raise exception 'Expected two independent units, got %', n; end if;

 select purchased_id into u1 from purchased_therapy_units(st,c) where unit_index=1;
 select purchased_id into u2 from purchased_therapy_units(st,c) where unit_index=2;

 -- ---- each unit is pending, and says so without being an error ------------
 r:=purchased_therapy_unit_state(u1);
 if not (r->>'choice_pending')::boolean then raise exception 'Unit 1 is not pending'; end if;
 if r->>'unit_label' <> 'Package C — Unit 1 of 2' then
  raise exception 'Wrong unit label: %', r->>'unit_label'; end if;
 if jsonb_array_length(r->'offered_choices')<>2 then
  raise exception 'Unit 1 was not sold both choices'; end if;
 if (r->>'voucher_qty')::int<>10 then raise exception 'Voucher allowance not snapshotted'; end if;

 -- a pending unit is not therapy and not vouchers
 if (r->>'benefit_choice') is not null then raise exception 'A pending unit already has a benefit'; end if;
 if (r->>'voucher_entitlement_id') is not null then
  raise exception 'A pending unit already has a voucher allowance'; end if;

 -- ---- therapy cannot start before a choice is made ------------------------
 begin
  perform activate_purchased_therapy(u1,sg_today(),'too early',null,null,true);
  raise exception 'Therapy activated on a unit with no chosen benefit';
 exception when others then
  if sqlerrm not like '%Choose a benefit%' then raise; end if; end;

 -- ---- unit 1 takes therapy, unit 2 takes vouchers -------------------------
 r:=choose_therapy_benefit(u1,'unlimited',gen_random_uuid(),'customer chose therapy');
 if r->'state'->>'benefit_choice' <> 'unlimited' then raise exception 'Unit 1 choice not recorded'; end if;
 -- choosing does not start it
 if (r->'state'->>'activation_date') is not null or (r->'state'->>'status')<>'pending_activation' then
  raise exception 'Choosing therapy started it'; end if;

 r:=choose_therapy_benefit(u2,'voucher',gen_random_uuid(),'customer chose vouchers');
 if (r->>'voucher_entitlement_id') is null then raise exception 'No voucher allowance created'; end if;
 if (r->'state'->'vouchers'->>'entitled')::int<>10 then
  raise exception 'Voucher allowance is not 10'; end if;
 if (r->'state'->'vouchers'->>'remaining')::int<>10 then
  raise exception 'Vouchers already consumed'; end if;

 -- one unit never has both
 if (select count(*) from purchased_therapy_entitlements
      where id=u2 and voucher_entitlement_id is not null and activation_date is null)<>1 then
  raise exception 'Unit 2 is not cleanly a voucher unit'; end if;

 -- ---- choosing twice is refused -------------------------------------------
 begin
  perform choose_therapy_benefit(u1,'voucher',gen_random_uuid(),null);
  raise exception 'A second choice was accepted';
 exception when others then
  if sqlerrm not like '%already been chosen%' then raise; end if; end;

 -- ---- unit 1 activates normally -------------------------------------------
 r:=activate_purchased_therapy(u1,sg_today(),'start now',null,null,true);
 if (r->>'activated')::boolean is not true then raise exception 'Unit 1 did not activate'; end if;
 -- and unit 2 still cannot
 begin
  perform activate_purchased_therapy(u2,sg_today(),'wrong',null,null,true);
  raise exception 'Therapy activated on the voucher unit';
 exception when others then
  if sqlerrm not like '%taken as vouchers%' then raise; end if; end;

 -- ---- unit 2 claims vouchers through the existing engine ------------------
 r:=claim_entitlement_vouchers(
      (select voucher_entitlement_id from purchased_therapy_entitlements where id=u2),
      jsonb_build_array(jsonb_build_object('voucher_id',v1,'quantity',4)),'some now');
 if (r->'state'->>'claimed')::int<>4 then raise exception 'Partial claim not recorded'; end if;
 if (r->>'invoice_no') not like '%-VC-INV-%' then
  raise exception 'The claim did not produce a Voucher Claim document'; end if;
 -- a voucher that was never offered is refused
 begin
  perform claim_entitlement_vouchers(
    (select voucher_entitlement_id from purchased_therapy_entitlements where id=u2),
    jsonb_build_array(jsonb_build_object('voucher_id',v3,'quantity',1)),null);
  raise exception 'Claimed a voucher the package never offered';
 exception when others then
  if sqlerrm not like '%not one of the choices%' then raise; end if; end;

 -- ---- a later package edit does not touch what was sold -------------------
 perform upsert_therapy_package_choice(pkg,'Package C','PKG-C','changed',true,3,25,array[v3],null);
 r:=purchased_therapy_unit_state(u2);
 if (r->>'voucher_qty')::int<>10 then
  raise exception 'A package edit changed a purchased allowance to %', r->>'voucher_qty'; end if;
 if jsonb_array_length(r->'eligible_vouchers')<>2 then
  raise exception 'A package edit changed which vouchers a purchased unit may take'; end if;
 if (select duration_months from purchased_therapy_entitlements where id=u1)<>1 then
  raise exception 'A package edit changed a purchased therapy duration'; end if;

 raise notice 'PASS: a choice package configures both sides, two units on one invoice take different benefits independently, choosing does not start therapy, vouchers claim through the existing engine, and a later package edit leaves purchased rights alone';
end $$;
rollback;
