-- Reassigning an invoice moves the benefits it produced, and only those.
--
-- Unused benefits follow the invoice. Anything already used stops the whole
-- correction and names what is in the way, so it goes through the existing
-- Owner/Manager benefit-transfer review instead of moving silently.
--
-- Disposable database only; everything is rolled back.
begin;
do $$
declare own uuid:=gen_random_uuid(); st uuid; c1 uuid; c2 uuid; other uuid; pm uuid;
 v1 uuid; promo uuid; inv uuid; it uuid; n int; r jsonb; unrelated uuid; unrelated_lot uuid;
begin
 insert into auth.users(id,email) values(own,'rab@tests.invalid');
 insert into profiles(id,full_name,email,role) values(own,'Owner','rab@tests.invalid','owner');
 perform set_config('request.jwt.claim.sub',own::text,true);
 insert into stores(name,code,country_code) values('RAB Store','RAB','SG') returning id into st;
 insert into customers(full_name,phone) values('RAB One','+6598935001') returning id into c1;
 insert into customers(full_name,phone) values('RAB Two','+6598935002') returning id into c2;
 insert into payment_methods(name) values('RAB Cash') returning id into pm;
 insert into vouchers(name,code,voucher_kind,qty_type,selling_price,is_active)
  values('RAB Facial','RABF','normal','limited',50,true) returning id into v1;
 insert into voucher_store_stock(voucher_id,store_id,current_qty) values(v1,st,100);
 insert into promotions(name,code,promo_type,fixed_price,is_active)
  values('RAB Promo','RABP','bundle',100,true) returning id into promo;
 insert into promotion_items(promotion_id,item_type,voucher_id,quantity) values(promo,'voucher',v1,2);
 insert into promotion_store_prices(promotion_id,store_id,selling_price,available_at_store)
  values(promo,st,100,true);

 -- An UNRELATED balance the old customer owns, which must never move.
 unrelated_lot:=grant_customer_credit(c1,'paid',250,'manual',null,st,sg_today(),null,'unrelated',null,null,own,null);

 inv:=create_invoice(st,c1,null,jsonb_build_array(jsonb_build_object('kind','promotion','promotion_id',promo,'quantity',1)));
 perform pay_invoice(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',100)));
 select id into it from invoice_items where invoice_id=inv;

 -- ---- what a reassignment would do, before it happens ---------------------
 select count(*) into n from invoice_transferable_benefits(inv) where kind='voucher' and movable;
 if n<>1 then raise exception 'Expected one movable voucher record, got %', n; end if;

 -- ---- the move ------------------------------------------------------------
 r:=correct_invoice(inv,
      jsonb_build_array(jsonb_build_object('invoice_item_id',it,'kind','promotion','promotion_id',promo,'quantity',1)),
      jsonb_build_object('customer_id',c2),'reassign',gen_random_uuid());

 if exists(select 1 from customer_reward_vouchers where source_id=it and customer_id<>c2) then
  raise exception 'The vouchers did not follow the invoice'; end if;
 -- the unrelated balance stayed put
 if (select customer_id from customer_credit_lots where id=unrelated_lot)<>c1 then
  raise exception 'An unrelated customer balance was moved'; end if;
 -- nothing was duplicated and no stock moved again
 if (select count(*) from customer_reward_vouchers where source_id=it)<>1 then
  raise exception 'The transfer duplicated a voucher record'; end if;
 if (select current_qty from voucher_store_stock where voucher_id=v1 and store_id=st)<>98 then
  raise exception 'Reassignment moved stock'; end if;
 -- the original source reference survived
 if (select source_type from customer_reward_vouchers where source_id=it)<>'invoice_promotion_voucher' then
  raise exception 'The original issuance reference was lost'; end if;

 -- ---- a FULLY used benefit stays behind, and does not block ----------------
 -- There is nothing left to move and nothing to strand, so the usage simply
 -- stays where it happened and the correction is allowed to proceed.
 update customer_reward_vouchers set status='redeemed', redeemed_at=now() where source_id=it;
 if (select count(*) from invoice_transferable_benefits(inv) where kind='voucher' and blocking)<>0 then
  raise exception 'A fully redeemed voucher is blocking the correction'; end if;
 r:=correct_invoice(inv,
      jsonb_build_array(jsonb_build_object('invoice_item_id',it,'kind','promotion','promotion_id',promo,'quantity',1)),
      jsonb_build_object('customer_id',c1),'move back',gen_random_uuid());
 if (select customer_id from customer_reward_vouchers where source_id=it)<>c2 then
  raise exception 'A redeemed voucher was moved to the new customer'; end if;

 -- ---- a PARTLY used benefit does stop it, and says what is in the way ------
 declare lot uuid; begin
  lot:=grant_customer_credit(c1,'paid',100,'invoice_line',it,st,sg_today(),null,'partly used',null,null,own,null);
  update customer_credit_lots set remaining_amount=40 where id=lot;
  if (select count(*) from invoice_transferable_benefits(inv) where kind='credit' and blocking)<>1 then
   raise exception 'A partly spent credit lot is not blocking'; end if;
  begin
   r:=correct_invoice(inv,
        jsonb_build_array(jsonb_build_object('invoice_item_id',it,'kind','promotion','promotion_id',promo,'quantity',1)),
        jsonb_build_object('customer_id',c2),'move again',gen_random_uuid());
   raise exception 'A partly spent benefit was moved silently';
  exception when others then
   if sqlerrm not like '%already been used%' then raise; end if;
   if sqlerrm not like '%Partly spent%' then
    raise exception 'The refusal did not say what is in the way: %', sqlerrm; end if;
  end;
  -- and the refusal left everything as it was
  if (select customer_id from invoices where id=inv)<>c1 then
   raise exception 'A refused correction still changed the customer'; end if;
  if (select remaining_amount from customer_credit_lots where id=lot)<>40 then
   raise exception 'A refused correction still touched the credit'; end if;
 end;

 raise notice 'PASS: unused benefits follow the invoice without duplicating or moving stock, unrelated balances stay put, a fully used benefit stays behind without blocking, and a partly used one stops the correction naming what is in the way';
end $$;
rollback;
