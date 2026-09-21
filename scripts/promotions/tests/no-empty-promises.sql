-- A promotion cannot promise a package it never grants (352).
--
-- The editor offered "Credit package" as an included item and as a choice-group
-- kind, and nothing anywhere issued it: create_invoice never reads
-- promotion_items, issue_credit_lines_for_invoice gates on line_kind in
-- ('credit_package','premium_bundle'), and a promotion sells as 'promotion'.
-- A customer could pay and receive nothing.
--
-- The half of this test that matters most is the SECOND half. It is easy to
-- close a trap by making the whole feature unusable; the rule for this project
-- is to preserve legitimate staff workflows. So every kind that genuinely works
-- must still be authorable, as an included item AND as a choice group.
--
-- Disposable database only; everything is rolled back.
\set ON_ERROR_STOP on
begin;
do $$
declare
  own uuid := gen_random_uuid();
  prod uuid; vch uuid; tp uuid; cp uuid; promo uuid; child uuid; g uuid; v_msg text;
begin
  insert into auth.users(id,email) values (own,'nep@tests.invalid');
  insert into profiles(id,full_name,email,role) values (own,'NEP Owner','nep@tests.invalid','owner');
  perform set_config('request.jwt.claim.sub', own::text, true);

  insert into products(name,sku) values ('NEP Item','NEP-1') returning id into prod;
  insert into vouchers(name,code,selling_price) values ('NEP Voucher','NEP-V',50) returning id into vch;
  insert into unlimited_therapy_packages(name, duration_months) values ('NEP Therapy', 3) returning id into tp;
  insert into credit_packages(name, customer_price, paid_credit_amount, grants_reward,
                              reward_qualifying_amount, allow_voucher, allow_therapy, effective_from)
    values ('NEP Package', 500, 500, false, 500, true, true, current_date) returning id into cp;

  insert into promotions(name,code) values ('NEP Promo','NEP-P') returning id into promo;
  insert into promotions(name,code) values ('NEP Child','NEP-C') returning id into child;
  insert into promotion_items(promotion_id,item_type,product_id,quantity) values (child,'product',prod,1);

  -- ── the trap is closed ────────────────────────────────────────────────────
  begin
    perform public.add_promotion_item(promo,'credit_package'::public.promotion_item_type,
      null,null,null,null,1,null,null,cp);
    raise exception 'FAIL: a credit package was accepted into a promotion; the customer would pay and get nothing';
  exception when others then
    get stacked diagnostics v_msg = message_text;
    if v_msg like 'FAIL:%' then raise; end if;
    -- The message has to tell staff what to do instead, not just say no.
    if v_msg !~ 'not issued yet' or v_msg !~ 'on its own' then
      raise exception 'FAIL: refused, but not with a message that explains what to do (%)', v_msg; end if;
  end;

  begin
    insert into promotion_choice_groups(promotion_id,label,item_kind,choose_qty)
      values (promo,'Pick a package','credit_package',1);
    raise exception 'FAIL: a choice group was set to credit_package';
  exception when others then
    get stacked diagnostics v_msg = message_text;
    if v_msg like 'FAIL:%' then raise; end if;
  end;

  -- The group is created OUTSIDE the block below on purpose: a plpgsql
  -- exception handler rolls back everything the block did, so a group created
  -- inside it would silently vanish and the count at the end would be wrong.
  insert into promotion_choice_groups(promotion_id,label,item_kind,choose_qty)
    values (promo,'Pick a product','product',1) returning id into g;
  insert into promotion_choice_options(group_id, product_id) values (g, prod);
  begin
    insert into promotion_choice_options(group_id, credit_package_id) values (g, cp);
    raise exception 'FAIL: a credit package was offered as a choice option';
  exception when others then
    get stacked diagnostics v_msg = message_text;
    if v_msg like 'FAIL:%' then raise; end if;
  end;

  -- ── and every kind that DOES work still works ─────────────────────────────
  -- A trap closed by breaking the feature is not a fix.
  perform public.add_promotion_item(promo,'product'::public.promotion_item_type,
    prod,null,null,null,1,null,null,null);
  perform public.add_promotion_item(promo,'voucher'::public.promotion_item_type,
    null,vch,null,null,1,null,null,null);
  perform public.add_promotion_item(promo,'treatment'::public.promotion_item_type,
    null,null,null,'A treatment',1,null,null,null);
  perform public.add_promotion_item(promo,'therapy'::public.promotion_item_type,
    null,null,null,null,1,null,tp,null);
  perform public.add_promotion_item(promo,'promotion'::public.promotion_item_type,
    null,null,child,null,1,null,null,null);

  if (select count(*) from promotion_items where promotion_id = promo) <> 5 then
    raise exception 'FAIL: only % of the 5 working item kinds could be added',
      (select count(*) from promotion_items where promotion_id = promo); end if;

  -- Choice groups too, including therapy — whose choices ARE issued, by
  -- invoice_therapy_entitlements_due. Removing that would be a real regression.
  insert into promotion_choice_groups(promotion_id,label,item_kind,choose_qty)
    values (promo,'Pick a therapy','therapy',1) returning id into g;
  insert into promotion_choice_options(group_id, therapy_package_id) values (g, tp);

  insert into promotion_choice_groups(promotion_id,label,item_kind,choose_qty)
    values (promo,'Pick a voucher','voucher',1) returning id into g;
  insert into promotion_choice_options(group_id, voucher_id) values (g, vch);

  insert into promotion_choice_groups(promotion_id,label,item_kind,choose_qty)
    values (promo,'Pick a promotion','promotion',1) returning id into g;
  insert into promotion_choice_options(group_id, child_promotion_id) values (g, child);

  if (select count(*) from promotion_choice_groups where promotion_id = promo) <> 4 then
    raise exception 'FAIL: the working choice-group kinds could not all be saved'; end if;

  raise notice 'PASS: the package kinds are refused with an explanation, and every kind that works is untouched.';
end $$;
rollback;
