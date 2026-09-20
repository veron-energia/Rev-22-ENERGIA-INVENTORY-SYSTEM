-- A claim may not be made to look smaller than it is.
--
-- claim_entitlement_vouchers counted the selections in one loop and issued them
-- in another. The counting loop added every quantity as it found it; the
-- issuing loop skipped the ones that were not positive. A negative line
-- therefore bought headroom: [{A: 5}, {B: -3}] counted as 2, passed a cap of 2,
-- and handed over five.
--
-- This drives the real function with exactly that payload and asserts both
-- halves of the fix: the claim is refused, and nothing was issued, spent or
-- recorded on the way to refusing it.
--
-- Disposable database only; everything is rolled back.
begin;
do $$
declare
  own uuid := gen_random_uuid(); st uuid; c uuid; pm uuid; cp uuid; inv uuid;
  v1 uuid; v2 uuid; e uuid; r jsonb;
  v_issued int; v_claims int; v_stock1 int; v_remaining int; v_msg text;
begin
  insert into auth.users(id,email) values (own,'nq@tests.invalid');
  insert into profiles(id,full_name,email,role) values (own,'NQ Owner','nq@tests.invalid','owner');
  perform set_config('request.jwt.claim.sub', own::text, true);
  insert into stores(name,code,country_code) values ('NQ Store','NQS','SG') returning id into st;
  insert into customers(full_name,phone) values ('NQ Buyer','+6598914777') returning id into c;
  insert into payment_methods(name) values ('NQ Cash') returning id into pm;

  insert into vouchers(name,code,voucher_kind,qty_type,selling_price,is_active)
    values ('NQ Facial','NQF','normal','limited',50,true) returning id into v1;
  insert into vouchers(name,code,voucher_kind,qty_type,selling_price,is_active)
    values ('NQ Massage','NQM','normal','limited',50,true) returning id into v2;
  insert into voucher_store_stock(voucher_id,store_id,current_qty) values (v1,st,50),(v2,st,50);

  insert into credit_packages(name,customer_price,paid_credit_amount,grants_reward,
                              reward_qualifying_amount,allow_voucher,allow_therapy,effective_from)
    values ('NQ Package',994,994,true,994,true,true,current_date) returning id into cp;
  insert into credit_package_stores(package_id,store_id) values (cp,st);
  insert into credit_package_vouchers(package_id,voucher_id) values (cp,v1),(cp,v2);

  inv := create_invoice(st,c,null,jsonb_build_array(jsonb_build_object(
           'kind','credit_package','credit_package_id',cp,'quantity',1)));
  perform pay_invoice(inv, jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',994)));

  select id into e from therapy_entitlements
   where customer_id = c and entitlement_kind = 'voucher' and claim_source_invoice_id = inv;
  if e is null then raise exception 'FIXTURE: the purchase created no claimable voucher entitlement'; end if;

  -- Claim everything but two, honestly, so the cap that follows is a real one.
  r := entitlement_voucher_state(e);
  v_remaining := (r->>'remaining')::int;
  if v_remaining < 3 then
    raise exception 'FIXTURE: this entitlement only has % to claim; the test needs at least 3', v_remaining; end if;
  if v_remaining > 2 then
    perform claim_entitlement_vouchers(e,
      jsonb_build_array(jsonb_build_object('voucher_id', v1, 'quantity', v_remaining - 2)), 'honest claim');
  end if;

  r := entitlement_voucher_state(e);
  if (r->>'remaining')::int <> 2 then
    raise exception 'FIXTURE: expected 2 left to claim, got %', (r->>'remaining')::int; end if;

  select count(*) into v_claims from voucher_claims where entitlement_id = e;
  select coalesce(sum(quantity),0) into v_issued from customer_reward_vouchers where entitlement_id = e;
  select current_qty into v_stock1 from voucher_store_stock where voucher_id = v1 and store_id = st;

  -- The attack: five of one, minus three of the other. It sums to the 2 that
  -- are left, and used to hand over five.
  begin
    perform claim_entitlement_vouchers(e, jsonb_build_array(
      jsonb_build_object('voucher_id', v1, 'quantity',  5),
      jsonb_build_object('voucher_id', v2, 'quantity', -3)), 'negative line');
    raise exception 'FAIL: a claim of 5 and -3 was accepted against 2 remaining';
  exception when others then
    get stacked diagnostics v_msg = message_text;
    if v_msg like 'FAIL:%' then raise; end if;
    if v_msg not like 'A voucher quantity must be%' then
      raise exception 'FAIL: refused for the wrong reason (%)', v_msg; end if;
  end;

  -- Refused, and refused before anything moved.
  r := entitlement_voucher_state(e);
  if (r->>'remaining')::int <> 2 then
    raise exception 'FAIL: the refused claim still consumed entitlement (% left)', (r->>'remaining')::int; end if;
  if (select count(*) from voucher_claims where entitlement_id = e) <> v_claims then
    raise exception 'FAIL: the refused claim still wrote a claim document'; end if;
  if (select coalesce(sum(quantity),0) from customer_reward_vouchers where entitlement_id = e) <> v_issued then
    raise exception 'FAIL: the refused claim still issued vouchers'; end if;
  if (select current_qty from voucher_store_stock where voucher_id = v1 and store_id = st) <> v_stock1 then
    raise exception 'FAIL: the refused claim still moved stock'; end if;

  -- Zero is malformed too: the application never sends it, and honouring part
  -- of a payload is how the original defect worked.
  begin
    perform claim_entitlement_vouchers(e, jsonb_build_array(
      jsonb_build_object('voucher_id', v1, 'quantity', 2),
      jsonb_build_object('voucher_id', v2, 'quantity', 0)), 'zero line');
    raise exception 'FAIL: a claim containing a zero quantity was accepted';
  exception when others then
    get stacked diagnostics v_msg = message_text;
    if v_msg like 'FAIL:%' then raise; end if;
    if v_msg not like 'A voucher quantity must be%' then
      raise exception 'FAIL: the zero line was refused for the wrong reason (%)', v_msg; end if;
  end;

  -- And an honest claim of exactly what is left still works: the fix refuses
  -- malformed quantities, not customers.
  perform claim_entitlement_vouchers(e, jsonb_build_array(
    jsonb_build_object('voucher_id', v1, 'quantity', 1),
    jsonb_build_object('voucher_id', v2, 'quantity', 1)), 'the rest');
  r := entitlement_voucher_state(e);
  if (r->>'remaining')::int <> 0 then
    raise exception 'FAIL: an honest final claim did not settle the entitlement (% left)', (r->>'remaining')::int; end if;
  if (select coalesce(sum(quantity),0) from customer_reward_vouchers where entitlement_id = e) <> v_issued + 2 then
    raise exception 'FAIL: the honest claim issued the wrong number of vouchers'; end if;

  raise notice 'PASS: a claim carrying a quantity below one is refused whole, nothing moves, and an honest claim still settles';
end $$;
rollback;
