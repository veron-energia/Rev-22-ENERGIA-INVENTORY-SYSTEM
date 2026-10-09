-- 408: an exchange settles its money and its stock once.
--
--   * A Wallet method never pays an exchange, and nothing is taken when nothing
--     is due (SALES-EXTRAS-M1).
--   * A whole-bundle exchange is previewed, takes exactly its top-up, and is
--     refused when it cannot be done completely: choices, benefits, a line of
--     more than one bundle, an item already exchanged on its own, a bundle not
--     on sale here (SALES-EXTRAS-2, SALES-EXTRAS-4).
--   * An exchanged invoice, its exchanged lines and a replacement invoice
--     cannot be cancelled, refunded, deleted or have those lines changed; an
--     invoice with a refund cannot be exchanged, even when the refund commits
--     while the exchange waits for the invoice (SALES-EXTRAS-1).
--   * At commit, no product comes back on an invoice an exchange is part of
--     beyond what the invoice took out: an exchanged item never comes back
--     twice and a replacement's exchange line never comes back, while a
--     correction's restore-then-take of another line or the store goes
--     through, and another line of the same product still refunds.
--   * A whole bundle edited after its sale, or sold before the stock
--     snapshot, is not swapped whole.
--   * Paying a part-paid replacement invoice does not take the replacement out
--     of stock again (SALES-EXTRAS-M2).
--   * An invoice with an affiliate can be exchanged, and the exchange carries
--     that affiliate unless told otherwise (EXC-3).
-- Fixtures only (made-up names, +6591400xxx phones, @sig.invalid emails).
-- Disposable database only; everything is rolled back.
begin;

create function pg_temp.q(p_store uuid, p_product uuid) returns int language sql as
  $$ select coalesce((select current_qty from public.store_inventory where store_id = p_store and product_id = p_product), 0) $$;
-- What a commit does to the replacement invoice: create it now, then go back
-- to waiting for the commit, so set_exchange_details runs first, as live.
create function pg_temp.settle() returns void language plpgsql as $$
begin
  set constraints public.exchange_creates_invoice immediate;
  set constraints public.exchange_creates_invoice deferred;
end $$;
-- What a commit does to the stock check (408's deferred stock_return_exchange_hold):
-- run every pending check now, then go back to waiting for the commit.
create function pg_temp.commit_checks() returns void language plpgsql as $$
begin
  if exists (select 1 from pg_constraint where conrelid = 'public.stock_movements'::regclass
              and conname = 'stock_return_exchange_hold' and condeferrable) then
    set constraints public.stock_return_exchange_hold immediate;
    set constraints public.stock_return_exchange_hold deferred;
  end if;
end $$;

do $$
declare
  own uuid := gen_random_uuid(); cc uuid := gen_random_uuid(); outsider uuid := gen_random_uuid();
  st uuid; st2 uuid; cust uuid; refc uuid; aff uuid; pm uuid; wal uuid;
  pa uuid; pb uuid; pc uuid; pd uuid; pe uuid; pf uuid;
  pra uuid; prb uuid; prc uuid; prch uuid; prben uuid; prend uuid; prinact uuid; prnotsold uuid; g uuid;
  inv uuid; inv2 uuid; li uuid; li2 uuid; ex uuid; exinv uuid; res jsonb; q0 int; q1 int; n int; v text;
  pay uuid; sm uuid; staff jsonb; d text; inv3 uuid; li3 uuid;
begin
  insert into auth.users(id, email) values
    (own, 'xm-own@sig.invalid'), (cc, 'xm-c@sig.invalid'), (outsider, 'xm-x@sig.invalid');
  insert into profiles(id, full_name, email, role) values
    (own, 'XM Owner', 'xm-own@sig.invalid', 'owner'),
    (cc, 'XM Staff C', 'xm-c@sig.invalid', 'staff'),
    (outsider, 'XM Staff X', 'xm-x@sig.invalid', 'staff');
  perform set_config('request.jwt.claim.sub', own::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', own, 'role', 'authenticated')::text, true);
  insert into stores(name, code, country_code) values ('XM Store', 'XMS', 'SG') returning id into st;
  insert into stores(name, code, country_code) values ('XM Other', 'XMO', 'SG') returning id into st2;
  insert into user_store_assignments(user_id, store_id) values (cc, st), (outsider, st2);
  staff := jsonb_build_array(cc::text);
  insert into customers(full_name, phone) values ('XM Buyer', '+6591400101') returning id into cust;
  insert into customers(full_name, phone) values ('XM Referrer', '+6591400102') returning id into refc;
  insert into customer_affiliates(customer_id, status, activated_at, activated_by)
    values (refc, 'active', now(), own) returning id into aff;
  insert into payment_methods(name, is_active) values ('XM Cash', true) returning id into pm;
  insert into payment_methods(name, is_active, is_wallet_credit, wallet_category)
    values ('XM Wallet - Exchange Credit', true, true, 'paid') returning id into wal;
  insert into products(name, sku, product_type) values ('XM A', 'XMA', 'own') returning id into pa;
  insert into products(name, sku, product_type) values ('XM B', 'XMB', 'own') returning id into pb;
  insert into products(name, sku, product_type) values ('XM C', 'XMC', 'own') returning id into pc;
  insert into products(name, sku, product_type) values ('XM D', 'XMD', 'own') returning id into pd;
  insert into products(name, sku, product_type) values ('XM E', 'XME', 'own') returning id into pe;
  insert into products(name, sku, product_type) values ('XM F', 'XMF', 'own') returning id into pf;
  insert into store_inventory(store_id, product_id, current_qty)
    values (st, pa, 50), (st, pb, 50), (st, pc, 50), (st, pd, 50), (st, pe, 50), (st, pf, 50),
           (st2, pa, 10), (st2, pd, 10);
  perform set_product_prices(st, pa, 100, 100, 'available');
  perform set_product_prices(st, pb, 100, 100, 'available');
  perform set_product_prices(st, pc, 120, 120, 'available');
  perform set_product_prices(st, pd, 50, 50, 'available');
  perform set_product_prices(st, pe, 30, 30, 'available');
  perform set_product_prices(st, pf, 1000, 1000, 'available');
  -- bundles of products: A+B (regular 200), C (120), C x3 (360)
  insert into promotions(name, code, fixed_price) values ('XM Bundle AB', 'XMAB', 150) returning id into pra;
  insert into promotion_items(promotion_id, item_type, product_id, quantity) values (pra, 'product', pa, 1), (pra, 'product', pb, 1);
  insert into promotions(name, code, fixed_price) values ('XM Bundle C', 'XMC1', 110) returning id into prb;
  insert into promotion_items(promotion_id, item_type, product_id, quantity) values (prb, 'product', pc, 1);
  insert into promotions(name, code, fixed_price) values ('XM Bundle CCC', 'XMC3', 300) returning id into prc;
  insert into promotion_items(promotion_id, item_type, product_id, quantity) values (prc, 'product', pc, 3);
  -- a bundle with a choice, one with a benefit, and three not on sale here today
  insert into promotions(name, code, fixed_price) values ('XM Bundle Choice', 'XMCH', 140) returning id into prch;
  insert into promotion_items(promotion_id, item_type, product_id, quantity) values (prch, 'product', pa, 1);
  insert into promotion_choice_groups(promotion_id, label, item_kind, choose_qty) values (prch, 'Pick one', 'product', 1) returning id into g;
  insert into promotion_choice_options(group_id, product_id) values (g, pd), (g, pe);
  insert into promotions(name, code, fixed_price) values ('XM Bundle Treat', 'XMTR', 90) returning id into prben;
  insert into promotion_items(promotion_id, item_type, product_id, quantity) values (prben, 'product', pa, 1);
  insert into promotion_items(promotion_id, item_type, treatment_name, quantity) values (prben, 'treatment', 'XM foot soak', 1);
  insert into promotions(name, code, fixed_price, end_date) values ('XM Bundle Ended', 'XMEN', 100, sg_today() - 1) returning id into prend;
  insert into promotion_items(promotion_id, item_type, product_id, quantity) values (prend, 'product', pc, 1);
  insert into promotions(name, code, fixed_price, is_active) values ('XM Bundle Off', 'XMOF', 100, false) returning id into prinact;
  insert into promotion_items(promotion_id, item_type, product_id, quantity) values (prinact, 'product', pc, 1);
  insert into promotions(name, code, fixed_price) values ('XM Bundle Elsewhere', 'XMEL', 100) returning id into prnotsold;
  insert into promotion_items(promotion_id, item_type, product_id, quantity) values (prnotsold, 'product', pc, 1);
  perform set_promotion_prices(pra, st, 150, 150, true);
  perform set_promotion_prices(prb, st, 110, 110, true);
  perform set_promotion_prices(prc, st, 300, 300, true);
  perform set_promotion_prices(prch, st, 140, 140, true);
  perform set_promotion_prices(prben, st, 90, 90, true);
  perform set_promotion_prices(prend, st, 100, 100, true);
  perform set_promotion_prices(prinact, st, 100, 100, true);
  perform set_promotion_prices(prnotsold, st, 100, 100, false);

  -- ════ 1. A Wallet method never pays an exchange (SALES-EXTRAS-M1) ═══════════
  inv := create_invoice(st, cust, null, jsonb_build_array(jsonb_build_object('kind', 'product', 'product_id', pa, 'quantity', 1)), 0, null, null, null);
  perform record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pm, 'amount', 100)), gen_random_uuid());
  select id into li from invoice_items where invoice_id = inv;
  q0 := pg_temp.q(st, pc);
  begin
    perform create_exchange_with_details('product', jsonb_build_object(
      'original_invoice_id', inv, 'processing_store_id', st,
      'returned', jsonb_build_array(jsonb_build_object('invoice_item_id', li, 'quantity', 1)),
      'replacement', jsonb_build_array(jsonb_build_object('product_id', pc, 'quantity', 1)),
      'payments', jsonb_build_array(jsonb_build_object('payment_method_id', wal, 'amount', 20)),
      'reason', 'Upgrade', 'served_by', staff));
    raise exception 'FAIL 1: a Wallet method paid an exchange''s top-up';
  exception when others then
    if sqlerrm not like '%is wallet credit, which cannot pay an exchange%' then raise; end if;
  end;
  if pg_temp.q(st, pc) <> q0 or exists (select 1 from product_exchanges where original_invoice_id = inv) then
    raise exception 'FAIL 1: the refused wallet exchange left stock or a record behind'; end if;
  res := create_exchange_with_details('product', jsonb_build_object(
    'original_invoice_id', inv, 'processing_store_id', st,
    'returned', jsonb_build_array(jsonb_build_object('invoice_item_id', li, 'quantity', 1)),
    'replacement', jsonb_build_array(jsonb_build_object('product_id', pc, 'quantity', 1)),
    'payments', jsonb_build_array(jsonb_build_object('payment_method_id', pm, 'amount', 20)),
    'reason', 'Upgrade', 'served_by', staff));
  ex := (res->>'id')::uuid;
  perform pg_temp.settle();
  select id into exinv from invoices where exchange_id = ex and is_exchange;
  if (select status::text from invoices where id = exinv) <> 'paid'
     or (select coalesce(sum(amount), 0) from invoice_payments where invoice_id = exinv) <> 20 then
    raise exception 'FAIL 1: the cash top-up did not pay the replacement invoice'; end if;

  -- ════ 2. Nothing is taken when nothing is due ═══════════════════════════════
  inv2 := create_invoice(st, cust, null, jsonb_build_array(jsonb_build_object('kind', 'product', 'product_id', pa, 'quantity', 1)), 0, null, null, null);
  perform record_invoice_payment(inv2, jsonb_build_array(jsonb_build_object('payment_method_id', pm, 'amount', 100)), gen_random_uuid());
  select id into li2 from invoice_items where invoice_id = inv2;
  begin
    perform create_exchange_with_details('product', jsonb_build_object(
      'original_invoice_id', inv2, 'processing_store_id', st,
      'returned', jsonb_build_array(jsonb_build_object('invoice_item_id', li2, 'quantity', 1)),
      'replacement', jsonb_build_array(jsonb_build_object('product_id', pb, 'quantity', 1)),
      'payments', jsonb_build_array(jsonb_build_object('payment_method_id', pm, 'amount', 10)),
      'reason', 'Even swap', 'served_by', staff));
    raise exception 'FAIL 2: a payment was accepted on an even swap (it would be dropped unrecorded)';
  exception when others then
    if sqlerrm not like '%Nothing is due on this exchange%' then raise; end if;
  end;
  perform create_exchange_with_details('product', jsonb_build_object(
    'original_invoice_id', inv2, 'processing_store_id', st,
    'returned', jsonb_build_array(jsonb_build_object('invoice_item_id', li2, 'quantity', 1)),
    'replacement', jsonb_build_array(jsonb_build_object('product_id', pb, 'quantity', 1)),
    'reason', 'Even swap', 'served_by', staff));
  perform pg_temp.settle();

  -- ════ 3. A whole bundle is previewed and takes exactly its top-up ═══════════
  inv := create_invoice(st, cust, null, jsonb_build_array(jsonb_build_object('kind', 'promotion', 'promotion_id', pra, 'quantity', 1)), 0, null, null, null);
  perform record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pm, 'amount', 150)), gen_random_uuid());
  select id into li from invoice_items where invoice_id = inv and line_kind = 'promotion';
  res := exchange_bundle_preview(inv, st, li, prc);
  if res->>'problem' is not null or (res->>'credit')::numeric <> 200 or (res->>'replacement')::numeric <> 360
     or (res->>'topup')::numeric <> 160 or (res->>'nonrefundable')::numeric <> 0
     or jsonb_array_length(res->'returned') <> 2 or jsonb_array_length(res->'replacement_items') <> 1
     or (res->'replacement_items'->0->>'quantity')::int <> 3 then
    raise exception 'FAIL 3: the preview is not credit 200, replacement 360, top-up 160: %', res; end if;
  begin
    perform create_exchange_with_details('bundle', jsonb_build_object(
      'original_invoice_id', inv, 'processing_store_id', st, 'original_invoice_item_id', li, 'new_promotion_id', prc,
      'payments', jsonb_build_array(jsonb_build_object('payment_method_id', pm, 'amount', 10)),
      'reason', 'Bigger bundle', 'served_by', staff));
    raise exception 'FAIL 3: a short payment on a dearer bundle was accepted';
  exception when others then
    if sqlerrm not like '%needs exactly S$160.00 paid now: S$10.00 was entered%' then raise; end if;
  end;
  begin
    perform create_exchange_with_details('bundle', jsonb_build_object(
      'original_invoice_id', inv, 'processing_store_id', st, 'original_invoice_item_id', li, 'new_promotion_id', prc,
      'reason', 'Bigger bundle', 'served_by', staff));
    raise exception 'FAIL 3: a dearer bundle was swapped with nothing paid';
  exception when others then
    if sqlerrm not like '%needs exactly S$160.00 paid now: S$0.00 was entered%' then raise; end if;
  end;
  q0 := pg_temp.q(st, pc); q1 := pg_temp.q(st, pa);
  res := create_exchange_with_details('bundle', jsonb_build_object(
    'original_invoice_id', inv, 'processing_store_id', st, 'original_invoice_item_id', li, 'new_promotion_id', prc,
    'payments', jsonb_build_array(jsonb_build_object('payment_method_id', pm, 'amount', 160)),
    'reason', 'Bigger bundle', 'served_by', staff));
  ex := (res->>'id')::uuid;
  perform pg_temp.settle();
  select id into exinv from invoices where exchange_id = ex and is_exchange;
  if (select topup_amount from product_exchanges where id = ex) <> 160
     or (select coalesce(sum(amount), 0) from product_exchange_payments where exchange_id = ex) <> 160
     or (select status::text from invoices where id = exinv) <> 'paid'
     or pg_temp.q(st, pc) <> q0 - 3 or pg_temp.q(st, pa) <> q1 + 1 then
    raise exception 'FAIL 3: the exact top-up swap did not record 160 paid, C -3 and A +1'; end if;

  -- ════ 4. A cheaper bundle: no payment, the rest is unused value ═════════════
  inv := create_invoice(st, cust, null, jsonb_build_array(jsonb_build_object('kind', 'promotion', 'promotion_id', pra, 'quantity', 1)), 0, null, null, null);
  perform record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pm, 'amount', 150)), gen_random_uuid());
  select id into li from invoice_items where invoice_id = inv and line_kind = 'promotion';
  if (exchange_bundle_preview(inv, st, li, prb)->>'nonrefundable')::numeric <> 80 then
    raise exception 'FAIL 4: the preview does not show the 80 of unused value'; end if;
  begin
    perform create_exchange_with_details('bundle', jsonb_build_object(
      'original_invoice_id', inv, 'processing_store_id', st, 'original_invoice_item_id', li, 'new_promotion_id', prb,
      'payments', jsonb_build_array(jsonb_build_object('payment_method_id', pm, 'amount', 50)),
      'reason', 'Smaller bundle', 'served_by', staff));
    raise exception 'FAIL 4: S$50 was taken on a cheaper bundle (it was dropped unrecorded)';
  exception when others then
    if sqlerrm not like '%Nothing is due on this exchange, so no payment can be taken (S$50.00%' then raise; end if;
  end;
  res := create_exchange_with_details('bundle', jsonb_build_object(
    'original_invoice_id', inv, 'processing_store_id', st, 'original_invoice_item_id', li, 'new_promotion_id', prb,
    'reason', 'Smaller bundle', 'served_by', staff));
  perform pg_temp.settle();
  if (select nonrefundable_amount from product_exchanges where id = (res->>'id')::uuid) <> 80 then
    raise exception 'FAIL 4: the unused value was not recorded'; end if;

  -- ════ 5. Swaps that cannot be done completely are refused, before and at Confirm
  inv := create_invoice(st, cust, null, jsonb_build_array(jsonb_build_object('kind', 'promotion', 'promotion_id', pra, 'quantity', 1)), 0, null, null, null);
  perform record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pm, 'amount', 150)), gen_random_uuid());
  select id into li from invoice_items where invoice_id = inv and line_kind = 'promotion';
  for res in select x from jsonb_array_elements(jsonb_build_array(
      jsonb_build_object('to', prch, 'says', '%has items chosen at the till%'),
      jsonb_build_object('to', prben, 'says', '%includes vouchers, therapy or other benefits%'),
      jsonb_build_object('to', prend, 'says', '%has ended%'),
      jsonb_build_object('to', prinact, 'says', '%is not active%'),
      jsonb_build_object('to', prnotsold, 'says', '%is not sold at this store%'))) x
  loop
    v := exchange_bundle_preview(inv, st, li, (res->>'to')::uuid)->>'problem';
    if v is null or v not like res->>'says' then
      raise exception 'FAIL 5: the preview of a swap into % said %', res->>'to', v; end if;
    begin
      perform create_exchange_with_details('bundle', jsonb_build_object(
        'original_invoice_id', inv, 'processing_store_id', st, 'original_invoice_item_id', li,
        'new_promotion_id', (res->>'to')::uuid, 'reason', 'Swap', 'served_by', staff));
      raise exception 'FAIL 5: a swap the preview refused was done: %', v;
    exception when others then
      if sqlerrm <> v then raise; end if;
    end;
  end loop;
  -- out of a bundle with a choice made at the till
  inv2 := create_invoice(st, cust, null, jsonb_build_array(jsonb_build_object('kind', 'promotion', 'promotion_id', prch, 'quantity', 1,
            'selections', jsonb_build_array(jsonb_build_object('group_id', g, 'options',
              jsonb_build_array(jsonb_build_object('product_id', pd, 'quantity', 1)))))), 0, null, null, null);
  perform record_invoice_payment(inv2, jsonb_build_array(jsonb_build_object('payment_method_id', pm,
    'amount', (select total_amount from invoices where id = inv2))), gen_random_uuid());
  select id into li2 from invoice_items where invoice_id = inv2 and line_kind = 'promotion';
  v := exchange_bundle_preview(inv2, st, li2, prb)->>'problem';
  if v is null or v not like '%chosen at the till%' then
    raise exception 'FAIL 5: a bundle with a choice made at the till could be swapped whole: %', v; end if;
  -- the choice the line recorded still counts once the bundle has no choice
  -- group of its own (here the group is moved to another bundle)
  update promotion_choice_groups set promotion_id = prinact where id = g;
  v := exchange_bundle_preview(inv2, st, li2, prb)->>'problem';
  if v is null or v not like 'Items of this bundle were chosen at the till%' then
    raise exception 'FAIL 5: a line with a recorded choice could be swapped whole once its bundle lost the choice: %', v; end if;
  -- a line of two bundles
  inv2 := create_invoice(st, cust, null, jsonb_build_array(jsonb_build_object('kind', 'promotion', 'promotion_id', pra, 'quantity', 2)), 0, null, null, null);
  perform record_invoice_payment(inv2, jsonb_build_array(jsonb_build_object('payment_method_id', pm, 'amount', 300)), gen_random_uuid());
  select id into li2 from invoice_items where invoice_id = inv2 and line_kind = 'promotion';
  q0 := pg_temp.q(st, pa);
  begin
    perform create_exchange_with_details('bundle', jsonb_build_object(
      'original_invoice_id', inv2, 'processing_store_id', st, 'original_invoice_item_id', li2, 'new_promotion_id', prb,
      'reason', 'Swap', 'served_by', staff));
    raise exception 'FAIL 5: a line of two bundles was swapped as one';
  exception when others then
    if sqlerrm not like '%This line holds 2 bundles%' then raise; end if;
  end;
  if pg_temp.q(st, pa) <> q0 then raise exception 'FAIL 5: the refused swap moved stock'; end if;

  -- ════ 6. An item exchanged on its own, then the whole bundle (SALES-EXTRAS-4)
  q0 := pg_temp.q(st, pa);
  res := create_exchange_with_details('bundle_component', jsonb_build_object(
    'original_invoice_id', inv, 'processing_store_id', st, 'original_invoice_item_id', li,
    'component_product_id', pa, 'component_qty', 1,
    'replacement', jsonb_build_array(jsonb_build_object('product_id', pc, 'quantity', 1)),
    'payments', jsonb_build_array(jsonb_build_object('payment_method_id', pm, 'amount', 20)),
    'reason', 'Swap A', 'served_by', staff));
  perform pg_temp.settle();
  v := exchange_bundle_preview(inv, st, li, prb)->>'problem';
  if v is null or v not like '%already exchanged on its own (EXC-%' then
    raise exception 'FAIL 6: the preview allows a whole swap after a component swap: %', v; end if;
  begin
    perform create_exchange_with_details('bundle', jsonb_build_object(
      'original_invoice_id', inv, 'processing_store_id', st, 'original_invoice_item_id', li, 'new_promotion_id', prb,
      'reason', 'Swap all', 'served_by', staff));
    raise exception 'FAIL 6: the whole bundle was swapped after one of its items had been';
  exception when others then
    if sqlerrm not like '%already exchanged on its own%' then raise; end if;
  end;
  if pg_temp.q(st, pa) <> q0 + 1 then
    raise exception 'FAIL 6: the component went back on the shelf % times, not once', pg_temp.q(st, pa) - q0; end if;

  -- ════ 6b. A bundle edited after its sale is not swapped whole ═══════════════
  inv2 := create_invoice(st, cust, null, jsonb_build_array(jsonb_build_object('kind', 'promotion', 'promotion_id', pra, 'quantity', 1)), 0, null, null, null);
  perform record_invoice_payment(inv2, jsonb_build_array(jsonb_build_object('payment_method_id', pm, 'amount', 150)), gen_random_uuid());
  select id into li2 from invoice_items where invoice_id = inv2 and line_kind = 'promotion';
  update promotion_items set product_id = pe where promotion_id = pra and product_id = pb;   -- A+B is now A+E
  q0 := pg_temp.q(st, pb); q1 := pg_temp.q(st, pe);
  v := exchange_bundle_preview(inv2, st, li2, prb)->>'problem';
  if v is null or v not like 'Bundle "XM Bundle AB" was changed after this sale%' then
    raise exception 'FAIL 6b: a bundle edited after its sale could be swapped whole: %', v; end if;
  begin
    perform create_exchange_with_details('bundle', jsonb_build_object(
      'original_invoice_id', inv2, 'processing_store_id', st, 'original_invoice_item_id', li2, 'new_promotion_id', prb,
      'reason', 'Swap', 'served_by', staff));
    raise exception 'FAIL 6b: a bundle edited after its sale was swapped whole';
  exception when others then
    if sqlerrm <> v then raise; end if;
  end;
  if pg_temp.q(st, pb) <> q0 or pg_temp.q(st, pe) <> q1 then raise exception 'FAIL 6b: the refused swap moved stock'; end if;
  update promotion_items set product_id = pb where promotion_id = pra and product_id = pe;   -- as sold again
  if exchange_bundle_preview(inv2, st, li2, prb)->>'problem' is not null then
    raise exception 'FAIL 6b: the bundle as sold is refused: %', exchange_bundle_preview(inv2, st, li2, prb)->>'problem'; end if;
  -- a sale from before the stock snapshot cannot be checked
  update invoices set stock_snapshot_version = null where id = inv2;
  v := exchange_bundle_preview(inv2, st, li2, prb)->>'problem';
  if v is null or v not like 'This sale of bundle "XM Bundle AB" was recorded before%' then
    raise exception 'FAIL 6b: a bundle sold before the stock snapshot could be swapped whole: %', v; end if;

  -- ════ 7. Who may preview ════════════════════════════════════════════════════
  perform set_config('request.jwt.claim.sub', outsider::text, true);
  begin
    perform exchange_bundle_preview(inv, st, li, prb);
    raise exception 'FAIL 7: staff of another store previewed this store''s exchange';
  exception when others then
    if sqlerrm not like '%do not have access to the processing store%' then raise; end if;
  end;
  -- ... nor this store's invoice, by naming their own store as the processing one
  begin
    perform exchange_bundle_preview(inv, st2, li, prb);
    raise exception 'FAIL 7: staff of another store read this store''s invoice line through the preview';
  exception when others then
    if sqlerrm not like 'Invoice not accessible%' then raise; end if;
  end;
  perform set_config('request.jwt.claim.sub', gen_random_uuid()::text, true);
  begin
    perform exchange_bundle_preview(inv, st, li, prb);
    raise exception 'FAIL 7: a login without a profile previewed an exchange';
  exception when others then
    -- 406's check: not active staff, refused as such (42501)
    if sqlstate <> '42501' or sqlerrm not like 'Only active Energia staff%' then raise; end if;
  end;
  perform set_config('request.jwt.claim.sub', own::text, true);

  -- ════ 8. An exchanged invoice and its replacement are not cancelled (SALES-EXTRAS-1)
  inv := create_invoice(st, cust, null, jsonb_build_array(jsonb_build_object('kind', 'product', 'product_id', pa, 'quantity', 1)), 0, null, null, null);
  perform record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pm, 'amount', 100)), gen_random_uuid());
  select id into li from invoice_items where invoice_id = inv;
  res := create_exchange_with_details('product', jsonb_build_object(
    'original_invoice_id', inv, 'processing_store_id', st,
    'returned', jsonb_build_array(jsonb_build_object('invoice_item_id', li, 'quantity', 1)),
    'replacement', jsonb_build_array(jsonb_build_object('product_id', pb, 'quantity', 1)),
    'reason', 'Colour', 'served_by', staff));
  ex := (res->>'id')::uuid;
  perform pg_temp.settle();
  select id into exinv from invoices where exchange_id = ex and is_exchange;
  q0 := pg_temp.q(st, pa); q1 := pg_temp.q(st, pb);
  begin
    perform cancel_invoice_recorded(inv, 'Customer changed mind', gen_random_uuid());
    raise exception 'FAIL 8: an exchanged invoice was cancelled';
  exception when others then
    -- whichever hold meets it first: the stock coming back, or the status
    if sqlerrm not like '%EX-%refused. Ask the Owner how to undo the exchange.' then raise; end if;
  end;
  if pg_temp.q(st, pa) <> q0 or (select status::text from invoices where id = inv) <> 'paid' then
    raise exception 'FAIL 8: the refused cancellation put the returned item back again'; end if;
  begin
    perform restore_invoice_stock(inv, 'direct');
    perform pg_temp.commit_checks();
    raise exception 'FAIL 8: the exchanged item was restocked a second time';
  exception when others then
    if sqlerrm not like '%already put back on the shelf by exchange EX-%' then raise; end if;
  end;
  begin
    insert into stock_movements(product_id, movement_type, to_store_id, invoice_id, quantity, notes)
      values (pb, 'invoice_refund_return', st, exinv, 1, 'direct');
    perform pg_temp.commit_checks();
    raise exception 'FAIL 8: a replacement invoice''s exchange line came back on the shelf';
  exception when others then
    if sqlerrm not like '%came from exchange EX-%which took it out of stock itself%' then raise; end if;
  end;
  begin
    update invoices set status = 'cancellation_requested' where id = inv;
    raise exception 'FAIL 8: a cancellation of an exchanged invoice was requested';
  exception when others then
    if sqlerrm not like 'Items on % were exchanged (EX-%' then raise; end if;
  end;
  begin
    perform cancel_invoice_recorded(exinv, 'Undo', gen_random_uuid());
    raise exception 'FAIL 8: a replacement invoice was cancelled';
  exception when others then
    if sqlerrm not like '%is the replacement invoice of exchange EX-%' then raise; end if;
  end;
  begin
    update invoices set deleted_at = now() where id = exinv;
    raise exception 'FAIL 8: a replacement invoice was deleted';
  exception when others then
    if sqlerrm not like '%is the replacement invoice of exchange EX-%' then raise; end if;
  end;
  if pg_temp.q(st, pb) <> q1 then raise exception 'FAIL 8: the refusals moved the replacement''s stock'; end if;
  perform pg_temp.commit_checks();   -- nothing that stayed is refused at commit

  -- ════ 8b. A correction of another line, or of the store, still goes through ═
  -- correct_invoice changes stock by restore_invoice_stock, the line rewrite
  -- and the store, then deduct_invoice_stock, all in one transaction.
  inv2 := create_invoice(st, cust, null, jsonb_build_array(
            jsonb_build_object('kind', 'product', 'product_id', pa, 'quantity', 1),
            jsonb_build_object('kind', 'product', 'product_id', pd, 'quantity', 1)), 0, null, null, null);
  perform record_invoice_payment(inv2, jsonb_build_array(jsonb_build_object('payment_method_id', pm, 'amount', 150)), gen_random_uuid());
  perform create_exchange_with_details('product', jsonb_build_object(
    'original_invoice_id', inv2, 'processing_store_id', st,
    'returned', jsonb_build_array(jsonb_build_object('invoice_item_id',
                  (select id from invoice_items where invoice_id = inv2 and product_id = pa), 'quantity', 1)),
    'replacement', jsonb_build_array(jsonb_build_object('product_id', pb, 'quantity', 1)),
    'reason', 'Colour', 'served_by', staff));
  perform pg_temp.settle();
  q0 := pg_temp.q(st, pa); q1 := pg_temp.q(st, pd);
  perform restore_invoice_stock(inv2, 'Invoice correction: D');
  perform deduct_invoice_stock(inv2, 'Invoice correction: D');
  perform pg_temp.commit_checks();
  if pg_temp.q(st, pa) <> q0 or pg_temp.q(st, pd) <> q1 then
    raise exception 'FAIL 8b: a correction''s restore and take moved stock (A % -> %, D % -> %)', q0, pg_temp.q(st, pa), q1, pg_temp.q(st, pd); end if;
  -- moving the invoice to another store: back at this one, out at the other
  perform restore_invoice_stock(inv2, 'Invoice correction: store');
  update invoices set store_id = st2 where id = inv2;
  perform deduct_invoice_stock(inv2, 'Invoice correction: store');
  perform pg_temp.commit_checks();
  if pg_temp.q(st, pa) <> q0 + 1 or pg_temp.q(st2, pa) <> 9 or pg_temp.q(st, pd) <> q1 + 1 or pg_temp.q(st2, pd) <> 9 then
    raise exception 'FAIL 8b: moving the store did not put A and D back here and take them there'; end if;
  -- and a restore that is not taken again is still refused
  begin
    perform restore_invoice_stock(inv2, 'direct');
    perform pg_temp.commit_checks();
    raise exception 'FAIL 8b: after the store move, the exchanged item was restocked a second time';
  exception when others then
    if sqlerrm not like 'XM A on % was already put back on the shelf by exchange EX-%' then raise; end if;
  end;

  -- ════ 9. Corrections cannot drop or change an exchanged line ════════════════
  begin
    update invoice_items set quantity = 2 where id = li;
    raise exception 'FAIL 9: an exchanged line''s quantity was changed';
  exception when others then
    if sqlerrm not like 'Items on % were exchanged%' then raise; end if;
  end;
  begin
    update invoice_items set product_id = pc where id = li;
    raise exception 'FAIL 9: an exchanged line''s product was changed';
  exception when others then
    if sqlerrm not like 'Items on % were exchanged%' then raise; end if;
  end;
  update invoice_items set quantity = quantity, product_id = product_id where id = li;   -- the same values: not a change
  begin
    update invoice_items set price_source = 'store' where invoice_id = exinv;
    raise exception 'FAIL 9: a replacement line''s price source was changed (the stock engine would owe it)';
  exception when others then
    if sqlerrm not like '%is the replacement invoice of exchange%' then raise; end if;
  end;
  begin
    update invoice_items set quantity = 3 where invoice_id = exinv;
    raise exception 'FAIL 9: a replacement line''s quantity was changed';
  exception when others then
    if sqlerrm not like '%is the replacement invoice of exchange%' then raise; end if;
  end;
  begin
    delete from invoice_items where invoice_id = exinv;
    raise exception 'FAIL 9: a replacement invoice''s exchange line was deleted';
  exception when others then
    if sqlerrm not like '%is the replacement invoice of exchange%' then raise; end if;
  end;
  begin
    delete from invoice_items where id = li;   -- (product_exchange_items' foreign key refuses this too)
    raise exception 'FAIL 9: an exchanged line was deleted';
  exception when others then
    if sqlerrm not like 'Items on % were exchanged%' then raise; end if;
  end;

  -- ════ 10. Refunds: never an exchanged line; the other lines still can ══════
  inv := create_invoice(st, cust, null, jsonb_build_array(
           jsonb_build_object('kind', 'product', 'product_id', pa, 'quantity', 1),
           jsonb_build_object('kind', 'product', 'product_id', pd, 'quantity', 1)), 0, null, null, null);
  perform record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pm, 'amount', 150)), gen_random_uuid());
  select id into li from invoice_items where invoice_id = inv and product_id = pa;
  select id into li2 from invoice_items where invoice_id = inv and product_id = pd;
  select id into pay from invoice_payments where invoice_id = inv;
  perform create_exchange_with_details('product', jsonb_build_object(
    'original_invoice_id', inv, 'processing_store_id', st,
    'returned', jsonb_build_array(jsonb_build_object('invoice_item_id', li, 'quantity', 1)),
    'replacement', jsonb_build_array(jsonb_build_object('product_id', pb, 'quantity', 1)),
    'reason', 'Colour', 'served_by', staff));
  perform pg_temp.settle();
  select id into sm from stock_movements where invoice_id = inv and product_id = pa and movement_type::text = 'store_sale';
  q0 := pg_temp.q(st, pa);
  -- Money back for the exchanged item, saying it was not returned (no stock
  -- moves, so only the refund's own trigger can stop it) ...
  begin
    perform refund_invoice_recorded(inv,
      jsonb_build_array(jsonb_build_object('invoice_item_id', li, 'amount', 100)),
      jsonb_build_array(jsonb_build_object('payment_id', pay, 'amount', 100)),
      jsonb_build_array(jsonb_build_object('movement_id', sm, 'not_returned_quantity', 1)),
      'Refund the exchanged item', gen_random_uuid());
    raise exception 'FAIL 10: an exchanged line was refunded';
  exception when others then
    if sqlerrm not like 'Items on % were exchanged (EX-%' then raise; end if;
  end;
  -- ... or as returned and sellable.
  begin
    perform refund_invoice_recorded(inv,
      jsonb_build_array(jsonb_build_object('invoice_item_id', li, 'amount', 100)),
      jsonb_build_array(jsonb_build_object('payment_id', pay, 'amount', 100)),
      jsonb_build_array(jsonb_build_object('movement_id', sm, 'sellable_quantity', 1)),
      'Refund the exchanged item', gen_random_uuid());
    raise exception 'FAIL 10: an exchanged line was refunded and restocked';
  exception when others then
    if sqlerrm not like 'Items on % were exchanged (EX-%' then raise; end if;
  end;
  if pg_temp.q(st, pa) <> q0 or exists (select 1 from invoice_refunds where invoice_id = inv) then
    raise exception 'FAIL 10: the refused refund left money or stock behind'; end if;
  select id into sm from stock_movements where invoice_id = inv and product_id = pd and movement_type::text = 'store_sale';
  q0 := pg_temp.q(st, pd);
  perform refund_invoice_recorded(inv,
    jsonb_build_array(jsonb_build_object('invoice_item_id', li2, 'amount', 50)),
    jsonb_build_array(jsonb_build_object('payment_id', pay, 'amount', 50)),
    jsonb_build_array(jsonb_build_object('movement_id', sm, 'sellable_quantity', 1)),
    'Refund the other item', gen_random_uuid());
  perform pg_temp.commit_checks();
  if pg_temp.q(st, pd) <> q0 + 1 or (select coalesce(sum(amount), 0) from invoice_refunds where invoice_id = inv) <> 50 then
    raise exception 'FAIL 10: the line that was not exchanged could not be refunded'; end if;
  -- two lines of A, one exchanged: the other is refunded and goes back on the
  -- shelf (2 sold = 1 by the exchange + 1 by the refund)
  inv3 := create_invoice(st, cust, null, jsonb_build_array(
            jsonb_build_object('kind', 'product', 'product_id', pa, 'quantity', 1),
            jsonb_build_object('kind', 'product', 'product_id', pa, 'quantity', 1)), 0, null, null, null);
  perform record_invoice_payment(inv3, jsonb_build_array(jsonb_build_object('payment_method_id', pm, 'amount', 200)), gen_random_uuid());
  select id into li3 from invoice_items where invoice_id = inv3 order by id limit 1;
  perform create_exchange_with_details('product', jsonb_build_object(
    'original_invoice_id', inv3, 'processing_store_id', st,
    'returned', jsonb_build_array(jsonb_build_object('invoice_item_id', li3, 'quantity', 1)),
    'replacement', jsonb_build_array(jsonb_build_object('product_id', pb, 'quantity', 1)),
    'reason', 'Colour', 'served_by', staff));
  perform pg_temp.settle();
  q0 := pg_temp.q(st, pa);
  if (select coalesce(sum(quantity), 0) from stock_movements where invoice_id = inv3 and product_id = pa and movement_type::text = 'store_sale') <> 2 then
    raise exception 'FAIL 10: fixture: two A were not taken out for the invoice'; end if;
  perform refund_invoice_recorded(inv3,
    jsonb_build_array(jsonb_build_object('invoice_item_id', (select id from invoice_items where invoice_id = inv3 and id <> li3), 'amount', 100)),
    jsonb_build_array(jsonb_build_object('payment_id', (select id from invoice_payments where invoice_id = inv3), 'amount', 100)),
    jsonb_build_array(jsonb_build_object('movement_id',
      (select id from stock_movements where invoice_id = inv3 and product_id = pa and movement_type::text = 'store_sale' limit 1),
      'sellable_quantity', 1)),
    'Refund the other A', gen_random_uuid());
  perform pg_temp.commit_checks();
  if pg_temp.q(st, pa) <> q0 + 1 then
    raise exception 'FAIL 10: the other line of the exchanged product was not refunded back onto the shelf'; end if;

  -- ════ 11. An invoice with a refund is not exchanged ═════════════════════════
  inv := create_invoice(st, cust, null, jsonb_build_array(
           jsonb_build_object('kind', 'product', 'product_id', pa, 'quantity', 1),
           jsonb_build_object('kind', 'product', 'product_id', pd, 'quantity', 1)), 0, null, null, null);
  perform record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pm, 'amount', 150)), gen_random_uuid());
  select id into li from invoice_items where invoice_id = inv and product_id = pa;
  select id into li2 from invoice_items where invoice_id = inv and product_id = pd;
  select id into pay from invoice_payments where invoice_id = inv;
  select id into sm from stock_movements where invoice_id = inv and product_id = pd and movement_type::text = 'store_sale';
  perform refund_invoice_recorded(inv,
    jsonb_build_array(jsonb_build_object('invoice_item_id', li2, 'amount', 50)),
    jsonb_build_array(jsonb_build_object('payment_id', pay, 'amount', 50)),
    jsonb_build_array(jsonb_build_object('movement_id', sm, 'sellable_quantity', 1)),
    'Refund D', gen_random_uuid());
  if exchange_ineligibility_reason(inv) not like 'A refund has already been recorded on this invoice%' then
    raise exception 'FAIL 11: an invoice with a refund is still offered for exchange'; end if;
  begin
    perform create_exchange_with_details('product', jsonb_build_object(
      'original_invoice_id', inv, 'processing_store_id', st,
      'returned', jsonb_build_array(jsonb_build_object('invoice_item_id', li, 'quantity', 1)),
      'replacement', jsonb_build_array(jsonb_build_object('product_id', pb, 'quantity', 1)),
      'reason', 'After refund', 'served_by', staff));
    raise exception 'FAIL 11: an invoice with a refund was exchanged';
  exception when others then
    if sqlerrm not like 'A refund has already been recorded on this invoice%' then raise; end if;
  end;

  -- ════ 11b. ... even when the refund commits while the exchange waits ═══════
  -- The first check (before the invoice is locked) cannot see a refund that
  -- holds the lock at that moment. Its answer then is simulated: the next
  -- eligibility check answers '' once. The check made after the lock sees it.
  d := pg_get_functiondef('public.exchange_ineligibility_reason(uuid)'::regprocedure);
  if (length(d) - length(replace(d, E'\nbegin\n', ''))) / length(E'\nbegin\n') <> 1 then
    raise exception 'FAIL 11b: fixture: exchange_ineligibility_reason has no single begin'; end if;
  execute replace(d, E'\nbegin\n', E'\nbegin\n  if current_setting(''xm.stale_check'', true) = ''on'' then\n'
    || E'    perform set_config(''xm.stale_check'', ''off'', true); return ''''; end if;\n');
  perform set_config('xm.stale_check', 'on', true);
  begin
    perform create_exchange_with_details('product', jsonb_build_object(
      'original_invoice_id', inv, 'processing_store_id', st,
      'returned', jsonb_build_array(jsonb_build_object('invoice_item_id', li, 'quantity', 1)),
      'replacement', jsonb_build_array(jsonb_build_object('product_id', pb, 'quantity', 1)),
      'reason', 'Waited for the lock', 'served_by', staff));
    raise exception 'FAIL 11b: a product exchange went ahead after a refund committed while it waited for the invoice';
  exception when others then
    if sqlerrm not like 'A refund has already been recorded on this invoice%' then raise; end if;
  end;
  -- the same for one item of a bundle
  inv2 := create_invoice(st, cust, null, jsonb_build_array(
            jsonb_build_object('kind', 'promotion', 'promotion_id', pra, 'quantity', 1),
            jsonb_build_object('kind', 'product', 'product_id', pd, 'quantity', 1)), 0, null, null, null);
  perform record_invoice_payment(inv2, jsonb_build_array(jsonb_build_object('payment_method_id', pm, 'amount', 200)), gen_random_uuid());
  perform refund_invoice_recorded(inv2,
    jsonb_build_array(jsonb_build_object('invoice_item_id', (select id from invoice_items where invoice_id = inv2 and product_id = pd), 'amount', 50)),
    jsonb_build_array(jsonb_build_object('payment_id', (select id from invoice_payments where invoice_id = inv2), 'amount', 50)),
    jsonb_build_array(jsonb_build_object('movement_id',
      (select id from stock_movements where invoice_id = inv2 and product_id = pd and movement_type::text = 'store_sale'),
      'sellable_quantity', 1)),
    'Refund D', gen_random_uuid());
  perform set_config('xm.stale_check', 'on', true);
  begin
    perform create_exchange_with_details('bundle_component', jsonb_build_object(
      'original_invoice_id', inv2, 'processing_store_id', st,
      'original_invoice_item_id', (select id from invoice_items where invoice_id = inv2 and line_kind = 'promotion'),
      'component_product_id', pa, 'component_qty', 1,
      'replacement', jsonb_build_array(jsonb_build_object('product_id', pb, 'quantity', 1)),
      'reason', 'Waited for the lock', 'served_by', staff));
    raise exception 'FAIL 11b: a component exchange went ahead after a refund committed while it waited for the invoice';
  exception when others then
    if sqlerrm not like 'A refund has already been recorded on this invoice%' then raise; end if;
  end;
  -- and the whole bundle (its quote, made after the locks, checks again)
  perform set_config('xm.stale_check', 'on', true);
  begin
    perform create_exchange_with_details('bundle', jsonb_build_object(
      'original_invoice_id', inv2, 'processing_store_id', st,
      'original_invoice_item_id', (select id from invoice_items where invoice_id = inv2 and line_kind = 'promotion'),
      'new_promotion_id', prb, 'reason', 'Waited for the lock', 'served_by', staff));
    raise exception 'FAIL 11b: a whole-bundle exchange went ahead after a refund committed while it waited for the invoice';
  exception when others then
    if sqlerrm not like 'A refund has already been recorded on this invoice%' then raise; end if;
  end;
  perform set_config('xm.stale_check', 'off', true);
  execute d;

  -- ════ 12. Paying a part-paid replacement does not take it out again (SALES-EXTRAS-M2)
  inv := create_invoice(st, cust, null, jsonb_build_array(jsonb_build_object('kind', 'product', 'product_id', pa, 'quantity', 1)), 0, null, null, null);
  perform record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pm, 'amount', 100)), gen_random_uuid());
  select id into li from invoice_items where invoice_id = inv;
  q0 := pg_temp.q(st, pf);
  res := create_exchange_with_details('product', jsonb_build_object(
    'original_invoice_id', inv, 'processing_store_id', st,
    'returned', jsonb_build_array(jsonb_build_object('invoice_item_id', li, 'quantity', 1)),
    'replacement', jsonb_build_array(jsonb_build_object('product_id', pf, 'quantity', 1)),
    'payments', jsonb_build_array(jsonb_build_object('payment_method_id', pm, 'amount', 100)),
    'reason', 'Upgrade, rest later', 'served_by', staff));
  ex := (res->>'id')::uuid;
  perform pg_temp.settle();
  select id into exinv from invoices where exchange_id = ex and is_exchange;
  if pg_temp.q(st, pf) <> q0 - 1 or (select status::text from invoices where id = exinv) <> 'partially_paid' then
    raise exception 'FAIL 12: fixture: the part-paid exchange did not take F out once'; end if;
  if exists (select 1 from invoice_stock_to_deduct(exinv) t where t.quantity > 0) then
    raise exception 'FAIL 12: the stock engine still owes the replacement: %',
      (select jsonb_agg(t) from invoice_stock_to_deduct(exinv) t); end if;
  perform record_invoice_payment(exinv, jsonb_build_array(jsonb_build_object('payment_method_id', pm, 'amount', 800)), gen_random_uuid());
  if (select status::text from invoices where id = exinv) <> 'paid' then
    raise exception 'FAIL 12: the balance did not settle the replacement invoice'; end if;
  if pg_temp.q(st, pf) <> q0 - 1 then
    raise exception 'FAIL 12: paying the balance took the replacement out again (F % instead of %)', pg_temp.q(st, pf), q0 - 1; end if;
  if exists (select 1 from stock_movements where invoice_id = exinv) then
    raise exception 'FAIL 12: a sale movement was written for the replacement invoice'; end if;
  -- a line added to the replacement invoice with no price source is owed
  -- (as rental, special and credit lines are written)
  insert into invoice_items(invoice_id, line_kind, product_id, quantity, unit_price, line_total, price_source)
    values (exinv, 'product', pd, 1, 50, 50, null);
  if (select jsonb_agg(t order by t.item_id) from invoice_required_stock(exinv) t)
     is distinct from jsonb_build_array(jsonb_build_object('kind', 'product', 'item_id', pd, 'quantity', 1)) then
    raise exception 'FAIL 12: a replacement invoice''s line with no price source is not owed: %',
      (select jsonb_agg(t) from invoice_required_stock(exinv) t); end if;
  -- the legacy branch (invoices from before the stock snapshot) owes the
  -- replacement nothing either, and still owes that line
  update invoices set stock_snapshot_version = null where id = exinv;
  if (select jsonb_agg(t order by t.item_id) from invoice_required_stock(exinv) t)
     is distinct from jsonb_build_array(jsonb_build_object('kind', 'product', 'item_id', pd, 'quantity', 1)) then
    raise exception 'FAIL 12: the legacy branch still requires the replacement: %',
      (select jsonb_agg(t) from invoice_required_stock(exinv) t); end if;
  update invoices set stock_snapshot_version = null where id = inv;
  if (select jsonb_agg(t order by t.item_id) from invoice_required_stock(inv) t)
     is distinct from jsonb_build_array(jsonb_build_object('kind', 'product', 'item_id', pa, 'quantity', 1)) then
    raise exception 'FAIL 12: the legacy branch changed for an ordinary invoice'; end if;

  -- ════ 13. An invoice with an affiliate can be exchanged (EXC-3) ═════════════
  inv := create_invoice(st, cust, aff, jsonb_build_array(jsonb_build_object('kind', 'product', 'product_id', pa, 'quantity', 1)), 0, null, null, null);
  perform record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pm, 'amount', 100)), gen_random_uuid());
  res := exchange_original_context(inv);
  if res->>'affiliate' is distinct from 'XM Referrer' or (res->>'affiliate_still_eligible')::boolean is not true
     or (res->>'affiliate_inherited_id')::uuid is distinct from aff then
    raise exception 'FAIL 13: the original sale''s affiliate is not shown: %', res; end if;
  select id into li from invoice_items where invoice_id = inv;
  res := create_exchange_with_details('product', jsonb_build_object(
    'original_invoice_id', inv, 'processing_store_id', st,
    'returned', jsonb_build_array(jsonb_build_object('invoice_item_id', li, 'quantity', 1)),
    'replacement', jsonb_build_array(jsonb_build_object('product_id', pc, 'quantity', 1)),
    'payments', jsonb_build_array(jsonb_build_object('payment_method_id', pm, 'amount', 20)),
    'reason', 'Colour', 'served_by', staff));
  ex := (res->>'id')::uuid;
  perform pg_temp.settle();
  if (select affiliate_id from product_exchanges where id = ex) is not null then
    raise exception 'FAIL 13: the legacy affiliate column was written'; end if;
  if (select exchange_affiliate_id from product_exchanges where id = ex) is distinct from aff
     or (select affiliate_id from invoices where exchange_id = ex and is_exchange) is distinct from aff then
    raise exception 'FAIL 13: left as the original sale, the exchange did not carry its affiliate'; end if;
  -- "None" stays none
  inv2 := create_invoice(st, cust, aff, jsonb_build_array(jsonb_build_object('kind', 'product', 'product_id', pa, 'quantity', 1)), 0, null, null, null);
  perform record_invoice_payment(inv2, jsonb_build_array(jsonb_build_object('payment_method_id', pm, 'amount', 100)), gen_random_uuid());
  res := create_exchange_with_details('product', jsonb_build_object(
    'original_invoice_id', inv2, 'processing_store_id', st,
    'returned', jsonb_build_array(jsonb_build_object('invoice_item_id', (select id from invoice_items where invoice_id = inv2), 'quantity', 1)),
    'replacement', jsonb_build_array(jsonb_build_object('product_id', pb, 'quantity', 1)),
    'reason', 'Colour', 'served_by', staff, 'affiliate', jsonb_build_object('mode', 'none')));
  perform pg_temp.settle();
  if (select exchange_affiliate_id from product_exchanges where id = (res->>'id')::uuid) is not null
     or (select affiliate_id from invoices where exchange_id = (res->>'id')::uuid and is_exchange) is not null then
    raise exception 'FAIL 13: an explicit None carried the affiliate'; end if;
  -- a suspended affiliate is not carried over
  update customer_affiliates set manually_suspended = true where id = aff;
  if exchange_inherited_affiliate(aff) is not null
     or (exchange_original_context(inv)->>'affiliate_still_eligible')::boolean is not false then
    raise exception 'FAIL 13: a suspended affiliate would be carried over'; end if;

  -- ════ 14. Who may call what ═════════════════════════════════════════════════
  if not has_function_privilege('authenticated', 'public.exchange_bundle_preview(uuid,uuid,uuid,uuid)', 'execute')
     or has_function_privilege('anon', 'public.exchange_bundle_preview(uuid,uuid,uuid,uuid)', 'execute') then
    raise exception 'FAIL 14: the preview is not staff''s alone'; end if;
  select string_agg(f, ', ') into v from unnest(array[
      'exchange_inherited_affiliate(uuid)', 'exchange_assert_payments(jsonb,numeric,boolean)',
      'exchange_bundle_quote(uuid,uuid,uuid,uuid)', 'exchange_invoice_hold(uuid,uuid[])',
      'trg_invoice_exchange_hold()', 'trg_invoice_refund_exchange_hold()',
      'trg_stock_return_exchange_hold()', 'trg_invoice_item_exchange_hold()']) f
   where has_function_privilege('authenticated', 'public.' || f, 'execute')
      or has_function_privilege('anon', 'public.' || f, 'execute');
  if v is not null then raise exception 'FAIL 14: internal helpers callable by a client role: %', v; end if;

  raise notice 'PASS: no Wallet method pays an exchange and nothing is taken when nothing is due; a whole bundle is previewed, takes exactly its top-up and is refused when it cannot be done completely (choices, benefits, two bundles on a line, an item already swapped, a bundle not on sale here, a bundle edited since or sold before the snapshot); exchanged invoices, exchanged lines and replacement invoices are not cancelled, refunded, deleted or changed while other lines still refund; at commit no product comes back beyond what the invoice took out, while a correction of another line or the store goes through; an invoice with a refund is not exchanged, even when the refund commits while the exchange waits; paying a part-paid replacement takes nothing out again and a line with no price source is still owed; an invoice with an affiliate is exchanged and carries it unless None; the preview needs both stores; the helpers are endpoints for nobody';
end $$;
rollback;
