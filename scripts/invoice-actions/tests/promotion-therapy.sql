-- Refunding or cancelling a promotion closes the therapy it granted (363).
--
-- A promotion that includes a therapy package grants purchased therapy units
-- linked to the promotion line at a price of 0. Before 363 the refund engine
-- closed units only for line_kind 'therapy', so a refunded promotion left its
-- therapy with the customer (production: INV-2026-0160 / UTP-0000006). The
-- rule is the one already set for therapy sold on its own: unused units go
-- with the line; used ones (started, ended, or vouchers collected) only on the
-- Owner/Manager 'therapy_activated' override with an amount.
--
-- It also covers the goods: the guided plan never offered a promotion's goods
-- back, so a guided refund of any promotion with goods was refused.
--
-- Needs 363. Disposable database only; everything is rolled back.
\set ON_ERROR_STOP on
begin;

create function pg_temp.goods(p jsonb) returns jsonb language sql as $$
  select coalesce(jsonb_agg(jsonb_build_object('movement_id',s->>'movement_id',
           'sellable_quantity',(s->>'proposed_sellable')::int,'damaged_quantity',0,'not_returned_quantity',0)),'[]'::jsonb)
    from jsonb_array_elements(p->'stock') s $$;

do $$
declare own uuid:=gen_random_uuid(); mgr uuid:=gen_random_uuid(); stf uuid:=gen_random_uuid(); mgr2 uuid:=gen_random_uuid();
 st uuid; st2 uuid; c uuid; c2 uuid; c3 uuid; c4 uuid; c5 uuid; c6 uuid; c7 uuid; c8 uuid; c9 uuid; c10 uuid;
 c11 uuid; c12 uuid; c13 uuid; c14 uuid; c15 uuid; c16 uuid; pm uuid; pbelt uuid; pv uuid; pch uuid; grp uuid; it2 uuid; u3 uuid; pc uuid; v1 uuid; tpu uuid; tpc uuid; tpt uuid;
 pa uuid; pb uuid; p2 uuid;
 inv uuid; other uuid; it uuid; u uuid; u2 uuid; orphan uuid; ent uuid; pay uuid; mv uuid;
 plan jsonb; req jsonb; res jsonb; codes text; qty0 int; mvn int; amt numeric;
begin
 insert into auth.users(id,email) values(own,'pt-own@tests.invalid'),(mgr,'pt-mgr@tests.invalid'),(stf,'pt-stf@tests.invalid'),
   (mgr2,'pt-mgr2@tests.invalid');
 insert into profiles(id,full_name,email,role) values
   (own,'Owner','pt-own@tests.invalid','owner'),(mgr,'Manager','pt-mgr@tests.invalid','manager'),
   (stf,'Staff','pt-stf@tests.invalid','staff'),(mgr2,'Other Manager','pt-mgr2@tests.invalid','manager');
 perform set_config('request.jwt.claim.sub',own::text,true);
 insert into stores(name,code,country_code) values('PT Store','PTS','SG') returning id into st;
 insert into stores(name,code,country_code) values('PT Other Store','PTO','SG') returning id into st2;
 insert into user_store_assignments(user_id,store_id) values(mgr,st),(stf,st),(mgr2,st2);
 insert into customers(full_name,phone) values('PT Buyer','+6598933001') returning id into c;
 insert into customers(full_name,phone) values('PT Other','+6598933002') returning id into c2;
 -- An ended period still holds its days for the same package (53's no-overlap
 -- constraint), so the sections that start therapy each have their own buyer.
 insert into customers(full_name,phone) values('PT Third','+6598933003') returning id into c3;
 insert into customers(full_name,phone) values('PT Fourth','+6598933004') returning id into c4;
 insert into customers(full_name,phone) values('PT Fifth','+6598933005') returning id into c5;
 insert into customers(full_name,phone) values('PT Sixth','+6598933006') returning id into c6;
 insert into customers(full_name,phone) values('PT Seventh','+6598933007') returning id into c7;
 insert into customers(full_name,phone) values('PT Eighth','+6598933008') returning id into c8;
 insert into customers(full_name,phone) values('PT Ninth','+6598933009') returning id into c9;
 insert into customers(full_name,phone) values('PT Tenth','+6598933010') returning id into c10;
 insert into customers(full_name,phone) values('PT C11','+6598933011') returning id into c11;
 insert into customers(full_name,phone) values('PT C12','+6598933012') returning id into c12;
 insert into customers(full_name,phone) values('PT C13','+6598933013') returning id into c13;
 insert into customers(full_name,phone) values('PT C14','+6598933014') returning id into c14;
 insert into customers(full_name,phone) values('PT C15','+6598933015') returning id into c15;
 insert into customers(full_name,phone) values('PT C16','+6598933016') returning id into c16;
 insert into payment_methods(name,is_active) values('PT Cash',true) returning id into pm;
 insert into products(name,sku,product_type) values('PT Corset','PTC','own') returning id into pc;
 insert into store_inventory(store_id,product_id,current_qty) values(st,pc,100);
 perform set_product_prices(st,pc,200,200,'available');
 insert into products(name,sku,product_type) values('PT Belt','PTB','own') returning id into pbelt;
 insert into store_inventory(store_id,product_id,current_qty) values(st,pbelt,100);
 perform set_product_prices(st,pbelt,150,150,'available');
 insert into vouchers(name,code,voucher_kind,qty_type,selling_price,is_active)
   values('PT Facial','PTF','normal','limited',50,true) returning id into v1;
 insert into voucher_store_stock(voucher_id,store_id,current_qty) values(v1,st,100);

 insert into unlimited_therapy_packages(name,duration_months,is_active,entitlement_kind)
   values('PT 3 Months',3,true,'unlimited') returning id into tpu;
 tpc:=upsert_therapy_package_choice(null,'PT Choice','PT-CH',null,true,1,10,array[v1],null);
 insert into unlimited_therapy_packages(name,duration_months,is_active,entitlement_kind)
   values('PT Own Line',6,true,'unlimited') returning id into tpt;
 insert into unlimited_therapy_store_prices(package_id,store_id,selling_price,available_at_store) values(tpt,st,600,true);

 -- A: a corset and three months' therapy. B: a corset and the choice package.
 -- 2: two lots of therapy per copy, no goods.
 insert into promotions(name,code) values('PT Bundle A','PT-A') returning id into pa;
 insert into promotion_items(promotion_id,item_type,product_id,quantity) values(pa,'product',pc,1);
 insert into promotion_items(promotion_id,item_type,therapy_package_id,quantity) values(pa,'therapy',tpu,1);
 perform set_promotion_prices(pa,st,610,610,true);
 insert into promotions(name,code) values('PT Bundle B','PT-B') returning id into pb;
 insert into promotion_items(promotion_id,item_type,product_id,quantity) values(pb,'product',pc,1);
 insert into promotion_items(promotion_id,item_type,therapy_package_id,quantity) values(pb,'therapy',tpc,1);
 perform set_promotion_prices(pb,st,500,500,true);
 insert into promotions(name,code) values('PT Double','PT-2') returning id into p2;
 insert into promotion_items(promotion_id,item_type,therapy_package_id,quantity) values(p2,'therapy',tpu,2);
 perform set_promotion_prices(p2,st,300,300,true);
 -- V: two facial vouchers and three months' therapy. CH: a garment of the
 -- customer's choice (corset or belt) and three months' therapy.
 insert into promotions(name,code) values('PT Vouchers','PT-V') returning id into pv;
 insert into promotion_items(promotion_id,item_type,voucher_id,quantity) values(pv,'voucher',v1,2);
 insert into promotion_items(promotion_id,item_type,therapy_package_id,quantity) values(pv,'therapy',tpu,1);
 perform set_promotion_prices(pv,st,500,500,true);
 insert into promotions(name,code) values('PT Choice Garment','PT-CH') returning id into pch;
 insert into promotion_items(promotion_id,item_type,therapy_package_id,quantity) values(pch,'therapy',tpu,1);
 insert into promotion_choice_groups(promotion_id,label,item_kind,choose_qty) values(pch,'Garment','product',1) returning id into grp;
 insert into promotion_choice_options(group_id,product_id) values(grp,pc),(grp,pbelt);
 perform set_promotion_prices(pch,st,400,400,true);

 -- Somebody else's bundle, which nothing below may touch.
 other:=create_invoice_with_details(st,c2,jsonb_build_array(jsonb_build_object('kind','promotion','promotion_id',pa,'quantity',1)),
   jsonb_build_object('business_date',sg_today()::text));
 perform record_invoice_payment(other,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',610)),gen_random_uuid());
 select id into u2 from purchased_therapy_entitlements where invoice_id=other;
 if u2 is null then raise exception 'Fixture: the promotion granted no therapy'; end if;

 -- ---- 1. the plan lists the unit and the goods -----------------------------
 inv:=create_invoice_with_details(st,c,jsonb_build_array(jsonb_build_object('kind','promotion','promotion_id',pa,'quantity',1)),
   jsonb_build_object('business_date',sg_today()::text));
 perform record_invoice_payment(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',610)),gen_random_uuid());
 select id into it from invoice_items where invoice_id=inv;
 select id into u from purchased_therapy_entitlements where invoice_item_id=it;
 if (select price_snapshot from purchased_therapy_entitlements where id=u)<>0 then
  raise exception 'Fixture: therapy inside a promotion should be priced at 0'; end if;
 plan:=invoice_action_plan(inv,'refund_full');
 if jsonb_array_length(coalesce(plan->'lines'->0->'therapy_units','[]'))<>1
    or plan->'lines'->0->'therapy_units'->0->>'id'<>u::text then
  raise exception '1: the plan does not list the promotion''s therapy unit: %',plan->'lines'; end if;
 select string_agg(x->>'code',',') into codes from jsonb_array_elements(plan->'overrides_required') x;
 if coalesce(codes,'') like '%therapy_activated%' then raise exception '1: unused therapy asked for an override'; end if;
 if not exists(select 1 from jsonb_array_elements_text(plan->'summary') t where t like 'Close therapy %PT Bundle A%not used yet%') then
  raise exception '1: the summary does not say the therapy closes: %',plan->'summary'; end if;
 if jsonb_array_length(plan#>'{effects,therapy_closed}')<>1 then raise exception '1: effects.therapy_closed missing'; end if;
 if jsonb_array_length(plan->'stock')<>1 or (plan->'stock'->0->>'proposed_sellable')::int<>1 then
  raise exception '1: the promotion''s corset is not offered back: %',plan->'stock'; end if;

 -- ---- 2. the guided full refund closes it -----------------------------------
 perform set_config('request.jwt.claim.sub',stf::text,true);
 req:=request_invoice_action_v2(inv,'refund_full','[]'::jsonb,'Customer returned the bundle',null,gen_random_uuid());
 perform set_config('request.jwt.claim.sub',own::text,true);
 plan:=invoice_action_plan(inv,'refund_full');
 res:=resolve_invoice_action_v2((req->>'request_id')::uuid,true,'Agreed',plan->>'plan_hash','[]'::jsonb,pg_temp.goods(plan),false);
 if res->>'status'<>'approved' or (res->>'refunded_amount')::numeric<>610 then raise exception '2: refund failed: %',res; end if;
 if (select status from purchased_therapy_entitlements where id=u)<>'refunded' then
  raise exception '2: a refunded promotion kept its therapy (the INV-2026-0160 gap)'; end if;
 if not exists(select 1 from audit_logs where table_name='purchased_therapy_entitlements' and record_id=u
                and action='closed_with_invoice_line' and new_data->>'request_id'=req->>'request_id') then
  raise exception '2: closing the unit was not audited against the request'; end if;
 if (select status from invoices where id=inv)<>'refunded' then raise exception '2: invoice not refunded'; end if;
 if (select current_qty from store_inventory where store_id=st and product_id=pc)<>99 then
  raise exception '2: the corset did not come back (stock %)',(select current_qty from store_inventory where store_id=st and product_id=pc); end if;
 begin
  perform claim_purchased_therapy(u,'unlimited',sg_today());
  raise exception '2: therapy from a refunded promotion could still be claimed';
 exception when others then if sqlerrm not like '%was refunded%' then raise; end if; end;
 -- a replay changes nothing
 res:=resolve_invoice_action_v2((req->>'request_id')::uuid,true,'again');
 if not coalesce((res->>'already_resolved')::boolean,false) then raise exception '2: replay not recognised'; end if;
 if (select count(*) from audit_logs where record_id=u and action='closed_with_invoice_line')<>1 then
  raise exception '2: the replay closed the unit twice'; end if;

 -- ---- 3. started therapy: the reviewed plan changes, and needs an amount ---
 inv:=create_invoice_with_details(st,c,jsonb_build_array(jsonb_build_object('kind','promotion','promotion_id',pa,'quantity',1)),
   jsonb_build_object('business_date',sg_today()::text));
 perform record_invoice_payment(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',610)),gen_random_uuid());
 select e.id into u from purchased_therapy_entitlements e join invoice_items x on x.id=e.invoice_item_id where x.invoice_id=inv;
 perform set_config('request.jwt.claim.sub',stf::text,true);
 req:=request_invoice_action_v2(inv,'refund_full','[]'::jsonb,'Changed her mind',null,gen_random_uuid());
 perform set_config('request.jwt.claim.sub',own::text,true);
 perform activate_purchased_therapy(u,sg_today(),'Started before the refund was approved');
 res:=resolve_invoice_action_v2((req->>'request_id')::uuid,true,'ok',null,'[]'::jsonb,null,false);
 if not coalesce((res->>'confirmation_required')::boolean,false) then
  raise exception '3: therapy started after the request, yet the reviewed plan was not invalidated: %',res; end if;
 plan:=res->'revised_plan';
 if not exists(select 1 from jsonb_array_elements(plan->'overrides_required') x
                where x->>'code'='therapy_activated' and (x->>'amount_required')::boolean
                  and x->>'invoice_item_id'=(plan->'lines'->0->>'invoice_item_id')) then
  raise exception '3: started promotion therapy must need an override with an amount: %',plan->'overrides_required'; end if;
 begin
  perform resolve_invoice_action_v2((req->>'request_id')::uuid,true,'ok',plan->>'plan_hash','[]'::jsonb,pg_temp.goods(plan),false);
  raise exception '3: started therapy was ended with no override';
 exception when others then if sqlerrm not like '%override reason is required for: therapy_activated%' then raise; end if; end;
 begin
  perform resolve_invoice_action_v2((req->>'request_id')::uuid,true,'ok',plan->>'plan_hash',
    jsonb_build_array(jsonb_build_object('code','therapy_activated','reason','Goodwill')),pg_temp.goods(plan),false);
  raise exception '3: started therapy was ended with no amount';
 exception when others then if sqlerrm not like '%therapy_activated (amount)%' then raise; end if; end;
 if (select status from purchased_therapy_entitlements where id=u)<>'active' or exists(select 1 from invoice_refunds where invoice_id=inv) then
  raise exception '3: a refused approval changed something'; end if;
 res:=resolve_invoice_action_v2((req->>'request_id')::uuid,true,'Half back',plan->>'plan_hash',
   jsonb_build_array(jsonb_build_object('code','therapy_activated','reason','Two months left, Manager agreed','amount',400)),
   pg_temp.goods(plan),false);
 if res->>'status'<>'approved' or (res->>'refunded_amount')::numeric<>400 then raise exception '3: authorized refund failed: %',res; end if;
 if (select status from purchased_therapy_entitlements where id=u)<>'refunded' then raise exception '3: started therapy not ended'; end if;
 if (select activation_date from purchased_therapy_entitlements where id=u) is null then raise exception '3: activation history erased'; end if;
 if not exists(select 1 from audit_logs where record_id=u and action='authorized_termination'
                and (new_data->>'amount')::numeric=400 and new_data->'override'->>'reason' like 'Two months left%') then
  raise exception '3: the termination was not audited with its amount and reason'; end if;

 -- ---- 4. vouchers collected count as used; cancelling without the money ----
 inv:=create_invoice_with_details(st,c,jsonb_build_array(jsonb_build_object('kind','promotion','promotion_id',pb,'quantity',1)),
   jsonb_build_object('business_date',sg_today()::text));
 perform record_invoice_payment(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',500)),gen_random_uuid());
 select e.id into u from purchased_therapy_entitlements e join invoice_items x on x.id=e.invoice_item_id where x.invoice_id=inv;
 perform claim_purchased_therapy(u,'voucher',null,null,null,false,
   jsonb_build_array(jsonb_build_object('voucher_id',v1,'quantity',2)));
 ent:=(select voucher_entitlement_id from purchased_therapy_entitlements where id=u);
 if (select status from purchased_therapy_entitlements where id=u)<>'pending_activation' or not therapy_unit_consumed(u) then
  raise exception '4: fixture: a unit with collected vouchers should be pending and used'; end if;
 plan:=invoice_action_plan(inv,'cancel');
 if not exists(select 1 from jsonb_array_elements(plan->'overrides_required') x where x->>'code'='therapy_activated') then
  raise exception '4: collected vouchers did not require the override'; end if;
 perform set_config('request.jwt.claim.sub',stf::text,true);
 req:=request_invoice_action_v2(inv,'cancel','[]'::jsonb,'Wrong bundle',null,gen_random_uuid());
 perform set_config('request.jwt.claim.sub',mgr::text,true);
 res:=resolve_invoice_action_v2((req->>'request_id')::uuid,true,'Cancelled',plan->>'plan_hash',
   jsonb_build_array(jsonb_build_object('code','therapy_activated','reason','Two facials used','amount',400)),
   pg_temp.goods(plan),false);
 if res->>'status'<>'approved' or (select status from invoices where id=inv)<>'cancelled' then raise exception '4: cancel failed: %',res; end if;
 if (select status from purchased_therapy_entitlements where id=u)<>'refunded' then raise exception '4: unit not ended'; end if;
 if not exists(select 1 from audit_logs where record_id=u and action='authorized_termination' and new_data->>'context'='cancel') then
  raise exception '4: the termination was not audited as part of the cancellation'; end if;
 if (entitlement_voucher_state(ent)->>'claimed')::int<>2 or (entitlement_voucher_state(ent)->>'remaining')::int<>0 then
  raise exception '4: expected the 2 collected vouchers kept and the other 8 withdrawn: %',entitlement_voucher_state(ent); end if;
 perform set_config('request.jwt.claim.sub',own::text,true);

 -- ---- 5. Finance panel: a part refund keeps it, the rest closes it (A) -----
 inv:=create_invoice_with_details(st,c,jsonb_build_array(jsonb_build_object('kind','promotion','promotion_id',pa,'quantity',1)),
   jsonb_build_object('business_date',sg_today()::text));
 perform record_invoice_payment(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',610)),gen_random_uuid());
 select id into it from invoice_items where invoice_id=inv;
 select id into u from purchased_therapy_entitlements where invoice_item_id=it;
 select id into pay from invoice_payments where invoice_id=inv;
 select id into mv from stock_movements where invoice_id=inv and movement_type::text='store_sale';
 perform refund_invoice_recorded(inv,jsonb_build_array(jsonb_build_object('invoice_item_id',it,'amount',100)),
   jsonb_build_array(jsonb_build_object('payment_id',pay,'amount',100)),
   jsonb_build_array(jsonb_build_object('movement_id',mv,'not_returned_quantity',1)),'Price adjustment',gen_random_uuid());
 if (select status from purchased_therapy_entitlements where id=u)<>'pending_activation' then
  raise exception '5: a part refund by amount closed the therapy'; end if;
 perform refund_invoice_recorded(inv,jsonb_build_array(jsonb_build_object('invoice_item_id',it,'amount',510)),
   jsonb_build_array(jsonb_build_object('payment_id',pay,'amount',510)),'[]'::jsonb,'Rest refunded',gen_random_uuid());
 if (select status from purchased_therapy_entitlements where id=u)<>'refunded' then
  raise exception '5: refunding the rest of the line did not close its therapy'; end if;
 if not exists(select 1 from audit_logs where record_id=u and action='closed_with_invoice_line' and new_data->>'context'='refund') then
  raise exception '5: not audited'; end if;

 -- ---- 6. Finance panel: used therapy is refused, not refunded around -------
 inv:=create_invoice_with_details(st,c3,jsonb_build_array(jsonb_build_object('kind','promotion','promotion_id',pa,'quantity',1)),
   jsonb_build_object('business_date',sg_today()::text));
 perform record_invoice_payment(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',610)),gen_random_uuid());
 select id into it from invoice_items where invoice_id=inv;
 select id into u from purchased_therapy_entitlements where invoice_item_id=it;
 perform activate_purchased_therapy(u,sg_today(),'started');
 select id into pay from invoice_payments where invoice_id=inv;
 select id into mv from stock_movements where invoice_id=inv and movement_type::text='store_sale';
 begin
  perform refund_invoice_recorded(inv,jsonb_build_array(jsonb_build_object('invoice_item_id',it,'amount',610)),
    jsonb_build_array(jsonb_build_object('payment_id',pay,'amount',610)),
    jsonb_build_array(jsonb_build_object('movement_id',mv,'sellable_quantity',1)),'Full refund',gen_random_uuid());
  raise exception '6: a promotion was refunded in full while its therapy kept running';
 exception when others then if sqlerrm not like '%has been started%use Refund / Cancel%' then raise; end if; end;
 -- ---- 7. and a direct cancellation is refused too (C) -----------------------
 begin
  perform cancel_invoice_recorded(inv,'Cancel it',gen_random_uuid());
  raise exception '7: an invoice was cancelled around running therapy';
 exception when others then if sqlerrm not like '%has been started%Refund / Cancel%' then raise; end if; end;
 if (select status from purchased_therapy_entitlements where id=u)<>'active' or (select status from invoices where id=inv)<>'paid'
    or exists(select 1 from invoice_refunds where invoice_id=inv) then
  raise exception '6/7: a refused action changed something'; end if;
 -- vouchers collected: before 363 a direct cancellation closed this silently as if unused
 inv:=create_invoice_with_details(st,c,jsonb_build_array(jsonb_build_object('kind','promotion','promotion_id',pb,'quantity',1)),
   jsonb_build_object('business_date',sg_today()::text));
 perform record_invoice_payment(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',500)),gen_random_uuid());
 select e.id into u from purchased_therapy_entitlements e join invoice_items x on x.id=e.invoice_item_id where x.invoice_id=inv;
 perform claim_purchased_therapy(u,'voucher',null,null,null,false,jsonb_build_array(jsonb_build_object('voucher_id',v1,'quantity',1)));
 begin
  perform cancel_invoice_recorded(inv,'Cancel it',gen_random_uuid());
  raise exception '7: collected vouchers were closed by a plain cancellation';
 exception when others then if sqlerrm not like '%vouchers from it were collected%' then raise; end if; end;
 if (select status from purchased_therapy_entitlements where id=u)<>'pending_activation' then raise exception '7: refused but changed'; end if;
 -- unused: a direct cancellation still closes it, as before
 inv:=create_invoice_with_details(st,c,jsonb_build_array(jsonb_build_object('kind','promotion','promotion_id',pa,'quantity',1)),
   jsonb_build_object('business_date',sg_today()::text));
 perform record_invoice_payment(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',610)),gen_random_uuid());
 select e.id into u from purchased_therapy_entitlements e join invoice_items x on x.id=e.invoice_item_id where x.invoice_id=inv;
 perform cancel_invoice_recorded(inv,'Cancel it',gen_random_uuid());
 if (select status from purchased_therapy_entitlements where id=u)<>'refunded' then raise exception '7: unused therapy survived a cancellation'; end if;

 -- ---- 8. part refund of 1 of 2 copies closes its share, unused first (B) ----
 inv:=create_invoice_with_details(st,c4,jsonb_build_array(jsonb_build_object('kind','promotion','promotion_id',pa,'quantity',2)),
   jsonb_build_object('business_date',sg_today()::text));
 perform record_invoice_payment(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',1220)),gen_random_uuid());
 select id into it from invoice_items where invoice_id=inv;
 if (select count(*) from purchased_therapy_entitlements where invoice_item_id=it)<>2 then raise exception '8: fixture: expected 2 units'; end if;
 select id into u from purchased_therapy_entitlements where invoice_item_id=it order by unit_index limit 1;
 perform activate_purchased_therapy(u,sg_today(),'first one started');
 plan:=invoice_action_plan(inv,'refund_partial',jsonb_build_array(jsonb_build_object('invoice_item_id',it,'quantity',1)));
 if jsonb_array_length(plan->'lines'->0->'therapy_units')<>1 or (plan->'lines'->0->'therapy_units'->0->>'used')::boolean then
  raise exception '8: returning 1 of 2 should close the unused unit only: %',plan->'lines'->0->'therapy_units'; end if;
 if exists(select 1 from jsonb_array_elements(plan->'overrides_required') x where x->>'code'='therapy_activated') then
  raise exception '8: no override is needed when the unused unit goes'; end if;
 if (plan->'stock'->0->>'proposed_sellable')::int<>1 then raise exception '8: expected 1 corset offered back: %',plan->'stock'; end if;
 perform set_config('request.jwt.claim.sub',stf::text,true);
 req:=request_invoice_action_v2(inv,'refund_partial',jsonb_build_array(jsonb_build_object('invoice_item_id',it,'quantity',1)),'One returned',null,gen_random_uuid());
 perform set_config('request.jwt.claim.sub',own::text,true);
 res:=resolve_invoice_action_v2((req->>'request_id')::uuid,true,'ok',plan->>'plan_hash','[]'::jsonb,pg_temp.goods(plan),false);
 if (res->>'refunded_amount')::numeric<>610 then raise exception '8: expected 610 back: %',res; end if;
 if (select status from purchased_therapy_entitlements where id=u)<>'active' then raise exception '8: the started unit was ended'; end if;
 if (select count(*) from purchased_therapy_entitlements where invoice_item_id=it and status='refunded')<>1 then
  raise exception '8: the unused unit was not closed'; end if;
 -- two lots per copy: 1 of 2 copies is 2 of 4 units
 inv:=create_invoice_with_details(st,c,jsonb_build_array(jsonb_build_object('kind','promotion','promotion_id',p2,'quantity',2)),
   jsonb_build_object('business_date',sg_today()::text));
 perform record_invoice_payment(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',600)),gen_random_uuid());
 select id into it from invoice_items where invoice_id=inv;
 plan:=invoice_action_plan(inv,'refund_partial',jsonb_build_array(jsonb_build_object('invoice_item_id',it,'quantity',1)));
 if jsonb_array_length(plan->'lines'->0->'therapy_units')<>2 then
  raise exception '8: 1 of 2 copies of a two-lot bundle should close 2 of 4 units: %',plan->'lines'->0->'therapy_units'; end if;

 -- ---- 9. therapy sold on its own line: a cancellation ends it now ----------
 inv:=create_invoice_with_details(st,c,jsonb_build_array(jsonb_build_object('kind','therapy','therapy_package_id',tpt,'quantity',1)),
   jsonb_build_object('business_date',sg_today()::text));
 perform record_invoice_payment(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',600)),gen_random_uuid());
 select e.id into u from purchased_therapy_entitlements e join invoice_items x on x.id=e.invoice_item_id where x.invoice_id=inv;
 perform activate_purchased_therapy(u,sg_today(),'started');
 perform set_config('request.jwt.claim.sub',stf::text,true);
 req:=request_invoice_action_v2(inv,'cancel','[]'::jsonb,'Moving abroad',null,gen_random_uuid());
 perform set_config('request.jwt.claim.sub',own::text,true);
 plan:=invoice_action_plan(inv,'cancel');
 res:=resolve_invoice_action_v2((req->>'request_id')::uuid,true,'Cancelled, refund on Friday',plan->>'plan_hash',
   jsonb_build_array(jsonb_build_object('code','therapy_activated','reason','Five months unused','amount',500)),null,false);
 if (select status from invoices where id=inv)<>'cancelled' then raise exception '9: not cancelled'; end if;
 if (select status from purchased_therapy_entitlements where id=u)<>'refunded' then
  raise exception '9: therapy kept running on a cancelled invoice after its termination was authorized'; end if;
 if coalesce((res->>'refund_recorded')::boolean,false) then raise exception '9: no money was said to go back'; end if;

 -- ---- 10. units no line holds (a correction deleted the line) ---------------
 -- (a) the guided full refund lists and closes an unused one
 inv:=create_invoice_with_details(st,c5,jsonb_build_array(jsonb_build_object('kind','promotion','promotion_id',pa,'quantity',1)),
   jsonb_build_object('business_date',sg_today()::text));
 perform record_invoice_payment(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',610)),gen_random_uuid());
 select id into orphan from purchased_therapy_entitlements where invoice_id=inv;
 -- detached as the pre-guided paid-invoice edit left UTP-0000002 (a correction
 -- could do the same until the correction migration, 362, settles its therapy)
 update purchased_therapy_entitlements set invoice_item_id=null where id=orphan;
 plan:=invoice_action_plan(inv,'refund_full');
 if not exists(select 1 from jsonb_array_elements_text(plan->'summary') t where t like 'Close therapy %on no invoice line: not used yet.') then
  raise exception '10a: the plan does not say the detached unit closes: %',plan->'summary'; end if;
 if not exists(select 1 from jsonb_array_elements(plan#>'{effects,therapy_closed}') t where t->>'line'='no invoice line') then
  raise exception '10a: effects.therapy_closed omits the detached unit'; end if;
 perform set_config('request.jwt.claim.sub',stf::text,true);
 req:=request_invoice_action_v2(inv,'refund_full','[]'::jsonb,'Returned',null,gen_random_uuid());
 perform set_config('request.jwt.claim.sub',own::text,true);
 perform resolve_invoice_action_v2((req->>'request_id')::uuid,true,'ok',plan->>'plan_hash','[]'::jsonb,pg_temp.goods(plan),false);
 if (select status from purchased_therapy_entitlements where id=orphan)<>'refunded'
    or not exists(select 1 from audit_logs where record_id=orphan and action='closed_with_invoice_line'
                   and new_data->>'invoice_item_id' is null and new_data->>'context'='refund_full') then
  raise exception '10a: the detached unit was not closed as reviewed'; end if;
 -- (b) a used one is left as it is and no longer blocks a cancellation
 inv:=create_invoice_with_details(st,c6,jsonb_build_array(jsonb_build_object('kind','promotion','promotion_id',pa,'quantity',1)),
   jsonb_build_object('business_date',sg_today()::text));
 perform record_invoice_payment(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',610)),gen_random_uuid());
 select id into orphan from purchased_therapy_entitlements where invoice_id=inv;
 -- detached as the pre-guided paid-invoice edit left UTP-0000002 (a correction
 -- could do the same until the correction migration, 362, settles its therapy)
 update purchased_therapy_entitlements set invoice_item_id=null where id=orphan;
 perform activate_purchased_therapy(orphan,sg_today(),'started after the swap');
 plan:=invoice_action_plan(inv,'cancel');
 if exists(select 1 from jsonb_array_elements(plan->'overrides_required') x where x->>'code'='therapy_activated') then
  raise exception '10b: a detached used unit asked for an override no line can carry'; end if;
 if not exists(select 1 from jsonb_array_elements_text(plan->'summary') t where t like '%on no invoice line%has been used, so it is left running.') then
  raise exception '10b: the plan does not say the detached used unit is left: %',plan->'summary'; end if;
 if not exists(select 1 from jsonb_array_elements(plan#>'{effects,therapy_left}') t where t->>'entitlement_no'=(select entitlement_no from purchased_therapy_entitlements where id=orphan)) then
  raise exception '10b: effects.therapy_left does not show the unit left running'; end if;
 perform set_config('request.jwt.claim.sub',stf::text,true);
 req:=request_invoice_action_v2(inv,'cancel','[]'::jsonb,'Wrong customer',null,gen_random_uuid());
 perform set_config('request.jwt.claim.sub',own::text,true);
 res:=resolve_invoice_action_v2((req->>'request_id')::uuid,true,'ok',plan->>'plan_hash','[]'::jsonb,pg_temp.goods(plan),false);
 if (select status from invoices where id=inv)<>'cancelled' then raise exception '10b: the invoice could not be cancelled: %',res; end if;
 if (select status from purchased_therapy_entitlements where id=orphan)<>'active' then
  raise exception '10b: a detached used unit was ended with no override'; end if;
 -- (c) the Finance panel: a fully refunded invoice closes an unused one
 inv:=create_invoice_with_details(st,c,jsonb_build_array(jsonb_build_object('kind','promotion','promotion_id',pa,'quantity',1)),
   jsonb_build_object('business_date',sg_today()::text));
 perform record_invoice_payment(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',610)),gen_random_uuid());
 select id into it from invoice_items where invoice_id=inv;
 insert into purchased_therapy_entitlements(entitlement_no,customer_id,store_id,package_id,invoice_id,invoice_item_id,
   package_name,duration_months,price_snapshot,purchase_date,activation_deadline,status,benefit_choice,offered_choices)
 select next_purchased_therapy_no(),customer_id,store_id,package_id,invoice_id,null,package_name,duration_months,0,
        purchase_date,activation_deadline,'pending_activation',benefit_choice,offered_choices
   from purchased_therapy_entitlements where invoice_id=inv returning id into orphan;
 select id into pay from invoice_payments where invoice_id=inv;
 select id into mv from stock_movements where invoice_id=inv and movement_type::text='store_sale';
 perform refund_invoice_recorded(inv,jsonb_build_array(jsonb_build_object('invoice_item_id',it,'amount',610)),
   jsonb_build_array(jsonb_build_object('payment_id',pay,'amount',610)),
   jsonb_build_array(jsonb_build_object('movement_id',mv,'sellable_quantity',1)),'Refunded at the counter',gen_random_uuid());
 if (select status from invoices where id=inv)<>'refunded' then raise exception '10c: not refunded'; end if;
 if (select status from purchased_therapy_entitlements where id=orphan)<>'refunded'
    or not exists(select 1 from audit_logs where record_id=orphan and action='closed_with_invoice') then
  raise exception '10c: the orphan unit stayed open on a refunded invoice'; end if;

 -- ---- 11. a later part refund takes the rest of the line (B) ---------------
 inv:=create_invoice_with_details(st,c7,jsonb_build_array(jsonb_build_object('kind','promotion','promotion_id',p2,'quantity',2)),
   jsonb_build_object('business_date',sg_today()::text));
 perform record_invoice_payment(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',600)),gen_random_uuid());
 select id into it from invoice_items where invoice_id=inv;
 select id into u from purchased_therapy_entitlements where invoice_item_id=it order by unit_index limit 1;
 perform activate_purchased_therapy(u,sg_today(),'one lot started');
 plan:=invoice_action_plan(inv,'refund_partial',jsonb_build_array(jsonb_build_object('invoice_item_id',it,'quantity',1)));
 if jsonb_array_length(plan->'lines'->0->'therapy_units')<>2
    or exists(select 1 from jsonb_array_elements(plan->'lines'->0->'therapy_units') t where (t->>'used')::boolean) then
  raise exception '11: the first copy back should close 2 unused lots: %',plan->'lines'->0->'therapy_units'; end if;
 perform set_config('request.jwt.claim.sub',stf::text,true);
 req:=request_invoice_action_v2(inv,'refund_partial',jsonb_build_array(jsonb_build_object('invoice_item_id',it,'quantity',1)),'One back',null,gen_random_uuid());
 perform set_config('request.jwt.claim.sub',own::text,true);
 perform resolve_invoice_action_v2((req->>'request_id')::uuid,true,'ok',plan->>'plan_hash','[]'::jsonb,null,false);
 if (select count(*) from purchased_therapy_entitlements where invoice_item_id=it and status='refunded')<>2 then
  raise exception '11: the first copy did not close exactly 2 units'; end if;
 -- the last copy is everything left on the line: all of its units, the used one on the override
 plan:=invoice_action_plan(inv,'refund_partial',jsonb_build_array(jsonb_build_object('invoice_item_id',it,'quantity',1)));
 if jsonb_array_length(plan->'lines'->0->'therapy_units')<>2
    or not exists(select 1 from jsonb_array_elements(plan->'overrides_required') x where x->>'code'='therapy_activated') then
  raise exception '11: the last copy must list both remaining units and ask for the override: %',plan->'lines'->0->'therapy_units'; end if;
 perform set_config('request.jwt.claim.sub',stf::text,true);
 req:=request_invoice_action_v2(inv,'refund_partial',jsonb_build_array(jsonb_build_object('invoice_item_id',it,'quantity',1)),'The other back',null,gen_random_uuid());
 perform set_config('request.jwt.claim.sub',own::text,true);
 res:=resolve_invoice_action_v2((req->>'request_id')::uuid,true,'ok',plan->>'plan_hash',
   jsonb_build_array(jsonb_build_object('code','therapy_activated','reason','One lot used for a week','amount',250)),null,false);
 if res->>'status'<>'approved' then raise exception '11: the last copy was refused: %',res; end if;
 if exists(select 1 from purchased_therapy_entitlements where invoice_item_id=it and status not in ('refunded','cancelled')) then
  raise exception '11: a unit of a fully refunded line is still open'; end if;

 -- ---- 12. after a price adjustment, a guided copy that takes the rest lists every unit
 inv:=create_invoice_with_details(st,c8,jsonb_build_array(jsonb_build_object('kind','promotion','promotion_id',pa,'quantity',2)),
   jsonb_build_object('business_date',sg_today()::text));
 perform record_invoice_payment(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',1220)),gen_random_uuid());
 select id into it from invoice_items where invoice_id=inv;
 select id into pay from invoice_payments where invoice_id=inv;
 select id into mv from stock_movements where invoice_id=inv and movement_type::text='store_sale';
 perform refund_invoice_recorded(inv,jsonb_build_array(jsonb_build_object('invoice_item_id',it,'amount',700)),
   jsonb_build_array(jsonb_build_object('payment_id',pay,'amount',700)),
   jsonb_build_array(jsonb_build_object('movement_id',mv,'not_returned_quantity',1)),'Price adjustment',gen_random_uuid());
 if (select count(*) from purchased_therapy_entitlements where invoice_item_id=it and status='pending_activation')<>2 then
  raise exception '12: a price adjustment closed therapy'; end if;
 plan:=invoice_action_plan(inv,'refund_partial',jsonb_build_array(jsonb_build_object('invoice_item_id',it,'quantity',1)));
 if (plan->'lines'->0->>'amount')::numeric<>520 or jsonb_array_length(plan->'lines'->0->'therapy_units')<>2 then
  raise exception '12: a copy taking the remaining 520 must list both units: %',plan->'lines'->0; end if;
 perform set_config('request.jwt.claim.sub',stf::text,true);
 req:=request_invoice_action_v2(inv,'refund_partial',jsonb_build_array(jsonb_build_object('invoice_item_id',it,'quantity',1)),'Rest back',null,gen_random_uuid());
 perform set_config('request.jwt.claim.sub',own::text,true);
 perform resolve_invoice_action_v2((req->>'request_id')::uuid,true,'ok',plan->>'plan_hash','[]'::jsonb,pg_temp.goods(plan),false);
 if (select count(*) from purchased_therapy_entitlements where invoice_item_id=it and status='refunded')<>2 then
  raise exception '12: the units listed were not both closed'; end if;

 -- ---- 13. a product line and a promotion drawing on one stock movement -----
 inv:=create_invoice_with_details(st,c9,jsonb_build_array(
   jsonb_build_object('kind','product','product_id',pc,'quantity',1),
   jsonb_build_object('kind','promotion','promotion_id',pa,'quantity',1)),jsonb_build_object('business_date',sg_today()::text));
 perform record_invoice_payment(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',810)),gen_random_uuid());
 select count(*), sum(quantity) into mvn, qty0 from stock_movements where invoice_id=inv and movement_type::text='store_sale' and product_id=pc;
 -- read the lines in the other order too (an index scan gives cart order)
 perform set_config('enable_seqscan','off',true);
 plan:=invoice_action_plan(inv,'refund_full');
 perform set_config('enable_seqscan','on',true);
 if coalesce((select sum((k->>'proposed_sellable')::int) from jsonb_array_elements(plan->'stock') k),0)<>qty0 then
  raise exception '13: with the lines read in cart order, expected both corsets offered back (%), got %',qty0,plan->'stock'; end if;
 plan:=invoice_action_plan(inv,'refund_full');
 if (select count(*) from jsonb_array_elements(plan->'stock') k group by k->>'movement_id' order by 1 desc limit 1)>1 then
  raise exception '13: one movement appears twice in the stock to confirm: %',plan->'stock'; end if;
 if (select sum((k->>'proposed_sellable')::int) from jsonb_array_elements(plan->'stock') k)<>qty0 then
  raise exception '13: expected both corsets offered back (%), got %',qty0,plan->'stock'; end if;
 qty0:=(select current_qty from store_inventory where store_id=st and product_id=pc);
 perform set_config('request.jwt.claim.sub',stf::text,true);
 req:=request_invoice_action_v2(inv,'refund_full','[]'::jsonb,'All returned',null,gen_random_uuid());
 perform set_config('request.jwt.claim.sub',own::text,true);
 perform resolve_invoice_action_v2((req->>'request_id')::uuid,true,'ok',plan->>'plan_hash','[]'::jsonb,pg_temp.goods(plan),false);
 if (select current_qty from store_inventory where store_id=st and product_id=pc)<>qty0+2 then
  raise exception '13: expected both corsets back on sale (from % to %)',qty0,(select current_qty from store_inventory where store_id=st and product_id=pc); end if;

 -- ---- 14. a used promotion line the payments no longer cover: state 0 ------
 -- Two lines of the bundle; the money held covers one. Whichever line the plan
 -- leaves at 0 has its therapy started.
 inv:=create_invoice_with_details(st,c10,jsonb_build_array(
   jsonb_build_object('kind','promotion','promotion_id',pa,'quantity',1),
   jsonb_build_object('kind','promotion','promotion_id',pa,'quantity',1)),jsonb_build_object('business_date',sg_today()::text));
 perform record_invoice_payment(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',1220)),gen_random_uuid());
 select id into pay from invoice_payments where invoice_id=inv;
 perform correct_invoice_payment(pay,610,sg_today(),pm,'Only 610 was really received',gen_random_uuid());
 plan:=invoice_action_plan(inv,'refund_full');
 select (l->>'invoice_item_id')::uuid into it from jsonb_array_elements(plan->'lines') l where (l->>'amount')::numeric=0 limit 1;
 if it is null then raise exception '14: fixture: expected one line left at 0 by the money held: %',plan->'lines'; end if;
 select id into u from purchased_therapy_entitlements where invoice_item_id=it;
 perform activate_purchased_therapy(u,sg_today(),'started');
 plan:=invoice_action_plan(inv,'refund_full');
 if (select (x->>'default_amount')::numeric from jsonb_array_elements(plan->'overrides_required') x
      where x->>'code'='therapy_activated' and x->>'invoice_item_id'=it::text)<>0 then
  raise exception '14: the pre-filled amount is not the line''s figure after the money cap: %',plan->'overrides_required'; end if;
 perform set_config('request.jwt.claim.sub',stf::text,true);
 req:=request_invoice_action_v2(inv,'refund_full','[]'::jsonb,'All returned',null,gen_random_uuid());
 perform set_config('request.jwt.claim.sub',own::text,true);
 res:=resolve_invoice_action_v2((req->>'request_id')::uuid,true,'ok',plan->>'plan_hash',
   jsonb_build_array(jsonb_build_object('code','therapy_activated','reason','Nothing was paid for it','amount',0)),pg_temp.goods(plan),false);
 if res->>'status'<>'approved' then raise exception '14: stating 0 for an uncovered used line was refused: %',res; end if;
 if (select status from purchased_therapy_entitlements where id=u)<>'refunded' then raise exception '14: the used unit was not ended'; end if;
 if not exists(select 1 from audit_logs where record_id=u and action='authorized_termination' and (new_data->>'amount')::numeric=0) then
  raise exception '14: the termination was not audited with the stated 0'; end if;
 if (res->>'refunded_amount')::numeric<>610 then raise exception '14: expected the 610 held to go back, got %',res->>'refunded_amount'; end if;
 if exists(select 1 from purchased_therapy_entitlements where invoice_id=inv and status not in ('refunded','cancelled')) then
  raise exception '14: a unit of the fully refunded invoice is still open'; end if;

 -- ---- 15. a part refund that closes the invoice closes an unused detached unit
 inv:=create_invoice_with_details(st,c11,jsonb_build_array(jsonb_build_object('kind','promotion','promotion_id',pa,'quantity',1)),
   jsonb_build_object('business_date',sg_today()::text));
 perform record_invoice_payment(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',610)),gen_random_uuid());
 select id into orphan from purchased_therapy_entitlements where invoice_id=inv;
 -- detached as the pre-guided paid-invoice edit left UTP-0000002 (a correction
 -- could do the same until the correction migration, 362, settles its therapy)
 update purchased_therapy_entitlements set invoice_item_id=null where id=orphan;
 select id into it from invoice_items where invoice_id=inv;
 plan:=invoice_action_plan(inv,'refund_partial',jsonb_build_array(jsonb_build_object('invoice_item_id',it,'quantity',1)));
 if not exists(select 1 from jsonb_array_elements(plan->'detached_therapy') t where t->>'id'=orphan::text) then
  raise exception '15: a part refund that pays back all that is left does not list the detached unit: %',plan->'detached_therapy'; end if;
 perform set_config('request.jwt.claim.sub',stf::text,true);
 req:=request_invoice_action_v2(inv,'refund_partial',jsonb_build_array(jsonb_build_object('invoice_item_id',it,'quantity',1)),'Returned',null,gen_random_uuid());
 perform set_config('request.jwt.claim.sub',own::text,true);
 perform resolve_invoice_action_v2((req->>'request_id')::uuid,true,'ok',plan->>'plan_hash','[]'::jsonb,pg_temp.goods(plan),false);
 if (select status from invoices where id=inv)<>'refunded' or (select status from purchased_therapy_entitlements where id=orphan)<>'refunded' then
  raise exception '15: the invoice closed but the detached unit stayed open'; end if;

 -- ---- 16. an amount that pays back the whole line needs the whole line reviewed
 inv:=create_invoice_with_details(st,c12,jsonb_build_array(jsonb_build_object('kind','promotion','promotion_id',pb,'quantity',2)),
   jsonb_build_object('business_date',sg_today()::text));
 perform record_invoice_payment(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',1000)),gen_random_uuid());
 select id into it from invoice_items where invoice_id=inv;
 for u in select id from purchased_therapy_entitlements where invoice_item_id=it loop
  perform claim_purchased_therapy(u,'voucher',null,null,null,false,jsonb_build_array(jsonb_build_object('voucher_id',v1,'quantity',1)));
 end loop;
 plan:=invoice_action_plan(inv,'refund_partial',jsonb_build_array(jsonb_build_object('invoice_item_id',it,'quantity',1)));
 if jsonb_array_length(plan->'lines'->0->'therapy_units')<>1 then raise exception '16: fixture: expected a share of 1 unit'; end if;
 perform set_config('request.jwt.claim.sub',stf::text,true);
 req:=request_invoice_action_v2(inv,'refund_partial',jsonb_build_array(jsonb_build_object('invoice_item_id',it,'quantity',1)),'One back',null,gen_random_uuid());
 perform set_config('request.jwt.claim.sub',own::text,true);
 begin
  perform resolve_invoice_action_v2((req->>'request_id')::uuid,true,'ok',plan->>'plan_hash',
    jsonb_build_array(jsonb_build_object('code','therapy_activated','reason','All of it','amount',1000)),pg_temp.goods(plan),false);
  raise exception '16: all of the line was paid back while part of its therapy stayed open';
 exception when others then if sqlerrm not like '%pays back all of%Full refund%' then raise; end if; end;
 if exists(select 1 from invoice_refunds where invoice_id=inv) then raise exception '16: a refused approval refunded money'; end if;
 res:=resolve_invoice_action_v2((req->>'request_id')::uuid,true,'ok',plan->>'plan_hash',
   jsonb_build_array(jsonb_build_object('code','therapy_activated','reason','One set used','amount',400)),pg_temp.goods(plan),false);
 if (res->>'refunded_amount')::numeric<>400
    or (select count(*) from purchased_therapy_entitlements where invoice_item_id=it and status='refunded')<>1 then
  raise exception '16: the share refund did not end exactly one unit for 400: %',res; end if;

 -- ---- 17. a promotion that issues vouchers and grants therapy -----------------
 inv:=create_invoice_with_details(st,c13,jsonb_build_array(jsonb_build_object('kind','promotion','promotion_id',pv,'quantity',1)),
   jsonb_build_object('business_date',sg_today()::text));
 perform record_invoice_payment(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',500)),gen_random_uuid());
 select e.id into u from purchased_therapy_entitlements e where e.invoice_id=inv;
 perform activate_purchased_therapy(u,sg_today(),'started');
 plan:=invoice_action_plan(inv,'refund_full');
 if not exists(select 1 from jsonb_array_elements(plan->'overrides_required') x
                where x->>'code'='therapy_activated' and not (x->>'amount_required')::boolean) then
  raise exception '17: a line whose refund is fixed by its vouchers must not ask for an amount: %',plan->'overrides_required'; end if;
 perform set_config('request.jwt.claim.sub',stf::text,true);
 req:=request_invoice_action_v2(inv,'refund_full','[]'::jsonb,'Returned',null,gen_random_uuid());
 perform set_config('request.jwt.claim.sub',own::text,true);
 res:=resolve_invoice_action_v2((req->>'request_id')::uuid,true,'ok',plan->>'plan_hash',
   jsonb_build_array(jsonb_build_object('code','therapy_activated','reason','Vouchers unused, therapy a week in')),pg_temp.goods(plan),false);
 if res->>'status'<>'approved' or (select status from purchased_therapy_entitlements where id=u)<>'refunded' then
  raise exception '17: refund with the reason alone failed: %',res; end if;
 if not exists(select 1 from audit_logs where record_id=u and action='authorized_termination'
                and (new_data->>'amount')::numeric=(res->>'refunded_amount')::numeric) then
  raise exception '17: the termination does not record the line''s own figure'; end if;

 -- ---- 18. goods chosen per copy: a full refund offers every garment --------------
 -- (Goods are listed by 361. A part refund of one copy currently offers the
 -- garments of every copy, because nothing records which copy chose which;
 -- reported with 363, not changed by it.)
 inv:=create_invoice_with_details(st,c14,jsonb_build_array(jsonb_build_object('kind','promotion','promotion_id',pch,'quantity',2,
   'selections',jsonb_build_array(jsonb_build_object('group_id',grp,'options',jsonb_build_array(
     jsonb_build_object('product_id',pc,'quantity',1),jsonb_build_object('product_id',pbelt,'quantity',1)))))),
   jsonb_build_object('business_date',sg_today()::text));
 perform record_invoice_payment(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',800)),gen_random_uuid());
 select id into it from invoice_items where invoice_id=inv;
 plan:=invoice_action_plan(inv,'refund_full');
 if coalesce((select sum((k->>'proposed_sellable')::int) from jsonb_array_elements(plan->'stock') k),0)<>2 then
  raise exception '18: a full refund should offer both garments, got %',plan->'stock'; end if;

 -- ---- 19. two lines with used therapy: each its own override ------------------
 inv:=create_invoice_with_details(st,c15,jsonb_build_array(
   jsonb_build_object('kind','promotion','promotion_id',pa,'quantity',1),
   jsonb_build_object('kind','promotion','promotion_id',pb,'quantity',1)),jsonb_build_object('business_date',sg_today()::text));
 perform record_invoice_payment(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',1110)),gen_random_uuid());
 select ii.id, e.id into it, u from invoice_items ii join purchased_therapy_entitlements e on e.invoice_item_id=ii.id
  where ii.invoice_id=inv and ii.promotion_id=pa;
 select ii.id, e.id into it2, u3 from invoice_items ii join purchased_therapy_entitlements e on e.invoice_item_id=ii.id
  where ii.invoice_id=inv and ii.promotion_id=pb;
 perform activate_purchased_therapy(u,sg_today(),'started');
 perform claim_purchased_therapy(u3,'voucher',null,null,null,false,jsonb_build_array(jsonb_build_object('voucher_id',v1,'quantity',1)));
 plan:=invoice_action_plan(inv,'cancel');
 if (select count(*) from jsonb_array_elements(plan->'overrides_required') x where x->>'code'='therapy_activated')<>2 then
  raise exception '19: fixture: expected two therapy overrides'; end if;
 -- one reason for a code no longer covers a line it does not name
 perform set_config('request.jwt.claim.sub',stf::text,true);
 req:=request_invoice_action_v2(inv,'cancel','[]'::jsonb,'Customer withdrew',null,gen_random_uuid());
 perform set_config('request.jwt.claim.sub',own::text,true);
 begin
  perform resolve_invoice_action_v2((req->>'request_id')::uuid,true,'ok',plan->>'plan_hash',
    jsonb_build_array(jsonb_build_object('code','therapy_activated','reason','A only','amount',100,'invoice_item_id',it)),
    pg_temp.goods(plan),false);
  raise exception '19: the second line''s therapy was ended without its own override';
 exception when others then if sqlerrm not like '%override reason is required for: therapy_activated%' then raise; end if; end;
 res:=resolve_invoice_action_v2((req->>'request_id')::uuid,true,'ok',plan->>'plan_hash',
   jsonb_build_array(
     jsonb_build_object('code','therapy_activated','reason','Bundle A: a month used','amount',100,'invoice_item_id',it),
     jsonb_build_object('code','therapy_activated','reason','Bundle B: one facial collected','amount',50,'invoice_item_id',it2)),
   pg_temp.goods(plan),false);
 if (select status from invoices where id=inv)<>'cancelled' then raise exception '19: not cancelled: %',res; end if;
 if not exists(select 1 from audit_logs where record_id=u and action='authorized_termination'
                and (new_data->>'amount')::numeric=100 and new_data->'override'->>'reason' like 'Bundle A%')
    or not exists(select 1 from audit_logs where record_id=u3 and action='authorized_termination'
                and (new_data->>'amount')::numeric=50 and new_data->'override'->>'reason' like 'Bundle B%') then
  raise exception '19: each line did not end on its own reason and amount'; end if;

 -- ---- 20. overrides that name no line (a request from before 363) ------------
 -- A plain promotion states an amount; a voucher promotion's refund is fixed by
 -- its vouchers. The amount naming no line must not land on the voucher line.
 inv:=create_invoice_with_details(st,c16,jsonb_build_array(
   jsonb_build_object('kind','promotion','promotion_id',pb,'quantity',1),
   jsonb_build_object('kind','promotion','promotion_id',pv,'quantity',1)),jsonb_build_object('business_date',sg_today()::text));
 perform record_invoice_payment(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',1000)),gen_random_uuid());
 select ii.id, e.id into it, u from invoice_items ii join purchased_therapy_entitlements e on e.invoice_item_id=ii.id
  where ii.invoice_id=inv and ii.promotion_id=pb;
 select ii.id, e.id into it2, u3 from invoice_items ii join purchased_therapy_entitlements e on e.invoice_item_id=ii.id
  where ii.invoice_id=inv and ii.promotion_id=pv;
 perform claim_purchased_therapy(u,'voucher',null,null,null,false,jsonb_build_array(jsonb_build_object('voucher_id',v1,'quantity',1)));
 perform activate_purchased_therapy(u3,sg_today(),'started');
 plan:=invoice_action_plan(inv,'refund_full');
 amt:=(select (l->>'amount')::numeric from jsonb_array_elements(plan->'lines') l where l->>'invoice_item_id'=it2::text);
 perform set_config('request.jwt.claim.sub',stf::text,true);
 req:=request_invoice_action_v2(inv,'refund_full','[]'::jsonb,'Both returned',null,gen_random_uuid());
 perform set_config('request.jwt.claim.sub',own::text,true);
 -- the reason-only override first: the one carrying the amount must still be found
 res:=resolve_invoice_action_v2((req->>'request_id')::uuid,true,'ok',plan->>'plan_hash',
   jsonb_build_array(jsonb_build_object('code','therapy_activated','reason','Old dialog'),
                     jsonb_build_object('code','therapy_activated','reason','Old dialog','amount',300)),pg_temp.goods(plan),false);
 if res->>'status'<>'approved' then raise exception '20: a request with overrides naming no line was refused: %',res; end if;
 if (res->>'refunded_amount')::numeric<>300+amt then
  raise exception '20: expected 300 for the plain promotion plus % for the voucher one, got %',amt,res->>'refunded_amount'; end if;
 if not exists(select 1 from audit_logs where record_id=u3 and action='authorized_termination' and (new_data->>'amount')::numeric=amt)
    or not exists(select 1 from audit_logs where record_id=u and action='authorized_termination' and (new_data->>'amount')::numeric=300) then
  raise exception '20: a termination recorded another line''s amount'; end if;

 -- ---- 21. bystanders, store access and permissions ----------------------------
 if (select status from purchased_therapy_entitlements where id=u2)<>'pending_activation' then
  raise exception '21: another customer''s therapy changed'; end if;
 perform set_config('request.jwt.claim.sub',mgr2::text,true);
 begin
  perform close_invoice_therapy_units(other,(select id from invoice_items where invoice_id=other),null,
    jsonb_build_object('code','therapy_activated','reason','x','amount',0),0,'x',gen_random_uuid(),'refund');
  raise exception '21: a manager of another store closed this store''s therapy';
 exception when others then if sqlerrm not like '%Invoice not accessible%' then raise; end if; end;
 perform set_config('request.jwt.claim.sub',own::text,true);
 if (select status from purchased_therapy_entitlements where id=u2)<>'pending_activation' then
  raise exception '21: a refused call changed another customer''s therapy'; end if;
 if has_function_privilege('authenticated','public.close_invoice_therapy_units(uuid,uuid,uuid[],jsonb,numeric,text,uuid,text)','execute')
    or has_function_privilege('anon','public.close_invoice_therapy_units(uuid,uuid,uuid[],jsonb,numeric,text,uuid,text)','execute') then
  raise exception '21: the helper is callable from the API'; end if;
 inv:=create_invoice_with_details(st,c,jsonb_build_array(jsonb_build_object('kind','product','product_id',pc,'quantity',1)),
   jsonb_build_object('business_date',sg_today()::text));
 if exists(select 1 from jsonb_array_elements(invoice_action_plan(inv,'cancel')->'lines') l where l ? 'therapy_units') then
  raise exception '21: a line with no therapy carries therapy_units, changing every plan''s hash'; end if;

 raise notice 'PASS: a promotion''s therapy closes with its line (full refund, cancellation, its share of a part refund, unused first, and all of it once the line is paid back); used therapy or collected vouchers need the Owner/Manager amount, 0 included, re-review when they change, and keep their history; a part refund by amount keeps it; the Finance panel and a direct cancellation refuse rather than refund or cancel around running therapy; a promotion''s goods are offered back, one row per movement; units no line holds close when unused (also when a part refund closes the invoice) and are left, without blocking, when used; an amount paying back a whole line needs the whole line reviewed; vouchers-backed lines need a reason, not an amount; goods chosen per copy come back per copy; two lines each take their own override; other stores, bystanders and API access untouched';
end $$;
rollback;
