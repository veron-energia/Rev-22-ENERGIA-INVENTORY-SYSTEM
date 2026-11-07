-- 495: a service (a product typed No commission) holds no stock (the user, 6 Nov
-- 2026). supabase/495_services_hold_no_stock.sql.
--
-- Every step goes through the app's own calls: the invoice form
-- (create_invoice_with_details), the Pay dialog (record_invoice_settlement), Record
-- Payment, Confirm FOC, Hand over items, the Goods panel, the Finance panel's refund
-- by line, the guided Refund in full, Cancel, Reopen, the invoice form's correction,
-- Fulfil from, Stock In, Adjustments and Approvals, the Products page's Save.
--
--   R. Without 495 (skipped with -v skip_install=1): what was wrong.
--   I. Install: as tested, twice; a function not as tested stops it, changing nothing.
--   A-H, J, K. Selling, refunding, cancelling, correcting a service; old sales.
--   L, M. Stock cannot go up on a service, by any path; down and 0 are allowed.
--   N. A product becomes a service only with nothing standing in the way.
--   O, P. Controls: a product takes stock as before; commission as before.
--   Q. The made-up stock removed (scripts/products/remove-service-stock-495.sql).
--   U. The UNDO (scripts/products/undo-495.sql).
--
-- Run from the repository's root, on a copy of production at 494 (or with
-- -v skip_install=1 where 495 is in):
--   psql -X -v ON_ERROR_STOP=1 -d <copy> -f scripts/products/tests/service-no-stock-495.sql
-- Disposable database only; everything is rolled back. Every name and code is
-- invented (@example.invalid); the phones are fictional (+61 2 5550 nnnn).
\set ON_ERROR_STOP on
\set t495_mig `cat supabase/495_services_hold_no_stock.sql`
\set t495_undo `cat scripts/products/undo-495.sql`
\set t495_remove `cat scripts/products/remove-service-stock-495.sql`
begin;
set local lock_timeout = '10s';
set local statement_timeout = '600s';
select set_config('t495.mig', :'t495_mig', true), set_config('t495.undo', :'t495_undo', true),
       set_config('t495.remove', :'t495_remove', true) \g /dev/null
set local client_min_messages = warning;

create temp table t495(k text primary key, id uuid);
create temp table t495_res(n serial primary key, ok boolean, label text);
create temp sequence t495_phone;
create function pg_temp.id(p_k text) returns uuid language sql as $f$ select id from t495 where k = p_k $f$;
create function pg_temp.put(p_k text, p_id uuid) returns uuid language sql as $f$
  insert into t495 values (p_k, p_id) on conflict (k) do update set id = excluded.id returning id $f$;
create function pg_temp.ok(p_ok boolean, p_label text) returns void language plpgsql as $f$
begin
  insert into t495_res(ok, label) values (coalesce(p_ok, false), p_label);
  if not coalesce(p_ok, false) then raise warning 'FAIL %', p_label; end if;
end $f$;
-- Runs a statement; null when it passes, the refusal's words when it does not.
create function pg_temp.err(p_sql text) returns text language plpgsql as $f$
begin
  execute p_sql;
  return null;
exception when others then
  return sqlerrm;
end $f$;
create function pg_temp.as_owner() returns void language plpgsql as $f$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', pg_temp.id('own'), 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', pg_temp.id('own')::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
end $f$;
create function pg_temp.cust() returns uuid language plpgsql as $f$
declare c uuid;
begin
  insert into customers(full_name, phone) values ('T495 Buyer ' || nextval('t495_phone'), '+6125550' || lpad((1000 + currval('t495_phone'))::text, 4, '0'))
    returning id into c;
  return c;
end $f$;
-- The stock row's quantity, or null where the place has no row.
create function pg_temp.sq(p_store uuid, p_product uuid) returns int language sql as $f$
  select current_qty from store_inventory where store_id = p_store and product_id = p_product $f$;
create function pg_temp.wq(p_wh uuid, p_product uuid) returns int language sql as $f$
  select current_qty from warehouse_inventory where warehouse_id = p_wh and product_id = p_product $f$;
create function pg_temp.moves(p_product uuid) returns bigint language sql as $f$
  select count(*) from stock_movements where product_id = p_product $f$;
create function pg_temp.imoves(p_inv uuid, p_product uuid) returns bigint language sql as $f$
  select count(*) from stock_movements where invoice_id = p_inv and product_id = p_product $f$;
create function pg_temp.pline(p_product uuid, p_q int default 1) returns jsonb language sql as $f$
  select jsonb_build_object('kind', 'product', 'product_id', p_product, 'quantity', p_q) $f$;
-- The invoice form with these lines, in store p_store.
create function pg_temp.form(p_lines jsonb, p_store uuid default null) returns uuid language sql as $f$
  select create_invoice_with_details(coalesce(p_store, pg_temp.id('st')), pg_temp.cust(), p_lines, jsonb_build_object('business_date', sg_today()::text)) $f$;
-- The Pay dialog, of p_amount or of all of it.
create function pg_temp.pay(p_inv uuid, p_amount numeric default null) returns void language plpgsql as $f$
begin
  perform record_invoice_settlement(p_inv, jsonb_build_object('receipts', jsonb_build_array(jsonb_build_object(
    'key', 'line-0', 'payment_method_id', pg_temp.id('pm'),
    'amount', coalesce(p_amount, (select total_amount from invoices where id = p_inv)),
    'payment_date', sg_today()::text)), 'arrangements', '[]'::jsonb), gen_random_uuid());
end $f$;
create function pg_temp.sale(p_lines jsonb, p_first numeric default null, p_store uuid default null) returns uuid language plpgsql as $f$
declare inv uuid;
begin
  inv := pg_temp.form(p_lines, p_store);
  perform pg_temp.pay(inv, p_first);
  return inv;
end $f$;
-- Record Payment of what is outstanding.
create function pg_temp.settle(p_inv uuid) returns void language plpgsql as $f$
begin
  perform record_invoice_payment(p_inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.id('pm'),
    'amount', (invoice_financial_position(p_inv)->>'outstanding')::numeric)), gen_random_uuid());
end $f$;
create function pg_temp.line(p_inv uuid, p_product uuid) returns uuid language sql as $f$
  select id from invoice_items where invoice_id = p_inv and product_id = p_product limit 1 $f$;
-- The receipts that hold p_amount, as the Finance panel splits a refund.
create function pg_temp.sources(p_inv uuid, p_amount numeric) returns jsonb language plpgsql as $f$
declare src jsonb := '[]'; left_ numeric := p_amount; p record;
begin
  for p in select id, invoice_payment_remaining(id) as rem from invoice_payments
            where invoice_id = p_inv and entry_kind in ('receipt', 'correction_replacement') and invoice_payment_remaining(id) > 0
            order by created_at, id loop
    exit when left_ <= 0;
    src := src || jsonb_build_array(jsonb_build_object('payment_id', p.id, 'amount', least(p.rem, left_)));
    left_ := left_ - least(p.rem, left_);
  end loop;
  return src;
end $f$;
-- The Finance panel's refund by line, the stock quantities left blank as a person
-- may leave them (p_stock: [] is what the panel sends then).
create function pg_temp.refund_line(p_inv uuid, p_item uuid, p_amount numeric, p_stock jsonb default '[]') returns text language plpgsql as $f$
begin
  perform refund_invoice_recorded(p_inv, jsonb_build_array(jsonb_build_object('invoice_item_id', p_item, 'amount', p_amount)),
    pg_temp.sources(p_inv, p_amount), p_stock, 'T495 refund by line', gen_random_uuid());
  return null;
exception when others then
  return sqlerrm;
end $f$;
-- The stock questions the Finance panel asks of an invoice.
create function pg_temp.asked(p_inv uuid) returns jsonb language sql as $f$
  select invoice_refund_options_before_sessions(p_inv)->'stock' $f$;
-- The guided Refund in full / Cancel, requested and approved as its plan reads.
create function pg_temp.guided(p_inv uuid, p_action text) returns text language plpgsql as $f$
declare req jsonb; pl jsonb;
begin
  req := request_invoice_action_v2(p_inv, p_action, '[]', 'T495 ' || p_action, null, gen_random_uuid());
  pl := invoice_action_plan(p_inv, p_action, '[]');
  perform resolve_invoice_action_v2((req->>'request_id')::uuid, true, 'T495 approve', pl->>'plan_hash',
    (select coalesce(jsonb_agg(case when coalesce((o->>'amount_required')::boolean, false)
              then jsonb_build_object('code', o->>'code', 'reason', 'T495 override', 'amount', (o->>'default_amount')::numeric)
              else jsonb_build_object('code', o->>'code', 'reason', 'T495 override') end), '[]'::jsonb)
       from jsonb_array_elements(coalesce(pl->'overrides_required', '[]')) o),
    -- The quantities its dialog proposes, confirmed as they are.
    (select jsonb_agg(jsonb_build_object('movement_id', s->>'movement_id', 'sellable_quantity', (s->>'proposed_sellable')::int,
                                         'damaged_quantity', 0, 'not_returned_quantity', 0))
       from jsonb_array_elements(coalesce(pl->'stock', '[]')) s),
    true);
  return null;
exception when others then
  return sqlerrm;
end $f$;
-- The invoice form's correction: another store, or a line's quantity.
create function pg_temp.correct(p_inv uuid, p_store uuid default null, p_item uuid default null, p_qty int default null) returns text language plpgsql as $f$
begin
  perform correct_invoice(p_inv, (select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('invoice_item_id', it.id, 'kind', it.line_kind,
            'product_id', it.product_id, 'promotion_id', it.promotion_id,
            'quantity', case when it.id = p_item then p_qty else it.quantity end, 'unit_price', it.unit_price)) order by it.id)
                                from invoice_items it where it.invoice_id = p_inv),
    jsonb_build_object('expected_edit_count', (select edit_count from invoices where id = p_inv),
      'customer_id', (select customer_id from invoices where id = p_inv),
      'store_id', coalesce(p_store, (select store_id from invoices where id = p_inv))),
    'T495 correction', gen_random_uuid());
  return null;
exception when others then
  return sqlerrm;
end $f$;
create function pg_temp.fp() returns text language sql as $f$
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.oid::regprocedure::text)) || ' ' || count(*)
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.prokind = 'f' $f$;
create function pg_temp.grants() returns text language sql as $f$
  select md5(string_agg(p.oid::regprocedure::text || '=' || coalesce((select string_agg(x::text, ',' order by x::text) from unnest(p.proacl) x), 'null'),
                        '|' order by p.oid::regprocedure::text))
    from pg_proc p where p.pronamespace = 'public'::regnamespace
     and p.proname not in ('product_is_service', 'trg_service_holds_no_stock', 'trg_product_becomes_service') $f$;

-- ── The fixture ──────────────────────────────────────────────────────
do $$
declare own uuid := gen_random_uuid(); st uuid; st2 uuid; pm uuid; wh uuid; svc uuid; prod uuid; third uuid; prm uuid; box uuid; g uuid;
begin
  insert into auth.users(id, email) values (own, 't495-owner@example.invalid');
  insert into profiles(id, full_name, email, role, is_active) values (own, 'T495 Owner', 't495-owner@example.invalid', 'owner', true);
  perform pg_temp.put('own', own);
  perform pg_temp.as_owner();
  insert into stores(name, code, country_code) values ('T495 Store', 'T495S1', 'SG') returning id into st;
  insert into stores(name, code, country_code) values ('T495 Other Store', 'T495S2', 'SG') returning id into st2;
  insert into payment_methods(name, is_active) values ('T495 Cash', true) returning id into pm;
  insert into warehouses(name, code) values ('T495 Warehouse', 'T495W') returning id into wh;
  -- A S$50 service with a price at both stores and no stock; a S$40 product, and a
  -- S$30 third-party product, with stock.
  insert into products(name, sku, product_type) values ('T495 Visit', 'T495-VISIT', 'no_commission') returning id into svc;
  insert into products(name, sku, product_type) values ('T495 Socks', 'T495-SOCKS', 'own') returning id into prod;
  insert into products(name, sku, product_type) values ('T495 Belt', 'T495-BELT', 'third_party') returning id into third;
  insert into store_inventory(store_id, product_id, current_qty) values (st, prod, 100), (st2, prod, 100), (st, third, 100);
  insert into warehouse_inventory(warehouse_id, product_id, current_qty) values (wh, prod, 100);
  perform set_product_prices(s, svc, 50, 50, 'available') from unnest(array[st, st2]) s;
  perform set_product_prices(s, prod, 40, 40, 'available') from unnest(array[st, st2]) s;
  perform set_product_prices(st, third, 30, 30, 'available');
  -- A S$70 promotion of the product and the service; a S$60 one offering either.
  insert into promotions(name, code, fixed_price) values ('T495 Socks and Visit', 'T495-SV', 70) returning id into prm;
  insert into promotion_items(promotion_id, item_type, product_id, quantity) values (prm, 'product', prod, 1), (prm, 'product', svc, 1);
  perform set_promotion_prices(prm, st, 70, 70, true);
  insert into promotions(name, code) values ('T495 Choose One', 'T495-CH') returning id into box;
  insert into promotion_choice_groups(promotion_id, label, item_kind, choose_qty) values (box, 'Choose one', 'product', 1) returning id into g;
  insert into promotion_choice_options(group_id, product_id) values (g, prod), (g, svc);
  perform set_promotion_prices(box, st, 60, 60, true);
  perform pg_temp.put('st', st); perform pg_temp.put('st2', st2); perform pg_temp.put('pm', pm); perform pg_temp.put('wh', wh);
  perform pg_temp.put('svc', svc); perform pg_temp.put('prod', prod); perform pg_temp.put('third', third);
  perform pg_temp.put('prm', prm); perform pg_temp.put('box', box); perform pg_temp.put('boxg', g);
end $$;

-- ── R. Without 495: what was wrong ───────────────────────────────────
\if :{?skip_install}
\else
do $$
declare inv uuid; e text; rs uuid; rs2 uuid;
begin
  perform pg_temp.as_owner();
  -- A service of its own, so what this leaves touches nothing below.
  insert into products(name, sku, product_type) values ('T495 Old Fee', 'T495-OLD', 'no_commission') returning id into rs;
  perform set_product_prices(pg_temp.id('st'), rs, 50, 50, 'available');
  inv := pg_temp.form(jsonb_build_array(pg_temp.pline(rs)));
  e := pg_temp.err(format('select pg_temp.pay(%L)', inv));
  perform pg_temp.ok(e like 'Insufficient store stock%', 'R1 before 495: a service with no stock could not be paid for');
  -- A S$50 service sold with stock typed in: the sale takes one.
  insert into store_inventory(store_id, product_id, current_qty) values (pg_temp.id('st'), rs, 1000);
  perform pg_temp.pay(inv);
  perform pg_temp.ok(pg_temp.sq(pg_temp.id('st'), rs) = 999 and pg_temp.imoves(inv, rs) = 1,
    'R2 before 495: paying took one from the stock typed in');
  perform pg_temp.ok(jsonb_array_length(pg_temp.asked(inv)) = 1, 'R3 before 495: a refund asked about its stock');
  -- Leaves no service with stock, for section I's and Q's counts.
  update store_inventory set current_qty = 0 where product_id = rs;
  update products set product_type = 'own' where id = rs;
end $$;
\endif

-- ── I. Install ───────────────────────────────────────────────────────
\if :{?skip_install}
do $$ begin perform pg_temp.ok(to_regprocedure('public.product_is_service(uuid)') is not null, 'I0 495 is in (skip_install)'); end $$;
\else
do $$
declare fp0 text := pg_temp.fp(); g0 text := pg_temp.grants(); fp1 text; e text; d text;
begin
  perform pg_temp.ok(to_regprocedure('public.product_is_service(uuid)') is null, 'I1 495 is not in yet');
  -- A function not as tested stops it, changing nothing.
  begin
    d := pg_get_functiondef('public.invoice_goods_out(uuid)'::regprocedure);
    execute replace(d, 'cross join lateral', '/* changed */ cross join lateral');
    fp1 := pg_temp.fp();
    e := pg_temp.err(current_setting('t495.mig'));
    perform pg_temp.ok(e like '495: public.invoice_goods_out(uuid) is not the version this was tested against%' and pg_temp.fp() = fp1,
      'I2 a patched function not as tested: refused, nothing changed');
    raise exception using errcode = 'P0495';
  exception when sqlstate 'P0495' then null;
  end;
  -- Install; then again, changing nothing.
  e := pg_temp.err(current_setting('t495.mig'));
  perform pg_temp.ok(e is null, 'I3 installs: ' || coalesce(e, 'yes'));
  fp1 := pg_temp.fp();
  perform pg_temp.ok(fp1 <> fp0 and split_part(fp1, ' ', 2)::int = split_part(fp0, ' ', 2)::int + 3, 'I4 three functions added');
  perform pg_temp.ok(pg_temp.grants() = g0, 'I5 every other function''s grants as before');
  e := pg_temp.err(current_setting('t495.mig'));
  perform pg_temp.ok(e is null and pg_temp.fp() = fp1 and pg_temp.grants() = g0, 'I6 installed again: as tested, nothing changes');
end $$;
\endif
do $$
begin
  perform pg_temp.ok(not has_function_privilege('anon', f, 'execute') and not has_function_privilege('authenticated', f, 'execute')
                     and has_function_privilege('service_role', f, 'execute'), 'I7 ' || f || ' is internal')
    from unnest(array['public.product_is_service(uuid)', 'public.trg_service_holds_no_stock()', 'public.trg_product_becomes_service()']) f;
end $$;

-- ── A. A service alone ───────────────────────────────────────────────
do $$
declare svc uuid := pg_temp.id('svc'); st uuid := pg_temp.id('st'); inv uuid; g jsonb;
begin
  perform pg_temp.as_owner();
  inv := pg_temp.sale(jsonb_build_array(pg_temp.pline(svc, 2)));
  perform pg_temp.ok((select status::text from invoices where id = inv) = 'paid', 'A1 a service with no stock is paid for');
  perform pg_temp.ok(pg_temp.sq(st, svc) is null and pg_temp.moves(svc) = 0, 'A2 no stock row and no movement');
  perform pg_temp.ok(not exists (select 1 from invoice_required_stock(inv)) and not exists (select 1 from invoice_stock_to_deduct(inv)),
    'A3 the invoice owes no stock');
  g := invoice_goods_status(inv);
  perform pg_temp.ok(jsonb_array_length(g->'products') = 0 and (g->>'required_total')::int = 0 and not (g->>'can_hand_over')::boolean,
    'A4 the Goods panel has nothing to hand over');
  perform pg_temp.ok(jsonb_array_length(pg_temp.asked(inv)) = 0, 'A5 a refund asks nothing about stock');
  perform pg_temp.ok((select line_kind::text from invoice_items where invoice_id = inv) = 'product'
                     and (select total_amount from invoices where id = inv) = 100, 'A6 still a product line of S$100');
  -- The backstop when an invoice becomes paid takes nothing.
  perform pg_temp.ok(ensure_invoice_stock_deducted(inv, 'T495') = 0, 'A7 the backstop takes nothing');
end $$;

-- ── B. With a product ────────────────────────────────────────────────
do $$
declare svc uuid := pg_temp.id('svc'); prod uuid := pg_temp.id('prod'); st uuid := pg_temp.id('st'); inv uuid; q0 int; g jsonb;
begin
  perform pg_temp.as_owner();
  q0 := pg_temp.sq(st, prod);
  inv := pg_temp.sale(jsonb_build_array(pg_temp.pline(svc), pg_temp.pline(prod)));
  perform pg_temp.ok(pg_temp.sq(st, prod) = q0 - 1 and pg_temp.imoves(inv, prod) = 1, 'B1 the product is taken');
  perform pg_temp.ok(pg_temp.sq(st, svc) is null and pg_temp.imoves(inv, svc) = 0, 'B2 the service is not');
  g := invoice_goods_status(inv);
  perform pg_temp.ok(jsonb_array_length(g->'products') = 1 and g->'products'->0->>'product_id' = prod::text, 'B3 the Goods panel lists the product alone');
end $$;

-- ── C. Paid in part, handed over ─────────────────────────────────────
do $$
declare svc uuid := pg_temp.id('svc'); prod uuid := pg_temp.id('prod'); st uuid := pg_temp.id('st'); inv uuid; g jsonb; e text; q0 int;
begin
  perform pg_temp.as_owner();
  -- A service alone, paid in part, then settled.
  inv := pg_temp.sale(jsonb_build_array(pg_temp.pline(svc)), 20);
  g := invoice_goods_status(inv);
  perform pg_temp.ok((select status::text from invoices where id = inv) = 'partially_paid' and not (g->>'can_hand_over')::boolean
                     and (g->>'to_collect_total')::int = 0, 'C1 paid in part: nothing to collect');
  e := pg_temp.err(format($q$select record_invoice_handover(%L, jsonb_build_object('items', jsonb_build_array(jsonb_build_object('product_id', %L, 'qty', 1))), gen_random_uuid())$q$, inv, svc));
  perform pg_temp.ok(e is not null and pg_temp.imoves(inv, svc) = 0, 'C2 a service cannot be handed over: ' || coalesce(e, 'it was'));
  perform pg_temp.settle(inv);
  perform pg_temp.ok((select status::text from invoices where id = inv) = 'paid' and pg_temp.imoves(inv, svc) = 0, 'C3 settled: paid, no stock');
  -- With a product: the product is handed over; settling takes no more.
  q0 := pg_temp.sq(st, prod);
  inv := pg_temp.sale(jsonb_build_array(pg_temp.pline(svc), pg_temp.pline(prod)), 20);
  g := invoice_goods_status(inv);
  perform pg_temp.ok((g->>'to_collect_total')::int = 1 and (g->>'can_hand_over')::boolean, 'C4 with a product: 1 to collect');
  perform record_invoice_handover(inv, jsonb_build_object('items', jsonb_build_array(jsonb_build_object('product_id', prod, 'qty', 1))), gen_random_uuid());
  perform pg_temp.settle(inv);
  perform pg_temp.ok(pg_temp.sq(st, prod) = q0 - 1 and pg_temp.imoves(inv, prod) = 1 and pg_temp.imoves(inv, svc) = 0, 'C5 handed over, then settled: the product taken once');
end $$;

-- ── D. FOC ───────────────────────────────────────────────────────────
do $$
declare svc uuid := pg_temp.id('svc'); prod uuid := pg_temp.id('prod'); st uuid := pg_temp.id('st'); inv uuid; it uuid; q0 int;
begin
  perform pg_temp.as_owner();
  q0 := pg_temp.sq(st, prod);
  inv := pg_temp.form(jsonb_build_array(pg_temp.pline(svc), pg_temp.pline(prod)));
  for it in select id from invoice_items where invoice_id = inv loop perform apply_line_foc(it, null, null, 'T495 giveaway'); end loop;
  perform confirm_foc_invoice(inv, null);
  perform pg_temp.ok((select status::text from invoices where id = inv) = 'completed_foc' and pg_temp.imoves(inv, svc) = 0 and pg_temp.sq(st, svc) is null
                     and pg_temp.sq(st, prod) = q0 - 1, 'D1 Confirm FOC: the product taken, the service not');
end $$;

-- ── E. Refund by line (the Finance panel) ────────────────────────────
do $$
declare svc uuid := pg_temp.id('svc'); prod uuid := pg_temp.id('prod'); st uuid := pg_temp.id('st'); inv uuid; e text; q0 int; stock jsonb;
begin
  perform pg_temp.as_owner();
  -- A service alone.
  inv := pg_temp.sale(jsonb_build_array(pg_temp.pline(svc)));
  e := pg_temp.refund_line(inv, pg_temp.line(inv, svc), 50);
  perform pg_temp.ok(e is null and pg_temp.sq(st, svc) is null and pg_temp.moves(svc) = 0, 'E1 a service refunded by line, no stock asked: ' || coalesce(e, 'ok'));
  -- With a product: the service line's refund asks nothing; the product's still does.
  q0 := pg_temp.sq(st, prod);
  inv := pg_temp.sale(jsonb_build_array(pg_temp.pline(svc), pg_temp.pline(prod)));
  perform pg_temp.ok(jsonb_array_length(pg_temp.asked(inv)) = 1 and pg_temp.asked(inv)->0->>'product_id' = prod::text, 'E2 the panel asks about the product alone');
  e := pg_temp.refund_line(inv, pg_temp.line(inv, svc), 50);
  perform pg_temp.ok(e is null, 'E3 the service line refunded, the product''s stock left blank: ' || coalesce(e, 'ok'));
  e := pg_temp.refund_line(inv, pg_temp.line(inv, prod), 40);
  perform pg_temp.ok(e like 'Record the returned-and-sellable%', 'E4 control: the product line, stock left blank, is still refused');
  stock := jsonb_build_array(jsonb_build_object('movement_id', pg_temp.asked(inv)->0->>'movement_id', 'sellable_quantity', 1, 'damaged_quantity', 0, 'not_returned_quantity', 0));
  e := pg_temp.refund_line(inv, pg_temp.line(inv, prod), 40, stock);
  perform pg_temp.ok(e is null and pg_temp.sq(st, prod) = q0, 'E5 control: the product returned as sellable goes back: ' || coalesce(e, 'ok'));
end $$;

-- ── F. The guided Refund in full ─────────────────────────────────────
do $$
declare svc uuid := pg_temp.id('svc'); prod uuid := pg_temp.id('prod'); st uuid := pg_temp.id('st'); inv uuid; e text; q0 int;
begin
  perform pg_temp.as_owner();
  inv := pg_temp.sale(jsonb_build_array(pg_temp.pline(svc)));
  perform pg_temp.ok(jsonb_array_length(invoice_action_plan(inv, 'refund_full', '[]')->'stock') = 0, 'F1 the plan lists no stock for a service');
  e := pg_temp.guided(inv, 'refund_full');
  perform pg_temp.ok(e is null and (select status::text from invoices where id = inv) = 'refunded' and pg_temp.moves(svc) = 0, 'F2 a service refunded in full: ' || coalesce(e, 'ok'));
  q0 := pg_temp.sq(st, prod);
  inv := pg_temp.sale(jsonb_build_array(pg_temp.pline(svc), pg_temp.pline(prod)));
  perform pg_temp.ok(jsonb_array_length(invoice_action_plan(inv, 'refund_full', '[]')->'stock') = 1
                     and invoice_action_plan(inv, 'refund_full', '[]')->'stock'->0->>'product_name' = 'T495 Socks', 'F3 with a product: the plan lists the product alone');
  e := pg_temp.guided(inv, 'refund_full');
  perform pg_temp.ok(e is null and (select status::text from invoices where id = inv) = 'refunded' and pg_temp.imoves(inv, svc) = 0 and pg_temp.sq(st, svc) is null,
    'F4 refunded in full: no stock for the service: ' || coalesce(e, 'ok'));
end $$;

-- ── G. Cancel, Reopen ────────────────────────────────────────────────
do $$
declare svc uuid := pg_temp.id('svc'); prod uuid := pg_temp.id('prod'); st uuid := pg_temp.id('st'); inv uuid; q0 int; p jsonb;
begin
  perform pg_temp.as_owner();
  q0 := pg_temp.sq(st, prod);
  inv := pg_temp.sale(jsonb_build_array(pg_temp.pline(svc), pg_temp.pline(prod)));
  perform cancel_invoice_recorded(inv, 'T495 cancel', gen_random_uuid());
  perform pg_temp.ok((select status::text from invoices where id = inv) = 'cancelled' and pg_temp.sq(st, prod) = q0 and pg_temp.sq(st, svc) is null
                     and pg_temp.imoves(inv, svc) = 0, 'G1 Cancel: the product goes back, nothing for the service');
  perform reopen_invoice(inv, 'T495 reopen', gen_random_uuid());
  if (select status::text from invoices where id = inv) <> 'paid' then perform pg_temp.settle(inv); end if;
  perform pg_temp.ok((select status::text from invoices where id = inv) = 'paid' and pg_temp.sq(st, prod) = q0 - 1 and pg_temp.sq(st, svc) is null,
    'G2 Reopen and settled: the product taken again, nothing for the service');
end $$;

-- ── H. Sales from before 495, the stock typed in still there ─────────
-- What the old code left: the store_sale movement and the row it took from. The
-- trigger is switched off just to write them: 495 would refuse the row.
create function pg_temp.old_world(p_inv uuid, p_product uuid, p_qty int) returns void language plpgsql as $f$
declare st uuid := (select store_id from invoices where id = p_inv);
begin
  alter table store_inventory disable trigger service_holds_no_stock;
  insert into store_inventory(store_id, product_id, current_qty) values (st, p_product, p_qty)
    on conflict (store_id, product_id) do update set current_qty = excluded.current_qty;
  alter table store_inventory enable trigger service_holds_no_stock;
  insert into stock_movements(product_id, movement_type, from_store_id, invoice_id, quantity, notes)
    values (p_product, 'store_sale', st, p_inv, 1, 'T495 sold before 495');
end $f$;
do $$
declare st uuid := pg_temp.id('st'); st2 uuid := pg_temp.id('st2'); prod uuid := pg_temp.id('prod'); old uuid; inv uuid; e text; q0 int; g jsonb;
begin
  perform pg_temp.as_owner();
  insert into products(name, sku, product_type) values ('T495 Fee Before', 'T495-FEE', 'no_commission') returning id into old;
  perform set_product_prices(s, old, 50, 50, 'available') from unnest(array[st, st2]) s;
  perform pg_temp.put('old', old);

  -- Paid before 495.
  inv := pg_temp.sale(jsonb_build_array(pg_temp.pline(old)));
  perform pg_temp.old_world(inv, old, 999);
  perform pg_temp.ok(not exists (select 1 from invoice_goods_out(inv)) and jsonb_array_length(pg_temp.asked(inv)) = 0, 'H1 an old sale: not out with the customer, and no refund asks');
  perform pg_temp.ok(jsonb_array_length(invoice_goods_status(inv)->'products') = 0, 'H2 an old sale: not on the Goods panel');
  perform pg_temp.ok((select count(*) from invoice_list_goods_out(array[inv])) = 0, 'H3 an old sale: not on the list''s goods out');
  e := pg_temp.refund_line(inv, pg_temp.line(inv, old), 50);
  perform pg_temp.ok(e is null and pg_temp.sq(st, old) = 999 and pg_temp.imoves(inv, old) = 1, 'H4 an old sale refunded by line: no stock moves: ' || coalesce(e, 'ok'));

  -- Cancelled and reopened.
  inv := pg_temp.sale(jsonb_build_array(pg_temp.pline(old)));
  perform pg_temp.old_world(inv, old, 999);
  perform cancel_invoice_recorded(inv, 'T495 cancel', gen_random_uuid());
  perform pg_temp.ok((select status::text from invoices where id = inv) = 'cancelled' and pg_temp.sq(st, old) = 999 and pg_temp.imoves(inv, old) = 1, 'H5 an old sale cancelled: nothing goes back');
  perform reopen_invoice(inv, 'T495 reopen', gen_random_uuid());
  if (select status::text from invoices where id = inv) <> 'paid' then perform pg_temp.settle(inv); end if;
  perform pg_temp.ok((select status::text from invoices where id = inv) = 'paid' and pg_temp.sq(st, old) = 999 and pg_temp.imoves(inv, old) = 1, 'H6 reopened and settled: nothing taken');

  -- Refunded in full, with a product on the invoice.
  q0 := pg_temp.sq(st, prod);
  inv := pg_temp.sale(jsonb_build_array(pg_temp.pline(old), pg_temp.pline(prod)));
  perform pg_temp.old_world(inv, old, 999);
  perform pg_temp.ok(jsonb_array_length(pg_temp.asked(inv)) = 1 and pg_temp.asked(inv)->0->>'product_id' = prod::text, 'H7 with a product: the panel asks about the product alone');
  e := pg_temp.guided(inv, 'refund_full');
  perform pg_temp.ok(e is null and pg_temp.sq(st, old) = 999, 'H8 refunded in full: the service''s row untouched: ' || coalesce(e, 'ok'));

  -- A product line's refund does not wait on an old sale of a service.
  inv := pg_temp.form(jsonb_build_array(pg_temp.pline(old), pg_temp.pline(pg_temp.id('third'))));
  perform pg_temp.pay(inv, 20);
  perform pg_temp.old_world(inv, old, 999);
  e := pg_temp.refund_line(inv, pg_temp.line(inv, pg_temp.id('third')), 20);
  perform pg_temp.ok(e is null, 'H9 a product line, its product not taken yet, an old sale of a service: not held up: ' || coalesce(e, 'ok'));

  -- Paid in part before 495, the stock typed in, settled after: nothing taken.
  inv := pg_temp.sale(jsonb_build_array(pg_temp.pline(old)), 20);
  perform pg_temp.settle(inv);
  perform pg_temp.ok((select status::text from invoices where id = inv) = 'paid' and pg_temp.sq(st, old) = 999 and pg_temp.imoves(inv, old) = 0, 'H10 paid in part, settled now: nothing taken');

  -- Corrected: another store; the stock typed in stays where it was.
  inv := pg_temp.sale(jsonb_build_array(pg_temp.pline(old), pg_temp.pline(prod)));
  perform pg_temp.old_world(inv, old, 999);
  e := pg_temp.correct(inv, st2);
  perform pg_temp.ok(e is null and pg_temp.sq(st, old) = 999 and pg_temp.sq(st2, old) is null, 'H11 an old sale moved to another store: its row untouched, none at the other: ' || coalesce(e, 'ok'));
end $$;

-- ── J. Corrections, the store change, the warehouse ──────────────────
do $$
declare svc uuid := pg_temp.id('svc'); prod uuid := pg_temp.id('prod'); st uuid := pg_temp.id('st'); st2 uuid := pg_temp.id('st2'); wh uuid := pg_temp.id('wh');
  inv uuid; e text; p jsonb; q0 int; w0 int;
begin
  perform pg_temp.as_owner();
  inv := pg_temp.sale(jsonb_build_array(pg_temp.pline(svc)));
  e := pg_temp.correct(inv, null, pg_temp.line(inv, svc), 2);
  perform pg_temp.ok(e is null and pg_temp.moves(svc) = 0, 'J1 a paid service''s quantity corrected: no stock: ' || coalesce(e, 'ok'));
  inv := pg_temp.sale(jsonb_build_array(pg_temp.pline(svc)));
  p := invoice_store_change_preview(inv, st2);
  perform pg_temp.ok(jsonb_array_length(p->'shortages') = 0 and jsonb_array_length(p->'required_stock') = 0 and not (p->>'blocked')::boolean, 'J2 the store-change preview: nothing short');
  e := pg_temp.correct(inv, st2);
  perform pg_temp.ok(e is null and (select store_id from invoices where id = inv) = st2 and pg_temp.sq(st2, svc) is null, 'J3 moved to another store: no stock: ' || coalesce(e, 'ok'));
  -- Fulfil from a warehouse holding the product and no service.
  q0 := pg_temp.sq(st, prod); w0 := pg_temp.wq(wh, prod);
  inv := pg_temp.form(jsonb_build_array(pg_temp.pline(svc), pg_temp.pline(prod)));
  e := pg_temp.err(format('select set_invoice_fulfilment_warehouse(%L, %L)', inv, wh));
  perform pg_temp.ok(e is null, 'J4 Fulfil from a warehouse: the service asks nothing of it: ' || coalesce(e, 'ok'));
  perform pg_temp.pay(inv);
  perform pg_temp.ok((select status::text from invoices where id = inv) = 'paid' and pg_temp.wq(wh, prod) = w0 - 1 and pg_temp.sq(st, prod) = q0
                     and pg_temp.wq(wh, svc) is null and pg_temp.sq(st, svc) is null, 'J5 paid: the warehouse sends the product, no service row anywhere');
  -- Control: a warehouse short of a real product still refuses.
  inv := pg_temp.form(jsonb_build_array(pg_temp.pline(svc), pg_temp.pline(pg_temp.id('third'))));
  e := pg_temp.err(format('select set_invoice_fulfilment_warehouse(%L, %L)', inv, wh));
  perform pg_temp.ok(e like 'That warehouse cannot cover this invoice: T495 Belt%' and e not like '%Visit%', 'J6 control: a warehouse short of a product still refuses, naming it alone');
end $$;

-- ── K. A promotion holding a service ─────────────────────────────────
do $$
declare svc uuid := pg_temp.id('svc'); prod uuid := pg_temp.id('prod'); st uuid := pg_temp.id('st'); inv uuid; q0 int; e text;
begin
  perform pg_temp.as_owner();
  q0 := pg_temp.sq(st, prod);
  inv := pg_temp.sale(jsonb_build_array(jsonb_build_object('kind', 'promotion', 'promotion_id', pg_temp.id('prm'), 'quantity', 1)));
  perform pg_temp.ok((select string_agg(r.item_id::text, ',') from invoice_required_stock(inv) r) = prod::text
                     and pg_temp.sq(st, prod) = q0 - 1 and pg_temp.imoves(inv, svc) = 0, 'K1 a promotion''s own contents: the product taken, the service not');
  e := pg_temp.refund_line(inv, (select id from invoice_items where invoice_id = inv), 70,
    (select jsonb_agg(jsonb_build_object('movement_id', s->>'movement_id', 'sellable_quantity', 1, 'damaged_quantity', 0, 'not_returned_quantity', 0)) from jsonb_array_elements(pg_temp.asked(inv)) s));
  perform pg_temp.ok(e is null and pg_temp.sq(st, prod) = q0 and pg_temp.sq(st, svc) is null, 'K2 refunded: the product back, nothing for the service: ' || coalesce(e, 'ok'));
  q0 := pg_temp.sq(st, prod);
  inv := pg_temp.sale(jsonb_build_array(jsonb_build_object('kind', 'promotion', 'promotion_id', pg_temp.id('box'), 'quantity', 1, 'selections',
    jsonb_build_array(jsonb_build_object('group_id', pg_temp.id('boxg'), 'options',
      jsonb_build_array(jsonb_build_object('product_id', svc, 'voucher_id', null, 'therapy_package_id', null, 'credit_package_id', null, 'child_promotion_id', null, 'quantity', 1)))))));
  perform pg_temp.ok((select status::text from invoices where id = inv) = 'paid' and not exists (select 1 from invoice_required_stock(inv))
                     and pg_temp.sq(st, prod) = q0 and pg_temp.imoves(inv, svc) = 0, 'K3 a service picked in a choice group: paid, no stock');
  -- An invoice from before stock snapshots counts the other way, to the same end.
  inv := pg_temp.form(jsonb_build_array(pg_temp.pline(svc), pg_temp.pline(prod, 2)));
  update invoices set stock_snapshot_version = null where id = inv;
  perform pg_temp.ok((select string_agg(r.item_id::text || ' ' || r.quantity, ',') from invoice_required_stock(inv) r) = prod::text || ' 2',
    'K4 an invoice with no snapshot owes the product alone');
end $$;

-- ── L. Stock cannot go up on a service ───────────────────────────────
do $$
declare svc uuid := pg_temp.id('svc'); st uuid := pg_temp.id('st'); wh uuid := pg_temp.id('wh'); e text; a jsonb; c_words constant text := 'T495 Visit is a service, so it holds no stock.';
begin
  perform pg_temp.as_owner();
  e := pg_temp.err(format($q$select warehouse_stock_ins(%L, %L, 'T495 delivery', null, null, gen_random_uuid())$q$, wh, jsonb_build_array(jsonb_build_object('product_id', svc, 'quantity', 5))));
  perform pg_temp.ok(e like '%' || c_words || '%' and pg_temp.wq(wh, svc) is null, 'L1 Stock In refused: ' || coalesce(e, 'it took it'));
  a := request_inventory_adjustments('store', st, jsonb_build_array(jsonb_build_object('product_id', svc, 'new_qty', 5)), 'T495 opening stock', null, gen_random_uuid());
  e := pg_temp.err(format('select resolve_inventory_adjustment(%L, true, null)', a->'requests'->0->>'request_id'));
  perform pg_temp.ok(e like '%' || c_words || '%' and pg_temp.sq(st, svc) is null and pg_temp.moves(svc) = 0, 'L2 an "opening stock" adjustment: refused at approval: ' || coalesce(e, 'it took it'));
  e := pg_temp.err(format('insert into store_inventory(store_id, product_id, current_qty) values (%L, %L, 5)', st, svc));
  perform pg_temp.ok(e = c_words, 'L3 a store row with stock: refused');
  e := pg_temp.err(format('insert into warehouse_inventory(warehouse_id, product_id, current_qty) values (%L, %L, 5)', wh, svc));
  perform pg_temp.ok(e = c_words, 'L4 a warehouse row with stock: refused');
  e := pg_temp.err(format('select lend_stock(''store'', %L, %L, sg_today() + 7, null, ''T495 borrower'', ''T495'', gen_random_uuid())', st, jsonb_build_array(jsonb_build_object('product_id', svc, 'qty', 1))));
  perform pg_temp.ok(e is not null and pg_temp.sq(st, svc) is null, 'L5 lending a service: refused: ' || coalesce(e, 'it lent it'));
end $$;

-- ── M. Down, and 0, are allowed ──────────────────────────────────────
do $$
declare st uuid := pg_temp.id('st'); wh uuid := pg_temp.id('wh'); old uuid := pg_temp.id('old'); svc uuid := pg_temp.id('svc'); e text;
begin
  perform pg_temp.as_owner();
  perform set_low_stock_threshold('store', st, svc, 0);
  perform pg_temp.ok(coalesce(pg_temp.sq(st, svc), 0) = 0, 'M1 a low-stock threshold on a service: allowed, at 0');
  e := pg_temp.err(format('update store_inventory set current_qty = 0, updated_at = now() where store_id = %L and product_id = %L', st, svc));
  perform pg_temp.ok(e is null, 'M2 a row at 0 updated: allowed');
  e := pg_temp.err(format('update store_inventory set low_stock_threshold = 2 where store_id = %L and product_id = %L', st, old));
  perform pg_temp.ok(e is null and pg_temp.sq(st, old) = 999, 'M3 a row with stock typed in: its threshold changes');
  e := pg_temp.err(format('update store_inventory set current_qty = 998 where store_id = %L and product_id = %L', st, old));
  perform pg_temp.ok(e is null, 'M4 stock typed in may go down');
  e := pg_temp.err(format('update store_inventory set current_qty = 999 where store_id = %L and product_id = %L', st, old));
  perform pg_temp.ok(e like '%is a service, so it holds no stock.', 'M5 and not back up');
  -- Back to where H left it, for Q.
  update store_inventory set current_qty = 0 where store_id = st and product_id = old;
end $$;

-- ── N. A product becomes a service ───────────────────────────────────
do $$
declare st uuid := pg_temp.id('st'); wh uuid := pg_temp.id('wh'); p uuid; e text; a jsonb; c_type constant jsonb := jsonb_build_object('product_type', 'no_commission');
begin
  perform pg_temp.as_owner();
  -- Added as a service on the Products page.
  a := save_product(null, jsonb_build_object('name', 'T495 New Service', 'sku', 'T495-NEW', 'product_type', 'no_commission'), null, null);
  perform pg_temp.ok((a->>'created')::boolean and (select product_type::text from products where id = (a->>'product_id')::uuid) = 'no_commission', 'N1 Add Service saves');

  insert into products(name, sku, product_type) values ('T495 Lamp', 'T495-LAMP', 'own') returning id into p;
  -- Holding stock.
  insert into store_inventory(store_id, product_id, current_qty) values (st, p, 3);
  e := pg_temp.err(format('select save_product(%L, %L, null, null)', p, c_type));
  perform pg_temp.ok(e like 'T495 Lamp cannot become a service yet: a service holds no stock. Still open: stock (3 at T495 Store).'
                     and (select product_type::text from products where id = p) = 'own', 'N2 holding stock: refused, saying where: ' || coalesce(e, 'it changed'));
  update store_inventory set current_qty = 0 where product_id = p;
  -- In a warehouse.
  insert into warehouse_inventory(warehouse_id, product_id, current_qty) values (wh, p, 2);
  e := pg_temp.err(format('update products set product_type = ''no_commission'' where id = %L', p));
  perform pg_temp.ok(e like '%stock (2 at T495 Warehouse)%', 'N3 in a warehouse, by the API: refused');
  update warehouse_inventory set current_qty = 0 where product_id = p;
  -- With nothing in the way.
  e := pg_temp.err(format('select save_product(%L, %L, null, null)', p, c_type));
  perform pg_temp.ok(e is null and public.product_is_service(p), 'N4 no stock left: it becomes a service: ' || coalesce(e, 'ok'));
  -- And back; it can hold stock again.
  perform save_product(p, jsonb_build_object('product_type', 'own'), null, null);
  e := pg_temp.err(format('update store_inventory set current_qty = 4 where store_id = %L and product_id = %L', st, p));
  perform pg_temp.ok(e is null and not public.product_is_service(p), 'N5 back to Own: it holds stock again');
  -- A save that leaves the type alone is not stopped, holding stock or not.
  e := pg_temp.err(format('select save_product(%L, %L, null, null)', p, jsonb_build_object('name', 'T495 Lamp 2')));
  perform pg_temp.ok(e is null, 'N6 another change to a product holding stock: as before');
  e := pg_temp.err(format('select save_product(%L, %L, null, null)', pg_temp.id('old'), jsonb_build_object('name', 'T495 Fee Before 2', 'product_type', 'no_commission')));
  perform pg_temp.ok(e is null, 'N7 a service saved with its type unchanged: as before');
end $$;
do $$
declare p uuid; pr uuid; e text;
begin
  perform pg_temp.as_owner();
  -- On a live promotion.
  select id into p from products where sku = 'T495-LAMP';
  update store_inventory set current_qty = 0 where product_id = p;
  insert into promotions(name, code, is_active) values ('T495 Lamp Deal', 'T495-LD', true) returning id into pr;
  insert into promotion_items(promotion_id, item_type, product_id, quantity) values (pr, 'product', p, 1);
  e := pg_temp.err(format('update products set product_type = ''no_commission'' where id = %L', p));
  perform pg_temp.ok(e like '%a live promotion (T495 Lamp Deal)%', 'N8 on a live promotion: refused: ' || coalesce(e, 'it changed'));
end $$;

-- ── O. Controls: a product as before ─────────────────────────────────
do $$
declare st uuid := pg_temp.id('st'); third uuid := pg_temp.id('third'); inv uuid; e text; p uuid;
begin
  perform pg_temp.as_owner();
  -- With no stock, paying a product is refused, as before.
  insert into products(name, sku, product_type) values ('T495 Empty', 'T495-EMPTY', 'own') returning id into p;
  perform set_product_prices(st, p, 10, 10, 'available');
  inv := pg_temp.form(jsonb_build_array(pg_temp.pline(p)));
  e := pg_temp.err(format('select pg_temp.pay(%L)', inv));
  perform pg_temp.ok(e like 'Insufficient store stock for T495 Empty%', 'O1 a product with no stock: payment still refused');
  -- Stock In and an adjustment on a product work.
  e := pg_temp.err(format($q$select warehouse_stock_ins(%L, %L, 'T495 delivery', null, null, gen_random_uuid())$q$, pg_temp.id('wh'), jsonb_build_array(jsonb_build_object('product_id', p, 'quantity', 5))));
  perform pg_temp.ok(e is null and pg_temp.wq(pg_temp.id('wh'), p) = 5, 'O2 Stock In of a product: as before: ' || coalesce(e, 'ok'));
  -- A third-party product takes stock.
  inv := pg_temp.sale(jsonb_build_array(pg_temp.pline(third)));
  perform pg_temp.ok(pg_temp.imoves(inv, third) = 1, 'O3 a third-party product is taken, as before');
end $$;

-- ── P. Commission as before ──────────────────────────────────────────
do $$
declare st uuid := pg_temp.id('st'); svc uuid := pg_temp.id('svc'); prod uuid := pg_temp.id('prod'); ref uuid; buyer uuid; inv uuid;
begin
  perform pg_temp.as_owner();
  ref := pg_temp.cust();
  insert into customers(full_name, phone, referred_by) values ('T495 Referred', '+6125550' || lpad((1000 + nextval('t495_phone'))::text, 4, '0'), ref) returning id into buyer;
  inv := create_invoice_with_details(st, buyer, jsonb_build_array(pg_temp.pline(svc), pg_temp.pline(prod)), jsonb_build_object('business_date', sg_today()::text));
  perform pg_temp.pay(inv);
  perform pg_temp.ok(exists (select 1 from commissions c where c.invoice_id = inv and c.invoice_item_id = pg_temp.line(inv, prod))
                     and not exists (select 1 from commissions c where c.invoice_id = inv and c.invoice_item_id = pg_temp.line(inv, svc)
                                      and c.commission_amount > 0), 'P1 the product earns commission, the service none');
end $$;

-- ── Q. The made-up stock removed ─────────────────────────────────────
do $$
declare st uuid := pg_temp.id('st'); st2 uuid := pg_temp.id('st2'); a uuid; b uuid; c uuid; e text; n0 bigint; fp0 text;
begin
  perform pg_temp.as_owner();
  -- Nothing to remove: it refuses.
  e := pg_temp.err(current_setting('t495.remove'));
  perform pg_temp.ok(e like '495 stock: found 0 rows and 0 units on services%', 'Q1 not what was read: refused: ' || coalesce(e, 'it ran'));
  -- As production: a service at two stores, two more at one.
  alter table store_inventory disable trigger service_holds_no_stock;
  insert into products(name, sku, product_type) values ('T495 Call', 'T495-Q1', 'no_commission') returning id into a;
  insert into products(name, sku, product_type) values ('T495 Repair', 'T495-Q2', 'no_commission') returning id into b;
  insert into products(name, sku, product_type) values ('T495 Fee', 'T495-Q3', 'no_commission') returning id into c;
  insert into store_inventory(store_id, product_id, current_qty) values (st, a, 1000), (st2, a, 999), (st, b, 999), (st, c, 997);
  alter table store_inventory enable trigger service_holds_no_stock;
  n0 := (select count(*) from stock_movements);
  -- The recording account missing: it refuses.
  perform set_config('request.jwt.claim.sub', '', true);
  e := pg_temp.err(current_setting('t495.remove'));
  perform pg_temp.ok(e like '495 stock: set the recording account first%', 'Q2 no recording account: refused');
  perform pg_temp.as_owner();
  e := pg_temp.err(current_setting('t495.remove'));
  perform pg_temp.ok(e is null, 'Q3 removed: ' || coalesce(e, 'ok'));
  perform pg_temp.ok(pg_temp.sq(st, a) = 0 and pg_temp.sq(st2, a) = 0 and pg_temp.sq(st, b) = 0 and pg_temp.sq(st, c) = 0, 'Q4 all four rows at 0, still there');
  perform pg_temp.ok((select count(*) from stock_movements) = n0 + 4
                     and (select count(*) from stock_movements m where m.movement_type = 'inventory_adjustment' and m.product_id in (a, b, c)
                           and m.notes like 'Adjustment: A service holds no stock%' and m.from_store_id is not null and m.to_store_id is null) = 4,
    'Q5 one adjustment movement per row, saying why');
  perform pg_temp.ok((select count(*) from approval_requests r where r.request_type = 'adjustment' and r.status = 'approved' and r.payload->>'reference' = '495'
                       or (r.request_type = 'adjustment' and r.status = 'approved' and r.reason like 'A service holds no stock%')) = 4, 'Q6 four approved requests on the Approvals history');
  -- Now they can be deleted, like any product holding nothing.
  e := pg_temp.err(format('select soft_delete_product(%L)', c));
  perform pg_temp.ok(e is null, 'Q7 a service with its stock gone can be deleted: ' || coalesce(e, 'ok'));
  -- Run again: refused, nothing changes.
  n0 := (select count(*) from stock_movements);
  e := pg_temp.err(current_setting('t495.remove'));
  perform pg_temp.ok(e like '495 stock: found 0 rows%' and (select count(*) from stock_movements) = n0, 'Q8 run again: refused, nothing changes');
end $$;

-- ── U. The UNDO ──────────────────────────────────────────────────────
-- 496 (where it is in) was applied after 495 and patches refund_invoice_recorded on top of
-- it, so it is undone first, as its own UNDO says.
select to_regprocedure('public.special_release_rows(uuid)') is not null as t495_has496 \gset
\if :t495_has496
\ir ../../special/undo-496.sql
\endif
do $$
declare e text; fp0 text;
begin
  e := pg_temp.err(current_setting('t495.undo'));
  perform pg_temp.ok(e is null, 'U1 UNDO runs: ' || coalesce(e, 'ok'));
  perform pg_temp.ok(to_regprocedure('public.product_is_service(uuid)') is null and to_regprocedure('public.trg_service_holds_no_stock()') is null
                     and to_regprocedure('public.trg_product_becomes_service()') is null
                     and not exists (select 1 from pg_trigger where tgname in ('service_holds_no_stock', 'products_become_service_check')),
    'U2 its functions and triggers are gone');
  perform pg_temp.ok(md5(pg_get_functiondef(s::regprocedure)) = m, 'U3 ' || s || ' is back')
    from (values ('public.invoice_required_stock(uuid)', 'c91dc1eb4f2b7b465de5fe4a8fb2ca0c'),
                 ('public.invoice_goods_out(uuid)', '15ffed0ff0d5d9cc5685af8e834302ae'),
                 ('public.restore_invoice_stock(uuid,text)', '092316c3af22361f80d186e38fe49bf3'),
                 ('public.invoice_refund_options_before_sessions(uuid)', 'bd3afcc79cd2f06f983607d54fed167c'),
                 ('public.refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid)', '804ecd829cfecf713783a09a05d93c7e'),
                 ('public.trg_fulfil_from_warehouse()', 'e1d41bce9c53d21ac2ab727042663cfb'),
                 ('public.set_invoice_fulfilment_warehouse(uuid,uuid)', '66bf7f38e06bf48116b63b71ca7663cb')) x(s, m);
  e := pg_temp.err(current_setting('t495.undo'));
  perform pg_temp.ok(e is not null, 'U4 run again: refused');
end $$;

-- ── The result ───────────────────────────────────────────────────────
set local client_min_messages = notice;
do $$
declare n int; f int; x text;
begin
  select count(*), count(*) filter (where not ok) into n, f from t495_res;
  if f > 0 then
    select string_agg(label, E'\n' order by t495_res.n) into x from t495_res where not ok;
    raise exception E'495: % of % checks FAILED:\n%', f, n, x;
  end if;
  raise notice '495: all % checks passed', n;
end $$;
rollback;
