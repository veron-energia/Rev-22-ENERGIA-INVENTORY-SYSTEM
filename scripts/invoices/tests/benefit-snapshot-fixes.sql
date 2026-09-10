begin;
do $$
<<benefit_snapshot_fixes>>
declare o uuid:=gen_random_uuid(); st uuid; st2 uuid; c uuid; c2 uuid; pm uuid; reason_id uuid;
 package_id uuid; inv uuid; item_id uuid; benefit_id uuid; moved_benefit uuid; original_voucher uuid;
 transferred_voucher uuid; replacement_voucher uuid; voucher_id uuid; payment_id uuid; request_id uuid;
 k int; line_kind text; price numeric; foc numeric; new_price numeric; expected_charge numeric;
 x jsonb; r jsonb; original_item jsonb; original_lots jsonb; original_values jsonb;
begin
 insert into auth.users(id,email) values(o,'benefit-snapshot-fixes@tests.invalid');
 insert into profiles(id,full_name,email,role) values(o,'Benefit Snapshot Owner','benefit-snapshot-fixes@tests.invalid','owner');
 perform set_config('request.jwt.claim.sub',o::text,true);
 insert into stores(name,code,country_code) values('Benefit Snapshot Origin','BSO','SG') returning id into st;
 insert into stores(name,code,country_code) values('Benefit Snapshot Destination','BSD','SG') returning id into st2;
 insert into customers(full_name,phone) values('Snapshot Buyer','+6591238751') returning id into c;
 insert into customers(full_name,phone) values('Snapshot Recipient','+6591238752') returning id into c2;
 insert into payment_methods(name) values('Benefit Snapshot Cash') returning id into pm;
 select id into reason_id from foc_reasons where code='staff_welfare';
 if reason_id is null then raise exception 'Fixture requires the seeded Staff Welfare FOC reason'; end if;

 -- These are real saved credit-purchase lines with original grant snapshots.
 -- The historical RPC records FOC amounts; a saved reason is attached before
 -- actual settlement issuance. No credit lot or benefit allocation is fabricated.
 for k in 1..3 loop
  line_kind:=case when k=2 then 'premium_bundle' else 'credit_package' end;
  price:=case when k=2 then 140 else 100 end;
  foc:=case when k=3 then 20 else price end;
  new_price:=case when k=2 then 110 else 80 end;
  expected_charge:=case when k=3 then 60 else 0 end;
  if line_kind='credit_package' then
   insert into credit_packages(name,customer_price,paid_credit_amount,allow_product,grants_reward)
    values('Saved FOC Package '||k,price,120,true,false) returning id into package_id;
   insert into credit_package_stores(package_id,store_id) values(package_id,st);
  else
   insert into premium_bundles(name,customer_payment_amount,paid_credit_amount,bonus_credit_amount,free_voucher_qty,grants_reward)
    values('Saved FOC Bundle',price,100,20,0,false) returning id into package_id;
   insert into premium_bundle_stores(bundle_id,store_id) values(package_id,st);
  end if;
  inv:=create_credit_purchase_invoice(st,c,jsonb_build_array(jsonb_build_object('kind',line_kind,'id',package_id,'foc_amount',foc,'voucher_selection','[]'::jsonb)));
  select id into item_id from invoice_items where invoice_id=inv;
  update invoice_items set foc_reason_id=reason_id,foc_reason='Staff Welfare — Saved benefit reason' where id=item_id;
  if k=3 then
   perform record_invoice_payment(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',price-foc)),gen_random_uuid());
  else
   update invoices set status='completed_foc' where id=inv;
  end if;
  if not exists(select 1 from invoice_items where id=item_id and credit_issued_at is not null and foc_quantity=1) then
   raise exception 'Fixture did not issue the saved FOC benefit'; end if;
  select to_jsonb(q) into original_item from invoice_items q where id=item_id;
  select jsonb_agg(to_jsonb(q) order by q.id) into original_lots from customer_credit_lots q
   join invoice_benefit_values b on b.lot_id=q.id where b.invoice_id=inv;
  select jsonb_agg(to_jsonb(b) order by b.id) into original_values from invoice_benefit_values b where b.invoice_id=inv;
  if original_lots is null or original_values is null then raise exception 'Fixture did not capture issued benefits'; end if;
  if line_kind='credit_package' then
   update credit_packages set name='Retired and repriced package',customer_price=999,paid_credit_amount=999,deleted_at=now() where id=package_id;
  else
   update premium_bundles set name='Retired and repriced bundle',customer_payment_amount=999,paid_credit_amount=999,bonus_credit_amount=999,deleted_at=now() where id=package_id;
  end if;
  update foc_reasons set is_active=false where id=reason_id;
  x:=jsonb_build_array(jsonb_build_object('invoice_item_id',item_id,'kind',line_kind,'quantity',1,'unit_price',new_price,
   'foc_quantity',1,'foc_reason_id',reason_id,'foc_reason','Staff Welfare — Saved benefit reason','voucher_selection','[]'::jsonb)
   ||case when line_kind='credit_package' then jsonb_build_object('credit_package_id',package_id) else jsonb_build_object('premium_bundle_id',package_id) end);
  request_id:=gen_random_uuid();
  r:=correct_invoice(inv,x,'{}','Correct price while preserving the saved FOC allocation',request_id);
  if (select total_amount from invoices where id=inv)<>expected_charge
   or (select line_total from invoice_items where id=item_id)<>expected_charge
   or (select foc_total from invoices where id=inv)<>new_price-expected_charge
   or (select foc_amount from invoice_items where id=item_id)<>new_price-expected_charge then
   raise exception 'Saved FOC benefit price correction charged the wrong amount: kind %, response %',line_kind,r; end if;
  if k<>3 and ((r->>'outstanding')::numeric<>0 or (select status from invoices where id=inv)<>'completed_foc') then
   raise exception 'A saved fully FOC benefit became payable: %',r; end if;
  if (original_item-array['unit_price','line_total','foc_amount','price_overridden','override_reason','override_by','override_at']) is distinct from
   ((select to_jsonb(q) from invoice_items q where id=item_id)-array['unit_price','line_total','foc_amount','price_overridden','override_reason','override_by','override_at']) then
   raise exception 'Benefit price correction changed saved catalogue/grant/FOC reason snapshots'; end if;
  if original_lots is distinct from (select jsonb_agg(to_jsonb(q) order by q.id) from customer_credit_lots q
   join invoice_benefit_values b on b.lot_id=q.id where b.invoice_id=inv)
   or original_values is distinct from (select jsonb_agg(to_jsonb(b) order by b.id) from invoice_benefit_values b where b.invoice_id=inv) then
   raise exception 'FOC price correction reissued or changed a purchased benefit'; end if;
  perform correct_invoice(inv,x,'{}','Correct price while preserving the saved FOC allocation',request_id);
 end loop;

 -- Move real bundle vouchers A -> B, refund one unit, cancel the remainder,
 -- then reopen and fully settle. Both replacement units must remain at B.
 insert into vouchers(name,code,qty_type,reward_eligible) values('Store-preserving Voucher','BS-V','limited',true) returning id into voucher_id;
 insert into voucher_store_stock(voucher_id,store_id,current_qty) values(voucher_id,st,10),(voucher_id,st2,5);
 insert into voucher_store_prices(voucher_id,store_id,selling_price,available_at_store) values(voucher_id,st,20,true),(voucher_id,st2,20,true);
 insert into premium_bundles(name,customer_payment_amount,paid_credit_amount,free_voucher_qty,grants_reward)
  values('Store-preserving Bundle',140,100,2,true) returning id into package_id;
 insert into premium_bundle_stores(bundle_id,store_id) values(package_id,st);
 insert into premium_bundle_vouchers(bundle_id,voucher_id) values(package_id,voucher_id);
 inv:=create_invoice(st,c,null,jsonb_build_array(jsonb_build_object('kind','premium_bundle','premium_bundle_id',package_id,'quantity',1,
  'voucher_selection',jsonb_build_array(jsonb_build_object('voucher_id',voucher_id,'quantity',2)))));
 perform record_invoice_payment(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',140)),gen_random_uuid());
 select id into item_id from invoice_items where invoice_id=inv;
 select id into payment_id from invoice_payments where invoice_id=inv;
 select id,reward_voucher_id into benefit_id,original_voucher from invoice_benefit_values where invoice_id=inv and reward_voucher_id is not null;
 r:=transfer_invoice_unused_benefit(benefit_id,c2,st2,'Correct recorded recipient and voucher store',gen_random_uuid());
 moved_benefit:=(r->>'benefit_id')::uuid;
 select reward_voucher_id into transferred_voucher from invoice_benefit_values where id=moved_benefit;
 perform refund_invoice_recorded(inv,jsonb_build_array(jsonb_build_object('invoice_item_id',item_id,'amount',20,
  'benefits',jsonb_build_array(jsonb_build_object('benefit_id',moved_benefit,'amount',20)))),
  jsonb_build_array(jsonb_build_object('payment_id',payment_id,'amount',20)),'[]','Refund one unused moved voucher',gen_random_uuid());
 perform cancel_invoice_recorded(inv,'Cancel remaining moved benefits',gen_random_uuid());
 if (select current_qty from voucher_store_stock s where s.voucher_id=benefit_snapshot_fixes.voucher_id and s.store_id=st)<>10
  or (select current_qty from voucher_store_stock s where s.voucher_id=benefit_snapshot_fixes.voucher_id and s.store_id=st2)<>5 then
  raise exception 'Cancellation/refund did not restore the actual voucher stores'; end if;
 r:=reopen_invoice(inv,'Restore the recorded recipient and store after review',gen_random_uuid());
 if (r->>'outstanding')::numeric<>20 or exists(select 1 from invoice_reopen_vouchers where invoice_id=inv and applied_at is not null) then
  raise exception 'Reopening should await the remaining actual payment: %',r; end if;
 request_id:=gen_random_uuid();
 perform record_invoice_payment(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',20)),request_id);
 select replacement_voucher_id into replacement_voucher from invoice_reopen_vouchers where invoice_id=inv;
 if not exists(select 1 from customer_reward_vouchers where id=replacement_voucher and customer_id=c2 and store_id=st2 and quantity=2 and status='held') then
  raise exception 'Reopening lost the corrected voucher recipient or store'; end if;
 if (select current_qty from voucher_store_stock s where s.voucher_id=benefit_snapshot_fixes.voucher_id and s.store_id=st)<>10
  or (select current_qty from voucher_store_stock s where s.voucher_id=benefit_snapshot_fixes.voucher_id and s.store_id=st2)<>3 then
  raise exception 'Reopening deducted voucher stock from the invoice store instead of the recorded benefit store'; end if;
 perform record_invoice_payment(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',20)),request_id);
 if (select count(*) from invoice_reopen_vouchers where invoice_id=inv and applied_at is not null)<>1
  or (select status from customer_reward_vouchers where id=original_voucher)<>'revoked'
  or (select status from customer_reward_vouchers where id=transferred_voucher)<>'revoked' then
  raise exception 'Settlement retry duplicated a replacement or changed original voucher history'; end if;
 raise notice 'PASS: full FOC package/bundle price corrections preserve zero charge, retired snapshots, reasons and grants; historical monetary FOC remains intact';
 raise notice 'PASS: transferred vouchers preserve actual recipient/store through refund, cancellation, reopening and idempotent full settlement';
end $$;
rollback;
