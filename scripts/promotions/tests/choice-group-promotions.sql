-- A choice group may offer a promotion, and two kinds that never worked now do (346).
--
-- The screen has always offered four kinds of choice group. Two of them —
-- therapy and credit packages — could not be saved at all, because the options
-- table still carried the constraint it was created with:
--     CHECK (product_id is not null or voucher_id is not null)
-- Production had 34 groups and 73 options, none of them therapy or credit.
--
-- The fifth kind, a group whose options are promotions, faces exactly the rules
-- a nested included item already faces. This drives all of it.
--
-- Disposable database only; everything is rolled back.
\set ON_ERROR_STOP on
begin;
do $$
declare
  own uuid := gen_random_uuid();
  prod uuid; tp uuid; cp uuid;
  parent uuid; child uuid; grandchild uuid; other uuid; withchoice uuid;
  g uuid; v_msg text; n int := 0;
begin
  insert into auth.users(id,email) values (own,'cg@tests.invalid');
  insert into profiles(id,full_name,email,role) values (own,'CG Owner','cg@tests.invalid','owner');
  perform set_config('request.jwt.claim.sub', own::text, true);

  insert into products(name,sku) values ('CG Item','CG-1') returning id into prod;
  -- Built here rather than taken from whatever the database happens to hold,
  -- so the two kinds that never worked are genuinely exercised everywhere.
  insert into unlimited_therapy_packages(name, duration_months)
    values ('CG Therapy', 3) returning id into tp;
  insert into credit_packages(name, customer_price, paid_credit_amount, grants_reward,
                              reward_qualifying_amount, allow_voucher, allow_therapy, effective_from)
    values ('CG Credit Package', 500, 500, false, 500, true, true, current_date) returning id into cp;

  insert into promotions(name,code) values ('CG Parent','CG-PAR') returning id into parent;
  insert into promotions(name,code) values ('CG Child','CG-CHD') returning id into child;
  insert into promotions(name,code) values ('CG Other','CG-OTH') returning id into other;
  insert into promotion_items(promotion_id,item_type,product_id,quantity) values (child,'product',prod,1);

  -- ---- the kind that never worked, and now does --------------------------
  -- Therapy only. 346 also unblocked credit_package groups, but nothing ever
  -- ISSUED one: a customer could choose a package and receive nothing. 352
  -- withdrew that kind for exactly that reason, so this test asserts the
  -- refusal rather than the save. A therapy choice IS issued, by
  -- invoice_therapy_entitlements_due, which is why it stays.
  if tp is null then
    raise exception 'FIXTURE: needed a therapy package to test that kind'; end if;
  insert into promotion_choice_groups(promotion_id,label,item_kind,choose_qty)
    values (parent,'Pick a therapy','therapy',1) returning id into g;
  insert into promotion_choice_options(group_id, therapy_package_id) values (g, tp);
  n := n + 1;

  if cp is null then
    raise exception 'FIXTURE: needed a credit package to test that it is refused'; end if;
  begin
    insert into promotion_choice_groups(promotion_id,label,item_kind,choose_qty)
      values (parent,'Pick a package','credit_package',1);
    raise exception 'FAIL: a choice group still offers credit packages, which are never issued (352)';
  exception when others then
    get stacked diagnostics v_msg = message_text;
    if v_msg like 'FAIL:%' then raise; end if;
  end;

  -- ---- the new kind --------------------------------------------------------
  insert into promotion_choice_groups(promotion_id,label,item_kind,choose_qty)
    values (parent,'Pick a promotion','promotion',1) returning id into g;
  insert into promotion_choice_options(group_id, child_promotion_id) values (g, child);

  -- ---- and the rules it inherits ------------------------------------------
  begin
    insert into promotion_choice_options(group_id, child_promotion_id) values (g, parent);
    raise exception 'FAIL: a promotion was offered inside its own choice group';
  exception when others then
    get stacked diagnostics v_msg = message_text;
    if v_msg like 'FAIL:%' then raise; end if;
    if v_msg !~ 'cannot include itself' then
      raise exception 'FAIL: self-reference refused for the wrong reason (%)', v_msg; end if;
  end;

  insert into promotions(name,code) values ('CG WithChoice','CG-WCH') returning id into withchoice;
  insert into promotion_choice_groups(promotion_id,label,item_kind,choose_qty)
    values (withchoice,'Pick one','product',1);
  begin
    insert into promotion_choice_options(group_id, child_promotion_id) values (g, withchoice);
    raise exception 'FAIL: a promotion with its own choice groups was offered in a choice group';
  exception when others then
    get stacked diagnostics v_msg = message_text;
    if v_msg like 'FAIL:%' then raise; end if;
    if v_msg !~ 'choice groups cannot be nested' then
      raise exception 'FAIL: refused for the wrong reason (%)', v_msg; end if;
  end;

  insert into promotions(name,code) values ('CG Grandchild','CG-GCH') returning id into grandchild;
  insert into promotion_items(promotion_id,item_type,child_promotion_id,quantity)
    values (other,'promotion',grandchild,1);
  begin
    insert into promotion_choice_options(group_id, child_promotion_id) values (g, other);
    raise exception 'FAIL: a promotion containing a promotion was offered, breaking the two-level limit';
  exception when others then
    get stacked diagnostics v_msg = message_text;
    if v_msg like 'FAIL:%' then raise; end if;
    if v_msg !~ 'Nesting limit' then
      raise exception 'FAIL: refused for the wrong reason (%)', v_msg; end if;
  end;

  -- ---- an option must match the kind its group advertises ------------------
  begin
    insert into promotion_choice_options(group_id, product_id) values (g, prod);
    raise exception 'FAIL: a product was added to a group that offers promotions';
  exception when others then
    get stacked diagnostics v_msg = message_text;
    if v_msg like 'FAIL:%' then raise; end if;
    if v_msg !~ 'each option must be' then
      raise exception 'FAIL: mismatched kind refused for the wrong reason (%)', v_msg; end if;
  end;

  -- ---- an option still names exactly one thing -----------------------------
  begin
    insert into promotion_choice_options(group_id, product_id, child_promotion_id) values (g, prod, child);
    raise exception 'FAIL: an option naming two things was accepted';
  exception when check_violation then null;
  when others then
    get stacked diagnostics v_msg = message_text;
    if v_msg like 'FAIL:%' then raise; end if;
  end;

  raise notice 'PASS: a choice group can offer a promotion under the existing nesting rules, therapy options can be saved, and credit packages are refused because nothing issues them';
end $$;
rollback;

-- ---------------------------------------------------------------------------
-- And the till takes it: a real invoice where the cashier picks a promotion
-- from a choice group, priced at the bundle's own price with no top-up (347).
-- ---------------------------------------------------------------------------
begin;
do $$
declare
  own uuid := gen_random_uuid();
  st uuid; cust uuid; prod uuid; pm uuid;
  bundle uuid; child_a uuid; child_b uuid; g uuid; inv uuid;
  v_total numeric; v_topup numeric; v_msg text;
begin
  insert into auth.users(id,email) values (own,'cgt@tests.invalid');
  insert into profiles(id,full_name,email,role) values (own,'CGT Owner','cgt@tests.invalid','owner');
  perform set_config('request.jwt.claim.sub', own::text, true);

  insert into stores(name,code,country_code) values ('CGT Store','CGTS','SG') returning id into st;
  insert into customers(full_name,phone) values ('CGT Buyer','+6591114321') returning id into cust;
  insert into payment_methods(name) values ('CGT Cash') returning id into pm;
  insert into products(name,sku) values ('CGT Item','CGT-1') returning id into prod;
  insert into store_inventory(store_id,product_id,current_qty) values (st,prod,100);
  perform set_product_prices(st, prod, 30, 30, 'available');

  -- Two promotions a customer may choose between, and the bundle that offers them.
  insert into promotions(name,code) values ('CGT Choice A','CGT-A') returning id into child_a;
  insert into promotions(name,code) values ('CGT Choice B','CGT-B') returning id into child_b;
  insert into promotion_items(promotion_id,item_type,product_id,quantity) values
    (child_a,'product',prod,1), (child_b,'product',prod,2);

  insert into promotions(name,code) values ('CGT Blind Box','CGT-BOX') returning id into bundle;
  insert into promotion_choice_groups(promotion_id,label,item_kind,choose_qty)
    values (bundle,'Pick your promotion','promotion',1) returning id into g;
  insert into promotion_choice_options(group_id, child_promotion_id) values (g, child_a), (g, child_b);
  perform set_promotion_prices(bundle, st, 50, 50, true);

  -- The cashier picks B, the dearer one. The blind box is still $50.
  inv := create_invoice(st, cust, null, jsonb_build_array(jsonb_build_object(
    'kind','promotion','promotion_id',bundle,'quantity',1,
    'selections', jsonb_build_array(jsonb_build_object(
      'group_id', g,
      'options', jsonb_build_array(jsonb_build_object('child_promotion_id', child_b, 'quantity', 1)))))));

  select total_amount into v_total from invoices where id = inv;
  select coalesce(sum(topup_amount),0) into v_topup from invoice_items where invoice_id = inv;

  if v_total <> 50 then
    raise exception 'FAIL: the blind box came to % rather than its own price of 50', v_total; end if;
  if v_topup <> 0 then
    raise exception 'FAIL: a promotion choice added a top-up of %, but it is covered by the bundle price', v_topup; end if;

  -- A promotion the group does not offer is refused, and says so plainly.
  begin
    perform create_invoice(st, cust, null, jsonb_build_array(jsonb_build_object(
      'kind','promotion','promotion_id',bundle,'quantity',1,
      'selections', jsonb_build_array(jsonb_build_object(
        'group_id', g,
        'options', jsonb_build_array(jsonb_build_object('child_promotion_id', bundle, 'quantity', 1)))))));
    raise exception 'FAIL: the till accepted a promotion the group never offered';
  exception when others then
    get stacked diagnostics v_msg = message_text;
    if v_msg like 'FAIL:%' then raise; end if;
    if v_msg !~ 'does not belong to choice group' then
      raise exception 'FAIL: refused for the wrong reason (%)', v_msg; end if;
  end;

  -- And the choice is written down. 346 and 347 let a promotion be offered and
  -- validated; neither stored it, so the row recording the pick had group_id
  -- and a quantity with every item column null (349).
  declare v_recorded uuid; v_rows int;
  begin
    select count(*) into v_rows
      from invoice_promotion_selections s
      join invoice_items ii on ii.id = s.invoice_item_id
     where ii.invoice_id = inv;
    select s.child_promotion_id into v_recorded
      from invoice_promotion_selections s
      join invoice_items ii on ii.id = s.invoice_item_id
     where ii.invoice_id = inv limit 1;
    if v_rows <> 1 then
      raise exception 'FAIL: expected one recorded choice, found %', v_rows; end if;
    if v_recorded is null then
      raise exception 'FAIL: the invoice records that a choice was made but not which promotion was chosen'; end if;
    if v_recorded <> child_b then
      raise exception 'FAIL: the invoice records the wrong promotion as chosen'; end if;
  end;

  raise notice 'PASS: the till takes a promotion choice, charges the bundle price with no top-up, records which promotion was chosen, and refuses one the group never offered';
end $$;
rollback;
