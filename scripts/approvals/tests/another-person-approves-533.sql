-- A Manager does not approve what they asked for or shaped, approves only for their own stores,
-- takes back up to S$1,000 on an invoice, and leaves credit by hand, credit given free or moved,
-- and payouts to an Owner (533; security audit of 17 Nov 2026, M9; the user, 20 Nov 2026).
--
-- Every call is made as the pages make it: a signed-in login (the authenticated role, its JWT)
-- calling the page's server function; a function no login may call is called as the database
-- owner with that login's claims, as the server function that reaches it calls it. The logins: an
-- Owner, Managers 1 and 2 working at stores A and B, Manager 3 working at store A only, Staff of
-- store A, an Admin.
--
--   T  Transfers. A Manager's own request: their Review & Dispatch is refused; the other Manager
--      dispatches it; they still reject or withdraw it. An Owner dispatches their own. A request
--      to store B: Manager 3 cannot dispatch or reject it, Manager 1 can; a warehouse to
--      warehouse request is open to Manager 3; a store chosen as a source must be theirs too.
--      A request a Manager edited (even when someone edited it after them): refused for them, the
--      other Manager dispatches it. A line added or a quantity raised while approving: refused
--      for a Manager, a lower quantity passes; an Owner adds and raises.
--   D  Discrepancies. A Manager who received the transfer (a shortage, or extra units waiting
--      since 510) cannot resolve it; the other Manager can; an Owner resolves one they received.
--      A transfer to store B: Manager 3 cannot resolve it, Manager 1 can.
--   A  Stock corrections. A Manager's own: their approval is refused, their rejection works, the
--      other Manager approves; an Owner approves their own. At store B Manager 3 cannot approve;
--      at a warehouse they can.
--   I  Invoice requests. A Manager's own refund request: their approval is refused, their
--      rejection works, the other Manager approves; an Owner approves their own. A Staff
--      cancellation approved by a Manager with the refund recorded still reaches
--      cancel_invoice_recorded.
--   C  The S$1,000 limit, refunds and lowered payments together: refunds to S$1,000 exactly pass,
--      S$0.01 more is refused, an Owner records above it; S$1,000.01 in one refund is refused; a
--      retry of a refund is not counted twice; a Staff request above it waits for an Owner (a
--      Manager's approval is refused, the Owner's passes); a payment a Manager lowers by
--      S$1,100 is refused, by S$900 passes and then only S$100 of refunds is left; a change of
--      date alone passes; a Manager removing a S$1,500 payment, or splitting it into S$100 +
--      S$100, is refused, an Owner does both; a split within the limit passes; a payment lowered
--      by S$500 and a refund of S$500 leave nothing for S$0.01 more.
--   R  Credit by hand: a Manager (and an Admin) cannot add, enter old balances or reverse; an
--      Owner can; a Manager still reads the balances.
--   P  Payouts: a Manager cannot record or correct an affiliate payout, record or void an
--      affiliate repayment, or record a staff commission payout; an Owner passes the role test;
--      a Manager still reads the payouts.
--   F  Make FOC on a credit package line: a Manager is refused, an Owner makes it; Staff still
--      make a product line free; a new invoice still refuses a credit package made free (355).
--   X  Moving unused credit or vouchers to another customer: a Manager is refused; an Owner
--      passes the role test.
--   W  Decision 10: a Manager cannot change a payment into or out of wallet credit through
--      correct_invoice_payment (wallet to PayNow, PayNow to wallet); an Owner does both, the credit
--      going back and being taken as before; a Manager changes PayNow to NETS, and Paid credit to
--      Bonus credit (both wallet). The other routes refuse a wallet method for everyone, Owners
--      included, with the sentences they had before 533: Edit Invoice's method change, a split of a
--      wallet payment or with a wallet part, and removing a wallet payment.
--   K  cancel_invoice_recorded and the old request_inventory_adjustment cannot be called by a
--      login; the page's request_inventory_adjustments still works.
--   G  533's fixed parts: the md5s and grants of the eighteen functions and two helpers, the
--      helpers closed to logins, the relied-on functions unchanged; installed here, only those
--      twenty functions and the two grants differ from before.
--   U  scripts/approvals/undo-533.sql puts every function and grant back exactly, refuses a
--      second time; 533 again makes exactly what it made.
--   M  533 a second time refuses ("533 is already in") and changes nothing.
--
-- Disposable local database only; everything is rolled back. Every name and number is invented
-- (M533-…, @example.invalid, INV-9001-…); phones are the fictional +61 491 570 nnn range. Run it on
-- a copy of production without 533 (it applies 533, then again); with -v skip_install=1 where 533
-- is already in (G is partly skipped, U and M are skipped); with -v control=1 on a copy WITHOUT
-- 533 (it does not install it, skips G, U and M, and fails on exactly the checks 533 makes pass).
-- Every check runs, then the file fails if any did.
--   psql -X -v ON_ERROR_STOP=1 -f scripts/approvals/tests/another-person-approves-533.sql
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '10s';
set local statement_timeout = '300s';
create temp table fn0 as
  select p.oid::regprocedure::text as fn, md5(pg_get_functiondef(p.oid)) as md5, p.proacl::text as acl
    from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p');
select position('533 (security audit' in coalesce(pg_get_functiondef(to_regprocedure('public.refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid)')), '')) > 0 as had533 \gset
\if :{?control}
\if :had533
\echo control: 533 is in on this copy; run -v control=1 on a copy without it
select 1/0;
\endif
\set mode control
\elif :{?skip_install}
\if :had533
\else
\echo 533 is not in: run without -v skip_install
select 1/0;
\endif
\set mode skip
\elif :had533
\echo 533 is already in: run with -v skip_install=1
select 1/0;
\else
\ir ../../../supabase/533_approvals_need_another_person_and_owner_limits.sql
\set mode install
\endif
create temp table fn1 as
  select p.oid::regprocedure::text as fn, md5(pg_get_functiondef(p.oid)) as md5, p.proacl::text as acl
    from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p');
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
create temp table sfx as select lower(substr(md5(gen_random_uuid()::text), 1, 6)) as s;
create function pg_temp.sfx() returns text language sql as $$ select s from sfx $$;

-- The sentences the pages show (the data contract).
create function pg_temp.s(key text) returns text language sql as $$
  select case key
    when 'own_transfer' then 'A Manager cannot approve their own transfer request. An Owner or another Manager approves it.'
    when 'edited' then 'A Manager who changed this transfer request cannot also approve it. An Owner or another Manager approves it.'
    when 'shaped' then 'A Manager cannot add lines or raise quantities while approving a transfer. An Owner or another Manager approves such a change.'
    when 'own_correction' then 'A Manager cannot approve their own stock correction. An Owner or another Manager approves it.'
    when 'own_request' then 'A Manager cannot approve their own request. An Owner or another Manager approves it.'
    when 'received' then 'A Manager cannot resolve a transfer they received themselves. An Owner or another Manager resolves it.'
    when 'store' then 'A Manager approves only for the stores they work at.'
    when 'credit' then 'Only an Owner can add or remove credit by hand.'
    when 'payout' then 'Only an Owner can record or correct an affiliate payout.'
    when 'cap' then 'A Manager can take back up to S$1,000 on an invoice, refunds and lowered payments together; an Owner does anything above that.'
    when 'foc' then 'Only an Owner can make a credit package or premium bundle line free.'
    when 'move' then 'Only an Owner can move unused credit or vouchers to another customer.'
    when 'repayment' then 'Only an Owner can record or void an affiliate repayment.'
    when 'staff_payout' then 'Only an Owner can record a staff commission payout.' end $$;
create function pg_temp.refused(t text, key text) returns boolean language sql as $$ select t = 'ERR 42501 ' || pg_temp.s(key) $$;
-- Passed the role test: succeeded, or refused for something else than any 533 sentence or a role.
create function pg_temp.past(t text) returns boolean language sql as $$
  select t like 'ok:%' or (t like 'ERR %' and t not like 'ERR 42501 %') $$;

-- One statement as someone: a signed-in login (its key), 'anon', or 'pg:<login>' (the database
-- owner with that login's claims, as a server function's own call). 'ok:<first column>', or
-- 'ERR <sqlstate> <message>'.
create function pg_temp.as_(who text, q text) returns text language plpgsql as $f$
declare v text; s text; m text;
begin
  begin
    if who = 'anon' then
      perform set_config('request.jwt.claim.sub', '', true);
      perform set_config('request.jwt.claim.role', 'anon', true);
      perform set_config('request.jwt.claims', '{"role":"anon"}', true);
      execute 'set local role anon';
    elsif who like 'pg:%' then
      perform set_config('request.jwt.claim.sub', pg_temp.fx(substr(who, 4))::text, true);
      perform set_config('request.jwt.claim.role', 'authenticated', true);
      perform set_config('request.jwt.claims', json_build_object('sub', pg_temp.fx(substr(who, 4)), 'role', 'authenticated')::text, true);
    else
      perform set_config('request.jwt.claim.sub', pg_temp.fx(who)::text, true);
      perform set_config('request.jwt.claim.role', 'authenticated', true);
      perform set_config('request.jwt.claims', json_build_object('sub', pg_temp.fx(who), 'role', 'authenticated')::text, true);
      execute 'set local role authenticated';
    end if;
    execute q into v;
    execute 'reset role';
    return 'ok:' || coalesce(v, '');
  exception when others then
    get stacked diagnostics s = returned_sqlstate, m = message_text;
    execute 'reset role';
    return 'ERR ' || s || ' ' || m;
  end;
end $f$;
-- The same, and a fixture step that must work: its first column.
create function pg_temp.must(who text, q text) returns text language plpgsql as $f$
declare t text := pg_temp.as_(who, q);
begin
  if t not like 'ok:%' then raise exception 'FIXTURE (%): % -> %', who, q, t; end if;
  return substr(t, 4);
end $f$;

-- ═════ Fixtures (invented), as the database owner ═════
do $fx$
declare r record; u uuid; s text := pg_temp.sfx();
begin
  for r in select * from (values ('own', 'owner'), ('mgr1', 'manager'), ('mgr2', 'manager'), ('mgr3', 'manager'),
                                 ('stf', 'staff'), ('adm', 'admin')) t(k, role) loop
    insert into auth.users(id, email, email_confirmed_at)
    values (gen_random_uuid(), 'm533-' || r.k || '-' || s || '@example.invalid', now()) returning id into u;
    insert into public.profiles(id, full_name, email, role, is_active)
    values (u, 'M533 ' || r.k, 'm533-' || r.k || '-' || s || '@example.invalid', r.role::public.user_role, true);
    perform pg_temp.put(r.k, u);
  end loop;
  insert into public.stores(name, code, country_code) values ('M533 Store A', 'M533A' || s, 'SG') returning id into u; perform pg_temp.put('sa', u);
  insert into public.stores(name, code, country_code) values ('M533 Store B', 'M533B' || s, 'SG') returning id into u; perform pg_temp.put('sb', u);
  insert into public.warehouses(name, code) values ('M533 Warehouse 1', 'M533W1' || s) returning id into u; perform pg_temp.put('w1', u);
  insert into public.warehouses(name, code) values ('M533 Warehouse 2', 'M533W2' || s) returning id into u; perform pg_temp.put('w2', u);
  -- Managers 1 and 2 work at stores A and B, Manager 3 at store A only, Staff at store A.
  insert into public.user_store_assignments(user_id, store_id)
  values (pg_temp.fx('mgr1'), pg_temp.fx('sa')), (pg_temp.fx('mgr1'), pg_temp.fx('sb')),
         (pg_temp.fx('mgr2'), pg_temp.fx('sa')), (pg_temp.fx('mgr2'), pg_temp.fx('sb')),
         (pg_temp.fx('mgr3'), pg_temp.fx('sa')), (pg_temp.fx('stf'), pg_temp.fx('sa'));
  insert into public.products(name, sku, product_type) values ('M533 Pillow', 'M533-P-' || s, 'own') returning id into u; perform pg_temp.put('p', u);
  insert into public.products(name, sku, product_type) values ('M533 Towel', 'M533-T-' || s, 'own') returning id into u; perform pg_temp.put('p2', u);
  -- A service (no stock): the invoices below sell it, so a refund asks no stock question.
  insert into public.products(name, sku, product_type) values ('M533 Session', 'M533-S-' || s, 'no_commission') returning id into u; perform pg_temp.put('sv', u);
  insert into public.warehouse_inventory(warehouse_id, product_id, current_qty)
  values (pg_temp.fx('w1'), pg_temp.fx('p'), 500), (pg_temp.fx('w2'), pg_temp.fx('p'), 500),
         (pg_temp.fx('w1'), pg_temp.fx('p2'), 500), (pg_temp.fx('w2'), pg_temp.fx('p2'), 500);
  insert into public.store_inventory(store_id, product_id, current_qty)
  values (pg_temp.fx('sa'), pg_temp.fx('p'), 500), (pg_temp.fx('sb'), pg_temp.fx('p'), 500),
         (pg_temp.fx('sa'), pg_temp.fx('p2'), 500), (pg_temp.fx('sb'), pg_temp.fx('p2'), 500);
  insert into public.customers(full_name, phone) values ('M533 Buyer', '+61491570533') returning id into u; perform pg_temp.put('c', u);
  insert into public.customers(full_name, phone) values ('M533 Other', '+61491570534') returning id into u; perform pg_temp.put('c2', u);
  insert into public.customers(full_name, phone) values ('M533 Wallet', '+61491570535') returning id into u; perform pg_temp.put('cw', u);
  -- A second money method, and two wallet-credit methods (Paid and Bonus credit).
  insert into public.payment_methods(name, is_active) values ('M533 NETS ' || s, true) returning id into u; perform pg_temp.put('nets', u);
  insert into public.payment_methods(name, is_active, is_wallet_credit, wallet_category)
    values ('M533 Wallet Paid ' || s, true, true, 'paid') returning id into u; perform pg_temp.put('wpaid', u);
  insert into public.payment_methods(name, is_active, is_wallet_credit, wallet_category)
    values ('M533 Wallet Bonus ' || s, true, true, 'bonus') returning id into u; perform pg_temp.put('wbonus', u);
  insert into public.payment_methods(name, is_active) values ('M533 PayNow ' || s, true) returning id into u; perform pg_temp.put('pm', u);
  insert into public.credit_packages(name, customer_price, paid_credit_amount, allow_product, allow_therapy)
    values ('M533 Package ' || s, 1000, 1000, true, true) returning id into u; perform pg_temp.put('cp', u);
  insert into public.credit_package_stores(package_id, store_id) values (pg_temp.fx('cp'), pg_temp.fx('sa'));
end $fx$;
do $fx2$
begin
  perform pg_temp.must('own', format('select public.set_product_prices(%L, %L, 10, 10, %L)::text', pg_temp.fx('sa'), pg_temp.fx('p'), 'available'));
  perform pg_temp.must('own', format('select public.set_product_prices(%L, %L, 10, 10, %L)::text', pg_temp.fx('sb'), pg_temp.fx('p'), 'available'));
  perform pg_temp.must('own', format('select public.set_product_prices(%L, %L, 10, 10, %L)::text', pg_temp.fx('sa'), pg_temp.fx('p2'), 'available'));
  perform pg_temp.must('own', format('select public.set_product_prices(%L, %L, 10, 10, %L)::text', pg_temp.fx('sb'), pg_temp.fx('p2'), 'available'));
  perform pg_temp.must('own', format('select public.set_product_prices(%L, %L, 1500, 1500, %L)::text', pg_temp.fx('sa'), pg_temp.fx('sv'), 'available'));
end $fx2$;

-- ── Transfer helpers ──
-- A request made by who: qty of p from src to dest; kept as fx(name); its line as fx(name || ':l').
create function pg_temp.treq(name text, who text, src_type text, src text, dest_type text, dest text, qty int) returns uuid language plpgsql as $$
declare r uuid;
begin
  r := (pg_temp.must(who, format('select (public.create_transfer_request(%L, %L, %L, %L, %L, %L::jsonb, %L)->>''id'')',
         src_type || '_to_' || dest_type, src_type, pg_temp.fx(src), dest_type, pg_temp.fx(dest),
         jsonb_build_array(jsonb_build_object('product_id', pg_temp.fx('p'), 'quantity', qty)), 'M533 ' || name)))::uuid;
  perform pg_temp.put(name, r);
  perform pg_temp.put(name || ':l', (select id from public.transfer_request_lines where transfer_request_id = r));
  return r;
end $$;
-- Review & Dispatch by who: the line approved at qty from (src_type, src); extra: more entries.
create function pg_temp.dispatch(who text, name text, qty int, src_type text, src text, extra jsonb default '[]'::jsonb) returns text language sql as $$
  select pg_temp.as_(who, format('select public.review_and_dispatch_transfer(%L, %L::jsonb, %L)::text', pg_temp.fx(name),
    jsonb_build_array(jsonb_build_object('line_id', pg_temp.fx(name || ':l'), 'approved_quantity', qty,
      'sources', jsonb_build_array(jsonb_build_object('source_type', src_type, 'source_id', pg_temp.fx(src), 'quantity', qty)))) || extra,
    'M533 dispatch')) $$;
create function pg_temp.receive(who text, name text, qty int) returns text language sql as $$
  select pg_temp.as_(who, format('select public.receive_transfer(%L, %L::jsonb, %L, false)::text', pg_temp.fx(name),
    jsonb_build_array(jsonb_build_object('line_id', pg_temp.fx(name || ':l'), 'received_quantity', qty)), 'M533 count')) $$;
create function pg_temp.resolve(who text, name text, res text) returns text language sql as $$
  select pg_temp.as_(who, format('select public.resolve_transfer_discrepancy(%L, %L::jsonb, null)::text', pg_temp.fx(name),
    jsonb_build_array(jsonb_build_object('line_id', pg_temp.fx(name || ':l'), 'resolution', res, 'reason', 'M533 ' || res)))) $$;
create function pg_temp.tstatus(name text) returns text language sql as $$
  select status::text from public.transfer_requests where id = pg_temp.fx(name) $$;

-- ═════ T Transfers ═════
-- Each check has its own request, so without 533 (control) only the checks 533 makes pass fail.
do $T$
declare t text;
begin
  -- T1 a Manager's own request
  perform pg_temp.treq('t1', 'mgr1', 'warehouse', 'w1', 'store', 'sa', 5);
  t := pg_temp.dispatch('mgr1', 't1', 5, 'warehouse', 'w1');
  perform pg_temp.check(pg_temp.refused(t, 'own_transfer') and pg_temp.tstatus('t1') = 'pending',
    'T1 a Manager cannot dispatch their own transfer request: ' || t);
  perform pg_temp.treq('t1b', 'mgr1', 'warehouse', 'w1', 'store', 'sa', 5);
  t := pg_temp.dispatch('mgr2', 't1b', 5, 'warehouse', 'w1');
  perform pg_temp.check(t like 'ok:%' and pg_temp.tstatus('t1b') = 'in_transit', 'T1b the other Manager dispatches it: ' || t);
  -- T2 an Owner's own
  perform pg_temp.treq('t2', 'own', 'warehouse', 'w1', 'store', 'sa', 5);
  t := pg_temp.dispatch('own', 't2', 5, 'warehouse', 'w1');
  perform pg_temp.check(t like 'ok:%' and pg_temp.tstatus('t2') = 'in_transit', 'T2 an Owner still dispatches their own request: ' || t);
  -- T3 a Manager rejects, and withdraws, their own
  perform pg_temp.treq('t3', 'mgr1', 'warehouse', 'w1', 'store', 'sa', 5);
  t := pg_temp.as_('mgr1', format('select public.reject_transfer(%L, %L)::text', pg_temp.fx('t3'), 'M533 not needed'));
  perform pg_temp.check(t like 'ok:%' and pg_temp.tstatus('t3') = 'rejected', 'T3 a Manager still rejects their own request: ' || t);
  perform pg_temp.treq('t3w', 'mgr1', 'warehouse', 'w1', 'store', 'sa', 5);
  t := pg_temp.as_('mgr1', format('select public.cancel_transfer_request(%L)::text', pg_temp.fx('t3w')));
  perform pg_temp.check(t like 'ok:%' and pg_temp.tstatus('t3w') <> 'pending', 'T3b a Manager still withdraws their own request: ' || t);
  -- T4 a request to store B: Manager 3 (store A only) neither dispatches nor rejects it; Manager 1 does
  perform pg_temp.treq('t4', 'own', 'warehouse', 'w1', 'store', 'sb', 5);
  t := pg_temp.dispatch('mgr3', 't4', 5, 'warehouse', 'w1');
  perform pg_temp.check(pg_temp.refused(t, 'store') and pg_temp.tstatus('t4') = 'pending', 'T4 a Manager cannot dispatch to a store they do not work at: ' || t);
  perform pg_temp.treq('t4b', 'own', 'warehouse', 'w1', 'store', 'sb', 5);
  t := pg_temp.as_('mgr3', format('select public.reject_transfer(%L, %L)::text', pg_temp.fx('t4b'), 'M533 no'));
  perform pg_temp.check(pg_temp.refused(t, 'store') and pg_temp.tstatus('t4b') = 'pending', 'T4b nor reject it: ' || t);
  perform pg_temp.treq('t4c', 'own', 'warehouse', 'w1', 'store', 'sb', 5);
  t := pg_temp.dispatch('mgr1', 't4c', 5, 'warehouse', 'w1');
  perform pg_temp.check(t like 'ok:%', 'T4c a Manager working at store B dispatches it: ' || t);
  -- T5 warehouses are open to every Manager
  perform pg_temp.treq('t5', 'own', 'warehouse', 'w1', 'warehouse', 'w2', 5);
  t := pg_temp.dispatch('mgr3', 't5', 5, 'warehouse', 'w1');
  perform pg_temp.check(t like 'ok:%', 'T5 a warehouse-to-warehouse transfer is open to any Manager: ' || t);
  -- T6 a store chosen as a source is one they work at
  perform pg_temp.treq('t6', 'own', 'warehouse', 'w1', 'store', 'sa', 5);
  t := pg_temp.dispatch('mgr3', 't6', 5, 'store', 'sb');
  perform pg_temp.check(pg_temp.refused(t, 'store') and pg_temp.tstatus('t6') = 'pending',
    'T6 a Manager cannot take the stock from a store they do not work at: ' || t);
  perform pg_temp.treq('t6b', 'own', 'warehouse', 'w1', 'store', 'sa', 5);
  t := pg_temp.dispatch('mgr3', 't6b', 5, 'warehouse', 'w1');
  perform pg_temp.check(t like 'ok:%', 'T6b from a warehouse to their own store they can: ' || t);
  -- T7 a request a Manager edited
  perform pg_temp.treq('t7', 'own', 'warehouse', 'w1', 'store', 'sa', 5);
  perform pg_temp.must('mgr2', format('select public.edit_transfer_request(%L, null, %L, null, null, null, null, null, %L)::text',
    pg_temp.fx('t7'), 'M533 clearer note', 'M533 edited by Manager 2'));
  t := pg_temp.dispatch('mgr2', 't7', 5, 'warehouse', 'w1');
  perform pg_temp.check(pg_temp.refused(t, 'edited') and pg_temp.tstatus('t7') = 'pending', 'T7 a Manager who edited the request cannot dispatch it: ' || t);
  perform pg_temp.treq('t7b', 'own', 'warehouse', 'w1', 'store', 'sa', 5);
  perform pg_temp.must('mgr2', format('select public.edit_transfer_request(%L, null, %L, null, null, null, null, null, %L)::text',
    pg_temp.fx('t7b'), 'M533 clearer note', 'M533 edited by Manager 2'));
  perform pg_temp.must('own', format('select public.edit_transfer_request(%L, null, %L, null, null, null, null, null, %L)::text',
    pg_temp.fx('t7b'), 'M533 owner note', 'M533 edited by the Owner after'));
  t := pg_temp.dispatch('mgr2', 't7b', 5, 'warehouse', 'w1');
  perform pg_temp.check(pg_temp.refused(t, 'edited'), 'T7b nor after someone else edited it later (the kept revisions): ' || t);
  perform pg_temp.treq('t7c', 'own', 'warehouse', 'w1', 'store', 'sa', 5);
  perform pg_temp.must('mgr2', format('select public.edit_transfer_request(%L, null, %L, null, null, null, null, null, %L)::text',
    pg_temp.fx('t7c'), 'M533 clearer note', 'M533 edited by Manager 2'));
  t := pg_temp.dispatch('mgr1', 't7c', 5, 'warehouse', 'w1');
  perform pg_temp.check(t like 'ok:%', 'T7c the other Manager dispatches a request Manager 2 edited: ' || t);
  -- T8 lines added and quantities raised while approving
  perform pg_temp.treq('t8', 'own', 'warehouse', 'w1', 'store', 'sa', 5);
  t := pg_temp.dispatch('mgr2', 't8', 6, 'warehouse', 'w1');
  perform pg_temp.check(pg_temp.refused(t, 'shaped') and pg_temp.tstatus('t8') = 'pending', 'T8 a Manager cannot approve more than was requested: ' || t);
  perform pg_temp.treq('t8b', 'own', 'warehouse', 'w1', 'store', 'sa', 5);
  t := pg_temp.dispatch('mgr2', 't8b', 5, 'warehouse', 'w1', jsonb_build_array(jsonb_build_object('product_id', pg_temp.fx('p2'),
    'approved_quantity', 2, 'sources', jsonb_build_array(jsonb_build_object('source_type', 'warehouse', 'source_id', pg_temp.fx('w1'), 'quantity', 2)))));
  perform pg_temp.check(pg_temp.refused(t, 'shaped') and pg_temp.tstatus('t8b') = 'pending', 'T8b nor add a line: ' || t);
  perform pg_temp.treq('t8c', 'own', 'warehouse', 'w1', 'store', 'sa', 5);
  t := pg_temp.dispatch('mgr2', 't8c', 4, 'warehouse', 'w1');
  perform pg_temp.check(t like 'ok:%' and (select approved_quantity from public.transfer_request_lines where id = pg_temp.fx('t8c:l')) = 4,
    'T8c a lower quantity is approved as before: ' || t);
  perform pg_temp.treq('t9', 'own', 'warehouse', 'w1', 'store', 'sa', 5);
  t := pg_temp.dispatch('own', 't9', 6, 'warehouse', 'w1', jsonb_build_array(jsonb_build_object('product_id', pg_temp.fx('p2'),
    'approved_quantity', 2, 'sources', jsonb_build_array(jsonb_build_object('source_type', 'warehouse', 'source_id', pg_temp.fx('w1'), 'quantity', 2)))));
  perform pg_temp.check(t like 'ok:%' and (select count(*) from public.transfer_request_lines where transfer_request_id = pg_temp.fx('t9')) = 2,
    'T8d an Owner raises a quantity and adds a line: ' || t);
end $T$;

-- ═════ D Discrepancies ═════
-- A transfer of 5 (or sent) from warehouse 1 to store, dispatched by the Owner and received by who as got.
create function pg_temp.got(name text, store text, sent int, who text, got int) returns void language plpgsql as $$
declare t text;
begin
  perform pg_temp.treq(name, 'own', 'warehouse', 'w1', 'store', store, sent);
  t := pg_temp.dispatch('own', name, sent, 'warehouse', 'w1'); if t not like 'ok:%' then raise exception 'FIXTURE % dispatch: %', name, t; end if;
  t := pg_temp.receive(who, name, got); if t not like 'ok:%' then raise exception 'FIXTURE % receive: %', name, t; end if;
end $$;
do $D$
declare t text;
begin
  -- D1 a shortage a Manager received
  perform pg_temp.got('d1', 'sa', 5, 'mgr1', 3);
  t := pg_temp.resolve('mgr1', 'd1', 'accept_loss');
  perform pg_temp.check(pg_temp.refused(t, 'received') and pg_temp.tstatus('d1') = 'received_with_discrepancy',
    'D1 a Manager cannot resolve a shortage they received: ' || t);
  perform pg_temp.got('d1b', 'sa', 5, 'mgr1', 3);
  t := pg_temp.resolve('mgr2', 'd1b', 'accept_loss');
  perform pg_temp.check(t like 'ok:%' and pg_temp.tstatus('d1b') = 'completed', 'D1b the other Manager resolves it: ' || t);
  -- D2 extra units waiting (510) that a Manager received
  perform pg_temp.got('d2', 'sa', 2, 'mgr1', 5);
  t := pg_temp.resolve('mgr1', 'd2', 'accept_surplus');
  perform pg_temp.check(pg_temp.refused(t, 'received') and (select extra_waiting_quantity from public.transfer_request_lines where id = pg_temp.fx('d2:l')) = 3,
    'D2 a Manager cannot accept the extra units they received themselves; the 3 still wait: ' || t);
  perform pg_temp.got('d2b', 'sa', 2, 'mgr1', 5);
  t := pg_temp.resolve('mgr2', 'd2b', 'accept_surplus');
  perform pg_temp.check(t like 'ok:%' and (select extra_waiting_quantity from public.transfer_request_lines where id = pg_temp.fx('d2b:l')) = 0,
    'D2b the other Manager accepts them: ' || t);
  -- D3 an Owner resolves one they received
  perform pg_temp.got('d3', 'sa', 5, 'own', 4);
  t := pg_temp.resolve('own', 'd3', 'accept_loss');
  perform pg_temp.check(t like 'ok:%', 'D3 an Owner still resolves a transfer they received: ' || t);
  -- D4 store B: Manager 3 cannot resolve it, Manager 1 can
  perform pg_temp.got('d4', 'sb', 5, 'own', 3);
  t := pg_temp.resolve('mgr3', 'd4', 'accept_loss');
  perform pg_temp.check(pg_temp.refused(t, 'store') and pg_temp.tstatus('d4') = 'received_with_discrepancy',
    'D4 a Manager cannot resolve a transfer to a store they do not work at: ' || t);
  perform pg_temp.got('d4b', 'sb', 5, 'own', 3);
  t := pg_temp.resolve('mgr1', 'd4b', 'accept_loss');
  perform pg_temp.check(t like 'ok:%', 'D4b a Manager working there resolves it: ' || t);
end $D$;

-- ═════ A Stock corrections ═════
-- A correction asked for by who, at (type, place) for product prod, to qty; through the old
-- single-line request as the database owner with who's claims (no page calls it; it records the
-- same request as the page's). Each check has its own place or product.
create function pg_temp.adj(who text, loc_type text, loc text, prod text, qty int) returns uuid language sql as $$
  select pg_temp.must('pg:' || who, format('select public.request_inventory_adjustment(%L::public.location_type, %L, %L, %s, %L, null)::text',
    loc_type, pg_temp.fx(loc), pg_temp.fx(prod), qty, 'M533 count'))::uuid $$;
create function pg_temp.adj_resolve(who text, req uuid, ok boolean) returns text language sql as $$
  select pg_temp.as_(who, format('select public.resolve_inventory_adjustment(%L, %L, %L)::text', req, ok, 'M533 checked')) $$;
create function pg_temp.astatus(req uuid) returns text language sql as $$ select status::text from public.approval_requests where id = req $$;
do $A$
declare r uuid; t text;
begin
  r := pg_temp.adj('mgr1', 'store', 'sa', 'p', 490);
  t := pg_temp.adj_resolve('mgr1', r, true);
  perform pg_temp.check(pg_temp.refused(t, 'own_correction') and pg_temp.astatus(r) = 'pending', 'A1 a Manager cannot approve their own stock correction: ' || t);
  r := pg_temp.adj('mgr1', 'warehouse', 'w1', 'p', 490);
  t := pg_temp.adj_resolve('mgr1', r, false);
  perform pg_temp.check(t like 'ok:%' and pg_temp.astatus(r) = 'rejected', 'A1b a Manager still rejects their own: ' || t);
  r := pg_temp.adj('mgr1', 'store', 'sb', 'p', 490);
  t := pg_temp.adj_resolve('mgr2', r, true);
  perform pg_temp.check(t like 'ok:%' and (select current_qty from public.store_inventory where store_id = pg_temp.fx('sb') and product_id = pg_temp.fx('p')) = 490,
    'A1c the other Manager approves it: ' || t);
  r := pg_temp.adj('own', 'store', 'sa', 'p2', 480);
  t := pg_temp.adj_resolve('own', r, true);
  perform pg_temp.check(t like 'ok:%', 'A2 an Owner still approves their own: ' || t);
  r := pg_temp.adj('own', 'store', 'sb', 'p2', 480);
  t := pg_temp.adj_resolve('mgr3', r, true);
  perform pg_temp.check(pg_temp.refused(t, 'store') and pg_temp.astatus(r) = 'pending', 'A3 a Manager cannot approve a correction at a store they do not work at: ' || t);
  r := pg_temp.adj('own', 'store', 'sb', 'p', 470);
  t := pg_temp.adj_resolve('mgr1', r, true);
  perform pg_temp.check(t like 'ok:%', 'A3b a Manager working at store B approves a correction there: ' || t);
  r := pg_temp.adj('own', 'warehouse', 'w2', 'p', 480);
  t := pg_temp.adj_resolve('mgr3', r, true);
  perform pg_temp.check(t like 'ok:%', 'A3c a warehouse correction is open to any Manager: ' || t);
end $A$;

-- ── Invoice helpers ──
-- An invoice at store A selling the S$1,500 service, paid (0: none) in one payment; fx(name).
create function pg_temp.inv(name text, paid numeric) returns uuid language plpgsql as $$
declare v uuid;
begin
  v := pg_temp.must('pg:own', format('select public.create_invoice(%L, %L, null, %L::jsonb)::text', pg_temp.fx('sa'), pg_temp.fx('c'),
         jsonb_build_array(jsonb_build_object('kind', 'product', 'product_id', pg_temp.fx('sv'), 'quantity', 1))))::uuid;
  perform pg_temp.put(name, v);
  if paid > 0 then
    perform pg_temp.must('pg:own', format('select public.record_invoice_payment(%L, %L::jsonb, %L)::text', v,
      jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.fx('pm'), 'amount', paid)), gen_random_uuid()));
  end if;
  return v;
end $$;
-- The invoice's live payment holding the most.
create function pg_temp.pay(name text) returns uuid language sql as $$
  select q.id from public.invoice_payments q
   where q.invoice_id = pg_temp.fx(name) and q.entry_kind in ('receipt', 'correction_replacement')
     and not exists (select 1 from public.invoice_payments x where x.corrects_payment_id = q.id and x.entry_kind = 'correction_reversal')
   order by public.invoice_payment_remaining(q.id) desc, q.created_at limit 1 $$;
-- The invoice view's direct refund by who: amount on its line, from its live payment.
create function pg_temp.refund(who text, name text, amount numeric, rid uuid default gen_random_uuid()) returns text language sql as $$
  select pg_temp.as_(who, format('select public.refund_invoice_recorded(%L, %L::jsonb, %L::jsonb, ''[]''::jsonb, %L, %L)::text',
    pg_temp.fx(name),
    jsonb_build_array(jsonb_build_object('invoice_item_id', (select id from public.invoice_items where invoice_id = pg_temp.fx(name) limit 1), 'amount', amount)),
    jsonb_build_array(jsonb_build_object('payment_id', pg_temp.pay(name), 'amount', amount)), 'M533 money back', rid)) $$;
create function pg_temp.refunded(name text) returns numeric language sql as $$
  select coalesce(sum(amount), 0) from public.invoice_refunds where invoice_id = pg_temp.fx(name) $$;
create function pg_temp.ireq(who text, name text, action text) returns uuid language sql as $$
  select (pg_temp.must(who, format('select public.request_invoice_action_v2(%L, %L, ''[]''::jsonb, %L, null, %L)::text',
    pg_temp.fx(name), action, 'M533 customer asked', gen_random_uuid()))::jsonb ->> 'request_id')::uuid $$;
create function pg_temp.iresolve(who text, req uuid, ok boolean, record_refund boolean default false) returns text language sql as $$
  select pg_temp.as_(who, format('select public.resolve_invoice_action_v2(%L, %L, %L, null, ''[]''::jsonb, null, %L)::text',
    req, ok, 'M533 decided', record_refund)) $$;
-- Corrections of the invoice's live payment: correct_invoice_payment as who; remove and split as
-- the database owner with who's claims (Edit Invoice, correct_invoice, reaches them so).
create function pg_temp.lower_to(who text, name text, amount numeric, day date default null) returns text language sql as $$
  select pg_temp.as_(who, format('select public.correct_invoice_payment(%L, %s, %L, %L, %L, %L)::text',
    pg_temp.pay(name), amount, coalesce(day, public.sg_today()), pg_temp.fx('pm'), 'M533 typed wrong', gen_random_uuid())) $$;
create function pg_temp.remove(who text, name text) returns text language sql as $$
  select pg_temp.as_('pg:' || who, format('select public.remove_invoice_payment(%L, %L, %L)::text', pg_temp.pay(name), 'M533 not paid', gen_random_uuid())) $$;
create function pg_temp.split(who text, name text, a numeric, b numeric) returns text language sql as $$
  select pg_temp.as_('pg:' || who, format('select public.split_invoice_payment(%L, %L::jsonb, %L, %L)::text', pg_temp.pay(name),
    jsonb_build_array(jsonb_build_object('amount', a, 'payment_method_id', pg_temp.fx('pm'), 'date', public.sg_today()),
                      jsonb_build_object('amount', b, 'payment_method_id', pg_temp.fx('pm'), 'date', public.sg_today())),
    'M533 split', gen_random_uuid())) $$;
create function pg_temp.held(name text) returns numeric language sql as $$ select public.invoice_net_received(pg_temp.fx(name)) $$;

-- ═════ I Invoice requests ═════
do $I$
declare r uuid; t text;
begin
  perform pg_temp.inv('i1', 1500);
  r := pg_temp.ireq('mgr1', 'i1', 'refund_full');
  t := pg_temp.iresolve('mgr1', r, true);
  perform pg_temp.check(pg_temp.refused(t, 'own_request') and pg_temp.astatus(r) = 'pending' and pg_temp.refunded('i1') = 0,
    'I1 a Manager cannot approve their own refund request: ' || t);
  perform pg_temp.inv('i1b', 1500);
  r := pg_temp.ireq('mgr1', 'i1b', 'refund_full');
  t := pg_temp.iresolve('mgr1', r, false);
  perform pg_temp.check(t like 'ok:%' and pg_temp.astatus(r) = 'rejected', 'I1b a Manager still rejects their own: ' || t);
  -- (the service is priced S$1,500: a S$300 payment leaves it part-paid; a full refund returns the S$300)
  perform pg_temp.inv('i2', 300);
  r := pg_temp.ireq('mgr1', 'i2', 'refund_full');
  t := pg_temp.iresolve('mgr2', r, true);
  perform pg_temp.check(t like 'ok:%' and pg_temp.astatus(r) = 'approved' and pg_temp.refunded('i2') = 300,
    'I1c the other Manager approves it (S$300): ' || t);
  perform pg_temp.inv('i3', 1500);
  r := pg_temp.ireq('own', 'i3', 'refund_full');
  t := pg_temp.iresolve('own', r, true);
  perform pg_temp.check(t like 'ok:%' and pg_temp.refunded('i3') = 1500, 'I2 an Owner still approves their own request (S$1,500): ' || t);
  -- I3 a Staff cancellation, approved by a Manager with S$300 paid back: the approval reaches cancel_invoice_recorded
  perform pg_temp.inv('i4', 300);
  r := pg_temp.ireq('stf', 'i4', 'cancel');
  t := pg_temp.iresolve('mgr1', r, true, true);
  perform pg_temp.check(t like 'ok:%' and (select status::text from public.invoices where id = pg_temp.fx('i4')) = 'cancelled'
                        and pg_temp.refunded('i4') = 300,
    'I3 a Manager approves a Staff cancellation with the S$300 paid back (cancel_invoice_recorded reached as before): ' || t);
end $I$;

-- ═════ C The S$1,000 limit ═════
do $C$
declare r uuid; t text; rid uuid := gen_random_uuid(); n numeric;
begin
  -- C1 to S$1,000 exactly, then S$0.01 more; an Owner above
  perform pg_temp.inv('c1', 1500);
  t := pg_temp.refund('mgr1', 'c1', 1000);
  perform pg_temp.check(t like 'ok:%' and pg_temp.refunded('c1') = 1000, 'C1 a Manager refunds S$1,000 exactly: ' || t);
  t := pg_temp.refund('mgr1', 'c1', 0.01);
  perform pg_temp.check(pg_temp.refused(t, 'cap') and pg_temp.refunded('c1') = 1000, 'C1b S$0.01 more is refused (cumulative): ' || t);
  t := pg_temp.refund('mgr2', 'c1', 0.01);
  perform pg_temp.check(pg_temp.refused(t, 'cap'), 'C1c by the other Manager too (it is the invoice''s limit): ' || t);
  n := pg_temp.refunded('c1');
  t := pg_temp.refund('own', 'c1', 200);
  perform pg_temp.check(t like 'ok:%' and pg_temp.refunded('c1') = n + 200, 'C1d an Owner records above it: ' || t);
  -- C2 S$1,000.01 at once; a retry is not counted twice
  perform pg_temp.inv('c2', 1500);
  t := pg_temp.refund('mgr1', 'c2', 1000.01);
  perform pg_temp.check(pg_temp.refused(t, 'cap') and pg_temp.refunded('c2') = 0, 'C2 S$1,000.01 in one refund is refused: ' || t);
  perform pg_temp.inv('c2b', 1500);
  t := pg_temp.refund('mgr1', 'c2b', 600, rid);
  perform pg_temp.check(t like 'ok:%', 'C2b S$600 is recorded: ' || t);
  t := pg_temp.refund('mgr1', 'c2b', 600, rid);
  perform pg_temp.check(t like 'ok:%' and t like '%"replayed": true%' and pg_temp.refunded('c2b') = 600,
    'C2c the same refund again (same request id) gives its first answer, not a second refund: ' || t);
  t := pg_temp.refund('mgr1', 'c2b', 400);
  perform pg_temp.check(t like 'ok:%' and pg_temp.refunded('c2b') = 1000, 'C2d S$400 more brings it to S$1,000: ' || t);
  -- C3 a Staff request above S$1,000 waits for an Owner
  perform pg_temp.inv('c3', 1500);
  r := pg_temp.ireq('stf', 'c3', 'refund_full');
  t := pg_temp.iresolve('mgr2', r, true);
  perform pg_temp.check(pg_temp.refused(t, 'cap') and pg_temp.astatus(r) = 'pending' and pg_temp.refunded('c3') = 0,
    'C3 a Manager cannot approve a Staff request for S$1,500; it waits: ' || t);
  t := pg_temp.iresolve('own', r, true);
  perform pg_temp.check(t like 'ok:%' and pg_temp.astatus(r) = 'approved' and pg_temp.refunded('c3') = 1500, 'C3b an Owner approves it: ' || t);
  -- C4 a lowered payment counts
  perform pg_temp.inv('c4', 1500);
  t := pg_temp.lower_to('mgr1', 'c4', 400);
  perform pg_temp.check(pg_temp.refused(t, 'cap') and pg_temp.held('c4') = 1500, 'C4 a Manager cannot lower a payment by S$1,100: ' || t);
  perform pg_temp.inv('c4b', 1500);
  t := pg_temp.lower_to('mgr1', 'c4b', 600);
  perform pg_temp.check(t like 'ok:%' and pg_temp.held('c4b') = 600, 'C4b a Manager lowers it by S$900: ' || t);
  t := pg_temp.refund('mgr1', 'c4b', 100.01);
  perform pg_temp.check(pg_temp.refused(t, 'cap'), 'C4c then a refund of S$100.01 is refused: ' || t);
  n := pg_temp.refunded('c4b');
  t := pg_temp.refund('mgr1', 'c4b', 100);
  perform pg_temp.check(t like 'ok:%' and pg_temp.refunded('c4b') = n + 100, 'C4d and S$100 is recorded (S$1,000 taken back): ' || t);
  t := pg_temp.lower_to('mgr1', 'c4b', (select amount from public.invoice_payments where id = pg_temp.pay('c4b')), public.sg_today() - 1);
  perform pg_temp.check(t like 'ok:%', 'C4e a change of date alone still passes at the limit: ' || t);
  t := pg_temp.lower_to('own', 'c4b', 300);
  perform pg_temp.check(t like 'ok:%', 'C4f an Owner lowers it further: ' || t);
  -- C5 Edit Invoice removes a payment (remove_invoice_payment)
  perform pg_temp.inv('c5', 1500);
  t := pg_temp.remove('mgr1', 'c5');
  perform pg_temp.check(pg_temp.refused(t, 'cap') and pg_temp.held('c5') = 1500, 'C5 a Manager cannot remove a S$1,500 payment: ' || t);
  perform pg_temp.inv('c5b', 1500);
  t := pg_temp.remove('own', 'c5b');
  perform pg_temp.check(t like 'ok:%' and pg_temp.held('c5b') = 0, 'C5b an Owner removes it: ' || t);
  perform pg_temp.inv('c5c', 900);
  t := pg_temp.remove('mgr1', 'c5c');
  perform pg_temp.check(t like 'ok:%' and pg_temp.held('c5c') = 0, 'C5c a Manager removes a S$900 payment (within the limit): ' || t);
  -- C6 Edit Invoice splits a payment (split_invoice_payment)
  perform pg_temp.inv('c6', 1500);
  t := pg_temp.split('mgr1', 'c6', 100, 100);
  perform pg_temp.check(pg_temp.refused(t, 'cap') and pg_temp.held('c6') = 1500, 'C6 a Manager cannot split S$1,500 into S$100 + S$100: ' || t);
  perform pg_temp.inv('c6b', 1500);
  t := pg_temp.split('mgr1', 'c6b', 800, 600);
  perform pg_temp.check(t like 'ok:%' and pg_temp.held('c6b') = 1400, 'C6b a split into S$800 + S$600 (S$100 lower) passes: ' || t);
  perform pg_temp.inv('c6c', 1500);
  t := pg_temp.split('mgr1', 'c6c', 900, 600);
  perform pg_temp.check(t like 'ok:%' and pg_temp.held('c6c') = 1500, 'C6c a split into S$900 + S$600 lowers nothing and passes: ' || t);
  perform pg_temp.inv('c6d', 1500);
  t := pg_temp.split('own', 'c6d', 100, 100);
  perform pg_temp.check(t like 'ok:%' and pg_temp.held('c6d') = 200, 'C6d an Owner splits S$1,500 into S$100 + S$100: ' || t);
  -- C7 a lowered payment and a refund together
  perform pg_temp.inv('c7', 1500);
  t := pg_temp.lower_to('mgr1', 'c7', 1000);
  perform pg_temp.check(t like 'ok:%', 'C7 a Manager lowers a payment by S$500: ' || t);
  t := pg_temp.refund('mgr1', 'c7', 500);
  perform pg_temp.check(t like 'ok:%', 'C7b and refunds S$500: ' || t);
  t := pg_temp.refund('mgr1', 'c7', 0.01);
  perform pg_temp.check(pg_temp.refused(t, 'cap'), 'C7c S$0.01 more is refused (S$500 lowered + S$500 refunded): ' || t);
  t := pg_temp.lower_to('mgr1', 'c7', 999.99);
  perform pg_temp.check(pg_temp.refused(t, 'cap'), 'C7d and so is lowering the payment by S$0.01: ' || t);
end $C$;

-- ═════ R Credit by hand ═════
do $R$
declare t text; lot1 uuid; lot2 uuid;
begin
  t := pg_temp.as_('mgr1', format('select public.adjust_customer_credit(%L, %L, %L, 50, %L, %L)::text', pg_temp.fx('c'), 'paid', 'increase', 'M533 goodwill', 'M533-REF-M'));
  perform pg_temp.check(pg_temp.refused(t, 'credit'), 'R1 a Manager cannot add credit by hand: ' || t);
  t := pg_temp.as_('adm', format('select public.adjust_customer_credit(%L, %L, %L, 50, %L, %L)::text', pg_temp.fx('c'), 'paid', 'increase', 'M533 goodwill', 'M533-REF-A'));
  perform pg_temp.check(t like 'ERR %', 'R1b nor an Admin (as before): ' || t);
  t := pg_temp.as_('own', format('select public.adjust_customer_credit(%L, %L, %L, 50, %L, %L, null, null, %L)::text', pg_temp.fx('c'), 'paid', 'increase', 'M533 goodwill', 'M533-REF-O', pg_temp.fx('sa')));
  perform pg_temp.check(t like 'ok:%', 'R1c an Owner adds it: ' || t);
  t := pg_temp.as_('mgr1', format('select public.adjust_customer_credit(%L, %L, %L, 10, %L, %L)::text', pg_temp.fx('c'), 'paid', 'decrease', 'M533 take off', 'M533-REF-D'));
  perform pg_temp.check(pg_temp.refused(t, 'credit'), 'R2 a Manager cannot remove credit by hand: ' || t);
  t := pg_temp.as_('mgr1', format('select public.add_legacy_credit(%L, %L, 20, %L, %L, %L, %L)::text', pg_temp.fx('c'), 'legacy', public.sg_today() - 400, pg_temp.fx('sa'), 'M533-OLD-M', 'M533 old card'));
  perform pg_temp.check(pg_temp.refused(t, 'credit'), 'R3 a Manager cannot enter an old-client balance: ' || t);
  t := pg_temp.as_('own', format('select public.add_legacy_credit(%L, %L, 20, %L, %L, %L, %L)::text', pg_temp.fx('c'), 'legacy', public.sg_today() - 400, pg_temp.fx('sa'), 'M533-OLD-O1', 'M533 old card'));
  perform pg_temp.check(t like 'ok:%', 'R3b an Owner enters it: ' || t);
  lot1 := pg_temp.must('own', format('select public.add_legacy_credit(%L, %L, 20, %L, %L, %L, %L)::text', pg_temp.fx('c'), 'legacy', public.sg_today() - 400, pg_temp.fx('sa'), 'M533-OLD-O2', 'M533 old card'))::uuid;
  lot2 := pg_temp.must('own', format('select public.add_legacy_credit(%L, %L, 20, %L, %L, %L, %L)::text', pg_temp.fx('c'), 'legacy', public.sg_today() - 400, pg_temp.fx('sa'), 'M533-OLD-O3', 'M533 old card'))::uuid;
  t := pg_temp.as_('mgr1', format('select public.customer_credit_balances(%L)::text', pg_temp.fx('c')));
  perform pg_temp.check(t like 'ok:%', 'R4 a Manager still reads the balances: ' || t);
  t := pg_temp.as_('pg:mgr1', format('select public.reverse_credit_lot(%L, %L)::text', lot1, 'M533 entered twice'));
  perform pg_temp.check(pg_temp.refused(t, 'credit'), 'R5 reverse_credit_lot (no login calls it) refuses a Manager: ' || t);
  t := pg_temp.as_('pg:own', format('select public.reverse_credit_lot(%L, %L)::text', lot2, 'M533 entered twice'));
  perform pg_temp.check(t like 'ok:%', 'R5b and lets an Owner: ' || t);
end $R$;

-- ═════ P Payouts ═════
do $P$
declare t text;
begin
  t := pg_temp.as_('mgr1', format('select public.record_affiliate_payout(%L, %L, 10, %L, public.sg_today(), %L, null, %L)::text',
    pg_temp.fx('c'), date_trunc('month', public.sg_today())::date, pg_temp.fx('pm'), 'M533-PAY', gen_random_uuid()));
  perform pg_temp.check(pg_temp.refused(t, 'payout'), 'P1 a Manager cannot record an affiliate payout: ' || t);
  t := pg_temp.as_('own', format('select public.record_affiliate_payout(%L, %L, 10, %L, public.sg_today(), %L, null, %L)::text',
    pg_temp.fx('c'), date_trunc('month', public.sg_today())::date, pg_temp.fx('pm'), 'M533-PAY', gen_random_uuid()));
  perform pg_temp.check(pg_temp.past(t), 'P1b an Owner passes the role test: ' || t);
  t := pg_temp.as_('mgr1', format('select public.correct_affiliate_payout(%L, 1, 10, %L, public.sg_today(), %L, null, %L, %L)::text',
    gen_random_uuid(), pg_temp.fx('pm'), 'M533-PAY', 'M533 fix', gen_random_uuid()));
  perform pg_temp.check(pg_temp.refused(t, 'payout'), 'P1c nor correct one: ' || t);
  t := pg_temp.as_('mgr1', 'select count(*)::text from public.affiliate_payout_overview()');
  perform pg_temp.check(t like 'ok:%', 'P1d a Manager still reads the payouts: ' || t);
  t := pg_temp.as_('mgr1', format('select public.record_affiliate_deduction_settlement(%L, 10, public.sg_today(), %L, %L, %L)::text',
    pg_temp.fx('c'), 'cash', 'M533 paid back', gen_random_uuid()));
  perform pg_temp.check(pg_temp.refused(t, 'repayment'), 'P2 a Manager cannot record an affiliate repayment: ' || t);
  t := pg_temp.as_('own', format('select public.record_affiliate_deduction_settlement(%L, 10, public.sg_today(), %L, %L, %L)::text',
    pg_temp.fx('c'), 'cash', 'M533 paid back', gen_random_uuid()));
  perform pg_temp.check(pg_temp.past(t), 'P2b an Owner passes the role test: ' || t);
  t := pg_temp.as_('mgr1', format('select public.void_affiliate_deduction_settlement(%L, %L, %L)::text', gen_random_uuid(), 'M533 wrong', gen_random_uuid()));
  perform pg_temp.check(pg_temp.refused(t, 'repayment'), 'P2c nor void one: ' || t);
  t := pg_temp.as_('own', format('select public.void_affiliate_deduction_settlement(%L, %L, %L)::text', gen_random_uuid(), 'M533 wrong', gen_random_uuid()));
  perform pg_temp.check(pg_temp.past(t), 'P2d an Owner passes the role test: ' || t);
  t := pg_temp.as_('mgr1', format('select public.create_staff_commission_payout(%L, public.sg_today(), %L)::text', pg_temp.fx('stf'), pg_temp.fx('pm')));
  perform pg_temp.check(pg_temp.refused(t, 'staff_payout'), 'P3 a Manager cannot record a staff commission payout: ' || t);
  t := pg_temp.as_('own', format('select public.create_staff_commission_payout(%L, public.sg_today(), %L)::text', pg_temp.fx('stf'), pg_temp.fx('pm')));
  perform pg_temp.check(pg_temp.past(t), 'P3b an Owner passes the role test: ' || t);
end $P$;

-- ═════ F Make FOC on a credit package; X moving unused credit ═════
-- An unpaid invoice at store A with one line of kind (credit_package or product); returns the line.
create function pg_temp.line_of(kind text) returns uuid language plpgsql as $$
declare v uuid;
begin
  v := pg_temp.must('pg:own', format('select public.create_invoice(%L, %L, null, %L::jsonb)::text', pg_temp.fx('sa'), pg_temp.fx('c'),
         jsonb_build_array(case kind when 'credit_package' then jsonb_build_object('kind', 'credit_package', 'credit_package_id', pg_temp.fx('cp'), 'quantity', 1)
                                     else jsonb_build_object('kind', 'product', 'product_id', pg_temp.fx('p'), 'quantity', 1) end)))::uuid;
  return (select id from public.invoice_items where invoice_id = v);
end $$;
do $F$
declare t text; li uuid;
begin
  li := pg_temp.line_of('credit_package');
  t := pg_temp.as_('mgr1', format('select public.apply_line_foc(%L, null, null, %L)::text', li, 'M533 gift'));
  perform pg_temp.check(pg_temp.refused(t, 'foc') and (select coalesce(foc_quantity, 0) from public.invoice_items where id = li) = 0,
    'F1 a Manager cannot make a credit package line free: ' || t);
  li := pg_temp.line_of('credit_package');
  t := pg_temp.as_('own', format('select public.apply_line_foc(%L, null, null, %L)::text', li, 'M533 gift'));
  perform pg_temp.check(t like 'ok:%', 'F1b an Owner makes it free: ' || t);
  li := pg_temp.line_of('product');
  t := pg_temp.as_('stf', format('select public.apply_line_foc(%L, null, null, %L)::text', li, 'M533 sample'));
  perform pg_temp.check(t like 'ok:%', 'F2 Staff still make a product line free: ' || t);
  t := pg_temp.as_('pg:own', format('select public.create_invoice(%L, %L, null, %L::jsonb)::text', pg_temp.fx('sa'), pg_temp.fx('c'),
         jsonb_build_array(jsonb_build_object('kind', 'credit_package', 'credit_package_id', pg_temp.fx('cp'), 'quantity', 1, 'is_foc', true, 'foc_reason', 'M533'))));
  perform pg_temp.check(t like 'ERR %A credit package cannot be made FOC when the invoice is created%', 'F3 a new invoice still refuses a credit package made free, for an Owner too (355): ' || t);
  t := pg_temp.as_('mgr1', format('select public.transfer_invoice_unused_benefit(%L, %L, %L, %L, %L)::text',
    gen_random_uuid(), pg_temp.fx('c2'), pg_temp.fx('sa'), 'M533 for her sister', gen_random_uuid()));
  perform pg_temp.check(pg_temp.refused(t, 'move'), 'X1 a Manager cannot move unused credit or vouchers to another customer: ' || t);
  t := pg_temp.as_('own', format('select public.transfer_invoice_unused_benefit(%L, %L, %L, %L, %L)::text',
    gen_random_uuid(), pg_temp.fx('c2'), pg_temp.fx('sa'), 'M533 for her sister', gen_random_uuid()));
  perform pg_temp.check(pg_temp.past(t), 'X1b an Owner passes the role test: ' || t);
end $F$;

-- ═════ W Into or out of wallet credit (decision 10) ═════
-- An invoice for customer cw selling the service at S$1,500, paid amount through method mkey; fx(name).
create function pg_temp.winv(name text, amount numeric, mkey text) returns uuid language plpgsql as $$
declare v uuid;
begin
  v := pg_temp.must('pg:own', format('select public.create_invoice(%L, %L, null, %L::jsonb)::text', pg_temp.fx('sa'), pg_temp.fx('cw'),
         jsonb_build_array(jsonb_build_object('kind', 'product', 'product_id', pg_temp.fx('sv'), 'quantity', 1))))::uuid;
  perform pg_temp.put(name, v);
  perform pg_temp.must('pg:own', format('select public.record_invoice_payment(%L, %L::jsonb, %L)::text', v,
    jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.fx(mkey), 'amount', amount)), gen_random_uuid()));
  return v;
end $$;
create function pg_temp.credit(cat text) returns numeric language sql as $$
  select coalesce(sum(remaining_amount), 0) from public.customer_credit_lots where customer_id = pg_temp.fx('cw') and category = cat $$;
-- correct_invoice_payment on the invoice's live payment by who: the same amount, method mkey.
create function pg_temp.remethod(who text, name text, mkey text) returns text language sql as $$
  select pg_temp.as_(who, format('select public.correct_invoice_payment(%L, %s, public.sg_today(), %L, %L, %L)::text',
    pg_temp.pay(name), (select amount from public.invoice_payments where id = pg_temp.pay(name)), pg_temp.fx(mkey),
    'M533 wrong method', gen_random_uuid())) $$;
create function pg_temp.method_of(name text) returns uuid language sql as $$
  select payment_method_id from public.invoice_payments where id = pg_temp.pay(name) $$;
do $fxw$
begin
  perform pg_temp.must('own', format('select public.adjust_customer_credit(%L, %L, %L, 1000, %L, %L, null, null, %L)::text',
    pg_temp.fx('cw'), 'paid', 'increase', 'M533 wallet', 'M533-W-P', pg_temp.fx('sa')));
  perform pg_temp.must('own', format('select public.adjust_customer_credit(%L, %L, %L, 500, %L, %L, null, null, %L)::text',
    pg_temp.fx('cw'), 'bonus', 'increase', 'M533 wallet', 'M533-W-B', pg_temp.fx('sa')));
end $fxw$;
do $W$
declare t text; n numeric;
begin
  -- W1 wallet to PayNow
  perform pg_temp.winv('w1', 100, 'wpaid');
  t := pg_temp.remethod('mgr1', 'w1', 'pm');
  perform pg_temp.check(t = 'ERR 42501 Only an Owner can change a payment into or out of wallet credit.' and pg_temp.method_of('w1') = pg_temp.fx('wpaid'),
    'W1 a Manager cannot change a wallet payment to PayNow: ' || t);
  perform pg_temp.winv('w1b', 100, 'wpaid');
  n := pg_temp.credit('paid');
  t := pg_temp.remethod('own', 'w1b', 'pm');
  perform pg_temp.check(t like 'ok:%' and pg_temp.method_of('w1b') = pg_temp.fx('pm') and pg_temp.credit('paid') = n + 100,
    'W1b an Owner does, and the S$100 of credit goes back to the wallet as before: ' || t);
  -- W2 PayNow to wallet
  perform pg_temp.winv('w2', 100, 'pm');
  t := pg_temp.remethod('mgr1', 'w2', 'wpaid');
  perform pg_temp.check(t = 'ERR 42501 Only an Owner can change a payment into or out of wallet credit.' and pg_temp.method_of('w2') = pg_temp.fx('pm'),
    'W2 a Manager cannot change a PayNow payment to wallet credit: ' || t);
  perform pg_temp.winv('w2b', 100, 'pm');
  n := pg_temp.credit('paid');
  t := pg_temp.remethod('own', 'w2b', 'wpaid');
  perform pg_temp.check(t like 'ok:%' and pg_temp.method_of('w2b') = pg_temp.fx('wpaid') and pg_temp.credit('paid') = n - 100,
    'W2b an Owner does, and S$100 of credit is taken as before: ' || t);
  -- W3 between money methods, and between wallet methods
  perform pg_temp.winv('w3', 100, 'pm');
  t := pg_temp.remethod('mgr1', 'w3', 'nets');
  perform pg_temp.check(t like 'ok:%' and pg_temp.method_of('w3') = pg_temp.fx('nets'), 'W3 a Manager still changes PayNow to NETS: ' || t);
  perform pg_temp.winv('w4', 100, 'wpaid');
  t := pg_temp.remethod('mgr1', 'w4', 'wbonus');
  perform pg_temp.check(t like 'ok:%' and pg_temp.method_of('w4') = pg_temp.fx('wbonus'),
    'W4 a Manager still changes Paid credit to Bonus credit (both wallet, so decision 10 does not apply): ' || t);
  -- W5 the other routes refuse a wallet method for everyone, with their sentences of before 533
  -- (Edit Invoice, correct_invoice, reaches correct_invoice_payment_methods, split and remove as the owner).
  perform pg_temp.winv('w5', 100, 'wpaid');
  perform pg_temp.winv('w5m', 100, 'pm');
  t := pg_temp.as_('pg:mgr1', format('select public.correct_invoice_payment_methods(%L, %L::jsonb, %L)::text', pg_temp.fx('w5'),
    jsonb_build_array(jsonb_build_object('payment_id', pg_temp.pay('w5'), 'payment_method_id', pg_temp.fx('pm'))), 'M533'));
  perform pg_temp.check(t = 'ERR P0001 A wallet credit payment cannot be changed this way — it consumed credit from the wallet',
    'W5 Edit Invoice''s method change still refuses wallet to PayNow for a Manager, as before: ' || t);
  t := pg_temp.as_('pg:own', format('select public.correct_invoice_payment_methods(%L, %L::jsonb, %L)::text', pg_temp.fx('w5'),
    jsonb_build_array(jsonb_build_object('payment_id', pg_temp.pay('w5'), 'payment_method_id', pg_temp.fx('pm'))), 'M533'));
  perform pg_temp.check(t = 'ERR P0001 A wallet credit payment cannot be changed this way — it consumed credit from the wallet',
    'W5b and for an Owner, as before: ' || t);
  t := pg_temp.as_('pg:mgr1', format('select public.correct_invoice_payment_methods(%L, %L::jsonb, %L)::text', pg_temp.fx('w5m'),
    jsonb_build_array(jsonb_build_object('payment_id', pg_temp.pay('w5m'), 'payment_method_id', pg_temp.fx('wpaid'))), 'M533'));
  perform pg_temp.check(t = 'ERR P0001 A wallet credit method cannot be set this way — refund and re-take the payment instead',
    'W5c and PayNow to wallet for a Manager, as before: ' || t);
  t := pg_temp.as_('pg:own', format('select public.correct_invoice_payment_methods(%L, %L::jsonb, %L)::text', pg_temp.fx('w5m'),
    jsonb_build_array(jsonb_build_object('payment_id', pg_temp.pay('w5m'), 'payment_method_id', pg_temp.fx('wpaid'))), 'M533'));
  perform pg_temp.check(t = 'ERR P0001 A wallet credit method cannot be set this way — refund and re-take the payment instead',
    'W5d and for an Owner, as before: ' || t);
  t := pg_temp.as_('pg:mgr1', format('select public.split_invoice_payment(%L, %L::jsonb, %L, %L)::text', pg_temp.pay('w5'),
    jsonb_build_array(jsonb_build_object('amount', 50, 'payment_method_id', pg_temp.fx('wpaid'), 'date', public.sg_today()),
                      jsonb_build_object('amount', 50, 'payment_method_id', pg_temp.fx('pm'), 'date', public.sg_today())), 'M533 split', gen_random_uuid()));
  perform pg_temp.check(t like 'ERR P0001 A wallet credit payment consumed credit from the wallet%',
    'W5e a Manager''s split of a wallet payment into a wallet part and a cash part is refused, as before: ' || t);
  t := pg_temp.as_('pg:own', format('select public.split_invoice_payment(%L, %L::jsonb, %L, %L)::text', pg_temp.pay('w5'),
    jsonb_build_array(jsonb_build_object('amount', 50, 'payment_method_id', pg_temp.fx('wpaid'), 'date', public.sg_today()),
                      jsonb_build_object('amount', 50, 'payment_method_id', pg_temp.fx('pm'), 'date', public.sg_today())), 'M533 split', gen_random_uuid()));
  perform pg_temp.check(t like 'ERR P0001 A wallet credit payment consumed credit from the wallet%', 'W5f and an Owner''s, as before: ' || t);
  t := pg_temp.as_('pg:mgr1', format('select public.split_invoice_payment(%L, %L::jsonb, %L, %L)::text', pg_temp.pay('w5m'),
    jsonb_build_array(jsonb_build_object('amount', 50, 'payment_method_id', pg_temp.fx('wpaid'), 'date', public.sg_today()),
                      jsonb_build_object('amount', 50, 'payment_method_id', pg_temp.fx('pm'), 'date', public.sg_today())), 'M533 split', gen_random_uuid()));
  perform pg_temp.check(t = 'ERR P0001 A wallet credit method cannot be set this way — refund and re-take the payment instead',
    'W5g a split of a PayNow payment with a wallet part is refused, as before: ' || t);
  t := pg_temp.as_('pg:own', format('select public.remove_invoice_payment(%L, %L, %L)::text', pg_temp.pay('w5'), 'M533 not paid', gen_random_uuid()));
  perform pg_temp.check(t like 'ERR P0001 A wallet credit payment consumed credit from the wallet%', 'W5h removing a wallet payment is refused, for an Owner too, as before: ' || t);
end $W$;

-- ═════ K Closed to logins ═════
do $K$
declare t text;
begin
  t := pg_temp.as_('mgr1', format('select public.cancel_invoice_recorded(%L, %L, %L)::text', pg_temp.fx('i1'), 'M533 straight', gen_random_uuid()));
  perform pg_temp.check(t like 'ERR 42501 permission denied for function cancel_invoice_recorded%'
                        and (select status::text from public.invoices where id = pg_temp.fx('i1')) <> 'cancelled',
    'K1 a login cannot call cancel_invoice_recorded straight: ' || t);
  t := pg_temp.as_('own', format('select public.cancel_invoice_recorded(%L, %L, %L)::text', pg_temp.fx('i1'), 'M533 straight', gen_random_uuid()));
  perform pg_temp.check(t like 'ERR 42501 permission denied for function cancel_invoice_recorded%', 'K1b not even an Owner: ' || t);
  t := pg_temp.as_('mgr1', format('select public.request_inventory_adjustment(''store''::public.location_type, %L, %L, 1, %L, null)::text',
    pg_temp.fx('sa'), pg_temp.fx('p'), 'M533 count'));
  perform pg_temp.check(t like 'ERR 42501 permission denied for function request_inventory_adjustment%', 'K2 nor the old request_inventory_adjustment: ' || t);
  t := pg_temp.as_('mgr1', format('select public.request_inventory_adjustments(%L, %L, %L::jsonb, %L, null, %L)::text', 'store', pg_temp.fx('sa'),
    jsonb_build_array(jsonb_build_object('product_id', pg_temp.fx('p2'), 'counted_qty', 499, 'current_qty', 500, 'new_qty', 499)), 'M533 count', gen_random_uuid()));
  perform pg_temp.check(t like 'ok:%', 'K3 the page''s request_inventory_adjustments still works: ' || t);
end $K$;

-- ═════ G 533's fixed parts ═════
\if :is_control
\echo NOTE  G, U and M are skipped (control)
\else
do $G$
begin
  perform pg_temp.check((select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace
                           and (p.oid::regprocedure::text, md5(pg_get_functiondef(p.oid))) in (
    ('review_and_dispatch_transfer(uuid,jsonb,text)', 'd1fe2d8b84895951f6f86fc1a89436d7'),
    ('reject_transfer(uuid,text)', 'cf337eabea93d00ae052853a0ffac850'),
    ('resolve_transfer_discrepancy(uuid,jsonb,text)', '00fadc33ac027da095483f22b6a6ed75'),
    ('resolve_inventory_adjustment(uuid,boolean,text)', '6aaa8f4ff405de2dde4cbf09ed7b1bcd'),
    ('resolve_invoice_action_v2(uuid,boolean,text,text,jsonb,jsonb,boolean)', 'd1ab83e457684ad3d010dd5a92719570'),
    ('refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid)', '4f81d244db8f8c5b6d35143456fa8cc7'),
    -- 542 (security audit of 17 Nov 2026, L20) changes these two: its AFTER md5s.
    ('resolve_invoice_action_v2(uuid,boolean,text,text,jsonb,jsonb,boolean)', 'beb94a98887d55d8698a830f489e1225'),
    ('refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid)', '7802bc26966f422978e2b764b289944f'),
    ('adjust_customer_credit(uuid,text,text,numeric,text,text,date,text,uuid,uuid)', '91d8bc8893f2be5df7c79a304067714b'),
    ('add_legacy_credit(uuid,text,numeric,date,uuid,text,text,date,uuid)', 'c1fc53090470a4e61a07aaf5a922d82d'),
    ('reverse_credit_lot(uuid,text,text,text)', '62ea75384be87010919f21a5884d0186'),
    ('affiliate_payout_save(uuid,integer,uuid,date,numeric,uuid,date,text,text,text,uuid)', 'd348969eb1673fb204957c43673983fc'),
    ('apply_line_foc(uuid,integer,uuid,text)', '4a0d20eccbdebaa9af74bd9c1eb362ef'),
    ('transfer_invoice_unused_benefit(uuid,uuid,uuid,text,uuid)', '9e108d79e6212474397b7c9cacf0dc27'),
    ('correct_invoice_payment(uuid,numeric,date,uuid,text,uuid)', '5ac4a3ac99f5e5cbda370fcd8c9f9cd0'),
    ('remove_invoice_payment(uuid,text,uuid)', 'ab2940828dffdd7aff007d036e88820b'),
    ('split_invoice_payment(uuid,jsonb,text,uuid)', 'f66d4ba00406e50171afcf6b4b79c969'),
    ('record_affiliate_deduction_settlement(uuid,numeric,date,text,text,uuid)', '66b37537ccdc44308e126889041f239f'),
    ('void_affiliate_deduction_settlement(uuid,text,uuid)', '6ceaca7815ed23c12bf233ebfa91d770'),
    ('create_staff_commission_payout(uuid,date,uuid,text,text)', '90c9d0ddd131fda739875bed4970e0e9'),
    ('invoice_payment_lowered_by(uuid)', '5502cb18da573d7b3132078bb0dbbde1'),
    ('invoice_taken_back(uuid)', '7bc3edff2b0307ea2fca9d9b7e8fa58b'))) = 20,
    'G1 the eighteen functions and the two helpers are 533''s');
  perform pg_temp.check(not has_function_privilege('authenticated', 'public.invoice_taken_back(uuid)', 'execute')
    and not has_function_privilege('anon', 'public.invoice_taken_back(uuid)', 'execute')
    and not has_function_privilege('authenticated', 'public.invoice_payment_lowered_by(uuid)', 'execute')
    and not has_function_privilege('anon', 'public.invoice_payment_lowered_by(uuid)', 'execute')
    and not has_function_privilege('authenticated', 'public.cancel_invoice_recorded(uuid,text,uuid)', 'execute')
    and not has_function_privilege('authenticated', 'public.request_inventory_adjustment(location_type,uuid,uuid,integer,text,text)', 'execute')
    and has_function_privilege('service_role', 'public.cancel_invoice_recorded(uuid,text,uuid)', 'execute')
    and has_function_privilege('authenticated', 'public.resolve_invoice_action_v2(uuid,boolean,text,text,jsonb,jsonb,boolean)', 'execute')
    and has_function_privilege('authenticated', 'public.refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid)', 'execute'),
    'G2 the helpers and the two closed functions cannot be called by a login; the pages'' functions can');
  perform pg_temp.check((select count(*) from pg_proc p where p.oid in (to_regprocedure('public.current_user_role()'), to_regprocedure('public.current_user_store_ids()'),
                           to_regprocedure('public.is_owner_or_manager()'), to_regprocedure('public.can_manage_customer_credit()'),
                           to_regprocedure('public.affiliate_payout_access(boolean)'), to_regprocedure('public.cancel_invoice_recorded(uuid,text,uuid)'))
                           and md5(pg_get_functiondef(p.oid)) in ('519b0a33a3548f970c5d585b6e76a389', '54191b973c31654b903d48bea01ce533',
                             'a98e50f1b6d3fa1e6c62cf52a8073cc8', 'a576249272a4c7fb68965d0f62649ed4', '90b7399378a7604afd4af97c059d0703',
                             '5490e4b48dfdab63b6dc5a0aa78d4bc7')) = 6,
    'G3 the helpers left alone and cancel_invoice_recorded''s text are unchanged');
end $G$;
\if :by_us
select pg_temp.check(
  (select string_agg(fn, ',' order by fn) from fn1 a full join fn0 b using (fn) where a.md5 is distinct from b.md5 or a.acl is distinct from b.acl)
  = 'add_legacy_credit(uuid,text,numeric,date,uuid,text,text,date,uuid),adjust_customer_credit(uuid,text,text,numeric,text,text,date,text,uuid,uuid),affiliate_payout_save(uuid,integer,uuid,date,numeric,uuid,date,text,text,text,uuid),apply_line_foc(uuid,integer,uuid,text),cancel_invoice_recorded(uuid,text,uuid),correct_invoice_payment(uuid,numeric,date,uuid,text,uuid),create_staff_commission_payout(uuid,date,uuid,text,text),invoice_payment_lowered_by(uuid),invoice_taken_back(uuid),record_affiliate_deduction_settlement(uuid,numeric,date,text,text,uuid),refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid),reject_transfer(uuid,text),remove_invoice_payment(uuid,text,uuid),request_inventory_adjustment(location_type,uuid,uuid,integer,text,text),resolve_inventory_adjustment(uuid,boolean,text),resolve_invoice_action_v2(uuid,boolean,text,text,jsonb,jsonb,boolean),resolve_transfer_discrepancy(uuid,jsonb,text),reverse_credit_lot(uuid,text,text,text),review_and_dispatch_transfer(uuid,jsonb,text),split_invoice_payment(uuid,jsonb,text,uuid),transfer_invoice_unused_benefit(uuid,uuid,uuid,text,uuid),void_affiliate_deduction_settlement(uuid,text,uuid)',
  'G4 installed here: only the eighteen functions, the two helpers and the two closed grants differ from before');
\endif

-- ═════ U The undo, and M 533 a second time ═════
\if :by_us
-- U1 refused while another function calls a helper.
savepoint u1;
create function public.m533_other(p uuid) returns numeric language sql as $f$ select public.invoice_taken_back(p) $f$;
\set ON_ERROR_STOP off
\ir ../undo-533.sql
\set ON_ERROR_STOP on
rollback to savepoint u1;
select pg_temp.check(:'LAST_ERROR_MESSAGE' like 'undo 533: 533''s helpers are also used by%', 'U1 the undo refuses while another function calls a helper: ' || :'LAST_ERROR_MESSAGE');
-- U2 the undo puts everything back.
\ir ../undo-533.sql
select pg_temp.check(not exists (select 1 from (select p.oid::regprocedure::text as fn, md5(pg_get_functiondef(p.oid)) as md5, p.proacl::text as acl
                                                  from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p')) a
                                  full join fn0 b using (fn) where a.md5 is distinct from b.md5 or a.acl is distinct from b.acl),
  'U2 after the undo every function and its rights are those of before 533, and the helpers are gone');
-- U3 a second undo refuses.
savepoint u3;
\set ON_ERROR_STOP off
\ir ../undo-533.sql
\set ON_ERROR_STOP on
rollback to savepoint u3;
select pg_temp.check(:'LAST_ERROR_MESSAGE' like 'undo 533: public.review_and_dispatch_transfer(uuid,jsonb,text) is already its version of before 533%', 'U3 the undo a second time refuses: ' || :'LAST_ERROR_MESSAGE');
-- U4 533 again makes exactly what it made.
\ir ../../../supabase/533_approvals_need_another_person_and_owner_limits.sql
select pg_temp.check(not exists (select 1 from (select p.oid::regprocedure::text as fn, md5(pg_get_functiondef(p.oid)) as md5, p.proacl::text as acl
                                                  from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p')) a
                                  full join fn1 b using (fn) where a.md5 is distinct from b.md5 or a.acl is distinct from b.acl),
  'U4 533 after the undo makes exactly what it made the first time');
-- M 533 a second time refuses and changes nothing.
savepoint m1;
\set ON_ERROR_STOP off
\ir ../../../supabase/533_approvals_need_another_person_and_owner_limits.sql
\set ON_ERROR_STOP on
rollback to savepoint m1;
select pg_temp.check(:'LAST_ERROR_MESSAGE' like '533 is already in on this database%', 'M1 533 a second time refuses: ' || :'LAST_ERROR_MESSAGE');
\else
\echo NOTE  U and M are skipped (533 was not installed by this file)
\endif
\endif

select count(*) as n_failed from failed \gset
\if :is_control
\echo control: :n_failed checks failed without 533 (each is one 533 makes pass)
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
