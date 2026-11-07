-- 496: a refund or a cancellation of a special sale already released from a warehouse or a
-- store asks what came back and puts what is sellable back where it left (the user, 6 Nov
-- 2026), through the app's own calls.
--
--   I  496 installs (four functions added, seven replaced), a second run changes nothing,
--      its self-test leaves no row; the column and the table are there.
--   L  A release links its sale to its movement (warehouse and store); the units are
--      offered to the refund screen and the guided plan, a waiting or supplier-sent one not,
--      a rental's not; a part refund lists as many units as are refunded; a sale released
--      before 496 is linked where the match is certain, and only there.
--   R  Refund in full, the screen's way (plan, request, approve): sellable goes back on the
--      warehouse or the store it left, with a Refund Return movement; the sale is over,
--      "Cancelled (refunded)", stock back; the answer and the Audit Log keep it.
--   D  Damaged and not returned add nothing, the sale stays released; a unit cannot be
--      answered twice.
--   G  Refused: a refund of the line with no answer, another invoice's movement, more than
--      is out, an answer of nothing; the same request replays; money is what it was.
--   Q  A part refund of a two-unit line: one unit asked, one back; the rest asked later.
--   C  A cancellation: the guided one takes the confirmed answers and puts back the rest;
--      one with no answer puts everything back; cancel with the refund recorded.
--   M  A special sale and an ordinary product on one invoice: each its own stock.
--   X  The same product on both lines: each line gets its own units, a refund of one
--      line offers that line's unit alone, and the invoice's own stock maths is untouched.
--   Y  Two special lines on one invoice, a warehouse's and a store's: refunded one by one.
--   O  Reopened and paid again: a unit that came back is raised afresh and taken again; one
--      that did not come back is not raised twice.
--   W  Waiting sales, supplier-sent sales (494) and rentals: as before.
--   F  The review's cases: a released and a waiting unit on one line, answers for the wrong
--      line, a refund that strands a unit, mixed outcomes then reopening, a correction
--      then a cancellation, a shelf (warehouse or store) deleted or without a stock row, a
--      line of one released and one waiting unit refunded then reopened, a waiting unit of
--      another line that excuses nothing.
--   H  Stock History shows the return at the shelf.
--   S  Access: the table is read by staff of the store alone; the four new functions are
--      internal; the patched ones keep their grants; what 496 does not touch is untouched.
--   U  UNDO puts the seven functions back to production's texts; 496 again puts them in.
--
-- Run on a copy of production at 494 or later (createdb -T of a template equal to it; never
-- the template itself):
--   psql -X -d <copy> -v ON_ERROR_STOP=1 -f scripts/special/tests/released-return-496.sql
-- (with -v skip_install=1 where 496 is in). Every check runs, then the file fails if any
-- did. Everything is rolled back. Every name, phone and email is invented (+61 2 5550 ....,
-- @example.invalid); the repository is public.
-- Note for edits: a check that calls a function and reads what it changed in ONE expression
-- reads the snapshot from before the call; call first, then check.
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '10s';
create temp table failed(n serial, msg text);
create function pg_temp.check(ok boolean, msg text) returns void language plpgsql as
$$begin
  if ok is distinct from true then insert into failed(msg) values (msg); raise notice 'FAIL  %', msg;
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
-- Signed in as a login of the fixtures, or signed out (null).
create function pg_temp.as_user(key text) returns void language sql as
$$ select set_config('request.jwt.claim.sub', coalesce(pg_temp.fx(key)::text, ''), true),
          set_config('request.jwt.claim.role', case when key is null then 'anon' else 'authenticated' end, true),
          set_config('request.jwt.claims', '', true) $$;

-- ═════ I Installs ═════
create temp table before_install as select pg_temp.fp() f;
\if :{?skip_install}
do $$ begin raise notice 'NOTE  I1-I2 are skipped: 496 is in already'; end $$;
\else
\ir ../../../supabase/496_released_special_sale_stock_comes_back.sql
create temp table after_first as select pg_temp.fp() f;
\ir ../../../supabase/496_released_special_sale_stock_comes_back.sql
select pg_temp.check((select f from after_first) = pg_temp.fp()
    and split_part(pg_temp.fp(), ' ', 2)::int = split_part((select f from before_install), ' ', 2)::int + 4,
  'I1 496 adds four functions, and a second run changes nothing: ' || pg_temp.fp());
select pg_temp.check(not exists (select 1 from public.special_sales where sale_no like '496-CHECK%')
    and not exists (select 1 from public.invoices where invoice_no like '496-CHECK%')
    and not exists (select 1 from auth.users where email like '496chk-%'),
  'I2 its self-test left no sale, no invoice and no login');
\endif
select pg_temp.check(exists (select 1 from pg_attribute where attrelid = 'public.special_sales'::regclass and attname = 'release_movement_id' and not attisdropped)
    and (select relrowsecurity from pg_class where oid = 'public.special_sale_returns'::regclass)
    and exists (select 1 from pg_indexes where indexname = 'special_sales_release_movement_key')
    and not exists (select 1 from pg_attribute where attrelid = 'public.stock_movements'::regclass and attname ilike '%special%'),
  'I3 the sale has its link column and unique index, the new table has row-level security, and stock_movements is not altered');

-- ═════ Fixtures (invented) ═════
do $$
declare sfx text := lower(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
  k text; u uuid; st uuid; st2 uuid; wh uuid; wh2 uuid; v uuid; ph text;
begin
  foreach k in array array['owner', 'manager', 'staff', 'other'] loop
    u := gen_random_uuid();
    insert into auth.users(id, email) values (u, 'r496-' || k || '-' || sfx || '@example.invalid');
    insert into public.profiles(id, full_name, email, role, is_active)
      values (u, 'R496 ' || k, 'r496-' || k || '-' || sfx || '@example.invalid',
              (case k when 'other' then 'staff' else k end)::public.user_role, true);
    insert into fx values (k, u);
  end loop;
  perform pg_temp.as_user('owner');
  insert into public.stores(name, code, country_code) values ('R496 Store ' || sfx, 'R496' || sfx, 'SG') returning id into st; insert into fx values ('store', st);
  insert into public.stores(name, code, country_code) values ('R496 Store B ' || sfx, 'R496B' || sfx, 'SG') returning id into st2; insert into fx values ('store2', st2);
  insert into public.warehouses(name, code) values ('R496 Warehouse ' || sfx, 'R496W' || sfx) returning id into wh; insert into fx values ('wh', wh);
  insert into public.warehouses(name, code) values ('R496 Warehouse B ' || sfx, 'R496X' || sfx) returning id into wh2; insert into fx values ('wh2', wh2);
  insert into public.payment_methods(name, is_active) values ('R496 Cash ' || sfx, true) returning id into v; insert into fx values ('cash', v);
  insert into public.user_store_assignments(user_id, store_id) values (pg_temp.fx('manager'), st), (pg_temp.fx('staff'), st), (pg_temp.fx('other'), st2);
  -- A fictional phone no customer holds.
  select '+6125550' || lpad(n::text, 4, '0') into ph from generate_series(1000, 9999) n
   where not exists (select 1 from public.customers c where public.normalize_customer_phone(c.phone) = '+6125550' || lpad(n::text, 4, '0'))
   order by n limit 1;
  insert into public.customers(full_name, phone) values ('R496 Buyer', ph) returning id into v; insert into fx values ('buyer', v);
end $$;

-- A special product (S$1,000) over a third-party product holding 10 at the warehouse ('wh') or the store ('store').
create function pg_temp.mkspecial(tag text, loc text) returns void language plpgsql as
$$declare p uuid; sp uuid;
begin
  insert into public.products(name, sku, product_type) values ('R496 ' || tag, 'R496-' || tag, 'third_party') returning id into p;
  if loc = 'wh' then insert into public.warehouse_inventory(warehouse_id, product_id, current_qty) values (pg_temp.fx('wh'), p, 10);
  elsif loc = 'wh2' then insert into public.warehouse_inventory(warehouse_id, product_id, current_qty) values (pg_temp.fx('wh2'), p, 10);
  else insert into public.store_inventory(store_id, product_id, current_qty) values (pg_temp.fx('store'), p, 10); end if;
  sp := public.upsert_special_product_from_product(null, p, 1000, 0, 0, 100, 0, 0);
  insert into fx values ('p_' || tag, p), ('sp_' || tag, sp);
end$$;
-- An ordinary product (S$100) with 10 in the store.
create function pg_temp.mkplain(tag text) returns void language plpgsql as
$$declare p uuid;
begin
  insert into public.products(name, sku, product_type) values ('R496 ' || tag, 'R496-' || tag, 'own') returning id into p;
  insert into public.store_product_prices(store_id, product_id, selling_price) values (pg_temp.fx('store'), p, 100);
  insert into public.store_inventory(store_id, product_id, current_qty) values (pg_temp.fx('store'), p, 10);
  insert into fx values ('p_' || tag, p);
end$$;
-- One product that is both: sold as a special sale (S$1,000, from the warehouse's 10) and as an ordinary product
-- (S$100, from the store's 10).
create function pg_temp.mkboth(tag text) returns void language plpgsql as
$$declare p uuid; sp uuid;
begin
  insert into public.products(name, sku, product_type) values ('R496 ' || tag, 'R496-' || tag, 'third_party') returning id into p;
  insert into public.warehouse_inventory(warehouse_id, product_id, current_qty) values (pg_temp.fx('wh'), p, 10);
  insert into public.store_product_prices(store_id, product_id, selling_price) values (pg_temp.fx('store'), p, 100);
  insert into public.store_inventory(store_id, product_id, current_qty) values (pg_temp.fx('store'), p, 10);
  sp := public.upsert_special_product_from_product(null, p, 1000, 0, 0, 100, 0, 0);
  insert into fx values ('p_' || tag, p), ('sp_' || tag, sp);
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
-- The invoice's special sales, by number.
create function pg_temp.sales(inv uuid) returns uuid[] language sql as
$$ select coalesce(array_agg(id order by sale_no), '{}') from public.special_sales where invoice_id = inv $$;
create function pg_temp.release(sale uuid, loc text default 'wh') returns void language sql as
$$ select public.fulfil_special_doc('special_sale', sale, pg_temp.fx(loc), case when loc = 'store' then 'store' else 'warehouse' end) $$;
create function pg_temp.mv(sale uuid) returns uuid language sql as
$$ select release_movement_id from public.special_sales where id = sale $$;
-- On hand of a product at the warehouse and at the store.
create function pg_temp.at_wh(tag text) returns bigint language sql as
$$ select coalesce((select sum(current_qty) from public.warehouse_inventory where product_id = pg_temp.fx('p_' || tag) and warehouse_id = pg_temp.fx('wh')), 0) $$;
create function pg_temp.at_store(tag text) returns bigint language sql as
$$ select coalesce((select sum(current_qty) from public.store_inventory where product_id = pg_temp.fx('p_' || tag) and store_id = pg_temp.fx('store')), 0) $$;
create function pg_temp.n_moves(tag text, typ text) returns bigint language sql as
$$ select count(*) from public.stock_movements where product_id = pg_temp.fx('p_' || tag) and movement_type::text = typ $$;
create function pg_temp.status_of(sale uuid) returns text language sql as
$$ select status from public.special_sales where id = sale $$;
create function pg_temp.sale_no_of(sale uuid) returns text language sql as
$$ select sale_no from public.special_sales where id = sale $$;
-- Money on an invoice, to see that nothing here moved it.
create function pg_temp.money(inv uuid) returns text language sql as
$$ select i.status::text || ' charge ' || round(public.invoice_charge_total(inv), 2) || ' held ' || round(public.invoice_net_received(inv), 2)
          || ' refunds ' || round(coalesce((select sum(amount) from public.invoice_refunds where invoice_id = inv), 0), 2)
     from public.invoices i where i.id = inv $$;

-- The screen's way: staff ask (and see the plan), an Owner approves with the stock the plan proposed, or as
-- answered ({"<sale no>": [sellable, damaged, not returned]}). Returns the approval's answer, with the plan under
-- 'plan' and the stock sent under 'stock_sent'.
create function pg_temp.guided(inv uuid, action text, lines jsonb default '[]', answers jsonb default '{}', record_refund boolean default false)
returns jsonb language plpgsql as
$$declare req jsonb; plan jsonb; st jsonb; res jsonb;
begin
  perform pg_temp.as_user('staff');
  req := public.request_invoice_action_v2(inv, action, lines, 'Check ' || action, null, gen_random_uuid());
  plan := req->'plan';
  select coalesce(jsonb_agg(jsonb_build_object('movement_id', s->>'movement_id',
           'sellable_quantity', coalesce((answers->(s->>'sale_no')->>0)::int, (s->>'proposed_sellable')::int),
           'damaged_quantity', coalesce((answers->(s->>'sale_no')->>1)::int, 0),
           'not_returned_quantity', coalesce((answers->(s->>'sale_no')->>2)::int, 0))), '[]'::jsonb)
    into st from jsonb_array_elements(coalesce(plan->'stock', '[]')) s;
  perform pg_temp.as_user('owner');
  res := public.resolve_invoice_action_v2((req->>'request_id')::uuid, true, 'Checked', plan->>'plan_hash', '[]',
           case when jsonb_array_length(st) > 0 then st end, record_refund);
  return res || jsonb_build_object('plan', plan, 'stock_sent', st);
end$$;
-- The plan alone, as staff see it.
create function pg_temp.plan(inv uuid, action text, lines jsonb default '[]') returns jsonb language plpgsql as
$$begin perform pg_temp.as_user('staff'); return public.invoice_action_plan(inv, action, lines); end$$;
-- A refund of one line recorded directly, as the Finance panel's form does.
create function pg_temp.refund_line(inv uuid, item uuid, amt numeric, stock jsonb, req uuid default gen_random_uuid()) returns jsonb language plpgsql as
$$declare pay uuid;
begin
  perform pg_temp.as_user('owner');
  select id into pay from public.invoice_payments where invoice_id = inv order by public.invoice_payment_remaining(id) desc limit 1;
  return public.refund_invoice_recorded(inv,
    jsonb_build_array(jsonb_build_object('invoice_item_id', item, 'amount', coalesce(amt, public.invoice_payment_remaining(pay)))),
    jsonb_build_array(jsonb_build_object('payment_id', pay, 'amount', coalesce(amt, public.invoice_payment_remaining(pay)))),
    stock, 'Check refund', req);
end$$;
-- A refund of several lines recorded directly (each {invoice_item_id, amount[, waiting]}), as the Finance panel's form does.
create function pg_temp.refund_lines(inv uuid, lines jsonb, stock jsonb, req uuid default gen_random_uuid()) returns jsonb language plpgsql as
$$declare pay uuid; total numeric;
begin
  perform pg_temp.as_user('owner');
  select id into pay from public.invoice_payments where invoice_id = inv order by public.invoice_payment_remaining(id) desc limit 1;
  select sum((l->>'amount')::numeric) into total from jsonb_array_elements(lines) l;
  return public.refund_invoice_recorded(inv, lines, jsonb_build_array(jsonb_build_object('payment_id', pay, 'amount', total)), stock, 'Check refund', req);
end$$;
-- The invoice line of one special product (tag) on an invoice.
create function pg_temp.line_for(inv uuid, tag text) returns uuid language sql as
$$ select id from public.invoice_items where invoice_id = inv and special_product_id = pg_temp.fx('sp_' || tag) $$;
create function pg_temp.line_of(inv uuid) returns uuid language sql as
$$ select id from public.invoice_items where invoice_id = inv and line_kind::text = 'special_product' order by id limit 1 $$;
create function pg_temp.answer(mv uuid, s int, d int, n int) returns jsonb language sql as
$$ select jsonb_build_array(jsonb_build_object('movement_id', mv, 'sellable_quantity', s, 'damaged_quantity', d, 'not_returned_quantity', n)) $$;

-- ═════ L Linked, and offered ═════
do $$
declare inv uuid; s uuid[]; opts jsonb; plan jsonb; rental_inv uuid; r uuid;
begin
  perform pg_temp.as_user('owner');
  perform pg_temp.mkspecial('l1', 'wh');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('l1', 2)));
  perform pg_temp.pay(inv);
  s := pg_temp.sales(inv);
  perform pg_temp.check(cardinality(s) = 2 and not exists (select 1 from public.special_release_rows(inv))
      and jsonb_array_length(public.invoice_refund_options(inv)->'stock') = 0,
    'L1 two waiting units are not offered');
  perform pg_temp.release(s[1]);
  perform pg_temp.check((select count(*) from public.special_release_rows(inv)) = 1
      and pg_temp.mv(s[1]) is not null and pg_temp.mv(s[2]) is null
      and exists (select 1 from public.stock_movements m where m.id = pg_temp.mv(s[1]) and m.movement_type::text = 'store_sale'
                     and m.from_warehouse_id = pg_temp.fx('wh') and m.from_store_id is null and m.quantity = 1 and m.invoice_id is null
                     and m.product_id = pg_temp.fx('p_l1')),
    'L2 a warehouse release links its sale to the movement that took the unit out, which carries no invoice id');
  perform pg_temp.release(s[2]);
  perform pg_temp.check((select count(*) from public.special_release_rows(inv)) = 2 and pg_temp.mv(s[2]) <> pg_temp.mv(s[1]),
    'L3 and so does the second');
  opts := public.invoice_refund_options(inv);
  perform pg_temp.check(jsonb_array_length(opts->'stock') = 2
      and (select bool_and(e->>'special_sale_id' is not null and (e->>'quantity')::int = 1 and (e->>'resolved_quantity')::int = 0
                           and e->>'location_type' = 'warehouse' and e->>'location_id' = pg_temp.fx('wh')::text
                           and e->>'location_name' like 'R496 Warehouse%' and e->>'store_id' is null
                           and e->>'invoice_item_id' = pg_temp.line_of(inv)::text and e->>'product_name' = 'R496 l1')
            from jsonb_array_elements(opts->'stock') e),
    'L4 the refund screen is offered both, the shelf they left named: ' || (opts->'stock')::text);
  plan := pg_temp.plan(inv, 'refund_full');
  perform pg_temp.check(jsonb_array_length(plan->'stock') = 2
      and (select bool_and((e->>'proposed_sellable')::int = 1 and (e->>'outstanding')::int = 1 and e->>'store_name' like 'R496 Warehouse%'
                           and (e->>'damaged_quantity')::int = 0 and (e->>'not_returned_quantity')::int = 0)
            from jsonb_array_elements(plan->'stock') e)
      and (plan->'summary')::text like '%Return 1 x R496 l1 to R496 Warehouse%, once the condition is confirmed.%',
    'L5 the guided plan lists both with a product''s fields and says where each goes: ' || (plan->'summary')::text);
  plan := pg_temp.plan(inv, 'refund_partial', jsonb_build_array(jsonb_build_object('invoice_item_id', pg_temp.line_of(inv), 'quantity', 1)));
  perform pg_temp.check(jsonb_array_length(plan->'stock') = 1 and plan->'stock'->0->>'sale_no' = pg_temp.sale_no_of(s[1]),
    'L6 a part refund of one unit lists one unit, the first by sale number');
  plan := pg_temp.plan(inv, 'cancel');
  perform pg_temp.check(jsonb_array_length(plan->'stock') = 2, 'L7 a cancellation lists both');

  -- The shelf is a store: named the same way, and the store's id is given.
  perform pg_temp.as_user('owner');
  perform pg_temp.mkspecial('l2', 'store');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('l2')));
  perform pg_temp.pay(inv);
  s := pg_temp.sales(inv);
  perform pg_temp.release(s[1], 'store');
  opts := public.invoice_refund_options(inv);
  perform pg_temp.check(opts->'stock'->0->>'location_type' = 'store' and opts->'stock'->0->>'store_id' = pg_temp.fx('store')::text
      and opts->'stock'->0->>'location_name' like 'R496 Store%'
      and (select source_store_id from public.special_sales where id = s[1]) = pg_temp.fx('store')
      and exists (select 1 from public.stock_movements m where m.id = pg_temp.mv(s[1]) and m.from_store_id = pg_temp.fx('store') and m.from_warehouse_id is null
                    and m.notes like '% (from store)'),
    'L8 a store release links the same way and is offered with its store');

  -- A rental released from a warehouse is not a special sale's unit.
  perform pg_temp.mkspecial('l3', 'wh');
  rental_inv := pg_temp.mk(jsonb_build_array(jsonb_build_object('kind', 'rental', 'special_product_id', pg_temp.fx('sp_l3'), 'quantity', 1,
                  'rental_rate_type', 'month', 'rental_periods', 1, 'rental_start_date', public.sg_today()::text)));
  perform pg_temp.pay(rental_inv);
  select id into r from public.rentals where invoice_id = rental_inv;
  perform public.fulfil_special_doc('rental', r, pg_temp.fx('wh'), 'warehouse');
  perform pg_temp.check(pg_temp.n_moves('l3', 'store_sale') = 1 and not exists (select 1 from public.special_release_rows(rental_inv))
      and jsonb_array_length(public.invoice_refund_options(rental_inv)->'stock') = 0,
    'L9 a rental''s release is not offered as a special sale''s unit');
end $$;

-- A sale released before 496: its movement and no link. Linked where the match is certain, and only there.
do $$
declare inv uuid; s uuid[]; n int; mv1 uuid;
begin
  perform pg_temp.as_user('owner');
  perform pg_temp.mkspecial('l4', 'wh');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('l4', 2)));
  perform pg_temp.pay(inv);
  s := pg_temp.sales(inv);
  perform pg_temp.release(s[1]);
  perform pg_temp.release(s[2]);
  mv1 := pg_temp.mv(s[1]);
  -- as released before 496: the link is not there
  update public.special_sales set release_movement_id = null where id = any (s);
  perform pg_temp.check(not exists (select 1 from public.special_release_rows(inv)), 'L10 a sale with no link offers nothing');
  n := public.link_released_special_movements();
  perform pg_temp.check(n = 2 and pg_temp.mv(s[1]) = mv1 and pg_temp.mv(s[2]) is not null and pg_temp.mv(s[1]) <> pg_temp.mv(s[2])
      and (select count(*) from public.special_release_rows(inv)) = 2,
    'L11 linking finds both by their notes (linked ' || n || ')');
  n := public.link_released_special_movements();
  perform pg_temp.check(n = 0, 'L12 and again changes nothing (linked ' || n || ')');
  perform pg_temp.check((select quantity from public.stock_movements where id = mv1) = 1 and pg_temp.at_wh('l4') = 8,
    'L13 linking changes no quantity and no stock');
  -- Two movements for one sale: not certain, so not linked; one again: linked.
  update public.special_sales set release_movement_id = null where id = s[1];
  insert into public.stock_movements(product_id, movement_type, from_warehouse_id, quantity, notes)
    select product_id, movement_type, from_warehouse_id, quantity, notes from public.stock_movements where id = mv1;
  n := public.link_released_special_movements();
  perform pg_temp.check(n = 0 and pg_temp.mv(s[1]) is null, 'L14 a sale matched by two movements is not linked (linked ' || n || ')');
  delete from public.stock_movements where product_id = pg_temp.fx('p_l4') and notes like '%' || pg_temp.sale_no_of(s[1]) || '%' and id <> mv1;
  n := public.link_released_special_movements();
  perform pg_temp.check(n = 1 and pg_temp.mv(s[1]) = mv1, 'L15 matched by one, it is linked (linked ' || n || ')');
end $$;

-- The same for a sale released from a store (its note says so).
do $$
declare inv uuid; s uuid[]; mv uuid; n int;
begin
  perform pg_temp.as_user('owner');
  perform pg_temp.mkspecial('l5', 'store');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('l5')));
  perform pg_temp.pay(inv);
  s := pg_temp.sales(inv); perform pg_temp.release(s[1], 'store');
  mv := pg_temp.mv(s[1]);
  update public.special_sales set release_movement_id = null where id = s[1];
  n := public.link_released_special_movements();
  perform pg_temp.check(n = 1 and pg_temp.mv(s[1]) = mv and pg_temp.at_store('l5') = 9,
    'L16 a sale released from a store is linked to its movement too (linked ' || n || ')');
end $$;

-- ═════ R Refund in full: sellable goes back ═════
do $$
declare inv uuid; s uuid[]; mv uuid; res jsonb; before text; ret record;
begin
  perform pg_temp.as_user('owner');
  perform pg_temp.mkspecial('r1', 'wh');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('r1')));
  perform pg_temp.pay(inv);
  s := pg_temp.sales(inv);
  perform pg_temp.release(s[1]);
  mv := pg_temp.mv(s[1]);
  before := pg_temp.money(inv);
  perform pg_temp.check(pg_temp.at_wh('r1') = 9, 'R0 released: 9 of 10 left in the warehouse');
  res := pg_temp.guided(inv, 'refund_full');
  perform pg_temp.check(res->>'status' = 'approved' and (select status::text from public.invoices where id = inv) = 'refunded',
    'R1 the screen''s Refund in full is approved and the invoice is refunded: ' || coalesce(res->>'status', '-'));
  perform pg_temp.check(pg_temp.at_wh('r1') = 10 and pg_temp.at_store('r1') = 0,
    'R2 the unit is back on the warehouse it left: 10 of 10');
  select * into ret from public.stock_movements where reversed_sale_id = mv;
  perform pg_temp.check(ret.movement_type::text = 'invoice_refund_return' and ret.to_warehouse_id = pg_temp.fx('wh') and ret.to_store_id is null
      and ret.from_warehouse_id is null and ret.from_store_id is null and ret.quantity = 1 and ret.invoice_id is null
      and ret.product_id = pg_temp.fx('p_r1') and ret.notes like 'Special sale returned — %(refunded): Checked',
    'R3 one Refund Return movement, into the warehouse, pointing at the release: ' || coalesce(ret.notes, '-'));
  perform pg_temp.check((select status from public.special_sales where id = s[1]) = 'cancelled'
      and (select stock_returned from public.special_sales where id = s[1])
      and (select notes from public.special_sales where id = s[1]) like '%Cancelled (refunded): Checked%'
      and (select cancelled_at from public.special_sales where id = s[1]) is not null,
    'R4 the sale is over: cancelled, stock back, "Cancelled (refunded)"');
  perform pg_temp.check(exists (select 1 from public.special_sale_returns r where r.movement_id = mv and r.special_sale_id = s[1] and r.invoice_id = inv
                                  and r.sellable_quantity = 1 and r.damaged_quantity = 0 and r.not_returned_quantity = 0
                                  and r.return_movement_id = ret.id and r.why = 'refunded' and r.created_by = pg_temp.fx('owner')),
    'R5 the answer is recorded, who gave it and the movement written');
  perform pg_temp.check(exists (select 1 from public.audit_logs l where l.record_id = s[1] and l.action = 'special_sale_stock_returned'
                                  and l.changed_by = pg_temp.fx('owner') and l.new_data->>'sellable' = '1' and l.new_data->>'why' = 'refunded'
                                  and l.new_data->>'location_name' like 'R496 Warehouse%' and l.old_data->>'status' = 'completed'),
    'R6 the Audit Log has it: who, how many, where, and the status it left');
  perform pg_temp.check(not exists (select 1 from public.special_release_rows(inv) r where r.quantity > r.resolved_quantity)
      and (select resolved_quantity from public.special_release_rows(inv)) = 1,
    'R7 the unit is settled: nothing left to ask');
  perform pg_temp.check(before = 'paid charge 1000.00 held 1000.00 refunds 0.00', 'R8 (the money before) ' || before);
  perform pg_temp.check(pg_temp.money(inv) = 'refunded charge 0.00 held 0.00 refunds 1000.00',
    'R9 the money is what a refund of the line has always done: ' || pg_temp.money(inv));
  perform pg_temp.check(pg_temp.at_store('r1') = 0 and pg_temp.n_moves('r1', 'invoice_refund_return') = 1 and pg_temp.n_moves('r1', 'store_sale') = 1,
    'R10 no other movement was written');
end $$;

-- The same from a store.
do $$
declare inv uuid; s uuid[]; mv uuid; res jsonb;
begin
  perform pg_temp.as_user('owner');
  perform pg_temp.mkspecial('r2', 'store');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('r2')));
  perform pg_temp.pay(inv);
  s := pg_temp.sales(inv);
  perform pg_temp.release(s[1], 'store');
  mv := pg_temp.mv(s[1]);
  res := pg_temp.guided(inv, 'refund_full');
  perform pg_temp.check(res->>'status' = 'approved' and pg_temp.at_store('r2') = 10 and pg_temp.at_wh('r2') = 0
      and exists (select 1 from public.stock_movements m where m.reversed_sale_id = mv and m.to_store_id = pg_temp.fx('store') and m.to_warehouse_id is null
                    and m.movement_type::text = 'invoice_refund_return')
      and (select status from public.special_sales where id = s[1]) = 'cancelled',
    'R11 released from a store: it goes back to the store, 10 of 10');
end $$;

-- ═════ D Damaged and not returned ═════
do $$
declare inv uuid; s uuid[]; res jsonb; t text;
begin
  perform pg_temp.as_user('owner');
  perform pg_temp.mkspecial('d1', 'wh');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('d1', 2)));
  perform pg_temp.pay(inv);
  s := pg_temp.sales(inv);
  perform pg_temp.release(s[1]); perform pg_temp.release(s[2]);
  -- one damaged, one not returned
  res := pg_temp.guided(inv, 'refund_full', '[]',
    jsonb_build_object(pg_temp.sale_no_of(s[1]), jsonb_build_array(0, 1, 0), pg_temp.sale_no_of(s[2]), jsonb_build_array(0, 0, 1)));
  perform pg_temp.check(res->>'status' = 'approved' and (select status::text from public.invoices where id = inv) = 'refunded',
    'D1 a refund where one came back damaged and one was not returned is approved');
  perform pg_temp.check(pg_temp.at_wh('d1') = 8 and pg_temp.n_moves('d1', 'invoice_refund_return') = 0,
    'D2 neither adds stock: 8 of 10, and no return movement');
  perform pg_temp.check(pg_temp.status_of(s[1]) = 'completed' and pg_temp.status_of(s[2]) = 'completed'
      and not coalesce((select stock_returned from public.special_sales where id = s[1]), false),
    'D3 both sales stay released');
  perform pg_temp.check((select count(*) from public.special_sale_returns where special_sale_id = any (s)) = 2
      and exists (select 1 from public.special_sale_returns where special_sale_id = s[1] and damaged_quantity = 1 and sellable_quantity = 0 and return_movement_id is null)
      and exists (select 1 from public.special_sale_returns where special_sale_id = s[2] and not_returned_quantity = 1 and sellable_quantity = 0 and return_movement_id is null),
    'D4 each answer is recorded, with no movement');
  perform pg_temp.check((select bool_and(r.resolved_quantity = r.quantity) from public.special_release_rows(inv) r), 'D5 both are settled');
  -- A settled unit cannot be answered again, by the function that records it.
  t := pg_temp.err(format('select public.return_released_special_stock(%L, %L, 1, 0, 0, gen_random_uuid(), ''again'', ''refunded'')', inv, pg_temp.mv(s[1])));
  perform pg_temp.check(t = 'Stock disposition exceeds the unresolved deduction', 'D6 answered again: ' || t);
  perform pg_temp.check(pg_temp.at_wh('d1') = 8, 'D7 and the stock is as it was');
end $$;

-- ═════ G Refused ═════
do $$
declare inv uuid; inv2 uuid; s uuid[]; s2 uuid[]; mv uuid; mv2 uuid; line uuid; t text; res jsonb; r2 jsonb; rq uuid := gen_random_uuid();
begin
  perform pg_temp.as_user('owner');
  perform pg_temp.mkspecial('g1', 'wh');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('g1')));
  perform pg_temp.pay(inv);
  s := pg_temp.sales(inv); perform pg_temp.release(s[1]); mv := pg_temp.mv(s[1]); line := pg_temp.line_of(inv);
  inv2 := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('g1')));
  perform pg_temp.pay(inv2);
  s2 := pg_temp.sales(inv2); perform pg_temp.release(s2[1]); mv2 := pg_temp.mv(s2[1]);

  t := pg_temp.err(format('select pg_temp.refund_line(%L, %L, null, ''[]''::jsonb)', inv, line));
  perform pg_temp.check(t = 'Record the returned-and-sellable, damaged, or not-returned quantities for this special sale refund',
    'G1 a refund of the line with no answer is refused, as a product''s is: ' || t);
  t := pg_temp.err(format('select pg_temp.refund_line(%L, %L, null, %L::jsonb)', inv, line, pg_temp.answer(mv2, 1, 0, 0)));
  perform pg_temp.check(t = 'Record the returned-and-sellable, damaged, or not-returned quantities for this special sale refund',
    'G2 the whole line refunded with another invoice''s unit answered, and its own not, is refused: ' || t);
  t := pg_temp.err(format('select pg_temp.refund_line(%L, %L, null, %L::jsonb)', inv, line, pg_temp.answer(mv, 2, 0, 0)));
  perform pg_temp.check(t = 'Stock disposition exceeds the unresolved deduction', 'G3 more than is out is refused: ' || t);
  t := pg_temp.err(format('select pg_temp.refund_line(%L, %L, null, %L::jsonb)', inv, line, pg_temp.answer(mv, 0, 0, 0)));
  perform pg_temp.check(t = 'Stock disposition exceeds the unresolved deduction', 'G4 an answer of nothing is refused: ' || t);
  t := pg_temp.err(format('select pg_temp.refund_line(%L, %L, null, %L::jsonb)', inv, line, pg_temp.answer(mv, -1, 2, 0)));
  perform pg_temp.check(t = 'Stock disposition exceeds the unresolved deduction', 'G5 a negative answer is refused: ' || t);
  perform pg_temp.check(pg_temp.at_wh('g1') = 8 and (select count(*) from public.special_sale_returns where special_sale_id in (s[1], s2[1])) = 0
      and (select status::text from public.invoices where id = inv) = 'paid' and pg_temp.money(inv) = 'paid charge 1000.00 held 1000.00 refunds 0.00',
    'G6 after those, nothing changed: stock, answers, invoice and money');
  perform pg_temp.as_user('staff');
  t := pg_temp.err(format('select public.refund_invoice_recorded(%L, ''[]''::jsonb, ''[]''::jsonb, ''[]''::jsonb, ''x'', gen_random_uuid())', inv));
  perform pg_temp.check(t = 'Only an Owner or Manager can record a refund', 'G7 staff cannot record a refund: ' || t);
  -- The same request id replays what it did, and cannot be used for other details.
  res := pg_temp.refund_line(inv, line, 1000, pg_temp.answer(mv, 1, 0, 0), rq);
  perform pg_temp.check(pg_temp.at_wh('g1') = 9, 'G8 answered sellable: 9');
  r2 := pg_temp.refund_line(inv, line, 1000, pg_temp.answer(mv, 1, 0, 0), rq);
  perform pg_temp.check(coalesce((r2->>'replayed')::boolean, false) and pg_temp.at_wh('g1') = 9 and pg_temp.n_moves('g1', 'invoice_refund_return') = 1,
    'G9 the same request again replays, and returns nothing twice');
  t := pg_temp.err(format('select pg_temp.refund_line(%L, %L, 1000, %L::jsonb, %L)', inv, line, pg_temp.answer(mv, 0, 1, 0), rq));
  perform pg_temp.check(t = 'This refund request ID was already used for different details', 'G10 the request id for other details is refused: ' || t);
  -- A part refund by amount, answered "not returned": the price is eased, the unit stays out, the invoice stays paid.
  res := pg_temp.refund_line(inv2, pg_temp.line_of(inv2), 100, pg_temp.answer(mv2, 0, 0, 1));
  perform pg_temp.check((select status::text from public.invoices where id = inv2) = 'paid' and pg_temp.at_wh('g1') = 9
      and pg_temp.status_of(s2[1]) = 'completed'
      and exists (select 1 from public.special_sale_returns where special_sale_id = s2[1] and not_returned_quantity = 1),
    'G11 a part refund answered "not returned": the invoice stays paid, the unit stays out and settled');
end $$;

-- ═════ Q A part refund of a two-unit line ═════
do $$
declare inv uuid; s uuid[]; plan jsonb; res jsonb; line uuid;
begin
  perform pg_temp.as_user('owner');
  perform pg_temp.mkspecial('q1', 'wh');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('q1', 2)));
  perform pg_temp.pay(inv);
  s := pg_temp.sales(inv); perform pg_temp.release(s[1]); perform pg_temp.release(s[2]);
  line := pg_temp.line_of(inv);
  res := pg_temp.guided(inv, 'refund_partial', jsonb_build_array(jsonb_build_object('invoice_item_id', line, 'quantity', 1)));
  perform pg_temp.check(res->>'status' = 'approved' and jsonb_array_length(res->'stock_sent') = 1,
    'Q1 refunding one of two units asks about one: ' || coalesce((res->'stock_sent')::text, '-'));
  perform pg_temp.check(pg_temp.at_wh('q1') = 9 and (select status::text from public.invoices where id = inv) = 'paid'
      and pg_temp.status_of(s[1]) = 'cancelled' and pg_temp.status_of(s[2]) = 'completed',
    'Q2 one unit is back (9 of 10), the first sale is over, the second is still released and the invoice is paid');
  perform pg_temp.check(pg_temp.money(inv) = 'paid charge 1000.00 held 1000.00 refunds 1000.00',
    'Q3 one unit''s price was refunded: ' || pg_temp.money(inv));
  plan := pg_temp.plan(inv, 'refund_full');
  perform pg_temp.check(jsonb_array_length(plan->'stock') = 1 and plan->'stock'->0->>'sale_no' = pg_temp.sale_no_of(s[2]),
    'Q4 refunding the rest asks about the unit left, and only it');
  res := pg_temp.guided(inv, 'refund_full', '[]', jsonb_build_object(pg_temp.sale_no_of(s[2]), jsonb_build_array(0, 0, 1)));
  perform pg_temp.check(res->>'status' = 'approved' and pg_temp.at_wh('q1') = 9 and pg_temp.status_of(s[2]) = 'completed'
      and (select status::text from public.invoices where id = inv) = 'refunded',
    'Q5 and it was not returned: stock stays 9, the invoice is refunded');
end $$;

-- ═════ C Cancellation ═════
do $$
declare inv uuid; s uuid[]; res jsonb; plan jsonb; ret record;
begin
  perform pg_temp.as_user('owner');
  -- the screen's way: one unit confirmed damaged, the other proposed sellable
  perform pg_temp.mkspecial('c1', 'wh');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('c1', 2)));
  perform pg_temp.pay(inv);
  s := pg_temp.sales(inv); perform pg_temp.release(s[1]); perform pg_temp.release(s[2]);
  plan := pg_temp.plan(inv, 'cancel');
  perform pg_temp.check(jsonb_array_length(plan->'stock') = 2 and (plan->>'refund_due')::numeric = 2000,
    'C1 the cancellation plan lists both units, and the refund due is S$2,000');
  res := pg_temp.guided(inv, 'cancel', '[]', jsonb_build_object(pg_temp.sale_no_of(s[1]), jsonb_build_array(0, 1, 0)));
  perform pg_temp.check(res->>'status' = 'approved' and (select status::text from public.invoices where id = inv) = 'cancelled',
    'C2 the guided cancellation is approved and the invoice is cancelled: ' || coalesce(res->>'status', '-'));
  perform pg_temp.check(pg_temp.at_wh('c1') = 9 and pg_temp.status_of(s[1]) = 'completed' and pg_temp.status_of(s[2]) = 'cancelled',
    'C3 the damaged one stays out, the other goes back: 9 of 10');
  select * into ret from public.stock_movements where reversed_sale_id = pg_temp.mv(s[2]);
  perform pg_temp.check(ret.movement_type::text = 'invoice_cancel_return' and ret.to_warehouse_id = pg_temp.fx('wh') and ret.notes like '%(invoice cancelled)%',
    'C4 the confirmed one is a Cancel Return into the warehouse, noted as the cancellation''s: ' || coalesce(ret.movement_type::text || ' ' || ret.notes, '-'));
  perform pg_temp.check((select notes from public.special_sales where id = s[2]) like '%Cancelled (invoice cancelled): %'
      and exists (select 1 from public.special_sale_returns where special_sale_id = s[1] and damaged_quantity = 1 and why = 'invoice cancelled'),
    'C5 the sale reads "Cancelled (invoice cancelled)", and the damaged answer is kept');

  -- no answers at all: the cancellation puts back everything unsettled, as it does a product's
  perform pg_temp.mkspecial('c2', 'wh');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('c2', 2)));
  perform pg_temp.pay(inv);
  s := pg_temp.sales(inv); perform pg_temp.release(s[1]); perform pg_temp.release(s[2]);
  perform pg_temp.as_user('owner');
  perform public.cancel_invoice_recorded(inv, 'Check cancellation', gen_random_uuid());
  perform pg_temp.check(pg_temp.at_wh('c2') = 10 and pg_temp.status_of(s[1]) = 'cancelled' and pg_temp.status_of(s[2]) = 'cancelled'
      and pg_temp.n_moves('c2', 'invoice_cancel_return') = 2
      and exists (select 1 from public.stock_movements m where m.reversed_sale_id = pg_temp.mv(s[1]) and m.to_warehouse_id = pg_temp.fx('wh') and m.movement_type::text = 'invoice_cancel_return'),
    'C6 cancel_invoice_recorded with no answers puts both back, as Cancel Returns: 10 of 10');

  -- cancel with the refund recorded in the same approval
  perform pg_temp.mkspecial('c3', 'store');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('c3')));
  perform pg_temp.pay(inv);
  s := pg_temp.sales(inv); perform pg_temp.release(s[1], 'store');
  res := pg_temp.guided(inv, 'cancel', '[]', '{}', true);
  perform pg_temp.check(res->>'status' = 'approved' and (res->>'refund_recorded')::boolean and pg_temp.at_store('c3') = 10
      and pg_temp.status_of(s[1]) = 'cancelled' and (select status::text from public.invoices where id = inv) in ('cancelled', 'refunded'),
    'C7 cancel with the refund recorded: the unit goes back to its store (' || pg_temp.at_store('c3') || ' of 10)');
  perform pg_temp.check((select count(*) from public.special_sale_returns where special_sale_id = s[1]) = 1
      and pg_temp.n_moves('c3', 'invoice_refund_return') + pg_temp.n_moves('c3', 'invoice_cancel_return') = 1,
    'C8 and settled once, with one movement');
end $$;

-- ═════ M Special sale and ordinary product on one invoice ═════
do $$
declare inv uuid; s uuid[]; plan jsonb; res jsonb;
begin
  perform pg_temp.as_user('owner');
  perform pg_temp.mkspecial('m1', 'wh');
  perform pg_temp.mkplain('m2');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('m1'), pg_temp.prod_line('m2')));
  perform pg_temp.pay(inv);
  s := pg_temp.sales(inv); perform pg_temp.release(s[1]);
  perform pg_temp.check(pg_temp.at_wh('m1') = 9 and pg_temp.at_store('m2') = 9, 'M1 the unit left the warehouse and the product left the store');
  plan := pg_temp.plan(inv, 'refund_full');
  perform pg_temp.check(jsonb_array_length(plan->'stock') = 2
      and (select count(*) from jsonb_array_elements(plan->'stock') e where e->>'special_sale_id' is not null and e->>'product_name' = 'R496 m1') = 1
      and (select count(*) from jsonb_array_elements(plan->'stock') e where e->>'special_sale_id' is null and e->>'product_name' = 'R496 m2') = 1,
    'M2 the plan asks about both, each its own: ' || (plan->'stock')::text);
  res := pg_temp.guided(inv, 'refund_full');
  perform pg_temp.check(res->>'status' = 'approved' and pg_temp.at_wh('m1') = 10 and pg_temp.at_store('m2') = 10 and pg_temp.at_store('m1') = 0 and pg_temp.at_wh('m2') = 0,
    'M3 each goes back to its own shelf: the unit to the warehouse, the product to the store');
  perform pg_temp.check(pg_temp.n_moves('m2', 'invoice_refund_return') = 1
      and (select invoice_id is not null from public.stock_movements where product_id = pg_temp.fx('p_m2') and movement_type::text = 'invoice_refund_return')
      and (select invoice_id is null from public.stock_movements where product_id = pg_temp.fx('p_m1') and movement_type::text = 'invoice_refund_return'),
    'M4 the product''s return carries the invoice as before; the special unit''s does not');
end $$;

-- ═════ X The same product on both lines ═════
do $$
declare inv uuid; s uuid[]; plan jsonb; res jsonb; before_deduct text; after_deduct text; opts jsonb; pline uuid; sline uuid; smv uuid;
begin
  perform pg_temp.as_user('owner');
  perform pg_temp.mkboth('x1');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('x1'), pg_temp.prod_line('x1')));
  perform pg_temp.pay(inv);
  s := pg_temp.sales(inv); perform pg_temp.release(s[1]);
  smv := pg_temp.mv(s[1]);
  select id into pline from public.invoice_items where invoice_id = inv and line_kind::text = 'product';
  sline := pg_temp.line_of(inv);
  perform pg_temp.check(pg_temp.at_wh('x1') = 9 and pg_temp.at_store('x1') = 9, 'X1 one unit from the warehouse (special), one from the store (ordinary)');
  select coalesce(string_agg(t.kind || ' ' || t.item_id || ' ' || t.quantity, ', ' order by t.item_id), '-') into before_deduct from public.invoice_stock_to_deduct(inv) t;
  plan := pg_temp.plan(inv, 'refund_full');
  perform pg_temp.check(jsonb_array_length(plan->'stock') = 2
      and (select count(distinct e->>'movement_id') from jsonb_array_elements(plan->'stock') e) = 2
      and (select count(*) from jsonb_array_elements(plan->'stock') e where e->>'special_sale_id' is not null) = 1
      and (select count(*) from jsonb_array_elements(plan->'stock') e where e->>'special_sale_id' is null and e->>'store_name' like 'R496 Store%') = 1,
    'X2 each line is offered its own unit once: the product line the store''s, the special line the warehouse''s: ' || (plan->'stock')::text);
  -- Refunding only one of the two lines offers only that line's unit, though the product is the same.
  plan := pg_temp.plan(inv, 'refund_partial', jsonb_build_array(jsonb_build_object('invoice_item_id', pline, 'quantity', 1)));
  perform pg_temp.check(jsonb_array_length(plan->'stock') = 1 and plan->'stock'->0->>'special_sale_id' is null and plan->'stock'->0->>'store_name' like 'R496 Store%',
    'X3 refunding the product line alone offers the store''s unit, not the special sale''s: ' || (plan->'stock')::text);
  plan := pg_temp.plan(inv, 'refund_partial', jsonb_build_array(jsonb_build_object('invoice_item_id', sline, 'quantity', 1)));
  perform pg_temp.check(jsonb_array_length(plan->'stock') = 1 and plan->'stock'->0->>'special_sale_id' = s[1]::text,
    'X4 refunding the special line alone offers the special sale''s unit, not the product''s: ' || (plan->'stock')::text);
  -- The special unit settled as damaged: nothing of it is in the tables the invoice's own stock maths reads.
  perform public.return_released_special_stock(inv, smv, 0, 1, 0, gen_random_uuid(), 'Check', 'refunded');
  select coalesce(string_agg(t.kind || ' ' || t.item_id || ' ' || t.quantity, ', ' order by t.item_id), '-') into after_deduct from public.invoice_stock_to_deduct(inv) t;
  perform pg_temp.check(before_deduct = after_deduct
      and not exists (select 1 from public.invoice_stock_dispositions d where d.invoice_id = inv and d.movement_id = smv)
      and (select invoice_id from public.stock_movements where id = smv) is null
      and not exists (select 1 from public.stock_movements m where m.invoice_id = inv and m.reversed_sale_id = smv),
    'X5 a damaged special unit leaves the invoice''s stock maths as it was, and is in no table it reads: ' || before_deduct);
  opts := public.invoice_refund_options(inv);
  perform pg_temp.check((select count(*) from jsonb_array_elements(opts->'stock') e where e->>'special_sale_id' is null and (e->>'resolved_quantity')::int = 0) = 1
      and (select count(*) from jsonb_array_elements(opts->'stock') e where e->>'special_sale_id' is not null and (e->>'resolved_quantity')::int = 1) = 1,
    'X6 the product''s deduction is still unsettled and the special unit settled');
  res := pg_temp.guided(inv, 'refund_full');
  perform pg_temp.check(res->>'status' = 'approved' and pg_temp.at_store('x1') = 10 and pg_temp.at_wh('x1') = 9,
    'X7 the refund returns the product to the store and leaves the damaged special unit out');
end $$;

-- ═════ Y Two special lines on one invoice ═════
do $$
declare inv uuid; sa uuid[]; sb uuid[]; sales uuid[]; la uuid; lb uuid; plan jsonb; res jsonb;
begin
  perform pg_temp.as_user('owner');
  perform pg_temp.mkspecial('y1', 'wh');
  perform pg_temp.mkspecial('y2', 'store');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('y1'), pg_temp.sale_line('y2')));
  perform pg_temp.pay(inv);
  select array_agg(id order by sale_no) into sales from public.special_sales where invoice_id = inv;
  select id into la from public.invoice_items where invoice_id = inv and special_product_id = pg_temp.fx('sp_y1');
  select id into lb from public.invoice_items where invoice_id = inv and special_product_id = pg_temp.fx('sp_y2');
  perform pg_temp.release((select id from public.special_sales where invoice_id = inv and special_product_id = pg_temp.fx('sp_y1')), 'wh');
  perform pg_temp.release((select id from public.special_sales where invoice_id = inv and special_product_id = pg_temp.fx('sp_y2')), 'store');
  perform pg_temp.check(pg_temp.at_wh('y1') = 9 and pg_temp.at_store('y2') = 9, 'Y1 one unit left a warehouse and one a store');
  plan := pg_temp.plan(inv, 'refund_partial', jsonb_build_array(jsonb_build_object('invoice_item_id', la, 'quantity', 1)));
  perform pg_temp.check(jsonb_array_length(plan->'stock') = 1 and plan->'stock'->0->>'location_type' = 'warehouse'
      and plan->'stock'->0->>'product_name' = 'R496 y1',
    'Y2 refunding the first line offers its unit alone: ' || (plan->'stock')::text);
  res := pg_temp.guided(inv, 'refund_partial', jsonb_build_array(jsonb_build_object('invoice_item_id', la, 'quantity', 1)));
  perform pg_temp.check(res->>'status' = 'approved' and pg_temp.at_wh('y1') = 10 and pg_temp.at_store('y2') = 9
      and (select status::text from public.invoices where id = inv) = 'paid',
    'Y3 only that unit goes back; the other line''s stays out and the invoice stays paid');
  plan := pg_temp.plan(inv, 'refund_full');
  perform pg_temp.check(jsonb_array_length(plan->'stock') = 1 and plan->'stock'->0->>'location_type' = 'store' and plan->'stock'->0->>'product_name' = 'R496 y2',
    'Y4 refunding the rest offers the other unit alone');
  res := pg_temp.guided(inv, 'refund_full');
  perform pg_temp.check(res->>'status' = 'approved' and pg_temp.at_store('y2') = 10 and pg_temp.at_wh('y1') = 10
      and (select status::text from public.invoices where id = inv) = 'refunded',
    'Y5 and it goes back to its store: both units home, the invoice refunded');
end $$;

-- ═════ O Reopened and paid again ═════
do $$
declare inv uuid; s uuid[]; s2 uuid[]; res jsonb;
begin
  perform pg_temp.as_user('owner');
  -- a unit that came back: raised afresh, released and taken again
  perform pg_temp.mkspecial('o1', 'wh');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('o1')));
  perform pg_temp.pay(inv);
  s := pg_temp.sales(inv); perform pg_temp.release(s[1]);
  res := pg_temp.guided(inv, 'refund_full');
  perform pg_temp.check(pg_temp.at_wh('o1') = 10 and (select status::text from public.invoices where id = inv) = 'refunded', 'O1 refunded, the unit back: 10 of 10');
  perform pg_temp.as_user('owner');
  perform public.reopen_invoice(inv, 'Customer came back for it', gen_random_uuid());
  perform pg_temp.pay(inv);
  s2 := pg_temp.sales(inv);
  perform pg_temp.check(cardinality(s2) = 2 and (select count(*) from public.special_sales where invoice_id = inv and status = 'pending') = 1
      and exists (select 1 from public.special_docs_awaiting_fulfilment() w where w.doc_id = any (s2)),
    'O2 reopened and paid again, its unit is raised afresh and waits (' || cardinality(s2) || ' sales)');
  perform pg_temp.release((select id from public.special_sales where invoice_id = inv and status = 'pending'));
  perform pg_temp.check(pg_temp.at_wh('o1') = 9, 'O3 released again, it is taken from stock again: 9');

  -- a unit that did not come back: not raised twice, as before
  perform pg_temp.mkspecial('o2', 'wh');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('o2')));
  perform pg_temp.pay(inv);
  s := pg_temp.sales(inv); perform pg_temp.release(s[1]);
  res := pg_temp.guided(inv, 'refund_full', '[]', jsonb_build_object(pg_temp.sale_no_of(s[1]), jsonb_build_array(0, 0, 1)));
  perform pg_temp.as_user('owner');
  perform public.reopen_invoice(inv, 'Customer came back for it', gen_random_uuid());
  perform pg_temp.pay(inv);
  perform pg_temp.check((select count(*) from public.special_sales where invoice_id = inv) = 1 and pg_temp.at_wh('o2') = 9,
    'O4 a unit that was not returned is not raised twice, and nothing more is taken: 9');
end $$;

-- ═════ W Waiting, supplier-sent and rentals: as before ═════
do $$
declare inv uuid; s uuid[]; res jsonb; plan jsonb; rental_inv uuid; r uuid; sup uuid;
begin
  perform pg_temp.as_user('owner');
  -- waiting: a refund cancels it as before, with no stock row
  perform pg_temp.mkspecial('w1', 'wh');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('w1')));
  perform pg_temp.pay(inv);
  s := pg_temp.sales(inv);
  plan := pg_temp.plan(inv, 'refund_full');
  perform pg_temp.check(jsonb_array_length(plan->'stock') = 0, 'W1 a waiting sale puts no stock row in the plan');
  res := pg_temp.guided(inv, 'refund_full');
  perform pg_temp.check(res->>'status' = 'approved' and pg_temp.status_of(s[1]) = 'cancelled' and pg_temp.at_wh('w1') = 10
      and (select notes from public.special_sales where id = s[1]) like '%Cancelled (refunded)%' and pg_temp.n_moves('w1', 'invoice_refund_return') = 0,
    'W2 and the refund cancels it as before (393), moving no stock');
  -- supplier-sent (494): nothing was taken, nothing is asked, nothing returns
  perform pg_temp.as_user('owner');
  perform pg_temp.mkspecial('w2', 'wh');
  insert into public.suppliers(name, phone) values ('R496 Supplier', '+61255509901') returning id into sup;
  insert into public.product_suppliers(product_id, supplier_id) values (pg_temp.fx('p_w2'), sup);
  perform public.set_special_product_consignment(pg_temp.fx('sp_w2'), true);
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('w2')));
  perform pg_temp.pay(inv);
  s := pg_temp.sales(inv);
  perform public.release_special_sale_to_supplier(s[1], sup, 'Check Road');
  plan := pg_temp.plan(inv, 'refund_full');
  perform pg_temp.check(jsonb_array_length(plan->'stock') = 0 and not exists (select 1 from public.special_release_rows(inv)),
    'W3 a sale sent by a supplier is not offered as stock');
  res := pg_temp.guided(inv, 'refund_full');
  perform pg_temp.check(res->>'status' = 'approved' and pg_temp.at_wh('w2') = 10 and pg_temp.status_of(s[1]) = 'completed'
      and not exists (select 1 from public.special_sale_returns where special_sale_id = s[1]),
    'W4 its refund goes through as before: no stock moves, the sale keeps its supplier');
  -- a rental out: a refund ends it and it waits for "Receive returned item", as before
  perform pg_temp.as_user('owner');
  perform pg_temp.mkspecial('w3', 'wh');
  rental_inv := pg_temp.mk(jsonb_build_array(jsonb_build_object('kind', 'rental', 'special_product_id', pg_temp.fx('sp_w3'), 'quantity', 1,
                  'rental_rate_type', 'month', 'rental_periods', 1, 'rental_start_date', public.sg_today()::text)));
  perform pg_temp.pay(rental_inv);
  select id into r from public.rentals where invoice_id = rental_inv;
  perform public.fulfil_special_doc('rental', r, pg_temp.fx('wh'), 'warehouse');
  plan := pg_temp.plan(rental_inv, 'refund_full');
  perform pg_temp.check(jsonb_array_length(plan->'stock') = 0, 'W5 a rental out puts no stock row in the plan');
  res := pg_temp.guided(rental_inv, 'refund_full');
  perform pg_temp.check(res->>'status' = 'approved' and pg_temp.at_wh('w3') = 9 and (select status from public.rentals where id = r) = 'cancelled'
      and not exists (select 1 from public.special_sale_returns where invoice_id = rental_inv),
    'W6 a rental''s refund ends it, its machine stays out until received back, as before');
end $$;

-- ═════ F Several units, several lines (the independent review's findings) ═════
do $$
declare inv uuid; s uuid[]; line uuid; plan jsonb; res jsonb; w jsonb; t text;
begin
  perform pg_temp.as_user('owner');
  -- A released, B waiting. One unit is refunded and the staff say "no" to B: the refunded unit is B.
  perform pg_temp.as_user('owner');
  perform pg_temp.mkspecial('f1', 'wh');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('f1', 2)));
  perform pg_temp.pay(inv);
  s := pg_temp.sales(inv); perform pg_temp.release(s[1]);
  line := pg_temp.line_of(inv);
  w := jsonb_build_array(jsonb_build_object('invoice_item_id', line, 'quantity', 1,
         'waiting', jsonb_build_array(jsonb_build_object('doc_id', s[2], 'still_taking', false))));
  plan := pg_temp.plan(inv, 'refund_partial', w);
  perform pg_temp.check(jsonb_array_length(plan->'stock') = 0,
    'F1 one unit refunded and the waiting one said "no" to: the released unit is not asked about');
  res := pg_temp.guided(inv, 'refund_partial', w);
  perform pg_temp.check(res->>'status' = 'approved' and pg_temp.status_of(s[1]) = 'completed' and pg_temp.status_of(s[2]) = 'cancelled'
      and pg_temp.at_wh('f1') = 9 and (select status::text from public.invoices where id = inv) = 'paid'
      and not exists (select 1 from public.special_sale_returns where invoice_id = inv),
    'F2 so the waiting unit is cancelled, the released one stays released and unsettled, and no stock moves: ' || coalesce(res->>'status', '-'));
  plan := pg_temp.plan(inv, 'cancel');
  perform pg_temp.check(jsonb_array_length(plan->'stock') = 1 and plan->'stock'->0->>'sale_no' = pg_temp.sale_no_of(s[1]),
    'F3 and a later cancellation can still ask about it');

  -- Answered "yes", or not at all: the refunded unit is the released one, which is asked about.
  perform pg_temp.as_user('owner');
  perform pg_temp.mkspecial('f4', 'wh');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('f4', 2)));
  perform pg_temp.pay(inv);
  s := pg_temp.sales(inv); perform pg_temp.release(s[1]);
  line := pg_temp.line_of(inv);
  plan := pg_temp.plan(inv, 'refund_partial', jsonb_build_array(jsonb_build_object('invoice_item_id', line, 'quantity', 1,
            'waiting', jsonb_build_array(jsonb_build_object('doc_id', s[2], 'still_taking', true)))));
  perform pg_temp.check(jsonb_array_length(plan->'stock') = 1 and plan->'stock'->0->>'sale_no' = pg_temp.sale_no_of(s[1]),
    'F4 the waiting unit still taken: the refunded unit is the released one, which is asked about');
  plan := pg_temp.plan(inv, 'refund_partial', jsonb_build_array(jsonb_build_object('invoice_item_id', line, 'quantity', 1)));
  perform pg_temp.check(jsonb_array_length(plan->'stock') = 1, 'F5 no answer about the waiting unit: the same');

  -- The same refund recorded directly (the Finance panel): a refund of part of the line with no answer is allowed
  -- only when it is a waiting unit the staff said "no" to that is being refunded.
  perform pg_temp.as_user('owner');
  perform pg_temp.mkspecial('f6', 'wh');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('f6', 2)));
  perform pg_temp.pay(inv);
  s := pg_temp.sales(inv); perform pg_temp.release(s[1]);
  line := pg_temp.line_of(inv);
  t := pg_temp.err(format('select pg_temp.refund_lines(%L, %L::jsonb, ''[]''::jsonb)', inv,
        jsonb_build_array(jsonb_build_object('invoice_item_id', line, 'amount', 1000))));
  perform pg_temp.check(t = 'Record the returned-and-sellable, damaged, or not-returned quantities for this special sale refund',
    'F6 part of the line refunded with no answer: refused: ' || t);
  t := pg_temp.err(format('select pg_temp.refund_lines(%L, %L::jsonb, ''[]''::jsonb)', inv,
        jsonb_build_array(jsonb_build_object('invoice_item_id', line, 'amount', 1000,
          'waiting', jsonb_build_array(jsonb_build_object('doc_id', s[2], 'still_taking', false))))));
  perform pg_temp.check(t = 'ok' and pg_temp.status_of(s[2]) = 'cancelled' and pg_temp.status_of(s[1]) = 'completed' and pg_temp.at_wh('f6') = 9
      and (select status::text from public.invoices where id = inv) = 'paid',
    'F7 with the waiting unit said "no" to, it goes through: it is the unit refunded; the released one stays: ' || t);
end $$;

-- Two special lines: an answer is for a unit of a line being refunded, and a refund of the whole line answers every unit.
do $$
declare inv uuid; sx uuid[]; sy uuid[]; lx uuid; ly uuid; mvx uuid; mvy uuid; t text; res jsonb;
begin
  perform pg_temp.as_user('owner');
  perform pg_temp.mkspecial('f8x', 'wh');
  perform pg_temp.mkspecial('f8y', 'wh');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('f8x'), pg_temp.sale_line('f8y')));
  perform pg_temp.pay(inv);
  select array_agg(id) into sx from public.special_sales where invoice_id = inv and special_product_id = pg_temp.fx('sp_f8x');
  select array_agg(id) into sy from public.special_sales where invoice_id = inv and special_product_id = pg_temp.fx('sp_f8y');
  perform pg_temp.release(sx[1]); perform pg_temp.release(sy[1]);
  mvx := pg_temp.mv(sx[1]); mvy := pg_temp.mv(sy[1]);
  lx := pg_temp.line_for(inv, 'f8x'); ly := pg_temp.line_for(inv, 'f8y');
  -- the whole of X, answered with Y's unit
  t := pg_temp.err(format('select pg_temp.refund_lines(%L, %L::jsonb, %L::jsonb)', inv,
        jsonb_build_array(jsonb_build_object('invoice_item_id', lx, 'amount', 1000)), pg_temp.answer(mvy, 1, 0, 0)));
  perform pg_temp.check(t = 'Record the returned-and-sellable, damaged, or not-returned quantities for this special sale refund',
    'F8 the whole of line X refunded, answered with line Y''s unit: refused: ' || t);
  -- part of X, answered with Y's unit
  t := pg_temp.err(format('select pg_temp.refund_lines(%L, %L::jsonb, %L::jsonb)', inv,
        jsonb_build_array(jsonb_build_object('invoice_item_id', lx, 'amount', 100)), pg_temp.answer(mvy, 1, 0, 0)));
  perform pg_temp.check(t = 'Answer for the units of the lines being refunded: that unit is on a line this refund does not cover',
    'F9 part of line X refunded, answered with line Y''s unit: refused: ' || t);
  -- both lines in full, answered for X alone: Y would be stranded on a refunded invoice
  t := pg_temp.err(format('select pg_temp.refund_lines(%L, %L::jsonb, %L::jsonb)', inv,
        jsonb_build_array(jsonb_build_object('invoice_item_id', lx, 'amount', 1000), jsonb_build_object('invoice_item_id', ly, 'amount', 1000)),
        pg_temp.answer(mvx, 1, 0, 0)));
  perform pg_temp.check(t = 'Record the returned-and-sellable, damaged, or not-returned quantities for this special sale refund',
    'F10 both lines in full, answered for X alone: refused, so no unit is left to a refunded invoice: ' || t);
  perform pg_temp.check(pg_temp.at_wh('f8x') = 9 and pg_temp.at_wh('f8y') = 9 and (select status::text from public.invoices where id = inv) = 'paid'
      and not exists (select 1 from public.special_sale_returns where invoice_id = inv),
    'F11 after those refusals nothing changed');
  -- both answered: it goes through
  res := pg_temp.refund_lines(inv, jsonb_build_array(jsonb_build_object('invoice_item_id', lx, 'amount', 1000), jsonb_build_object('invoice_item_id', ly, 'amount', 1000)),
           jsonb_build_array(jsonb_build_object('movement_id', mvx, 'sellable_quantity', 1, 'damaged_quantity', 0, 'not_returned_quantity', 0),
                             jsonb_build_object('movement_id', mvy, 'sellable_quantity', 0, 'damaged_quantity', 1, 'not_returned_quantity', 0)));
  perform pg_temp.check((select status::text from public.invoices where id = inv) = 'refunded' and pg_temp.at_wh('f8x') = 10 and pg_temp.at_wh('f8y') = 9,
    'F12 with both answered the refund goes through: X back, Y damaged');
end $$;

-- A line of two units, one back in stock and one damaged: reopened and paid again, the one that came back is raised again.
do $$
declare inv uuid; s uuid[]; res jsonb; n int;
begin
  perform pg_temp.as_user('owner');
  perform pg_temp.mkspecial('f13', 'wh');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('f13', 2)));
  perform pg_temp.pay(inv);
  s := pg_temp.sales(inv); perform pg_temp.release(s[1]); perform pg_temp.release(s[2]);
  res := pg_temp.guided(inv, 'refund_full', '[]', jsonb_build_object(pg_temp.sale_no_of(s[2]), jsonb_build_array(0, 1, 0)));
  perform pg_temp.check(res->>'status' = 'approved' and pg_temp.at_wh('f13') = 9 and pg_temp.status_of(s[1]) = 'cancelled' and pg_temp.status_of(s[2]) = 'completed',
    'F13 one unit back, one damaged: 9 of 10');
  perform pg_temp.as_user('owner');
  perform public.reopen_invoice(inv, 'Customer came back for both', gen_random_uuid());
  perform pg_temp.pay(inv);
  perform pg_temp.check((select count(*) from public.special_sales where invoice_id = inv) = 3
      and (select count(*) from public.special_sales where invoice_id = inv and status = 'pending') = 1,
    'F14 reopened and paid again: the unit that came back is raised again (one waiting), the damaged one is not');
  n := public.create_special_docs_for_invoice(inv);
  perform pg_temp.check(n = 0 and (select count(*) from public.special_sales where invoice_id = inv) = 3,
    'F15 and running it again raises nothing more (' || n || ')');
  perform pg_temp.release((select id from public.special_sales where invoice_id = inv and status = 'pending'));
  perform pg_temp.check(pg_temp.at_wh('f13') = 8, 'F16 released again, it is taken from stock again: 8');
end $$;

-- A correction that removes or lowers a line: a cancellation moves only the units its plan lists.
do $$
declare inv uuid; s uuid[]; pline uuid; sline uuid; plan jsonb; res jsonb;
begin
  perform pg_temp.as_user('owner');
  perform pg_temp.mkspecial('f17', 'wh');
  perform pg_temp.mkplain('f17p');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('f17'), pg_temp.prod_line('f17p')));
  perform pg_temp.pay(inv);
  s := pg_temp.sales(inv); perform pg_temp.release(s[1]);
  select id into pline from public.invoice_items where invoice_id = inv and line_kind::text = 'product';
  perform public.correct_invoice(inv, jsonb_build_array(jsonb_build_object('invoice_item_id', pline, 'kind', 'product',
            'product_id', pg_temp.fx('p_f17p'), 'quantity', 1)), '{}'::jsonb, 'Machine line removed', gen_random_uuid());
  perform pg_temp.check(not exists (select 1 from public.invoice_items where invoice_id = inv and line_kind::text = 'special_product')
      and pg_temp.status_of(s[1]) = 'completed' and pg_temp.at_wh('f17') = 9,
    'F17 a correction removes the machine line and leaves the released unit alone (known, as before)');
  plan := pg_temp.plan(inv, 'cancel');
  perform pg_temp.check(jsonb_array_length(plan->'stock') = 1 and plan->'stock'->0->>'special_sale_id' is null,
    'F18 the cancellation plan lists the product only');
  res := pg_temp.guided(inv, 'cancel');
  perform pg_temp.check(res->>'status' = 'approved' and pg_temp.at_wh('f17') = 9 and pg_temp.status_of(s[1]) = 'completed' and pg_temp.at_store('f17p') = 10,
    'F19 and the cancellation moves only that: the product back, the machine as it was (9)');

  perform pg_temp.as_user('owner');
  perform pg_temp.mkspecial('f20', 'wh');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('f20', 2)));
  perform pg_temp.pay(inv);
  s := pg_temp.sales(inv); perform pg_temp.release(s[1]); perform pg_temp.release(s[2]);
  sline := pg_temp.line_of(inv);
  perform public.correct_invoice(inv, jsonb_build_array(jsonb_build_object('invoice_item_id', sline, 'kind', 'special_product',
            'special_product_id', pg_temp.fx('sp_f20'), 'quantity', 1)), '{}'::jsonb, 'One machine only', gen_random_uuid());
  plan := pg_temp.plan(inv, 'cancel');
  perform pg_temp.check(jsonb_array_length(plan->'stock') = 1 and plan->'stock'->0->>'sale_no' = pg_temp.sale_no_of(s[1]),
    'F20 a line lowered from two units to one: the cancellation plan lists one unit');
  res := pg_temp.guided(inv, 'cancel');
  perform pg_temp.check(res->>'status' = 'approved' and pg_temp.at_wh('f20') = 9 and pg_temp.status_of(s[1]) = 'cancelled' and pg_temp.status_of(s[2]) = 'completed',
    'F21 and the cancellation puts back that one (9 of 10), not both');
  -- directly, with no answers at all, the same
  perform pg_temp.as_user('owner');
  perform pg_temp.mkspecial('f22', 'wh');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('f22', 2)));
  perform pg_temp.pay(inv);
  s := pg_temp.sales(inv); perform pg_temp.release(s[1]); perform pg_temp.release(s[2]);
  perform public.correct_invoice(inv, jsonb_build_array(jsonb_build_object('invoice_item_id', pg_temp.line_of(inv), 'kind', 'special_product',
            'special_product_id', pg_temp.fx('sp_f22'), 'quantity', 1)), '{}'::jsonb, 'One machine only', gen_random_uuid());
  perform public.cancel_invoice_recorded(inv, 'Check cancellation', gen_random_uuid());
  perform pg_temp.check(pg_temp.at_wh('f22') = 9 and pg_temp.status_of(s[1]) = 'cancelled' and pg_temp.status_of(s[2]) = 'completed',
    'F22 cancel_invoice_recorded alone does the same: one unit');
end $$;

-- The shelf it left: deleted since, or its stock row gone.
do $$
declare inv uuid; s uuid[]; mv uuid; t text; res jsonb;
begin
  perform pg_temp.as_user('owner');
  perform pg_temp.mkspecial('f23', 'wh2');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('f23')));
  perform pg_temp.pay(inv);
  s := pg_temp.sales(inv); perform pg_temp.release(s[1], 'wh2'); mv := pg_temp.mv(s[1]);
  update public.warehouse_inventory set current_qty = 0 where warehouse_id = pg_temp.fx('wh2') and product_id = pg_temp.fx('p_f23');
  update public.warehouses set deleted_at = now() where id = pg_temp.fx('wh2');
  t := pg_temp.err(format('select pg_temp.refund_line(%L, %L, null, %L::jsonb)', inv, pg_temp.line_of(inv), pg_temp.answer(mv, 1, 0, 0)));
  perform pg_temp.check(t like 'The warehouse it left (%) has been deleted, so the unit cannot be put back there.%'
      and not exists (select 1 from public.special_sale_returns where invoice_id = inv),
    'F23 sellable into a warehouse deleted since is refused, with nothing recorded: ' || t);
  t := pg_temp.err(format('select pg_temp.refund_line(%L, %L, null, %L::jsonb)', inv, pg_temp.line_of(inv), pg_temp.answer(mv, 0, 0, 1)));
  perform pg_temp.check(t = 'ok' and (select status::text from public.invoices where id = inv) = 'refunded',
    'F24 and "not returned" goes through: ' || t);

  -- its stock row gone (a warehouse can have none): the row is made, with the one unit
  perform pg_temp.as_user('owner');
  perform pg_temp.mkspecial('f25', 'wh');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('f25')));
  perform pg_temp.pay(inv);
  s := pg_temp.sales(inv); perform pg_temp.release(s[1]); mv := pg_temp.mv(s[1]);
  delete from public.warehouse_inventory where warehouse_id = pg_temp.fx('wh') and product_id = pg_temp.fx('p_f25');
  res := pg_temp.guided(inv, 'refund_full');
  perform pg_temp.check(res->>'status' = 'approved' and pg_temp.at_wh('f25') = 1
      and exists (select 1 from public.warehouse_inventory where warehouse_id = pg_temp.fx('wh') and product_id = pg_temp.fx('p_f25') and current_qty = 1),
    'F25 a warehouse with no stock row for it gets one, holding the unit');
  perform pg_temp.as_user('owner');
  perform pg_temp.mkspecial('f26', 'store');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('f26')));
  perform pg_temp.pay(inv);
  s := pg_temp.sales(inv); perform pg_temp.release(s[1], 'store');
  delete from public.store_inventory where store_id = pg_temp.fx('store') and product_id = pg_temp.fx('p_f26');
  res := pg_temp.guided(inv, 'refund_full');
  perform pg_temp.check(res->>'status' = 'approved' and pg_temp.at_store('f26') = 1, 'F26 and so does a store');
end $$;

-- A line of two units, one released and one still waiting: refunded in full, the released one comes back and the
-- waiting one is cancelled (393); reopened and paid again, both are raised again.
do $$
declare inv uuid; s uuid[]; res jsonb;
begin
  perform pg_temp.as_user('owner');
  perform pg_temp.mkspecial('f27', 'wh');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('f27', 2)));
  perform pg_temp.pay(inv);
  s := pg_temp.sales(inv); perform pg_temp.release(s[1]);
  res := pg_temp.guided(inv, 'refund_full');
  perform pg_temp.check(res->>'status' = 'approved' and pg_temp.at_wh('f27') = 10
      and pg_temp.status_of(s[1]) = 'cancelled' and pg_temp.status_of(s[2]) = 'cancelled',
    'F27 one unit released, one waiting, refunded in full: the unit is back (10 of 10) and both sales are cancelled');
  perform pg_temp.as_user('owner');
  perform public.reopen_invoice(inv, 'Customer came back for both', gen_random_uuid());
  perform pg_temp.pay(inv);
  perform pg_temp.check((select count(*) from public.special_sales where invoice_id = inv) = 4
      and (select count(*) from public.special_sales where invoice_id = inv and status = 'pending') = 2,
    'F28 reopened and paid again: both units are raised again (two waiting), the one that was only waiting too');
end $$;

-- A store deleted since: the unit cannot go back on its shelf (sellable is refused), as for a warehouse. A store
-- of its own, since one holding stock cannot be deleted.
do $$
declare inv uuid; s uuid[]; mv uuid; t text; st3 uuid; sfx text := lower(substr(md5(random()::text), 1, 6));
begin
  perform pg_temp.as_user('owner');
  insert into public.stores(name, code, country_code) values ('R496 Store C ' || sfx, 'R496C' || sfx, 'SG') returning id into st3;
  perform pg_temp.mkspecial('f29', 'wh');
  insert into public.store_inventory(store_id, product_id, current_qty) values (st3, pg_temp.fx('p_f29'), 5);
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('f29')));
  perform pg_temp.pay(inv);
  s := pg_temp.sales(inv); perform public.fulfil_special_doc('special_sale', s[1], st3, 'store'); mv := pg_temp.mv(s[1]);
  update public.store_inventory set current_qty = 0 where store_id = st3 and product_id = pg_temp.fx('p_f29');
  update public.stores set deleted_at = now() where id = st3;
  t := pg_temp.err(format('select pg_temp.refund_line(%L, %L, null, %L::jsonb)', inv, pg_temp.line_of(inv), pg_temp.answer(mv, 1, 0, 0)));
  perform pg_temp.check(t like 'The store it left (%) has been deleted, so the unit cannot be put back there.%'
      and not exists (select 1 from public.special_sale_returns where invoice_id = inv),
    'F29 sellable into a store deleted since is refused, with nothing recorded: ' || t);
  t := pg_temp.err(format('select pg_temp.refund_line(%L, %L, null, %L::jsonb)', inv, pg_temp.line_of(inv), pg_temp.answer(mv, 0, 0, 1)));
  perform pg_temp.check(t = 'ok' and (select status::text from public.invoices where id = inv) = 'refunded',
    'F29b and "not returned" goes through: ' || t);
end $$;

-- A part refund of a line with a released unit asks about it, even when the same refund says of another line's
-- waiting unit that the customer is not taking it.
do $$
declare inv uuid; sa uuid; sb uuid; la uuid; lb uuid; t text;
begin
  perform pg_temp.as_user('owner');
  perform pg_temp.mkspecial('f30a', 'wh'); perform pg_temp.mkspecial('f30b', 'wh');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('f30a'), pg_temp.sale_line('f30b')));
  perform pg_temp.pay(inv);
  select id into sa from public.special_sales where invoice_id = inv and special_product_id = pg_temp.fx('sp_f30a');
  select id into sb from public.special_sales where invoice_id = inv and special_product_id = pg_temp.fx('sp_f30b');
  perform pg_temp.release(sa);
  la := pg_temp.line_for(inv, 'f30a'); lb := pg_temp.line_for(inv, 'f30b');
  t := pg_temp.err(format('select pg_temp.refund_lines(%L, %L::jsonb, %L::jsonb)', inv,
         jsonb_build_array(jsonb_build_object('invoice_item_id', la, 'amount', 100),
                           jsonb_build_object('invoice_item_id', lb, 'amount', 1000,
                             'waiting', jsonb_build_array(jsonb_build_object('doc_id', sb, 'still_taking', false)))),
         '[]'));
  perform pg_temp.check(t like 'Record the returned-and-sellable, damaged, or not-returned quantities for this special sale refund%'
      and (select status::text from public.invoices where id = inv) = 'paid',
    'F30 a part refund of the line with the released unit asks, though another line''s waiting unit was said not wanted: ' || t);
end $$;

-- ═════ H History ═════
do $$
declare inv uuid; s uuid[]; ret uuid; res jsonb;
begin
  perform pg_temp.as_user('owner');
  perform pg_temp.mkspecial('h1', 'wh');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('h1')));
  perform pg_temp.pay(inv);
  s := pg_temp.sales(inv); perform pg_temp.release(s[1]);
  res := pg_temp.guided(inv, 'refund_full');
  select id into ret from public.stock_movements where reversed_sale_id = pg_temp.mv(s[1]);
  perform pg_temp.check(public.stock_history_effect(ret, 'warehouse:' || pg_temp.fx('wh')) = 1
      and public.stock_history_effect(pg_temp.mv(s[1]), 'warehouse:' || pg_temp.fx('wh')) = -1
      and public.stock_history_type_label('invoice_refund_return') = 'Refund Return',
    'H1 Stock History: the release is -1 at the warehouse and the return +1, labelled Refund Return');
  perform pg_temp.check(exists (select 1 from public.stock_history_inventory_changes c where c.product_id = pg_temp.fx('p_h1')
                                   and c.location_key = 'warehouse:' || pg_temp.fx('wh') and c.delta = 1),
    'H2 and the inventory change was captured by its trigger');
end $$;

-- ═════ S Access, grants, and what is untouched ═════
do $$
declare inv uuid; s uuid[]; res jsonb;
begin
  perform pg_temp.as_user('owner');
  perform pg_temp.mkspecial('s1', 'wh');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('s1')));
  perform pg_temp.pay(inv);
  s := pg_temp.sales(inv); perform pg_temp.release(s[1]);
  res := pg_temp.guided(inv, 'refund_full');
  insert into fx values ('s_inv', inv);
end $$;
select pg_temp.fx('s_inv')::text as s_inv, pg_temp.fx('owner')::text as u_owner, pg_temp.fx('staff')::text as u_staff, pg_temp.fx('other')::text as u_other \gset
select set_config('request.jwt.claim.sub', :'u_owner', true), set_config('request.jwt.claim.role', 'authenticated', true), set_config('request.jwt.claims', '', true);
set local role authenticated;
select count(*) as n from public.special_sale_returns where invoice_id = :'s_inv' \gset owner_
reset role;
select set_config('request.jwt.claim.sub', :'u_staff', true);
set local role authenticated;
select count(*) as n from public.special_sale_returns where invoice_id = :'s_inv' \gset staff_
reset role;
select set_config('request.jwt.claim.sub', :'u_other', true);
set local role authenticated;
select count(*) as n from public.special_sale_returns where invoice_id = :'s_inv' \gset other_
reset role;
select set_config('request.jwt.claim.sub', '', true), set_config('request.jwt.claim.role', 'anon', true);
set local role anon;
select count(*) as n from public.special_sale_returns \gset anon_
reset role;
select pg_temp.check(:owner_n = 1 and :staff_n = 1 and :other_n = 0 and :anon_n = 0,
  'S1 the answers are read by an Owner and staff of the store, not by another store''s staff or a signed-out visitor: '
  || :owner_n || '/' || :staff_n || '/' || :other_n || '/' || :anon_n);
select pg_temp.check(not exists (
    select 1 from unnest(array['special_release_rows(uuid)', 'return_released_special_stock(uuid,uuid,integer,integer,integer,uuid,text,text)',
                               'restore_released_special_stock(uuid,text,uuid)', 'link_released_special_movements()']) f
     where has_function_privilege('anon', to_regprocedure('public.' || f), 'execute') or has_function_privilege('authenticated', to_regprocedure('public.' || f), 'execute')
        or not has_function_privilege('service_role', to_regprocedure('public.' || f), 'execute')),
  'S2 the four new functions are internal: the service role alone');
select pg_temp.check(
    has_function_privilege('authenticated', to_regprocedure('public.fulfil_special_doc(text,uuid,uuid,text)'), 'execute')
    and has_function_privilege('authenticated', to_regprocedure('public.invoice_refund_options(uuid)'), 'execute')
    and has_function_privilege('authenticated', to_regprocedure('public.invoice_action_plan(uuid,text,jsonb)'), 'execute')
    and has_function_privilege('authenticated', to_regprocedure('public.refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid)'), 'execute')
    and has_function_privilege('authenticated', to_regprocedure('public.cancel_invoice_recorded(uuid,text,uuid)'), 'execute')
    and not has_function_privilege('anon', to_regprocedure('public.refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid)'), 'execute')
    and not has_function_privilege('authenticated', to_regprocedure('public.record_invoice_stock_return(uuid,jsonb,text,uuid)'), 'execute')
    and not has_function_privilege('authenticated', to_regprocedure('public.create_special_docs_for_invoice(uuid)'), 'execute'),
  'S3 the patched functions keep their grants: signed-in staff as before, and the two internal ones still internal');
-- What 496 does not touch is what it was (production's md5, or 495's where 495 is in).
select pg_temp.check(
    pg_temp.md5_of('resolve_invoice_action_v2(uuid,boolean,text,text,jsonb,jsonb,boolean)') = '201f08ebf14a64cd88d411a7cfb4c9c4'
    and pg_temp.md5_of('request_invoice_action_v2(uuid,text,jsonb,text,text,uuid)') = '4360d74462ed1fc950b6bd8b5157b3ae'
    and pg_temp.md5_of('settle_waiting_special_docs_on_refund(uuid,jsonb,text)') = 'edfd1f1beb7ab3b6739096a618cd6a96'
    and pg_temp.md5_of('cancel_waiting_special_docs(uuid,text,text,uuid,uuid[])') = 'fe4753fffded2cc463dbe24571a9675c'
    and pg_temp.md5_of('special_doc_invoice_problem(uuid,uuid)') = 'be2b8ec5a4003a1dca34e17a82f89932'
    and pg_temp.md5_of('rentals_follow_refund(uuid,jsonb,text)') = '0426b050207ccb4fe0a991b3cafc9769'
    and pg_temp.md5_of('invoice_refunded_stock(uuid)') = 'f12af401547ce01e2b95ec3a5c230bad'
    and pg_temp.md5_of('release_special_sale_to_supplier(uuid,uuid,text)') = '15b36ba68fd7b70a1361e80f5e5fad4e'
    and pg_temp.md5_of('special_docs_awaiting_fulfilment()') = 'fdaf5aca81c63cc99f8fddcfcf10564c'
    and pg_temp.md5_of('restore_invoice_stock(uuid,text)') in ('092316c3af22361f80d186e38fe49bf3', 'fe23a3b4e428641b5aed19580614070a')
    and pg_temp.md5_of('invoice_goods_out(uuid)') in ('15ffed0ff0d5d9cc5685af8e834302ae', 'bb002119b3cb779a4b1c8bb79e08ae25'),
  'S4 the approval and request functions, the waiting-sale rules, the rentals, the supplier release and restore_invoice_stock (so a correction) are untouched');

-- ═════ U Undo and again ═════
\if :{?skip_install}
do $$ begin raise notice 'NOTE  U1-U3 are skipped: they undo and reinstall 496'; end $$;
\else
create temp table after_install as select pg_temp.fp() f;
\ir ../undo-496.sql
select pg_temp.check((select count(*) from pg_proc where pronamespace = 'public'::regnamespace
                       and proname in ('special_release_rows', 'return_released_special_stock', 'restore_released_special_stock', 'link_released_special_movements')) = 0
    and split_part(pg_temp.fp(), ' ', 2)::int = split_part((select f from after_install), ' ', 2)::int - 4
    and exists (select 1 from information_schema.columns where table_name = 'special_sales' and column_name = 'release_movement_id')
    and exists (select 1 from pg_class where relname = 'special_sale_returns'),
  'U1 undo drops the four functions and keeps the column and the table');
select pg_temp.check(pg_temp.md5_of('fulfil_special_doc(text,uuid,uuid,text)') = 'e2fd9fca6842b5193ec7020445a45189'
    and pg_temp.md5_of('invoice_refund_options(uuid)') = '689a71c246260d2c10ec44dd94eb7139'
    and pg_temp.md5_of('invoice_action_plan(uuid,text,jsonb)') = '383d618edb28c3c9a360242d038a022c'
    and pg_temp.md5_of('refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid)') in ('804ecd829cfecf713783a09a05d93c7e', '3280f4ed6afb93aed7366eaf100c6383')
    and pg_temp.md5_of('record_invoice_stock_return(uuid,jsonb,text,uuid)') = '6b125cb5df1eb103781662bef41e9417'
    and pg_temp.md5_of('cancel_invoice_recorded(uuid,text,uuid)') = 'de52d9dbaef8ab15163bef35cb9d733d'
    and pg_temp.md5_of('create_special_docs_for_invoice(uuid)') = '429f4ac315cb5d0557c2005807bad115',
  'U2 and the seven are production''s texts again (refund_invoice_recorded: or 495''s, where 495 is in)');
\ir ../../../supabase/496_released_special_sale_stock_comes_back.sql
select pg_temp.check(pg_temp.fp() = (select f from after_install), 'U3 496 again gives back exactly what it gave: ' || pg_temp.fp());
\endif

-- ═════ Done ═════
do $$
declare n int; msgs text;
begin
  select count(*), string_agg(msg, E'\n') into n, msgs from failed;
  if n > 0 then raise exception '% check(s) failed:%', n, E'\n' || msgs; end if;
  raise notice 'All 496 checks passed.';
end $$;
rollback;
