-- The Low findings L13, L14, L16 and L19 of the security audit of 17 Nov 2026 (541): pictures only,
-- and no SVG, in the two upload buckets; one active-staff test (require_active_staff) in twelve
-- functions; a send is logged against a document the caller can see, with its own number and
-- customer; a loan comes back where it was lent from unless an Owner or a Manager says otherwise
-- (the user, 26 Nov 2026); a TikTok file has at most 20,000 rows; a price change logs the old price;
-- a Manager's company-wide user management is kept (R2).
--
-- Calls are made as the pages make them: a signed-in login (the authenticated role, its JWT), or
-- as a server function runs (the database owner with the login's claims, "pg:"), or the secret key
-- ("service"). Each call is rolled back on its own. The logins: an Owner, a Manager of the store, a
-- Manager of no store, Staff of the store, Staff of another store, an Inventory Manager, and two
-- made-up states that require_active_staff() refuses but the older tests let by: an Owner and a
-- Staff member switched on with an invitation still pending, and a Staff member deleted but still
-- switched on. Made-up rows: three stores (one closed), two warehouses, a product, two customers, a
-- paid and an unpaid invoice, a special sale, a rental, a loan at the store and one at a warehouse.
--
--   B  (install mode) every case below, as it answers before 541, kept to compare.
--   A  L14: each of the twelve functions answers active staff, other roles and the secret key
--      exactly as before 541; the pending and the deleted logins are refused (or, for the two that
--      answer, get "no"), where before they got through.
--   S  L16: the send log takes the number and customer from the document; refuses another store's
--      invoice, a missing or deleted document, no document, an unknown kind (22023) and the secret
--      key; a special sale and a rental follow their read rules (a Manager of no store logs them,
--      but not an invoice of a store not theirs).
--   L  L19 loans: back into its own store, by Staff; into another store: refused for Staff, allowed
--      for a Manager and an Owner (the stock lands there and the event row says so); a warehouse:
--      the permission as before; used and lost as before; a closed store refused as before.
--   K  L19 TikTok: an order file and a settlement file (its lines, and its Withdrawal records) of
--      20,001 rows refused (54000), 20,000 staged, the access check still first.
--   P  L19 prices: the change log's old_data carries the price before (none for a first price,
--      removed: true for a price taken off the list); new_data as before.
--   G  541's fixed parts: the buckets' rules (store-assets PNG/JPEG/WebP up to 5 MB;
--      survey-attachments without image/* or SVG, its documents and 10 MB as before; invoice-pdfs
--      as before), the 18 functions' AFTER md5s, grants and search path public, pg_temp; no other
--      function changed; "update profiles" (R2) unchanged.
--   U  scripts/permissions/undo-541.sql puts everything back exactly; a second undo refuses; 541
--      again makes the same.
--   M  541 a second time refuses.
--
-- Disposable local database only; everything is rolled back. Every name and number is invented
-- (Testing ..., @example.invalid; phones +61 491 570 nnn). Run it on a copy of production with 540
-- and without 541 (it applies 541, then again); with -v skip_install=1 where 541 is in (B, U and M
-- skipped).
--   psql -X -v ON_ERROR_STOP=1 -f scripts/permissions/tests/security-lows-541.sql
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '10s';
set local statement_timeout = '900s';
create temp table fn0 as
  select p.oid::regprocedure::text as fn, md5(pg_get_functiondef(p.oid)) as md5, p.proacl::text as acl
    from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p');
create temp table bk0 as select id, public, file_size_limit, allowed_mime_types from storage.buckets;
select to_regprocedure('public.inventory_manager_guard(text)') is not null as had540,
       md5(pg_get_functiondef('public.record_document_send(text,text,text,uuid,uuid,text,text,text,text)'::regprocedure))
         = 'a7fd9efd60794d3c2f5595b328ce7a75' as had541 \gset
\if :had540
\else
\echo 540 is not in: 541 needs it
select 1/0;
\endif
\if :{?skip_install}
\if :had541
\else
\echo 541 is not in: run without -v skip_install
select 1/0;
\endif
\set mode skip
\elif :had541
\echo 541 is already in: run with -v skip_install=1
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
create function pg_temp.ph(n int) returns text language sql as
$$ select '+61491570' || lpad((((select ph from sfx) + n) % 1000)::text, 3, '0') $$;
create function pg_temp.claims(who text) returns void language plpgsql as $f$
begin
  perform set_config('request.jwt.claim.sub', coalesce(pg_temp.fx(who)::text, ''), true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', pg_temp.fx(who), 'role', 'authenticated')::text, true);
end $f$;
-- Runs q and rolls back whatever it did: 'ok:<answer>' or 'ERR <sqlstate> <message>'.
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
declare r record; u uuid; t text := pg_temp.tok();
begin
  insert into public.app_settings(id) values (true) on conflict do nothing;
  insert into public.stores(name, code, country_code) values ('Testing Store A', 'T541A' || upper(substr(md5(t), 1, 4)), 'SG') returning id into u; perform pg_temp.put('st', u);
  insert into public.stores(name, code, country_code) values ('Testing Store B', 'T541B' || upper(substr(md5(t), 1, 4)), 'SG') returning id into u; perform pg_temp.put('st2', u);
  insert into public.stores(name, code, country_code, is_active) values ('Testing Store Closed', 'T541C' || upper(substr(md5(t), 1, 4)), 'SG', false) returning id into u; perform pg_temp.put('st3', u);
  insert into public.warehouses(name, code) values ('Testing Warehouse A', 'W541A' || upper(substr(md5(t), 1, 4))) returning id into u; perform pg_temp.put('wh', u);
  insert into public.warehouses(name, code) values ('Testing Warehouse B', 'W541B' || upper(substr(md5(t), 1, 4))) returning id into u; perform pg_temp.put('wh2', u);
  -- k, role, invitation, deleted, store
  for r in select * from (values
      ('own', 'owner', 'accepted', false, null), ('mgr', 'manager', 'accepted', false, 'st'),
      ('mgr0', 'manager', 'accepted', false, null), ('stf', 'staff', 'accepted', false, 'st'),
      ('stf2', 'staff', 'accepted', false, 'st2'), ('invm', 'inventory_manager', 'accepted', false, 'st'),
      ('adm', 'admin', 'accepted', false, null),
      ('pendo', 'owner', 'pending', false, null), ('pend', 'staff', 'pending', false, 'st'),
      ('gone', 'staff', 'accepted', true, 'st')) x(k, role, inv, del, store) loop
    insert into auth.users(id, email, email_confirmed_at) values (gen_random_uuid(), 'm541-' || r.k || '-' || md5(t) || '@example.invalid', now()) returning id into u;
    insert into public.profiles(id, full_name, email, role, is_active, invitation_status, deleted_at)
    values (u, 'Testing ' || r.k, 'm541-' || r.k || '-' || md5(t) || '@example.invalid', r.role::public.user_role, true, r.inv,
            case when r.del then now() end);
    perform pg_temp.put(r.k, u);
    if r.store is not null then
      insert into public.user_store_assignments(user_id, store_id) values (u, pg_temp.fx(r.store));
    end if;
  end loop;
  perform set_config('request.jwt.claim.sub', pg_temp.fx('own')::text, true);
  insert into public.products(name, sku, product_type) values ('Testing Item', 'T541-' || md5(t), 'own') returning id into u; perform pg_temp.put('p', u);
  insert into public.store_inventory(store_id, product_id, current_qty) values (pg_temp.fx('st'), u, 50), (pg_temp.fx('st2'), u, 50);
  insert into public.warehouse_inventory(warehouse_id, product_id, current_qty) values (pg_temp.fx('wh'), u, 50), (pg_temp.fx('wh2'), u, 50);
  perform public.set_product_prices(pg_temp.fx('st'), u, 100, 100, 'available');
  perform set_config('request.jwt.claim.sub', '', true);
  insert into public.payment_methods(name, is_active) values ('Testing Cash ' || md5(t), true) returning id into u; perform pg_temp.put('pm', u);
  insert into public.customers(full_name, first_name, last_name, phone, email) values ('Testing ' || t || ' One', 'Testing', t || ' One', pg_temp.ph(1), t || '-c1@example.invalid') returning id into u; perform pg_temp.put('c1', u);
  insert into public.customers(full_name, first_name, last_name, phone, email) values ('Testing ' || t || ' Two', 'Testing', t || ' Two', pg_temp.ph(2), t || '-c2@example.invalid') returning id into u; perform pg_temp.put('c2', u);
  insert into public.special_products(name, sku) values ('Testing Special', 'T541S-' || md5(t)) returning id into u; perform pg_temp.put('sp', u);
  insert into public.special_sales(sale_no, special_product_id, quantity, customer_id, store_id, source_type, source_store_id)
  values ('SS-9001-' || t, pg_temp.fx('sp'), 1, pg_temp.fx('c1'), pg_temp.fx('st'), 'store', pg_temp.fx('st')) returning id into u; perform pg_temp.put('ss', u);
  insert into public.rentals(rental_no, special_product_id, customer_id, quantity, rate_type, periods, start_date, expected_return_date, store_id, source_store_id)
  values ('RN-9001-' || t, pg_temp.fx('sp'), pg_temp.fx('c1'), 1, (enum_range(null::public.special_rate_type))[1], 1, public.sg_today(), public.sg_today() + 7,
          pg_temp.fx('st'), pg_temp.fx('st')) returning id into u; perform pg_temp.put('rn', u);
end $fx$;
create function pg_temp.must(who text, q text) returns text language plpgsql as $f$
declare v text;
begin
  perform pg_temp.claims(who);
  execute 'set local role authenticated';
  execute q into v;
  execute 'reset role';
  perform set_config('request.jwt.claim.sub', '', true);
  return v;
end $f$;
select pg_temp.put('i1', pg_temp.must('stf', format('select public.create_invoice_with_details(%L::uuid, %L::uuid, %L::jsonb, %L::jsonb)::text',
  pg_temp.fx('st'), pg_temp.fx('c1'), jsonb_build_array(jsonb_build_object('kind', 'product', 'product_id', pg_temp.fx('p'), 'quantity', 1)),
  jsonb_build_object('business_date', public.sg_today())))::uuid) \g /dev/null
select pg_temp.must('stf', format('select public.record_invoice_settlement(%L::uuid, %L::jsonb, %L::uuid)::text', pg_temp.fx('i1'),
  jsonb_build_object('receipts', jsonb_build_array(jsonb_build_object('key', 'line-0', 'payment_method_id', pg_temp.fx('pm'),
    'amount', (select total_amount from public.invoices where id = pg_temp.fx('i1')), 'payment_date', public.sg_today()::text)), 'arrangements', '[]'::jsonb),
  gen_random_uuid())) \g /dev/null
select pg_temp.put('i2', pg_temp.must('stf', format('select public.create_invoice_with_details(%L::uuid, %L::uuid, %L::jsonb, %L::jsonb)::text',
  pg_temp.fx('st'), pg_temp.fx('c1'), jsonb_build_array(jsonb_build_object('kind', 'product', 'product_id', pg_temp.fx('p'), 'quantity', 1)),
  jsonb_build_object('business_date', public.sg_today())))::uuid) \g /dev/null
select pg_temp.must('stf', format('select public.lend_stock(%L, %L::uuid, %L::jsonb, public.sg_today() + 7, %L::uuid, null, %L, gen_random_uuid())::text',
  'store', pg_temp.fx('st'), jsonb_build_array(jsonb_build_object('product_id', pg_temp.fx('p'), 'quantity', 2)), pg_temp.fx('c1'), 'Trial')) \g /dev/null
select pg_temp.must('mgr', format('select public.lend_stock(%L, %L::uuid, %L::jsonb, public.sg_today() + 7, null, %L, %L, gen_random_uuid())::text',
  'warehouse', pg_temp.fx('wh'), jsonb_build_array(jsonb_build_object('product_id', pg_temp.fx('p'), 'quantity', 2)), 'Testing ' || pg_temp.tok() || ' Typed', 'Trial')) \g /dev/null
select pg_temp.put('l1', (select id from public.stock_loans where customer_id = pg_temp.fx('c1') limit 1)) \g /dev/null
select pg_temp.put('l2', (select id from public.stock_loans where borrower_name = 'Testing ' || pg_temp.tok() || ' Typed' limit 1)) \g /dev/null

-- A take-back of one unit of a loan: outcome, and for a return the place.
create function pg_temp.back(loan text, outcome text, loc_type text, loc text) returns text language sql as $$
  select format('select public.return_stock_loan(%L::uuid, %L::jsonb, null, gen_random_uuid())::text', pg_temp.fx(loan),
    jsonb_build_array(jsonb_build_object('line_id', (select id from public.stock_loan_lines where loan_id = pg_temp.fx(loan) limit 1),
      'outcome', outcome, 'quantity', 1)
      || case when outcome = 'returned' then jsonb_build_object('condition', 'good', 'location_type', loc_type, 'location_id', pg_temp.fx(loc))
              else '{}'::jsonb end)) $$;
-- A send, then the row it wrote (as a server function runs it, so the row can be read back).
create function pg_temp.send_read(kind text, doc uuid) returns text language plpgsql as $$
declare v uuid;
begin
  v := public.record_document_send(kind, 'INV-9001-NOT-IT', 'whatsapp', doc, pg_temp.fx('c2'), pg_temp.ph(9));
  return (select coalesce(d.doc_no, '') || '|' || coalesce(d.customer_id::text, '') || '|' || coalesce(d.sent_by::text, '')
            from public.document_sends d where d.id = v);
end $$;
create function pg_temp.send_deleted() returns text language plpgsql as $$
begin
  update public.invoices set deleted_at = now() where id = pg_temp.fx('i1');
  return pg_temp.send_read('invoice', pg_temp.fx('i1'));
end $$;
-- A return as a Manager into another store: what landed where.
create function pg_temp.back_elsewhere() returns text language plpgsql as $$
declare q0 int; q1 int; r jsonb;
begin
  select current_qty into q0 from public.store_inventory where store_id = pg_temp.fx('st2') and product_id = pg_temp.fx('p');
  execute pg_temp.back('l1', 'returned', 'store', 'st2') into r;
  select current_qty into q1 from public.store_inventory where store_id = pg_temp.fx('st2') and product_id = pg_temp.fx('p');
  return (q1 - q0)::text || '|' || (select count(*) from public.stock_loan_events e where e.loan_id = pg_temp.fx('l1')
                                     and e.outcome = 'returned' and e.location_type = 'store' and e.store_id = pg_temp.fx('st2'))::text;
end $$;
-- A price change and what the change log says.
create function pg_temp.price_log(store text, removed_first boolean) returns text language plpgsql as $$
declare v_seen uuid[];
begin
  if removed_first then
    update public.store_product_prices set deleted_at = now() where store_id = pg_temp.fx(store) and product_id = pg_temp.fx('p');
  end if;
  -- The entries already there (one transaction: they share its time), so the new one is found by id.
  select coalesce(array_agg(a.id), '{}') into v_seen from public.audit_logs a where a.action = 'product_prices_set' and a.record_id = pg_temp.fx('p');
  perform public.set_product_prices(pg_temp.fx(store), pg_temp.fx('p'), 120, 120, 'available');
  return (select string_agg(coalesce(a.old_data::text, 'null') || ' => ' || a.new_data::text, ' ; ') from public.audit_logs a
           where a.action = 'product_prices_set' and a.record_id = pg_temp.fx('p') and a.id <> all (v_seen));
end $$;
create function pg_temp.srows(n int) returns jsonb language sql as $$
  select jsonb_agg(jsonb_build_object('order_adjustment_id', 'T541S-' || g, 'type', 'Order', 'order_id', 'T541-' || g, 'total_settlement_amount', '1.00'))
    from generate_series(1, n) g $$;
create function pg_temp.brows(n int) returns jsonb language sql as $$
  select jsonb_agg(jsonb_build_object('transaction_type', 'Payments', 'reference_id', 'T541R-' || g, 'amount', '1.00'))
    from generate_series(1, n) g $$;
-- A settlement file as the page sends it: what was staged.
create function pg_temp.settle_file(n int, nb int) returns text language plpgsql as $$
declare b uuid;
begin
  b := public.stage_tiktok_settlement_file(pg_temp.fx('st'), 's.xlsx', 'Order details', pg_temp.srows(n), coalesce(pg_temp.brows(nb), '[]'::jsonb));
  return (select count(*) from public.tiktok_settlement_rows r where r.batch_id = b) || '|'
      || (select count(*) from public.tiktok_balance_records r where r.batch_id = b);
end $$;
create function pg_temp.rows(n int) returns jsonb language sql as $$
  select jsonb_agg(jsonb_build_object('order_id', 'T541-' || g, 'seller_sku', 'T541-SKU', 'quantity', '1', 'order_status', 'Shipped'))
    from generate_series(1, n) g $$;

-- The cases: key, who, query, when (b: before and after; a: after only).
create temp table cases(k text primary key, who text, q text, phase text default 'b');
insert into cases(k, who, q) values
  ('A01 portal login, Owner', 'own', format('select public.affiliate_portal_login(%L::uuid)::text', pg_temp.fx('c1'))),
  ('A02 portal login, Staff', 'stf', format('select public.affiliate_portal_login(%L::uuid)::text', pg_temp.fx('c1'))),
  ('A03 portal login, pending Owner', 'pendo', format('select public.affiliate_portal_login(%L::uuid)::text', pg_temp.fx('c1'))),
  ('A04 portal login, secret key', 'service', format('select public.affiliate_portal_login(%L::uuid)::text', pg_temp.fx('c1'))),
  ('A05 unlink, Owner', 'own', format('select public.unlink_affiliate_account(%L::uuid, %L)::text', pg_temp.fx('c1'), 'Testing reason')),
  ('A06 unlink, Manager', 'mgr', format('select public.unlink_affiliate_account(%L::uuid, %L)::text', pg_temp.fx('c1'), 'Testing reason')),
  ('A07 unlink, pending Owner', 'pendo', format('select public.unlink_affiliate_account(%L::uuid, %L)::text', pg_temp.fx('c1'), 'Testing reason')),
  ('A08 unlink, secret key', 'service', format('select public.unlink_affiliate_account(%L::uuid, %L)::text', pg_temp.fx('c1'), 'Testing reason')),
  ('A09 TikTok payouts, Owner', 'own', 'select public.tiktok_bank_payouts(public.sg_today() - 30, public.sg_today())::text'),
  ('A10 TikTok payouts, Staff', 'stf', 'select public.tiktok_bank_payouts(public.sg_today() - 30, public.sg_today())::text'),
  ('A11 TikTok payouts, pending Owner', 'pendo', 'select public.tiktok_bank_payouts(public.sg_today() - 30, public.sg_today())::text'),
  ('A12 TikTok payouts, secret key', 'service', 'select public.tiktok_bank_payouts(public.sg_today() - 30, public.sg_today())::text'),
  ('A13 TikTok Xero, Manager', 'mgr', 'select public.tiktok_xero_payouts(2026, 10)::text'),
  ('A14 TikTok Xero, Staff', 'stf', 'select public.tiktok_xero_payouts(2026, 10)::text'),
  ('A15 TikTok Xero, pending Owner', 'pendo', 'select public.tiktok_xero_payouts(2026, 10)::text'),
  ('A16 TikTok Xero, secret key', 'service', 'select public.tiktok_xero_payouts(2026, 10)::text'),
  ('A17 Stock History filters, Staff', 'stf', 'select public.stock_history_options(''types'', '''', 0)::text'),
  ('A18 Stock History filters, Inventory Manager', 'invm', 'select public.stock_history_options(''types'', '''', 0)::text'),
  ('A19 Stock History filters, pending Staff', 'pend', 'select public.stock_history_options(''types'', '''', 0)::text'),
  ('A20 Stock History filters, secret key', 'service', 'select public.stock_history_options(''types'', '''', 0)::text'),
  ('A21 customer match, Staff', 'stf', format('select public.customer_match_candidates(%L, null)::text', pg_temp.ph(1))),
  ('A22 customer match, pending Staff', 'pend', format('select public.customer_match_candidates(%L, null)::text', pg_temp.ph(1))),
  ('A23 customer match, secret key', 'service', format('select public.customer_match_candidates(%L, null)::text', pg_temp.ph(1))),
  ('A24 customer match, Inventory Manager', 'invm', format('select public.customer_match_candidates(%L, null)::text', pg_temp.ph(1))),
  ('A25 affiliate directory, Staff', 'stf', 'select public.affiliate_staff_directory(null, 50, 0)::text'),
  ('A26 affiliate directory, pending Staff', 'pend', 'select public.affiliate_staff_directory(null, 50, 0)::text'),
  ('A27 affiliate directory, secret key', 'service', 'select public.affiliate_staff_directory(null, 50, 0)::text'),
  ('A28 hand over, Staff', 'stf', format('select (public.record_invoice_handover(%L::uuid, %L::jsonb, gen_random_uuid()) is not null)::text',
     pg_temp.fx('i2'), jsonb_build_object('items', jsonb_build_array(jsonb_build_object('product_id', pg_temp.fx('p'), 'qty', 1))))),
  ('A29 hand over, pending Staff', 'pend', format('select (public.record_invoice_handover(%L::uuid, %L::jsonb, gen_random_uuid()) is not null)::text',
     pg_temp.fx('i2'), jsonb_build_object('items', jsonb_build_array(jsonb_build_object('product_id', pg_temp.fx('p'), 'qty', 1))))),
  ('A30 hand over, secret key', 'service', format('select (public.record_invoice_handover(%L::uuid, %L::jsonb, gen_random_uuid()) is not null)::text',
     pg_temp.fx('i2'), jsonb_build_object('items', jsonb_build_array(jsonb_build_object('product_id', pg_temp.fx('p'), 'qty', 1))))),
  ('A31 settlement, Staff', 'stf', format('select (public.record_invoice_settlement(%L::uuid, %L::jsonb, gen_random_uuid()) is not null)::text', pg_temp.fx('i2'),
     jsonb_build_object('receipts', jsonb_build_array(jsonb_build_object('key', 'line-0', 'payment_method_id', pg_temp.fx('pm'), 'amount', 100, 'payment_date', public.sg_today()::text)), 'arrangements', '[]'::jsonb))),
  ('A32 settlement, pending Staff', 'pend', format('select (public.record_invoice_settlement(%L::uuid, %L::jsonb, gen_random_uuid()) is not null)::text', pg_temp.fx('i2'),
     jsonb_build_object('receipts', jsonb_build_array(jsonb_build_object('key', 'line-0', 'payment_method_id', pg_temp.fx('pm'), 'amount', 100, 'payment_date', public.sg_today()::text)), 'arrangements', '[]'::jsonb))),
  ('A33 settlement, secret key', 'service', format('select (public.record_invoice_settlement(%L::uuid, %L::jsonb, gen_random_uuid()) is not null)::text', pg_temp.fx('i2'),
     jsonb_build_object('receipts', jsonb_build_array(jsonb_build_object('key', 'line-0', 'payment_method_id', pg_temp.fx('pm'), 'amount', 100, 'payment_date', public.sg_today()::text)), 'arrangements', '[]'::jsonb))),
  ('A34 important, Staff', 'stf', format('select public.set_product_important(%L::uuid, true)::text', pg_temp.fx('p'))),
  ('A35 important, pending Staff', 'pend', format('select public.set_product_important(%L::uuid, true)::text', pg_temp.fx('p'))),
  ('A36 important, deleted Staff', 'gone', format('select public.set_product_important(%L::uuid, true)::text', pg_temp.fx('p'))),
  ('A37 important, secret key', 'service', format('select public.set_product_important(%L::uuid, true)::text', pg_temp.fx('p'))),
  ('A38 may correct, Staff', 'stf', format('select public.staff_may_correct_invoice(%L::uuid)::text', pg_temp.fx('i1'))),
  ('A39 may correct, Owner', 'own', format('select public.staff_may_correct_invoice(%L::uuid)::text', pg_temp.fx('i1'))),
  ('A40 may correct, pending Staff', 'pend', format('select public.staff_may_correct_invoice(%L::uuid)::text', pg_temp.fx('i1'))),
  ('A41 may correct, deleted Staff', 'gone', format('select public.staff_may_correct_invoice(%L::uuid)::text', pg_temp.fx('i1'))),
  ('A42 my stores, Staff', 'stf', 'select string_agg(store_name || ''/'' || is_default, '','' order by store_name) from public.my_assigned_stores() where store_name like ''Testing Store%'''),
  ('A43 my stores, Owner', 'own', 'select string_agg(store_name, '','' order by store_name) from public.my_assigned_stores() where store_name like ''Testing Store%'''),
  ('A44 my stores, pending Staff', 'pend', 'select coalesce(string_agg(store_name, '',''), ''none'') from public.my_assigned_stores()'),
  ('A45 my stores, deleted Staff', 'gone', 'select coalesce(string_agg(store_name, '',''), ''none'') from public.my_assigned_stores()'),
  ('A46 my stores, secret key', 'service', 'select coalesce(string_agg(store_name, '',''), ''none'') from public.my_assigned_stores()'),
  ('S01 send, Staff of the store', 'pg:stf', format('select pg_temp.send_read(''invoice'', %L::uuid)', pg_temp.fx('i1'))),
  ('S02 send, Staff of another store', 'pg:stf2', format('select pg_temp.send_read(''invoice'', %L::uuid)', pg_temp.fx('i1'))),
  ('S03 send, Owner', 'pg:own', format('select pg_temp.send_read(''invoice'', %L::uuid)', pg_temp.fx('i1'))),
  ('S04 send, a Manager of no store, invoice', 'pg:mgr0', format('select pg_temp.send_read(''invoice'', %L::uuid)', pg_temp.fx('i1'))),
  ('S05 send, no such document', 'pg:stf', 'select pg_temp.send_read(''invoice'', gen_random_uuid())'),
  ('S06 send, no document', 'pg:stf', 'select pg_temp.send_read(''invoice'', null)'),
  ('S07 send, unknown kind', 'pg:stf', format('select pg_temp.send_read(''receipt'', %L::uuid)', pg_temp.fx('i1'))),
  ('S08 send, deleted invoice', 'pg:stf', 'select pg_temp.send_deleted()'),
  ('S09 send, special sale, Staff of the store', 'pg:stf', format('select pg_temp.send_read(''special_sale'', %L::uuid)', pg_temp.fx('ss'))),
  ('S10 send, special sale, Staff of another store', 'pg:stf2', format('select pg_temp.send_read(''special_sale'', %L::uuid)', pg_temp.fx('ss'))),
  ('S11 send, special sale, a Manager of no store', 'pg:mgr0', format('select pg_temp.send_read(''special_sale'', %L::uuid)', pg_temp.fx('ss'))),
  ('S12 send, rental, Staff of the store', 'pg:stf', format('select pg_temp.send_read(''rental'', %L::uuid)', pg_temp.fx('rn'))),
  ('S13 send, rental, Staff of another store', 'pg:stf2', format('select pg_temp.send_read(''rental'', %L::uuid)', pg_temp.fx('rn'))),
  ('S14 send, secret key', 'service', format('select public.record_document_send(''invoice'', ''INV-9001-NOT-IT'', ''whatsapp'', %L::uuid)::text', pg_temp.fx('i1'))),
  ('S15 send, Inventory Manager', 'invm', format('select public.record_document_send(''invoice'', ''INV-9001-NOT-IT'', ''whatsapp'', %L::uuid)::text', pg_temp.fx('i1'))),
  ('S16 send, as the page sends it', 'stf', format('select (public.record_document_send(''invoice'', %L, ''whatsapp'', %L::uuid, %L::uuid, %L, null, ''sent'', null) is not null)::text',
     (select invoice_no from public.invoices where id = pg_temp.fx('i1')), pg_temp.fx('i1'), pg_temp.fx('c1'), pg_temp.ph(1))),
  ('L01 back to its store, Staff', 'stf', pg_temp.back('l1', 'returned', 'store', 'st')),
  ('L02 into another store, Staff', 'stf', pg_temp.back('l1', 'returned', 'store', 'st2')),
  ('L03 into another store, Manager', 'pg:mgr', 'select pg_temp.back_elsewhere()'),
  ('L04 into another store, Owner', 'own', pg_temp.back('l1', 'returned', 'store', 'st2')),
  ('L05 into a warehouse, Staff', 'stf', pg_temp.back('l1', 'returned', 'warehouse', 'wh')),
  ('L06 into a warehouse, Owner', 'own', pg_temp.back('l1', 'returned', 'warehouse', 'wh')),
  ('L07 warehouse loan into another warehouse, Manager', 'mgr', pg_temp.back('l2', 'returned', 'warehouse', 'wh2')),
  ('L08 warehouse loan back to its warehouse, Manager', 'mgr', pg_temp.back('l2', 'returned', 'warehouse', 'wh')),
  ('L09 used, Staff', 'stf', pg_temp.back('l1', 'used', null, null)),
  ('L10 lost, Staff', 'stf', pg_temp.back('l1', 'lost', null, null)),
  ('L11 into a closed store, Manager', 'mgr', pg_temp.back('l1', 'returned', 'store', 'st3')),
  ('L12 into a store, Inventory Manager', 'invm', pg_temp.back('l1', 'returned', 'store', 'st')),
  ('L13 into another store, Admin', 'adm', pg_temp.back('l1', 'returned', 'store', 'st2')),
  ('L14 back to its store, Admin', 'adm', pg_temp.back('l1', 'returned', 'store', 'st')),
  ('L15 into a warehouse, Admin', 'adm', pg_temp.back('l1', 'returned', 'warehouse', 'wh')),
  ('L17 a warehouse loan, Admin', 'adm', pg_temp.back('l2', 'returned', 'warehouse', 'wh')),
  ('L16 into another store, secret key', 'service', pg_temp.back('l1', 'returned', 'store', 'st2')),
  ('P01 first price at a store', 'pg:own', 'select pg_temp.price_log(''st2'', false)'),
  ('P02 a price changed', 'pg:own', 'select pg_temp.price_log(''st'', false)'),
  ('P03 a price taken off the list, set again', 'pg:own', 'select pg_temp.price_log(''st'', true)');
insert into cases(k, who, q, phase) values
  ('K01 20,001 rows', 'own', format('select public.stage_tiktok_orders(%L::uuid, ''t.xlsx'', ''Sheet1'', pg_temp.rows(20001))::text', pg_temp.fx('st')), 'a'),
  ('K02 20,000 rows', 'pg:own', format('select (public.stage_tiktok_orders(%L::uuid, ''t.xlsx'', ''Sheet1'', pg_temp.rows(20000)) is not null)::text', pg_temp.fx('st')), 'a'),
  ('K03 20,001 rows, Staff of another store', 'pg:stf2', format('select public.stage_tiktok_orders(%L::uuid, ''t.xlsx'', ''Sheet1'', pg_temp.rows(20001))::text', pg_temp.fx('st')), 'a'),
  ('K04 three rows, Staff', 'pg:stf', format('select (public.stage_tiktok_orders(%L::uuid, ''t.xlsx'', ''Sheet1'', pg_temp.rows(3)) is not null)::text', pg_temp.fx('st')), 'b'),
  ('K05 settlement file, 20,001 lines', 'pg:own', 'select pg_temp.settle_file(20001, 3)', 'a'),
  ('K06 settlement file, 20,001 Withdrawal records', 'pg:own', 'select pg_temp.settle_file(3, 20001)', 'a'),
  ('K07 settled lines alone, 20,001', 'pg:own', format('select public.stage_tiktok_settlement(%L::uuid, ''s.xlsx'', ''Order details'', pg_temp.srows(20001))::text', pg_temp.fx('st')), 'a'),
  ('K08 settlement file, 20,000 lines and 20,000 Withdrawal records', 'pg:own', 'select pg_temp.settle_file(20000, 20000)', 'a'),
  ('K09 settlement file, 20,001 Withdrawal records, Staff of another store', 'pg:stf2', 'select pg_temp.settle_file(3, 20001)', 'a'),
  ('K10 settlement file, three lines and three records, Staff', 'pg:stf', 'select pg_temp.settle_file(3, 3)', 'b');
-- K01 as a signed-in login cannot call pg_temp.rows: the rows are made first.
update cases set who = 'pg:own' where k = 'K01 20,001 rows';
create temp table res(k text, phase text, v text, primary key (k, phase));

-- ═════ B Before 541 (install mode only) ═════
\if :by_us
insert into res select c.k, 'before', pg_temp.as_(c.who, c.q) from cases c where c.phase = 'b' order by c.k;
\ir ../../../supabase/541_lows_upload_rules_staff_test_send_log_loans_tiktok_prices.sql
select pg_temp.check((select v from res where k = 'A03 portal login, pending Owner' and phase = 'before') like 'ok:%',
  'B1 before 541 an Owner switched on with a pending invitation passes the older test: ' || (select v from res where k = 'A03 portal login, pending Owner' and phase = 'before'));
select pg_temp.check((select v from res where k = 'A45 my stores, deleted Staff' and phase = 'before') = 'ok:Testing Store A',
  'B2 before 541 a deleted Staff member still gets their store: ' || (select v from res where k = 'A45 my stores, deleted Staff' and phase = 'before'));
select pg_temp.check((select v from res where k = 'S02 send, Staff of another store' and phase = 'before') like 'ok:INV-9001-NOT-IT|%',
  'B3 before 541 Staff of another store log a send of the invoice, with the number they typed: ' || (select v from res where k = 'S02 send, Staff of another store' and phase = 'before'));
select pg_temp.check((select v from res where k = 'L02 into another store, Staff' and phase = 'before') like 'ok:%',
  'B4 before 541 Staff take a loan back into another store');
select pg_temp.check((select v from res where k = 'P02 a price changed' and phase = 'before') like 'ok:null => %',
  'B5 before 541 a price change logs no old price: ' || (select v from res where k = 'P02 a price changed' and phase = 'before'));
\endif

insert into res select c.k, 'after', pg_temp.as_(c.who, c.q) from cases c order by c.k;
create function pg_temp.r(key text) returns text language sql as $$ select v from res where k = key and phase = 'after' $$;
create function pg_temp.rb(key text) returns text language sql as $$ select v from res where k = key and phase = 'before' $$;
create function pg_temp.lid() returns text language sql as $$ select loan_no from public.stock_loans where id = pg_temp.fx('l1') $$;

-- ═════ A L14: the same answers, but for logins the test now refuses ═════
create temp table changed(k text primary key, expect text);
insert into changed values
  ('A03 portal login, pending Owner', 'ERR 42501 Only active Energia staff can do this.'),
  ('A07 unlink, pending Owner', 'ERR 42501 Only active Energia staff can do this.'),
  ('A11 TikTok payouts, pending Owner', 'ERR 42501 Only active Energia staff can do this.'),
  ('A15 TikTok Xero, pending Owner', 'ERR 42501 Only active Energia staff can do this.'),
  ('A19 Stock History filters, pending Staff', 'ERR 42501 Only active Energia staff can do this.'),
  ('A22 customer match, pending Staff', 'ERR 42501 Only active Energia staff can do this.'),
  ('A29 hand over, pending Staff', 'ERR 42501 Only active Energia staff can do this.'),
  ('A35 important, pending Staff', 'ERR 42501 Only active Energia staff can do this.'),
  ('A36 important, deleted Staff', 'ERR 42501 Only active Energia staff can do this.'),
  ('A44 my stores, pending Staff', 'ok:none'),
  ('A45 my stores, deleted Staff', 'ok:none');
select pg_temp.check(pg_temp.r(c.k) = c.expect, c.k || ': ' || pg_temp.r(c.k)) from changed c order by c.k;
select pg_temp.check(pg_temp.r(c.k) = (select x.v from res x where x.k = c.k and x.phase = 'before'),
         c.k || ' answers as before 541: ' || left(pg_temp.r(c.k), 160))
  from cases c where c.k like 'A%' and c.k not in (select k from changed) and :'mode' = 'install' order by c.k;
-- What each gives, in either mode.
select pg_temp.check(pg_temp.r('A01 portal login, Owner') = 'ok:{"linked": false}', 'A01b an Owner reads a customer''s portal login: ' || pg_temp.r('A01 portal login, Owner'));
select pg_temp.check(pg_temp.r('A02 portal login, Staff') = 'ERR 42501 Only an Owner can see or unlink an affiliate login', 'A02b Staff are refused with the function''s own sentence');
select pg_temp.check(pg_temp.r('A04 portal login, secret key') = 'ERR 42501 Only an Owner can see or unlink an affiliate login', 'A04b the secret key is still refused: ' || pg_temp.r('A04 portal login, secret key'));
select pg_temp.check(pg_temp.r('A05 unlink, Owner') = 'ERR P0001 This customer has no portal login linked.', 'A05b an Owner gets past the test: ' || pg_temp.r('A05 unlink, Owner'));
select pg_temp.check(pg_temp.r('A08 unlink, secret key') = 'ERR 42501 Only an Owner can unlink an affiliate login', 'A08b the secret key is still refused');
select pg_temp.check(pg_temp.r('A09 TikTok payouts, Owner') like 'ok:%' and pg_temp.r('A13 TikTok Xero, Manager') like 'ok:%', 'A09b an Owner and a Manager read the TikTok payouts');
select pg_temp.check(pg_temp.r('A10 TikTok payouts, Staff') = 'ERR P0001 Only an Owner or Manager can see the TikTok payouts'
                 and pg_temp.r('A12 TikTok payouts, secret key') = 'ERR P0001 Only an Owner or Manager can see the TikTok payouts'
                 and pg_temp.r('A16 TikTok Xero, secret key') = 'ERR P0001 Only an Owner or Manager can export TikTok payouts for Xero',
  'A10b Staff and the secret key are refused with the functions'' own sentences');
select pg_temp.check(pg_temp.r('A17 Stock History filters, Staff') like 'ok:%' and pg_temp.r('A18 Stock History filters, Inventory Manager') like 'ok:%'
                 and pg_temp.r('A20 Stock History filters, secret key') = 'ERR P0001 Stock History is available to internal staff only',
  'A17b Stock History filters: Staff and an Inventory Manager in, the secret key out: ' || pg_temp.r('A20 Stock History filters, secret key'));
select pg_temp.check(pg_temp.r('A21 customer match, Staff') like 'ok:%' and pg_temp.r('A23 customer match, secret key') = 'ERR 42501 You do not have permission to look up customers'
                 and pg_temp.r('A24 customer match, Inventory Manager') = 'ERR 42501 An Inventory Manager works with stock only.',
  'A21b customer match: Staff in; the secret key and an Inventory Manager (540) out');
select pg_temp.check(pg_temp.r('A25 affiliate directory, Staff') like 'ok:%' and pg_temp.r('A26 affiliate directory, pending Staff') = 'ERR 42501 Only active Energia staff can do this.'
                 and pg_temp.r('A27 affiliate directory, secret key') = 'ERR 42501 Sign in to view the affiliate directory',
  'A25b affiliate directory: Staff in, pending out (as before), the secret key out (as before)');
select pg_temp.check(pg_temp.r('A28 hand over, Staff') = 'ok:true' and pg_temp.r('A30 hand over, secret key') = 'ERR 42501 Only an active user can hand over goods',
  'A28b hand over: Staff in, the secret key out: ' || pg_temp.r('A28 hand over, Staff') || ' / ' || pg_temp.r('A30 hand over, secret key'));
select pg_temp.check(pg_temp.r('A31 settlement, Staff') = 'ok:true' and pg_temp.r('A32 settlement, pending Staff') like 'ERR 42501 %'
                 and pg_temp.r('A33 settlement, secret key') like 'ERR 42501 %',
  'A31b settlement: Staff in; pending Staff and the secret key out: ' || pg_temp.r('A32 settlement, pending Staff') || ' / ' || pg_temp.r('A33 settlement, secret key'));
select pg_temp.check(pg_temp.r('A34 important, Staff') = 'ok:' and pg_temp.r('A37 important, secret key') = 'ERR P0001 No active profile for the current user',
  'A34b mark important: Staff in, the secret key out: ' || pg_temp.r('A37 important, secret key'));
select pg_temp.check(pg_temp.r('A38 may correct, Staff') = 'ok:true' and pg_temp.r('A39 may correct, Owner') = 'ok:false'
                 and pg_temp.r('A40 may correct, pending Staff') = 'ok:false' and pg_temp.r('A41 may correct, deleted Staff') = 'ok:false',
  'A38b may correct: true for Staff of the store, false (no error) for an Owner, pending and deleted Staff');
select pg_temp.check(pg_temp.r('A42 my stores, Staff') = 'ok:Testing Store A/true'
                 and pg_temp.r('A43 my stores, Owner') = 'ok:Testing Store A,Testing Store B'
                 and pg_temp.r('A46 my stores, secret key') = 'ok:none',
  'A42b my stores: Staff their store, an Owner every open store, the secret key none: ' || pg_temp.r('A43 my stores, Owner'));

-- ═════ S L16: the send log ═════
select pg_temp.check(pg_temp.r('S01 send, Staff of the store') = 'ok:' || (select invoice_no from public.invoices where id = pg_temp.fx('i1')) || '|' || pg_temp.fx('c1') || '|' || pg_temp.fx('stf'),
  'S01 Staff of the store log a send; the number and customer are the invoice''s, not the ones sent: ' || pg_temp.r('S01 send, Staff of the store'));
select pg_temp.check(pg_temp.r('S02 send, Staff of another store') = 'ERR 42501 That document is not one you can see.', 'S02 Staff of another store are refused: ' || pg_temp.r('S02 send, Staff of another store'));
select pg_temp.check(pg_temp.r('S03 send, Owner') like 'ok:' || (select invoice_no from public.invoices where id = pg_temp.fx('i1')) || '|%', 'S03 an Owner logs a send of any store''s invoice');
select pg_temp.check(pg_temp.r('S04 send, a Manager of no store, invoice') = 'ERR 42501 That document is not one you can see.', 'S04 a Manager logs an invoice of their stores only (the invoices'' read rule)');
select pg_temp.check(pg_temp.r('S05 send, no such document') = 'ERR 42501 That document is not one you can see.'
                 and pg_temp.r('S06 send, no document') = 'ERR 42501 That document is not one you can see.'
                 and pg_temp.r('S08 send, deleted invoice') = 'ERR 42501 That document is not one you can see.',
  'S05 a missing, absent or deleted document is refused');
select pg_temp.check(pg_temp.r('S07 send, unknown kind') = 'ERR 22023 Unknown document kind "receipt"', 'S07 an unknown kind: ' || pg_temp.r('S07 send, unknown kind'));
select pg_temp.check(pg_temp.r('S09 send, special sale, Staff of the store') = 'ok:SS-9001-' || pg_temp.tok() || '|' || pg_temp.fx('c1') || '|' || pg_temp.fx('stf')
                 and pg_temp.r('S11 send, special sale, a Manager of no store') like 'ok:SS-9001-%'
                 and pg_temp.r('S10 send, special sale, Staff of another store') = 'ERR 42501 That document is not one you can see.',
  'S09 a special sale: Staff of its store and a Manager log it, with its number and customer; Staff of another store do not');
select pg_temp.check(pg_temp.r('S12 send, rental, Staff of the store') = 'ok:RN-9001-' || pg_temp.tok() || '|' || pg_temp.fx('c1') || '|' || pg_temp.fx('stf')
                 and pg_temp.r('S13 send, rental, Staff of another store') = 'ERR 42501 That document is not one you can see.',
  'S12 a rental: Staff of its store log it with its number and customer; Staff of another store do not');
select pg_temp.check(pg_temp.r('S14 send, secret key') = 'ERR 42501 That document is not one you can see.', 'S14 the secret key logs no send: ' || pg_temp.r('S14 send, secret key'));
select pg_temp.check(pg_temp.r('S15 send, Inventory Manager') = 'ERR 42501 An Inventory Manager works with stock only.', 'S15 an Inventory Manager is refused by 540''s guard, first');
select pg_temp.check(pg_temp.r('S16 send, as the page sends it') = 'ok:true', 'S16 the page''s own call (sendDoc.ts, all nine arguments) is logged');

-- ═════ L L19: loans ═════
select pg_temp.check(pg_temp.r('L01 back to its store, Staff') like 'ok:%', 'L01 Staff take a loan back into its own store');
select pg_temp.check(pg_temp.r('L02 into another store, Staff') = 'ERR 42501 ' || pg_temp.lid() || ' was lent from Testing Store A, so it comes back there. Only an Owner or a Manager can take it back into another store or warehouse.',
  'L02 Staff may not take it back into another store: ' || pg_temp.r('L02 into another store, Staff'));
select pg_temp.check(pg_temp.r('L03 into another store, Manager') = 'ok:1|1', 'L03 a Manager takes it back into another store; the unit lands there and the event row says so: ' || pg_temp.r('L03 into another store, Manager'));
select pg_temp.check(pg_temp.r('L04 into another store, Owner') like 'ok:%', 'L04 an Owner takes it back into another store');
select pg_temp.check(pg_temp.r('L05 into a warehouse, Staff') like 'ERR 42501 ' || pg_temp.lid() || ' was lent from Testing Store A%', 'L05 Staff may not take a store''s loan into a warehouse: ' || pg_temp.r('L05 into a warehouse, Staff'));
select pg_temp.check(pg_temp.r('L06 into a warehouse, Owner') like 'ok:%', 'L06 an Owner takes a store''s loan into a warehouse (the warehouse permission)');
select pg_temp.check(pg_temp.r('L07 warehouse loan into another warehouse, Manager') like 'ok:%' and pg_temp.r('L08 warehouse loan back to its warehouse, Manager') like 'ok:%',
  'L07 a Manager with the warehouse permission takes a warehouse loan back into it or another warehouse');
select pg_temp.check(pg_temp.r('L09 used, Staff') like 'ok:%' and pg_temp.r('L10 lost, Staff') like 'ok:%', 'L09 used and lost entries as before');
select pg_temp.check(pg_temp.r('L11 into a closed store, Manager') = 'ERR P0001 Store not found', 'L11 a closed store is refused as before: ' || pg_temp.r('L11 into a closed store, Manager'));
select pg_temp.check(pg_temp.r('L12 into a store, Inventory Manager') = 'ERR 42501 An Inventory Manager does not lend stock or take it back.', 'L12 an Inventory Manager is refused by 540''s guard');
select pg_temp.check(pg_temp.r('L13 into another store, Admin') = 'ERR 42501 ' || pg_temp.lid() || ' was lent from Testing Store A, so it comes back there. Only an Owner or a Manager can take it back into another store or warehouse.'
                 and pg_temp.r('L15 into a warehouse, Admin') = 'ERR 42501 ' || pg_temp.lid() || ' was lent from Testing Store A, so it comes back there. Only an Owner or a Manager can take it back into another store or warehouse.'
                 and pg_temp.r('L17 a warehouse loan, Admin') = 'ERR P0001 You do not have permission to take back a loan from a warehouse',
  'L13 an Admin is on the Staff side: not into another store or warehouse: ' || pg_temp.r('L13 into another store, Admin'));
select pg_temp.check(pg_temp.r('L14 back to its store, Admin') like 'ok:%', 'L14 an Admin takes it back into its own store: ' || left(pg_temp.r('L14 back to its store, Admin'), 120));
select pg_temp.check(pg_temp.r('L16 into another store, secret key') like 'ERR %', 'L16 the secret key does not take a loan back elsewhere: ' || pg_temp.r('L16 into another store, secret key'));
select pg_temp.check(pg_temp.r(c.k) = pg_temp.rb(c.k), c.k || ' answers as before 541')
  from cases c where c.k in ('L01 back to its store, Staff', 'L03 into another store, Manager', 'L04 into another store, Owner', 'L06 into a warehouse, Owner',
                             'L07 warehouse loan into another warehouse, Manager', 'L08 warehouse loan back to its warehouse, Manager',
                             'L11 into a closed store, Manager', 'L12 into a store, Inventory Manager')
   and :'mode' = 'install' and pg_temp.r(c.k) not like 'ok:%' order by c.k;
select pg_temp.check(pg_temp.rb(c.k) like 'ok:%', c.k || ' worked before 541 too')
  from cases c where c.k in ('L01 back to its store, Staff', 'L03 into another store, Manager', 'L04 into another store, Owner', 'L06 into a warehouse, Owner',
                             'L07 warehouse loan into another warehouse, Manager', 'L08 warehouse loan back to its warehouse, Manager', 'L09 used, Staff', 'L10 lost, Staff')
   and :'mode' = 'install' order by c.k;

-- ═════ K L19: TikTok rows ═════
select pg_temp.check(pg_temp.r('K01 20,001 rows') = 'ERR 54000 A TikTok file has at most 20,000 rows. Please export a shorter date range and try again.', 'K01 20,001 rows are refused: ' || pg_temp.r('K01 20,001 rows'));
select pg_temp.check(pg_temp.r('K02 20,000 rows') = 'ok:true', 'K02 20,000 rows (the page''s most) are staged: ' || left(pg_temp.r('K02 20,000 rows'), 160));
select pg_temp.check(pg_temp.r('K03 20,001 rows, Staff of another store') = 'ERR P0001 You can only import TikTok sales for your assigned store', 'K03 the access check comes first: ' || pg_temp.r('K03 20,001 rows, Staff of another store'));
select pg_temp.check(pg_temp.r('K04 three rows, Staff') = 'ok:true' and (:'mode' <> 'install' or pg_temp.rb('K04 three rows, Staff') = 'ok:true'), 'K04 a small file by Staff of the store, as before');

select pg_temp.check(pg_temp.r('K05 settlement file, 20,001 lines') = 'ERR 54000 A TikTok file has at most 20,000 rows. Please export a shorter date range and try again.'
                 and pg_temp.r('K07 settled lines alone, 20,001') = 'ERR 54000 A TikTok file has at most 20,000 rows. Please export a shorter date range and try again.',
  'K05 a settlement file of 20,001 lines is refused, through the page''s function and on its own: ' || pg_temp.r('K05 settlement file, 20,001 lines'));
select pg_temp.check(pg_temp.r('K06 settlement file, 20,001 Withdrawal records') = 'ERR 54000 A TikTok file''s Withdrawal records have at most 20,000 rows. Please export a shorter date range and try again.',
  'K06 20,001 Withdrawal records are refused: ' || pg_temp.r('K06 settlement file, 20,001 Withdrawal records'));
select pg_temp.check(pg_temp.r('K08 settlement file, 20,000 lines and 20,000 Withdrawal records') = 'ok:20000|20000',
  'K08 20,000 lines and 20,000 Withdrawal records (the page''s most) are staged: ' || pg_temp.r('K08 settlement file, 20,000 lines and 20,000 Withdrawal records'));
select pg_temp.check(pg_temp.r('K09 settlement file, 20,001 Withdrawal records, Staff of another store') = 'ERR P0001 You can only import TikTok sales for your assigned store',
  'K09 the access check comes first: ' || pg_temp.r('K09 settlement file, 20,001 Withdrawal records, Staff of another store'));
select pg_temp.check(pg_temp.r('K10 settlement file, three lines and three records, Staff') = 'ok:3|3'
                 and (:'mode' <> 'install' or pg_temp.rb('K10 settlement file, three lines and three records, Staff') = 'ok:3|3'),
  'K10 a small settlement file by Staff of the store, as before: ' || pg_temp.r('K10 settlement file, three lines and three records, Staff'));

-- ═════ P L19: prices ═════
select pg_temp.check(pg_temp.r('P01 first price at a store') = format('ok:null => {"price": 120, "store": "%s"}', pg_temp.fx('st2')), 'P01 a first price: no old price: ' || pg_temp.r('P01 first price at a store'));
select pg_temp.check(pg_temp.r('P02 a price changed') = format('ok:{"price": 100.00, "store": "%s"} => {"price": 120, "store": "%s"}', pg_temp.fx('st'), pg_temp.fx('st')), 'P02 a change: the old price beside the new: ' || pg_temp.r('P02 a price changed'));
select pg_temp.check(pg_temp.r('P03 a price taken off the list, set again') = format('ok:{"price": 100.00, "store": "%s", "removed": true} => {"price": 120, "store": "%s"}', pg_temp.fx('st'), pg_temp.fx('st')), 'P03 a price set again after it was taken off: ' || pg_temp.r('P03 a price taken off the list, set again'));
select pg_temp.check(split_part(pg_temp.r(k), ' => ', 2) = split_part(pg_temp.rb(k), ' => ', 2), k || ': new_data as before 541')
  from unnest(array['P01 first price at a store', 'P02 a price changed', 'P03 a price taken off the list, set again']) k where :'mode' = 'install';

-- ═════ G 541's fixed parts ═════
select pg_temp.check(exists (select 1 from storage.buckets where id = 'store-assets' and public and file_size_limit = 5242880
                                and allowed_mime_types = array['image/png', 'image/jpeg', 'image/webp']), 'G1 store-assets: PNG, JPEG, WebP, 5 MB, still public');
select pg_temp.check(exists (select 1 from storage.buckets where id = 'survey-attachments' and not public and file_size_limit = 10485760
                                and allowed_mime_types = array['image/jpeg', 'image/png', 'image/gif', 'image/webp', 'image/heic', 'image/heif',
                                  'application/pdf', 'application/msword', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
                                  'application/vnd.ms-excel', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', 'text/csv', 'text/plain']),
  'G2 survey-attachments: six photo types, no image/* and no SVG, the seven document types and 10 MB as before');
select pg_temp.check(not exists (select 1 from storage.buckets b, unnest(b.allowed_mime_types) t where b.id in ('store-assets', 'survey-attachments') and (t like '%svg%' or t like '%*%')),
  'G3 neither bucket takes SVG or a wildcard');
select pg_temp.check(exists (select 1 from storage.buckets where id = 'invoice-pdfs' and not public and file_size_limit = 10485760 and allowed_mime_types = array['application/pdf']),
  'G4 invoice-pdfs as it was');
select pg_temp.check(count(*) = 18, 'G5 the 18 functions are 541''s, with search_path public, pg_temp and their grants as before: ' || count(*))
  from unnest(array['affiliate_portal_login(uuid)', 'affiliate_staff_directory(text,integer,integer)', 'customer_match_candidates(text,text)', 'my_assigned_stores()',
                    'record_invoice_handover(uuid,jsonb,uuid)', 'record_invoice_settlement(uuid,jsonb,uuid)', 'set_product_important(uuid,boolean)',
                    'staff_may_correct_invoice(uuid)', 'stock_history_options(text,text,integer)', 'tiktok_bank_payouts(date,date)',
                    'tiktok_xero_payouts(integer,integer)', 'unlink_affiliate_account(uuid,text)',
                    'record_document_send(text,text,text,uuid,uuid,text,text,text,text)', 'return_stock_loan(uuid,jsonb,text,uuid)',
                    'stage_tiktok_orders(uuid,text,text,jsonb)', 'set_product_prices(uuid,uuid,numeric,numeric,text)',
                    'stage_tiktok_settlement(uuid,text,text,jsonb)', 'stage_tiktok_settlement_file(uuid,text,text,jsonb,jsonb)']) with ordinality s(sig, o)
  join unnest(array['1d9948cd8a49c58d54a83cb56c34656e', '350e02961ff61d5acdde7684e81c20b6', '96c185afbada30429ec9dce140a20fe7', '1e896989080f3da3f5ef7d72d51b5eb0',
                    '7234e8bb7f2ed2cfefa8354bb9843d2d', 'bec4ba292611157069c6813d22d04b9b', 'd5db927d78c68df7148ee9c499f117ea', 'e12563642234afde67989672f35b1c30',
                    '152d825c64c76e83d2e91eaddd5df05e', '40e93118b55f19b5aa5cf1cf33baf678', '236cc0c0256e211a62788064d547e0a3', 'e7067514af76bc9d20cb25b6544ee9d8',
                    'a7fd9efd60794d3c2f5595b328ce7a75', '90a623e74ca682594d2be55d5b67935c', '086b5958fa3d0e7c40cd5f333602cb53', 'cda58f1502d007f759ce9dda71c97ddf',
                    '3fbeeb26dd744e36f1e2ce075defe8d2', '45bbe95629b8140649a5360296e68b7a']) with ordinality m(md5, o) using (o)
  join pg_proc p on p.oid = to_regprocedure('public.' || s.sig)
 where md5(pg_get_functiondef(p.oid)) = m.md5 and p.proconfig = array['search_path=public, pg_temp']
   and p.proacl::text = (select acl from fn0 where fn = s.sig);
select pg_temp.check(not exists (select 1 from pg_policy p where p.polrelid = 'public.profiles'::regclass and p.polname = 'update profiles'
                                    and md5(coalesce(pg_get_expr(p.polqual, p.polrelid), '') || '|' || coalesce(pg_get_expr(p.polwithcheck, p.polrelid), '')) is distinct from
                                        (select md5(coalesce(pg_get_expr(q.polqual, q.polrelid), '') || '|' || coalesce(pg_get_expr(q.polwithcheck, q.polrelid), '')) from pg_policy q
                                          where q.polrelid = 'public.profiles'::regclass and q.polname = 'update profiles'))
                 and exists (select 1 from pg_policy p where p.polrelid = 'public.profiles'::regclass and p.polname = 'update profiles'),
  'G6 "update profiles" (a Manager''s company-wide user management, R2) is still there');
select pg_temp.check(count(*) = 7, 'G8 540''s guard is still the first statement in the seven 541 functions that have it: ' || count(*))
  from unnest(array['affiliate_staff_directory(text,integer,integer)', 'customer_match_candidates(text,text)', 'record_invoice_handover(uuid,jsonb,uuid)',
                    'record_invoice_settlement(uuid,jsonb,uuid)', 'record_document_send(text,text,text,uuid,uuid,text,text,text,text)',
                    'return_stock_loan(uuid,jsonb,text,uuid)', 'stage_tiktok_orders(uuid,text,text,jsonb)']) s(sig)
 where (s.sig = 'stage_tiktok_orders(uuid,text,text,jsonb)' and pg_get_functiondef(to_regprocedure('public.' || s.sig)) !~ 'inventory_manager_guard')
    or split_part(substr(pg_get_functiondef(to_regprocedure('public.' || s.sig)),
                         strpos(pg_get_functiondef(to_regprocedure('public.' || s.sig)), E'begin\n') + 6), E'\n', 1) like '  perform public.inventory_manager_guard(%';
\if :by_us
select pg_temp.check((select count(*) from (select fn, md5, acl from fn0 except
                                            select p.oid::regprocedure::text, md5(pg_get_functiondef(p.oid)), p.proacl::text
                                              from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p')) x) = 18,
  'G7 541 changed exactly 18 functions and made none');

-- ═════ U the undo, and M ═════
savepoint u1;
\ir ../undo-541.sql
select pg_temp.check(not exists (select fn, md5, acl from fn0 except
                                 select p.oid::regprocedure::text, md5(pg_get_functiondef(p.oid)), p.proacl::text
                                   from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p'))
                 and (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p')) = (select count(*) from fn0),
  'U1 the undo puts every function back exactly as before 541');
select pg_temp.check(not exists (select * from bk0 except select id, public, file_size_limit, allowed_mime_types from storage.buckets)
                 and not exists (select id, public, file_size_limit, allowed_mime_types from storage.buckets except select * from bk0),
  'U2 the undo puts the buckets'' rules back');
savepoint u2;
\set ON_ERROR_STOP off
\ir ../undo-541.sql
\set ON_ERROR_STOP on
rollback to savepoint u2;
select pg_temp.check(:'LAST_ERROR_MESSAGE' like 'undo 541: % is already its version of before 541%', 'U3 a second undo refuses: ' || :'LAST_ERROR_MESSAGE');
create temp table fn1 as select p.oid::regprocedure::text as fn, md5(pg_get_functiondef(p.oid)) as md5 from pg_proc p where false;
\ir ../../../supabase/541_lows_upload_rules_staff_test_send_log_loans_tiktok_prices.sql
select pg_temp.check((select count(*) from (select fn, md5, acl from fn0 except
                                            select p.oid::regprocedure::text, md5(pg_get_functiondef(p.oid)), p.proacl::text
                                              from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p')) x) = 18
                 and md5(pg_get_functiondef('public.record_document_send(text,text,text,uuid,uuid,text,text,text,text)'::regprocedure)) = 'a7fd9efd60794d3c2f5595b328ce7a75',
  'U4 541 after the undo makes the same again');
rollback to savepoint u1;
savepoint m1;
\set ON_ERROR_STOP off
\ir ../../../supabase/541_lows_upload_rules_staff_test_send_log_loans_tiktok_prices.sql
\set ON_ERROR_STOP on
rollback to savepoint m1;
select pg_temp.check(:'LAST_ERROR_MESSAGE' like '541 is already in on this database%', 'M1 541 a second time refuses: ' || :'LAST_ERROR_MESSAGE');
\else
\echo NOTE  B, G7, U and M are skipped (541 was not installed by this file)
\endif

select count(*) as n_failed from failed \gset
do $$ begin
  if (select count(*) from failed) > 0 then
    raise exception '% check(s) failed: %', (select count(*) from failed), (select string_agg(msg, E'\n' order by n) from failed);
  end if;
  raise notice 'ALL PASSED';
end $$;
rollback;
