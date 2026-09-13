-- A cancelled entitlement must not be reported as claimable.
--
-- claim_entitlement_vouchers always refused one, but the two functions that
-- REPORT what is outstanding worked from quantities alone: a cancelled reward
-- of ten read as ten waiting to be claimed, so reconciliation listed it as
-- needing an eligible list and the panel drew a claim form for it.
--
-- Disposable database only; everything is rolled back.
begin;
do $$
declare own uuid:=gen_random_uuid(); st uuid; c uuid; v1 uuid; e uuid; live uuid; r jsonb; n int;
begin
 insert into auth.users(id,email) values(own,'cno@tests.invalid');
 insert into profiles(id,full_name,email,role) values(own,'Owner','cno@tests.invalid','owner');
 perform set_config('request.jwt.claim.sub',own::text,true);
 insert into stores(name,code,country_code) values('CNO Store','CNO','SG') returning id into st;
 insert into customers(full_name,phone) values('CNO Buyer','+6598919001') returning id into c;
 insert into vouchers(name,code,voucher_kind,qty_type,selling_price,is_active)
  values('CNO Facial','CNOF','normal','limited',50,true) returning id into v1;
 insert into voucher_store_stock(voucher_id,store_id,current_qty) values(v1,st,50);

 -- Cancelled, nothing ever issued, nothing revoked: the live shape of LEG-0000078.
 insert into therapy_entitlements(entitlement_no,customer_id,store_id,package_name,entitlement_kind,
   voucher_qty,qualifying_amount,qualified_value,forfeited_value,activation_deadline,status,
   created_by,earner_kind)
 values(next_legacy_entitlement_no(),c,st,'Cancelled reward','voucher',10,994,994,0,sg_today()+300,
        'cancelled',own,'credit_package')
 returning id into e;

 -- ---- it offers nothing ----------------------------------------------------
 r:=entitlement_voucher_state(e);
 if (r->>'remaining')::int<>0 then
  raise exception 'A cancelled entitlement still offers %', r->>'remaining'; end if;
 if not (r->>'cancelled')::boolean then
  raise exception 'The state does not say the entitlement was cancelled'; end if;
 -- and says what it was worth, so nothing is hidden
 if (r->>'entitled')::int<>10 then
  raise exception 'The entitled figure was lost'; end if;

 -- ---- reconciliation says why ----------------------------------------------
 select count(*) into n from voucher_claim_reconciliation(st)
  where entitlement_id=e and classification='cancelled' and remaining=0 and entitled=10;
 if n<>1 then raise exception 'Reconciliation does not report the cancellation as the reason'; end if;
 select count(*) into n from voucher_claim_reconciliation(st)
  where entitlement_id=e and classification='needs_eligible_list';
 if n<>0 then raise exception 'A cancelled entitlement is still listed as needing an eligible list'; end if;
 -- nothing to suggest arranging for something that cannot be claimed
 if (select suggested_eligible from voucher_claim_reconciliation(st) where entitlement_id=e) is not null then
  raise exception 'Reconciliation suggested choices for a cancelled entitlement'; end if;

 -- ---- and still cannot be claimed ------------------------------------------
 begin
  r:=claim_entitlement_vouchers(e,jsonb_build_array(jsonb_build_object('voucher_id',v1,'quantity',1)),null);
  raise exception 'A cancelled entitlement was claimed';
 exception when others then
  if sqlerrm not like '%cancelled%' then raise; end if; end;

 if jsonb_array_length(customer_outstanding_voucher_claims(c))<>0 then
  raise exception 'A cancelled entitlement is offered at the counter'; end if;

 -- ---- a live one alongside it is unaffected --------------------------------
 insert into therapy_entitlements(entitlement_no,customer_id,store_id,package_name,entitlement_kind,
   voucher_qty,qualifying_amount,qualified_value,forfeited_value,activation_deadline,status,
   created_by,earner_kind,eligible_voucher_ids,claim_source_type)
 values(next_legacy_entitlement_no(),c,st,'Live reward','voucher',6,994,994,0,sg_today()+300,
        'pending_activation',own,'credit_package',array[v1],'credit_package')
 returning id into live;
 if (entitlement_voucher_state(live)->>'remaining')::int<>6 then
  raise exception 'A live entitlement was caught by the cancellation rule'; end if;
 select count(*) into n from voucher_claim_reconciliation(st)
  where entitlement_id=live and classification='ready' and remaining=6;
 if n<>1 then raise exception 'A live entitlement no longer reconciles as ready'; end if;

 raise notice 'PASS: a cancelled entitlement offers nothing, says cancellation is the reason, keeps its entitled figure, and leaves live entitlements alone';
end $$;
rollback;
