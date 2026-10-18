-- 424: what a returned item counts for, and where staff may exchange.
--
--   * Staff who work at two stores exchange at either one, not only at the
--     first store they were given; staff of one store are still refused at
--     the other (X-9).
--   * A returned item counts for the lower of today's price at the processing
--     store and what the customer paid for it; a free item gives no credit
--     (the Owner, 9 Oct 2026, Q17; SALES-EXTRAS-5). This holds for a
--     discounted line, a line whose price has since dropped, an FOC line, an
--     invoice discount shared by two lines, one product of a bundle (its share
--     of what the bundle line was paid, split by the value of everything the
--     line gave, vouchers and choices made at the till included), and a line
--     of a replacement invoice (paid partly by the credit it was given).
--   * A whole bundle's returned rows add up to its credit, to the cent.
--   * The Exchanges page sees the same figures before Confirm
--     (exchange_credit_preview), and only staff of both stores see them.
--   * The returned rows record the credit given, and the audit entry keeps
--     today's price and what was paid beside it.
--   * An instalment on the additional payment is recorded on the replacement
--     invoice (method and months), and only for money taken through that
--     method (SALES-EXTRAS-14).
--   * create_exchange_with_details refuses a login that is not staff (406).
-- Fixtures only (made-up names, +65914002xx phones, @sig.invalid emails).
-- Disposable database only; everything is rolled back.
\set ON_ERROR_STOP on
begin;

-- Acting as a signed-in person (null: the server, with auth.uid() kept for
-- the records' created_by).
create function pg_temp.as_user(p uuid, keep uuid) returns void language plpgsql as $$
begin
  if p is null then
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.sub', coalesce(keep::text, ''), true);
  else
    perform set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', p::text, true);
  end if;
end $$;
-- What a commit does to the replacement invoice: create it now, then go back
-- to waiting for the commit, so set_exchange_details runs first, as live.
create function pg_temp.settle() returns void language plpgsql as $$
begin
  set constraints public.exchange_creates_invoice immediate;
  set constraints public.exchange_creates_invoice deferred;
end $$;
-- What a commit does to 408's stock check: run every pending check now.
create function pg_temp.commit_checks() returns void language plpgsql as $$
begin
  if exists (select 1 from pg_constraint where conrelid = 'public.stock_movements'::regclass
              and conname = 'stock_return_exchange_hold' and condeferrable) then
    set constraints public.stock_return_exchange_hold immediate;
    set constraints public.stock_return_exchange_hold deferred;
  end if;
end $$;
create function pg_temp.line(p_inv uuid, p_product uuid) returns uuid language sql as
  $$ select id from public.invoice_items where invoice_id = p_inv and product_id = p_product order by id limit 1 $$;
-- One line of the credit preview, or one quantity of one product of a bundle line.
create function pg_temp.pv(p jsonb, p_line uuid) returns jsonb language sql as
  $$ select x from jsonb_array_elements(p->'lines') x where x->>'invoice_item_id' = p_line::text $$;
create function pg_temp.pvc(p jsonb, p_line uuid, p_product uuid, p_qty int) returns jsonb language sql as $$
  select o from jsonb_array_elements(pg_temp.pv(p, p_line)->'components') c,
                jsonb_array_elements(c->'options') o
   where c->>'product_id' = p_product::text and (o->>'quantity')::int = p_qty $$;
-- Today's price, what was paid and the credit, as "today/paid/credit".
create function pg_temp.fig(p jsonb) returns text language sql as
  $$ select coalesce(p->>'todays', '-') || '/' || coalesce(p->>'paid', '-') || '/' || coalesce(p->>'credit', '-') $$;

do $$
declare
  own uuid := gen_random_uuid(); s2 uuid := gen_random_uuid(); s1 uuid := gen_random_uuid();
  st uuid; st2 uuid; cust uuid; pm uuid; card uuid;
  pa uuid; pb uuid; pc uuid; pd uuid; pf uuid; pra uuid; prc uuid;
  inv uuid; inv2 uuid; li uuid; li2 uuid; ex uuid; exinv uuid; res jsonb; prev jsonb; v text; n int;
  st2staff jsonb; ststaff jsonb;
  vo1 uuid; vo2 uuid; prv uuid; prs uuid; g uuid; t1 uuid; t2 uuid; t3 uuid; p5 uuid; prw uuid; prf uuid;
begin
  insert into auth.users(id, email) values
    (own, 'xcr-own@sig.invalid'), (s2, 'xcr-s2@sig.invalid'), (s1, 'xcr-s1@sig.invalid');
  insert into profiles(id, full_name, email, role) values
    (own, 'XCR Owner', 'xcr-own@sig.invalid', 'owner'),
    (s2, 'XCR Staff Two', 'xcr-s2@sig.invalid', 'staff'),
    (s1, 'XCR Staff One', 'xcr-s1@sig.invalid', 'staff');
  perform pg_temp.as_user(null, own);
  insert into stores(name, code, country_code) values ('XCR Retail', 'XCRR', 'SG') returning id into st;
  insert into stores(name, code, country_code) values ('XCR Van', 'XCRV', 'SG') returning id into st2;
  -- Staff Two works at both stores, Retail first (as every member of staff in
  -- production); Staff One at Retail only.
  insert into user_store_assignments(user_id, store_id, created_at) values
    (s2, st, now() - interval '30 days'), (s2, st2, now() - interval '1 day'), (s1, st, now() - interval '30 days');
  st2staff := jsonb_build_array(s2::text);
  ststaff := jsonb_build_array(s1::text);
  insert into customers(full_name, phone) values ('XCR Buyer', '+61491578148') returning id into cust;
  insert into payment_methods(name, is_active) values ('XCR Cash', true) returning id into pm;
  insert into payment_methods(name, is_active) values ('XCR Card', true) returning id into card;
  insert into products(name, sku, product_type) values ('XCR A', 'XCRA', 'own') returning id into pa;
  insert into products(name, sku, product_type) values ('XCR B', 'XCRB', 'own') returning id into pb;
  insert into products(name, sku, product_type) values ('XCR C', 'XCRC', 'own') returning id into pc;
  insert into products(name, sku, product_type) values ('XCR D', 'XCRD', 'own') returning id into pd;
  insert into products(name, sku, product_type) values ('XCR F', 'XCRF', 'own') returning id into pf;
  insert into store_inventory(store_id, product_id, current_qty)
    select s, p, 50 from unnest(array[st, st2]) s, unnest(array[pa, pb, pc, pd, pf]) p;
  perform set_product_prices(s, pa, 100, 100, 'available') from unnest(array[st, st2]) s;
  perform set_product_prices(s, pb, 100, 100, 'available') from unnest(array[st, st2]) s;
  perform set_product_prices(s, pc, 120, 120, 'available') from unnest(array[st, st2]) s;
  perform set_product_prices(s, pd, 50, 50, 'available') from unnest(array[st, st2]) s;
  perform set_product_prices(s, pf, 1000, 1000, 'available') from unnest(array[st, st2]) s;
  -- bundle A+B (S$200 of products today) sold for S$150; bundle C (S$120)
  insert into promotions(name, code, fixed_price) values ('XCR Bundle AB', 'XCRAB', 150) returning id into pra;
  insert into promotion_items(promotion_id, item_type, product_id, quantity) values (pra, 'product', pa, 1), (pra, 'product', pb, 1);
  insert into promotions(name, code, fixed_price) values ('XCR Bundle C', 'XCRC1', 110) returning id into prc;
  insert into promotion_items(promotion_id, item_type, product_id, quantity) values (prc, 'product', pc, 1);
  perform set_promotion_prices(p, s, x, x, true)
     from (values (pra, 150::numeric), (prc, 110::numeric)) b(p, x), unnest(array[st, st2]) s;

  -- ════ 1. Staff on two stores exchange at either one (X-9) ══════════════════
  inv := create_invoice(st2, cust, null, jsonb_build_array(jsonb_build_object('kind', 'product', 'product_id', pa, 'quantity', 1)), 0, null, null, null);
  perform record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pm, 'amount', 100)), gen_random_uuid());
  perform pg_temp.as_user(s2, null);
  if my_assigned_store_id() is distinct from st then
    raise exception 'FIXTURE 1: Staff Two''s first store is not Retail'; end if;
  res := create_exchange_with_details('product', jsonb_build_object(
    'original_invoice_id', inv, 'processing_store_id', st2,
    'returned', jsonb_build_array(jsonb_build_object('invoice_item_id', pg_temp.line(inv, pa), 'quantity', 1)),
    'replacement', jsonb_build_array(jsonb_build_object('product_id', pb, 'quantity', 1)),
    'reason', 'Colour', 'served_by', st2staff));
  perform pg_temp.settle();
  if (select processing_store_id from product_exchanges where id = (res->>'id')::uuid) <> st2 then
    raise exception 'FAIL 1: Staff Two''s exchange at the Van was not recorded there'; end if;
  -- one item of a bundle, and a whole bundle, at the second store too
  inv := create_invoice(st2, cust, null, jsonb_build_array(jsonb_build_object('kind', 'promotion', 'promotion_id', pra, 'quantity', 1)), 0, null, null, null);
  perform record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pm, 'amount', 150)), gen_random_uuid());
  res := create_exchange_with_details('bundle_component', jsonb_build_object(
    'original_invoice_id', inv, 'processing_store_id', st2,
    'original_invoice_item_id', (select id from invoice_items where invoice_id = inv and line_kind = 'promotion'),
    'component_product_id', pa, 'component_qty', 1,
    'replacement', jsonb_build_array(jsonb_build_object('product_id', pd, 'quantity', 1)),
    'reason', 'Size', 'served_by', st2staff));
  perform pg_temp.settle();
  inv := create_invoice(st2, cust, null, jsonb_build_array(jsonb_build_object('kind', 'promotion', 'promotion_id', pra, 'quantity', 1)), 0, null, null, null);
  perform record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pm, 'amount', 150)), gen_random_uuid());
  res := create_exchange_with_details('bundle', jsonb_build_object(
    'original_invoice_id', inv, 'processing_store_id', st2,
    'original_invoice_item_id', (select id from invoice_items where invoice_id = inv and line_kind = 'promotion'),
    'new_promotion_id', prc, 'reason', 'Swap', 'served_by', st2staff));
  perform pg_temp.settle();
  -- Staff of one store are still refused at the other.
  inv := create_invoice(st2, cust, null, jsonb_build_array(jsonb_build_object('kind', 'product', 'product_id', pa, 'quantity', 1)), 0, null, null, null);
  perform pg_temp.as_user(null, own);
  perform record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pm, 'amount', 100)), gen_random_uuid());
  perform pg_temp.as_user(s1, null);
  begin
    perform create_exchange_with_details('product', jsonb_build_object(
      'original_invoice_id', inv, 'processing_store_id', st2,
      'returned', jsonb_build_array(jsonb_build_object('invoice_item_id', pg_temp.line(inv, pa), 'quantity', 1)),
      'replacement', jsonb_build_array(jsonb_build_object('product_id', pb, 'quantity', 1)),
      'reason', 'Colour', 'served_by', ststaff));
    raise exception 'FAIL 1: staff of Retail only exchanged at the Van';
  exception when others then
    if sqlerrm not like 'You do not have access to the processing store%' then raise; end if;
  end;
  if exists (select 1 from product_exchanges where original_invoice_id = inv) then
    raise exception 'FAIL 1: the refused exchange left a record'; end if;
  -- A login that is not staff is refused by the page's call itself (406).
  perform pg_temp.as_user(gen_random_uuid(), null);
  begin
    perform create_exchange_with_details('product', jsonb_build_object(
      'original_invoice_id', inv, 'processing_store_id', st2, 'returned', '[]'::jsonb, 'replacement', '[]'::jsonb,
      'reason', 'x', 'served_by', st2staff));
    raise exception 'FAIL 1: a login with no profile reached the exchange';
  exception when others then
    if sqlstate <> '42501' or sqlerrm not like 'Only active Energia staff%' then raise; end if;
  end;
  perform pg_temp.as_user(null, own);

  -- ════ 2. A discounted line counts for what was paid (Q17) ══════════════════
  perform set_config('invoice.manual_discount_reason', 'XCR loyalty', true);
  inv := create_invoice(st, cust, null, jsonb_build_array(jsonb_build_object('kind', 'product', 'product_id', pa, 'quantity', 1)), 25, null, null, null);
  perform set_config('invoice.manual_discount_reason', '', true);
  if (select total_amount from invoices where id = inv) <> 75 then
    raise exception 'FIXTURE 2: the discounted invoice is %, not 75', (select total_amount from invoices where id = inv); end if;
  perform record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pm, 'amount', 75)), gen_random_uuid());
  li := pg_temp.line(inv, pa);
  prev := exchange_credit_preview(inv, st);
  if pg_temp.fig(pg_temp.pv(prev, li)) <> '100.00/75.00/75.00' then
    raise exception 'FAIL 2: the preview of a line paid 75 at 100 today is %', pg_temp.fig(pg_temp.pv(prev, li)); end if;
  res := create_exchange_with_details('product', jsonb_build_object(
    'original_invoice_id', inv, 'processing_store_id', st,
    'returned', jsonb_build_array(jsonb_build_object('invoice_item_id', li, 'quantity', 1)),
    'replacement', jsonb_build_array(jsonb_build_object('product_id', pc, 'quantity', 1)),
    'payments', jsonb_build_array(jsonb_build_object('payment_method_id', pm, 'amount', 45)),
    'reason', 'Upgrade', 'served_by', ststaff));
  ex := (res->>'id')::uuid;
  perform pg_temp.settle();
  if (select returned_credit_total from product_exchanges where id = ex) <> 75
     or (select topup_amount from product_exchanges where id = ex) <> 45 then
    raise exception 'FAIL 2: the discounted line was credited %, top-up %, not 75 and 45',
      (select returned_credit_total from product_exchanges where id = ex), (select topup_amount from product_exchanges where id = ex); end if;
  -- the returned row records the credit it gave, and the audit both figures
  if (select unit_price::text || '/' || line_total::text from product_exchange_items
       where exchange_id = ex and direction = 'returned') <> '75.00/75.00' then
    raise exception 'FAIL 2: the returned row records % (unit/total), not the 75 credit',
      (select unit_price::text || '/' || line_total::text from product_exchange_items where exchange_id = ex and direction = 'returned'); end if;
  if (select (new_data->>'credit_todays_price')::numeric = 100 and (new_data->>'credit_paid')::numeric = 75
        from audit_logs where record_id = ex and action = 'exchange_completed') is not true then
    raise exception 'FAIL 2: the audit entry does not keep today''s price 100 and the 75 paid'; end if;
  if (select total_amount from invoices where exchange_id = ex and is_exchange) <> 45 then
    raise exception 'FAIL 2: the replacement invoice is not the 45 top-up'; end if;

  -- ════ 3. A price that dropped below what was paid counts at today's price ══
  inv := create_invoice(st, cust, null, jsonb_build_array(jsonb_build_object('kind', 'product', 'product_id', pa, 'quantity', 1)), 0, null, null, null);
  perform record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pm, 'amount', 100)), gen_random_uuid());
  perform set_product_prices(st, pa, 80, 80, 'available');
  if pg_temp.fig(pg_temp.pv(exchange_credit_preview(inv, st), pg_temp.line(inv, pa))) <> '80.00/100.00/80.00' then
    raise exception 'FAIL 3: a line paid 100 at 80 today previews %',
      pg_temp.fig(pg_temp.pv(exchange_credit_preview(inv, st), pg_temp.line(inv, pa))); end if;
  res := create_exchange_with_details('product', jsonb_build_object(
    'original_invoice_id', inv, 'processing_store_id', st,
    'returned', jsonb_build_array(jsonb_build_object('invoice_item_id', pg_temp.line(inv, pa), 'quantity', 1)),
    'replacement', jsonb_build_array(jsonb_build_object('product_id', pb, 'quantity', 1)),
    'payments', jsonb_build_array(jsonb_build_object('payment_method_id', pm, 'amount', 20)),
    'reason', 'Colour', 'served_by', ststaff));
  perform pg_temp.settle();
  if (select returned_credit_total from product_exchanges where id = (res->>'id')::uuid) <> 80 then
    raise exception 'FAIL 3: the line was not credited at today''s 80'; end if;
  perform set_product_prices(st, pa, 100, 100, 'available');

  -- ════ 4. A free item gives no credit ═══════════════════════════════════════
  inv := create_invoice(st, cust, null, jsonb_build_array(
           jsonb_build_object('kind', 'product', 'product_id', pa, 'quantity', 1),
           jsonb_build_object('kind', 'product', 'product_id', pd, 'quantity', 1)), 0, null, null, null);
  perform apply_line_foc(pg_temp.line(inv, pa), null, null, 'XCR birthday gift');
  if (select total_amount from invoices where id = inv) <> 50 then
    raise exception 'FIXTURE 4: the invoice with A free is %, not 50', (select total_amount from invoices where id = inv); end if;
  perform record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pm, 'amount', 50)), gen_random_uuid());
  prev := exchange_credit_preview(inv, st);
  if pg_temp.fig(pg_temp.pv(prev, pg_temp.line(inv, pa))) <> '100.00/0.00/0.00'
     or pg_temp.fig(pg_temp.pv(prev, pg_temp.line(inv, pd))) <> '50.00/50.00/50.00' then
    raise exception 'FAIL 4: the free line previews %, the paid one %', pg_temp.fig(pg_temp.pv(prev, pg_temp.line(inv, pa))),
      pg_temp.fig(pg_temp.pv(prev, pg_temp.line(inv, pd))); end if;
  res := create_exchange_with_details('product', jsonb_build_object(
    'original_invoice_id', inv, 'processing_store_id', st,
    'returned', jsonb_build_array(jsonb_build_object('invoice_item_id', pg_temp.line(inv, pa), 'quantity', 1)),
    'replacement', jsonb_build_array(jsonb_build_object('product_id', pb, 'quantity', 1)),
    'payments', jsonb_build_array(jsonb_build_object('payment_method_id', pm, 'amount', 100)),
    'reason', 'Swap the gift', 'served_by', ststaff));
  perform pg_temp.settle();
  if (select returned_credit_total::text || '/' || topup_amount::text from product_exchanges where id = (res->>'id')::uuid) <> '0.00/100.00' then
    raise exception 'FAIL 4: the free item was credited (credit/top-up %)',
      (select returned_credit_total::text || '/' || topup_amount::text from product_exchanges where id = (res->>'id')::uuid); end if;

  -- ════ 5. An invoice discount is shared by its lines ════════════════════════
  perform set_config('invoice.manual_discount_reason', 'XCR loyalty', true);
  inv := create_invoice(st, cust, null, jsonb_build_array(
           jsonb_build_object('kind', 'product', 'product_id', pa, 'quantity', 1),
           jsonb_build_object('kind', 'product', 'product_id', pd, 'quantity', 1)), 30, null, null, null);
  perform set_config('invoice.manual_discount_reason', '', true);
  perform record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pm, 'amount', 120)), gen_random_uuid());
  prev := exchange_credit_preview(inv, st);
  if pg_temp.fig(pg_temp.pv(prev, pg_temp.line(inv, pa))) <> '100.00/80.00/80.00'
     or pg_temp.fig(pg_temp.pv(prev, pg_temp.line(inv, pd))) <> '50.00/40.00/40.00' then
    raise exception 'FAIL 5: S$30 off S$150 is not shared 20/10: A %, D %', pg_temp.fig(pg_temp.pv(prev, pg_temp.line(inv, pa))),
      pg_temp.fig(pg_temp.pv(prev, pg_temp.line(inv, pd))); end if;

  -- ════ 6. One product of a bundle: its share of what the line was paid ══════
  inv := create_invoice(st, cust, null, jsonb_build_array(jsonb_build_object('kind', 'promotion', 'promotion_id', pra, 'quantity', 1)), 0, null, null, null);
  perform record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pm, 'amount', 150)), gen_random_uuid());
  li := (select id from invoice_items where invoice_id = inv and line_kind = 'promotion');
  prev := exchange_credit_preview(inv, st);
  if pg_temp.fig(pg_temp.pvc(prev, li, pa, 1)) <> '100.00/75.00/75.00' or pg_temp.fig(pg_temp.pvc(prev, li, pb, 1)) <> '100.00/75.00/75.00'
     or pg_temp.fig(pg_temp.pv(prev, li)) <> '200.00/150.00/150.00' then
    raise exception 'FAIL 6: the bundle sold for 150 previews A %, B %, whole %', pg_temp.fig(pg_temp.pvc(prev, li, pa, 1)),
      pg_temp.fig(pg_temp.pvc(prev, li, pb, 1)), pg_temp.fig(pg_temp.pv(prev, li)); end if;
  res := create_exchange_with_details('bundle_component', jsonb_build_object(
    'original_invoice_id', inv, 'processing_store_id', st, 'original_invoice_item_id', li,
    'component_product_id', pa, 'component_qty', 1,
    'replacement', jsonb_build_array(jsonb_build_object('product_id', pc, 'quantity', 1)),
    'payments', jsonb_build_array(jsonb_build_object('payment_method_id', pm, 'amount', 45)),
    'reason', 'Size', 'served_by', ststaff));
  ex := (res->>'id')::uuid;
  perform pg_temp.settle();
  if (select returned_credit_total::text || '/' || topup_amount::text from product_exchanges where id = ex) <> '75.00/45.00'
     or (select line_total from product_exchange_items where exchange_id = ex and direction = 'returned') <> 75 then
    raise exception 'FAIL 6: one product of the bundle was credited % (credit/top-up), not 75/45',
      (select returned_credit_total::text || '/' || topup_amount::text from product_exchanges where id = ex); end if;
  if (select (new_data->>'credit_todays_price')::numeric = 100 and (new_data->>'credit_paid')::numeric = 75
        from audit_logs where record_id = ex and action = 'bundle_component_exchange_completed') is not true then
    raise exception 'FAIL 6: the audit entry does not keep today''s price 100 and the 75 paid'; end if;
  -- two bundles on a line: each quantity of a product is its share
  inv := create_invoice(st, cust, null, jsonb_build_array(jsonb_build_object('kind', 'promotion', 'promotion_id', pra, 'quantity', 2)), 0, null, null, null);
  perform record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pm, 'amount', 300)), gen_random_uuid());
  li := (select id from invoice_items where invoice_id = inv and line_kind = 'promotion');
  prev := exchange_credit_preview(inv, st);
  if pg_temp.fig(pg_temp.pvc(prev, li, pa, 1)) <> '100.00/75.00/75.00' or pg_temp.fig(pg_temp.pvc(prev, li, pa, 2)) <> '200.00/150.00/150.00'
     or pg_temp.pvc(prev, li, pa, 3) is not null then
    raise exception 'FAIL 6: two bundles preview A×1 %, A×2 %', pg_temp.fig(pg_temp.pvc(prev, li, pa, 1)), pg_temp.fig(pg_temp.pvc(prev, li, pa, 2)); end if;
  -- A bundle that also gives a voucher: A (S$100) and a S$300 voucher, sold
  -- for S$200. A's share is S$200 x 100 / 400 = S$50, not the whole S$200.
  insert into vouchers(name, code, selling_price) values ('XCR Voucher 300', 'XCRV300', 300) returning id into vo1;
  insert into vouchers(name, code, selling_price) values ('XCR Voucher 100', 'XCRV100', 100) returning id into vo2;
  insert into promotions(name, code, fixed_price) values ('XCR Bundle A+V', 'XCRAV', 200) returning id into prv;
  insert into promotion_items(promotion_id, item_type, product_id, quantity) values (prv, 'product', pa, 1);
  insert into promotion_items(promotion_id, item_type, voucher_id, quantity) values (prv, 'voucher', vo1, 1);
  perform set_promotion_prices(prv, st, 200, 200, true);
  inv := create_invoice(st, cust, null, jsonb_build_array(jsonb_build_object('kind', 'promotion', 'promotion_id', prv, 'quantity', 1)), 0, null, null, null);
  perform record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pm, 'amount', 200)), gen_random_uuid());
  li := (select id from invoice_items where invoice_id = inv and line_kind = 'promotion');
  prev := exchange_credit_preview(inv, st);
  if pg_temp.fig(pg_temp.pvc(prev, li, pa, 1)) <> '100.00/50.00/50.00' or pg_temp.fig(pg_temp.pv(prev, li)) <> '400.00/200.00/200.00' then
    raise exception 'FAIL 6: A of a S$200 bundle that also gave a S$300 voucher previews % (whole %), not 100/50/50',
      pg_temp.fig(pg_temp.pvc(prev, li, pa, 1)), pg_temp.fig(pg_temp.pv(prev, li)); end if;
  res := create_exchange_with_details('bundle_component', jsonb_build_object(
    'original_invoice_id', inv, 'processing_store_id', st, 'original_invoice_item_id', li,
    'component_product_id', pa, 'component_qty', 1,
    'replacement', jsonb_build_array(jsonb_build_object('product_id', pd, 'quantity', 1)),
    'reason', 'Size', 'served_by', ststaff));
  ex := (res->>'id')::uuid;
  perform pg_temp.settle();
  if (select returned_credit_total::text || '/' || topup_amount::text || '/' || nonrefundable_amount::text
        from product_exchanges where id = ex) <> '50.00/0.00/0.00' then
    raise exception 'FAIL 6: A of the bundle with a voucher was credited % (credit/top-up/unused), not 50/0/0',
      (select returned_credit_total::text || '/' || topup_amount::text || '/' || nonrefundable_amount::text
         from product_exchanges where id = ex); end if;
  -- A voucher chosen at the till counts too: A and a choice of the S$300 or
  -- the S$100 voucher, sold for S$150 with the S$300 one chosen. A's share is
  -- S$150 x 100 / 400 = S$37.50.
  insert into promotions(name, code, fixed_price) values ('XCR Bundle A+choice', 'XCRAS', 150) returning id into prs;
  insert into promotion_items(promotion_id, item_type, product_id, quantity) values (prs, 'product', pa, 1);
  insert into promotion_choice_groups(promotion_id, label, item_kind, choose_qty)
    values (prs, 'XCR pick a voucher', 'voucher', 1) returning id into g;
  insert into promotion_choice_options(group_id, voucher_id) values (g, vo1), (g, vo2);
  perform set_promotion_prices(prs, st, 150, 150, true);
  inv := create_invoice(st, cust, null, jsonb_build_array(jsonb_build_object(
    'kind', 'promotion', 'promotion_id', prs, 'quantity', 1,
    'selections', jsonb_build_array(jsonb_build_object('group_id', g,
      'options', jsonb_build_array(jsonb_build_object('voucher_id', vo1, 'quantity', 1)))))), 0, null, null, null);
  perform record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pm, 'amount', 150)), gen_random_uuid());
  li := (select id from invoice_items where invoice_id = inv and line_kind = 'promotion');
  if pg_temp.fig(pg_temp.pvc(exchange_credit_preview(inv, st), li, pa, 1)) <> '100.00/37.50/37.50' then
    raise exception 'FAIL 6: A of a S$150 bundle with a S$300 voucher chosen previews %, not 100/37.50/37.50',
      pg_temp.fig(pg_temp.pvc(exchange_credit_preview(inv, st), li, pa, 1)); end if;

  -- ════ 7. A line of a replacement invoice was also paid by its credit ════════
  inv := create_invoice(st, cust, null, jsonb_build_array(jsonb_build_object('kind', 'product', 'product_id', pa, 'quantity', 1)), 0, null, null, null);
  perform record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pm, 'amount', 100)), gen_random_uuid());
  res := create_exchange_with_details('product', jsonb_build_object(
    'original_invoice_id', inv, 'processing_store_id', st,
    'returned', jsonb_build_array(jsonb_build_object('invoice_item_id', pg_temp.line(inv, pa), 'quantity', 1)),
    'replacement', jsonb_build_array(jsonb_build_object('product_id', pc, 'quantity', 1)),
    'payments', jsonb_build_array(jsonb_build_object('payment_method_id', pm, 'amount', 20)),
    'reason', 'Upgrade', 'served_by', ststaff));
  perform pg_temp.settle();
  select id into exinv from invoices where exchange_id = (res->>'id')::uuid and is_exchange;
  -- C on the replacement: 20 paid now and 100 carried over = 120, as today
  if pg_temp.fig(pg_temp.pv(exchange_credit_preview(exinv, st), pg_temp.line(exinv, pc))) <> '120.00/120.00/120.00' then
    raise exception 'FAIL 7: the replacement line previews %, not 120 paid',
      pg_temp.fig(pg_temp.pv(exchange_credit_preview(exinv, st), pg_temp.line(exinv, pc))); end if;
  res := create_exchange_with_details('product', jsonb_build_object(
    'original_invoice_id', exinv, 'processing_store_id', st,
    'returned', jsonb_build_array(jsonb_build_object('invoice_item_id', pg_temp.line(exinv, pc), 'quantity', 1)),
    'replacement', jsonb_build_array(jsonb_build_object('product_id', pb, 'quantity', 1)),
    'reason', 'Changed mind again', 'served_by', ststaff));
  perform pg_temp.settle();
  if (select returned_credit_total::text || '/' || nonrefundable_amount::text from product_exchanges where id = (res->>'id')::uuid) <> '120.00/20.00' then
    raise exception 'FAIL 7: the replacement line was credited % (credit/unused), not 120/20',
      (select returned_credit_total::text || '/' || nonrefundable_amount::text from product_exchanges where id = (res->>'id')::uuid); end if;

  -- ════ 8. Who sees the credit preview ═══════════════════════════════════════
  inv := create_invoice(st2, cust, null, jsonb_build_array(jsonb_build_object('kind', 'product', 'product_id', pa, 'quantity', 1)), 0, null, null, null);
  perform record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pm, 'amount', 100)), gen_random_uuid());
  perform pg_temp.as_user(s2, null);
  if pg_temp.fig(pg_temp.pv(exchange_credit_preview(inv, st), pg_temp.line(inv, pa))) <> '100.00/100.00/100.00' then
    raise exception 'FAIL 8: Staff Two (both stores) cannot preview a Van sale processed at Retail'; end if;
  perform pg_temp.as_user(s1, null);
  begin
    perform exchange_credit_preview(inv, st);
    raise exception 'FAIL 8: staff of Retail only read a Van invoice through the preview';
  exception when others then
    if sqlerrm not like 'Invoice not accessible%' then raise; end if;
  end;
  begin
    perform exchange_credit_preview(inv, st2);
    raise exception 'FAIL 8: staff of Retail only previewed at the Van';
  exception when others then
    if sqlerrm not like 'You do not have access to the processing store%' then raise; end if;
  end;
  perform pg_temp.as_user(gen_random_uuid(), null);
  begin
    perform exchange_credit_preview(inv, st2);
    raise exception 'FAIL 8: a login with no profile previewed an exchange';
  exception when others then
    if sqlstate <> '42501' or sqlerrm not like 'Only active Energia staff%' then raise; end if;
  end;
  perform pg_temp.as_user(null, own);

  -- ════ 9. An instalment is recorded on the replacement invoice ══════════════
  inv := create_invoice(st, cust, null, jsonb_build_array(jsonb_build_object('kind', 'product', 'product_id', pa, 'quantity', 1)), 0, null, null, null);
  perform record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pm, 'amount', 100)), gen_random_uuid());
  li := pg_temp.line(inv, pa);
  for res in select x from jsonb_array_elements(jsonb_build_array(
      jsonb_build_object('inst', jsonb_build_object('method_id', pm, 'months', 6), 'says', '%must be one the money was taken through%'),
      jsonb_build_object('inst', jsonb_build_object('method_id', card, 'months', 0), 'says', '%positive whole number of months%'),
      jsonb_build_object('inst', jsonb_build_object('method_id', card, 'months', 2.5), 'says', '%positive whole number of months%'),
      jsonb_build_object('inst', jsonb_build_object('months', 6), 'says', '%positive whole number of months%'),
      jsonb_build_object('inst', to_jsonb('six months'::text), 'says', '%must say its payment method and months%'))) x
  loop
    begin
      perform create_exchange_with_details('product', jsonb_build_object(
        'original_invoice_id', inv, 'processing_store_id', st,
        'returned', jsonb_build_array(jsonb_build_object('invoice_item_id', li, 'quantity', 1)),
        'replacement', jsonb_build_array(jsonb_build_object('product_id', pf, 'quantity', 1)),
        'payments', jsonb_build_array(jsonb_build_object('payment_method_id', card, 'amount', 900)),
        'instalment', res->'inst', 'reason', 'Upgrade', 'served_by', ststaff));
      raise exception 'FAIL 9: the instalment % was accepted', res->'inst';
    exception when others then
      if sqlerrm not like res->>'says' then raise; end if;
    end;
  end loop;
  if exists (select 1 from product_exchanges where original_invoice_id = inv) then
    raise exception 'FAIL 9: a refused instalment left an exchange behind'; end if;
  res := create_exchange_with_details('product', jsonb_build_object(
    'original_invoice_id', inv, 'processing_store_id', st,
    'returned', jsonb_build_array(jsonb_build_object('invoice_item_id', li, 'quantity', 1)),
    'replacement', jsonb_build_array(jsonb_build_object('product_id', pf, 'quantity', 1)),
    'payments', jsonb_build_array(jsonb_build_object('payment_method_id', card, 'amount', 900)),
    'instalment', jsonb_build_object('method_id', card, 'months', 6), 'reason', 'Upgrade', 'served_by', ststaff));
  set constraints public.exchange_creates_invoice deferred;   -- as the next call starts in production
  select id into exinv from invoices where exchange_id = (res->>'id')::uuid and is_exchange;
  if (select instalment_category || '/' || instalment_method_id::text || '/' || instalment_months::text from invoices where id = exinv)
     is distinct from 'in_house/' || card::text || '/6'
     or (res->>'exchange_invoice_id')::uuid is distinct from exinv or (res->'instalment'->>'months')::int <> 6 then
    raise exception 'FAIL 9: the replacement invoice does not record the 6-month instalment by card'; end if;
  if (select status::text || '/' || paid_amount::text from invoices where id = exinv) <> 'paid/900.00'
     or not exists (select 1 from invoice_service_staff where invoice_id = exinv and staff_id = s1) then
    raise exception 'FAIL 9: the replacement invoice is not paid 900 and served by Staff One'; end if;
  -- an even swap takes no money, so there is nothing to label
  inv := create_invoice(st, cust, null, jsonb_build_array(jsonb_build_object('kind', 'product', 'product_id', pa, 'quantity', 1)), 0, null, null, null);
  perform record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pm, 'amount', 100)), gen_random_uuid());
  begin
    perform create_exchange_with_details('product', jsonb_build_object(
      'original_invoice_id', inv, 'processing_store_id', st,
      'returned', jsonb_build_array(jsonb_build_object('invoice_item_id', pg_temp.line(inv, pa), 'quantity', 1)),
      'replacement', jsonb_build_array(jsonb_build_object('product_id', pb, 'quantity', 1)),
      'instalment', jsonb_build_object('method_id', card, 'months', 6), 'reason', 'Colour', 'served_by', ststaff));
    raise exception 'FAIL 9: an instalment was recorded on an even swap';
  exception when others then
    if sqlerrm not like '%must be one the money was taken through%' then raise; end if;
  end;
  -- and with no instalment the replacement invoice carries none
  res := create_exchange_with_details('product', jsonb_build_object(
    'original_invoice_id', inv, 'processing_store_id', st,
    'returned', jsonb_build_array(jsonb_build_object('invoice_item_id', pg_temp.line(inv, pa), 'quantity', 1)),
    'replacement', jsonb_build_array(jsonb_build_object('product_id', pb, 'quantity', 1)),
    'instalment', null, 'reason', 'Colour', 'served_by', ststaff));
  perform pg_temp.settle();
  if exists (select 1 from invoices where exchange_id = (res->>'id')::uuid and is_exchange
              and (instalment_category is not null or instalment_method_id is not null or instalment_months is not null)) then
    raise exception 'FAIL 9: an exchange with no instalment recorded one'; end if;

  -- ════ 10. A whole bundle's returned rows add up to its credit ══════════════
  -- Three S$10 items sold together for S$20, swapped whole for a S$5 bundle:
  -- each row is a third of S$20, and the last takes what is left.
  insert into products(name, sku, product_type) values ('XCR T1', 'XCRT1', 'own') returning id into t1;
  insert into products(name, sku, product_type) values ('XCR T2', 'XCRT2', 'own') returning id into t2;
  insert into products(name, sku, product_type) values ('XCR T3', 'XCRT3', 'own') returning id into t3;
  insert into products(name, sku, product_type) values ('XCR Five', 'XCR5', 'own') returning id into p5;
  insert into store_inventory(store_id, product_id, current_qty) select st, p, 50 from unnest(array[t1, t2, t3, p5]) p;
  perform set_product_prices(st, p, 10, 10, 'available') from unnest(array[t1, t2, t3]) p;
  perform set_product_prices(st, p5, 5, 5, 'available');
  insert into promotions(name, code, fixed_price) values ('XCR Three', 'XCRT', 20) returning id into prw;
  insert into promotion_items(promotion_id, item_type, product_id, quantity) values (prw, 'product', t1, 1), (prw, 'product', t2, 1), (prw, 'product', t3, 1);
  insert into promotions(name, code, fixed_price) values ('XCR Five Bundle', 'XCRF5', 5) returning id into prf;
  insert into promotion_items(promotion_id, item_type, product_id, quantity) values (prf, 'product', p5, 1);
  perform set_promotion_prices(p, st, x, x, true) from (values (prw, 20::numeric), (prf, 5::numeric)) b(p, x);
  inv := create_invoice(st, cust, null, jsonb_build_array(jsonb_build_object('kind', 'promotion', 'promotion_id', prw, 'quantity', 1)), 0, null, null, null);
  perform record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pm, 'amount', 20)), gen_random_uuid());
  res := create_exchange_with_details('bundle', jsonb_build_object(
    'original_invoice_id', inv, 'processing_store_id', st,
    'original_invoice_item_id', (select id from invoice_items where invoice_id = inv and line_kind = 'promotion'),
    'new_promotion_id', prf, 'reason', 'Swap', 'served_by', ststaff));
  ex := (res->>'id')::uuid;
  perform pg_temp.settle();
  if (select returned_credit_total::text || '/' || nonrefundable_amount::text from product_exchanges where id = ex) <> '20.00/15.00' then
    raise exception 'FAIL 10: the S$20 bundle swapped for a S$5 one gave % (credit/unused), not 20/15',
      (select returned_credit_total::text || '/' || nonrefundable_amount::text from product_exchanges where id = ex); end if;
  if (select sum(line_total) from product_exchange_items where exchange_id = ex and direction = 'returned') <> 20
     or (select count(*) from product_exchange_items where exchange_id = ex and direction = 'returned') <> 3
     or (select string_agg(line_total::text, ',' order by line_total desc) from product_exchange_items
          where exchange_id = ex and direction = 'returned') <> '6.67,6.67,6.66' then
    raise exception 'FAIL 10: the returned rows (%) do not add up to the S$20 credit',
      (select string_agg(line_total::text, ',' order by line_total desc) from product_exchange_items
        where exchange_id = ex and direction = 'returned'); end if;

  perform pg_temp.commit_checks();   -- nothing here is refused at commit
  raise notice 'PASS: staff on two stores exchange at either and staff of one store are refused at the other; a returned item counts for the lower of today''s price and what was paid (discounted, price dropped, free, a shared invoice discount, one product of a bundle, also beside a voucher in the bundle or chosen at the till, a replacement line), as the preview shows only to staff of both stores; the returned rows and the audit keep the figures, and a whole bundle''s rows add up to its credit; an instalment is recorded on the replacement invoice only for money taken through its method; a login that is not staff is refused';
end $$;
rollback;
