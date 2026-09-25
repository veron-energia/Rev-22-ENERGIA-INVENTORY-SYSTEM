-- Packages cover therapy services, and a purchase is claimed in one step (359).
--
--   * any unlimited or choice package can list the services it covers; the
--     unit copies them when sold, each with the service's own limit;
--   * a vouchers-only package takes its services from its voucher; a choice
--     package offers session vouchers only;
--   * Claim chooses and starts therapy, or chooses and hands over vouchers, in
--     one transaction; an overlap asks first and records nothing;
--   * a scheduled unit is claimed again to start it now or move it; its own
--     period is not an overlap, and a unit Reschedule left without a start can
--     still be started;
--   * collected vouchers make a unit "used" for refunds, in the guided flow and
--     in the engine; uncollected ones are withdrawn;
--   * a unit taken as vouchers is not listed as unlimited therapy, is listed
--     as unclaimed only while vouchers are owed, and — unchanged — still stops
--     the same package being bought again while it is current.
--
-- Disposable database only; everything is rolled back.
begin;
do $$
declare own uuid:=gen_random_uuid(); stf uuid:=gen_random_uuid(); tag text:=substr(md5(random()::text),1,6);
 st uuid; c uuid; c2 uuid; c3 uuid; c4 uuid; c5 uuid; pm uuid; inv5 uuid; inv6 uuid; inv7 uuid; u5 uuid; u6 uuid;
 u7 uuid; ua uuid; ub uuid; uc uuid; d6 date; svc_pr uuid; svc_f uuid; svc_old uuid; v1 uuid; v2 uuid; vdisc uuid;
 p_unl uuid; p_ch uuid; p_v uuid; inv uuid; inv2 uuid; inv3 uuid; inv4 uuid; it uuid;
 u uuid; u2 uuid; u3 uuid; u4 uuid; r jsonb; plan jsonb; req jsonb; res jsonb; rq uuid; n int; s text;
 ent uuid;
begin
 insert into auth.users(id,email) values(own,'psc-own-'||tag||'@tests.invalid'),(stf,'psc-stf-'||tag||'@tests.invalid');
 insert into profiles(id,full_name,email,role) values
   (own,'Owner','psc-own-'||tag||'@tests.invalid','owner'),(stf,'Staff','psc-stf-'||tag||'@tests.invalid','staff');
 perform set_config('request.jwt.claim.sub',own::text,true);
 insert into stores(name,code,country_code) values('PSC Store '||tag,'PSC'||tag,'SG') returning id into st;
 insert into user_store_assignments(user_id,store_id) values(stf,st);
 insert into customers(full_name,phone) values('PSC Buyer','+6598'||lpad((floor(random()*900000)+100000)::int::text,6,'0')) returning id into c;
 insert into customers(full_name,phone) values('PSC Second','+6598'||lpad((floor(random()*900000)+100000)::int::text,6,'0')) returning id into c2;
 insert into customers(full_name,phone) values('PSC Third','+6598'||lpad((floor(random()*900000)+100000)::int::text,6,'0')) returning id into c3;
 insert into customers(full_name,phone) values('PSC Fifth','+6598'||lpad((floor(random()*900000)+100000)::int::text,6,'0')) returning id into c5;
 insert into customers(full_name,phone) values('PSC Fourth','+6598'||lpad((floor(random()*900000)+100000)::int::text,6,'0')) returning id into c4;
 insert into payment_methods(name) values('PSC Cash '||tag) returning id into pm;
 insert into vouchers(name,code,voucher_kind,qty_type,selling_price,is_active)
  values('PSC MEOL '||tag,'PSCM'||tag,'normal','limited',50,true) returning id into v1;
 insert into vouchers(name,code,voucher_kind,qty_type,selling_price,is_active)
  values('PSC 3in1 '||tag,'PSC3'||tag,'normal','unlimited',50,true) returning id into v2;
 insert into vouchers(name,code,voucher_kind,qty_type,selling_price,discount_percent,is_active)
  values('PSC 50% '||tag,'PSCD'||tag,'percentage_discount','unlimited',0,50,true) returning id into vdisc;
 insert into voucher_store_stock(voucher_id,store_id,current_qty) values(v1,st,50);

 svc_pr:=(upsert_therapy_service(null,'psc-pr-'||tag,'PSC Recharge '||tag,72,20,'per_hours',1,5,null,true,null)->>'id')::uuid;
 svc_f :=(upsert_therapy_service(null,'psc-f-'||tag,'PSC Facial '||tag,194,60,'unrestricted',1,null,null,true,null)->>'id')::uuid;
 svc_old:=(upsert_therapy_service(null,'psc-o-'||tag,'PSC Old '||tag,50,30,'unrestricted',1,null,null,true,null)->>'id')::uuid;
 perform archive_therapy_service(svc_old,'retired');

 -- ---- 1. saving packages ------------------------------------------------------
 -- a NEW unlimited package keeps its SKU (it used to be dropped) and its services
 p_unl:=save_therapy_package(null,'PSC 3 months '||tag,'PSC-U-'||tag,null,true,'unlimited',3,null,null,null,array[svc_pr,svc_f,svc_f]);
 if (select sku from unlimited_therapy_packages where id=p_unl)<>'PSC-U-'||tag then
  raise exception 'The SKU of a new unlimited package was not saved'; end if;
 if (select count(*) from therapy_package_services where package_id=p_unl)<>2 then
  raise exception 'An unlimited package did not keep its two services'; end if;

 -- an archived service cannot be newly linked
 begin
  perform save_therapy_package(p_unl,'PSC 3 months '||tag,'PSC-U-'||tag,null,true,'unlimited',3,null,null,null,array[svc_pr,svc_old]);
  raise exception 'An archived service was linked';
 exception when others then if sqlerrm not like '%archived or no longer exists%' then raise; end if; end;

 -- a vouchers-only package takes its services from its voucher
 begin
  perform save_therapy_package(null,'PSC vouchers '||tag,null,null,true,'voucher',null,5,v1,null,array[svc_pr]);
  raise exception 'A vouchers-only package accepted services';
 exception when others then if sqlerrm not like '%covers what its voucher covers%' then raise; end if; end;
 p_v:=save_therapy_package(null,'PSC vouchers '||tag,'PSC-V-'||tag,null,true,'voucher',null,5,v1,null,null);
 if (select sku from unlimited_therapy_packages where id=p_v)<>'PSC-V-'||tag then
  raise exception 'The SKU of a new voucher package was not saved'; end if;

 -- a choice package offers session vouchers only
 begin
  perform save_therapy_package(null,'PSC choice '||tag,null,null,true,'choice',1,10,null,array[v1,vdisc],array[svc_pr]);
  raise exception 'A discount voucher was offered as a therapy choice';
 exception when others then if sqlerrm not like '%session vouchers%' then raise; end if; end;
 p_ch:=save_therapy_package(null,'PSC choice '||tag,'PSC-C-'||tag,null,true,'choice',1,10,null,array[v1,v2],array[svc_pr,svc_f]);
 if (select entitlement_kind from unlimited_therapy_packages where id=p_ch)<>'choice'
    or (select count(*) from therapy_package_vouchers where package_id=p_ch)<>2
    or (select count(*) from therapy_package_services where package_id=p_ch)<>2 then
  raise exception 'The choice package was not saved with its lists'; end if;
 begin
  perform save_therapy_package(null,'PSC dup '||tag,'PSC-C-'||tag,null,true,'choice',1,10,null,array[v1],null);
  raise exception 'A duplicate SKU was accepted';
 exception when others then if sqlerrm not like 'SKU "%" is already used by another item' then raise; end if; end;

 -- turning a package into another kind drops the lists that kind cannot hold
 perform save_therapy_package(p_unl,'PSC 3 months '||tag,'PSC-U-'||tag,null,true,'voucher',null,5,v1,null,null);
 if exists(select 1 from therapy_package_services where package_id=p_unl) then
  raise exception 'A vouchers-only package kept its services'; end if;
 perform save_therapy_package(p_unl,'PSC 3 months '||tag,'PSC-U-'||tag,null,true,'unlimited',3,null,null,null,array[svc_pr]);
 if (select count(*) from therapy_package_services where package_id=p_unl)<>1 then
  raise exception 'Services could not be set again on the unlimited package'; end if;
 if not exists(select 1 from audit_logs where record_id=p_unl and action='therapy_package_services_set') then
  raise exception 'Changing the services was not audited'; end if;

 -- staff cannot manage packages
 perform set_config('request.jwt.claim.sub',stf::text,true);
 begin
  perform save_therapy_package(p_unl,'PSC hijack','PSC-U-'||tag,null,true,'unlimited',3,null,null,null,null);
  raise exception 'Staff saved a package';
 exception when others then if sqlerrm not like '%Only an Owner or Manager%' then raise; end if; end;
 perform set_config('request.jwt.claim.sub',own::text,true);

 insert into unlimited_therapy_store_prices(package_id,store_id,selling_price,available_at_store)
   values(p_unl,st,300,true),(p_ch,st,500,true);

 -- ---- 2. a sold unit covers the package's services, with their limits ---------
 inv:=create_invoice(st,c,null,jsonb_build_array(jsonb_build_object('kind','therapy','therapy_package_id',p_ch,'quantity',1)));
 perform record_invoice_payment(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',500)),gen_random_uuid());
 select e.id into u from purchased_therapy_entitlements e where e.invoice_id=inv;
 r:=purchased_therapy_unit_state(u);
 if jsonb_array_length(r->'eligible_services')<>2 then raise exception 'The unit did not copy its two services'; end if;
 if not exists(select 1 from jsonb_array_elements(r->'eligible_services') x
                where x->>'service_id'=svc_pr::text and x->>'limit' like 'At most once every 5 hours%') then
  raise exception 'The Power Recharge limit is not shown with the coverage: %', r->'eligible_services'; end if;
 if not exists(select 1 from jsonb_array_elements(r->'eligible_services') x
                where x->>'service_id'=svc_f::text and x->'limit'='null'::jsonb) then
  raise exception 'A service with no limit shows one'; end if;
 if not (r->>'choice_pending')::boolean then raise exception 'The choice unit is not pending'; end if;

 -- ---- 3. Claim unlimited: one step, by ordinary staff ---------------------------
 perform set_config('request.jwt.claim.sub',stf::text,true);
 rq:=gen_random_uuid();
 r:=claim_purchased_therapy(u,'unlimited',sg_today(),'SG',null,false,null,rq,'customer took therapy');
 if not (r->>'success')::boolean or not (r->>'chose_now')::boolean then raise exception 'Claim did not choose: %', r; end if;
 if (select (benefit_choice, status) from purchased_therapy_entitlements where id=u) is distinct from ('unlimited'::text,'active'::text) then
  raise exception 'Claiming unlimited did not choose and start it in one step'; end if;
 if (select count(*) from therapy_benefit_choice_history where purchased_entitlement_id=u)<>1 then
  raise exception 'The choice was not kept in the history'; end if;
 begin
  perform claim_purchased_therapy(u,'unlimited',sg_today(),'SG',null,false,null,rq,null);
  raise exception 'A retried claim was carried out twice';
 exception when others then if sqlerrm not like '%already%' then raise; end if; end;
 begin
  perform claim_purchased_therapy(u,'voucher',null,null,null,false,null,gen_random_uuid(),null);
  raise exception 'A unit taken as therapy was also taken as vouchers';
 exception when others then if sqlerrm not like '%already taken as unlimited therapy%' then raise; end if; end;

 -- ---- 4. an overlap asks first, and then nothing is recorded ------------------
 perform set_config('request.jwt.claim.sub',own::text,true);
 inv2:=create_invoice(st,c,null,jsonb_build_array(jsonb_build_object('kind','therapy','therapy_package_id',p_unl,'quantity',1)));
 perform record_invoice_payment(inv2,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',300)),gen_random_uuid());
 select e.id into u2 from purchased_therapy_entitlements e where e.invoice_id=inv2;
 perform set_config('request.jwt.claim.sub',stf::text,true);
 rq:=gen_random_uuid();
 r:=claim_purchased_therapy(u2,'unlimited',sg_today(),'SG',null,false,null,rq,null);
 if coalesce((r->>'requires_confirmation')::boolean,false) is not true or (r->>'success')::boolean then
  raise exception 'An overlapping start did not ask first: %', r; end if;
 if (select status from purchased_therapy_entitlements where id=u2)<>'pending_activation' then
  raise exception 'An unconfirmed overlap still started the therapy'; end if;
 if exists(select 1 from therapy_choice_requests where request_id=rq) then
  raise exception 'An unconfirmed overlap kept its request'; end if;
 -- confirming it, with the same request id, goes through
 r:=claim_purchased_therapy(u2,'unlimited',sg_today(),'SG',null,true,null,rq,'overlap agreed');
 if (select status from purchased_therapy_entitlements where id=u2)<>'active' then
  raise exception 'A confirmed overlap did not start: %', r; end if;
 -- the unlimited-only unit's coverage is on the customer's page
 r:=therapy_customer_detail(c);
 if not exists(select 1 from jsonb_array_elements(r->'unlimited') x, jsonb_array_elements(x->'covers') y
                where x->>'id'=u2::text and y->>'service_id'=svc_pr::text) then
  raise exception 'The customer page does not show what the package covers'; end if;

 -- ---- 5. Claim vouchers: some now, the rest later -------------------------------
 perform set_config('request.jwt.claim.sub',own::text,true);
 inv3:=create_invoice(st,c2,null,jsonb_build_array(jsonb_build_object('kind','therapy','therapy_package_id',p_ch,'quantity',1)));
 perform record_invoice_payment(inv3,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',500)),gen_random_uuid());
 select e.id, e.invoice_item_id into u3, it from purchased_therapy_entitlements e where e.invoice_id=inv3;
 perform set_config('request.jwt.claim.sub',stf::text,true);
 -- a discount voucher cannot be slipped in
 begin
  perform claim_purchased_therapy(u3,'voucher',null,null,null,false,
    jsonb_build_array(jsonb_build_object('voucher_id',vdisc,'quantity',1)),gen_random_uuid(),null);
  raise exception 'A voucher outside the package list was handed over';
 exception when others then if sqlerrm not like '%not one of the choices%' then raise; end if; end;
 if (select benefit_choice from purchased_therapy_entitlements where id=u3) is not null then
  raise exception 'A refused claim still recorded the choice'; end if;
 r:=claim_purchased_therapy(u3,'voucher',null,null,null,false,
     jsonb_build_array(jsonb_build_object('voucher_id',v1,'quantity',2),jsonb_build_object('voucher_id',v2,'quantity',1)),
     gen_random_uuid(),null);
 select voucher_entitlement_id into ent from purchased_therapy_entitlements where id=u3;
 if entitlement_claimed_qty(ent)<>3 then raise exception 'Expected 3 collected, got %', entitlement_claimed_qty(ent); end if;
 if (select current_qty from voucher_store_stock where voucher_id=v1 and store_id=st)<>48 then
  raise exception 'Stock was not taken for the collected vouchers'; end if;
 r:=claim_purchased_therapy(u3,'voucher',null,null,null,false,
     jsonb_build_array(jsonb_build_object('voucher_id',v2,'quantity',2)),gen_random_uuid(),null);
 if entitlement_claimed_qty(ent)<>5 then raise exception 'A later collection did not add up'; end if;
 begin
  perform claim_purchased_therapy(u3,'voucher',null,null,null,false,null,gen_random_uuid(),null);
  raise exception 'An empty claim on a unit already taken as vouchers did nothing silently';
 exception when others then if sqlerrm not like '%at least one voucher%' then raise; end if; end;

 -- a unit taken as vouchers is not unlimited therapy on the customer's page …
 r:=therapy_customer_detail(c2);
 if exists(select 1 from jsonb_array_elements(r->'unlimited') x where x->>'id'=u3::text) then
  raise exception 'A unit taken as vouchers is listed as unlimited therapy'; end if;
 -- … the holdings list still shows the customer while vouchers are owed …
 if not exists(select 1 from therapy_customer_summary(null,500,0,false) x where x.customer_id=c2 and x.unlimited_pending>0) then
  raise exception 'A customer owed vouchers dropped out of the holdings list'; end if;
 r:=customer_overview(c2);
 if not exists(select 1 from jsonb_array_elements(r->'purchased_therapy') x where x->>'benefit'='voucher') then
  raise exception 'The customer overview does not say the unit was taken as vouchers'; end if;
 -- … and, as before, the same package cannot be bought again while it is current
 perform set_config('request.jwt.claim.sub',own::text,true);
 begin
  perform create_invoice(st,c2,null,jsonb_build_array(jsonb_build_object('kind','therapy','therapy_package_id',p_ch,'quantity',1)));
  raise exception 'The repurchase rule changed';
 exception when others then if sqlerrm not like '%already has a current entitlement%' then raise; end if; end;
 insert into unlimited_therapy_store_prices(package_id,store_id,selling_price,available_at_store) values(p_v,st,200,true);
 inv5:=create_invoice(st,c4,null,jsonb_build_array(jsonb_build_object('kind','therapy','therapy_package_id',p_v,'quantity',1)));
 perform record_invoice_payment(inv5,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',200)),gen_random_uuid());
 begin
  perform create_invoice(st,c4,null,jsonb_build_array(jsonb_build_object('kind','therapy','therapy_package_id',p_v,'quantity',1)));
  raise exception 'A second vouchers-only package was sold next to a current one';
 exception when others then if sqlerrm not like '%already has a current entitlement%' then raise; end if; end;

 -- a pending choice is listed as a choice still to be made
 inv4:=create_invoice(st,c3,null,jsonb_build_array(jsonb_build_object('kind','therapy','therapy_package_id',p_ch,'quantity',1)));
 perform record_invoice_payment(inv4,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',500)),gen_random_uuid());
 select e.id into u4 from purchased_therapy_entitlements e where e.invoice_id=inv4;
 r:=therapy_customer_detail(c3);
 if not exists(select 1 from jsonb_array_elements(r->'pending') x where x->>'reward_kind'='choice' and (x->>'voucher_qty')::int=10) then
  raise exception 'A pending choice is not listed as one: %', r->'pending'; end if;
 -- while a unit still waiting as unlimited therapy does stop a second purchase
 begin
  perform create_invoice(st,c,null,jsonb_build_array(jsonb_build_object('kind','therapy','therapy_package_id',p_unl,'quantity',1)));
  raise exception 'A second purchase next to a current unlimited period was allowed';
 exception when others then if sqlerrm not like '%already has a current entitlement%' then raise; end if; end;

 -- ---- 5b. a scheduled unit is started early or moved through Claim -------------
 inv6:=create_invoice(st,c4,null,jsonb_build_array(jsonb_build_object('kind','therapy','therapy_package_id',p_unl,'quantity',1)));
 perform record_invoice_payment(inv6,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',300)),gen_random_uuid());
 select e.id into u6 from purchased_therapy_entitlements e where e.invoice_id=inv6;
 perform set_config('request.jwt.claim.sub',stf::text,true);
 r:=claim_purchased_therapy(u6,'unlimited',sg_today()+14,'SG',null,false,null,gen_random_uuid(),null);
 if (select status from purchased_therapy_entitlements where id=u6)<>'scheduled' then raise exception 'A future start did not schedule: %', r; end if;
 -- moving it to another future date: its own period is not an overlap
 r:=claim_purchased_therapy(u6,'unlimited',sg_today()+7,'SG',null,false,null,gen_random_uuid(),'moved');
 if coalesce((r->>'requires_confirmation')::boolean,false) then raise exception 'A unit overlapped itself: %', r; end if;
 if (select activation_date from purchased_therapy_entitlements where id=u6)<>sg_today()+7 then
  raise exception 'Moving a scheduled start did not move it'; end if;
 -- and starting it today
 r:=claim_purchased_therapy(u6,'unlimited',sg_today(),'SG',null,false,null,gen_random_uuid(),'came in early');
 if (select status from purchased_therapy_entitlements where id=u6)<>'active' then raise exception 'Starting a scheduled unit early failed: %', r; end if;
 -- a unit that Reschedule set to "scheduled" with no start can still be started
 inv6:=create_invoice(st,c3,null,jsonb_build_array(jsonb_build_object('kind','therapy','therapy_package_id',p_unl,'quantity',1)));
 perform set_config('request.jwt.claim.sub',own::text,true);
 perform record_invoice_payment(inv6,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',300)),gen_random_uuid());
 select e.id into u5 from purchased_therapy_entitlements e where e.invoice_id=inv6;
 perform reschedule_purchased_therapy(u5,sg_today()+3,'customer asked');
 if (select (status, activation_date) from purchased_therapy_entitlements where id=u5) is distinct from ('scheduled'::text, null::date) then
  raise exception 'Fixture: Reschedule did not leave a start-less scheduled unit'; end if;
 r:=claim_purchased_therapy(u5,'unlimited',sg_today()+3,'SG',null,false,null,gen_random_uuid(),null);
 if (select activation_date from purchased_therapy_entitlements where id=u5) is distinct from sg_today()+3 then
  raise exception 'A rescheduled unit could not be claimed: %', r; end if;

 -- ---- 5c. the overlap question leaves the unit itself out ----------------------
 select expiry_date into d6 from purchased_therapy_entitlements where id=u6;       -- c4's running period
 inv7:=create_invoice(st,c4,null,jsonb_build_array(jsonb_build_object('kind','therapy','therapy_package_id',p_ch,'quantity',1)));
 perform record_invoice_payment(inv7,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',500)),gen_random_uuid());
 select e.id into u7 from purchased_therapy_entitlements e where e.invoice_id=inv7;
 r:=claim_purchased_therapy(u7,'unlimited',d6+5,'SG',null,false,null,gen_random_uuid(),null);
 if (select status from purchased_therapy_entitlements where id=u7)<>'scheduled' then raise exception 'Fixture: u7 not scheduled: %', r; end if;
 r:=claim_purchased_therapy(u7,'unlimited',sg_today(),'SG',null,false,null,gen_random_uuid(),null);
 if not coalesce((r->>'requires_confirmation')::boolean,false) then raise exception 'Starting over another period did not ask: %', r; end if;
 if (r->>'suggested_start')::date<>d6+1 then raise exception 'Suggested % instead of the day after the other period (%)', r->>'suggested_start', d6+1; end if;
 if exists(select 1 from jsonb_array_elements(r->'existing') x where x->>'entitlement_no'=(select entitlement_no from purchased_therapy_entitlements where id=u7)) then
  raise exception 'The unit was listed as overlapping itself'; end if;
 if (select (status, activation_date) from purchased_therapy_entitlements where id=u7) is distinct from ('scheduled'::text, d6+5) then
  raise exception 'An unconfirmed question moved the unit'; end if;

 -- ---- 5d. two units of one package never share days, even for a future start ----
 perform set_config('request.jwt.claim.sub',own::text,true);
 inv7:=create_invoice(st,c5,null,jsonb_build_array(
         jsonb_build_object('kind','therapy','therapy_package_id',p_unl,'quantity',1),
         jsonb_build_object('kind','therapy','therapy_package_id',p_unl,'quantity',1),
         jsonb_build_object('kind','therapy','therapy_package_id',p_ch,'quantity',1)));
 perform record_invoice_payment(inv7,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',1100)),gen_random_uuid());
 select e.id into ua from purchased_therapy_entitlements e where e.invoice_id=inv7 and e.package_id=p_unl order by e.unit_index, e.created_at limit 1;
 select e.id into ub from purchased_therapy_entitlements e where e.invoice_id=inv7 and e.package_id=p_unl and e.id<>ua limit 1;
 select e.id into uc from purchased_therapy_entitlements e where e.invoice_id=inv7 and e.package_id=p_ch;
 perform claim_purchased_therapy(ua,'unlimited',sg_today(),'SG',null,false,null,gen_random_uuid(),null);
 begin
  perform claim_purchased_therapy(ub,'unlimited',sg_today()+10,'SG',null,true,null,gen_random_uuid(),'overlap agreed');
  raise exception 'Two units of one package were scheduled on the same days';
 exception when others then if sqlerrm not like '%same package on some of those days%' then raise; end if; end;
 if (select status from purchased_therapy_entitlements where id=ub)<>'pending_activation' then
  raise exception 'A refused same-package claim changed the unit'; end if;

 -- ---- 5e. a choice unit Reschedule left "scheduled" can still take vouchers ------
 perform reschedule_purchased_therapy(uc,sg_today()+5,'customer asked');
 perform claim_purchased_therapy(uc,'voucher',null,null,null,false,null,gen_random_uuid(),null);
 if (select (status, scheduled_date, benefit_choice) from purchased_therapy_entitlements where id=uc)
    is distinct from ('pending_activation'::text, null::date, 'voucher'::text) then
  raise exception 'Taking vouchers on a rescheduled choice unit failed'; end if;

 -- ---- 6. refunds: collected vouchers are used ----------------------------------
 -- the Purchased-tab refund cannot terminate it
 begin
  perform refund_purchased_therapy(u3,'changed mind');
  raise exception 'A unit with collected vouchers was refunded from the Purchased tab';
 exception when others then if sqlerrm not like '%already been collected%' then raise; end if; end;
 -- the guided flow asks for the Owner/Manager override with an amount
 plan:=invoice_action_plan(inv3,'refund_full');
 if not exists(select 1 from jsonb_array_elements(plan->'overrides_required') x
                where x->>'code'='therapy_activated' and (x->>'amount_required')::boolean
                  and x->>'message' like '%vouchers from it have already been collected%') then
  raise exception 'The guided refund does not ask for the override: %', plan->'overrides_required'; end if;
 -- the engine refuses it without one
 begin
  perform refund_invoice_recorded(inv3,
    jsonb_build_array(jsonb_build_object('invoice_item_id',it,'amount',500)),
    jsonb_build_array(jsonb_build_object('payment_id',(select id from invoice_payments where invoice_id=inv3 limit 1),'amount',500)),
    '[]'::jsonb,'no override',gen_random_uuid());
  raise exception 'A unit with collected vouchers was refunded in full without an override';
 exception when others then if sqlerrm not like '%cannot be refunded%' then raise; end if; end;
 -- with it, the unit ends and only the uncollected vouchers are withdrawn
 req:=request_invoice_action_v2(inv3,'refund_full','[]'::jsonb,'Customer moving overseas',null,gen_random_uuid());
 res:=resolve_invoice_action_v2((req->>'request_id')::uuid,true,'Half back',null,
   jsonb_build_array(jsonb_build_object('code','therapy_activated','reason','5 of 10 collected','amount',250)),null,false);
 if res->>'status'<>'approved' then raise exception 'The authorized termination failed: %', res; end if;
 if (select status from purchased_therapy_entitlements where id=u3)<>'refunded' then
  raise exception 'The unit was not ended'; end if;
 if (select revoked_qty from therapy_entitlements where id=ent)<>5 then
  raise exception 'Expected the 5 uncollected vouchers withdrawn, got %', (select revoked_qty from therapy_entitlements where id=ent); end if;
 if (select coalesce(sum(quantity),0) from customer_reward_vouchers where entitlement_id=ent and status='held')<>5 then
  raise exception 'The collected vouchers were taken back from the customer'; end if;

  -- nothing is left on the allowance, so it is no longer an unclaimed benefit
 r:=therapy_customer_detail(c2);
 if exists(select 1 from jsonb_array_elements(r->'pending') x where x->>'entitlement_no'=(select entitlement_no from therapy_entitlements where id=ent)) then
  raise exception 'A fully resolved voucher allowance is still listed as unclaimed'; end if;
 if exists(select 1 from therapy_customer_summary(null,500,0,false) x where x.customer_id=c2 and x.unlimited_pending>0) then
  raise exception 'A customer with nothing owed is still listed as unclaimed'; end if;

 -- a unit taken as vouchers with none collected is still unused: a whole refund
 perform set_config('request.jwt.claim.sub',stf::text,true);
 perform claim_purchased_therapy(u4,'voucher',null,null,null,false,null,gen_random_uuid(),null);
 perform set_config('request.jwt.claim.sub',own::text,true);
 plan:=invoice_action_plan(inv4,'refund_full');
 if exists(select 1 from jsonb_array_elements(plan->'overrides_required') x where x->>'code'='therapy_activated') then
  raise exception 'Vouchers chosen but not collected were treated as used'; end if;
 req:=request_invoice_action_v2(inv4,'refund_full','[]'::jsonb,'Changed mind',null,gen_random_uuid());
 res:=resolve_invoice_action_v2((req->>'request_id')::uuid,true,'ok',null,'[]'::jsonb,null,false);
 if res->>'status'<>'approved' then raise exception 'The unused refund failed: %', res; end if;
 select status into s from therapy_entitlements where id=(select voucher_entitlement_id from purchased_therapy_entitlements where id=u4);
 if s<>'cancelled' then raise exception 'The uncollected voucher allowance was not withdrawn (status %)', s; end if;

 raise notice 'PASS: packages save any kind with SKU, services and session-voucher lists; units copy services with their limits; Claim chooses and starts therapy or hands over vouchers in one step, an overlap asks first and records nothing, retries do not repeat; collected vouchers make a unit used in the guided flow and the engine while uncollected ones are withdrawn; a scheduled unit can be moved or started early; a unit taken as vouchers is not shown as unlimited therapy, is listed only while vouchers are owed, and the repurchase rule is unchanged';
end $$;
rollback;
