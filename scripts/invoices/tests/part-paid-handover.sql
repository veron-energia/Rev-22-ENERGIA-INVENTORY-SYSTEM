-- 399: goods handed over before full payment.
--
-- The Owner's rules of 6 Oct 2026: a part payment on an invoice with goods to
-- collect is saved with the answer "Nothing taken" or the products taken now
-- (per product, up to what is still to collect, promotion contents and picks
-- included), in the same transaction; a "Hand over items" button does the same
-- with no payment; a hand-over is a store_sale from the invoice's store,
-- linked to the invoice, with a record and an audit row, refused when the
-- store is short or the invoice fulfils from a warehouse; full payment takes
-- only the rest and the guarantee trigger finds nothing missing; a correction
-- that takes off handed-over goods is refused until "Record items returned"
-- (Owner/Manager: Good back to the shelf, Damaged / Not returned written off)
-- and one that leaves them alone never puts them back on the shelf; Make FOC
-- takes only the rest; Delete refuses while goods are out; a warehouse never
-- counts them twice; callers without the hand-over key work as before.
--
--   1  The migration re-runs as a no-op; grants.
--   2  A part payment with items: movements, stock, the record, the audit row.
--   3  A part payment with "Nothing taken": nothing moves; it is recorded.
--   4  Retries: the same request writes nothing again; a different answer
--      under the same request is refused.
--   5  Refusals leave nothing behind: more than still to collect, a product
--      not on the invoice, malformed answers, a short store.
--   6  Hand over items: later, with no payment; who may; on what.
--   7  Full payment takes only the rest; the guarantee finds nothing missing;
--      the two "already deducted" figures agree.
--   8  Promotions and picks.
--   9  Cancellation and refund with goods out.
--   10 Corrections: refused while they take off handed-over goods, allowed
--      after Record items returned; other corrections keep the goods out; a
--      correction that settles the invoice takes only the rest.
--   11 Record items returned: who, what, retries.
--   12 Make FOC takes only the rest.
--   13 Delete refuses while goods are out.
--   14 Fulfil from a warehouse: refused in combination, at every door,
--      including goods the customer kept (Not returned); allowed, and
--      counted once, after Good or Damaged.
--   15 Callers without the key (website orders, record_invoice_payment, the
--      internal payment path) work as before; a full payment skips the key.
--   16 What the page reads: invoice_goods_status and invoice_list_goods_out;
--      nothing "to collect" once paid, cancelled or refunded.
--   17 Settled after a Damaged return, by every path (Record Payment,
--      Correct amount, a header-only correction): the replacement leaves the
--      shelf once, the guarantee and the gaps report agree.
--
-- Every check runs, then the file fails if any did. Disposable local database
-- only; everything is rolled back. 399 is applied inside this transaction, so
-- run the file on its own:
--   psql -v ON_ERROR_STOP=1 -f scripts/invoices/tests/part-paid-handover.sql
-- On a local database that has drifted from production, pass a file that
-- installs production's functions, run right after the begin below:
--   psql -v ON_ERROR_STOP=1 -v prelude=/path/to/prod_prelude.sql -f ...
-- Every name, phone, number and amount here is invented.
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '10s';
set local statement_timeout = '300s';
\if :{?prelude}
\i :prelude
\endif

\ir ../../../supabase/399_part_paid_handover.sql

create temp table failed(n serial, msg text);
create function pg_temp.check(ok boolean, msg text) returns void language plpgsql as
$$begin
  if ok is distinct from true then insert into failed(msg) values (msg); raise notice 'FAIL  %', msg;
  else raise notice 'PASS  %', msg; end if;
end$$;
create temp table fx(k text primary key, v uuid);
create function pg_temp.fx(key text) returns uuid language sql as $$ select v from fx where k = key $$;
create function pg_temp.as_user(key text) returns void language sql as
$$ select set_config('request.jwt.claim.sub', pg_temp.fx(key)::text, true) $$;
-- Shelf stock of a test product at a store.
create function pg_temp.stock(p text, st text default 'A') returns int language sql as
$$ select coalesce((select current_qty from public.store_inventory
                     where store_id = pg_temp.fx(st) and product_id = pg_temp.fx(p)), 0) $$;
-- An invoice's store_sale units of a product, less cancellation returns.
create function pg_temp.sold(inv uuid, p text) returns int language sql as
$$ select coalesce(sum(case when movement_type::text = 'store_sale' then quantity
                            when movement_type::text = 'invoice_cancel_return' then -quantity else 0 end), 0)::int
     from public.stock_movements where invoice_id = inv and product_id = pg_temp.fx(p) $$;
create function pg_temp.moves(inv uuid) returns int language sql as
$$ select count(*)::int from public.stock_movements where invoice_id = inv $$;
create function pg_temp.todo(inv uuid, p text) returns int language sql as
$$ select coalesce(sum(quantity), 0)::int from public.invoice_stock_to_deduct(inv)
    where kind = 'product' and item_id = pg_temp.fx(p) $$;
create function pg_temp.out_qty(inv uuid, p text) returns int language sql as
$$ select coalesce(sum(quantity), 0)::int from public.invoice_goods_out(inv) where product_id = pg_temp.fx(p) $$;
create function pg_temp.pays(inv uuid) returns int language sql as
$$ select count(*)::int from public.invoice_payments where invoice_id = inv $$;
create function pg_temp.hrows(inv uuid) returns int language sql as
$$ select count(*)::int from public.invoice_handovers where invoice_id = inv $$;
-- {"items": [...]} from product keys and quantities: pg_temp.take('pillow', 1, 'socks', 2).
create function pg_temp.take(p1 text, q1 int, p2 text default null, q2 int default null) returns jsonb language sql as
$$ select jsonb_build_object('items', jsonb_build_array(jsonb_build_object('product_id', pg_temp.fx(p1), 'qty', q1))
     || case when p2 is null then '[]'::jsonb
             else jsonb_build_array(jsonb_build_object('product_id', pg_temp.fx(p2), 'qty', q2)) end) $$;
-- An invoice at a store for Jane Tan, made by the Owner.
create function pg_temp.mk(lines jsonb, st text default 'A') returns uuid language plpgsql as
$$begin perform pg_temp.as_user('o');
  return public.create_invoice(pg_temp.fx(st), pg_temp.fx('jane'), null, lines); end$$;
create function pg_temp.line(p text, q int) returns jsonb language sql as
$$ select jsonb_build_object('kind', 'product', 'product_id', pg_temp.fx(p), 'quantity', q) $$;
-- A payment as the Invoices page records it, with or without the hand-over key.
create function pg_temp.settle(inv uuid, amount numeric, req uuid, handover jsonb default null, with_key boolean default true)
returns jsonb language sql as
$$ select public.record_invoice_settlement(inv,
     jsonb_build_object('receipts', jsonb_build_array(jsonb_build_object('key', 'line-0',
       'payment_method_id', pg_temp.fx('cash'), 'amount', amount)), 'arrangements', '[]'::jsonb)
     || case when with_key and handover is not null then jsonb_build_object('handover', handover) else '{}'::jsonb end,
     req) $$;
-- Runs a statement; null when it worked, else the refusal (everything it did is undone).
create function pg_temp.err(stmt text) returns text language plpgsql as
$$begin execute stmt; return null; exception when others then return sqlerrm; end$$;
-- The invoice's product lines as the correction form sends them back.
create function pg_temp.lines(inv uuid) returns jsonb language sql as
$$ select jsonb_agg(jsonb_build_object('invoice_item_id', id, 'kind', line_kind::text, 'product_id', product_id,
     'quantity', quantity, 'unit_price', unit_price) order by id)
     from public.invoice_items where invoice_id = inv $$;
-- The same lines with one product's quantity changed (0 removes the line).
create function pg_temp.lines_with(inv uuid, p text, q int) returns jsonb language sql as
$$ select coalesce(jsonb_agg(case when (l->>'product_id')::uuid = pg_temp.fx(p) then l || jsonb_build_object('quantity', q) else l end)
                     filter (where not ((l->>'product_id')::uuid = pg_temp.fx(p) and q = 0)), '[]'::jsonb)
     from jsonb_array_elements(pg_temp.lines(inv)) l $$;
create function pg_temp.correct(inv uuid, items jsonb, hdr jsonb default '{}'::jsonb) returns text language plpgsql as
$$begin perform public.correct_invoice(inv, items, hdr, 'Keyed wrongly at the till', gen_random_uuid()); return null;
exception when others then return sqlerrm; end$$;

-- ═════ Fixtures (invented) ═════
do $$
declare o uuid := gen_random_uuid(); m uuid := gen_random_uuid(); s uuid := gen_random_uuid();
  sb uuid := gen_random_uuid(); sx uuid := gen_random_uuid();
  sfx text := lower(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
  ph text := lpad((floor(random() * 9000))::int::text, 4, '0');
  st_a uuid; st_b uuid; wh uuid; cash uuid; jane uuid; promo uuid; grp uuid; k text; pid uuid;
begin
  insert into auth.users(id, email) values
    (o, 'h399-o-' || sfx || '@sig.invalid'), (m, 'h399-m-' || sfx || '@sig.invalid'),
    (s, 'h399-s-' || sfx || '@sig.invalid'), (sb, 'h399-sb-' || sfx || '@sig.invalid'),
    (sx, 'h399-sx-' || sfx || '@sig.invalid');
  insert into public.profiles(id, full_name, email, role) values
    (o, 'H399 Owner', 'h399-o-' || sfx || '@sig.invalid', 'owner'),
    (m, 'H399 Manager', 'h399-m-' || sfx || '@sig.invalid', 'manager'),
    (s, 'H399 Staff', 'h399-s-' || sfx || '@sig.invalid', 'staff'),
    (sb, 'H399 Staff B', 'h399-sb-' || sfx || '@sig.invalid', 'staff'),
    (sx, 'H399 Former Staff', 'h399-sx-' || sfx || '@sig.invalid', 'staff');
  perform set_config('request.jwt.claim.sub', o::text, true);
  insert into public.stores(name, code, country_code) values ('H399 Store A ' || sfx, 'H399A' || sfx, 'SG') returning id into st_a;
  insert into public.stores(name, code, country_code) values ('H399 Store B ' || sfx, 'H399B' || sfx, 'SG') returning id into st_b;
  insert into public.warehouses(name, code) values ('H399 Warehouse ' || sfx, 'H399W' || sfx) returning id into wh;
  insert into public.user_store_assignments(user_id, store_id) values (s, st_a), (m, st_a), (sb, st_b), (sx, st_a);
  update public.profiles set is_active = false where id = sx;
  insert into public.payment_methods(name) values ('H399 Cash ' || sfx) returning id into cash;
  insert into public.customers(full_name, phone) values ('Jane Tan', '+659139' || ph) returning id into jane;
  insert into fx values ('o', o), ('m', m), ('s', s), ('sb', sb), ('sx', sx), ('A', st_a), ('B', st_b), ('wh', wh),
    ('cash', cash), ('jane', jane);
  foreach k in array array['pillow', 'socks', 'beads', 'bottle', 'corset', 'pad', 'scarce', 'band'] loop
    insert into public.products(name, sku, product_type) values ('H399 ' || initcap(k), 'H399-' || k || '-' || sfx, 'own')
      returning id into pid;
    insert into fx values (k, pid);
    insert into public.store_inventory(store_id, product_id, current_qty)
      values (st_a, pid, case when k = 'scarce' then 1 else 20 end), (st_b, pid, 20);
    insert into public.warehouse_inventory(warehouse_id, product_id, current_qty) values (wh, pid, 20);
    perform public.set_product_prices(st_a, pid, 100, 100, 'available');
    perform public.set_product_prices(st_b, pid, 100, 100, 'available');
  end loop;
  -- A sleep set: a bottle and two beads, and one pick of a corset or a pad.
  insert into public.promotions(name, code) values ('H399 Sleep Set ' || sfx, 'H399-SET-' || sfx) returning id into promo;
  insert into public.promotion_items(promotion_id, item_type, product_id, quantity)
    values (promo, 'product', pg_temp.fx('bottle'), 1), (promo, 'product', pg_temp.fx('beads'), 2);
  insert into public.promotion_choice_groups(promotion_id, label, item_kind, choose_qty)
    values (promo, 'Pick one support', 'product', 1) returning id into grp;
  insert into public.promotion_choice_options(group_id, product_id)
    values (grp, pg_temp.fx('corset')), (grp, pg_temp.fx('pad'));
  perform public.set_promotion_prices(promo, st_a, 500, 500, true);
  insert into fx values ('promo', promo), ('grp', grp);
end $$;

-- ===== 1. Re-run, grants =====
create temp table t399_before as
  select p.oid::regprocedure::text as fn, md5(pg_get_functiondef(p.oid)) as md5,
         coalesce(array_to_string(p.proacl, ','), '') as acl
    from pg_proc p where p.pronamespace = 'public'::regnamespace;
create temp table t399_rel_before as
  select c.relname, (select count(*) from pg_attribute a where a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped) as cols,
         (select count(*) from pg_constraint k where k.conrelid = c.oid) as cons,
         (select count(*) from pg_policies pl where pl.schemaname = 'public' and pl.tablename = c.relname) as pols,
         coalesce(array_to_string(c.relacl, ','), '') as acl
    from pg_class c where c.relnamespace = 'public'::regnamespace
     and c.relname in ('invoice_handovers', 'invoice_handover_lines', 'invoice_handover_return_lines');
\ir ../../../supabase/399_part_paid_handover.sql
do $$
begin
  perform pg_temp.check(not exists (select 1 from pg_proc p left join t399_before b on b.fn = p.oid::regprocedure::text
      where p.pronamespace = 'public'::regnamespace
        and (b.fn is null or b.md5 <> md5(pg_get_functiondef(p.oid))
             or b.acl <> coalesce(array_to_string(p.proacl, ','), ''))),
    '1a a second run of 399 changes no function or grant');
  perform pg_temp.check((select count(*) from t399_rel_before) = 3 and not exists (
      select 1 from t399_rel_before b join pg_class c on c.relname = b.relname and c.relnamespace = 'public'::regnamespace
       where b.cols <> (select count(*) from pg_attribute a where a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped)
          or b.cons <> (select count(*) from pg_constraint k where k.conrelid = c.oid)
          or b.pols <> (select count(*) from pg_policies pl where pl.schemaname = 'public' and pl.tablename = c.relname)
          or b.acl <> coalesce(array_to_string(c.relacl, ','), '')),
    '1b a second run changes no table, column, constraint, policy or table grant');
  perform pg_temp.check(not exists (select 1 from unnest(array['public.invoice_goods_out(uuid)',
        'public.invoice_goods_kept_check(uuid)', 'public.invoice_handover_internal(uuid,jsonb,uuid,text,uuid)',
        'public.invoice_before_full_payment(uuid)']) f
      where has_function_privilege('authenticated', f, 'execute') or has_function_privilege('anon', f, 'execute')),
    '1c the internal helpers are callable by no client role');
  perform pg_temp.check(not exists (select 1 from unnest(array['public.record_invoice_handover(uuid,jsonb,uuid)',
        'public.record_invoice_goods_return(uuid,jsonb,text,uuid)', 'public.invoice_goods_status(uuid)',
        'public.invoice_list_goods_out(uuid[])', 'public.record_invoice_settlement(uuid,jsonb,uuid)']) f
      where not has_function_privilege('authenticated', f, 'execute') or has_function_privilege('anon', f, 'execute')),
    '1d the page''s functions are staff-only');
  perform pg_temp.check(not exists (select 1 from unnest(array['public.invoice_handovers', 'public.invoice_handover_lines',
        'public.invoice_handover_return_lines']) t
      where has_table_privilege('authenticated', t, 'insert') or has_table_privilege('authenticated', t, 'update')
         or has_table_privilege('authenticated', t, 'delete') or has_table_privilege('anon', t, 'select')
         or not has_table_privilege('authenticated', t, 'select')),
    '1e staff read the hand-over records (row-level security by store) and write them only through the functions');
end $$;

-- ===== 2. A part payment with items =====
do $$
declare inv uuid; req uuid := gen_random_uuid(); res jsonb; h public.invoice_handovers%rowtype; m public.stock_movements%rowtype;
  p0 int := pg_temp.stock('pillow'); s0 int := pg_temp.stock('socks');
begin
  inv := pg_temp.mk(jsonb_build_array(pg_temp.line('pillow', 2), pg_temp.line('socks', 3)));
  insert into fx values ('inv2', inv);
  perform pg_temp.as_user('s');
  res := pg_temp.settle(inv, 150, req, pg_temp.take('pillow', 1, 'socks', 2));
  perform pg_temp.check((select status::text from public.invoices where id = inv) = 'partially_paid'
      and pg_temp.pays(inv) = 1 and (select paid_amount from public.invoices where id = inv) = 150,
    '2a the part payment is recorded as before (part-paid, 150 of 500)');
  perform pg_temp.check(pg_temp.stock('pillow') = p0 - 1 and pg_temp.stock('socks') = s0 - 2,
    '2b the store''s stock goes down by what was taken (1 pillow, 2 socks)');
  perform pg_temp.check(pg_temp.moves(inv) = 2 and not exists (select 1 from public.stock_movements x where x.invoice_id = inv
      and (x.movement_type::text <> 'store_sale' or x.from_store_id <> pg_temp.fx('A')
           or x.notes <> 'Handed over before full payment — ' || (select invoice_no from public.invoices where id = inv)
           or x.created_by <> pg_temp.fx('s'))),
    '2c one store_sale per product, from the invoice''s store, linked to it, by the staff member, noted "Handed over before full payment — INV…"');
  select * into h from public.invoice_handovers where invoice_id = inv;
  perform pg_temp.check(h.kind = 'handover' and h.source = 'payment' and h.settlement_request_id = req
      and h.created_by = pg_temp.fx('s') and h.store_id = pg_temp.fx('A') and h.request_id = md5(req::text || ':handover')::uuid
      and (select count(*) from public.invoice_handover_lines l where l.handover_id = h.id) = 2
      and not exists (select 1 from public.invoice_handover_lines l join public.stock_movements x on x.id = l.movement_id
                       where l.handover_id = h.id and (x.product_id <> l.product_id or x.quantity <> l.quantity)),
    '2d the record: a header (who, when, with this payment''s request) and a line per product pointing at its movement');
  perform pg_temp.check(exists (select 1 from public.audit_logs a where a.record_id = inv and a.action = 'invoice_goods_handed_over'
      and a.changed_by = pg_temp.fx('s') and a.store_id = pg_temp.fx('A') and jsonb_array_length(a.new_data->'items') = 2),
    '2e an audit row says what was handed over');
  perform pg_temp.check(res->'handover'->>'kind' = 'handover' and jsonb_array_length(res->'handover'->'items') = 2
      and (res->'handover'->>'replayed')::boolean = false,
    '2f the settlement answers with the hand-over');
  perform pg_temp.check(pg_temp.todo(inv, 'pillow') = 1 and pg_temp.todo(inv, 'socks') = 1
      and pg_temp.out_qty(inv, 'pillow') = 1 and pg_temp.out_qty(inv, 'socks') = 2,
    '2g still to collect: 1 pillow and 1 sock; out with the customer: 1 pillow and 2 socks');
end $$;

-- ===== 3. "Nothing taken" =====
do $$
declare inv uuid; res jsonb; p0 int := pg_temp.stock('pillow');
begin
  inv := pg_temp.mk(jsonb_build_array(pg_temp.line('pillow', 1)));
  perform pg_temp.as_user('s');
  res := pg_temp.settle(inv, 40, gen_random_uuid(), '{"none": true}'::jsonb);
  perform pg_temp.check(pg_temp.moves(inv) = 0 and pg_temp.stock('pillow') = p0 and pg_temp.pays(inv) = 1
      and (select status::text from public.invoices where id = inv) = 'partially_paid',
    '3a "Nothing taken": the payment is recorded and no stock moves');
  perform pg_temp.check((select count(*) from public.invoice_handovers h where h.invoice_id = inv and h.kind = 'nothing_taken'
      and h.source = 'payment' and h.created_by = pg_temp.fx('s')) = 1
      and not exists (select 1 from public.invoice_handover_lines l where l.invoice_id = inv)
      and exists (select 1 from public.audit_logs a where a.record_id = inv and a.action = 'invoice_goods_nothing_taken')
      and res->'handover'->>'kind' = 'nothing_taken',
    '3b and the answer is recorded, with who and when, and audited');
end $$;

-- ===== 4. Retries =====
do $$
declare inv uuid; req uuid := gen_random_uuid(); res jsonb; p0 int; n0 int; e text; breq uuid := gen_random_uuid();
begin
  inv := pg_temp.mk(jsonb_build_array(pg_temp.line('pillow', 3)));
  perform pg_temp.as_user('s');
  perform pg_temp.settle(inv, 100, req, pg_temp.take('pillow', 1));
  p0 := pg_temp.stock('pillow'); n0 := pg_temp.moves(inv);
  res := pg_temp.settle(inv, 100, req, pg_temp.take('pillow', 1));
  perform pg_temp.check(pg_temp.pays(inv) = 1 and pg_temp.moves(inv) = n0 and pg_temp.stock('pillow') = p0
      and pg_temp.hrows(inv) = 1 and (res->'handover'->>'replayed')::boolean,
    '4a the same payment retried writes no second payment, movement or record, and says it was a replay');
  e := pg_temp.err(format('select pg_temp.settle(%L, 100, %L, pg_temp.take(''pillow'', 2))', inv, req));
  perform pg_temp.check(e like '%already used for a different hand-over%' and pg_temp.pays(inv) = 1
      and pg_temp.moves(inv) = n0 and pg_temp.stock('pillow') = p0,
    '4b the same request with a different answer is refused, leaving everything as it was');
  -- The button, retried.
  perform public.record_invoice_handover(inv, pg_temp.take('pillow', 1), breq);
  p0 := pg_temp.stock('pillow'); n0 := pg_temp.moves(inv);
  res := public.record_invoice_handover(inv, pg_temp.take('pillow', 1), breq);
  perform pg_temp.check((res->>'replayed')::boolean and pg_temp.moves(inv) = n0 and pg_temp.stock('pillow') = p0
      and pg_temp.hrows(inv) = 2,
    '4c Hand over items retried writes nothing again');
  e := pg_temp.err(format('select public.record_invoice_handover(%L, pg_temp.take(''pillow'', 1, ''socks'', 1), %L)', inv, breq));
  perform pg_temp.check(e like '%already used for a different hand-over%', '4d and with a different answer is refused');
end $$;

-- ===== 5. Refusals leave nothing behind =====
do $$
declare inv uuid; inv_s uuid; e text; p0 int; sc0 int; ok boolean := true; stmt text;
begin
  inv := pg_temp.mk(jsonb_build_array(pg_temp.line('pillow', 2)));
  perform pg_temp.as_user('s');
  p0 := pg_temp.stock('pillow');
  e := pg_temp.err(format('select pg_temp.settle(%L, 50, gen_random_uuid(), pg_temp.take(''pillow'', 3))', inv));
  perform pg_temp.check(e like 'Only 2 of "H399 Pillow" is still to collect%' and pg_temp.pays(inv) = 0
      and pg_temp.moves(inv) = 0 and pg_temp.stock('pillow') = p0 and pg_temp.hrows(inv) = 0,
    '5a more than is still to collect is refused, and the payment with it');
  e := pg_temp.err(format('select pg_temp.settle(%L, 50, gen_random_uuid(), pg_temp.take(''band'', 1))', inv));
  perform pg_temp.check(e like '"H399 Band" is not on %' and pg_temp.pays(inv) = 0, '5b a product not on the invoice is refused');
  foreach stmt in array array[
      '{"none": true, "items": [{"product_id": "%s", "qty": 1}]}', '{"items": []}', '{}', '{"none": false}',
      '{"items": [{"product_id": "%s", "qty": 0}]}', '{"items": [{"product_id": "%s", "qty": 1.5}]}',
      '{"items": [{"product_id": "%s", "qty": "1"}]}', '{"items": [{"product_id": "not-a-product", "qty": 1}]}',
      '{"none": "yes"}', '[]', '"none"'] loop
    e := pg_temp.err(format('select pg_temp.settle(%L, 50, gen_random_uuid(), %L::jsonb)', inv,
                            replace(stmt, '%s', pg_temp.fx('pillow')::text)));
    if e is null then ok := false; raise notice 'accepted: %', stmt; end if;
  end loop;
  perform pg_temp.check(ok and pg_temp.pays(inv) = 0 and pg_temp.moves(inv) = 0 and pg_temp.hrows(inv) = 0,
    '5c malformed answers (both, neither, an empty list, 0, 1.5, a text quantity, no product, not an object) are refused');
  -- A short store: 1 unit on the shelf.
  inv_s := pg_temp.mk(jsonb_build_array(pg_temp.line('scarce', 2)));
  perform pg_temp.as_user('s');
  sc0 := pg_temp.stock('scarce');
  e := pg_temp.err(format('select pg_temp.settle(%L, 50, gen_random_uuid(), pg_temp.take(''scarce'', 2))', inv_s));
  perform pg_temp.check(e like 'Not enough stock at H399 Store A % for "H399 Scarce": handing over 2, the store has 1'
      and pg_temp.pays(inv_s) = 0 and pg_temp.moves(inv_s) = 0 and pg_temp.stock('scarce') = sc0,
    '5d a short store refuses the hand-over, and the payment with it (as a full payment is refused today)');
  e := pg_temp.err(format('select public.record_invoice_handover(%L, pg_temp.take(''scarce'', 1), null)', inv_s));
  perform pg_temp.check(e like '%request ID is required%', '5e a request id is required');
end $$;

-- ===== 6. Hand over items (no payment) =====
do $$
declare inv uuid; inv_paid uuid; res jsonb; e text; p0 int;
begin
  inv := pg_temp.mk(jsonb_build_array(pg_temp.line('pillow', 2), pg_temp.line('socks', 1)));
  insert into fx values ('inv6', inv);
  perform pg_temp.as_user('s');
  p0 := pg_temp.stock('pillow');
  res := public.record_invoice_handover(inv, pg_temp.take('pillow', 1), gen_random_uuid());
  perform pg_temp.check((select status::text from public.invoices where id = inv) = 'unpaid' and pg_temp.pays(inv) = 0
      and pg_temp.stock('pillow') = p0 - 1 and pg_temp.sold(inv, 'pillow') = 1
      and (select source from public.invoice_handovers where id = (res->>'handover_id')::uuid) = 'button',
    '6a staff hand over a pillow on an unpaid invoice with no payment: it leaves the shelf, recorded as from the button');
  perform pg_temp.as_user('s');
  perform public.record_invoice_settlement(inv, jsonb_build_object('receipts', jsonb_build_array(jsonb_build_object(
    'key', 'line-0', 'payment_method_id', pg_temp.fx('cash'), 'amount', 50)), 'arrangements', '[]'::jsonb), gen_random_uuid());
  res := public.record_invoice_handover(inv, pg_temp.take('pillow', 1, 'socks', 1), gen_random_uuid());
  perform pg_temp.check(pg_temp.sold(inv, 'pillow') = 2 and pg_temp.sold(inv, 'socks') = 1
      and pg_temp.todo(inv, 'pillow') = 0 and pg_temp.todo(inv, 'socks') = 0,
    '6b and later, on the part-paid invoice, the rest');
  e := pg_temp.err(format('select public.record_invoice_handover(%L, pg_temp.take(''pillow'', 1), gen_random_uuid())', inv));
  perform pg_temp.check(e like 'Only 0 of "H399 Pillow"%', '6c nothing more than the invoice holds');
  perform pg_temp.as_user('sb');
  e := pg_temp.err(format('select public.record_invoice_handover(%L, pg_temp.take(''pillow'', 1), gen_random_uuid())', pg_temp.fx('inv2')));
  perform pg_temp.check(e = 'No access to this invoice', '6d staff of another store are refused');
  perform pg_temp.as_user('sx');
  e := pg_temp.err(format('select public.record_invoice_handover(%L, pg_temp.take(''pillow'', 1), gen_random_uuid())', pg_temp.fx('inv2')));
  perform pg_temp.check(e like 'Only an active user%', '6e a deactivated user is refused');
  perform pg_temp.as_user('s');
  e := pg_temp.err(format('select public.record_invoice_handover(%L, ''{"none": true}''::jsonb, gen_random_uuid())', pg_temp.fx('inv2')));
  perform pg_temp.check(e like 'Hand over items records the goods%', '6f "Nothing taken" is no hand-over for the button');
  inv_paid := pg_temp.mk(jsonb_build_array(pg_temp.line('band', 1)));
  perform pg_temp.settle(inv_paid, 100, gen_random_uuid());
  e := pg_temp.err(format('select public.record_invoice_handover(%L, pg_temp.take(''band'', 1), gen_random_uuid())', inv_paid));
  perform pg_temp.check(e like 'Goods are handed over this way only on an unpaid or part-paid invoice%paid)',
    '6g a paid invoice is refused (its goods left at payment)');
end $$;

-- ===== 7. Full payment takes only the rest =====
do $$
declare inv uuid := pg_temp.fx('inv2'); p0 int := pg_temp.stock('pillow'); s0 int := pg_temp.stock('socks'); n0 int;
  gap int; ensured int;
begin
  n0 := pg_temp.moves(inv);
  perform pg_temp.as_user('s');
  perform pg_temp.settle(inv, 350, gen_random_uuid());
  perform pg_temp.check((select status::text from public.invoices where id = inv) = 'paid', '7a the rest is paid: paid in full');
  perform pg_temp.check(pg_temp.stock('pillow') = p0 - 1 and pg_temp.stock('socks') = s0 - 1
      and pg_temp.sold(inv, 'pillow') = 2 and pg_temp.sold(inv, 'socks') = 3 and pg_temp.moves(inv) = n0 + 2,
    '7b full payment takes only what was not handed over (1 pillow, 1 sock), never the handed-over goods again');
  select count(*) into gap from public.invoice_stock_gaps((select invoice_no from public.invoices where id = inv));
  ensured := public.ensure_invoice_stock_deducted(inv, null);
  perform pg_temp.check(gap = 0 and ensured = 0 and pg_temp.moves(inv) = n0 + 2,
    '7c the guarantee finds nothing missing (no stock gap; ensure_invoice_stock_deducted deducts nothing)');
  perform pg_temp.check(not exists (select 1 from public.invoice_required_stock(inv) r
       where r.kind = 'product' and (r.quantity - public.invoice_product_net_deducted(inv, r.item_id) <> 0
             or exists (select 1 from public.invoice_stock_to_deduct(inv) t where t.item_id = r.item_id and t.quantity <> 0))),
    '7d the two "already deducted" figures agree: nothing to deduct and nothing missing');
  perform pg_temp.check(not exists (select 1 from public.invoice_goods_status(inv) s,
       jsonb_array_elements(s->'products') p where (p->>'to_collect')::int <> 0 or (p->>'collected')::int <> (p->>'required')::int),
    '7e the invoice shows everything collected');
end $$;

-- ===== 8. Promotions and picks =====
do $$
declare inv uuid; p_b int := pg_temp.stock('beads'); p_bo int := pg_temp.stock('bottle'); p_c int := pg_temp.stock('corset');
  p_pad int := pg_temp.stock('pad'); e text; st jsonb;
begin
  inv := pg_temp.mk(jsonb_build_array(
    jsonb_build_object('kind', 'promotion', 'promotion_id', pg_temp.fx('promo'), 'quantity', 1,
      'selections', jsonb_build_array(jsonb_build_object('group_id', pg_temp.fx('grp'),
        'options', jsonb_build_array(jsonb_build_object('product_id', pg_temp.fx('corset'), 'quantity', 1))))),
    pg_temp.line('beads', 1)));
  perform pg_temp.check(pg_temp.todo(inv, 'beads') = 3 and pg_temp.todo(inv, 'bottle') = 1 and pg_temp.todo(inv, 'corset') = 1
      and pg_temp.todo(inv, 'pad') = 0, '8a fixture: 3 beads (2 in the set, 1 on its own), a bottle and the picked corset to collect');
  perform pg_temp.as_user('s');
  perform pg_temp.settle(inv, 200, gen_random_uuid(), pg_temp.take('corset', 1, 'beads', 2));
  perform pg_temp.check(pg_temp.stock('corset') = p_c - 1 and pg_temp.stock('beads') = p_b - 2 and pg_temp.stock('bottle') = p_bo,
    '8b the pick and two of the beads are handed over with a part payment');
  e := pg_temp.err(format('select public.record_invoice_handover(%L, pg_temp.take(''pad'', 1), gen_random_uuid())', inv));
  perform pg_temp.check(e like '"H399 Pad" is not on %', '8c the option not picked is not on the invoice');
  st := public.invoice_goods_status(inv);
  perform pg_temp.check(exists (select 1 from jsonb_array_elements(st->'products') p where p->>'name' = 'H399 Beads'
        and (p->>'required')::int = 3 and (p->>'collected')::int = 2 and (p->>'to_collect')::int = 1
        and p->'via' ? (select name from public.promotions where id = pg_temp.fx('promo')))
      and exists (select 1 from jsonb_array_elements(st->'products') p where p->>'name' = 'H399 Corset'
        and (p->>'to_collect')::int = 0 and (p->>'collected')::int = 1),
    '8d the status counts the set''s contents and picks with the product line, and names the set they come through');
  perform pg_temp.settle(inv, 400, gen_random_uuid());
  perform pg_temp.check(pg_temp.stock('beads') = p_b - 3 and pg_temp.stock('bottle') = p_bo - 1
      and pg_temp.stock('corset') = p_c - 1 and pg_temp.stock('pad') = p_pad
      and (select count(*) from public.invoice_stock_gaps((select invoice_no from public.invoices where id = inv))) = 0,
    '8e full payment takes the rest of the set (1 bead, the bottle), the pick never twice; no gap');
end $$;

-- ===== 9. Cancellation and refund with goods out =====
do $$
declare inv uuid; inv2 uuid; p0 int; s0 int; plan jsonb; req jsonb; res jsonb; stock jsonb;
begin
  -- An Owner's cancellation puts what is out back on the shelf (restore_invoice_stock).
  p0 := pg_temp.stock('pillow');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.line('pillow', 2)));
  perform pg_temp.as_user('s');
  perform pg_temp.settle(inv, 50, gen_random_uuid(), pg_temp.take('pillow', 2));
  perform pg_temp.as_user('o');
  perform public.cancel_invoice_recorded(inv, 'Customer changed her mind', gen_random_uuid());
  perform pg_temp.check((select status::text from public.invoices where id = inv) = 'cancelled'
      and pg_temp.stock('pillow') = p0 and pg_temp.sold(inv, 'pillow') = 0 and pg_temp.out_qty(inv, 'pillow') = 0,
    '9a cancelling a part-paid invoice puts the handed-over pillows back on the shelf');
  -- The guided cancellation asks what came back: one good, one damaged.
  p0 := pg_temp.stock('pillow');
  inv2 := pg_temp.mk(jsonb_build_array(pg_temp.line('pillow', 2)));
  perform pg_temp.as_user('s');
  perform pg_temp.settle(inv2, 50, gen_random_uuid(), pg_temp.take('pillow', 2));
  perform pg_temp.as_user('o');
  plan := public.invoice_action_plan(inv2, 'cancel');
  perform pg_temp.check(jsonb_array_length(plan->'stock') = 1
      and (plan->'stock'->0->>'movement_id')::uuid = (select movement_id from public.invoice_handover_lines where invoice_id = inv2),
    '9b the guided cancellation lists the hand-over for Good / Damaged / Not returned');
  select jsonb_agg(jsonb_build_object('movement_id', s->>'movement_id', 'sellable_quantity', 1, 'damaged_quantity', 1,
           'not_returned_quantity', 0)) into stock from jsonb_array_elements(plan->'stock') s;
  req := public.request_invoice_action_v2(inv2, 'cancel', '[]'::jsonb, 'Customer changed her mind', null, gen_random_uuid());
  res := public.resolve_invoice_action_v2((req->>'request_id')::uuid, true, 'ok', null, '[]'::jsonb, stock, false);
  perform pg_temp.check(res->>'status' = 'approved' and (select status::text from public.invoices where id = inv2) = 'cancelled'
      and pg_temp.stock('pillow') = p0 - 1 and pg_temp.out_qty(inv2, 'pillow') = 0,
    '9c approved: the good pillow goes back, the damaged one is written off, nothing is left out');
  -- A refund of the part payment with a goods line asks for the goods as well.
  p0 := pg_temp.stock('socks');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.line('socks', 1)));
  perform pg_temp.as_user('s');
  perform pg_temp.settle(inv, 60, gen_random_uuid(), pg_temp.take('socks', 1));
  perform pg_temp.as_user('o');
  plan := public.invoice_action_plan(inv, 'refund_full');
  perform pg_temp.check(jsonb_array_length(coalesce(plan->'stock', '[]'::jsonb)) = 1,
    '9d the refund plan of a part-paid invoice lists the handed-over sock');
  select jsonb_agg(jsonb_build_object('movement_id', s->>'movement_id', 'sellable_quantity', 1, 'damaged_quantity', 0,
           'not_returned_quantity', 0)) into stock from jsonb_array_elements(plan->'stock') s;
  req := public.request_invoice_action_v2(inv, 'refund_full', '[]'::jsonb, 'Refund the deposit', null, gen_random_uuid());
  res := public.resolve_invoice_action_v2((req->>'request_id')::uuid, true, 'ok', null, '[]'::jsonb, stock, true);
  perform pg_temp.check(res->>'status' = 'approved' and pg_temp.stock('socks') = p0 and pg_temp.out_qty(inv, 'socks') = 0,
    '9e approved: the money goes back and the sock with it');
end $$;

-- ===== 10. Corrections =====
do $$
declare inv uuid; e text; p0 int; s0 int; n0 int; rv int;
begin
  -- Pillow x2 and socks x2 (400); 150 paid; one pillow handed over.
  inv := pg_temp.mk(jsonb_build_array(pg_temp.line('pillow', 2), pg_temp.line('socks', 2)));
  insert into fx values ('inv10', inv);
  perform pg_temp.as_user('s');
  perform pg_temp.settle(inv, 150, gen_random_uuid(), pg_temp.take('pillow', 1));
  p0 := pg_temp.stock('pillow'); s0 := pg_temp.stock('socks'); n0 := pg_temp.moves(inv);
  rv := (select count(*) from public.invoice_revisions where invoice_id = inv);
  perform pg_temp.as_user('o');
  e := pg_temp.correct(inv, pg_temp.lines_with(inv, 'pillow', 0));
  perform pg_temp.check(e like 'GOODS_HANDED_OVER: This correction takes off goods the customer already took: "H399 Pillow" (1 with the customer, the corrected invoice keeps 0)%Record items returned%'
      and pg_temp.moves(inv) = n0 and pg_temp.stock('pillow') = p0
      and (select count(*) from public.invoice_revisions where invoice_id = inv) = rv
      and (select count(*) from public.invoice_items where invoice_id = inv) = 2,
    '10a removing the handed-over pillow is refused, clearly, and nothing changes');
  e := pg_temp.correct(inv, pg_temp.lines_with(inv, 'pillow', 1));
  perform pg_temp.check(e is null, '10b reducing the pillows to the 1 handed over is allowed (the handed-over one stays on the invoice)');
  perform pg_temp.check(pg_temp.moves(inv) = n0 and pg_temp.stock('pillow') = p0 and pg_temp.stock('socks') = s0
      and pg_temp.out_qty(inv, 'pillow') = 1 and (select status::text from public.invoices where id = inv) = 'partially_paid',
    '10c and it moves no stock: nothing back on the shelf, nothing taken for the unpaid rest');
  perform pg_temp.as_user('s');
  e := pg_temp.correct(inv, pg_temp.lines_with(inv, 'socks', 3));
  perform pg_temp.check(e is null and pg_temp.moves(inv) = n0 and pg_temp.stock('pillow') = p0 and pg_temp.stock('socks') = s0
      and pg_temp.out_qty(inv, 'pillow') = 1 and pg_temp.todo(inv, 'socks') = 3,
    '10d staff correcting another line (3 socks) keep the handed-over pillow out; no stock moves');
  perform pg_temp.as_user('o');
  e := pg_temp.correct(inv, pg_temp.lines(inv), jsonb_build_object('store_id', pg_temp.fx('B')));
  perform pg_temp.check(e like 'GOODS_HANDED_OVER: Goods on this invoice were handed over from its store%',
    '10e moving the invoice to another store is refused while goods are out');
  -- Record items returned, then the correction goes through.
  perform public.record_invoice_goods_return(inv, jsonb_build_array(jsonb_build_object('product_id', pg_temp.fx('pillow'), 'good', 1)),
    'Brought back unused', gen_random_uuid());
  perform pg_temp.check(pg_temp.stock('pillow') = p0 + 1 and pg_temp.out_qty(inv, 'pillow') = 0
      and exists (select 1 from public.stock_movements x where x.invoice_id = inv and x.movement_type::text = 'invoice_cancel_return'
        and x.reversed_sale_id = (select l.movement_id from public.invoice_handover_lines l where l.invoice_id = inv)
        and x.to_store_id = pg_temp.fx('A') and x.quantity = 1),
    '10f Record items returned (Good) puts the pillow back on the shelf with an invoice_cancel_return pointing at the hand-over');
  n0 := pg_temp.moves(inv);
  e := pg_temp.correct(inv, pg_temp.lines_with(inv, 'pillow', 0));
  perform pg_temp.check(e is null and pg_temp.moves(inv) = n0 and pg_temp.stock('pillow') = p0 + 1
      and pg_temp.stock('socks') = s0 and pg_temp.sold(inv, 'socks') = 0 and pg_temp.todo(inv, 'socks') = 3
      and not exists (select 1 from public.invoice_items where invoice_id = inv and product_id = pg_temp.fx('pillow')),
    '10g after it the pillow line can be removed, and no stock moves: the part-paid invoice''s socks are not taken (before 399 a correction of an invoice with any store_sale took every line, paid or not)'
      || coalesce(' (refused: ' || e || ')', ''));
end $$;
do $$
declare inv uuid; e text; p0 int; s0 int; n0 int;
begin
  -- A correction that leaves the invoice paid takes the rest, net.
  inv := pg_temp.mk(jsonb_build_array(pg_temp.line('pillow', 2), pg_temp.line('socks', 1)));
  perform pg_temp.as_user('s');
  perform pg_temp.settle(inv, 250, gen_random_uuid(), pg_temp.take('pillow', 1));
  p0 := pg_temp.stock('pillow'); s0 := pg_temp.stock('socks'); n0 := pg_temp.moves(inv);
  perform pg_temp.as_user('o');
  e := pg_temp.correct(inv, pg_temp.lines_with(inv, 'socks', 0));
  perform pg_temp.check(e is null and (select status::text from public.invoices where id = inv) = 'paid'
      and pg_temp.stock('pillow') = p0 - 1 and pg_temp.stock('socks') = s0 and pg_temp.sold(inv, 'pillow') = 2
      and pg_temp.moves(inv) = n0 + 1
      and (select count(*) from public.invoice_stock_gaps((select invoice_no from public.invoices where id = inv))) = 0,
    '10h a correction that leaves the invoice paid takes only the pillow not handed over; nothing goes back on the shelf; no gap');
  -- A paid invoice's correction is as before: the difference.
  p0 := pg_temp.stock('pillow');
  e := pg_temp.correct(inv, pg_temp.lines_with(inv, 'pillow', 1));
  perform pg_temp.check(e is null and pg_temp.stock('pillow') = p0 + 1 and pg_temp.sold(inv, 'pillow') = 1,
    '10i correcting a paid invoice still nets to the difference (one pillow back)');
  -- Paid in full, then corrected up to part-paid: its goods left at that
  -- payment, and the added ones still leave at once, as before 399.
  p0 := pg_temp.stock('pillow');
  e := pg_temp.correct(inv, pg_temp.lines_with(inv, 'pillow', 3));
  perform pg_temp.check(e is null and (select status::text from public.invoices where id = inv) = 'partially_paid'
      and pg_temp.stock('pillow') = p0 - 2 and pg_temp.sold(inv, 'pillow') = 3
      and not public.invoice_before_full_payment(inv)
      and not (public.invoice_goods_status(inv)->>'open')::boolean
      and not (public.invoice_goods_status(inv)->>'can_hand_over')::boolean,
    '10j a paid invoice corrected up to part-paid takes the added pillows at once, as before; it is not "before full payment"');
  e := pg_temp.err(format('select public.record_invoice_goods_return(%L, ''[{"product_id": "%s", "good": 1}]''::jsonb, ''Back'', gen_random_uuid())',
                          inv, pg_temp.fx('pillow')));
  perform pg_temp.check(e like 'Items returned are recorded here only on an unpaid or part-paid invoice not yet paid in full%',
    '10k and its goods come back through Refund / Cancel, not Record items returned');
end $$;

-- ===== 11. Record items returned =====
do $$
declare inv uuid; e text; p0 int; req uuid := gen_random_uuid(); res jsonb; n0 int; d0 int;
begin
  inv := pg_temp.mk(jsonb_build_array(pg_temp.line('pillow', 3)));
  perform pg_temp.as_user('s');
  perform pg_temp.settle(inv, 100, gen_random_uuid(), pg_temp.take('pillow', 2));
  perform public.record_invoice_handover(inv, pg_temp.take('pillow', 1), gen_random_uuid());
  e := pg_temp.err(format('select public.record_invoice_goods_return(%L, ''[{"product_id": "%s", "good": 1}]''::jsonb, ''Back'', gen_random_uuid())',
                          inv, pg_temp.fx('pillow')));
  perform pg_temp.check(e like 'Only an Owner or Manager can record items returned', '11a staff may not record items returned');
  perform pg_temp.as_user('m');
  e := pg_temp.err(format('select public.record_invoice_goods_return(%L, ''[{"product_id": "%s", "good": 1}]''::jsonb, '' '', gen_random_uuid())',
                          inv, pg_temp.fx('pillow')));
  perform pg_temp.check(e = 'Give the reason the goods came back', '11b a reason is required');
  e := pg_temp.err(format('select public.record_invoice_goods_return(%L, ''[{"product_id": "%s", "good": 2, "damaged": 2}]''::jsonb, ''Back'', gen_random_uuid())',
                          inv, pg_temp.fx('pillow')));
  perform pg_temp.check(e like 'Only 3 of "H399 Pillow" is out with the customer%', '11c no more than is out');
  p0 := pg_temp.stock('pillow'); n0 := pg_temp.moves(inv);
  d0 := (select count(*) from public.invoice_stock_dispositions where invoice_id = inv);
  res := public.record_invoice_goods_return(inv, jsonb_build_array(jsonb_build_object('product_id', pg_temp.fx('pillow'),
           'good', 1, 'damaged', 1, 'not_returned', 1)), 'Torn in the bag', req);
  perform pg_temp.check(pg_temp.stock('pillow') = p0 + 1 and pg_temp.moves(inv) = n0 + 1
      and (select count(*) from public.invoice_stock_dispositions where invoice_id = inv) = d0 + 2
      and (select sum(damaged_quantity) from public.invoice_stock_dispositions where invoice_id = inv) = 1
      and (select sum(not_returned_quantity) from public.invoice_stock_dispositions where invoice_id = inv) = 1
      and pg_temp.out_qty(inv, 'pillow') = 0,
    '11d the Manager records 1 good (back on the shelf), 1 damaged and 1 not returned (written off through the dispositions), oldest hand-over first');
  perform pg_temp.check((select count(*) from public.invoice_handover_return_lines where invoice_id = inv) = 2
      and exists (select 1 from public.audit_logs a where a.record_id = inv and a.action = 'invoice_goods_returned' and a.reason = 'Torn in the bag')
      and (select kind from public.invoice_handovers where request_id = req) = 'return',
    '11e recorded per hand-over movement, with the reason, and audited');
  perform pg_temp.check(pg_temp.todo(inv, 'pillow') = 2,
    '11f still to collect: the good one and the damaged one (the customer keeps the one not returned)');
  n0 := pg_temp.moves(inv); p0 := pg_temp.stock('pillow');
  res := public.record_invoice_goods_return(inv, jsonb_build_array(jsonb_build_object('product_id', pg_temp.fx('pillow'),
           'good', 1, 'damaged', 1, 'not_returned', 1)), 'Torn in the bag', req);
  perform pg_temp.check((res->>'replayed')::boolean and pg_temp.moves(inv) = n0 and pg_temp.stock('pillow') = p0,
    '11g retried, it writes nothing again');
  e := pg_temp.err(format('select public.record_invoice_goods_return(%L, ''[{"product_id": "%s", "good": 1}]''::jsonb, ''Other'', %L)',
                          inv, pg_temp.fx('pillow'), req));
  perform pg_temp.check(e like '%already used for something else%', '11h a different answer under the same request is refused');
  e := pg_temp.err(format('select public.record_invoice_goods_return(%L, ''[{"product_id": "%s", "good": 1}]''::jsonb, ''Back'', gen_random_uuid())',
                          pg_temp.fx('inv2'), pg_temp.fx('pillow')));
  perform pg_temp.check(e like 'Items returned are recorded here only on an unpaid or part-paid invoice not yet paid in full%Refund / Cancel%',
    '11i a paid invoice''s goods come back through Refund / Cancel');
end $$;

-- ===== 12. Make FOC =====
do $$
declare inv uuid; it uuid; p0 int; res jsonb; n_foc int;
begin
  inv := pg_temp.mk(jsonb_build_array(pg_temp.line('pillow', 2)));
  select id into it from public.invoice_items where invoice_id = inv;
  perform public.apply_line_foc(it, 2, null, 'Goodwill for a long-standing customer');
  perform pg_temp.as_user('s');
  p0 := pg_temp.stock('pillow');
  perform public.record_invoice_handover(inv, pg_temp.take('pillow', 1), gen_random_uuid());
  perform pg_temp.as_user('o');
  res := public.confirm_foc_invoice(inv, null);
  select count(*) into n_foc from public.stock_movements where invoice_id = inv and notes like 'FOC — %';
  perform pg_temp.check(res->>'status' = 'completed_foc' and pg_temp.stock('pillow') = p0 - 2 and pg_temp.sold(inv, 'pillow') = 2
      and n_foc = 1 and (select quantity from public.stock_movements where invoice_id = inv and notes like 'FOC — %') = 1
      and (select count(*) from public.invoice_stock_gaps((select invoice_no from public.invoices where id = inv))) = 0,
    '12a Confirm FOC takes only the pillow not handed over (2 in all, not 3); no gap');
  -- Handed over in full: Confirm FOC takes nothing more.
  inv := pg_temp.mk(jsonb_build_array(pg_temp.line('socks', 1)));
  select id into it from public.invoice_items where invoice_id = inv;
  perform public.apply_line_foc(it, 1, null, 'Goodwill');
  perform public.record_invoice_handover(inv, pg_temp.take('socks', 1), gen_random_uuid());
  p0 := pg_temp.stock('socks');
  res := public.confirm_foc_invoice(inv, null);
  perform pg_temp.check(res->>'status' = 'completed_foc' and pg_temp.stock('socks') = p0 and pg_temp.sold(inv, 'socks') = 1,
    '12b a FOC invoice handed over in full is confirmed with no second deduction');
end $$;

-- ===== 13. Delete =====
do $$
declare inv uuid; e text;
begin
  inv := pg_temp.mk(jsonb_build_array(pg_temp.line('band', 1)));
  perform pg_temp.as_user('s');
  perform public.record_invoice_handover(inv, pg_temp.take('band', 1), gen_random_uuid());
  e := pg_temp.err(format('select public.delete_invoice(%L)', inv));
  perform pg_temp.check(e like 'Goods on this invoice were handed over to the customer%'
      and (select deleted_at from public.invoices where id = inv) is null,
    '13a an unpaid invoice with goods out cannot be deleted');
  perform pg_temp.as_user('o');
  perform public.record_invoice_goods_return(inv, jsonb_build_array(jsonb_build_object('product_id', pg_temp.fx('band'), 'good', 1)),
    'Returned', gen_random_uuid());
  perform pg_temp.as_user('s');
  e := pg_temp.err(format('select public.delete_invoice(%L)', inv));
  perform pg_temp.check(e is null and (select deleted_at from public.invoices where id = inv) is not null,
    '13b once the goods are recorded as returned it can be');
end $$;

-- ===== 14. Fulfil from a warehouse =====
do $$
declare inv uuid; inv2 uuid; e text; w0 int; p0 int;
begin
  inv := pg_temp.mk(jsonb_build_array(pg_temp.line('pillow', 2)));
  perform pg_temp.as_user('o');
  perform public.set_invoice_fulfilment_warehouse(inv, pg_temp.fx('wh'));
  perform pg_temp.as_user('s');
  e := pg_temp.err(format('select pg_temp.settle(%L, 50, gen_random_uuid(), pg_temp.take(''pillow'', 1))', inv));
  perform pg_temp.check(e like '% is set to fulfil from a warehouse%' and pg_temp.pays(inv) = 0 and pg_temp.moves(inv) = 0,
    '14a a hand-over on an invoice fulfilled from a warehouse is refused');
  perform pg_temp.settle(inv, 50, gen_random_uuid(), '{"none": true}'::jsonb);
  perform pg_temp.check(pg_temp.pays(inv) = 1 and pg_temp.moves(inv) = 0, '14b "Nothing taken" is still recorded with its payment');
  inv2 := pg_temp.mk(jsonb_build_array(pg_temp.line('pillow', 2)));
  perform pg_temp.as_user('s');
  perform public.record_invoice_handover(inv2, pg_temp.take('pillow', 1), gen_random_uuid());
  perform pg_temp.as_user('o');
  e := pg_temp.err(format('select public.set_invoice_fulfilment_warehouse(%L, %L)', inv2, pg_temp.fx('wh')));
  perform pg_temp.check(e like 'Goods on this invoice already left this store with the customer%Keep this store''s stock.'
      and (select fulfil_warehouse_id from public.invoices where id = inv2) is null,
    '14c a warehouse cannot be chosen once goods were handed over from the store');
  perform pg_temp.check(pg_temp.err(format('select public.set_invoice_fulfilment_warehouse(%L, null)', inv2)) is null,
    '14d choosing the store''s own stock is always allowed');
  -- The backstop: the column set behind the setter's back.
  update public.invoices set fulfil_warehouse_id = pg_temp.fx('wh') where id = inv2;
  w0 := (select current_qty from public.warehouse_inventory where warehouse_id = pg_temp.fx('wh') and product_id = pg_temp.fx('pillow'));
  p0 := pg_temp.stock('pillow');
  e := pg_temp.err(format('select pg_temp.settle(%L, 200, gen_random_uuid())', inv2));
  perform pg_temp.check(e like 'Goods on % were handed over from the store before it was paid in full%'
      and (select status::text from public.invoices where id = inv2) = 'unpaid' and pg_temp.stock('pillow') = p0
      and (select current_qty from public.warehouse_inventory where warehouse_id = pg_temp.fx('wh') and product_id = pg_temp.fx('pillow')) = w0,
    '14e paying it in full from a warehouse is refused rather than counted twice');
  update public.invoices set fulfil_warehouse_id = null where id = inv2;
  -- Fulfilment from a warehouse with nothing handed over is as before.
  w0 := (select current_qty from public.warehouse_inventory where warehouse_id = pg_temp.fx('wh') and product_id = pg_temp.fx('pillow'));
  p0 := pg_temp.stock('pillow');
  perform pg_temp.as_user('s');
  perform pg_temp.settle(inv, 150, gen_random_uuid());
  perform pg_temp.check((select status::text from public.invoices where id = inv) = 'paid' and pg_temp.stock('pillow') = p0
      and (select current_qty from public.warehouse_inventory where warehouse_id = pg_temp.fx('wh') and product_id = pg_temp.fx('pillow')) = w0 - 2,
    '14f an invoice fulfilled from a warehouse with nothing handed over settles from the warehouse as before');
end $$;
do $$
declare inv uuid; e text; w0 int; p0 int;
begin
  -- 2 socks; 1 handed over with a part payment, then recorded as Not returned
  -- (the customer kept it: it counts as collected).
  inv := pg_temp.mk(jsonb_build_array(pg_temp.line('socks', 2)));
  perform pg_temp.as_user('s');
  perform pg_temp.settle(inv, 50, gen_random_uuid(), pg_temp.take('socks', 1));
  perform pg_temp.as_user('m');
  perform public.record_invoice_goods_return(inv, jsonb_build_array(jsonb_build_object('product_id', pg_temp.fx('socks'),
    'not_returned', 1)), 'Customer kept it', gen_random_uuid());
  perform pg_temp.check(pg_temp.out_qty(inv, 'socks') = 0 and pg_temp.todo(inv, 'socks') = 1,
    '14g fixture: the sock kept is no longer out, and counts as collected (1 still to collect)');
  perform pg_temp.as_user('o');
  e := pg_temp.err(format('select public.set_invoice_fulfilment_warehouse(%L, %L)', inv, pg_temp.fx('wh')));
  perform pg_temp.check(e like 'Goods on this invoice already left this store with the customer%'
      and (select fulfil_warehouse_id from public.invoices where id = inv) is null,
    '14h a warehouse cannot be chosen while the customer keeps a handed-over sock (Not returned): it would send both');
  -- The backstop, with the column set behind the setter's back.
  update public.invoices set fulfil_warehouse_id = pg_temp.fx('wh') where id = inv;
  w0 := (select current_qty from public.warehouse_inventory where warehouse_id = pg_temp.fx('wh') and product_id = pg_temp.fx('socks'));
  p0 := pg_temp.stock('socks');
  perform pg_temp.as_user('s');
  e := pg_temp.err(format('select pg_temp.settle(%L, 150, gen_random_uuid())', inv));
  perform pg_temp.check(e like 'Goods on % were handed over from the store before it was paid in full%'
      and (select status::text from public.invoices where id = inv) = 'partially_paid' and pg_temp.stock('socks') = p0
      and (select current_qty from public.warehouse_inventory where warehouse_id = pg_temp.fx('wh') and product_id = pg_temp.fx('socks')) = w0,
    '14i and paying it in full from a warehouse is refused rather than counted twice');
  update public.invoices set fulfil_warehouse_id = null where id = inv;
  -- 2 pillows; 1 handed over, then back Damaged (written off): the warehouse
  -- may send both, and the store keeps only the write-off.
  inv := pg_temp.mk(jsonb_build_array(pg_temp.line('pillow', 2)));
  p0 := pg_temp.stock('pillow');
  w0 := (select current_qty from public.warehouse_inventory where warehouse_id = pg_temp.fx('wh') and product_id = pg_temp.fx('pillow'));
  perform pg_temp.as_user('s');
  perform pg_temp.settle(inv, 50, gen_random_uuid(), pg_temp.take('pillow', 1));
  perform pg_temp.as_user('m');
  perform public.record_invoice_goods_return(inv, jsonb_build_array(jsonb_build_object('product_id', pg_temp.fx('pillow'),
    'damaged', 1)), 'Torn', gen_random_uuid());
  perform pg_temp.as_user('o');
  e := pg_temp.err(format('select public.set_invoice_fulfilment_warehouse(%L, %L)', inv, pg_temp.fx('wh')));
  perform pg_temp.as_user('s');
  perform pg_temp.settle(inv, 150, gen_random_uuid());
  perform pg_temp.check(e is null and (select status::text from public.invoices where id = inv) = 'paid'
      and pg_temp.stock('pillow') = p0 - 1
      and (select current_qty from public.warehouse_inventory where warehouse_id = pg_temp.fx('wh') and product_id = pg_temp.fx('pillow')) = w0 - 2
      and (select count(*) from public.invoice_stock_gaps((select invoice_no from public.invoices where id = inv))) = 0,
    '14j after a Damaged return the warehouse may be chosen: it sends both pillows, the store is down only the damaged one; no gap'
      || coalesce(' (refused: ' || e || ')', ''));
end $$;

-- ===== 15. Callers without the key =====
do $$
declare inv uuid; res jsonb; p0 int := pg_temp.stock('pillow'); n0 int;
begin
  inv := pg_temp.mk(jsonb_build_array(pg_temp.line('pillow', 2)));
  perform pg_temp.as_user('s');
  res := pg_temp.settle(inv, 50, gen_random_uuid());
  perform pg_temp.check(not (res ? 'handover') and pg_temp.moves(inv) = 0 and pg_temp.hrows(inv) = 0 and pg_temp.stock('pillow') = p0
      and (select status::text from public.invoices where id = inv) = 'partially_paid',
    '15a a settlement without the key (website orders, exchanges) is a part payment as before: no stock, no record');
  res := public.record_invoice_settlement(inv, jsonb_build_object('receipts', jsonb_build_array(jsonb_build_object('key', 'line-0',
    'payment_method_id', pg_temp.fx('cash'), 'amount', 10)), 'arrangements', '[]'::jsonb, 'handover', null), gen_random_uuid());
  perform pg_temp.check(not (res ? 'handover') and pg_temp.hrows(inv) = 0, '15b a null hand-over key is no answer');
  perform public.record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.fx('cash'), 'amount', 20)),
    gen_random_uuid());
  perform pg_temp.check(pg_temp.moves(inv) = 0 and pg_temp.pays(inv) = 3, '15c record_invoice_payment (website orders) as before');
  perform public.invoice_record_payments_internal(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.fx('cash'), 'amount', 120)));
  perform pg_temp.check((select status::text from public.invoices where id = inv) = 'paid' and pg_temp.stock('pillow') = p0 - 2
      and pg_temp.sold(inv, 'pillow') = 2, '15d the internal payment path settles and takes the stock as before');
  -- A full payment carrying an answer: every item leaves with the payment, once.
  inv := pg_temp.mk(jsonb_build_array(pg_temp.line('socks', 2)));
  p0 := pg_temp.stock('socks');
  perform pg_temp.as_user('s');
  res := pg_temp.settle(inv, 200, gen_random_uuid(), pg_temp.take('socks', 1));
  perform pg_temp.check(res->'handover'->>'skipped' = 'paid_in_full' and pg_temp.stock('socks') = p0 - 2
      and pg_temp.sold(inv, 'socks') = 2 and pg_temp.hrows(inv) = 0,
    '15e a payment that settles in full skips the answer: the payment took every item, once');
end $$;

-- ===== 16. What the page reads =====
do $$
declare st jsonb; ids uuid[]; e text; inv uuid := pg_temp.fx('inv10');
begin
  perform pg_temp.as_user('s');
  st := public.invoice_goods_status(pg_temp.fx('inv6'));
  perform pg_temp.check((st->>'to_collect_total')::int = 0 and (st->>'collected_total')::int = 3 and (st->>'out_total')::int = 3
      and not (st->>'can_hand_over')::boolean and not (st->>'can_record_return')::boolean
      and jsonb_array_length(st->'history') = 2 and st->'history'->0->>'created_by_name' = 'H399 Staff'
      and st->'history'->0->'items'->0->>'name' = 'H399 Pillow',
    '16a invoice_goods_status: totals, history with who and what; staff cannot record returns');
  perform pg_temp.as_user('o');
  st := public.invoice_goods_status(inv);
  perform pg_temp.check((st->>'can_hand_over')::boolean and exists (select 1 from jsonb_array_elements(st->'history') h
      where h->>'kind' = 'return' and h->'items'->0->>'good' = '1'),
    '16b and an invoice with goods still to collect may be handed over; a return shows good / damaged / not returned');
  ids := array[pg_temp.fx('inv6'), pg_temp.fx('inv2'), inv];
  perform pg_temp.as_user('s');
  perform pg_temp.check((select array_agg(invoice_id) from public.invoice_list_goods_out(ids)) = array[pg_temp.fx('inv6')]
      and (select quantity from public.invoice_list_goods_out(ids)) = 3,
    '16c the list''s "Goods out": the part-paid invoice with goods out, not the paid one nor one with nothing out');
  perform pg_temp.as_user('sb');
  e := pg_temp.err(format('select public.invoice_goods_status(%L)', pg_temp.fx('inv6')));
  perform pg_temp.check(e = 'No access to this invoice' and not exists (select 1 from public.invoice_list_goods_out(ids)),
    '16d staff of another store see neither');
end $$;
do $$
declare inv uuid; st jsonb; mv uuid;
begin
  -- Cancelled after a hand-over (the pillow back on the shelf): nothing to collect.
  inv := pg_temp.mk(jsonb_build_array(pg_temp.line('pillow', 2)));
  perform pg_temp.as_user('s');
  perform pg_temp.settle(inv, 50, gen_random_uuid(), pg_temp.take('pillow', 1));
  perform pg_temp.as_user('o');
  perform public.cancel_invoice_recorded(inv, 'Customer changed her mind', gen_random_uuid());
  st := public.invoice_goods_status(inv);
  perform pg_temp.check(st->>'status' = 'cancelled' and not (st->>'open')::boolean and jsonb_array_length(st->'history') = 1
      and (st->>'to_collect_total')::int = 0 and (st->>'collected_total')::int = 0 and (st->>'out_total')::int = 0
      and not (st->>'can_hand_over')::boolean,
    '16e a cancelled invoice with a hand-over in its history shows nothing to collect and nothing collected');
  -- Paid after a hand-over, then one sock refunded back to the shelf.
  inv := pg_temp.mk(jsonb_build_array(pg_temp.line('socks', 2)));
  perform pg_temp.as_user('s');
  perform pg_temp.settle(inv, 50, gen_random_uuid(), pg_temp.take('socks', 1));
  perform pg_temp.settle(inv, 150, gen_random_uuid());
  perform pg_temp.as_user('o');
  select id into mv from public.stock_movements where invoice_id = inv and movement_type::text = 'store_sale'
   order by coalesce(stock_history_recorded_at, created_at), id limit 1;
  perform public.record_invoice_stock_return(inv, jsonb_build_array(jsonb_build_object('movement_id', mv, 'sellable_quantity', 1)),
    'Refunded one pair', gen_random_uuid());
  st := public.invoice_goods_status(inv);
  perform pg_temp.check(st->>'status' = 'paid' and not (st->>'open')::boolean
      and (st->>'to_collect_total')::int = 0 and (st->>'collected_total')::int = 1,
    '16f a paid invoice with one of two socks refunded back shows 1 collected and nothing to collect');
end $$;

-- ===== 17. Settled after a Damaged return, by every path =====
-- One bottle, S$100; S$40 paid with the bottle handed over; the Manager
-- records it back Damaged (written off), so the customer is owed a new one.
create function pg_temp.damaged_case(out inv uuid, out p0 int) language plpgsql as
$$begin
  inv := pg_temp.mk(jsonb_build_array(pg_temp.line('bottle', 1)));
  p0 := pg_temp.stock('bottle');
  perform pg_temp.as_user('s');
  perform pg_temp.settle(inv, 40, gen_random_uuid(), pg_temp.take('bottle', 1));
  perform pg_temp.as_user('m');
  perform public.record_invoice_goods_return(inv, jsonb_build_array(jsonb_build_object('product_id', pg_temp.fx('bottle'),
    'damaged', 1)), 'Cracked', gen_random_uuid());
end$$;
-- After settling: the replacement left the shelf (2 in all: the damaged one
-- and the new one), nothing is to collect or missing, and both figures agree.
create function pg_temp.settled_once(inv uuid, p0 int) returns boolean language sql as
$$ select (select status::text from public.invoices where id = inv) = 'paid'
      and pg_temp.stock('bottle') = p0 - 2 and pg_temp.todo(inv, 'bottle') = 0
      and public.invoice_product_net_deducted(inv, pg_temp.fx('bottle')) = 1
      and (select count(*) from public.invoice_stock_gaps((select invoice_no from public.invoices where id = inv))) = 0
      and public.ensure_invoice_stock_deducted(inv, null) = 0
      and (public.invoice_goods_status(inv)->>'to_collect_total')::int = 0 $$;
do $$
declare c record; pay uuid; e text;
begin
  select * into c from pg_temp.damaged_case();
  perform pg_temp.check(pg_temp.stock('bottle') = c.p0 - 1 and pg_temp.todo(c.inv, 'bottle') = 1
      and public.invoice_product_net_deducted(c.inv, pg_temp.fx('bottle')) = 0,
    '17a after the Damaged return, 1 bottle is still to collect, and the guarantee''s figure agrees (0 delivered)');
  perform pg_temp.as_user('s');
  perform pg_temp.settle(c.inv, 60, gen_random_uuid());
  perform pg_temp.check(pg_temp.settled_once(c.inv, c.p0), '17b settled by Record Payment: the new bottle leaves once; no gap');
  select * into c from pg_temp.damaged_case();
  select id into pay from public.invoice_payments where invoice_id = c.inv limit 1;
  perform pg_temp.as_user('o');
  perform public.correct_invoice_payment(pay, 100, (now() at time zone 'Asia/Singapore')::date, pg_temp.fx('cash'),
    'Keyed 40, was 100', gen_random_uuid());
  perform pg_temp.check(pg_temp.settled_once(c.inv, c.p0),
    '17c settled by Correct amount (no deduction runs): the guarantee takes the new bottle; no gap');
  select * into c from pg_temp.damaged_case();
  perform pg_temp.as_user('o');
  e := pg_temp.correct(c.inv, pg_temp.lines(c.inv), jsonb_build_object('manual_discount', 60, 'manual_discount_reason', 'Goodwill'));
  perform pg_temp.check(e is null and pg_temp.settled_once(c.inv, c.p0),
    '17d settled by a header-only correction (a manual discount): the guarantee takes the new bottle; no gap'
      || coalesce(' (refused: ' || e || ')', ''));
end $$;

do $$
declare v_n int; msgs text;
begin
  select count(*), string_agg(f.msg, E'\n' order by f.n) into v_n, msgs from failed f;
  if v_n > 0 then raise exception '399 hand-over: % check(s) failed:%', v_n, E'\n' || msgs; end if;
  raise notice '399 hand-over: every check passed';
end $$;
rollback;
