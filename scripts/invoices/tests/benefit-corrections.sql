begin;
do $$
declare o uuid:=gen_random_uuid(); st uuid; st2 uuid; c uuid; c2 uuid; pm uuid; cp uuid;
 inv uuid; it uuid; b uuid; lot uuid; pay uuid; p uuid; spend uuid; wpm uuid; v uuid; sid uuid; svc uuid;
 rid uuid:=gen_random_uuid(); crid uuid:=gen_random_uuid(); tid uuid:=gen_random_uuid();
 x jsonb; r jsonb; original jsonb; moved uuid; movedlot uuid; q jsonb;
begin
 insert into auth.users(id,email) values(o,'benefit-corrections@tests.invalid');
 insert into profiles(id,full_name,email,role) values(o,'Benefit Owner','benefit-corrections@tests.invalid','owner');
 perform set_config('request.jwt.claim.sub',o::text,true);
 insert into stores(name,code,country_code) values('Benefit Corrections','BC','SG') returning id into st;
 insert into stores(name,code,country_code) values('Benefit Destination','BD','SG') returning id into st2;
 insert into customers(full_name,phone) values('Original Recipient','+6591238791') returning id into c;
 insert into customers(full_name,phone) values('Correct Recipient','+6591238792') returning id into c2;
 insert into payment_methods(name) values('Benefit Cash') returning id into pm;
 -- allow_therapy too: paid package credit may only fund therapy sessions and
 -- therapy-session vouchers (242), so a package permitting products alone
 -- could not spend its paid balance at all.
 insert into credit_packages(name,customer_price,paid_credit_amount,allow_product,allow_therapy) values('Original Package',100,120,true,true) returning id into cp;
 insert into credit_package_stores(package_id,store_id) values(cp,st);
 inv:=create_invoice(st,c,null,jsonb_build_array(jsonb_build_object('kind','credit_package','credit_package_id',cp,'quantity',1)));
 perform record_invoice_payment(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',100)),gen_random_uuid());
 select id,to_jsonb(row_item) into it,original from invoice_items row_item where invoice_id=inv;
 select id,lot_id into b,lot from invoice_benefit_values where invoice_item_id=it;
 select id into pay from invoice_payments where invoice_id=inv;
 -- Retired/repriced catalogue cannot overwrite an issued grant during a price edit.
 update credit_packages set customer_price=999,paid_credit_amount=999,name='Changed Catalogue',deleted_at=now() where id=cp;
 x:=jsonb_build_array(jsonb_build_object('invoice_item_id',it,'kind','credit_package','credit_package_id',cp,'quantity',1,'unit_price',80));
 r:=correct_invoice(inv,x,'{}','Correct sold price',rid);
 if (r->>'refund_due')::numeric<>20 then raise exception 'Sold package reduction did not expose refund due: %',r; end if;
 q:=(select to_jsonb(row_item) from invoice_items row_item where id=it);
 if (q-array['unit_price','line_total','price_overridden','override_reason','override_by','override_at']) is distinct from
    (original-array['unit_price','line_total','price_overridden','override_reason','override_by','override_at']) then
  raise exception 'Price correction rewrote immutable grant/catalogue snapshots'; end if;
 if (select remaining_amount from customer_credit_lots where id=lot)<>120 then raise exception 'Price edit issued or revoked credit'; end if;
 perform correct_invoice(inv,x,'{}','Correct sold price',rid);
 begin
  perform correct_invoice(inv,x,'{"notes":"Different operation"}','Correct sold price',rid);
  raise exception 'Different correction payload accepted with reused request';
 exception when others then if sqlerrm not like '%different details%' then raise; end if; end;
 -- Real wallet consumption establishes that only unused value moves.
 -- Consumed as a therapy session, which is what paid package credit is for.
 -- This used to buy an own-brand product; the mandatory matrix now refuses that
 -- from a paid balance, and the point of the block -- that only the UNUSED part
 -- of a partly consumed benefit transfers -- is unchanged by what consumed it.
 svc:=(upsert_therapy_service(null,'BC-PR','Benefit Spend Session',60,30,'per_hours',1,5,null,true,null)->>'id')::uuid;
 perform set_therapy_service_store(svc,st,true,null);
 spend:=create_invoice(st,c,null,jsonb_build_array(jsonb_build_object('kind','therapy','therapy_service_id',svc,'quantity',1)));
 select id into wpm from payment_methods where wallet_category='paid' and is_system limit 1;
 perform record_invoice_payment(spend,jsonb_build_array(jsonb_build_object('payment_method_id',wpm,'amount',60)),gen_random_uuid());
 r:=transfer_invoice_unused_benefit(b,c2,st2,'Correct unused recipient',tid); moved:=(r->>'benefit_id')::uuid;
 select lot_id into movedlot from invoice_benefit_values where id=moved;
 if (select remaining_amount from customer_credit_lots where id=lot)<>0 or (select customer_id from customer_credit_lots where id=lot)<>c then
  raise exception 'Transfer changed original ownership or retained duplicate credit'; end if;
 if not exists(select 1 from customer_credit_lots where id=movedlot and customer_id=c2 and store_id=st2 and original_amount=60 and remaining_amount=60) then
  raise exception 'Unused portion not moved correctly'; end if;
 if (select paid_value from invoice_benefit_values where id=moved)<>50 then raise exception 'Transfer cashed out bonus value'; end if;
 if not exists(select 1 from invoice_line_credit_allocations where invoice_id=spend and lot_id=lot and amount=60) then
  raise exception 'Transfer rewrote consumed credit history'; end if;
 perform transfer_invoice_unused_benefit(b,c2,st2,'Correct unused recipient',tid);
 if (select count(*) from invoice_benefit_transfers where invoice_id=inv)<>1 then raise exception 'Transfer retry duplicated value'; end if;
 begin
  perform transfer_invoice_unused_benefit(b,c,st,'Changed transfer',tid);
  raise exception 'Reused transfer request accepted different recipient';
 exception when others then if sqlerrm not like '%different details%' then raise; end if; end;
 begin
  perform correct_invoice(inv,x,jsonb_build_object('customer_id',c2),'Change buyer',gen_random_uuid());
  raise exception 'Buyer correction silently changed issued recipients';
 exception when others then if sqlerrm not like '%Review the issued recipients%' then raise; end if; end;
 perform correct_invoice(inv,x,jsonb_build_object('customer_id',c2,'preserve_issued_recipients',true),'Reviewed buyer correction',gen_random_uuid());
 perform refund_invoice_recorded(inv,jsonb_build_array(jsonb_build_object('invoice_item_id',it,'amount',20,'overpayment',true,
  'benefits',jsonb_build_array(jsonb_build_object('benefit_id',moved,'amount',20)))),jsonb_build_array(jsonb_build_object('payment_id',pay,'amount',20)),
  '[]','Return corrected price difference from unused value',gen_random_uuid());
 if (select remaining_amount from customer_credit_lots where id=movedlot)<>36 then raise exception 'Moved benefit refund did not preserve proportional bonus rule'; end if;
 if invoice_charge_total(inv)<>80 or invoice_net_received(inv)<>80 then raise exception 'Overpayment refund reduced charge twice'; end if;
 perform cancel_invoice_recorded(inv,'Cancel remaining unused balance',crid);
 perform reopen_invoice(inv,'Restore unused balance after review',gen_random_uuid());
 perform cancel_invoice_recorded(inv,'Cancel remaining unused balance',crid);
 if (select status from invoices where id=inv)='cancelled' then raise exception 'Old cancel retry cancelled a later reopening'; end if;
 if (select remaining_amount from customer_credit_lots where id=movedlot)<>60 then raise exception 'Reopening reinstated transferred credit incorrectly'; end if;
 if (select remaining_amount from customer_credit_lots where id=lot)<>0 then raise exception 'Reopening duplicated transferred original credit'; end if;
 -- Voucher transfers preserve originals and reconcile actual source locations.
 insert into vouchers(name,code,qty_type,reward_eligible) values('Transfer Voucher','BC-V','limited',true) returning id into v;
 insert into voucher_store_stock(voucher_id,store_id,current_qty) values(v,st,10),(v,st2,0);
 insert into voucher_store_prices(voucher_id,store_id,selling_price,available_at_store) values(v,st,20,true);
 insert into premium_bundles(name,customer_payment_amount,paid_credit_amount,free_voucher_qty,grants_reward)
  values('Transfer Bundle',140,100,2,true) returning id into cp;
 insert into premium_bundle_stores(bundle_id,store_id) values(cp,st);
 insert into premium_bundle_vouchers(bundle_id,voucher_id) values(cp,v);
 inv:=create_invoice(st,c,null,jsonb_build_array(jsonb_build_object('kind','premium_bundle','premium_bundle_id',cp,'quantity',1,
  'voucher_selection',jsonb_build_array(jsonb_build_object('voucher_id',v,'quantity',2)))));
 perform record_invoice_payment(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',140)),gen_random_uuid());
 select id,reward_voucher_id into b,sid from invoice_benefit_values where invoice_id=inv and reward_voucher_id is not null;
 begin
  perform transfer_invoice_unused_benefit(b,c2,st2,'No destination stock',gen_random_uuid());
  raise exception 'Moved vouchers with no destination stock';
 exception when others then if sqlerrm not like '%Not enough voucher stock%' then raise; end if; end;
 if (select status from customer_reward_vouchers where id=sid)<>'held' then raise exception 'Failed transfer partially revoked voucher'; end if;
 update voucher_store_stock set current_qty=5 where voucher_id=v and store_id=st2;
 r:=transfer_invoice_unused_benefit(b,c2,st2,'Correct unused voucher recipient',gen_random_uuid()); moved:=(r->>'benefit_id')::uuid;
 if (select current_qty from voucher_store_stock where voucher_id=v and store_id=st)<>10
  or (select current_qty from voucher_store_stock where voucher_id=v and store_id=st2)<>3 then raise exception 'Voucher transfer lost stock locations'; end if;
 if (select status from customer_reward_vouchers where id=sid)<>'revoked' then raise exception 'Voucher transfer left duplicate held units'; end if;
 update customer_reward_vouchers set status='redeemed' where id=(select reward_voucher_id from invoice_benefit_values where id=moved);
 begin
  perform transfer_invoice_unused_benefit(moved,c,st,'Cannot transfer used vouchers',gen_random_uuid());
  raise exception 'Redeemed voucher transfer accepted';
 exception when others then if sqlerrm not like '%Only unused held vouchers%' then raise; end if; end;
 -- A sale stock movement cannot establish that an ordinary sold voucher is
 -- unused. Since 254 a voucher sold through this code DOES record its issued
 -- units, so this block deletes them to reproduce the case that still has no
 -- evidence: a voucher sold before issuance was recorded at all. That
 -- historical case is what must stay pending review, and it is the only one --
 -- scripts/invoices/tests/sold-voucher-issuance.sql covers the tracked path.
 inv:=create_invoice(st,c,null,jsonb_build_array(jsonb_build_object('kind','voucher','voucher_id',v,'quantity',1)));
 perform record_invoice_payment(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',20)),gen_random_uuid());
 select id into it from invoice_items where invoice_id=inv;
 select id into pay from invoice_payments where invoice_id=inv;
 delete from invoice_benefit_values where invoice_item_id=it;
 delete from customer_reward_vouchers where source_type='invoice_voucher_sale' and source_id=it;
 begin
  perform refund_invoice_recorded(inv,jsonb_build_array(jsonb_build_object('invoice_item_id',it,'amount',20)),
   jsonb_build_array(jsonb_build_object('payment_id',pay,'amount',20)),'[]','Unknown voucher use',gen_random_uuid());
  raise exception 'Untracked sold voucher was refunded without unused evidence';
 exception when others then if sqlerrm not like '%source-linked unused/redemption%' then raise; end if; end;
 begin
  perform cancel_invoice_recorded(inv,'Unknown voucher use',gen_random_uuid());
  raise exception 'Cancellation bypassed untracked voucher review';
 exception when others then if sqlerrm not like '%Review the original issued voucher units%' then raise; end if; end;
 if jsonb_array_length(invoice_refund_options(inv)->'review_notes')<>1 then raise exception 'Missing voucher review guidance'; end if;
 -- Simulate an unmapped historical package, with exact original bonus evidence.
 insert into credit_packages(name,customer_price,paid_credit_amount,bonus_enabled,bonus_value,allow_product)
  values('Historical bonus evidence',100,100,true,20,true) returning id into cp;
 insert into credit_package_stores(package_id,store_id) values(cp,st);
 inv:=create_invoice(st,c,null,jsonb_build_array(jsonb_build_object('kind','credit_package','credit_package_id',cp,'quantity',1)));
 perform record_invoice_payment(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',100)),gen_random_uuid());
 select id into it from invoice_items where invoice_id=inv;
 select credit_lot_id,bonus_credit_lot_id into lot,movedlot from credit_package_sales where invoice_id=inv;
 delete from invoice_benefit_values where invoice_id=inv; -- fixture only: mimic legacy absence
 begin
  perform record_invoice_benefit_values(it,jsonb_build_array(jsonb_build_object('lot_id',lot,'paid_value',100,'granted_value',100)),'Original purchase record reviewed');
  raise exception 'Incomplete historical allocation accepted';
 exception when others then if sqlerrm not like '%Record every original%' then raise; end if; end;
 if exists(select 1 from invoice_benefit_values where invoice_id=inv) then raise exception 'Partial mapping committed after validation failure'; end if;
 perform record_invoice_benefit_values(it,jsonb_build_array(jsonb_build_object('lot_id',lot,'paid_value',83.33,'granted_value',100),
  jsonb_build_object('lot_id',movedlot,'paid_value',16.67,'granted_value',20)),'Original paid and bonus grants and receipt reviewed');
 if (select count(*) from invoice_benefit_values where invoice_id=inv)<>2 then raise exception 'Complete bonus mapping not saved'; end if;
 x:=jsonb_build_array(jsonb_build_object('invoice_item_id',it,'kind','credit_package','credit_package_id',cp,'quantity',1));
 rid:=gen_random_uuid();
 original:=(select to_jsonb(row_invoice) from invoices row_invoice where id=inv);
 r:=correct_invoice(inv,x,'{}','Save unchanged invoice',rid);
 if not coalesce((r->>'unchanged')::boolean,false) or original is distinct from (select to_jsonb(row_invoice) from invoices row_invoice where id=inv) then
  raise exception 'No-op save changed invoice state'; end if;
 perform correct_invoice(inv,x,'{"notes":"Later correction"}','Subsequent correction',gen_random_uuid());
 perform correct_invoice(inv,x,'{}','Save unchanged invoice',rid);
 if (select notes from invoices where id=inv)<>'Later correction' then raise exception 'No-op retry overwrote subsequent correction'; end if;
 perform cancel_invoice_recorded(inv,'Cancel for no-op retry check',gen_random_uuid());
 rid:=gen_random_uuid();
 perform cancel_invoice_recorded(inv,'Already cancelled request',rid);
 perform reopen_invoice(inv,'Later reopening',gen_random_uuid());
 perform cancel_invoice_recorded(inv,'Already cancelled request',rid);
 if (select status from invoices where id=inv)='cancelled' then raise exception 'Initially unchanged cancellation replayed after reopening'; end if;
 raise notice 'PASS: sold-price correction preserves snapshots; request payload binding; partially consumed credit transfer, refund and reopening; buyer confirmation; voucher transfer stock and redeemed protection';
 raise notice 'PASS: unknown voucher usage stays pending review; incomplete historical mappings roll back; exact bonus lot mapping accepted';
 raise notice 'PASS: successful no-op retries cannot overwrite a later edit or cancel a later reopening';
end $$;
rollback;
