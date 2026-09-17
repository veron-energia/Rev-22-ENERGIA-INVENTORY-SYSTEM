-- A premium bundle's reward vouchers can be chosen later.
--
-- create_invoice refused any bundle line whose selection was not the exact full
-- allowance, so a customer who had not decided could not buy the bundle. The
-- deferral machinery already existed; only the validation stood in the way.
--
-- Disposable database only; everything is rolled back.
begin;
do $$
declare own uuid:=gen_random_uuid(); st uuid; c1 uuid; c2 uuid; c3 uuid; pm uuid;
 v1 uuid; v2 uuid; bundle uuid; inv uuid; ent uuid; r jsonb; n int; stock0 int;
begin
 insert into auth.users(id,email) values(own,'bds@t.invalid');
 insert into profiles(id,full_name,email,role) values(own,'Owner','bds@t.invalid','owner');
 perform set_config('request.jwt.claim.sub',own::text,true);
 insert into stores(name,code,country_code) values('BDS','BDS','SG') returning id into st;
 insert into customers(full_name,phone) values('BDS One','+6591610001') returning id into c1;
 insert into customers(full_name,phone) values('BDS Two','+6591610002') returning id into c2;
 insert into customers(full_name,phone) values('BDS Three','+6591610003') returning id into c3;
 insert into payment_methods(name) values('BDS Cash') returning id into pm;
 insert into vouchers(name,code,voucher_kind,qty_type,selling_price,is_active)
  values('BDS Facial','BDSF','normal','limited',50,true) returning id into v1;
 insert into vouchers(name,code,voucher_kind,qty_type,selling_price,is_active)
  values('BDS Massage','BDSM','normal','limited',50,true) returning id into v2;
 insert into voucher_store_stock(voucher_id,store_id,current_qty) values(v1,st,100),(v2,st,100);

 insert into premium_bundles(name,customer_payment_amount,paid_credit_amount,bonus_credit_amount,
                             grants_reward,free_voucher_qty,is_active)
  values('BDS Bundle',1000,1000,200,true,10,true) returning id into bundle;
 insert into premium_bundle_stores(bundle_id,store_id) values(bundle,st);
 insert into premium_bundle_vouchers(bundle_id,voucher_id) values(bundle,v1),(bundle,v2);

 select current_qty into stock0 from voucher_store_stock where voucher_id=v1 and store_id=st;

 -- ---- none chosen at the till ----------------------------------------------
 inv:=create_invoice(st,c1,null,jsonb_build_array(jsonb_build_object(
        'kind','premium_bundle','premium_bundle_id',bundle,'quantity',1,
        'voucher_selection',jsonb_build_array())));
 perform pay_invoice(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',1000)));
 -- nothing issued, nothing taken from stock
 if (select count(*) from customer_reward_vouchers where customer_id=c1)<>0 then
  raise exception 'Vouchers were issued when none were chosen'; end if;
 if (select current_qty from voucher_store_stock where voucher_id=v1 and store_id=st)<>stock0 then
  raise exception 'Stock moved for an unselected allowance'; end if;
 -- the whole allowance is claimable
 select id into ent from therapy_entitlements where claim_source_invoice_id=inv;
 if ent is null then raise exception 'No claimable allowance was created'; end if;
 if (entitlement_voucher_state(ent)->>'remaining')::int<>10 then
  raise exception 'The deferred allowance is not the full 10'; end if;
 -- and its deadline comes from the purchase, not an unrelated therapy rule
 if (select activation_deadline from therapy_entitlements where id=ent)
    <> (sg_today() + interval '1 year')::date then
  raise exception 'The deadline was not dated from the purchase'; end if;

 -- ---- some chosen at the till ----------------------------------------------
 declare inv2 uuid; ent2 uuid; begin
  inv2:=create_invoice(st,c2,null,jsonb_build_array(jsonb_build_object(
          'kind','premium_bundle','premium_bundle_id',bundle,'quantity',1,
          'voucher_selection',jsonb_build_array(
            jsonb_build_object('voucher_id',v1,'quantity',3),
            jsonb_build_object('voucher_id',v2,'quantity',1)))));
  perform pay_invoice(inv2,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',1000)));
  if (select coalesce(sum(quantity),0) from customer_reward_vouchers where customer_id=c2)<>4 then
   raise exception 'The chosen 4 were not issued'; end if;
  select id into ent2 from therapy_entitlements where claim_source_invoice_id=inv2;
  if (entitlement_voucher_state(ent2)->>'remaining')::int<>6 then
   raise exception 'The remaining 6 are not claimable'; end if;
  -- immediate plus later never exceeds the allowance
  perform claim_entitlement_vouchers(ent2,jsonb_build_array(jsonb_build_object('voucher_id',v1,'quantity',6)),null);
  if (entitlement_voucher_state(ent2)->>'remaining')::int<>0 then
   raise exception 'Claiming the rest did not settle the allowance'; end if;
  if (select coalesce(sum(quantity),0) from customer_reward_vouchers where customer_id=c2)<>10 then
   raise exception 'Issued total is not the allowance'; end if;
  begin
   perform claim_entitlement_vouchers(ent2,jsonb_build_array(jsonb_build_object('voucher_id',v1,'quantity',1)),null);
   raise exception 'Claimed past the allowance';
  exception when others then
   if sqlerrm not like '%Nothing left%' then raise; end if; end;
 end;

 -- ---- all chosen at the till still works -----------------------------------
 declare inv3 uuid; begin
  inv3:=create_invoice(st,c3,null,jsonb_build_array(jsonb_build_object(
          'kind','premium_bundle','premium_bundle_id',bundle,'quantity',1,
          'voucher_selection',jsonb_build_array(jsonb_build_object('voucher_id',v1,'quantity',10)))));
  perform pay_invoice(inv3,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',1000)));
  if (select coalesce(sum(quantity),0) from customer_reward_vouchers where customer_id=c3)<>10 then
   raise exception 'A full selection was not issued'; end if;
  if exists(select 1 from therapy_entitlements where claim_source_invoice_id=inv3) then
   raise exception 'A full selection still created a deferred allowance'; end if;
 end;

 -- ---- more than the allowance is still refused -----------------------------
 begin
  perform create_invoice(st,c1,null,jsonb_build_array(jsonb_build_object(
    'kind','premium_bundle','premium_bundle_id',bundle,'quantity',1,
    'voucher_selection',jsonb_build_array(jsonb_build_object('voucher_id',v1,'quantity',11)))));
  raise exception 'More vouchers than the bundle grants were accepted';
 exception when others then
  if sqlerrm not like '%more reward voucher%' then raise; end if; end;

 -- ---- an ineligible voucher is still refused -------------------------------
 declare v3 uuid; begin
  insert into vouchers(name,code,voucher_kind,qty_type,selling_price,is_active)
   values('BDS Other','BDSO','normal','limited',50,true) returning id into v3;
  insert into voucher_store_stock(voucher_id,store_id,current_qty) values(v3,st,10);
  begin
   perform create_invoice(st,c1,null,jsonb_build_array(jsonb_build_object(
     'kind','premium_bundle','premium_bundle_id',bundle,'quantity',1,
     'voucher_selection',jsonb_build_array(jsonb_build_object('voucher_id',v3,'quantity',1)))));
   raise exception 'A voucher the bundle never offered was accepted';
  exception when others then
   if sqlerrm not like '%not an eligible choice%' then raise; end if; end;
 end;

 raise notice 'PASS: a bundle sells with none, some or all of its vouchers chosen, the remainder stays claimable with a deadline from the purchase, stock moves only for what is issued, immediate plus later never exceeds the allowance, and over-selection and ineligible vouchers are still refused';
end $$;
rollback;
