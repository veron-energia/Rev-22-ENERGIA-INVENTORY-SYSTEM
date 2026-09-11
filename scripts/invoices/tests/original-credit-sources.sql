begin;
do $$
declare o uuid:=gen_random_uuid(); st uuid; c uuid; pm uuid; cp uuid; inv uuid; it uuid; s uuid; l uuid; bonus uuid;
 pay uuid; b uuid; bb uuid; x jsonb; r jsonb;
begin
 insert into auth.users(id,email) values(o,'original-sources@tests.invalid');
 insert into profiles(id,full_name,email,role) values(o,'Original Sources Owner','original-sources@tests.invalid','owner');
 perform set_config('request.jwt.claim.sub',o::text,true);
 insert into stores(name,code,country_code) values('Original Sources','OS','SG') returning id into st;
 insert into customers(full_name,phone) values('Original Sources Recipient','+6591238711') returning id into c;
 insert into payment_methods(name) values('Original Sources Cash') returning id into pm;
 insert into credit_packages(name,customer_price,paid_credit_amount,bonus_enabled,bonus_value,allow_product,grants_reward)
  values('Historical Bonus',100,100,true,20,true,false) returning id into cp;
 insert into credit_package_stores(package_id,store_id) values(cp,st);
 inv:=create_invoice(st,c,null,jsonb_build_array(jsonb_build_object('kind','credit_package','credit_package_id',cp,'quantity',1)));
 perform record_invoice_payment(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',100)),gen_random_uuid());
 select id into it from invoice_items where invoice_id=inv;
 select id into pay from invoice_payments where invoice_id=inv;
 select id,credit_lot_id,bonus_credit_lot_id into s,l,bonus from credit_package_sales where invoice_id=inv;
 if bonus is null then raise exception 'Expected actual issued bonus lot'; end if;
 delete from invoice_benefit_values where invoice_id=inv; -- fixture: actual pre178 missing mapping
 update credit_package_sales set bonus_credit_lot_id=null,original_sources_verified_at=null,original_sources_evidence=null where id=s;
 r:=invoice_benefit_review_options(inv);
 if (r#>>'{lines,0,sources,0,verified}')::boolean or r#>>'{lines,0,sources,0,candidates,0,lot_id}'<>bonus::text then
  raise exception 'Review did not expose unresolved original bonus evidence: %',r; end if;
 begin
  perform record_invoice_benefit_values(it,jsonb_build_array(jsonb_build_object('lot_id',l,'paid_value',100,'granted_value',100)),'Original receipt, bonus omitted');
  raise exception 'Pre178 missing bonus provenance bypassed completeness guard';
 exception when others then if sqlerrm not like '%Historical bonus-credit provenance%' then raise; end if; end;
 perform verify_invoice_credit_sale_sources(s,bonus,false,'Reviewed original purchase grant ledger and receipt; exact bonus grant identified');
 r:=invoice_benefit_review_options(inv);
 if not (r#>>'{lines,0,sources,0,verified}')::boolean or jsonb_array_length(r#>'{lines,0,benefits}')<>2 then raise exception 'Verified source did not reveal both grants'; end if;
 perform record_invoice_benefit_values(it,jsonb_build_array(jsonb_build_object('lot_id',l,'paid_value',83.33,'granted_value',100),
  jsonb_build_object('lot_id',bonus,'paid_value',16.67,'granted_value',20)),'Original 100 cash allocated over original 120 credit including bonus');
 select id into b from invoice_benefit_values where lot_id=l;
 select id into bb from invoice_benefit_values where lot_id=bonus;
 perform refund_invoice_recorded(inv,jsonb_build_array(jsonb_build_object('invoice_item_id',it,'amount',100,'benefits',jsonb_build_array(
  jsonb_build_object('benefit_id',b,'amount',83.33),jsonb_build_object('benefit_id',bb,'amount',16.67)))),
  jsonb_build_array(jsonb_build_object('payment_id',pay,'amount',100)),'[]','All original unused credit returned',gen_random_uuid());
 if exists(select 1 from customer_credit_lots where id in(l,bonus) and remaining_amount<>0) then raise exception 'Verified refund left bonus credit spendable'; end if;
 -- A documented no-bonus decision is explicit, never inferred from NULL.
 update credit_packages set bonus_enabled=false where id=cp;
 inv:=create_invoice(st,c,null,jsonb_build_array(jsonb_build_object('kind','credit_package','credit_package_id',cp,'quantity',1)));
 perform record_invoice_payment(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',100)),gen_random_uuid());
 select id into it from invoice_items where invoice_id=inv;
 select id,credit_lot_id into s,l from credit_package_sales where invoice_id=inv;
 delete from invoice_benefit_values where invoice_id=inv;
 update credit_package_sales set original_sources_verified_at=null,original_sources_evidence=null where id=s;
 perform verify_invoice_credit_sale_sources(s,null,true,'Original signed allocation and grant ledger confirm no bonus issued on this purchase');
 perform record_invoice_benefit_values(it,jsonb_build_array(jsonb_build_object('lot_id',l,'paid_value',100,'granted_value',100)),'Original paid grant and no-bonus evidence verified');
 -- Credit-package rewards are a separate source, not presumed free to retain.
 update credit_packages set grants_reward=true,reward_qualifying_amount=50 where id=cp;
 inv:=create_invoice(st,c,null,jsonb_build_array(jsonb_build_object('kind','credit_package','credit_package_id',cp,'quantity',1)));
 perform record_invoice_payment(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',100)),gen_random_uuid());
 if not exists(select 1 from credit_package_sales where invoice_id=inv and reward_units>0) then raise exception 'Expected actual qualification reward units'; end if;
 select id into it from invoice_items where invoice_id=inv;
 select id into pay from invoice_payments where invoice_id=inv;
 select id into b from invoice_benefit_values where invoice_item_id=it;
 begin
  perform refund_invoice_recorded(inv,jsonb_build_array(jsonb_build_object('invoice_item_id',it,'amount',100,'benefits',jsonb_build_array(jsonb_build_object('benefit_id',b,'amount',100)))),
   jsonb_build_array(jsonb_build_object('payment_id',pay,'amount',100)),'[]','Unresolved qualification reward',gen_random_uuid());
  raise exception 'Refund bypassed qualification reward evidence';
 exception when others then if sqlerrm not like '%qualification reward entitlements%' then raise; end if; end;
 begin
  perform cancel_invoice_recorded(inv,'Unresolved qualification reward',gen_random_uuid());
  raise exception 'Cancellation bypassed qualification reward evidence';
 exception when others then if sqlerrm not like '%qualification reward entitlements%' then raise; end if; end;
 -- The block must be answerable, not permanent: resolving the rewards lets the
 -- ordinary cancellation through, and the sale records that it was resolved.
 perform resolve_invoice_credit_rewards(inv,'Reviewed the reward entitlements for this return');
 perform cancel_invoice_recorded(inv,'Cancel after resolving the rewards',gen_random_uuid());
 if (select status::text from invoices where id=inv)<>'cancelled' then
  raise exception 'Cancellation still blocked after the rewards were resolved'; end if;

 raise notice 'PASS: true pre178 missing bonus link stays pending; explicit source/no-bonus review; full refund revokes paid and bonus credit; qualification rewards cannot bypass review, and the review can actually be completed';
end $$;
rollback;
