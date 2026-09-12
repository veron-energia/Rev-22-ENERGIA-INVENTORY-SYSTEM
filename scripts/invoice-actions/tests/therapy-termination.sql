-- Terminating an activated therapy entitlement under an authorized override.
--
-- Before 296 this was refused outright by the refund engine, so the guided
-- flow could only collect a reason and then fail. These assertions cover the
-- action actually being carried out, and the limits that still bind it.
-- Disposable database only; everything is rolled back.
begin;
do $$
declare own uuid:=gen_random_uuid(); stf uuid:=gen_random_uuid();
 st uuid; c uuid; c2 uuid; pm uuid; tp uuid; inv uuid; inv2 uuid; other uuid;
 it uuid; ent uuid; ent2 uuid; plan jsonb; req jsonb; res jsonb; s text; n numeric; codes text;
begin
 insert into auth.users(id,email) values(own,'tt-own@tests.invalid'),(stf,'tt-stf@tests.invalid');
 insert into profiles(id,full_name,email,role) values
   (own,'Owner','tt-own@tests.invalid','owner'),(stf,'Staff','tt-stf@tests.invalid','staff');
 perform set_config('request.jwt.claim.sub',own::text,true);
 insert into stores(name,code,country_code) values('TT Store','TTS','SG') returning id into st;
 insert into user_store_assignments(user_id,store_id) values(stf,st);
 insert into customers(full_name,phone) values('TT Buyer','+6598885001') returning id into c;
 insert into customers(full_name,phone) values('TT Other','+6598885002') returning id into c2;
 insert into payment_methods(name) values('TT Cash') returning id into pm;
 insert into unlimited_therapy_packages(name,duration_months,is_active,entitlement_kind)
   values('TT 6 Month',6,true,'unlimited') returning id into tp;
 insert into unlimited_therapy_store_prices(package_id,store_id,selling_price,available_at_store)
   values(tp,st,600,true);

 -- An unrelated customer's entitlement, which must not move.
 inv2:=create_invoice(st,c2,null,jsonb_build_array(jsonb_build_object('kind','therapy','therapy_package_id',tp,'quantity',1)));
 perform record_invoice_payment(inv2,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',600)),gen_random_uuid());
 select e.id into ent2 from purchased_therapy_entitlements e join invoice_items x on x.id=e.invoice_item_id where x.invoice_id=inv2;
 perform activate_purchased_therapy(ent2,sg_today(),'Other customer started');

 inv:=create_invoice(st,c,null,jsonb_build_array(jsonb_build_object('kind','therapy','therapy_package_id',tp,'quantity',1)));
 perform record_invoice_payment(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',600)),gen_random_uuid());
 select id into it from invoice_items where invoice_id=inv;
 select id into ent from purchased_therapy_entitlements where invoice_item_id=it;

 -- ---- UNUSED (pending_activation) needs no usage override ----------------
 plan:=invoice_action_plan(inv,'refund_full');
 if coalesce((plan->>'blocked')::boolean,false) then
  raise exception 'An unactivated entitlement must not be blocked: %',plan->'blockers'; end if;
 select string_agg(x->>'code',',') into codes from jsonb_array_elements(plan->'overrides_required') x;
 if coalesce(codes,'') like '%therapy_activated%' then
  raise exception 'An unactivated entitlement must not need a usage override'; end if;

 -- ---- ACTIVATED is an override, not a blocker ----------------------------
 perform activate_purchased_therapy(ent,sg_today(),'Customer started');
 if (select status from purchased_therapy_entitlements where id=ent)<>'active' then
  raise exception 'Fixture did not activate'; end if;
 plan:=invoice_action_plan(inv,'refund_full');
 if coalesce((plan->>'blocked')::boolean,false) then
  raise exception 'Activated therapy must be an override now, not a blocker: %',plan->'blockers'; end if;
 if not exists(select 1 from jsonb_array_elements(plan->'overrides_required') x
                where x->>'code'='therapy_activated' and (x->>'amount_required')::boolean) then
  raise exception 'Activated therapy must require an override carrying an amount'; end if;

 -- ---- staff may ask, but cannot carry it out -----------------------------
 perform set_config('request.jwt.claim.sub',stf::text,true);
 req:=request_invoice_action_v2(inv,'refund_full','[]'::jsonb,'Customer moving overseas',null,gen_random_uuid());
 if not coalesce((req#>>'{plan,requires_override}')::boolean,false) then
  raise exception 'Staff must be told an override is required'; end if;
 begin
  perform resolve_invoice_action_v2((req->>'request_id')::uuid,true,'me');
  raise exception 'Staff terminated an activated entitlement';
 exception when others then if sqlerrm not like '%Only an Owner or Manager%' then raise; end if; end;
 if (select status from purchased_therapy_entitlements where id=ent)<>'active' then
  raise exception 'A refused attempt changed the entitlement'; end if;

 -- ---- an amount is required, not just a reason ---------------------------
 perform set_config('request.jwt.claim.sub',own::text,true);
 begin
  perform resolve_invoice_action_v2((req->>'request_id')::uuid,true,'ok',null,
    jsonb_build_array(jsonb_build_object('code','therapy_activated','reason','Goodwill')),null,false);
  raise exception 'Approved an activated termination with no stated amount';
 exception when others then if sqlerrm not like '%(amount)%' then raise; end if; end;
 if (select status from purchased_therapy_entitlements where id=ent)<>'active' then
  raise exception 'A failed approval changed the entitlement'; end if;
 if exists(select 1 from invoice_refunds where invoice_id=inv) then
  raise exception 'A failed approval recorded a refund'; end if;

 -- ---- the payment ceiling still binds ------------------------------------
 begin
  perform resolve_invoice_action_v2((req->>'request_id')::uuid,true,'ok',null,
    jsonb_build_array(jsonb_build_object('code','therapy_activated','reason','Goodwill','amount',5000)),null,false);
  raise exception 'An override was allowed to exceed the money actually held';
 exception when others then
  if sqlerrm like '%Only an Owner%' then raise; end if;
 end;
 if (select status from purchased_therapy_entitlements where id=ent)<>'active' then
  raise exception 'A rejected over-ceiling attempt changed the entitlement'; end if;

 -- ---- authorized partial termination -------------------------------------
 res:=resolve_invoice_action_v2((req->>'request_id')::uuid,true,'Pro-rata goodwill',null,
   jsonb_build_array(jsonb_build_object('code','therapy_activated',
     'reason','Three months unused, Manager agreed half','amount',300)),null,false);
 if res->>'status'<>'approved' then raise exception 'Authorized termination failed: %',res; end if;
 if coalesce((res->>'refunded_amount')::numeric,0)<>300 then
  raise exception 'Expected 300 refunded, got %',res->>'refunded_amount'; end if;

 -- terminated, and gone from active balances
 select status into s from purchased_therapy_entitlements where id=ent;
 if s<>'refunded' then raise exception 'Entitlement not terminated, status %',s; end if;
 if exists(select 1 from purchased_therapy_entitlements where id=ent and status in ('active','scheduled','pending_activation')) then
  raise exception 'Terminated entitlement still counts as an active balance'; end if;
 -- and the refresher cannot bring it back
 perform refresh_purchased_therapy_statuses();
 if (select status from purchased_therapy_entitlements where id=ent)<>'refunded' then
  raise exception 'The status refresher revived a terminated entitlement'; end if;

 -- history kept
 if (select activation_date from purchased_therapy_entitlements where id=ent) is null then
  raise exception 'Activation history was erased'; end if;
 if (select price_snapshot from purchased_therapy_entitlements where id=ent) is null then
  raise exception 'The original purchase snapshot was erased'; end if;
 if not exists(select 1 from audit_logs where table_name='purchased_therapy_entitlements'
                and record_id=ent and action='authorized_termination'
                and new_data->'override'->>'reason' like 'Three months unused%') then
  raise exception 'The authorized termination was not audited with its reason'; end if;

 -- ---- the unrelated customer is untouched --------------------------------
 if (select status from purchased_therapy_entitlements where id=ent2)<>'active' then
  raise exception 'An unrelated entitlement was terminated'; end if;

 -- ---- no repeat termination, no second refund ----------------------------
 res:=resolve_invoice_action_v2((req->>'request_id')::uuid,true,'again');
 if not coalesce((res->>'already_resolved')::boolean,false) then
  raise exception 'A repeated approval was not recognised'; end if;
 if (select count(*) from invoice_refunds where invoice_id=inv and request_id=(req->>'request_id')::uuid)<>1 then
  raise exception 'A repeated approval refunded twice'; end if;
 -- the standalone entry point agrees
 begin
  perform refund_purchased_therapy(ent,'try again');
  raise exception 'refund_purchased_therapy re-terminated an already terminated entitlement';
 exception when others then if sqlerrm not like '%already refunded%' then raise; end if; end;

 raise notice 'PASS: activated therapy terminates under an authorized override with a stated amount; unactivated needs none; staff cannot execute; amount and payment ceilings bind; failures change nothing; activation/purchase history and unrelated entitlements survive; no repeat termination or double refund';
end $$;
rollback;
