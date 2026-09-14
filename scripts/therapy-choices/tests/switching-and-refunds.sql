-- Switching a benefit, who may do it, and what a reversal withdraws.
--
-- Switching is only safe while nothing has been committed on either side. A
-- scheduled start date counts as committed even though the period has not
-- begun: it is a promise to the customer and it already feeds the overlap
-- check. After that, and after any voucher is claimed, staff are sent to the
-- correction/refund workflow instead.
--
-- Disposable database only; everything is rolled back.
begin;
do $$
declare own uuid:=gen_random_uuid(); mgr uuid:=gen_random_uuid(); stf uuid:=gen_random_uuid();
 other uuid:=gen_random_uuid();
 st uuid; st2 uuid; c uuid; pm uuid; pkg uuid; inv uuid; v1 uuid; v2 uuid; svc uuid;
 u1 uuid; u2 uuid; u3 uuid; ent uuid; r jsonb; n int; rq uuid;
begin
 insert into auth.users(id,email) values(own,'sw-own@tests.invalid'),(mgr,'sw-mgr@tests.invalid'),
   (stf,'sw-stf@tests.invalid'),(other,'sw-oth@tests.invalid');
 insert into profiles(id,full_name,email,role) values
   (own,'Owner','sw-own@tests.invalid','owner'),
   (mgr,'Manager','sw-mgr@tests.invalid','manager'),
   (stf,'Staff','sw-stf@tests.invalid','staff'),
   (other,'Other Staff','sw-oth@tests.invalid','staff');
 perform set_config('request.jwt.claim.sub',own::text,true);
 insert into stores(name,code,country_code) values('SW Store','SWS','SG') returning id into st;
 insert into stores(name,code,country_code) values('SW Other','SWO','SG') returning id into st2;
 insert into user_store_assignments(user_id,store_id) values(mgr,st),(stf,st),(other,st2);
 insert into customers(full_name,phone) values('SW Buyer','+6598922001') returning id into c;
 insert into payment_methods(name) values('SW Cash') returning id into pm;
 insert into vouchers(name,code,voucher_kind,qty_type,selling_price,is_active)
  values('SW Facial','SWF','normal','limited',50,true) returning id into v1;
 insert into vouchers(name,code,voucher_kind,qty_type,selling_price,is_active)
  values('SW Massage','SWM','normal','limited',50,true) returning id into v2;
 insert into voucher_store_stock(voucher_id,store_id,current_qty) values(v1,st,50),(v2,st,50);
 svc:=(upsert_therapy_service(null,'SW-PR','SW Session',50,30,'per_hours',1,5,null,true,null)->>'id')::uuid;
 perform set_therapy_service_store(svc,st,true,null);

 pkg:=upsert_therapy_package_choice(null,'Package C','PKG-C2',null,true,1,10,array[v1,v2],array[svc]);
 insert into unlimited_therapy_store_prices(package_id,store_id,selling_price,available_at_store)
  values(pkg,st,500,true);

 inv:=create_invoice(st,c,null,jsonb_build_array(
        jsonb_build_object('kind','therapy','therapy_package_id',pkg,'quantity',1),
        jsonb_build_object('kind','therapy','therapy_package_id',pkg,'quantity',1),
        jsonb_build_object('kind','therapy','therapy_package_id',pkg,'quantity',1)));
 perform pay_invoice(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',1500)));
 select purchased_id into u1 from purchased_therapy_units(st,c) where unit_index=1;
 select purchased_id into u2 from purchased_therapy_units(st,c) where unit_index=2;
 select purchased_id into u3 from purchased_therapy_units(st,c) where unit_index=3;

 -- ---- staff may record the initial choice ---------------------------------
 perform set_config('request.jwt.claim.sub',stf::text,true);
 r:=choose_therapy_benefit(u1,'voucher',gen_random_uuid(),'staff recorded');
 if r->'state'->>'benefit_choice'<>'voucher' then raise exception 'Staff could not record a choice'; end if;

 -- ---- but staff may NOT switch one -----------------------------------------
 begin
  perform switch_therapy_benefit(u1,'unlimited','changed mind',gen_random_uuid());
  raise exception 'Staff switched a chosen benefit';
 exception when others then
  if sqlerrm not like '%Only an Owner or Manager%' then raise; end if; end;

 -- ---- a manager may, with a reason ----------------------------------------
 perform set_config('request.jwt.claim.sub',mgr::text,true);
 begin
  perform switch_therapy_benefit(u1,'unlimited','',gen_random_uuid());
  raise exception 'A switch without a reason was accepted';
 exception when others then
  if sqlerrm not like '%Give a reason%' then raise; end if; end;

 ent:=(select voucher_entitlement_id from purchased_therapy_entitlements where id=u1);
 r:=switch_therapy_benefit(u1,'unlimited','customer changed mind',gen_random_uuid());
 if r->>'previous_choice'<>'voucher' or r->>'new_choice'<>'unlimited' then
  raise exception 'The switch did not record both sides'; end if;

 -- atomic: the old allowance is withdrawn, not left alongside
 if (select status from therapy_entitlements where id=ent)<>'cancelled' then
  raise exception 'The previous voucher allowance is still live'; end if;
 if (entitlement_voucher_state(ent)->>'remaining')::int<>0 then
  raise exception 'The previous voucher allowance is still claimable'; end if;
 if (select voucher_entitlement_id from purchased_therapy_entitlements where id=u1) is not null then
  raise exception 'The unit still points at a withdrawn allowance'; end if;

 -- it is recorded
 select count(*) into n from therapy_benefit_choice_history
  where purchased_entitlement_id=u1 and previous_choice='voucher' and new_choice='unlimited'
    and reason='customer changed mind' and changed_by=mgr;
 if n<>1 then raise exception 'The switch was not recorded with its reason and author'; end if;

 -- ---- scheduling closes the door ------------------------------------------
 perform activate_purchased_therapy(u1,sg_today()+30,'scheduled start',null,null,true);
 if (select status from purchased_therapy_entitlements where id=u1)<>'scheduled' then
  raise exception 'Expected the unit to be scheduled'; end if;
 r:=purchased_therapy_unit_state(u1);
 if (r->>'can_switch')::boolean then raise exception 'A scheduled unit still reports as switchable'; end if;
 begin
  perform switch_therapy_benefit(u1,'voucher','too late',gen_random_uuid());
  raise exception 'Switched after the therapy was scheduled';
 exception when others then
  if sqlerrm not like '%activated or scheduled%' then raise; end if; end;

 -- ---- claiming closes the door too ----------------------------------------
 r:=choose_therapy_benefit(u2,'voucher',gen_random_uuid(),null);
 ent:=(select voucher_entitlement_id from purchased_therapy_entitlements where id=u2);
 perform claim_entitlement_vouchers(ent,jsonb_build_array(jsonb_build_object('voucher_id',v1,'quantity',1)),null);
 if (purchased_therapy_unit_state(u2)->>'can_switch')::boolean then
  raise exception 'A unit with claimed vouchers reports as switchable'; end if;
 begin
  perform switch_therapy_benefit(u2,'unlimited','too late',gen_random_uuid());
  raise exception 'Switched after vouchers were claimed';
 exception when others then
  if sqlerrm not like '%already been claimed%' then raise; end if; end;

 -- ---- a repeated request is refused ---------------------------------------
 rq:=gen_random_uuid();
 perform choose_therapy_benefit(u3,'voucher',rq,null);
 begin
  perform choose_therapy_benefit(u3,'unlimited',rq,null);
  raise exception 'A repeated request created a second choice';
 exception when others then
  if sqlerrm not like '%already been submitted%' then raise; end if; end;

 -- ---- another store's staff cannot see or touch it ------------------------
 perform set_config('request.jwt.claim.sub',other::text,true);
 begin
  perform purchased_therapy_unit_state(u3);
  raise exception 'Staff from another store read the unit';
 exception when others then
  if sqlerrm not like '%No access to this store%' then raise; end if; end;
 select count(*) into n from purchased_therapy_units(null,c);
 if n<>0 then raise exception 'Another store''s staff listed % units', n; end if;

 -- ---- quantities are validated --------------------------------------------
 perform set_config('request.jwt.claim.sub',own::text,true);
 ent:=(select voucher_entitlement_id from purchased_therapy_entitlements where id=u3);
 begin
  perform claim_entitlement_vouchers(ent,jsonb_build_array(jsonb_build_object('voucher_id',v1,'quantity',-3)),null);
  raise exception 'A negative quantity was accepted';
 exception when others then
  if sqlerrm not like '%at least one%' and sqlerrm not like '%positive%' then raise; end if; end;
 begin
  perform claim_entitlement_vouchers(ent,jsonb_build_array(jsonb_build_object('voucher_id',v1,'quantity',99)),null);
  raise exception 'More than the allowance was accepted';
 exception when others then
  if sqlerrm not like '%left to claim%' then raise; end if; end;

 -- ---- a reversal withdraws what was not used ------------------------------
 -- u3 chose vouchers and claimed none.
 update purchased_therapy_entitlements set status='cancelled' where id=u3;
 if (entitlement_voucher_state(ent)->>'remaining')::int<>0 then
  raise exception 'A cancelled unit still offers vouchers'; end if;
 begin
  perform choose_therapy_benefit(u3,'unlimited',gen_random_uuid(),null);
  raise exception 'Chose a benefit against a cancelled purchase';
 exception when others then
  if sqlerrm not like '%nothing can be chosen%' then raise; end if; end;

 -- u2 claimed 1 of 10: the claimed one stays, the other 9 go.
 ent:=(select voucher_entitlement_id from purchased_therapy_entitlements where id=u2);
 update purchased_therapy_entitlements set status='refunded' where id=u2;
 r:=entitlement_voucher_state(ent);
 if (r->>'claimed')::int<>1 then raise exception 'A reversal took back a claimed voucher'; end if;
 if (r->>'remaining')::int<>0 then raise exception 'A refunded unit still offers vouchers'; end if;
 if (select count(*) from customer_reward_vouchers where entitlement_id=ent)<>1 then
  raise exception 'The vouchers already handed over were deleted'; end if;

 -- partial reversal: u1 is untouched by u2 and u3 being reversed
 if (select status from purchased_therapy_entitlements where id=u1)<>'scheduled' then
  raise exception 'Reversing other units changed unit 1'; end if;

 raise notice 'PASS: staff may record a choice but only an Owner or Manager may switch one, switching is closed by scheduling or by any claim, repeated requests are refused, other stores are shut out, quantities are validated, and a reversal withdraws only what was unused';
end $$;
rollback;
