-- Selling a voucher records what the customer received, so the line can be
-- refunded, cancelled and reviewed like every other benefit.
--
-- Before 254 this whole workflow was refused, for new sales as well as
-- historical ones. Disposable database only; everything is rolled back.
begin;
do $$
declare o uuid:=gen_random_uuid(); st uuid; c uuid; pm uuid; v uuid; vlim uuid;
 inv uuid; it uuid; pay uuid; ben record; inv2 uuid; it2 uuid; pay2 uuid; n integer;
begin
 insert into auth.users(id,email) values(o,'sold-voucher@tests.invalid');
 insert into profiles(id,full_name,email,role) values(o,'Owner','sold-voucher@tests.invalid','owner');
 perform set_config('request.jwt.claim.sub',o::text,true);
 insert into stores(name,code,country_code) values('Sold Voucher','SVT','SG') returning id into st;
 insert into customers(full_name,phone) values('SV Buyer','+6593330001') returning id into c;
 insert into payment_methods(name,is_active) values('SV Cash',true) returning id into pm;
 insert into vouchers(name,code,voucher_kind,selling_price,qty_type)
  values('Sold Limited','SVL','normal',40,'limited') returning id into vlim;
 insert into voucher_store_stock(voucher_id,store_id,current_qty) values(vlim,st,10);
 insert into voucher_store_prices(voucher_id,store_id,selling_price,available_at_store) values(vlim,st,40,true);

 -- Nothing is issued until the money is taken.
 inv:=create_invoice(st,c,null,jsonb_build_array(jsonb_build_object('kind','voucher','voucher_id',vlim,'quantity',2)));
 select id into it from invoice_items where invoice_id=inv;
 if exists(select 1 from customer_reward_vouchers where source_id=it) then
  raise exception 'Unpaid invoice issued voucher units'; end if;

 perform pay_invoice(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',80)));
 select * into ben from invoice_benefit_values where invoice_item_id=it;
 if ben.reward_voucher_id is null then raise exception 'Paid voucher line issued no units'; end if;
 if (select quantity from customer_reward_vouchers where id=ben.reward_voucher_id)<>2 then
  raise exception 'Issued unit count does not match the line quantity'; end if;
 if ben.paid_value<>80 or ben.granted_value<>2 then
  raise exception 'Issued benefit did not record the discounted line value and units'; end if;

 -- Issuing again must not double the customer's holdings.
 if issue_sold_vouchers_for_invoice(inv)<>0 then raise exception 'Re-issuing duplicated units'; end if;

 -- A line with recorded units is no longer a review case.
 if invoice_untracked_voucher(inv,it) then raise exception 'Tracked voucher line still treated as unreviewable'; end if;

 -- Money may not go back without saying which units come back with it.
 begin
  perform refund_invoice_recorded(inv,jsonb_build_array(jsonb_build_object('invoice_item_id',it,'amount',40)),
   jsonb_build_array(jsonb_build_object('payment_id',(select id from invoice_payments where invoice_id=inv)),'amount',40),
   '[]','No allocation',gen_random_uuid());
  raise exception 'Voucher refund accepted without a benefit allocation';
 exception when others then
  if sqlerrm like '%Voucher refund accepted%' then raise; end if; end;

 select id into pay from invoice_payments where invoice_id=inv;
 -- One of the two units, at its allocated paid value.
 perform refund_invoice_recorded(inv,
  jsonb_build_array(jsonb_build_object('invoice_item_id',it,'amount',40,
    'benefits',jsonb_build_array(jsonb_build_object('benefit_id',ben.id,'amount',40)))),
  jsonb_build_array(jsonb_build_object('payment_id',pay,'amount',40)),'[]','One unit returned',gen_random_uuid());
 if (select quantity from customer_reward_vouchers where id=ben.reward_voucher_id)<>1 then
  raise exception 'Partial voucher refund did not reduce the held units'; end if;
 if (select status from customer_reward_vouchers where id=ben.reward_voucher_id)<>'held' then
  raise exception 'Remaining unit was revoked by a partial refund'; end if;
 if (select current_qty from voucher_store_stock where voucher_id=vlim and store_id=st)<>9 then
  raise exception 'Limited voucher stock did not return with the refunded unit'; end if;

 -- More than remains cannot be refunded.
 begin
  perform refund_invoice_recorded(inv,
   jsonb_build_array(jsonb_build_object('invoice_item_id',it,'amount',80,
     'benefits',jsonb_build_array(jsonb_build_object('benefit_id',ben.id,'amount',80)))),
   jsonb_build_array(jsonb_build_object('payment_id',pay,'amount',80)),'[]','Too much',gen_random_uuid());
  raise exception 'Refund exceeded the remaining units';
 exception when others then
  if sqlerrm='Refund exceeded the remaining units' then raise; end if; end;

 -- Cancelling an invoice takes back the units it issued.
 insert into vouchers(name,code,voucher_kind,selling_price,qty_type)
  values('Sold Unlimited','SVU','normal',25,'unlimited') returning id into v;
 insert into voucher_store_prices(voucher_id,store_id,selling_price,available_at_store) values(v,st,25,true);
 inv2:=create_invoice(st,c,null,jsonb_build_array(jsonb_build_object('kind','voucher','voucher_id',v,'quantity',1)));
 perform pay_invoice(inv2,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',25)));
 select id into it2 from invoice_items where invoice_id=inv2;
 perform cancel_invoice_recorded(inv2,'Cancelled after issue',gen_random_uuid());
 if (select status from customer_reward_vouchers where source_id=it2)<>'revoked' then
  raise exception 'Cancelled invoice left its issued voucher units held'; end if;

 -- A line with no recorded units — the genuine historical case — stays pending.
 delete from invoice_benefit_values where invoice_item_id=it2;
 if not invoice_untracked_voucher(inv2,it2) then
  raise exception 'A line without issued units should still need review'; end if;
 select count(*) into n from invoice_untracked_voucher_lines() where invoice_item_id=it2;
 if n<>1 then raise exception 'Untracked voucher line missing from the review list'; end if;

 raise notice 'PASS: sold vouchers are issued at payment, refundable only with an allocation, revoked on cancellation, and untracked historical lines still need review';
end $$;
rollback;
