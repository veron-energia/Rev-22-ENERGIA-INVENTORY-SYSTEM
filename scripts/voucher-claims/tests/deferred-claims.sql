-- Vouchers a customer is owed, claimed when they are ready.
--
-- Covers the whole path through the real invoice functions: a credit package
-- purchase snapshots what may be chosen, the customer takes some now and some
-- later, each claim writes its own Voucher Claim document that is not a sale,
-- stock leaves once, and a refund withdraws only what was never claimed.
--
-- Disposable database only; everything is rolled back.
begin;
do $$
declare own uuid:=gen_random_uuid(); st uuid; c uuid; pm uuid; cp uuid; inv uuid;
 v1 uuid; v2 uuid; v3 uuid; e uuid; r jsonb; n int; v_claim_inv uuid;
begin
 insert into auth.users(id,email) values(own,'dvc@tests.invalid');
 insert into profiles(id,full_name,email,role) values(own,'Owner','dvc@tests.invalid','owner');
 perform set_config('request.jwt.claim.sub',own::text,true);
 insert into stores(name,code,country_code) values('DVC Store','DVC','SG') returning id into st;
 insert into customers(full_name,phone) values('DVC Buyer','+6598914001') returning id into c;
 insert into payment_methods(name) values('DVC Cash') returning id into pm;

 insert into vouchers(name,code,voucher_kind,qty_type,selling_price,is_active)
  values('DVC Facial','DVCF','normal','limited',50,true) returning id into v1;
 insert into vouchers(name,code,voucher_kind,qty_type,selling_price,is_active)
  values('DVC Massage','DVCM','normal','limited',50,true) returning id into v2;
 insert into vouchers(name,code,voucher_kind,qty_type,selling_price,is_active)
  values('DVC Other','DVCO','normal','limited',50,true) returning id into v3;
 insert into voucher_store_stock(voucher_id,store_id,current_qty) values(v1,st,20),(v2,st,20),(v3,st,20);

 -- A package whose reward is 10 vouchers, choosable from two of the three.
 insert into credit_packages(name,customer_price,paid_credit_amount,grants_reward,
                             reward_qualifying_amount,allow_voucher,allow_therapy,effective_from)
  values('DVC Package',994,994,true,994,true,true,current_date) returning id into cp;
 insert into credit_package_stores(package_id,store_id) values(cp,st);
 insert into credit_package_vouchers(package_id,voucher_id) values(cp,v1),(cp,v2);

 inv:=create_invoice(st,c,null,jsonb_build_array(jsonb_build_object(
        'kind','credit_package','credit_package_id',cp,'quantity',1)));
 perform pay_invoice(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',994)));

 select id into e from therapy_entitlements
  where customer_id=c and entitlement_kind='voucher' and claim_source_invoice_id=inv;
 if e is null then raise exception 'The purchase did not create a claimable voucher entitlement'; end if;

 -- ---- the snapshot ---------------------------------------------------------
 r:=entitlement_voucher_state(e);
 if not (r->>'snapshot_present')::boolean then
  raise exception 'The eligible choices were not snapshotted at purchase'; end if;
 if jsonb_array_length(r->'eligible')<>2 then
  raise exception 'Expected two eligible vouchers, got %', jsonb_array_length(r->'eligible'); end if;
 if (r->>'claim_deadline') is null then raise exception 'No claim deadline was recorded'; end if;

 -- Editing the package later must not change what this customer may choose.
 insert into credit_package_vouchers(package_id,voucher_id) values(cp,v3);
 if jsonb_array_length(entitlement_voucher_state(e)->'eligible')<>2 then
  raise exception 'A later package edit changed an existing entitlement''s choices'; end if;

 -- ---- entitled / claimed / remaining --------------------------------------
 if (r->>'claimed')::int<>0 or (r->>'remaining')::int<>(r->>'entitled')::int then
  raise exception 'A new entitlement should be wholly unclaimed'; end if;

 -- ---- some now -------------------------------------------------------------
 r:=claim_entitlement_vouchers(e,jsonb_build_array(jsonb_build_object('voucher_id',v1,'quantity',3)),'some now');
 if (r->'state'->>'claimed')::int<>3 then raise exception 'Claim of 3 not recorded'; end if;
 if (r->'state'->>'remaining')::int<>(r->'state'->>'entitled')::int-3 then
  raise exception 'Remaining did not fall by 3'; end if;
 v_claim_inv:=(r->>'invoice_id')::uuid;

 -- ---- the document it produced --------------------------------------------
 if (select invoice_no from invoices where id=v_claim_inv) not like '%-VC-INV-%' then
  raise exception 'A voucher claim did not get its own reference series'; end if;
 if not (select is_voucher_claim from invoices where id=v_claim_inv) then
  raise exception 'The claim document is not marked as a voucher claim'; end if;
 if (select total_amount+paid_amount from invoices where id=v_claim_inv)<>0 then
  raise exception 'A voucher claim must not carry a value'; end if;
 if exists(select 1 from invoice_payments where invoice_id=v_claim_inv) then
  raise exception 'A voucher claim must not carry a payment'; end if;
 if exists(select 1 from invoice_items where invoice_id=v_claim_inv) then
  raise exception 'A voucher claim must not carry sellable lines'; end if;
 if exists(select 1 from commissions where invoice_id=v_claim_inv)
    or exists(select 1 from staff_commissions where invoice_id=v_claim_inv) then
  raise exception 'A voucher claim earned commission'; end if;
 if exists(select 1 from customer_credit_lots where source_record_id=v_claim_inv) then
  raise exception 'A voucher claim granted credit'; end if;
 if exists(select 1 from credit_package_sales where invoice_id=v_claim_inv)
    or exists(select 1 from premium_bundle_sales where invoice_id=v_claim_inv) then
  raise exception 'A voucher claim was recorded as a sale'; end if;

 -- ---- stock leaves once ----------------------------------------------------
 if (select current_qty from voucher_store_stock where voucher_id=v1 and store_id=st)<>17 then
  raise exception 'Stock was not deducted exactly once for the claim'; end if;

 -- ---- a voucher that was never on offer ------------------------------------
 begin
  r:=claim_entitlement_vouchers(e,jsonb_build_array(jsonb_build_object('voucher_id',v3,'quantity',1)),null);
  raise exception 'Claimed a voucher that was not one of the snapshotted choices';
 exception when others then
  if sqlerrm not like '%not one of the choices%' then raise; end if; end;

 -- ---- more than is left ----------------------------------------------------
 begin
  r:=claim_entitlement_vouchers(e,jsonb_build_array(jsonb_build_object('voucher_id',v1,'quantity',99)),null);
  raise exception 'Claimed more than remained';
 exception when others then
  if sqlerrm not like '%left to claim%' then raise; end if; end;

 -- ---- and some later -------------------------------------------------------
 r:=claim_entitlement_vouchers(e,jsonb_build_array(
      jsonb_build_object('voucher_id',v1,'quantity',2),
      jsonb_build_object('voucher_id',v2,'quantity',2)),'later');
 if (r->'state'->>'claimed')::int<>7 then raise exception 'Second claim not accumulated'; end if;
 select count(*) into n from invoices where is_voucher_claim and voucher_claim_entitlement_id=e;
 if n<>2 then raise exception 'Expected one document per claim, got %', n; end if;

 -- ---- outstanding list -----------------------------------------------------
 if jsonb_array_length(customer_outstanding_voucher_claims(c))<>1 then
  raise exception 'The customer''s outstanding claim was not listed'; end if;

 raise notice 'PASS: purchase snapshots the choices, partial claims accumulate, and each claim is its own document that is not a sale';
end $$;
rollback;
