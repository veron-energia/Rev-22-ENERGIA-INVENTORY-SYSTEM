-- The four holes 350 left in the money path, and 351 closed.
--
-- 350 taught ONE function that a promotion line can carry a benefit. Every
-- other function in the money path still believed only line_kind
-- 'credit_package' and 'premium_bundle' ever do. Each of those beliefs was a
-- hole, and none of them is visible from the happy path that
-- promotion-package-benefits.sql exercises — which is exactly why 350 passed
-- its own test while being unsafe to ship.
--
--   1. wallet credit could buy a promotion that grants credit — the customer
--      spends restricted credit and receives fresh credit: minting;
--   2. refunding such a promotion returned the cash and left the credit;
--   3. a bundle inside a promotion was valued at zero for exchanges;
--   4. an unavailable bundle inside a promotion aborted settlement at the till.
--
-- Disposable database only; everything is rolled back.
\set ON_ERROR_STOP on
begin;
do $$
declare
  own uuid := gen_random_uuid();
  st uuid; st2 uuid; cust uuid; cp uuid; pb uuid; promo uuid; plain uuid;
  inv uuid; li uuid; v_msg text; v_alloc jsonb; v_funded numeric; v_total numeric;
  PROMO_PRICE constant numeric := 300;
  PKG_CREDIT  constant numeric := 500;
  BUNDLE_PAY  constant numeric := 2000;
begin
  insert into auth.users(id,email) values (own,'pkm@tests.invalid');
  insert into profiles(id,full_name,email,role) values (own,'PKM Owner','pkm@tests.invalid','owner');
  perform set_config('request.jwt.claim.sub', own::text, true);

  insert into stores(name,code) values ('PKM Store','PKM') returning id into st;
  insert into stores(name,code) values ('PKM Other','PKM2') returning id into st2;
  insert into customers(full_name,phone) values ('PKM Customer','+6590000351') returning id into cust;

  insert into credit_packages(name, customer_price, paid_credit_amount, grants_reward,
                              reward_qualifying_amount, allow_voucher, allow_therapy, effective_from)
    values ('PKM Package', PKG_CREDIT, PKG_CREDIT, false, PKG_CREDIT, true, true, current_date)
    returning id into cp;
  insert into premium_bundles(name, customer_payment_amount, paid_credit_amount,
                              bonus_credit_amount, free_voucher_qty, effective_from)
    values ('PKM Bundle', BUNDLE_PAY, BUNDLE_PAY, 0, 0, current_date)
    returning id into pb;

  insert into promotions(name,code) values ('PKM Promo','PKM-1') returning id into promo;
  perform public.add_promotion_item(promo,'credit_package'::public.promotion_item_type,
    null,null,null,null,1,null,null,cp,null);
  perform public.add_promotion_item(promo,'premium_bundle'::public.promotion_item_type,
    null,null,null,null,1,null,null,null,pb);

  -- ── 3. a bundle inside a promotion is worth what it costs ─────────────────
  -- Checked first because it needs nothing sold. Before 351 this returned only
  -- the package's 500: the bundle contributed nothing, and a whole-bundle
  -- exchange pays out on this figure.
  v_total := public.promotion_original_total(promo, st);
  if v_total <> PKG_CREDIT + BUNDLE_PAY then
    raise exception 'FAIL: the promotion''s original total is %, but it contains a % package and a % bundle',
      v_total, PKG_CREDIT, BUNDLE_PAY; end if;

  -- ── 1. credit may not buy credit through a promotion wrapper ──────────────
  -- Give the customer a wallet balance, then try to pay a promotion that grants
  -- a package out of it. Before 351 the allocator funded the line, because a
  -- promotion's purpose is 'promotion' and it only skipped the two direct kinds.
  insert into invoices(invoice_no,store_id,customer_id,created_by,status,
                       subtotal,discount_total,total_amount)
    values ('PKM-TEST-1',st,cust,own,'unpaid',PROMO_PRICE,0,PROMO_PRICE)
    returning id into inv;
  insert into invoice_items(invoice_id,line_kind,promotion_id,quantity,unit_price,line_total)
    values (inv,'promotion',promo,1,PROMO_PRICE,PROMO_PRICE)
    returning id into li;

  -- Granted through the real path rather than by hand, so the lot is shaped
  -- the way the allocator expects. Note credit_spendable_categories() already
  -- includes 'promotion': wallet credit is MEANT to buy promotions. The guard
  -- has to be narrow enough to keep that true, which is asserted below.
  perform public.add_legacy_credit(cust, 'legacy', 1000, current_date, st,
                                   'PKM-CREDIT', 'test fixture', current_date, own);

  begin
    v_alloc := public.allocate_invoice_wallet_credit(inv, PROMO_PRICE, null);
  exception when others then
    get stacked diagnostics v_msg = message_text;
    v_alloc := jsonb_build_object('refused', v_msg);
  end;
  select coalesce(sum(amount - coalesce(reversed_amount,0)),0) into v_funded
    from invoice_line_credit_allocations where invoice_item_id = li;
  if v_funded > 0 then
    raise exception 'FAIL: wallet credit funded % of a promotion that grants a credit package; the customer mints money (%)',
      v_funded, v_alloc; end if;

  -- A promotion that contains NO package is still payable from the wallet —
  -- the guard must be narrow, not a blanket ban on paying for promotions.
  insert into promotions(name,code) values ('PKM Plain','PKM-2') returning id into plain;
  perform public.add_promotion_item(plain,'treatment'::public.promotion_item_type,
    null,null,null,'A treatment',1,null,null,null,null);
  declare inv2 uuid; li2 uuid; v_funded2 numeric;
  begin
    insert into invoices(invoice_no,store_id,customer_id,created_by,status,
                         subtotal,discount_total,total_amount)
      values ('PKM-TEST-2',st,cust,own,'unpaid',100,0,100) returning id into inv2;
    insert into invoice_items(invoice_id,line_kind,promotion_id,quantity,unit_price,line_total)
      values (inv2,'promotion',plain,1,100,100) returning id into li2;
    perform public.allocate_invoice_wallet_credit(inv2, 100, null);
    select coalesce(sum(amount - coalesce(reversed_amount,0)),0) into v_funded2
      from invoice_line_credit_allocations where invoice_item_id = li2;
    if v_funded2 <= 0 then
      raise exception 'FAIL: the guard is too broad — an ordinary promotion can no longer be paid from the wallet'; end if;
  end;

  -- ── 2. refunding it reverses what it granted ──────────────────────────────
  -- Settle the first invoice with real money, then assert the refund path now
  -- recognises the promotion line as benefit-bearing. Before 351 the branch
  -- test excluded it outright, so the reversal block never ran: cash back,
  -- credit kept.
  update invoices set status = 'paid' where id = inv;
  if (select count(*) from invoice_benefit_values where invoice_item_id = li) = 0 then
    raise exception 'FIXTURE: the settlement recorded no benefit values to reverse'; end if;

  -- NOTE ON THIS ASSERTION. It checks the function's TEXT, and that is a weak
  -- test: an earlier draft of 351 passed this exact check while having broken
  -- EVERY refund in the system, because it aliased the subquery `b` and the
  -- function already declares a variable `b` (plpgsql.variable_conflict is
  -- 'error' here). A text assertion cannot see that — plpgsql parses lazily, so
  -- only actually running a refund does.
  --
  -- What caught it were the behavioural suites, which must be run alongside
  -- this one and are the real gate:
  --   scripts/invoices/regression.sql
  --   scripts/invoices/tests/benefit-corrections.sql
  --   scripts/invoice-actions/tests/cancel-refund-combined.sql
  --
  -- This assertion is kept only to pin the alias, and it pins the CORRECT one.
  if (select prosrc from pg_proc where proname='refund_invoice_recorded'
        and pronamespace='public'::regnamespace)
     not like '%invoice_benefit_values ibv where ibv.invoice_item_id = it.id%' then
    raise exception 'FAIL: refund_invoice_recorded still cannot see a promotion line''s granted benefits'; end if;

  -- ── 4. an unsellable package cannot be authored into a promotion ──────────
  declare p3 uuid; pb2 uuid;
  begin
    insert into promotions(name,code) values ('PKM Promo3','PKM-3') returning id into p3;

    -- store-scoped
    insert into premium_bundles(name, customer_payment_amount, effective_from)
      values ('PKM Scoped', 500, current_date) returning id into pb2;
    insert into premium_bundle_stores(bundle_id, store_id) values (pb2, st2);
    begin
      perform public.add_promotion_item(p3,'premium_bundle'::public.promotion_item_type,
        null,null,null,null,1,null,null,null,pb2);
      raise exception 'FAIL: a store-limited bundle was accepted into a promotion; settlement would abort at any other store';
    exception when others then
      get stacked diagnostics v_msg = message_text;
      if v_msg like 'FAIL:%' then raise; end if;
      if v_msg !~ 'limited to certain stores' then
        raise exception 'FAIL: refused for the wrong reason (%)', v_msg; end if;
    end;

    -- inactive
    update premium_bundles set is_active = false where id = pb2;
    delete from premium_bundle_stores where bundle_id = pb2;
    begin
      perform public.add_promotion_item(p3,'premium_bundle'::public.promotion_item_type,
        null,null,null,null,1,null,null,null,pb2);
      raise exception 'FAIL: an inactive bundle was accepted into a promotion';
    exception when others then
      get stacked diagnostics v_msg = message_text;
      if v_msg like 'FAIL:%' then raise; end if;
      if v_msg !~ 'Activate' then
        raise exception 'FAIL: inactive bundle refused for the wrong reason (%)', v_msg; end if;
    end;
  end;

  -- ── 4b. and one already inside a promotion cannot become unsellable ───────
  begin
    update premium_bundles set is_active = false where id = pb;
    raise exception 'FAIL: a bundle inside a live promotion was retired; its promotion would fail at the till';
  exception when others then
    get stacked diagnostics v_msg = message_text;
    if v_msg like 'FAIL:%' then raise; end if;
    if v_msg !~ 'inside promotion' then
      raise exception 'FAIL: retiring refused for the wrong reason (%)', v_msg; end if;
  end;

  begin
    insert into premium_bundle_stores(bundle_id, store_id) values (pb, st2);
    raise exception 'FAIL: a bundle inside a live promotion was limited to one store';
  exception when others then
    get stacked diagnostics v_msg = message_text;
    if v_msg like 'FAIL:%' then raise; end if;
    if v_msg !~ 'inside promotion' then
      raise exception 'FAIL: store-limiting refused for the wrong reason (%)', v_msg; end if;
  end;

  begin
    update credit_packages set is_active = false where id = cp;
    raise exception 'FAIL: a credit package inside a live promotion was retired';
  exception when others then
    get stacked diagnostics v_msg = message_text;
    if v_msg like 'FAIL:%' then raise; end if;
    if v_msg !~ 'inside promotion' then
      raise exception 'FAIL: package retiring refused for the wrong reason (%)', v_msg; end if;
  end;

  -- ── 4c. but the guard must not outlive the promotion ─────────────────────
  -- A guard that stops an Owner retiring an old bundle because of a promotion
  -- nobody can buy any more would be a worse bug than the one it prevents.
  -- Retire the promotion, and the bundle must become retirable again.
  update invoices set status = 'cancelled' where id = inv;
  update promotions set is_active = false where id = promo;
  begin
    update premium_bundles set is_active = false where id = pb;
  exception when others then
    get stacked diagnostics v_msg = message_text;
    raise exception 'FAIL: the bundle is still locked by a promotion that is no longer sellable (%)', v_msg;
  end;
  update premium_bundles set is_active = true where id = pb;

  -- Same for a deleted promotion.
  update promotions set is_active = true, deleted_at = now() where id = promo;
  begin
    update credit_packages set is_active = false where id = cp;
  exception when others then
    get stacked diagnostics v_msg = message_text;
    raise exception 'FAIL: the credit package is still locked by a deleted promotion (%)', v_msg;
  end;

  raise notice 'PASS: the promotion keeps its own money, and its packages stay sellable.';
end $$;
rollback;
