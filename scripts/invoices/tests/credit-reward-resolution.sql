-- Refunding and cancelling a credit package that granted qualification rewards.
--
-- 191 blocked every such invoice with no way to clear the block. These cover the
-- refusal, the resolution, and the lines that must stay untouched.
-- Disposable database only; everything is rolled back.
begin;
do $$
declare o uuid:=gen_random_uuid(); staff uuid:=gen_random_uuid();
 st uuid; c uuid; pm uuid; pkg uuid; smallpkg uuid;
 inv uuid; inv2 uuid; inv3 uuid; it uuid; it3 uuid; pay uuid; pay3 uuid;
 sale uuid; sale2 uuid; sale3 uuid; r jsonb; n integer; ent uuid;
begin
 insert into auth.users(id,email) values(o,'cr-owner@tests.invalid'),(staff,'cr-staff@tests.invalid');
 insert into profiles(id,full_name,email,role) values
   (o,'Owner','cr-owner@tests.invalid','owner'),(staff,'Staff','cr-staff@tests.invalid','staff');
 perform set_config('request.jwt.claim.sub',o::text,true);
 insert into stores(name,code,country_code) values('CR Store','CRS','SG') returning id into st;
 insert into user_store_assignments(user_id,store_id) values(staff,st);
 insert into customers(full_name,phone) values('CR Buyer','+6598004444') returning id into c;
 insert into payment_methods(name,is_active) values('CR Cash',true) returning id into pm;
 insert into credit_packages(name,customer_price,paid_credit_amount,effective_from,allow_product)
  values('CR Package',1000,1000,current_date,true) returning id into pkg;
 insert into credit_package_stores(package_id,store_id) values(pkg,st);

 -- ---------------------------------------------------------------
 -- 1. A package sold today grants a reward, and used to be unrefundable.
 -- ---------------------------------------------------------------
 inv:=create_invoice(st,c,null,jsonb_build_array(jsonb_build_object('kind','credit_package','credit_package_id',pkg,'quantity',1)));
 perform pay_invoice(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',1000)));
 select id into sale from credit_package_sales where invoice_id=inv;
 select id into it from invoice_items where invoice_id=inv;
 select id into pay from invoice_payments where invoice_id=inv;

 if (select reward_units from credit_package_sales where id=sale)<1 then
  raise exception 'This fixture needs a package that actually grants a reward'; end if;
 select count(*) into n from invoice_credit_reward_entitlements(inv) where disposition='withdrawable';
 if n<1 then raise exception 'The reward entitlement was not found through its group id'; end if;

 begin
  perform cancel_invoice_recorded(inv,'Cancel',gen_random_uuid());
  raise exception 'Cancelled while rewards were unresolved';
 exception when others then
  if sqlerrm like 'Cancelled while rewards%' then raise; end if;
  if sqlerrm not like '%qualification reward entitlements that are still outstanding%' then
   raise exception 'Unexpected refusal: %', sqlerrm; end if; end;

 -- ---------------------------------------------------------------
 -- 2. Resolving is permissioned and needs a reason.
 -- ---------------------------------------------------------------
 perform set_config('request.jwt.claim.sub',staff::text,true);
 begin
  perform resolve_invoice_credit_rewards(inv,'Trying');
  raise exception 'Staff resolved qualification rewards';
 exception when others then
  if sqlerrm like 'Staff resolved%' then raise; end if;
  if sqlerrm not like '%Owner or Manager%' then raise; end if; end;
 perform set_config('request.jwt.claim.sub',o::text,true);
 begin
  perform resolve_invoice_credit_rewards(inv,'   ');
  raise exception 'Resolved without a reason';
 exception when others then
  if sqlerrm like 'Resolved without%' then raise; end if;
  if sqlerrm not like '%reason is required%' then raise; end if; end;

 -- ---------------------------------------------------------------
 -- 3. Resolving withdraws the unclaimed unit, and the cancel proceeds.
 -- ---------------------------------------------------------------
 r:=resolve_invoice_credit_rewards(inv,'Customer returned the package');
 if (r->>'withdrawn')::int<>1 then raise exception 'The unclaimed entitlement was not withdrawn'; end if;
 if (select count(*) from therapy_entitlements
      where qualification_group_id=credit_package_reward_group(sale) and status='cancelled')<>1 then
  raise exception 'The entitlement was not cancelled'; end if;
 if (select rewards_resolved_at from credit_package_sales where id=sale) is null then
  raise exception 'The resolution was not recorded on the sale'; end if;
 if not exists(select 1 from audit_logs where action='qualification_rewards_resolved') then
  raise exception 'The resolution was not audited'; end if;

 perform cancel_invoice_recorded(inv,'Cancel after resolving',gen_random_uuid());
 if (select status::text from invoices where id=inv)<>'cancelled' then
  raise exception 'Cancellation did not go through after resolving'; end if;

 -- Resolving again must not withdraw anything a second time.
 r:=resolve_invoice_credit_rewards(inv,'Again');
 if (r->>'sales_resolved')::int<>0 then raise exception 'A resolved sale was resolved twice'; end if;

 -- ---------------------------------------------------------------
 -- 4. A CLAIMED entitlement is never touched, and must be acknowledged.
 -- ---------------------------------------------------------------
 inv2:=create_invoice(st,c,null,jsonb_build_array(jsonb_build_object('kind','credit_package','credit_package_id',pkg,'quantity',1)));
 perform pay_invoice(inv2,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',1000)));
 select id into sale2 from credit_package_sales where invoice_id=inv2;
 select id into ent from therapy_entitlements where qualification_group_id=credit_package_reward_group(sale2) limit 1;
 update therapy_entitlements set status='active', activation_date=current_date, claimed_at=now() where id=ent;

 if (select disposition from invoice_credit_reward_entitlements(inv2) limit 1)<>'consumed' then
  raise exception 'An activated entitlement should read as consumed'; end if;
 begin
  perform resolve_invoice_credit_rewards(inv2,'Return it');
  raise exception 'Resolved a consumed entitlement without acknowledgement';
 exception when others then
  if sqlerrm like 'Resolved a consumed%' then raise; end if;
  if sqlerrm not like '%already activated or claimed%' then raise; end if; end;

 r:=resolve_invoice_credit_rewards(inv2,'Return it; the claimed therapy stays',null,true);
 if (r->>'retained')::int<>1 then raise exception 'The consumed entitlement was not counted as retained'; end if;
 if (select status from therapy_entitlements where id=ent)<>'active' then
  raise exception 'A claimed entitlement was altered'; end if;
 if (select claimed_at from therapy_entitlements where id=ent) is null then
  raise exception 'Claim history was erased'; end if;

 -- ---------------------------------------------------------------
 -- 5. A package too small to qualify blocks nothing at all.
 -- ---------------------------------------------------------------
 insert into credit_packages(name,customer_price,paid_credit_amount,effective_from,allow_product)
  values('CR Small',100,100,current_date,true) returning id into smallpkg;
 insert into credit_package_stores(package_id,store_id) values(smallpkg,st);
 inv3:=create_invoice(st,c,null,jsonb_build_array(jsonb_build_object('kind','credit_package','credit_package_id',smallpkg,'quantity',1)));
 perform pay_invoice(inv3,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',100)));
 select id into sale3 from credit_package_sales where invoice_id=inv3;
 select id into it3 from invoice_items where invoice_id=inv3;
 select id into pay3 from invoice_payments where invoice_id=inv3;
 if (select reward_units from credit_package_sales where id=sale3)<>0 then
  raise exception 'A sub-qualifying package should grant no reward units'; end if;
 perform refund_invoice_recorded(inv3,
   jsonb_build_array(jsonb_build_object('invoice_item_id',it3,'amount',100,
     'benefits',(select jsonb_agg(jsonb_build_object('benefit_id',b.id,'amount',100))
                   from invoice_benefit_values b where b.invoice_item_id=it3 and b.lot_id is not null))),
   jsonb_build_array(jsonb_build_object('payment_id',pay3,'amount',100)),'[]','Refund',gen_random_uuid());
 if (select coalesce(sum(amount),0) from invoice_refunds where invoice_id=inv3)<>100 then
  raise exception 'A package with no rewards could not be refunded'; end if;

 raise notice 'PASS: the reported refusal reproduces; rewards are found through the issuer''s own group id; resolution is permissioned, audited and replay-safe; unclaimed units are withdrawn and the cancel proceeds; claimed units keep their status and history; a package granting no rewards refunds without any of this';
end $$;
rollback;
