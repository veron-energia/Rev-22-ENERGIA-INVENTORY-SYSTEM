-- 500: every special sale not cancelled follows its invoice's customer and store and its line's
-- price, and a customer change no longer warns about benefits the invoice does not have (the
-- user, 7 Nov 2026), through the app's own calls.
--
--   I  500 installs (two functions replaced, none added), a second run changes nothing, its
--      self-test leaves no row.
--   A  The customer: a machine released, from a warehouse or a store, or sent by a supplier
--      follows, in words of its own; where it left from, stock and movements stay; a cancelled
--      one stays; only once.
--   B  The store: the same.
--   F  After it: a machine that followed still comes back by a refund, a lowered line, a cancellation.
--   P  A corrected price: released, waiting and supplier-sent sales show it; the summary says so;
--      no stock and no money moves; a dearer price makes the invoice owe; another machine, another
--      line, a cancelled sale, a discount and a rental's line stay out of it.
--   C  A cancelled or refunded invoice is left as it is; a rental out still refuses.
--   W  The benefits warning: none on an invoice with no benefits, and with benefits as before.
--   S  Grants of the patched functions are unchanged.
--   U  UNDO puts the two functions back to production's texts; 500 again puts them in.
--
-- Run on a copy of production at 498 (createdb -T of a template equal to it; never the
-- template itself):
--   psql -X -d <copy> -v ON_ERROR_STOP=1 -f scripts/special/tests/sales-follow-invoice-500.sql
-- (with -v skip_install=1 where 500 is in). Every check runs, then the file fails if any did.
-- Everything is rolled back. Every name, phone and email is invented (+61 2 5550 ....,
-- @example.invalid); the repository is public.
-- Note for edits: a check that calls a function and reads what it changed in ONE expression
-- reads the snapshot from before the call; call first, then check.
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '10s';
create temp table failed(n serial, msg text);
create function pg_temp.check(ok boolean, msg text) returns void language plpgsql as
$$begin
  if ok is distinct from true then insert into failed(msg) values (msg); raise warning 'FAIL %', msg;
  else raise notice 'PASS  %', msg; end if;
end$$;
create function pg_temp.err(q text) returns text language plpgsql as
$$begin execute q; return 'ok'; exception when others then return sqlerrm; end$$;
create function pg_temp.fp() returns text language sql set search_path = public as
$$ select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.oid::regprocedure::text)) || ' ' || count(*)
     from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p') $$;
create function pg_temp.md5_of(sig text) returns text language sql set search_path = public as
$$ select md5(pg_get_functiondef(to_regprocedure('public.' || sig))) $$;

create temp table fx(k text primary key, v uuid);
create function pg_temp.fx(key text) returns uuid language sql as $$ select v from fx where k = key $$;
create function pg_temp.as_user(key text) returns void language sql as
$$ select set_config('request.jwt.claim.sub', coalesce(pg_temp.fx(key)::text, ''), true),
          set_config('request.jwt.claim.role', case when key is null then 'anon' else 'authenticated' end, true),
          set_config('request.jwt.claims', '', true) $$;

-- ═════ I Installs ═════
create temp table acl_before as
  select p.oid::regprocedure::text as sig, (select coalesce(string_agg(x::text, ',' order by x::text), '') from unnest(p.proacl) x) as acl
    from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('invoice_special_sales_follow_lines', 'preview_invoice_correction');
create temp table before_install as select pg_temp.fp() f;
\if :{?skip_install}
do $$ begin raise notice 'NOTE  I1-I2 are skipped: 500 is in already'; end $$;
\else
\ir ../../../supabase/500_special_sales_follow_invoice_customer_store_price.sql
create temp table after_first as select pg_temp.fp() f;
\ir ../../../supabase/500_special_sales_follow_invoice_customer_store_price.sql
select pg_temp.check((select f from after_first) = pg_temp.fp()
    and split_part(pg_temp.fp(), ' ', 2) = split_part((select f from before_install), ' ', 2),
  'I1 500 adds no function, and a second run changes nothing: ' || pg_temp.fp());
select pg_temp.check(not exists (select 1 from public.special_sales where sale_no like '500-CHECK%')
    and not exists (select 1 from public.invoices where invoice_no like '500-CHECK%')
    and not exists (select 1 from auth.users where email like '500chk-%'),
  'I2 its self-test left no sale, no invoice and no login');
\endif

-- ═════ Fixtures (invented) ═════
do $$
declare sfx text := lower(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
  k text; u uuid; st uuid; st2 uuid; wh uuid; wh2 uuid; v uuid; ph text;
begin
  foreach k in array array['owner', 'manager', 'staff', 'other'] loop
    u := gen_random_uuid();
    insert into auth.users(id, email) values (u, 'c500-' || k || '-' || sfx || '@example.invalid');
    insert into public.profiles(id, full_name, email, role, is_active)
      values (u, 'C500 ' || k, 'c500-' || k || '-' || sfx || '@example.invalid',
              (case k when 'other' then 'staff' else k end)::public.user_role, true);
    insert into fx values (k, u);
  end loop;
  perform pg_temp.as_user('owner');
  insert into public.stores(name, code, country_code) values ('C500 Store ' || sfx, 'C500' || sfx, 'SG') returning id into st; insert into fx values ('store', st);
  insert into public.stores(name, code, country_code) values ('C500 Store B ' || sfx, 'C500B' || sfx, 'SG') returning id into st2; insert into fx values ('store2', st2);
  insert into public.warehouses(name, code) values ('C500 Warehouse ' || sfx, 'C500W' || sfx) returning id into wh; insert into fx values ('wh', wh);
  insert into public.warehouses(name, code) values ('C500 Warehouse B ' || sfx, 'C500X' || sfx) returning id into wh2; insert into fx values ('wh2', wh2);
  insert into public.payment_methods(name, is_active) values ('C500 Cash ' || sfx, true) returning id into v; insert into fx values ('cash', v);
  insert into public.user_store_assignments(user_id, store_id) values (pg_temp.fx('manager'), st), (pg_temp.fx('staff'), st), (pg_temp.fx('other'), st2);
  select '+6125550' || lpad(n::text, 4, '0') into ph from generate_series(1000, 9999) n
   where not exists (select 1 from public.customers c where public.normalize_customer_phone(c.phone) = '+6125550' || lpad(n::text, 4, '0'))
   order by n limit 1;
  insert into public.customers(full_name, phone) values ('C500 Buyer', ph) returning id into v; insert into fx values ('buyer', v);
  insert into public.customers(full_name, phone) values ('C500 Second Buyer', '+61255509904') returning id into v; insert into fx values ('buyer2', v);
end $$;

-- A special product (S$1,000) over a third-party product holding 10 at the warehouse ('wh', 'wh2') or the store ('store').
create function pg_temp.mkspecial(tag text, loc text default 'wh') returns void language plpgsql as
$$declare p uuid; sp uuid;
begin
  insert into public.products(name, sku, product_type) values ('C500 ' || tag, 'C500-' || tag, 'third_party') returning id into p;
  if loc = 'wh' then insert into public.warehouse_inventory(warehouse_id, product_id, current_qty) values (pg_temp.fx('wh'), p, 10);
  elsif loc = 'wh2' then insert into public.warehouse_inventory(warehouse_id, product_id, current_qty) values (pg_temp.fx('wh2'), p, 10);
  else insert into public.store_inventory(store_id, product_id, current_qty) values (pg_temp.fx('store'), p, 10); end if;
  sp := public.upsert_special_product_from_product(null, p, 1000, 0, 0, 100, 0, 0);
  insert into fx values ('p_' || tag, p), ('sp_' || tag, sp);
end$$;
create function pg_temp.mkplain(tag text) returns void language plpgsql as
$$declare p uuid;
begin
  insert into public.products(name, sku, product_type) values ('C500 ' || tag, 'C500-' || tag, 'own') returning id into p;
  insert into public.store_product_prices(store_id, product_id, selling_price) values (pg_temp.fx('store'), p, 100);
  insert into public.store_inventory(store_id, product_id, current_qty) values (pg_temp.fx('store'), p, 10);
  insert into fx values ('p_' || tag, p);
end$$;
create function pg_temp.sale_line(tag text, qty int default 1) returns jsonb language sql as
$$ select jsonb_build_object('kind', 'special_product', 'special_product_id', pg_temp.fx('sp_' || tag), 'quantity', qty) $$;
create function pg_temp.prod_line(tag text, qty int default 1) returns jsonb language sql as
$$ select jsonb_build_object('kind', 'product', 'product_id', pg_temp.fx('p_' || tag), 'quantity', qty) $$;
create function pg_temp.mk(items jsonb) returns uuid language sql as
$$ select public.create_invoice_with_details(pg_temp.fx('store'), pg_temp.fx('buyer'), items,
            jsonb_build_object('business_date', public.sg_today()::text)) $$;
create function pg_temp.pay(inv uuid, amount numeric default null) returns void language sql as
$$ select public.pay_invoice(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.fx('cash'),
     'amount', coalesce(amount, public.invoice_charge_total(inv) - public.invoice_net_received(inv))))) $$;
create function pg_temp.sales(inv uuid) returns uuid[] language sql as
$$ select coalesce(array_agg(id order by sale_no), '{}') from public.special_sales where invoice_id = inv $$;
create function pg_temp.release(sale uuid, loc text default 'wh') returns void language sql as
$$ select public.fulfil_special_doc('special_sale', sale, pg_temp.fx(loc), case when loc in ('store', 'store2') then 'store' else 'warehouse' end) $$;
create function pg_temp.mv(sale uuid) returns uuid language sql as
$$ select release_movement_id from public.special_sales where id = sale $$;
create function pg_temp.at_wh(tag text, wh text default 'wh') returns bigint language sql as
$$ select coalesce((select sum(current_qty) from public.warehouse_inventory where product_id = pg_temp.fx('p_' || tag) and warehouse_id = pg_temp.fx(wh)), 0) $$;
create function pg_temp.at_store(tag text) returns bigint language sql as
$$ select coalesce((select sum(current_qty) from public.store_inventory where product_id = pg_temp.fx('p_' || tag) and store_id = pg_temp.fx('store')), 0) $$;
create function pg_temp.status_of(sale uuid) returns text language sql as
$$ select status from public.special_sales where id = sale $$;
create function pg_temp.back(sale uuid) returns boolean language sql as
$$ select coalesce(stock_returned, false) from public.special_sales where id = sale $$;
create function pg_temp.notes_of(sale uuid) returns text language sql as
$$ select notes from public.special_sales where id = sale $$;
create function pg_temp.sale_no_of(sale uuid) returns text language sql as
$$ select sale_no from public.special_sales where id = sale $$;
create function pg_temp.line_of(inv uuid, tag text) returns uuid language sql as
$$ select id from public.invoice_items where invoice_id = inv and special_product_id = pg_temp.fx('sp_' || tag) limit 1 $$;
-- The corrected invoice's special line, kept (by its id) with a quantity, and a machine (by tag).
create function pg_temp.keep(line uuid, tag text, qty int default 1) returns jsonb language sql as
$$ select jsonb_build_object('invoice_item_id', line, 'kind', 'special_product', 'special_product_id', pg_temp.fx('sp_' || tag), 'quantity', qty) $$;
create function pg_temp.keep_plain(line uuid, tag text, qty int default 1) returns jsonb language sql as
$$ select jsonb_build_object('invoice_item_id', line, 'kind', 'product', 'product_id', pg_temp.fx('p_' || tag), 'quantity', qty) $$;
create function pg_temp.correct(inv uuid, items jsonb, req uuid default gen_random_uuid()) returns jsonb language sql as
$$ select public.correct_invoice(inv, items, '{}'::jsonb, 'Check correction', req) $$;
create function pg_temp.preview(inv uuid, items jsonb) returns jsonb language sql as
$$ select public.preview_invoice_correction(inv, jsonb_build_object('items', items)) $$;
-- What the answer says, as one text; and the states in order.
create function pg_temp.said(res jsonb) returns text language sql as
$$ select coalesce(string_agg(e->>'what', ' | '), '') from jsonb_array_elements(coalesce(res->'special', '[]')) e $$;
create function pg_temp.states(res jsonb) returns text language sql as
$$ select coalesce(string_agg(e->>'state', ','), '') from jsonb_array_elements(coalesce(res->'special', '[]')) e $$;
create function pg_temp.answer(mv uuid, s int, d int, n int) returns jsonb language sql as
$$ select jsonb_build_array(jsonb_build_object('movement_id', mv, 'sellable_quantity', s, 'damaged_quantity', d, 'not_returned_quantity', n)) $$;
-- The payment a refund can come from, as the screen offers it (one a correction replaced is not).
create function pg_temp.current_payment(inv uuid) returns uuid language sql as
$$ select p.id from public.invoice_payments p where p.invoice_id = inv and p.entry_kind <> 'correction_reversal'
      and not exists (select 1 from public.invoice_payments v where v.corrects_payment_id = p.id and v.entry_kind = 'correction_reversal')
    order by public.invoice_payment_remaining(p.id) desc limit 1 $$;
create function pg_temp.refund_line(inv uuid, item uuid, amt numeric, stock jsonb, req uuid default gen_random_uuid()) returns jsonb language plpgsql as
$$declare pay uuid;
begin
  perform pg_temp.as_user('owner');
  pay := pg_temp.current_payment(inv);
  return public.refund_invoice_recorded(inv,
    jsonb_build_array(jsonb_build_object('invoice_item_id', item, 'amount', coalesce(amt, public.invoice_payment_remaining(pay)))),
    jsonb_build_array(jsonb_build_object('payment_id', pay, 'amount', coalesce(amt, public.invoice_payment_remaining(pay)))),
    stock, 'Check refund', req);
end$$;

-- The payment corrected down to what the lowered invoice charges (the money handed back), as the correction form does it.
create function pg_temp.pay_down(inv uuid) returns void language sql as
$$ select public.correct_invoice_payment(pg_temp.current_payment(inv),
     public.invoice_charge_total(inv), public.sg_today(), pg_temp.fx('cash'), 'Check money handed back', gen_random_uuid()) $$;

create function pg_temp.cust_of(sale uuid) returns uuid language sql as
$$ select customer_id from public.special_sales where id = sale $$;
create function pg_temp.store_of(sale uuid) returns uuid language sql as
$$ select store_id from public.special_sales where id = sale $$;
-- A supplier for one special product, ticked as consignment (494).
create function pg_temp.supplier_for(tag text) returns void language plpgsql as
$$declare sup uuid;
begin
  insert into public.suppliers(name, phone) values ('C500 Supplier ' || tag, '+6125550' || lpad((9000 + (select count(*) from fx))::text, 4, '0')) returning id into sup;
  insert into public.product_suppliers(product_id, supplier_id) values (pg_temp.fx('p_' || tag), sup);
  perform public.set_special_product_consignment(pg_temp.fx('sp_' || tag), true);
  insert into fx values ('sup_' || tag, sup);
end$$;

-- ═════ A A machine out follows the customer and store ═════
do $$
declare inv uuid; s uuid[]; res jsonb; line uuid; pv jsonb; e jsonb; mv0 uuid; wh0 uuid; n bigint; other uuid;
begin
  perform pg_temp.as_user('owner');
  perform pg_temp.mkspecial('a1');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('a1', 2))); perform pg_temp.pay(inv);
  s := pg_temp.sales(inv); line := pg_temp.line_of(inv, 'a1');
  perform pg_temp.release(s[1]);
  mv0 := pg_temp.mv(s[1]);
  n := (select count(*) from public.stock_movements where product_id = pg_temp.fx('p_a1'));

  -- The summary says it first, and changes nothing.
  pv := public.preview_invoice_correction(inv, jsonb_build_object('items', jsonb_build_array(pg_temp.keep(line, 'a1', 2)), 'customer_id', pg_temp.fx('buyer2')));
  select x into e from jsonb_array_elements(pv->'effects') x where x->>'area' = 'special_sales';
  perform pg_temp.check(e->'items'->0->>'what' = pg_temp.sale_no_of(s[1]) || ': C500 a1, already released, now shows C500 Second Buyer; no stock moves'
      and e->'items'->1->>'what' = pg_temp.sale_no_of(s[2]) || ': C500 a1 moves to C500 Second Buyer',
    'A1 the summary names both, the released one as released: ' || coalesce(e::text, 'no entry'));
  perform pg_temp.check(pg_temp.cust_of(s[1]) = pg_temp.fx('buyer') and pg_temp.cust_of(s[2]) = pg_temp.fx('buyer'), 'A2 and changes nothing');

  res := public.correct_invoice(inv, jsonb_build_array(pg_temp.keep(line, 'a1', 2)), jsonb_build_object('customer_id', pg_temp.fx('buyer2')), 'Wrong customer', gen_random_uuid());
  perform pg_temp.check(pg_temp.cust_of(s[1]) = pg_temp.fx('buyer2') and pg_temp.cust_of(s[2]) = pg_temp.fx('buyer2'), 'A3 saved: released and waiting both have the new customer');
  perform pg_temp.check(pg_temp.states(res) = 'moved,moved', 'A4 the answer has both: ' || pg_temp.said(res));
  perform pg_temp.check(pg_temp.status_of(s[1]) = 'completed' and pg_temp.mv(s[1]) = mv0 and (select warehouse_id from public.special_sales where id = s[1]) = pg_temp.fx('wh'),
    'A5 the released one is still released, from where it left');
  perform pg_temp.check(pg_temp.at_wh('a1') = 9 and (select count(*) from public.stock_movements where product_id = pg_temp.fx('p_a1')) = n
      and not exists (select 1 from public.special_sale_returns where invoice_id = inv), 'A6 no stock moves, no new movement, no return');
  perform pg_temp.check(pg_temp.notes_of(s[1]) like '%Follows invoice % as corrected: Wrong customer%', 'A7 a note on it');
  perform pg_temp.check(exists (select 1 from public.audit_logs a where a.action = 'special_sale_follows_invoice' and a.record_id = s[1]
        and a.old_data->>'customer_id' = pg_temp.fx('buyer')::text and a.new_data->>'customer_id' = pg_temp.fx('buyer2')::text), 'A8 the Audit Log has before and after');

  -- Only once, and the same request replays.
  res := public.correct_invoice(inv, jsonb_build_array(pg_temp.keep(line, 'a1', 2)), jsonb_build_object('customer_id', pg_temp.fx('buyer2'), 'notes', 'Only a note'), 'A note', gen_random_uuid());
  perform pg_temp.check(pg_temp.states(res) = '' and (select count(*) from public.audit_logs a where a.action = 'special_sale_follows_invoice' and a.record_id = s[1]) = 1, 'A9 a later save moves nothing');

  -- Released from a store, and sent by a supplier: the same, and where it came from stays.
  perform pg_temp.mkspecial('a10', 'store');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('a10'))); perform pg_temp.pay(inv);
  s := pg_temp.sales(inv); line := pg_temp.line_of(inv, 'a10');
  perform pg_temp.release(s[1], 'store');
  res := public.correct_invoice(inv, jsonb_build_array(pg_temp.keep(line, 'a10')), jsonb_build_object('customer_id', pg_temp.fx('buyer2')), 'Wrong customer', gen_random_uuid());
  perform pg_temp.check(pg_temp.cust_of(s[1]) = pg_temp.fx('buyer2') and (select source_store_id from public.special_sales where id = s[1]) = pg_temp.fx('store') and pg_temp.at_store('a10') = 9,
    'A10 released from a store: follows, and still from that store');
  perform pg_temp.mkspecial('a11');
  perform pg_temp.supplier_for('a11');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('a11'))); perform pg_temp.pay(inv);
  s := pg_temp.sales(inv); line := pg_temp.line_of(inv, 'a11');
  perform public.release_special_sale_to_supplier(s[1], pg_temp.fx('sup_a11'), 'Check Road');
  res := public.correct_invoice(inv, jsonb_build_array(pg_temp.keep(line, 'a11')), jsonb_build_object('customer_id', pg_temp.fx('buyer2'), 'store_id', pg_temp.fx('store2')), 'Wrong both', gen_random_uuid());
  perform pg_temp.check(pg_temp.cust_of(s[1]) = pg_temp.fx('buyer2') and pg_temp.store_of(s[1]) = pg_temp.fx('store2')
      and (select supplier_id from public.special_sales where id = s[1]) = pg_temp.fx('sup_a11') and (select deliver_to from public.special_sales where id = s[1]) = 'Check Road'
      and pg_temp.said(res) like '%, already released, now shows C500 Second Buyer and C500 Store B %; no stock moves',
    'A11 sent by a supplier: follows customer and store; the supplier and the address stay: ' || pg_temp.said(res));

  -- A cancelled one, and its stock back, stays as it ended.
  perform pg_temp.mkspecial('a12');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('a12', 2))); perform pg_temp.pay(inv);
  s := pg_temp.sales(inv); line := pg_temp.line_of(inv, 'a12');
  perform pg_temp.release(s[1]); perform pg_temp.release(s[2]);
  res := pg_temp.correct(inv, jsonb_build_array(pg_temp.keep(line, 'a12', 1)));
  perform pg_temp.check(pg_temp.status_of(s[2]) = 'cancelled' and pg_temp.back(s[2]), 'A12 lowered: the newest is back');
  res := public.correct_invoice(inv, jsonb_build_array(pg_temp.keep(line, 'a12', 1)), jsonb_build_object('customer_id', pg_temp.fx('buyer2')), 'Wrong customer', gen_random_uuid());
  perform pg_temp.check(pg_temp.cust_of(s[2]) = pg_temp.fx('buyer') and pg_temp.cust_of(s[1]) = pg_temp.fx('buyer2') and pg_temp.states(res) = 'moved', 'A13 the cancelled one stays with the first customer; the other moves');
end $$;

-- ═════ B The store ═════
do $$
declare inv uuid; s uuid[]; res jsonb; line uuid;
begin
  perform pg_temp.as_user('owner');
  perform pg_temp.mkspecial('b1');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('b1', 2))); perform pg_temp.pay(inv);
  s := pg_temp.sales(inv); line := pg_temp.line_of(inv, 'b1');
  perform pg_temp.release(s[1]);
  res := public.correct_invoice(inv, jsonb_build_array(pg_temp.keep(line, 'b1', 2)), jsonb_build_object('store_id', pg_temp.fx('store2')), 'Wrong store', gen_random_uuid());
  perform pg_temp.check(pg_temp.store_of(s[1]) = pg_temp.fx('store2') and pg_temp.store_of(s[2]) = pg_temp.fx('store2'), 'B1 released and waiting both follow the store');
  perform pg_temp.check((select warehouse_id from public.special_sales where id = s[1]) = pg_temp.fx('wh') and pg_temp.at_wh('b1') = 9, 'B2 the warehouse it left from stays, no stock moves');
  perform pg_temp.check(pg_temp.said(res) like '%, already released, now shows C500 Store B %; no stock moves%' and pg_temp.said(res) like '% moves to C500 Store B %', 'B3 said for both: ' || pg_temp.said(res));
end $$;

-- ═════ F After it: a machine that followed still comes back ═════
do $$
declare inv uuid; s uuid[]; res jsonb; line uuid;
begin
  perform pg_temp.as_user('owner');
  -- Refund: back on the shelf it left, the customer as corrected.
  perform pg_temp.mkspecial('f1');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('f1'))); perform pg_temp.pay(inv);
  s := pg_temp.sales(inv); line := pg_temp.line_of(inv, 'f1');
  perform pg_temp.release(s[1]);
  res := public.correct_invoice(inv, jsonb_build_array(pg_temp.keep(line, 'f1')), jsonb_build_object('customer_id', pg_temp.fx('buyer2'), 'store_id', pg_temp.fx('store2')), 'Wrong both', gen_random_uuid());
  res := pg_temp.refund_line(inv, line, 1000, pg_temp.answer(pg_temp.mv(s[1]), 1, 0, 0));
  perform pg_temp.check(pg_temp.at_wh('f1') = 10 and pg_temp.status_of(s[1]) = 'cancelled' and pg_temp.back(s[1]) and pg_temp.cust_of(s[1]) = pg_temp.fx('buyer2'),
    'F1 refunded: back at the warehouse it left (10 of 10)');
  -- Lowered: the same.
  perform pg_temp.mkspecial('f2');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('f2', 2))); perform pg_temp.pay(inv);
  s := pg_temp.sales(inv); line := pg_temp.line_of(inv, 'f2');
  perform pg_temp.release(s[1]); perform pg_temp.release(s[2]);
  res := public.correct_invoice(inv, jsonb_build_array(pg_temp.keep(line, 'f2', 2)), jsonb_build_object('customer_id', pg_temp.fx('buyer2')), 'Wrong customer', gen_random_uuid());
  res := pg_temp.correct(inv, jsonb_build_array(pg_temp.keep(line, 'f2', 1)));
  perform pg_temp.check(pg_temp.at_wh('f2') = 9 and pg_temp.status_of(s[2]) = 'cancelled' and pg_temp.states(res) = 'back', 'F2 lowered after following: one goes back');
  -- Cancelled: everything back.
  perform pg_temp.mkspecial('f3');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('f3'))); perform pg_temp.pay(inv);
  s := pg_temp.sales(inv); line := pg_temp.line_of(inv, 'f3');
  perform pg_temp.release(s[1]);
  res := public.correct_invoice(inv, jsonb_build_array(pg_temp.keep(line, 'f3')), jsonb_build_object('customer_id', pg_temp.fx('buyer2')), 'Wrong customer', gen_random_uuid());
  res := public.cancel_invoice_recorded(inv, 'Check cancellation', gen_random_uuid());
  perform pg_temp.check(pg_temp.at_wh('f3') = 10 and pg_temp.status_of(s[1]) = 'cancelled', 'F3 cancelled after following: back (10 of 10)');
end $$;

-- ═════ P A corrected price ═════
do $$
declare inv uuid; s uuid[]; res jsonb; line uuid; other uuid; pv jsonb; e jsonb; n bigint; before_paid numeric; t text;
begin
  perform pg_temp.as_user('owner');
  perform pg_temp.mkspecial('p1');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('p1', 2))); perform pg_temp.pay(inv);
  s := pg_temp.sales(inv); line := pg_temp.line_of(inv, 'p1');
  perform pg_temp.release(s[1]);
  n := (select count(*) from public.stock_movements where product_id = pg_temp.fx('p_p1'));
  before_paid := public.invoice_net_received(inv);

  -- The summary says it first, and changes nothing.
  pv := public.preview_invoice_correction(inv, jsonb_build_object('items', jsonb_build_array(pg_temp.keep(line, 'p1', 2) || jsonb_build_object('unit_price', 900))));
  select x into e from jsonb_array_elements(pv->'effects') x where x->>'area' = 'special_sales';
  perform pg_temp.check(e->'items'->0->>'what' = pg_temp.sale_no_of(s[1]) || ': C500 p1 now shows S$900.00, was S$1000.00'
      and e->'items'->1->>'what' = pg_temp.sale_no_of(s[2]) || ': C500 p1 now shows S$900.00, was S$1000.00',
    'P1 the summary says the new price for both: ' || coalesce(e::text, 'no entry'));
  perform pg_temp.check((select unit_price from public.special_sales where id = s[1]) = 1000, 'P2 and changes nothing');

  res := public.correct_invoice(inv, jsonb_build_array(pg_temp.keep(line, 'p1', 2) || jsonb_build_object('unit_price', 900)), '{}'::jsonb, 'A better price', gen_random_uuid());
  perform pg_temp.check(pg_temp.states(res) = 'repriced,repriced', 'P3 saved: both answered: ' || pg_temp.said(res));
  perform pg_temp.check(not exists (select 1 from public.special_sales where id = any(s) and (unit_price, total_amount) is distinct from (900::numeric, 900::numeric)), 'P4 released and waiting both show S$900');
  perform pg_temp.check(pg_temp.status_of(s[1]) = 'completed' and pg_temp.status_of(s[2]) = 'pending', 'P5 neither changes state');
  perform pg_temp.check(pg_temp.at_wh('p1') = 9 and (select count(*) from public.stock_movements where product_id = pg_temp.fx('p_p1')) = n, 'P6 no stock moves');
  perform pg_temp.check(public.invoice_net_received(inv) = before_paid and public.invoice_charge_total(inv) = 1800, 'P7 no money moves: received as it was, the invoice charges S$1,800');
  perform pg_temp.check(pg_temp.notes_of(s[1]) like '%Follows invoice % as corrected: A better price%'
      and exists (select 1 from public.audit_logs a where a.action = 'special_sale_price_follows_invoice' and a.record_id = s[1] and (a.old_data->>'total_amount')::numeric = 1000 and (a.new_data->>'total_amount')::numeric = 900),
    'P8 a note, and the Audit Log has before and after');

  -- The same price again: nothing.
  res := public.correct_invoice(inv, jsonb_build_array(pg_temp.keep(line, 'p1', 2) || jsonb_build_object('unit_price', 900)), jsonb_build_object('notes', 'Only a note'), 'A note', gen_random_uuid());
  perform pg_temp.check(pg_temp.states(res) = '', 'P9 the same price again: nothing');

  -- The price and the customer in one save: both said, one note.
  perform pg_temp.mkspecial('p10');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('p10'))); perform pg_temp.pay(inv);
  s := pg_temp.sales(inv); line := pg_temp.line_of(inv, 'p10');
  res := public.correct_invoice(inv, jsonb_build_array(pg_temp.keep(line, 'p10') || jsonb_build_object('unit_price', 900)), jsonb_build_object('customer_id', pg_temp.fx('buyer2')), 'Both wrong', gen_random_uuid());
  perform pg_temp.check(pg_temp.states(res) = 'moved,repriced' and pg_temp.cust_of(s[1]) = pg_temp.fx('buyer2') and (select total_amount from public.special_sales where id = s[1]) = 900,
    'P10 price and customer in one save: ' || pg_temp.said(res));
  perform pg_temp.check((length(pg_temp.notes_of(s[1])) - length(replace(pg_temp.notes_of(s[1]), 'Follows invoice', ''))) / length('Follows invoice') = 1, 'P11 one note, not two');

  -- A dearer price: the invoice owes, the waiting one waits (498), the released one shows the new price.
  perform pg_temp.mkspecial('p12');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('p12', 2))); perform pg_temp.pay(inv);
  s := pg_temp.sales(inv); line := pg_temp.line_of(inv, 'p12');
  perform pg_temp.release(s[1]);
  res := public.correct_invoice(inv, jsonb_build_array(pg_temp.keep(line, 'p12', 2) || jsonb_build_object('unit_price', 1100)), '{}'::jsonb, 'Dearer', gen_random_uuid());
  t := pg_temp.err(format('select pg_temp.release(%L)', s[2]));
  perform pg_temp.check((select status::text from public.invoices where id = inv) = 'partially_paid' and t like '%has S$200.00 owing%' and (select total_amount from public.special_sales where id = s[1]) = 1100,
    'P12 dearer: the invoice owes S$200, the waiting one waits, the released one shows the new price: ' || t);

  -- A supplier sent it: the price follows, the supplier stays.
  perform pg_temp.mkspecial('p13');
  perform pg_temp.supplier_for('p13');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('p13'))); perform pg_temp.pay(inv);
  s := pg_temp.sales(inv); line := pg_temp.line_of(inv, 'p13');
  perform public.release_special_sale_to_supplier(s[1], pg_temp.fx('sup_p13'), null);
  res := public.correct_invoice(inv, jsonb_build_array(pg_temp.keep(line, 'p13') || jsonb_build_object('unit_price', 900)), '{}'::jsonb, 'A better price', gen_random_uuid());
  perform pg_temp.check((select total_amount from public.special_sales where id = s[1]) = 900 and (select supplier_id from public.special_sales where id = s[1]) = pg_temp.fx('sup_p13'), 'P13 sent by a supplier: the price follows');

  -- Another machine on the line: a unit a supplier sent stays at its own price; the new one has the line's.
  perform pg_temp.mkspecial('p14'); perform pg_temp.mkspecial('p14n');
  perform pg_temp.supplier_for('p14');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('p14'))); perform pg_temp.pay(inv);
  s := pg_temp.sales(inv); line := pg_temp.line_of(inv, 'p14');
  perform public.release_special_sale_to_supplier(s[1], pg_temp.fx('sup_p14'), null);
  res := public.correct_invoice(inv, jsonb_build_array(pg_temp.keep(line, 'p14n') || jsonb_build_object('unit_price', 700)), '{}'::jsonb, 'Another machine', gen_random_uuid());
  perform pg_temp.check((select total_amount from public.special_sales where id = s[1]) = 1000
      and (select total_amount from public.special_sales where invoice_item_id = line and status = 'pending') = 700 and pg_temp.states(res) = 'stays,raised',
    'P14 another machine: the unit a supplier sent keeps its price, the new one has the line''s: ' || pg_temp.said(res));

  -- Another line on the invoice, and a cancelled sale, stay.
  perform pg_temp.mkspecial('p15'); perform pg_temp.mkspecial('p15o');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('p15', 2), pg_temp.sale_line('p15o'))); perform pg_temp.pay(inv);
  line := pg_temp.line_of(inv, 'p15'); other := pg_temp.line_of(inv, 'p15o');
  res := pg_temp.correct(inv, jsonb_build_array(pg_temp.keep(line, 'p15', 1), pg_temp.keep(other, 'p15o')));
  res := public.correct_invoice(inv, jsonb_build_array(pg_temp.keep(line, 'p15', 1) || jsonb_build_object('unit_price', 900), pg_temp.keep(other, 'p15o')), '{}'::jsonb, 'A better price', gen_random_uuid());
  perform pg_temp.check((select array_agg(total_amount order by sale_no) from public.special_sales where invoice_item_id = line) = array[900, 1000]::numeric[]
      and (select total_amount from public.special_sales where invoice_item_id = other) = 1000 and pg_temp.states(res) = 'repriced',
    'P15 only the sale of that line, and not the cancelled one');

  -- More machines at a new price: all at the new price.
  perform pg_temp.mkspecial('p16');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('p16'))); perform pg_temp.pay(inv);
  line := pg_temp.line_of(inv, 'p16');
  res := public.correct_invoice(inv, jsonb_build_array(pg_temp.keep(line, 'p16', 2) || jsonb_build_object('unit_price', 900)), '{}'::jsonb, 'Two, cheaper', gen_random_uuid());
  perform pg_temp.check((select array_agg(total_amount order by sale_no) from public.special_sales where invoice_item_id = line) = array[900, 900]::numeric[], 'P16 raised and repriced: both S$900: ' || pg_temp.said(res));

  -- A discount does not reach the sale: the price before any discount, as a rental's fee.
  perform pg_temp.mkspecial('p17');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('p17'))); perform pg_temp.pay(inv);
  s := pg_temp.sales(inv); line := pg_temp.line_of(inv, 'p17');
  res := public.correct_invoice(inv, jsonb_build_array(pg_temp.keep(line, 'p17') || jsonb_build_object('line_discount_type', 'manual', 'line_discount_amount', 100, 'line_discount_reason', 'Check')), '{}'::jsonb, 'A discount', gen_random_uuid());
  perform pg_temp.check((select line_discount from public.invoice_items where id = line) = 100 and (select total_amount from public.special_sales where id = s[1]) = 1000 and pg_temp.states(res) = '', 'P17 a discount on the line: the sale stays at the price before it');
  res := public.correct_invoice(inv, jsonb_build_array(pg_temp.keep(line, 'p17') || jsonb_build_object('unit_price', 900, 'line_discount_type', 'manual', 'line_discount_amount', 100, 'line_discount_reason', 'Check')), '{}'::jsonb, 'A better price', gen_random_uuid());
  perform pg_temp.check((select unit_price from public.special_sales where id = s[1]) = 900 and (select total_amount from public.special_sales where id = s[1]) = 900,
    'P17b a new price with that discount: the sale shows the new price, before the discount: ' || pg_temp.said(res));

  -- Refunded after a new price: the unit comes back; the money is the invoice's.
  perform pg_temp.mkspecial('p18');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('p18'))); perform pg_temp.pay(inv);
  s := pg_temp.sales(inv); line := pg_temp.line_of(inv, 'p18');
  perform pg_temp.release(s[1]);
  res := public.correct_invoice(inv, jsonb_build_array(pg_temp.keep(line, 'p18') || jsonb_build_object('unit_price', 900)), '{}'::jsonb, 'A better price', gen_random_uuid());
  perform pg_temp.pay_down(inv);
  res := pg_temp.refund_line(inv, line, 900, pg_temp.answer(pg_temp.mv(s[1]), 1, 0, 0));
  perform pg_temp.check(pg_temp.at_wh('p18') = 10 and pg_temp.status_of(s[1]) = 'cancelled', 'P18 refunded after a new price: back (10 of 10)');

  -- A rental's line is not touched here.
  perform pg_temp.mkspecial('p19'); perform pg_temp.mkspecial('p19r');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('p19'),
           jsonb_build_object('kind', 'rental', 'special_product_id', pg_temp.fx('sp_p19r'), 'quantity', 1, 'rental_rate_type', 'month', 'rental_periods', 1, 'rental_start_date', public.sg_today()::text)));
  perform pg_temp.pay(inv);
  s := pg_temp.sales(inv); line := pg_temp.line_of(inv, 'p19');
  select id into other from public.invoice_items where invoice_id = inv and line_kind::text = 'rental';
  res := public.correct_invoice(inv, jsonb_build_array(pg_temp.keep(line, 'p19') || jsonb_build_object('unit_price', 900),
           jsonb_build_object('invoice_item_id', other, 'kind', 'rental', 'special_product_id', pg_temp.fx('sp_p19r'), 'quantity', 1, 'rental_rate_type', 'month', 'rental_periods', 1, 'rental_start_date', public.sg_today()::text)),
           '{}'::jsonb, 'A better price', gen_random_uuid());
  perform pg_temp.check((select total_amount from public.special_sales where id = s[1]) = 900 and pg_temp.states(res) = 'repriced', 'P19 a rental beside it: only the sale is answered here');
end $$;

-- ═════ C Left as they are ═════
do $$
declare inv uuid; s uuid[]; res jsonb; line uuid; r uuid; other uuid; t text; pv jsonb;
begin
  perform pg_temp.as_user('owner');
  -- A cancelled or refunded invoice: its sales stay, whatever is asked.
  perform pg_temp.mkspecial('c1');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('c1'))); perform pg_temp.pay(inv);
  s := pg_temp.sales(inv); line := pg_temp.line_of(inv, 'c1');
  perform pg_temp.release(s[1]);
  update public.invoices set status = 'cancelled', customer_id = pg_temp.fx('buyer2') where id = inv;
  update public.invoice_items set unit_price = 900 where id = line;
  res := jsonb_build_object('special', public.invoice_special_sales_follow_lines(inv, '[]'::jsonb, 'Check', null));
  perform pg_temp.check(pg_temp.states(res) = '' and pg_temp.cust_of(s[1]) = pg_temp.fx('buyer') and (select total_amount from public.special_sales where id = s[1]) = 1000, 'C1 a cancelled invoice is left as it is');
  update public.invoices set status = 'refunded' where id = inv;
  res := jsonb_build_object('special', public.invoice_special_sales_follow_lines(inv, '[]'::jsonb, 'Check', null));
  perform pg_temp.check(pg_temp.states(res) = '' and pg_temp.cust_of(s[1]) = pg_temp.fx('buyer'), 'C2 and so is a refunded one');

  -- A rental out still refuses a customer change, as 458 has it; the sale beside it then moves nothing.
  perform pg_temp.mkspecial('c3'); perform pg_temp.mkspecial('c3r');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('c3'),
           jsonb_build_object('kind', 'rental', 'special_product_id', pg_temp.fx('sp_c3r'), 'quantity', 1, 'rental_rate_type', 'month', 'rental_periods', 1, 'rental_start_date', public.sg_today()::text)));
  perform pg_temp.pay(inv);
  s := pg_temp.sales(inv); line := pg_temp.line_of(inv, 'c3');
  select id into r from public.rentals where invoice_id = inv;
  perform public.fulfil_special_doc('rental', r, pg_temp.fx('wh'), 'warehouse');
  select id into other from public.invoice_items where invoice_id = inv and line_kind::text = 'rental';
  t := pg_temp.err(format('select public.correct_invoice(%L, %L, %L, %L, %L)', inv, jsonb_build_array(pg_temp.keep(line, 'c3'),
           jsonb_build_object('invoice_item_id', other, 'kind', 'rental', 'special_product_id', pg_temp.fx('sp_c3r'), 'quantity', 1, 'rental_rate_type', 'month', 'rental_periods', 1, 'rental_start_date', public.sg_today()::text)),
           jsonb_build_object('customer_id', pg_temp.fx('buyer2')), 'Wrong customer', gen_random_uuid()));
  perform pg_temp.check(t <> 'ok' and pg_temp.cust_of(s[1]) = pg_temp.fx('buyer'), 'C3 a rental out refuses it, as before, and nothing moves: ' || t);
end $$;

-- ═════ W The benefits warning ═════
do $$
declare inv uuid; res jsonb; line uuid; pv jsonb; pkg uuid; t text; st uuid;
begin
  perform pg_temp.as_user('owner');
  -- No benefits: no question, not blocking, and the save goes through, as it always did.
  perform pg_temp.mkplain('w1');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.prod_line('w1'))); perform pg_temp.pay(inv);
  select id into line from public.invoice_items where invoice_id = inv;
  perform pg_temp.check(not exists (select 1 from public.invoice_transferable_benefits(inv)), 'W0 this invoice has no benefits');
  pv := public.preview_invoice_correction(inv, jsonb_build_object('items', jsonb_build_array(pg_temp.keep_plain(line, 'w1')), 'customer_id', pg_temp.fx('buyer2')));
  perform pg_temp.check(not exists (select 1 from jsonb_array_elements(pv->'needs_review') e where e->>'area' = 'benefits') and (pv->>'blocking')::boolean is false,
    'W1 no benefits: the summary does not ask, and does not say it will be refused: ' || coalesce((pv->'needs_review')::text, ''));
  perform pg_temp.check(exists (select 1 from jsonb_array_elements(pv->'effects') e where e->>'area' = 'customer' and e->>'change' = 'reassigned'), 'W2 and still says the customer changes');
  res := public.correct_invoice(inv, jsonb_build_array(pg_temp.keep_plain(line, 'w1')), jsonb_build_object('customer_id', pg_temp.fx('buyer2')), 'Wrong customer', gen_random_uuid());
  perform pg_temp.check((select customer_id from public.invoices where id = inv) = pg_temp.fx('buyer2'), 'W3 and the save goes through, as it did');

  -- With benefits: it still asks, and the save is still refused without an answer.
  st := pg_temp.fx('store');
  insert into public.credit_packages(name, customer_price, paid_credit_amount, bonus_enabled, bonus_value, allow_product, allow_therapy, allow_voucher, grants_reward)
  values ('C500 Package', 100, 100, false, 0, true, true, true, false) returning id into pkg;
  insert into public.credit_package_stores(package_id, store_id) values (pkg, st);
  inv := pg_temp.mk(jsonb_build_array(jsonb_build_object('kind', 'credit_package', 'credit_package_id', pkg, 'quantity', 1))); perform pg_temp.pay(inv);
  select id into line from public.invoice_items where invoice_id = inv;
  perform pg_temp.check(exists (select 1 from public.invoice_transferable_benefits(inv)), 'W4 this invoice has benefits');
  pv := public.preview_invoice_correction(inv, jsonb_build_object('items', jsonb_build_array(jsonb_build_object('invoice_item_id', line, 'kind', 'credit_package', 'credit_package_id', pkg, 'quantity', 1)), 'customer_id', pg_temp.fx('buyer2')));
  perform pg_temp.check(exists (select 1 from jsonb_array_elements(pv->'needs_review') e where e->>'area' = 'benefits' and e->>'detail' like 'Choose whether the unused benefits%') and (pv->>'blocking')::boolean,
    'W5 with benefits: the summary still asks, and blocks');
  t := pg_temp.err(format('select public.correct_invoice(%L, %L, %L, %L, %L)', inv, jsonb_build_array(jsonb_build_object('invoice_item_id', line, 'kind', 'credit_package', 'credit_package_id', pkg, 'quantity', 1)),
        jsonb_build_object('customer_id', pg_temp.fx('buyer2')), 'Wrong customer', gen_random_uuid()));
  perform pg_temp.check(t like 'BENEFIT_ACTION_REQUIRED%', 'W6 and the save is still refused without an answer: ' || t);
  pv := public.preview_invoice_correction(inv, jsonb_build_object('items', jsonb_build_array(jsonb_build_object('invoice_item_id', line, 'kind', 'credit_package', 'credit_package_id', pkg, 'quantity', 1)), 'customer_id', pg_temp.fx('buyer2'), 'benefit_action', 'transfer'));
  perform pg_temp.check(not exists (select 1 from jsonb_array_elements(pv->'needs_review') e where e->>'detail' like 'Choose whether%'), 'W7 answered: it no longer asks');
  pv := public.preview_invoice_correction(inv, jsonb_build_object('items', jsonb_build_array(jsonb_build_object('invoice_item_id', line, 'kind', 'credit_package', 'credit_package_id', pkg, 'quantity', 1)), 'store_id', pg_temp.fx('store2')));
  perform pg_temp.check(not exists (select 1 from jsonb_array_elements(pv->'needs_review') e where e->>'detail' like 'Choose whether%'), 'W8 a store change alone: it does not ask, as before');
end $$;

-- ═════ S Access ═════
select pg_temp.check(not exists (
    select 1 from acl_before b join pg_proc p on p.oid::regprocedure::text = b.sig
     where b.acl is distinct from (select coalesce(string_agg(x::text, ',' order by x::text), '') from unnest(p.proacl) x)),
  'S1 the patched functions keep their grants');
select pg_temp.check(not has_function_privilege('authenticated', 'public.invoice_special_sales_follow_lines(uuid,jsonb,text,uuid)', 'execute')
    and has_function_privilege('authenticated', 'public.preview_invoice_correction(uuid,jsonb)', 'execute'),
  'S2 the follow-lines function stays internal, and the summary stays callable');

-- ═════ U UNDO ═════
\if :{?skip_install}
do $$ begin raise notice 'NOTE  U1-U3 are skipped: 500 is in already'; end $$;
\else
create temp table after_install as select pg_temp.fp() f;
\ir ../undo-500.sql
select pg_temp.check(pg_temp.md5_of('invoice_special_sales_follow_lines(uuid,jsonb,text,uuid)') = '3cf6cfd8a22e5776e7b77e8d5ff3753d'
    and pg_temp.md5_of('preview_invoice_correction(uuid,jsonb)') = '13b0925c29bd8ca14d8d8b7bd961fef8',
  'U1 undo puts the two back to production''s texts');
select pg_temp.check((select f from before_install) = pg_temp.fp(), 'U2 the whole fingerprint is back: ' || pg_temp.fp());
\ir ../../../supabase/500_special_sales_follow_invoice_customer_store_price.sql
select pg_temp.check(pg_temp.fp() = (select f from after_install), 'U3 500 again gives back exactly what it gave: ' || pg_temp.fp());
\endif

-- ═════ Done ═════
do $$
declare n int; msgs text;
begin
  select count(*), string_agg(msg, E'\n') into n, msgs from failed;
  if n > 0 then raise exception '% check(s) failed:%', n, E'\n' || msgs; end if;
  raise notice 'All 500 checks passed.';
end $$;
rollback;
