-- A reward claimed before 310 existed must not be claimable again.
--
-- claim_legacy_therapy issued the vouchers and wrote no claim row, so deriving
-- "claimed" from voucher_claims alone reported a fully-taken reward as wholly
-- unclaimed. The live system had five such entitlements of ten, every voucher
-- already issued, each offering another ten.
--
-- This reproduces that exact shape: an entitlement marked claimed and active,
-- with its vouchers already in customer_reward_vouchers and no claim row.
--
-- Disposable database only; everything is rolled back.
begin;
do $$
declare own uuid:=gen_random_uuid(); st uuid; c uuid; v1 uuid; e uuid; r jsonb; n int;
begin
 insert into auth.users(id,email) values(own,'pic@tests.invalid');
 insert into profiles(id,full_name,email,role) values(own,'Owner','pic@tests.invalid','owner');
 perform set_config('request.jwt.claim.sub',own::text,true);
 insert into stores(name,code,country_code) values('PIC Store','PIC','SG') returning id into st;
 insert into customers(full_name,phone) values('PIC Buyer','+6598918001') returning id into c;
 insert into vouchers(name,code,voucher_kind,qty_type,selling_price,is_active)
  values('PIC Facial','PICF','normal','limited',50,true) returning id into v1;
 insert into voucher_store_stock(voucher_id,store_id,current_qty) values(v1,st,100);

 insert into therapy_entitlements(entitlement_no,customer_id,store_id,package_name,entitlement_kind,
   voucher_qty,qualifying_amount,qualified_value,forfeited_value,activation_deadline,status,
   created_by,earner_kind,claimed_by,claimed_at,activation_date)
 values(next_legacy_entitlement_no(),c,st,'Historic reward','voucher',10,994,994,0,sg_today()+300,
        'active',own,'credit_package',own,now(),sg_today())
 returning id into e;

 -- Exactly what the old path left behind: the vouchers, and no claim row.
 insert into customer_reward_vouchers(customer_id,voucher_id,entitlement_id,store_id,quantity,issued_by,notes)
 values(c,v1,e,st,10,own,'Legacy reward — never expires, not transferable');

 -- ---- it must read as fully claimed ---------------------------------------
 r:=entitlement_voucher_state(e);
 if (r->>'claimed')::int<>10 then
  raise exception 'Vouchers issued before 310 were not counted as claimed (claimed=%)', r->>'claimed'; end if;
 if (r->>'remaining')::int<>0 then
  raise exception 'A fully-claimed historic reward still offers % more', r->>'remaining'; end if;

 -- ---- and must refuse a second hand-over ----------------------------------
 begin
  r:=claim_entitlement_vouchers(e,jsonb_build_array(jsonb_build_object('voucher_id',v1,'quantity',10)),null);
  raise exception 'A reward already handed over in full was claimed a second time';
 exception when others then
  if sqlerrm not like '%Nothing left%' then raise; end if; end;

 if (select current_qty from voucher_store_stock where voucher_id=v1 and store_id=st)<>100 then
  raise exception 'Stock was taken for a refused second claim'; end if;
 if (select coalesce(sum(quantity),0) from customer_reward_vouchers where entitlement_id=e)<>10 then
  raise exception 'A second set of vouchers was issued'; end if;

 -- ---- reconciliation must not invite it either ----------------------------
 select count(*) into n from voucher_claim_reconciliation(st)
  where entitlement_id=e and classification='nothing_outstanding' and remaining=0;
 if n<>1 then raise exception 'Reconciliation still reports a fully-claimed reward as outstanding'; end if;

 if jsonb_array_length(customer_outstanding_voucher_claims(c))<>0 then
  raise exception 'A fully-claimed reward is still offered at the counter'; end if;

 -- ---- a partly-issued historic reward keeps only its true remainder -------
 update customer_reward_vouchers set quantity=4 where entitlement_id=e;
 r:=entitlement_voucher_state(e);
 if (r->>'claimed')::int<>4 or (r->>'remaining')::int<>6 then
  raise exception 'Partly-issued historic reward mis-stated: claimed=% remaining=%',
    r->>'claimed', r->>'remaining'; end if;

 -- claiming the true remainder works, and mixes with the legacy count
 r:=claim_entitlement_vouchers(e,jsonb_build_array(jsonb_build_object('voucher_id',v1,'quantity',6)),null);
 if (r->'state'->>'claimed')::int<>10 or (r->'state'->>'remaining')::int<>0 then
  raise exception 'Claiming the remainder did not settle the entitlement'; end if;

 raise notice 'PASS: vouchers handed over before 310 count as claimed, a settled reward cannot be taken twice, and a partly-issued one offers only its true remainder';
end $$;
rollback;
