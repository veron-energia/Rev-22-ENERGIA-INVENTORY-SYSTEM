-- The review describes what will actually happen to the customer's credit.
--
-- Reported on INV-2026-0210: a S$500 package granting S$500 paid + S$25 bonus
-- previewed as "Remove S$476.19 paid / S$23.81 bonus". Those are the money
-- (S$500) split between the benefits in proportion to what each was granted --
-- invoice_benefit_values.paid_value, the accounting share of the PRICE. The
-- execution removed S$500 and S$25, correctly. The preview was describing a
-- different quantity from the one it was labelling.
-- Disposable database only; everything is rolled back.
begin;
do $$
declare own uuid:=gen_random_uuid();
 st uuid; c uuid; c2 uuid; pm uuid; cp uuid; pb uuid; v uuid;
 inv uuid; inv2 uuid; it uuid; plan jsonb; e jsonb; res jsonb; req jsonb;
 lot uuid; bonus uuid; money numeric; paid numeric; bon numeric; units int;
begin
 insert into auth.users(id,email) values(own,'cpv-own@tests.invalid');
 insert into profiles(id,full_name,email,role) values(own,'Owner','cpv-own@tests.invalid','owner');
 perform set_config('request.jwt.claim.sub',own::text,true);
 insert into stores(name,code,country_code) values('CPV Store','CPV','SG') returning id into st;
 insert into customers(full_name,phone) values('CPV Buyer','+6598896001') returning id into c;
 insert into customers(full_name,phone) values('CPV Stranger','+6598896002') returning id into c2;
 insert into payment_methods(name) values('CPV Cash') returning id into pm;
 insert into credit_packages(name,customer_price,paid_credit_amount,bonus_enabled,bonus_mode,bonus_value,allow_product,allow_therapy)
   values('CPV S$500',500,500,true,'fixed',25,true,true) returning id into cp;
 insert into credit_package_stores(package_id,store_id) values(cp,st);

 -- ---- the reported case ---------------------------------------------------
 inv:=create_invoice(st,c,null,jsonb_build_array(jsonb_build_object('kind','credit_package','credit_package_id',cp,'quantity',1)));
 perform record_invoice_payment(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',500)),gen_random_uuid());
 select id into it from invoice_items where invoice_id=inv;
 select b.lot_id into lot from invoice_benefit_values b join customer_credit_lots l on l.id=b.lot_id
   where b.invoice_item_id=it and l.category='paid';
 select b.lot_id into bonus from invoice_benefit_values b join customer_credit_lots l on l.id=b.lot_id
   where b.invoice_item_id=it and l.category='bonus';

 plan:=invoice_action_plan(inv,'refund_full'); e:=plan->'effects';
 money:=(e#>>'{money_returned,total}')::numeric;
 select (q->>'credit_removed')::numeric into paid from jsonb_array_elements(e->'benefits') q where q->>'kind'='paid';
 select (q->>'credit_removed')::numeric into bon  from jsonb_array_elements(e->'benefits') q where q->>'kind'='bonus';
 if money<>500 then raise exception 'Money returned should be 500, got %',money; end if;
 if paid<>500 then raise exception 'Paid credit removed should be 500, got % (the accounting share is 476.19)',paid; end if;
 if bon<>25   then raise exception 'Bonus credit removed should be 25, got % (the accounting share is 23.81)',bon; end if;
 -- the accounting share is kept, separately, because it is what caps the refund
 if (select (q->>'accounting_value')::numeric from jsonb_array_elements(e->'benefits') q where q->>'kind'='paid')<>476.19 then
  raise exception 'The accounting allocation was lost'; end if;
 -- and it is never presented as credit
 if exists(select 1 from jsonb_array_elements(plan->'summary') s where s#>>'{}' like '%476.19%of paid credit%') then
  raise exception 'The summary still describes the accounting split as credit removed'; end if;

 -- ---- preview, revalidation and execution agree ---------------------------
 req:=request_invoice_action_v2(inv,'refund_full','[]'::jsonb,'Customer changed their mind',null,gen_random_uuid());
 if not exists(select 1 from jsonb_array_elements(req#>'{plan,effects,benefits}') q
                where q->>'credit_removed' is not null) then
  raise exception 'The request did not record the credit it would remove'; end if;
 res:=resolve_invoice_action_v2((req->>'request_id')::uuid,true,'Approved');
 if (res#>>'{refunded_amount}')::numeric<>money then
  raise exception 'Execution returned % but the preview promised %',res->>'refunded_amount',money; end if;
 if (select remaining_amount from customer_credit_lots where id=lot)<>0 then
  raise exception 'Paid credit was not removed as previewed'; end if;
 if (select remaining_amount from customer_credit_lots where id=bonus)<>0 then
  raise exception 'Bonus credit was not removed as previewed'; end if;
 if exists(select 1 from customer_credit_lots where customer_id=c2) then
  raise exception 'A stranger''s balance moved'; end if;

 -- ---- partially used balances --------------------------------------------
 inv2:=create_invoice(st,c,null,jsonb_build_array(jsonb_build_object('kind','credit_package','credit_package_id',cp,'quantity',1)));
 perform record_invoice_payment(inv2,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',500)),gen_random_uuid());
 select id into it from invoice_items where invoice_id=inv2;
 select b.lot_id into lot from invoice_benefit_values b join customer_credit_lots l on l.id=b.lot_id
   where b.invoice_item_id=it and l.category='paid';
 -- spend 100 of the 500 paid credit
 update customer_credit_lots set remaining_amount=remaining_amount-100 where id=lot;
 insert into customer_credit_ledger(wallet_id,customer_id,entry_type,category,amount,lot_id,source_type,store_id,reason,created_by)
  select wallet_id,customer_id,'use',category,100,id,'manual_use',store_id,'Spent',own from customer_credit_lots where id=lot;

 plan:=invoice_action_plan(inv2,'refund_full'); e:=plan->'effects';
 select (q->>'credit_removed')::numeric into paid from jsonb_array_elements(e->'benefits') q where q->>'kind'='paid';
 if paid<>400 then raise exception 'Only the remaining 400 of paid credit should be removed, got %',paid; end if;
 money:=(e#>>'{money_returned,total}')::numeric;
 if money>=500 then raise exception 'Spending credit must reduce the money returned, got %',money; end if;
 res:=resolve_invoice_action_v2((request_invoice_action_v2(inv2,'refund_full','[]'::jsonb,'Part used',null,gen_random_uuid())->>'request_id')::uuid,
   true,'Approved',null,jsonb_build_array(jsonb_build_object('code','credit_used','reason','Manager agreed')),null,false);
 if (select remaining_amount from customer_credit_lots where id=lot)<>0 then
  raise exception 'The remaining paid credit was not removed as previewed'; end if;
 if not exists(select 1 from customer_credit_ledger where lot_id=lot and entry_type='use') then
  raise exception 'The record of the spent credit was destroyed'; end if;

 -- ---- a premium bundle: paid, bonus AND vouchers, each named separately ----
 insert into vouchers(name,code,qty_type,reward_eligible) values('CPV V','CPV-V','limited',true) returning id into v;
 insert into voucher_store_stock(voucher_id,store_id,current_qty) values(v,st,10);
 insert into voucher_store_prices(voucher_id,store_id,selling_price,available_at_store) values(v,st,20,true);
 insert into premium_bundles(name,customer_payment_amount,paid_credit_amount,bonus_credit_amount,free_voucher_qty,grants_reward)
   values('CPV Bundle',140,100,40,2,true) returning id into pb;
 insert into premium_bundle_stores(bundle_id,store_id) values(pb,st);
 insert into premium_bundle_vouchers(bundle_id,voucher_id) values(pb,v);
 inv:=create_invoice(st,c,null,jsonb_build_array(jsonb_build_object('kind','premium_bundle','premium_bundle_id',pb,'quantity',1,
   'voucher_selection',jsonb_build_array(jsonb_build_object('voucher_id',v,'quantity',2)))));
 perform record_invoice_payment(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',140)),gen_random_uuid());
 plan:=invoice_action_plan(inv,'refund_full'); e:=plan->'effects';
 select (q->>'credit_removed')::numeric into paid from jsonb_array_elements(e->'benefits') q where q->>'kind'='paid';
 select (q->>'credit_removed')::numeric into bon  from jsonb_array_elements(e->'benefits') q where q->>'kind'='bonus';
 select (q->>'units_revoked')::int      into units from jsonb_array_elements(e->'benefits') q where q->>'kind'='voucher';
 if paid<>100 then raise exception 'Bundle paid credit removed should be 100, got %',paid; end if;
 if bon<>40   then raise exception 'Bundle bonus credit removed should be 40, got %',bon; end if;
 if units<>2  then raise exception 'Bundle voucher units revoked should be 2, got %',units; end if;
 -- a voucher benefit reports units, never a money "credit removed"
 if (select q->>'credit_removed' from jsonb_array_elements(e->'benefits') q where q->>'kind'='voucher') is not null then
  raise exception 'Voucher units were reported as credit'; end if;
 if (e#>>'{money_returned,total}')::numeric<>140 then
  raise exception 'Bundle money returned should be the 140 paid, got %',e#>>'{money_returned,total}'; end if;

 -- ---- a balance that moves between preview and approval needs confirming ---
 plan:=invoice_action_plan(inv,'refund_full');
 req:=request_invoice_action_v2(inv,'refund_full','[]'::jsonb,'Bundle back',null,gen_random_uuid());
 select b.lot_id into lot from invoice_benefit_values b join customer_credit_lots l on l.id=b.lot_id
   where b.invoice_id=inv and l.category='paid';
 update customer_credit_lots set remaining_amount=remaining_amount-10 where id=lot;
 res:=resolve_invoice_action_v2((req->>'request_id')::uuid,true,'Approve',null,
   jsonb_build_array(jsonb_build_object('code','credit_used','reason','Spent since')),null,false);
 if not coalesce((res->>'confirmation_required')::boolean,false) then
  raise exception 'A balance change between preview and approval was applied without confirmation'; end if;
 if not exists(select 1 from jsonb_array_elements(res#>'{revised_plan,effects,benefits}') q
                where q->>'credit_removed' is not null) then
  raise exception 'The revised plan does not state the credit it would now remove'; end if;

 raise notice 'PASS: money returned, accounting allocation, paid credit, bonus credit and voucher units are reported separately and correctly; preview, request, revalidation and execution agree; partially used balances remove only what is left; a balance moving between preview and approval requires confirmation';
end $$;
rollback;
