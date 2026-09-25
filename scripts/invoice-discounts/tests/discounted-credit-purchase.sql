-- A discounted credit package or premium bundle grants what was paid (355).
--
-- The owner's rule: a discounted credit purchase grants PAID credit equal to the
-- amount actually paid; bonus credit and free vouchers are unchanged.
--
-- Scenario A replicates production invoice INV-2026-0292 exactly: a $15,000
-- premium bundle with a S$3,994 manual discount, part-paid $1,000, $636 and
-- $327, then the S$9,043 balance. Before 355 that final payment was refused,
-- because the issuer passed a discount of 0 and the bundle demanded full price.
--
-- Scenarios H-L (round 2) pin the FOC refusal on a NEW credit line: is_foc as
-- well as foc_quantity, at creation and when a correction adds the line, while
-- is_foc on a product and a Make-FOC line kept through a correction still work.
--
-- Every scenario uses its own customer so credit never leaks between them.
-- Other sessions share the database, so every code, SKU, name, e-mail and phone
-- carries a per-run suffix: two runs never wait on each other's unique keys.
-- Disposable database only; everything is rolled back.
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '10s';
set local statement_timeout = '120s';

-- A Singapore mobile number no customer has, that the phone normaliser accepts
-- as it is (some random +659 numbers it rejects).
create function pg_temp.dcp_phone() returns text language plpgsql volatile as $f$
declare v_phone text;
begin
  loop
    v_phone := '+659' || lpad(floor(random() * 10000000)::int::text, 7, '0');
    exit when public.normalize_customer_phone(v_phone) = v_phone
          and not exists (select 1 from public.customers cu where cu.phone = v_phone);
  end loop;
  return v_phone;
end $f$;

do $$
declare
  x text := substr(md5(random()::text || clock_timestamp()::text), 1, 8);
  o uuid := gen_random_uuid(); s uuid := gen_random_uuid();
  st uuid; pm uuid; v uuid; v2 uuid; pb uuid; cp uuid; pa uuid; lv uuid;
  c uuid; inv uuid; it uuid; it2 uuid;
  v_paid numeric; v_bonus numeric; v_vouchers numeric; v_msg text; v_n int;
  v_legacy_checked boolean := false; v_skipped text[] := '{}';
  v_bundle_basket jsonb; v_line record; v_head record;
begin
  insert into auth.users(id,email) values (o,'dcp-'||x||'@tests.invalid'),(s,'dcp-s-'||x||'@tests.invalid');
  insert into profiles(id,full_name,email,role) values
    (o,'DCP Owner','dcp-'||x||'@tests.invalid','owner'),(s,'DCP Staff','dcp-s-'||x||'@tests.invalid','staff');
  perform set_config('request.jwt.claim.sub', o::text, true);
  insert into stores(name,code,country_code) values ('DCP Store '||x,'DCP'||x,'SG') returning id into st;
  insert into user_store_assignments(user_id,store_id) values (s,st);
  insert into payment_methods(name) values ('DCP Cash '||x) returning id into pm;

  insert into vouchers(name,code,qty_type,reward_eligible) values ('DCP V1 '||x,'DCP-V1-'||x,'limited',true) returning id into v;
  insert into vouchers(name,code,qty_type,reward_eligible) values ('DCP V2 '||x,'DCP-V2-'||x,'limited',true) returning id into v2;
  insert into voucher_store_stock(voucher_id,store_id,current_qty) values (v,st,500),(v2,st,500);
  insert into voucher_store_prices(voucher_id,store_id,selling_price,available_at_store) values (v,st,20,true),(v2,st,20,true);

  insert into premium_bundles(name,customer_payment_amount,paid_credit_amount,bonus_credit_amount,free_voucher_qty,grants_reward)
    values ('DCP $15,000 bundle '||x,15000,15000,2000,150,true) returning id into pb;
  insert into premium_bundle_stores(bundle_id,store_id) values (pb,st);
  insert into premium_bundle_vouchers(bundle_id,voucher_id) values (pb,v),(pb,v2);
  v_bundle_basket := jsonb_build_array(jsonb_build_object('voucher_id',v,'quantity',100),
                                       jsonb_build_object('voucher_id',v2,'quantity',50));

  insert into credit_packages(name,customer_price,paid_credit_amount,allow_product,allow_therapy)
    values ('DCP Credit 500 '||x,500,500,true,true) returning id into cp;
  insert into credit_package_stores(package_id,store_id) values (cp,st);

  insert into products(name,sku,product_type) values ('DCP Product '||x,'DCP-P-'||x,'own') returning id into pa;
  insert into store_inventory(store_id,product_id,current_qty) values (st,pa,100);
  perform set_product_prices(st,pa,100,100,'available');

  -- ── A. INV-2026-0292: a discounted bundle can now be completed ────────────
  insert into customers(full_name,phone) values ('DCP A', pg_temp.dcp_phone()) returning id into c;
  inv := create_invoice_with_details(st, c, jsonb_build_array(jsonb_build_object(
           'kind','premium_bundle','premium_bundle_id',pb,'quantity',1,
           'voucher_selection', jsonb_build_array(jsonb_build_object('voucher_id',v,'quantity',100),
                                                  jsonb_build_object('voucher_id',v2,'quantity',50)))),
         jsonb_build_object('business_date', current_date::text, 'manual_discount', 3994,
                            'manual_discount_reason', 'upgrade from the 3,994 bundle',
                            'service_staff', jsonb_build_array(s)));
  perform record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',1000)), gen_random_uuid());
  perform record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',636)),  gen_random_uuid());
  perform record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',327)),  gen_random_uuid());
  begin
    perform record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',9043)), gen_random_uuid());
  exception when others then
    get stacked diagnostics v_msg = message_text;
    raise exception 'FAIL A: the final payment on a discounted bundle was refused: %', v_msg;
  end;
  if (select status::text from invoices where id = inv) <> 'paid' then
    raise exception 'FAIL A: the discounted bundle did not settle (status %)', (select status from invoices where id = inv); end if;

  select coalesce(sum(original_amount) filter (where category='paid'),0),
         coalesce(sum(original_amount) filter (where category='bonus'),0)
    into v_paid, v_bonus
    from customer_credit_lots where customer_id = c and status <> 'reversed';
  select coalesce(sum(quantity),0) into v_vouchers from customer_reward_vouchers where customer_id = c;
  if v_paid <> 11006 then
    raise exception 'FAIL A: paid credit is %, but the customer paid 11,006 (15,000 less 3,994)', v_paid; end if;
  if v_bonus <> 2000 then
    raise exception 'FAIL A: bonus credit is %, the bundle defines 2,000 whatever the discount', v_bonus; end if;
  if v_vouchers <> 150 then
    raise exception 'FAIL A: % vouchers, the bundle defines 150 whatever the discount', v_vouchers; end if;
  raise notice 'PASS A: INV-2026-0292 replica settles: 11,006 paid credit, 2,000 bonus, 150 vouchers';

  -- ── B. a discounted credit package grants what was paid, not list price ───
  insert into customers(full_name,phone) values ('DCP B', pg_temp.dcp_phone()) returning id into c;
  inv := create_invoice_with_details(st, c, jsonb_build_array(jsonb_build_object(
           'kind','credit_package','credit_package_id',cp,'quantity',1)),
         jsonb_build_object('business_date', current_date::text, 'manual_discount', 100,
                            'manual_discount_reason', 'test discount', 'service_staff', jsonb_build_array(s)));
  perform record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',400)), gen_random_uuid());
  select coalesce(sum(original_amount),0) into v_paid
    from customer_credit_lots where customer_id = c and category = 'paid' and status <> 'reversed';
  if v_paid <> 400 then
    raise exception 'FAIL B: a $500 package sold for $400 granted % paid credit, expected 400', v_paid; end if;
  raise notice 'PASS B: $500 package discounted to $400 grants 400 paid credit';

  -- ── C. an undiscounted package still grants its full credit ──────────────
  insert into customers(full_name,phone) values ('DCP C', pg_temp.dcp_phone()) returning id into c;
  inv := create_invoice_with_details(st, c, jsonb_build_array(jsonb_build_object(
           'kind','credit_package','credit_package_id',cp,'quantity',1)),
         jsonb_build_object('business_date', current_date::text, 'service_staff', jsonb_build_array(s)));
  perform record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',500)), gen_random_uuid());
  select coalesce(sum(original_amount),0) into v_paid
    from customer_credit_lots where customer_id = c and category = 'paid' and status <> 'reversed';
  if v_paid <> 500 then
    raise exception 'FAIL C: an undiscounted $500 package granted %, expected 500 — the fix touched the normal case', v_paid; end if;
  raise notice 'PASS C: an undiscounted package still grants its full 500';

  -- ── D. a discounted package paid in parts never releases more than paid ──
  insert into customers(full_name,phone) values ('DCP D', pg_temp.dcp_phone()) returning id into c;
  inv := create_invoice_with_details(st, c, jsonb_build_array(jsonb_build_object(
           'kind','credit_package','credit_package_id',cp,'quantity',1)),
         jsonb_build_object('business_date', current_date::text, 'manual_discount', 100,
                            'manual_discount_reason', 'test discount', 'service_staff', jsonb_build_array(s)));
  perform record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',150)), gen_random_uuid());
  select coalesce(sum(original_amount),0) into v_paid
    from customer_credit_lots where customer_id = c and category = 'paid' and status <> 'reversed';
  if v_paid > 150 then
    raise exception 'FAIL D: after paying 150 the customer holds % paid credit', v_paid; end if;
  perform record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',250)), gen_random_uuid());
  select coalesce(sum(original_amount),0) into v_paid
    from customer_credit_lots where customer_id = c and category = 'paid' and status <> 'reversed';
  if v_paid <> 400 then
    raise exception 'FAIL D: a $400 discounted package paid in two parts ended with % paid credit, expected 400', v_paid; end if;
  raise notice 'PASS D: part-paid discounted package releases with the money and ends at 400';

  -- ── E. a product's own line voucher does not shrink the package beside it
  insert into customers(full_name,phone) values ('DCP E', pg_temp.dcp_phone()) returning id into c;
  begin
    insert into vouchers(name,code,qty_type,selling_price,voucher_kind,discount_amount)
      values ('DCP Line Voucher '||x,'DCP-LV-'||x,'unlimited',0,'fixed_discount',20) returning id into lv;
    inv := create_invoice_with_details(st, c, jsonb_build_array(
             jsonb_build_object('kind','credit_package','credit_package_id',cp,'quantity',1),
             jsonb_build_object('kind','product','product_id',pa,'quantity',1,'line_voucher_id',lv)),
           jsonb_build_object('business_date', current_date::text, 'service_staff', jsonb_build_array(s)));
    select id into it from invoice_items where invoice_id = inv and line_kind = 'credit_package';
    if invoice_item_external_value(it) <> 500 then
      raise exception 'FAIL E: a $20 voucher on the PRODUCT cut the package line to %', invoice_item_external_value(it); end if;
    raise notice 'PASS E: a line voucher on a product leaves the package beside it at 500';
  exception when others then
    get stacked diagnostics v_msg = message_text;
    if v_msg like 'FAIL%' then raise; end if;
    -- The fixture's voucher shape is catalogue-dependent; if this build cannot
    -- express a product line voucher, say so rather than pass silently.
    raise notice 'SKIP E: could not build a product line voucher here (%)', v_msg;
    v_skipped := v_skipped || 'E'::text;
  end;

  -- ── F. FOC or a line voucher on a NEW credit line is refused, clearly ────
  insert into customers(full_name,phone) values ('DCP F', pg_temp.dcp_phone()) returning id into c;
  begin
    perform create_invoice(st, c, null::uuid, jsonb_build_array(jsonb_build_object(
      'kind','credit_package','credit_package_id',cp,'quantity',1,'foc_quantity',1,'foc_reason','Staff welfare')), 0::numeric, null::text, null::uuid, '[]'::jsonb);
    raise exception 'FAIL F: FOC on a new credit package line was accepted (the 8-argument path)';
  exception when others then
    get stacked diagnostics v_msg = message_text;
    if v_msg like 'FAIL%' then raise; end if;
    if v_msg !~ 'cannot be made FOC when the invoice is created' then
      raise exception 'FAIL F: FOC refused for the wrong reason: %', v_msg; end if;
  end;
  raise notice 'PASS F (8-argument): foc_quantity on a new credit package line is refused';
  -- The legacy 7-argument overload never declared v_foc_qty, so a refusal that
  -- referenced it would install cleanly and fail at runtime. With both overloads
  -- present it cannot be called at all (seven arguments match both, the newer
  -- one defaulting its eighth), so to exercise its patched body for real the
  -- newer overload is dropped inside a savepoint, the legacy one is called, and
  -- the drop is rolled back by a sentinel exception.
  if to_regprocedure('public.create_invoice(uuid,uuid,uuid,jsonb,numeric,text,uuid)') is null then
    raise notice 'SKIP F (legacy): no 7-argument create_invoice in this database to exercise';
    v_skipped := v_skipped || 'F (legacy)'::text;
  else
  begin
    drop function public.create_invoice(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb);
    begin
      perform create_invoice(st, c, null::uuid, jsonb_build_array(jsonb_build_object(
        'kind','credit_package','credit_package_id',cp,'quantity',1,'foc_quantity',1,'foc_reason','Staff welfare')),
        0::numeric, null::text, null::uuid);
      raise exception 'FAIL F: the legacy 7-argument create_invoice accepted FOC on a credit line';
    exception when others then
      get stacked diagnostics v_msg = message_text;
      if v_msg like 'FAIL%' then raise; end if;
      if v_msg ~ 'v_foc_qty' then
        raise exception 'FAIL F: the legacy create_invoice references an undeclared variable: %', v_msg; end if;
      if v_msg !~ 'cannot be made FOC when the invoice is created' then
        raise exception 'FAIL F: the legacy path refused FOC for the wrong reason: %', v_msg; end if;
    end;
    -- ...and it still sells an ordinary credit package.
    inv := create_invoice(st, c, null::uuid, jsonb_build_array(jsonb_build_object(
             'kind','credit_package','credit_package_id',cp,'quantity',1)), 0::numeric, null::text, null::uuid);
    if inv is null then raise exception 'FAIL F: the legacy path can no longer sell a credit package'; end if;
    raise notice 'PASS F (legacy): the patched 7-argument body runs, refuses FOC, and still sells';
    -- A variable survives the sentinel's rollback; the dropped function does not.
    v_legacy_checked := true;
    raise exception 'ROLLBACK_LEGACY_PROBE';
  exception when others then
    get stacked diagnostics v_msg = message_text;
    if v_msg <> 'ROLLBACK_LEGACY_PROBE' then raise; end if;
  end;
  end if;
  if to_regprocedure('public.create_invoice(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb)') is null then
    raise exception 'FIXTURE F: the probe failed to restore the current create_invoice'; end if;
  -- Only claim both overloads when both were actually exercised. A skipped
  -- legacy probe already said SKIP above and must not be reported as a PASS.
  if v_legacy_checked then
    raise notice 'PASS F: FOC on a new credit line is refused on both create_invoice overloads';
  elsif to_regprocedure('public.create_invoice(uuid,uuid,uuid,jsonb,numeric,text,uuid)') is not null then
    raise exception 'FAIL F: a 7-argument create_invoice exists but the legacy probe never completed';
  end if;

  -- ── G. a discount given after credit was released takes the excess back ─
  insert into customers(full_name,phone) values ('DCP G', pg_temp.dcp_phone()) returning id into c;
  inv := create_invoice_with_details(st, c, jsonb_build_array(jsonb_build_object(
           'kind','credit_package','credit_package_id',cp,'quantity',1)),
         jsonb_build_object('business_date', current_date::text, 'service_staff', jsonb_build_array(s)));
  perform record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',450)), gen_random_uuid());
  select coalesce(sum(remaining_amount),0) into v_paid
    from customer_credit_lots where customer_id = c and category = 'paid' and status = 'active';
  if v_paid <> 450 then raise exception 'FIXTURE G: expected 450 released, got %', v_paid; end if;
  select id into it from invoice_items where invoice_id = inv and line_kind = 'credit_package';
  perform correct_invoice(inv,
    jsonb_build_array(jsonb_build_object('invoice_item_id',it,'kind','credit_package','credit_package_id',cp,'quantity',1)),
    jsonb_build_object('manual_discount', 100, 'manual_discount_reason', 'late discount'),
    'Late discount', gen_random_uuid());
  select coalesce(sum(remaining_amount),0) into v_paid
    from customer_credit_lots where customer_id = c and category = 'paid' and status = 'active';
  if v_paid > 400 then
    raise exception 'FAIL G: after discounting to $400, the customer still holds % paid credit', v_paid; end if;
  raise notice 'PASS G: a later discount took back the unspent excess (holds %)', v_paid;

  -- ── H. is_foc on a NEW credit line is refused at creation (355, round 2) ──
  -- is_foc means "the whole quantity is FOC"; it is the other way a line asks
  -- for FOC and must be refused exactly like foc_quantity. A reason is supplied
  -- so the mandatory-FOC-reason check cannot be what stops the line.
  insert into customers(full_name,phone) values ('DCP H', pg_temp.dcp_phone()) returning id into c;
  begin
    perform create_invoice_with_details(st, c, jsonb_build_array(jsonb_build_object(
      'kind','credit_package','credit_package_id',cp,'quantity',1,'is_foc',true,'foc_reason','Staff welfare')),
      jsonb_build_object('business_date', current_date::text, 'service_staff', jsonb_build_array(s)));
    raise exception 'FAIL H: is_foc on a new credit package line was accepted by create_invoice_with_details';
  exception when others then
    get stacked diagnostics v_msg = message_text;
    if v_msg like 'FAIL%' then raise; end if;
    if position('A credit package cannot be made FOC when the invoice is created' in v_msg) = 0 then
      raise exception 'FAIL H: is_foc on a new credit package was refused for the wrong reason: %', v_msg; end if;
  end;
  begin
    perform create_invoice_with_details(st, c, jsonb_build_array(jsonb_build_object(
      'kind','premium_bundle','premium_bundle_id',pb,'quantity',1,'is_foc',true,'foc_reason','Staff welfare',
      'voucher_selection', v_bundle_basket)),
      jsonb_build_object('business_date', current_date::text, 'service_staff', jsonb_build_array(s)));
    raise exception 'FAIL H: is_foc on a new premium bundle line was accepted by create_invoice_with_details';
  exception when others then
    get stacked diagnostics v_msg = message_text;
    if v_msg like 'FAIL%' then raise; end if;
    if position('A premium bundle cannot be made FOC when the invoice is created' in v_msg) = 0 then
      raise exception 'FAIL H: is_foc on a new premium bundle was refused for the wrong reason: %', v_msg; end if;
  end;
  raise notice 'PASS H: is_foc on a new credit package and on a new premium bundle is refused at creation, with the FOC message';

  -- ── I. ...and when a correction ADDS the credit line ─────────────────────
  insert into customers(full_name,phone) values ('DCP I', pg_temp.dcp_phone()) returning id into c;
  inv := create_invoice_with_details(st, c, jsonb_build_array(
           jsonb_build_object('kind','product','product_id',pa,'quantity',1)),
         jsonb_build_object('business_date', current_date::text, 'service_staff', jsonb_build_array(s)));
  select id into it2 from invoice_items where invoice_id = inv and line_kind = 'product';
  begin
    perform correct_invoice(inv, jsonb_build_array(
      jsonb_build_object('invoice_item_id',it2,'kind','product','product_id',pa,'quantity',1),
      jsonb_build_object('kind','credit_package','credit_package_id',cp,'quantity',1,'is_foc',true,'foc_reason','Staff welfare')),
      '{}'::jsonb, 'Add a free package', gen_random_uuid());
    raise exception 'FAIL I: a correction added a credit package line with is_foc';
  exception when others then
    get stacked diagnostics v_msg = message_text;
    if v_msg like 'FAIL%' then raise; end if;
    if position('A credit package cannot be made FOC when the invoice is created' in v_msg) = 0 then
      raise exception 'FAIL I: is_foc on an added credit package was refused for the wrong reason: %', v_msg; end if;
  end;
  begin
    perform correct_invoice(inv, jsonb_build_array(
      jsonb_build_object('invoice_item_id',it2,'kind','product','product_id',pa,'quantity',1),
      jsonb_build_object('kind','credit_package','credit_package_id',cp,'quantity',1,'foc_quantity',1,'foc_reason','Staff welfare')),
      '{}'::jsonb, 'Add a free package', gen_random_uuid());
    raise exception 'FAIL I: a correction added a credit package line with foc_quantity';
  exception when others then
    get stacked diagnostics v_msg = message_text;
    if v_msg like 'FAIL%' then raise; end if;
    if position('A credit package cannot be made FOC when the invoice is created' in v_msg) = 0 then
      raise exception 'FAIL I: foc_quantity on an added credit package was refused for the wrong reason: %', v_msg; end if;
  end;
  begin
    perform correct_invoice(inv, jsonb_build_array(
      jsonb_build_object('invoice_item_id',it2,'kind','product','product_id',pa,'quantity',1),
      jsonb_build_object('kind','premium_bundle','premium_bundle_id',pb,'quantity',1,'is_foc',true,'foc_reason','Staff welfare',
                         'voucher_selection', v_bundle_basket)),
      '{}'::jsonb, 'Add a free bundle', gen_random_uuid());
    raise exception 'FAIL I: a correction added a premium bundle line with is_foc';
  exception when others then
    get stacked diagnostics v_msg = message_text;
    if v_msg like 'FAIL%' then raise; end if;
    if position('A premium bundle cannot be made FOC when the invoice is created' in v_msg) = 0 then
      raise exception 'FAIL I: is_foc on an added premium bundle was refused for the wrong reason: %', v_msg; end if;
  end;
  -- The refusal is about FOC, not about adding credit in a correction: the same
  -- lines without FOC go through, charged in full.
  perform correct_invoice(inv, jsonb_build_array(
    jsonb_build_object('invoice_item_id',it2,'kind','product','product_id',pa,'quantity',1),
    jsonb_build_object('kind','credit_package','credit_package_id',cp,'quantity',1),
    jsonb_build_object('kind','premium_bundle','premium_bundle_id',pb,'quantity',1,'voucher_selection', v_bundle_basket)),
    '{}'::jsonb, 'Add a package and a bundle', gen_random_uuid());
  select count(*) filter (where line_kind in ('credit_package','premium_bundle')) as credit_lines,
         count(*) filter (where coalesce(foc_quantity,0) > 0 or is_foc) as foc_lines
    into v_line from invoice_items where invoice_id = inv;
  select total_amount, foc_total into v_head from invoices where id = inv;
  if v_line.credit_lines <> 2 or v_line.foc_lines <> 0 or v_head.total_amount <> 15600 or coalesce(v_head.foc_total,0) <> 0 then
    raise exception 'FAIL I: adding a package and a bundle without FOC gave % credit lines, % FOC lines, total %, FOC %',
      v_line.credit_lines, v_line.foc_lines, v_head.total_amount, v_head.foc_total; end if;
  raise notice 'PASS I: a correction adding a credit package (is_foc or foc_quantity) or a premium bundle (is_foc) as FOC is refused; without FOC it is added';

  -- ── J. an explicit "not FOC" on a new credit line is not mistaken for FOC ─
  insert into customers(full_name,phone) values ('DCP J', pg_temp.dcp_phone()) returning id into c;
  begin
    inv := create_invoice_with_details(st, c, jsonb_build_array(
             jsonb_build_object('kind','credit_package','credit_package_id',cp,'quantity',1,'is_foc',false,'foc_quantity',0),
             jsonb_build_object('kind','premium_bundle','premium_bundle_id',pb,'quantity',1,'is_foc',false,'foc_quantity',0,
                                'voucher_selection', v_bundle_basket)),
           jsonb_build_object('business_date', current_date::text, 'service_staff', jsonb_build_array(s)));
  exception when others then
    get stacked diagnostics v_msg = message_text;
    raise exception 'FAIL J: is_foc false / foc_quantity 0 on new credit lines was refused: %', v_msg;
  end;
  if (select total_amount from invoices where id = inv) <> 15500 then
    raise exception 'FAIL J: the package and bundle with is_foc false total %, expected 15,500',
      (select total_amount from invoices where id = inv); end if;
  raise notice 'PASS J: is_foc false and foc_quantity 0 on new credit lines are accepted and charged in full';

  -- ── K. is_foc on a PRODUCT line is still accepted ────────────────────────
  insert into customers(full_name,phone) values ('DCP K', pg_temp.dcp_phone()) returning id into c;
  begin
    inv := create_invoice_with_details(st, c, jsonb_build_array(
             jsonb_build_object('kind','product','product_id',pa,'quantity',1,'is_foc',true,'foc_reason','Staff welfare')),
           jsonb_build_object('business_date', current_date::text, 'service_staff', jsonb_build_array(s)));
  exception when others then
    get stacked diagnostics v_msg = message_text;
    raise exception 'FAIL K: is_foc on a product line was refused at creation: %', v_msg;
  end;
  select * into v_line from invoice_items where invoice_id = inv;
  select total_amount, foc_total, has_foc into v_head from invoices where id = inv;
  if not coalesce(v_line.is_foc,false) or v_line.foc_quantity <> 1 or v_line.foc_amount <> 100
     or v_line.line_total <> 0 or v_line.foc_reason is distinct from 'Staff welfare' then
    raise exception 'FAIL K: an is_foc product line was saved as is_foc %, FOC qty %, FOC % , charged %, reason %',
      v_line.is_foc, v_line.foc_quantity, v_line.foc_amount, v_line.line_total, v_line.foc_reason; end if;
  if not v_head.has_foc or v_head.total_amount <> 0 or v_head.foc_total <> 100 then
    raise exception 'FAIL K: an all-FOC product invoice shows has_foc %, total %, FOC %',
      v_head.has_foc, v_head.total_amount, v_head.foc_total; end if;
  -- ...and a correction may add one.
  inv := create_invoice_with_details(st, c, jsonb_build_array(
           jsonb_build_object('kind','product','product_id',pa,'quantity',1)),
         jsonb_build_object('business_date', current_date::text, 'service_staff', jsonb_build_array(s)));
  select id into it2 from invoice_items where invoice_id = inv;
  begin
    perform correct_invoice(inv, jsonb_build_array(
      jsonb_build_object('invoice_item_id',it2,'kind','product','product_id',pa,'quantity',1),
      jsonb_build_object('kind','product','product_id',pa,'quantity',2,'is_foc',true,'foc_reason','Staff welfare')),
      '{}'::jsonb, 'Add two free products', gen_random_uuid());
  exception when others then
    get stacked diagnostics v_msg = message_text;
    raise exception 'FAIL K: a correction adding an is_foc product line was refused: %', v_msg;
  end;
  select * into v_line from invoice_items where invoice_id = inv and id <> it2;
  select total_amount, foc_total, has_foc into v_head from invoices where id = inv;
  if not coalesce(v_line.is_foc,false) or v_line.foc_quantity <> 2 or v_line.foc_amount <> 200 or v_line.line_total <> 0 then
    raise exception 'FAIL K: the added is_foc product line was saved as is_foc %, FOC qty %, FOC %, charged %',
      v_line.is_foc, v_line.foc_quantity, v_line.foc_amount, v_line.line_total; end if;
  if v_head.total_amount <> 100 or v_head.foc_total <> 200 then
    raise exception 'FAIL K: after adding two free products the invoice totals %, FOC % (expected 100 and 200)',
      v_head.total_amount, v_head.foc_total; end if;
  raise notice 'PASS K: is_foc on a product line is still accepted, at creation and when a correction adds it';

  -- ── L. a Make-FOC credit line kept through a correction is not "new" ─────
  -- The refusal is for NEW lines. A package given away with Make FOC and sent
  -- back unchanged (its FOC fields included) must pass through a correction that
  -- adds something else, and stay FOC.
  insert into customers(full_name,phone) values ('DCP L', pg_temp.dcp_phone()) returning id into c;
  inv := create_invoice_with_details(st, c, jsonb_build_array(
           jsonb_build_object('kind','product','product_id',pa,'quantity',1),
           jsonb_build_object('kind','credit_package','credit_package_id',cp,'quantity',1)),
         jsonb_build_object('business_date', current_date::text, 'service_staff', jsonb_build_array(s)));
  select id into it2 from invoice_items where invoice_id = inv and line_kind = 'product';
  select id into it  from invoice_items where invoice_id = inv and line_kind = 'credit_package';
  perform apply_line_foc(it, 1, null, 'Staff welfare');
  if (select total_amount from invoices where id = inv) <> 100
     or not (select is_foc from invoice_items where id = it) then
    raise exception 'FIXTURE L: Make FOC did not give the package away'; end if;
  begin
    perform correct_invoice(inv, jsonb_build_array(
      jsonb_build_object('invoice_item_id',it2,'kind','product','product_id',pa,'quantity',1,'unit_price',100),
      jsonb_build_object('invoice_item_id',it,'kind','credit_package','credit_package_id',cp,'quantity',1,'unit_price',500,
                         'foc_quantity',1,'foc_reason','Staff welfare'),
      jsonb_build_object('kind','product','product_id',pa,'quantity',1)),
      '{}'::jsonb, 'Add a product beside the free package', gen_random_uuid());
  exception when others then
    get stacked diagnostics v_msg = message_text;
    raise exception 'FAIL L: a correction keeping a Make-FOC package line was refused: %', v_msg;
  end;
  select * into v_line from invoice_items where invoice_id = inv and line_kind = 'credit_package';
  select total_amount, foc_total into v_head from invoices where id = inv;
  if v_line.id <> it or not coalesce(v_line.is_foc,false) or v_line.foc_amount <> 500 or v_line.line_total <> 0 then
    raise exception 'FAIL L: the kept FOC package came back as same line %, is_foc %, FOC %, charged %',
      v_line.id = it, v_line.is_foc, v_line.foc_amount, v_line.line_total; end if;
  if v_head.total_amount <> 200 or v_head.foc_total <> 500 then
    raise exception 'FAIL L: after adding a product beside the free package the invoice totals %, FOC % (expected 200 and 500)',
      v_head.total_amount, v_head.foc_total; end if;
  raise notice 'PASS L: a Make-FOC package kept through a correction is not refused and stays FOC';

  -- L2. The same kept line as the invoice form actually sends it. The form's
  -- loader (InvoicesPage, edit mode) does not copy foc_quantity/foc_reason onto
  -- credit_package or premium_bundle lines, so the line no longer "matches",
  -- update_invoice_internal rewrites it through the credit_package upsert (which
  -- does not touch the foc_* columns), and the invoice charges the package again
  -- while the line still says FOC. Only the note changes here.
  inv := create_invoice_with_details(st, c, jsonb_build_array(
           jsonb_build_object('kind','product','product_id',pa,'quantity',1),
           jsonb_build_object('kind','credit_package','credit_package_id',cp,'quantity',1)),
         jsonb_build_object('business_date', current_date::text, 'service_staff', jsonb_build_array(s)));
  select id into it2 from invoice_items where invoice_id = inv and line_kind = 'product';
  select id into it  from invoice_items where invoice_id = inv and line_kind = 'credit_package';
  perform apply_line_foc(it, 1, null, 'Staff welfare');
  -- Sent without its FOC, the line would be re-charged while still saying FOC.
  -- It is refused instead (the form now sends a Make-FOC credit line back with
  -- its FOC, so staff never meet this), and nothing on the invoice moves.
  begin
    perform correct_invoice(inv, jsonb_build_array(
      jsonb_build_object('invoice_item_id',it2,'kind','product','product_id',pa,'quantity',1,'unit_price',100),
      jsonb_build_object('invoice_item_id',it,'kind','credit_package','credit_package_id',cp,'quantity',1,'unit_price',500)),
      jsonb_build_object('notes','only the note changed'), 'Note only', gen_random_uuid());
    raise exception 'FAIL L2: a correction that drops a Make-FOC package''s FOC was accepted';
  exception when others then
    if sqlerrm like 'FAIL L2%' then raise; end if;
    if sqlerrm not like '%FOC can only be changed with Make FOC or Undo FOC%' then
      raise exception 'FAIL L2: refused for the wrong reason: %', sqlerrm; end if;
  end;
  select * into v_line from invoice_items where id = it;
  select total_amount, foc_total into v_head from invoices where id = inv;
  if v_head.total_amount <> 100 or v_head.foc_total <> 500 or v_line.line_total <> 0 or not coalesce(v_line.is_foc,false) then
    raise exception 'FAIL L2: the refused correction still changed the invoice: total %, FOC %, line is_foc %, charged %',
      v_head.total_amount, v_head.foc_total, v_line.is_foc, v_line.line_total; end if;
  raise notice 'PASS L2: a correction that would drop a credit line''s FOC is refused; the invoice is unchanged';

  if cardinality(v_skipped) > 0 then
    raise notice 'PASS (with SKIP: %): a discounted credit purchase grants what was paid, a discounted bundle completes, and nothing else moved.',
      array_to_string(v_skipped, ', ');
  else
    raise notice 'PASS: a discounted credit purchase grants what was paid, a discounted bundle completes, and nothing else moved.';
  end if;
end $$;
rollback;
