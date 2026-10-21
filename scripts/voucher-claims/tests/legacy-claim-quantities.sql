-- A Legacy claim may not be made to look smaller than it is, nor hand a
-- reward over twice (422, THERAPY-4). The neighbour of negative-quantity.sql.
--
-- claim_legacy_therapy added up every quantity, negatives included, and
-- issued only the positive ones: 12 and -2 passed "exactly 10" and issued 12.
-- It also took any unclaimed voucher reward, a credit package's included,
-- without counting what had been handed over in the Vouchers window, so a
-- reward with 3 of 10 collected could be claimed again for all 10.
--
-- This drives the real sale (a credit package bought and paid) and asserts:
-- a voucher reward is refused by the Legacy claim and nothing moves; the
-- Vouchers window refuses a voucher off the reward's list, a discount voucher,
-- and quantities below one; and a Legacy reward taken as vouchers by its rule
-- refuses negative and zero lines but still takes exactly 10.
--
-- Needs 422 on the database. Disposable database only; everything is rolled
-- back.
begin;
do $$
declare
  own uuid := gen_random_uuid(); st uuid; c uuid; pm uuid; cp uuid; inv uuid;
  v1 uuid; v2 uuid; vd uuid; e uuid; u uuid; rv uuid; r jsonb;
  v_issued int; v_stock int; v_msg text;
begin
  if to_regprocedure('public.claim_legacy_therapy(uuid,date,uuid,jsonb,text,text,boolean)') is null then
    raise exception 'FIXTURE: this database does not have 422 (claim_legacy_therapy has no p_allow_overlap)'; end if;
  insert into auth.users(id,email) values (own,'lcq@tests.invalid');
  insert into profiles(id,full_name,email,role) values (own,'LCQ Owner','lcq@tests.invalid','owner');
  perform set_config('request.jwt.claim.sub', own::text, true);
  insert into stores(name,code,country_code) values ('LCQ Store','LCQS','SG') returning id into st;
  insert into customers(full_name,phone) values ('LCQ Buyer','+6598914778') returning id into c;
  insert into payment_methods(name) values ('LCQ Cash') returning id into pm;

  insert into vouchers(name,code,voucher_kind,qty_type,selling_price,is_active)
    values ('LCQ Facial','LCQF','normal','limited',50,true) returning id into v1;
  insert into vouchers(name,code,voucher_kind,qty_type,selling_price,is_active)
    values ('LCQ Massage','LCQM','normal','limited',50,true) returning id into v2;
  insert into vouchers(name,code,voucher_kind,qty_type,selling_price,is_active,discount_amount)
    values ('LCQ Ten Off','LCQD','fixed_discount','unlimited',0,true,10) returning id into vd;
  insert into voucher_store_stock(voucher_id,store_id,current_qty) values (v1,st,50),(v2,st,50);

  insert into credit_packages(name,customer_price,paid_credit_amount,grants_reward,
                              reward_qualifying_amount,allow_voucher,allow_therapy,effective_from)
    values ('LCQ Package',994,994,true,994,true,true,current_date) returning id into cp;
  insert into credit_package_stores(package_id,store_id) values (cp,st);
  insert into credit_package_vouchers(package_id,voucher_id) values (cp,v1),(cp,v2);

  inv := create_invoice(st,c,null,jsonb_build_array(jsonb_build_object(
           'kind','credit_package','credit_package_id',cp,'quantity',1)));
  perform pay_invoice(inv, jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',994)));

  select id into e from therapy_entitlements
   where customer_id = c and entitlement_kind = 'voucher' and claim_source_invoice_id = inv;
  if e is null then raise exception 'FIXTURE: the purchase created no claimable voucher entitlement'; end if;
  r := entitlement_voucher_state(e);
  if (r->>'remaining')::int < 4 then
    raise exception 'FIXTURE: this entitlement only has % to claim; the test needs at least 4', (r->>'remaining')::int; end if;

  -- Three handed over honestly in the Vouchers window.
  perform claim_entitlement_vouchers(e, jsonb_build_array(jsonb_build_object('voucher_id', v1, 'quantity', 3)), 'first visit');
  select coalesce(sum(quantity),0) into v_issued from customer_reward_vouchers where entitlement_id = e;
  select current_qty into v_stock from voucher_store_stock where voucher_id = v1 and store_id = st;

  -- 1. The Legacy claim refuses the reward outright, whatever it is sent.
  begin
    perform claim_legacy_therapy(e, null, null,
      jsonb_build_array(jsonb_build_object('voucher_id', v1, 'quantity', (r->>'entitled')::int)));
    raise exception 'FAIL: a credit-package reward with 3 handed over was claimed again in full';
  exception when others then
    get stacked diagnostics v_msg = message_text;
    if v_msg like 'FAIL:%' then raise; end if;
    if v_msg not like 'This is a voucher reward.%' then
      raise exception 'FAIL: refused for the wrong reason (%)', v_msg; end if;
  end;
  if (select coalesce(sum(quantity),0) from customer_reward_vouchers where entitlement_id = e) <> v_issued
     or (select current_qty from voucher_store_stock where voucher_id = v1 and store_id = st) <> v_stock
     or (select status from therapy_entitlements where id = e) <> 'pending_activation' then
    raise exception 'FAIL: the refused Legacy claim still issued vouchers, moved stock or changed the reward'; end if;

  -- 2. The Vouchers window: a voucher off the reward's list ...
  begin
    perform claim_entitlement_vouchers(e, jsonb_build_array(jsonb_build_object('voucher_id', vd, 'quantity', 1)), 'off the list');
    raise exception 'FAIL: a voucher off the reward''s list was handed over';
  exception when others then
    get stacked diagnostics v_msg = message_text;
    if v_msg like 'FAIL:%' then raise; end if;
    if v_msg not like 'That voucher was not one of the choices%' then
      raise exception 'FAIL: the voucher off the list was refused for the wrong reason (%)', v_msg; end if;
  end;
  -- ... and quantities below one, a zero and a negative line.
  begin
    perform claim_entitlement_vouchers(e, jsonb_build_array(
      jsonb_build_object('voucher_id', v1, 'quantity', 0),
      jsonb_build_object('voucher_id', v2, 'quantity', 1)), 'zero line');
    raise exception 'FAIL: a zero line was accepted';
  exception when others then
    get stacked diagnostics v_msg = message_text;
    if v_msg like 'FAIL:%' then raise; end if;
    if v_msg not like 'A voucher quantity must be%' then
      raise exception 'FAIL: the zero line was refused for the wrong reason (%)', v_msg; end if;
  end;
  if (select coalesce(sum(quantity),0) from customer_reward_vouchers where entitlement_id = e) <> v_issued then
    raise exception 'FAIL: a refused claim in the Vouchers window still issued vouchers'; end if;

  -- 3. A Legacy reward of unlimited therapy, taken as 10 vouchers by its rule.
  insert into therapy_package_rules(name, qualifying_amount, entitlement_kind, voucher_qty, tier_key, applies_to)
    values ('LCQ Ten Vouchers', 994, 'voucher', 10, 'LCQ-TIER', 'customer') returning id into rv;
  insert into therapy_entitlements(entitlement_no, customer_id, store_id, package_name, entitlement_kind,
      duration_months, qualifying_amount, qualified_value, activation_deadline, status, reward_tier_key)
    values ('LCQ-LEGACY-1', c, st, 'LCQ One Month', 'unlimited', 1, 994, 994, current_date + 30,
            'pending_activation', 'LCQ-TIER') returning id into u;
  begin
    perform claim_legacy_therapy(u, null, rv, jsonb_build_array(
      jsonb_build_object('voucher_id', v1, 'quantity', 12),
      jsonb_build_object('voucher_id', v2, 'quantity', -2)));
    raise exception 'FAIL: 12 and -2 were accepted as 10';
  exception when others then
    get stacked diagnostics v_msg = message_text;
    if v_msg like 'FAIL:%' then raise; end if;
    if v_msg not like 'A voucher quantity must be a whole number of at least one; got -2%' then
      raise exception 'FAIL: 12 and -2 were refused for the wrong reason (%)', v_msg; end if;
  end;
  begin
    perform claim_legacy_therapy(u, null, rv, jsonb_build_array(
      jsonb_build_object('voucher_id', v1, 'quantity', 10),
      jsonb_build_object('voucher_id', v2, 'quantity', 0)));
    raise exception 'FAIL: a Legacy claim with a zero line was accepted';
  exception when others then
    get stacked diagnostics v_msg = message_text;
    if v_msg like 'FAIL:%' then raise; end if;
    if v_msg not like 'A voucher quantity must be%' then
      raise exception 'FAIL: the zero line was refused for the wrong reason (%)', v_msg; end if;
  end;
  if exists (select 1 from customer_reward_vouchers where entitlement_id = u) then
    raise exception 'FAIL: a refused Legacy claim still issued vouchers'; end if;
  r := claim_legacy_therapy(u, null, rv, jsonb_build_array(
         jsonb_build_object('voucher_id', v1, 'quantity', 7),
         jsonb_build_object('voucher_id', v2, 'quantity', 3)));
  if not coalesce((r->>'claimed')::boolean, false)
     or (select coalesce(sum(quantity),0) from customer_reward_vouchers where entitlement_id = u) <> 10 then
    raise exception 'FAIL: an honest Legacy claim of exactly 10 did not issue 10'; end if;

  raise notice 'PASS: a Legacy claim refuses voucher rewards and quantities below one, the Vouchers window refuses a voucher off the list and a zero line, nothing moves on a refusal, and an honest claim of exactly 10 still issues 10';
end $$;
rollback;
