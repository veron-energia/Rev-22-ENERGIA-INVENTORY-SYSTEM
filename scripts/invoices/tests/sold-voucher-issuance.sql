-- Selling a voucher records what the customer received, so the line can be
-- refunded, cancelled and reviewed like every other benefit.
--
-- Before 254 this whole workflow was refused, for new sales as well as
-- historical ones. Disposable database only; everything is rolled back.
--
-- The second block (416, INVOICES-CREATE-7): a voucher, and a promotion's
-- voucher pick, given away on a fully FOC invoice are issued when the FOC is
-- confirmed, from the stock the confirmation takes, once; cancelling the
-- invoice takes them back and returns the stock. The third, the same
-- through Edit Invoice. The fourth (the Owner, 9 Oct 2026): taking the FOC
-- off a completed FOC invoice takes back its unused vouchers and returns
-- their stock, leaves used ones and reports them, and paying it gives them
-- again once; a correction that makes a part-paid voucher invoice paid takes
-- the voucher stock once, as Record Payment does. The fifth: the FOC taken
-- off in a save that also changes the lines (what is given again is what the
-- corrected lines give), stock taken once when a FOC invoice's products
-- change, a voucher moved to a friend, a line that gave vouchers removed, a
-- reopened FOC invoice, and therapy vouchers. The sixth: when the FOC comes
-- off, what Confirm FOC took is recorded by voucher, so a reopening's row at
-- one store counts for vouchers since moved to another (10 Oct 2026; with or
-- without 417). The seventh (10 Oct 2026): a save that keeps a FOC invoice
-- FOC keeps no voucher stock for a voucher line it raises, so the payment
-- after the FOC comes off takes each unit once; what Confirm FOC took is
-- recorded at the stores that hold the vouchers, store by store; and the
-- summary refuses what the save refuses (with 417 it also cancels and
-- checks 10 at each store). The eighth (10 Oct 2026): a premium bundle's
-- vouchers, moved to a friend or given again on a reopening, are not
-- counted as taken at Confirm FOC and not taken back when the FOC comes off
-- another line; a voucher moved to another store of the same customer is
-- taken back and given again when paid. The ninth runs with 417 only: a
-- voucher line raised or lowered while FOC, then cancel, reopen, cancel
-- (KNOWN FAULT notices while 417's reopen and cancel are the 10 Oct texts;
-- a failure with any other). The last prints the known
-- faults of batch B03's reopening as notices; it never fails. Needs 416 (psql -v
-- mig=supabase/416_invoice_editing_foc_and_payment_guards.sql installs it
-- after "begin;").
begin;
\if :{?mig}
\i :mig
\endif
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

-- ═════ 416: given free on a confirmed FOC invoice ═════
do $$
declare o uuid:=gen_random_uuid(); st uuid; c uuid; vlim uuid; pr uuid; g uuid;
 inv uuid; it uuid; inv2 uuid; it2 uuid; r jsonb;
begin
 insert into auth.users(id,email) values(o,'sold-voucher-foc@tests.invalid');
 insert into profiles(id,full_name,email,role) values(o,'Owner','sold-voucher-foc@tests.invalid','owner');
 perform set_config('request.jwt.claim.sub',o::text,true);
 insert into stores(name,code,country_code) values('Sold Voucher FOC','SVF','SG') returning id into st;
 insert into customers(full_name,phone) values('SVF Buyer','+61491571266') returning id into c;
 insert into vouchers(name,code,voucher_kind,selling_price,qty_type)
  values('Giveaway Limited','SVFL','normal',40,'limited') returning id into vlim;
 insert into voucher_store_stock(voucher_id,store_id,current_qty) values(vlim,st,10);
 insert into voucher_store_prices(voucher_id,store_id,selling_price,available_at_store) values(vlim,st,40,true);

 -- Two vouchers given away: issued when the FOC is confirmed.
 inv:=create_invoice(st,c,null,jsonb_build_array(jsonb_build_object('kind','voucher','voucher_id',vlim,'quantity',2)));
 select id into it from invoice_items where invoice_id=inv;
 perform apply_line_foc(it,null,null,'Event giveaway');
 if exists(select 1 from customer_reward_vouchers where source_id=it) then
  raise exception 'A FOC voucher was issued before the FOC was confirmed'; end if;
 r:=confirm_foc_invoice(inv,null);
 if r->>'status' is distinct from 'completed_foc' then raise exception 'FOC was not confirmed: %', r; end if;
 if (select quantity from customer_reward_vouchers where source_id=it and status='held') is distinct from 2 then
  raise exception 'Confirming a FOC invoice did not issue the two vouchers it gives'; end if;
 if (select current_qty from voucher_store_stock where voucher_id=vlim and store_id=st) is distinct from 8 then
  raise exception 'The FOC vouchers were not taken from stock once'; end if;
 if (select paid_value from invoice_benefit_values where invoice_item_id=it) is distinct from 0 then
  raise exception 'A free voucher was recorded as paid for'; end if;
 if issue_sold_vouchers_for_invoice(inv) is distinct from 0 then raise exception 'Issuing the FOC vouchers again duplicated them'; end if;

 -- A promotion whose voucher pick is given away.
 insert into promotions(name,code,promo_type,fixed_price) values('SVF Bundle','SVFB','bundle',60) returning id into pr;
 insert into promotion_store_prices(promotion_id,store_id,selling_price,available_at_store) values(pr,st,60,true);
 insert into promotion_choice_groups(promotion_id,label,item_kind,choose_qty) values(pr,'Pick a voucher','voucher',1) returning id into g;
 insert into promotion_choice_options(group_id,voucher_id) values(g,vlim);
 inv2:=create_invoice(st,c,null,jsonb_build_array(jsonb_build_object('kind','promotion','promotion_id',pr,'quantity',1,
   'selections',jsonb_build_array(jsonb_build_object('group_id',g,'options',jsonb_build_array(jsonb_build_object('voucher_id',vlim,'quantity',1)))))));
 select id into it2 from invoice_items where invoice_id=inv2;
 perform apply_line_foc(it2,null,null,'Event giveaway');
 perform confirm_foc_invoice(inv2,null);
 if (select count(*) from customer_reward_vouchers where source_id=it2 and source_type='invoice_promotion_voucher' and status='held') is distinct from 1 then
  raise exception 'Confirming a FOC promotion did not issue its voucher pick'; end if;
 if (select current_qty from voucher_store_stock where voucher_id=vlim and store_id=st) is distinct from 7 then
  raise exception 'The promotion''s voucher pick was not taken from stock once'; end if;

 -- Cancelling the FOC invoice takes the vouchers back and returns the stock.
 perform cancel_invoice_recorded(inv,'Giveaway undone',gen_random_uuid());
 if (select status from customer_reward_vouchers where source_id=it) is distinct from 'revoked' then
  raise exception 'Cancelling a FOC invoice left its vouchers held'; end if;
 if (select current_qty from voucher_store_stock where voucher_id=vlim and store_id=st) is distinct from 9 then
  raise exception 'Cancelling a FOC invoice did not return its voucher stock'; end if;

 raise notice 'PASS: vouchers and a promotion''s voucher pick given away on a FOC invoice are issued when it is confirmed, once, from the stock it takes; cancelling takes them back and returns the stock';
end $$;

-- ═════ 416: given free through Edit Invoice (a correction) ═════
-- The page sends every edit through correct_invoice, and offers FOC on a
-- voucher line and a promotion line. A correction that completes the invoice
-- as FOC issues the vouchers, so it takes their stock as Confirm FOC does:
-- once, with no invoice_voucher_movements row, so a cancel puts it back once.
do $$
declare o uuid:=gen_random_uuid(); s uuid:=gen_random_uuid(); st uuid; c uuid; vlim uuid; pr uuid; g uuid;
 inv uuid; it uuid; x jsonb; r jsonb; e text; n integer;
begin
 insert into auth.users(id,email) values(o,'sold-voucher-cfoc@tests.invalid'),(s,'sold-voucher-cfoc-s@tests.invalid');
 insert into profiles(id,full_name,email,role) values(o,'Owner','sold-voucher-cfoc@tests.invalid','owner'),
   (s,'Staff','sold-voucher-cfoc-s@tests.invalid','staff');
 perform set_config('request.jwt.claim.sub',o::text,true);
 insert into stores(name,code,country_code) values('Sold Voucher CFOC','SVC','SG') returning id into st;
 insert into user_store_assignments(user_id,store_id) values(s,st);
 insert into customers(full_name,phone) values('SVC Buyer','+61491572665') returning id into c;
 insert into vouchers(name,code,voucher_kind,selling_price,qty_type)
  values('Edit Giveaway','SVCL','normal',40,'limited') returning id into vlim;
 insert into voucher_store_stock(voucher_id,store_id,current_qty) values(vlim,st,10);
 insert into voucher_store_prices(voucher_id,store_id,selling_price,available_at_store) values(vlim,st,40,true);
 insert into promotions(name,code,promo_type,fixed_price) values('SVC Bundle','SVCB','bundle',60) returning id into pr;
 insert into promotion_store_prices(promotion_id,store_id,selling_price,available_at_store) values(pr,st,60,true);
 insert into promotion_choice_groups(promotion_id,label,item_kind,choose_qty) values(pr,'Pick a voucher','voucher',1) returning id into g;
 insert into promotion_choice_options(group_id,voucher_id) values(g,vlim);
 -- Staff, as on the page.
 perform set_config('request.jwt.claim.sub',s::text,true);

 -- C1 Two vouchers, made fully FOC in Edit Invoice: 10 → 8, two held, no
 -- movement row; the stock taken is audited.
 inv:=create_invoice_with_details(st,c,jsonb_build_array(jsonb_build_object('kind','voucher','voucher_id',vlim,'quantity',2)),
   jsonb_build_object('business_date',sg_today()::text));
 x:=(select jsonb_agg(jsonb_build_object('invoice_item_id',id,'kind','voucher','voucher_id',voucher_id,'quantity',quantity,
      'unit_price',unit_price,'foc_quantity',quantity,'foc_reason','Event giveaway')) from invoice_items where invoice_id=inv);
 r:=correct_invoice(inv,x,jsonb_build_object('expected_edit_count',0),'Given away',gen_random_uuid());
 if (select status from invoices where id=inv) is distinct from 'completed_foc' then
  raise exception 'C1 the correction did not complete the invoice as FOC: %', r; end if;
 if (select coalesce(sum(quantity),0) from customer_reward_vouchers where source_id in (select id from invoice_items where invoice_id=inv) and status='held') <> 2 then
  raise exception 'C1 the two free vouchers were not issued'; end if;
 if (select current_qty from voucher_store_stock where voucher_id=vlim and store_id=st) is distinct from 8 then
  raise exception 'C1 the two free vouchers were not taken from stock once (stock %)', (select current_qty from voucher_store_stock where voucher_id=vlim and store_id=st); end if;
 if exists(select 1 from invoice_voucher_movements where invoice_id=inv) then
  raise exception 'C1 a movement row was written, so a cancel would put the stock back twice'; end if;
 if not exists(select 1 from audit_logs where record_id=vlim and action='voucher_sold' and new_data->>'invoice_no'=(select invoice_no from invoices where id=inv)
                and (new_data->>'qty')::int=2 and (new_data->>'foc')::boolean and (new_data->>'correction')::boolean) then
  raise exception 'C1 the stock taken was not audited'; end if;
 -- A later edit of the FOC invoice takes nothing more (Owner: staff may not correct it).
 perform set_config('request.jwt.claim.sub',o::text,true);
 x:=(select jsonb_agg(jsonb_build_object('invoice_item_id',id,'kind','voucher','voucher_id',voucher_id,'quantity',quantity,
      'unit_price',unit_price,'foc_quantity',foc_quantity,'foc_reason',foc_reason)) from invoice_items where invoice_id=inv);
 perform correct_invoice(inv,x,jsonb_build_object('notes','Handed over at the event'),'Note added',gen_random_uuid());
 if (select current_qty from voucher_store_stock where voucher_id=vlim and store_id=st) is distinct from 8
    or (select coalesce(sum(quantity),0) from customer_reward_vouchers where source_id in (select id from invoice_items where invoice_id=inv) and status='held') <> 2 then
  raise exception 'C1 a later edit of the FOC invoice took stock or issued vouchers again'; end if;
 -- Cancelling it puts the stock back once: 8 → 10.
 perform cancel_invoice_recorded(inv,'Giveaway undone',gen_random_uuid());
 if (select current_qty from voucher_store_stock where voucher_id=vlim and store_id=st) is distinct from 10 then
  raise exception 'C1 cancelling did not put the stock back once (stock %)', (select current_qty from voucher_store_stock where voucher_id=vlim and store_id=st); end if;

 -- C2 A promotion with one voucher pick, made fully FOC in Edit Invoice: 10 → 9; cancel → 10.
 perform set_config('request.jwt.claim.sub',s::text,true);
 inv:=create_invoice_with_details(st,c,jsonb_build_array(jsonb_build_object('kind','promotion','promotion_id',pr,'quantity',1,
   'selections',jsonb_build_array(jsonb_build_object('group_id',g,'options',jsonb_build_array(jsonb_build_object('voucher_id',vlim,'quantity',1)))))),
   jsonb_build_object('business_date',sg_today()::text));
 x:=(select jsonb_agg(jsonb_build_object('invoice_item_id',id,'kind','promotion','promotion_id',promotion_id,'quantity',quantity,
      'unit_price',unit_price,'foc_quantity',quantity,'foc_reason','Event giveaway',
      'selections',jsonb_build_array(jsonb_build_object('group_id',g,'options',jsonb_build_array(jsonb_build_object('voucher_id',vlim,'quantity',1))))))
      from invoice_items where invoice_id=inv);
 perform correct_invoice(inv,x,jsonb_build_object('expected_edit_count',0),'Given away',gen_random_uuid());
 if (select status from invoices where id=inv) is distinct from 'completed_foc'
    or (select count(*) from customer_reward_vouchers where source_id in (select id from invoice_items where invoice_id=inv)
          and source_type='invoice_promotion_voucher' and status='held') <> 1 then
  raise exception 'C2 the promotion''s voucher pick was not issued'; end if;
 if (select current_qty from voucher_store_stock where voucher_id=vlim and store_id=st) is distinct from 9 then
  raise exception 'C2 the voucher pick was not taken from stock once (stock %)', (select current_qty from voucher_store_stock where voucher_id=vlim and store_id=st); end if;
 perform set_config('request.jwt.claim.sub',o::text,true);
 perform cancel_invoice_recorded(inv,'Giveaway undone',gen_random_uuid());
 if (select current_qty from voucher_store_stock where voucher_id=vlim and store_id=st) is distinct from 10 then
  raise exception 'C2 cancelling did not put the voucher pick''s stock back once'; end if;

 -- C3 Make FOC on both lines and then an edit of the note alone: the edit
 -- completes the invoice as FOC, so it takes the stock too (10 → 8).
 perform set_config('request.jwt.claim.sub',s::text,true);
 inv:=create_invoice_with_details(st,c,jsonb_build_array(jsonb_build_object('kind','voucher','voucher_id',vlim,'quantity',2)),
   jsonb_build_object('business_date',sg_today()::text));
 select id into it from invoice_items where invoice_id=inv;
 perform apply_line_foc(it,null,null,'Event giveaway');
 x:=(select jsonb_agg(jsonb_build_object('invoice_item_id',id,'kind','voucher','voucher_id',voucher_id,'quantity',quantity,
      'unit_price',unit_price,'foc_quantity',foc_quantity,'foc_reason',foc_reason)) from invoice_items where invoice_id=inv);
 perform correct_invoice(inv,x,jsonb_build_object('notes','For the raffle','expected_edit_count',(select edit_count from invoices where id=inv)),
   'Note added',gen_random_uuid());
 if (select status from invoices where id=inv) is distinct from 'completed_foc'
    or (select current_qty from voucher_store_stock where voucher_id=vlim and store_id=st) is distinct from 8
    or (select coalesce(sum(quantity),0) from customer_reward_vouchers where source_id=it and status='held') <> 2 then
  raise exception 'C3 an edit that completed a Make FOC invoice did not issue and take the two vouchers once (status %, stock %)',
    (select status from invoices where id=inv), (select current_qty from voucher_store_stock where voucher_id=vlim and store_id=st); end if;
 perform set_config('request.jwt.claim.sub',o::text,true);
 perform cancel_invoice_recorded(inv,'Giveaway undone',gen_random_uuid());
 if (select current_qty from voucher_store_stock where voucher_id=vlim and store_id=st) is distinct from 10 then
  raise exception 'C3 cancelling did not put the stock back once'; end if;

 -- C4 Not enough stock: the summary says so and the save is refused, as
 -- Confirm FOC refuses it. Nothing is issued or taken.
 update voucher_store_stock set current_qty=1 where voucher_id=vlim and store_id=st;
 perform set_config('request.jwt.claim.sub',s::text,true);
 inv:=create_invoice_with_details(st,c,jsonb_build_array(jsonb_build_object('kind','voucher','voucher_id',vlim,'quantity',2)),
   jsonb_build_object('business_date',sg_today()::text));
 x:=(select jsonb_agg(jsonb_build_object('invoice_item_id',id,'kind','voucher','voucher_id',voucher_id,'quantity',quantity,
      'unit_price',unit_price,'foc_quantity',quantity,'foc_reason','Event giveaway')) from invoice_items where invoice_id=inv);
 r:=preview_invoice_correction(inv,jsonb_build_object('items',x,'expected_edit_count',0));
 if not (r->>'blocking')::boolean or r->'outcome'->>'checked' <> 'false'
    or not r->'needs_review' @> '[{"area":"correction","detail":"Not enough stock of the voucher \"Edit Giveaway\" in this store to give it free: 1 left, 2 needed."}]' then
  raise exception 'C4 the summary did not say the stock is short: %', r; end if;
 begin
  perform correct_invoice(inv,x,jsonb_build_object('expected_edit_count',0),'Given away',gen_random_uuid());
 exception when others then e:=sqlerrm;
 end;
 if e is distinct from 'Not enough stock of the voucher "Edit Giveaway" in this store to give it free: 1 left, 2 needed.' then
  raise exception 'C4 a correction to FOC with too little stock was not refused: %', coalesce(e,'saved'); end if;
 if (select status from invoices where id=inv) is distinct from 'unpaid'
    or (select current_qty from voucher_store_stock where voucher_id=vlim and store_id=st) is distinct from 1
    or exists(select 1 from customer_reward_vouchers where source_id in (select id from invoice_items where invoice_id=inv)) then
  raise exception 'C4 the refused correction left something behind'; end if;

 raise notice 'PASS: a correction that completes an invoice as FOC (a voucher line, a promotion''s voucher pick, or Make FOC then any edit) issues the vouchers and takes their stock once; a later edit takes nothing more; cancelling puts the stock back once; too little stock is refused, and the summary says so';
end $$;

-- ═════ 416: the FOC taken off; a correction that makes it paid ═════
-- The Owner, 9 Oct 2026. Taking the FOC off a completed FOC invoice takes
-- back, in the same save, the vouchers it gave that are still unused and
-- returns their stock; used ones stay with the customer and are reported;
-- all of it is audited. When the invoice is paid, the vouchers taken back
-- are given again, from the stock the payment takes, once. A correction
-- that makes a part-paid voucher invoice paid takes the voucher stock as
-- Record Payment does (with an invoice_voucher_movements row), once.
do $$
declare o uuid:=gen_random_uuid(); st uuid; c uuid; pm uuid; vlim uuid; pr uuid; g uuid;
 inv uuid; it uuid; x jsonb; r jsonb; e text; used uuid; back uuid; pay uuid; s0 int;
begin
 insert into auth.users(id,email) values(o,'sold-voucher-unfoc@tests.invalid');
 insert into profiles(id,full_name,email,role) values(o,'Owner','sold-voucher-unfoc@tests.invalid','owner');
 perform set_config('request.jwt.claim.sub',o::text,true);
 insert into stores(name,code,country_code) values('Sold Voucher UNFOC','SVU','SG') returning id into st;
 insert into customers(full_name,phone) values('SVU Buyer','+61491570737') returning id into c;
 insert into payment_methods(name,is_active) values('SVU Cash',true) returning id into pm;
 insert into vouchers(name,code,voucher_kind,selling_price,qty_type)
  values('Unfoc Voucher','SVUL','normal',40,'limited') returning id into vlim;
 insert into voucher_store_stock(voucher_id,store_id,current_qty) values(vlim,st,10);
 insert into voucher_store_prices(voucher_id,store_id,selling_price,available_at_store) values(vlim,st,40,true);
 insert into promotions(name,code,promo_type,fixed_price) values('SVU Bundle','SVUB','bundle',60) returning id into pr;
 insert into promotion_store_prices(promotion_id,store_id,selling_price,available_at_store) values(pr,st,60,true);
 insert into promotion_choice_groups(promotion_id,label,item_kind,choose_qty) values(pr,'Pick a voucher','voucher',1) returning id into g;
 insert into promotion_choice_options(group_id,voucher_id) values(g,vlim);

 -- U1 Two vouchers on two lines, confirmed FOC (10 -> 8); the customer uses one.
 inv:=create_invoice_with_details(st,c,jsonb_build_array(jsonb_build_object('kind','voucher','voucher_id',vlim,'quantity',1),
   jsonb_build_object('kind','voucher','voucher_id',vlim,'quantity',1)),jsonb_build_object('business_date',sg_today()::text));
 for it in select id from invoice_items where invoice_id=inv order by id loop perform apply_line_foc(it,null,null,'Event giveaway'); end loop;
 perform confirm_foc_invoice(inv,null);
 select v.id into used from customer_reward_vouchers v join invoice_benefit_values b on b.reward_voucher_id=v.id where b.invoice_id=inv order by b.invoice_item_id limit 1;
 select v.id into back from customer_reward_vouchers v join invoice_benefit_values b on b.reward_voucher_id=v.id where b.invoice_id=inv and v.id<>used;
 -- A redemption as recorded on the voucher (fixture).
 update customer_reward_vouchers set status='redeemed', redeemed_at=now() where id=used;
 if (select current_qty from voucher_store_stock where voucher_id=vlim and store_id=st) is distinct from 8 then
  raise exception 'U1 fixture: Confirm FOC did not take the two vouchers'; end if;

 -- The summary says, before the save, what taking the FOC off does.
 x:=(select jsonb_agg(jsonb_build_object('invoice_item_id',id,'kind','voucher','voucher_id',voucher_id,'quantity',quantity,'unit_price',40,'foc_quantity',0) order by id)
      from invoice_items where invoice_id=inv);
 r:=preview_invoice_correction(inv,jsonb_build_object('items',x,'expected_edit_count',(select edit_count from invoices where id=inv)));
 if not r->'effects' @> jsonb_build_array(jsonb_build_object('area','vouchers','change','changed',
      'detail','Removing the FOC takes back the unused vouchers it gave (Unfoc Voucher × 1). They are given again as the corrected lines give them when the invoice is paid.',
      'items',jsonb_build_array(jsonb_build_object('kind','voucher','what','Unfoc Voucher × 1','why','used; it stays with the customer'))))
    or (r->>'blocking')::boolean
    or (select ef->>'detail' from jsonb_array_elements(r->'effects') ef where ef->>'area'='vouchers') like '%Used vouchers%' then
  raise exception 'U1 the summary did not say what taking the FOC off does: %', r->'effects'; end if;
 if (select current_qty from voucher_store_stock where voucher_id=vlim and store_id=st) is distinct from 8
    or (select status from customer_reward_vouchers where id=back) is distinct from 'held' then
  raise exception 'U1 the summary changed something'; end if;

 -- The save takes back the unused one and returns its stock (8 -> 9); the
 -- used one stays with the customer; the page is told both.
 r:=correct_invoice(inv,x,jsonb_build_object('expected_edit_count',(select edit_count from invoices where id=inv)),'Not a giveaway after all',gen_random_uuid());
 if r->'foc_vouchers' is distinct from '{"taken_back":["Unfoc Voucher × 1"],"kept_used":["Unfoc Voucher × 1"]}'::jsonb then
  raise exception 'U1 the save did not report the vouchers: %', r->'foc_vouchers'; end if;
 if (select status from invoices where id=inv) is distinct from 'unpaid'
    or (select current_qty from voucher_store_stock where voucher_id=vlim and store_id=st) is distinct from 9
    or (select status from customer_reward_vouchers where id=back) is distinct from 'revoked'
    or (select status from customer_reward_vouchers where id=used) is distinct from 'redeemed'
    or (select cancelled_unused_value from invoice_benefit_values where reward_voucher_id=back) is distinct from 1.00 then
  raise exception 'U1 taking the FOC off did not take back the unused voucher once (status %, stock %)',
    (select status from invoices where id=inv), (select current_qty from voucher_store_stock where voucher_id=vlim and store_id=st); end if;
 -- The used voucher's unit stays out: recorded against the invoice now, so a payment does not take it again.
 if (select coalesce(sum(quantity),0) from invoice_voucher_movements where invoice_id=inv) <> 1 then
  raise exception 'U1 the used voucher is not recorded as out (movement rows %)', (select coalesce(sum(quantity),0) from invoice_voucher_movements where invoice_id=inv); end if;
 if not exists(select 1 from audit_logs where record_id=back and action='foc_removed_voucher_taken_back'
                and (new_data->>'stock_returned')::int=1)
    or not exists(select 1 from audit_logs where record_id=inv and action='foc_removed_vouchers'
                and new_data->'taken_back'='["Unfoc Voucher × 1"]' and new_data->'kept_used'='["Unfoc Voucher × 1"]') then
  raise exception 'U1 taking the FOC off was not audited'; end if;
 -- U2 Paid in full: the voucher taken back is given again from the stock
 -- the payment takes (9 -> 8), once; the used one is not given again.
 perform pay_invoice(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',80)));
 if (select status from invoices where id=inv) is distinct from 'paid'
    or (select current_qty from voucher_store_stock where voucher_id=vlim and store_id=st) is distinct from 8
    or (select coalesce(sum(quantity),0) from invoice_voucher_movements where invoice_id=inv) <> 2 then
  raise exception 'U2 the payment did not take the stock of the voucher given again once (stock %)',
    (select current_qty from voucher_store_stock where voucher_id=vlim and store_id=st); end if;
 if (select count(*) from customer_reward_vouchers v join invoice_benefit_values b on b.reward_voucher_id=v.id
      where b.invoice_id=inv and v.status='held' and v.source_type='invoice_reopen' and v.quantity=1 and v.customer_id=c and b.paid_value=40) <> 1
    or (select count(*) from customer_reward_vouchers v join invoice_benefit_values b on b.reward_voucher_id=v.id
      where b.invoice_id=inv and v.status='held') <> 1
    or not exists(select 1 from invoice_reopen_vouchers q where q.invoice_id=inv and q.applied_at is not null and q.replacement_voucher_id is not null
                   and q.benefit_id=(select id from invoice_benefit_values where reward_voucher_id=back))
    or (select cancelled_unused_value from invoice_benefit_values where reward_voucher_id=back) is distinct from 0.00 then
  raise exception 'U2 the voucher taken back was not given again once, worth what the line now charges'; end if;
 if issue_sold_vouchers_for_invoice(inv) <> 0 then raise exception 'U2 issuing again gave more vouchers'; end if;

 -- U3 A promotion's voucher pick made FOC in Edit Invoice (8 -> 7), the FOC
 -- taken off again with nothing used (7 -> 8), then paid (8 -> 7).
 inv:=create_invoice_with_details(st,c,jsonb_build_array(jsonb_build_object('kind','promotion','promotion_id',pr,'quantity',1,
   'selections',jsonb_build_array(jsonb_build_object('group_id',g,'options',jsonb_build_array(jsonb_build_object('voucher_id',vlim,'quantity',1)))))),
   jsonb_build_object('business_date',sg_today()::text));
 x:=(select jsonb_agg(jsonb_build_object('invoice_item_id',id,'kind','promotion','promotion_id',promotion_id,'quantity',quantity,
      'unit_price',unit_price,'foc_quantity',quantity,'foc_reason','Event giveaway',
      'selections',jsonb_build_array(jsonb_build_object('group_id',g,'options',jsonb_build_array(jsonb_build_object('voucher_id',vlim,'quantity',1))))))
      from invoice_items where invoice_id=inv);
 perform correct_invoice(inv,x,jsonb_build_object('expected_edit_count',0),'Given away',gen_random_uuid());
 if (select current_qty from voucher_store_stock where voucher_id=vlim and store_id=st) is distinct from 7 then
  raise exception 'U3 fixture: the FOC pick was not taken'; end if;
 x:=(select jsonb_agg(jsonb_build_object('invoice_item_id',id,'kind','promotion','promotion_id',promotion_id,'quantity',quantity,
      'unit_price',60,'foc_quantity',0,
      'selections',jsonb_build_array(jsonb_build_object('group_id',g,'options',jsonb_build_array(jsonb_build_object('voucher_id',vlim,'quantity',1))))))
      from invoice_items where invoice_id=inv);
 r:=correct_invoice(inv,x,jsonb_build_object('expected_edit_count',(select edit_count from invoices where id=inv)),'Not a giveaway',gen_random_uuid());
 if r->'foc_vouchers' is distinct from '{"taken_back":["Unfoc Voucher × 1"],"kept_used":[]}'::jsonb
    or (select status from invoices where id=inv) is distinct from 'unpaid'
    or (select current_qty from voucher_store_stock where voucher_id=vlim and store_id=st) is distinct from 8
    or exists(select 1 from customer_reward_vouchers v join invoice_benefit_values b on b.reward_voucher_id=v.id where b.invoice_id=inv and v.status='held')
    or (select coalesce(sum(quantity),0) from invoice_voucher_movements where invoice_id=inv) <> 0 then
  raise exception 'U3 taking the FOC off a promotion''s voucher pick did not take it back once: %', r->'foc_vouchers'; end if;
 perform pay_invoice(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',60)));
 if (select current_qty from voucher_store_stock where voucher_id=vlim and store_id=st) is distinct from 7
    or (select count(*) from customer_reward_vouchers v join invoice_benefit_values b on b.reward_voucher_id=v.id
         where b.invoice_id=inv and v.status='held' and v.source_type='invoice_reopen' and b.paid_value=60) <> 1 then
  raise exception 'U3 the paid promotion did not give its pick again once (stock %)', (select current_qty from voucher_store_stock where voucher_id=vlim and store_id=st); end if;

 -- U4 Taken off and then cancelled while still unpaid: nothing is held and
 -- no movement row was written, so the stock is as it was (7 -> 5 -> 7 -> 7).
 inv:=create_invoice_with_details(st,c,jsonb_build_array(jsonb_build_object('kind','voucher','voucher_id',vlim,'quantity',2)),
   jsonb_build_object('business_date',sg_today()::text));
 select id into it from invoice_items where invoice_id=inv;
 perform apply_line_foc(it,null,null,'Event giveaway');
 perform confirm_foc_invoice(inv,null);
 x:=(select jsonb_agg(jsonb_build_object('invoice_item_id',id,'kind','voucher','voucher_id',voucher_id,'quantity',quantity,'unit_price',40,'foc_quantity',0))
      from invoice_items where invoice_id=inv);
 perform correct_invoice(inv,x,jsonb_build_object('expected_edit_count',(select edit_count from invoices where id=inv)),'Not a giveaway',gen_random_uuid());
 if (select current_qty from voucher_store_stock where voucher_id=vlim and store_id=st) is distinct from 7 then
  raise exception 'U4 taking the FOC off did not return both vouchers'; end if;
 perform cancel_invoice_recorded(inv,'Not wanted',gen_random_uuid());
 if (select current_qty from voucher_store_stock where voucher_id=vlim and store_id=st) is distinct from 7 then
  raise exception 'U4 cancelling after the FOC came off moved the stock again (stock %)', (select current_qty from voucher_store_stock where voucher_id=vlim and store_id=st); end if;

 -- U5 Rule 13: a correction that makes a part-paid voucher invoice paid
 -- takes the voucher stock as Record Payment does, with a movement row
 -- (7 -> 5), and issues the vouchers; a later edit takes nothing more.
 inv:=create_invoice_with_details(st,c,jsonb_build_array(jsonb_build_object('kind','voucher','voucher_id',vlim,'quantity',2)),
   jsonb_build_object('business_date',sg_today()::text));
 perform pay_invoice(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',40)));
 x:=(select jsonb_agg(jsonb_build_object('invoice_item_id',id,'kind','voucher','voucher_id',voucher_id,'quantity',quantity,'unit_price',40))
      from invoice_items where invoice_id=inv);
 perform correct_invoice(inv,x,jsonb_build_object('manual_discount',40,'manual_discount_reason','Loyalty'),'Discount agreed',gen_random_uuid());
 if (select status from invoices where id=inv) is distinct from 'paid'
    or (select current_qty from voucher_store_stock where voucher_id=vlim and store_id=st) is distinct from 5
    or (select coalesce(sum(quantity),0) from invoice_voucher_movements where invoice_id=inv and reason like 'Invoice correction settled it: %') <> 2
    or (select coalesce(sum(v.quantity),0) from customer_reward_vouchers v join invoice_benefit_values b on b.reward_voucher_id=v.id
         where b.invoice_id=inv and v.status='held') <> 2 then
  raise exception 'U5 a correction that made the invoice paid did not take the voucher stock once (stock %)',
    (select current_qty from voucher_store_stock where voucher_id=vlim and store_id=st); end if;
 perform correct_invoice(inv,x,jsonb_build_object('notes','Called the customer'),'Note added',gen_random_uuid());
 if (select current_qty from voucher_store_stock where voucher_id=vlim and store_id=st) is distinct from 5
    or (select coalesce(sum(quantity),0) from invoice_voucher_movements where invoice_id=inv) <> 2 then
  raise exception 'U5 a later edit took the voucher stock again'; end if;

 -- U6 Too little stock: the summary says so and the save is refused, as a
 -- payment is; nothing is issued or taken.
 update voucher_store_stock set current_qty=1 where voucher_id=vlim and store_id=st;
 inv:=create_invoice_with_details(st,c,jsonb_build_array(jsonb_build_object('kind','voucher','voucher_id',vlim,'quantity',2)),
   jsonb_build_object('business_date',sg_today()::text));
 perform pay_invoice(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',40)));
 x:=(select jsonb_agg(jsonb_build_object('invoice_item_id',id,'kind','voucher','voucher_id',voucher_id,'quantity',quantity,'unit_price',40))
      from invoice_items where invoice_id=inv);
 r:=preview_invoice_correction(inv,jsonb_build_object('items',x,'manual_discount',40,'manual_discount_reason','Loyalty'));
 if not (r->>'blocking')::boolean or r->'outcome'->>'checked' <> 'false'
    or not r->'needs_review' @> '[{"area":"correction","detail":"Not enough stock of the voucher \"Unfoc Voucher\" in this store: 1 left, 2 needed."}]' then
  raise exception 'U6 the summary did not say the stock is short: %', r; end if;
 e:=null;
 begin
  perform correct_invoice(inv,x,jsonb_build_object('manual_discount',40,'manual_discount_reason','Loyalty'),'Discount agreed',gen_random_uuid());
 exception when others then e:=sqlerrm;
 end;
 if e is distinct from 'Not enough stock of the voucher "Unfoc Voucher" in this store: 1 left, 2 needed.' then
  raise exception 'U6 a correction to paid with too little stock was not refused: %', coalesce(e,'saved'); end if;
 if (select status from invoices where id=inv) is distinct from 'partially_paid'
    or (select current_qty from voucher_store_stock where voucher_id=vlim and store_id=st) is distinct from 1
    or exists(select 1 from customer_reward_vouchers v join invoice_benefit_values b on b.reward_voucher_id=v.id where b.invoice_id=inv) then
  raise exception 'U6 the refused correction left something behind'; end if;

 raise notice 'PASS: taking the FOC off a completed FOC invoice takes back its unused vouchers and returns their stock in the same save, leaves used ones with the customer, reports and audits both; paying it then gives them again from the stock the payment takes, once; cancelling it unpaid moves nothing more; a correction that makes a part-paid voucher invoice paid takes the voucher stock once, as Record Payment does, and too little stock is refused and shown in the summary';
end $$;

-- ═════ 416: the FOC taken off in a save that also changes the lines ═════
-- The vouchers given again at payment are what the corrected lines give,
-- less what is still out: a quantity raised or lowered, a voucher or a pick
-- swapped. Stock is taken once, whether the save also changes products or
-- the invoice stays FOC. A voucher moved to another customer stays with
-- them. A line that gave vouchers cannot be removed. The 'invoice_reopen'
-- vouchers of a reopened FOC invoice are taken back, and a therapy voucher
-- with a session used stays.
do $$
declare o uuid:=gen_random_uuid(); st uuid; c uuid; c2 uuid; pm uuid; vlim uuid; vun uuid; va uuid; vb uuid; vt uuid;
 svc uuid; p uuid; pr uuid; g uuid; inv uuid; it uuid; x jsonb; r jsonb; e text; mode text; v uuid; tvi uuid; n int;
begin
 insert into auth.users(id,email) values(o,'sold-voucher-lines@tests.invalid');
 insert into profiles(id,full_name,email,role) values(o,'Owner','sold-voucher-lines@tests.invalid','owner');
 perform set_config('request.jwt.claim.sub',o::text,true);
 insert into stores(name,code,country_code) values('Sold Voucher Lines','SVW','SG') returning id into st;
 insert into customers(full_name,phone) values('SVW Buyer','+61491572983') returning id into c;
 insert into customers(full_name,phone) values('SVW Friend','+61491573770') returning id into c2;
 insert into payment_methods(name,is_active) values('SVW Cash',true) returning id into pm;
 insert into vouchers(name,code,voucher_kind,selling_price,qty_type) values('Lines Limited','SVWL','normal',40,'limited') returning id into vlim;
 insert into vouchers(name,code,voucher_kind,selling_price,qty_type) values('Lines Unlimited','SVWU','normal',40,'unlimited') returning id into vun;
 insert into vouchers(name,code,voucher_kind,selling_price,qty_type) values('Pick A','SVWA','normal',40,'limited') returning id into va;
 insert into vouchers(name,code,voucher_kind,selling_price,qty_type) values('Pick B','SVWB','normal',40,'limited') returning id into vb;
 insert into voucher_store_stock(voucher_id,store_id,current_qty) values(vlim,st,10),(va,st,10),(vb,st,10);
 insert into voucher_store_prices(voucher_id,store_id,selling_price,available_at_store)
  values(vlim,st,40,true),(vun,st,40,true),(va,st,40,true),(vb,st,40,true);
 insert into promotions(name,code,promo_type,fixed_price) values('SVW Bundle','SVWP','bundle',60) returning id into pr;
 insert into promotion_store_prices(promotion_id,store_id,selling_price,available_at_store) values(pr,st,60,true);
 insert into promotion_choice_groups(promotion_id,label,item_kind,choose_qty) values(pr,'Pick a voucher','voucher',1) returning id into g;
 insert into promotion_choice_options(group_id,voucher_id) values(g,va),(g,vb);
 insert into products(name,sku,product_type) values('SVW Socks','SVWS','own') returning id into p;
 insert into store_inventory(store_id,product_id,current_qty) values(st,p,50);
 perform set_product_prices(st,p,100,100,'available');

 -- W1-W3 The quantity changed in the save that takes the FOC off. Paid, the
 -- customer holds what the corrected line sells, worth what it charges.
 foreach mode in array array['limited 2->3','limited 2->1','unlimited 2->3'] loop
  v := case when mode like 'limited%' then vlim else vun end;
  update voucher_store_stock set current_qty=10 where voucher_id=vlim and store_id=st;
  inv:=create_invoice_with_details(st,c,jsonb_build_array(jsonb_build_object('kind','voucher','voucher_id',v,'quantity',2)),
    jsonb_build_object('business_date',sg_today()::text));
  select id into it from invoice_items where invoice_id=inv;
  perform apply_line_foc(it,null,null,'Event giveaway');
  perform confirm_foc_invoice(inv,null);
  n := case when mode like '%2->3' then 3 else 1 end;
  x:=jsonb_build_array(jsonb_build_object('invoice_item_id',it,'kind','voucher','voucher_id',v,'quantity',n,'unit_price',40,'foc_quantity',0));
  r:=preview_invoice_correction(inv,jsonb_build_object('items',x,'expected_edit_count',(select edit_count from invoices where id=inv)));
  if not r->'effects' @> jsonb_build_array(jsonb_build_object('area','vouchers',
       'detail',format('Removing the FOC takes back the unused vouchers it gave (%s × 2). They are given again as the corrected lines give them when the invoice is paid.',
                       (select name from vouchers where id=v)))) then
   raise exception 'W [%] the summary did not say the vouchers come back as the corrected lines give them: %', mode, r->'effects'; end if;
  perform correct_invoice(inv,x,jsonb_build_object('expected_edit_count',(select edit_count from invoices where id=inv)),'Sold after all',gen_random_uuid());
  if (select current_qty from voucher_store_stock where voucher_id=vlim and store_id=st) is distinct from 10 then
   raise exception 'W [%] taking the FOC off did not put the stock back', mode; end if;
  perform pay_invoice(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',40*n)));
  if (select coalesce(sum(cv.quantity),0) from customer_reward_vouchers cv join invoice_benefit_values b on b.reward_voucher_id=cv.id
       where b.invoice_id=inv and cv.status='held' and cv.voucher_id=v) <> n
     or (select coalesce(sum(b.paid_value),0) from customer_reward_vouchers cv join invoice_benefit_values b on b.reward_voucher_id=cv.id
       where b.invoice_id=inv and cv.status='held') <> 40*n
     or (mode like 'limited%' and (select current_qty from voucher_store_stock where voucher_id=vlim and store_id=st) is distinct from 10-n) then
   raise exception 'W [%] paid: the customer does not hold what the corrected line sells (held %, paid values %, stock %)', mode,
     (select coalesce(sum(cv.quantity),0) from customer_reward_vouchers cv join invoice_benefit_values b on b.reward_voucher_id=cv.id where b.invoice_id=inv and cv.status='held'),
     (select string_agg(b.paid_value::text,',') from customer_reward_vouchers cv join invoice_benefit_values b on b.reward_voucher_id=cv.id where b.invoice_id=inv and cv.status='held'),
     (select current_qty from voucher_store_stock where voucher_id=vlim and store_id=st); end if;
  if exists(select 1 from invoice_benefit_values where invoice_id=inv and cancelled_unused_value>0) then
   raise exception 'W [%] a voucher taken back is still waiting to be given again', mode; end if;
  if issue_sold_vouchers_for_invoice(inv) <> 0 then raise exception 'W [%] issuing again gave more', mode; end if;
 end loop;

 -- W4 The promotion's pick swapped from A to B: B is given, A is not; A's
 -- stock is back and B's is taken once.
 inv:=create_invoice_with_details(st,c,jsonb_build_array(jsonb_build_object('kind','promotion','promotion_id',pr,'quantity',1,
   'selections',jsonb_build_array(jsonb_build_object('group_id',g,'options',jsonb_build_array(jsonb_build_object('voucher_id',va,'quantity',1)))))),
   jsonb_build_object('business_date',sg_today()::text));
 perform apply_line_foc((select id from invoice_items where invoice_id=inv),null,null,'Event giveaway');
 perform confirm_foc_invoice(inv,null);
 x:=(select jsonb_agg(jsonb_build_object('invoice_item_id',id,'kind','promotion','promotion_id',promotion_id,'quantity',1,'unit_price',60,'foc_quantity',0,
      'selections',jsonb_build_array(jsonb_build_object('group_id',g,'options',jsonb_build_array(jsonb_build_object('voucher_id',vb,'quantity',1))))))
      from invoice_items where invoice_id=inv);
 perform correct_invoice(inv,x,jsonb_build_object('expected_edit_count',(select edit_count from invoices where id=inv)),'Sold, and B not A',gen_random_uuid());
 perform pay_invoice(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',60)));
 if (select current_qty from voucher_store_stock where voucher_id=va and store_id=st) is distinct from 10
    or (select current_qty from voucher_store_stock where voucher_id=vb and store_id=st) is distinct from 9
    or (select string_agg(vo.name||' x'||cv.quantity||' '||b.paid_value, ', ') from customer_reward_vouchers cv join vouchers vo on vo.id=cv.voucher_id
         join invoice_benefit_values b on b.reward_voucher_id=cv.id where b.invoice_id=inv and cv.status='held') is distinct from 'Pick B x1 60.00' then
  raise exception 'W4 the swapped pick was not given as the corrected line gives it (A %, B %, held %)',
    (select current_qty from voucher_store_stock where voucher_id=va and store_id=st),(select current_qty from voucher_store_stock where voucher_id=vb and store_id=st),
    (select string_agg(vo.name||' x'||cv.quantity||' '||b.paid_value, ', ') from customer_reward_vouchers cv join vouchers vo on vo.id=cv.voucher_id
      join invoice_benefit_values b on b.reward_voucher_id=cv.id where b.invoice_id=inv and cv.status='held'); end if;

 -- W5 A voucher line's voucher swapped from A to B on the same line: B x2
 -- is given as the line's sale, A is not.
 update voucher_store_stock set current_qty=10 where store_id=st and voucher_id in (va,vb);
 inv:=create_invoice_with_details(st,c,jsonb_build_array(jsonb_build_object('kind','voucher','voucher_id',va,'quantity',2)),
   jsonb_build_object('business_date',sg_today()::text));
 select id into it from invoice_items where invoice_id=inv;
 perform apply_line_foc(it,null,null,'Event giveaway');
 perform confirm_foc_invoice(inv,null);
 x:=jsonb_build_array(jsonb_build_object('invoice_item_id',it,'kind','voucher','voucher_id',vb,'quantity',2,'unit_price',40,'foc_quantity',0));
 perform correct_invoice(inv,x,jsonb_build_object('expected_edit_count',(select edit_count from invoices where id=inv)),'Sold, and B not A',gen_random_uuid());
 perform pay_invoice(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',80)));
 if (select current_qty from voucher_store_stock where voucher_id=va and store_id=st) is distinct from 10
    or (select current_qty from voucher_store_stock where voucher_id=vb and store_id=st) is distinct from 8
    or (select string_agg(vo.name||' x'||cv.quantity||' '||b.paid_value, ', ') from customer_reward_vouchers cv join vouchers vo on vo.id=cv.voucher_id
         join invoice_benefit_values b on b.reward_voucher_id=cv.id where b.invoice_id=inv and cv.status='held') is distinct from 'Pick B x2 80.00' then
  raise exception 'W5 the swapped voucher was not given as the corrected line gives it (A %, B %, held %)',
    (select current_qty from voucher_store_stock where voucher_id=va and store_id=st),(select current_qty from voucher_store_stock where voucher_id=vb and store_id=st),
    (select string_agg(vo.name||' x'||cv.quantity||' '||b.paid_value, ', ') from customer_reward_vouchers cv join vouchers vo on vo.id=cv.voucher_id
      join invoice_benefit_values b on b.reward_voucher_id=cv.id where b.invoice_id=inv and cv.status='held'); end if;

 -- W6-W9 A completed FOC invoice with socks and two vouchers, corrected with
 -- more socks: the voucher stock Confirm FOC took is not taken again.
 foreach mode in array array['FOC off','stays FOC','last units','FOC off, vouchers 2->3'] loop
  update voucher_store_stock set current_qty=case when mode='last units' then 2 else 10 end where voucher_id=vlim and store_id=st;
  inv:=create_invoice_with_details(st,c,jsonb_build_array(jsonb_build_object('kind','product','product_id',p,'quantity',1),
     jsonb_build_object('kind','voucher','voucher_id',vlim,'quantity',2)),jsonb_build_object('business_date',sg_today()::text));
  for it in select id from invoice_items where invoice_id=inv loop perform apply_line_foc(it,null,null,'Event giveaway'); end loop;
  perform confirm_foc_invoice(inv,null);
  x:=(select jsonb_agg(jsonb_build_object('invoice_item_id',id,'kind',line_kind,'product_id',product_id,'voucher_id',voucher_id,
       'quantity',case when line_kind='product' then 2 when mode like '%2->3' then 3 else quantity end,'unit_price',unit_price,
       'foc_quantity',case when mode in ('stays FOC','last units') then case when line_kind='product' then 2 else quantity end else 0 end,
       'foc_reason',case when mode in ('stays FOC','last units') then 'Event giveaway' end) order by id)
       from invoice_items where invoice_id=inv);
  e:=null;
  begin
   r:=preview_invoice_correction(inv,jsonb_build_object('items',x,'expected_edit_count',(select edit_count from invoices where id=inv)));
   if (r->'outcome'->>'checked')::boolean is not true then
    raise exception 'W [%] the summary refused the save: %', mode, r->'outcome'; end if;
   perform correct_invoice(inv,x,jsonb_build_object('expected_edit_count',(select edit_count from invoices where id=inv)),'Two socks',gen_random_uuid());
  exception when others then e:=sqlerrm;
  end;
  if e is not null then raise exception 'W [%] the correction was refused: %', mode, e; end if;
  if mode in ('stays FOC','last units') then
   if (select status from invoices where id=inv) is distinct from 'completed_foc'
      or (select current_qty from voucher_store_stock where voucher_id=vlim and store_id=st) is distinct from (case when mode='last units' then 0 else 8 end)
      or (select coalesce(sum(quantity),0) from invoice_voucher_movements where invoice_id=inv) <> 0 then
    raise exception 'W [%] the voucher stock was taken again or a movement row kept (stock %, rows %)', mode,
      (select current_qty from voucher_store_stock where voucher_id=vlim and store_id=st),
      (select coalesce(sum(quantity),0) from invoice_voucher_movements where invoice_id=inv); end if;
   -- Cancelling it puts the stock back once.
   perform cancel_invoice_recorded(inv,'Giveaway undone',gen_random_uuid());
   if (select current_qty from voucher_store_stock where voucher_id=vlim and store_id=st) is distinct from (case when mode='last units' then 2 else 10 end) then
    raise exception 'W [%] cancelling did not put the stock back once (stock %)', mode, (select current_qty from voucher_store_stock where voucher_id=vlim and store_id=st); end if;
  else
   n := case when mode like '%2->3' then 3 else 2 end;
   -- 457 (the Owner, 22 Oct 2026): a save that leaves the invoice unpaid
   -- keeps no voucher stock for its lines (no voucher is given until it is
   -- paid; the payment takes them), so once the FOC is off the stock is back
   -- at 10 whatever the line now asks. Before 457 the save took a raised
   -- line's extra unit at once (12-n), out with no voucher until payment. The
   -- payment below ends the same either way. 457's correct_invoice is known
   -- by the wording of the row it writes.
   if (select current_qty from voucher_store_stock where voucher_id=vlim and store_id=st) is distinct from
      (case when position('Not paid in full, nothing given yet' in pg_get_functiondef('public.correct_invoice(uuid,jsonb,jsonb,text,uuid)'::regprocedure)) > 0
            then 10 else 12-n end) then
    raise exception 'W [%] after the save the voucher stock is % (expected %)', mode,
      (select current_qty from voucher_store_stock where voucher_id=vlim and store_id=st),
      (case when position('Not paid in full, nothing given yet' in pg_get_functiondef('public.correct_invoice(uuid,jsonb,jsonb,text,uuid)'::regprocedure)) > 0
            then 10 else 12-n end); end if;
   perform pay_invoice(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',(select total_amount from invoices where id=inv))));
   if (select current_qty from voucher_store_stock where voucher_id=vlim and store_id=st) is distinct from 10-n
      or (select coalesce(sum(quantity),0) from invoice_voucher_movements where invoice_id=inv) <> n
      or (select coalesce(sum(cv.quantity),0) from customer_reward_vouchers cv join invoice_benefit_values b on b.reward_voucher_id=cv.id
           where b.invoice_id=inv and cv.status='held') <> n then
    raise exception 'W [%] paid: voucher stock % (expected %), rows %, held %', mode,
      (select current_qty from voucher_store_stock where voucher_id=vlim and store_id=st), 10-n,
      (select coalesce(sum(quantity),0) from invoice_voucher_movements where invoice_id=inv),
      (select coalesce(sum(cv.quantity),0) from customer_reward_vouchers cv join invoice_benefit_values b on b.reward_voucher_id=cv.id
        where b.invoice_id=inv and cv.status='held'); end if;
  end if;
 end loop;

 -- W10 One of two vouchers moved to a friend, then the FOC taken off: the
 -- friend keeps it, it is reported, and the payment takes only the other.
 update voucher_store_stock set current_qty=10 where voucher_id=vlim and store_id=st;
 inv:=create_invoice_with_details(st,c,jsonb_build_array(jsonb_build_object('kind','voucher','voucher_id',vlim,'quantity',1),
   jsonb_build_object('kind','voucher','voucher_id',vlim,'quantity',1)),jsonb_build_object('business_date',sg_today()::text));
 for it in select id from invoice_items where invoice_id=inv order by id loop perform apply_line_foc(it,null,null,'Event giveaway'); end loop;
 perform confirm_foc_invoice(inv,null);
 perform transfer_invoice_unused_benefit((select b.id from invoice_benefit_values b where b.invoice_id=inv order by b.invoice_item_id limit 1),
   c2,st,'Given to her friend',gen_random_uuid());
 x:=(select jsonb_agg(jsonb_build_object('invoice_item_id',id,'kind','voucher','voucher_id',voucher_id,'quantity',quantity,'unit_price',40,'foc_quantity',0) order by id)
      from invoice_items where invoice_id=inv);
 r:=preview_invoice_correction(inv,jsonb_build_object('items',x,'expected_edit_count',(select edit_count from invoices where id=inv)));
 if not r->'effects' @> '[{"area":"vouchers","items":[{"kind":"voucher","what":"Lines Limited × 1","why":"moved to another customer; it stays with them"}]}]' then
  raise exception 'W10 the summary did not list the voucher moved to a friend: %', r->'effects'; end if;
 r:=correct_invoice(inv,x,jsonb_build_object('expected_edit_count',(select edit_count from invoices where id=inv)),'Not a giveaway',gen_random_uuid());
 if r->'foc_vouchers' is distinct from '{"taken_back":["Lines Limited × 1"],"kept_used":["Lines Limited × 1 — moved to another customer; it stays with them"]}'::jsonb
    or (select current_qty from voucher_store_stock where voucher_id=vlim and store_id=st) is distinct from 9
    or (select status from customer_reward_vouchers where customer_id=c2) is distinct from 'held' then
  raise exception 'W10 taking the FOC off did not leave the moved voucher with the friend: %', r->'foc_vouchers'; end if;
 perform pay_invoice(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',80)));
 if (select current_qty from voucher_store_stock where voucher_id=vlim and store_id=st) is distinct from 8
    or (select coalesce(sum(quantity),0) from customer_reward_vouchers where customer_id=c2 and status='held') <> 1
    or (select coalesce(sum(cv.quantity),0) from customer_reward_vouchers cv join invoice_benefit_values b on b.reward_voucher_id=cv.id
         where b.invoice_id=inv and cv.status='held' and cv.customer_id=c) <> 1 then
  raise exception 'W10 paid: stock % (expected 8), friend %, buyer %', (select current_qty from voucher_store_stock where voucher_id=vlim and store_id=st),
    (select coalesce(sum(quantity),0) from customer_reward_vouchers where customer_id=c2 and status='held'),
    (select coalesce(sum(cv.quantity),0) from customer_reward_vouchers cv join invoice_benefit_values b on b.reward_voucher_id=cv.id
      where b.invoice_id=inv and cv.status='held' and cv.customer_id=c); end if;

 -- W11 The FOC taken off and the voucher line removed: refused in plain
 -- words, in the summary and in the save; nothing changes.
 update voucher_store_stock set current_qty=10 where voucher_id=vlim and store_id=st;
 inv:=create_invoice_with_details(st,c,jsonb_build_array(jsonb_build_object('kind','voucher','voucher_id',vlim,'quantity',2),
    jsonb_build_object('kind','product','product_id',p,'quantity',1)),jsonb_build_object('business_date',sg_today()::text));
 for it in select id from invoice_items where invoice_id=inv loop perform apply_line_foc(it,null,null,'Event giveaway'); end loop;
 perform confirm_foc_invoice(inv,null);
 x:=(select jsonb_agg(jsonb_build_object('invoice_item_id',id,'kind','product','product_id',product_id,'quantity',1,'unit_price',100,'foc_quantity',0))
      from invoice_items where invoice_id=inv and line_kind='product');
 r:=preview_invoice_correction(inv,jsonb_build_object('items',x,'expected_edit_count',(select edit_count from invoices where id=inv)));
 if r->'outcome'->>'refusal' is distinct from 'A line you removed gave vouchers to the customer. Keep the line, or take the vouchers back with Refund / Cancel.' then
  raise exception 'W11 the summary did not give the plain refusal: %', r->'outcome'; end if;
 e:=null;
 begin
  perform correct_invoice(inv,x,jsonb_build_object('expected_edit_count',(select edit_count from invoices where id=inv)),'Sold the socks; no vouchers',gen_random_uuid());
 exception when others then e:=sqlerrm;
 end;
 if e is distinct from 'A line you removed gave vouchers to the customer. Keep the line, or take the vouchers back with Refund / Cancel.'
    or (select status from invoices where id=inv) is distinct from 'completed_foc'
    or (select current_qty from voucher_store_stock where voucher_id=vlim and store_id=st) is distinct from 8 then
  raise exception 'W11 removing a line that gave vouchers was not refused in plain words: %', coalesce(e,'saved'); end if;

 -- W12 FOC, cancelled, reopened (its vouchers come back as 'invoice_reopen'
 -- replacements), then the FOC taken off: those are taken back and their
 -- stock returned.
 inv:=create_invoice_with_details(st,c,jsonb_build_array(jsonb_build_object('kind','voucher','voucher_id',vlim,'quantity',2)),
   jsonb_build_object('business_date',sg_today()::text));
 select id into it from invoice_items where invoice_id=inv;
 perform apply_line_foc(it,null,null,'Event giveaway');
 perform confirm_foc_invoice(inv,null);
 perform cancel_invoice_recorded(inv,'Mistake',gen_random_uuid());
 perform reopen_invoice(inv,'Customer came back',gen_random_uuid());
 if (select count(*) from customer_reward_vouchers cv join invoice_benefit_values b on b.reward_voucher_id=cv.id
      where b.invoice_id=inv and cv.status='held' and cv.source_type='invoice_reopen') <> 1 then
  raise exception 'W12 fixture: the reopening did not give the vouchers again as invoice_reopen'; end if;
 n := (select current_qty from voucher_store_stock where voucher_id=vlim and store_id=st);
 x:=jsonb_build_array(jsonb_build_object('invoice_item_id',it,'kind','voucher','voucher_id',vlim,'quantity',2,'unit_price',40,'foc_quantity',0));
 r:=correct_invoice(inv,x,jsonb_build_object('expected_edit_count',(select edit_count from invoices where id=inv)),'Not a giveaway',gen_random_uuid());
 if r->'foc_vouchers' is distinct from '{"taken_back":["Lines Limited × 2"],"kept_used":[]}'::jsonb
    or (select current_qty from voucher_store_stock where voucher_id=vlim and store_id=st) is distinct from n+2
    or exists(select 1 from customer_reward_vouchers cv join invoice_benefit_values b on b.reward_voucher_id=cv.id where b.invoice_id=inv and cv.status='held') then
  raise exception 'W12 the reopened FOC invoice''s vouchers were not taken back with their stock: % (stock % from %)', r->'foc_vouchers',
    (select current_qty from voucher_store_stock where voucher_id=vlim and store_id=st), n; end if;

 -- W13 A therapy voucher given free; a session is used on one of two
 -- vouchers. Taking the FOC off keeps that one, in the summary and the save,
 -- and the save goes through. Paid, the other is given again with its rights.
 insert into therapy_services(service_code,name,standard_price,duration_minutes,is_active)
  values('SVW-SVC','SVW service',20,30,true) returning id into svc;
 insert into vouchers(name,code,qty_type,reward_eligible) values('Lines Therapy','SVWT','limited',true) returning id into vt;
 insert into voucher_store_stock(voucher_id,store_id,current_qty) values(vt,st,10);
 insert into voucher_store_prices(voucher_id,store_id,selling_price,available_at_store) values(vt,st,40,true);
 perform upsert_therapy_voucher_definition(vt,jsonb_build_array(jsonb_build_object('kind','fixed','service_id',svc,'quantity',2)),
  'months',1,'unrestricted',1,null,'SVW terms');
 inv:=create_invoice_with_details(st,c,jsonb_build_array(jsonb_build_object('kind','voucher','voucher_id',vt,'quantity',1),
   jsonb_build_object('kind','voucher','voucher_id',vt,'quantity',1)),jsonb_build_object('business_date',sg_today()::text));
 for it in select id from invoice_items where invoice_id=inv order by id loop perform apply_line_foc(it,null,null,'Event giveaway'); end loop;
 perform confirm_foc_invoice(inv,null);
 select t.id into tvi from therapy_voucher_issues t join invoice_benefit_values b on b.reward_voucher_id=t.reward_voucher_id
  where b.invoice_id=inv order by b.invoice_item_id limit 1;
 if tvi is null then raise exception 'W13 fixture: no therapy rights were recorded'; end if;
 update therapy_voucher_issues set sessions_used=1 where id=tvi;
 x:=(select jsonb_agg(jsonb_build_object('invoice_item_id',id,'kind','voucher','voucher_id',voucher_id,'quantity',quantity,'unit_price',40,'foc_quantity',0) order by id)
      from invoice_items where invoice_id=inv);
 r:=preview_invoice_correction(inv,jsonb_build_object('items',x,'expected_edit_count',(select edit_count from invoices where id=inv)));
 if not r->'effects' @> '[{"area":"vouchers","items":[{"kind":"voucher","what":"Lines Therapy × 1","why":"used; it stays with the customer"}]}]'
    or jsonb_array_length((select e2->'items' from jsonb_array_elements(r->'effects') e2 where e2->>'area'='vouchers')) <> 1 then
  raise exception 'W13 the summary did not keep the therapy voucher with a session used: %', r->'effects'; end if;
 e:=null;
 begin
  r:=correct_invoice(inv,x,jsonb_build_object('expected_edit_count',(select edit_count from invoices where id=inv)),'Not a giveaway',gen_random_uuid());
 exception when others then e:=sqlerrm;
 end;
 if e is not null then raise exception 'W13 the save was refused: %', e; end if;
 if r->'foc_vouchers' is distinct from '{"taken_back":["Lines Therapy × 1"],"kept_used":["Lines Therapy × 1"]}'::jsonb
    or (select cv.status from customer_reward_vouchers cv join therapy_voucher_issues t on t.reward_voucher_id=cv.id where t.id=tvi) is distinct from 'held' then
  raise exception 'W13 the therapy voucher with a session used was not kept: %', r->'foc_vouchers'; end if;
 perform pay_invoice(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',80)));
 if (select count(*) from customer_reward_vouchers cv join invoice_benefit_values b on b.reward_voucher_id=cv.id
      join therapy_voucher_issues t on t.reward_voucher_id=cv.id
      where b.invoice_id=inv and cv.status='held' and cv.source_type='invoice_reopen' and t.source_issue_id is not null) <> 1
    or (select current_qty from voucher_store_stock where voucher_id=vt and store_id=st) is distinct from 8 then
  raise exception 'W13 paid: the therapy voucher was not given again once with its rights (stock %)',
    (select current_qty from voucher_store_stock where voucher_id=vt and store_id=st); end if;

 -- W14 A therapy voucher line raised from 2 to 3 as the FOC comes off: paid,
 -- all 3 are given, each with recorded rights.
 update voucher_store_stock set current_qty=10 where voucher_id=vt and store_id=st;
 inv:=create_invoice_with_details(st,c,jsonb_build_array(jsonb_build_object('kind','voucher','voucher_id',vt,'quantity',2)),
   jsonb_build_object('business_date',sg_today()::text));
 select id into it from invoice_items where invoice_id=inv;
 perform apply_line_foc(it,null,null,'Event giveaway');
 perform confirm_foc_invoice(inv,null);
 x:=jsonb_build_array(jsonb_build_object('invoice_item_id',it,'kind','voucher','voucher_id',vt,'quantity',3,'unit_price',40,'foc_quantity',0));
 perform correct_invoice(inv,x,jsonb_build_object('expected_edit_count',(select edit_count from invoices where id=inv)),'Three, sold',gen_random_uuid());
 perform pay_invoice(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',120)));
 if (select coalesce(sum(cv.quantity),0) from customer_reward_vouchers cv join invoice_benefit_values b on b.reward_voucher_id=cv.id
      join therapy_voucher_issues t on t.reward_voucher_id=cv.id where b.invoice_id=inv and cv.status='held') <> 3
    or (select current_qty from voucher_store_stock where voucher_id=vt and store_id=st) is distinct from 7 then
  raise exception 'W14 paid: the three therapy vouchers were not all given with rights (stock %)',
    (select current_qty from voucher_store_stock where voucher_id=vt and store_id=st); end if;

 raise notice 'PASS: taking the FOC off with a changed quantity, voucher or pick gives at payment what the corrected lines give, worth what they charge; voucher stock is taken once when the save also changes products, whether the FOC comes off or stays; a voucher moved to a friend stays with them; a line that gave vouchers is refused in plain words; a reopened FOC invoice''s vouchers are taken back; a therapy voucher with a session used stays, and therapy vouchers given again keep their rights';
end $$;

-- ═════ 416: what Confirm FOC took is recorded by voucher, not store by store ═════
-- FOC, cancelled and reopened (the reopening records or takes the 2 units
-- at the first store), then an Owner moves both vouchers to a friend at a
-- second store, then the FOC is taken off. The friend keeps them. The save
-- must not record the 2 units again because the vouchers now sit at another
-- store than the reopening's row: it writes no 'Taken at Confirm FOC' row,
-- and the invoice's rows for the voucher hold what they held before. Counted
-- store by store, it wrote 2 more, and with 417 the last cancel then gave 22
-- in the two stores, not 20 (B03's cancel-voucher-stock-once.sql case 14).
-- Runs the same with or without 417.
do $$
declare o uuid:=gen_random_uuid(); st uuid; st2 uuid; c uuid; c2 uuid; vlim uuid; inv uuid; it uuid; x jsonb; r jsonb; n int;
begin
 insert into auth.users(id,email) values(o,'sold-voucher-rows@tests.invalid');
 insert into profiles(id,full_name,email,role) values(o,'Owner','sold-voucher-rows@tests.invalid','owner');
 perform set_config('request.jwt.claim.sub',o::text,true);
 insert into stores(name,code,country_code) values('Sold Voucher Rows','SVR','SG') returning id into st;
 insert into stores(name,code,country_code) values('Sold Voucher Rows 2','SVR2','SG') returning id into st2;
 insert into customers(full_name,phone) values('SVR Buyer','+61491574118') returning id into c;
 insert into customers(full_name,phone) values('SVR Friend','+61491570156') returning id into c2;
 insert into vouchers(name,code,voucher_kind,selling_price,qty_type) values('Rows Limited','SVRL','normal',40,'limited') returning id into vlim;
 insert into voucher_store_stock(voucher_id,store_id,current_qty) values(vlim,st,10),(vlim,st2,10);
 insert into voucher_store_prices(voucher_id,store_id,selling_price,available_at_store) values(vlim,st,40,true),(vlim,st2,40,true);
 inv:=create_invoice_with_details(st,c,jsonb_build_array(jsonb_build_object('kind','voucher','voucher_id',vlim,'quantity',2)),
   jsonb_build_object('business_date',sg_today()::text));
 select id into it from invoice_items where invoice_id=inv;
 perform apply_line_foc(it,null,null,'Event giveaway');
 perform confirm_foc_invoice(inv,null);
 perform cancel_invoice_recorded(inv,'Mistake',gen_random_uuid());
 perform reopen_invoice(inv,'Customer came back',gen_random_uuid());
 if (select coalesce(sum(cv.quantity),0) from customer_reward_vouchers cv join invoice_benefit_values b on b.reward_voucher_id=cv.id
      where b.invoice_id=inv and cv.status='held' and cv.store_id=st) <> 2
    or (select coalesce(sum(quantity),0) from invoice_voucher_movements where invoice_id=inv and store_id=st) < 2 then
  raise exception 'R1 fixture: the reopening did not give 2 vouchers again at the first store with a row there'; end if;
 n := (select sum(quantity) from invoice_voucher_movements where invoice_id=inv and voucher_id=vlim);
 perform transfer_invoice_unused_benefit(
   (select b.id from invoice_benefit_values b join customer_reward_vouchers cv on cv.id=b.reward_voucher_id
     where b.invoice_id=inv and cv.status='held'),
   c2,st2,'Given to her friend at the other store',gen_random_uuid());
 if (select coalesce(sum(quantity),0) from customer_reward_vouchers where customer_id=c2 and store_id=st2 and status='held') <> 2 then
  raise exception 'R1 fixture: the 2 vouchers did not move to the friend at the second store'; end if;
 x:=jsonb_build_array(jsonb_build_object('invoice_item_id',it,'kind','voucher','voucher_id',vlim,'quantity',2,'unit_price',40,'foc_quantity',0));
 r:=correct_invoice(inv,x,jsonb_build_object('expected_edit_count',(select edit_count from invoices where id=inv)),'Not a giveaway',gen_random_uuid());
 if r->'foc_vouchers' is distinct from '{"taken_back":[],"kept_used":["Rows Limited × 2 — moved to another customer; it stays with them"]}'::jsonb then
  raise exception 'R1 the moved vouchers were not left with the friend: %', r->'foc_vouchers'; end if;
 if exists (select 1 from invoice_voucher_movements where invoice_id=inv and reason like 'Taken at Confirm FOC:%')
    or (select sum(quantity) from invoice_voucher_movements where invoice_id=inv and voucher_id=vlim) is distinct from n then
  raise exception 'R1 the FOC off recorded the reopening''s units again: the rows hold % (expected %): %',
    (select sum(quantity) from invoice_voucher_movements where invoice_id=inv and voucher_id=vlim), n,
    (select string_agg(case when store_id=st then 'store 1' else 'store 2' end || ' ' || quantity || ' ' || reason, '; ' order by created_at, id)
       from invoice_voucher_movements where invoice_id=inv); end if;
 raise notice 'PASS: when the FOC comes off, what Confirm FOC took is recorded by voucher: a reopening''s row at one store counts for vouchers an Owner has since moved to another, so nothing is recorded twice';
end $$;

-- ═════ 416: a save that keeps the invoice FOC, and where 'Taken at Confirm FOC' sits ═════
-- S1 A completed FOC invoice with socks and 2 vouchers. Its voucher line is
-- raised to 3 while it stays FOC, then the socks change twice. Nothing is
-- given for the change, so no voucher stock is taken for it: 8 throughout,
-- and no row is kept. The FOC then comes off (10), and the payment gives 3
-- and takes 3: 7, with 3 held (10 in all). Before (10 Oct), the raise took
-- a unit with a row, the FOC-off save counted that row as part of what
-- Confirm FOC took, and the payment took the unit again: 6 with 3 held.
-- S2 The same raise while FOC, then the FOC taken off with the line back at
-- 2: paid 8, with 2 held.
-- S3 Moved to a second store (store only) while FOC, then the FOC taken
-- off: the 'Taken at Confirm FOC' row sits at the first store, where
-- Confirm FOC took the stock and rule 14 gives it back, so each store's
-- rows add up to what is out there. Cancelled unpaid: 10 and 10. Paid
-- instead, the payment takes at the second store, the invoice's store now.
-- S4 Two lines of the voucher, one line's voucher moved to a friend at the
-- second store, then the FOC taken off: one row at each store, as each
-- holds one; rule 14 gives the first back. The rows match the stock out at
-- each store after the save and after the payment.
-- S5 One unit already on a row at the second store: only the other unit is
-- recorded, at the first store, never more than the voucher lacks in all.
-- S6 Socks and 2 vouchers, FOC, cancelled, reopened, both vouchers moved to
-- a friend at the second store, then the FOC taken off with the voucher
-- line raised to 3 while the first store has none left. The rows already
-- record the 2, so only the 3rd unit is taken, at the invoice's store, and
-- the summary and the save both refuse it. With 1 in stock both go through
-- (with 457 the save gives that unit back, as the invoice is left unpaid,
-- and the payment takes it).
-- S7 Moved to the second store and its voucher line raised to 3 in one save
-- that keeps it FOC: the raise is taken and given back at the second store,
-- where it was taken, so the first keeps 8 out and the second 10.
-- With 417 installed (its cancel gives voucher stock back once), S1, S2, S3
-- and S4 are also cancelled at the end and must come back to 10 at each
-- store; without it the cancel is B03's and is not checked here.
create function pg_temp.svs_at(p_v uuid, p_s uuid) returns int language sql as $f$
  select current_qty from voucher_store_stock where voucher_id = p_v and store_id = p_s $f$;
create function pg_temp.svs_rows(p_inv uuid, p_s uuid) returns int language sql as $f$
  select coalesce(sum(quantity), 0)::int from invoice_voucher_movements where invoice_id = p_inv and store_id = p_s $f$;
create function pg_temp.svs_held(p_inv uuid, p_s uuid) returns int language sql as $f$
  select coalesce(sum(cv.quantity), 0)::int from customer_reward_vouchers cv
    join invoice_benefit_values b on b.reward_voucher_id = cv.id
   where b.invoice_id = p_inv and cv.status <> 'revoked' and (p_s is null or cv.store_id = p_s) $f$;
-- The 'Taken at Confirm FOC' rows of the save made with that reason, by store.
create function pg_temp.svs_taken(p_inv uuid, p_reason text) returns text language sql as $f$
  select coalesce(string_agg(s.code || ' ' || mv.quantity, ', ' order by s.code), '')
    from invoice_voucher_movements mv join stores s on s.id = mv.store_id
   where mv.invoice_id = p_inv and mv.reason = 'Taken at Confirm FOC: ' || p_reason $f$;
create function pg_temp.svs_417() returns boolean language sql as $f$
  select to_regprocedure('public.invoice_voucher_stock_unrecorded(uuid,boolean)') is not null $f$;
do $$
declare o uuid:=gen_random_uuid(); st uuid; st2 uuid; c uuid; c2 uuid; pm uuid; vlim uuid; p uuid;
 inv uuid; it uuid; itp uuid; itv uuid; x jsonb; r jsonb; e text; mode text; k int; n int;
begin
 insert into auth.users(id,email) values(o,'sold-voucher-still@tests.invalid');
 insert into profiles(id,full_name,email,role) values(o,'Owner','sold-voucher-still@tests.invalid','owner');
 perform set_config('request.jwt.claim.sub',o::text,true);
 insert into stores(name,code,country_code) values('Sold Voucher Still','SVS1','SG') returning id into st;
 insert into stores(name,code,country_code) values('Sold Voucher Still 2','SVS2','SG') returning id into st2;
 insert into customers(full_name,phone) values('SVS Buyer','+61491571491') returning id into c;
 insert into customers(full_name,phone) values('SVS Friend','+61491571804') returning id into c2;
 insert into payment_methods(name,is_active) values('SVS Cash',true) returning id into pm;
 insert into vouchers(name,code,voucher_kind,selling_price,qty_type) values('Still Limited','SVSL','normal',40,'limited') returning id into vlim;
 insert into voucher_store_stock(voucher_id,store_id,current_qty) values(vlim,st,10),(vlim,st2,10);
 insert into voucher_store_prices(voucher_id,store_id,selling_price,available_at_store) values(vlim,st,40,true),(vlim,st2,40,true);
 insert into products(name,sku,product_type) values('SVS Socks','SVSS','own') returning id into p;
 insert into store_inventory(store_id,product_id,current_qty) values(st,p,50),(st2,p,50);
 perform set_product_prices(st,p,30,30,'available');
 perform set_product_prices(st2,p,30,30,'available');

 -- S1 and S2
 foreach mode in array array['S1 raised to 3','S2 raised to 3, then back to 2'] loop
  update voucher_store_stock set current_qty=10 where voucher_id=vlim;
  inv:=create_invoice_with_details(st,c,jsonb_build_array(jsonb_build_object('kind','product','product_id',p,'quantity',1),
     jsonb_build_object('kind','voucher','voucher_id',vlim,'quantity',2)),jsonb_build_object('business_date',sg_today()::text));
  select id into itp from invoice_items where invoice_id=inv and line_kind='product';
  select id into itv from invoice_items where invoice_id=inv and line_kind='voucher';
  perform apply_line_foc(itp,null,null,'Event giveaway');
  perform apply_line_foc(itv,null,null,'Event giveaway');
  perform confirm_foc_invoice(inv,null);
  for k in 1 .. 3 loop  -- the raise, then the socks changed twice, still FOC
   x:=jsonb_build_array(
     jsonb_build_object('invoice_item_id',itp,'kind','product','product_id',p,'quantity',k,'unit_price',30,'foc_quantity',k,'foc_reason','Event giveaway'),
     jsonb_build_object('invoice_item_id',itv,'kind','voucher','voucher_id',vlim,'quantity',3,'unit_price',40,'foc_quantity',3,'foc_reason','Event giveaway'));
   r:=preview_invoice_correction(inv,jsonb_build_object('items',x,'expected_edit_count',(select edit_count from invoices where id=inv)));
   if (r->'outcome'->>'checked')::boolean is not true then
    raise exception '% (edit %) the summary refused a save that keeps it FOC: %', mode, k, r->'outcome'; end if;
   perform correct_invoice(inv,x,jsonb_build_object('expected_edit_count',(select edit_count from invoices where id=inv)),'Still a giveaway '||k,gen_random_uuid());
   if (select status from invoices where id=inv) <> 'completed_foc' or pg_temp.svs_at(vlim,st) <> 8
      or pg_temp.svs_rows(inv,st) <> 0 or pg_temp.svs_held(inv,null) <> 2 then
    raise exception '% (edit %) the save that keeps it FOC took voucher stock for what it does not give: status %, stock % (expected 8), rows %, held %',
      mode, k, (select status from invoices where id=inv), pg_temp.svs_at(vlim,st), pg_temp.svs_rows(inv,st), pg_temp.svs_held(inv,null); end if;
  end loop;
  if not exists (select 1 from invoice_voucher_movements where invoice_id=inv and reason like 'Still FOC, nothing given for the change:%' and quantity = -1) then
   raise exception '% the raise was not taken and given back by the save, as a row says', mode; end if;
  n := case when mode like 'S1%' then 3 else 2 end;
  x:=jsonb_build_array(
    jsonb_build_object('invoice_item_id',itp,'kind','product','product_id',p,'quantity',3,'unit_price',30,'foc_quantity',0),
    jsonb_build_object('invoice_item_id',itv,'kind','voucher','voucher_id',vlim,'quantity',n,'unit_price',40,'foc_quantity',0));
  perform correct_invoice(inv,x,jsonb_build_object('expected_edit_count',(select edit_count from invoices where id=inv)),'Not a giveaway',gen_random_uuid());
  if pg_temp.svs_taken(inv,'Not a giveaway') <> 'SVS1 2' then
   raise exception '% the FOC off recorded "%" as taken at Confirm FOC, not "SVS1 2"', mode, pg_temp.svs_taken(inv,'Not a giveaway'); end if;
  if (select status from invoices where id=inv) <> 'unpaid' or pg_temp.svs_at(vlim,st) <> 10 or pg_temp.svs_rows(inv,st) <> 0
     or pg_temp.svs_held(inv,null) <> 0 then
   raise exception '% the FOC off: status %, stock % (expected 10), rows %, held %', mode,
     (select status from invoices where id=inv), pg_temp.svs_at(vlim,st), pg_temp.svs_rows(inv,st), pg_temp.svs_held(inv,null); end if;
  perform pay_invoice(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',(select total_amount from invoices where id=inv))));
  if pg_temp.svs_at(vlim,st) <> 10-n or pg_temp.svs_held(inv,st) <> n or pg_temp.svs_rows(inv,st) <> n then
   raise exception '% paid: stock % with % held and rows % (expected %, %, %): a unit was taken twice', mode,
     pg_temp.svs_at(vlim,st), pg_temp.svs_held(inv,st), pg_temp.svs_rows(inv,st), 10-n, n, n; end if;
  if pg_temp.svs_417() then
   perform cancel_invoice_recorded(inv,'Mistake',gen_random_uuid());
   if pg_temp.svs_at(vlim,st) <> 10 then
    raise exception '% cancelled (with 417): stock %, not 10', mode, pg_temp.svs_at(vlim,st); end if;
  end if;
 end loop;

 -- S3 Moved to the second store (store only) while FOC, then the FOC off.
 foreach mode in array array['S3 cancelled unpaid','S3 paid'] loop
  update voucher_store_stock set current_qty=10 where voucher_id=vlim;
  inv:=create_invoice_with_details(st,c,jsonb_build_array(jsonb_build_object('kind','voucher','voucher_id',vlim,'quantity',2)),
    jsonb_build_object('business_date',sg_today()::text));
  select id into it from invoice_items where invoice_id=inv;
  perform apply_line_foc(it,null,null,'Event giveaway');
  perform confirm_foc_invoice(inv,null);
  x:=jsonb_build_array(jsonb_build_object('invoice_item_id',it,'kind','voucher','voucher_id',vlim,'quantity',2,'unit_price',40,'foc_quantity',2,'foc_reason','Event giveaway'));
  perform correct_invoice(inv,x,jsonb_build_object('store_id',st2,'expected_edit_count',(select edit_count from invoices where id=inv)),'Wrong store',gen_random_uuid());
  if (select (store_id, status::text) from invoices where id=inv) is distinct from (st2, 'completed_foc'::text)
     or pg_temp.svs_at(vlim,st) <> 8 or pg_temp.svs_held(inv,st) <> 2 then
   raise exception '% fixture: moved to the second store, still FOC, the 2 out at the first', mode; end if;
  x:=jsonb_build_array(jsonb_build_object('invoice_item_id',it,'kind','voucher','voucher_id',vlim,'quantity',2,'unit_price',40,'foc_quantity',0));
  perform correct_invoice(inv,x,jsonb_build_object('expected_edit_count',(select edit_count from invoices where id=inv)),'Not a giveaway',gen_random_uuid());
  if pg_temp.svs_taken(inv,'Not a giveaway') <> 'SVS1 2' then
   raise exception '% the FOC off recorded "%" as taken at Confirm FOC, not "SVS1 2" (the first store, where it was taken)', mode, pg_temp.svs_taken(inv,'Not a giveaway'); end if;
  if pg_temp.svs_at(vlim,st) <> 10 or pg_temp.svs_at(vlim,st2) <> 10 or pg_temp.svs_rows(inv,st) <> 0 or pg_temp.svs_rows(inv,st2) <> 0 then
   raise exception '% the FOC off: stock % and %, rows % and % (expected 10 and 10, rows 0 and 0)', mode,
     pg_temp.svs_at(vlim,st), pg_temp.svs_at(vlim,st2), pg_temp.svs_rows(inv,st), pg_temp.svs_rows(inv,st2); end if;
  if mode = 'S3 paid' then
   perform pay_invoice(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',80)));
   if pg_temp.svs_at(vlim,st) <> 10 or pg_temp.svs_at(vlim,st2) <> 8 or pg_temp.svs_rows(inv,st) <> 0 or pg_temp.svs_rows(inv,st2) <> 2
      or pg_temp.svs_held(inv,st2) <> 2 then
    raise exception '% paid: stock % and %, rows % and %, held at the second store % (expected 10 and 8, rows 0 and 2, 2 held)', mode,
      pg_temp.svs_at(vlim,st), pg_temp.svs_at(vlim,st2), pg_temp.svs_rows(inv,st), pg_temp.svs_rows(inv,st2), pg_temp.svs_held(inv,st2); end if;
  end if;
  if mode = 'S3 cancelled unpaid' or pg_temp.svs_417() then
   perform cancel_invoice_recorded(inv,'Mistake',gen_random_uuid());
   if pg_temp.svs_at(vlim,st) <> 10 or pg_temp.svs_at(vlim,st2) <> 10 then
    raise exception '% cancelled: stock % and %, not 10 and 10', mode, pg_temp.svs_at(vlim,st), pg_temp.svs_at(vlim,st2); end if;
  end if;
 end loop;

 -- S4 Two lines of the voucher; one line's voucher moved to a friend at the
 -- second store; then the FOC off.
 update voucher_store_stock set current_qty=10 where voucher_id=vlim;
 inv:=create_invoice_with_details(st,c,jsonb_build_array(jsonb_build_object('kind','voucher','voucher_id',vlim,'quantity',1),
   jsonb_build_object('kind','voucher','voucher_id',vlim,'quantity',1)),jsonb_build_object('business_date',sg_today()::text));
 for it in select id from invoice_items where invoice_id=inv order by id loop perform apply_line_foc(it,null,null,'Event giveaway'); end loop;
 perform confirm_foc_invoice(inv,null);
 perform transfer_invoice_unused_benefit((select b.id from invoice_benefit_values b where b.invoice_id=inv order by b.invoice_item_id desc limit 1),
   c2,st2,'Given to her friend at the other store',gen_random_uuid());
 if pg_temp.svs_at(vlim,st) <> 9 or pg_temp.svs_at(vlim,st2) <> 9 or pg_temp.svs_held(inv,st) <> 1 or pg_temp.svs_held(inv,st2) <> 1 then
  raise exception 'S4 fixture: one voucher out at each store'; end if;
 x:=(select jsonb_agg(jsonb_build_object('invoice_item_id',id,'kind','voucher','voucher_id',voucher_id,'quantity',1,'unit_price',40,'foc_quantity',0) order by id)
      from invoice_items where invoice_id=inv);
 perform correct_invoice(inv,x,jsonb_build_object('expected_edit_count',(select edit_count from invoices where id=inv)),'Not a giveaway',gen_random_uuid());
 if pg_temp.svs_taken(inv,'Not a giveaway') <> 'SVS1 1, SVS2 1' then
  raise exception 'S4 the FOC off recorded "%" as taken at Confirm FOC, not "SVS1 1, SVS2 1" (one at each store)', pg_temp.svs_taken(inv,'Not a giveaway'); end if;
 if pg_temp.svs_at(vlim,st) <> 10 or pg_temp.svs_at(vlim,st2) <> 9 or pg_temp.svs_rows(inv,st) <> 0 or pg_temp.svs_rows(inv,st2) <> 1 then
  raise exception 'S4 the FOC off: stock % and %, rows % and % (expected 10 and 9, rows 0 and 1)',
    pg_temp.svs_at(vlim,st), pg_temp.svs_at(vlim,st2), pg_temp.svs_rows(inv,st), pg_temp.svs_rows(inv,st2); end if;
 perform pay_invoice(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',(select total_amount from invoices where id=inv))));
 if pg_temp.svs_at(vlim,st) <> 9 or pg_temp.svs_at(vlim,st2) <> 9 or pg_temp.svs_rows(inv,st) <> 1 or pg_temp.svs_rows(inv,st2) <> 1
    or pg_temp.svs_held(inv,st) <> 1 or pg_temp.svs_held(inv,st2) <> 1 then
  raise exception 'S4 paid: stock % and %, rows % and %, held % and % (expected 9 and 9, rows 1 and 1, 1 held at each)',
    pg_temp.svs_at(vlim,st), pg_temp.svs_at(vlim,st2), pg_temp.svs_rows(inv,st), pg_temp.svs_rows(inv,st2),
    pg_temp.svs_held(inv,st), pg_temp.svs_held(inv,st2); end if;
 if pg_temp.svs_417() then
  perform cancel_invoice_recorded(inv,'Mistake',gen_random_uuid());
  if pg_temp.svs_at(vlim,st) <> 10 or pg_temp.svs_at(vlim,st2) <> 10 then
   raise exception 'S4 cancelled (with 417): stock % and %, not 10 and 10', pg_temp.svs_at(vlim,st), pg_temp.svs_at(vlim,st2); end if;
 end if;

 -- S5 One unit already on a row at the second store (as if an earlier step
 -- had recorded it there): the FOC off records only the other, at the first.
 update voucher_store_stock set current_qty=10 where voucher_id=vlim;
 inv:=create_invoice_with_details(st,c,jsonb_build_array(jsonb_build_object('kind','voucher','voucher_id',vlim,'quantity',2)),
   jsonb_build_object('business_date',sg_today()::text));
 select id into it from invoice_items where invoice_id=inv;
 perform apply_line_foc(it,null,null,'Event giveaway');
 perform confirm_foc_invoice(inv,null);
 insert into invoice_voucher_movements(invoice_id,voucher_id,store_id,quantity,reason,created_by)
  values(inv,vlim,st2,1,'SVS one unit on a row at the second store',o);
 x:=jsonb_build_array(jsonb_build_object('invoice_item_id',it,'kind','voucher','voucher_id',vlim,'quantity',2,'unit_price',40,'foc_quantity',0));
 perform correct_invoice(inv,x,jsonb_build_object('expected_edit_count',(select edit_count from invoices where id=inv)),'Not a giveaway',gen_random_uuid());
 if pg_temp.svs_taken(inv,'Not a giveaway') <> 'SVS1 1' or (select sum(quantity) from invoice_voucher_movements where invoice_id=inv) <> 0 then
  raise exception 'S5 the FOC off recorded "%" as taken at Confirm FOC (expected "SVS1 1"), and the rows hold % (expected 0)',
    pg_temp.svs_taken(inv,'Not a giveaway'), (select sum(quantity) from invoice_voucher_movements where invoice_id=inv); end if;

 -- S6 FOC, cancelled, reopened, moved to the friend, then the FOC off with
 -- the voucher line raised to 3 while the first store has none left.
 update voucher_store_stock set current_qty=10 where voucher_id=vlim;
 inv:=create_invoice_with_details(st,c,jsonb_build_array(jsonb_build_object('kind','product','product_id',p,'quantity',1),
    jsonb_build_object('kind','voucher','voucher_id',vlim,'quantity',2)),jsonb_build_object('business_date',sg_today()::text));
 select id into itp from invoice_items where invoice_id=inv and line_kind='product';
 select id into itv from invoice_items where invoice_id=inv and line_kind='voucher';
 perform apply_line_foc(itp,null,null,'Event giveaway');
 perform apply_line_foc(itv,null,null,'Event giveaway');
 perform confirm_foc_invoice(inv,null);
 perform cancel_invoice_recorded(inv,'Mistake',gen_random_uuid());
 perform reopen_invoice(inv,'Customer came back',gen_random_uuid());
 if (select status from invoices where id=inv) <> 'completed_foc' or pg_temp.svs_held(inv,st) <> 2 or pg_temp.svs_rows(inv,st) < 2 then
  raise exception 'S6 fixture: reopened as FOC with 2 vouchers and a row at the first store (status %, held %, rows %)',
    (select status from invoices where id=inv), pg_temp.svs_held(inv,st), pg_temp.svs_rows(inv,st); end if;
 n := (select sum(quantity) from invoice_voucher_movements where invoice_id=inv);
 perform transfer_invoice_unused_benefit((select b.id from invoice_benefit_values b join customer_reward_vouchers cv on cv.id=b.reward_voucher_id
     where b.invoice_id=inv and cv.status='held'), c2,st2,'Given to her friend at the other store',gen_random_uuid());
 update voucher_store_stock set current_qty=0 where voucher_id=vlim and store_id=st;
 x:=jsonb_build_array(
   jsonb_build_object('invoice_item_id',itp,'kind','product','product_id',p,'quantity',1,'unit_price',30,'foc_quantity',0),
   jsonb_build_object('invoice_item_id',itv,'kind','voucher','voucher_id',vlim,'quantity',3,'unit_price',40,'foc_quantity',0));
 r:=preview_invoice_correction(inv,jsonb_build_object('items',x,'expected_edit_count',(select edit_count from invoices where id=inv)));
 e:=null;
 begin
  perform correct_invoice(inv,x,jsonb_build_object('expected_edit_count',(select edit_count from invoices where id=inv)),'Not a giveaway, and 3',gen_random_uuid());
 exception when others then e:=sqlerrm;
 end;
 if (r->'outcome'->>'checked')::boolean is not false or e is null or e not like '%voucher stock%' then
  raise exception 'S6 with none left at the first store: the summary said checked % and the save said "%" (both must refuse: the rows already record the 2, so the 3rd unit is taken there)',
    r->'outcome'->>'checked', coalesce(e, 'saved'); end if;
 update voucher_store_stock set current_qty=1 where voucher_id=vlim and store_id=st;
 r:=preview_invoice_correction(inv,jsonb_build_object('items',x,'expected_edit_count',(select edit_count from invoices where id=inv)));
 if (r->'outcome'->>'checked')::boolean is not true then
  raise exception 'S6 with 1 left at the first store the summary refused it: %', r->'outcome'; end if;
 perform correct_invoice(inv,x,jsonb_build_object('expected_edit_count',(select edit_count from invoices where id=inv)),'Not a giveaway, and 3',gen_random_uuid());
 -- 457 (the Owner, 22 Oct 2026): the save leaves the invoice unpaid, so it
 -- keeps no voucher stock for the 3rd unit (taken and given back; the
 -- payment takes it): 1 left and the rows as they were. Before 457 the save
 -- kept it: 0 left, one row more. 457's correct_invoice is known by the
 -- wording of the row it writes.
 k := case when position('Not paid in full, nothing given yet' in pg_get_functiondef('public.correct_invoice(uuid,jsonb,jsonb,text,uuid)'::regprocedure)) > 0
           then 0 else 1 end;
 if pg_temp.svs_taken(inv,'Not a giveaway, and 3') <> '' or pg_temp.svs_at(vlim,st) <> 1 - k
    or (select sum(quantity) from invoice_voucher_movements where invoice_id=inv) <> n + k then
  raise exception 'S6 saved: taken at Confirm FOC "%", stock at the first store %, rows % (expected none, %, %)',
    pg_temp.svs_taken(inv,'Not a giveaway, and 3'), pg_temp.svs_at(vlim,st), (select sum(quantity) from invoice_voucher_movements where invoice_id=inv), 1 - k, n + k; end if;
 -- S7 Moved and raised in one save that keeps it FOC.
 update voucher_store_stock set current_qty=10 where voucher_id=vlim;
 inv:=create_invoice_with_details(st,c,jsonb_build_array(jsonb_build_object('kind','product','product_id',p,'quantity',1),
    jsonb_build_object('kind','voucher','voucher_id',vlim,'quantity',2)),jsonb_build_object('business_date',sg_today()::text));
 select id into itp from invoice_items where invoice_id=inv and line_kind='product';
 select id into itv from invoice_items where invoice_id=inv and line_kind='voucher';
 perform apply_line_foc(itp,null,null,'Event giveaway');
 perform apply_line_foc(itv,null,null,'Event giveaway');
 perform confirm_foc_invoice(inv,null);
 x:=jsonb_build_array(
   jsonb_build_object('invoice_item_id',itp,'kind','product','product_id',p,'quantity',1,'unit_price',30,'foc_quantity',1,'foc_reason','Event giveaway'),
   jsonb_build_object('invoice_item_id',itv,'kind','voucher','voucher_id',vlim,'quantity',3,'unit_price',40,'foc_quantity',3,'foc_reason','Event giveaway'));
 perform correct_invoice(inv,x,jsonb_build_object('store_id',st2,'expected_edit_count',(select edit_count from invoices where id=inv)),'Wrong store, and 3',gen_random_uuid());
 if (select status from invoices where id=inv) <> 'completed_foc' or pg_temp.svs_at(vlim,st) <> 8 or pg_temp.svs_at(vlim,st2) <> 10
    or pg_temp.svs_rows(inv,st) <> 0 or pg_temp.svs_rows(inv,st2) <> 0 then
  raise exception 'S7 moved and raised, still FOC: status %, stock % and %, rows % and % (expected 8 and 10, rows 0 and 0)',
    (select status from invoices where id=inv), pg_temp.svs_at(vlim,st), pg_temp.svs_at(vlim,st2), pg_temp.svs_rows(inv,st), pg_temp.svs_rows(inv,st2); end if;

 raise notice 'PASS: a save that keeps a FOC invoice FOC takes no voucher stock for what it does not give, so the payment after the FOC comes off takes each unit once; what Confirm FOC took is recorded at the stores that hold the vouchers, one row per store, never more than the voucher lacks in all, and the summary refuses what the save refuses';
end $$;

-- ═════ 416: premium bundle vouchers, and a voucher moved to another store of the same customer ═════
-- B1 A voucher line of 2 and a premium bundle giving 1 of the same voucher,
-- all FOC and confirmed (the bundle takes its own unit). The bundle's
-- voucher is moved to a friend at the second store, then the FOC comes off
-- the voucher line only. Confirm FOC took 2 for the voucher line, so only
-- 2 are recorded as taken then, at the first store; the bundle's moved
-- voucher is not counted and not touched. Paid: 8 and 9 (17), the buyer
-- holds 2 and the friend 1. Before (10 Oct), the moved bundle voucher was
-- counted as taken at Confirm FOC, and the payment took one unit too few
-- (9 and 9, 3 held). With 417 the cancel then gives back 10 and 10.
-- B2 A premium bundle giving 1 and a voucher line of 2, FOC, cancelled and
-- reopened (the bundle's voucher comes back as 'invoice_reopen'), then the
-- FOC off the voucher line only. Only the voucher line's 2 are taken back,
-- in the summary and the save; the bundle's voucher stays. Paid, 3 held
-- (7 at the store with 417 in). Before, the bundle's voucher was taken back
-- too and never given again.
-- B3 Two voucher lines of 1; one voucher moved to the second store of the
-- same customer, then the FOC off. Both are unused and the customer's own,
-- so both are taken back (10 and 10), and the summary says so. Paid, both
-- are given again at the invoice's store: 8 and 10, 2 held there. With 417
-- the cancel gives back 10 and 10. Before, the moved one was called "moved
-- to another customer" and left with the customer while the invoice was
-- unpaid.
create function pg_temp.svb_at(p_v uuid, p_s uuid) returns int language sql as $f$
  select coalesce((select current_qty from voucher_store_stock where voucher_id = p_v and store_id = p_s), 0) $f$;
create function pg_temp.svb_rows(p_inv uuid, p_s uuid) returns int language sql as $f$
  select coalesce(sum(quantity), 0)::int from invoice_voucher_movements where invoice_id = p_inv and store_id = p_s $f$;
create function pg_temp.svb_held(p_inv uuid, p_c uuid, p_s uuid) returns int language sql as $f$
  select coalesce(sum(cv.quantity), 0)::int from customer_reward_vouchers cv
    join invoice_benefit_values b on b.reward_voucher_id = cv.id
   where b.invoice_id = p_inv and cv.status <> 'revoked'
     and (p_c is null or cv.customer_id = p_c) and (p_s is null or cv.store_id = p_s) $f$;
create function pg_temp.svb_taken(p_inv uuid, p_reason text) returns text language sql as $f$
  select coalesce(string_agg(s.code || ' ' || mv.quantity, ', ' order by s.code), '')
    from invoice_voucher_movements mv join stores s on s.id = mv.store_id
   where mv.invoice_id = p_inv and mv.reason = 'Taken at Confirm FOC: ' || p_reason $f$;
-- The corrected lines: every line as it is, the voucher lines without FOC.
create function pg_temp.svb_lines(p_inv uuid) returns jsonb language sql as $f$
  select jsonb_agg(case when it.line_kind = 'voucher'
                        then jsonb_build_object('invoice_item_id', it.id, 'kind', 'voucher', 'voucher_id', it.voucher_id,
                                                'quantity', it.quantity, 'unit_price', it.unit_price, 'foc_quantity', 0)
                        else jsonb_build_object('invoice_item_id', it.id, 'kind', 'premium_bundle', 'premium_bundle_id', it.premium_bundle_id,
                                                'quantity', it.quantity, 'unit_price', it.unit_price, 'foc_quantity', it.foc_quantity,
                                                'foc_reason', it.foc_reason, 'voucher_selection', it.bundle_voucher_selection) end
                   order by it.id)
    from invoice_items it where it.invoice_id = p_inv $f$;
do $$
declare o uuid:=gen_random_uuid(); st uuid; st2 uuid; c uuid; c2 uuid; pm uuid; v uuid; pb uuid;
 inv uuid; it uuid; bi uuid; x jsonb; r jsonb; e jsonb; is417 boolean;
begin
 insert into auth.users(id,email) values(o,'sold-voucher-bundle@tests.invalid');
 insert into profiles(id,full_name,email,role) values(o,'Owner','sold-voucher-bundle@tests.invalid','owner');
 perform set_config('request.jwt.claim.sub',o::text,true);
 is417 := to_regprocedure('public.invoice_voucher_stock_unrecorded(uuid,boolean)') is not null;
 insert into stores(name,code,country_code) values('Sold Voucher Bundle','SVB1','SG') returning id into st;
 insert into stores(name,code,country_code) values('Sold Voucher Bundle 2','SVB2','SG') returning id into st2;
 insert into customers(full_name,phone) values('SVB Buyer','+61491574118') returning id into c;
 insert into customers(full_name,phone) values('SVB Friend','+61491574632') returning id into c2;
 insert into payment_methods(name,is_active) values('SVB Cash',true) returning id into pm;
 insert into vouchers(name,code,voucher_kind,selling_price,qty_type,reward_eligible) values('Bundle Limited','SVBL','normal',40,'limited',true) returning id into v;
 insert into voucher_store_stock(voucher_id,store_id,current_qty) values(v,st,10),(v,st2,10);
 insert into voucher_store_prices(voucher_id,store_id,selling_price,available_at_store) values(v,st,40,true),(v,st2,40,true);
 insert into premium_bundles(name,customer_payment_amount,paid_credit_amount,free_voucher_qty,grants_reward)
  values('SVB Bundle',140,100,1,true) returning id into pb;
 insert into premium_bundle_stores(bundle_id,store_id) values(pb,st),(pb,st2);
 insert into premium_bundle_vouchers(bundle_id,voucher_id) values(pb,v);

 -- B1
 inv:=create_invoice_with_details(st,c,jsonb_build_array(
   jsonb_build_object('kind','voucher','voucher_id',v,'quantity',2),
   jsonb_build_object('kind','premium_bundle','premium_bundle_id',pb,'quantity',1,
                      'voucher_selection',jsonb_build_array(jsonb_build_object('voucher_id',v,'quantity',1)))),
   jsonb_build_object('business_date',sg_today()::text));
 for it in select id from invoice_items where invoice_id=inv order by id loop perform apply_line_foc(it,null,null,'Event giveaway'); end loop;
 perform confirm_foc_invoice(inv,null);
 select id into bi from invoice_items where invoice_id=inv and line_kind='premium_bundle';
 if pg_temp.svb_at(v,st) <> 7 or pg_temp.svb_held(inv,c,st) <> 3 or pg_temp.svb_rows(inv,st) <> 0 then
  raise exception 'B1 fixture: Confirm FOC with the bundle: stock % (expected 7), held %, rows %',
    pg_temp.svb_at(v,st), pg_temp.svb_held(inv,c,st), pg_temp.svb_rows(inv,st); end if;
 perform transfer_invoice_unused_benefit((select b.id from invoice_benefit_values b where b.invoice_item_id=bi and b.reward_voucher_id is not null),
   c2,st2,'The bundle voucher, given to her friend at the other store',gen_random_uuid());
 if pg_temp.svb_at(v,st) <> 8 or pg_temp.svb_at(v,st2) <> 9 or pg_temp.svb_held(inv,c2,st2) <> 1 then
  raise exception 'B1 fixture: the bundle voucher moved to the friend (stock % and %)', pg_temp.svb_at(v,st), pg_temp.svb_at(v,st2); end if;
 x:=pg_temp.svb_lines(inv);
 r:=preview_invoice_correction(inv,jsonb_build_object('items',x,'expected_edit_count',(select edit_count from invoices where id=inv)));
 select e2 into e from jsonb_array_elements(r->'effects') e2 where e2->>'area'='vouchers';
 if e->>'detail' is distinct from 'Removing the FOC takes back the unused vouchers it gave (Bundle Limited × 2). They are given again as the corrected lines give them when the invoice is paid.'
    or e->'items' is distinct from '[]'::jsonb then
  raise exception 'B1 the summary listed the bundle''s voucher with the voucher line''s: %', e; end if;
 r:=correct_invoice(inv,x,jsonb_build_object('expected_edit_count',(select edit_count from invoices where id=inv)),'Not a giveaway',gen_random_uuid());
 if pg_temp.svb_taken(inv,'Not a giveaway') <> 'SVB1 2' then
  raise exception 'B1 the FOC off recorded "%" as taken at Confirm FOC, not "SVB1 2" (the bundle took its own unit)', pg_temp.svb_taken(inv,'Not a giveaway'); end if;
 if r->'foc_vouchers' is distinct from '{"taken_back":["Bundle Limited × 2"],"kept_used":[]}'::jsonb
    or pg_temp.svb_at(v,st) <> 10 or pg_temp.svb_at(v,st2) <> 9 or pg_temp.svb_held(inv,c2,st2) <> 1 then
  raise exception 'B1 the FOC off: % ; stock % and % (expected 10 and 9), friend holds %',
    r->'foc_vouchers', pg_temp.svb_at(v,st), pg_temp.svb_at(v,st2), pg_temp.svb_held(inv,c2,st2); end if;
 perform pay_invoice(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',(select total_amount from invoices where id=inv))));
 if pg_temp.svb_at(v,st) <> 8 or pg_temp.svb_at(v,st2) <> 9 or pg_temp.svb_rows(inv,st) <> 2 or pg_temp.svb_rows(inv,st2) <> 0
    or pg_temp.svb_held(inv,c,st) <> 2 or pg_temp.svb_held(inv,c2,st2) <> 1 then
  raise exception 'B1 paid: stock % and % (expected 8 and 9), rows % and % (expected 2 and 0), buyer % and friend % (expected 2 and 1): a unit was not taken',
    pg_temp.svb_at(v,st), pg_temp.svb_at(v,st2), pg_temp.svb_rows(inv,st), pg_temp.svb_rows(inv,st2),
    pg_temp.svb_held(inv,c,st), pg_temp.svb_held(inv,c2,st2); end if;
 if is417 then
  perform cancel_invoice_recorded(inv,'Mistake',gen_random_uuid());
  if pg_temp.svb_at(v,st) <> 10 or pg_temp.svb_at(v,st2) <> 10 then
   raise exception 'B1 cancelled (with 417): stock % and %, not 10 and 10', pg_temp.svb_at(v,st), pg_temp.svb_at(v,st2); end if;
 end if;

 -- B2
 update voucher_store_stock set current_qty=10 where voucher_id=v;
 inv:=create_invoice_with_details(st,c,jsonb_build_array(
   jsonb_build_object('kind','premium_bundle','premium_bundle_id',pb,'quantity',1,
                      'voucher_selection',jsonb_build_array(jsonb_build_object('voucher_id',v,'quantity',1))),
   jsonb_build_object('kind','voucher','voucher_id',v,'quantity',2)),
   jsonb_build_object('business_date',sg_today()::text));
 for it in select id from invoice_items where invoice_id=inv order by id loop perform apply_line_foc(it,null,null,'Event giveaway'); end loop;
 perform confirm_foc_invoice(inv,null);
 select id into bi from invoice_items where invoice_id=inv and line_kind='premium_bundle';
 perform cancel_invoice_recorded(inv,'Mistake',gen_random_uuid());
 perform reopen_invoice(inv,'Customer came back',gen_random_uuid());
 if (select status from invoices where id=inv) <> 'completed_foc'
    or not exists (select 1 from customer_reward_vouchers cv join invoice_benefit_values b on b.reward_voucher_id=cv.id
                    where b.invoice_item_id=bi and cv.status='held' and cv.source_type='invoice_reopen') then
  raise exception 'B2 fixture: reopened as FOC with the bundle''s voucher given again as invoice_reopen'; end if;
 x:=pg_temp.svb_lines(inv);
 r:=preview_invoice_correction(inv,jsonb_build_object('items',x,'expected_edit_count',(select edit_count from invoices where id=inv)));
 select e2 into e from jsonb_array_elements(r->'effects') e2 where e2->>'area'='vouchers';
 if e->>'detail' is distinct from 'Removing the FOC takes back the unused vouchers it gave (Bundle Limited × 2). They are given again as the corrected lines give them when the invoice is paid.'
    or e->'items' is distinct from '[]'::jsonb then
  raise exception 'B2 the summary would take back the bundle''s reopened voucher: %', e; end if;
 r:=correct_invoice(inv,x,jsonb_build_object('expected_edit_count',(select edit_count from invoices where id=inv)),'Not a giveaway',gen_random_uuid());
 if r->'foc_vouchers' is distinct from '{"taken_back":["Bundle Limited × 2"],"kept_used":[]}'::jsonb
    or not exists (select 1 from customer_reward_vouchers cv join invoice_benefit_values b on b.reward_voucher_id=cv.id
                    where b.invoice_item_id=bi and cv.status='held') then
  raise exception 'B2 the FOC off took back the bundle''s voucher: %', r->'foc_vouchers'; end if;
 perform pay_invoice(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',(select total_amount from invoices where id=inv))));
 if pg_temp.svb_held(inv,c,st) <> 3
    or not exists (select 1 from customer_reward_vouchers cv join invoice_benefit_values b on b.reward_voucher_id=cv.id
                    where b.invoice_item_id=bi and cv.status='held')
    or (is417 and pg_temp.svb_at(v,st) <> 7) then
  raise exception 'B2 paid: % held (expected 3, the bundle''s among them), stock % (expected 7 with 417)',
    pg_temp.svb_held(inv,c,st), pg_temp.svb_at(v,st); end if;

 -- B3
 update voucher_store_stock set current_qty=10 where voucher_id=v;
 inv:=create_invoice_with_details(st,c,jsonb_build_array(jsonb_build_object('kind','voucher','voucher_id',v,'quantity',1),
   jsonb_build_object('kind','voucher','voucher_id',v,'quantity',1)),jsonb_build_object('business_date',sg_today()::text));
 for it in select id from invoice_items where invoice_id=inv order by id loop perform apply_line_foc(it,null,null,'Event giveaway'); end loop;
 perform confirm_foc_invoice(inv,null);
 perform transfer_invoice_unused_benefit((select b.id from invoice_benefit_values b where b.invoice_id=inv order by b.invoice_item_id desc limit 1),
   c,st2,'She will use it at the other store',gen_random_uuid());
 if pg_temp.svb_at(v,st) <> 9 or pg_temp.svb_at(v,st2) <> 9 or pg_temp.svb_held(inv,c,st) <> 1 or pg_temp.svb_held(inv,c,st2) <> 1 then
  raise exception 'B3 fixture: one voucher at each store, both the buyer''s'; end if;
 x:=pg_temp.svb_lines(inv);
 r:=preview_invoice_correction(inv,jsonb_build_object('items',x,'expected_edit_count',(select edit_count from invoices where id=inv)));
 select e2 into e from jsonb_array_elements(r->'effects') e2 where e2->>'area'='vouchers';
 if e->>'detail' is distinct from 'Removing the FOC takes back the unused vouchers it gave (Bundle Limited × 1, Bundle Limited × 1). They are given again as the corrected lines give them when the invoice is paid.'
    or e->'items' is distinct from '[]'::jsonb then
  raise exception 'B3 the summary did not take back the voucher moved to the buyer''s other store: %', e; end if;
 r:=correct_invoice(inv,x,jsonb_build_object('expected_edit_count',(select edit_count from invoices where id=inv)),'Not a giveaway',gen_random_uuid());
 if r->'foc_vouchers' is distinct from '{"taken_back":["Bundle Limited × 1","Bundle Limited × 1"],"kept_used":[]}'::jsonb
    or pg_temp.svb_at(v,st) <> 10 or pg_temp.svb_at(v,st2) <> 10 or pg_temp.svb_held(inv,null,null) <> 0
    or pg_temp.svb_rows(inv,st) <> 0 or pg_temp.svb_rows(inv,st2) <> 0 then
  raise exception 'B3 the FOC off: % ; stock % and % (expected 10 and 10), held %, rows % and %', r->'foc_vouchers',
    pg_temp.svb_at(v,st), pg_temp.svb_at(v,st2), pg_temp.svb_held(inv,null,null), pg_temp.svb_rows(inv,st), pg_temp.svb_rows(inv,st2); end if;
 perform pay_invoice(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',80)));
 if pg_temp.svb_at(v,st) <> 8 or pg_temp.svb_at(v,st2) <> 10 or pg_temp.svb_held(inv,c,st) <> 2 or pg_temp.svb_held(inv,null,null) <> 2
    or pg_temp.svb_rows(inv,st) <> 2 or pg_temp.svb_rows(inv,st2) <> 0
    or exists (select 1 from invoice_benefit_values where invoice_id=inv and cancelled_unused_value > 0) then
  raise exception 'B3 paid: stock % and % (expected 8 and 10), held at the invoice''s store % of % (expected 2 of 2), rows % and % (expected 2 and 0)',
    pg_temp.svb_at(v,st), pg_temp.svb_at(v,st2), pg_temp.svb_held(inv,c,st), pg_temp.svb_held(inv,null,null),
    pg_temp.svb_rows(inv,st), pg_temp.svb_rows(inv,st2); end if;
 if is417 then
  perform cancel_invoice_recorded(inv,'Mistake',gen_random_uuid());
  if pg_temp.svb_at(v,st) <> 10 or pg_temp.svb_at(v,st2) <> 10 then
   raise exception 'B3 cancelled (with 417): stock % and %, not 10 and 10', pg_temp.svb_at(v,st), pg_temp.svb_at(v,st2); end if;
 end if;

 raise notice 'PASS: a premium bundle''s vouchers, moved or given again on a reopening, are not counted as taken at Confirm FOC and not taken back when the FOC comes off another line, so the payment takes each unit once; a voucher moved to another store of the same customer is taken back and given again when paid';
end $$;

-- ═════ With 417: a voucher line raised or lowered while FOC, then cancel, reopen, cancel ═════
-- Two vouchers given free (8). The voucher line is raised to 3, or lowered
-- to 1, in a save that keeps the invoice FOC: nothing is given or taken
-- back for the change, so the customer still holds 2 and 8 stays out. Then
-- cancel (10), reopen and cancel again: 10 both times. With 416 and 417 as
-- of 10 Oct (417's file 0beaeaac...) the second cancel ends at 9 for the
-- raise (the reopening takes the line's 3 but gives back only the 2 held)
-- and 11 for the lowering (the cancel gives back the 2 held and the rows
-- too). The change is B03's, in 417's reopen_invoice and cancel: until it is
-- made, with those two functions as they are in that file, this prints
-- KNOWN FAULT notices; with any other version of them it must end at 10, or
-- it fails. Without 417 the cancel and reopen are not checked here.
do $$
declare o uuid:=gen_random_uuid(); st uuid; c uuid; vlim uuid; inv uuid; it uuid; x jsonb; mode text; n int;
 c1 int; c2 int; known boolean;
begin
 if to_regprocedure('public.invoice_voucher_stock_unrecorded(uuid,boolean)') is null then
  raise notice 'SKIP: without 417 the cancel and reopen of a FOC invoice whose voucher line changed are not checked here';
  return;
 end if;
 known := md5(pg_get_functiondef('public.reopen_invoice(uuid,text,uuid)'::regprocedure)) = 'c9fcab7adfccdaeba1eb8dee4134ba47'
       or md5(pg_get_functiondef('public.cancel_invoice_recorded(uuid,text,uuid)'::regprocedure)) = 'bba59740ea8134a257907cdaf5171991';
 insert into auth.users(id,email) values(o,'sold-voucher-reopen@tests.invalid');
 insert into profiles(id,full_name,email,role) values(o,'Owner','sold-voucher-reopen@tests.invalid','owner');
 perform set_config('request.jwt.claim.sub',o::text,true);
 insert into stores(name,code,country_code) values('Sold Voucher Reopen','SVRO','SG') returning id into st;
 insert into customers(full_name,phone) values('SVR Buyer','+61491575254') returning id into c;
 insert into vouchers(name,code,voucher_kind,selling_price,qty_type) values('Reopen Limited','SVROL','normal',40,'limited') returning id into vlim;
 insert into voucher_store_stock(voucher_id,store_id,current_qty) values(vlim,st,10);
 insert into voucher_store_prices(voucher_id,store_id,selling_price,available_at_store) values(vlim,st,40,true);
 foreach mode in array array['raised 2 to 3','lowered 2 to 1'] loop
  update voucher_store_stock set current_qty=10 where voucher_id=vlim and store_id=st;
  inv:=create_invoice_with_details(st,c,jsonb_build_array(jsonb_build_object('kind','voucher','voucher_id',vlim,'quantity',2)),
    jsonb_build_object('business_date',sg_today()::text));
  select id into it from invoice_items where invoice_id=inv;
  perform apply_line_foc(it,null,null,'Event giveaway');
  perform confirm_foc_invoice(inv,null);
  n := case when mode like 'raised%' then 3 else 1 end;
  x:=jsonb_build_array(jsonb_build_object('invoice_item_id',it,'kind','voucher','voucher_id',vlim,'quantity',n,'unit_price',40,
                                          'foc_quantity',n,'foc_reason','Event giveaway'));
  perform correct_invoice(inv,x,jsonb_build_object('expected_edit_count',(select edit_count from invoices where id=inv)),'Still a giveaway',gen_random_uuid());
  if (select status from invoices where id=inv) <> 'completed_foc'
     or (select current_qty from voucher_store_stock where voucher_id=vlim and store_id=st) <> 8 then
   raise exception 'R [%] fixture: still FOC with 8 in stock (stock %)', mode,
     (select current_qty from voucher_store_stock where voucher_id=vlim and store_id=st); end if;
  perform cancel_invoice_recorded(inv,'Mistake',gen_random_uuid());
  c1 := (select current_qty from voucher_store_stock where voucher_id=vlim and store_id=st);
  perform reopen_invoice(inv,'Customer came back',gen_random_uuid());
  perform cancel_invoice_recorded(inv,'Mistake again',gen_random_uuid());
  c2 := (select current_qty from voucher_store_stock where voucher_id=vlim and store_id=st);
  if c1 = 10 and c2 = 10 then
   raise notice 'PASS: [%] while FOC, then cancel, reopen and cancel: 10 both times', mode;
  elsif known then
   raise notice 'KNOWN FAULT (B03''s 417 reopen_invoice and cancel, with 416; measured, not a failure): [%] cancelled %, then reopened and cancelled again %; expected 10 both times', mode, c1, c2;
  else
   raise exception 'R [%] while FOC, then cancel, reopen and cancel: % then % (expected 10 both times)', mode, c1, c2;
  end if;
 end loop;
end $$;

-- ═════ Known faults outside 416 (B03's functions), measured, not asserted ═════
-- Reopening a cancelled completed FOC invoice, or one whose FOC was taken
-- off, takes its voucher stock twice: deduct_invoice_stock with a movement
-- row, then apply_reopened_invoice_vouchers. Expected 8 for two vouchers;
-- printed as KNOWN FAULT until batch B03 changes those functions.
do $$
declare o uuid:=gen_random_uuid(); st uuid; c uuid; pm uuid; vlim uuid; inv uuid; it uuid; x jsonb; mode text; got int;
begin
 insert into auth.users(id,email) values(o,'sold-voucher-known@tests.invalid');
 insert into profiles(id,full_name,email,role) values(o,'Owner','sold-voucher-known@tests.invalid','owner');
 perform set_config('request.jwt.claim.sub',o::text,true);
 insert into stores(name,code,country_code) values('Sold Voucher Known','SVK','SG') returning id into st;
 insert into customers(full_name,phone) values('SVK Buyer','+61491573087') returning id into c;
 insert into payment_methods(name,is_active) values('SVK Cash',true) returning id into pm;
 insert into vouchers(name,code,voucher_kind,selling_price,qty_type) values('Known Limited','SVKL','normal',40,'limited') returning id into vlim;
 insert into voucher_store_stock(voucher_id,store_id,current_qty) values(vlim,st,10);
 insert into voucher_store_prices(voucher_id,store_id,selling_price,available_at_store) values(vlim,st,40,true);
 foreach mode in array array['FOC, cancel, reopen','FOC off, cancel, reopen, pay'] loop
  update voucher_store_stock set current_qty=10 where voucher_id=vlim and store_id=st;
  inv:=create_invoice_with_details(st,c,jsonb_build_array(jsonb_build_object('kind','voucher','voucher_id',vlim,'quantity',2)),
    jsonb_build_object('business_date',sg_today()::text));
  select id into it from invoice_items where invoice_id=inv;
  perform apply_line_foc(it,null,null,'Event giveaway');
  perform confirm_foc_invoice(inv,null);
  if mode like 'FOC off%' then
   x:=jsonb_build_array(jsonb_build_object('invoice_item_id',it,'kind','voucher','voucher_id',vlim,'quantity',2,'unit_price',40,'foc_quantity',0));
   perform correct_invoice(inv,x,jsonb_build_object('expected_edit_count',(select edit_count from invoices where id=inv)),'Not a giveaway',gen_random_uuid());
  end if;
  perform cancel_invoice_recorded(inv,'Mistake',gen_random_uuid());
  perform reopen_invoice(inv,'Customer came back',gen_random_uuid());
  if mode like '%pay' then
   perform pay_invoice(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',80)));
  end if;
  got := (select current_qty from voucher_store_stock where voucher_id=vlim and store_id=st);
  if got = 8 then
   raise notice 'KNOWN FAULT (B03) now right: [%] voucher stock 8 for two vouchers', mode;
  else
   raise notice 'KNOWN FAULT (B03, not 416; measured, not a failure): [%] voucher stock % for two vouchers, expected 8 (reopening takes it with deduct_invoice_stock and again with apply_reopened_invoice_vouchers)', mode, got;
  end if;
 end loop;
end $$;
rollback;
