begin;
do $$
declare o uuid:=gen_random_uuid(); st uuid; st2 uuid; a uuid; b uuid; c uuid; cash uuid; wallet_paid uuid; wallet_bonus uuid;
 package_id uuid; purchase uuid; original_paid uuid; original_bonus uuid; paid_benefit uuid; bonus_benefit uuid;
 first_paid uuid; final_paid uuid; final_bonus uuid; first_benefit uuid; last_benefit uuid; last_transfer uuid;
 product_own uuid; product_third uuid; session_voucher uuid; spend uuid; fake uuid; paid_restrictions jsonb;
 bundle_paid uuid; bundle_bonus uuid; bundle_benefit uuid; r jsonb; entry record;
begin
 insert into auth.users(id,email) values(o,'credit-transfer-policy@tests.invalid');
 insert into profiles(id,full_name,email,role) values(o,'Transfer Policy Owner','credit-transfer-policy@tests.invalid','owner');
 perform set_config('request.jwt.claim.sub',o::text,true);
 insert into stores(name,code,country_code) values('Credit Policy Origin','CPO','SG') returning id into st;
 insert into stores(name,code,country_code) values('Credit Policy Destination','CPD','SG') returning id into st2;
 insert into customers(full_name,phone) values('Policy Original','+6591238741') returning id into a;
 insert into customers(full_name,phone) values('Policy First Recipient','+6591238742') returning id into b;
 insert into customers(full_name,phone) values('Policy Final Recipient','+6591238743') returning id into c;
 insert into payment_methods(name) values('Credit Policy Cash') returning id into cash;
 select id into wallet_paid from payment_methods where is_system and wallet_category='paid' limit 1;
 select id into wallet_bonus from payment_methods where is_system and wallet_category='bonus' limit 1;
 if wallet_paid is null or wallet_bonus is null then raise exception 'Wallet payment methods are missing from the baseline'; end if;

 insert into credit_packages(name,customer_price,paid_credit_amount,bonus_enabled,bonus_value,allow_product,allow_therapy,allow_voucher,grants_reward)
  values('Recorded Policy Package',100,120,true,20,true,true,true,false) returning id into package_id;
 insert into credit_package_stores(package_id,store_id) values(package_id,st);
 purchase:=create_invoice(st,a,null,jsonb_build_array(jsonb_build_object('kind','credit_package','credit_package_id',package_id,'quantity',1)));
 perform record_invoice_payment(purchase,jsonb_build_array(jsonb_build_object('payment_method_id',cash,'amount',100)),gen_random_uuid());
 select v.id,v.lot_id into paid_benefit,original_paid from invoice_benefit_values v join customer_credit_lots l on l.id=v.lot_id where v.invoice_id=purchase and l.category='paid';
 select v.id,v.lot_id into bonus_benefit,original_bonus from invoice_benefit_values v join customer_credit_lots l on l.id=v.lot_id where v.invoice_id=purchase and l.category='bonus';
 select usage_restrictions into paid_restrictions from customer_credit_lots where id=original_paid;
 r:=transfer_invoice_unused_benefit(paid_benefit,b,st2,'Correct the unused paid-credit recipient',gen_random_uuid());
 first_benefit:=(r->>'benefit_id')::uuid;
 select lot_id into first_paid from invoice_benefit_values where id=first_benefit;
 r:=transfer_invoice_unused_benefit(first_benefit,c,st2,'Correct recipient again with original provenance',gen_random_uuid());
 last_benefit:=(r->>'benefit_id')::uuid;
 select lot_id into final_paid from invoice_benefit_values where id=last_benefit;
 select source_record_id into last_transfer from customer_credit_lots where id=final_paid;
 r:=transfer_invoice_unused_benefit(bonus_benefit,c,st2,'Correct the unused bonus-credit recipient',gen_random_uuid());
 select lot_id into final_bonus from invoice_benefit_values where id=(r->>'benefit_id')::uuid;
 if credit_lot_policy_for(final_paid)<>'package_paid' or credit_lot_policy_for(final_bonus)<>'package_bonus' then
  raise exception 'Transferred package credit lost the original paid/bonus policy'; end if;
 if (select usage_restrictions from customer_credit_lots where id=final_paid) is distinct from paid_restrictions
  or (select category from customer_credit_lots where id=final_bonus)<>'bonus'
  or (select remaining_amount from customer_credit_lots where id=original_paid)<>0
  or (select remaining_amount from customer_credit_lots where id=first_paid)<>0 then
  raise exception 'Transfers changed restrictions/category or duplicated the original credit'; end if;
 if not exists(select 1 from customer_credit_eligibility(c) where lot_id=final_paid and policy='package_paid' and not needs_review and source_name='Recorded Policy Package')
  or exists(select 1 from credit_lots_needing_review() where lot_id in(final_paid,final_bonus)) then
  raise exception 'Eligibility/review screens do not agree with transferred-credit spending policy'; end if;

 insert into products(name,sku,product_type) values('Transfer Policy Own Product','CP-OWN','own') returning id into product_own;
 insert into products(name,sku,product_type) values('Transfer Policy Third Party','CP-THIRD','third_party') returning id into product_third;
 insert into store_inventory(store_id,product_id,current_qty) values(st2,product_own,10),(st2,product_third,10);
 perform set_product_prices(st2,product_own,5,5,'available');
 perform set_product_prices(st2,product_third,5,5,'available');
 spend:=create_invoice(st2,c,null,jsonb_build_array(jsonb_build_object('kind','product','product_id',product_own,'quantity',1)));
 begin
  perform record_invoice_payment(spend,jsonb_build_array(jsonb_build_object('payment_method_id',wallet_paid,'amount',5)),gen_random_uuid());
  raise exception 'Restricted transferred paid credit bought an own-brand product';
 exception when others then if sqlerrm not like '%could be funded by eligible credit%' then raise; end if; end;
 perform record_invoice_payment(spend,jsonb_build_array(jsonb_build_object('payment_method_id',wallet_bonus,'amount',5)),gen_random_uuid());
 if not exists(select 1 from invoice_line_credit_allocations where invoice_id=spend and lot_id=final_bonus and amount=5) then
  raise exception 'The original-policy bonus lot did not fund the allowed product'; end if;
 if (select remaining_amount from customer_credit_lots where id=final_paid)<>120 then raise exception 'Disallowed purchase consumed package paid credit'; end if;
 insert into vouchers(name,code,qty_type,voucher_kind) values('Transferred Policy Session Voucher','CP-SESSION','unlimited','normal') returning id into session_voucher;
 perform consume_customer_credit(c,5,'manual_use',null,st2,'paid','Policy test direct voucher spend','voucher',session_voucher);
 if (select remaining_amount from customer_credit_lots where id=final_paid)<>115 then
  raise exception 'Direct spending failed to resolve the original policy of a twice-transferred lot'; end if;

 -- Both premium-bundle categories keep bundle rules through two transfers.
 insert into premium_bundles(name,customer_payment_amount,paid_credit_amount,bonus_credit_amount,free_voucher_qty,grants_reward)
  values('Recorded Policy Bundle',50,50,10,0,false) returning id into package_id;
 insert into premium_bundle_stores(bundle_id,store_id) values(package_id,st);
 purchase:=create_invoice(st,a,null,jsonb_build_array(jsonb_build_object('kind','premium_bundle','premium_bundle_id',package_id,'quantity',1,'voucher_selection','[]'::jsonb)));
 perform record_invoice_payment(purchase,jsonb_build_array(jsonb_build_object('payment_method_id',cash,'amount',50)),gen_random_uuid());
 for entry in select v.id,l.category from invoice_benefit_values v join customer_credit_lots l on l.id=v.lot_id where v.invoice_id=purchase loop
  r:=transfer_invoice_unused_benefit(entry.id,b,st2,'Move unused bundle allocation',gen_random_uuid());
  r:=transfer_invoice_unused_benefit((r->>'benefit_id')::uuid,c,st2,'Correct bundle recipient again',gen_random_uuid());
  bundle_benefit:=(r->>'benefit_id')::uuid;
  if entry.category='paid' then select lot_id into bundle_paid from invoice_benefit_values where id=bundle_benefit;
  else select lot_id into bundle_bonus from invoice_benefit_values where id=bundle_benefit; end if;
 end loop;
 if credit_lot_policy_for(bundle_paid)<>'bundle_any' or credit_lot_policy_for(bundle_bonus)<>'bundle_any' then
  raise exception 'Transferred bundle credit did not retain the bundle policy'; end if;
 spend:=create_invoice(st2,c,null,jsonb_build_array(jsonb_build_object('kind','product','product_id',product_third,'quantity',1)));
 perform record_invoice_payment(spend,jsonb_build_array(jsonb_build_object('payment_method_id',wallet_paid,'amount',5)),gen_random_uuid());
 if not exists(select 1 from invoice_line_credit_allocations where invoice_id=spend and lot_id=bundle_paid and amount=5)
  or (select remaining_amount from customer_credit_lots where id=final_paid)<>115 then
  raise exception 'Third-party spending did not select only the transferred bundle credit'; end if;
 if credit_policy_allows(credit_lot_policy_for(bundle_paid),'credit_package')
  or credit_policy_allows(credit_lot_policy_for(final_bonus),'third_party_product') then
  raise exception 'Transfer weakened the original spending restrictions'; end if;

 -- A matching source_type/source_record_id alone is not proof of a transfer.
 fake:=grant_customer_credit(c,'paid',5,'invoice_benefit_transfer',last_transfer,st2);
 if credit_lot_policy_for(fake)<>'needs_review'
  or not exists(select 1 from credit_lots_needing_review() where lot_id=fake)
  or credit_lot_policy('invoice_benefit_transfer','paid',true)<>'needs_review' then
  raise exception 'An unlinked transfer claim was treated as spendable'; end if;
 begin
  update invoice_benefit_transfers set source_benefit_id=replacement_benefit_id where id=last_transfer;
  if credit_lot_policy_for(final_paid)<>'needs_review' then raise exception 'Cyclic transfer provenance was accepted'; end if;
  raise exception 'Rollback cyclic fixture';
 exception when raise_exception then if sqlerrm<>'Rollback cyclic fixture' then raise; end if; end;
 begin
  update customer_credit_lots set usage_restrictions='{}' where id=final_paid;
  if credit_lot_policy_for(final_paid)<>'needs_review' then raise exception 'Changed transfer restrictions were accepted'; end if;
  raise exception 'Rollback restriction fixture';
 exception when raise_exception then if sqlerrm<>'Rollback restriction fixture' then raise; end if; end;
 if credit_lot_policy_for(final_paid)<>'package_paid' then raise exception 'Fixture rollback did not preserve the valid transfer chain'; end if;
 if has_function_privilege('anon','public.invoice_credit_transfer_origin(uuid)','EXECUTE')
  or has_function_privilege('authenticated','public.invoice_credit_transfer_origin(uuid)','EXECUTE') then
  raise exception 'Private transfer ancestry was exposed directly'; end if;
 perform set_config('request.jwt.claim.sub','',true);
 if credit_lot_policy_for(final_paid)<>'needs_review' then raise exception 'Unauthenticated policy lookup bypassed wallet visibility'; end if;
 perform set_config('request.jwt.claim.sub',o::text,true);
 raise notice 'PASS: paid/bonus package and bundle policies survive transfers of transfers, preserve restrictions, and drive real invoice/direct spending';
 raise notice 'PASS: eligibility and review agree; forged, cyclic and modified transfer provenance is blocked; private ancestry stays private';
end $$;
rollback;
