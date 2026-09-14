-- The invoice's affiliate decides the invoice's affiliate commission.
--
-- Covers the reported None-to-affiliate case and the transitions around it,
-- including the one that is easy to get wrong: an explicit "None" must not
-- quietly fall back to the customer's own referrer.
--
-- Disposable database only; everything is rolled back.
begin;
do $$
declare own uuid:=gen_random_uuid(); st uuid; buyer uuid; refr uuid; ca uuid; cb uuid;
 affr uuid; affa uuid; affb uuid; pm uuid; prod uuid; inv uuid; it uuid; r jsonb; n int;
 payout uuid; before_paid numeric;
begin
 insert into auth.users(id,email) values(own,'afc@tests.invalid');
 insert into profiles(id,full_name,email,role) values(own,'Owner','afc@tests.invalid','owner');
 perform set_config('request.jwt.claim.sub',own::text,true);
 insert into stores(name,code,country_code) values('AFC Store','AFC','SG') returning id into st;
 insert into customers(full_name,phone) values('AFC Referrer','+6598937000') returning id into refr;
 -- the buyer HAS a profile referrer throughout, which must never win over an explicit choice
 insert into customers(full_name,phone,referred_by) values('AFC Buyer','+6598937001',refr) returning id into buyer;
 insert into customers(full_name,phone) values('Aishah Angullia','+6598937002') returning id into ca;
 insert into customers(full_name,phone) values('AFC Second','+6598937003') returning id into cb;
 insert into customer_affiliates(customer_id,status,store_id,activated_at) values(refr,'active',st,now()) returning id into affr;
 insert into customer_affiliates(customer_id,status,store_id,activated_at) values(ca,'active',st,now()) returning id into affa;
 insert into customer_affiliates(customer_id,status,store_id,activated_at) values(cb,'active',st,now()) returning id into affb;
 insert into payment_methods(name) values('AFC Cash') returning id into pm;
 insert into products(name,sku,product_type) values('AFC Item','AFC-1','own') returning id into prod;
 insert into store_inventory(store_id,product_id,current_qty) values(st,prod,50);
 perform set_product_prices(st,prod,100,100,'available');

 inv:=create_invoice(st,buyer,null,jsonb_build_array(jsonb_build_object('kind','product','product_id',prod,'quantity',1)));
 perform pay_invoice(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',100)));
 select id into it from invoice_items where invoice_id=inv;

 -- the starting point: no explicit affiliate, so the profile referrer is credited
 if (select referrer_customer_id from commissions where invoice_id=inv and status='earned' and tier='tier1')<>refr then
  raise exception 'The profile referrer should be credited before any explicit choice'; end if;
 if diagnose_invoice_affiliate(inv)->>'resolution'<>'customer_profile_referrer' then
  raise exception 'The diagnosis does not report the fallback'; end if;

 -- ---- None -> Aishah (the reported case) ----------------------------------
 r:=correct_invoice(inv,jsonb_build_array(jsonb_build_object('invoice_item_id',it,'kind','product','product_id',prod,'quantity',1)),
      jsonb_build_object('affiliate_id',affa),'credit Aishah',gen_random_uuid());
 if (select affiliate_id from invoices where id=inv)<>affa then raise exception 'The affiliate was not persisted'; end if;
 if not (select affiliate_selection_explicit from invoices where id=inv) then
  raise exception 'The selection was not recorded as explicit'; end if;
 select count(*) into n from commissions where invoice_id=inv and status='earned' and referrer_customer_id=ca;
 if n<>1 then raise exception 'Expected one earned commission for Aishah, got %', n; end if;
 if (select count(*) from commissions where invoice_id=inv and status='earned' and referrer_customer_id=refr)<>0 then
  raise exception 'The previous referrer is still earning'; end if;
 if diagnose_invoice_affiliate(inv)->>'resolution'<>'explicit_affiliate' then
  raise exception 'The diagnosis does not report the explicit choice'; end if;

 -- ---- A -> B ---------------------------------------------------------------
 r:=correct_invoice(inv,jsonb_build_array(jsonb_build_object('invoice_item_id',it,'kind','product','product_id',prod,'quantity',1)),
      jsonb_build_object('affiliate_id',affb),'switch to B',gen_random_uuid());
 if (select count(*) from commissions where invoice_id=inv and status='earned' and referrer_customer_id=cb)<>1 then
  raise exception 'B is not earning after the switch'; end if;
 if (select count(*) from commissions where invoice_id=inv and status='earned' and referrer_customer_id=ca)<>0 then
  raise exception 'A is still earning after the switch'; end if;

 -- ---- B -> explicit None ---------------------------------------------------
 r:=correct_invoice(inv,jsonb_build_array(jsonb_build_object('invoice_item_id',it,'kind','product','product_id',prod,'quantity',1)),
      jsonb_build_object('affiliate_id',null),'no affiliate',gen_random_uuid());
 if (select count(*) from commissions where invoice_id=inv and status='earned')<>0 then
  raise exception 'An explicit None still earned commission'; end if;
 if (select count(*) from commissions where invoice_id=inv and status='earned' and referrer_customer_id=refr)<>0 then
  raise exception 'An explicit None fell back to the customer profile referrer'; end if;
 if diagnose_invoice_affiliate(inv)->>'resolution'<>'explicit_none' then
  raise exception 'The diagnosis does not report the explicit none'; end if;

 -- ---- back to A, then saving A again creates no duplicate ------------------
 r:=correct_invoice(inv,jsonb_build_array(jsonb_build_object('invoice_item_id',it,'kind','product','product_id',prod,'quantity',1)),
      jsonb_build_object('affiliate_id',affa),'back to A',gen_random_uuid());
 r:=correct_invoice(inv,jsonb_build_array(jsonb_build_object('invoice_item_id',it,'kind','product','product_id',prod,'quantity',1)),
      jsonb_build_object('affiliate_id',affa),'same again',gen_random_uuid());
 if (select count(*) from commissions where invoice_id=inv and status='earned')<>1 then
  raise exception 'Saving the same affiliate duplicated the commission'; end if;

 -- ---- the customer's profile referral is never touched ---------------------
 if (select referred_by from customers where id=buyer)<>refr then
  raise exception 'Correcting the invoice affiliate changed the customer profile referral'; end if;

 -- ---- a correction that omits the field changes nothing, and says so -------
 r:=preview_invoice_correction(inv,jsonb_build_object('notes','just a note'));
 if not exists(select 1 from jsonb_array_elements(r->'effects') e
                where e->>'area'='affiliate' and e->>'change'='unchanged') then
  raise exception 'The preview does not report an omitted affiliate as unchanged'; end if;
 r:=correct_invoice(inv,jsonb_build_array(jsonb_build_object('invoice_item_id',it,'kind','product','product_id',prod,'quantity',1)),
      jsonb_build_object('notes','just a note'),'note only',gen_random_uuid());
 if (select affiliate_id from invoices where id=inv)<>affa then
  raise exception 'A note-only correction changed the affiliate'; end if;
 if (select count(*) from commissions where invoice_id=inv and status='earned')<>1 then
  raise exception 'A note-only correction disturbed the commission'; end if;

 -- ---- an already-paid commission is adjusted, not moved --------------------
 insert into commission_payouts(id,payout_month,referrer_customer_id,total_tier1,total_tier2,total_amount,status,paid_at)
  values(gen_random_uuid(),date_trunc('month',now())::date,ca,15,0,15,'paid',now()) returning id into payout;
 update commissions set payout_id=payout, status='paid'
  where invoice_id=inv and status='earned' and referrer_customer_id=ca;
 r:=correct_invoice(inv,jsonb_build_array(jsonb_build_object('invoice_item_id',it,'kind','product','product_id',prod,'quantity',1)),
      jsonb_build_object('affiliate_id',affb),'switch after payout',gen_random_uuid());
 -- the payout record survives, attached to the person actually paid
 if (select count(*) from commissions where invoice_id=inv and payout_id=payout and referrer_customer_id=ca)<>1 then
  raise exception 'The recorded payout was removed or moved to another affiliate'; end if;
 -- and a balancing adjustment exists rather than a silent recovery
 if (select count(*) from commissions where invoice_id=inv and adjusts_commission_id is not null and commission_amount<0)<>1 then
  raise exception 'No balancing adjustment was raised for the paid commission'; end if;
 -- the new affiliate earns going forward
 if (select count(*) from commissions where invoice_id=inv and status='earned' and referrer_customer_id=cb)<>1 then
  raise exception 'The new affiliate is not earning after a paid switch'; end if;

 raise notice 'PASS: an explicit invoice affiliate overrides the profile referrer in every direction, explicit None earns nothing without falling back, repeats do not duplicate, a note-only save leaves it alone and says so, and a paid commission is adjusted rather than moved';
end $$;
rollback;
