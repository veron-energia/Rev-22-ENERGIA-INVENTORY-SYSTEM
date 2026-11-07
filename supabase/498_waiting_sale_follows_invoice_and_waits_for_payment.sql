-- 498_waiting_sale_follows_invoice_and_waits_for_payment.sql
--
-- A SPECIAL SALE STILL WAITING FOLLOWS ITS INVOICE'S CUSTOMER AND STORE, AND IS NOT RELEASED
-- WHILE ITS INVOICE OWES MONEY
-- (the user, 7 Nov 2026: asked which of these two to fix next, both, "Waiting sale follows
-- customer" and "Waiting sale waits for payment")
--
-- (The number 498 is this file's name, its errors' prefix, its self-test's error code P0498,
-- its suite's and its UNDO's; if it changes at commit, change it in these places alone.)
--
-- WHAT WAS WRONG
--
--   1. A correction of an invoice's customer or store left the sale waiting for a warehouse
--      with the old ones, so the Special page named the wrong customer and its WhatsApp and
--      email buttons used that customer's details, and its receipt had the wrong store. A
--      rental waiting does follow (458).
--   2. A sale waiting could be released while its invoice owed money: an invoice raised by a
--      correction (497 lets a raised quantity join the waiting list), or a payment taken back.
--      A rental waits for the payment (458). A sale is raised only once its invoice is paid
--      (393), so these are the two ways one can wait on an invoice that owes. Both release
--      paths: a warehouse or store (fulfil_special_doc), and a supplier (494,
--      release_special_sale_to_supplier).
--   Production, 7 Nov 2026, read only: no sale waiting, so nothing to repair and no figure wrong.
--
-- WHAT THIS DOES
--
--   1. invoice_special_sales_follow_lines (497): a sale still waiting takes the invoice's
--      customer and store whenever they differ, with a note on the sale and an Audit Log
--      entry, and the correction summary says so. correct_invoice now calls it when the
--      customer or the store changed, as well as when the lines did.
--   2. fulfil_special_doc and release_special_sale_to_supplier refuse a sale whose invoice is
--      unpaid or part-paid with money owing, in the rental's words: "SPS-... cannot be released
--      yet: its invoice INV-... has S$... owing. Take the payment first, then release it."
--      A sale with no invoice has nothing to wait for. The supplier path now takes the invoice
--      first, shared, as the warehouse path does (496), so this check cannot pass while a
--      correction of that invoice is saving.
--
-- WHAT THIS DOES NOT DO
--
--   A sale already released, or sent by a supplier, keeps its customer and store, and so its
--   receipt and its WhatsApp and email buttons: the user was asked about a sale still waiting
--   (a rental out refuses the move outright, 458). A cancelled sale, and every sale of a
--   cancelled or refunded invoice, is left as it is. No page changes: the summary shows
--   whatever the correction answers, and the Special page shows the refusal.
--
-- UNDO: scripts/special/undo-498.sql (refuses unless each function is 498's version; sales that
-- already moved stay moved). Undo 498 before 497. A later migration changing these functions
-- must pin 498's AFTER md5s below.
--
-- One transaction with its history row, by the usual wrapper; nothing else is written.

do $mig$
declare
  -- The functions this patches: BEFORE (production now) and AFTER md5s
  c_sig constant text[] := array[
    'invoice_special_sales_follow_lines(uuid,jsonb,text,uuid)',
    'correct_invoice(uuid,jsonb,jsonb,text,uuid)',
    'fulfil_special_doc(text,uuid,uuid,text)',
    'release_special_sale_to_supplier(uuid,uuid,text)'];
  c_before constant text[] := array[
    '630cd846df0cb44a2b6038e83a46a18d',
    '9aac5395dd18fd8349727d6c8aa0c633',
    '9b4520efc9d06b04360bacc2c035215b',
    '15b36ba68fd7b70a1361e80f5e5fad4e'];
  c_after constant text[] := array[
    '3cf6cfd8a22e5776e7b77e8d5ff3753d',
    'cea93a5dd73d429f6437f4c9a8fcaa52',
    'f21b8f6e42e7f17aa8c15b7ab0976935',
    'aaea37ea6d5b2c00e24738c678028b66'];
  -- Each patch: which function (its place in c_sig), the text found exactly once
  -- in it, and the text put in its place. The UNDO file swaps them back.
  c_fn constant int[] := array[1, 1, 2, 3, 4, 4, 4];
  c_anchor constant text[] := array[
$a$--   * A cancelled or refunded invoice, and a rental's line, are left as they are.
-- Internal. Answers [{sale_no, state, what}], state: waiting_off, back, stays, raised.$a$,
$a$  end loop;
  return v_list;
end $function$$a$,
$a$ if not same_lines then
   v497_special := public.invoice_special_sales_follow_lines(i.id,v_snapshot->'items',p_reason,p_request_id);$a$,
$a$      raise exception '% cannot be released yet: its invoice % has S$% owing. Take the payment first, then release it.',
        v_no, v458_inv, to_char(v458_owing, 'FM999999990.00');
    end if;
  end if;$a$,
$a$  v_note text := nullif(btrim(coalesce(p_deliver_to, '')), '');$a$,
$a$  select * into v_sale from public.special_sales where id = p_sale_id
     and warehouse_id is null and source_store_id is null and supplier_id is null$a$,
$a$    raise exception '% cannot be released: %. It is no longer waiting for a warehouse.', v_sale.sale_no, v_problem;
  end if;$a$];
  c_new constant text[] := array[
$n$--   * 498 (the user, 7 Nov 2026): a sale still waiting takes the invoice's customer and
--     store whenever they differ, whichever line it is on. A released one keeps them:
--     the machine went to that customer from there.
--   * A cancelled or refunded invoice, and a rental's line, are left as they are.
-- Internal. Answers [{sale_no, state, what}], state: waiting_off, back, stays, raised, moved.$n$,
$n$  end loop;

  -- 498: a sale still waiting follows the invoice's customer and store.
  for r in select s.id, s.sale_no, s.special_product_id, s.customer_id, s.store_id
             from public.special_sales s
            where s.invoice_id = p_invoice_id and s.status <> 'cancelled'
              and s.warehouse_id is null and s.source_store_id is null and s.supplier_id is null
              and (s.customer_id, s.store_id) is distinct from (v_inv.customer_id, v_inv.store_id)
            order by s.sale_no for update
  loop
    update public.special_sales
       set customer_id = v_inv.customer_id, store_id = v_inv.store_id,
           notes = concat_ws(E'\n', notes, 'Follows invoice ' || coalesce(v_inv.invoice_no, '') || ' as corrected: ' || v_reason)
     where id = r.id;
    perform public.write_audit_ex('special_sales', r.id, 'special_sale_follows_invoice',
      jsonb_build_object('customer_id', r.customer_id, 'store_id', r.store_id),
      jsonb_build_object('customer_id', v_inv.customer_id, 'store_id', v_inv.store_id, 'doc_no', r.sale_no, 'invoice_id', p_invoice_id),
      'special', v_reason, v_inv.store_id);
    v_list := v_list || jsonb_build_array(jsonb_build_object('sale_no', r.sale_no, 'state', 'moved',
      'what', r.sale_no || ': ' || public.special_product_name(r.special_product_id) || ' moves to '
        || concat_ws(' and ',
             case when v_inv.customer_id is distinct from r.customer_id
                  then coalesce((select c.full_name from public.customers c where c.id = v_inv.customer_id), 'the invoice''s customer') end,
             case when v_inv.store_id is distinct from r.store_id
                  then coalesce((select t.name from public.stores t where t.id = v_inv.store_id), 'the invoice''s store') end)));
  end loop;
  return v_list;
end $function$$n$,
$n$ if not same_lines or (n.customer_id, n.store_id) is distinct from (i.customer_id, i.store_id) then  -- 498: a sale still waiting follows these too
   v497_special := public.invoice_special_sales_follow_lines(i.id,v_snapshot->'items',p_reason,p_request_id);$n$,
$n$      raise exception '% cannot be released yet: its invoice % has S$% owing. Take the payment first, then release it.',
        v_no, v458_inv, to_char(v458_owing, 'FM999999990.00');
    end if;
  end if;
  -- 498 (the user, 7 Nov 2026): and so does a special sale: raised once its invoice is
  -- paid, it can find itself on one that owes after a correction or a payment taken back.
  if p_doc_kind = 'special_sale' then
    select i.invoice_no, greatest(public.invoice_charge_total(i.id) - public.invoice_net_received(i.id), 0)
      into v458_inv, v458_owing
      from public.special_sales x join public.invoices i on i.id = x.invoice_id
     where x.id = p_doc_id and i.status in ('unpaid', 'partially_paid');
    if coalesce(v458_owing, 0) > 0 then
      raise exception '% cannot be released yet: its invoice % has S$% owing. Take the payment first, then release it.',
        v_no, v458_inv, to_char(v458_owing, 'FM999999990.00');
    end if;
  end if;$n$,
$n$  v_note text := nullif(btrim(coalesce(p_deliver_to, '')), '');
  v498_inv text; v498_owing numeric;  -- 498$n$,
$n$  -- 498: the invoice first, shared, as fulfil_special_doc takes it (496), so the check below
  -- and a correction or a payment of that invoice wait for one another.
  perform 1 from public.invoices v
   where v.id = (select s0.invoice_id from public.special_sales s0 where s0.id = p_sale_id)
     for share;
  select * into v_sale from public.special_sales where id = p_sale_id
     and warehouse_id is null and source_store_id is null and supplier_id is null$n$,
$n$    raise exception '% cannot be released: %. It is no longer waiting for a warehouse.', v_sale.sale_no, v_problem;
  end if;
  -- 498 (the user, 7 Nov 2026): it waits for its invoice to be paid in full, as fulfil_special_doc.
  select i.invoice_no, greatest(public.invoice_charge_total(i.id) - public.invoice_net_received(i.id), 0)
    into v498_inv, v498_owing
    from public.invoices i
   where i.id = v_sale.invoice_id and i.status in ('unpaid', 'partially_paid');
  if coalesce(v498_owing, 0) > 0 then
    raise exception '% cannot be released yet: its invoice % has S$% owing. Take the payment first, then release it.',
      v_sale.sale_no, v498_inv, to_char(v498_owing, 'FM999999990.00');
  end if;$n$];

  -- Relied on, not changed (production now)
  c_relied constant text[] := array[
    'preview_invoice_correction(uuid,jsonb)',
    'special_docs_awaiting_fulfilment()',
    'special_doc_invoice_problem(uuid,uuid)',
    'invoice_charge_total(uuid)',
    'invoice_net_received(uuid)',
    'create_special_docs_for_invoice(uuid)'];
  c_relied_md5 constant text[] := array[
    '13b0925c29bd8ca14d8d8b7bd961fef8',
    'fdaf5aca81c63cc99f8fddcfcf10564c',
    'be2b8ec5a4003a1dca34e17a82f89932',
    '8297147511ba285db2279598f3d727fb',
    'f256bea69b7defa38a950753bbc248da',
    '540b98385d9632abcc5fe35c23c00bb5'];

  v_path text := current_setting('search_path');
  v_def text[] := array_fill(null::text, array[4]);
  v_make boolean[] := array_fill(false, array[4]);
  v_acl text[] := array_fill(null::text, array[4]);
  d text; i int;
  -- the self-test's made-up records
  t_sfx text; t_base int; t_owner uuid; t_store uuid; t_store2 uuid; t_wh uuid; t_cust uuid; t_cust2 uuid; t_prd uuid; t_sp uuid; t_inv uuid; t_item uuid;
  t_a uuid; t_b uuid; t_got jsonb; t_msg text; t_sup uuid;
begin
  -- Definitions are read and compared with public alone on the search path.
  perform set_config('search_path', 'public', true);

  -- 1. Checks: nothing is changed before all of them pass
  for i in 1 .. cardinality(c_relied) loop
    if to_regprocedure('public.' || c_relied[i]) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) <> c_relied_md5[i] then
      raise exception '498: public.% is missing or not the version this was tested against. Re-read it and re-test before applying.', c_relied[i];
    end if;
  end loop;

  -- The functions it patches: BEFORE (patched) or AFTER (left alone).
  for i in 1 .. cardinality(c_sig) loop
    if to_regprocedure('public.' || c_sig[i]) is null then raise exception '498: public.% is missing', c_sig[i]; end if;
    d := pg_get_functiondef(to_regprocedure('public.' || c_sig[i]));
    v_acl[i] := (select coalesce(string_agg(x::text, ',' order by x::text), '')
                   from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i]));
    if md5(d) = c_after[i] then
      raise notice '498: public.% is already this version; left alone', c_sig[i];
    elsif md5(d) = c_before[i] then
      v_make[i] := true;
      v_def[i] := d;
    else
      raise exception '498: public.% is not the version this was tested against (md5 %). Re-read it and re-test before applying.', c_sig[i], md5(d);
    end if;
  end loop;

  -- Each patch's text is found exactly once, and gives the tested text.
  for i in 1 .. cardinality(c_fn) loop
    if v_make[c_fn[i]] then
      if (length(v_def[c_fn[i]]) - length(replace(v_def[c_fn[i]], c_anchor[i], ''))) / length(c_anchor[i]) <> 1 then
        raise exception '498: patch % does not find its text exactly once in public.%', i, c_sig[c_fn[i]]; end if;
      v_def[c_fn[i]] := replace(v_def[c_fn[i]], c_anchor[i], c_new[i]);
    end if;
  end loop;
  for i in 1 .. cardinality(c_sig) loop
    if v_make[i] and md5(v_def[i]) <> c_after[i] then
      raise exception '498: the patched text of public.% is not the tested one (md5 %)', c_sig[i], md5(v_def[i]); end if;
  end loop;

  -- 2. Install
  for i in 1 .. cardinality(c_sig) loop
    if v_make[i] then execute v_def[i]; end if;
  end loop;

  -- 3. Checks after installing
  for i in 1 .. cardinality(c_sig) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_sig[i]))) <> c_after[i] then
      raise exception '498: public.% was installed with an md5 other than the tested one', c_sig[i]; end if;
    -- compared as sets: production lists them in another order than a local copy
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i])) is distinct from v_acl[i] then
      raise exception '498: the grants of public.% changed', c_sig[i]; end if;
  end loop;

  -- 4. Self-test, in a block that is always undone
  -- Made-up records only ("498 Check", @example.invalid, fictional +61 2 5550 phones); the
  -- invoice and its sales are written straight to their tables with their own numbers, so
  -- no sale number is used, and no payment is recorded. It ends by raising P0498, which
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
    if t_base is null then raise exception '498: the self-test found no free fictional phone'; end if;
    insert into auth.users (id, email) values (gen_random_uuid(), '498chk-owner-' || t_sfx || '@example.invalid') returning id into t_owner;
    insert into public.profiles (id, full_name, email, role, is_active)
    values (t_owner, '498 Check Owner', '498chk-owner-' || t_sfx || '@example.invalid', 'owner', true);
    perform set_config('request.jwt.claim.sub', t_owner::text, true);
    perform set_config('request.jwt.claim.role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', t_owner, 'role', 'authenticated')::text, true);
    insert into public.stores (name, code, country_code) values ('498 Check ' || t_sfx, '498-' || t_sfx, 'SG') returning id into t_store;
    insert into public.stores (name, code, country_code) values ('498 Check B ' || t_sfx, '498B-' || t_sfx, 'SG') returning id into t_store2;
    insert into public.warehouses (name, code) values ('498 Check ' || t_sfx, '498-' || t_sfx) returning id into t_wh;
    insert into public.customers (full_name, phone) values ('498 Check', '+6125550' || lpad(t_base::text, 4, '0')) returning id into t_cust;
    insert into public.customers (full_name, phone) values ('498 Check Other', '+6125550' || lpad((t_base + 1)::text, 4, '0')) returning id into t_cust2;
    insert into public.products (name, sku, product_type) values ('498 Check ' || t_sfx, '498-P-' || t_sfx, 'third_party') returning id into t_prd;
    insert into public.warehouse_inventory (warehouse_id, product_id, current_qty) values (t_wh, t_prd, 5);
    t_sp := public.upsert_special_product_from_product(null, t_prd, 100);
    insert into public.invoices (invoice_no, store_id, customer_id, created_by, status)
    values ('498-CHECK-' || t_sfx, t_store, t_cust, t_owner, 'partially_paid') returning id into t_inv;
    insert into public.invoice_items (invoice_id, line_kind, special_product_id, quantity, unit_price, line_total)
    values (t_inv, 'special_product', t_sp, 2, 100, 200) returning id into t_item;
    update public.invoices set total_amount = 200 where id = t_inv;
    insert into public.special_sales (sale_no, special_product_id, quantity, unit_price, total_amount, status, notes, invoice_id, invoice_item_id, store_id, customer_id, sold_by)
    values ('498-CHECK-A-' || t_sfx, t_sp, 1, 100, 100, 'pending', '498 self-test', t_inv, t_item, t_store, t_cust, t_owner) returning id into t_a;
    insert into public.special_sales (sale_no, special_product_id, quantity, unit_price, total_amount, status, notes, invoice_id, invoice_item_id, store_id, customer_id, sold_by)
    values ('498-CHECK-B-' || t_sfx, t_sp, 1, 100, 100, 'pending', '498 self-test', t_inv, t_item, t_store, t_cust, t_owner) returning id into t_b;

    -- The invoice owes money: not released, from a warehouse, nor by a supplier.
    t_msg := null;
    begin perform public.fulfil_special_doc('special_sale', t_a, t_wh, 'warehouse');
    exception when others then t_msg := sqlerrm; end;
    if t_msg is null or t_msg not like '498-CHECK-A-% cannot be released yet: its invoice 498-CHECK-% has S$% owing. Take the payment first, then release it.' then
      raise exception '498: a sale was released while its invoice owed money: %', coalesce(t_msg, 'no refusal'); end if;
    if (select current_qty from public.warehouse_inventory where warehouse_id = t_wh and product_id = t_prd) <> 5 then
      raise exception '498: a refused release moved stock'; end if;
    insert into public.suppliers (name, phone) values ('498 Check ' || t_sfx, '+6125550' || lpad((t_base + 2)::text, 4, '0')) returning id into t_sup;
    insert into public.product_suppliers (product_id, supplier_id) values (t_prd, t_sup);
    perform public.set_special_product_consignment(t_sp, true);
    t_msg := null;
    begin perform public.release_special_sale_to_supplier(t_a, t_sup, null);
    exception when others then t_msg := sqlerrm; end;
    if t_msg is null or t_msg not like '%cannot be released yet: its invoice %' then
      raise exception '498: a sale was sent by a supplier while its invoice owed money: %', coalesce(t_msg, 'no refusal'); end if;

    -- Once nothing is owing it can be: the invoice is paid.
    update public.invoices set status = 'paid' where id = t_inv;
    perform public.fulfil_special_doc('special_sale', t_a, t_wh, 'warehouse');
    if (select status from public.special_sales where id = t_a) <> 'completed' then
      raise exception '498: a sale on a paid invoice was not released'; end if;

    -- The waiting one follows the invoice's customer and store; the released one does not.
    update public.invoices set customer_id = t_cust2, store_id = t_store2 where id = t_inv;
    t_got := public.invoice_special_sales_follow_lines(t_inv, '[]'::jsonb, '498 self-test', gen_random_uuid());
    if jsonb_array_length(t_got) <> 1 or t_got->0->>'state' <> 'moved' or t_got->0->>'sale_no' <> '498-CHECK-B-' || t_sfx
       or (select customer_id from public.special_sales where id = t_b) is distinct from t_cust2
       or (select store_id from public.special_sales where id = t_b) is distinct from t_store2
       or (select customer_id from public.special_sales where id = t_a) is distinct from t_cust
       or (select store_id from public.special_sales where id = t_a) is distinct from t_store
       or (select notes from public.special_sales where id = t_b) not like '%Follows invoice 498-CHECK-% as corrected: 498 self-test%' then
      raise exception '498: a waiting sale did not follow its invoice: %', t_got; end if;
    t_got := public.invoice_special_sales_follow_lines(t_inv, '[]'::jsonb, '498 self-test', gen_random_uuid());
    if t_got <> '[]'::jsonb then raise exception '498: following twice did something: %', t_got; end if;

    raise exception using errcode = 'P0498', message = '498: self-test done, undone';
  exception when sqlstate 'P0498' then null;
  end;

  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
