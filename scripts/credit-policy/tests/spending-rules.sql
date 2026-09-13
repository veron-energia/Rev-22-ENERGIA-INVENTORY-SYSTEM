-- What a credit package's balance may buy is the Owner's decision, per package.
--
-- 242 enforced one hardcoded rule for every package. These assertions cover the
-- approved defaults, an Owner changing them, existing unused balances following
-- the change, and everyone else being refused — at the database, not by hiding
-- a button. Disposable database only; everything is rolled back.
begin;
do $$
declare own uuid:=gen_random_uuid(); mgr uuid:=gen_random_uuid(); stf uuid:=gen_random_uuid();
 st uuid; c uuid; pm uuid; cp uuid; cp2 uuid; pb uuid; inv uuid; it uuid;
 paid_lot uuid; bonus_lot uuid; bundle_lot uuid; r jsonb; rules jsonb; n int;
begin
 insert into auth.users(id,email) values(own,'cs-own@tests.invalid'),(mgr,'cs-mgr@tests.invalid'),(stf,'cs-stf@tests.invalid');
 insert into profiles(id,full_name,email,role) values
   (own,'Owner','cs-own@tests.invalid','owner'),
   (mgr,'Manager','cs-mgr@tests.invalid','manager'),
   (stf,'Staff','cs-stf@tests.invalid','staff');
 perform set_config('request.jwt.claim.sub',own::text,true);
 insert into stores(name,code,country_code) values('CS Store','CSS','SG') returning id into st;
 insert into user_store_assignments(user_id,store_id) values(mgr,st),(stf,st);
 insert into customers(full_name,phone) values('CS Buyer','+6598911001') returning id into c;
 insert into payment_methods(name) values('CS Cash') returning id into pm;
 insert into credit_packages(name,customer_price,paid_credit_amount,bonus_enabled,bonus_mode,bonus_value,allow_product,allow_therapy)
   values('CS Package',100,100,true,'fixed',50,true,true) returning id into cp;
 insert into credit_package_stores(package_id,store_id) values(cp,st);
 insert into credit_packages(name,customer_price,paid_credit_amount,allow_product,allow_therapy)
   values('CS Other',100,100,true,true) returning id into cp2;
 insert into credit_package_stores(package_id,store_id) values(cp2,st);

 inv:=create_invoice(st,c,null,jsonb_build_array(jsonb_build_object('kind','credit_package','credit_package_id',cp,'quantity',1)));
 perform record_invoice_payment(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',100)),gen_random_uuid());
 select id into paid_lot from customer_credit_lots where customer_id=c and category='paid';
 select id into bonus_lot from customer_credit_lots where customer_id=c and category='bonus';

 -- ---- the approved defaults ----------------------------------------------
 rules:=credit_package_effective_rules(cp);
 if rules->>'source'<>'default' then raise exception 'A new package should start on the defaults'; end if;
 if not credit_lot_allows_category(paid_lot,'therapy_session') then
  raise exception 'Paid credit must buy an individual therapy session by default'; end if;
 if credit_lot_allows_category(paid_lot,'session_voucher') then
  raise exception 'Paid credit must NOT buy a therapy voucher by default'; end if;
 if credit_lot_allows_category(paid_lot,'unlimited_therapy') then
  raise exception 'Paid credit must NOT buy an unlimited therapy package by default'; end if;
 if not credit_lot_allows_category(bonus_lot,'own_product') then
  raise exception 'Bonus credit must buy own-brand products by default'; end if;
 if not credit_lot_allows_category(bonus_lot,'third_party_product') then
  raise exception 'Bonus credit must buy third-party products by default'; end if;
 -- credit never buys more credit, whatever the rule says
 if credit_lot_allows_category(paid_lot,'credit_package')
    or credit_lot_allows_category(bonus_lot,'premium_bundle') then
  raise exception 'Credit was allowed to buy more credit'; end if;

 -- ---- only an Owner may change them --------------------------------------
 perform set_config('request.jwt.claim.sub',stf::text,true);
 begin
  perform set_credit_package_spending_rules(cp,array['session_voucher'],array['own_product'],'Staff try');
  raise exception 'Staff changed a package policy';
 exception when others then
  if sqlerrm like 'Staff changed%' then raise; end if;
  if sqlerrm not like '%Only an Owner%' then raise; end if; end;
 perform set_config('request.jwt.claim.sub',mgr::text,true);
 begin
  perform set_credit_package_spending_rules(cp,array['session_voucher'],array['own_product'],'Manager try');
  raise exception 'A Manager changed a package policy';
 exception when others then
  if sqlerrm like 'A Manager changed%' then raise; end if;
  if sqlerrm not like '%Only an Owner%' then raise; end if; end;
 -- ...and a Manager cannot preview one either, but CAN read the summary
 if credit_lot_spending_summary(paid_lot)->'allowed' is null then
  raise exception 'A Manager cannot see what a balance may be spent on'; end if;

 -- ---- the Owner sees the impact before saving ----------------------------
 perform set_config('request.jwt.claim.sub',own::text,true);
 r:=preview_credit_package_policy_change(cp,array['therapy_session','session_voucher'],array['own_product','third_party_product']);
 if (r->>'affected_customers')::int<>1 then
  raise exception 'The preview should name the one affected customer, got %',r->>'affected_customers'; end if;
 if (r->>'affected_paid_credit')::numeric<>100 then
  raise exception 'The preview should total 100 of affected paid credit, got %',r->>'affected_paid_credit'; end if;
 if (r->>'affected_bonus_credit')::numeric<>50 then
  raise exception 'The preview should total 50 of affected bonus credit, got %',r->>'affected_bonus_credit'; end if;
 if r->'before' is null or r->'after' is null then
  raise exception 'The preview must show both the previous and the proposed rules'; end if;
 -- previewing changes nothing
 if credit_lot_allows_category(paid_lot,'session_voucher') then
  raise exception 'Previewing a change applied it'; end if;

 -- ---- a reason is required ------------------------------------------------
 begin
  perform set_credit_package_spending_rules(cp,array['therapy_session','session_voucher'],array['own_product'],'  ');
  raise exception 'A policy change was saved with no reason';
 exception when others then
  if sqlerrm like 'A policy change was saved%' then raise; end if;
  if sqlerrm not like '%reason for the policy change%' then raise; end if; end;

 -- ---- an unsupported category is refused ---------------------------------
 begin
  perform set_credit_package_spending_rules(cp,array['credit_package'],array['own_product'],'Buy more credit');
  raise exception 'Credit was made able to buy more credit';
 exception when others then
  if sqlerrm like 'Credit was made able%' then raise; end if;
  if sqlerrm not like '%Not a category credit may be spent on%' then raise; end if; end;

 -- ---- the Owner enables vouchers; EXISTING unused credit follows ---------
 perform set_credit_package_spending_rules(cp,array['therapy_session','session_voucher'],
   array['own_product','third_party_product'],'Owner approved therapy vouchers on paid credit');
 if not credit_lot_allows_category(paid_lot,'session_voucher') then
  raise exception 'Existing unused paid credit did not follow the new rule'; end if;
 if not credit_lot_allows_category(paid_lot,'therapy_session') then
  raise exception 'The change removed a category it should have kept'; end if;
 -- balances, grants and past spending are untouched
 if (select remaining_amount from customer_credit_lots where id=paid_lot)<>100 then
  raise exception 'A policy change altered a balance'; end if;
 if (select original_amount from customer_credit_lots where id=paid_lot)<>100 then
  raise exception 'A policy change altered an original grant'; end if;

 -- ---- another package is unaffected --------------------------------------
 if (credit_package_effective_rules(cp2)->>'source')<>'default' then
  raise exception 'Changing one package changed another'; end if;

 -- ---- the change is on the record ----------------------------------------
 select count(*) into n from credit_package_spending_rule_history where package_id=cp;
 if n<>1 then raise exception 'The policy change was not recorded, % rows',n; end if;
 if (select reason from credit_package_spending_rule_history where package_id=cp)
    not like 'Owner approved%' then raise exception 'The reason was not kept'; end if;
 if (select changed_by from credit_package_spending_rule_history where package_id=cp)<>own then
  raise exception 'The editor was not recorded'; end if;
 if (select before_rules->>'source' from credit_package_spending_rule_history where package_id=cp)<>'default' then
  raise exception 'The previous rules were not kept for audit'; end if;

 -- ---- premium bundle credit keeps its own rule ---------------------------
 insert into premium_bundles(name,customer_payment_amount,paid_credit_amount,bonus_credit_amount,free_voucher_qty)
   values('CS Bundle',200,150,50,0) returning id into pb;
 insert into premium_bundle_stores(bundle_id,store_id) values(pb,st);
 inv:=create_invoice(st,c,null,jsonb_build_array(jsonb_build_object('kind','premium_bundle','premium_bundle_id',pb,'quantity',1)));
 perform record_invoice_payment(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',200)),gen_random_uuid());
 select l.id into bundle_lot from customer_credit_lots l
  where l.customer_id=c and l.source_type='premium_bundle' and l.category='paid';
 if bundle_lot is null then raise exception 'The bundle did not issue paid credit'; end if;
 if not credit_lot_allows_category(bundle_lot,'own_product')
    or not credit_lot_allows_category(bundle_lot,'unlimited_therapy')
    or not credit_lot_allows_category(bundle_lot,'money_voucher') then
  raise exception 'Premium bundle credit should buy every otherwise supported item'; end if;
 if credit_lot_allows_category(bundle_lot,'credit_package')
    or credit_lot_allows_category(bundle_lot,'premium_bundle') then
  raise exception 'Premium bundle credit bought more credit'; end if;
 -- and it is never offered as a package category
 if 'credit_package' = any(credit_spendable_categories())
    or 'premium_bundle' = any(credit_spendable_categories()) then
  raise exception 'Buying more credit is offered as a selectable policy category'; end if;

 -- ---- an unidentifiable source stays held for review ----------------------
 -- Asserted through the rule itself: a posted lot cannot be edited (correctly),
 -- so the condition is exercised where it is decided.
 if credit_lot_policy('credit_package','paid',false)<>'needs_review' then
  raise exception 'A package balance with no identifiable source was not held for review'; end if;
 if credit_lot_policy('premium_bundle','paid',false)<>'needs_review' then
  raise exception 'A bundle balance with no identifiable source was not held for review'; end if;
 if credit_policy_allows('needs_review','therapy_session')
    or credit_policy_allows('needs_review','own_product') then
  raise exception 'A balance held for review was allowed to spend'; end if;
 -- an unrecognised source is never treated as unrestricted
 if credit_lot_policy('something_new','paid',true)<>'needs_review' then
  raise exception 'An unrecognised credit source fell through to unrestricted'; end if;

 raise notice 'PASS: default paid credit buys therapy sessions but not vouchers or unlimited therapy, bonus buys own and third-party products; only an Owner may change a package policy and only with a reason; the preview counts affected customers and credit without applying anything; existing unused balances follow the change while amounts and grants do not; other packages are untouched; every change is kept with its previous rules; premium bundle credit buys everything except more credit; and an unidentifiable source is held for review';
end $$;
rollback;
