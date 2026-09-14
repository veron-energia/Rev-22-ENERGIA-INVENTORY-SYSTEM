-- Two records of the same person become one.
--
-- Forty-four tables reference customers. The merge repoints them from the
-- catalogue rather than a hand-written list, carries credit balances into the
-- surviving wallet, and refuses the two cases a script must not decide: two
-- affiliate records, and a commission that has one record as buyer and the
-- other as referrer.
--
-- Disposable database only; everything is rolled back.
begin;
do $$
declare own uuid:=gen_random_uuid(); st uuid; keep uuid; dup uuid; other uuid; pm uuid;
 prod uuid; v1 uuid; inv uuid; lot uuid; r jsonb; n bigint; rq uuid:=gen_random_uuid();
 keep_wallet uuid; dup_wallet uuid;
begin
 insert into auth.users(id,email) values(own,'mrg@tests.invalid');
 insert into profiles(id,full_name,email,role) values(own,'Owner','mrg@tests.invalid','owner');
 perform set_config('request.jwt.claim.sub',own::text,true);
 insert into stores(name,code,country_code) values('MRG Store','MRG','SG') returning id into st;
 insert into payment_methods(name) values('MRG Cash') returning id into pm;
 insert into products(name,sku,product_type) values('MRG Item','MRG-1','own') returning id into prod;
 insert into store_inventory(store_id,product_id,current_qty) values(st,prod,50);
 perform set_product_prices(st,prod,100,100,'available');
 insert into vouchers(name,code,voucher_kind,qty_type,selling_price,is_active)
  values('MRG Facial','MRGF','normal','limited',50,true) returning id into v1;
 insert into voucher_store_stock(voucher_id,store_id,current_qty) values(v1,st,50);

 insert into customers(full_name,phone) values('Same Person','+6598735402') returning id into keep;
 insert into customers(full_name,phone) values('Same Person (dup)','+6598735402') returning id into dup;
 insert into customers(full_name,phone,referred_by) values('Referred By Dup','+6598735403',dup) returning id into other;

 -- the duplicate holds real things
 inv:=create_invoice(st,dup,null,jsonb_build_array(jsonb_build_object('kind','product','product_id',prod,'quantity',1)));
 perform pay_invoice(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',100)));
 lot:=grant_customer_credit(dup,'paid',300,'manual',null,st,sg_today(),null,'dup credit',null,null,own,null);
 insert into customer_reward_vouchers(customer_id,voucher_id,store_id,quantity,status,issued_by,notes)
  values(dup,v1,st,2,'held',own,'held by the duplicate');
 -- and so does the keeper, so both have wallets
 perform grant_customer_credit(keep,'paid',100,'manual',null,st,sg_today(),null,'keep credit',null,null,own,null);

 select id into keep_wallet from customer_credit_wallets where customer_id=keep;
 select id into dup_wallet  from customer_credit_wallets where customer_id=dup;
 if keep_wallet is null or dup_wallet is null then raise exception 'Both should have a wallet for this test'; end if;

 -- ---- the preview describes it -------------------------------------------
 r:=preview_customer_merge(keep,dup);
 if not (r->>'can_merge')::boolean then
  raise exception 'A clean merge was reported as blocked: %', r->'blocking'; end if;
 if (r->'moving'->>'invoices')::int<>1 then raise exception 'The invoice was not counted'; end if;
 if (r->'moving'->>'credit_remaining')::numeric<>300 then raise exception 'The credit was not counted'; end if;
 if (r->'moving'->>'vouchers')::int<>2 then raise exception 'The vouchers were not counted'; end if;
 if (r->'moving'->>'referred_customers')::int<>1 then raise exception 'The referred customer was not counted'; end if;

 -- ---- two affiliate records must stop it ----------------------------------
 declare a1 uuid; a2 uuid; begin
  insert into customer_affiliates(customer_id,status,store_id,activated_at) values(keep,'active',st,now()) returning id into a1;
  insert into customer_affiliates(customer_id,status,store_id,activated_at) values(dup,'active',st,now()) returning id into a2;
  if (preview_customer_merge(keep,dup)->>'can_merge')::boolean then
   raise exception 'Two affiliate records did not block the merge'; end if;
  begin
   perform merge_customer_records(keep,dup,'try anyway',gen_random_uuid());
   raise exception 'The merge ran with two affiliate records';
  exception when others then
   if sqlerrm not like '%needs review first%' then raise; end if; end;
  delete from customer_affiliates where id=a2;   -- resolve it the way a person would
 end;

 -- ---- a commission between the two must stop it ---------------------------
 insert into commissions(invoice_id,buyer_customer_id,referrer_customer_id,tier,product_type,
                         line_amount,rate,commission_amount,status)
  values(inv,keep,dup,'tier1','own',100,15,15,'earned');
 if (preview_customer_merge(keep,dup)->>'can_merge')::boolean then
  raise exception 'A commission between the two did not block the merge'; end if;
 delete from commissions where buyer_customer_id=keep and referrer_customer_id=dup;

 -- ---- the merge -----------------------------------------------------------
 r:=merge_customer_records(keep,dup,'same person, duplicate record',rq);
 if not (r->>'success')::boolean then raise exception 'The merge did not report success'; end if;

 -- everything moved
 if (select customer_id from invoices where id=inv)<>keep then raise exception 'The invoice did not move'; end if;
 -- credit is drawn down and reissued, never repointed
 if (select remaining_amount from customer_credit_lots where id=lot)<>0 then
  raise exception 'The duplicate''s lot was not drawn down'; end if;
 if (select customer_id from customer_credit_lots where id=lot)<>dup then
  raise exception 'The original lot was repointed instead of reissued'; end if;
 if (select coalesce(sum(remaining_amount),0) from customer_credit_lots
      where customer_id=keep and source_type='customer_merge')<>300 then
  raise exception 'The replacement credit is wrong'; end if;
 if (select count(*) from customer_reward_vouchers where customer_id=dup)<>0 then
  raise exception 'A voucher stayed with the duplicate'; end if;
 if (select referred_by from customers where id=other)<>keep then
  raise exception 'The referred customer still points at the duplicate'; end if;

 -- the balance was carried into the surviving wallet, and the append-only
 -- ledger was left recording what actually happened at the time
 if (select count(*) from customer_credit_ledger where customer_id=dup)=0 then
  raise exception 'The historical ledger entries were rewritten'; end if;
 if (select wallet_id from customer_credit_lots
       where customer_id=keep and source_type='customer_merge')<>keep_wallet then
  raise exception 'The replacement is not in the surviving wallet'; end if;
 if (select coalesce(sum(remaining_amount),0) from customer_credit_lots
      where customer_id=keep and status='active')<>400 then
  raise exception 'The combined balance is wrong'; end if;

 -- the affiliate record came across
 if (select customer_id from customer_affiliates where id=(select id from customer_affiliates limit 1))<>keep then
  raise exception 'The affiliate record did not move'; end if;

 -- the duplicate is retired, not destroyed
 if (select deleted_at from customers where id=dup) is null then
  raise exception 'The duplicate was not retired'; end if;
 if (select count(*) from customers where id=dup)<>1 then
  raise exception 'The duplicate row was destroyed'; end if;
 if (select notes from customers where id=dup) not like '%Merged into%' then
  raise exception 'The duplicate does not record where it went'; end if;

 -- ---- a retry does not merge twice ----------------------------------------
 r:=merge_customer_records(keep,dup,'same person, duplicate record',rq);
 if not (r->>'replayed')::boolean then raise exception 'A retry was not recognised'; end if;

 raise notice 'PASS: a duplicate hands over its invoices, credit, vouchers and referrals, balances are carried into one wallet, the record is retired rather than destroyed, retries do not repeat it, and two affiliate records or a commission between the pair stop it for review';
end $$;
rollback;
