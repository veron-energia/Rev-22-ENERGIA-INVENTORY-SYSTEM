-- Vouchers sold inside a promotion must have a recorded owner.
--
-- A voucher LINE has always issued properly. A voucher delivered inside a
-- PROMOTION got no customer_reward_vouchers row and no invoice_benefit_values
-- row, so invoice_untracked_voucher() reported it untracked and correct_invoice
-- refused every customer or store change on the invoice — the reported
-- "Review the original issued voucher units..." refusal. The guard was right;
-- the issuance was incomplete.
--
-- Disposable database only; everything is rolled back.
begin;
do $$
declare own uuid:=gen_random_uuid(); st uuid; c1 uuid; c2 uuid; pm uuid;
 v1 uuid; v2 uuid; promo uuid; inv uuid; it uuid; n int; r jsonb; stock_before int;
begin
 insert into auth.users(id,email) values(own,'pvo@tests.invalid');
 insert into profiles(id,full_name,email,role) values(own,'Owner','pvo@tests.invalid','owner');
 perform set_config('request.jwt.claim.sub',own::text,true);
 insert into stores(name,code,country_code) values('PVO Store','PVO','SG') returning id into st;
 insert into customers(full_name,phone) values('PVO One','+6598934001') returning id into c1;
 insert into customers(full_name,phone) values('PVO Two','+6598934002') returning id into c2;
 insert into payment_methods(name) values('PVO Cash') returning id into pm;
 insert into vouchers(name,code,voucher_kind,qty_type,selling_price,is_active)
  values('PVO Facial','PVOF','normal','limited',50,true) returning id into v1;
 insert into vouchers(name,code,voucher_kind,qty_type,selling_price,is_active)
  values('PVO Massage','PVOM','normal','limited',30,true) returning id into v2;
 insert into voucher_store_stock(voucher_id,store_id,current_qty) values(v1,st,50),(v2,st,50);

 -- A promotion carrying two voucher types: the shape that failed.
 insert into promotions(name,code,promo_type,fixed_price,is_active)
  values('PVO Promo','PVOP','bundle',120,true) returning id into promo;
 insert into promotion_items(promotion_id,item_type,voucher_id,quantity)
  values(promo,'voucher',v1,2),(promo,'voucher',v2,1);
 insert into promotion_store_prices(promotion_id,store_id,selling_price,available_at_store)
  values(promo,st,120,true);

 inv:=create_invoice(st,c1,null,jsonb_build_array(jsonb_build_object(
        'kind','promotion','promotion_id',promo,'quantity',1)));
 select current_qty into stock_before from voucher_store_stock where voucher_id=v1 and store_id=st;
 perform pay_invoice(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',120)));
 select id into it from invoice_items where invoice_id=inv;

 -- ---- the owner is now recorded ------------------------------------------
 select count(*) into n from customer_reward_vouchers
  where source_type='invoice_promotion_voucher' and source_id=it;
 if n<>2 then raise exception 'Expected an ownership record per voucher type, got %', n; end if;
 if (select sum(quantity) from customer_reward_vouchers where source_id=it)<>3 then
  raise exception 'The recorded units do not match what the promotion sold'; end if;
 if (select customer_id from customer_reward_vouchers where source_id=it limit 1)<>c1 then
  raise exception 'The vouchers were recorded against the wrong customer'; end if;

 -- evidence exists, so the line is no longer untracked
 if invoice_untracked_voucher(inv) then
  raise exception 'The promotion line is still reported as untracked'; end if;

 -- the paid value is split by units and totals the line value
 if (select round(sum(paid_value),2) from invoice_benefit_values where invoice_item_id=it)
    <> round(invoice_discounted_line_value(it),2) then
  raise exception 'The paid value split does not add up to the line value'; end if;

 -- ---- and stock was NOT taken twice ---------------------------------------
 if (select current_qty from voucher_store_stock where voucher_id=v1 and store_id=st)
    <> stock_before - 2 then
  raise exception 'Voucher stock moved more than once'; end if;

 -- ---- issuing again changes nothing ---------------------------------------
 if issue_sold_vouchers_for_invoice(inv)<>0 then
  raise exception 'A replayed issuance created more records'; end if;
 select count(*) into n from customer_reward_vouchers where source_id=it;
 if n<>2 then raise exception 'A replayed issuance duplicated ownership records'; end if;

 -- ---- the correction that used to be refused now works ---------------------
 r:=correct_invoice(inv,
      jsonb_build_array(jsonb_build_object('invoice_item_id',it,'kind','promotion','promotion_id',promo,'quantity',1)),
      jsonb_build_object('customer_id',c2,'benefit_action','transfer'),'move to the right customer',gen_random_uuid());
 if (select customer_id from invoices where id=inv)<>c2 then
  raise exception 'The customer was not reassigned'; end if;

 -- and the vouchers went with it, without being duplicated or reset
 if (select count(*) from customer_reward_vouchers where source_id=it)<>2 then
  raise exception 'Reassignment duplicated the voucher records'; end if;
 if (select sum(quantity) from customer_reward_vouchers where source_id=it)<>3 then
  raise exception 'Reassignment changed the voucher quantities'; end if;

 -- the holders changed, and only these records did
 if exists(select 1 from customer_reward_vouchers where source_id=it and customer_id<>c2) then
  raise exception 'A voucher stayed with the previous customer'; end if;
 if (select store_id from customer_reward_vouchers where source_id=it limit 1)
    <> (select store_id from invoices where id=inv) then
  raise exception 'The voucher store does not match the invoice'; end if;

 raise notice 'PASS: promotion vouchers get a recorded owner at sale, evidence adds up to the line value, stock moves once, replays change nothing, and the customer correction that was refused now succeeds';
end $$;
rollback;
