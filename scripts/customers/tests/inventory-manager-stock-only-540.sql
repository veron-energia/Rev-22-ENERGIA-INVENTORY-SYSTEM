-- An Inventory Manager works with stock only: no invoices, no customers' names or phones, no
-- customer benefit records, no rentals or special sales, no lending to or taking back from
-- customers (540; security audit of 17 Nov 2026, M13; the user, 25 Nov 2026: "Stock only", "No
-- lending by IM"; 26 Nov 2026: "Close them too").
--
-- Every call is made as the pages make it: a signed-in login (the authenticated role, its JWT), or
-- as a server function runs it (the database owner with the login's claims, "pg:"), or with no
-- login at all (the server's own work), or the secret key. Each call that could write is rolled
-- back on its own. The logins: an Owner, a Manager, Staff and an Inventory Manager of one store,
-- and an Admin. Made-up rows: a store, a warehouse, a product, two customers (one the other's
-- referrer), a paid and an unpaid invoice by Staff, a printed invoice, a loan to a customer at the
-- store and one to a typed name at the warehouse.
--
--   B  (install mode) Before 540: the Inventory Manager makes an invoice, reads the store's
--      invoices and the invoice list with the customer's name, lends stock; old loan notes name the
--      borrower. The Staff answer to every road is kept, to compare after.
--   R  Every road of the audit's lists 1 and 2 (create, settle, correct, delete, hand over, ask,
--      label, preview, exchange, split package and bundle invoices, the two therapy claims, the
--      three therapy actions, print and send, and the four functions of a customer's therapy that
--      run as their caller) refuses the Inventory Manager with the sentence;
--      Staff get exactly the answer they got before 540 (install mode), or at least not the
--      Inventory Manager's refusal (skip mode). New Invoice and payment by Staff work.
--   L  Loans: the Inventory Manager may not lend or take back, at a store or a warehouse; they see
--      a location's loans with no borrower or phone; Staff and a Manager lend
--      and take back; the new movement notes carry the loan number only, old ones keep the name.
--   T  Reads: the Inventory Manager of the store reads no row of invoices, invoice lines,
--      payments, customers, phone history, loans, loan lines, the print and send log, handovers,
--      exchanges, therapy invoices, the 15 tables of customer benefit records (an affiliate's row
--      among them), rentals or special sales; Staff still read them.
--   K  The stock work an Inventory Manager keeps runs for them: stock in at the warehouse, a
--      stock correction, a stock use, a transfer request, a product save, a TikTok file, Stock
--      History, the Dashboard's functions, the sales ledger, the FOC lines, the loans list.
--   D  What the Inventory Manager keeps: the Dashboard's sales totals and alerts, the FOC totals
--      without the customer's name, stock functions.
--   W  "No invoicing" by any route (a server function's own write, with the login's claims) is
--      refused for the Inventory Manager, and passes for Staff, a Manager, the secret key and the
--      server's own work (no login).
--   X  The generated check: every signed-in function whose text reads customers' full_name or
--      phone, a loan's borrower_name or stock_loan_json, every invoice- or exchange-named one and
--      the audit's list, called as the Inventory Manager with the made-up rows: each is refused or
--      answers with no name or phone of the fixture. (From pg_proc, so it holds for new functions.)
--   G  540's fixed parts: the guard and the trigger function postgres's alone; the guard first in
--      62 functions; the three triggers; the seven read rules.
--   U  scripts/customers/undo-540.sql puts everything back exactly; a second undo refuses; 540
--      again makes the same.
--   M  540 a second time refuses.
--
-- Disposable local database only; everything is rolled back. Every name and number is invented
-- (M540 ..., @example.invalid; phones +61 491 570 nnn). Run it on a copy of production with 539
-- and without 540 (it applies 540, then again); with -v skip_install=1 where 540 is in (B, U and M
-- skipped, G in part); with -v control=1 on a copy WITHOUT 540 (it skips B, G, U and M and fails on
-- exactly the checks 540 makes pass).
--   psql -X -v ON_ERROR_STOP=1 -f scripts/customers/tests/inventory-manager-stock-only-540.sql
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
       to_regprocedure('public.customer_list_guard(integer)') is not null as had539 \gset
\if :had539
\else
\echo 539 is not in: 540 needs it
select 1/0;
\endif
\if :{?control}
\if :had540
\echo control: 540 is in on this copy; run -v control=1 on a copy without it
select 1/0;
\endif
\set mode control
\elif :{?skip_install}
\if :had540
\else
\echo 540 is not in: run without -v skip_install
select 1/0;
\endif
\set mode skip
\elif :had540
\echo 540 is already in: run with -v skip_install=1
select 1/0;
\else
\set mode install
\endif
select :'mode' = 'install' as by_us, :'mode' = 'control' as is_control \gset

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
create function pg_temp.s(key text) returns text language sql as $$
  select case key
    when 'invoice' then 'An Inventory Manager does not make or change invoices.'
    when 'loan' then 'An Inventory Manager does not lend stock or take it back.'
    when 'stock' then 'An Inventory Manager works with stock only.' end $$;
create function pg_temp.claims(who text) returns void language plpgsql as $f$
begin
  perform set_config('request.jwt.claim.sub', coalesce(pg_temp.fx(who)::text, ''), true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', pg_temp.fx(who), 'role', 'authenticated')::text, true);
end $f$;
-- Runs q and rolls back whatever it did: 'ok:<answer>' or 'ERR <sqlstate> <message>'.
-- who: a login (signed in), 'pg:<login>' (as a server function runs, with the login's claims),
-- 'nologin' (the server's own work) or 'service' (the secret key).
create function pg_temp.as_(who text, q text) returns text language plpgsql as $f$
declare v text; s text; m text;
begin
  begin
    if who = 'service' then
      perform set_config('request.jwt.claim.sub', '', true);
      perform set_config('request.jwt.claim.role', 'service_role', true);
      perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
      execute 'set local role service_role';
    elsif who = 'nologin' then
      perform set_config('request.jwt.claim.sub', '', true);
      perform set_config('request.jwt.claim.role', '', true);
      perform set_config('request.jwt.claims', '', true);
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
-- The same, kept (fixtures and the writes a check needs).
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
create function pg_temp.refused(t text, key text) returns boolean language sql as
$$ select t = 'ERR 42501 ' || pg_temp.s(key) $$;
create function pg_temp.leaks(v text) returns boolean language sql as $$
  select v like 'ok:%' and (v ~ (select tok from sfx) or v ~ substr(pg_temp.ph(1), 2) or v ~ substr(pg_temp.ph(2), 2)
                            or v ~ substr(pg_temp.ph(3), 2)) $$;

-- ═════ Fixtures (invented) ═════
do $fx$
declare r record; u uuid; t text := pg_temp.tok();
begin
  for r in select * from (values ('own', 'owner'), ('mgr', 'manager'), ('stf', 'staff'), ('invm', 'inventory_manager'), ('adm', 'admin')) x(k, role) loop
    insert into auth.users(id, email, email_confirmed_at) values (gen_random_uuid(), 'm540-' || r.k || '-' || md5(t) || '@example.invalid', now()) returning id into u;
    insert into public.profiles(id, full_name, email, role, is_active) values (u, 'M540 staff ' || r.k, 'm540-' || r.k || '-' || md5(t) || '@example.invalid', r.role::public.user_role, true);
    perform pg_temp.put(r.k, u);
  end loop;
  insert into public.app_settings(id) values (true) on conflict do nothing;
  insert into public.stores(name, code, country_code) values ('M540 Store', 'M540' || upper(substr(md5(t), 1, 4)), 'SG') returning id into u; perform pg_temp.put('st', u);
  insert into public.warehouses(name, code) values ('M540 Warehouse', 'W540' || upper(substr(md5(t), 1, 4))) returning id into u; perform pg_temp.put('wh', u);
  insert into public.user_store_assignments(user_id, store_id) select pg_temp.fx(k), pg_temp.fx('st') from unnest(array['mgr', 'stf', 'invm']) k;
  perform set_config('request.jwt.claim.sub', pg_temp.fx('own')::text, true);
  insert into public.products(name, sku, product_type) values ('M540 Item', 'M540-' || md5(t), 'own') returning id into u; perform pg_temp.put('p', u);
  insert into public.store_inventory(store_id, product_id, current_qty) values (pg_temp.fx('st'), u, 50);
  insert into public.warehouse_inventory(warehouse_id, product_id, current_qty) values (pg_temp.fx('wh'), u, 50);
  perform public.set_product_prices(pg_temp.fx('st'), u, 100, 100, 'available');
  perform set_config('request.jwt.claim.sub', '', true);
  insert into public.payment_methods(name, is_active) values ('M540 Cash ' || md5(t), true) returning id into u; perform pg_temp.put('pm', u);
  insert into public.customers(full_name, first_name, last_name, phone, email) values ('M540 ' || t || ' Referrer', 'M540', t || ' Referrer', pg_temp.ph(2), t || '-c2@example.invalid') returning id into u; perform pg_temp.put('c2', u);
  insert into public.customers(full_name, first_name, last_name, phone, email, referred_by) values ('M540 ' || t || ' Alpha', 'M540', t || ' Alpha', pg_temp.ph(1), t || '-c1@example.invalid', pg_temp.fx('c2')) returning id into u; perform pg_temp.put('c1', u);
  insert into public.customer_phone_history(customer_id, phone, reason) values (pg_temp.fx('c1'), pg_temp.ph(3), 'Made-up old number');
  insert into public.customer_affiliates(customer_id, status, notes) values (pg_temp.fx('c2'), 'active', 'M540 made-up affiliate note') returning id into u;
  perform pg_temp.put('a2', u);
end $fx$;
create function pg_temp.new_invoice(who text) returns text language sql as $$
  select format('select public.create_invoice_with_details(%L::uuid, %L::uuid, %L::jsonb, %L::jsonb)::text',
    pg_temp.fx('st'), pg_temp.fx('c1'), jsonb_build_array(jsonb_build_object('kind', 'product', 'product_id', pg_temp.fx('p'), 'quantity', 1)),
    jsonb_build_object('business_date', public.sg_today())) $$;
create function pg_temp.settle(inv text) returns text language sql as $$
  select format('select public.record_invoice_settlement(%L::uuid, %L::jsonb, %L::uuid)::text', pg_temp.fx(inv),
    jsonb_build_object('receipts', jsonb_build_array(jsonb_build_object('key', 'line-0', 'payment_method_id', pg_temp.fx('pm'),
      'amount', (select total_amount from public.invoices where id = pg_temp.fx(inv)), 'payment_date', public.sg_today()::text)), 'arrangements', '[]'::jsonb),
    gen_random_uuid()) $$;
create function pg_temp.lend(loc text, cust boolean) returns text language sql as $$
  select format('select public.lend_stock(%L, %L::uuid, %L::jsonb, public.sg_today() + 7, %s, %s, %L, gen_random_uuid())::text',
    loc, pg_temp.fx(case loc when 'store' then 'st' else 'wh' end),
    jsonb_build_array(jsonb_build_object('product_id', pg_temp.fx('p'), 'quantity', 1)),
    case when cust then quote_literal(pg_temp.fx('c1')) || '::uuid' else 'null' end,
    case when cust then 'null' else quote_literal('M540 ' || pg_temp.tok() || ' Typed') end, 'Trial') $$;
create function pg_temp.giveback(loan text) returns text language sql as $$
  select format('select public.return_stock_loan(%L::uuid, %L::jsonb, null, gen_random_uuid())::text', pg_temp.fx(loan),
    jsonb_build_array(jsonb_build_object('line_id', (select id from public.stock_loan_lines where loan_id = pg_temp.fx(loan) limit 1),
      'outcome', 'returned', 'quantity', 1, 'condition', 'good',
      'location_type', (select location_type from public.stock_loans where id = pg_temp.fx(loan)),
      'location_id', (select coalesce(store_id, warehouse_id) from public.stock_loans where id = pg_temp.fx(loan))))) $$;
select pg_temp.put('i1', pg_temp.must('stf', pg_temp.new_invoice('stf'))::uuid) \g /dev/null
select pg_temp.must('stf', pg_temp.settle('i1')) \g /dev/null
select pg_temp.put('i2', pg_temp.must('stf', pg_temp.new_invoice('stf'))::uuid) \g /dev/null
select pg_temp.must('stf', pg_temp.lend('store', true)) \g /dev/null
select pg_temp.must('mgr', pg_temp.lend('warehouse', false)) \g /dev/null
select pg_temp.put('l1', (select id from public.stock_loans where customer_id = pg_temp.fx('c1') order by lent_at limit 1)) \g /dev/null
select pg_temp.put('l2', (select id from public.stock_loans where borrower_name = 'M540 ' || pg_temp.tok() || ' Typed' limit 1)) \g /dev/null
select pg_temp.must('stf', format('select public.record_document_printed(%L, %L::uuid)::text', 'invoice', pg_temp.fx('i1'))) \g /dev/null
select pg_temp.must('stf', format('select public.record_document_send(%L, %L, %L, %L::uuid, %L::uuid, %L)::text', 'invoice',
  (select invoice_no from public.invoices where id = pg_temp.fx('i1')), 'whatsapp', pg_temp.fx('i1'), pg_temp.fx('c1'), pg_temp.ph(1))) \g /dev/null
-- I1's line made FOC (the Dashboard's FOC totals read it).
update public.invoice_items set foc_quantity = 1, is_foc = true, foc_amount = line_total, foc_reason = 'M540 made-up FOC'
 where invoice_id = pg_temp.fx('i1');

-- ═════ The generic call (X), and the roads (R) ═════
create function pg_temp.argval(n text, t regtype) returns text language sql as $$
  select case
    when t = 'uuid'::regtype then coalesce(quote_literal(case
        when n ~ 'customer|buyer|beneficiar|referr|person|member' then pg_temp.fx('c1')
        when n ~ 'invoice|record|doc_id|source' then pg_temp.fx('i1')
        when n ~ 'warehouse' then pg_temp.fx('wh')
        when n ~ 'store|location' then pg_temp.fx('st')
        when n ~ 'product' then pg_temp.fx('p')
        when n ~ 'loan' then pg_temp.fx('l1')
        when n ~ 'user|staff|profile' then pg_temp.fx('stf') end) || '::uuid', 'null::uuid')
    when t = 'text'::regtype then case
        when n ~ 'location_type' then quote_literal('store')
        when n ~ 'search|query|term|^p_q$|name|text' then quote_literal('M540 ' || pg_temp.tok())
        when n ~ 'kind' then quote_literal('invoice')
        when n ~ 'period|granularity|grain' then quote_literal('day')
        else 'null::text' end
    when t in ('integer'::regtype, 'bigint'::regtype, 'smallint'::regtype) then case when n ~ 'limit|size' then '50' when n ~ 'offset|page' then '0' else 'null::' || t::text end
    when t = 'boolean'::regtype then 'false'
    when t = 'date'::regtype then case when n ~ 'from|start' then '(public.sg_today() - 30)' when n ~ 'to|end' then '(public.sg_today() + 30)' else 'null::date' end
    when t = 'timestamp with time zone'::regtype then case when n ~ 'from|start' then '(now() - interval ''30 days'')' when n ~ 'to|end' then '(now() + interval ''30 days'')' else 'null::timestamptz' end
    else 'null::' || format_type(t, null) end $$;
create function pg_temp.callsql(f oid) returns text language plpgsql as $f$
declare p record; args text := ''; i int; n text; t regtype;
begin
  select * into p from pg_proc where oid = f;
  for i in 1 .. p.pronargs loop
    t := p.proargtypes[i - 1];
    n := coalesce((select x from unnest(coalesce(p.proargnames, '{}'::text[])) with ordinality u(x, o)
                    where o = (select o2 from unnest(coalesce(p.proargmodes, array_fill('i'::"char", array[p.pronargs]))) with ordinality m(md, o2)
                                where md in ('i', 'b', 'v') offset i - 1 limit 1)), 'p' || i);
    args := args || case when i > 1 then ', ' else '' end || pg_temp.argval(lower(n), t);
  end loop;
  if p.proretset then return format('select string_agg(to_jsonb(x)::text, %L) from %s(%s) x', '|', f::regproc, args); end if;
  return format('select (%s(%s))::text', f::regproc, args);
end $f$;
create temp table roads(fn text primary key, key text, q text);
insert into roads(fn, key) values
  ('create_invoice_with_details(uuid,uuid,jsonb,jsonb)', 'invoice'),
  ('record_invoice_settlement(uuid,jsonb,uuid)', 'invoice'),
  ('correct_invoice(uuid,jsonb,jsonb,text,uuid)', 'invoice'),
  ('delete_invoice(uuid,text)', 'invoice'),
  ('record_invoice_handover(uuid,jsonb,uuid)', 'invoice'),
  ('request_invoice_action_v2(uuid,text,jsonb,text,text,uuid)', 'invoice'),
  ('set_invoice_instalment_label(uuid,uuid,integer)', 'invoice'),
  ('preview_invoice_correction(uuid,jsonb)', 'invoice'),
  ('create_exchange_with_details(text,jsonb)', 'invoice'),
  ('create_split_credit_package_invoices(uuid,uuid,jsonb,uuid[],uuid,text,uuid)', 'invoice'),
  ('create_split_premium_bundle_invoices(uuid,uuid,jsonb,uuid[],uuid,text,uuid)', 'invoice'),
  ('claim_entitlement_vouchers(uuid,jsonb,text,uuid)', 'invoice'),
  ('claim_purchased_therapy(uuid,text,date,text,text,boolean,jsonb,uuid,text)', 'invoice'),
  ('activate_purchased_therapy(uuid,date,text,text,text,boolean)', 'stock'),
  ('choose_therapy_benefit(uuid,text,uuid,text)', 'stock'),
  ('reschedule_purchased_therapy(uuid,date,text)', 'stock'),
  ('record_document_printed(text,uuid)', 'stock'),
  ('record_document_send(text,text,text,uuid,uuid,text,text,text,text)', 'stock'),
  ('customer_therapy_session_balance(uuid)', 'stock'),
  ('customer_therapy_voucher_rights(uuid,date)', 'stock'),
  ('therapy_customer_entitlements(uuid,date)', 'stock'),
  ('therapy_customer_service_summary(uuid,date)', 'stock'),
  ('lend_stock(text,uuid,jsonb,date,uuid,text,text,uuid)', 'loan'),
  ('return_stock_loan(uuid,jsonb,text,uuid)', 'loan');
update roads set q = pg_temp.callsql(to_regprocedure('public.' || fn));
-- Real arguments where the page's own make the call reach its end.
update roads set q = pg_temp.new_invoice('x') where fn like 'create_invoice_with_details%';
update roads set q = pg_temp.settle('i2') where fn like 'record_invoice_settlement%';
update roads set q = format('select public.record_document_send(%L, %L, %L, %L::uuid, %L::uuid, %L)::text', 'invoice',
                            (select invoice_no from public.invoices where id = pg_temp.fx('i1')), 'whatsapp', pg_temp.fx('i1'), pg_temp.fx('c1'), pg_temp.ph(1))
 where fn like 'record_document_send%';
update roads set q = pg_temp.lend('store', true) where fn like 'lend_stock%';
update roads set q = pg_temp.giveback('l1') where fn like 'return_stock_loan%';
alter table roads add column stf_before text;

-- ═════ B Before 540 (install mode only) ═════
\if :by_us
update roads set stf_before = pg_temp.as_('stf', q);
select pg_temp.check(pg_temp.as_('invm', pg_temp.new_invoice('invm')) like 'ok:%', 'B1 before 540, an Inventory Manager makes an invoice');
select pg_temp.check(pg_temp.as_('invm', format('select count(*) from public.invoices where id = %L', pg_temp.fx('i1'))) = 'ok:1',
  'B2 before 540, an Inventory Manager reads the store''s invoices');
select pg_temp.check(pg_temp.leaks(pg_temp.as_('invm', format('select public.invoice_list_page(null, null, null, null, null, %L::uuid, null, null, 50, 0)::text', pg_temp.fx('st')))),
  'B3 before 540, the Invoices list gives an Inventory Manager the customer''s name');
select pg_temp.check(pg_temp.as_('invm', pg_temp.lend('store', true)) like 'ok:%', 'B4 before 540, an Inventory Manager lends stock to a customer');
select pg_temp.check(exists (select 1 from public.stock_movements where notes like '%lent to M540 ' || pg_temp.tok() || ' Alpha%'),
  'B5 before 540, a loan''s movement note names the borrower (it stays so after)');
\ir ../../../supabase/540_an_inventory_manager_works_with_stock_only.sql
\else
\echo NOTE  B is skipped (540 is not installed by this file)
\endif
create temp table fn1 as
  select p.oid::regprocedure::text as fn, md5(pg_get_functiondef(p.oid)) as md5, p.proacl::text as acl
    from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p');

-- ═════ R The roads ═════
select pg_temp.check(pg_temp.refused(pg_temp.as_('invm', q), key), 'R1 ' || split_part(fn, '(', 1) || ' refuses an Inventory Manager: ' || left(pg_temp.as_('invm', q), 110))
  from roads order by fn;
-- The same answer: the same refusal or error, or an answer (a new invoice or loan has a new id).
select pg_temp.check(case when :'mode' = 'install' then (pg_temp.as_('stf', q) like 'ok:%' and stf_before like 'ok:%') or pg_temp.as_('stf', q) = stf_before
                          else pg_temp.as_('stf', q) not like 'ERR 42501 An Inventory Manager%' end,
  'R2 ' || split_part(fn, '(', 1) || ' answers Staff as before 540: ' || left(pg_temp.as_('stf', q), 110))
  from roads order by fn;
select pg_temp.check(pg_temp.as_('stf', pg_temp.new_invoice('stf')) like 'ok:%' and pg_temp.as_('stf', pg_temp.settle('i2')) like 'ok:%',
  'R3 Staff still make an invoice and take its payment');

-- ═════ L Loans ═════
select pg_temp.check(pg_temp.refused(pg_temp.as_('invm', pg_temp.lend('store', true)), 'loan')
                     and pg_temp.refused(pg_temp.as_('invm', pg_temp.lend('store', false)), 'loan')
                     and pg_temp.refused(pg_temp.as_('invm', pg_temp.lend('warehouse', false)), 'loan')
                     and pg_temp.refused(pg_temp.as_('invm', pg_temp.giveback('l2')), 'loan'),
  'L1 an Inventory Manager may not lend (to a customer or a typed name, at the store or the warehouse) or take back: '
  || pg_temp.as_('invm', pg_temp.lend('warehouse', false)));
select pg_temp.check(pg_temp.as_('stf', pg_temp.lend('store', false)) like 'ok:%' and pg_temp.as_('mgr', pg_temp.lend('warehouse', false)) like 'ok:%'
                     and pg_temp.as_('stf', pg_temp.giveback('l1')) like 'ok:%' and pg_temp.as_('mgr', pg_temp.giveback('l2')) like 'ok:%',
  'L2 Staff lend and take back at the store, a Manager at the warehouse');
select pg_temp.as_('invm', format('select public.stock_loans_at(%L, %L::uuid, false)::text', 'store', pg_temp.fx('st'))) as l3im,
       pg_temp.as_('stf', format('select public.stock_loans_at(%L, %L::uuid, false)::text', 'store', pg_temp.fx('st'))) as l3st \gset
select pg_temp.check(:'l3im' like 'ok:%' and jsonb_array_length(substr(:'l3im', 4)::jsonb -> 'open') >= 1
                     and not pg_temp.leaks(:'l3im') and substr(:'l3im', 4)::jsonb -> 'open' -> 0 ? 'loan_no'
                     and not (substr(:'l3im', 4)::jsonb -> 'open' -> 0 ? 'borrower') and not (substr(:'l3im', 4)::jsonb -> 'open' -> 0 ? 'borrower_phone'),
  'L3 an Inventory Manager sees the store''s loans with no borrower or phone (can_act stays theirs: it is also Record use): ' || left(:'l3im', 140));
select pg_temp.check(pg_temp.leaks(:'l3st') and (substr(:'l3st', 4)::jsonb ->> 'can_act') = 'true',
  'L4 Staff see the borrower and may act, as before');
select pg_temp.check(pg_temp.as_('invm', format('select public.stock_loans_at(%L, %L::uuid, false)::text', 'warehouse', pg_temp.fx('wh'))) like 'ok:%'
                     and not pg_temp.leaks(pg_temp.as_('invm', format('select public.stock_loans_at(%L, %L::uuid, false)::text', 'warehouse', pg_temp.fx('wh')))),
  'L5 at the warehouse too: the loans, no borrower');
select pg_temp.must('stf', pg_temp.lend('store', true)) \g /dev/null
select pg_temp.put('l3', (select id from public.stock_loans where customer_id = pg_temp.fx('c1') order by lent_at desc, loan_no desc limit 1)) \g /dev/null
select pg_temp.must('stf', pg_temp.giveback('l3')) \g /dev/null
select (select loan_no from public.stock_loans where id = pg_temp.fx('l3')) as l3no \gset
select pg_temp.check((select string_agg(m.notes, ' | ' order by m.created_at) from public.stock_movements m
                       where m.notes like :'l3no' || ' %')
                     = :'l3no' || ' lent (Trial), due back ' || to_char(public.sg_today() + 7, 'DD Mon YYYY') || ' | ' || :'l3no' || ' returned',
  'L6 the new movement notes carry the loan number only: ' || coalesce((select string_agg(m.notes, ' | ' order by m.created_at) from public.stock_movements m where m.notes like :'l3no' || ' %'), 'none'));
select pg_temp.check((select borrower_name is null and customer_id = pg_temp.fx('c1') from public.stock_loans where id = pg_temp.fx('l3')),
  'L7 the borrower stays on the loan record');

-- ═════ T Reads ═════
select pg_temp.check(pg_temp.as_('invm', format('select count(*) from public.%I', t)) = 'ok:0',
  'T1 an Inventory Manager of the store reads no row of ' || t || ': ' || pg_temp.as_('invm', format('select count(*) from public.%I', t)))
  from unnest(array['invoices', 'invoice_items', 'invoice_payments', 'customers', 'customer_phone_history', 'stock_loans', 'stock_loan_lines',
                    'stock_loan_events', 'document_sends', 'invoice_handovers', 'invoice_voucher_movements', 'product_exchanges',
                    'therapy_entitlement_invoices', 'credit_package_sales', 'credit_package_split_allocations', 'premium_bundle_sales',
                    'premium_bundle_split_allocations', 'special_credit_allocations', 'purchased_therapy_entitlements', 'therapy_entitlements',
                    'therapy_expiry_adjustments', 'therapy_qualification_topups', 'therapy_voucher_issues', 'customer_therapy_sessions',
                    'customer_reward_vouchers', 'voucher_claims', 'voucher_redemptions', 'customer_affiliates', 'rentals', 'special_sales']) t;
select pg_temp.check(pg_temp.as_('stf', format('select count(*) > 0 from public.%I where %s', t, w)) = 'ok:true',
  'T2 Staff still read ' || t)
  from (values ('invoices', format('id = %L', pg_temp.fx('i1'))), ('customers', format('id = %L', pg_temp.fx('c1'))),
               ('customer_phone_history', format('customer_id = %L', pg_temp.fx('c1'))), ('stock_loans', format('id = %L', pg_temp.fx('l1'))),
               ('document_sends', format('doc_id = %L', pg_temp.fx('i1'))), ('customer_affiliates', format('id = %L', pg_temp.fx('a2')))) x(t, w);

-- ═════ K The stock work an Inventory Manager keeps ═════
select pg_temp.check(pg_temp.as_('invm', q) like 'ok:%', 'K1 an Inventory Manager runs ' || label || ': ' || left(pg_temp.as_('invm', q), 100))
  from (values
    ('warehouse stock in', format('select public.warehouse_stock_in(%L::uuid, %L::uuid, 1, %L)::text', pg_temp.fx('wh'), pg_temp.fx('p'), 'Delivery')),
    ('a stock correction', format('select public.request_inventory_adjustments(%L, %L::uuid, %L::jsonb, %L, null, gen_random_uuid())::text', 'store', pg_temp.fx('st'),
       jsonb_build_array(jsonb_build_object('product_id', pg_temp.fx('p'), 'new_qty', 40)), 'Counted')),
    ('a stock use', format('select public.record_stock_uses(%L, %L::uuid, %L::jsonb, %L, null, gen_random_uuid())::text', 'store', pg_temp.fx('st'),
       jsonb_build_array(jsonb_build_object('product_id', pg_temp.fx('p'), 'quantity', 1)), 'Tester')),
    ('a transfer request', format('select public.create_transfer_request(%L, %L, %L::uuid, %L, %L::uuid, %L::jsonb, null)::text', 'warehouse_to_store', 'warehouse', pg_temp.fx('wh'),
       'store', pg_temp.fx('st'), jsonb_build_array(jsonb_build_object('line_kind', 'product', 'product_id', pg_temp.fx('p'), 'quantity', 2)))),
    ('a product save', format('select public.save_product(%L::uuid, %L::jsonb, null, null)::text', pg_temp.fx('p'), '{"low_stock_threshold": 3}')),
    ('a TikTok file', format('select public.stage_tiktok_orders(%L::uuid, %L, null, %L::jsonb)::text', pg_temp.fx('st'), 'M540.csv',
       jsonb_build_array(jsonb_build_object('order_id', 'M540-1', 'seller_sku', 'M540-SKU', 'quantity', '1', 'order_status', 'Shipped', 'product_name', 'M540 item')))),
    ('Stock History', format('select count(*)::text from public.stock_history_page(%L::jsonb, 100, 0, null)',
       jsonb_build_object('from', public.sg_today() - 30, 'to', public.sg_today(), 'search', '', 'products', '[]'::jsonb,
                          'locations', '[]'::jsonb, 'people', '[]'::jsonb, 'types', '[]'::jsonb))),
    ('the Dashboard sales', format('select public.dashboard_sales(%L, null, null, null)::text', 'day')),
    ('the Dashboard sales by store', format('select public.dashboard_sales_by_store(%L, null, null)::text', 'day')),
    ('the Dashboard alerts', 'select public.dashboard_alerts_summary()::text'),
    ('the transfer alerts', 'select public.transfer_receipt_alerts()::text'),
    ('the TikTok stock alerts', 'select count(*)::text from public.tiktok_negative_stock_alerts()'),
    ('the takings by method', 'select count(*)::text from public.daily_payments_by_method(null, null, null)'),
    ('the sales ledger', 'select count(*)::text from public.invoice_sales_ledger()'),
    ('the FOC lines', 'select count(*)::text from public.report_foc_lines(null, null, null)'),
    ('the loans list', format('select public.stock_loans_at(%L, %L::uuid, false)::text', 'store', pg_temp.fx('st')))) x(label, q);

-- ═════ D What an Inventory Manager keeps ═════
select pg_temp.check(pg_temp.as_('invm', q) like 'ok:%' and not pg_temp.leaks(pg_temp.as_('invm', q)),
  'D1 an Inventory Manager keeps ' || label || ': ' || left(pg_temp.as_('invm', q), 90))
  from (values ('the day''s sales', format('select public.dashboard_sales(%L, null, null, %L::uuid)::text', 'day', pg_temp.fx('st'))),
               ('sales by store', format('select public.dashboard_sales_by_store(%L, null, null)::text', 'day')),
               ('takings by method', format('select count(*)::text from public.daily_payments_by_method(null, null, %L::uuid)', pg_temp.fx('st'))),
               ('the Dashboard alerts', 'select public.dashboard_alerts_summary()::text'),
               ('transfer alerts', 'select public.transfer_receipt_alerts()::text'),
               ('their stores', 'select count(*)::text from public.my_assigned_stores()')) x(label, q);
select pg_temp.check(substr(pg_temp.as_('invm', format('select public.dashboard_sales(%L, null, null, %L::uuid)::text', 'day', pg_temp.fx('st'))), 4)::jsonb ->> 'sales'
                     = substr(pg_temp.as_('stf', format('select public.dashboard_sales(%L, null, null, %L::uuid)::text', 'day', pg_temp.fx('st'))), 4)::jsonb ->> 'sales',
  'D2 the sales total an Inventory Manager sees is Staff''s');
select pg_temp.as_('invm', format('select string_agg(coalesce(customer_name, %L) || %L || foc_value, %L) from public.report_foc_lines(null, null, %L::uuid)', '-', '/', ',', pg_temp.fx('st'))) as d3im,
       pg_temp.as_('stf', format('select string_agg(coalesce(customer_name, %L) || %L || foc_value, %L) from public.report_foc_lines(null, null, %L::uuid)', '-', '/', ',', pg_temp.fx('st'))) as d3st \gset
select pg_temp.check(:'d3im' like 'ok:-/%' and not pg_temp.leaks(:'d3im') and pg_temp.leaks(:'d3st')
                     and split_part(:'d3im', '/', 2) = split_part(:'d3st', '/', 2),
  'D3 the Dashboard''s FOC lines: the same values, the customer''s name for Staff only: ' || :'d3im' || ' | ' || left(:'d3st', 60));

-- ═════ W "No invoicing" by any route ═════
select pg_temp.check(pg_temp.refused(pg_temp.as_('pg:invm', format('with u as (update public.%I set id = id where false returning id) select count(*) from u', t)), 'invoice'),
  'W1 a server function''s write of ' || t || ' for an Inventory Manager is refused')
  from unnest(array['invoices', 'invoice_items', 'invoice_payments']) t;
select pg_temp.check(pg_temp.as_(w, format('with u as (update public.%I set id = id where false returning id) select count(*) from u', t)) = 'ok:0',
  'W2 the same write passes for ' || w || ' (' || t || ')')
  from unnest(array['pg:stf', 'pg:mgr', 'pg:own', 'pg:adm', 'nologin', 'service']) w, unnest(array['invoices', 'invoice_payments']) t
 where not (w = 'service' and t = 'invoice_payments');
select pg_temp.check(pg_temp.as_('nologin', 'select public.inventory_manager_guard(''invoice'')::text') = 'ok:'
                     and pg_temp.as_('service', 'select public.inventory_manager_guard(''invoice'')::text') = 'ok:'
                     and pg_temp.as_('stf', 'select public.inventory_manager_guard(''invoice'')::text') = 'ok:'
                     and pg_temp.refused(pg_temp.as_('invm', 'select public.inventory_manager_guard(''invoice'')::text'), 'invoice'),
  'W3 the guard passes the server''s own work (no login: cron, website orders, event VIP invoices), the secret key and Staff, and refuses an Inventory Manager');

-- ═════ X The generated check ═════
create temp table xcand as
  select p.oid, p.oid::regprocedure::text as fn
    from pg_proc p, lateral (select pg_get_functiondef(p.oid) d) x
   where p.pronamespace = 'public'::regnamespace and p.prokind = 'f'
     and has_function_privilege('authenticated', p.oid, 'execute') and p.prorettype <> 'trigger'::regtype
     and ((x.d ~* '\mcustomers\M' and x.d ~* '\m(full_name|phone)\M') or x.d ~* 'borrower_name|stock_loan_json'
          or p.proname ~ 'invoice|exchange'
          or p.proname in ('report_pricing', 'therapy_customer_detail', 'customer_overview', 'affiliate_staff_directory',
                           'customer_match_candidates', 'purchased_therapy_units', 'report_discounts', 'report_foc_lines',
                           'therapy_recalculation_preview', 'therapy_closure_impact', 'therapy_list_page',
                           'activate_purchased_therapy', 'choose_therapy_benefit', 'reschedule_purchased_therapy',
                           'record_document_printed', 'record_document_send'));
create temp table xrun as select c.fn, pg_temp.callsql(c.oid) as q from xcand c;
alter table xrun add column invm text, add column own text;
update xrun set invm = pg_temp.as_('invm', q), own = pg_temp.as_('own', q);
select count(*) as x_n, count(*) filter (where invm like 'ERR%') as x_refused, count(*) filter (where pg_temp.leaks(own)) as x_owner_sees,
       count(*) filter (where pg_temp.leaks(invm)) as x_leaks from xrun \gset
\echo NOTE  X: :x_n functions; refused or failed for the Inventory Manager: :x_refused; the Owner answer showed the made-up names in :x_owner_sees
select pg_temp.check(:x_leaks = 0 and :x_n >= 140,
  format('X1 none of the %s functions gives an Inventory Manager a made-up customer''s or borrower''s name or phone (%s refused or failed; the Owner saw the names in %s): %s',
         :x_n, :x_refused, :x_owner_sees, coalesce((select string_agg(fn, ', ') from xrun where pg_temp.leaks(invm)), 'none')));

-- ═════ G 540's fixed parts ═════
\if :is_control
\echo NOTE  G, U and M are skipped (control)
\else
select pg_temp.check((select string_agg(x::text, ',' order by x::text) from pg_proc p, unnest(p.proacl) x where p.oid = 'public.inventory_manager_guard(text)'::regprocedure)
                       = 'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres'
                     and not has_function_privilege('anon', 'public.inventory_manager_guard(text)', 'execute')
                     and (select string_agg(x::text, ',') from pg_proc p, unnest(p.proacl) x where p.oid = 'public.no_invoicing_for_inventory_managers()'::regprocedure) = 'postgres=X/postgres',
  'G1 the guard for signed-in logins and the service role (four callers run as their caller), the trigger function postgres''s alone');
select pg_temp.check((select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace
                        and pg_get_functiondef(p.oid) ~ 'inventory_manager_guard\(''(invoice|loan|stock)''\);  -- 540 ') = 66,
  'G2 the guard runs first in 66 functions');
select pg_temp.check((select count(*) from pg_trigger t where t.tgname = 'no_invoicing_for_inventory_managers' and t.tgenabled = 'O'
                        and t.tgrelid in ('public.invoices'::regclass, 'public.invoice_items'::regclass, 'public.invoice_payments'::regclass)) = 3,
  'G3 the "No invoicing" trigger is on invoices, invoice lines and invoice payments');
select pg_temp.check((select count(*) from pg_policy p join pg_class c on c.oid = p.polrelid
                       where c.relnamespace = 'public'::regnamespace and p.polcmd = 'r'
                         and pg_get_expr(p.polqual, p.polrelid) like '((( SELECT current_user_role() AS current_user_role) IS DISTINCT FROM ''inventory_manager''::user_role) AND %') = 24,
  'G4 the 24 read rules leave an Inventory Manager out');
\if :by_us
select pg_temp.check((select count(*) from fn0 a full join fn1 b using (fn) where a.md5 is distinct from b.md5 or a.acl is distinct from b.acl) = 70,
  'G5 installed here, only the 68 functions and the two new ones changed: '
  || (select count(*) from fn0 a full join fn1 b using (fn) where a.md5 is distinct from b.md5 or a.acl is distinct from b.acl));
-- ═════ U The undo, then 540 again ═════
savepoint u1;
\ir ../undo-540.sql
select pg_temp.check(not exists (select 1 from fn0 a full join (select p.oid::regprocedure::text as fn, md5(pg_get_functiondef(p.oid)) as md5, p.proacl::text as acl
                                                                   from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p')) b using (fn)
                                  where a.md5 is distinct from b.md5 or a.acl is distinct from b.acl)
                     and not exists (select 1 from pol0 a full join (select c.relname, p.polname, pg_get_expr(p.polqual, p.polrelid) as qual
                                                                         from pg_policy p join pg_class c on c.oid = p.polrelid where c.relnamespace = 'public'::regnamespace) b
                                       using (relname, polname) where a.qual is distinct from b.qual)
                     and not exists (select 1 from pg_trigger where tgname = 'no_invoicing_for_inventory_managers'),
  'U1 undo-540 puts every function, grant and read rule back exactly, and drops the triggers');
select pg_temp.check(pg_temp.as_('invm', pg_temp.new_invoice('invm')) like 'ok:%', 'U2 after the undo an Inventory Manager makes an invoice again (as before 540)');
savepoint u2;
\set ON_ERROR_STOP off
\ir ../undo-540.sql
\set ON_ERROR_STOP on
rollback to savepoint u2;
select pg_temp.check(:'LAST_ERROR_MESSAGE' like 'undo 540: % is already its version of before 540%', 'U3 the undo a second time refuses: ' || :'LAST_ERROR_MESSAGE');
\ir ../../../supabase/540_an_inventory_manager_works_with_stock_only.sql
select pg_temp.check(not exists (select 1 from (select p.oid::regprocedure::text as fn, md5(pg_get_functiondef(p.oid)) as md5, p.proacl::text as acl
                                                  from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p')) a
                                  full join fn1 b using (fn) where a.md5 is distinct from b.md5 or a.acl is distinct from b.acl),
  'U4 540 after the undo makes exactly what it made the first time');
rollback to savepoint u1;
savepoint m1;
\set ON_ERROR_STOP off
\ir ../../../supabase/540_an_inventory_manager_works_with_stock_only.sql
\set ON_ERROR_STOP on
rollback to savepoint m1;
select pg_temp.check(:'LAST_ERROR_MESSAGE' like '540 is already in on this database%', 'M1 540 a second time refuses: ' || :'LAST_ERROR_MESSAGE');
\else
\echo NOTE  G5, U and M are skipped (540 was not installed by this file)
\endif
\endif

select count(*) as n_failed from failed \gset
\if :is_control
\echo control: :n_failed checks failed without 540 (each is one 540 makes pass)
select string_agg(split_part(msg, ' ', 1), ' ' order by n) as control_failed from failed \gset
\echo control failed: :control_failed
rollback;
\else
do $$ begin
  if (select count(*) from failed) > 0 then
    raise exception '% check(s) failed: %', (select count(*) from failed), (select string_agg(msg, E'\n' order by n) from failed);
  end if;
  raise notice 'ALL PASSED';
end $$;
rollback;
\endif
