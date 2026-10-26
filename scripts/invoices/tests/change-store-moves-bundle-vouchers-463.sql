-- 463: a customer change that takes the benefits along also takes what an
-- Owner moved to the same customer at another store, and a Premium Bundle's
-- vouchers (the Owner, 24 Oct 2026, decisions 2 and 3); its summary says
-- what a waiting reopening will give back (W1, 460's NOT COVERED 7); no
-- invoice for a removed customer record (K6s).
-- supabase/463_change_takes_store_moves_and_bundle_vouchers.sql (after 462).
--
-- Every step goes through the app's own calls (462's suite harness): the
-- invoice form (create_invoice_with_details) and the Pay dialog
-- (record_invoice_settlement), Record Payment, Cancel, the Finance panel's
-- refund by line and "Record refund paid" (refund_invoice_recorded), its
-- Correct payment (correct_invoice_payment), Reopen, Move
-- (transfer_invoice_unused_benefit), the invoice form's customer change
-- (correct_invoice, 'transfer' or 'keep', and its summary,
-- preview_invoice_correction), a customer merge, Delete customer. Each app
-- call is followed by what its commit does (462's trigger is deferred; this
-- suite is one transaction, so its queued rows are run at that point; and
-- the vouchers the call gave are dated when it ends, as a call committed on
-- its own dates them, so a voucher given again after a change is dated
-- after it: the critics of 24 Oct 2026 found the one transaction hid that).
--
-- The cases (A the buyer; B, C later customers; K a record a merge keeps; F
-- a friend an Owner moved something to; cp a S$100 Credit Package, cpb one
-- with a S$10 Bonus, v a voucher line of two S$30 vouchers, vl the same
-- limited, pbv a S$140 Premium Bundle with two vouchers, pbl one with two
-- limited vouchers; 'store2' the second store):
--   T1 to T1x, T1h: the package's credit moved by an Owner to A at the
--      second store, then the customer changed (with a second change, a
--      merge, a reopening before or while it waits, the Bonus too, a refund
--      by line after): decision 2. C2, C2r, C2w: cancelled, refunded in full
--      or waiting for a reopening's payment after the change, then reopened
--      (paid).
--   T1p, T1d: a session paid from the package before the Move, refunded
--      (or its payment corrected to cash) before the change. T1s, P1: a
--      session paid from the moved credit, or from the package before the
--      Move, blocks the change ("Partly spent", 461's rule, as L5 without the
--      Move; the critics of 24 Oct 2026).
--   T2 to T2m, T2wc: the two vouchers moved to A at the second store, then
--      the change (cancelled and reopened after; a reopening waiting; the
--      store changed too; a reopening paid before; given again after the
--      change, then reopened again).
--   V3 to V4m, V9, V3r, C4, V4c, V3rC, V3w: a Premium Bundle's vouchers on a
--      change (a second change, the store changed too, a reopening waiting,
--      the line refunded in full first, then merged; its vouchers moved to A
--      at the second store first; cancelled or refunded in full after the
--      change and reopened; given again after the change and reopened
--      again, or changed again): decision 3.
--   Controls (the same with and without 463): T1k, T2k, V3k, T1sk, P1k
--   ('keep'), T1f, T1g, T2f (moved to a friend, or by the friend to another
--   store: the friend keeps it), T1n, V1w, V3x, V3rx, C2x, C2rx, T2x, C2wx,
--   V3wx (cancelled, refunded or waiting after the change: nobody holds
--   anything), V5, V6, X3, K1, F2, L5, K8, S4.
-- In every case: 462's invariants (no lot of the invoice's family holds
-- credit unless a record names it; each lot's balance is its ledger's; no
-- chain over 12; moved lots traced and spendable; origins kept; a named
-- lot holding credit is held by whoever holds the benefits, by 463's rule
-- where 463 is in: a Move to the same customer at another store is the
-- invoice's own), and Cancel (tried, undone) takes all of the invoice's
-- credit back from whoever holds it.
--
--   S. Where it starts: 462 in (installed first where it is not), 463 in
--      (nomig) or not, the eight functions at their BEFOREs.
--   R. Without 463 (skipped with -v nomig=1), undone: each 'fixed' case
--      ends otherwise (the old outcome reproduced); each control as
--      expected.
--   Q. The read-only query in 463's header (the same text), on those
--      states: what it lists, by reason (exactly the expected cases for 1,
--      3, 5 to 9); the controls not listed, or only where expected (the
--      cancelled, refunded and waiting ones under 6 to 8).
--   9. Refusals, each changing nothing: the R states (credit moved to the
--      same customer held by the old customer after a change: exactly the
--      invoices Q lists under 1); a changed function, a changed function it
--      relies on, 462's trigger missing, a new way of giving a bundle's
--      vouchers, an overload. The same grants in another order do not stop
--      it.
--   M. The mid set: begun before 463, finished after it (also cancelled,
--      refunded or waiting after the change when it goes in, and with
--      vouchers given again to the old customer after the change).
--  10. 463 installed twice: as tested, the second run changing nothing, two
--      functions added, the other grants as before (as sets).
--   A. Each case after 463: who holds what (and at which store), the plans'
--      codes and refund due, the invariants, Cancel; the controls exactly
--      as before 463.
--   V. Vouchers: a store-moved limited voucher, and a bundle's, keep their
--      store (no stock moves); a voucher line's go to the new store with
--      their stock (417); the change's list and summary show them, and show
--      store-moved credit from a partly spent package as blocking.
--   W. W1: the summary of a change while a reopening waits lists what its
--      payment will give the new customer (not what was moved to a friend;
--      nothing with 'keep'; nothing when nothing waits), and the payment
--      gives exactly that.
--   G. K6s: no invoice for a record a merge retired or Delete removed; a
--      request made before the merge still gets back its invoice.
--   K. KNOWN (not covered by 463), checked as they are: W2 (460's NOT
--      COVERED 3), S1m (445's NOT COVERED 1).
--
-- Run on a copy of production as it is (464 in: 432fcb99, 1379 functions;
-- 465 and 467, TikTok only, do not change what it checks):
--   psql -X -v ON_ERROR_STOP=1 -f scripts/invoices/tests/change-store-moves-bundle-vouchers-463.sql
-- It installs 462 first where it is not in, then 463 itself (twice), inside
-- its transaction. Where 463 is in already, add -v nomig=1 (S checks it as
-- tested; R, Q, 9 and M are skipped; every case after 463 is still
-- checked). Sections 9 let the install fail on purpose (psql prints its
-- ERROR); the suite then checks that message. Disposable database only;
-- everything is rolled back. Every name, code and amount is invented
-- (@example.com); the phones are numbers kept for fiction (ACMA,
-- +61491570000 to +61491570999).
-- Where 470 is in too (-v nomig=1), the forwarder is at 470's AFTER (470
-- adds nothing); every case here ends as before (470's suite checks what it
-- changes). Where 471 is in too, the forwarder is at 471's AFTER (471 adds
-- nothing; it holds back in place, without a reissue, what is given back
-- while a package is cancelled, refunded or waiting); every case here ends
-- as before (471's suite, plain-cancelled-package-credit-471, checks that).
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '10s';
set local statement_timeout = '900s';

-- ── Set-up and the app's calls (462's suite harness, for 463) ─────────────
create temp table t463(k text primary key, id uuid);
create temp table t463_res(phase text, k text, v jsonb, primary key (phase, k));
create temp sequence t463_phone;
create function pg_temp.t463_id(p_k text) returns uuid language sql as $f$ select id from t463 where k = p_k $f$;
create function pg_temp.t463_put(p_k text, p_id uuid) returns uuid language sql as $f$
  insert into t463 values (p_k, p_id) on conflict (k) do update set id = excluded.id returning id $f$;
create function pg_temp.t463_check(p_ok boolean, p_label text) returns void language plpgsql as $f$
begin
  if not coalesce(p_ok, false) then raise exception 'FAIL %', p_label; end if;
end $f$;
create function pg_temp.t463_fingerprint() returns text language sql as $f$
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.oid::regprocedure::text)) || ' ' || count(*)
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prokind in ('f', 'p') $f$;
create function pg_temp.t463_462_in() returns boolean language sql as $f$
  select to_regprocedure('public.credit_given_back_follows(uuid)') is not null
     and exists (select 1 from pg_trigger where tgname = 'credit_given_back_follows'
                  and tgrelid = 'public.customer_credit_ledger'::regclass) $f$;
create function pg_temp.t463_in() returns boolean language sql as $f$
  select to_regprocedure('public.invoice_benefit_moved_to_other(uuid)') is not null $f$;
-- 470 is in: the forwarder at 470's AFTER.
create function pg_temp.t463_470_in() returns boolean language sql as $f$
  select to_regprocedure('public.credit_given_back_follows(uuid)') is not null
     and md5(pg_get_functiondef('public.credit_given_back_follows(uuid)'::regprocedure)) = 'b7720a148f5371bd2bd844d3076ea3b2' $f$;
-- 471 is in: the forwarder at 471's AFTER.
create function pg_temp.t463_471_in() returns boolean language sql as $f$
  select to_regprocedure('public.credit_given_back_follows(uuid)') is not null
     and md5(pg_get_functiondef('public.credit_given_back_follows(uuid)'::regprocedure)) = '1417d83e7d7be49209f5cd1369d07ec7' $f$;
-- What a commit does at the end of each app call (each is its own
-- transaction in the app): 462's deferred trigger runs. Here the suite is
-- one transaction, so the trigger's queued rows are run at this point.
-- (Not where each step really commits: t463.autocommit 'on', for running
-- the same cases one call per transaction on a disposable copy; there the
-- dating below changes nothing, each call having its own now().)
create function pg_temp.t463_commit() returns void language plpgsql as $f$
begin
  if pg_temp.t463_462_in() and coalesce(current_setting('t463.autocommit', true), '') <> 'on' then
    execute 'set constraints public.credit_given_back_follows immediate';
    execute 'set constraints public.credit_given_back_follows deferred';
  end if;
  -- And what the call gave is dated when it ends, as a call that is its own
  -- transaction dates it (the suite's now() is the same for every call): the
  -- vouchers it gave (a voucher given again after a change is dated after
  -- the change's Audit Log row, which t463_change dates the same way). So
  -- what reads when a voucher was given (who a reopening gives it to, the
  -- header's query) sees the order the app makes (the critics of 24 Oct
  -- 2026: one transaction dated a voucher given again after a change before
  -- that change).
  update customer_reward_vouchers set issued_at = clock_timestamp() where issued_at = now();
end $f$;

do $$
declare own uuid := gen_random_uuid(); st uuid; st2 uuid; pm uuid; v uuid; vl uuid; cp uuid; cpb uuid; pbv uuid; pbl uuid; svc uuid; svc5 uuid;
begin
  insert into auth.users(id, email) values (own, 't463-owner@example.com');
  insert into profiles(id, full_name, email, role, is_active) values (own, 'T463 Owner', 't463-owner@example.com', 'owner', true);
  perform set_config('request.jwt.claims', json_build_object('sub', own, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', own::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  insert into stores(name, code, country_code) values ('T463 Store', 'T463S1', 'SG') returning id into st;
  insert into stores(name, code, country_code) values ('T463 Other Store', 'T463S2', 'SG') returning id into st2;
  insert into payment_methods(name, is_active) values ('T463 Cash', true) returning id into pm;
  insert into vouchers(name, code, voucher_kind, qty_type, selling_price, is_active)
    values ('T463 Plain 30', 'T463-P30', 'normal', 'unlimited', 30, true) returning id into v;
  insert into voucher_store_prices(voucher_id, store_id, selling_price, available_at_store) values (v, st, 30, true), (v, st2, 30, true);
  insert into credit_packages(name, customer_price, paid_credit_amount, bonus_enabled, allow_product, allow_therapy)
    values ('T463 S$100', 100, 100, false, true, true) returning id into cp;
  insert into credit_package_stores(package_id, store_id) values (cp, st), (cp, st2);
  insert into credit_packages(name, customer_price, paid_credit_amount, bonus_enabled, bonus_value, allow_product, allow_therapy, grants_reward)
    values ('T463 S$100 + S$10', 100, 100, true, 10, true, true, false) returning id into cpb;
  insert into credit_package_stores(package_id, store_id) values (cpb, st), (cpb, st2);
  insert into premium_bundles(name, customer_payment_amount, paid_credit_amount, bonus_credit_amount, free_voucher_qty, grants_reward)
    values ('T463 Bundle S$140 + 2 vouchers', 140, 100, 40, 2, true) returning id into pbv;
  insert into premium_bundle_stores(bundle_id, store_id) values (pbv, st), (pbv, st2);
  insert into premium_bundle_vouchers(bundle_id, voucher_id) values (pbv, v);
  -- A limited S$30 voucher (100 in stock at each store) and a bundle that
  -- gives two of it: what a change does with its stock.
  insert into vouchers(name, code, voucher_kind, qty_type, selling_price, is_active)
    values ('T463 Limited 30', 'T463-L30', 'normal', 'limited', 30, true) returning id into vl;
  insert into voucher_store_prices(voucher_id, store_id, selling_price, available_at_store) values (vl, st, 30, true), (vl, st2, 30, true);
  insert into voucher_store_stock(voucher_id, store_id, current_qty) values (vl, st, 100), (vl, st2, 100);
  insert into premium_bundles(name, customer_payment_amount, paid_credit_amount, bonus_credit_amount, free_voucher_qty, grants_reward)
    values ('T463 Bundle S$140 + 2 limited', 140, 100, 40, 2, true) returning id into pbl;
  insert into premium_bundle_stores(bundle_id, store_id) values (pbl, st), (pbl, st2);
  insert into premium_bundle_vouchers(bundle_id, voucher_id) values (pbl, vl);
  svc := (upsert_therapy_service(null, 'T463-SESSION', 'T463 Session', 20, 30, 'per_hours', 1, 5, null, true, null) ->> 'id')::uuid;
  perform set_therapy_service_store(svc, st, true, null);
  svc5 := (upsert_therapy_service(null, 'T463-SHORT', 'T463 Short session', 5, 15, 'per_hours', 1, 5, null, true, null) ->> 'id')::uuid;
  perform set_therapy_service_store(svc5, st, true, null);
  insert into t463 values ('own', own), ('store', st), ('store2', st2), ('pm', pm), ('v', v), ('vl', vl), ('cp', cp), ('cpb', cpb), ('pbv', pbv), ('pbl', pbl),
    ('svc', svc), ('svc5', svc5),
    ('wallet', (select id from payment_methods where name = 'Wallet — Credit Package Paid' and is_wallet_credit and deleted_at is null)),
    ('bwallet', (select id from payment_methods where name = 'Wallet — Premium Bundle Paid' and is_wallet_credit and deleted_at is null));
  perform pg_temp.t463_check(pg_temp.t463_id('wallet') is not null and pg_temp.t463_id('bwallet') is not null, 'setup: the wallet methods (443) are there');
end $$;

-- A customer of one run of one case: '<phase>/<case>/<role>'.
create function pg_temp.t463_cust(p_k text) returns uuid language plpgsql as $f$
declare c uuid;
begin
  insert into customers(full_name, phone) values ('T463 ' || p_k, '+61491570' || lpad((nextval('t463_phone') % 1000)::text, 3, '0'))
    returning id into c;
  return pg_temp.t463_put(p_k, c);
end $f$;
-- The invoice form with these lines ('cp' / 'cpb' a Credit Package, 'pbv' the
-- Premium Bundle ('pbl' the one with limited vouchers), 'v' ('vl' limited) a
-- voucher line of p_qty units), paid through the Pay
-- dialog: in full, or p_first of it (a part-paid package).
create function pg_temp.t463_sale(p_cust uuid, p_kinds text[], p_first numeric default null, p_qty int default 2)
  returns uuid language plpgsql as $f$
declare inv uuid; v_lines jsonb := '[]'; i int;
begin
  for i in 1 .. cardinality(p_kinds) loop
    v_lines := v_lines || jsonb_build_array(case
      when p_kinds[i] in ('v', 'vl') then jsonb_build_object('kind', 'voucher', 'voucher_id', pg_temp.t463_id(p_kinds[i]), 'quantity', p_qty)
      when p_kinds[i] in ('cp', 'cpb') then jsonb_build_object('kind', 'credit_package', 'credit_package_id', pg_temp.t463_id(p_kinds[i]), 'quantity', 1)
      else jsonb_build_object('kind', 'premium_bundle', 'premium_bundle_id', pg_temp.t463_id(p_kinds[i]), 'quantity', 1,
        'voucher_selection', jsonb_build_array(jsonb_build_object('voucher_id',
          pg_temp.t463_id(case when p_kinds[i] = 'pbl' then 'vl' else 'v' end), 'quantity', 2))) end);
  end loop;
  inv := create_invoice_with_details(pg_temp.t463_id('store'), p_cust, v_lines, jsonb_build_object('business_date', sg_today()::text));
  perform record_invoice_settlement(inv, jsonb_build_object('receipts', jsonb_build_array(jsonb_build_object(
    'key', 'line-0', 'payment_method_id', pg_temp.t463_id('pm'),
    'amount', coalesce(p_first, (select total_amount from invoices where id = inv)),
    'payment_date', sg_today()::text)), 'arrangements', '[]'::jsonb), gen_random_uuid());
  return inv;
end $f$;
-- Record Payment of what is outstanding (nothing when it is settled).
create function pg_temp.t463_pay(p_inv uuid) returns void language plpgsql as $f$
begin
  if (invoice_financial_position(p_inv)->>'outstanding')::numeric > 0 then
    perform record_invoice_payment(p_inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.t463_id('pm'),
      'amount', (invoice_financial_position(p_inv)->>'outstanding')::numeric)), gen_random_uuid());
  end if;
end $f$;
-- The receipts that still hold p_amount between them, as the Finance panel
-- splits a refund across them.
create function pg_temp.t463_sources(p_inv uuid, p_amount numeric) returns jsonb language plpgsql as $f$
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
create function pg_temp.t463_line(p_inv uuid, p_n int default 1) returns uuid language sql as $f$
  select id from invoice_items where invoice_id = p_inv order by id offset p_n - 1 limit 1 $f$;
-- The Finance panel's refund by line of line p_n: p_amount off its Paid
-- benefit (the one an Owner did not move, or with p_holder the one p_holder
-- holds), or every unused benefit it still holds (p_amount null).
create function pg_temp.t463_back(p_inv uuid, p_n int, p_amount numeric default null, p_holder uuid default null)
  returns void language plpgsql as $f$
declare opts jsonb; ben jsonb; tot numeric; item uuid := pg_temp.t463_line(p_inv, p_n);
begin
  opts := invoice_refund_options_before_sessions(p_inv);
  if p_amount is not null then
    select jsonb_build_array(jsonb_build_object('benefit_id', b->>'id', 'amount', p_amount)), p_amount
      into ben, tot
      from jsonb_array_elements(opts->'benefits') b
      left join invoice_benefit_values bv on bv.id = (b->>'id')::uuid
      left join customer_credit_lots l on l.id = bv.lot_id
     where b->>'invoice_item_id' = item::text and b->>'benefit_kind' = 'paid'
       and (p_holder is null and not exists (select 1 from invoice_benefit_transfers t where t.replacement_benefit_id = bv.id)
            or l.customer_id = p_holder)
     order by (b->>'paid_value')::numeric desc limit 1;
  else
    select jsonb_agg(jsonb_build_object('benefit_id', b->>'id', 'amount', (b->>'max_refund')::numeric)), sum((b->>'max_refund')::numeric)
      into ben, tot from jsonb_array_elements(opts->'benefits') b
     where b->>'invoice_item_id' = item::text and (b->>'max_refund')::numeric > 0;
  end if;
  if ben is null then raise exception 'T463: nothing to refund on that line'; end if;
  perform refund_invoice_recorded(p_inv, jsonb_build_array(jsonb_build_object('invoice_item_id', item, 'amount', tot, 'benefits', ben)),
    pg_temp.t463_sources(p_inv, tot), '[]'::jsonb, 'T463 by line', gen_random_uuid());
end $f$;
-- The invoice form's customer change, its lines as they are (and the store,
-- when given), with 'transfer' or 'keep'. The change's Audit Log row is
-- dated now, as a later call's is (the suite is one transaction).
create function pg_temp.t463_lines(p_inv uuid) returns jsonb language sql as $f$
  select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('invoice_item_id', it.id, 'kind', it.line_kind,
           'credit_package_id', it.credit_package_id, 'premium_bundle_id', it.premium_bundle_id, 'voucher_id', it.voucher_id,
           'quantity', it.quantity, 'unit_price', it.unit_price, 'voucher_selection', it.bundle_voucher_selection)) order by it.id)
    from invoice_items it where it.invoice_id = p_inv $f$;
create function pg_temp.t463_change(p_inv uuid, p_cust uuid, p_action text default 'transfer', p_store text default null)
  returns void language plpgsql as $f$
begin
  perform correct_invoice(p_inv, pg_temp.t463_lines(p_inv),
    jsonb_build_object('expected_edit_count', (select edit_count from invoices where id = p_inv),
      'customer_id', p_cust, 'store_id', coalesce(pg_temp.t463_id(p_store), (select store_id from invoices where id = p_inv)),
      'benefit_action', p_action),
    'T463 wrong customer', gen_random_uuid());
  update audit_logs set created_at = clock_timestamp()
   where record_id = p_inv and action = 'invoice_benefits_followed_reassignment' and new_data->>'to_customer' = p_cust::text
     and created_at = now();
end $f$;
create function pg_temp.t463_merge(p_keep uuid, p_dup uuid) returns void language plpgsql as $f$
begin
  perform merge_customer_records(p_keep, p_dup, 'T463 the same person', gen_random_uuid());
end $f$;
-- The Finance panel's Move of line p_n's (0: any line's) unused benefit (its Paid credit,
-- or its Bonus with p_kind 'bonus', or a voucher) to p_to, at p_store.
create function pg_temp.t463_move(p_inv uuid, p_n int, p_to uuid, p_kind text default 'paid', p_store text default null)
  returns void language plpgsql as $f$
declare b uuid;
begin
  select bv.id into b from invoice_benefit_values bv
    left join customer_reward_vouchers v on v.id = bv.reward_voucher_id
    left join customer_credit_lots l on l.id = bv.lot_id
   where (p_n = 0 and bv.invoice_id = p_inv or p_n > 0 and bv.invoice_item_id = pg_temp.t463_line(p_inv, greatest(p_n, 1)))
     and (v.status = 'held' and p_kind = 'voucher' or l.remaining_amount > 0 and l.category = p_kind)
   order by bv.granted_value desc limit 1;
  if b is null then raise exception 'T463: nothing to move on that line'; end if;
  perform transfer_invoice_unused_benefit(b, p_to, coalesce(pg_temp.t463_id(p_store), (select store_id from invoices where id = p_inv)),
    'T463 move', gen_random_uuid());
end $f$;
-- The invoice form: p_n sessions of S$20 (or S$5 with p_svc 'svc5') for
-- p_cust, paid with the wallet (Credit Package Paid) through Record Payment.
create function pg_temp.t463_spend(p_cust uuid, p_n int default 1, p_svc text default 'svc') returns uuid language plpgsql as $f$
declare inv uuid; v_lines jsonb := '[]'; i int;
begin
  for i in 1 .. p_n loop
    v_lines := v_lines || jsonb_build_array(jsonb_build_object('kind', 'therapy', 'therapy_service_id', pg_temp.t463_id(p_svc), 'quantity', 1));
  end loop;
  inv := create_invoice_with_details(pg_temp.t463_id('store'), p_cust, v_lines, jsonb_build_object('business_date', sg_today()::text));
  perform record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.t463_id('wallet'),
    'amount', (select total_amount from invoices where id = inv))), gen_random_uuid());
  if (select status::text from invoices where id = inv) <> 'paid' then raise exception 'T463: the session paid from credit is not paid'; end if;
  return inv;
end $f$;
-- The session cancelled and "Record refund paid": what its payment took goes
-- back to the lots it came from (refund_invoice_recorded's wallet refund).
create function pg_temp.t463_unspend(p_inv uuid) returns void language plpgsql as $f$
declare due numeric;
begin
  perform cancel_invoice_recorded(p_inv, 'T463 cancel session', gen_random_uuid());
  due := (invoice_financial_position(p_inv)->>'refund_due')::numeric;
  if due is null or due <= 0 then due := (invoice_action_plan(p_inv, 'cancel', '[]')->>'refund_due')::numeric; end if;
  perform refund_invoice_recorded(p_inv, jsonb_build_array(jsonb_build_object('amount', due)), pg_temp.t463_sources(p_inv, due), '[]'::jsonb,
    'T463 refund paid', gen_random_uuid());
end $f$;
-- The Finance panel's Correct payment on a session's wallet payment: the
-- date only ('date'), a smaller amount ('amount', S$5 less), or another
-- method ('cash').
create function pg_temp.t463_fix(p_inv uuid, p_how text) returns void language plpgsql as $f$
declare p invoice_payments%rowtype;
begin
  select * into p from invoice_payments where invoice_id = p_inv and entry_kind in ('receipt', 'correction_replacement')
     and not exists (select 1 from invoice_payments q where q.corrects_payment_id = invoice_payments.id and q.entry_kind = 'correction_reversal')
   order by created_at desc, id desc limit 1;
  perform correct_invoice_payment(p.id,
    case p_how when 'amount' then p.amount - 5 else p.amount end,
    sg_today() - 1,
    case p_how when 'cash' then pg_temp.t463_id('pm') else p.payment_method_id end,
    'T463 correct payment ' || p_how, gen_random_uuid());
end $f$;
-- A special document's wallet payment as pay_special_with_credit records it
-- (a stand-in: no page calls that function, and no credit category allows a
-- special document today, purchase_category): p_amount off the customer's
-- largest lot ('use', its allocations), so refund_special_credit, the real
-- one, gives it back.
create function pg_temp.t463_special(p_cust uuid, p_kind text, p_doc uuid, p_amount numeric) returns void language plpgsql as $f$
declare l customer_credit_lots%rowtype; e uuid;
begin
  select * into l from customer_credit_lots where customer_id = p_cust and status = 'active' and remaining_amount >= p_amount
   order by remaining_amount desc, id limit 1 for update;
  insert into customer_credit_ledger(wallet_id, customer_id, entry_type, category, amount, lot_id, source_type, source_record_id, store_id, note, created_by)
  values (l.wallet_id, p_cust, 'use', l.category, p_amount, l.id, p_kind, p_doc, l.store_id, 'T463 special', auth.uid()) returning id into e;
  update customer_credit_lots set remaining_amount = remaining_amount - p_amount, updated_at = now() where id = l.id;
  insert into customer_credit_allocations(ledger_entry_id, lot_id, customer_id, amount) values (e, l.id, p_cust, p_amount);
  insert into special_credit_allocations(doc_kind, doc_id, customer_id, lot_id, category, amount, created_by)
  values (p_kind, p_doc, p_cust, l.id, l.category, p_amount, auth.uid());
end $f$;
-- The guided Refund in full / Cancel as an Owner confirms it, with a reason
-- for every override the plan asks for, the money recorded as paid back.
create function pg_temp.t463_guided(p_inv uuid, p_action text) returns void language plpgsql as $f$
declare plan jsonb; req jsonb; ov jsonb;
begin
  plan := invoice_action_plan(p_inv, p_action, '[]');
  req := request_invoice_action_v2(p_inv, p_action, '[]', 'T463 ' || p_action, null, gen_random_uuid());
  select coalesce(jsonb_agg(case when coalesce((o->>'amount_required')::boolean, false)
           then jsonb_build_object('code', o->>'code', 'reason', 'T463 override', 'amount', (o->>'default_amount')::numeric)
           else jsonb_build_object('code', o->>'code', 'reason', 'T463 override') end), '[]'::jsonb)
    into ov from jsonb_array_elements(coalesce(plan->'overrides_required', '[]')) o;
  perform resolve_invoice_action_v2((req->>'request_id')::uuid, true, 'T463 ' || p_action, plan->>'plan_hash', ov, null, true);
end $f$;


-- ── What the records say ────────────────────────────────────────────────────
create function pg_temp.t463_moved_to_other(p_benefit uuid) returns boolean language plpgsql as $f$
declare v boolean;
begin
  execute 'select public.invoice_benefit_moved_to_other($1)' into v using p_benefit;
  return v;
end $f$;
-- The lots an invoice's records name: its benefit values, its sale's lots, a
-- split's issued lot, released credit (credit_package_progress_lots).
create function pg_temp.t463_named(p_inv uuid) returns setof uuid language sql as $f$
  select lot_id from invoice_benefit_values where invoice_id = p_inv and lot_id is not null
  union select x from credit_package_sales s, unnest(array[s.credit_lot_id, s.bonus_credit_lot_id]) x where s.invoice_id = p_inv and x is not null
  union select x from premium_bundle_sales s, unnest(array[s.paid_credit_lot_id, s.bonus_credit_lot_id]) x where s.invoice_id = p_inv and x is not null
  union select issued_lot_id from invoice_credit_splits where invoice_id = p_inv and issued_lot_id is not null
  union select lot_id from credit_package_progress_lots where invoice_id = p_inv $f$;
-- The invoice's lot family (the critic's 6): every lot its records name and
-- each Move's two lots (from the Move's ledger rows), the lots each replaced
-- and every lot reissued from any of them.
create function pg_temp.t463_family(p_inv uuid) returns setof uuid language sql as $f$
  with recursive seed as (
    select x as id from pg_temp.t463_named(p_inv) x
    union select e.lot_id from customer_credit_ledger e join invoice_benefit_transfers t on t.id = e.source_record_id
     where t.invoice_id = p_inv and e.source_type in ('invoice_benefit_transfer_out', 'invoice_benefit_transfer_in')),
  up(id, n) as (select id, 0 from seed
                union select l.reassigned_from_lot_id, up.n + 1 from up join customer_credit_lots l on l.id = up.id
                 where l.reassigned_from_lot_id is not null and up.n < 30),
  down(id, n) as (select id, 0 from up
                  union select l.id, down.n + 1 from down join customer_credit_lots l on l.reassigned_from_lot_id = down.id where down.n < 30)
  select distinct id from down $f$;
-- The lots behind a lot an invoice's benefit rows name: those it replaced,
-- back along reissues of the same source (credit given back on one of them
-- follows to the named lot; credit_given_back_follows).
create function pg_temp.t463_behind(p_inv uuid) returns setof uuid language sql as $f$
  with recursive c(id, n) as (
    select lot_id, 0 from invoice_benefit_values where invoice_id = p_inv and lot_id is not null
    union select p.id, c.n + 1 from c join customer_credit_lots l on l.id = c.id
            join customer_credit_lots p on p.id = l.reassigned_from_lot_id
             and (p.source_type, p.source_record_id) is not distinct from (l.source_type, l.source_record_id)
           where c.n < 12)
  select distinct id from c $f$;
-- How many lots back a lot's chain goes (reassigned_from_lot_id).
create function pg_temp.t463_depth(p_lot uuid) returns int language sql as $f$
  with recursive c(id, n) as (select p_lot, 0 union all
    select l.reassigned_from_lot_id, c.n + 1 from c join customer_credit_lots l on l.id = c.id
     where l.reassigned_from_lot_id is not null and c.n < 40)
  select max(n) from c $f$;
-- A lot's balance by its ledger rows: credit added (grants, increases,
-- credit returned: the 'reverse' rows that put credit back, as the
-- statement reads them, and 'rental_late_fee'), less credit taken (uses,
-- decreases, real reversals).
create function pg_temp.t463_ledger_balance(p_lot uuid) returns numeric language sql as $f$
  select coalesce(sum(case when e.entry_type in ('grant', 'adjust_increase') then e.amount
                           when e.entry_type = 'reverse' and e.source_type in ('invoice_payment_refund', 'payment_correction', 'invoice_reopen',
                                                                               'special_sale', 'rental', 'rental_late_fee') then e.amount
                           else -e.amount end), 0)
    from customer_credit_ledger e where e.lot_id = p_lot $f$;
-- What is wrong with an invoice's credit ('' when nothing), checked in every
-- case (the critic's 6 and the judge's graft 4):
--   * no lot of its family holds credit unless one of its records names it;
--   * each family lot's balance is what its ledger rows say;
--   * no family lot's chain goes back more than 12 lots (the readers' limit);
--   * a moved lot holding credit traces to its origin and can be spent;
--   * a lot its benefit rows name keeps the origin of the lot it replaced;
--   * a named lot holding credit is held by whoever holds the benefits
--     (a Move's lot to someone else by its recipient, following merges;
--     463 where it is in: a Move to the same customer at another store is
--     the invoice's own);
--   * no sale paid from a lot no record names, behind no lot a benefit row
--     names, can still be refunded (its credit would go back there);
--   * no benefit row holds back more than it granted, nor anything once
--     the invoice is settled again with no reopening waiting (the critics'
--     V1 to X2: a stale reserve let a later Refund in full leave credit);
--   * a refunded invoice leaves no credit on its family.
create function pg_temp.t463_invariants(p_inv uuid) returns text language plpgsql as $f$
declare probs text := ''; l record; root record; v uuid; st text := (select status::text from invoices where id = p_inv);
begin
  for l in select cl.* from customer_credit_lots cl where cl.id in (select pg_temp.t463_family(p_inv)) loop
    if l.remaining_amount > 0 and l.id not in (select pg_temp.t463_named(p_inv)) then
      probs := probs || format(' S$%s on a lot no record names (%s);', l.remaining_amount, (select full_name from customers where id = l.customer_id)); end if;
    if l.id not in (select pg_temp.t463_named(p_inv)) and l.id not in (select pg_temp.t463_behind(p_inv))
       and (exists (select 1 from invoice_line_credit_allocations a where a.lot_id = l.id and a.amount > coalesce(a.reversed_amount, 0))
            or exists (select 1 from special_credit_allocations s where s.lot_id = l.id and s.amount > coalesce(s.reversed_amount, 0))) then
      probs := probs || ' a sale paid from a lot no record names can still be refunded (its credit would stay there);'; end if;
    if pg_temp.t463_ledger_balance(l.id) <> l.remaining_amount then
      probs := probs || format(' lot holds %s, its ledger %s;', l.remaining_amount, pg_temp.t463_ledger_balance(l.id)); end if;
    if pg_temp.t463_depth(l.id) > 12 then probs := probs || format(' chain %s lots deep;', pg_temp.t463_depth(l.id)); end if;
    if l.remaining_amount > 0 and l.source_type = 'invoice_benefit_transfer'
       and (invoice_credit_transfer_origin(l.id) is null or credit_lot_policy_for(l.id) = 'needs_review') then
      probs := probs || ' a moved lot lost its origin;'; end if;
  end loop;
  for l in select bv.id as bid, bv.lot_id, cl.customer_id, cl.remaining_amount, cl.created_at, cl.source_type, cl.source_record_id,
                  cl.category, cl.usage_restrictions,
                  case when to_regprocedure('public.invoice_benefit_moved_to_other(uuid)') is null
                       then exists (select 1 from invoice_benefit_transfers t where t.replacement_benefit_id = bv.id)
                       else pg_temp.t463_moved_to_other(bv.id) end as moved_in
             from invoice_benefit_values bv join customer_credit_lots cl on cl.id = bv.lot_id where bv.invoice_id = p_inv loop
    with recursive c(id, n) as (select l.lot_id, 0 union all
                                select x.reassigned_from_lot_id, c.n + 1 from c join customer_credit_lots x on x.id = c.id
                                 where x.reassigned_from_lot_id is not null and c.n < 12)
    select x.* into root from c join customer_credit_lots x on x.id = c.id order by c.n desc limit 1;
    if (l.source_type, l.source_record_id, l.category, l.usage_restrictions)
       is distinct from (root.source_type, root.source_record_id, root.category, root.usage_restrictions) then
      probs := probs || ' a lot lost its origin;'; end if;
    if l.remaining_amount > 0 and to_regprocedure('public.invoice_credit_live_holder(uuid,uuid,timestamp with time zone)') is not null then
      execute 'select public.invoice_credit_live_holder($1, $2, $3)' into v
        using p_inv, l.customer_id, case when l.moved_in then 'infinity'::timestamptz else l.created_at end;
      if v is distinct from l.customer_id then
        probs := probs || format(' S$%s held by %s, not by the benefits'' holder %s;', l.remaining_amount,
          (select full_name from customers where id = l.customer_id), (select full_name from customers where id = v)); end if;
    end if;
  end loop;
  if exists (select 1 from invoice_benefit_values bv where bv.invoice_id = p_inv and bv.lot_id is not null
              and bv.cancelled_unused_value > bv.granted_value) then
    probs := probs || ' a benefit row holds back more than it granted;'; end if;
  if st in ('paid', 'partially_paid', 'unpaid', 'completed_foc')
     and not exists (select 1 from invoice_reopen_benefits q where q.invoice_id = p_inv and q.applied_at is null)
     and exists (select 1 from invoice_benefit_values bv where bv.invoice_id = p_inv and bv.lot_id is not null and bv.cancelled_unused_value > 0) then
    probs := probs || format(' S$%s still held back for a cancellation, settled with no reopening waiting;',
      (select sum(cancelled_unused_value) from invoice_benefit_values where invoice_id = p_inv and lot_id is not null)); end if;
  if st = 'refunded' and (select coalesce(sum(remaining_amount), 0) from customer_credit_lots where id in (select pg_temp.t463_family(p_inv))) > 0 then
    probs := probs || format(' refunded, but S$%s of its credit is still held;',
      (select sum(remaining_amount) from customer_credit_lots where id in (select pg_temp.t463_family(p_inv)))); end if;
  return probs;
end $f$;
-- Credit left on the invoice's family once Cancel has run, the Cancel undone
-- (0 when Cancel takes it all back from whoever holds it); null when the
-- invoice cannot be cancelled now, -1 when Cancel is refused.
create function pg_temp.t463_cancel_left(p_inv uuid) returns numeric language plpgsql as $f$
declare v numeric;
begin
  if (select status::text from invoices where id = p_inv) not in ('paid', 'partially_paid', 'unpaid') then return null; end if;
  begin
    perform cancel_invoice_recorded(p_inv, 'T463 probe', gen_random_uuid());
    perform pg_temp.t463_commit();
    v := (select coalesce(sum(remaining_amount), 0) from customer_credit_lots where id in (select pg_temp.t463_family(p_inv)));
    raise exception using errcode = 'P0463', message = v::text;
  exception when sqlstate 'P0463' then return sqlerrm::numeric;
            when others then return -1;
  end;
end $f$;
create function pg_temp.t463_codes(p_inv uuid, p_action text) returns text language plpgsql as $f$
begin
  return (select coalesce(string_agg(o->>'code', ',' order by o->>'code'), '-')
            from jsonb_array_elements(coalesce(invoice_action_plan(p_inv, p_action, '[]')->'overrides_required', '[]')) o);
exception when others then return 'ERR';
end $f$;
create function pg_temp.t463_due(p_inv uuid, p_action text) returns numeric language plpgsql as $f$
begin
  return (invoice_action_plan(p_inv, p_action, '[]')->>case when p_action = 'cancel' then 'refund_due' else 'refund_amount' end)::numeric;
exception when others then return null;
end $f$;

-- ── The cases ───────────────────────────────────────────────────────────────
-- A case is a list of steps, each one app call (and its commit), on the
-- case's own customers (A the buyer, B and C later customers, K and K2
-- records a merge keeps, F and G friends an Owner moved credit to). A step
-- refused stops the case, the refusal recorded. Steps:
--   sale R kinds [first]  the invoice (cp, cpb, pbv, v; part-paid: first)
--   pay                   Record Payment of what is outstanding
--   back N amt|all [R]    refund by line of line N (R: the benefit R holds)
--   move N R [kind] [store2]  an Owner's Move of line N's credit (or voucher)
--   cancel, reopen, wait  Cancel; Reopen; Cancel + every line paid back + Reopen
--   refundall             the guided Refund in full, recorded
--   change R [keep] [store2]  the customer change ('transfer' unless keep)
--   merge KEEP DUP        a customer merge
--   spend R [n] [svc5]    a session invoice (n lines) for R paid from credit
--   unspend Sn            that session cancelled and its refund recorded
--   fix Sn date|amount|cash   the Finance panel's Correct payment on it
--   sale2 R               another S$100 package for R (paid)
--   delete R              delete_customer
--   special R kind amt / unspecial Dn  special-document credit and its refund
--   reverse R             an Owner's reversal of R's largest lot
--   repair                repair_credit_package_progress_lots()
create function pg_temp.t463_role(p_pre text, p_r text) returns uuid language plpgsql as $f$
begin
  return coalesce(pg_temp.t463_id(p_pre || '/' || p_r), pg_temp.t463_cust(p_pre || '/' || p_r));
end $f$;
-- One step of a case (one app call, then what its commit does). Null, or
-- the step and the refusal; a refused step changes nothing.
create function pg_temp.t463_step(p_pre text, p_st text) returns text language plpgsql as $f$
declare w text[] := regexp_split_to_array(btrim(p_st), '\s+'); inv uuid := pg_temp.t463_id(p_pre || '/inv'); x uuid; i int; n int;
begin
  case w[1]
  when 'sale' then
    perform pg_temp.t463_put(p_pre || '/inv', pg_temp.t463_sale(pg_temp.t463_role(p_pre, w[2]), string_to_array(w[3], ','), w[4]::numeric));
  when 'sale2' then
    perform pg_temp.t463_put(p_pre || '/inv2', pg_temp.t463_sale(pg_temp.t463_role(p_pre, w[2]), array['cp']));
  when 'pay' then perform pg_temp.t463_pay(inv);
  when 'back' then
    perform pg_temp.t463_back(inv, w[2]::int, case when w[3] = 'all' then null else w[3]::numeric end,
                              case when w[4] is not null then pg_temp.t463_role(p_pre, w[4]) end);
  when 'move' then
    perform pg_temp.t463_move(inv, w[2]::int, pg_temp.t463_role(p_pre, w[3]),
      case when w[4] in ('bonus', 'voucher') then w[4] else 'paid' end,
      case when 'store2' = any (w) then 'store2' end);
  when 'cancel' then perform cancel_invoice_recorded(inv, 'T463 cancel', gen_random_uuid());
  when 'reopen' then perform reopen_invoice(inv, 'T463 reopen', gen_random_uuid());
  when 'wait' then
    perform cancel_invoice_recorded(inv, 'T463 cancel', gen_random_uuid());
    for i in 1 .. (select count(*)::int from invoice_items where invoice_id = inv) loop
      perform pg_temp.t463_back(inv, i);
    end loop;
    perform reopen_invoice(inv, 'T463 reopen', gen_random_uuid());
  when 'refundall' then perform pg_temp.t463_guided(inv, 'refund_full');
  when 'change' then
    perform pg_temp.t463_change(inv, pg_temp.t463_role(p_pre, w[2]), case when 'keep' = any (w) then 'keep' else 'transfer' end,
                                case when 'store2' = any (w) then 'store2' end);
  when 'merge' then perform pg_temp.t463_merge(pg_temp.t463_role(p_pre, w[2]), pg_temp.t463_role(p_pre, w[3]));
  when 'spend' then
    n := (select count(*) from t463 where k ~ ('^' || p_pre || '/S[0-9]+$')) + 1;
    perform pg_temp.t463_put(p_pre || '/S' || n,
      pg_temp.t463_spend(pg_temp.t463_role(p_pre, w[2]), coalesce(w[3]::int, 1), coalesce(w[4], 'svc')));
  when 'unspend' then perform pg_temp.t463_unspend(pg_temp.t463_id(p_pre || '/' || w[2]));
  when 'fix' then perform pg_temp.t463_fix(pg_temp.t463_id(p_pre || '/' || w[2]), w[3]);
  when 'delete' then
    x := pg_temp.t463_role(p_pre, w[2]);
    perform delete_customer(x, (select full_name from customers where id = x), 'T463 delete');
  when 'special' then
    n := (select count(*) from t463 where k ~ ('^' || p_pre || '/D[0-9]+$')) + 1; x := gen_random_uuid();
    perform pg_temp.t463_put(p_pre || '/D' || n, x);
    perform pg_temp.t463_put(p_pre || '/D' || n || '/kind:' || w[3], null);
    perform pg_temp.t463_special(pg_temp.t463_role(p_pre, w[2]), w[3], x, w[4]::numeric);
  when 'unspecial' then
    perform refund_special_credit((select split_part(k, 'kind:', 2) from t463 where k like p_pre || '/' || w[2] || '/kind:%'),
                                  pg_temp.t463_id(p_pre || '/' || w[2]));
  when 'reverse' then
    x := pg_temp.t463_role(p_pre, w[2]);
    perform reverse_credit_lot((select id from customer_credit_lots where customer_id = x and remaining_amount > 0
                                 order by remaining_amount desc, id limit 1), 'T463 reversal');
  when 'repair' then perform repair_credit_package_progress_lots();
  else raise exception 'T463: unknown step %', p_st;
  end case;
  perform pg_temp.t463_commit();
  return null;
exception when others then
  return btrim(p_st) || ': ' || sqlerrm;
end $f$;
-- What a case ends with: the invoice's status and money, who holds what
-- (credit, '/n' held vouchers), the plans' codes and refund due (Cancel's
-- refund due; Refund in full's amount), the refusal that stopped it, what is
-- wrong with its credit, and the credit Cancel would leave behind.
create function pg_temp.t463_outcome(p_pre text, p_err text) returns jsonb language sql as $f$
  select jsonb_build_object(
    'status', (select status::text from invoices where id = i.id),
    'net', invoice_net_received(i.id),
    'holds', (select jsonb_object_agg(split_part(t.k, '/', 3),
                (select coalesce(sum(l.remaining_amount), 0) from customer_credit_lots l where l.customer_id = t.id)::numeric(12,2)::text
                || coalesce('/' || nullif((select sum(v.quantity) from customer_reward_vouchers v where v.customer_id = t.id and v.status = 'held'), 0)::text, ''))
              from t463 t where t.k like p_pre || '/%' and split_part(t.k, '/', 4) = ''
                and split_part(t.k, '/', 3) !~ '^(inv|inv2|S[0-9]+|D[0-9]+|err)$'),
    'at2', (select jsonb_object_agg(split_part(t.k, '/', 3),
                (select coalesce(sum(l.remaining_amount), 0) from customer_credit_lots l
                  where l.customer_id = t.id and l.store_id = pg_temp.t463_id('store2'))::numeric(12,2)::text
                || coalesce('/' || nullif((select sum(v.quantity) from customer_reward_vouchers v
                                            where v.customer_id = t.id and v.status = 'held' and v.store_id = pg_temp.t463_id('store2')), 0)::text, ''))
              from t463 t where t.k like p_pre || '/%' and split_part(t.k, '/', 4) = ''
                and split_part(t.k, '/', 3) !~ '^(inv|inv2|S[0-9]+|D[0-9]+|err)$'),
    'cancel', pg_temp.t463_codes(i.id, 'cancel'),
    'due', pg_temp.t463_due(i.id, 'cancel'),
    'refund', pg_temp.t463_codes(i.id, 'refund_full'),
    'rdue', pg_temp.t463_due(i.id, 'refund_full'),
    'error', p_err,
    'invariants', pg_temp.t463_invariants(i.id),
    'cancel_left', pg_temp.t463_cancel_left(i.id))
    from (select pg_temp.t463_id(p_pre || '/inv') as id) i $f$;
-- A case's steps p_from to p_to (all by default), stopping at a refusal;
-- with p_to null, its outcome (kept in t463_res under p_phase).
create temp table t463_err(pre text primary key, err text);
create function pg_temp.t463_run(p_phase text, p_case text, p_steps text, p_from int default 1, p_to int default null)
  returns jsonb language plpgsql as $f$
declare v_pre text := p_phase || '/' || p_case; st text[] := string_to_array(p_steps, ';'); i int; v_err text; v_out jsonb;
begin
  v_err := (select e.err from t463_err e where e.pre = v_pre);
  for i in p_from .. least(coalesce(p_to, cardinality(st)), cardinality(st)) loop
    exit when v_err is not null;
    continue when btrim(st[i]) = '';
    v_err := pg_temp.t463_step(v_pre, st[i]);
  end loop;
  insert into t463_err values (v_pre, v_err) on conflict (pre) do update set err = excluded.err;
  if p_to is not null then return null; end if;
  v_out := pg_temp.t463_outcome(v_pre, v_err);
  insert into t463_res values (p_phase, p_case, v_out) on conflict (phase, k) do update set v = excluded.v;
  return v_out;
end $f$;

-- Whether an outcome has what is expected: each key equal ('holds' as a
-- containment of who holds what), a key ending in '~' as a LIKE pattern of
-- that key's text.
create function pg_temp.t463_meets(p_out jsonb, p_exp jsonb) returns boolean language sql as $f$
  select coalesce(bool_and(case
           when e.key like '%~' then coalesce(p_out->>left(e.key, -1), '') like (e.value #>> '{}')
           when e.key in ('holds', 'at2') then coalesce(p_out->e.key, '{}') @> e.value
           when jsonb_typeof(e.value) = 'number' then (p_out->>e.key)::numeric = (e.value #>> '{}')::numeric
           else (p_out->e.key) is not distinct from e.value end), true)
    from jsonb_each(p_exp) e $f$;
-- What differs between an outcome and what is expected (for the FAIL line).
create function pg_temp.t463_diff(p_out jsonb, p_exp jsonb) returns text language sql as $f$
  select string_agg(e.key || ': wanted ' || e.value::text || ', got ' || coalesce(p_out->left(e.key, case when e.key like '%~' then -1 else 1000 end), 'null')::text, '; ')
    from jsonb_each(p_exp) e where not pg_temp.t463_meets(p_out, jsonb_build_object(e.key, e.value)) $f$;

-- The cases: (k, kind, steps, what 462 gives). kind: 'fixed' (before 462 it
-- ends otherwise: the fault is reproduced first), 'control' (the same with
-- and without 462), 'new' (only after 462). The expected outcome lists who
-- holds what (credit, '/n' held vouchers), the cancel plan's codes and
-- refund due, and so on; every case also checks the invariants and that
-- Cancel takes everything back from whoever holds it.

-- 463 goes in after 462: where 462 is not in yet (a copy of production at
-- 464), it is installed first (it checks itself).
select not pg_temp.t463_462_in() as t463_need462 \gset
\if :t463_need462
\ir ../../../supabase/462_moved_and_merged_credit_follows_its_records.sql
\endif
select set_config('t463.need462', :'t463_need462', false);

-- The cases: (k, kind, steps, what 463 gives). kind: 'fixed' (before 463 it
-- ends otherwise: the old outcome is reproduced first), 'control' (the same
-- with and without 463). The expected outcome lists who holds what (credit,
-- '/n' held vouchers; 'at2' what of it is at the second store), the cancel
-- plan's codes and refund due, and so on; every case also checks the
-- invariants and that Cancel takes everything back from whoever holds it.
create temp table t463_cases(k text primary key, kind text not null, steps text not null, expect jsonb not null, ord serial);
insert into t463_cases(k, kind, steps, expect) values
-- Decision 2, credit: a Move to the same customer at another store (a store
-- correction) is taken along by a later customer change with 'transfer'.
('T1', 'fixed', 'sale A cp; move 1 A store2; change B',
  '{"holds":{"A":"0.00","B":"100.00"},"at2":{"B":"100.00"},"cancel":"-","due":100,"refund":"-","rdue":100}'),
('T1r', 'fixed', 'sale A cp; back 1 40; move 1 A store2; change B; cancel; reopen; pay',
  '{"holds":{"A":"0.00","B":"100.00"},"at2":{"B":"60.00"},"cancel":"-","due":100}'),
('T1w', 'fixed', 'sale A cp; back 1 40; move 1 A store2; cancel; reopen; change B; pay',
  '{"holds":{"A":"0.00","B":"100.00"},"at2":{"B":"60.00"},"cancel":"-","due":100}'),
('T1c', 'fixed', 'sale A cp; move 1 A store2; change B; change C',
  '{"holds":{"A":"0.00","B":"0.00","C":"100.00"},"at2":{"C":"100.00"},"cancel":"-","due":100}'),
('T1m', 'fixed', 'sale A cp; move 1 A store2; merge K A; change B',
  '{"holds":{"A":"0.00","B":"100.00","K":"0.00"},"at2":{"B":"100.00"},"cancel":"-","due":100}'),
('T1x', 'fixed', 'sale A cpb; move 1 A store2; move 1 A bonus store2; change B',
  '{"holds":{"A":"0.00","B":"110.00"},"at2":{"B":"110.00"},"cancel":"-","due":100}'),
('T1h', 'fixed', 'sale A cp; move 1 A store2; change B; back 1 30 B',
  '{"holds":{"A":"0.00","B":"70.00"},"at2":{"B":"70.00"},"net":70,"cancel":"-","due":70}'),
-- ... a session paid from the package before the Move, refunded (or its
-- payment corrected to cash) before the change: nothing is spent, so all of
-- it goes to the new customer, the S$80 at the second store.
('T1p', 'fixed', 'sale A cp; spend A; move 1 A store2; unspend S1; change B',
  '{"holds":{"A":"0.00","B":"100.00"},"at2":{"B":"80.00"},"cancel":"-","due":100}'),
('T1d', 'fixed', 'sale A cp; spend A; move 1 A store2; fix S1 cash; change B',
  '{"holds":{"A":"0.00","B":"100.00"},"at2":{"B":"80.00"},"cancel":"-","due":100}'),
-- ... credit spent blocks the change, as for the invoice's own credit
-- (461's rule): spent from the moved lot (T1s), or from the package before
-- the Move (P1: the Move gave its row only the S$80 left; the critics of 24
-- Oct 2026: before, P1's change went through and split the package; without
-- the Move it is refused, L5; refunded first, it goes through, T1p).
('T1s', 'fixed', 'sale A cp; move 1 A store2; spend A; change B',
  '{"holds":{"A":"80.00"},"at2":{"A":"80.00"},"cancel":"credit_used","due":80,"error~":"change B: These benefits have already been used and cannot move with the invoice: Paid credit 80.00 (Partly spent).%"}'),
('P1', 'fixed', 'sale A cp; spend A; move 1 A store2; change B',
  '{"holds":{"A":"80.00"},"at2":{"A":"80.00"},"cancel":"credit_used","due":80,"error~":"change B: These benefits have already been used and cannot move with the invoice: Paid credit 80.00 (Partly spent).%"}'),
-- ... cancelled or refunded in full after a change, reopened (and paid)
-- after it: the new customer gets it all back (C2, C2r; the critics of 24
-- Oct 2026: begun before 463 and reopened after it, M).
('C2', 'fixed', 'sale A cp; move 1 A store2; change B; cancel; reopen',
  '{"holds":{"A":"0.00","B":"100.00"},"at2":{"B":"100.00"},"cancel":"-","due":100}'),
('C2r', 'fixed', 'sale A cp; move 1 A store2; change B; refundall; reopen; pay',
  '{"holds":{"A":"0.00","B":"100.00"},"at2":{"B":"100.00"},"cancel":"-","due":100}'),
('C2w', 'fixed', 'sale A cp; move 1 A store2; change B; wait; pay',
  '{"holds":{"A":"0.00","B":"100.00"},"at2":{"B":"100.00"},"cancel":"-","due":100}'),
-- Decision 2, vouchers: they follow at the store they were moved to.
('T2', 'fixed', 'sale A v; move 1 A voucher store2; change B',
  '{"holds":{"A":"0.00","B":"0.00/2"},"at2":{"B":"0.00/2"},"cancel":"-","due":60}'),
('T2c', 'fixed', 'sale A v; move 1 A voucher store2; change B; cancel; reopen',
  '{"holds":{"A":"0.00","B":"0.00/2"},"at2":{"B":"0.00/2"}}'),
('T2w', 'fixed', 'sale A v; move 1 A voucher store2; wait; change B; pay',
  '{"holds":{"A":"0.00","B":"0.00/2"},"at2":{"B":"0.00/2"}}'),
('T2s', 'fixed', 'sale A v; move 1 A voucher store2; change B store2',
  '{"holds":{"A":"0.00","B":"0.00/2"},"at2":{"B":"0.00/2"}}'),
('T2m', 'fixed', 'sale A v; move 1 A voucher store2; wait; pay; change B',
  '{"holds":{"A":"0.00","B":"0.00/2"},"at2":{"B":"0.00/2"}}'),
-- ... given again by a reopening after the change, then cancelled and
-- reopened again: the new customer's still (the critics of 24 Oct 2026:
-- before 463 the payment gave them again to A, dated after the change, so
-- every later reopening gave them back to A; 463 reads the holder from the
-- first voucher of the chain).
('T2wc', 'fixed', 'sale A v; move 1 A voucher store2; wait; change B; pay; cancel; reopen',
  '{"holds":{"A":"0.00","B":"0.00/2"},"at2":{"B":"0.00/2"}}'),
-- Decision 3: a Premium Bundle's vouchers follow a change, as its credit does.
('V3', 'fixed', 'sale A pbv; change B',
  '{"holds":{"A":"0.00","B":"140.00/2"},"cancel":"-","due":140}'),
('V3c', 'fixed', 'sale A pbv; change B; change C',
  '{"holds":{"A":"0.00","B":"0.00","C":"140.00/2"},"cancel":"-","due":140}'),
('V3s', 'fixed', 'sale A pbv; change B store2',
  '{"holds":{"A":"0.00","B":"140.00/2"},"at2":{"B":"0.00"}}'),
('V4', 'fixed', 'sale A pbv; wait; change B; pay',
  '{"holds":{"A":"0.00","B":"140.00/2"},"cancel":"-","due":140}'),
('V7', 'fixed', 'sale A pbv; back 1 all; cancel; reopen; change B; pay',
  '{"holds":{"A":"0.00","B":"140.00/2"}}'),
('V9', 'fixed', 'sale A pbv; move 1 A voucher store2; change B',
  '{"holds":{"A":"0.00","B":"140.00/2"},"at2":{"B":"0.00/2"}}'),
('V4m', 'fixed', 'sale A pbv; wait; change B; pay; merge K B',
  '{"holds":{"A":"0.00","B":"0.00","K":"140.00/2"}}'),
-- ... cancelled (or refunded in full) after the change and reopened (paid):
-- the new customer gets the vouchers again with the credit; given again
-- after the change and reopened again (V4c), or changed again (V3rC): the
-- holder's (the critics of 24 Oct 2026).
('V3r', 'fixed', 'sale A pbv; change B; cancel; reopen',
  '{"holds":{"A":"0.00","B":"140.00/2"},"cancel":"-","due":140}'),
('C4', 'fixed', 'sale A pbv; change B; refundall; reopen; pay',
  '{"holds":{"A":"0.00","B":"140.00/2"},"cancel":"-","due":140}'),
('V4c', 'fixed', 'sale A pbv; wait; change B; pay; cancel; reopen',
  '{"holds":{"A":"0.00","B":"140.00/2"},"cancel":"-","due":140}'),
('V3rC', 'fixed', 'sale A pbv; change B; cancel; reopen; change C',
  '{"holds":{"A":"0.00","B":"0.00","C":"140.00/2"},"cancel":"-","due":140}'),
('V3w', 'fixed', 'sale A pbv; change B; wait; pay',
  '{"holds":{"A":"0.00","B":"140.00/2"},"cancel":"-","due":140}'),
-- Controls: the same with and without 463.
('T1k', 'control', 'sale A cp; move 1 A store2; change B keep',
  '{"holds":{"A":"100.00","B":"0.00"},"at2":{"A":"100.00"},"cancel":"-","due":100}'),
('T1f', 'control', 'sale A cp; move 1 A store2; move 1 F; change B',
  '{"holds":{"A":"0.00","B":"0.00","F":"100.00"},"cancel":"-","due":100}'),
('T1g', 'control', 'sale A cp; move 1 F; move 1 F store2; change B',
  '{"holds":{"A":"0.00","B":"0.00","F":"100.00"},"at2":{"F":"100.00"},"cancel":"-","due":100}'),
('T1n', 'control', 'sale A cp; back 1 40; move 1 F; cancel; reopen; change B; pay',
  '{"holds":{"A":"0.00","B":"40.00","F":"60.00"},"cancel":"-","due":100}'),
('T2k', 'control', 'sale A v; move 1 A voucher store2; change B keep',
  '{"holds":{"A":"0.00/2","B":"0.00"},"at2":{"A":"0.00/2"}}'),
('T2f', 'control', 'sale A v; move 1 F voucher; move 1 F voucher store2; change B',
  '{"holds":{"A":"0.00","B":"0.00","F":"0.00/2"},"at2":{"F":"0.00/2"}}'),
('V1w', 'control', 'sale A v; move 1 F voucher; change B',
  '{"holds":{"A":"0.00","B":"0.00","F":"0.00/2"}}'),
('V3k', 'control', 'sale A pbv; change B keep',
  '{"holds":{"A":"140.00/2","B":"0.00"}}'),
('V3x', 'control', 'sale A pbv; change B; cancel',
  '{"holds":{"A":"0.00","B":"0.00"},"status":"cancelled"}'),
-- (cancelled or refunded in full after the change, not reopened, or the
-- reopening waiting: nobody holds anything, with and without 463; the
-- header's query lists what the next reopening, or the payment, gives
-- otherwise: 6, 7 and 8)
('V3rx', 'control', 'sale A pbv; change B; refundall',
  '{"holds":{"A":"0.00","B":"0.00"},"status":"refunded"}'),
('C2x', 'control', 'sale A cp; move 1 A store2; change B; cancel',
  '{"holds":{"A":"0.00","B":"0.00"},"status":"cancelled"}'),
('C2rx', 'control', 'sale A cp; move 1 A store2; change B; refundall',
  '{"holds":{"A":"0.00","B":"0.00"},"status":"refunded"}'),
('T2x', 'control', 'sale A v; move 1 A voucher store2; change B; cancel',
  '{"holds":{"A":"0.00","B":"0.00"},"status":"cancelled"}'),
('C2wx', 'control', 'sale A cp; move 1 A store2; change B; wait',
  '{"holds":{"A":"0.00","B":"0.00"}}'),
('V3wx', 'control', 'sale A pbv; change B; wait',
  '{"holds":{"A":"0.00","B":"0.00"}}'),
-- (partly spent, the customer changed with 'keep': nothing moves, with and
-- without 463)
('T1sk', 'control', 'sale A cp; move 1 A store2; spend A; change B keep',
  '{"holds":{"A":"80.00","B":"0.00"},"at2":{"A":"80.00"},"cancel":"credit_used","due":80}'),
('P1k', 'control', 'sale A cp; spend A; move 1 A store2; change B keep',
  '{"holds":{"A":"80.00","B":"0.00"},"at2":{"A":"80.00"},"cancel":"credit_used","due":80}'),
('V5', 'control', 'sale A pbv; move 1 F voucher; change B',
  '{"holds":{"A":"0.00","B":"140.00","F":"0.00/2"}}'),
('V6', 'control', 'sale A pbv; merge K A',
  '{"holds":{"A":"0.00","K":"140.00/2"}}'),
('X3', 'control', 'sale A cpb,v; wait; change B; pay',
  '{"holds":{"A":"0.00","B":"110.00/2"}}'),
('K1', 'control', 'sale A cpb,v; wait; change B keep; pay',
  '{"holds":{"A":"110.00/2","B":"0.00"}}'),
('F2', 'control', 'sale A cp; move 1 F; change B',
  '{"holds":{"A":"0.00","B":"0.00","F":"100.00"},"cancel":"-","due":100}'),
('L5', 'control', 'sale A cp; spend A; change B',
  '{"holds":{"A":"80.00"},"error~":"change B: These benefits have already been used and cannot move with the invoice: Paid credit 80.00 (Partly spent).%"}'),
('K8', 'control', 'sale A cp; back 1 40; move 1 F; cancel; reopen; pay',
  '{"holds":{"A":"40.00","F":"60.00"},"cancel":"-","due":100}'),
('S4', 'control', 'sale A cp; spend A; move 1 F; change B; unspend S1',
  '{"holds":{"A":"0.00","B":"20.00","F":"80.00"},"cancel":"-","due":100}');

-- The read-only query in 463's header (the same text): what 463 would
-- refuse to install over, and what it reads differently.
create function pg_temp.t463_header_query() returns table(reason text, invoice_no text, n bigint) language sql as $hq$
with recursive
mv(benefit_id, at_id, other, n) as (
  select t.replacement_benefit_id, t.source_benefit_id,
         (t.before_snapshot->>'customer_id') is distinct from coalesce(t.after_snapshot->>'customer_id', t.customer_id::text), 0
    from public.invoice_benefit_transfers t where t.replacement_benefit_id is not null
  union all
  select mv.benefit_id, t.source_benefit_id,
         (t.before_snapshot->>'customer_id') is distinct from coalesce(t.after_snapshot->>'customer_id', t.customer_id::text), mv.n + 1
    from mv join public.invoice_benefit_transfers t on t.replacement_benefit_id = mv.at_id
   where not mv.other and mv.n < 64),
-- benefit rows an Owner moved to the same customer at another store (463's
-- invoice_benefit_moved_to_other false for a row a Move made)
store_moved as (
  select b.* from public.invoice_benefit_values b
   where b.id in (select mv.benefit_id from mv group by mv.benefit_id having not bool_or(mv.other))),
-- their credit, with 463's test for a customer change (invoice_transferable_
-- benefits: it moves when untouched, or nothing on it spent and nothing
-- holds a claim on it, 461; and nothing spent on the rows it was moved from
-- before the Move, invoice_benefit_moved_from_spent)
sm_credit as (
  select b.invoice_id, b.id, l.id as lot_id, l.customer_id, l.created_at, l.remaining_amount, l.status,
         (l.remaining_amount = l.original_amount and l.reassigned_from_lot_id is null
          or l.remaining_amount + b.cancelled_unused_value + public.invoice_benefit_unused_elsewhere(b.id) >= b.granted_value
             and b.cancelled_unused_value = 0
             and not exists (select 1 from public.invoice_reopen_benefits q where q.invoice_id = b.invoice_id and q.applied_at is null)
             and not exists (select 1 from public.invoices iv where iv.id = b.invoice_id and iv.status in ('cancelled', 'refunded')))
         and not exists (
           with recursive m(benefit_id, n) as (
             select t.source_benefit_id, 0 from public.invoice_benefit_transfers t where t.replacement_benefit_id = b.id
             union all
             select t.source_benefit_id, m.n + 1
               from m join public.invoice_benefit_transfers t on t.replacement_benefit_id = m.benefit_id where m.n < 64)
           select 1 from m
             join public.invoice_benefit_values sb on sb.id = m.benefit_id and sb.lot_id is not null
             left join public.customer_credit_lots sl on sl.id = sb.lot_id
            where coalesce(sl.remaining_amount, 0) + sb.cancelled_unused_value
                  + public.invoice_benefit_unused_elsewhere(sb.id) < sb.granted_value) as moves
    from store_moved b join public.customer_credit_lots l on l.id = b.lot_id),
-- the invoice's own vouchers by 463's rule (invoice_own_voucher_ids): its
-- voucher and promotion lines', a Premium Bundle's, one an Owner moved from
-- one of them to the same customer at another store, and those given again
-- in place of any of them; with when the first of each chain was given (463
-- gives one again to whoever holds the benefits since then) and whether it
-- was the invoice's own before 463 (460's: a line's, and those given again
-- in its place)
own_v(invoice_id, id, kind, root_at, own_before, n) as (
  select it.invoice_id, v.id, 'line', v.issued_at, true, 0
    from public.customer_reward_vouchers v join public.invoice_items it on it.id = v.source_id
   where v.source_type in ('invoice_voucher_sale', 'invoice_promotion_voucher')
  union all
  select s.invoice_id, v.id, 'bundle', v.issued_at, false, 0
    from public.premium_bundle_sales s
    join public.customer_reward_vouchers v on v.source_type = 'premium_bundle' and v.source_id = s.id
   where s.invoice_id is not null
  union all
  select o.invoice_id, x.id, case when x.moved then 'moved' else o.kind end, o.root_at, o.own_before and not x.moved, o.n + 1
    from own_v o
    join public.invoice_benefit_values b on b.reward_voucher_id = o.id and b.invoice_id = o.invoice_id
    cross join lateral (
      select q.replacement_voucher_id as id, false as moved
        from public.invoice_reopen_vouchers q
       where q.benefit_id = b.id and q.invoice_id = o.invoice_id and q.replacement_voucher_id is not null
      union all
      select rb.reward_voucher_id, true
        from public.invoice_benefit_transfers t
        join store_moved rb on rb.id = t.replacement_benefit_id
       where t.source_benefit_id = b.id and t.invoice_id = o.invoice_id and rb.reward_voucher_id is not null) x
   where o.n < 64),
-- who a reopening gives each one again to: from 463 (apply_reopened_invoice_
-- vouchers), and before it
own_vh as (
  select o.invoice_id, o.kind, v.id, v.customer_id, v.status, v.redeemed_at,
         public.invoice_benefits_holder(o.invoice_id, v.customer_id, o.root_at) as holder_after,
         case when o.own_before then public.invoice_benefits_holder(o.invoice_id, v.customer_id, v.issued_at)
              else v.customer_id end as holder_before
    from own_v o join public.customer_reward_vouchers v on v.id = o.id),
found(reason, invoice_id, n) as (
  -- 463 refuses to install (it needs a decision first; a data fix):
  select '1 refuses: credit an Owner moved to the same customer at another store, held by someone other than whoever holds the benefits now (a customer change with "transfer" left it)', c.invoice_id, count(*)
    from sm_credit c
   where c.remaining_amount > 0 and c.status = 'active'
     and c.customer_id is distinct from public.invoice_credit_live_holder(c.invoice_id, c.customer_id, c.created_at)
   group by c.invoice_id
  union all
  -- 463 changes the answer (no refusal):
  select '2 changes: credit an Owner moved to the same customer at another store, unspent (a later change with "transfer" takes it along)', c.invoice_id, count(*)
    from sm_credit c
   where c.remaining_amount > 0 and c.status = 'active' and c.moves
   group by c.invoice_id
  union all
  select '3 changes: credit an Owner moved to the same customer at another store, partly spent (on it, or on the row it was moved from before the Move): a change with "transfer" is now refused as "Partly spent" until it is resolved', c.invoice_id, count(*)
    from sm_credit c
   where c.remaining_amount > 0 and c.status = 'active' and not c.moves
   group by c.invoice_id
  union all
  select '4 changes: vouchers an Owner moved to the same customer at another store (or given again in their place), unused (a later change with "transfer" takes them along, at their store)', v.invoice_id, count(*)
    from own_vh v
   where v.kind = 'moved' and v.status = 'held' and v.redeemed_at is null
   group by v.invoice_id
  union all
  select '5 changes: the invoice''s own vouchers (a voucher line''s, a Premium Bundle''s, a store-moved one, or given again in their place), unused, held by someone other than whoever holds the benefits now (a change with "transfer" before 463 left them, or a reopening before 463 gave them again to the old customer): a Cancel and Reopen now gives them again to the holder, and a later change takes them along', v.invoice_id, count(*)
    from own_vh v
   where v.status = 'held' and v.redeemed_at is null and v.holder_after is distinct from v.holder_before
   group by v.invoice_id
  union all
  select '6 changes: a reopening waiting to be settled whose payment gives a Premium Bundle''s or a store-moved voucher, or store-moved credit, to someone else than before (the holder of the benefits after a change with "transfer")', x.invoice_id, count(*)
    from (select q.invoice_id from public.invoice_reopen_vouchers q
            join public.invoice_benefit_values b on b.id = q.benefit_id
            join own_vh v on v.id = b.reward_voucher_id and v.invoice_id = q.invoice_id
           where q.applied_at is null and v.holder_after is distinct from v.holder_before
          union all
          select q.invoice_id from public.invoice_reopen_benefits q
            join public.customer_credit_ledger e on e.id = q.source_ledger_id
            join sm_credit c on c.invoice_id = q.invoice_id and e.lot_id = any (public.credit_lot_ancestry(c.lot_id))
           where q.applied_at is null
             and public.invoice_credit_live_holder(q.invoice_id, c.customer_id, c.created_at)
                 is distinct from public.invoice_credit_live_holder(q.invoice_id, c.customer_id, 'infinity')) x
   group by x.invoice_id
  union all
  select '7 changes: cancelled or refunded (or a line refunded), not reopened yet: credit an Owner moved to the same customer at another store that the next reopening gives back to someone else than before (the holder of the benefits after a change with "transfer")', c.invoice_id, count(*)
    from sm_credit c
   where exists (select 1 from public.customer_credit_ledger e
                  where e.lot_id = any (public.credit_lot_ancestry(c.lot_id))
                    and (e.source_type = 'invoice_cancel_benefit' and e.source_record_id = c.invoice_id
                         or e.source_type = 'invoice_benefit_refund'
                            and exists (select 1 from public.invoice_refunds r where r.invoice_id = c.invoice_id and r.request_id = e.source_record_id))
                    and not exists (select 1 from public.invoice_reopen_benefits q where q.source_ledger_id = e.id))
     and public.invoice_credit_live_holder(c.invoice_id, c.customer_id, c.created_at)
         is distinct from public.invoice_credit_live_holder(c.invoice_id, c.customer_id, 'infinity')
   group by c.invoice_id
  union all
  select '8 changes: cancelled or refunded (or a line refunded), not reopened yet: the invoice''s own vouchers (a Premium Bundle''s, a store-moved one, or given again in their place) that the next reopening gives again to someone else than before (the holder of the benefits after a change with "transfer")', v.invoice_id, count(*)
    from own_vh v
    join public.invoice_benefit_values b on b.reward_voucher_id = v.id and b.invoice_id = v.invoice_id
    cross join lateral public.invoice_voucher_reopen_candidates(v.invoice_id) k
   where k.benefit_id = b.id
     and k.quantity > coalesce((select sum(q.quantity) from public.invoice_reopen_vouchers q
                                 where q.benefit_id = b.id and q.applied_at is null), 0)
     and v.holder_after is distinct from v.holder_before
   group by v.invoice_id
  union all
  select '9 changes: credit an Owner moved to the same customer at another store, held by someone other than whoever holds the benefits now, with sales paid from it that can still be refunded (their credit then goes to the holder)', c.invoice_id, count(*)
    from sm_credit c
   where c.customer_id is distinct from public.invoice_credit_live_holder(c.invoice_id, c.customer_id, c.created_at)
     and (exists (select 1 from public.invoice_line_credit_allocations a where a.lot_id = c.lot_id and a.amount > coalesce(a.reversed_amount, 0))
          or exists (select 1 from public.special_credit_allocations s where s.lot_id = c.lot_id and s.amount > coalesce(s.reversed_amount, 0)))
   group by c.invoice_id
  union all
  select '10 changes: a reopening waiting to be settled (the summary of a customer change now lists what its payment gives the new customer)', x.invoice_id, count(*)
    from (select invoice_id from public.invoice_reopen_benefits where applied_at is null
          union all select invoice_id from public.invoice_reopen_vouchers where applied_at is null) x
   group by x.invoice_id
  union all
  select '11 changes: invoices with a Premium Bundle''s unused vouchers (a later change with "transfer" moves them too; a count)', null::uuid, count(distinct v.invoice_id)
    from own_vh v join public.invoices iv on iv.id = v.invoice_id
   where v.kind = 'bundle' and v.status = 'held' and v.redeemed_at is null and iv.deleted_at is null
  union all
  select '12 changes: customer records a merge retired or Delete customer removed (a new invoice for one is refused; a count)', null::uuid, count(*)
    from public.customers c where c.deleted_at is not null)
select f.reason, i.invoice_no, f.n
  from found f left join public.invoices i on i.id = f.invoice_id
 where f.n > 0
 order by split_part(f.reason, ' ', 1)::int, i.invoice_no
$hq$;

-- ===== S. Where it starts =====
create temp table t463_fp(k text primary key, v text);
create function pg_temp.t463_grants(p_without text[] default '{}') returns text language sql as $f$
  select md5(string_agg(p.oid::regprocedure::text || '=' || coalesce(p.proacl::text, ''), '|' order by p.oid::regprocedure::text))
    from pg_proc p where p.pronamespace = 'public'::regnamespace and not (p.proname = any (p_without)) $f$;
create function pg_temp.t463_grant_set(p_sig text) returns text[] language sql as $f$
  select array_agg(x::text order by x::text) from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || p_sig) $f$;
-- The eight functions 463 changes: BEFORE (production at 464 with 462 in,
-- 24 Oct 2026) and AFTER; the two it adds.
create temp table t463_md5(sig text primary key, before text, after text, after470 text);
insert into t463_md5 values
  ('invoice_own_voucher_ids(uuid)', '9340840f1ce4e031ec3613198688ba2e', 'ee0202627b9500dcbad103d3ade2401f', null),
  ('move_invoice_benefits_to_customer(uuid,uuid,uuid,text)', '130c25c6ce3d91b7b421e6f4c3d02353', 'c01606c84ee13ddcd88c15521d6d9aed', null),
  ('invoice_transferable_benefits(uuid)', 'd0d19b7c765337c3cd68096fdc6de7dd', '68736a39ed765ee787242bc62bbaeebb', null),
  ('apply_reopened_invoice_benefits()', '4efef2f1e97bed6a3f0eed0df4e2df51', '36eaa7224e514d3e7e42e3eeb51acfb5', null),
  ('credit_given_back_follows(uuid)', '9d75978de5b247a8de1aaee4e894a698', '844b73106bbf362768ed4a899ceb00d5', 'b7720a148f5371bd2bd844d3076ea3b2'),
  ('preview_invoice_correction(uuid,jsonb)', '3047239c7418179e84927f6f00e7f2eb', 'f26752231c100461e11caddc03c98a33', null),
  ('create_invoice_with_details(uuid,uuid,jsonb,jsonb)', '770ee0129b0e9fe909259ad7ea95b8d0', '0ac29c7aa909dd756ec572645ca86448', null),
  ('apply_reopened_invoice_vouchers()', '28d3b7a69b91ddebcdb200559d96a0ef', '6684840544d1ad8a28e2415934300054', null),
  ('invoice_benefit_moved_to_other(uuid)', null, '7016bed898e1bbe9d0ac4a05037d07c2', null),
  ('invoice_benefit_moved_from_spent(uuid)', null, '901fde963b051cfd93fcd9f7dab7149e', null);
-- (470, where it is in, changes the forwarder: after470; 471, where it is
-- in, changes it again: its AFTER below.)
create function pg_temp.t463_at(p_col text) returns boolean language sql as $f$
  select bool_and(case when p_col = 'before' then (m.before is null and to_regprocedure('public.' || m.sig) is null)
                                                  or md5(pg_get_functiondef(to_regprocedure('public.' || m.sig))) = m.before
                       else to_regprocedure('public.' || m.sig) is not null
                            and md5(pg_get_functiondef(to_regprocedure('public.' || m.sig)))
                                = case when pg_temp.t463_471_in() and m.sig = 'credit_given_back_follows(uuid)' then '1417d83e7d7be49209f5cd1369d07ec7'
                                       when pg_temp.t463_470_in() or pg_temp.t463_471_in() then coalesce(m.after470, m.after) else m.after end end)
    from t463_md5 m $f$;
insert into t463_fp values ('start', pg_temp.t463_fingerprint()), ('grants', pg_temp.t463_grants());
\if :{?nomig}
do $$ begin
  perform pg_temp.t463_check(pg_temp.t463_462_in() and pg_temp.t463_in() and pg_temp.t463_at('after'), 'S -v nomig=1: 462 and 463 are in, as tested');
end $$;
\else
do $$ begin
  perform pg_temp.t463_check(pg_temp.t463_462_in() and not pg_temp.t463_in() and pg_temp.t463_at('before'),
    'S 462 is in, 463 is not yet and its eight functions are at 462''s, 458''s, 456''s and 460''s AFTERs (this suite installs it; use -v nomig=1 where it is in)');
  raise notice 'S: 462 in (%), 463 not yet: %', case when current_setting('t463.need462')::boolean then 'installed by this suite' else 'already' end,
    pg_temp.t463_fingerprint();
end $$;

-- ===== R. Before 463: each case reproduced (undone afterwards) =====
-- A 'fixed' case does not end as 463 makes it; a control does, exactly.
savepoint t463_r;
do $$
declare c record; o jsonb; res text := '';
begin
  for c in select * from t463_cases order by ord loop
    o := pg_temp.t463_run('before', c.k, c.steps);
    if c.kind = 'fixed' then
      perform pg_temp.t463_check(not (pg_temp.t463_meets(o, c.expect) and coalesce(o->>'invariants', '') = ''),
        'R ' || c.k || ' already ends as 463 makes it, without 463: ' || o::text);
      res := res || format(E'\n  %s: %s%s%s', c.k, (select string_agg(h.key || ' ' || (h.value #>> '{}'), ', ' order by h.key) from jsonb_each(o->'holds') h),
        coalesce('; cancel ' || nullif(o->>'cancel', '-') || ' due ' || (o->>'due'), ''),
        coalesce('; ' || nullif(o->>'invariants', ''), '') || coalesce('; refused: ' || left(o->>'error', 120), ''));
    else
      perform pg_temp.t463_check(pg_temp.t463_meets(o, c.expect) and coalesce(o->>'invariants', '') = ''
          and coalesce((o->>'cancel_left')::numeric, 0) = 0,
        'R control ' || c.k || ' without 463: ' || coalesce(pg_temp.t463_diff(o, c.expect), '') || ' ' || o::text);
    end if;
  end loop;
  raise notice 'PASS R: without 463 every fixed case ends otherwise (the old outcomes reproduced), the controls as expected:%', res;
end $$;

-- Without 463, too: the summary of a change while a reopening waits lists
-- nothing of what its payment gives back (W1), and an invoice is made for a
-- record a merge retired (K6s).
do $$
declare inv uuid; a uuid; m text;
begin
  perform pg_temp.t463_run('before', 'W1', 'sale A cpb,v; move 0 F bonus; wait', 1, 3);
  inv := pg_temp.t463_id('before/W1/inv');
  perform pg_temp.t463_check(not (preview_invoice_correction(inv, jsonb_build_object('customer_id', pg_temp.t463_cust('before/W1/B'),
                                    'benefit_action', 'transfer'))->'effects' @> '[{"area": "benefits"}]'),
    'R W1 the summary already lists benefits without 463');
  perform pg_temp.t463_run('before', 'K6s', 'sale A cp; merge K A', 1, 2);
  a := pg_temp.t463_id('before/K6s/A');
  begin
    perform create_invoice_with_details(pg_temp.t463_id('store'), a,
      jsonb_build_array(jsonb_build_object('kind', 'voucher', 'voucher_id', pg_temp.t463_id('v'), 'quantity', 1)),
      jsonb_build_object('business_date', sg_today()::text));
    m := 'accepted';
  exception when others then m := sqlerrm;
  end;
  perform pg_temp.t463_check(m = 'accepted', 'R K6s an invoice for a retired record without 463: ' || m);
  raise notice 'PASS R (2): without 463 the summary of a change while a reopening waits lists no benefits (W1), and an invoice is made for a record a merge retired (K6s)';
end $$;

-- ===== Q. The header's read-only query, on these states =====
-- (The vouchers each step gave are dated when it ends, as in the app, so a
-- voucher given again after a change is dated after it: t463_commit.)
create temp table t463_q as select * from pg_temp.t463_header_query();
create function pg_temp.t463_q_has(p_reason text, p_case text) returns boolean language sql as $f$
  select exists (select 1 from t463_q q join invoices i on i.invoice_no = q.invoice_no
                  where split_part(q.reason, ' ', 1) = p_reason and i.id = pg_temp.t463_id('before/' || p_case || '/inv')) $f$;
-- The cases a reason lists, by name.
create function pg_temp.t463_q_cases(p_reason text) returns text language sql as $f$
  select coalesce(string_agg(c.k, ',' order by c.k), '')
    from t463_cases c where pg_temp.t463_q_has(p_reason, c.k) $f$;
do $$
declare v_want text; c record; r text; v_exact jsonb;
begin
  -- Exactly these cases, for the reasons that refuse or say what the next
  -- step does differently (1, 3, 5, 7, 8, 9); the others at least these.
  v_exact := jsonb_build_object(
    -- 1 (refuses): credit moved to the same customer at another store, held
    -- by the old customer after a 'transfer' change (the change refused for
    -- P1 and T1s from 463 went through before it)
    '1', 'C2,C2r,C2w,P1,T1,T1c,T1d,T1h,T1m,T1p,T1r,T1s,T1w,T1x',
    -- 3: such credit partly spent (on it, or before the Move): a change now
    -- refused
    '3', 'P1,P1k,T1s,T1sk',
    -- 5: own vouchers held by someone other than whoever holds the benefits
    -- (left by a change, or given again to the old customer after it)
    '5', 'C4,T2,T2c,T2m,T2s,T2w,T2wc,V3,V3c,V3r,V3rC,V3s,V3w,V4,V4c,V4m,V7,V9',
    -- 7 and 8: cancelled or refunded after a change, not reopened yet
    '7', 'C2rx,C2x',
    '8', 'T2x,V3rx,V3x',
    -- 9: sales paid from such credit, still refundable
    '9', 'T1s');
  for r in select jsonb_object_keys(v_exact) loop
    perform pg_temp.t463_check(pg_temp.t463_q_cases(r) = v_exact->>r,
      'Q ' || r || ' lists ' || pg_temp.t463_q_cases(r) || ', not ' || (v_exact->>r));
  end loop;
  foreach v_want in array array['2:T1', '2:T1r', '2:T1w', '2:T1c', '2:T1m', '2:T1x', '2:T1h', '2:T1p', '2:T1d', '2:T1k', '2:C2', '2:C2r', '2:C2w',
                                '4:T2', '4:T2k', '4:T2s', '4:T2m', '4:T2c', '4:T2w', '4:T2wc', '4:V9',
                                '6:C2wx', '6:V3wx', '10:C2wx', '10:V3wx'] loop
    perform pg_temp.t463_check(pg_temp.t463_q_has(split_part(v_want, ':', 1), split_part(v_want, ':', 2)),
      'Q ' || v_want || ' is not listed');
  end loop;
  perform pg_temp.t463_check(pg_temp.t463_q_cases('6') = 'C2wx,V3wx', 'Q 6 lists ' || pg_temp.t463_q_cases('6'));
  perform pg_temp.t463_check(exists (select 1 from t463_q where split_part(reason, ' ', 1) = '11' and n > 0)
      and exists (select 1 from t463_q where split_part(reason, ' ', 1) = '12' and n > 0), 'Q 11 and 12 count nothing');
  -- The controls 463 does not change are not listed under 1 to 9 (T1k, T2k,
  -- T1sk, P1k and the cancelled, refunded and waiting ones only where said
  -- above).
  for c in select * from t463_cases where k in ('T1f', 'T1g', 'T1n', 'V1w', 'V3k', 'V5', 'V6', 'X3', 'K1', 'F2', 'L5', 'K8', 'S4', 'T2f') loop
    perform pg_temp.t463_check(not exists (select 1 from t463_q q join invoices i on i.invoice_no = q.invoice_no
                                            where i.id = pg_temp.t463_id('before/' || c.k || '/inv')
                                              and split_part(q.reason, ' ', 1)::int between 1 and 9),
      'Q control ' || c.k || ' is listed');
  end loop;
  perform pg_temp.t463_check(not exists (select 1 from t463_q q join invoices i on i.invoice_no = q.invoice_no
                                          join t463_cases tc on i.id = pg_temp.t463_id('before/' || tc.k || '/inv')
                                         where split_part(q.reason, ' ', 1)::int between 1 and 9
                                           and (tc.k = 'T1k' and split_part(q.reason, ' ', 1) <> '2'
                                                or tc.k = 'T2k' and split_part(q.reason, ' ', 1) <> '4'
                                                or tc.k in ('T1sk', 'P1k') and split_part(q.reason, ' ', 1) <> '3'
                                                or tc.k in ('C2x', 'C2rx') and split_part(q.reason, ' ', 1) <> '7'
                                                or tc.k in ('T2x', 'V3x', 'V3rx') and split_part(q.reason, ' ', 1) <> '8'
                                                or tc.k in ('C2wx', 'V3wx') and split_part(q.reason, ' ', 1) <> '6')),
    'Q a control is listed under another reason: ' ||
      (select string_agg(tc.k || ':' || split_part(q.reason, ' ', 1), ', ') from t463_q q join invoices i on i.invoice_no = q.invoice_no
         join t463_cases tc on i.id = pg_temp.t463_id('before/' || tc.k || '/inv')
        where tc.kind = 'control' and split_part(q.reason, ' ', 1)::int between 1 and 9));
  raise notice 'PASS Q: the header''s read-only query lists % invoices (%), each reason as expected; the controls 463 does not change are not listed under 1 to 9',
    (select count(distinct invoice_no) from t463_q),
    (select string_agg(x.r || ' ' || x.n, ', ' order by x.r::int) from (select split_part(reason, ' ', 1) r, sum(n) n from t463_q group by 1) x);
end $$;

-- ===== 9. The refusals, each changing nothing =====
-- 9a With these states in (credit an Owner moved to the same customer at
-- another store, held by the old customer after a change): refused, naming
-- those invoices.
savepoint t463_9;
\set ON_ERROR_STOP off
\ir ../../../supabase/463_change_takes_store_moves_and_bundle_vouchers.sql
\set ON_ERROR_STOP on
rollback to savepoint t463_9;
select :'LAST_ERROR_MESSAGE' as t463_9a \gset
select set_config('t463.msg', :'t463_9a', false);
do $$
declare m text := current_setting('t463.msg'); v text;
begin
  select string_agg(invoice_no, ', ' order by invoice_no) into v from t463_q where split_part(reason, ' ', 1) = '1';
  perform pg_temp.t463_check(m = format('463: %s invoice(s) have credit an Owner moved to the same customer at another store, held by someone other than whoever holds their benefits now (%s): a customer change with "transfer" left it. Decide where it belongs (a data fix), then apply. Nothing was changed.',
                                        (select count(*) from t463_q where split_part(reason, ' ', 1) = '1'), v)
      and not pg_temp.t463_in() and pg_temp.t463_at('before'),
    '9a refused with: ' || m);
end $$;
-- Keep R's outcomes; undo its records.
select coalesce(jsonb_object_agg(k, v), '{}'::jsonb)::text as t463_rbefore from t463_res where phase = 'before' \gset
rollback to savepoint t463_r;
insert into t463_res select 'before', key, value from jsonb_each(:'t463_rbefore'::jsonb);
do $$ begin
  perform pg_temp.t463_check((select count(*) from t463_res where phase = 'before') = (select count(*) from t463_cases)
      and pg_temp.t463_fingerprint() = (select v from t463_fp where k = 'start'),
    'R undone, its outcomes kept');
end $$;
-- 9b A function it changes not as tested: refused.
savepoint t463_9;
do $$ begin
  execute replace(pg_get_functiondef('public.move_invoice_benefits_to_customer(uuid,uuid,uuid,text)'::regprocedure),
                  'declare v_blocked text;', 'declare /* another version */ v_blocked text;');
end $$;
\set ON_ERROR_STOP off
\ir ../../../supabase/463_change_takes_store_moves_and_bundle_vouchers.sql
\set ON_ERROR_STOP on
rollback to savepoint t463_9;
select :'LAST_ERROR_MESSAGE' as t463_9 \gset
select set_config('t463.msg', :'t463_9', false);
do $$ begin
  perform pg_temp.t463_check(current_setting('t463.msg') like '463: public.move_invoice_benefits_to_customer(uuid,uuid,uuid,text) is not the version this was tested against (md5 %',
    '9b a changed function: ' || current_setting('t463.msg'));
end $$;
-- 9c A function it relies on not as tested (460's holder): refused.
savepoint t463_9;
do $$ begin
  execute replace(pg_get_functiondef('public.invoice_benefits_holder(uuid,uuid,timestamp with time zone)'::regprocedure),
                  '  with recursive k(id, n) as (', '  with recursive /* another version */ k(id, n) as (');
end $$;
\set ON_ERROR_STOP off
\ir ../../../supabase/463_change_takes_store_moves_and_bundle_vouchers.sql
\set ON_ERROR_STOP on
rollback to savepoint t463_9;
select :'LAST_ERROR_MESSAGE' as t463_9 \gset
select set_config('t463.msg', :'t463_9', false);
do $$ begin
  perform pg_temp.t463_check(current_setting('t463.msg') like '463: public.invoice_benefits_holder(uuid,uuid,timestamp with time zone) is missing or not the version this was tested against (md5 %',
    '9c a function it relies on: ' || current_setting('t463.msg'));
end $$;
-- 9d Without 462's trigger (462 not in): refused.
savepoint t463_9;
drop trigger credit_given_back_follows on public.customer_credit_ledger;
\set ON_ERROR_STOP off
\ir ../../../supabase/463_change_takes_store_moves_and_bundle_vouchers.sql
\set ON_ERROR_STOP on
rollback to savepoint t463_9;
select :'LAST_ERROR_MESSAGE' as t463_9 \gset
select set_config('t463.msg', :'t463_9', false);
do $$ begin
  perform pg_temp.t463_check(current_setting('t463.msg') = '463: 462''s trigger credit_given_back_follows is not there as 462 made it; 463 goes in after 462',
    '9d without 462''s trigger: ' || current_setting('t463.msg'));
end $$;
-- 9e A new way of giving a Premium Bundle's vouchers: refused.
savepoint t463_9;
create function public.t463_another_bundle_writer(p_c uuid, p_v uuid) returns void language sql as $f$
  insert into public.customer_reward_vouchers(customer_id, voucher_id, quantity, status, source_type)
  values (p_c, p_v, 1, 'held', 'premium_bundle') $f$;
\set ON_ERROR_STOP off
\ir ../../../supabase/463_change_takes_store_moves_and_bundle_vouchers.sql
\set ON_ERROR_STOP on
rollback to savepoint t463_9;
select :'LAST_ERROR_MESSAGE' as t463_9 \gset
select set_config('t463.msg', :'t463_9', false);
do $$ begin
  perform pg_temp.t463_check(current_setting('t463.msg') like '463: what gives a Premium Bundle''s vouchers is not as read on 24 Oct 2026 (%t463_another_bundle_writer(uuid,uuid)%',
    '9e a new bundle voucher writer: ' || current_setting('t463.msg'));
end $$;
-- 9f Another function taking one of the names (an overload): refused.
savepoint t463_9;
create function public.invoice_own_voucher_ids(p_invoice_id uuid, p_extra boolean) returns table(voucher_id uuid) language sql as $f$
  select null::uuid where false $f$;
\set ON_ERROR_STOP off
\ir ../../../supabase/463_change_takes_store_moves_and_bundle_vouchers.sql
\set ON_ERROR_STOP on
rollback to savepoint t463_9;
select :'LAST_ERROR_MESSAGE' as t463_9 \gset
select set_config('t463.msg', :'t463_9', false);
do $$ begin
  perform pg_temp.t463_check(current_setting('t463.msg') = '463: another function takes the name of one this changes or adds: invoice_own_voucher_ids(uuid,boolean)',
    '9f an overload: ' || current_setting('t463.msg'));
end $$;
-- 9g The same grants listed in another order: not a refusal.
savepoint t463_9;
revoke execute on function public.preview_invoice_correction(uuid,jsonb) from authenticated;
grant execute on function public.preview_invoice_correction(uuid,jsonb) to authenticated;
\ir ../../../supabase/463_change_takes_store_moves_and_bundle_vouchers.sql
do $$ begin
  perform pg_temp.t463_check(pg_temp.t463_in() and pg_temp.t463_at('after'), '9g the same grants in another order stopped it');
end $$;
rollback to savepoint t463_9;
do $$ begin
  perform pg_temp.t463_check(pg_temp.t463_fingerprint() = (select v from t463_fp where k = 'start') and not pg_temp.t463_in()
      and pg_temp.t463_grants() = (select v from t463_fp where k = 'grants'),
    '9 the refusals left a change');
  raise notice 'PASS 9: refused, changing nothing: credit moved to the same customer at another store held by the old customer after a change (the R states the header''s query lists under 1), a function changed or relied on not as tested, 462''s trigger missing, a new way of giving a Premium Bundle''s vouchers, an overload. The same grants in another order do not stop it';
end $$;

-- ===== M. Begun before 463, finished after it (the mid set) =====
create temp table t463_mid(k text primary key, ord serial, split int, steps text, expect jsonb);
insert into t463_mid(k, split, steps, expect) select 'm' || k, s, steps, expect from (values
  -- the Move (and the cancellation) before, the change after
  ('T1', 2), ('T1w', 5), ('T2', 2), ('T2w', 3), ('V4', 2), ('V7', 4), ('T1p', 3), ('P1', 3),
  -- the change before (a control's state), the rest after
  ('T1k', 3), ('V3x', 2),
  -- the change and the cancellation, refund in full or waiting reopening
  -- before, the reopening (and its payment) after (the critics of 24 Oct
  -- 2026: the header's query lists these, 6 to 8)
  ('C2', 4), ('C2r', 4), ('C2w', 4), ('T2c', 4), ('V3r', 3), ('C4', 3), ('V3w', 3),
  -- the vouchers given again to the old customer after the change before,
  -- reopened again (or changed again) after (5)
  ('V4c', 4), ('T2wc', 5), ('V3rC', 4)) x(k, s)
  join t463_cases c using (k);
do $$ declare c record; begin
  for c in select * from t463_mid order by ord loop
    perform pg_temp.t463_run('mid', c.k, c.steps, 1, c.split);
  end loop;
end $$;
\endif

-- ===== 10. Install 463, twice =====
\if :{?nomig}
do $$ begin raise notice 'NOTE 10: -v nomig=1, so 463 is not installed here (R, Q, 9 and M are skipped)'; end $$;
\else
\ir ../../../supabase/463_change_takes_store_moves_and_bundle_vouchers.sql
do $$ begin insert into t463_fp values ('first', pg_temp.t463_fingerprint()); end $$;
\ir ../../../supabase/463_change_takes_store_moves_and_bundle_vouchers.sql
do $$ begin insert into t463_fp values ('second', pg_temp.t463_fingerprint()); end $$;
\endif
do $$
begin
  perform pg_temp.t463_check(pg_temp.t463_in() and pg_temp.t463_at('after'), '10 463 is not installed as tested');
  perform pg_temp.t463_check((select count(*) from pg_proc where pronamespace = 'public'::regnamespace
                               and proname in ('invoice_own_voucher_ids', 'move_invoice_benefits_to_customer', 'invoice_transferable_benefits',
                                               'apply_reopened_invoice_benefits', 'credit_given_back_follows', 'preview_invoice_correction',
                                               'create_invoice_with_details', 'apply_reopened_invoice_vouchers',
                                               'invoice_benefit_moved_to_other', 'invoice_benefit_moved_from_spent')) = 10, '10 an overload exists');
  perform pg_temp.t463_check(
        pg_temp.t463_grant_set('invoice_own_voucher_ids(uuid)') = '{postgres=X/postgres,service_role=X/postgres}'
    and pg_temp.t463_grant_set('move_invoice_benefits_to_customer(uuid,uuid,uuid,text)') = '{postgres=X/postgres,service_role=X/postgres}'
    and pg_temp.t463_grant_set('invoice_transferable_benefits(uuid)') = '{authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres}'
    and pg_temp.t463_grant_set('apply_reopened_invoice_benefits()') = '{postgres=X/postgres,service_role=X/postgres}'
    and pg_temp.t463_grant_set('credit_given_back_follows(uuid)') = '{postgres=X/postgres,service_role=X/postgres}'
    and pg_temp.t463_grant_set('preview_invoice_correction(uuid,jsonb)') = '{authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres}'
    and pg_temp.t463_grant_set('create_invoice_with_details(uuid,uuid,jsonb,jsonb)') = '{authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres}'
    and pg_temp.t463_grant_set('apply_reopened_invoice_vouchers()') = '{postgres=X/postgres,service_role=X/postgres}'
    and pg_temp.t463_grant_set('invoice_benefit_moved_to_other(uuid)') = '{postgres=X/postgres,service_role=X/postgres}'
    and not has_function_privilege('anon', 'public.invoice_benefit_moved_to_other(uuid)', 'execute')
    and not has_function_privilege('authenticated', 'public.invoice_benefit_moved_to_other(uuid)', 'execute')
    and pg_temp.t463_grant_set('invoice_benefit_moved_from_spent(uuid)') = '{postgres=X/postgres,service_role=X/postgres}'
    and not has_function_privilege('anon', 'public.invoice_benefit_moved_from_spent(uuid)', 'execute')
    and not has_function_privilege('authenticated', 'public.invoice_benefit_moved_from_spent(uuid)', 'execute'),
    '10 who may call them is not as intended');
  if exists (select 1 from t463_fp where k = 'first') then
    perform pg_temp.t463_check((select v from t463_fp where k = 'second') = (select v from t463_fp where k = 'first'),
      '10 the second run of 463 changed functions');
    perform pg_temp.t463_check(split_part((select v from t463_fp where k = 'first'), ' ', 2)::int
                               = split_part((select v from t463_fp where k = 'start'), ' ', 2)::int + 2,
      '10 463 did not add exactly two functions');
    perform pg_temp.t463_check(pg_temp.t463_grants(array['invoice_benefit_moved_to_other', 'invoice_benefit_moved_from_spent']) = (select v from t463_fp where k = 'grants'),
      '10 the grants of the functions already there changed');
  end if;
  raise notice 'PASS 10: 463 installed as tested (%); the eight functions at their AFTERs, the two helpers the server''s alone; %',
    pg_temp.t463_fingerprint(),
    coalesce((select 'the second run changed nothing, two functions added, the other grants as before' where exists (select 1 from t463_fp where k = 'first')),
             'it was in before the suite (nomig)');
end $$;

-- ===== A. Each case after 463 =====
do $$
declare c record; o jsonb; b jsonb; res text := '';
begin
  for c in select * from t463_cases order by ord loop
    o := pg_temp.t463_run('after', c.k, c.steps);
    perform pg_temp.t463_check(pg_temp.t463_meets(o, c.expect),
      'A ' || c.k || ': ' || coalesce(pg_temp.t463_diff(o, c.expect), '') || ' ' || o::text);
    perform pg_temp.t463_check(coalesce(o->>'invariants', '') = '', 'A ' || c.k || ' invariants: ' || (o->>'invariants'));
    perform pg_temp.t463_check(coalesce((o->>'cancel_left')::numeric, 0) = 0,
      'A ' || c.k || ': Cancel leaves S$' || (o->>'cancel_left') || ' of the invoice''s credit behind');
    b := (select v from t463_res where phase = 'before' and k = c.k);
    if c.kind = 'control' and b is not null then
      perform pg_temp.t463_check(o = b, 'A control ' || c.k || ' changed with 463: before ' || b::text || ', after ' || o::text);
    end if;
    res := res || format(E'\n  %s %s: %s%s', c.kind, c.k,
      (select string_agg(h.key || ' ' || (h.value #>> '{}'), ', ' order by h.key) from jsonb_each(o->'holds') h),
      coalesce('; cancel ' || (o->>'cancel') || ' due ' || (o->>'due'), '') || coalesce('; refused: ' || left(o->>'error', 100), ''));
  end loop;
  raise notice 'PASS A: after 463 each case ends by the Owner''s answers (decisions 2 and 3), and in every case the invariants hold (462''s, with 463''s holder rule) and Cancel takes all the invoice''s credit back from whoever holds it; the controls are exactly as before 463%:%',
    case when exists (select 1 from t463_res where phase = 'before') then '' else ' (no before figures: -v nomig=1)' end, res;
end $$;

-- ===== M (after). The mid set finished with 463 in =====
\if :{?nomig}
\else
do $$
declare c record; o jsonb; res text := '';
begin
  for c in select * from t463_mid order by ord loop
    o := pg_temp.t463_run('mid', c.k, c.steps, c.split + 1);
    perform pg_temp.t463_check(pg_temp.t463_meets(o, c.expect) and coalesce(o->>'invariants', '') = ''
        and coalesce((o->>'cancel_left')::numeric, 0) = 0,
      'M ' || c.k || ': ' || coalesce(pg_temp.t463_diff(o, c.expect), '') || ' ' || o::text);
    res := res || ' ' || c.k;
  end loop;
  raise notice 'PASS M: begun before 463 and finished after it, each ends as the whole case does after 463:%', res;
end $$;
\endif

-- ===== V. Vouchers: the store and the stock =====
-- A limited voucher (100 at each store): a voucher line sold at the first
-- store and moved by an Owner to the same customer at the second store, then
-- the customer changed: the vouchers stay at the second store and no stock
-- moves (the Move moved it); the voucher line's own vouchers, changed with
-- the store, move to the new store with their stock (417); a Premium
-- Bundle's follow the customer and keep their store (as its credit does):
-- no stock moves.
create function pg_temp.t463_stock(p_store text) returns int language sql as $f$
  select current_qty from voucher_store_stock where voucher_id = pg_temp.t463_id('vl') and store_id = pg_temp.t463_id(p_store) $f$;
do $$
declare s1 int; s2 int; o jsonb;
begin
  perform pg_temp.t463_run('V', 'L1', 'sale A vl; move 1 A voucher store2', 1, 2);
  s1 := pg_temp.t463_stock('store'); s2 := pg_temp.t463_stock('store2');
  o := pg_temp.t463_run('V', 'L1', 'sale A vl; move 1 A voucher store2; change B', 3);
  perform pg_temp.t463_check(o->'holds' @> '{"A":"0.00","B":"0.00/2"}' and o->'at2' @> '{"B":"0.00/2"}' and o->>'error' is null
      and pg_temp.t463_stock('store') = s1 and pg_temp.t463_stock('store2') = s2,
    'V L1 a store-moved limited voucher: ' || o::text || format(' stock %s/%s -> %s/%s', s1, s2, pg_temp.t463_stock('store'), pg_temp.t463_stock('store2')));
  perform pg_temp.t463_run('V', 'L2', 'sale A vl', 1, 1);
  s1 := pg_temp.t463_stock('store'); s2 := pg_temp.t463_stock('store2');
  o := pg_temp.t463_run('V', 'L2', 'sale A vl; change B store2', 2);
  perform pg_temp.t463_check(o->'at2' @> '{"B":"0.00/2"}' and pg_temp.t463_stock('store') = s1 + 2 and pg_temp.t463_stock('store2') = s2 - 2,
    'V L2 the invoice''s own limited vouchers, changed with the store: ' || o::text);
  perform pg_temp.t463_run('V', 'L3', 'sale A pbl', 1, 1);
  s1 := pg_temp.t463_stock('store'); s2 := pg_temp.t463_stock('store2');
  o := pg_temp.t463_run('V', 'L3', 'sale A pbl; change B store2', 2);
  perform pg_temp.t463_check(o->'holds' @> '{"A":"0.00","B":"140.00/2"}' and o->'at2' @> '{"B":"0.00"}'
      and pg_temp.t463_stock('store') = s1 and pg_temp.t463_stock('store2') = s2 and o->>'invariants' = '',
    'V L3 a Premium Bundle''s limited vouchers, changed with the store: ' || o::text
      || format(' stock %s/%s -> %s/%s', s1, s2, pg_temp.t463_stock('store'), pg_temp.t463_stock('store2')));
  -- The change's list and summary show what moves: the store-moved credit
  -- and vouchers, a bundle's vouchers.
  perform pg_temp.t463_run('V', 'S1', 'sale A cp; move 1 A store2', 1, 2);
  perform pg_temp.t463_check(exists (select 1 from invoice_transferable_benefits(pg_temp.t463_id('V/S1/inv')) x
                                      where x.kind = 'credit' and x.movable and x.units = 100 and not x.blocking),
    'V S1 the store-moved credit is not listed as moving');
  perform pg_temp.t463_check(
    preview_invoice_correction(pg_temp.t463_id('V/S1/inv'), jsonb_build_object('customer_id', pg_temp.t463_cust('V/S1/B'), 'benefit_action', 'transfer'))->'effects'
      @> '[{"area": "benefits", "change": "transferring", "items": [{"kind": "credit", "what": "Paid credit 100.00"}]}]',
    'V S1 the summary does not list the store-moved credit');
  -- Moved from a package partly spent before the Move: listed as blocking,
  -- "Partly spent" (461's rule, as without the Move); the session refunded,
  -- it moves (the critics of 24 Oct 2026).
  perform pg_temp.t463_run('V', 'S3', 'sale A cp; spend A; move 1 A store2', 1, 3);
  perform pg_temp.t463_check(exists (select 1 from invoice_transferable_benefits(pg_temp.t463_id('V/S3/inv')) x
                                      where x.kind = 'credit' and x.units = 80 and x.blocking and not x.movable
                                        and x.blocked_reason = 'Partly spent'),
    'V S3 store-moved credit from a partly spent package is not listed as blocking: ' ||
      (select jsonb_agg(to_jsonb(x))::text from invoice_transferable_benefits(pg_temp.t463_id('V/S3/inv')) x));
  perform pg_temp.t463_check(
    preview_invoice_correction(pg_temp.t463_id('V/S3/inv'), jsonb_build_object('customer_id', pg_temp.t463_cust('V/S3/B'), 'benefit_action', 'transfer'))->'needs_review'
      @> '[{"area": "benefits", "items": [{"kind": "credit", "what": "Paid credit 80.00", "why": "Partly spent"}]}]',
    'V S3 the summary does not show the store-moved credit as blocking: ' ||
      (preview_invoice_correction(pg_temp.t463_id('V/S3/inv'), jsonb_build_object('customer_id', pg_temp.t463_id('V/S3/B'), 'benefit_action', 'transfer'))->'needs_review')::text);
  perform pg_temp.t463_run('V', 'S3', 'sale A cp; spend A; move 1 A store2; unspend S1', 4, 4);
  perform pg_temp.t463_check(not exists (select 1 from invoice_transferable_benefits(pg_temp.t463_id('V/S3/inv')) x where x.blocking)
      and exists (select 1 from invoice_transferable_benefits(pg_temp.t463_id('V/S3/inv')) x
                   where x.kind = 'credit' and x.units = 80 and x.movable),
    'V S3 refunded, the store-moved credit is not listed as moving');
  perform pg_temp.t463_run('V', 'S2', 'sale A pbv', 1, 1);
  perform pg_temp.t463_check(exists (select 1 from invoice_transferable_benefits(pg_temp.t463_id('V/S2/inv')) x
                                      where x.kind = 'voucher' and x.movable and x.description = 'T463 Plain 30 × 2'),
    'V S2 the bundle''s vouchers are not listed as moving');
  raise notice 'PASS V: a store-moved limited voucher follows the change at its store, no stock moving; a voucher line''s own move to the new store with their stock (417); a Premium Bundle''s follow the customer at their store, no stock moving; the change''s list and summary show the store-moved credit and the bundle''s vouchers';
end $$;

-- ===== W. The summary of a change while a reopening waits (W1) =====
-- 460's NOT COVERED 7: a cpb package and two vouchers, its S$10 Bonus moved
-- to a friend, cancelled, every line paid back, reopened (it waits): the
-- summary of a change to B lists what the payment will give B (S$100 Paid,
-- the two vouchers), not the friend's Bonus; with 'keep', nothing moving; no
-- reopening waiting, no such line. A bundle's, and a store-moved package's
-- (decision 2), too; a package moved to a friend: none.
create function pg_temp.t463_waiting(p_inv uuid, p_to uuid, p_action text) returns jsonb language sql as $f$
  select coalesce(jsonb_agg(e->'items' order by e::text), '[]'::jsonb)
    from jsonb_array_elements(preview_invoice_correction(p_inv, jsonb_build_object('customer_id', p_to, 'benefit_action', p_action))->'effects') e
   where e->>'area' = 'benefits' and e->>'change' = 'transferring'
     and e->>'detail' like 'The invoice''s reopening waits for its payment.%' $f$;
do $$
declare inv uuid; b uuid; o jsonb;
begin
  perform pg_temp.t463_run('W', 'W1', 'sale A cpb,v; move 0 F bonus; wait', 1, 3);
  inv := pg_temp.t463_id('W/W1/inv'); b := pg_temp.t463_cust('W/W1/B');
  perform pg_temp.t463_check(pg_temp.t463_waiting(inv, b, 'transfer')
      = '[[{"kind": "credit", "what": "Paid credit 100.00"}, {"kind": "voucher", "what": "T463 Plain 30 × 2"}]]'::jsonb,
    'W W1: ' || pg_temp.t463_waiting(inv, b, 'transfer')::text);
  perform pg_temp.t463_check(pg_temp.t463_waiting(inv, b, 'keep') = '[]'::jsonb
      and not (preview_invoice_correction(inv, jsonb_build_object('customer_id', b, 'benefit_action', 'keep'))->'effects'
               @> '[{"area": "benefits", "change": "transferring"}]'),
    'W W1 with keep lists benefits moving');
  -- Without a choice yet, the same line (the review asks to choose).
  perform pg_temp.t463_check(pg_temp.t463_waiting(inv, b, '') = pg_temp.t463_waiting(inv, b, 'transfer'), 'W W1 without a choice');
  -- Then changed and paid: B holds what the summary said, the friend the Bonus.
  o := pg_temp.t463_run('W', 'W1', 'sale A cpb,v; move 0 F bonus; wait; change B; pay', 4);
  perform pg_temp.t463_check(o->'holds' @> '{"A":"0.00","B":"100.00/2","F":"10.00"}' and o->>'invariants' = '', 'W W1 paid: ' || o::text);
  -- A bundle's waiting reopening.
  perform pg_temp.t463_run('W', 'W2', 'sale A pbv; wait', 1, 2);
  perform pg_temp.t463_check(pg_temp.t463_waiting(pg_temp.t463_id('W/W2/inv'), pg_temp.t463_cust('W/W2/B'), 'transfer')
      = '[[{"kind": "credit", "what": "Bonus credit 40.00"}, {"kind": "credit", "what": "Paid credit 100.00"}, {"kind": "voucher", "what": "T463 Plain 30 × 2"}]]'::jsonb,
    'W W2: ' || pg_temp.t463_waiting(pg_temp.t463_id('W/W2/inv'), pg_temp.t463_id('W/W2/B'), 'transfer')::text);
  -- A package an Owner moved to the same customer at another store: listed;
  -- moved to a friend: not.
  perform pg_temp.t463_run('W', 'W3', 'sale A cp; move 1 A store2; wait', 1, 3);
  perform pg_temp.t463_check(pg_temp.t463_waiting(pg_temp.t463_id('W/W3/inv'), pg_temp.t463_cust('W/W3/B'), 'transfer')
      = '[[{"kind": "credit", "what": "Paid credit 100.00"}]]'::jsonb,
    'W W3: ' || pg_temp.t463_waiting(pg_temp.t463_id('W/W3/inv'), pg_temp.t463_id('W/W3/B'), 'transfer')::text);
  perform pg_temp.t463_run('W', 'W4', 'sale A cp; move 1 F; wait', 1, 3);
  perform pg_temp.t463_check(pg_temp.t463_waiting(pg_temp.t463_id('W/W4/inv'), pg_temp.t463_cust('W/W4/B'), 'transfer') = '[]'::jsonb,
    'W W4: ' || pg_temp.t463_waiting(pg_temp.t463_id('W/W4/inv'), pg_temp.t463_id('W/W4/B'), 'transfer')::text);
  -- No reopening waiting: no such line (what moves now is listed as before).
  perform pg_temp.t463_run('W', 'W5', 'sale A cpb,v', 1, 1);
  perform pg_temp.t463_check(pg_temp.t463_waiting(pg_temp.t463_id('W/W5/inv'), pg_temp.t463_cust('W/W5/B'), 'transfer') = '[]'::jsonb
      and preview_invoice_correction(pg_temp.t463_id('W/W5/inv'), jsonb_build_object('customer_id', pg_temp.t463_id('W/W5/B'), 'benefit_action', 'transfer'))->'effects'
          @> '[{"area": "benefits", "change": "transferring", "detail": "These unused benefits move to the new customer with their original source, deadlines and restrictions unchanged."}]',
    'W W5 nothing waiting');
  raise notice 'PASS W: while a reopening waits, the summary of a change lists what its payment will give the new customer (W1: S$100 Paid and two vouchers, not the friend''s Bonus; a bundle''s S$40 Bonus, S$100 Paid and two vouchers; a store-moved package''s S$100), nothing with keep, nothing moved to a friend, no such line when nothing waits; and the payment gives exactly that';
end $$;

-- ===== G. No invoice for a removed customer record (K6s) =====
do $$
declare k uuid; a uuid; dd uuid; inv uuid; m text; req uuid := gen_random_uuid(); inv2 uuid;
begin
  perform pg_temp.t463_run('G', 'K6s', 'sale A cp', 1, 1);
  a := pg_temp.t463_id('G/K6s/A');
  -- A request made before the merge, sent again after it, gets back the
  -- invoice it made (416), as before.
  inv := create_invoice_with_details(pg_temp.t463_id('store'), a,
    jsonb_build_array(jsonb_build_object('kind', 'voucher', 'voucher_id', pg_temp.t463_id('v'), 'quantity', 1)),
    jsonb_build_object('business_date', sg_today()::text, 'request_id', req));
  k := pg_temp.t463_cust('G/K6s/K');
  perform pg_temp.t463_merge(k, a);
  begin
    perform create_invoice_with_details(pg_temp.t463_id('store'), a,
      jsonb_build_array(jsonb_build_object('kind', 'voucher', 'voucher_id', pg_temp.t463_id('v'), 'quantity', 1)),
      jsonb_build_object('business_date', sg_today()::text));
    m := 'accepted';
  exception when others then m := sqlerrm;
  end;
  perform pg_temp.t463_check(m = 'This customer''s record was merged into another or deleted. Choose the customer again.',
    'G a merged record: ' || m);
  inv2 := create_invoice_with_details(pg_temp.t463_id('store'), a,
    jsonb_build_array(jsonb_build_object('kind', 'voucher', 'voucher_id', pg_temp.t463_id('v'), 'quantity', 1)),
    jsonb_build_object('business_date', sg_today()::text, 'request_id', req));
  perform pg_temp.t463_check(inv2 = inv, 'G the request made before the merge, sent again, did not get its invoice back');
  dd := pg_temp.t463_cust('G/K6s/D');
  perform delete_customer(dd, (select full_name from customers where id = dd), 'T463 delete');
  begin
    perform create_invoice_with_details(pg_temp.t463_id('store'), dd,
      jsonb_build_array(jsonb_build_object('kind', 'voucher', 'voucher_id', pg_temp.t463_id('v'), 'quantity', 1)),
      jsonb_build_object('business_date', sg_today()::text));
    m := 'accepted';
  exception when others then m := sqlerrm;
  end;
  perform pg_temp.t463_check(m = 'This customer''s record was merged into another or deleted. Choose the customer again.',
    'G a deleted record: ' || m);
  perform pg_temp.t463_check(create_invoice_with_details(pg_temp.t463_id('store'), k,
      jsonb_build_array(jsonb_build_object('kind', 'voucher', 'voucher_id', pg_temp.t463_id('v'), 'quantity', 1)),
      jsonb_build_object('business_date', sg_today()::text)) is not null, 'G the kept record');
  perform pg_temp.t463_check(not exists (select 1 from invoices where customer_id in (a, dd) and id <> inv), 'G an invoice was made for a removed record');
  raise notice 'PASS G: an invoice for a record a merge retired, or one Delete removed, is refused with "This customer''s record was merged into another or deleted. Choose the customer again."; a request made before the merge still gets back the invoice it made; the kept record is invoiced as usual';
end $$;

-- ===== K. KNOWN: not covered by 463 (each checked as it is) =====
do $$
declare o jsonb;
begin
  -- K1 (460's NOT COVERED 3, W2): vouchers a reopening gives again stay at
  -- the store of the voucher they replace, after a change that moved the
  -- invoice to another store (an Owner decision).
  o := pg_temp.t463_run('K', 'W2', 'sale A v; wait; change B store2; pay');
  perform pg_temp.t463_check(o->'holds' @> '{"B":"0.00/2"}' and coalesce(o->'at2'->>'B', '') = '0.00',
    'K1 W2: look at 463 again ' || o::text);
  -- K2 (445's NOT COVERED 1): a merge of a record that spent wallet credit
  -- is still refused.
  o := pg_temp.t463_run('K', 'S1m', 'sale A cp; spend A; move 1 A store2; unspend S1; merge K A');
  perform pg_temp.t463_check(coalesce(o->>'error', '') like 'merge K A: Credit allocations cannot be changed once recorded%',
    'K2 S1m: look at 463 again ' || o::text);
  raise notice 'KNOWN K: (not covered by 463) (1) vouchers a reopening gives again stay at the store of the voucher they replace, after a change that moved the invoice to another store (W2, 460''s NOT COVERED 3: an Owner decision); (2) a merge of a record that spent wallet credit is refused (S1m, 445''s NOT COVERED 1); (3) a voucher an Owner moved to the same customer at another store, and a Premium Bundle''s, keep their store when the customer changes (as credit does; a voucher line''s go to the invoice''s store, 417); (4) vouchers claimed later from a Premium Bundle''s voucher allowance, and a therapy voucher with sessions used but still held, are as before (header NOT COVERED)';
end $$;

rollback;
