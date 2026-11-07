-- 500_special_sales_follow_invoice_customer_store_price.sql
--
-- EVERY SPECIAL SALE NOT CANCELLED FOLLOWS ITS INVOICE'S CUSTOMER AND STORE AND ITS LINE'S PRICE,
-- AND A CUSTOMER CHANGE NO LONGER WARNS ABOUT BENEFITS THE INVOICE DOES NOT HAVE
-- (the user, 7 Nov 2026: a machine already released or sent by a supplier, "Follow the invoice
-- too"; "Corrected price"; a machine already released, "Yes, same as waiting"; "False warning")
--
-- (The number 500 is this file's name, its errors' prefix, its self-test's error code P0500,
-- its suite's and its UNDO's; if it changes at commit, change it in these places alone.)
--
-- WHAT WAS WRONG
--
--   1. 498 moved only a sale still waiting. A machine released, or sent by a supplier, kept the
--      old customer and store, so the Special page, its receipt and its WhatsApp and email
--      buttons used the old customer, and the receipt had the old store. Production, read only,
--      7 Nov 2026: one such sale (put right beside this migration, with the user's OK).
--   2. A corrected price stayed on the invoice: a sale keeps the amount it was raised with, so
--      the Special page and the receipt showed the old one. Production: every sale's amount
--      equals its line's price today, so nothing is out of step.
--   3. Since 17 Sep 2026 a customer change on an invoice with no benefits said "Choose whether
--      the unused benefits move..." and "Saving will be refused", and then the save went through.
--      The summary asked whenever no choice was sent; the save asks only when
--      invoice_transferable_benefits has a row, and the page offers the choice only then.
--
-- WHAT THIS DOES
--
--   1. invoice_special_sales_follow_lines: every sale not cancelled takes the invoice's customer
--      and store whenever they differ, waiting, released or sent by a supplier. Where the machine
--      physically left from is not touched (warehouse_id, source_store_id, supplier_id,
--      deliver_to, the stock movement), and no stock moves.
--   2. It also gives every sale not cancelled its line's price when they differ, on a line still
--      holding the same machine: the price before any discount, as the sale is raised and as a
--      rental's fee is. No money and no stock moves: reports and payments read the invoice, and
--      the sale's amount is what its list, export and documents show. correct_invoice already
--      calls it when the lines change, and a new price is a changed line (invoice_line_matches).
--   3. Note, Audit Log ('special_sale_follows_invoice', 'special_sale_price_follows_invoice'), and
--      the correction summary and the page's note say it (state 'moved', 'repriced').
--   4. preview_invoice_correction asks about benefits only when the invoice has some, as the
--      save does. Nothing else about the summary changes.
--
-- WHAT THIS DOES NOT DO
--
--   A cancelled sale, and every sale of a cancelled or refunded invoice, is left as it is. A sale
--   a supplier sent on a line now holding another machine keeps its price (497 says it stays).
--   The Discount on a line does not reach the sale. A rental out still refuses a customer change
--   (458). No page changes: the summary and the note show whatever the correction answers.
--
-- UNDO: scripts/special/undo-500.sql (refuses unless each function is 500's version; sales that
-- already followed stay as they are). Undo 500 before 498. A later migration changing these
-- functions must pin 500's AFTER md5s below.
--
-- One transaction with its history row, by the usual wrapper; nothing else is written.

do $mig$
declare
  -- The functions this patches: BEFORE (production now) and AFTER md5s
  c_sig constant text[] := array[
    'invoice_special_sales_follow_lines(uuid,jsonb,text,uuid)',
    'preview_invoice_correction(uuid,jsonb)'];
  c_before constant text[] := array[
    '3cf6cfd8a22e5776e7b77e8d5ff3753d',
    '13b0925c29bd8ca14d8d8b7bd961fef8'];
  c_after constant text[] := array[
    '933ef75eaa654cbcef7ad8671c63d812',
    '23c180873b6545bd83fb20d21708aa9e'];
  -- Each patch: which function (its place in c_sig), the text found exactly once
  -- in it, and the text put in its place. The UNDO file swaps them back.
  c_fn constant int[] := array[1, 1, 1, 2];
  c_anchor constant text[] := array[
$a$--   * 498 (the user, 7 Nov 2026): a sale still waiting takes the invoice's customer and
--     store whenever they differ, whichever line it is on. A released one keeps them:
--     the machine went to that customer from there.
--   * A cancelled or refunded invoice, and a rental's line, are left as they are.
-- Internal. Answers [{sale_no, state, what}], state: waiting_off, back, stays, raised, moved.$a$,
$a$  -- 498: a sale still waiting follows the invoice's customer and store.
  for r in select s.id, s.sale_no, s.special_product_id, s.customer_id, s.store_id
             from public.special_sales s
            where s.invoice_id = p_invoice_id and s.status <> 'cancelled'
              and s.warehouse_id is null and s.source_store_id is null and s.supplier_id is null
              and (s.customer_id, s.store_id) is distinct from (v_inv.customer_id, v_inv.store_id)$a$,
$a$      'what', r.sale_no || ': ' || public.special_product_name(r.special_product_id) || ' moves to '
        || concat_ws(' and ',
             case when v_inv.customer_id is distinct from r.customer_id
                  then coalesce((select c.full_name from public.customers c where c.id = v_inv.customer_id), 'the invoice''s customer') end,
             case when v_inv.store_id is distinct from r.store_id
                  then coalesce((select t.name from public.stores t where t.id = v_inv.store_id), 'the invoice''s store') end)));
  end loop;
  return v_list;$a$,
$a$    elsif coalesce(p_header->>'benefit_action','') = '' then
      v_reviews := v_reviews || jsonb_build_array(jsonb_build_object(
        'area','benefits',$a$];
  c_new constant text[] := array[
$n$--   * 498, 500 (the user, 7 Nov 2026): every sale not cancelled takes the invoice's customer
--     and store whenever they differ, whichever line it is on: waiting, released or sent by a
--     supplier. Where it left from stays, and no stock moves.
--   * 500: and its line's price, on a line still holding the same machine: the price before any
--     discount, as it was raised and as a rental's fee. No money and no stock moves: the invoice
--     stays the record of what is owed.
--   * A cancelled or refunded invoice, and a rental's line, are left as they are.
-- Internal. Answers [{sale_no, state, what}], state: waiting_off, back, stays, raised, moved, repriced.$n$,
$n$  -- 498, 500: every sale not cancelled follows the invoice's customer and store.
  for r in select s.id, s.sale_no, s.special_product_id, s.customer_id, s.store_id,
                  (s.warehouse_id is not null or s.source_store_id is not null or s.supplier_id is not null) as is_out
             from public.special_sales s
            where s.invoice_id = p_invoice_id and s.status <> 'cancelled'
              and (s.customer_id, s.store_id) is distinct from (v_inv.customer_id, v_inv.store_id)$n$,
$n$      'what', r.sale_no || ': ' || public.special_product_name(r.special_product_id)
        || case when r.is_out then ', already released, now shows ' else ' moves to ' end
        || concat_ws(' and ',
             case when v_inv.customer_id is distinct from r.customer_id
                  then coalesce((select c.full_name from public.customers c where c.id = v_inv.customer_id), 'the invoice''s customer') end,
             case when v_inv.store_id is distinct from r.store_id
                  then coalesce((select t.name from public.stores t where t.id = v_inv.store_id), 'the invoice''s store') end)
        || case when r.is_out then '; no stock moves' else '' end));
  end loop;

  -- 500: and each takes its line's price.
  for r in select s.id, s.sale_no, s.special_product_id, s.quantity, s.unit_price, s.total_amount,
                  round(coalesce(it.unit_price, 0), 2) as line_price
             from public.special_sales s
             join public.invoice_items it on it.id = s.invoice_item_id and it.invoice_id = s.invoice_id
            where s.invoice_id = p_invoice_id and s.status <> 'cancelled'
              and it.line_kind::text = 'special_product' and it.special_product_id = s.special_product_id
              and (s.unit_price, s.total_amount) is distinct from
                  (round(coalesce(it.unit_price, 0), 2), round(coalesce(it.unit_price, 0), 2) * s.quantity)
            order by s.sale_no for update of s
  loop
    update public.special_sales
       set unit_price = r.line_price, total_amount = r.line_price * r.quantity,
           notes = case when strpos(coalesce(notes, ''), 'Follows invoice ' || coalesce(v_inv.invoice_no, '') || ' as corrected: ' || v_reason) > 0 then notes
                        else concat_ws(E'\n', notes, 'Follows invoice ' || coalesce(v_inv.invoice_no, '') || ' as corrected: ' || v_reason) end
     where id = r.id;
    perform public.write_audit_ex('special_sales', r.id, 'special_sale_price_follows_invoice',
      jsonb_build_object('unit_price', r.unit_price, 'total_amount', r.total_amount),
      jsonb_build_object('unit_price', r.line_price, 'total_amount', r.line_price * r.quantity, 'doc_no', r.sale_no, 'invoice_id', p_invoice_id),
      'special', v_reason, v_inv.store_id);
    v_list := v_list || jsonb_build_array(jsonb_build_object('sale_no', r.sale_no, 'state', 'repriced',
      'what', r.sale_no || ': ' || public.special_product_name(r.special_product_id)
        || ' now shows S$' || to_char(r.line_price * r.quantity, 'FM999999990.00')
        || ', was S$' || to_char(r.total_amount, 'FM999999990.00')));
  end loop;
  return v_list;$n$,
$n$    elsif coalesce(p_header->>'benefit_action','') = ''
          and exists (select 1 from public.invoice_transferable_benefits(p_invoice_id)) then  -- 500: only when the save would ask
      v_reviews := v_reviews || jsonb_build_array(jsonb_build_object(
        'area','benefits',$n$];

  -- Relied on, not changed (production now)
  c_relied constant text[] := array[
    'correct_invoice(uuid,jsonb,jsonb,text,uuid)',
    'invoice_line_matches(uuid,jsonb)',
    'invoice_transferable_benefits(uuid)',
    'special_docs_awaiting_fulfilment()',
    'return_released_special_stock(uuid,uuid,integer,integer,integer,uuid,text,text)',
    'fulfil_special_doc(text,uuid,uuid,text)',
    'release_special_sale_to_supplier(uuid,uuid,text)'];
  c_relied_md5 constant text[] := array[
    'cea93a5dd73d429f6437f4c9a8fcaa52',
    '0c32f7c591efb9864ff5b1cb2201b744',
    '1546de1f83d970424d26e65941f4dcb8',
    'fdaf5aca81c63cc99f8fddcfcf10564c',
    '13c9f26bd2c3c275dcee559a22caa8e0',
    'f21b8f6e42e7f17aa8c15b7ab0976935',
    'aaea37ea6d5b2c00e24738c678028b66'];

  v_path text := current_setting('search_path');
  v_def text[] := array_fill(null::text, array[2]);
  v_make boolean[] := array_fill(false, array[2]);
  v_acl text[] := array_fill(null::text, array[2]);
  d text; i int;
  -- the self-test's made-up records
  t_sfx text; t_base int; t_owner uuid; t_store uuid; t_store2 uuid; t_wh uuid; t_cust uuid; t_cust2 uuid; t_prd uuid; t_sp uuid; t_inv uuid; t_item uuid;
  t_a uuid; t_b uuid; t_c uuid; t_got jsonb; t_states text; t_pv jsonb;
begin
  -- Definitions are read and compared with public alone on the search path.
  perform set_config('search_path', 'public', true);

  -- 1. Checks: nothing is changed before all of them pass
  for i in 1 .. cardinality(c_relied) loop
    if to_regprocedure('public.' || c_relied[i]) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) <> c_relied_md5[i] then
      raise exception '500: public.% is missing or not the version this was tested against. Re-read it and re-test before applying.', c_relied[i];
    end if;
  end loop;

  -- The functions it patches: BEFORE (patched) or AFTER (left alone).
  for i in 1 .. cardinality(c_sig) loop
    if to_regprocedure('public.' || c_sig[i]) is null then raise exception '500: public.% is missing', c_sig[i]; end if;
    d := pg_get_functiondef(to_regprocedure('public.' || c_sig[i]));
    v_acl[i] := (select coalesce(string_agg(x::text, ',' order by x::text), '')
                   from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i]));
    if md5(d) = c_after[i] then
      raise notice '500: public.% is already this version; left alone', c_sig[i];
    elsif md5(d) = c_before[i] then
      v_make[i] := true;
      v_def[i] := d;
    else
      raise exception '500: public.% is not the version this was tested against (md5 %). Re-read it and re-test before applying.', c_sig[i], md5(d);
    end if;
  end loop;

  -- Each patch's text is found exactly once, and gives the tested text.
  for i in 1 .. cardinality(c_fn) loop
    if v_make[c_fn[i]] then
      if (length(v_def[c_fn[i]]) - length(replace(v_def[c_fn[i]], c_anchor[i], ''))) / length(c_anchor[i]) <> 1 then
        raise exception '500: patch % does not find its text exactly once in public.%', i, c_sig[c_fn[i]]; end if;
      v_def[c_fn[i]] := replace(v_def[c_fn[i]], c_anchor[i], c_new[i]);
    end if;
  end loop;
  for i in 1 .. cardinality(c_sig) loop
    if v_make[i] and md5(v_def[i]) <> c_after[i] then
      raise exception '500: the patched text of public.% is not the tested one (md5 %)', c_sig[i], md5(v_def[i]); end if;
  end loop;

  -- 2. Install
  for i in 1 .. cardinality(c_sig) loop
    if v_make[i] then execute v_def[i]; end if;
  end loop;

  -- 3. Checks after installing
  for i in 1 .. cardinality(c_sig) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_sig[i]))) <> c_after[i] then
      raise exception '500: public.% was installed with an md5 other than the tested one', c_sig[i]; end if;
    -- compared as sets: production lists them in another order than a local copy
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i])) is distinct from v_acl[i] then
      raise exception '500: the grants of public.% changed', c_sig[i]; end if;
  end loop;

  -- 4. Self-test, in a block that is always undone
  -- Made-up records only ("500 Check", @example.invalid, fictional +61 2 5550 phones); the
  -- invoice and its sales are written straight to their tables with their own numbers, so
  -- no sale number is used, and no payment is recorded. It ends by raising P0500, which
  -- undoes all it wrote.
  begin
    t_sfx := lower(substr(md5(gen_random_uuid()::text), 1, 8));
    -- Fictional phones no customer holds, in use or deleted (range scans of the two partial phone indexes, as 486's)
    select min(g) into t_base from generate_series(2000, 9980, 10) g
     where not exists (select 1 from public.customers c
                        where c.deleted_at is null and public.normalize_customer_phone(c.phone)
                              between '+6125550' || lpad(g::text, 4, '0') and '+6125550' || lpad((g + 9)::text, 4, '0'))
       and not exists (select 1 from public.customers c
                        where c.deleted_at is not null and public.normalize_customer_phone(c.phone)
                              between '+6125550' || lpad(g::text, 4, '0') and '+6125550' || lpad((g + 9)::text, 4, '0'));
    if t_base is null then raise exception '500: the self-test found no free fictional phone'; end if;
    insert into auth.users (id, email) values (gen_random_uuid(), '500chk-owner-' || t_sfx || '@example.invalid') returning id into t_owner;
    insert into public.profiles (id, full_name, email, role, is_active)
    values (t_owner, '500 Check Owner', '500chk-owner-' || t_sfx || '@example.invalid', 'owner', true);
    perform set_config('request.jwt.claim.sub', t_owner::text, true);
    perform set_config('request.jwt.claim.role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', t_owner, 'role', 'authenticated')::text, true);
    insert into public.stores (name, code, country_code) values ('500 Check ' || t_sfx, '500-' || t_sfx, 'SG') returning id into t_store;
    insert into public.stores (name, code, country_code) values ('500 Check B ' || t_sfx, '500B-' || t_sfx, 'SG') returning id into t_store2;
    insert into public.warehouses (name, code) values ('500 Check ' || t_sfx, '500-' || t_sfx) returning id into t_wh;
    insert into public.customers (full_name, phone) values ('500 Check', '+6125550' || lpad(t_base::text, 4, '0')) returning id into t_cust;
    insert into public.customers (full_name, phone) values ('500 Check Other', '+6125550' || lpad((t_base + 1)::text, 4, '0')) returning id into t_cust2;
    insert into public.products (name, sku, product_type) values ('500 Check ' || t_sfx, '500-P-' || t_sfx, 'third_party') returning id into t_prd;
    insert into public.warehouse_inventory (warehouse_id, product_id, current_qty) values (t_wh, t_prd, 5);
    t_sp := public.upsert_special_product_from_product(null, t_prd, 100);
    insert into public.invoices (invoice_no, store_id, customer_id, created_by, status, total_amount)
    values ('500-CHECK-' || t_sfx, t_store, t_cust, t_owner, 'paid', 300) returning id into t_inv;
    insert into public.invoice_items (invoice_id, line_kind, special_product_id, quantity, unit_price, line_total)
    values (t_inv, 'special_product', t_sp, 3, 100, 300) returning id into t_item;
    insert into public.special_sales (sale_no, special_product_id, quantity, unit_price, total_amount, status, notes, invoice_id, invoice_item_id, store_id, customer_id, sold_by)
    values ('500-CHECK-A-' || t_sfx, t_sp, 1, 100, 100, 'pending', '500 self-test', t_inv, t_item, t_store, t_cust, t_owner) returning id into t_a;
    insert into public.special_sales (sale_no, special_product_id, quantity, unit_price, total_amount, status, notes, invoice_id, invoice_item_id, store_id, customer_id, sold_by)
    values ('500-CHECK-B-' || t_sfx, t_sp, 1, 100, 100, 'pending', '500 self-test', t_inv, t_item, t_store, t_cust, t_owner) returning id into t_b;
    insert into public.special_sales (sale_no, special_product_id, quantity, unit_price, total_amount, status, notes, invoice_id, invoice_item_id, store_id, customer_id, sold_by)
    values ('500-CHECK-C-' || t_sfx, t_sp, 1, 100, 100, 'cancelled', '500 self-test', t_inv, t_item, t_store, t_cust, t_owner) returning id into t_c;
    perform public.fulfil_special_doc('special_sale', t_a, t_wh, 'warehouse');

    -- Corrected to another customer, another store and another price: the released and the
    -- waiting sale follow, the cancelled one does not, and no stock moves.
    update public.invoices set customer_id = t_cust2, store_id = t_store2 where id = t_inv;
    update public.invoice_items set unit_price = 80, line_total = 240 where id = t_item;
    t_got := public.invoice_special_sales_follow_lines(t_inv, '[]'::jsonb, '500 self-test', gen_random_uuid());
    t_states := (select string_agg(e->>'state', ',') from jsonb_array_elements(t_got) e);
    if t_states is distinct from 'moved,moved,repriced,repriced' then
      raise exception '500: the sales did not follow as expected: %', t_got; end if;
    if t_got->0->>'what' not like '%, already released, now shows 500 Check Other and 500 Check B %; no stock moves'
       or t_got->1->>'what' not like '% moves to 500 Check Other and 500 Check B %'
       or t_got->2->>'what' not like '% now shows S$80.00, was S$100.00' then
      raise exception '500: the summary''s words are wrong: %', t_got; end if;
    if exists (select 1 from public.special_sales s where s.id in (t_a, t_b)
                and (s.customer_id, s.store_id, s.unit_price, s.total_amount) is distinct from (t_cust2, t_store2, 80::numeric, 80::numeric)) then
      raise exception '500: a sale did not take the invoice''s customer, store and price'; end if;
    if exists (select 1 from public.special_sales s where s.id = t_c
                and (s.customer_id, s.store_id, s.unit_price, s.total_amount) is distinct from (t_cust, t_store, 100::numeric, 100::numeric)) then
      raise exception '500: a cancelled sale was changed'; end if;
    if (select warehouse_id from public.special_sales where id = t_a) is distinct from t_wh
       or (select current_qty from public.warehouse_inventory where warehouse_id = t_wh and product_id = t_prd) <> 4 then
      raise exception '500: following moved stock, or lost where the machine left from'; end if;
    t_got := public.invoice_special_sales_follow_lines(t_inv, '[]'::jsonb, '500 self-test', gen_random_uuid());
    if t_got <> '[]'::jsonb then raise exception '500: following twice did something: %', t_got; end if;

    -- A customer change on an invoice with no benefits no longer asks about them.
    t_pv := public.preview_invoice_correction(t_inv, jsonb_build_object('items', jsonb_build_array(jsonb_build_object(
              'invoice_item_id', t_item, 'kind', 'special_product', 'special_product_id', t_sp, 'quantity', 3)), 'customer_id', t_cust));
    if exists (select 1 from jsonb_array_elements(t_pv->'needs_review') e where e->>'area' = 'benefits') then
      raise exception '500: the summary still asks about benefits the invoice does not have: %', t_pv->'needs_review'; end if;

    raise exception using errcode = 'P0500', message = '500: self-test done, undone';
  exception when sqlstate 'P0500' then null;
  end;

  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
