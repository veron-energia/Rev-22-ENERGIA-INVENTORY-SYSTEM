begin;
do $$
declare o uuid:=gen_random_uuid(); st uuid; c uuid; c2 uuid; af uuid; p uuid; promo uuid; v uuid; pm uuid; inv uuid; it uuid; pay uuid; lot uuid; b uuid; cp uuid;
 x jsonb; r jsonb; before_item jsonb; st_before int; sid uuid; amt numeric;
begin
 insert into auth.users(id,email) values(o,'extended@tests.invalid');
 insert into profiles(id,full_name,email,role) values(o,'Extended Owner','extended@tests.invalid','owner');
 perform set_config('request.jwt.claim.sub',o::text,true);
 insert into stores(name,code,country_code) values('Extended Tests','EXT','SG') returning id into st;
 insert into customers(full_name,phone) values('Buyer','+6591238800') returning id into c;
 insert into customers(full_name,phone) values('Recipient and Referrer','+6591238801') returning id into c2;
 insert into customer_affiliates(customer_id,status) values(c2,'active') returning id into af;
 update customers set referred_by=c2 where id=c;
 insert into payment_methods(name) values('Extended Cash') returning id into pm;
 insert into products(name,sku,product_type) values('Fixed Snapshot Product','EXT-P','own') returning id into p;
 insert into store_inventory(store_id,product_id,current_qty) values(st,p,100);
 perform set_product_prices(st,p,100,100,'available');
 insert into promotions(name,code) values('Snapshot Bundle','EXT-PROMO') returning id into promo;
 insert into promotion_items(promotion_id,item_type,product_id,quantity) values(promo,'product',p,2);
 insert into promotion_store_prices(promotion_id,store_id,selling_price) values(promo,st,100);
 inv:=create_invoice(st,c,null,jsonb_build_array(jsonb_build_object('kind','promotion','promotion_id',promo,'quantity',1)));
 -- Change catalogue AFTER saving; payment must issue the saved two units.
 update promotion_items set quantity=7 where promotion_id=promo;
 perform record_invoice_payment(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',100)),gen_random_uuid());
 if (select current_qty from store_inventory where store_id=st and product_id=p)<>98 then raise exception 'Payment used changed catalogue stock'; end if;
 select id,to_jsonb(t) into it,before_item from invoice_items t where invoice_id=inv;
 x:=jsonb_build_array(jsonb_build_object('invoice_item_id',it,'kind','promotion','promotion_id',promo,'quantity',1));
 r:=edit_paid_invoice(inv,x,'Affiliate-only correction',null,null,null,af,true);
 if before_item is distinct from (select to_jsonb(t) from invoice_items t where id=it) then raise exception 'Affiliate correction rebuilt a line'; end if;
 if exists(select 1 from invoice_items where invoice_id is null) then raise exception 'Invoice id integrity lost'; end if;
 r:=correct_invoice(inv,x,'{"affiliate_id":null}','Explicitly clear affiliate',gen_random_uuid());
 if (invoice_effective_affiliate(inv)->>'has_affiliate')::boolean then raise exception 'Cleared affiliate fell back to customer referrer'; end if;
 if exists(select 1 from commissions where invoice_id=inv and status in ('earned','blocked') and commission_amount>0) then raise exception 'Cleared affiliate still earns'; end if;
 perform correct_invoice(inv,x,'{"notes":"Preserve explicit none"}','Unrelated correction',gen_random_uuid());
 if (invoice_effective_affiliate(inv)->>'has_affiliate')::boolean then raise exception 'Unrelated edit changed affiliate'; end if;
 perform cancel_invoice_recorded(inv,'Cancel snapshot bundle',gen_random_uuid());
 if (select current_qty from store_inventory where store_id=st and product_id=p)<>100 then raise exception 'Cancellation used changed catalogue'; end if;
 -- Explicit price correction preserves line identity and makes additional amount owing.
 inv:=create_invoice(st,c,null,jsonb_build_array(jsonb_build_object('kind','product','product_id',p,'quantity',1)));
 perform pay_invoice(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',100)));
 select id into it from invoice_items where invoice_id=inv;
 x:=jsonb_build_array(jsonb_build_object('invoice_item_id',it,'kind','product','product_id',p,'quantity',1,'unit_price',150));
 r:=correct_invoice(inv,x,'{}','Correct unit price',gen_random_uuid());
 if (r->>'outstanding')::numeric<>50 or (select unit_price from invoice_items where id=it)<>150 then raise exception 'Price correction did not create owing balance: %',r; end if;
 -- Separate bonus lot and multi-recipient issuance retain exact original lot links.
 insert into credit_packages(name,customer_price,paid_credit_amount,bonus_enabled,bonus_value,allow_product,grants_reward)
 values('Paid plus bonus',100,100,true,20,true,false) returning id into cp;
 insert into credit_package_stores(package_id,store_id) values(cp,st);
 inv:=create_invoice(st,c,null,jsonb_build_array(jsonb_build_object('kind','credit_package','credit_package_id',cp,'quantity',1)));
 select id into it from invoice_items where invoice_id=inv;
 insert into invoice_credit_splits(invoice_id,invoice_item_id,customer_id,amount,created_by) values(inv,it,c,50,o),(inv,it,c2,50,o);
 perform pay_invoice(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',100)));
 if (select count(*) from invoice_benefit_values where invoice_item_id=it)<>4 then raise exception 'Paid and bonus lots for both recipients not captured'; end if;
 if (select sum(paid_value) from invoice_benefit_values where invoice_item_id=it)<>100 then raise exception 'Bonus paid values do not reconcile to actual money'; end if;
 select id into pay from invoice_payments where invoice_id=inv;
 select bv.id,bv.lot_id,bv.paid_value into b,lot,amt from invoice_benefit_values bv join customer_credit_lots l on l.id=bv.lot_id where bv.invoice_item_id=it and l.customer_id=c2 and l.category='bonus';
 perform cancel_invoice_recorded(inv,'Cancel unused credits',gen_random_uuid());
 if (select remaining_amount from customer_credit_lots where id=lot)<>0 then raise exception 'Cancelled bonus remains spendable'; end if;
 perform refund_invoice_recorded(inv,jsonb_build_array(jsonb_build_object('invoice_item_id',it,'amount',amt,'benefits',jsonb_build_array(jsonb_build_object('benefit_id',b,'amount',amt)))),
 jsonb_build_array(jsonb_build_object('payment_id',pay,'amount',amt)),'[]','Refund recipient bonus allocation',gen_random_uuid());
 if (select cancelled_unused_value from invoice_benefit_values where id=b)<>0 then raise exception 'Cancelled refund did not release its reserved benefit'; end if;
 -- Unused voucher benefits are refunded in whole units, with actual paid allocation.
 insert into vouchers(name,code,qty_type,reward_eligible) values('Unused reward','EXT-V','limited',true) returning id into v;
 insert into voucher_store_stock(voucher_id,store_id,current_qty) values(v,st,100);
 insert into voucher_store_prices(voucher_id,store_id,selling_price,available_at_store) values(v,st,20,true);
 insert into premium_bundles(name,customer_payment_amount,paid_credit_amount,free_voucher_qty,grants_reward)
 values('Voucher allocation',140,100,2,true) returning id into cp;
 insert into premium_bundle_stores(bundle_id,store_id) values(cp,st);
 insert into premium_bundle_vouchers(bundle_id,voucher_id) values(cp,v);
 inv:=create_invoice(st,c,null,jsonb_build_array(jsonb_build_object('kind','premium_bundle','premium_bundle_id',cp,'quantity',1,
  'voucher_selection',jsonb_build_array(jsonb_build_object('voucher_id',v,'quantity',2)))));
 perform pay_invoice(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',140)));
 select id into it from invoice_items where invoice_id=inv;
 select id into pay from invoice_payments where invoice_id=inv;
 select id,reward_voucher_id into b,sid from invoice_benefit_values where invoice_item_id=it and reward_voucher_id is not null;
 if b is null then raise exception 'Voucher allocation was not captured'; end if;
 perform refund_invoice_recorded(inv,jsonb_build_array(jsonb_build_object('invoice_item_id',it,'amount',20,'benefits',jsonb_build_array(jsonb_build_object('benefit_id',b,'amount',20)))),
  jsonb_build_array(jsonb_build_object('payment_id',pay,'amount',20)),'[]','One unused voucher',gen_random_uuid());
 if (select quantity from customer_reward_vouchers where id=sid)<>1 or (select status from customer_reward_vouchers where id=sid)<>'held' then raise exception 'Partial voucher refund revoked wrong quantity'; end if;
 if (select current_qty from voucher_store_stock where voucher_id=v and store_id=st)<>99 then raise exception 'Voucher return did not restore one'; end if;
 update customer_reward_vouchers set status='redeemed' where id=sid;
 begin
  perform refund_invoice_recorded(inv,jsonb_build_array(jsonb_build_object('invoice_item_id',it,'amount',20,'benefits',jsonb_build_array(jsonb_build_object('benefit_id',b,'amount',20)))),
   jsonb_build_array(jsonb_build_object('payment_id',pay,'amount',20)),'[]','Cannot refund redeemed voucher',gen_random_uuid());
  raise exception 'Redeemed voucher refund accepted';
 exception when others then if sqlerrm not like '%unused paid value%' then raise; end if; end;
 perform cancel_invoice_recorded(inv,'Cancel remaining bundle benefits',gen_random_uuid());
 if (invoice_reopen_preview(inv)->>'voucher_units_to_reinstate_after_settlement')::int<>1 then raise exception 'Reopen preview lost the refunded unused voucher'; end if;
 perform reopen_invoice(inv,'Replace only refunded unused benefits',gen_random_uuid());
 if exists(select 1 from invoice_reopen_vouchers where invoice_id=inv and applied_at is not null) then raise exception 'Vouchers issued before reopened settlement'; end if;
 perform record_invoice_payment(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',20)),gen_random_uuid());
 if (select count(*) from invoice_reopen_vouchers where invoice_id=inv and applied_at is not null)<>1 then raise exception 'Reopened settlement did not issue one traced replacement'; end if;
 if (select status from customer_reward_vouchers where id=sid)<>'redeemed' then raise exception 'Reopening erased the original redeemed voucher'; end if;
 if (select current_qty from voucher_store_stock where voucher_id=v and store_id=st)<>98 then raise exception 'Reopening did not deduct replacement voucher stock once'; end if;
 raise notice 'PASS: unused voucher proration, partial-unit revocation, redeemed-voucher protection';
 raise notice 'PASS: exact edit_paid_invoice affiliate path, explicit clearing, immutable promotion stock, price increase, separate bonus lots, multi-recipient cancellation/refund';
end $$;
rollback;
