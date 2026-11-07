-- 497: a correction of a special sale line takes the line's sales with it (the user, 7 Nov
-- 2026), through the app's own calls.
--
--   I  497 installs (one function added, four replaced), a second run changes nothing, its
--      self-test leaves no row.
--   A  A line removed: a released unit goes back on the warehouse or store it left, its sale
--      is over and everything is on record; a waiting unit comes off the list.
--   B  A line lowered: a waiting unit first, then the newest released one; only what is above
--      the new quantity; another line's units are not touched; a price change moves nothing.
--   C  Another machine on the line: the old one comes off, the new one joins the list.
--   D  A raised quantity joins the list, says when the invoice owes money, and is not raised
--      twice by the payment; a line with no sale at all stays as it is; an added line and an
--      unpaid invoice's line are raised as before.
--   E  The summary says what the save does, changes nothing and uses up no sale number.
--   F  After it: the same request replays, a refund and a cancellation do not take the unit
--      back again, reopened and paid again raises what the corrected line holds, and a line
--      raised again later gets a new unit.
--   G  A line with a refund: units a refund settled are not on the line any more; another
--      machine on it is refused in words; removing it is refused as before.
--   H  A machine a supplier sent (494) stays as it is, and a released one comes off first.
--   J  A warehouse or store since deleted: refused in words, nothing moves.
--   K  A cancelled or refunded invoice, a rental's line and an ordinary product: as before.
--   N  Who: staff of the store do it as a product's stock; staff of another store cannot;
--      nobody can call the new function directly.
--   O  Reopened, not yet paid again: what the payment raises, and what it would pass over.
--   S  Grants of the patched functions are unchanged.
--   U  UNDO puts the four functions back to production's texts; 497 again puts them in.
--
-- Run on a copy of production at 496 (createdb -T of a template equal to it; never the
-- template itself):
--   psql -X -d <copy> -v ON_ERROR_STOP=1 -f scripts/special/tests/correction-follows-497.sql
-- (with -v skip_install=1 where 497 is in). Every check runs, then the file fails if any did.
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
    from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('correct_invoice', 'preview_invoice_correction', 'return_released_special_stock', 'restore_released_special_stock');
create temp table before_install as select pg_temp.fp() f;
\if :{?skip_install}
do $$ begin raise notice 'NOTE  I1-I2 are skipped: 497 is in already'; end $$;
\else
\ir ../../../supabase/497_correction_follows_special_sales.sql
create temp table after_first as select pg_temp.fp() f;
\ir ../../../supabase/497_correction_follows_special_sales.sql
select pg_temp.check((select f from after_first) = pg_temp.fp()
    and split_part(pg_temp.fp(), ' ', 2)::int = split_part((select f from before_install), ' ', 2)::int + 1,
  'I1 497 adds one function, and a second run changes nothing: ' || pg_temp.fp());
select pg_temp.check(not exists (select 1 from public.special_sales where sale_no like '497-CHECK%')
    and not exists (select 1 from public.invoices where invoice_no like '497-CHECK%')
    and not exists (select 1 from auth.users where email like '497chk-%'),
  'I2 its self-test left no sale, no invoice and no login');
\endif
select pg_temp.check(exists (select 1 from pg_constraint where conrelid = 'public.special_sale_returns'::regclass
                               and conname = 'special_sale_returns_why_check' and pg_get_constraintdef(oid) like '%line corrected%'
                               and pg_get_constraintdef(oid) like '%refunded%' and pg_get_constraintdef(oid) like '%invoice cancelled%'),
  'I3 special_sale_returns accepts line corrected, and still the two before it');

-- ═════ Fixtures (invented) ═════
do $$
declare sfx text := lower(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
  k text; u uuid; st uuid; st2 uuid; wh uuid; wh2 uuid; v uuid; ph text;
begin
  foreach k in array array['owner', 'manager', 'staff', 'other'] loop
    u := gen_random_uuid();
    insert into auth.users(id, email) values (u, 'c497-' || k || '-' || sfx || '@example.invalid');
    insert into public.profiles(id, full_name, email, role, is_active)
      values (u, 'C497 ' || k, 'c497-' || k || '-' || sfx || '@example.invalid',
              (case k when 'other' then 'staff' else k end)::public.user_role, true);
    insert into fx values (k, u);
  end loop;
  perform pg_temp.as_user('owner');
  insert into public.stores(name, code, country_code) values ('C497 Store ' || sfx, 'C497' || sfx, 'SG') returning id into st; insert into fx values ('store', st);
  insert into public.stores(name, code, country_code) values ('C497 Store B ' || sfx, 'C497B' || sfx, 'SG') returning id into st2; insert into fx values ('store2', st2);
  insert into public.warehouses(name, code) values ('C497 Warehouse ' || sfx, 'C497W' || sfx) returning id into wh; insert into fx values ('wh', wh);
  insert into public.warehouses(name, code) values ('C497 Warehouse B ' || sfx, 'C497X' || sfx) returning id into wh2; insert into fx values ('wh2', wh2);
  insert into public.payment_methods(name, is_active) values ('C497 Cash ' || sfx, true) returning id into v; insert into fx values ('cash', v);
  insert into public.user_store_assignments(user_id, store_id) values (pg_temp.fx('manager'), st), (pg_temp.fx('staff'), st), (pg_temp.fx('other'), st2);
  select '+6125550' || lpad(n::text, 4, '0') into ph from generate_series(1000, 9999) n
   where not exists (select 1 from public.customers c where public.normalize_customer_phone(c.phone) = '+6125550' || lpad(n::text, 4, '0'))
   order by n limit 1;
  insert into public.customers(full_name, phone) values ('C497 Buyer', ph) returning id into v; insert into fx values ('buyer', v);
end $$;

-- A special product (S$1,000) over a third-party product holding 10 at the warehouse ('wh', 'wh2') or the store ('store').
create function pg_temp.mkspecial(tag text, loc text default 'wh') returns void language plpgsql as
$$declare p uuid; sp uuid;
begin
  insert into public.products(name, sku, product_type) values ('C497 ' || tag, 'C497-' || tag, 'third_party') returning id into p;
  if loc = 'wh' then insert into public.warehouse_inventory(warehouse_id, product_id, current_qty) values (pg_temp.fx('wh'), p, 10);
  elsif loc = 'wh2' then insert into public.warehouse_inventory(warehouse_id, product_id, current_qty) values (pg_temp.fx('wh2'), p, 10);
  else insert into public.store_inventory(store_id, product_id, current_qty) values (pg_temp.fx('store'), p, 10); end if;
  sp := public.upsert_special_product_from_product(null, p, 1000, 0, 0, 100, 0, 0);
  insert into fx values ('p_' || tag, p), ('sp_' || tag, sp);
end$$;
create function pg_temp.mkplain(tag text) returns void language plpgsql as
$$declare p uuid;
begin
  insert into public.products(name, sku, product_type) values ('C497 ' || tag, 'C497-' || tag, 'own') returning id into p;
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

-- ═════ A A line removed ═════
do $$
declare inv uuid; s uuid[]; res jsonb; mv uuid; other uuid; ret public.special_sale_returns%rowtype; m public.stock_movements%rowtype;
begin
  perform pg_temp.as_user('owner');
  perform pg_temp.mkspecial('a1'); perform pg_temp.mkspecial('a1k');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('a1'), pg_temp.sale_line('a1k')));
  perform pg_temp.pay(inv);
  select id into other from public.invoice_items where invoice_id = inv and special_product_id = pg_temp.fx('sp_a1k');
  s := array(select id from public.special_sales where invoice_id = inv and special_product_id = pg_temp.fx('sp_a1'));
  perform pg_temp.release(s[1]); mv := pg_temp.mv(s[1]);
  perform pg_temp.check(pg_temp.at_wh('a1') = 9, 'A0 released: 9 of 10 at the warehouse');
  res := pg_temp.correct(inv, jsonb_build_array(pg_temp.keep(other, 'a1k')));
  perform pg_temp.check(pg_temp.at_wh('a1') = 10, 'A1 the line removed: the released unit is back at the warehouse (10)');
  perform pg_temp.check(pg_temp.status_of(s[1]) = 'cancelled' and pg_temp.back(s[1]) and pg_temp.notes_of(s[1]) like '%Cancelled (line corrected): Check correction%',
    'A2 its sale is over: cancelled, stock back, "Cancelled (line corrected)", the reason kept');
  select * into ret from public.special_sale_returns where special_sale_id = s[1];
  select * into m from public.stock_movements where id = ret.return_movement_id;
  perform pg_temp.check(ret.why = 'line corrected' and ret.sellable_quantity = 1 and ret.damaged_quantity = 0 and ret.not_returned_quantity = 0
      and ret.reason = 'Check correction' and ret.movement_id = mv and ret.created_by = pg_temp.fx('owner'),
    'A3 special_sale_returns keeps it: line corrected, one sellable, who and why');
  perform pg_temp.check(m.movement_type::text = 'invoice_cancel_return' and m.to_warehouse_id = pg_temp.fx('wh') and m.quantity = 1 and m.reversed_sale_id = mv
      and m.invoice_id is null and m.notes like 'Special sale returned%' and m.notes like '%line corrected%',
    'A4 a Cancel Return movement into the warehouse, reversing the release, with no invoice id (the invoice''s own stock maths must not see it)');
  perform pg_temp.check(exists (select 1 from public.audit_logs a where a.action = 'special_sale_stock_returned' and a.record_id = s[1]
                                  and a.new_data->>'why' = 'line corrected' and a.new_data->>'location_type' = 'warehouse'),
    'A5 the Audit Log has it');
  perform pg_temp.check(pg_temp.states(res) = 'back' and pg_temp.said(res) = pg_temp.sale_no_of(s[1]) || ': C497 a1 goes back to ' || (select name from public.warehouses where id = pg_temp.fx('wh')),
    'A6 the answer says it, for the page: ' || pg_temp.said(res));
  perform pg_temp.check(not exists (select 1 from public.special_release_rows(inv) r where r.quantity > r.resolved_quantity and r.special_sale_id = s[1]),
    'A7 no refund or cancellation can offer it now');

  -- From a store
  perform pg_temp.mkspecial('a2', 'store'); perform pg_temp.mkspecial('a2k');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('a2'), pg_temp.sale_line('a2k')));
  perform pg_temp.pay(inv);
  select id into other from public.invoice_items where invoice_id = inv and special_product_id = pg_temp.fx('sp_a2k');
  s := array(select id from public.special_sales where invoice_id = inv and special_product_id = pg_temp.fx('sp_a2'));
  perform pg_temp.release(s[1], 'store');
  perform pg_temp.check(pg_temp.at_store('a2') = 9, 'A8 released from a store: 9 of 10');
  res := pg_temp.correct(inv, jsonb_build_array(pg_temp.keep(other, 'a2k')));
  perform pg_temp.check(pg_temp.at_store('a2') = 10 and pg_temp.status_of(s[1]) = 'cancelled' and pg_temp.back(s[1])
      and exists (select 1 from public.stock_movements m2 where m2.reversed_sale_id = pg_temp.mv(s[1]) and m2.to_store_id = pg_temp.fx('store') and m2.movement_type::text = 'invoice_cancel_return'),
    'A9 it goes back on the store it left');

  -- Waiting
  perform pg_temp.mkspecial('a3'); perform pg_temp.mkspecial('a3k');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('a3'), pg_temp.sale_line('a3k')));
  perform pg_temp.pay(inv);
  select id into other from public.invoice_items where invoice_id = inv and special_product_id = pg_temp.fx('sp_a3k');
  s := array(select id from public.special_sales where invoice_id = inv and special_product_id = pg_temp.fx('sp_a3'));
  res := pg_temp.correct(inv, jsonb_build_array(pg_temp.keep(other, 'a3k')));
  perform pg_temp.check(pg_temp.status_of(s[1]) = 'cancelled' and not pg_temp.back(s[1]) and pg_temp.at_wh('a3') = 10
      and pg_temp.notes_of(s[1]) like '%Cancelled (line removed)%' and not exists (select 1 from public.special_sale_returns where special_sale_id = s[1]),
    'A10 a waiting unit comes off as the line goes (393), no stock moves, no return recorded');
  perform pg_temp.check(pg_temp.states(res) = 'waiting_off' and pg_temp.said(res) like '%C497 a3 comes off the waiting list', 'A11 and the answer says so: ' || pg_temp.said(res));
end $$;

-- ═════ B A line lowered ═════
do $$
declare inv uuid; s uuid[]; res jsonb; line uuid; other uuid;
begin
  perform pg_temp.as_user('owner');
  -- Two released, lowered to one: the newest goes back.
  perform pg_temp.mkspecial('b1');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('b1', 2))); perform pg_temp.pay(inv);
  s := pg_temp.sales(inv); perform pg_temp.release(s[1]); perform pg_temp.release(s[2]); line := pg_temp.line_of(inv, 'b1');
  res := pg_temp.correct(inv, jsonb_build_array(pg_temp.keep(line, 'b1', 1)));
  perform pg_temp.check(pg_temp.at_wh('b1') = 9 and pg_temp.status_of(s[2]) = 'cancelled' and pg_temp.back(s[2]) and pg_temp.status_of(s[1]) = 'completed',
    'B1 two released, lowered to one: the newest goes back, the other stays (9 of 10)');
  perform pg_temp.check(pg_temp.states(res) = 'back', 'B2 and the answer says one went back: ' || pg_temp.said(res));

  -- One waiting and two released: the waiting one first, whichever is the oldest.
  perform pg_temp.mkspecial('b3');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('b3', 3))); perform pg_temp.pay(inv);
  s := pg_temp.sales(inv); perform pg_temp.release(s[2]); perform pg_temp.release(s[3]); line := pg_temp.line_of(inv, 'b3');
  res := pg_temp.correct(inv, jsonb_build_array(pg_temp.keep(line, 'b3', 2)));
  perform pg_temp.check(pg_temp.status_of(s[1]) = 'cancelled' and not pg_temp.back(s[1]) and pg_temp.notes_of(s[1]) like '%Cancelled (line corrected): Check correction%'
      and pg_temp.status_of(s[2]) = 'completed' and pg_temp.status_of(s[3]) = 'completed' and pg_temp.at_wh('b3') = 8,
    'B3 three lowered to two: the waiting unit comes off, though it is the oldest, and both released stay');
  perform pg_temp.check(pg_temp.states(res) = 'waiting_off', 'B4 the answer says so: ' || pg_temp.said(res));
  res := pg_temp.correct(inv, jsonb_build_array(pg_temp.keep(line, 'b3', 1)));
  perform pg_temp.check(pg_temp.status_of(s[3]) = 'cancelled' and pg_temp.back(s[3]) and pg_temp.status_of(s[2]) = 'completed' and pg_temp.at_wh('b3') = 9,
    'B5 lowered again to one: then the newest released goes back');

  -- Lowered by two at once
  perform pg_temp.mkspecial('b6');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('b6', 3))); perform pg_temp.pay(inv);
  s := pg_temp.sales(inv); perform pg_temp.release(s[1]); perform pg_temp.release(s[2]); line := pg_temp.line_of(inv, 'b6');
  res := pg_temp.correct(inv, jsonb_build_array(pg_temp.keep(line, 'b6', 1)));
  perform pg_temp.check(pg_temp.status_of(s[3]) = 'cancelled' and not pg_temp.back(s[3]) and pg_temp.status_of(s[2]) = 'cancelled' and pg_temp.back(s[2])
      and pg_temp.status_of(s[1]) = 'completed' and pg_temp.at_wh('b6') = 9 and pg_temp.states(res) = 'waiting_off,back',
    'B6 three lowered to one at once: the waiting one, then the newest released: ' || pg_temp.states(res));

  -- Two lines of one machine: only the lowered line's units.
  perform pg_temp.mkspecial('b7');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('b7', 2), pg_temp.sale_line('b7', 1))); perform pg_temp.pay(inv);
  select id into line from public.invoice_items where invoice_id = inv and quantity = 2;
  select id into other from public.invoice_items where invoice_id = inv and quantity = 1;
  s := array(select id from public.special_sales where invoice_id = inv and invoice_item_id = other);
  perform pg_temp.release(s[1]);
  res := pg_temp.correct(inv, jsonb_build_array(pg_temp.keep(line, 'b7', 1), pg_temp.keep(other, 'b7', 1)));
  perform pg_temp.check(pg_temp.status_of(s[1]) = 'completed' and pg_temp.at_wh('b7') = 9
      and (select count(*) from public.special_sales where invoice_item_id = line and status = 'pending') = 1
      and (select count(*) from public.special_sales where invoice_item_id = line and status = 'cancelled') = 1,
    'B7 two lines of one machine: lowering one touches the other line''s released unit not at all');

  -- A price change alone
  perform pg_temp.mkspecial('b8');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('b8', 2))); perform pg_temp.pay(inv);
  s := pg_temp.sales(inv); perform pg_temp.release(s[1]); line := pg_temp.line_of(inv, 'b8');
  res := public.correct_invoice(inv, jsonb_build_array(pg_temp.keep(line, 'b8', 2) || jsonb_build_object('unit_price', 900)), '{}'::jsonb, 'A better price', gen_random_uuid());
  perform pg_temp.check(pg_temp.states(res) = '' and pg_temp.status_of(s[1]) = 'completed' and pg_temp.status_of(s[2]) = 'pending' and pg_temp.at_wh('b8') = 9,
    'B8 a new price and the same quantity: no sale moves, nothing said');
end $$;

-- ═════ C Another machine on the line ═════
do $$
declare inv uuid; s uuid[]; res jsonb; line uuid; n uuid[]; sale public.special_sales%rowtype;
begin
  perform pg_temp.as_user('owner');
  perform pg_temp.mkspecial('c1'); perform pg_temp.mkspecial('c1n');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('c1'))); perform pg_temp.pay(inv);
  s := pg_temp.sales(inv); perform pg_temp.release(s[1]); line := pg_temp.line_of(inv, 'c1');
  res := pg_temp.correct(inv, jsonb_build_array(pg_temp.keep(line, 'c1n')));
  perform pg_temp.check(pg_temp.at_wh('c1') = 10 and pg_temp.status_of(s[1]) = 'cancelled' and pg_temp.back(s[1]),
    'C1 the released old machine goes back');
  n := array(select id from public.special_sales where invoice_id = inv and status = 'pending');
  select * into sale from public.special_sales where id = n[1];
  perform pg_temp.check(cardinality(n) = 1 and sale.special_product_id = pg_temp.fx('sp_c1n') and sale.invoice_item_id = line
      and sale.customer_id = pg_temp.fx('buyer') and sale.store_id = pg_temp.fx('store') and sale.quantity = 1 and sale.unit_price = 1000 and sale.total_amount = 1000
      and sale.sold_by = pg_temp.fx('owner') and sale.notes like 'From invoice % as corrected' and sale.sale_no like 'SPS-%',
    'C2 the new machine joins the waiting list, on the same line, with the invoice''s customer and store and the line''s price');
  perform pg_temp.check(pg_temp.states(res) = 'back,raised' and pg_temp.said(res) like '%1 more C497 c1n joins the waiting list', 'C3 the answer says both: ' || pg_temp.said(res));
  perform pg_temp.check(exists (select 1 from public.special_docs_awaiting_fulfilment() d where d.doc_id = n[1] and d.doc_kind = 'special_sale'),
    'C4 it is on the Special page''s waiting list');
  perform pg_temp.release(n[1]);
  perform pg_temp.check(pg_temp.at_wh('c1n') = 9 and pg_temp.status_of(n[1]) = 'completed', 'C5 and it can be released');
  perform pg_temp.check((select count(*) from public.special_release_rows(inv) r where r.quantity > r.resolved_quantity) = 1
      and (select r.special_sale_id from public.special_release_rows(inv) r where r.quantity > r.resolved_quantity) = n[1],
    'C6 a refund would offer only the new machine');

  -- A waiting old machine, and more of the new one
  perform pg_temp.mkspecial('c7'); perform pg_temp.mkspecial('c7n');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('c7'))); perform pg_temp.pay(inv);
  s := pg_temp.sales(inv); line := pg_temp.line_of(inv, 'c7');
  res := pg_temp.correct(inv, jsonb_build_array(pg_temp.keep(line, 'c7n', 2)));
  perform pg_temp.check(pg_temp.status_of(s[1]) = 'cancelled' and not pg_temp.back(s[1]) and pg_temp.at_wh('c7') = 10
      and (select count(*) from public.special_sales where invoice_id = inv and status = 'pending' and special_product_id = pg_temp.fx('sp_c7n')) = 2,
    'C7 a waiting old machine comes off, and two of the new one join');
  perform pg_temp.check(pg_temp.states(res) = 'waiting_off,raised' and pg_temp.said(res) like '%2 more C497 c7n join the waiting list%', 'C8 the answer: ' || pg_temp.said(res));
end $$;

-- ═════ D A raised quantity ═════
do $$
declare inv uuid; s uuid[]; res jsonb; line uuid; other uuid; n int;
begin
  perform pg_temp.as_user('owner');
  perform pg_temp.mkspecial('d1');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('d1'))); perform pg_temp.pay(inv);
  s := pg_temp.sales(inv); perform pg_temp.release(s[1]); line := pg_temp.line_of(inv, 'd1');
  res := pg_temp.correct(inv, jsonb_build_array(pg_temp.keep(line, 'd1', 3)));
  perform pg_temp.check(pg_temp.status_of(s[1]) = 'completed' and pg_temp.at_wh('d1') = 9
      and (select count(*) from public.special_sales where invoice_item_id = line and status = 'pending') = 2,
    'D1 raised from one to three: the released one stays, two more wait');
  perform pg_temp.check(pg_temp.states(res) = 'raised' and pg_temp.said(res) = '2 more C497 d1 join the waiting list; the invoice owes money, so take the payment before releasing it',
    'D2 the answer says so, and that the invoice owes money: ' || pg_temp.said(res));
  perform pg_temp.check((select status::text from public.invoices where id = inv) = 'partially_paid', 'D3 the invoice owes the difference');
  perform pg_temp.pay(inv);
  perform pg_temp.check((select status::text from public.invoices where id = inv) = 'paid'
      and (select count(*) from public.special_sales where invoice_item_id = line and status = 'pending') = 2
      and (select count(*) from public.special_sales where invoice_item_id = line) = 3,
    'D4 the payment does not raise them twice');

  -- A raise that leaves nothing owing does not say so.
  perform pg_temp.mkspecial('d5');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('d5'))); perform pg_temp.pay(inv);
  line := pg_temp.line_of(inv, 'd5');
  res := public.correct_invoice(inv, jsonb_build_array(pg_temp.keep(line, 'd5', 2) || jsonb_build_object('unit_price', 500)), '{}'::jsonb, 'Two at the price of one', gen_random_uuid());
  perform pg_temp.check(pg_temp.said(res) = '1 more C497 d5 joins the waiting list'
      and (select unit_price from public.special_sales where invoice_item_id = line and status = 'pending' order by sale_no desc limit 1) = 500,
    'D5 nothing owing: it does not say so, and the new unit has the line''s price: ' || pg_temp.said(res));

  -- A line with no sale at all stays as it is (the Owner, 6 Oct 2026).
  perform pg_temp.mkspecial('d6');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('d6'))); perform pg_temp.pay(inv);
  line := pg_temp.line_of(inv, 'd6');
  delete from public.special_sales where invoice_id = inv;
  res := pg_temp.correct(inv, jsonb_build_array(pg_temp.keep(line, 'd6', 2)));
  perform pg_temp.check(pg_temp.states(res) = '' and not exists (select 1 from public.special_sales where invoice_id = inv),
    'D6 a line with no sale at all stays as it is when raised');

  -- A line added to a paid invoice: raised as before, once.
  perform pg_temp.mkspecial('d7'); perform pg_temp.mkspecial('d7a');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('d7'))); perform pg_temp.pay(inv);
  line := pg_temp.line_of(inv, 'd7');
  res := pg_temp.correct(inv, jsonb_build_array(pg_temp.keep(line, 'd7'), pg_temp.sale_line('d7a', 2)));
  perform pg_temp.check(pg_temp.states(res) = '' and not exists (select 1 from public.special_sales where invoice_id = inv and special_product_id = pg_temp.fx('sp_d7a')),
    'D7 a line added to a paid invoice, which now owes for it: not raised yet, as before');
  perform pg_temp.pay(inv);
  perform pg_temp.check((select count(*) from public.special_sales where invoice_id = inv and special_product_id = pg_temp.fx('sp_d7a') and status = 'pending') = 2
      and (select count(*) from public.special_sales where invoice_id = inv and special_product_id = pg_temp.fx('sp_d7')) = 1,
    'D7b the payment raises it, once, and the other line''s sale stays one');
  -- One added free, so the invoice stays paid: raised at once, as before (393), once.
  perform pg_temp.mkspecial('d7f');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('d7'))); perform pg_temp.pay(inv);
  line := pg_temp.line_of(inv, 'd7');
  res := public.correct_invoice(inv, jsonb_build_array(pg_temp.keep(line, 'd7'), pg_temp.sale_line('d7f', 2) || jsonb_build_object('unit_price', 0)), '{}'::jsonb, 'A free extra', gen_random_uuid());
  perform pg_temp.check((select status::text from public.invoices where id = inv) = 'paid'
      and (select count(*) from public.special_sales where invoice_id = inv and special_product_id = pg_temp.fx('sp_d7f') and status = 'pending') = 2
      and (select count(*) from public.special_sales where invoice_id = inv and special_product_id = pg_temp.fx('sp_d7')) = 1,
    'D7c a line added and the invoice still paid: raised at once, once, as before');

  -- Unpaid: nothing raised until the payment, then the corrected quantity.
  perform pg_temp.mkspecial('d8');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('d8'))); line := pg_temp.line_of(inv, 'd8');
  res := pg_temp.correct(inv, jsonb_build_array(pg_temp.keep(line, 'd8', 2)));
  perform pg_temp.check(pg_temp.states(res) = '' and not exists (select 1 from public.special_sales where invoice_id = inv), 'D8 an unpaid invoice raised: nothing is raised yet');
  perform pg_temp.pay(inv);
  perform pg_temp.check((select count(*) from public.special_sales where invoice_id = inv and status = 'pending') = 2, 'D9 the payment raises the corrected two');
end $$;

-- ═════ E The summary ═════
do $$
declare inv uuid; s uuid[]; pv jsonb; res jsonb; line uuid; other uuid; e jsonb; seq_before bigint; n_before bigint; items jsonb; stock_before text;
begin
  perform pg_temp.as_user('owner');
  perform pg_temp.mkspecial('e1'); perform pg_temp.mkspecial('e1n');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('e1', 2))); perform pg_temp.pay(inv);
  s := pg_temp.sales(inv); perform pg_temp.release(s[1]); perform pg_temp.release(s[2]); line := pg_temp.line_of(inv, 'e1');
  items := jsonb_build_array(pg_temp.keep(line, 'e1n', 3));
  select last_value into seq_before from public.special_sale_no_seq;
  n_before := (select count(*) from public.special_sales where invoice_id = inv);
  pv := pg_temp.preview(inv, items);
  select x into e from jsonb_array_elements(pv->'effects') x where x->>'area' = 'special_sales';
  perform pg_temp.check(e is not null and e->>'change' = 'changed' and e->>'detail' like '%make sure it really came back%stock adjustment%',
    'E1 the summary has a Special sales entry that says to check the machine really came back');
  perform pg_temp.check(jsonb_array_length(e->'items') = 3
      and e->'items'->0->>'what' = pg_temp.sale_no_of(s[2]) || ': C497 e1 goes back to ' || (select name from public.warehouses where id = pg_temp.fx('wh'))
      and e->'items'->1->>'what' = pg_temp.sale_no_of(s[1]) || ': C497 e1 goes back to ' || (select name from public.warehouses where id = pg_temp.fx('wh'))
      and e->'items'->2->>'what' like '3 more C497 e1n join the waiting list%',
    'E2 it lists each sale in order: ' || (e->'items')::text);
  perform pg_temp.check(pg_temp.at_wh('e1') = 8 and pg_temp.status_of(s[1]) = 'completed' and pg_temp.status_of(s[2]) = 'completed'
      and (select count(*) from public.special_sales where invoice_id = inv) = n_before
      and not exists (select 1 from public.special_sale_returns where invoice_id = inv)
      and (select special_product_id from public.invoice_items where id = line) = pg_temp.fx('sp_e1'),
    'E3 and it changes nothing: stock, sales, returns and the line are as they were');
  perform pg_temp.check((select last_value from public.special_sale_no_seq) = seq_before, 'E4 and it uses up no sale number');
  res := pg_temp.correct(inv, items);
  perform pg_temp.check((select jsonb_agg(x->>'what') from jsonb_array_elements(e->'items') x) = (select jsonb_agg(x->>'what') from jsonb_array_elements(res->'special') x),
    'E5 the save says word for word what the summary said');
  perform pg_temp.check(pg_temp.at_wh('e1') = 10 and (select count(*) from public.special_sales where invoice_id = inv and status = 'pending') = 3, 'E6 and does it');

  -- Nothing to say: no entry.
  perform pg_temp.mkspecial('e7'); perform pg_temp.mkplain('e7p');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('e7'), pg_temp.prod_line('e7p', 2))); perform pg_temp.pay(inv);
  s := pg_temp.sales(inv); perform pg_temp.release(s[1]);
  line := pg_temp.line_of(inv, 'e7');
  select id into other from public.invoice_items where invoice_id = inv and line_kind::text = 'product';
  pv := pg_temp.preview(inv, jsonb_build_array(pg_temp.keep(line, 'e7'), pg_temp.keep_plain(other, 'e7p', 1)));
  perform pg_temp.check(not exists (select 1 from jsonb_array_elements(pv->'effects') x where x->>'area' = 'special_sales')
      and pv->'outcome' is not null,
    'E7 a correction of another line only: no Special sales entry');
  -- Only joining the list: no warning about a machine coming back.
  pv := pg_temp.preview(inv, jsonb_build_array(pg_temp.keep(line, 'e7', 2), pg_temp.keep_plain(other, 'e7p', 2)));
  select x into e from jsonb_array_elements(pv->'effects') x where x->>'area' = 'special_sales';
  perform pg_temp.check(e->>'detail' = 'Saving does what is listed here.' and e->'items'->0->>'what' like '1 more C497 e7 joins the waiting list%',
    'E8 only joining the list: the entry has no warning about a machine coming back: ' || (e->>'detail'));
end $$;

-- ═════ F After it ═════
do $$
declare inv uuid; s uuid[]; res jsonb; line uuid; req uuid := gen_random_uuid(); plan jsonb; pay uuid; n uuid[];
begin
  perform pg_temp.as_user('owner');
  -- The same request again
  perform pg_temp.mkspecial('f1');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('f1', 2))); perform pg_temp.pay(inv);
  s := pg_temp.sales(inv); perform pg_temp.release(s[1]); perform pg_temp.release(s[2]); line := pg_temp.line_of(inv, 'f1');
  res := pg_temp.correct(inv, jsonb_build_array(pg_temp.keep(line, 'f1', 1)), req);
  res := pg_temp.correct(inv, jsonb_build_array(pg_temp.keep(line, 'f1', 1)), req);
  perform pg_temp.check((res->>'replayed')::boolean and pg_temp.at_wh('f1') = 9 and (select count(*) from public.special_sale_returns where invoice_id = inv) = 1,
    'F1 the same request again replays: nothing goes back twice');
  -- A new request with the same lines
  res := pg_temp.correct(inv, jsonb_build_array(pg_temp.keep(line, 'f1', 1)));
  perform pg_temp.check(pg_temp.states(res) = '' and pg_temp.at_wh('f1') = 9, 'F2 a new save of the same lines moves nothing');

  -- Then a cancellation: the unit that went back is not put back again.
  res := public.cancel_invoice_recorded(inv, 'Check cancellation', gen_random_uuid());
  perform pg_temp.check(pg_temp.at_wh('f1') = 10 and pg_temp.status_of(s[1]) = 'cancelled' and pg_temp.status_of(s[2]) = 'cancelled'
      and (select count(*) from public.special_sale_returns where invoice_id = inv) = 2
      and (select count(*) from public.stock_movements where product_id = pg_temp.fx('p_f1') and movement_type::text = 'invoice_cancel_return') = 2,
    'F3 then cancelled: the other unit goes back, each once (10 of 10, not 11)');

  -- Then a refund: only the unit still out is asked about.
  perform pg_temp.mkspecial('f4');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('f4', 2))); perform pg_temp.pay(inv);
  s := pg_temp.sales(inv); perform pg_temp.release(s[1]); perform pg_temp.release(s[2]); line := pg_temp.line_of(inv, 'f4');
  res := pg_temp.correct(inv, jsonb_build_array(pg_temp.keep(line, 'f4', 1)));
  perform pg_temp.pay_down(inv);
  plan := public.invoice_action_plan(inv, 'refund_full', '[]');
  perform pg_temp.check(jsonb_array_length(plan->'stock') = 1 and plan->'stock'->0->>'sale_no' = pg_temp.sale_no_of(s[1]),
    'F4 a full refund asks about the one unit still out');
  perform pg_temp.check(pg_temp.err(format('select public.refund_invoice_recorded(%L, %L, %L, %L, %L, %L)', inv,
        jsonb_build_array(jsonb_build_object('invoice_item_id', line, 'amount', 1000)),
        jsonb_build_array(jsonb_build_object('payment_id', pg_temp.current_payment(inv), 'amount', 1000)),
        pg_temp.answer(pg_temp.mv(s[2]), 1, 0, 0), 'Check refund', gen_random_uuid())) in ('Stock disposition exceeds the unresolved deduction', 'Record the returned-and-sellable, damaged, or not-returned quantities for this special sale refund'),
    'F5 an answer for the unit that went back is refused');
  perform pg_temp.check(pg_temp.at_wh('f4') = 9, 'F6 and no stock moved');
  res := pg_temp.refund_line(inv, line, 1000, pg_temp.answer(pg_temp.mv(s[1]), 1, 0, 0));
  perform pg_temp.check(pg_temp.at_wh('f4') = 10 and pg_temp.status_of(s[1]) = 'cancelled', 'F7 the refund of the unit still out puts it back (10 of 10)');

  -- Reopened and paid again: what the corrected line holds.
  perform public.reopen_invoice(inv, 'Customer came back for it', gen_random_uuid());
  perform pg_temp.pay(inv);
  perform pg_temp.check((select quantity from public.invoice_items where id = line) = 1
      and (select count(*) from public.special_sales where invoice_id = inv and status = 'pending') = 1,
    'F8 reopened and paid again: one waits, the line''s one, not two');

  -- Lowered and raised again later: a new unit.
  perform pg_temp.mkspecial('f9');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('f9', 2))); perform pg_temp.pay(inv);
  s := pg_temp.sales(inv); perform pg_temp.release(s[1]); perform pg_temp.release(s[2]); line := pg_temp.line_of(inv, 'f9');
  res := pg_temp.correct(inv, jsonb_build_array(pg_temp.keep(line, 'f9', 1)));
  res := pg_temp.correct(inv, jsonb_build_array(pg_temp.keep(line, 'f9', 2)));
  perform pg_temp.check(pg_temp.at_wh('f9') = 9 and pg_temp.status_of(s[1]) = 'completed' and pg_temp.status_of(s[2]) = 'cancelled'
      and (select count(*) from public.special_sales where invoice_item_id = line and status = 'pending') = 1,
    'F9 lowered, then raised again: a new unit waits, the old one stays over');
end $$;

-- ═════ G A line with a refund ═════
do $$
declare inv uuid; s uuid[]; res jsonb; line uuid; t text; other uuid;
begin
  perform pg_temp.as_user('owner');
  -- One of two refunded, not returned: lowering the line to the one left moves nothing.
  perform pg_temp.mkspecial('g1');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('g1', 2))); perform pg_temp.pay(inv);
  s := pg_temp.sales(inv); perform pg_temp.release(s[1]); perform pg_temp.release(s[2]); line := pg_temp.line_of(inv, 'g1');
  res := pg_temp.refund_line(inv, line, 1000, pg_temp.answer(pg_temp.mv(s[1]), 0, 0, 1));
  perform pg_temp.check(pg_temp.at_wh('g1') = 8 and pg_temp.status_of(s[1]) = 'completed', 'G0 one of two refunded, not returned: nothing back');
  res := pg_temp.correct(inv, jsonb_build_array(pg_temp.keep(line, 'g1', 1)));
  perform pg_temp.check(pg_temp.states(res) = '' and pg_temp.at_wh('g1') = 8 and pg_temp.status_of(s[2]) = 'completed',
    'G1 the line lowered to the one left: the customer keeps it, nothing moves');

  -- One of two refunded and back: the same.
  perform pg_temp.mkspecial('g2');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('g2', 2))); perform pg_temp.pay(inv);
  s := pg_temp.sales(inv); perform pg_temp.release(s[1]); perform pg_temp.release(s[2]); line := pg_temp.line_of(inv, 'g2');
  res := pg_temp.refund_line(inv, line, 1000, pg_temp.answer(pg_temp.mv(s[1]), 1, 0, 0));
  perform pg_temp.check(pg_temp.at_wh('g2') = 9 and pg_temp.status_of(s[1]) = 'cancelled', 'G2 one of two refunded and back: 9');
  res := pg_temp.correct(inv, jsonb_build_array(pg_temp.keep(line, 'g2', 1)));
  perform pg_temp.check(pg_temp.states(res) = '' and pg_temp.at_wh('g2') = 9 and pg_temp.status_of(s[2]) = 'completed',
    'G3 the line lowered to the one left: nothing moves');

  -- Another machine on a line with a refund: refused in words.
  perform pg_temp.mkspecial('g4'); perform pg_temp.mkspecial('g4n');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('g4', 2))); perform pg_temp.pay(inv);
  s := pg_temp.sales(inv); perform pg_temp.release(s[1]); perform pg_temp.release(s[2]); line := pg_temp.line_of(inv, 'g4');
  res := pg_temp.refund_line(inv, line, 1000, pg_temp.answer(pg_temp.mv(s[1]), 0, 0, 1));
  t := pg_temp.err(format('select pg_temp.correct(%L, %L)', inv, jsonb_build_array(pg_temp.keep(line, 'g4n', 2))));
  perform pg_temp.check(t = 'A refund is recorded on this line, so its machine cannot be changed. Keep the line as it is and add the other machine as a new line.',
    'G4 another machine on a line with a refund is refused in words: ' || t);
  perform pg_temp.check(pg_temp.at_wh('g4') = 8 and (select special_product_id from public.invoice_items where id = line) = pg_temp.fx('sp_g4') and pg_temp.status_of(s[2]) = 'completed',
    'G5 and nothing moved');

  -- Removing a line with a refund: refused as before, nothing moves.
  perform pg_temp.mkspecial('g6'); perform pg_temp.mkspecial('g6k');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('g6', 2), pg_temp.sale_line('g6k'))); perform pg_temp.pay(inv);
  line := pg_temp.line_of(inv, 'g6'); other := pg_temp.line_of(inv, 'g6k');
  s := array(select id from public.special_sales where invoice_item_id = line order by sale_no);
  perform pg_temp.release(s[1]); perform pg_temp.release(s[2]);
  res := pg_temp.refund_line(inv, line, 1000, pg_temp.answer(pg_temp.mv(s[1]), 0, 0, 1));
  t := pg_temp.err(format('select pg_temp.correct(%L, %L)', inv, jsonb_build_array(pg_temp.keep(other, 'g6k'))));
  perform pg_temp.check(t like 'Commission review required: a refunded original invoice line is unavailable%' and pg_temp.at_wh('g6') = 8 and pg_temp.status_of(s[2]) = 'completed',
    'G6 removing a line with a refund is refused as before, and nothing moves: ' || t);
end $$;

-- ═════ H A machine a supplier sent ═════
do $$
declare inv uuid; s uuid[]; res jsonb; line uuid; other uuid; sup uuid;
begin
  perform pg_temp.as_user('owner');
  perform pg_temp.mkspecial('h1'); perform pg_temp.mkspecial('h1k');
  insert into public.suppliers(name, phone) values ('C497 Supplier', '+61255509902') returning id into sup;
  insert into public.product_suppliers(product_id, supplier_id) values (pg_temp.fx('p_h1'), sup);
  perform public.set_special_product_consignment(pg_temp.fx('sp_h1'), true);
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('h1'), pg_temp.sale_line('h1k'))); perform pg_temp.pay(inv);
  line := pg_temp.line_of(inv, 'h1'); other := pg_temp.line_of(inv, 'h1k');
  s := array(select id from public.special_sales where invoice_item_id = line);
  perform public.release_special_sale_to_supplier(s[1], sup, 'Check Road');
  res := pg_temp.correct(inv, jsonb_build_array(pg_temp.keep(other, 'h1k')));
  perform pg_temp.check(pg_temp.status_of(s[1]) = 'completed' and pg_temp.at_wh('h1') = 10 and not exists (select 1 from public.special_sale_returns where special_sale_id = s[1]),
    'H1 a machine a supplier sent, its line removed: the sale stays, no stock moves');
  perform pg_temp.check(pg_temp.states(res) = 'stays' and pg_temp.said(res) like '%C497 h1 stays as it is, and no stock moves: C497 Supplier sent it', 'H2 and the answer says so: ' || pg_temp.said(res));

  -- Lowered, with one from the warehouse and one from the supplier: the warehouse's comes off.
  perform pg_temp.mkspecial('h3');
  insert into public.product_suppliers(product_id, supplier_id) values (pg_temp.fx('p_h3'), sup);
  perform public.set_special_product_consignment(pg_temp.fx('sp_h3'), true);
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('h3', 2))); perform pg_temp.pay(inv);
  s := pg_temp.sales(inv); line := pg_temp.line_of(inv, 'h3');
  perform pg_temp.release(s[1]);
  perform public.release_special_sale_to_supplier(s[2], sup, 'Check Road');
  res := pg_temp.correct(inv, jsonb_build_array(pg_temp.keep(line, 'h3', 1)));
  perform pg_temp.check(pg_temp.at_wh('h3') = 10 and pg_temp.status_of(s[1]) = 'cancelled' and pg_temp.status_of(s[2]) = 'completed' and pg_temp.states(res) = 'back',
    'H3 one from the warehouse and one from a supplier, lowered to one: the warehouse''s goes back, though it is the older');

  -- Released, with no movement to reverse (none on production; 496 linked all 8): it stays, and says why.
  perform pg_temp.mkspecial('h4'); perform pg_temp.mkspecial('h4k');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('h4'), pg_temp.sale_line('h4k'))); perform pg_temp.pay(inv);
  line := pg_temp.line_of(inv, 'h4'); other := pg_temp.line_of(inv, 'h4k');
  s := array(select id from public.special_sales where invoice_item_id = line);
  perform pg_temp.release(s[1]);
  update public.special_sales set release_movement_id = null where id = s[1];
  res := pg_temp.correct(inv, jsonb_build_array(pg_temp.keep(other, 'h4k')));
  perform pg_temp.check(pg_temp.status_of(s[1]) = 'completed' and pg_temp.at_wh('h4') = 9 and pg_temp.states(res) = 'stays'
      and pg_temp.said(res) like '%C497 h4 stays as it is, and no stock moves: it has no stock movement to reverse',
    'H4 a released sale with no movement to reverse stays, and the answer says why: ' || pg_temp.said(res));
end $$;

-- ═════ J A warehouse or store since deleted ═════
do $$
declare inv uuid; s uuid[]; res jsonb; line uuid; other uuid; t text; pv jsonb; st uuid;
begin
  perform pg_temp.as_user('owner');
  perform pg_temp.mkspecial('j1', 'wh2'); perform pg_temp.mkspecial('j1k');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('j1'), pg_temp.sale_line('j1k'))); perform pg_temp.pay(inv);
  line := pg_temp.line_of(inv, 'j1'); other := pg_temp.line_of(inv, 'j1k');
  s := array(select id from public.special_sales where invoice_item_id = line);
  perform pg_temp.release(s[1], 'wh2');
  update public.warehouse_inventory set current_qty = 0 where warehouse_id = pg_temp.fx('wh2') and product_id = pg_temp.fx('p_j1');
  update public.warehouses set deleted_at = now() where id = pg_temp.fx('wh2');
  t := pg_temp.err(format('select pg_temp.correct(%L, %L)', inv, jsonb_build_array(pg_temp.keep(other, 'j1k'))));
  perform pg_temp.check(t like '%left C497 Warehouse B%, which has been deleted, so it cannot go back there. Restore C497 Warehouse B% first, or take it back with Refund, which can record it as not returned.',
    'J1 a warehouse since deleted: refused in words: ' || t);
  perform pg_temp.check(exists (select 1 from public.invoice_items where id = line) and pg_temp.status_of(s[1]) = 'completed' and not exists (select 1 from public.special_sale_returns where special_sale_id = s[1]),
    'J2 and the correction is undone whole: the line is there, the sale as it was');
  pv := pg_temp.preview(inv, jsonb_build_array(pg_temp.keep(other, 'j1k')));
  perform pg_temp.check((pv->>'blocking')::boolean and (pv->'needs_review')::text like '%which has been deleted%',
    'J3 the summary shows the refusal before anyone saves');
  update public.warehouses set deleted_at = null where id = pg_temp.fx('wh2');
  res := pg_temp.correct(inv, jsonb_build_array(pg_temp.keep(other, 'j1k')));
  perform pg_temp.check(pg_temp.states(res) = 'back' and pg_temp.at_wh('j1', 'wh2') = 1, 'J4 restored, it goes back');

  -- A store
  insert into public.stores(name, code, country_code) values ('C497 Store C', 'C497C', 'SG') returning id into st;
  insert into fx values ('store3', st);
  perform pg_temp.mkspecial('j5'); perform pg_temp.mkspecial('j5k');
  insert into public.store_inventory(store_id, product_id, current_qty) values (st, pg_temp.fx('p_j5'), 1);
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('j5'), pg_temp.sale_line('j5k'))); perform pg_temp.pay(inv);
  line := pg_temp.line_of(inv, 'j5'); other := pg_temp.line_of(inv, 'j5k');
  s := array(select id from public.special_sales where invoice_item_id = line);
  perform public.fulfil_special_doc('special_sale', s[1], st, 'store');
  update public.stores set deleted_at = now() where id = st;
  t := pg_temp.err(format('select pg_temp.correct(%L, %L)', inv, jsonb_build_array(pg_temp.keep(other, 'j5k'))));
  perform pg_temp.check(t like '%left C497 Store C, which has been deleted%' and pg_temp.status_of(s[1]) = 'completed', 'J5 a store since deleted: the same: ' || t);
end $$;

-- ═════ K As before ═════
do $$
declare inv uuid; s uuid[]; res jsonb; line uuid; other uuid; r uuid; before jsonb; before_stock bigint; rp uuid;
begin
  perform pg_temp.as_user('owner');
  -- A cancelled invoice: left as it is, whatever is asked, even with a unit still out
  -- (one above its line's quantity from before 497, which a cancellation leaves alone).
  perform pg_temp.mkspecial('k1');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('k1', 3))); perform pg_temp.pay(inv);
  s := pg_temp.sales(inv); perform pg_temp.release(s[1]); perform pg_temp.release(s[2]); perform pg_temp.release(s[3]); line := pg_temp.line_of(inv, 'k1');
  before := (select jsonb_agg(to_jsonb(it)) from public.invoice_items it where it.id = line);
  update public.invoice_items set quantity = 1 where id = line;
  res := public.cancel_invoice_recorded(inv, 'Check cancellation', gen_random_uuid());
  perform pg_temp.check(pg_temp.status_of(s[1]) = 'cancelled' and pg_temp.status_of(s[2]) = 'completed' and pg_temp.status_of(s[3]) = 'completed' and pg_temp.at_wh('k1') = 8,
    'K0 cancelled: the unit on the line back, the two above it still out');
  res := jsonb_build_object('special', public.invoice_special_sales_follow_lines(inv, before, 'Check', null));
  perform pg_temp.check(pg_temp.states(res) = '' and pg_temp.status_of(s[3]) = 'completed' and pg_temp.at_wh('k1') = 8, 'K1 a cancelled invoice is left as it is');

  -- A rental beside a special sale: not touched, and its line's rules as before.
  perform pg_temp.mkspecial('k2'); perform pg_temp.mkspecial('k2r');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('k2', 2),
           jsonb_build_object('kind', 'rental', 'special_product_id', pg_temp.fx('sp_k2r'), 'quantity', 1,
             'rental_rate_type', 'month', 'rental_periods', 1, 'rental_start_date', public.sg_today()::text)));
  perform pg_temp.pay(inv);
  s := pg_temp.sales(inv); perform pg_temp.release(s[1]); perform pg_temp.release(s[2]);
  select id into r from public.rentals where invoice_id = inv;
  perform public.fulfil_special_doc('rental', r, pg_temp.fx('wh'), 'warehouse');
  line := pg_temp.line_of(inv, 'k2');
  select id into other from public.invoice_items where invoice_id = inv and line_kind::text = 'rental';
  res := pg_temp.correct(inv, jsonb_build_array(pg_temp.keep(line, 'k2', 1),
           jsonb_build_object('invoice_item_id', other, 'kind', 'rental', 'special_product_id', pg_temp.fx('sp_k2r'), 'quantity', 1,
             'rental_rate_type', 'month', 'rental_periods', 1, 'rental_start_date', public.sg_today()::text)));
  perform pg_temp.check(pg_temp.at_wh('k2') = 9 and pg_temp.at_wh('k2r') = 9 and (select status::text from public.rentals where id = r) = 'active' and pg_temp.states(res) = 'back',
    'K2 a rental out beside it: the rental stays out, only the special sale goes back');

  -- An ordinary product beside it: its stock as before, and the machine's untouched by the product's restore.
  perform pg_temp.mkspecial('k3'); perform pg_temp.mkplain('k3p');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('k3', 2), pg_temp.prod_line('k3p', 3))); perform pg_temp.pay(inv);
  s := pg_temp.sales(inv); perform pg_temp.release(s[1]); perform pg_temp.release(s[2]);
  line := pg_temp.line_of(inv, 'k3'); select id into other from public.invoice_items where invoice_id = inv and line_kind::text = 'product';
  perform pg_temp.check(pg_temp.at_store('k3p') = 7, 'K3 the product took 3 of 10');
  res := pg_temp.correct(inv, jsonb_build_array(pg_temp.keep(line, 'k3', 2), pg_temp.keep_plain(other, 'k3p', 1)));
  perform pg_temp.check(pg_temp.at_store('k3p') = 9 and pg_temp.at_wh('k3') = 8 and pg_temp.status_of(s[1]) = 'completed' and pg_temp.status_of(s[2]) = 'completed' and pg_temp.states(res) = '',
    'K4 the product lowered: its stock back (9), the machines untouched');
  res := pg_temp.correct(inv, jsonb_build_array(pg_temp.keep(line, 'k3', 1), pg_temp.keep_plain(other, 'k3p', 1)));
  perform pg_temp.check(pg_temp.at_store('k3p') = 9 and pg_temp.at_wh('k3') = 9 and pg_temp.states(res) = 'back',
    'K5 the machine lowered: one machine back (9), the product''s stock as it was (9)');

  -- Known limits, as before 497: a waiting sale keeps its own customer when the invoice's is corrected,
  -- and can be released while the invoice owes money (a rental cannot, 458).
  perform pg_temp.mkspecial('k6');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('k6'))); perform pg_temp.pay(inv);
  s := pg_temp.sales(inv); line := pg_temp.line_of(inv, 'k6');
  insert into public.customers(full_name, phone) values ('C497 Other Buyer', '+61255509903') returning id into rp;
  res := public.correct_invoice(inv, jsonb_build_array(pg_temp.keep(line, 'k6')), jsonb_build_object('customer_id', rp), 'Wrong customer', gen_random_uuid());
  perform pg_temp.check((select customer_id from public.invoices where id = inv) = rp
      and (select customer_id from public.special_sales where id = s[1]) = pg_temp.fx('buyer'),
    'K6 as before: a correction of the invoice''s customer leaves a waiting sale''s own customer');
  res := pg_temp.correct(inv, jsonb_build_array(pg_temp.keep(line, 'k6', 2)));
  perform pg_temp.check((select status::text from public.invoices where id = inv) = 'partially_paid', 'K7 raised: the invoice owes money');
  perform pg_temp.check(pg_temp.err(format('select pg_temp.release(%L)', (select id from public.special_sales where invoice_item_id = line and status = 'pending' order by sale_no desc limit 1))) = 'ok',
    'K8 as before: a waiting sale can be released while its invoice owes money');
end $$;

-- ═════ N Who ═════
do $$
declare inv uuid; s uuid[]; res jsonb; line uuid; t text;
begin
  perform pg_temp.as_user('owner');
  perform pg_temp.mkspecial('n1');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('n1', 2))); perform pg_temp.pay(inv);
  s := pg_temp.sales(inv); perform pg_temp.release(s[1]); perform pg_temp.release(s[2]); line := pg_temp.line_of(inv, 'n1');
  perform pg_temp.as_user('other');
  t := pg_temp.err(format('select pg_temp.correct(%L, %L)', inv, jsonb_build_array(pg_temp.keep(line, 'n1', 1))));
  perform pg_temp.check(t <> 'ok' and pg_temp.at_wh('n1') = 8, 'N1 staff of another store cannot: ' || t);
  perform pg_temp.as_user('staff');
  res := pg_temp.correct(inv, jsonb_build_array(pg_temp.keep(line, 'n1', 1)));
  perform pg_temp.check(pg_temp.states(res) = 'back' and pg_temp.at_wh('n1') = 9
      and (select created_by from public.special_sale_returns where special_sale_id = s[2]) = pg_temp.fx('staff'),
    'N2 staff of the store do it, as they do a product''s stock, and the record names them');
  perform pg_temp.check(not has_function_privilege('authenticated', 'public.invoice_special_sales_follow_lines(uuid,jsonb,text,uuid)', 'execute')
      and not has_function_privilege('anon', 'public.invoice_special_sales_follow_lines(uuid,jsonb,text,uuid)', 'execute')
      and has_function_privilege('service_role', 'public.invoice_special_sales_follow_lines(uuid,jsonb,text,uuid)', 'execute'),
    'N3 nobody signed in can call the new function; it is internal');
  perform pg_temp.as_user('owner');
end $$;

-- ═════ O Reopened, not yet paid again ═════
do $$
declare inv uuid; s uuid[]; res jsonb; line uuid;
begin
  perform pg_temp.as_user('owner');
  -- A waiting unit cancelled by the refund: nothing counts, so the payment raises the whole line.
  perform pg_temp.mkspecial('o1');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('o1'))); perform pg_temp.pay(inv);
  s := pg_temp.sales(inv); line := pg_temp.line_of(inv, 'o1');
  res := pg_temp.refund_line(inv, line, 1000, '[]'::jsonb);
  perform public.reopen_invoice(inv, 'Customer came back for it', gen_random_uuid());
  res := pg_temp.correct(inv, jsonb_build_array(pg_temp.keep(line, 'o1', 2)));
  perform pg_temp.check(pg_temp.states(res) = '' and (select count(*) from public.special_sales where invoice_item_id = line and status = 'pending') = 0,
    'O1 reopened, a waiting unit gone with the refund, raised to two: nothing is raised yet');
  perform pg_temp.pay(inv);
  perform pg_temp.check((select count(*) from public.special_sales where invoice_item_id = line and status = 'pending') = 2, 'O2 the payment raises the two');

  -- A released unit not returned still counts, so the payment would pass the line over: raised now.
  perform pg_temp.mkspecial('o3');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('o3'))); perform pg_temp.pay(inv);
  s := pg_temp.sales(inv); perform pg_temp.release(s[1]); line := pg_temp.line_of(inv, 'o3');
  res := pg_temp.refund_line(inv, line, 1000, pg_temp.answer(pg_temp.mv(s[1]), 0, 0, 1));
  perform public.reopen_invoice(inv, 'Customer came back for it', gen_random_uuid());
  res := pg_temp.correct(inv, jsonb_build_array(pg_temp.keep(line, 'o3', 2)));
  perform pg_temp.check(pg_temp.states(res) = 'raised' and (select count(*) from public.special_sales where invoice_item_id = line and status = 'pending') = 1,
    'O3 reopened, a unit not returned, raised to two: one joins the list now, as the payment would pass the line over');
  perform pg_temp.pay(inv);
  perform pg_temp.check((select count(*) from public.special_sales where invoice_item_id = line and status = 'pending') = 1
      and pg_temp.status_of(s[1]) = 'completed' and pg_temp.at_wh('o3') = 9,
    'O4 the payment does not raise it twice');

  -- A unit back, the other not returned: lowered on the way, the sums still hold.
  perform pg_temp.mkspecial('o5');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('o5', 3))); perform pg_temp.pay(inv);
  s := pg_temp.sales(inv); perform pg_temp.release(s[1]); perform pg_temp.release(s[2]); perform pg_temp.release(s[3]); line := pg_temp.line_of(inv, 'o5');
  res := pg_temp.correct(inv, jsonb_build_array(pg_temp.keep(line, 'o5', 2)));
  perform pg_temp.check(pg_temp.status_of(s[3]) = 'cancelled' and pg_temp.at_wh('o5') = 8, 'O5 three lowered to two: the newest back (8)');
  perform pg_temp.pay_down(inv);
  res := pg_temp.refund_line(inv, line, null, pg_temp.answer(pg_temp.mv(s[1]), 0, 0, 1) || pg_temp.answer(pg_temp.mv(s[2]), 1, 0, 0));
  perform public.reopen_invoice(inv, 'Customer came back for them', gen_random_uuid());
  perform pg_temp.pay(inv);
  perform pg_temp.check((select count(*) from public.special_sales where invoice_item_id = line and status = 'pending') = 1
      and (select quantity from public.invoice_items where id = line) = 2 and pg_temp.at_wh('o5') = 9,
    'O6 refunded (one not returned, one back), reopened and paid: one waits, so the line''s two are one out and one waiting');
end $$;

-- ═════ S Access ═════
select pg_temp.check(not exists (
    select 1 from acl_before b join pg_proc p on p.oid::regprocedure::text = b.sig
     where b.acl is distinct from (select coalesce(string_agg(x::text, ',' order by x::text), '') from unnest(p.proacl) x)),
  'S1 the patched functions keep their grants');
select pg_temp.check(has_function_privilege('authenticated', 'public.correct_invoice(uuid,jsonb,jsonb,text,uuid)', 'execute')
    and has_function_privilege('authenticated', 'public.preview_invoice_correction(uuid,jsonb)', 'execute')
    and not has_function_privilege('authenticated', 'public.return_released_special_stock(uuid,uuid,integer,integer,integer,uuid,text,text)', 'execute')
    and not has_function_privilege('authenticated', 'public.restore_released_special_stock(uuid,text,uuid)', 'execute'),
  'S2 the two pages'' calls stay callable, the two stock helpers stay internal');

-- ═════ U UNDO ═════
\if :{?skip_install}
do $$ begin raise notice 'NOTE  U1-U3 are skipped: 497 is in already'; end $$;
\else
create temp table after_install as select pg_temp.fp() f;
\ir ../undo-497.sql
select pg_temp.check(to_regprocedure('public.invoice_special_sales_follow_lines(uuid,jsonb,text,uuid)') is null
    and split_part(pg_temp.fp(), ' ', 2)::int = split_part((select f from after_install), ' ', 2)::int - 1,
  'U1 undo drops the function');
select pg_temp.check(pg_temp.md5_of('correct_invoice(uuid,jsonb,jsonb,text,uuid)') = '04d647e13e9424a9375942e5812e91a2'
    and pg_temp.md5_of('preview_invoice_correction(uuid,jsonb)') = 'f26752231c100461e11caddc03c98a33'
    and pg_temp.md5_of('return_released_special_stock(uuid,uuid,integer,integer,integer,uuid,text,text)') = '71c22eb51b75650836e09a95b827c0fe'
    and pg_temp.md5_of('restore_released_special_stock(uuid,text,uuid)') = '5f1b3d1d0c78a0c49d7fc2171301f5d1',
  'U2 and the four are production''s texts again');
select pg_temp.check((select f from before_install) = pg_temp.fp(), 'U3 the whole fingerprint is back: ' || pg_temp.fp());
\ir ../../../supabase/497_correction_follows_special_sales.sql
select pg_temp.check(pg_temp.fp() = (select f from after_install), 'U4 497 again gives back exactly what it gave: ' || pg_temp.fp());
\endif

-- ═════ Done ═════
do $$
declare n int; msgs text;
begin
  select count(*), string_agg(msg, E'\n') into n, msgs from failed;
  if n > 0 then raise exception '% check(s) failed:%', n, E'\n' || msgs; end if;
  raise notice 'All 497 checks passed.';
end $$;
rollback;
