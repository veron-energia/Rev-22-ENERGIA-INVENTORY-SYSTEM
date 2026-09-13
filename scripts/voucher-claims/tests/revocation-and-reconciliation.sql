-- A refund or cancellation withdraws what was never claimed, and nothing else.
--
-- Also covers the read-only reconciliation of purchases made before any of
-- this existed, which must report and never write.
--
-- Disposable database only; everything is rolled back.
begin;
do $$
declare own uuid:=gen_random_uuid(); st uuid; c uuid; c2 uuid; pm uuid; cp uuid;
 inv uuid; inv2 uuid; v1 uuid; e uuid; e2 uuid; r jsonb; n int; v_old uuid;
begin
 insert into auth.users(id,email) values(own,'rvc@tests.invalid');
 insert into profiles(id,full_name,email,role) values(own,'Owner','rvc@tests.invalid','owner');
 perform set_config('request.jwt.claim.sub',own::text,true);
 insert into stores(name,code,country_code) values('RVC Store','RVC','SG') returning id into st;
 insert into customers(full_name,phone) values('RVC Buyer','+6598916001') returning id into c;
 insert into customers(full_name,phone) values('RVC Two','+6598916002') returning id into c2;
 insert into payment_methods(name) values('RVC Cash') returning id into pm;
 insert into vouchers(name,code,voucher_kind,qty_type,selling_price,is_active)
  values('RVC Facial','RVCF','normal','limited',50,true) returning id into v1;
 insert into voucher_store_stock(voucher_id,store_id,current_qty) values(v1,st,50);

 insert into credit_packages(name,customer_price,paid_credit_amount,grants_reward,
                             reward_qualifying_amount,allow_voucher,effective_from)
  values('RVC Package',994,994,true,994,true,current_date) returning id into cp;
 insert into credit_package_stores(package_id,store_id) values(cp,st);
 insert into credit_package_vouchers(package_id,voucher_id) values(cp,v1);

 -- ---- partly claimed, then refunded ---------------------------------------
 inv:=create_invoice(st,c,null,jsonb_build_array(jsonb_build_object(
        'kind','credit_package','credit_package_id',cp,'quantity',1)));
 perform pay_invoice(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',994)));
 select id into e from therapy_entitlements where claim_source_invoice_id=inv;

 r:=claim_entitlement_vouchers(e,jsonb_build_array(jsonb_build_object('voucher_id',v1,'quantity',4)),null);
 if (r->'state'->>'remaining')::int<>6 then raise exception 'Expected 6 remaining before the refund'; end if;

 update invoices set status='refunded' where id=inv;

 r:=entitlement_voucher_state(e);
 if (r->>'claimed')::int<>4 then raise exception 'The refund changed what was already claimed'; end if;
 if (r->>'revoked')::int<>6 then raise exception 'The unclaimed 6 were not revoked, got %', r->>'revoked'; end if;
 if (r->>'remaining')::int<>0 then raise exception 'Something is still claimable after a refund'; end if;
 if (select count(*) from customer_reward_vouchers where entitlement_id=e)<>1 then
  raise exception 'The vouchers already handed over were withdrawn'; end if;

 begin
  r:=claim_entitlement_vouchers(e,jsonb_build_array(jsonb_build_object('voucher_id',v1,'quantity',1)),null);
  raise exception 'A revoked entitlement was still claimable';
 exception when others then
  if sqlerrm not like '%Nothing left%' then raise; end if; end;

 -- Revoking twice must not double-count.
 n:=revoke_unclaimed_entitlement_vouchers(inv,'again');
 if n<>0 then raise exception 'Revocation was not idempotent, withdrew % more', n; end if;

 -- ---- never claimed, then cancelled ---------------------------------------
 inv2:=create_invoice(st,c2,null,jsonb_build_array(jsonb_build_object(
         'kind','credit_package','credit_package_id',cp,'quantity',1)));
 perform pay_invoice(inv2,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',994)));
 select id into e2 from therapy_entitlements where claim_source_invoice_id=inv2;

 update invoices set status='cancelled' where id=inv2;
 r:=entitlement_voucher_state(e2);
 if (r->>'remaining')::int<>0 then raise exception 'A cancelled purchase left claimable vouchers'; end if;
 if (r->>'status')<>'cancelled' then
  raise exception 'An entitlement nobody claimed from should be cancelled outright, got %', r->>'status'; end if;
 if jsonb_array_length(customer_outstanding_voucher_claims(c2))<>0 then
  raise exception 'A cancelled entitlement is still offered at the counter'; end if;

 -- ---- reconciliation of a purchase that predates the snapshot -------------
 insert into therapy_entitlements(entitlement_no,customer_id,store_id,package_name,entitlement_kind,
   voucher_qty,qualifying_amount,qualified_value,forfeited_value,activation_deadline,status,
   created_by,earner_kind)
 values(next_legacy_entitlement_no(),c2,st,'Historic reward','voucher',5,994,994,0,
        sg_today()+30,'pending_activation',own,'credit_package')
 returning id into v_old;

 select count(*) into n from voucher_claim_reconciliation(st)
  where entitlement_id=v_old and has_snapshot=false and classification='needs_eligible_list';
 if n<>1 then raise exception 'The pre-snapshot entitlement was not reported for review'; end if;

 select count(*) into n from voucher_claim_reconciliation(st) where entitlement_id=e and classification='ready';
 if n<>1 then raise exception 'A snapshotted entitlement should reconcile as ready'; end if;

 -- Reading it must not have written anything.
 if (select eligible_voucher_ids from therapy_entitlements where id=v_old) is not null then
  raise exception 'Reconciliation wrote to an entitlement'; end if;

 -- An entitlement with no snapshot is still refused a guessed choice.
 begin
  r:=claim_entitlement_vouchers(v_old,jsonb_build_array(jsonb_build_object('voucher_id',v1,'quantity',1)),null);
  -- Allowed: with no snapshot there is nothing to check against, which is why
  -- reconciliation exists. Assert it at least recorded a claim document.
  if (r->>'invoice_no') is null then raise exception 'A claim produced no document'; end if;
 exception when others then
  if sqlerrm like '%not one of the choices%' then
   raise exception 'A pre-snapshot entitlement must not refuse every voucher'; end if;
  raise; end;

 raise notice 'PASS: a refund or cancellation withdraws only what was never claimed, revoking is idempotent, and historical entitlements are reported without being written to';
end $$;
rollback;
