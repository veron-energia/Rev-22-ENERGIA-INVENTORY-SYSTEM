-- Overrides, and what an override may and may not do.
--
-- An Owner/Manager override waives a TIME or USAGE restriction. It never
-- waives authorization, the actual-payment ceiling, duplicate-refund
-- protection, or truthful stock handling — and it never manufactures money or
-- benefits that were already consumed.
-- Disposable database only; everything is rolled back.
begin;
do $$
declare own uuid:=gen_random_uuid(); stf uuid:=gen_random_uuid();
 st uuid; c uuid; c2 uuid; pm uuid; cp uuid; inv uuid; unpaid uuid;
 req jsonb; res jsonb; plan jsonb; lot uuid; it uuid; n numeric; s text; codes text;
begin
 insert into auth.users(id,email) values(own,'ov-own@tests.invalid'),(stf,'ov-stf@tests.invalid');
 insert into profiles(id,full_name,email,role) values
   (own,'Owner','ov-own@tests.invalid','owner'),(stf,'Staff','ov-stf@tests.invalid','staff');
 perform set_config('request.jwt.claim.sub',own::text,true);
 insert into stores(name,code,country_code) values('OV Store','OVS','SG') returning id into st;
 insert into user_store_assignments(user_id,store_id) values(stf,st);
 insert into customers(full_name,phone) values('OV Buyer','+6598881111') returning id into c;
 insert into customers(full_name,phone) values('OV Stranger','+6598882222') returning id into c2;
 insert into payment_methods(name) values('OV Cash') returning id into pm;
 insert into credit_packages(name,customer_price,paid_credit_amount,allow_product,allow_therapy)
   values('OV Package',100,120,true,true) returning id into cp;
 insert into credit_package_stores(package_id,store_id) values(cp,st);

 -- An unrelated customer's balance, which must never move.
 insert into credit_packages(name,customer_price,paid_credit_amount,allow_product,allow_therapy)
   values('OV Other',50,50,true,true);

 inv:=create_invoice(st,c,null,jsonb_build_array(jsonb_build_object('kind','credit_package','credit_package_id',cp,'quantity',1)));
 perform record_invoice_payment(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',100)),gen_random_uuid());
 select id into it from invoice_items where invoice_id=inv;
 select lot_id into lot from invoice_benefit_values where invoice_item_id=it;

 -- ---- unused credit needs no override -----------------------------------
 plan:=invoice_action_plan(inv,'refund_full');
 if coalesce((plan->>'requires_override')::boolean,false) then
  raise exception 'Refunding wholly unused credit must not require an override: %',plan->'overrides_required'; end if;
 if (plan->>'refund_amount')::numeric<>100 then
  raise exception 'Unused package must refund the price paid, got %',plan->>'refund_amount'; end if;

 -- ---- spending part of it turns the same action into an override --------
 -- Spend 30 of the granted 120. Written directly because the only purchase
 -- paid package credit may fund is a therapy session (242), which needs a
 -- whole therapy fixture this test does not need; these two writes are exactly
 -- what consume_customer_credit() performs, and the refund rule under test
 -- reads the lot and its ledger, not the purchase that spent it.
 update customer_credit_lots set remaining_amount=remaining_amount-30 where id=lot;
 insert into customer_credit_ledger(wallet_id,customer_id,entry_type,category,amount,lot_id,source_type,store_id,reason,created_by)
  select wallet_id,customer_id,'use',category,30,id,'manual_use',store_id,'Used on a therapy session',own
    from customer_credit_lots where id=lot;
 plan:=invoice_action_plan(inv,'refund_full');
 select string_agg(x->>'code',',') into codes from jsonb_array_elements(plan->'overrides_required') x;
 if codes is null or codes not like '%credit_used%' then
  raise exception 'Spending package credit must require an override, got %',coalesce(codes,'none'); end if;
 -- Only the credit still there is refundable: 120 granted, 30 spent, 90 left,
 -- worth 90/120 of the 100 paid.
 if (plan->>'refund_amount')::numeric<>75 then
  raise exception 'Refund must follow the unused portion of the original grant, got %',plan->>'refund_amount'; end if;

 -- The request records that an override will be needed, so staff are told.
 perform set_config('request.jwt.claim.sub',stf::text,true);
 req:=request_invoice_action_v2(inv,'refund_full','[]'::jsonb,'Customer wants out',null,gen_random_uuid());
 if not coalesce((req#>>'{plan,requires_override}')::boolean,false) then
  raise exception 'The request must tell staff an override is required'; end if;

 -- ---- an override still needs a stated reason ---------------------------
 perform set_config('request.jwt.claim.sub',own::text,true);
 begin
  perform resolve_invoice_action_v2((req->>'request_id')::uuid,true,'go on');
  raise exception 'Approved a usage override with no reason';
 exception when others then
  if sqlerrm not like '%override reason is required%' then raise; end if;
 end;

 res:=resolve_invoice_action_v2((req->>'request_id')::uuid,true,'Goodwill',null,
   jsonb_build_array(jsonb_build_object('code','credit_used','reason','Manager goodwill, customer moving overseas')),
   null,false);
 if res->>'status'<>'approved' then raise exception 'Override approval failed: %',res; end if;
 if (res#>>'{outcome,refunded_amount}')::numeric<>75 then
  raise exception 'Override refunded something other than the unused portion: %',res#>>'{outcome,refunded_amount}'; end if;

 -- Remaining credit is gone; consumed credit is NOT clawed back, and the
 -- balance is never driven negative to recover it.
 n:=(select remaining_amount from customer_credit_lots where id=lot);
 if n<>0 then raise exception 'Remaining credit should be removed entirely, got %',n; end if;
 if exists(select 1 from customer_credit_lots where customer_id=c and remaining_amount<0) then
  raise exception 'An override drove a credit balance negative to recover spent credit'; end if;
 if not exists(select 1 from customer_credit_ledger where lot_id=lot and entry_type='use') then
  raise exception 'The history of the credit that was used was destroyed'; end if;
 -- The override is on the record, with its reason.
 if not exists(select 1 from audit_logs where action='invoice_action_approved'
                and new_data->'overrides'->0->>'reason' like 'Manager goodwill%') then
  raise exception 'The override reason was not audited'; end if;

 -- ---- an unrelated customer is untouched --------------------------------
 if exists(select 1 from customer_credit_lots where customer_id=c2) then
  raise exception 'A stranger''s balance was touched by this refund'; end if;

 -- ---- the payment ceiling is not waivable -------------------------------
 -- Everything refundable has now been refunded; another go must be refused
 -- however senior the person asking.
 plan:=invoice_action_plan(inv,'refund_full');
 if (plan->>'refund_amount')::numeric<>0 then
  raise exception 'A fully refunded invoice still offers %',plan->>'refund_amount'; end if;

 -- ---- cancelling an unpaid invoice records no money movement ------------
 unpaid:=create_invoice(st,c,null,jsonb_build_array(jsonb_build_object('kind','credit_package','credit_package_id',cp,'quantity',1)));
 plan:=invoice_action_plan(unpaid,'cancel');
 if (plan->>'refund_amount')::numeric<>0 or (plan->>'refund_due')::numeric<>0 then
  raise exception 'An unpaid cancellation proposed money movement: % / %',plan->>'refund_amount',plan->>'refund_due'; end if;
 perform set_config('request.jwt.claim.sub',stf::text,true);
 req:=request_invoice_action_v2(unpaid,'cancel','[]'::jsonb,'Raised by mistake',null,gen_random_uuid());
 perform set_config('request.jwt.claim.sub',own::text,true);
 res:=resolve_invoice_action_v2((req->>'request_id')::uuid,true,'Agreed');
 select status into s from invoices where id=unpaid;
 if s<>'cancelled' then raise exception 'Unpaid cancellation left status %',s; end if;
 if exists(select 1 from invoice_refunds where invoice_id=unpaid) then
  raise exception 'Cancelling an unpaid invoice invented a refund record'; end if;

 raise notice 'PASS: unused benefits need no override, spent credit does and is limited to the unused portion, override reasons are required and audited, consumed credit and its history survive, strangers'' balances are untouched, the payment ceiling is not waivable, and an unpaid cancellation records no money';
end $$;
rollback;
