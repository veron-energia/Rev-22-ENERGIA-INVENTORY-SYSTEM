-- A credit package or premium bundle inside a promotion grants what it
-- promises — exactly once, and still exactly once after a correction (350).
--
-- Before 350 the promotion editor let you put a credit package into a
-- promotion's Included items, and selling that promotion granted the customer
-- nothing at all. This proves the four things that had to become true, and the
-- one that had to STAY true:
--
--   1. settling the invoice issues the package's credit and sells the bundle;
--   2. the amount granted comes from the PACKAGE definition, not from the
--      promotion's price — a $300 promotion containing a $500 package grants
--      $500 of credit, and the derived sale records NO cash of its own, which
--      is what keeps the commission single (351);
--   3. issuing twice is impossible: the flag sits on the promotion line;
--   4. a correction cannot resurrect the benefit, because the promotion line
--      is in the correction payload and survives the delete that would have
--      wiped a derived child line;
--   5. invoice_benefit_values is written, without which
--      cancel_invoice_recorded refuses to cancel the invoice forever.
--
-- Disposable database only; everything is rolled back.
\set ON_ERROR_STOP on
begin;
do $$
declare
  own uuid := gen_random_uuid();
  st uuid; cust uuid; cp uuid; pb uuid; promo uuid; inv uuid; li uuid;
  v_cp_sales int; v_pb_sales int; v_lots int; v_granted numeric; v_paid numeric;
  v_issued timestamptz; v_bv int; v_msg text; v_n int;
  PROMO_PRICE constant numeric := 300;
  PKG_CREDIT  constant numeric := 500;
  BUNDLE_PAY  constant numeric := 2000;
begin
  -- ── actors ────────────────────────────────────────────────────────────────
  insert into auth.users(id,email) values (own,'ppb@tests.invalid');
  insert into profiles(id,full_name,email,role) values (own,'PPB Owner','ppb@tests.invalid','owner');
  perform set_config('request.jwt.claim.sub', own::text, true);

  insert into stores(name,code) values ('PPB Store','PPB') returning id into st;
  insert into customers(full_name,phone) values ('PPB Customer','+6590000350') returning id into cust;

  -- A package worth 500 and a bundle whose list price is 2000. Both are built
  -- here rather than borrowed from whatever the database holds, so the
  -- assertions below are about known numbers.
  insert into credit_packages(name, customer_price, paid_credit_amount, grants_reward,
                              reward_qualifying_amount, allow_voucher, allow_therapy, effective_from)
    values ('PPB Package', PKG_CREDIT, PKG_CREDIT, false, PKG_CREDIT, true, true, current_date)
    returning id into cp;
  insert into premium_bundles(name, customer_payment_amount, paid_credit_amount,
                              bonus_credit_amount, free_voucher_qty, effective_from)
    values ('PPB Bundle', BUNDLE_PAY, BUNDLE_PAY, 0, 0, current_date)
    returning id into pb;

  -- ── a promotion that contains both, sold for far less than their list ─────
  insert into promotions(name,code) values ('PPB Promo','PPB-1') returning id into promo;
  perform public.add_promotion_item(promo,'credit_package'::public.promotion_item_type,
    null,null,null,null,1,null,null,cp,null);
  -- The kind that could not be authored at all before 350.
  perform public.add_promotion_item(promo,'premium_bundle'::public.promotion_item_type,
    null,null,null,null,1,null,null,null,pb);

  if (select count(*) from promotion_items where promotion_id = promo) <> 2 then
    raise exception 'FIXTURE: the promotion did not take both package kinds';
  end if;

  -- ── sell it ───────────────────────────────────────────────────────────────
  insert into invoices(invoice_no,store_id,customer_id,created_by,status,
                       subtotal,discount_total,total_amount)
    values ('PPB-TEST-1',st,cust,own,'unpaid',PROMO_PRICE,0,PROMO_PRICE)
    returning id into inv;
  insert into invoice_items(invoice_id,line_kind,promotion_id,quantity,unit_price,line_total)
    values (inv,'promotion',promo,1,PROMO_PRICE,PROMO_PRICE)
    returning id into li;

  -- Before settlement nothing is owed yet.
  if exists (select 1 from credit_package_sales where invoice_id = inv) then
    raise exception 'FAIL: credit was issued before the invoice was settled'; end if;

  -- The real path: settling the invoice is what issues benefits.
  update invoices set status = 'paid' where id = inv;

  -- ── 1. both benefits were issued ──────────────────────────────────────────
  select count(*) into v_cp_sales from credit_package_sales where invoice_id = inv;
  select count(*) into v_pb_sales from premium_bundle_sales  where invoice_id = inv;
  if v_cp_sales <> 1 then
    raise exception 'FAIL: the credit package inside the promotion produced % sales, expected 1', v_cp_sales; end if;
  if v_pb_sales <> 1 then
    raise exception 'FAIL: the premium bundle inside the promotion produced % sales, expected 1', v_pb_sales; end if;

  -- ── 2. the AMOUNT comes from the package, the CASH from the promotion ─────
  -- Both packages grant what they DEFINE: 500 + 2000, on an invoice that took
  -- 300. If this ever equals the promotion's price, the rule has been inverted.
  select coalesce(sum(l.original_amount),0) into v_granted
    from customer_credit_lots l
   where l.customer_id = cust;
  if v_granted <> PKG_CREDIT + BUNDLE_PAY then
    raise exception 'FAIL: granted % of credit; the two packages define %',
      v_granted, PKG_CREDIT + BUNDLE_PAY; end if;

  -- And the derived sales record NO cash (351). The customer paid the
  -- PROMOTION; that line took the money and earns the commission at the
  -- promotion's own rate. Recording cash here as well commissioned the same
  -- money twice, and reconcile_invoice_commissions brought the duplicate back
  -- on every correction. Both earners return early on external_paid <= 0, so
  -- zero is what closes it through every path — and it is simply true.
  select coalesce(sum(external_paid),0) into v_paid from credit_package_sales where invoice_id = inv;
  if v_paid <> 0 then
    raise exception 'FAIL: the derived package sale recorded % of cash it never took', v_paid; end if;
  if (select coalesce(sum(external_paid),0) from premium_bundle_sales where invoice_id = inv) <> 0 then
    raise exception 'FAIL: the derived bundle sale recorded cash it never took'; end if;

  -- Which is what makes the commission single. Asserted at the mechanism, so
  -- this fails if anyone ever reintroduces an external figure here.
  if coalesce((public.earn_credit_package_commission(
        (select id from credit_package_sales where invoice_id = inv)))->>'skipped','false') <> 'true' then
    raise exception 'FAIL: the derived package sale earns its own commission on top of the promotion line'; end if;
  if coalesce((public.earn_premium_bundle_commission(
        (select id from premium_bundle_sales where invoice_id = inv)))->>'skipped','false') <> 'true' then
    raise exception 'FAIL: the derived bundle sale earns its own commission on top of the promotion line'; end if;

  -- ── 5. the evidence cancel_invoice_recorded insists on ────────────────────
  select count(*) into v_bv from invoice_benefit_values where invoice_item_id = li;
  if v_bv = 0 then
    raise exception 'FAIL: no invoice_benefit_values recorded; this invoice could never be cancelled'; end if;

  -- ── 3. issuing twice is impossible ────────────────────────────────────────
  select credit_issued_at into v_issued from invoice_items where id = li;
  if v_issued is null then
    raise exception 'FAIL: the promotion line was not stamped, so a re-settle would issue again'; end if;

  perform public.issue_credit_lines_for_invoice(inv);
  if (select count(*) from credit_package_sales where invoice_id = inv) <> 1
     or (select count(*) from premium_bundle_sales where invoice_id = inv) <> 1 then
    raise exception 'FAIL: running the issuer again issued the benefits a second time'; end if;

  -- ── 4. and a correction cannot resurrect them ─────────────────────────────
  -- This is the delete update_invoice_internal performs on every correction,
  -- verbatim, with a payload that carries the promotion line the way the till
  -- carries it. A derived child line would not be in this payload and would be
  -- destroyed and rebuilt with a fresh id and a null flag — which is precisely
  -- why 350 issues from the promotion line instead of creating one.
  delete from public.invoice_items ii
   where ii.invoice_id = inv
     and not exists (select 1 from jsonb_array_elements(
                       jsonb_build_array(jsonb_build_object('invoice_item_id', li))) x
                      where nullif(x->>'invoice_item_id','')::uuid = ii.id);

  select count(*) into v_n from invoice_items where id = li;
  if v_n <> 1 then
    raise exception 'FAIL: the correction destroyed the line that carries the issued flag'; end if;
  select credit_issued_at into v_issued from invoice_items where id = li;
  if v_issued is null then
    raise exception 'FAIL: the correction cleared the issued flag; the next settle would pay twice'; end if;

  perform public.issue_credit_lines_for_invoice(inv);
  if (select count(*) from credit_package_sales where invoice_id = inv) <> 1
     or (select count(*) from premium_bundle_sales where invoice_id = inv) <> 1 then
    raise exception 'FAIL: the benefits were issued again after a correction'; end if;

  -- ── and the authoring rules hold ──────────────────────────────────────────
  begin
    perform public.add_promotion_item(promo,'premium_bundle'::public.promotion_item_type,
      null,null,null,null,1,null,null,null,null);
    raise exception 'FAIL: a premium bundle item was saved without a bundle';
  exception when others then
    get stacked diagnostics v_msg = message_text;
    if v_msg like 'FAIL:%' then raise; end if;
    if v_msg !~ 'Select a premium bundle' then
      raise exception 'FAIL: refused for the wrong reason (%)', v_msg; end if;
  end;

  raise notice 'PASS: a package inside a promotion grants its benefit exactly once, and once only across a correction.';
end $$;
rollback;
