-- Premium bundles through the guided workflow.
--
-- A bundle carries several kinds of benefit at once -- paid credit, bonus
-- credit and issued vouchers -- so it is the case where "reverse only what is
-- genuinely unused, and only from THIS purchase" has the most ways to go wrong.
-- Disposable database only; everything is rolled back.
begin;
do $$
declare own uuid:=gen_random_uuid(); stf uuid:=gen_random_uuid();
 st uuid; c uuid; c2 uuid; pm uuid; pb uuid; v uuid; inv uuid; inv2 uuid;
 it uuid; plan jsonb; req jsonb; res jsonb; lot uuid; bonus uuid; rv uuid;
 n numeric; codes text; held int;
begin
 insert into auth.users(id,email) values(own,'pb-own@tests.invalid'),(stf,'pb-stf@tests.invalid');
 insert into profiles(id,full_name,email,role) values
   (own,'Owner','pb-own@tests.invalid','owner'),(stf,'Staff','pb-stf@tests.invalid','staff');
 perform set_config('request.jwt.claim.sub',own::text,true);
 insert into stores(name,code,country_code) values('PB Store','PBS','SG') returning id into st;
 insert into user_store_assignments(user_id,store_id) values(stf,st);
 insert into customers(full_name,phone) values('PB Buyer','+6598889001') returning id into c;
 insert into customers(full_name,phone) values('PB Stranger','+6598889002') returning id into c2;
 insert into payment_methods(name) values('PB Cash') returning id into pm;
 insert into vouchers(name,code,qty_type,reward_eligible) values('PB Voucher','PB-V','limited',true) returning id into v;
 insert into voucher_store_stock(voucher_id,store_id,current_qty) values(v,st,10);
 insert into voucher_store_prices(voucher_id,store_id,selling_price,available_at_store) values(v,st,20,true);
 -- 140 paid: 100 paid credit, 40 bonus credit, plus two issued vouchers.
 insert into premium_bundles(name,customer_payment_amount,paid_credit_amount,bonus_credit_amount,free_voucher_qty,grants_reward)
   values('PB Bundle',140,100,40,2,true) returning id into pb;
 insert into premium_bundle_stores(bundle_id,store_id) values(pb,st);
 insert into premium_bundle_vouchers(bundle_id,voucher_id) values(pb,v);

 -- A stranger buys the same bundle. Nothing about them may move.
 inv2:=create_invoice(st,c2,null,jsonb_build_array(jsonb_build_object('kind','premium_bundle','premium_bundle_id',pb,'quantity',1,
   'voucher_selection',jsonb_build_array(jsonb_build_object('voucher_id',v,'quantity',2)))));
 perform record_invoice_payment(inv2,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',140)),gen_random_uuid());

 inv:=create_invoice(st,c,null,jsonb_build_array(jsonb_build_object('kind','premium_bundle','premium_bundle_id',pb,'quantity',1,
   'voucher_selection',jsonb_build_array(jsonb_build_object('voucher_id',v,'quantity',2)))));
 perform record_invoice_payment(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',140)),gen_random_uuid());
 select id into it from invoice_items where invoice_id=inv;
 select b.lot_id into lot from invoice_benefit_values b join customer_credit_lots l on l.id=b.lot_id
   where b.invoice_item_id=it and l.category='paid';
 select b.lot_id into bonus from invoice_benefit_values b join customer_credit_lots l on l.id=b.lot_id
   where b.invoice_item_id=it and l.category='bonus';
 select reward_voucher_id into rv from invoice_benefit_values where invoice_item_id=it and reward_voucher_id is not null;
 if lot is null or bonus is null or rv is null then
  raise exception 'Fixture did not issue paid credit, bonus credit and vouchers together'; end if;

 -- ---- wholly unused: no usage override, everything reversed --------------
 plan:=invoice_action_plan(inv,'refund_full');
 select string_agg(x->>'code',',') into codes from jsonb_array_elements(plan->'overrides_required') x;
 if coalesce(codes,'') ~ '(credit_used|voucher_redeemed)' then
  raise exception 'An untouched bundle must need no usage override, got %',codes; end if;
 if (plan->>'refund_amount')::numeric<>140 then
  raise exception 'An untouched bundle must refund the 140 paid, got %',plan->>'refund_amount'; end if;
 -- the plan must name all three benefit kinds it will reverse
 if (select count(*) from jsonb_array_elements(plan->'lines') l,
      jsonb_array_elements(l->'benefits') b)<3 then
  raise exception 'The plan must cover paid credit, bonus credit and the issued vouchers'; end if;

 -- ---- spend part of the credit: now it is an override, capped ------------
 update customer_credit_lots set remaining_amount=remaining_amount-20 where id=lot;
 insert into customer_credit_ledger(wallet_id,customer_id,entry_type,category,amount,lot_id,source_type,store_id,reason,created_by)
  select wallet_id,customer_id,'use',category,20,id,'manual_use',store_id,'Spent on a session',own
    from customer_credit_lots where id=lot;
 plan:=invoice_action_plan(inv,'refund_full');
 select string_agg(x->>'code',',') into codes from jsonb_array_elements(plan->'overrides_required') x;
 if coalesce(codes,'') not like '%credit_used%' then
  raise exception 'Spent bundle credit must require an override, got %',coalesce(codes,'none'); end if;
 if (plan->>'refund_amount')::numeric>=140 then
  raise exception 'Spending credit must reduce what is refundable, got %',plan->>'refund_amount'; end if;

 -- ---- redeem one voucher unit: a second usage override -------------------
 update customer_reward_vouchers set quantity=quantity-1 where id=rv;
 plan:=invoice_action_plan(inv,'refund_full');
 select string_agg(distinct x->>'code',',') into codes from jsonb_array_elements(plan->'overrides_required') x;
 if coalesce(codes,'') not like '%voucher_redeemed%' then
  raise exception 'A redeemed bundle voucher must require an override, got %',coalesce(codes,'none'); end if;

 -- ---- approve with both overrides ----------------------------------------
 perform set_config('request.jwt.claim.sub',stf::text,true);
 req:=request_invoice_action_v2(inv,'refund_full','[]'::jsonb,'Customer returning the bundle',null,gen_random_uuid());
 perform set_config('request.jwt.claim.sub',own::text,true);
 res:=resolve_invoice_action_v2((req->>'request_id')::uuid,true,'Manager agreed',null,
   jsonb_build_array(
     jsonb_build_object('code','credit_used','reason','Manager goodwill on the spent 20'),
     jsonb_build_object('code','voucher_redeemed','reason','One session already taken')),
   null,false);
 if res->>'status'<>'approved' then raise exception 'Bundle reversal failed: %',res; end if;

 -- only what was left is gone; what was used stays used
 if (select remaining_amount from customer_credit_lots where id=lot)<>0 then
  raise exception 'Remaining paid credit should be removed, got %',(select remaining_amount from customer_credit_lots where id=lot); end if;
 if (select remaining_amount from customer_credit_lots where id=bonus)<>0 then
  raise exception 'Remaining bonus credit should be removed, got %',(select remaining_amount from customer_credit_lots where id=bonus); end if;
 if exists(select 1 from customer_credit_lots where customer_id=c and remaining_amount<0) then
  raise exception 'A bundle reversal drove a balance negative to claw back spent credit'; end if;
 if not exists(select 1 from customer_credit_ledger where lot_id=lot and entry_type='use') then
  raise exception 'The record of the credit that was spent was destroyed'; end if;
 -- the redeemed voucher unit is not restored as usable
 select case when status='held' then quantity else 0 end into held from customer_reward_vouchers where id=rv;
 if held<>0 then raise exception 'Unused voucher units should be revoked, % still held',held; end if;

 -- ---- the stranger is untouched ------------------------------------------
 if (select coalesce(sum(remaining_amount),0) from customer_credit_lots where customer_id=c2)<>140 then
  raise exception 'A stranger''s bundle balance moved: %',
    (select coalesce(sum(remaining_amount),0) from customer_credit_lots where customer_id=c2); end if;
 if exists(select 1 from customer_reward_vouchers rv2 join invoice_benefit_values b on b.reward_voucher_id=rv2.id
            where b.invoice_id=inv2 and rv2.status<>'held') then
  raise exception 'A stranger''s bundle vouchers were revoked'; end if;

 -- ---- the payment ceiling, and no second reversal ------------------------
 n:=(select coalesce(sum(amount),0) from invoice_refunds where invoice_id=inv);
 if n>140 then raise exception 'Refunded more than the customer ever paid: %',n; end if;
 plan:=invoice_action_plan(inv,'refund_full');
 if (plan->>'refund_amount')::numeric<>0 then
  raise exception 'A fully reversed bundle still offers %',plan->>'refund_amount'; end if;
 -- commissions reversed once, not twice
 if (select count(*) from commissions where invoice_item_id=it and status='earned')<>0 then
  raise exception 'Bundle commission was not reversed'; end if;

 raise notice 'PASS: an untouched bundle reverses paid credit, bonus credit and vouchers with no usage override; spent credit and redeemed vouchers each require one and cap the refund; only this purchase''s remaining benefits are removed; spent history, balances of others and the payment ceiling all hold';
end $$;
rollback;
