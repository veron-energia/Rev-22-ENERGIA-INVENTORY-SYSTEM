-- 498: a special sale still waiting follows its invoice's customer and store, and is not
-- released while its invoice owes money (the user, 7 Nov 2026), through the app's own calls.
--
--   I  498 installs (four functions replaced, none added), a second run changes nothing, its
--      self-test leaves no row.
--   A  The customer: waiting sales follow, a released, supplier-sent or cancelled one does
--      not; a note, the Audit Log, the answer, the summary, the waiting list; only once.
--   B  The store: the same; both in one save.
--   C  A cancelled or refunded invoice is left as it is; a waiting rental follows as before.
--   P  Waiting for the payment: from a warehouse, a store or a supplier, refused in the
--      rental's words with what is owing, no stock moved; released once paid in full; a
--      paid invoice, one paid more than it charges, a refund on it, a free-of-charge one, a
--      sale with no invoice, a rental and who may release as before.
--   S  Grants of the patched functions are unchanged.
--   U  UNDO puts the four functions back to production's texts; 498 again puts them in.
--
-- Run on a copy of production at 497 (createdb -T of a template equal to it; never the
-- template itself):
--   psql -X -d <copy> -v ON_ERROR_STOP=1 -f scripts/special/tests/waiting-sale-follows-498.sql
-- (with -v skip_install=1 where 498 is in). Every check runs, then the file fails if any did.
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
    from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('invoice_special_sales_follow_lines', 'correct_invoice', 'fulfil_special_doc', 'release_special_sale_to_supplier');
create temp table before_install as select pg_temp.fp() f;
\if :{?skip_install}
do $$ begin raise notice 'NOTE  I1-I2 are skipped: 498 is in already'; end $$;
\else
\ir ../../../supabase/498_waiting_sale_follows_invoice_and_waits_for_payment.sql
create temp table after_first as select pg_temp.fp() f;
\ir ../../../supabase/498_waiting_sale_follows_invoice_and_waits_for_payment.sql
select pg_temp.check((select f from after_first) = pg_temp.fp()
    and split_part(pg_temp.fp(), ' ', 2) = split_part((select f from before_install), ' ', 2),
  'I1 498 adds no function, and a second run changes nothing: ' || pg_temp.fp());
select pg_temp.check(not exists (select 1 from public.special_sales where sale_no like '498-CHECK%')
    and not exists (select 1 from public.invoices where invoice_no like '498-CHECK%')
    and not exists (select 1 from auth.users where email like '498chk-%')
    and not exists (select 1 from public.suppliers where name like '498 Check%'),
  'I2 its self-test left no sale, no invoice, no login and no supplier');
\endif

-- ═════ Fixtures (invented) ═════
do $$
declare sfx text := lower(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
  k text; u uuid; st uuid; st2 uuid; wh uuid; wh2 uuid; v uuid; ph text;
begin
  foreach k in array array['owner', 'manager', 'staff', 'other'] loop
    u := gen_random_uuid();
    insert into auth.users(id, email) values (u, 'c498-' || k || '-' || sfx || '@example.invalid');
    insert into public.profiles(id, full_name, email, role, is_active)
      values (u, 'C498 ' || k, 'c498-' || k || '-' || sfx || '@example.invalid',
              (case k when 'other' then 'staff' else k end)::public.user_role, true);
    insert into fx values (k, u);
  end loop;
  perform pg_temp.as_user('owner');
  insert into public.stores(name, code, country_code) values ('C498 Store ' || sfx, 'C498' || sfx, 'SG') returning id into st; insert into fx values ('store', st);
  insert into public.stores(name, code, country_code) values ('C498 Store B ' || sfx, 'C498B' || sfx, 'SG') returning id into st2; insert into fx values ('store2', st2);
  insert into public.warehouses(name, code) values ('C498 Warehouse ' || sfx, 'C498W' || sfx) returning id into wh; insert into fx values ('wh', wh);
  insert into public.warehouses(name, code) values ('C498 Warehouse B ' || sfx, 'C498X' || sfx) returning id into wh2; insert into fx values ('wh2', wh2);
  insert into public.payment_methods(name, is_active) values ('C498 Cash ' || sfx, true) returning id into v; insert into fx values ('cash', v);
  insert into public.user_store_assignments(user_id, store_id) values (pg_temp.fx('manager'), st), (pg_temp.fx('staff'), st), (pg_temp.fx('other'), st2);
  select '+6125550' || lpad(n::text, 4, '0') into ph from generate_series(1000, 9999) n
   where not exists (select 1 from public.customers c where public.normalize_customer_phone(c.phone) = '+6125550' || lpad(n::text, 4, '0'))
   order by n limit 1;
  insert into public.customers(full_name, phone) values ('C498 Buyer', ph) returning id into v; insert into fx values ('buyer', v);
  insert into public.customers(full_name, phone) values ('C498 Second Buyer', '+61255509904') returning id into v; insert into fx values ('buyer2', v);
end $$;

-- A special product (S$1,000) over a third-party product holding 10 at the warehouse ('wh', 'wh2') or the store ('store').
create function pg_temp.mkspecial(tag text, loc text default 'wh') returns void language plpgsql as
$$declare p uuid; sp uuid;
begin
  insert into public.products(name, sku, product_type) values ('C498 ' || tag, 'C498-' || tag, 'third_party') returning id into p;
  if loc = 'wh' then insert into public.warehouse_inventory(warehouse_id, product_id, current_qty) values (pg_temp.fx('wh'), p, 10);
  elsif loc = 'wh2' then insert into public.warehouse_inventory(warehouse_id, product_id, current_qty) values (pg_temp.fx('wh2'), p, 10);
  else insert into public.store_inventory(store_id, product_id, current_qty) values (pg_temp.fx('store'), p, 10); end if;
  sp := public.upsert_special_product_from_product(null, p, 1000, 0, 0, 100, 0, 0);
  insert into fx values ('p_' || tag, p), ('sp_' || tag, sp);
end$$;
create function pg_temp.mkplain(tag text) returns void language plpgsql as
$$declare p uuid;
begin
  insert into public.products(name, sku, product_type) values ('C498 ' || tag, 'C498-' || tag, 'own') returning id into p;
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
  insert into public.suppliers(name, phone) values ('C498 Supplier ' || tag, '+6125550' || lpad((9000 + (select count(*) from fx))::text, 4, '0')) returning id into sup;
  insert into public.product_suppliers(product_id, supplier_id) values (pg_temp.fx('p_' || tag), sup);
  perform public.set_special_product_consignment(pg_temp.fx('sp_' || tag), true);
  insert into fx values ('sup_' || tag, sup);
end$$;

-- ═════ A The customer ═════
do $$
declare inv uuid; s uuid[]; res jsonb; line uuid; pv jsonb; e jsonb; other uuid; n int;
  v500 boolean := pg_get_functiondef('public.invoice_special_sales_follow_lines(uuid,jsonb,text,uuid)'::regprocedure) like '%500: and each takes%';  -- 500: a machine out follows too
begin
  perform pg_temp.as_user('owner');
  perform pg_temp.mkspecial('a1');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('a1', 3))); perform pg_temp.pay(inv);
  s := pg_temp.sales(inv); line := pg_temp.line_of(inv, 'a1');
  perform pg_temp.release(s[1]);
  res := public.correct_invoice(inv, jsonb_build_array(pg_temp.keep(line, 'a1', 3)), jsonb_build_object('customer_id', pg_temp.fx('buyer2')), 'Wrong customer', gen_random_uuid());
  perform pg_temp.check((select customer_id from public.invoices where id = inv) = pg_temp.fx('buyer2'), 'A0 the invoice has the new customer');
  perform pg_temp.check(pg_temp.cust_of(s[2]) = pg_temp.fx('buyer2') and pg_temp.cust_of(s[3]) = pg_temp.fx('buyer2'), 'A1 both waiting sales follow it, with the lines unchanged');
  perform pg_temp.check(pg_temp.cust_of(s[1]) = case when v500 then pg_temp.fx('buyer2') else pg_temp.fx('buyer') end, 'A2 the released one keeps the customer it went to (until 500, which has it follow too)');
  perform pg_temp.check(pg_temp.notes_of(s[2]) like '%Follows invoice % as corrected: Wrong customer%' and (v500 or pg_temp.notes_of(s[1]) not like '%Follows invoice%'), 'A3 a note on each that moved, none on the other (until 500)');
  perform pg_temp.check(exists (select 1 from public.audit_logs a where a.action = 'special_sale_follows_invoice' and a.record_id = s[2]
        and a.old_data->>'customer_id' = pg_temp.fx('buyer')::text and a.new_data->>'customer_id' = pg_temp.fx('buyer2')::text),
    'A4 the Audit Log has before and after');
  perform pg_temp.check(pg_temp.states(res) = case when v500 then 'moved,moved,moved' else 'moved,moved' end and pg_temp.said(res) like '%C498 a1 moves to C498 Second Buyer%'
      and pg_temp.said(res) like '%' || pg_temp.sale_no_of(s[2]) || ':%', 'A5 the answer says it, for the page: ' || pg_temp.said(res));
  perform pg_temp.check((select d.customer_name from public.special_docs_awaiting_fulfilment() d where d.doc_id = s[2]) = 'C498 Second Buyer', 'A6 the Special page''s waiting list names the new customer');

  -- A new correction with nothing new moves nothing.
  res := public.correct_invoice(inv, jsonb_build_array(pg_temp.keep(line, 'a1', 3)), jsonb_build_object('customer_id', pg_temp.fx('buyer2'), 'notes', 'Only a note'), 'A note', gen_random_uuid());
  perform pg_temp.check(pg_temp.states(res) = '' and (select count(*) from public.audit_logs a where a.action = 'special_sale_follows_invoice' and a.record_id = s[2]) = 1,
    'A7 a later save with the same customer moves nothing');

  -- The summary shows it first, and changes nothing.
  perform pg_temp.mkspecial('a8');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('a8'))); perform pg_temp.pay(inv);
  s := pg_temp.sales(inv); line := pg_temp.line_of(inv, 'a8');
  pv := public.preview_invoice_correction(inv, jsonb_build_object('items', jsonb_build_array(pg_temp.keep(line, 'a8')), 'customer_id', pg_temp.fx('buyer2'),
          'benefit_action', 'keep'));
  select x into e from jsonb_array_elements(pv->'effects') x where x->>'area' = 'special_sales';
  perform pg_temp.check(e->>'detail' = 'Saving does what is listed here.' and e->'items'->0->>'what' = pg_temp.sale_no_of(s[1]) || ': C498 a8 moves to C498 Second Buyer',
    'A8 the summary says who it moves to: ' || coalesce(e::text, 'no entry'));
  perform pg_temp.check(pg_temp.cust_of(s[1]) = pg_temp.fx('buyer') and (select customer_id from public.invoices where id = inv) = pg_temp.fx('buyer'), 'A9 and changes nothing');

  -- A sale a supplier sent, and a cancelled one, stay.
  perform pg_temp.mkspecial('a10');
  perform pg_temp.supplier_for('a10');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('a10', 3))); perform pg_temp.pay(inv);
  s := pg_temp.sales(inv); line := pg_temp.line_of(inv, 'a10');
  perform public.release_special_sale_to_supplier(s[1], pg_temp.fx('sup_a10'), 'Check Road');
  res := pg_temp.correct(inv, jsonb_build_array(pg_temp.keep(line, 'a10', 2)));
  perform pg_temp.check(pg_temp.status_of(s[3]) = 'cancelled', 'A10 lowered: the newest waiting one is cancelled');
  res := public.correct_invoice(inv, jsonb_build_array(pg_temp.keep(line, 'a10', 2)), jsonb_build_object('customer_id', pg_temp.fx('buyer2')), 'Wrong customer', gen_random_uuid());
  perform pg_temp.check(pg_temp.cust_of(s[1]) = case when v500 then pg_temp.fx('buyer2') else pg_temp.fx('buyer') end and pg_temp.cust_of(s[3]) = pg_temp.fx('buyer') and pg_temp.cust_of(s[2]) = pg_temp.fx('buyer2'),
    'A11 a sale a supplier sent (until 500) and a cancelled one stay; the waiting one moves');

  -- Corrected in the same save: the new one has the new customer, and is said once.
  perform pg_temp.mkspecial('a12');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('a12'))); perform pg_temp.pay(inv);
  s := pg_temp.sales(inv); line := pg_temp.line_of(inv, 'a12');
  res := public.correct_invoice(inv, jsonb_build_array(pg_temp.keep(line, 'a12', 2)), jsonb_build_object('customer_id', pg_temp.fx('buyer2')), 'More, and another customer', gen_random_uuid());
  perform pg_temp.check((select count(*) from public.special_sales where invoice_item_id = line and status = 'pending' and customer_id = pg_temp.fx('buyer2')) = 2
      and pg_temp.states(res) = 'raised,moved', 'A12 raised and moved in one save: both wait for the new customer: ' || pg_temp.states(res));

  -- The same request again: replayed, nothing twice.
  perform pg_temp.mkspecial('a14');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('a14'))); perform pg_temp.pay(inv);
  s := pg_temp.sales(inv); line := pg_temp.line_of(inv, 'a14');
  other := gen_random_uuid();
  res := public.correct_invoice(inv, jsonb_build_array(pg_temp.keep(line, 'a14')), jsonb_build_object('customer_id', pg_temp.fx('buyer2')), 'Wrong customer', other);
  res := public.correct_invoice(inv, jsonb_build_array(pg_temp.keep(line, 'a14')), jsonb_build_object('customer_id', pg_temp.fx('buyer2')), 'Wrong customer', other);
  perform pg_temp.check((res->>'replayed')::boolean and (select count(*) from public.audit_logs a where a.action = 'special_sale_follows_invoice' and a.record_id = s[1]) = 1
      and pg_temp.notes_of(s[1]) like '%Follows invoice%' and pg_temp.notes_of(s[1]) not like '%Follows invoice%Follows invoice%', 'A14 the same request again replays: moved and noted once');

  -- Staff of the store can correct the customer; the sale follows.
  perform pg_temp.mkspecial('a15');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('a15'))); perform pg_temp.pay(inv);
  s := pg_temp.sales(inv); line := pg_temp.line_of(inv, 'a15');
  perform pg_temp.as_user('staff');
  res := public.correct_invoice(inv, jsonb_build_array(pg_temp.keep(line, 'a15')), jsonb_build_object('customer_id', pg_temp.fx('buyer2')), 'Wrong customer', gen_random_uuid());
  perform pg_temp.check(pg_temp.cust_of(s[1]) = pg_temp.fx('buyer2') and pg_temp.states(res) = 'moved', 'A15 staff of the store correct the customer: the sale follows');
  perform pg_temp.as_user('owner');

  -- Whatever the waiting list shows follows, by the list's own rule (not only the word 'pending').
  perform pg_temp.mkspecial('a16');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('a16'))); perform pg_temp.pay(inv);
  s := pg_temp.sales(inv); line := pg_temp.line_of(inv, 'a16');
  update public.special_sales set status = 'paid' where id = s[1];
  perform pg_temp.check(exists (select 1 from public.special_docs_awaiting_fulfilment() d where d.doc_id = s[1]), 'A16 the waiting list shows a sale with no place, whatever its status word');
  res := public.correct_invoice(inv, jsonb_build_array(pg_temp.keep(line, 'a16')), jsonb_build_object('customer_id', pg_temp.fx('buyer2')), 'Wrong customer', gen_random_uuid());
  perform pg_temp.check(pg_temp.cust_of(s[1]) = pg_temp.fx('buyer2'), 'A17 and it follows');

  -- One released from a store stays too.
  perform pg_temp.mkspecial('a18', 'store');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('a18'))); perform pg_temp.pay(inv);
  s := pg_temp.sales(inv); line := pg_temp.line_of(inv, 'a18');
  perform pg_temp.release(s[1], 'store');
  res := public.correct_invoice(inv, jsonb_build_array(pg_temp.keep(line, 'a18')), jsonb_build_object('customer_id', pg_temp.fx('buyer2')), 'Wrong customer', gen_random_uuid());
  perform pg_temp.check(pg_temp.cust_of(s[1]) = case when v500 then pg_temp.fx('buyer2') else pg_temp.fx('buyer') end and pg_temp.states(res) = case when v500 then 'moved' else '' end, 'A18 a sale released from a store keeps its customer (until 500)');

  -- A save that changes neither the lines nor the customer or store calls nothing.
  perform pg_temp.mkspecial('a19');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('a19'))); perform pg_temp.pay(inv);
  s := pg_temp.sales(inv); line := pg_temp.line_of(inv, 'a19');
  update public.special_sales set customer_id = pg_temp.fx('buyer2') where id = s[1];
  res := public.correct_invoice(inv, jsonb_build_array(pg_temp.keep(line, 'a19')), jsonb_build_object('notes', 'Only a note'), 'A note', gen_random_uuid());
  perform pg_temp.check(pg_temp.cust_of(s[1]) = pg_temp.fx('buyer2') and pg_temp.states(res) = '', 'A19 a note alone leaves a sale as it is, even out of step with the invoice');

  -- A correction that does not save moves nothing.
  perform pg_temp.mkspecial('a13');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('a13'))); perform pg_temp.pay(inv);
  s := pg_temp.sales(inv); line := pg_temp.line_of(inv, 'a13');
  perform pg_temp.check(pg_temp.err(format('select public.correct_invoice(%L, %L, %L, %L, %L)', inv, jsonb_build_array(pg_temp.keep(line, 'a13')),
        jsonb_build_object('customer_id', pg_temp.fx('buyer2'), 'expected_edit_count', 99), 'Stale', gen_random_uuid())) like 'This invoice was changed by another user%'
      and pg_temp.cust_of(s[1]) = pg_temp.fx('buyer'), 'A13 a refused correction moves nothing');
end $$;

-- ═════ B The store ═════
do $$
declare inv uuid; s uuid[]; res jsonb; line uuid; p uuid; pv jsonb; e jsonb;
  v500 boolean := pg_get_functiondef('public.invoice_special_sales_follow_lines(uuid,jsonb,text,uuid)'::regprocedure) like '%500: and each takes%';  -- 500: a machine out follows too
begin
  perform pg_temp.as_user('owner');
  perform pg_temp.mkspecial('b1');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('b1', 2))); perform pg_temp.pay(inv);
  s := pg_temp.sales(inv); line := pg_temp.line_of(inv, 'b1');
  perform pg_temp.release(s[1]);
  res := public.correct_invoice(inv, jsonb_build_array(pg_temp.keep(line, 'b1', 2)), jsonb_build_object('store_id', pg_temp.fx('store2')), 'Wrong store', gen_random_uuid());
  perform pg_temp.check((select store_id from public.invoices where id = inv) = pg_temp.fx('store2') and pg_temp.store_of(s[2]) = pg_temp.fx('store2'), 'B1 a waiting sale follows the invoice to the other store');
  perform pg_temp.check(pg_temp.store_of(s[1]) = case when v500 then pg_temp.fx('store2') else pg_temp.fx('store') end, 'B2 the released one keeps the store it was sold at (until 500)');
  perform pg_temp.check(pg_temp.states(res) = case when v500 then 'moved,moved' else 'moved' end and pg_temp.said(res) like '%C498 b1 moves to C498 Store B%', 'B3 the answer says so: ' || pg_temp.said(res));
  perform pg_temp.check((select d.store_name from public.special_docs_awaiting_fulfilment() d where d.doc_id = s[2]) like 'C498 Store B%', 'B4 the waiting list names the new store');

  -- Both in one save.
  perform pg_temp.mkspecial('b6');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('b6'))); perform pg_temp.pay(inv);
  s := pg_temp.sales(inv); line := pg_temp.line_of(inv, 'b6');
  res := public.correct_invoice(inv, jsonb_build_array(pg_temp.keep(line, 'b6')), jsonb_build_object('customer_id', pg_temp.fx('buyer2'), 'store_id', pg_temp.fx('store2')), 'Wrong both', gen_random_uuid());
  perform pg_temp.check(pg_temp.cust_of(s[1]) = pg_temp.fx('buyer2') and pg_temp.store_of(s[1]) = pg_temp.fx('store2')
      and pg_temp.said(res) like '%C498 b6 moves to C498 Second Buyer and C498 Store B%', 'B6 both in one save, both said: ' || pg_temp.said(res));

  -- The summary, for a store.
  perform pg_temp.mkspecial('b7');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('b7'))); perform pg_temp.pay(inv);
  s := pg_temp.sales(inv); line := pg_temp.line_of(inv, 'b7');
  pv := public.preview_invoice_correction(inv, jsonb_build_object('items', jsonb_build_array(pg_temp.keep(line, 'b7')), 'store_id', pg_temp.fx('store2')));
  select x into e from jsonb_array_elements(pv->'effects') x where x->>'area' = 'special_sales';
  perform pg_temp.check(e->'items'->0->>'what' like pg_temp.sale_no_of(s[1]) || ': C498 b7 moves to C498 Store B%' and pg_temp.store_of(s[1]) = pg_temp.fx('store'),
    'B7 the summary says which store, and changes nothing: ' || coalesce(e::text, 'no entry'));

  -- Staff cannot move a store (377), so nothing follows.
  perform pg_temp.mkspecial('b8');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('b8'))); perform pg_temp.pay(inv);
  s := pg_temp.sales(inv); line := pg_temp.line_of(inv, 'b8');
  perform pg_temp.as_user('staff');
  perform pg_temp.check(pg_temp.err(format('select public.correct_invoice(%L, %L, %L, %L, %L)', inv, jsonb_build_array(pg_temp.keep(line, 'b8')),
        jsonb_build_object('store_id', pg_temp.fx('store2')), 'Wrong store', gen_random_uuid())) <> 'ok' and pg_temp.store_of(s[1]) = pg_temp.fx('store'), 'B8 staff cannot move the store, so the sale stays');
  perform pg_temp.as_user('owner');
end $$;

-- ═════ C Left as they are ═════
do $$
declare inv uuid; s uuid[]; res jsonb; line uuid; r uuid; other uuid; before uuid;
begin
  perform pg_temp.as_user('owner');
  -- A cancelled invoice: its sales stay, whatever is asked.
  perform pg_temp.mkspecial('c1');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('c1'))); perform pg_temp.pay(inv);
  s := pg_temp.sales(inv); line := pg_temp.line_of(inv, 'c1');
  update public.invoices set status = 'cancelled', customer_id = pg_temp.fx('buyer2') where id = inv;
  res := jsonb_build_object('special', public.invoice_special_sales_follow_lines(inv, '[]'::jsonb, 'Check', null));
  perform pg_temp.check(pg_temp.states(res) = '' and pg_temp.cust_of(s[1]) = pg_temp.fx('buyer'), 'C1 a cancelled invoice is left as it is');
  update public.invoices set status = 'refunded' where id = inv;
  res := jsonb_build_object('special', public.invoice_special_sales_follow_lines(inv, '[]'::jsonb, 'Check', null));
  perform pg_temp.check(pg_temp.states(res) = '' and pg_temp.cust_of(s[1]) = pg_temp.fx('buyer'), 'C2 and so is a refunded one');

  -- A waiting rental beside it: as 458 has it, it follows by itself; another invoice's sale stays.
  perform pg_temp.mkspecial('c3'); perform pg_temp.mkspecial('c3r');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('c3'),
           jsonb_build_object('kind', 'rental', 'special_product_id', pg_temp.fx('sp_c3r'), 'quantity', 1,
             'rental_rate_type', 'month', 'rental_periods', 1, 'rental_start_date', public.sg_today()::text)));
  perform pg_temp.pay(inv);
  s := pg_temp.sales(inv); line := pg_temp.line_of(inv, 'c3');
  select id into r from public.rentals where invoice_id = inv;
  select id into other from public.invoice_items where invoice_id = inv and line_kind::text = 'rental';
  perform pg_temp.mkspecial('c3o');
  before := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('c3o'))); perform pg_temp.pay(before);
  res := public.correct_invoice(inv, jsonb_build_array(pg_temp.keep(line, 'c3'),
           jsonb_build_object('invoice_item_id', other, 'kind', 'rental', 'special_product_id', pg_temp.fx('sp_c3r'), 'quantity', 1,
             'rental_rate_type', 'month', 'rental_periods', 1, 'rental_start_date', public.sg_today()::text)),
           jsonb_build_object('customer_id', pg_temp.fx('buyer2'), 'benefit_action', 'keep'), 'Wrong customer', gen_random_uuid());
  perform pg_temp.check(pg_temp.cust_of(s[1]) = pg_temp.fx('buyer2') and (select customer_id from public.rentals where id = r) = pg_temp.fx('buyer2')
      and (select customer_id from public.special_sales where invoice_id = before) = pg_temp.fx('buyer')
      and jsonb_array_length(res->'rentals') = 1 and pg_temp.states(res) = 'moved',
    'C3 the sale and the waiting rental both follow, each said once, and another invoice''s sale stays');
end $$;

-- ═════ P Waits for the payment ═════
do $$
declare inv uuid; s uuid[]; res jsonb; line uuid; t text; pay uuid; before bigint; no text;
begin
  perform pg_temp.as_user('owner');
  -- Raised by a correction: the new unit waits for the money.
  perform pg_temp.mkspecial('p1');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('p1'))); perform pg_temp.pay(inv);
  s := pg_temp.sales(inv); line := pg_temp.line_of(inv, 'p1');
  perform pg_temp.release(s[1]);
  res := pg_temp.correct(inv, jsonb_build_array(pg_temp.keep(line, 'p1', 2)));
  s := pg_temp.sales(inv); no := (select invoice_no from public.invoices where id = inv);
  perform pg_temp.check(pg_temp.said(res) like '%take the payment before releasing it' and (select status::text from public.invoices where id = inv) = 'partially_paid', 'P0 raised: one more waits, and the invoice owes S$1,000');
  t := pg_temp.err(format('select pg_temp.release(%L)', s[2]));
  perform pg_temp.check(t = pg_temp.sale_no_of(s[2]) || ' cannot be released yet: its invoice ' || no || ' has S$1000.00 owing. Take the payment first, then release it.',
    'P1 from a warehouse: refused in words: ' || t);
  perform pg_temp.check(pg_temp.at_wh('p1') = 9 and pg_temp.status_of(s[2]) = 'pending' and not exists (select 1 from public.stock_movements where id = pg_temp.mv(s[2])), 'P2 no stock moved, it still waits');
  t := pg_temp.err(format('select pg_temp.release(%L, %L)', s[2], 'store'));
  perform pg_temp.check(t like '%cannot be released yet: its invoice%', 'P3 from a store: the same');
  perform pg_temp.pay(inv, 400);
  t := pg_temp.err(format('select pg_temp.release(%L)', s[2]));
  perform pg_temp.check(t = pg_temp.sale_no_of(s[2]) || ' cannot be released yet: its invoice ' || no || ' has S$600.00 owing. Take the payment first, then release it.',
    'P4 part of it paid: refused, with what is left: ' || t);
  perform pg_temp.pay(inv);
  t := pg_temp.err(format('select pg_temp.release(%L)', s[2]));
  perform pg_temp.check(t = 'ok' and pg_temp.at_wh('p1') = 8 and pg_temp.status_of(s[2]) = 'completed', 'P5 paid in full: released');

  -- A payment taken back from an invoice with a waiting sale.
  perform pg_temp.mkspecial('p6');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('p6'))); perform pg_temp.pay(inv);
  s := pg_temp.sales(inv);
  perform public.correct_invoice_payment(pg_temp.current_payment(inv), 200, public.sg_today(), pg_temp.fx('cash'), 'Keyed wrong', gen_random_uuid());
  perform pg_temp.check((select status::text from public.invoices where id = inv) = 'partially_paid'
      and pg_temp.err(format('select pg_temp.release(%L)', s[1])) like '%cannot be released yet: its invoice % has S$800.00 owing%', 'P6 a payment corrected down: refused');

  -- A supplier: the same.
  perform pg_temp.mkspecial('p7');
  perform pg_temp.supplier_for('p7');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('p7'))); perform pg_temp.pay(inv);
  line := pg_temp.line_of(inv, 'p7');
  res := pg_temp.correct(inv, jsonb_build_array(pg_temp.keep(line, 'p7', 2)));
  s := pg_temp.sales(inv);
  t := pg_temp.err(format('select public.release_special_sale_to_supplier(%L, %L, %L)', s[2], pg_temp.fx('sup_p7'), 'Check Road'));
  perform pg_temp.check(t like pg_temp.sale_no_of(s[2]) || ' cannot be released yet: its invoice % has S$1000.00 owing. Take the payment first, then release it.'
      and pg_temp.status_of(s[2]) = 'pending' and (select supplier_id from public.special_sales where id = s[2]) is null, 'P7 a supplier cannot send it either: ' || t);
  perform pg_temp.pay(inv);
  t := pg_temp.err(format('select public.release_special_sale_to_supplier(%L, %L, %L)', s[2], pg_temp.fx('sup_p7'), 'Check Road'));
  perform pg_temp.check(t = 'ok' and pg_temp.status_of(s[2]) = 'completed', 'P8 paid in full: it can');
  -- One transaction cannot wait for itself, so this reads the text; with two sessions (7 Nov 2026) the
  -- release waited for a correction holding the invoice, and without this line went straight through.
  perform pg_temp.check(pg_get_functiondef('public.release_special_sale_to_supplier(uuid,uuid,text)'::regprocedure) ~ 'perform 1 from public\.invoices v\s+where v\.id = \(select s0\.invoice_id from public\.special_sales s0 where s0\.id = p_sale_id\)\s+for share',
    'P8b the supplier path takes the invoice first, as the warehouse path does');

  -- Nothing owing: as before. An overpaid invoice, a free line, and a sale with no invoice.
  perform pg_temp.mkspecial('p9');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('p9', 2))); perform pg_temp.pay(inv);
  s := pg_temp.sales(inv); line := pg_temp.line_of(inv, 'p9');
  res := pg_temp.correct(inv, jsonb_build_array(pg_temp.keep(line, 'p9', 1)));
  perform pg_temp.check(pg_temp.err(format('select pg_temp.release(%L)', s[1])) = 'ok' and pg_temp.status_of(s[1]) = 'completed', 'P9 a paid invoice, more than paid after a correction: released');
  perform pg_temp.mkspecial('p10');
  perform pg_temp.supplier_for('p10');
  insert into public.special_sales(sale_no, special_product_id, quantity, unit_price, total_amount, status, customer_id, sold_by)
  values ('C498-P10A', pg_temp.fx('sp_p10'), 1, 1000, 1000, 'pending', pg_temp.fx('buyer'), pg_temp.fx('owner')),
         ('C498-P10B', pg_temp.fx('sp_p10'), 1, 1000, 1000, 'pending', pg_temp.fx('buyer'), pg_temp.fx('owner'));
  perform pg_temp.check(pg_temp.err(format('select pg_temp.release(%L)', (select id from public.special_sales where sale_no = 'C498-P10A'))) = 'ok'
      and pg_temp.err(format('select public.release_special_sale_to_supplier(%L, %L, %L)', (select id from public.special_sales where sale_no = 'C498-P10B'), pg_temp.fx('sup_p10'), 'Check Road')) = 'ok',
    'P10 a sale with no invoice has nothing to wait for, by either path');

  -- A refund of another line, and of one unit of its own line: nothing owes.
  perform pg_temp.mkspecial('p12'); perform pg_temp.mkspecial('p12b');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('p12'), pg_temp.sale_line('p12b'))); perform pg_temp.pay(inv);
  s := array(select id from public.special_sales where invoice_item_id = pg_temp.line_of(inv, 'p12b'));
  perform pg_temp.release(s[1]);
  res := pg_temp.refund_line(inv, pg_temp.line_of(inv, 'p12b'), 1000, pg_temp.answer(pg_temp.mv(s[1]), 1, 0, 0));
  s := array(select id from public.special_sales where invoice_item_id = pg_temp.line_of(inv, 'p12'));
  t := pg_temp.err(format('select pg_temp.release(%L)', s[1]));
  perform pg_temp.check(t = 'ok' and pg_temp.status_of(s[1]) = 'completed', 'P12 another line refunded: the machine still waiting is released: ' || t);
  perform pg_temp.mkspecial('p13');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('p13', 2))); perform pg_temp.pay(inv);
  s := pg_temp.sales(inv); line := pg_temp.line_of(inv, 'p13');
  res := pg_temp.refund_line(inv, line, 1000, '[]'::jsonb);
  t := pg_temp.err(format('select pg_temp.release(%L)', (select id from public.special_sales where invoice_item_id = line and status = 'pending' order by sale_no limit 1)));
  perform pg_temp.check(t = 'ok', 'P13 one of two refunded: the other is released: ' || t);

  -- A free-of-charge invoice, and one marked part-paid with nothing owing.
  perform pg_temp.mkspecial('p14');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('p14', 2))); perform pg_temp.pay(inv);
  s := pg_temp.sales(inv);
  update public.invoices set status = 'completed_foc' where id = inv;
  perform pg_temp.check(pg_temp.err(format('select pg_temp.release(%L)', s[1])) = 'ok', 'P14 a free-of-charge invoice: released');
  update public.invoices set status = 'partially_paid' where id = inv;
  perform pg_temp.check(pg_temp.err(format('select pg_temp.release(%L)', s[2])) = 'ok', 'P15 part-paid in name with nothing owing: released');
  perform pg_temp.mkspecial('p15s'); perform pg_temp.supplier_for('p15s');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('p15s'))); perform pg_temp.pay(inv);
  s := pg_temp.sales(inv);
  update public.invoices set status = 'partially_paid' where id = inv;
  t := pg_temp.err(format('select public.release_special_sale_to_supplier(%L, %L, %L)', s[1], pg_temp.fx('sup_p15s'), 'Check Road'));
  perform pg_temp.check(t = 'ok', 'P15b and by a supplier: ' || t);

  -- Owner and Manager only, as before, whatever is owing.
  perform pg_temp.mkspecial('p16');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('p16'))); perform pg_temp.pay(inv);
  s := pg_temp.sales(inv);
  perform pg_temp.as_user('manager');
  perform pg_temp.check(pg_temp.err(format('select pg_temp.release(%L)', s[1])) = 'ok', 'P16 a Manager releases a paid one');
  perform pg_temp.as_user('staff');
  perform pg_temp.check(pg_temp.err(format('select public.fulfil_special_doc(%L, %L, %L, %L)', 'special_sale', (select id from public.special_sales where sale_no = 'C498-P10A'), pg_temp.fx('wh'), 'warehouse')) like 'Only an Owner or Manager%',
    'P17 staff still cannot release');
  perform pg_temp.as_user('owner');

  -- A rental: its own words, as before.
  perform pg_temp.mkspecial('p11');
  inv := pg_temp.mk(jsonb_build_array(jsonb_build_object('kind', 'rental', 'special_product_id', pg_temp.fx('sp_p11'), 'quantity', 1,
          'rental_rate_type', 'month', 'rental_periods', 1, 'rental_start_date', public.sg_today()::text)));
  perform pg_temp.pay(inv);
  perform public.correct_invoice_payment(pg_temp.current_payment(inv), 10, public.sg_today(), pg_temp.fx('cash'), 'Keyed wrong', gen_random_uuid());
  perform pg_temp.check(pg_temp.err(format($q$select public.fulfil_special_doc('rental', %L, %L, 'warehouse')$q$, (select id from public.rentals where invoice_id = inv), pg_temp.fx('wh'))) like '%cannot be released yet: its invoice % owing%',
    'P11 a rental waits for the payment, as before');
end $$;

-- ═════ S Access ═════
select pg_temp.check(not exists (
    select 1 from acl_before b join pg_proc p on p.oid::regprocedure::text = b.sig
     where b.acl is distinct from (select coalesce(string_agg(x::text, ',' order by x::text), '') from unnest(p.proacl) x)),
  'S1 the patched functions keep their grants');
select pg_temp.check(not has_function_privilege('authenticated', 'public.invoice_special_sales_follow_lines(uuid,jsonb,text,uuid)', 'execute')
    and has_function_privilege('authenticated', 'public.correct_invoice(uuid,jsonb,jsonb,text,uuid)', 'execute')
    and has_function_privilege('authenticated', 'public.fulfil_special_doc(text,uuid,uuid,text)', 'execute')
    and has_function_privilege('authenticated', 'public.release_special_sale_to_supplier(uuid,uuid,text)', 'execute'),
  'S2 the follow-lines function stays internal, and the pages'' calls stay callable');

-- ═════ U UNDO ═════
\if :{?skip_install}
do $$ begin raise notice 'NOTE  U1-U3 are skipped: 498 is in already'; end $$;
\else
create temp table after_install as select pg_temp.fp() f;
\ir ../undo-498.sql
select pg_temp.check(pg_temp.md5_of('invoice_special_sales_follow_lines(uuid,jsonb,text,uuid)') = '630cd846df0cb44a2b6038e83a46a18d'
    and pg_temp.md5_of('correct_invoice(uuid,jsonb,jsonb,text,uuid)') = '9aac5395dd18fd8349727d6c8aa0c633'
    and pg_temp.md5_of('fulfil_special_doc(text,uuid,uuid,text)') = '9b4520efc9d06b04360bacc2c035215b'
    and pg_temp.md5_of('release_special_sale_to_supplier(uuid,uuid,text)') = '15b36ba68fd7b70a1361e80f5e5fad4e',
  'U1 undo puts the four back to production''s texts');
select pg_temp.check((select f from before_install) = pg_temp.fp(), 'U2 the whole fingerprint is back: ' || pg_temp.fp());
\ir ../../../supabase/498_waiting_sale_follows_invoice_and_waits_for_payment.sql
select pg_temp.check(pg_temp.fp() = (select f from after_install), 'U3 498 again gives back exactly what it gave: ' || pg_temp.fp());
\endif

-- ═════ Done ═════
do $$
declare n int; msgs text;
begin
  select count(*), string_agg(msg, E'\n') into n, msgs from failed;
  if n > 0 then raise exception '% check(s) failed:%', n, E'\n' || msgs; end if;
  raise notice 'All 498 checks passed.';
end $$;
rollback;
