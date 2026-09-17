-- Reassigning an invoice moves that purchase's credit, and nobody else's.
--
-- 316 selected credit lots partly by the CATALOGUE package id, which a lot
-- carries in source_record_id. That matched every lot ever granted from that
-- package to anyone, so reassigning one customer's invoice emptied the wallets
-- of strangers who had bought the same product: A=700 B=0 C=700 became
-- A=0 B=1400 C=0. The preview said 1400 too.
--
-- Disposable database only; everything is rolled back.
begin;
do $$
declare own uuid:=gen_random_uuid(); st uuid; a uuid; b uuid; c uuid; d uuid; pm uuid;
 pkg uuid; svc uuid; own_p uuid; wpm_paid uuid; wpm_bonus uuid;
 inv_a uuid; inv_a2 uuid; inv_c uuid; it_a uuid; it_a2 uuid; r jsonb;
 c_lots uuid[]; c_before numeric; paid_lot uuid; bonus_lot uuid; spend uuid; n int;
begin
 insert into auth.users(id,email) values(own,'rop@t.invalid');
 insert into profiles(id,full_name,email,role) values(own,'Owner','rop@t.invalid','owner');
 perform set_config('request.jwt.claim.sub',own::text,true);
 insert into stores(name,code,country_code) values('ROP','ROP','SG') returning id into st;
 insert into customers(full_name,phone) values('Cust A','+6591510001') returning id into a;
 insert into customers(full_name,phone) values('Cust B','+6591510002') returning id into b;
 insert into customers(full_name,phone) values('Cust C','+6591510003') returning id into c;
 insert into customers(full_name,phone) values('Cust D','+6591510004') returning id into d;
 insert into payment_methods(name) values('ROP Cash') returning id into pm;
 select id into wpm_paid  from payment_methods where wallet_category='paid'  and is_system limit 1;
 select id into wpm_bonus from payment_methods where wallet_category='bonus' and is_system limit 1;
 insert into products(name,sku,product_type) values('ROP Own','ROP-OWN','own') returning id into own_p;
 insert into store_inventory(store_id,product_id,current_qty) values(st,own_p,50);
 perform set_product_prices(st,own_p,50,50,'available');
 svc:=(upsert_therapy_service(null,'ROP-PR','ROP Session',50,30,'per_hours',1,5,null,true,null)->>'id')::uuid;
 perform set_therapy_service_store(svc,st,true,null);

 insert into credit_packages(name,customer_price,paid_credit_amount,bonus_enabled,bonus_mode,bonus_value,
                             allow_product,allow_therapy,effective_from)
  values('ROP Package',500,500,true,'fixed',200,true,true,current_date) returning id into pkg;
 insert into credit_package_stores(package_id,store_id) values(pkg,st);

 -- A buys it twice; C buys the same catalogue package once.
 inv_a:=create_invoice(st,a,null,jsonb_build_array(jsonb_build_object('kind','credit_package','credit_package_id',pkg,'quantity',1)));
 perform pay_invoice(inv_a,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',500)));
 select id into it_a from invoice_items where invoice_id=inv_a;
 inv_a2:=create_invoice(st,a,null,jsonb_build_array(jsonb_build_object('kind','credit_package','credit_package_id',pkg,'quantity',1)));
 perform pay_invoice(inv_a2,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',500)));
 select id into it_a2 from invoice_items where invoice_id=inv_a2;
 inv_c:=create_invoice(st,c,null,jsonb_build_array(jsonb_build_object('kind','credit_package','credit_package_id',pkg,'quantity',1)));
 perform pay_invoice(inv_c,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',500)));

 select array_agg(id order by id) into c_lots from customer_credit_lots where customer_id=c;
 select coalesce(sum(remaining_amount),0) into c_before from customer_credit_lots where customer_id=c and status='active';

 -- ---- the preview describes only this invoice ------------------------------
 if (select coalesce(sum(units),0) from invoice_transferable_benefits(inv_a) where kind='credit' and movable)<>700 then
  raise exception 'The preview offers credit that does not belong to this invoice'; end if;

 -- ---- an explicit action is required ---------------------------------------
 begin
  perform correct_invoice(inv_a,
    jsonb_build_array(jsonb_build_object('invoice_item_id',it_a,'kind','credit_package','credit_package_id',pkg,'quantity',1)),
    jsonb_build_object('customer_id',b),'no action given',gen_random_uuid());
  raise exception 'A reassignment ran without saying what to do with the benefits';
 exception when others then
  if sqlerrm not like '%BENEFIT_ACTION_REQUIRED%' then raise; end if; end;

 -- ---- transfer: only A's first purchase moves ------------------------------
 r:=correct_invoice(inv_a,
      jsonb_build_array(jsonb_build_object('invoice_item_id',it_a,'kind','credit_package','credit_package_id',pkg,'quantity',1)),
      jsonb_build_object('customer_id',b,'benefit_action','transfer'),'reassign A to B',gen_random_uuid());

 if (select coalesce(sum(remaining_amount),0) from customer_credit_lots where customer_id=b and status='active')<>700 then
  raise exception 'B did not receive exactly this purchase''s 700'; end if;
 if (select coalesce(sum(remaining_amount),0) from customer_credit_lots where customer_id=a and status='active')<>700 then
  raise exception 'A''s OTHER purchase was swept up as well'; end if;
 if (select coalesce(sum(remaining_amount),0) from customer_credit_lots where customer_id=c and status='active')<>c_before then
  raise exception 'An unrelated customer''s balance changed'; end if;
 -- C's lots are untouched down to their identities and ledger
 if (select array_agg(id order by id) from customer_credit_lots where customer_id=c)<>c_lots then
  raise exception 'An unrelated customer''s lots were replaced'; end if;
 if exists(select 1 from customer_credit_ledger where customer_id=c and source_record_id=inv_a) then
  raise exception 'An unrelated customer got a ledger entry for this invoice'; end if;

 -- ---- paid and bonus separately, and eligibility intact --------------------
 select id into paid_lot  from customer_credit_lots where customer_id=b and category='paid'  and status='active';
 select id into bonus_lot from customer_credit_lots where customer_id=b and category='bonus' and status='active';
 if (select remaining_amount from customer_credit_lots where id=paid_lot)<>500 then raise exception 'Paid amount wrong'; end if;
 if (select remaining_amount from customer_credit_lots where id=bonus_lot)<>200 then raise exception 'Bonus amount wrong'; end if;
 if (select source_type from customer_credit_lots where id=paid_lot)<>'credit_package' then
  raise exception 'The transferred lot lost its origin'; end if;
 if not credit_lot_allows_category(paid_lot,'therapy_session') then
  raise exception 'Transferred paid credit lost its therapy eligibility'; end if;
 if credit_lot_allows_category(paid_lot,'own_product') then
  raise exception 'Transferred paid credit gained product eligibility it never had'; end if;
 if not credit_lot_allows_category(bonus_lot,'own_product')
    or not credit_lot_allows_category(bonus_lot,'third_party_product') then
  raise exception 'Transferred bonus credit lost its product eligibility'; end if;
 if credit_lot_allows_category(bonus_lot,'therapy_session') then
  raise exception 'Transferred bonus credit gained therapy eligibility'; end if;

 -- it actually spends on a real therapy service
 spend:=create_invoice(st,b,null,jsonb_build_array(jsonb_build_object('kind','therapy','therapy_service_id',svc,'quantity',1)));
 perform record_invoice_payment(spend,jsonb_build_array(jsonb_build_object('payment_method_id',wpm_paid,'amount',50)),gen_random_uuid());
 if (select remaining_amount from customer_credit_lots where id=paid_lot)<>450 then
  raise exception 'The transferred paid credit did not fund the therapy session'; end if;

 -- ---- a partly spent lot stops the next hop rather than moving silently ----
 begin
  perform correct_invoice(inv_a,
    jsonb_build_array(jsonb_build_object('invoice_item_id',it_a,'kind','credit_package','credit_package_id',pkg,'quantity',1)),
    jsonb_build_object('customer_id',d,'benefit_action','transfer'),'reassign B to D',gen_random_uuid());
  raise exception 'A partly spent lot was moved without review';
 exception when others then
  if sqlerrm not like '%already been used%' then raise; end if;
  if sqlerrm not like '%Partly spent%' then
   raise exception 'The refusal did not name what is in the way: %', sqlerrm; end if; end;
 -- and the refusal changed nothing
 if (select customer_id from invoices where id=inv_a)<>b then
  raise exception 'A refused correction still moved the invoice'; end if;
 if (select remaining_amount from customer_credit_lots where id=paid_lot)<>450 then
  raise exception 'A refused correction still touched the credit'; end if;

 -- ---- a second hop of an UNSPENT lot keeps provenance and eligibility ------
 declare inv_b uuid; it_b uuid; moved uuid; begin
  inv_b:=create_invoice(st,b,null,jsonb_build_array(jsonb_build_object('kind','credit_package','credit_package_id',pkg,'quantity',1)));
  perform pay_invoice(inv_b,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',500)));
  select id into it_b from invoice_items where invoice_id=inv_b;
  perform correct_invoice(inv_b,
    jsonb_build_array(jsonb_build_object('invoice_item_id',it_b,'kind','credit_package','credit_package_id',pkg,'quantity',1)),
    jsonb_build_object('customer_id',d,'benefit_action','transfer'),'hop one',gen_random_uuid());
  perform correct_invoice(inv_b,
    jsonb_build_array(jsonb_build_object('invoice_item_id',it_b,'kind','credit_package','credit_package_id',pkg,'quantity',1)),
    jsonb_build_object('customer_id',c,'benefit_action','transfer'),'hop two',gen_random_uuid());
  select id into moved from customer_credit_lots
   where customer_id=c and category='paid' and status='active' and reassigned_from_lot_id is not null;
  if moved is null then raise exception 'The twice-reassigned lot was not found'; end if;
  if (select source_type from customer_credit_lots where id=moved)<>'credit_package' then
   raise exception 'Two hops lost the origin'; end if;
  if not credit_lot_allows_category(moved,'therapy_session') then
   raise exception 'Two hops lost therapy eligibility'; end if;
  -- and it is still reachable from its invoice
  if not exists(select 1 from invoice_credit_lot_ids(inv_b) where lot_id=moved) then
   raise exception 'A twice-reassigned lot is no longer reachable from its invoice'; end if;
 end;

 -- ---- keep: nothing moves --------------------------------------------------
 r:=correct_invoice(inv_a2,
      jsonb_build_array(jsonb_build_object('invoice_item_id',it_a2,'kind','credit_package','credit_package_id',pkg,'quantity',1)),
      jsonb_build_object('customer_id',d,'benefit_action','keep'),'move the invoice only',gen_random_uuid());
 if (select customer_id from invoices where id=inv_a2)<>d then
  raise exception 'Keep did not change the invoice customer'; end if;
 if (select coalesce(sum(remaining_amount),0) from customer_credit_lots where customer_id=a and status='active')<>700 then
  raise exception 'Keep moved the benefits anyway'; end if;
 -- and the invoice can still find them
 if (select count(*) from invoice_credit_lot_ids(inv_a2))<>2 then
  raise exception 'Kept benefits are invisible to their source invoice'; end if;

 raise notice 'PASS: a reassignment moves only the lots that purchase issued, unrelated customers and the same customer''s other purchases are untouched, paid and bonus keep their separate eligibility and spend correctly, an explicit action is required, and keep leaves ownership alone while staying visible to the invoice';
end $$;
rollback;
