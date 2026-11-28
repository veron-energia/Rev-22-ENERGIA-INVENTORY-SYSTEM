-- The Low finding L20 of the security audit of 17 Nov 2026 (542): a refund or cancellation
-- request's details are shown to an Owner, a Manager of the invoice's store and the staff member
-- who raised it (297's rule; the user, 26 Nov 2026: "Requester sees own"), also through the
-- approval_requests table and a resolved request's outcome; the stock answers given with a refund
-- are for the refunded lines; a waiting request approved by a direct action gets its approval
-- entry in the Audit Log, and one approved through its own approval gets exactly one.
--
-- Calls are made as the pages make them: a signed-in login (the authenticated role, its JWT), or
-- as a server function runs (the database owner with the login's claims, "pg:"), or the secret key
-- ("service"). Each call is rolled back on its own. The logins: an Owner, a Manager of the store, a
-- Manager of another store, two Staff of the store (one raises the requests), an Admin and an
-- Inventory Manager. Made-up rows: two stores, three products, a promotion, a customer, four paid
-- invoices (two product lines; a promotion line and a product line; one for a request rejected
-- already; one with a cancellation request), a refund request on the first, and a stock correction
-- request (another kind, whose rule is unchanged).
--
--   B  (install mode) every case below, as it answers before 542, kept to compare.
--   D  invoice_action_request_detail: Owner, the store's Manager and the requester read it; the
--      other Staff member and the Admin are refused (they read it before 542); the other store's
--      Manager, the Inventory Manager (540, first) and the secret key are refused, as before.
--   T  approval_requests: the invoice request is read by the Owner, the store's Manager and the
--      requester; not by the Admin or the other store's Manager (who read it before), nor the other
--      Staff member (as before). The stock correction request is read as before.
--   R  resolve_invoice_action_v2 on a resolved request: the other store's Manager is refused (told
--      its outcome before 542); the store's Manager is told, as before.
--   S  refund stock answers: an answer for another line's stock is refused (accepted before); an
--      answer for the line's own stock, a promotion line's products, and stock no line holds pass,
--      as before; a line whose own stock is answered already is refunded with no answer while
--      another line's stock is unanswered (refused before); a line whose stock is unanswered still
--      needs an answer.
--   Q  how many units an answer may put back, unchanged by 542: per deduction, all answers (this
--      refund's and earlier ones', any route) and cancellation returns together at most what it
--      took, so per product at most what the invoice deducted; a deduction answered twice in one
--      refund is refused by the table's own key; stock no line holds is bounded the same way; a
--      refused answer records nothing. An answer is not held to the quantity a refund pays for
--      (Q5: half the line's money, both its units back), as before.
--   E  the Audit Log: an approval through Approvals writes one invoice_action_approved entry (as
--      before); a direct refund that closes the invoice and a direct cancellation each write one for
--      the waiting request they approve (none before).
--   G  542's fixed parts: the four functions' AFTER md5s, grants and search path; the helper
--      postgres's alone; the read rule; 540's guard still first in invoice_action_request_detail.
--   U  scripts/invoice-actions/undo-542.sql puts everything back exactly; a second undo refuses;
--      542 again makes the same.
--   M  542 a second time refuses.
--
-- Disposable local database only; everything is rolled back. Every name and number is invented
-- (Testing ..., INV numbers from the app's own sequence, @example.invalid; phones +61 491 570 nnn).
-- Run it on a copy of production with 540 and without 542 (it applies 542, then again); with
-- -v skip_install=1 where 542 is in (B, U and M skipped).
--   psql -X -v ON_ERROR_STOP=1 -f scripts/invoice-actions/tests/refund-request-rules-542.sql
\set ON_ERROR_STOP on
begin;
-- 548 (the Class page): where it is in, its UNDO goes first of all, before 547's (it calls 540's
-- inventory_manager_guard, which 540's UNDO refuses while any other function uses it).
select to_regprocedure('public.class_page_data()') is not null as t548_in \gset
\if :t548_in
select set_config('energia.undo548_test_only', 'on', true) \g /dev/null
\ir ../../classes/undo-548.sql
\endif
-- 547 (goods collected for special, consignment and rental items): where it is in, its UNDO goes
-- first of all, before 546's.
select to_regprocedure('public.invoice_special_collect_internal(uuid,uuid,jsonb)') is not null as t547_in \gset
\if :t547_in
select set_config('energia.undo547_test_only', 'on', true) \g /dev/null
\ir ../../special/undo-547.sql
\endif
set local lock_timeout = '10s';
set local statement_timeout = '900s';
create temp table fn0 as
  select p.oid::regprocedure::text as fn, md5(pg_get_functiondef(p.oid)) as md5, p.proacl::text as acl
    from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p');
create temp table pol0 as
  select c.relname, p.polname, pg_get_expr(p.polqual, p.polrelid) as qual
    from pg_policy p join pg_class c on c.oid = p.polrelid where c.relnamespace = 'public'::regnamespace;
select to_regprocedure('public.inventory_manager_guard(text)') is not null as had540,
       to_regprocedure('public.invoice_line_holds_stock(uuid,uuid)') is not null as had542 \gset
\if :had540
\else
\echo 540 is not in: 542 needs it
select 1/0;
\endif
\if :{?skip_install}
\if :had542
\else
\echo 542 is not in: run without -v skip_install
select 1/0;
\endif
\set mode skip
\elif :had542
\echo 542 is already in: run with -v skip_install=1
select 1/0;
\else
\set mode install
\endif
select :'mode' = 'install' as by_us \gset

create temp table failed(n serial, msg text);
create function pg_temp.check(ok boolean, msg text) returns void language plpgsql as
$$begin
  if ok is distinct from true then insert into failed(msg) values (msg); raise notice 'FAIL  %', msg;
  else raise notice 'PASS  %', msg; end if;
end$$;
create temp table fx(k text primary key, v uuid);
create function pg_temp.fx(key text) returns uuid language sql as $$ select v from fx where k = key $$;
create function pg_temp.put(key text, val uuid) returns uuid language sql as
$$ insert into fx values (key, val) on conflict (k) do update set v = excluded.v returning v $$;
create temp table sfx as select 'zq' || lower(substr(md5(gen_random_uuid()::text), 1, 6)) as tok, (floor(random() * 900))::int as ph;
create function pg_temp.tok() returns text language sql as $$ select tok from sfx $$;
create function pg_temp.claims(who text) returns void language plpgsql as $f$
begin
  perform set_config('request.jwt.claim.sub', coalesce(pg_temp.fx(who)::text, ''), true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', pg_temp.fx(who), 'role', 'authenticated')::text, true);
end $f$;
create function pg_temp.as_(who text, q text) returns text language plpgsql as $f$
declare v text; s text; m text;
begin
  begin
    if who = 'service' then
      perform set_config('request.jwt.claim.sub', '', true);
      perform set_config('request.jwt.claim.role', 'service_role', true);
      perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
      execute 'set local role service_role';
    elsif who like 'pg:%' then
      perform pg_temp.claims(substr(who, 4));
    else
      perform pg_temp.claims(who);
      execute 'set local role authenticated';
    end if;
    execute q into v;
    raise exception using errcode = 'P0999', message = coalesce(v, '');
  exception
    when sqlstate 'P0999' then get stacked diagnostics m = message_text; return 'ok:' || m;
    when others then get stacked diagnostics s = returned_sqlstate, m = message_text; return 'ERR ' || s || ' ' || m;
  end;
end $f$;

-- ═════ Fixtures (invented) ═════
do $fx$
declare r record; u uuid; t text := pg_temp.tok(); inv uuid;
begin
  insert into public.app_settings(id) values (true) on conflict do nothing;
  insert into public.stores(name, code, country_code) values ('Testing Store A', 'T542A' || upper(substr(md5(t), 1, 4)), 'SG') returning id into u; perform pg_temp.put('st', u);
  insert into public.stores(name, code, country_code) values ('Testing Store B', 'T542B' || upper(substr(md5(t), 1, 4)), 'SG') returning id into u; perform pg_temp.put('st2', u);
  for r in select * from (values
      ('own', 'owner', null), ('mgr', 'manager', 'st'), ('mgr2', 'manager', 'st2'), ('stf', 'staff', 'st'),
      ('stfb', 'staff', 'st'), ('adm', 'admin', null), ('invm', 'inventory_manager', 'st')) x(k, role, store) loop
    insert into auth.users(id, email, email_confirmed_at) values (gen_random_uuid(), 'm542-' || r.k || '-' || md5(t) || '@example.invalid', now()) returning id into u;
    insert into public.profiles(id, full_name, email, role, is_active) values (u, 'Testing ' || r.k, 'm542-' || r.k || '-' || md5(t) || '@example.invalid', r.role::public.user_role, true);
    perform pg_temp.put(r.k, u);
    if r.store is not null then
      insert into public.user_store_assignments(user_id, store_id) values (u, pg_temp.fx(r.store));
    end if;
  end loop;
  perform set_config('request.jwt.claim.sub', pg_temp.fx('own')::text, true);
  insert into public.customers(full_name, first_name, last_name, phone, email)
  values ('Testing ' || t || ' Buyer', 'Testing', t || ' Buyer', '+61491570' || lpad((select ph from sfx)::text, 3, '0'), t || '@example.invalid') returning id into u; perform pg_temp.put('c', u);
  insert into public.payment_methods(name, is_active) values ('Testing Visa ' || t, true) returning id into u; perform pg_temp.put('pm', u);
  insert into public.products(name, sku, product_type) values ('Testing A', 'T542-A-' || t, 'own') returning id into u; perform pg_temp.put('pa', u);
  insert into public.products(name, sku, product_type) values ('Testing B', 'T542-B-' || t, 'own') returning id into u; perform pg_temp.put('pb', u);
  insert into public.products(name, sku, product_type) values ('Testing C', 'T542-C-' || t, 'own') returning id into u; perform pg_temp.put('pc', u);
  insert into public.products(name, sku, product_type) values ('Testing D', 'T542-D-' || t, 'own') returning id into u; perform pg_temp.put('pd', u);
  insert into public.store_inventory(store_id, product_id, current_qty)
  select pg_temp.fx('st'), pg_temp.fx(k), 50 from unnest(array['pa', 'pb', 'pc', 'pd']) k;
  perform public.set_product_prices(pg_temp.fx('st'), pg_temp.fx(k), 100, 100, 'available') from unnest(array['pa', 'pb', 'pc', 'pd']) k;
  insert into public.promotions(name, code) values ('Testing Promotion ' || t, 'T542-P-' || t) returning id into u; perform pg_temp.put('promo', u);
  insert into public.promotion_items(promotion_id, item_type, product_id, quantity) values (u, 'product', pg_temp.fx('pc'), 1);
  insert into public.promotion_store_prices(promotion_id, store_id, selling_price) values (u, pg_temp.fx('st'), 300);
  -- I1: two product lines, A x2 and B x1. I3: a promotion line (C) and a product line (A).
  -- I2: a request rejected already. I4: a cancellation request waiting.
  inv := public.create_invoice(pg_temp.fx('st'), pg_temp.fx('c'), null, jsonb_build_array(
           jsonb_build_object('kind', 'product', 'product_id', pg_temp.fx('pa'), 'quantity', 2),
           jsonb_build_object('kind', 'product', 'product_id', pg_temp.fx('pb'), 'quantity', 1)));
  perform pg_temp.put('i1', inv);
  inv := public.create_invoice(pg_temp.fx('st'), pg_temp.fx('c'), null, jsonb_build_array(jsonb_build_object('kind', 'product', 'product_id', pg_temp.fx('pb'), 'quantity', 1)));
  perform pg_temp.put('i2', inv);
  inv := public.create_invoice(pg_temp.fx('st'), pg_temp.fx('c'), null, jsonb_build_array(
           jsonb_build_object('kind', 'promotion', 'promotion_id', pg_temp.fx('promo'), 'quantity', 1),
           jsonb_build_object('kind', 'product', 'product_id', pg_temp.fx('pa'), 'quantity', 1)));
  perform pg_temp.put('i3', inv);
  inv := public.create_invoice(pg_temp.fx('st'), pg_temp.fx('c'), null, jsonb_build_array(jsonb_build_object('kind', 'product', 'product_id', pg_temp.fx('pd'), 'quantity', 1)));
  perform pg_temp.put('i4', inv);
  for r in select x from unnest(array['i1', 'i2', 'i3', 'i4']) x loop
    perform public.record_invoice_payment(pg_temp.fx(r.x), jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.fx('pm'),
      'amount', (select total_amount from public.invoices where id = pg_temp.fx(r.x)))), gen_random_uuid());
  end loop;
  if (select count(*) from public.stock_movements where invoice_id = pg_temp.fx('i1') and movement_type::text = 'store_sale') <> 2
     or not exists (select 1 from public.stock_movements where invoice_id = pg_temp.fx('i3') and product_id = pg_temp.fx('pc') and movement_type::text = 'store_sale') then
    raise exception 'Fixture: the invoices took no stock as expected'; end if;
  -- The requests, by Staff.
  perform set_config('request.jwt.claim.sub', pg_temp.fx('stf')::text, true);
  perform pg_temp.put('r1', (public.request_invoice_action_v2(pg_temp.fx('i1'), 'refund_full', '[]'::jsonb, 'Testing reason one', null, gen_random_uuid())->>'request_id')::uuid);
  perform pg_temp.put('r2', (public.request_invoice_action_v2(pg_temp.fx('i2'), 'refund_full', '[]'::jsonb, 'Testing reason two', null, gen_random_uuid())->>'request_id')::uuid);
  perform pg_temp.put('r4', (public.request_invoice_action_v2(pg_temp.fx('i4'), 'cancel', '[]'::jsonb, 'Testing reason four', null, gen_random_uuid())->>'request_id')::uuid);
  perform set_config('request.jwt.claim.sub', pg_temp.fx('own')::text, true);
  perform public.resolve_invoice_action_v2(pg_temp.fx('r2'), false, 'Testing rejection');
  insert into public.approval_requests(request_type, status, requested_by, related_record_id, reason, payload)
  values ('adjustment', 'pending', pg_temp.fx('stf'), gen_random_uuid(), 'Testing correction', '{}'::jsonb) returning id into u;
  perform pg_temp.put('radj', u);
  perform set_config('request.jwt.claim.sub', '', true);
end $fx$;
create function pg_temp.mv(inv text, prod text) returns uuid language sql as $$
  select id from public.stock_movements where invoice_id = pg_temp.fx(inv) and product_id = pg_temp.fx(prod) and movement_type::text = 'store_sale' $$;
create function pg_temp.item(inv text, prod text) returns uuid language sql as $$
  select id from public.invoice_items where invoice_id = pg_temp.fx(inv)
     and (product_id = pg_temp.fx(prod) or (prod = 'promo' and promotion_id = pg_temp.fx('promo'))) limit 1 $$;
create function pg_temp.pay(inv text) returns uuid language sql as $$
  select id from public.invoice_payments where invoice_id = pg_temp.fx(inv) order by created_at limit 1 $$;
-- A refund of one line by an Owner, with the given stock answers: [movement, sellable, not returned].
create function pg_temp.refund(inv text, line text, amount numeric, answers jsonb) returns text language plpgsql as $$
declare r jsonb;
begin
  r := public.refund_invoice_recorded(pg_temp.fx(inv),
         jsonb_build_array(jsonb_build_object('invoice_item_id', pg_temp.item(inv, line), 'amount', amount)),
         jsonb_build_array(jsonb_build_object('payment_id', pg_temp.pay(inv), 'amount', amount)),
         coalesce((select jsonb_agg(jsonb_build_object('movement_id', pg_temp.mv(inv, a->>0), 'sellable_quantity', (a->>1)::int,
                                                       'damaged_quantity', 0, 'not_returned_quantity', (a->>2)::int))
                     from jsonb_array_elements(answers) a), '[]'::jsonb),
         'Testing refund', gen_random_uuid());
  return 'refunded ' || (r->>'refunded_amount');
end $$;
-- Line A refunded by half, all its stock answered; then its other half with no answer.
create function pg_temp.refund_twice() returns text language plpgsql as $$
begin
  perform pg_temp.refund('i1', 'pa', 100, '[["pa", 2, 0]]');
  return pg_temp.refund('i1', 'pa', 100, '[]');
end $$;
-- The promotion edited after the sale: its product C replaced by D, so C's deduction is no line's.
create function pg_temp.refund_orphan() returns text language plpgsql as $$
begin
  update public.promotion_items set product_id = pg_temp.fx('pd') where promotion_id = pg_temp.fx('promo') and product_id = pg_temp.fx('pc');
  return pg_temp.refund('i3', 'promo', 300, '[["pc", 1, 0]]');
end $$;
-- Q: how many units an answer may put back (bounded per deduction since 295/496; 542 leaves it).
create function pg_temp.q_twice() returns text language plpgsql as $$
begin
  perform pg_temp.refund('i1', 'pa', 100, '[["pa", 2, 0]]');
  return pg_temp.refund('i1', 'pa', 100, '[["pa", 1, 0]]');
end $$;
create function pg_temp.q_orphan_over() returns text language plpgsql as $$
begin
  update public.promotion_items set product_id = pg_temp.fx('pd') where promotion_id = pg_temp.fx('promo') and product_id = pg_temp.fx('pc');
  return pg_temp.refund('i3', 'promo', 300, '[["pc", 2, 0]]');
end $$;
-- A refused answer records nothing: stock, answers and refunds as they were.
create function pg_temp.q_nothing() returns text language plpgsql as $$
declare q0 int; d0 bigint; r0 bigint; m text;
begin
  select current_qty into q0 from public.store_inventory where store_id = pg_temp.fx('st') and product_id = pg_temp.fx('pa');
  select count(*) into d0 from public.invoice_stock_dispositions where invoice_id = pg_temp.fx('i1');
  select count(*) into r0 from public.invoice_refunds where invoice_id = pg_temp.fx('i1');
  begin
    perform pg_temp.refund('i1', 'pa', 200, '[["pa", 3, 0]]');
    m := 'recorded';
  exception when others then m := sqlerrm;
  end;
  return m || '|' || ((select current_qty from public.store_inventory where store_id = pg_temp.fx('st') and product_id = pg_temp.fx('pa')) = q0)
           || '|' || ((select count(*) from public.invoice_stock_dispositions where invoice_id = pg_temp.fx('i1')) = d0)
           || '|' || ((select count(*) from public.invoice_refunds where invoice_id = pg_temp.fx('i1')) = r0);
end $$;
-- The approval of R1 through Approvals, with the plan's stock: its approval entries.
create function pg_temp.approve_r1() returns text language plpgsql as $$
declare v_plan jsonb; v_stock jsonb;
begin
  v_plan := public.invoice_action_plan(pg_temp.fx('i1'), 'refund_full', '[]'::jsonb);
  select jsonb_agg(jsonb_build_object('movement_id', s->>'movement_id', 'sellable_quantity', (s->>'proposed_sellable')::int,
                                      'damaged_quantity', 0, 'not_returned_quantity', 0)) into v_stock
    from jsonb_array_elements(v_plan->'stock') s;
  perform public.resolve_invoice_action_v2(pg_temp.fx('r1'), true, 'Testing approval', null, '[]'::jsonb, v_stock, false);
  return (select status from public.approval_requests where id = pg_temp.fx('r1')) || '|'
      || (select count(*) from public.audit_logs a where a.table_name = 'approval_requests' and a.record_id = pg_temp.fx('r1') and a.action = 'invoice_action_approved');
end $$;
-- A direct full refund of I1 (both lines, both answers) while R1 waits.
create function pg_temp.direct_refund() returns text language plpgsql as $$
begin
  perform public.refund_invoice_recorded(pg_temp.fx('i1'),
    jsonb_build_array(jsonb_build_object('invoice_item_id', pg_temp.item('i1', 'pa'), 'amount', 200),
                      jsonb_build_object('invoice_item_id', pg_temp.item('i1', 'pb'), 'amount', 100)),
    jsonb_build_array(jsonb_build_object('payment_id', pg_temp.pay('i1'), 'amount', 300)),
    jsonb_build_array(jsonb_build_object('movement_id', pg_temp.mv('i1', 'pa'), 'sellable_quantity', 2, 'damaged_quantity', 0, 'not_returned_quantity', 0),
                      jsonb_build_object('movement_id', pg_temp.mv('i1', 'pb'), 'sellable_quantity', 1, 'damaged_quantity', 0, 'not_returned_quantity', 0)),
    'Testing direct refund', gen_random_uuid());
  return (select status from public.approval_requests where id = pg_temp.fx('r1')) || '|'
      || coalesce((select string_agg(a.new_data->>'direct_action' || ':' || a.store_id::text, ',') from public.audit_logs a
           where a.table_name = 'approval_requests' and a.record_id = pg_temp.fx('r1') and a.action = 'invoice_action_approved'), '');
end $$;
-- A direct cancellation of I4 while R4 waits; and R4 approved through Approvals.
create function pg_temp.direct_cancel() returns text language plpgsql as $$
begin
  perform public.cancel_invoice_recorded(pg_temp.fx('i4'), 'Testing direct cancellation', gen_random_uuid());
  return (select status from public.approval_requests where id = pg_temp.fx('r4')) || '|'
      || coalesce((select string_agg(a.new_data->>'direct_action', ',') from public.audit_logs a
           where a.table_name = 'approval_requests' and a.record_id = pg_temp.fx('r4') and a.action = 'invoice_action_approved'), '');
end $$;
create function pg_temp.approve_r4() returns text language plpgsql as $$
declare v_plan jsonb; v_stock jsonb;
begin
  v_plan := public.invoice_action_plan(pg_temp.fx('i4'), 'cancel', '[]'::jsonb);
  select jsonb_agg(jsonb_build_object('movement_id', s->>'movement_id', 'sellable_quantity', (s->>'proposed_sellable')::int,
                                      'damaged_quantity', 0, 'not_returned_quantity', 0)) into v_stock
    from jsonb_array_elements(v_plan->'stock') s;
  perform public.resolve_invoice_action_v2(pg_temp.fx('r4'), true, 'Testing approval', null, '[]'::jsonb, v_stock, false);
  return (select status from public.approval_requests where id = pg_temp.fx('r4')) || '|'
      || (select count(*) from public.audit_logs a where a.table_name = 'approval_requests' and a.record_id = pg_temp.fx('r4') and a.action = 'invoice_action_approved');
end $$;

create temp table cases(k text primary key, who text, q text);
insert into cases(k, who, q)
select 'D ' || x.n || ' ' || x.who, x.who, format('select (public.invoice_action_request_detail(%L::uuid)->>''reason'')', pg_temp.fx('r1'))
  from (values ('1', 'own'), ('2', 'mgr'), ('3', 'stf'), ('4', 'stfb'), ('5', 'adm'), ('6', 'mgr2'), ('7', 'invm'), ('8', 'service')) x(n, who);
insert into cases(k, who, q)
select 'T ' || x.n || ' ' || x.who, x.who, format('select count(*)::text from public.approval_requests where id = %L::uuid', pg_temp.fx('r1'))
  from (values ('1', 'own'), ('2', 'mgr'), ('3', 'stf'), ('4', 'stfb'), ('5', 'adm'), ('6', 'mgr2')) x(n, who);
insert into cases(k, who, q)
select 'T adj ' || x.who, x.who, format('select count(*)::text from public.approval_requests where id = %L::uuid', pg_temp.fx('radj'))
  from (values ('own'), ('mgr'), ('mgr2'), ('adm'), ('stf'), ('stfb')) x(who);
insert into cases(k, who, q) values
  ('R1 resolved, the store''s Manager', 'mgr', format('select (public.resolve_invoice_action_v2(%L::uuid, true)->>''already_resolved'')', pg_temp.fx('r2'))),
  ('R2 resolved, another store''s Manager', 'mgr2', format('select (public.resolve_invoice_action_v2(%L::uuid, true)->>''already_resolved'')', pg_temp.fx('r2'))),
  ('R3 waiting, another store''s Manager', 'mgr2', format('select (public.resolve_invoice_action_v2(%L::uuid, false, ''x'')->>''status'')', pg_temp.fx('r1'))),
  ('S1 line A, B''s stock answered', 'pg:own', 'select pg_temp.refund(''i1'', ''pa'', 100, ''[["pb", 1, 0]]'')'),
  ('S2 line A, its own stock answered', 'pg:own', 'select pg_temp.refund(''i1'', ''pa'', 100, ''[["pa", 1, 0]]'')'),
  ('S3 line A again, its stock answered already, B''s not', 'pg:own', 'select pg_temp.refund_twice()'),
  ('S4 line A, no answer, its stock unanswered', 'pg:own', 'select pg_temp.refund(''i1'', ''pa'', 100, ''[]'')'),
  ('S5 line B, A''s stock answered as not returned', 'pg:own', 'select pg_temp.refund(''i1'', ''pb'', 100, ''[["pa", 0, 1]]'')'),
  ('S6 a promotion line, its product''s stock', 'pg:own', 'select pg_temp.refund(''i3'', ''promo'', 300, ''[["pc", 1, 0]]'')'),
  ('S7 the product line of I3, the promotion''s stock', 'pg:own', 'select pg_temp.refund(''i3'', ''pa'', 100, ''[["pc", 1, 0]]'')'),
  ('S8 a promotion line, stock no line holds', 'pg:own', 'select pg_temp.refund_orphan()'),
  ('Q1 line A, three units back of the two it took', 'pg:own', 'select pg_temp.refund(''i1'', ''pa'', 200, ''[["pa", 3, 0]]'')'),
  ('Q2 line A again, one more unit after both were answered', 'pg:own', 'select pg_temp.q_twice()'),
  ('Q3 one deduction answered twice in one refund', 'pg:own', 'select pg_temp.refund(''i1'', ''pa'', 200, ''[["pa", 1, 0], ["pa", 1, 0]]'')'),
  ('Q4 stock no line holds, two units of the one taken', 'pg:own', 'select pg_temp.q_orphan_over()'),
  ('Q5 half of line A, both its units back', 'pg:own', 'select pg_temp.refund(''i1'', ''pa'', 100, ''[["pa", 2, 0]]'')'),
  ('Q6 a refused answer records nothing', 'pg:own', 'select pg_temp.q_nothing()'),
  ('E1 R1 approved through Approvals', 'pg:own', 'select pg_temp.approve_r1()'),
  ('E2 a direct full refund while R1 waits', 'pg:own', 'select pg_temp.direct_refund()'),
  ('E3 a direct cancellation while R4 waits', 'pg:own', 'select pg_temp.direct_cancel()'),
  ('E4 R4 approved through Approvals', 'pg:own', 'select pg_temp.approve_r4()');
create temp table res(k text, phase text, v text, primary key (k, phase));

\if :by_us
insert into res select c.k, 'before', pg_temp.as_(c.who, c.q) from cases c order by c.k;
\ir ../../../supabase/542_refund_requests_read_by_their_rule_and_refund_stock_follows_its_lines.sql
\endif
insert into res select c.k, 'after', pg_temp.as_(c.who, c.q) from cases c order by c.k;
create function pg_temp.r(key text) returns text language sql as $$ select v from res where k = key and phase = 'after' $$;
create function pg_temp.rb(key text) returns text language sql as $$ select v from res where k = key and phase = 'before' $$;

-- What changes, and what each case gives after 542.
create temp table expect(k text primary key, after text, before text);
insert into expect values
  ('D 1 own', 'ok:Testing reason one', 'ok:Testing reason one'),
  ('D 2 mgr', 'ok:Testing reason one', 'ok:Testing reason one'),
  ('D 3 stf', 'ok:Testing reason one', 'ok:Testing reason one'),
  ('D 4 stfb', 'ERR P0001 Invoice request not accessible', 'ok:Testing reason one'),
  ('D 5 adm', 'ERR P0001 Invoice request not accessible', 'ok:Testing reason one'),
  ('D 6 mgr2', 'ERR P0001 Invoice request not accessible', 'ERR P0001 Invoice request not accessible'),
  ('D 7 invm', 'ERR 42501 An Inventory Manager works with stock only.', 'ERR 42501 An Inventory Manager works with stock only.'),
  ('D 8 service', 'ERR P0001 Invoice request not accessible', 'ERR P0001 Invoice request not accessible'),
  ('T 1 own', 'ok:1', 'ok:1'), ('T 2 mgr', 'ok:1', 'ok:1'), ('T 3 stf', 'ok:1', 'ok:1'),
  ('T 4 stfb', 'ok:0', 'ok:0'), ('T 5 adm', 'ok:0', 'ok:1'), ('T 6 mgr2', 'ok:0', 'ok:1'),
  ('T adj own', 'ok:1', 'ok:1'), ('T adj mgr', 'ok:1', 'ok:1'), ('T adj mgr2', 'ok:1', 'ok:1'),
  ('T adj adm', 'ok:1', 'ok:1'), ('T adj stf', 'ok:1', 'ok:1'), ('T adj stfb', 'ok:0', 'ok:0'),
  ('R1 resolved, the store''s Manager', 'ok:true', 'ok:true'),
  ('R2 resolved, another store''s Manager', 'ERR P0001 Invoice not accessible', 'ok:true'),
  ('R3 waiting, another store''s Manager', 'ERR P0001 Invoice not accessible', 'ERR P0001 Invoice not accessible'),
  ('S1 line A, B''s stock answered', 'ERR P0001 Answer for the stock of the lines being refunded: "Testing B" is not on a line this refund covers. Nothing was recorded.', 'ok:refunded 100.00'),
  ('S2 line A, its own stock answered', 'ok:refunded 100.00', 'ok:refunded 100.00'),
  ('S3 line A again, its stock answered already, B''s not', 'ok:refunded 100.00', 'ERR P0001 Record the returned-and-sellable, damaged, or not-returned quantities for this product refund'),
  ('S4 line A, no answer, its stock unanswered', 'ERR P0001 Record the returned-and-sellable, damaged, or not-returned quantities for this product refund', 'ERR P0001 Record the returned-and-sellable, damaged, or not-returned quantities for this product refund'),
  ('S5 line B, A''s stock answered as not returned', 'ERR P0001 Answer for the stock of the lines being refunded: "Testing A" is not on a line this refund covers. Nothing was recorded.', 'ok:refunded 100.00'),
  ('S6 a promotion line, its product''s stock', 'ok:refunded 300.00', 'ok:refunded 300.00'),
  ('S7 the product line of I3, the promotion''s stock', 'ERR P0001 Answer for the stock of the lines being refunded: "Testing C" is not on a line this refund covers. Nothing was recorded.', 'ok:refunded 100.00'),
  ('S8 a promotion line, stock no line holds', 'ok:refunded 300.00', 'ok:refunded 300.00'),
  ('Q1 line A, three units back of the two it took', 'ERR P0001 Stock disposition exceeds the unresolved deduction', 'ERR P0001 Stock disposition exceeds the unresolved deduction'),
  ('Q2 line A again, one more unit after both were answered', 'ERR P0001 Stock disposition exceeds the unresolved deduction', 'ERR P0001 Stock disposition exceeds the unresolved deduction'),
  ('Q3 one deduction answered twice in one refund', 'ERR 23505 duplicate key value violates unique constraint "invoice_stock_dispositions_invoice_id_request_id_movement_i_key"', 'ERR 23505 duplicate key value violates unique constraint "invoice_stock_dispositions_invoice_id_request_id_movement_i_key"'),
  ('Q4 stock no line holds, two units of the one taken', 'ERR P0001 Stock disposition exceeds the unresolved deduction', 'ERR P0001 Stock disposition exceeds the unresolved deduction'),
  ('Q5 half of line A, both its units back', 'ok:refunded 100.00', 'ok:refunded 100.00'),
  ('Q6 a refused answer records nothing', 'ok:Stock disposition exceeds the unresolved deduction|true|true|true', 'ok:Stock disposition exceeds the unresolved deduction|true|true|true'),
  ('E1 R1 approved through Approvals', 'ok:approved|1', 'ok:approved|1'),
  ('E2 a direct full refund while R1 waits', 'ok:approved|refund:' || pg_temp.fx('st'), 'ok:approved|'),
  ('E3 a direct cancellation while R4 waits', 'ok:approved|cancellation', 'ok:approved|'),
  ('E4 R4 approved through Approvals', 'ok:approved|1', 'ok:approved|1');
select pg_temp.check(pg_temp.r(e.k) = e.after, e.k || ': ' || coalesce(pg_temp.r(e.k), 'no answer')) from expect e order by e.k;
select pg_temp.check(pg_temp.rb(e.k) = e.before, e.k || ' before 542: ' || coalesce(pg_temp.rb(e.k), 'no answer'))
  from expect e where :'mode' = 'install' order by e.k;
select pg_temp.check(count(*) = 0, 'every case has an expectation') from cases c where c.k not in (select k from expect);

-- ═════ G 542's fixed parts ═════
select pg_temp.check(count(*) = 4, 'G1 the four functions are 542''s, with search_path public, pg_temp and their grants as before: ' || count(*))
  from unnest(array['invoice_action_request_detail(uuid)', 'refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid)',
                    'complete_invoice_finance_request()', 'resolve_invoice_action_v2(uuid,boolean,text,text,jsonb,jsonb,boolean)']) with ordinality s(sig, o)
  join unnest(array['d70250367385b0dec1ea5273d85e796c', '7802bc26966f422978e2b764b289944f',
                    'ce65794aff1f9e1f3953a82012dc377e', 'beb94a98887d55d8698a830f489e1225']) with ordinality m(md5, o) using (o)
  join pg_proc p on p.oid = to_regprocedure('public.' || s.sig)
 where md5(pg_get_functiondef(p.oid)) = m.md5 and p.proconfig = array['search_path=public, pg_temp']
   and p.proacl::text = (select acl from fn0 where fn = s.sig);
select pg_temp.check(md5(pg_get_functiondef(p.oid)) = 'dbec8434a00e2969cf41c7145be440af' and p.proacl::text = '{postgres=X/postgres}'
                 and not has_function_privilege('authenticated', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute')
                 and not has_function_privilege('service_role', p.oid, 'execute') and p.proconfig = array['search_path=public, pg_temp'],
  'G2 invoice_line_holds_stock is 542''s and postgres''s alone')
  from pg_proc p where p.oid = 'public.invoice_line_holds_stock(uuid,uuid)'::regprocedure;
select pg_temp.check(split_part(substr(pg_get_functiondef('public.invoice_action_request_detail(uuid)'::regprocedure),
                       strpos(pg_get_functiondef('public.invoice_action_request_detail(uuid)'::regprocedure), E'begin\n') + 6), E'\n', 1)
                     like '  perform public.inventory_manager_guard(%', 'G3 540''s guard is still the first statement of invoice_action_request_detail');
select pg_temp.check((select count(*) from pg_policy p where p.polrelid = 'public.approval_requests'::regclass) = 1
                 and (select pg_get_expr(p.polqual, p.polrelid) from pg_policy p where p.polrelid = 'public.approval_requests'::regclass) like '%request_type = ANY (ARRAY[''invoice_cancel''::text, ''invoice_refund''::text])%',
  'G4 approval_requests has its one read rule, 542''s');
\if :by_us
select pg_temp.check((select count(*) from (select fn, md5, acl from fn0 except
                                            select p.oid::regprocedure::text, md5(pg_get_functiondef(p.oid)), p.proacl::text
                                              from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p')) x) = 4
                 and (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p')) = (select count(*) from fn0) + 1,
  'G5 542 changed exactly four functions and made one');
select pg_temp.check((select count(*) from (select * from pol0 except
                                            select c.relname, p.polname, pg_get_expr(p.polqual, p.polrelid)
                                              from pg_policy p join pg_class c on c.oid = p.polrelid where c.relnamespace = 'public'::regnamespace) x) = 1,
  'G6 542 changed exactly one read rule');

-- ═════ U the undo, and M ═════
savepoint u1;
\ir ../undo-542.sql
select pg_temp.check(not exists (select fn, md5, acl from fn0 except
                                 select p.oid::regprocedure::text, md5(pg_get_functiondef(p.oid)), p.proacl::text
                                   from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p'))
                 and (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p')) = (select count(*) from fn0)
                 and not exists (select * from pol0 except
                                 select c.relname, p.polname, pg_get_expr(p.polqual, p.polrelid)
                                   from pg_policy p join pg_class c on c.oid = p.polrelid where c.relnamespace = 'public'::regnamespace),
  'U1 the undo puts every function and read rule back exactly as before 542');
savepoint u2;
\set ON_ERROR_STOP off
\ir ../undo-542.sql
\set ON_ERROR_STOP on
rollback to savepoint u2;
select pg_temp.check(:'LAST_ERROR_MESSAGE' like 'undo 542: % is already its version of before 542%', 'U2 a second undo refuses: ' || :'LAST_ERROR_MESSAGE');
\ir ../../../supabase/542_refund_requests_read_by_their_rule_and_refund_stock_follows_its_lines.sql
select pg_temp.check(md5(pg_get_functiondef('public.refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid)'::regprocedure)) = '7802bc26966f422978e2b764b289944f'
                 and to_regprocedure('public.invoice_line_holds_stock(uuid,uuid)') is not null, 'U3 542 after the undo makes the same again');
rollback to savepoint u1;
savepoint m1;
\set ON_ERROR_STOP off
\ir ../../../supabase/542_refund_requests_read_by_their_rule_and_refund_stock_follows_its_lines.sql
\set ON_ERROR_STOP on
rollback to savepoint m1;
select pg_temp.check(:'LAST_ERROR_MESSAGE' like '542 is already in on this database%', 'M1 542 a second time refuses: ' || :'LAST_ERROR_MESSAGE');
\else
\echo NOTE  B, G5, G6, U and M are skipped (542 was not installed by this file)
\endif

do $$ begin
  if (select count(*) from failed) > 0 then
    raise exception '% check(s) failed: %', (select count(*) from failed), (select string_agg(msg, E'\n' order by n) from failed);
  end if;
  raise notice 'ALL PASSED';
end $$;
rollback;
