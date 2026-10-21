-- 417 (audit finding INVOICES-AFTER-M1): refunding or cancelling a credit
-- package whose qualification rewards are still outstanding, through Refund /
-- Cancel.
--
-- Before 417 the guided plan said nothing about the rewards and let the
-- request be raised; approval then failed inside the refund ("qualification
-- reward entitlements that are still outstanding") and left the request
-- waiting (production: INV-2026-0072 and INV-2026-0337, five unclaimed
-- rewards each). Now:
--   * the plan lists them as a non-blocking override, reward_withdrawal, and
--     those already activated or claimed as reward_consumed_kept; staff can
--     still raise the request;
--   * approving needs a reason for each, and settles the rewards in the same
--     step as the refund or cancellation (resolve_invoice_credit_rewards): the
--     unclaimed ones are withdrawn, the claimed ones keep their history;
--   * a refund that fails withdraws nothing;
--   * a part refund of another line on the same invoice leaves the rewards
--     alone: nothing is asked and nothing is withdrawn.
--
-- Needs 417. Disposable database only; everything is rolled back. Every name,
-- phone and amount here is invented (@tests.invalid).
\set ON_ERROR_STOP on
begin;

-- A refund that fails at the very end, on demand, to show nothing before it stays.
create function public.t417_refuse_refund() returns trigger language plpgsql as $f$
begin
  if current_setting('t417.refuse_refund', true) = 'on' then raise exception 'T417: the refund failed for the test'; end if;
  return new;
end $f$;
create trigger t417_refuse_refund before insert on public.invoice_refunds
  for each row execute function public.t417_refuse_refund();

do $$
declare o uuid := gen_random_uuid(); stf uuid := gen_random_uuid();
  st uuid; c uuid; pm uuid; pkg uuid; inv uuid; inv2 uuid; inv3 uuid; inv4 uuid; it uuid; sale uuid; sale2 uuid; sale3 uuid;
  sale4 uuid; p uuid; itp uuid;
  plan jsonb; req uuid; res jsonb; ent uuid; codes text; n int; msg text;
begin
  insert into auth.users(id, email) values (o, 't417rw-owner@tests.invalid'), (stf, 't417rw-staff@tests.invalid');
  insert into profiles(id, full_name, email, role, is_active) values
    (o, 'T417 Owner', 't417rw-owner@tests.invalid', 'owner', true),
    (stf, 'T417 Staff', 't417rw-staff@tests.invalid', 'staff', true);
  perform set_config('request.jwt.claim.sub', o::text, true);
  insert into stores(name, code, country_code) values ('T417 RW Store', 'T417RW', 'SG') returning id into st;
  insert into user_store_assignments(user_id, store_id) values (stf, st);
  insert into customers(full_name, phone) values ('T417 RW Buyer', '+61491570737') returning id into c;
  insert into payment_methods(name, is_active) values ('T417 RW Cash', true) returning id into pm;
  insert into credit_packages(name, customer_price, paid_credit_amount, effective_from, allow_product)
    values ('T417 RW Package', 1000, 1000, current_date, true) returning id into pkg;
  insert into credit_package_stores(package_id, store_id) values (pkg, st);

  -- ---- 1. The plan names the rewards; nothing is blocked ------------------
  inv := create_invoice(st, c, null, jsonb_build_array(jsonb_build_object('kind', 'credit_package', 'credit_package_id', pkg, 'quantity', 1)));
  perform pay_invoice(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pm, 'amount', 1000)));
  select id into sale from credit_package_sales where invoice_id = inv;
  select id into it from invoice_items where invoice_id = inv;
  select count(*) into n from therapy_entitlements where qualification_group_id = credit_package_reward_group(sale) and status = 'pending_activation';
  if n < 1 then raise exception 'Fixture: the package granted no reward'; end if;
  plan := invoice_action_plan(inv, 'refund_full', '[]');
  if (plan->>'blocked')::boolean then raise exception 'FAIL 1: the rewards block the plan: %', plan->'blockers'; end if;
  select string_agg(x->>'code', ',' order by x->>'code') into codes from jsonb_array_elements(plan->'overrides_required') x;
  if codes is distinct from 'reward_withdrawal' then raise exception 'FAIL 1: overrides asked: %', codes; end if;
  if jsonb_array_length(plan#>'{effects,rewards,withdrawn}') <> n or jsonb_array_length(plan#>'{effects,rewards,kept}') <> 0
     or not exists (select 1 from jsonb_array_elements(plan->'overrides_required') x
                     where x->>'code' = 'reward_withdrawal' and x->>'message' like 'Reward entitlements from this credit package that were not claimed yet (%) are withdrawn with this refund.'
                       and x->'invoice_item_ids' = jsonb_build_array(it)) then
    raise exception 'FAIL 1: the rewards are not named: %', plan->'overrides_required'; end if;
  if not exists (select 1 from jsonb_array_elements(invoice_action_plan(inv, 'cancel', '[]')->'overrides_required') x
                  where x->>'code' = 'reward_withdrawal' and x->>'message' like '%withdrawn with this cancellation.') then
    raise exception 'FAIL 1: the cancellation does not name them'; end if;

  -- ---- 2. Staff raise the request; approval needs the reason --------------
  perform set_config('request.jwt.claim.sub', stf::text, true);
  req := (request_invoice_action_v2(inv, 'refund_full', '[]', 'Customer wants the money back', null, gen_random_uuid())->>'request_id')::uuid;
  perform set_config('request.jwt.claim.sub', o::text, true);
  begin
    perform resolve_invoice_action_v2(req, true, 'Agreed', plan->>'plan_hash', '[]', null, false);
    raise exception 'FAIL 2: approved without a reason for the rewards';
  exception when others then
    if sqlerrm not like 'An Owner/Manager override reason is required for: reward_withdrawal%' then raise; end if;
  end;

  -- ---- 3. A refund that fails withdraws nothing ---------------------------
  perform set_config('t417.refuse_refund', 'on', true);
  begin
    perform resolve_invoice_action_v2(req, true, 'Agreed', plan->>'plan_hash',
      jsonb_build_array(jsonb_build_object('code', 'reward_withdrawal', 'reason', 'Package refunded')), null, false);
    raise exception 'FAIL 3: the refund did not fail';
  exception when others then
    if sqlerrm not like 'T417: the refund failed for the test%' then raise; end if;
  end;
  perform set_config('t417.refuse_refund', 'off', true);
  if (select count(*) from therapy_entitlements where qualification_group_id = credit_package_reward_group(sale) and status = 'pending_activation') <> n
     or (select rewards_resolved_at from credit_package_sales where id = sale) is not null
     or (select status from approval_requests where id = req) <> 'pending'
     or exists (select 1 from invoice_refunds where invoice_id = inv) then
    raise exception 'FAIL 3: a failed refund left the rewards withdrawn or the request resolved'; end if;

  -- ---- 4. The approval settles them with the refund -----------------------
  res := resolve_invoice_action_v2(req, true, 'Agreed', plan->>'plan_hash',
    jsonb_build_array(jsonb_build_object('code', 'reward_withdrawal', 'reason', 'Package refunded')), null, false);
  if res->>'status' <> 'approved' or (res->>'refunded_amount')::numeric <> 1000 then raise exception 'FAIL 4: %', res; end if;
  if exists (select 1 from therapy_entitlements where qualification_group_id = credit_package_reward_group(sale) and status = 'pending_activation')
     or (select count(*) from therapy_entitlements where qualification_group_id = credit_package_reward_group(sale) and status = 'cancelled') <> n then
    raise exception 'FAIL 4: the unclaimed rewards were not withdrawn'; end if;
  if (select rewards_resolution->>'request_id' from credit_package_sales where id = sale) <> req::text
     or (select rewards_resolution->>'reason' from credit_package_sales where id = sale) <> 'Package refunded' then
    raise exception 'FAIL 4: the settlement does not name the request and its reason'; end if;
  if (select status::text from invoices where id = inv) <> 'refunded' then raise exception 'FAIL 4: the invoice was not refunded'; end if;

  -- ---- 5. A claimed reward keeps its history, on its own reason -----------
  inv2 := create_invoice(st, c, null, jsonb_build_array(jsonb_build_object('kind', 'credit_package', 'credit_package_id', pkg, 'quantity', 1)));
  perform pay_invoice(inv2, jsonb_build_array(jsonb_build_object('payment_method_id', pm, 'amount', 1000)));
  select id into sale2 from credit_package_sales where invoice_id = inv2;
  select id into ent from therapy_entitlements where qualification_group_id = credit_package_reward_group(sale2) order by id limit 1;
  update therapy_entitlements set status = 'active', activation_date = current_date, claimed_at = now() where id = ent;
  plan := invoice_action_plan(inv2, 'cancel', '[]');
  select string_agg(x->>'code', ',' order by x->>'code') into codes from jsonb_array_elements(plan->'overrides_required') x;
  if codes is distinct from 'reward_consumed_kept,reward_withdrawal' then raise exception 'FAIL 5: overrides asked: %', codes; end if;
  if plan#>'{effects,rewards,kept}' <> jsonb_build_array((select entitlement_no from therapy_entitlements where id = ent)) then
    raise exception 'FAIL 5: the claimed reward is not named as kept: %', plan#>'{effects,rewards}'; end if;
  req := (request_invoice_action_v2(inv2, 'cancel', '[]', 'Customer cancelled', null, gen_random_uuid())->>'request_id')::uuid;
  begin
    perform resolve_invoice_action_v2(req, true, 'Agreed', plan->>'plan_hash',
      jsonb_build_array(jsonb_build_object('code', 'reward_withdrawal', 'reason', 'Cancelled')), null, false);
    raise exception 'FAIL 5: cancelled without confirming the claimed reward stays';
  exception when others then
    if sqlerrm not like 'An Owner/Manager override reason is required for: reward_consumed_kept%' then raise; end if;
  end;
  res := resolve_invoice_action_v2(req, true, 'Agreed', plan->>'plan_hash',
    jsonb_build_array(jsonb_build_object('code', 'reward_withdrawal', 'reason', 'Cancelled'),
                      jsonb_build_object('code', 'reward_consumed_kept', 'reason', 'The activated one stays')), null, false);
  if res->>'status' <> 'approved' or (select status::text from invoices where id = inv2) <> 'cancelled' then
    raise exception 'FAIL 5: the cancellation did not go through: %', res; end if;
  -- The settlement leaves it alone and keeps its history. (Closing the invoice
  -- then applies the existing voucher rule, revoke_unclaimed_entitlement_
  -- vouchers: a voucher reward none of whose vouchers were collected closes.
  -- That is not this migration's and is not tested here.)
  if (select claimed_at from therapy_entitlements where id = ent) is null
     or exists (select 1 from audit_logs where record_id = ent and action = 'reward_withdrawn_for_invoice_resolution') then
    raise exception 'FAIL 5: the settlement withdrew the claimed reward or erased its history'; end if;
  if exists (select 1 from therapy_entitlements where qualification_group_id = credit_package_reward_group(sale2)
              and id <> ent and status = 'pending_activation') then
    raise exception 'FAIL 5: an unclaimed reward was left with the cancelled package'; end if;
  if (select (rewards_resolution->>'retained')::int from credit_package_sales where id = sale2) <> 1 then
    raise exception 'FAIL 5: the kept reward was not counted'; end if;

  -- ---- 6. Settled already, or none granted: nothing is asked --------------
  plan := invoice_action_plan(inv2, 'cancel', '[]');
  if exists (select 1 from jsonb_array_elements(plan->'overrides_required') x where x->>'code' like 'reward_%') then
    raise exception 'FAIL 6: settled rewards are asked about again'; end if;
  inv3 := create_invoice(st, c, null, jsonb_build_array(jsonb_build_object('kind', 'credit_package', 'credit_package_id', pkg, 'quantity', 1)));
  perform pay_invoice(inv3, jsonb_build_array(jsonb_build_object('payment_method_id', pm, 'amount', 1000)));
  select id into sale3 from credit_package_sales where invoice_id = inv3;
  update therapy_entitlements set status = 'cancelled' where qualification_group_id = credit_package_reward_group(sale3);
  if exists (select 1 from jsonb_array_elements(invoice_action_plan(inv3, 'refund_full', '[]')->'overrides_required') x
              where x->>'code' like 'reward_%') then
    raise exception 'FAIL 6: rewards already closed are asked about'; end if;

  -- ---- 7. A part refund of another line leaves the rewards alone ----------
  insert into products(name, sku, product_type) values ('T417 RW Item', 'T417RWI', 'own') returning id into p;
  insert into store_inventory(store_id, product_id, current_qty) values (st, p, 100);
  perform set_product_prices(st, p, 100, 100, 'available');
  inv4 := create_invoice(st, c, null, jsonb_build_array(
    jsonb_build_object('kind', 'credit_package', 'credit_package_id', pkg, 'quantity', 1),
    jsonb_build_object('kind', 'product', 'product_id', p, 'quantity', 2)));
  perform pay_invoice(inv4, jsonb_build_array(jsonb_build_object('payment_method_id', pm, 'amount', 1200)));
  select id into sale4 from credit_package_sales where invoice_id = inv4;
  select id into itp from invoice_items where invoice_id = inv4 and product_id = p;
  select count(*) into n from therapy_entitlements where qualification_group_id = credit_package_reward_group(sale4) and status = 'pending_activation';
  if n < 1 or (select status::text from invoices where id = inv4) <> 'paid' then
    raise exception 'Fixture 7: the package granted no reward, or the invoice is not paid'; end if;
  plan := invoice_action_plan(inv4, 'refund_partial', jsonb_build_array(jsonb_build_object('invoice_item_id', itp, 'quantity', 1)));
  if (plan->>'blocked')::boolean or (plan->>'refund_amount')::numeric <> 100 then
    raise exception 'Fixture 7: the plan for one item back is %', plan; end if;
  if exists (select 1 from jsonb_array_elements(plan->'overrides_required') x where x->>'code' like 'reward_%')
     or jsonb_array_length(coalesce(plan#>'{effects,rewards,withdrawn}', '[]')) <> 0
     or jsonb_array_length(coalesce(plan#>'{effects,rewards,kept}', '[]')) <> 0 then
    raise exception 'FAIL 7: a part refund of another line asks about the rewards: % / %',
      plan->'overrides_required', plan#>'{effects,rewards}'; end if;
  perform set_config('request.jwt.claim.sub', stf::text, true);
  req := (request_invoice_action_v2(inv4, 'refund_partial', jsonb_build_array(jsonb_build_object('invoice_item_id', itp, 'quantity', 1)),
    'One item back', null, gen_random_uuid())->>'request_id')::uuid;
  perform set_config('request.jwt.claim.sub', o::text, true);
  res := resolve_invoice_action_v2(req, true, 'Agreed', plan->>'plan_hash', '[]',
    (select coalesce(jsonb_agg(jsonb_build_object('movement_id', s->>'movement_id', 'sellable_quantity', (s->>'proposed_sellable')::int,
       'damaged_quantity', 0, 'not_returned_quantity', 0)), '[]'::jsonb) from jsonb_array_elements(plan->'stock') s), true);
  if res->>'status' <> 'approved' or (res->>'refunded_amount')::numeric <> 100 then raise exception 'FAIL 7: %', res; end if;
  if (select count(*) from therapy_entitlements where qualification_group_id = credit_package_reward_group(sale4) and status = 'pending_activation') <> n
     or (select rewards_resolved_at from credit_package_sales where id = sale4) is not null then
    raise exception 'FAIL 7: a part refund of another line withdrew the package''s rewards'; end if;

  raise notice 'PASS: a credit package''s outstanding rewards are named in the plan without blocking it; staff can raise the request; approval needs a reason for them (and one more for any already claimed); they are settled in the same step as the refund or cancellation, which a failed refund undoes; unclaimed ones are withdrawn, claimed ones keep their status and history; nothing is asked once settled or when none are open; a part refund of another line leaves them alone';
end $$;

rollback;
