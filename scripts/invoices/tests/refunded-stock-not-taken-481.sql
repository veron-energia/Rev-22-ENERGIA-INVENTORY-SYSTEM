-- 481: the payment that settles an invoice (a reopened one, or one paid in
-- part and settled later) takes from stock only what was not refunded by
-- line; a product line refunded by line since the sale or since the last
-- reopening is not taken from stock again, by that payment or by any other
-- way an invoice takes stock for its lines (a hand-over before full
-- payment, a correction that changes its stock, its fulfilment from a
-- warehouse, the backstop when it becomes paid), and invoice_stock_to_deduct
-- no longer reports such units as still to take (479's NOT COVERED 1; the
-- Owner, 29 Oct 2026, ~18:45 SGT, Q2: "Fix it separately").
-- supabase/481_settlement_takes_no_refunded_stock.sql (after 479).
--
-- Every step goes through the app's own calls: the invoice form
-- (create_invoice_with_details) and the Pay dialog (record_invoice_settlement)
-- of the whole amount or a part, Record Payment of what is outstanding or of
-- an amount, Correct payment (correct_invoice_payment), Cancel, Reopen, the
-- Finance panel's refund by line (refund_invoice_recorded: of a product or
-- promotion line by money with the stock outcome it asks for, returned and
-- sellable, damaged or not returned: 'backps', 'backpd', 'backpn'; of a
-- credit line: 'back'; of voucher units: 'backv'; of a therapy line's
-- sessions by money: 'backt') and "Record refund paid" of an amount with no
-- line ('paidback'), the guided Refund in full and Cancel (requested, an
-- Owner approving them as the plan reads then, "Record refund paid"
-- ticked), "Hand over items" (record_invoice_handover), "Fulfil from" a
-- warehouse (set_invoice_fulfilment_warehouse), the invoice form's
-- correction moving the invoice to another store or changing a product
-- line's quantity (correct_invoice), the invoice form alone (nothing paid),
-- Record Payment from the wallet (Credit Package Paid credit) and Correct
-- payment of a receipt's date alone. Each app
-- call is followed by what its commit does (462's trigger on the ledger is
-- DEFERRABLE INITIALLY DEFERRED and this suite is one transaction: SET
-- CONSTRAINTS ... IMMEDIATE, then DEFERRED).
--
-- The cases (A the buyer; pr a S$40 product with stock at both stores and at
-- a warehouse, pr2 two of it, prm a S$70 promotion of two of it; v a voucher
-- line of 2 units at S$30; th a therapy line of 3 sessions at S$20; cp the
-- S$100 Credit Package; cpp a S$100 Credit Package whose paid credit buys
-- products too (its spending rules), bought on an invoice of its own; bx a
-- S$50 blind box, its prize A the product and a
-- pair of gloves, bx2 two boxes with prize A twice, bxm two boxes with prize
-- A and prize B (two belts), bxd a S$50 box with prize A and the product
-- picked directly). What a case reads: the invoice's status and net
-- money, the refund it shows as due ('due'), the warehouse's sends (its
-- 'invoice_fulfilled_from_warehouse' audit rows, 'fulfil'), its stock
-- movements by kind ('stock'), what is out with the
-- customer by its movements ('out': store sales less the returns of a
-- Cancel and of a refund), what invoice_stock_to_deduct reports ('td'), the
-- Goods panel (invoice_goods_status: 'goods', on the invoice / collected /
-- to collect, per product, sorted), the stock reports (invoice_stock_gaps:
-- 'gap', sorted), what the
-- case's steps took from the stores and the warehouse ('dstore', 'dwh'),
-- the product lines' refunds by line ('prref', all of them; 'prref_since',
-- since the last reopening), the sessions ('sess'), who holds what ('holds':
-- credit, '/n' held vouchers), the Reopen dialog's "Stock to issue" where
-- the invoice is cancelled ('issue'), the plan its last guided step read
-- (its lines sorted: their order is not fixed, so no comparison depends on
-- it), and the refusal that stopped it.
--   Fixed (before 481 the units a refund by line paid back were taken from
--   stock; after it not; 'expect0' before, 'expect' after):
--   VPR, CPR    cancelled, a voucher (S$50 of the package) refunded by line,
--               reopened, the guided Refund in full (the product's S$40 and
--               the rest), paid: before, a second store sale.
--   PRxk, PRxk2 with 3 sessions, the product's S$40 refunded by line while
--               cancelled and again after the reopening, paid.
--   PRn1, PRn2  with 3 sessions, 1 refunded by line while cancelled,
--               reopened, the Refund in full (479's route; either line
--               written first), paid.
--   PV1         1 voucher refunded while cancelled, reopened, the product
--               refunded by line, paid.
--   P3a, P3b    the sessions all and the product refunded by line while
--               cancelled, reopened, S$40 paid, the Refund in full refunds
--               the product again (479's NOT COVERED 17), paid.
--   PRpp, L6, PRM  paid in part, the product (the promotion) refunded by line,
--               settled by Record Payment (by Correct payment): before, taken.
--   L7, M2      a line of two (two lines of one), one unit's S$40 refunded.
--   W2          fulfilled from a warehouse: before, the warehouse sent it.
--   H2, H4      handed over before full payment, refunded by line with the
--               unit returned, paid (a line of two in H4).
--   H3          paid in part, refunded by line, then handed over: before
--               allowed, after refused ("Only 0 of ... is still to collect").
--   PRpd        paid, refunded by line with the unit returned: before,
--               invoice_stock_to_deduct reported 1; PRpds, PRpdd, a
--               correction moving the store then took it again (returned
--               as sellable; damaged).
--   RD1, RD4, RD10, RD6, RD6s, RD8, RW67, RW67b, RW25  a unit whose paid
--               value is not whole cents (the review of 2 Nov 2026): 3 of the
--               product and 2 vouchers with an Owner's S$30 discount (the
--               product's line S$100.00, S$33.333 a unit), S$66.66 refunded
--               by line (in two refunds of S$33.33; three), then paid: before,
--               the count lost a unit to the cent; paid, 2 units returned
--               with S$66.66 (then the store moved); the reopened route; a
--               2-unit line of S$66.67 (S$33.33; S$66.66 refunded); a 4-unit
--               line of S$100.00 (S$99.98 refunded: 3 units).
--   BX1, BX2, BXD, BXF, BXW, BXP, BXM  a S$50 blind box (483: its prize's
--               products are the line's stock components), refunded by line:
--               paid in part then settled by Record Payment (BX1), one of two
--               boxes on a line (BX2), with a product picked directly too
--               (BXD), by Correct payment (BXF), on an invoice fulfilled from
--               a warehouse (BXW: the store gives a promotion's contents);
--               paid, its prize returned (BXP: before, 2 still to take); two
--               boxes with different prizes, one box's value refunded (BXM:
--               each prize in proportion, rounded down, NOT COVERED 10).
--   The cut plans (t481_ocases: the guided plan cut to the money held in
--   the order it lists the lines, not fixed; each run with its lines written
--   both ways and checked for the line its plan lists first): P1a/b, P5a/b
--   (a voucher line, the product's S$40 refunded by line or paid back with
--   no line while cancelled, S$10 paid since: the product first, its S$40
--   again: fixed; the vouchers first, S$10 of it: still taken, NOT COVERED
--   1), P4a/b (with 3 sessions, 1 refunded: the product first, its S$40
--   again: fixed; the therapy line first: refused, as before).
--   Controls (exactly the same before 481 and after it, every key): L1 paid
--   at once; L2 in part, then paid; L3 cancelled, reopened straight to paid;
--   L4, PRx1p refunded by line while cancelled, reopened, paid (the
--   reopening charges it again: delivered again); L5 settled by Correct
--   payment; L8 S$20 of a line of two refunded (NOT COVERED 1); H1 handed over
--   then paid; W1 fulfilled from a warehouse; W3, W4 a warehouse invoice
--   cancelled and reopened (NOT COVERED 3); PRpdn refunded, the unit Not
--   returned, the store moved; PRc cancelled, the product refunded (the
--   Reopen dialog: 1 to issue), PRcb then reopened (1 to collect); RC1, RC2
--   Correct payment raising a cancelled invoice's money, reopened straight
--   to paid; CPr, CPd refunded with the unit returned, cancelled, reopened,
--   settled by Record Payment, by Correct payment (NOT COVERED 2); E4w3
--   paid from the wallet on an invoice fulfilled from a warehouse, then one
--   Correct payment of the receipt's date alone: the warehouse sends it
--   again (NOT COVERED 3, widened from the review of 2 Nov 2026); BX0 a
--   blind box paid at once; BXL4 refunded by line while cancelled, reopened,
--   paid (delivered again); BXpt S$25 of the S$50 box (NOT COVERED 1); PRx1,
--   PRnl1, PRxr2, PRxc1 (479's NOT COVERED 10 product shapes: refused, as
--   before, so the product is not refunded a second time there); PRM2 half
--   of the promotion refunded (NOT COVERED 1).
--   Known, different before 481 and after it ('expect0' before, 'expect'
--   after, not compared key by key): F1 (NOT COVERED 13) 3 of the product
--   paid, one unit's S$40 refunded by line with the unit returned, then the
--   invoice form cuts the line to 2: the correction puts back what is out
--   and takes the line again, before 481 2 units, from 481 1 (the refund
--   counted as its unit); the money the same, S$40 shown as due back.
--
--   S. Where it starts: 479 in (its three AFTERs); 481 in (nomig) or not.
--   R. Without 481 (skipped with -v nomig=1), undone: each case as before
--      481 (the fixed ones taking the refunded units).
--   Q. The read-only query in 481's header (the same text), on those states
--      and on the states after 481: what it lists, by reason (1, 2).
--   9. Refusals, each changing nothing: a function of the four not as
--      tested; a partial install; a function it relies on not as tested
--      (479's AFTERs among them); an overload of a name; a new caller; a
--      new writer of refunds or of stock outcomes, a new setter of
--      reopened_at, a new reader of store sales; the triggers not as read; a
--      column read not as read; other grants. The same grants in another
--      order do not stop it.
--  10. 481 installed twice: as tested, the second run changing nothing, one
--      function added (the server's alone), the grants as before.
--   A. Each case after 481: as expected; a control exactly as before 481
--      (and a known case with no 'expect0').
--   P. Probes: the four texts beside 481's parts exactly as before (worked
--      back, by md5); the header's query's rule equal to
--      invoice_refunded_stock on every case's state.
--   K. KNOWN (481's NOT COVERED), checked as they are: 1 (P1b, P5b, L8,
--      PRM2, BXpt), 2 (CPd, CPr), 3 (W3, W4; E4w3, a settled warehouse
--      invoice paid from the wallet whose receipt's date alone is corrected:
--      sent again; the header's second read-only query lists it, not W1),
--      4 (P3a, P3b, P1a, P4a, P5a: the
--      product's line refunded a second time; its stock side fixed), 5 (a
--      limited voucher refunded by line before its vouchers are given:
--      refused, LV1), 8 (the promotions' stock report lists PRM as missing),
--      10 (BXM: two boxes with different prizes, one refunded), 12 (RDp1,
--      RDp2, RDp3: more units returned with a refund than its money pays for),
--      13 (F1: an Edit Invoice cutting a line a refund by line paid back).
--
-- Run on a copy of production at 486 with 479 applied (3 Nov 2026:
-- 8928dd46, 1398 functions; at 485 with 479 it was 5695d246, 486 having
-- changed the merge preview alone; 481 pins 483's
-- capture_invoice_stock_components, so it refuses on a copy at 478):
--   psql -X -v ON_ERROR_STOP=1 -f scripts/invoices/tests/refunded-stock-not-taken-481.sql
-- It installs 481 itself (twice) inside its transaction. Where 481 is in
-- already, add -v nomig=1 (S checks it as tested; R, Q's first part and 9
-- are skipped; every case after 481 is still checked). Section 9 lets the
-- install fail on purpose (psql prints its ERROR); the suite then checks
-- that message. Disposable database only; everything is rolled back. Every
-- name, code and amount is invented (@example.com); the phones are numbers
-- kept for fiction (ACMA, +61491570000 to +61491570999).
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '10s';
set local statement_timeout = '1800s';

-- ── Set-up and the app's calls ───────────────────────────────────────────────
create temp table t481(k text primary key, id uuid);
create temp table t481_res(phase text, k text, v jsonb, primary key (phase, k));
create temp table t481_fp(k text primary key, fp text);
create temp table t481_err(pre text primary key, err text, at int);
create temp table t481_plan(pre text primary key, lines text, first text);
create temp sequence t481_phone;
create function pg_temp.t481_id(p_k text) returns uuid language sql as $f$ select id from t481 where k = p_k $f$;
create function pg_temp.t481_put(p_k text, p_id uuid) returns uuid language sql as $f$
  insert into t481 values (p_k, p_id) on conflict (k) do update set id = excluded.id returning id $f$;
create function pg_temp.t481_check(p_ok boolean, p_label text) returns void language plpgsql as $f$
begin
  if not coalesce(p_ok, false) then raise exception 'FAIL %', p_label; end if;
end $f$;
create function pg_temp.t481_fingerprint() returns text language sql as $f$
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.oid::regprocedure::text)) || ' ' || count(*)
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prokind in ('f', 'p') $f$;
-- Who may call a function (the set) and the whole grant list (by name;
-- without 481's new function, so it compares with the list before 481).
create function pg_temp.t481_grants() returns text language sql as $f$
  select md5(string_agg(p.oid::regprocedure::text || '=' || coalesce((select string_agg(x::text, ',' order by x::text) from unnest(p.proacl) x), 'null'),
                        '|' order by p.oid::regprocedure::text))
    from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname <> 'invoice_refunded_stock' $f$;
create function pg_temp.t481_grant_set(p_sig text) returns text[] language sql as $f$
  select array_agg(x::text order by x::text) from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || p_sig) $f$;
create function pg_temp.t481_462_in() returns boolean language sql as $f$
  select to_regprocedure('public.credit_given_back_follows(uuid)') is not null
     and exists (select 1 from pg_trigger where tgname = 'credit_given_back_follows'
                  and tgrelid = 'public.customer_credit_ledger'::regclass) $f$;
-- 479 is in (its three AFTERs, as 481 pins them).
create function pg_temp.t481_479_in() returns boolean language sql as $f$
  select md5(pg_get_functiondef('public.refund_invoice_therapy_sessions(uuid,numeric,text,uuid)'::regprocedure)) = '35d3f1ba4c906a66a8deb131c777dab8'
     and md5(pg_get_functiondef('public.correct_invoice_therapy_sessions(uuid,jsonb,uuid,uuid,text,uuid)'::regprocedure)) = '32df6441a3f5e37e164b1279f8dc502b'
     and md5(pg_get_functiondef('public.trg_create_therapy_sessions_on_paid()'::regprocedure)) = '15f4bbc260e53ba538debc0947082f43' $f$;
-- The four functions 481 changes: BEFORE (production at 478 with 479 in, 30
-- Oct 2026, as on its copy) and AFTER; and the one it adds.
create temp table t481_md5(sig text primary key, before text, after text);
insert into t481_md5 values
  ('invoice_stock_to_deduct(uuid)', '6356494ccb8545d46c56b788f8f85f54', '5480e6042b4521829ebce1ef14937162'),
  ('invoice_product_net_deducted(uuid,uuid)', 'f6288d8eb44af4cd4dbed11f63d3427a', 'e42acff8d87d5d2299159fa9ce6805ae'),
  ('trg_fulfil_from_warehouse()', '4abf4bf68e4f00658a8da66469e7059e', 'e1d41bce9c53d21ac2ab727042663cfb'),
  ('invoice_goods_status(uuid)', '651039eac932b5d1f51fc75313ed4320', 'ca966a2c6a1949afc98503862263b58d');
create function pg_temp.t481_at(p_col text) returns boolean language sql as $f$
  select bool_and(md5(pg_get_functiondef(to_regprocedure('public.' || m.sig))) = case when p_col = 'before' then m.before else m.after end)
    from t481_md5 m $f$;
-- 481 is in: the new function is there, at its AFTER.
create function pg_temp.t481_in() returns boolean language sql as $f$
  select to_regprocedure('public.invoice_refunded_stock(uuid)') is not null
     and md5(pg_get_functiondef(to_regprocedure('public.invoice_refunded_stock(uuid)'))) = 'f12af401547ce01e2b95ec3a5c230bad' $f$;
-- What a commit does at the end of each app call: 462's deferred trigger on
-- the ledger runs (481 adds no trigger). Here the suite is one transaction,
-- so the trigger's queued rows are run at this point.
create function pg_temp.t481_commit() returns void language plpgsql as $f$
begin
  if pg_temp.t481_462_in() then
    execute 'set constraints public.credit_given_back_follows immediate';
    execute 'set constraints public.credit_given_back_follows deferred';
  end if;
end $f$;

do $$
declare own uuid := gen_random_uuid(); st uuid; st2 uuid; pm uuid; v uuid; lv uuid; cp uuid; cpp uuid; svc uuid; prod uuid; prm uuid; wh uuid;
begin
  insert into auth.users(id, email) values (own, 't481-owner@example.com');
  insert into profiles(id, full_name, email, role, is_active) values (own, 'T481 Owner', 't481-owner@example.com', 'owner', true);
  perform set_config('request.jwt.claims', json_build_object('sub', own, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', own::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  insert into stores(name, code, country_code) values ('T481 Store', 'T481S1', 'SG') returning id into st;
  insert into stores(name, code, country_code) values ('T481 Other Store', 'T481S2', 'SG') returning id into st2;
  insert into payment_methods(name, is_active) values ('T481 Cash', true) returning id into pm;
  insert into vouchers(name, code, voucher_kind, qty_type, selling_price, is_active)
    values ('T481 Plain 30', 'T481-P30', 'normal', 'unlimited', 30, true) returning id into v;
  insert into voucher_store_prices(voucher_id, store_id, selling_price, available_at_store) values (v, st, 30, true), (v, st2, 30, true);
  -- a limited voucher with stock (NOT COVERED 5)
  insert into vouchers(name, code, voucher_kind, qty_type, selling_price, is_active)
    values ('T481 Limited 30', 'T481-L30', 'normal', 'limited', 30, true) returning id into lv;
  insert into voucher_store_prices(voucher_id, store_id, selling_price, available_at_store) values (lv, st, 30, true);
  insert into voucher_store_stock(voucher_id, store_id, current_qty) values (lv, st, 100);
  insert into credit_packages(name, customer_price, paid_credit_amount, bonus_enabled, allow_product, allow_therapy)
    values ('T481 S$100', 100, 100, false, true, true) returning id into cp;
  insert into credit_package_stores(package_id, store_id) values (cp, st), (cp, st2);
  -- (E4w3) a S$100 Credit Package whose paid credit buys products too (its
  -- spending rules, as an Owner sets them; by default paid package credit
  -- buys sessions only)
  insert into credit_packages(name, customer_price, paid_credit_amount, bonus_enabled, allow_product, allow_therapy)
    values ('T481 S$100 Products', 100, 100, false, true, true) returning id into cpp;
  insert into credit_package_stores(package_id, store_id) values (cpp, st), (cpp, st2);
  perform set_credit_package_spending_rules(cpp, array['therapy_session', 'own_product'], array['own_product', 'third_party_product'],
    'T481 products too');
  svc := (upsert_therapy_service(null, 'T481-SESSION', 'T481 Session', 20, 30, 'per_hours', 1, 5, null, true, null) ->> 'id')::uuid;
  perform set_therapy_service_store(svc, st, true, null);
  -- the S$40 product, stocked at both stores and at a warehouse; a S$70
  -- promotion of two of it
  insert into products(name, sku, product_type) values ('T481 Socks', 'T481-SOCKS', 'own') returning id into prod;
  insert into store_inventory(store_id, product_id, current_qty) values (st, prod, 100), (st2, prod, 100);
  perform set_product_prices(st, prod, 40, 40, 'available');
  perform set_product_prices(st2, prod, 40, 40, 'available');
  insert into warehouses(name, code) values ('T481 Warehouse', 'T481W') returning id into wh;
  insert into warehouse_inventory(warehouse_id, product_id, current_qty) values (wh, prod, 100);
  insert into promotions(name, code, fixed_price) values ('T481 Two Socks', 'T481-2S', 70) returning id into prm;
  insert into promotion_items(promotion_id, item_type, product_id, quantity) values (prm, 'product', prod, 2);
  perform set_promotion_prices(prm, st, 70, 70, true);
  insert into t481 values ('own', own), ('store', st), ('store2', st2), ('pm', pm), ('v', v), ('lv', lv), ('cp', cp),
    ('svc', svc), ('prod', prod), ('prm', prm), ('wh', wh), ('cpp', cpp),
    -- the wallet method that spends Credit Package paid credit (443's)
    ('wallet', (select id from payment_methods where name = 'Wallet — Credit Package Paid' and is_wallet_credit and deleted_at is null));
  perform pg_temp.t481_check(pg_temp.t481_id('wallet') is not null, 'setup: the wallet method (443) is there');
end $$;
-- A S$50 blind box as the real ones are made (483: one choice group whose
-- options are promotions, its prize): prize A the socks and a pair of gloves,
-- prize B two belts; and a S$50 box with a prize group and a product group
-- (the socks picked directly too). Gloves and belts are stocked at both
-- stores, as the socks are.
do $$
declare st uuid := pg_temp.t481_id('store'); st2 uuid := pg_temp.t481_id('store2'); prod uuid := pg_temp.t481_id('prod');
  gloves uuid; belt uuid; pa uuid; pb uuid; box uuid; g uuid; box2 uuid; g2 uuid; gp uuid;
begin
  perform set_config('request.jwt.claim.sub', pg_temp.t481_id('own')::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  insert into products(name, sku, product_type) values ('T481 Gloves', 'T481-GLOVES', 'own') returning id into gloves;
  insert into products(name, sku, product_type) values ('T481 Belt', 'T481-BELT', 'own') returning id into belt;
  insert into store_inventory(store_id, product_id, current_qty) values (st, gloves, 100), (st2, gloves, 100), (st, belt, 100), (st2, belt, 100);
  perform set_product_prices(s, p, 40, 40, 'available') from unnest(array[st, st2]) s, unnest(array[gloves, belt]) p;
  insert into promotions(name, code) values ('T481 Prize Socks + Gloves', 'T481-PA') returning id into pa;
  insert into promotion_items(promotion_id, item_type, product_id, quantity) values (pa, 'product', prod, 1), (pa, 'product', gloves, 1);
  insert into promotions(name, code) values ('T481 Prize Two Belts', 'T481-PB') returning id into pb;
  insert into promotion_items(promotion_id, item_type, product_id, quantity) values (pb, 'product', belt, 2);
  insert into promotions(name, code) values ('T481 Blind Box', 'T481-BX') returning id into box;
  insert into promotion_choice_groups(promotion_id, label, item_kind, choose_qty)
    values (box, 'Choose your blind box products', 'promotion', 1) returning id into g;
  insert into promotion_choice_options(group_id, child_promotion_id) values (g, pa), (g, pb);
  perform set_promotion_prices(box, s, 50, 50, true) from unnest(array[st, st2]) s;
  insert into promotions(name, code) values ('T481 Box With Extra', 'T481-BXD') returning id into box2;
  insert into promotion_choice_groups(promotion_id, label, item_kind, choose_qty)
    values (box2, 'Choose your prize', 'promotion', 1) returning id into g2;
  insert into promotion_choice_options(group_id, child_promotion_id) values (g2, pa), (g2, pb);
  insert into promotion_choice_groups(promotion_id, label, item_kind, choose_qty)
    values (box2, 'Choose an extra', 'product', 1) returning id into gp;
  insert into promotion_choice_options(group_id, product_id) values (gp, prod);
  perform set_promotion_prices(box2, s, 50, 50, true) from unnest(array[st, st2]) s;
  insert into t481 values ('gloves', gloves), ('belt', belt), ('prizeA', pa), ('prizeB', pb), ('box', box), ('boxg', g),
    ('box2', box2), ('box2g', g2), ('box2gp', gp);
end $$;
-- A pick as the invoice form sends it (every pick column, the unused null).
create function pg_temp.t481_pick(p_promo uuid, p_product uuid, p_q int) returns jsonb language sql as $f$
  select jsonb_build_object('product_id', p_product, 'voucher_id', null, 'therapy_package_id', null, 'credit_package_id', null,
                            'child_promotion_id', p_promo, 'quantity', p_q) $f$;

-- A customer of one run of one case: '<phase>/<case>/<role>'.
create function pg_temp.t481_cust(p_k text) returns uuid language plpgsql as $f$
declare c uuid;
begin
  insert into customers(full_name, phone) values ('T481 ' || p_k, '+61491570' || lpad((nextval('t481_phone') % 1000)::text, 3, '0'))
    returning id into c;
  return pg_temp.t481_put(p_k, c);
end $f$;
create function pg_temp.t481_role(p_pre text, p_r text) returns uuid language plpgsql as $f$
begin
  return coalesce(pg_temp.t481_id(p_pre || '/' || p_r), pg_temp.t481_cust(p_pre || '/' || p_r));
end $f$;
-- The invoice form with these lines (in the order given), with an Owner's
-- manual discount of p_discount where one is given (its reason given), then
-- the Pay dialog of what it charges, or of p_first of it.
create function pg_temp.t481_sale(p_cust uuid, p_kinds text[], p_first numeric default null, p_discount numeric default null)
  returns uuid language plpgsql as $f$
declare inv uuid; v_lines jsonb := '[]'; i int;
begin
  for i in 1 .. cardinality(p_kinds) loop
    v_lines := v_lines || jsonb_build_array(case p_kinds[i]
      when 'v' then jsonb_build_object('kind', 'voucher', 'voucher_id', pg_temp.t481_id('v'), 'quantity', 2)
      when 'lv' then jsonb_build_object('kind', 'voucher', 'voucher_id', pg_temp.t481_id('lv'), 'quantity', 2)
      when 'th' then jsonb_build_object('kind', 'therapy', 'therapy_service_id', pg_temp.t481_id('svc'), 'quantity', 3)
      when 'pr' then jsonb_build_object('kind', 'product', 'product_id', pg_temp.t481_id('prod'), 'quantity', 1)
      when 'pr2' then jsonb_build_object('kind', 'product', 'product_id', pg_temp.t481_id('prod'), 'quantity', 2)
      when 'pr3' then jsonb_build_object('kind', 'product', 'product_id', pg_temp.t481_id('prod'), 'quantity', 3)
      when 'pr4' then jsonb_build_object('kind', 'product', 'product_id', pg_temp.t481_id('prod'), 'quantity', 4)
      when 'prm' then jsonb_build_object('kind', 'promotion', 'promotion_id', pg_temp.t481_id('prm'), 'quantity', 1)
      -- the blind box (483): prize A; two boxes, prize A twice; two boxes,
      -- prize A and prize B; the box with an extra, prize A and the socks
      when 'bx' then jsonb_build_object('kind', 'promotion', 'promotion_id', pg_temp.t481_id('box'), 'quantity', 1, 'selections',
        jsonb_build_array(jsonb_build_object('group_id', pg_temp.t481_id('boxg'), 'options',
          jsonb_build_array(pg_temp.t481_pick(pg_temp.t481_id('prizeA'), null, 1)))))
      when 'bx2' then jsonb_build_object('kind', 'promotion', 'promotion_id', pg_temp.t481_id('box'), 'quantity', 2, 'selections',
        jsonb_build_array(jsonb_build_object('group_id', pg_temp.t481_id('boxg'), 'options',
          jsonb_build_array(pg_temp.t481_pick(pg_temp.t481_id('prizeA'), null, 2)))))
      when 'bxm' then jsonb_build_object('kind', 'promotion', 'promotion_id', pg_temp.t481_id('box'), 'quantity', 2, 'selections',
        jsonb_build_array(jsonb_build_object('group_id', pg_temp.t481_id('boxg'), 'options',
          jsonb_build_array(pg_temp.t481_pick(pg_temp.t481_id('prizeA'), null, 1), pg_temp.t481_pick(pg_temp.t481_id('prizeB'), null, 1)))))
      when 'bxd' then jsonb_build_object('kind', 'promotion', 'promotion_id', pg_temp.t481_id('box2'), 'quantity', 1, 'selections',
        jsonb_build_array(
          jsonb_build_object('group_id', pg_temp.t481_id('box2g'), 'options', jsonb_build_array(pg_temp.t481_pick(pg_temp.t481_id('prizeA'), null, 1))),
          jsonb_build_object('group_id', pg_temp.t481_id('box2gp'), 'options', jsonb_build_array(pg_temp.t481_pick(null, pg_temp.t481_id('prod'), 1)))))
      when 'cp' then jsonb_build_object('kind', 'credit_package', 'credit_package_id', pg_temp.t481_id('cp'), 'quantity', 1)
      when 'cpp' then jsonb_build_object('kind', 'credit_package', 'credit_package_id', pg_temp.t481_id('cpp'), 'quantity', 1) end);
  end loop;
  inv := create_invoice_with_details(pg_temp.t481_id('store'), p_cust, v_lines, jsonb_build_object('business_date', sg_today()::text)
           || case when p_discount is not null
                   then jsonb_build_object('manual_discount', p_discount, 'manual_discount_reason', 'T481 discount') else '{}'::jsonb end);
  perform record_invoice_settlement(inv, jsonb_build_object('receipts', jsonb_build_array(jsonb_build_object(
    'key', 'line-0', 'payment_method_id', pg_temp.t481_id('pm'),
    'amount', coalesce(p_first, (select total_amount from invoices where id = inv)),
    'payment_date', sg_today()::text)), 'arrangements', '[]'::jsonb), gen_random_uuid());
  return inv;
end $f$;
-- The receipts that still hold p_amount between them, as the Finance panel
-- splits a refund across them.
create function pg_temp.t481_sources(p_inv uuid, p_amount numeric) returns jsonb language plpgsql as $f$
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
-- Line N of an invoice: its credit lines first, then its voucher lines, its
-- therapy lines, then the rest (products, promotions), each by id.
create function pg_temp.t481_line(p_inv uuid, p_n int default 1) returns uuid language sql as $f$
  select id from invoice_items where invoice_id = p_inv
   order by case when line_kind in ('credit_package', 'premium_bundle') then 0 when line_kind = 'voucher' then 1
                 when therapy_service_id is not null then 2 else 3 end, id offset p_n - 1 limit 1 $f$;
-- The plan a guided step works from: its lines (kind:amount), sorted.
create function pg_temp.t481_planlines(p_inv uuid, p_action text) returns text language plpgsql as $f$
begin
  return (select coalesce(string_agg((l->>'line_kind') || ':' || ((l->>'amount')::numeric)::text, ' ' order by (l->>'line_kind'), (l->>'amount')::numeric), '-')
            from jsonb_array_elements(invoice_action_plan(p_inv, p_action, '[]')->'lines') l);
exception when others then return 'ERR';
end $f$;
-- The line the plan lists first (its kind; the order is not fixed).
create function pg_temp.t481_planfirst(p_inv uuid, p_action text) returns text language plpgsql as $f$
begin
  return (invoice_action_plan(p_inv, p_action, '[]')->'lines'->0->>'line_kind');
exception when others then return null;
end $f$;
-- The Finance panel's refund by line of a product (or promotion) line by
-- money, with the stock outcome it asks for of the units still out
-- unresolved: returned and sellable ('sellable'), damaged ('damaged') or not
-- returned ('kept'); none once a Cancel returned them (the panel then sends
-- no stock, InvoiceFinancePanel.tsx).
create function pg_temp.t481_backp(p_inv uuid, p_n int, p_amount numeric, p_how text) returns void language plpgsql as $f$
declare x uuid := pg_temp.t481_line(p_inv, p_n);
begin
  perform refund_invoice_recorded(p_inv, jsonb_build_array(jsonb_build_object('invoice_item_id', x, 'amount', p_amount)),
    pg_temp.t481_sources(p_inv, p_amount),
    (select coalesce(jsonb_agg(jsonb_build_object('movement_id', s->>'movement_id',
              'sellable_quantity', case when p_how = 'sellable' then (s->>'quantity')::int - (s->>'resolved_quantity')::int else 0 end,
              'damaged_quantity', case when p_how = 'damaged' then (s->>'quantity')::int - (s->>'resolved_quantity')::int else 0 end,
              'not_returned_quantity', case when p_how = 'kept' then (s->>'quantity')::int - (s->>'resolved_quantity')::int else 0 end)), '[]'::jsonb)
       from jsonb_array_elements(invoice_refund_options_before_sessions(p_inv)->'stock') s
      where (s->>'quantity')::int > (s->>'resolved_quantity')::int),
    'T481 product by line', gen_random_uuid());
end $f$;
-- The guided Refund in full / Cancel: requested, then an Owner approving it
-- as its plan reads then, a reason for every override, "Record refund paid".
create function pg_temp.t481_guided(p_pre text, p_inv uuid, p_action text) returns void language plpgsql as $f$
declare req jsonb; pl jsonb;
begin
  req := request_invoice_action_v2(p_inv, p_action, '[]', 'T481 ' || p_action, null, gen_random_uuid());
  pl := invoice_action_plan(p_inv, p_action, '[]');
  perform resolve_invoice_action_v2((req->>'request_id')::uuid, true, 'T481 approve', pl->>'plan_hash',
    (select coalesce(jsonb_agg(case when coalesce((o->>'amount_required')::boolean, false)
              then jsonb_build_object('code', o->>'code', 'reason', 'T481 override', 'amount', (o->>'default_amount')::numeric)
              else jsonb_build_object('code', o->>'code', 'reason', 'T481 override') end), '[]'::jsonb)
       from jsonb_array_elements(coalesce(pl->'overrides_required', '[]')) o),
    null, true);
end $f$;

-- ── The cases ───────────────────────────────────────────────────────────────
-- Steps (each one app call, then what its commit does; a refused step stops
-- the case, the refusal recorded):
--   sale R kinds [first]  the invoice form, then the Pay dialog (of first)
--   saled R kinds disc [first]  the same with an Owner's manual discount of disc
--   pay                   Record Payment of what is outstanding
--   payamt amt            Record Payment of amt
--   fixup amt             Correct payment of the latest receipt, amt more
--   back N amt            a refund by line of amt of credit line N's Paid credit
--   backv N units         a refund by line of that many voucher units of line N
--   backt N amt           a refund by line of therapy line N by money
--   backps|backpd|backpn N amt  a refund by line of product line N by money,
--                         the units out returned as sellable / damaged / not returned
--   backpsn N amt units   the same, that many of the units out returned as sellable
--   paidback amt          "Record refund paid" of amt with no line
--   cancel, reopen        Cancel; Reopen
--   refundall, guidedcancel  the guided Refund in full; Cancel with "Record refund paid"
--   storefix              the invoice form: moved to the other store, nothing else
--   qty N q               the invoice form: product line N's quantity q, nothing else
--   hand N                "Hand over items": N of the product now
--   wh                    "Fulfil from" the warehouse
--   order R n             the invoice form alone: n of the product, nothing paid
--   credit R              R buys cpp (paid credit that buys products) on an
--                         invoice of its own, paid in full
--   payw                  Record Payment of what is outstanding from the wallet
--                         (Credit Package Paid credit)
--   fixdate n             Correct payment of the latest receipt: its amount and
--                         method kept, its date n days earlier
create function pg_temp.t481_step(p_pre text, p_st text) returns text language plpgsql as $f$
declare w text[] := regexp_split_to_array(btrim(p_st), '\s+'); inv uuid := pg_temp.t481_id(p_pre || '/inv'); x uuid;
begin
  case w[1]
  when 'sale' then
    perform pg_temp.t481_put(p_pre || '/inv', pg_temp.t481_sale(pg_temp.t481_role(p_pre, w[2]), string_to_array(w[3], ','), w[4]::numeric));
  when 'saled' then
    perform pg_temp.t481_put(p_pre || '/inv', pg_temp.t481_sale(pg_temp.t481_role(p_pre, w[2]), string_to_array(w[3], ','), w[5]::numeric, w[4]::numeric));
  when 'pay' then
    if (invoice_financial_position(inv)->>'outstanding')::numeric > 0 then
      perform record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.t481_id('pm'),
        'amount', (invoice_financial_position(inv)->>'outstanding')::numeric)), gen_random_uuid());
    end if;
  when 'payamt' then
    perform record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.t481_id('pm'),
      'amount', w[2]::numeric)), gen_random_uuid());
  when 'fixup' then
    perform correct_invoice_payment(p.id, p.amount + w[2]::numeric, sg_today(), p.payment_method_id, 'T481 correct payment', gen_random_uuid())
      from (select q.* from invoice_payments q where q.invoice_id = inv and q.entry_kind in ('receipt', 'correction_replacement')
              and not exists (select 1 from invoice_payments r where r.corrects_payment_id = q.id)
            order by q.created_at desc, q.id desc limit 1) p;
    if not found then raise exception 'T481: no receipt to correct'; end if;
  when 'back' then
    perform refund_invoice_recorded(inv, jsonb_build_array(jsonb_build_object('invoice_item_id', b->>'invoice_item_id', 'amount', w[3]::numeric,
        'benefits', jsonb_build_array(jsonb_build_object('benefit_id', b->>'id', 'amount', w[3]::numeric)))),
      pg_temp.t481_sources(inv, w[3]::numeric), '[]'::jsonb, 'T481 credit by line', gen_random_uuid())
      from jsonb_array_elements(invoice_refund_options_before_sessions(inv)->'benefits') b
     where b->>'invoice_item_id' = pg_temp.t481_line(inv, w[2]::int)::text and b->>'benefit_kind' = 'paid'
     limit 1;
    if not found then raise exception 'T481: nothing to refund on that line'; end if;
  when 'backv' then
    x := pg_temp.t481_line(inv, w[2]::int);
    perform refund_invoice_recorded(inv, jsonb_build_array(jsonb_build_object('invoice_item_id', x, 'amount', b.amt,
        'benefits', jsonb_build_array(jsonb_build_object('benefit_id', b.id, 'amount', b.amt)))),
      pg_temp.t481_sources(inv, b.amt), '[]'::jsonb, 'T481 voucher by line', gen_random_uuid())
      from (select o->>'id' as id, round(w[3]::int * (o->>'paid_value')::numeric / (o->>'granted_value')::numeric, 2) as amt
              from jsonb_array_elements(invoice_refund_options_before_sessions(inv)->'benefits') o
             where o->>'invoice_item_id' = x::text and o->>'benefit_kind' = 'voucher' and (o->>'max_refund')::numeric > 0
             order by (o->>'max_refund')::numeric desc limit 1) b;
    if not found then raise exception 'T481: no voucher to refund on that line'; end if;
  when 'backt' then
    x := pg_temp.t481_line(inv, w[2]::int);
    perform refund_invoice_recorded(inv, jsonb_build_array(jsonb_build_object('invoice_item_id', x, 'amount', w[3]::numeric)),
      pg_temp.t481_sources(inv, w[3]::numeric), '[]'::jsonb, 'T481 by line', gen_random_uuid());
  when 'backps' then perform pg_temp.t481_backp(inv, w[2]::int, w[3]::numeric, 'sellable');
  when 'backpd' then perform pg_temp.t481_backp(inv, w[2]::int, w[3]::numeric, 'damaged');
  when 'backpn' then perform pg_temp.t481_backp(inv, w[2]::int, w[3]::numeric, 'kept');
  when 'backpsn' then
    -- the same, that many of the units out returned as sellable (the review
    -- of 2 Nov 2026: S$66.66 of a 3-unit S$100.00 line, its 2 units back)
    perform refund_invoice_recorded(inv, jsonb_build_array(jsonb_build_object('invoice_item_id', pg_temp.t481_line(inv, w[2]::int), 'amount', w[3]::numeric)),
      pg_temp.t481_sources(inv, w[3]::numeric),
      (select coalesce(jsonb_agg(jsonb_build_object('movement_id', s->>'movement_id',
                'sellable_quantity', least(w[4]::int, (s->>'quantity')::int - (s->>'resolved_quantity')::int),
                'damaged_quantity', 0, 'not_returned_quantity', 0)), '[]'::jsonb)
         from jsonb_array_elements(invoice_refund_options_before_sessions(inv)->'stock') s
        where (s->>'quantity')::int > (s->>'resolved_quantity')::int),
      'T481 product by line', gen_random_uuid());
  when 'paidback' then
    perform refund_invoice_recorded(inv, jsonb_build_array(jsonb_build_object('amount', w[2]::numeric)),
      pg_temp.t481_sources(inv, w[2]::numeric), '[]'::jsonb, 'T481 refund paid', gen_random_uuid());
  when 'cancel' then perform cancel_invoice_recorded(inv, 'T481 cancel', gen_random_uuid());
  when 'reopen' then perform reopen_invoice(inv, 'T481 reopen', gen_random_uuid());
  when 'refundall' then perform pg_temp.t481_guided(p_pre, inv, 'refund_full');
  when 'guidedcancel' then perform pg_temp.t481_guided(p_pre, inv, 'cancel');
  when 'storefix' then
    perform correct_invoice(inv, (select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('invoice_item_id', it.id, 'kind', it.line_kind,
              'credit_package_id', it.credit_package_id, 'voucher_id', it.voucher_id, 'therapy_service_id', it.therapy_service_id,
              'product_id', it.product_id, 'promotion_id', it.promotion_id, 'quantity', it.quantity, 'unit_price', it.unit_price)) order by it.id)
                                  from invoice_items it where it.invoice_id = inv),
      jsonb_build_object('expected_edit_count', (select edit_count from invoices where id = inv),
        'customer_id', (select customer_id from invoices where id = inv), 'store_id', pg_temp.t481_id('store2')),
      'T481 wrong store', gen_random_uuid());
  when 'hand' then
    perform record_invoice_handover(inv, jsonb_build_object('items', jsonb_build_array(jsonb_build_object(
      'product_id', pg_temp.t481_id('prod'), 'qty', w[2]::int))), gen_random_uuid());
  when 'wh' then perform set_invoice_fulfilment_warehouse(inv, pg_temp.t481_id('wh'));
  when 'qty' then
    -- (F1) the invoice form as storefix sends it, the invoice's own store,
    -- product line N's quantity changed
    x := pg_temp.t481_line(inv, w[2]::int);
    perform correct_invoice(inv, (select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('invoice_item_id', it.id, 'kind', it.line_kind,
              'credit_package_id', it.credit_package_id, 'voucher_id', it.voucher_id, 'therapy_service_id', it.therapy_service_id,
              'product_id', it.product_id, 'promotion_id', it.promotion_id,
              'quantity', case when it.id = x then w[3]::int else it.quantity end, 'unit_price', it.unit_price)) order by it.id)
                                  from invoice_items it where it.invoice_id = inv),
      jsonb_build_object('expected_edit_count', (select edit_count from invoices where id = inv),
        'customer_id', (select customer_id from invoices where id = inv), 'store_id', (select store_id from invoices where id = inv)),
      'T481 quantity wrong', gen_random_uuid());
  when 'order' then
    -- (E4w3) the invoice form alone
    perform pg_temp.t481_put(p_pre || '/inv', create_invoice_with_details(pg_temp.t481_id('store'), pg_temp.t481_role(p_pre, w[2]),
      jsonb_build_array(jsonb_build_object('kind', 'product', 'product_id', pg_temp.t481_id('prod'), 'quantity', w[3]::int)),
      jsonb_build_object('business_date', sg_today()::text)));
  when 'credit' then
    perform pg_temp.t481_put(p_pre || '/cpinv', pg_temp.t481_sale(pg_temp.t481_role(p_pre, w[2]), array['cpp']));
  when 'payw' then
    perform record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.t481_id('wallet'),
      'amount', (invoice_financial_position(inv)->>'outstanding')::numeric)), gen_random_uuid());
  when 'fixdate' then
    perform correct_invoice_payment(p.id, p.amount, sg_today() - w[2]::int, p.payment_method_id, 'T481 payment date', gen_random_uuid())
      from (select q.* from invoice_payments q where q.invoice_id = inv and q.entry_kind in ('receipt', 'correction_replacement')
              and not exists (select 1 from invoice_payments r where r.corrects_payment_id = q.id)
            order by q.created_at desc, q.id desc limit 1) p;
    if not found then raise exception 'T481: no receipt to correct'; end if;
  else raise exception 'T481: unknown step %', p_st;
  end case;
  perform pg_temp.t481_commit();
  return null;
exception when others then
  return btrim(p_st) || ': ' || sqlerrm;
end $f$;
-- What a case ends with (above). 'dstore' and 'dwh' are what its steps took
-- from the stores and from the warehouse (t481_run reads them around them).
create temp table t481_qty(pre text primary key, store0 int, wh0 int);
create function pg_temp.t481_outcome(p_pre text, p_err text) returns jsonb language plpgsql as $f$
declare inv uuid := pg_temp.t481_id(p_pre || '/inv'); g jsonb; v jsonb; d numeric;
begin
  begin g := invoice_goods_status(inv); exception when others then g := jsonb_build_object('err', sqlerrm); end;
  begin d := coalesce((invoice_financial_position(inv)->>'refund_due')::numeric, 0); exception when others then d := null; end;
  select jsonb_build_object(
    'status', i.status::text,
    'net', invoice_net_received(i.id),
    'due', d,
    'fulfil', (select count(*) from audit_logs a where a.table_name = 'invoices' and a.record_id = i.id
                                                   and a.action = 'invoice_fulfilled_from_warehouse'),
    'stock', (select coalesce(string_agg(m.k, ', ' order by m.k), '-')
                from (select x.movement_type::text || ' ' || sum(x.quantity) as k from stock_movements x
                       where x.invoice_id = i.id group by x.movement_type) m),
    'out', (select coalesce(sum(case when m.movement_type::text = 'store_sale' then m.quantity
                                     when m.movement_type::text in ('invoice_cancel_return', 'invoice_refund_return') then -m.quantity else 0 end), 0)
              from stock_movements m where m.invoice_id = i.id),
    'td', (select coalesce(sum(t.quantity), 0) from invoice_stock_to_deduct(i.id) t where t.kind = 'product'),
    -- (both sorted: the order the Goods panel and the stock report list
    -- their rows in is not fixed)
    'goods', coalesce((select string_agg((p->>'required') || '/' || (p->>'collected') || '/' || (p->>'to_collect'), ','
                                         order by (p->>'required') || '/' || (p->>'collected') || '/' || (p->>'to_collect'))
                         from jsonb_array_elements(g->'products') p), coalesce(g->>'err', '-')),
    'gap', (select coalesce(string_agg(x.required || '/' || x.net_recorded || '/' || x.missing, ','
                                       order by x.required || '/' || x.net_recorded || '/' || x.missing), '-')
              from invoice_stock_gaps(i.invoice_no) x),
    'dstore', (select coalesce(sum(current_qty), 0) from store_inventory where product_id = pg_temp.t481_id('prod'))
              - (select store0 from t481_qty where pre = p_pre),
    'dwh', (select coalesce(sum(current_qty), 0) from warehouse_inventory where product_id = pg_temp.t481_id('prod'))
           - (select wh0 from t481_qty where pre = p_pre),
    'prref', (select coalesce(sum((x->>'amount')::numeric), 0) from invoice_refunds r cross join lateral jsonb_array_elements(coalesce(r.outcome->'lines', '[]')) x
                join invoice_items it on it.id = (x->>'invoice_item_id')::uuid
               where r.invoice_id = i.id and it.line_kind::text in ('product', 'promotion')),
    'prref_since', (select coalesce(sum((x->>'amount')::numeric), 0) from invoice_refunds r cross join lateral jsonb_array_elements(coalesce(r.outcome->'lines', '[]')) x
                      join invoice_items it on it.id = (x->>'invoice_item_id')::uuid
                     where r.invoice_id = i.id and it.line_kind::text in ('product', 'promotion')
                       and (i.reopened_at is null or r.created_at > i.reopened_at)),
    'sess', coalesce((select string_agg(format('%s/%s r%s c%s %s', s.quantity_purchased - s.quantity_used - s.quantity_refunded - s.quantity_cancelled,
                                                s.quantity_purchased, s.quantity_refunded, s.quantity_cancelled, s.status), ', ' order by s.created_at, s.id)
                        from customer_therapy_sessions s where s.invoice_id = i.id and s.is_current), '-'),
    'holds', (select coalesce(sum(l.remaining_amount), 0)::numeric(12,2)::text
                     || coalesce('/' || nullif((select sum(q.quantity) from customer_reward_vouchers q where q.customer_id = i.customer_id and q.status = 'held'), 0)::text, '')
                from customer_credit_lots l where l.customer_id = i.customer_id),
    'issue', case when i.status::text in ('cancelled', 'refunded')
                  then (select coalesce(sum((s->>'quantity')::int), 0) from jsonb_array_elements(invoice_reopen_preview(i.id)->'stock_to_issue') s
                         where s->>'kind' = 'product') end,
    'plan', (select p.lines from t481_plan p where p.pre = p_pre),
    'error', p_err)
    into v from invoices i where i.id = inv;
  return v;
end $f$;
-- A case's steps (all), stopping at a refusal; its outcome kept in t481_res
-- under p_phase.
create function pg_temp.t481_run(p_phase text, p_case text, p_steps text) returns jsonb language plpgsql as $f$
declare v_pre text := p_phase || '/' || p_case; st text[] := string_to_array(p_steps, ';'); i int; v_err text; v_out jsonb; inv uuid;
begin
  insert into t481_qty values (v_pre, (select coalesce(sum(current_qty), 0) from store_inventory where product_id = pg_temp.t481_id('prod')),
                                      (select coalesce(sum(current_qty), 0) from warehouse_inventory where product_id = pg_temp.t481_id('prod')))
    on conflict (pre) do update set store0 = excluded.store0, wh0 = excluded.wh0;
  for i in 1 .. cardinality(st) loop
    exit when v_err is not null;
    continue when btrim(st[i]) = '';
    inv := pg_temp.t481_id(v_pre || '/inv');
    -- The plan a guided step works from, read as it reads it (kept whether
    -- the step then goes through or is refused): its lines, and the one it
    -- lists first.
    if inv is not null and btrim(st[i]) in ('refundall', 'guidedcancel') then
      insert into t481_plan values (v_pre, pg_temp.t481_planlines(inv, case btrim(st[i]) when 'refundall' then 'refund_full' else 'cancel' end),
                                   pg_temp.t481_planfirst(inv, case btrim(st[i]) when 'refundall' then 'refund_full' else 'cancel' end))
        on conflict (pre) do update set lines = excluded.lines, first = excluded.first;
    end if;
    v_err := pg_temp.t481_step(v_pre, st[i]);
    if v_err is not null then
      insert into t481_err values (v_pre, v_err, i) on conflict (pre) do update set err = excluded.err, at = excluded.at;
    end if;
  end loop;
  v_out := pg_temp.t481_outcome(v_pre, v_err);
  insert into t481_res values (p_phase, p_case, v_out) on conflict (phase, k) do update set v = excluded.v;
  return v_out;
end $f$;
-- The line the case's last guided plan listed first (its kind).
create function pg_temp.t481_first(p_phase text, p_case text) returns text language sql as $f$
  select first from t481_plan where pre = p_phase || '/' || p_case $f$;
-- Whether an outcome has what is expected: each key equal, a key ending in
-- '~' as a LIKE pattern of that key's text.
create function pg_temp.t481_meets(p_out jsonb, p_exp jsonb) returns boolean language sql as $f$
  select coalesce(bool_and(case
           when e.key like '%~' then coalesce(p_out->>left(e.key, -1), '') like (e.value #>> '{}')
           when jsonb_typeof(e.value) = 'number' then coalesce((p_out->>e.key)::numeric = (e.value #>> '{}')::numeric, false)
           else (p_out->e.key) is not distinct from e.value end), true)
    from jsonb_each(p_exp) e $f$;
create function pg_temp.t481_diff(p_out jsonb, p_exp jsonb) returns text language sql as $f$
  select string_agg(e.key || ': wanted ' || e.value::text || ', got ' || coalesce(p_out->left(e.key, case when e.key like '%~' then -1 else 1000 end), 'null')::text, '; ')
    from jsonb_each(p_exp) e where not pg_temp.t481_meets(p_out, jsonb_build_object(e.key, e.value)) $f$;

-- The cases: (k, kind, steps, what 481 gives, what 478 and 479 gave where
-- it differs). kind: 'fixed' (expect0 before 481, expect after it),
-- 'control' (expect before and after, and exactly the same, every key),
-- 'known' (a NOT COVERED item: as a control).
create temp table t481_cases(k text primary key, kind text not null, steps text not null, expect jsonb not null, expect0 jsonb, ord serial);
insert into t481_cases(k, kind, steps, expect, expect0) values
-- cancelled, refunded by line after the reopening, then paid
('VPR', 'fixed', 'sale A pr,v; cancel; backv 1 1; reopen; refundall; pay',
  '{"status":"paid","net":30,"stock":"invoice_cancel_return 1, store_sale 1","out":0,"td":0,"dstore":0,"holds":"0.00/1","goods":"1/0/0","gap":"-","error":null}',
  '{"status":"paid","net":30,"stock":"invoice_cancel_return 1, store_sale 2","out":1,"td":0,"dstore":-1,"holds":"0.00/1","goods":"1/1/0","gap":"-","error":null}'),
('CPR', 'fixed', 'sale A pr,cp; cancel; back 1 50; reopen; refundall; pay',
  '{"status":"paid","net":50,"stock":"invoice_cancel_return 1, store_sale 1","out":0,"td":0,"dstore":0,"holds":"50.00","goods":"1/0/0","error":null}',
  '{"status":"paid","net":50,"stock":"invoice_cancel_return 1, store_sale 2","out":1,"td":0,"dstore":-1,"holds":"50.00","goods":"1/1/0","error":null}'),
('PRxk', 'fixed', 'sale A pr,th; cancel; backps 2 40; reopen; backps 2 40; pay',
  '{"status":"paid","net":60,"sess":"3/3 r0 c0 available","stock":"invoice_cancel_return 1, store_sale 1","out":0,"td":0,"dstore":0,"prref":80,"error":null}',
  '{"status":"paid","net":60,"sess":"3/3 r0 c0 available","stock":"invoice_cancel_return 1, store_sale 2","out":1,"td":0,"dstore":-1,"prref":80,"error":null}'),
('PRxk2', 'fixed', 'sale A th,pr; cancel; backps 2 40; reopen; backps 2 40; pay',
  '{"status":"paid","net":60,"sess":"3/3 r0 c0 available","stock":"invoice_cancel_return 1, store_sale 1","out":0,"td":0,"dstore":0,"error":null}',
  '{"status":"paid","net":60,"sess":"3/3 r0 c0 available","stock":"invoice_cancel_return 1, store_sale 2","out":1,"td":0,"dstore":-1,"error":null}'),
('PRn1', 'fixed', 'sale A pr,th; cancel; backt 1 20; reopen; refundall; pay',
  '{"status":"paid","net":20,"sess":"1/3 r2 c0 available","stock":"invoice_cancel_return 1, store_sale 1","out":0,"td":0,"dstore":0,"plan":"product:40.00 therapy:40.00","error":null}',
  '{"status":"paid","net":20,"sess":"1/3 r2 c0 available","stock":"invoice_cancel_return 1, store_sale 2","out":1,"td":0,"dstore":-1,"plan":"product:40.00 therapy:40.00","error":null}'),
('PRn2', 'fixed', 'sale A th,pr; cancel; backt 1 20; reopen; refundall; pay',
  '{"status":"paid","net":20,"sess":"1/3 r2 c0 available","stock":"invoice_cancel_return 1, store_sale 1","out":0,"td":0,"dstore":0,"error":null}',
  '{"status":"paid","net":20,"sess":"1/3 r2 c0 available","stock":"invoice_cancel_return 1, store_sale 2","out":1,"td":0,"dstore":-1,"error":null}'),
('PV1', 'fixed', 'sale A pr,v; cancel; backv 1 1; reopen; backps 2 40; pay',
  '{"status":"paid","stock":"invoice_cancel_return 1, store_sale 1","out":0,"td":0,"dstore":0,"error":null}',
  '{"status":"paid","stock":"invoice_cancel_return 1, store_sale 2","out":1,"td":0,"dstore":-1,"error":null}'),
('P3a', 'fixed', 'sale A pr,th; cancel; backps 2 40; backt 1 60; reopen; payamt 40; refundall; pay',
  '{"status":"paid","net":60,"sess":"3/3 r0 c0 available","stock":"invoice_cancel_return 1, store_sale 1","out":0,"td":0,"dstore":0,"prref":80,"plan":"product:40.00 therapy:0.00","error":null}',
  '{"status":"paid","net":60,"sess":"3/3 r0 c0 available","stock":"invoice_cancel_return 1, store_sale 2","out":1,"td":0,"dstore":-1,"prref":80,"plan":"product:40.00 therapy:0.00","error":null}'),
('P3b', 'fixed', 'sale A th,pr; cancel; backps 2 40; backt 1 60; reopen; payamt 40; refundall; pay',
  '{"status":"paid","net":60,"sess":"3/3 r0 c0 available","stock":"invoice_cancel_return 1, store_sale 1","out":0,"td":0,"dstore":0,"prref":80,"error":null}',
  '{"status":"paid","net":60,"sess":"3/3 r0 c0 available","stock":"invoice_cancel_return 1, store_sale 2","out":1,"td":0,"dstore":-1,"prref":80,"error":null}'),
-- paid in part, refunded by line, then settled
('PRpp', 'fixed', 'sale A pr,v 50; backps 2 40; pay',
  '{"status":"paid","net":60,"stock":"-","out":0,"td":0,"dstore":0,"holds":"0.00/2","goods":"1/0/0","error":null}',
  '{"status":"paid","net":60,"stock":"store_sale 1","out":1,"td":0,"dstore":-1,"holds":"0.00/2","goods":"1/1/0","error":null}'),
('L6', 'fixed', 'sale A pr,v 50; backps 2 40; fixup 50',
  '{"status":"paid","net":60,"stock":"-","out":0,"td":0,"dstore":0,"error":null}',
  '{"status":"paid","net":60,"stock":"store_sale 1","out":1,"td":0,"dstore":-1,"error":null}'),
('PRM', 'fixed', 'sale A prm,v 100; backps 2 70; pay',
  '{"status":"paid","net":60,"stock":"-","out":0,"td":0,"dstore":0,"goods":"2/0/0","error":null}',
  '{"status":"paid","net":60,"stock":"store_sale 2","out":2,"td":0,"dstore":-2,"goods":"2/2/0","error":null}'),
('L7', 'fixed', 'sale A pr2,v 80; backps 2 40; pay',
  '{"status":"paid","net":100,"stock":"store_sale 1","out":1,"td":0,"dstore":-1,"goods":"2/1/0","error":null}',
  '{"status":"paid","net":100,"stock":"store_sale 2","out":2,"td":0,"dstore":-2,"goods":"2/2/0","error":null}'),
('M2', 'fixed', 'sale A pr,pr,v 80; backps 3 40; pay',
  '{"status":"paid","net":100,"stock":"store_sale 1","out":1,"td":0,"dstore":-1,"goods":"2/1/0","error":null}',
  '{"status":"paid","net":100,"stock":"store_sale 2","out":2,"td":0,"dstore":-2,"goods":"2/2/0","error":null}'),
('W2', 'fixed', 'sale A pr,v 50; wh; backps 2 40; pay',
  '{"status":"paid","net":60,"stock":"-","out":0,"td":0,"dstore":0,"dwh":0,"error":null}',
  '{"status":"paid","net":60,"stock":"store_sale 1","out":1,"td":0,"dstore":0,"dwh":-1,"error":null}'),
-- handed over before full payment
('H2', 'fixed', 'sale A pr,v 50; hand 1; backps 2 40; pay',
  '{"status":"paid","net":60,"stock":"invoice_refund_return 1, store_sale 1","out":0,"td":0,"dstore":0,"gap":"-","error":null}',
  '{"status":"paid","net":60,"stock":"invoice_refund_return 1, store_sale 2","out":1,"td":0,"dstore":-1,"gap":"1/2/-1","error":null}'),
('H4', 'fixed', 'sale A pr2,v 80; hand 1; backps 2 40; pay',
  '{"status":"paid","net":100,"stock":"invoice_refund_return 1, store_sale 2","out":1,"td":0,"dstore":-1,"goods":"2/1/0","gap":"-","error":null}',
  '{"status":"paid","net":100,"stock":"invoice_refund_return 1, store_sale 3","out":2,"td":0,"dstore":-2,"goods":"2/2/0","gap":"2/3/-1","error":null}'),
('H3', 'fixed', 'sale A pr,v 50; backps 2 40; hand 1',
  '{"status":"partially_paid","net":10,"stock":"-","out":0,"td":0,"dstore":0,"goods":"1/0/0","error~":"hand 1: Only 0 of %"}',
  '{"status":"partially_paid","net":10,"stock":"store_sale 1","out":1,"td":0,"dstore":-1,"goods":"1/1/0","error":null}'),
-- paid, refunded by line with the unit returned (written off)
('PRpd', 'fixed', 'sale A pr,v; backps 2 40',
  '{"status":"paid","net":60,"stock":"invoice_refund_return 1, store_sale 1","out":0,"td":0,"dstore":0,"goods":"1/0/0","error":null}',
  '{"status":"paid","net":60,"stock":"invoice_refund_return 1, store_sale 1","out":0,"td":1,"dstore":0,"goods":"1/0/0","error":null}'),
('PRpds', 'fixed', 'sale A pr,v; backps 2 40; storefix',
  '{"status":"paid","net":60,"stock":"invoice_refund_return 1, store_sale 1","out":0,"td":0,"dstore":0,"gap":"-","error":null}',
  '{"status":"paid","net":60,"stock":"invoice_refund_return 1, store_sale 2","out":1,"td":0,"dstore":-1,"gap":"1/2/-1","error":null}'),
('PRpdd', 'fixed', 'sale A pr,v; backpd 2 40; storefix',
  '{"status":"paid","net":60,"stock":"store_sale 1","out":1,"td":0,"dstore":-1,"gap":"-","goods":"1/0/0","error":null}',
  '{"status":"paid","net":60,"stock":"store_sale 2","out":2,"td":0,"dstore":-2,"gap":"1/2/-1","goods":"1/1/0","error":null}'),
-- the review of 2 Nov 2026: a unit whose paid value is not whole cents. 3 of
-- the product and the 2 vouchers with an Owner's S$30 discount (S$150; the
-- product's line S$100.00, S$33.333 a unit), S$100 paid, S$66.66 of it
-- refunded by line (RD1; in two refunds of S$33.33, RD4; three, RD10: all 3
-- units), then the rest paid: before this rule the count lost a unit to the
-- cent (one taken again); paid in full, 2 units returned with S$66.66 (RD6:
-- nothing left to take; RD6s, the store then moved: 1 out); the reopened
-- route (RD8); a 2-unit line of S$66.67 (S$33.335 a unit), S$33.33 refunded
-- (RW67: 1 unit, as before this rule) or S$66.66 (RW67b: 2); a 4-unit line
-- of S$100.00 (S$25.00 a unit), S$99.98 refunded (RW25: 3 units, nothing to
-- round).
('RD1', 'fixed', 'saled A pr3,v 30 100; backps 2 66.66; pay',
  '{"status":"paid","net":83.34,"stock":"store_sale 1","out":1,"td":0,"dstore":-1,"goods":"3/1/0","gap":"-","error":null}',
  '{"status":"paid","net":83.34,"stock":"store_sale 3","out":3,"td":0,"dstore":-3,"goods":"3/3/0","gap":"-","error":null}'),
('RD4', 'fixed', 'saled A pr3,v 30 100; backps 2 33.33; backps 2 33.33; pay',
  '{"status":"paid","net":83.34,"stock":"store_sale 1","out":1,"td":0,"dstore":-1,"goods":"3/1/0","gap":"-","error":null}',
  '{"status":"paid","net":83.34,"stock":"store_sale 3","out":3,"td":0,"dstore":-3,"goods":"3/3/0","gap":"-","error":null}'),
('RD10', 'fixed', 'saled A pr3,v 30 100; backps 2 33.33; backps 2 33.33; backps 2 33.33; pay',
  '{"status":"paid","net":50.01,"stock":"-","out":0,"td":0,"dstore":0,"goods":"3/0/0","gap":"-","error":null}',
  '{"status":"paid","net":50.01,"stock":"store_sale 3","out":3,"td":0,"dstore":-3,"goods":"3/3/0","gap":"-","error":null}'),
('RD6', 'fixed', 'saled A pr3,v 30; backpsn 2 66.66 2',
  '{"status":"paid","net":83.34,"stock":"invoice_refund_return 2, store_sale 3","out":1,"td":0,"dstore":-1,"goods":"3/1/0","gap":"-","error":null}',
  '{"status":"paid","net":83.34,"stock":"invoice_refund_return 2, store_sale 3","out":1,"td":2,"dstore":-1,"goods":"3/1/0","gap":"-","error":null}'),
('RD6s', 'fixed', 'saled A pr3,v 30; backpsn 2 66.66 2; storefix',
  '{"status":"paid","net":83.34,"stock":"invoice_cancel_return 1, invoice_refund_return 2, store_sale 4","out":1,"td":0,"dstore":-1,"goods":"3/1/0","gap":"-","error":null}',
  '{"status":"paid","net":83.34,"stock":"invoice_cancel_return 1, invoice_refund_return 2, store_sale 6","out":3,"td":0,"dstore":-3,"goods":"3/3/0","gap":"3/5/-2","error":null}'),
('RD8', 'fixed', 'saled A pr3,v 30; cancel; paidback 50; reopen; backps 2 66.66; pay',
  '{"status":"paid","net":83.34,"stock":"invoice_cancel_return 3, store_sale 4","out":1,"td":0,"dstore":-1,"goods":"3/1/0","gap":"-","error":null}',
  '{"status":"paid","net":83.34,"stock":"invoice_cancel_return 3, store_sale 6","out":3,"td":0,"dstore":-3,"goods":"3/3/0","gap":"-","error":null}'),
('RW67', 'fixed', 'saled A pr2,v 23.33 50; backps 2 33.33; pay',
  '{"status":"paid","net":83.34,"stock":"store_sale 1","out":1,"td":0,"dstore":-1,"goods":"2/1/0","gap":"-","error":null}',
  '{"status":"paid","net":83.34,"stock":"store_sale 2","out":2,"td":0,"dstore":-2,"goods":"2/2/0","gap":"-","error":null}'),
('RW67b', 'fixed', 'saled A pr2,v 23.33 70; backps 2 66.66; pay',
  '{"status":"paid","net":50.01,"stock":"-","out":0,"td":0,"dstore":0,"goods":"2/0/0","gap":"-","error":null}',
  '{"status":"paid","net":50.01,"stock":"store_sale 2","out":2,"td":0,"dstore":-2,"goods":"2/2/0","gap":"-","error":null}'),
('RW25', 'fixed', 'saled A pr4,v 82.50 100; backps 2 99.98; pay',
  '{"status":"paid","net":37.52,"stock":"store_sale 1","out":1,"td":0,"dstore":-1,"goods":"4/1/0","gap":"-","error":null}',
  '{"status":"paid","net":37.52,"stock":"store_sale 4","out":4,"td":0,"dstore":-4,"goods":"4/4/0","gap":"-","error":null}'),
-- NOT COVERED 12 (checking RD6, 2 Nov 2026; not 481's): more units returned
-- with a refund by line than its money pays for. S$10 of the S$40 product
-- refunded, its unit returned as sellable: still reported to take on the
-- paid invoice (RDp1), and a store move takes it again (RDp2), as before
-- 481; S$33.33 of the 3-unit S$100.00 line, 2 units returned: 1 unit
-- counted, so 1 still to take (RDp3; before 481, 2).
('RDp1', 'known', 'sale A pr,v; backps 2 10',
  '{"status":"paid","net":90,"stock":"invoice_refund_return 1, store_sale 1","out":0,"td":1,"goods":"1/0/0","gap":"-","error":null}', null),
('RDp2', 'known', 'sale A pr,v; backps 2 10; storefix',
  '{"status":"paid","net":90,"stock":"invoice_refund_return 1, store_sale 2","out":1,"td":0,"goods":"1/1/0","gap":"1/2/-1","error":null}', null),
('RDp3', 'fixed', 'saled A pr3,v 30; backpsn 2 33.33 2',
  '{"status":"paid","net":116.67,"stock":"invoice_refund_return 2, store_sale 3","out":1,"td":1,"goods":"3/1/0","gap":"-","error":null}',
  '{"status":"paid","net":116.67,"stock":"invoice_refund_return 2, store_sale 3","out":1,"td":2,"goods":"3/1/0","gap":"-","error":null}'),
-- NOT COVERED 13 (the review of 2 Nov 2026; for the Owner): an Edit Invoice
-- that cuts a line a refund by line paid back. 3 of the product paid, one
-- unit's S$40 refunded by line with the unit returned, then the line cut to
-- 2: the correction puts back what is out and takes the line again, before
-- 481 its 2 (the stock report then listing a surplus of 1), from 481 1 (the
-- refund counted as its unit); the money the same (S$40 shown as due back).
-- Known, so not 'fixed': which is right depends on what the cut meant.
('F1', 'known', 'sale A pr3; backpsn 1 40 1; qty 1 2',
  '{"status":"paid","net":80,"due":40,"stock":"invoice_cancel_return 2, invoice_refund_return 1, store_sale 4","out":1,"td":0,"dstore":-1,"goods":"2/1/0","gap":"-","error":null}',
  '{"status":"paid","net":80,"due":40,"stock":"invoice_cancel_return 2, invoice_refund_return 1, store_sale 5","out":2,"td":0,"dstore":-2,"goods":"2/2/0","gap":"2/3/-1","error":null}'),
-- controls: what is not refunded is taken as before
('L1', 'control', 'sale A pr,v', '{"status":"paid","net":100,"stock":"store_sale 1","out":1,"td":0,"dstore":-1,"error":null}', null),
('L2', 'control', 'sale A pr,v 50; pay', '{"status":"paid","net":100,"stock":"store_sale 1","out":1,"td":0,"dstore":-1,"error":null}', null),
('L3', 'control', 'sale A pr,th; cancel; reopen; pay',
  '{"status":"paid","net":100,"stock":"invoice_cancel_return 1, store_sale 2","out":1,"td":0,"dstore":-1,"error":null}', null),
('L4', 'control', 'sale A pr,v; cancel; backps 2 40; reopen; pay',
  '{"status":"paid","net":100,"stock":"invoice_cancel_return 1, store_sale 2","out":1,"td":0,"dstore":-1,"prref":40,"prref_since":0,"error":null}', null),
('PRx1p', 'control', 'sale A pr,th; cancel; backps 2 40; reopen; pay',
  '{"status":"paid","net":100,"sess":"3/3 r0 c0 available","stock":"invoice_cancel_return 1, store_sale 2","out":1,"td":0,"dstore":-1,"error":null}', null),
('L5', 'control', 'sale A pr,v 50; payamt 10; fixup 40', '{"status":"paid","net":100,"stock":"store_sale 1","out":1,"td":0,"dstore":-1,"error":null}', null),
('L8', 'known', 'sale A pr2,v 80; backps 2 20; pay',
  '{"status":"paid","net":120,"stock":"store_sale 2","out":2,"td":0,"dstore":-2,"goods":"2/2/0","error":null}', null),
('PRM2', 'known', 'sale A prm,v 100; backps 2 35; pay',
  '{"status":"paid","net":95,"stock":"store_sale 2","out":2,"td":0,"dstore":-2,"error":null}', null),
('H1', 'control', 'sale A pr,v 50; hand 1; pay', '{"status":"paid","net":100,"stock":"store_sale 1","out":1,"td":0,"dstore":-1,"error":null}', null),
('W1', 'control', 'sale A pr,v 50; wh; pay', '{"status":"paid","net":100,"stock":"store_sale 1","out":1,"td":0,"dstore":0,"dwh":-1,"error":null}', null),
('W3', 'known', 'sale A pr,v 50; wh; pay; cancel; reopen',
  '{"status":"paid","net":100,"stock":"invoice_cancel_return 1, store_sale 2","out":1,"td":0,"dstore":1,"dwh":-2,"error":null}', null),
('W4', 'known', 'sale A pr,v 50; wh; pay; cancel; backps 2 40; reopen; pay',
  '{"status":"paid","net":100,"stock":"invoice_cancel_return 1, store_sale 2","out":1,"td":0,"dstore":1,"dwh":-2,"error":null}', null),
-- NOT COVERED 3, widened (the review of 2 Nov 2026): any move back to paid of
-- a settled warehouse invoice sends it again. Paid from the wallet (Credit
-- Package Paid credit), then one Correct payment of the receipt's date
-- alone (the status goes to partially paid and back inside that call): the
-- warehouse -2, the store +1, two sends; the money and the credit unchanged
('E4w3', 'known', 'credit A; order A 1; wh; payw; fixdate 1',
  '{"status":"paid","net":40,"due":0,"stock":"store_sale 1","out":1,"td":0,"dstore":1,"dwh":-2,"fulfil":2,"holds":"60.00","error":null}', null),
('PRpdn', 'control', 'sale A pr,v; backpn 2 40; storefix',
  '{"status":"paid","net":60,"stock":"store_sale 1","out":1,"td":0,"dstore":-1,"goods":"1/1/0","gap":"-","error":null}', null),
('PRc', 'control', 'sale A pr,v; cancel; backps 2 40',
  '{"status":"cancelled","net":60,"stock":"invoice_cancel_return 1, store_sale 1","out":0,"td":1,"dstore":0,"issue":1,"error":null}', null),
('PRcb', 'control', 'sale A pr,v; cancel; backps 2 40; reopen',
  '{"status":"partially_paid","net":60,"stock":"invoice_cancel_return 1, store_sale 1","out":0,"td":1,"dstore":0,"goods":"1/0/1","error":null}', null),
('RC1', 'control', 'sale A pr,v; backps 2 40; cancel; fixup 40; reopen',
  '{"status":"paid","net":100,"stock":"invoice_refund_return 1, store_sale 2","out":1,"td":0,"dstore":-1,"gap":"1/2/-1","error":null}', null),
('RC2', 'control', 'sale A pr,v; cancel; backps 2 40; fixup 40; reopen',
  '{"status":"paid","net":100,"stock":"invoice_cancel_return 1, store_sale 2","out":1,"td":0,"dstore":-1,"error":null}', null),
('CPr', 'known', 'sale A pr,v; backps 2 40; cancel; reopen; pay',
  '{"status":"paid","net":100,"stock":"invoice_refund_return 1, store_sale 2","out":1,"td":0,"dstore":-1,"gap":"1/2/-1","error":null}', null),
('CPd', 'known', 'sale A pr,v; backps 2 40; cancel; reopen; fixup 40',
  '{"status":"paid","net":100,"stock":"invoice_refund_return 1, store_sale 1","out":0,"td":1,"dstore":0,"gap":"-","error":null}', null),
-- 479's NOT COVERED 10 product shapes: refused, as before (the product is
-- not refunded a second time there)
('PRx1', 'control', 'sale A pr,th; cancel; backps 2 40; reopen; refundall; pay',
  '{"status":"partially_paid","net":60,"sess":"0/3 r0 c3 cancelled","stock":"invoice_cancel_return 1, store_sale 1","prref":40,"prref_since":0,"error~":"refundall: Settle the reopened invoice before changing its queued sessions%"}', null),
('PRnl1', 'control', 'sale A pr,th; cancel; paidback 40; reopen; refundall; pay',
  '{"status":"partially_paid","net":60,"sess":"0/3 r0 c3 cancelled","stock":"invoice_cancel_return 1, store_sale 1","prref":0,"error~":"refundall: Settle the reopened invoice before changing its queued sessions%"}', null),
('PRxr2', 'control', 'sale A th,pr; cancel; backps 2 40; reopen; refundall',
  '{"status":"partially_paid","net":60,"sess":"0/3 r0 c3 cancelled","prref":40,"prref_since":0,"error~":"refundall: Settle the reopened invoice before changing its queued sessions%"}', null),
('PRxc1', 'control', 'sale A pr,th; cancel; backps 2 40; reopen; guidedcancel',
  '{"status":"partially_paid","net":60,"sess":"0/3 r0 c3 cancelled","prref":40,"prref_since":0,"error~":"guidedcancel: Settle the reopened invoice before changing its queued sessions%"}', null),
-- NOT COVERED 5: a limited voucher line cannot be refunded by line before
-- its vouchers are given
('LV1', 'known', 'sale A lv,pr 30; backt 1 30; pay',
  '{"status":"partially_paid","net":30,"stock":"-","td":1,"error~":"backt 1 30: This sold voucher has no source-linked unused/redemption record.%"}', null);
-- A blind box (483: its prize's products are its line's stock components,
-- recorded from the pick), the S$50 box refunded by line: its prize is not
-- taken again, as a product line's unit is not ('goods' lists each of Belt,
-- Gloves, Socks as on the invoice / collected / to collect, the three
-- sorted, as the Goods panel's order is not fixed; 'dstore' is the socks').
insert into t481_cases(k, kind, steps, expect, expect0) values
-- paid in part, the box refunded by line, settled: by Record Payment
('BX1', 'fixed', 'sale A bx,v 60; backps 2 50; pay',
  '{"status":"paid","net":60,"stock":"-","out":0,"td":0,"dstore":0,"goods":"1/0/0,1/0/0","gap":"-","holds":"0.00/2","error":null}',
  '{"status":"paid","net":60,"stock":"store_sale 2","out":2,"td":0,"dstore":-1,"goods":"1/1/0,1/1/0","gap":"-","holds":"0.00/2","error":null}'),
-- two boxes on one line (prize A twice), one box's S$50 refunded: one prize
('BX2', 'fixed', 'sale A bx2,v 110; backps 2 50; pay',
  '{"status":"paid","net":110,"stock":"store_sale 2","out":2,"td":0,"dstore":-1,"goods":"2/1/0,2/1/0","gap":"-","error":null}',
  '{"status":"paid","net":110,"stock":"store_sale 4","out":4,"td":0,"dstore":-2,"goods":"2/2/0,2/2/0","gap":"-","error":null}'),
-- the box with the socks picked directly too (one component, summed)
('BXD', 'fixed', 'sale A bxd,v 60; backps 2 50; pay',
  '{"status":"paid","net":60,"stock":"-","out":0,"td":0,"dstore":0,"goods":"1/0/0,2/0/0","error":null}',
  '{"status":"paid","net":60,"stock":"store_sale 3","out":3,"td":0,"dstore":-2,"goods":"1/1/0,2/2/0","error":null}'),
-- settled by Correct payment (the backstop)
('BXF', 'fixed', 'sale A bx,v 60; backps 2 50; fixup 50',
  '{"status":"paid","net":60,"stock":"-","out":0,"td":0,"dstore":0,"gap":"-","error":null}',
  '{"status":"paid","net":60,"stock":"store_sale 2","out":2,"td":0,"dstore":-1,"gap":"-","error":null}'),
-- "Fulfil from" a warehouse: a promotion's contents come from the store (the
-- warehouse sends product lines only), so before 481 the store took the prize
('BXW', 'fixed', 'sale A bx,v 60; wh; backps 2 50; pay',
  '{"status":"paid","net":60,"stock":"-","out":0,"td":0,"dstore":0,"dwh":0,"error":null}',
  '{"status":"paid","net":60,"stock":"store_sale 2","out":2,"td":0,"dstore":-1,"dwh":0,"error":null}'),
-- paid, the box refunded by line with its prize returned as sellable
('BXP', 'fixed', 'sale A bx,v; backps 2 50',
  '{"status":"paid","net":60,"stock":"invoice_refund_return 2, store_sale 2","out":0,"td":0,"dstore":0,"goods":"1/0/0,1/0/0","gap":"-","error":null}',
  '{"status":"paid","net":60,"stock":"invoice_refund_return 2, store_sale 2","out":0,"td":2,"dstore":0,"goods":"1/0/0,1/0/0","gap":"-","error":null}'),
-- two boxes on one line with different prizes (A and B), one box's S$50
-- refunded: which box is not recorded, so each prize's products count in
-- proportion, rounded down (one of prize B's two belts not taken, prize A
-- taken): 481's NOT COVERED 10, for the Owner
('BXM', 'fixed', 'sale A bxm,v 110; backps 2 50; pay',
  '{"status":"paid","net":110,"stock":"store_sale 3","out":3,"td":0,"dstore":-1,"goods":"1/1/0,1/1/0,2/1/0","error":null}',
  '{"status":"paid","net":110,"stock":"store_sale 4","out":4,"td":0,"dstore":-1,"goods":"1/1/0,1/1/0,2/2/0","error":null}'),
-- controls: a box paid at once; refunded by line while cancelled, reopened
-- (the line charged again) and paid: delivered again
('BX0', 'control', 'sale A bx,v', '{"status":"paid","net":110,"stock":"store_sale 2","out":2,"td":0,"dstore":-1,"goods":"1/1/0,1/1/0","error":null}', null),
('BXL4', 'control', 'sale A bx,v; cancel; backps 2 50; reopen; pay',
  '{"status":"paid","net":110,"stock":"invoice_cancel_return 2, store_sale 4","out":2,"td":0,"dstore":-1,"prref":50,"prref_since":0,"error":null}', null),
-- part of a box's value refunded (NOT COVERED 1): its prize is taken
('BXpt', 'known', 'sale A bx,v 60; backps 2 25; pay',
  '{"status":"paid","net":85,"stock":"store_sale 2","out":2,"td":0,"dstore":-1,"error":null}', null);
-- The cut plans: each run with its lines written both ways, checked for
-- the line its plan lists first (the order is not fixed).
create temp table t481_ocases(k text primary key, shape text not null, steps text not null, ord serial);
insert into t481_ocases(k, shape, steps) values
  ('P1a', 'P1', 'sale A pr,v; cancel; backps 2 40; reopen; payamt 10; refundall; pay'),
  ('P1b', 'P1', 'sale A v,pr; cancel; backps 2 40; reopen; payamt 10; refundall; pay'),
  ('P5a', 'P5', 'sale A pr,v; cancel; paidback 40; reopen; payamt 10; refundall; pay'),
  ('P5b', 'P5', 'sale A v,pr; cancel; paidback 40; reopen; payamt 10; refundall; pay'),
  ('P4a', 'P4', 'sale A pr,th; cancel; backps 2 40; backt 1 20; reopen; refundall; pay'),
  ('P4b', 'P4', 'sale A th,pr; cancel; backps 2 40; backt 1 20; reopen; refundall; pay');
-- (shape, the line listed first, after 481, before 481)
create temp table t481_oexp(shape text, first text, expect jsonb not null, expect0 jsonb not null, primary key (shape, first));
insert into t481_oexp values
  -- the product first: its S$40 refunded again and 1 voucher, then paid S$30:
  -- the other voucher; the product not taken again (before 481: taken)
  ('P1', 'product',
    '{"status":"paid","net":30,"holds":"0.00/1","stock":"invoice_cancel_return 1, store_sale 1","out":0,"td":0,"prref":80,"error":null}',
    '{"status":"paid","net":30,"holds":"0.00/1","stock":"invoice_cancel_return 1, store_sale 2","out":1,"td":0,"prref":80,"error":null}'),
  -- the vouchers first: S$10 of the product refunded, then paid S$30: the
  -- product taken, as before 481 (NOT COVERED 1)
  ('P1', 'voucher',
    '{"status":"paid","net":30,"holds":"0.00","stock":"invoice_cancel_return 1, store_sale 2","out":1,"td":0,"prref":50,"error":null}',
    '{"status":"paid","net":30,"holds":"0.00","stock":"invoice_cancel_return 1, store_sale 2","out":1,"td":0,"prref":50,"error":null}'),
  ('P5', 'product',
    '{"status":"paid","net":30,"holds":"0.00/1","stock":"invoice_cancel_return 1, store_sale 1","out":0,"td":0,"prref":40,"error":null}',
    '{"status":"paid","net":30,"holds":"0.00/1","stock":"invoice_cancel_return 1, store_sale 2","out":1,"td":0,"prref":40,"error":null}'),
  ('P5', 'voucher',
    '{"status":"paid","net":30,"holds":"0.00","stock":"invoice_cancel_return 1, store_sale 2","out":1,"td":0,"prref":10,"error":null}',
    '{"status":"paid","net":30,"holds":"0.00","stock":"invoice_cancel_return 1, store_sale 2","out":1,"td":0,"prref":10,"error":null}'),
  -- the product first: its S$40 again, the sessions nothing, then paid S$60:
  -- 3 of 3; the product not taken again (before 481: taken)
  ('P4', 'product',
    '{"status":"paid","net":60,"sess":"3/3 r0 c0 available","stock":"invoice_cancel_return 1, store_sale 1","out":0,"td":0,"prref":80,"error":null}',
    '{"status":"paid","net":60,"sess":"3/3 r0 c0 available","stock":"invoice_cancel_return 1, store_sale 2","out":1,"td":0,"prref":80,"error":null}'),
  -- the therapy line first: refused, as before
  ('P4', 'therapy',
    '{"status":"partially_paid","net":40,"sess":"0/3 r1 c2 refunded","stock":"invoice_cancel_return 1, store_sale 1","prref":40,"error~":"refundall: Settle the reopened invoice before changing its queued sessions%"}',
    '{"status":"partially_paid","net":40,"sess":"0/3 r1 c2 refunded","stock":"invoice_cancel_return 1, store_sale 1","prref":40,"error~":"refundall: Settle the reopened invoice before changing its queued sessions%"}');

-- The read-only query in 481's header (the same text, taken from the file
-- when this suite was written).
create function pg_temp.t481_header_query() returns table(reason text, invoice_no text, n bigint) language sql as $hq$
with
-- per product or promotion line (as invoice_required_stock counts it), on an
-- invoice not cancelled or refunded: the whole units its refunds by line
-- since the invoice was last reopened (or since the sale) paid back, at the
-- line's paid value, and the products they take (481's rule,
-- invoice_refunded_stock, written out: the function is 481's)
l as (
  select i.id as invoice_id, it.id as item_id, it.line_kind::text as lk, it.quantity, it.product_id, it.promotion_id,
         i.stock_snapshot_version as snap, public.invoice_discounted_line_value(it.id) as worth,
         coalesce((select sum((x->>'amount')::numeric)
                     from public.invoice_refunds r cross join lateral jsonb_array_elements(coalesce(r.outcome->'lines', '[]'::jsonb)) x
                    where r.invoice_id = i.id and x->>'invoice_item_id' = it.id::text
                      and not coalesce((x->>'overpayment')::boolean, false)
                      and (i.reopened_at is null or r.created_at > i.reopened_at)), 0) as refunded
    from public.invoices i join public.invoice_items it on it.invoice_id = i.id
   where i.deleted_at is null and i.status::text not in ('cancelled', 'refunded')
     and it.line_kind::text in ('product', 'promotion') and it.quantity > 0
     and (it.price_source is distinct from 'exchange' or not i.is_exchange)),
u as (
  select l.*, least(l.quantity, floor((l.refunded + 0.005)
           / case when trunc(l.worth / l.quantity, 2) > 0
                  then trunc(l.worth / l.quantity, 2) else l.worth / l.quantity end))::integer as n
    from l where l.refunded > 0 and l.worth > 0),
c as (
  select u.invoice_id, s.item_id as product_id, floor(s.quantity::numeric * u.n / u.quantity)::integer as q
    from u join public.invoice_stock_components s on s.invoice_item_id = u.item_id and s.kind = 'product'
   where u.n > 0 and u.snap = 1
  union all
  select u.invoice_id, u.product_id, u.n
    from u where u.n > 0 and u.snap is distinct from 1 and u.lk = 'product' and u.product_id is not null
  union all
  select u.invoice_id, s.item_id, floor(s.quantity::numeric * u.n / u.quantity)::integer
    from u cross join lateral public.promotion_stock_items(u.promotion_id, u.quantity) s
   where u.n > 0 and u.snap is distinct from 1 and u.lk = 'promotion' and u.promotion_id is not null and s.kind = 'product'
  union all
  select u.invoice_id, s.product_id, floor(s.quantity::numeric * u.n / u.quantity)::integer
    from u join public.invoice_promotion_selections s on s.invoice_item_id = u.item_id
   where u.n > 0 and u.snap is distinct from 1 and u.lk = 'promotion' and s.product_id is not null),
-- per invoice and product: the units refunded, what its lines take
-- (invoice_required_stock), what is with the customer, not returned or
-- written off (invoice_goods_out), and what is out counting the units kept as
-- Not returned (its sales less the returns and write-offs, as
-- invoice_stock_to_deduct reads them before 481)
st as (
  select f.invoice_id, f.product_id, f.units,
         coalesce((select sum(r.quantity) from public.invoice_required_stock(f.invoice_id) r
                    where r.kind = 'product' and r.item_id = f.product_id), 0) as lines,
         coalesce((select sum(g.quantity) from public.invoice_goods_out(f.invoice_id) g
                    where g.product_id = f.product_id), 0) as with_customer,
         coalesce((select sum(case when m.movement_type::text = 'store_sale' then m.quantity else -m.quantity end)
                     from public.stock_movements m
                    where m.invoice_id = f.invoice_id and m.product_id = f.product_id
                      and m.movement_type::text in ('store_sale', 'invoice_cancel_return', 'invoice_refund_return', 'refund_return')), 0)
           - coalesce((select sum(d.damaged_quantity) from public.invoice_stock_dispositions d
                        join public.stock_movements m on m.id = d.movement_id
                       where d.invoice_id = f.invoice_id and m.product_id = f.product_id), 0) as out_
    from (select c.invoice_id, c.product_id, sum(c.q) as units from c where c.product_id is not null
           group by c.invoice_id, c.product_id having sum(c.q) > 0) f),
found(reason, invoice_id, n) as (
  -- (1 can also list an invoice whose refunded line a later Edit Invoice
  -- lowered, its quantity, unit price or line discount or the invoice's
  -- manual discount, with nothing taken after the refund but by that
  -- correction, or nothing at all: 481's NOT COVERED 13; read its
  -- revisions and stock history before a charge, a recovery or a write-off)
  select '1 for the Owner (481 changes no record): a product refunded by line since its invoice was last reopened (or since the sale) is with the customer again beyond what its lines still charge, taken from stock after its refund (by the payment that settled the invoice, a correction that changed its stock, or a hand-over before full payment) and not returned; from 481 a refund by line keeps its units from being taken (the count is of units)', st.invoice_id, sum(least(st.units, st.with_customer - (st.lines - st.units)))
    from st where st.with_customer > st.lines - st.units
   group by st.invoice_id
  union all
  select '2 changes: units a refund by line paid back since the invoice was last reopened (or since the sale) that invoice_stock_to_deduct reported as still to take before 481 (the payment that settles the invoice, a hand-over, a correction that changes its stock, or its fulfilment from a warehouse took them); from 481 they are not taken (the count is of units)', st.invoice_id, sum(least(st.units, st.lines - st.out_))
    from st where st.lines - st.out_ > 0
   group by st.invoice_id)
select f.reason, i.invoice_no, f.n
  from found f join public.invoices i on i.id = f.invoice_id
 order by f.reason, i.invoice_no
$hq$;
-- What the header's query lists for an invoice: 'reason/count', by reason.
create function pg_temp.t481_listed(p_inv uuid) returns text language sql as $f$
  select string_agg(left(q.reason, 1) || '/' || q.n, ',' order by q.reason)
    from pg_temp.t481_header_query() q join invoices i on i.invoice_no = q.invoice_no where i.id = p_inv $f$;
-- The header's second read-only query (the same text): the warehouse's sends
-- (481's NOT COVERED 3, widened from the review of 2 Nov 2026).
create function pg_temp.t481_warehouse_query() returns table(reason text, invoice_no text, since bigint, sends bigint) language sql as $wq$
with
-- per invoice, the warehouse's sends: trg_fulfil_from_warehouse writes one
-- 'invoice_fulfilled_from_warehouse' audit row each time an invoice with
-- "Fulfil from" set moves to paid (or completed FOC); counted in all, and
-- since the invoice was last reopened (from the time of its last
-- 'invoice_reopened' audit row, which a send by the reopening itself shares,
-- one transaction; every row where it was never reopened)
s as (
  select a.record_id as invoice_id, count(*) as sends,
         count(*) filter (where a.created_at >= coalesce(
           (select max(r.created_at) from public.audit_logs r
             where r.table_name = 'invoices' and r.record_id = a.record_id and r.action = 'invoice_reopened'),
           '-infinity'::timestamptz)) as since
    from public.audit_logs a
   where a.table_name = 'invoices' and a.action = 'invoice_fulfilled_from_warehouse'
   group by a.record_id)
select case when s.since > 1
            then '1 for the Owner (481 changes no record): sent from the warehouse more than once since the invoice was last reopened (or since the sale), taken off paid and back by Correct payment, Edit Invoice or a removed payment, or by a Correct payment of a wallet-credit receipt; each send after the first left the warehouse short and the store over by the product lines'' units (from 481 less the units refunded by line) (the counts are of sends: since the last reopening, and in all)'
            else '2 for the Owner (481 changes no record): sent from the warehouse more than once in all but at most once since the invoice was last reopened: the reopening''s settlement sent it again (NOT COVERED 3''s Cancel and Reopen), or a send counted under 1 came before the reopening (the counts are of sends: since the last reopening, and in all)' end as reason,
       i.invoice_no, s.since, s.sends
  from s join public.invoices i on i.id = s.invoice_id
 where i.deleted_at is null and (s.since > 1 or s.sends > 1)
 order by 1, 2
$wq$;
-- The header's query's rule (its first part, the units refunded by line per
-- invoice and product) beside invoice_refunded_stock (P2): the query's text
-- up to its per-product totals, run on one invoice.
create temp table t481_qtext(t text);
insert into t481_qtext values ($qt$
with
-- per product or promotion line (as invoice_required_stock counts it), on an
-- invoice not cancelled or refunded: the whole units its refunds by line
-- since the invoice was last reopened (or since the sale) paid back, at the
-- line's paid value, and the products they take (481's rule,
-- invoice_refunded_stock, written out: the function is 481's)
l as (
  select i.id as invoice_id, it.id as item_id, it.line_kind::text as lk, it.quantity, it.product_id, it.promotion_id,
         i.stock_snapshot_version as snap, public.invoice_discounted_line_value(it.id) as worth,
         coalesce((select sum((x->>'amount')::numeric)
                     from public.invoice_refunds r cross join lateral jsonb_array_elements(coalesce(r.outcome->'lines', '[]'::jsonb)) x
                    where r.invoice_id = i.id and x->>'invoice_item_id' = it.id::text
                      and not coalesce((x->>'overpayment')::boolean, false)
                      and (i.reopened_at is null or r.created_at > i.reopened_at)), 0) as refunded
    from public.invoices i join public.invoice_items it on it.invoice_id = i.id
   where i.deleted_at is null and i.status::text not in ('cancelled', 'refunded')
     and it.line_kind::text in ('product', 'promotion') and it.quantity > 0
     and (it.price_source is distinct from 'exchange' or not i.is_exchange)),
u as (
  select l.*, least(l.quantity, floor((l.refunded + 0.005)
           / case when trunc(l.worth / l.quantity, 2) > 0
                  then trunc(l.worth / l.quantity, 2) else l.worth / l.quantity end))::integer as n
    from l where l.refunded > 0 and l.worth > 0),
c as (
  select u.invoice_id, s.item_id as product_id, floor(s.quantity::numeric * u.n / u.quantity)::integer as q
    from u join public.invoice_stock_components s on s.invoice_item_id = u.item_id and s.kind = 'product'
   where u.n > 0 and u.snap = 1
  union all
  select u.invoice_id, u.product_id, u.n
    from u where u.n > 0 and u.snap is distinct from 1 and u.lk = 'product' and u.product_id is not null
  union all
  select u.invoice_id, s.item_id, floor(s.quantity::numeric * u.n / u.quantity)::integer
    from u cross join lateral public.promotion_stock_items(u.promotion_id, u.quantity) s
   where u.n > 0 and u.snap is distinct from 1 and u.lk = 'promotion' and u.promotion_id is not null and s.kind = 'product'
  union all
  select u.invoice_id, s.product_id, floor(s.quantity::numeric * u.n / u.quantity)::integer
    from u join public.invoice_promotion_selections s on s.invoice_item_id = u.item_id
   where u.n > 0 and u.snap is distinct from 1 and u.lk = 'promotion' and s.product_id is not null),
-- per invoice and product: the units refunded, what its lines take
-- (invoice_required_stock), what is with the customer, not returned or
-- written off (invoice_goods_out), and what is out counting the units kept as
-- Not returned (its sales less the returns and write-offs, as
-- invoice_stock_to_deduct reads them before 481)
st as (
  select f.invoice_id, f.product_id, f.units,
         coalesce((select sum(r.quantity) from public.invoice_required_stock(f.invoice_id) r
                    where r.kind = 'product' and r.item_id = f.product_id), 0) as lines,
         coalesce((select sum(g.quantity) from public.invoice_goods_out(f.invoice_id) g
                    where g.product_id = f.product_id), 0) as with_customer,
         coalesce((select sum(case when m.movement_type::text = 'store_sale' then m.quantity else -m.quantity end)
                     from public.stock_movements m
                    where m.invoice_id = f.invoice_id and m.product_id = f.product_id
                      and m.movement_type::text in ('store_sale', 'invoice_cancel_return', 'invoice_refund_return', 'refund_return')), 0)
           - coalesce((select sum(d.damaged_quantity) from public.invoice_stock_dispositions d
                        join public.stock_movements m on m.id = d.movement_id
                       where d.invoice_id = f.invoice_id and m.product_id = f.product_id), 0) as out_
    from (select c.invoice_id, c.product_id, sum(c.q) as units from c where c.product_id is not null
           group by c.invoice_id, c.product_id having sum(c.q) > 0) f),
found(reason, invoice_id, n) as (
  -- (1 can also list an invoice whose refunded line a later Edit Invoice
  -- lowered, its quantity, unit price or line discount or the invoice's
  -- manual discount, with nothing taken after the refund but by that
  -- correction, or nothing at all: 481's NOT COVERED 13; read its
  -- revisions and stock history before a charge, a recovery or a write-off)
  select '1 for the Owner (481 changes no record): a product refunded by line since its invoice was last reopened (or since the sale) is with the customer again beyond what its lines still charge, taken from stock after its refund (by the payment that settled the invoice, a correction that changed its stock, or a hand-over before full payment) and not returned; from 481 a refund by line keeps its units from being taken (the count is of units)', st.invoice_id, sum(least(st.units, st.with_customer - (st.lines - st.units)))
    from st where st.with_customer > st.lines - st.units
   group by st.invoice_id
  union all
  select '2 changes: units a refund by line paid back since the invoice was last reopened (or since the sale) that invoice_stock_to_deduct reported as still to take before 481 (the payment that settles the invoice, a hand-over, a correction that changes its stock, or its fulfilment from a warehouse took them); from 481 they are not taken (the count is of units)', st.invoice_id, sum(least(st.units, st.lines - st.out_))
    from st where st.lines - st.out_ > 0
   group by st.invoice_id)
select f.reason, i.invoice_no, f.n
  from found f join public.invoices i on i.id = f.invoice_id
 order by f.reason, i.invoice_no
$qt$);
create function pg_temp.t481_query_units(p_inv uuid) returns text language plpgsql as $f$
declare q text := (select t from t481_qtext); v text;
begin
  q := left(q, position(E',\n-- per invoice and product' in q) - 1);
  execute q || $x$ select coalesce(string_agg(c.product_id || ':' || c.q, ',' order by c.product_id), '-')
                     from (select c.invoice_id, c.product_id, sum(c.q)::int as q from c where c.product_id is not null and c.invoice_id = $1
                            group by c.invoice_id, c.product_id having sum(c.q) > 0) c $x$ into v using p_inv;
  return v;
end $f$;
create function pg_temp.t481_function_units(p_inv uuid) returns text language plpgsql as $f$
declare v text;
begin
  execute $x$ select coalesce(string_agg(u.item_id || ':' || u.q, ',' order by u.item_id), '-')
                from (select item_id, sum(quantity)::int as q from public.invoice_refunded_stock($1) group by item_id) u $x$ into v using p_inv;
  return v;
end $f$;

-- ===== S. Where it starts =====
\if :{?nomig}
do $$ begin
  perform pg_temp.t481_check(pg_temp.t481_479_in(), 'S -v nomig=1: 479 is in');
  perform pg_temp.t481_check(pg_temp.t481_in() and pg_temp.t481_at('after'), 'S -v nomig=1: 481 is in, as tested');
end $$;
\else
do $$ begin
  perform pg_temp.t481_check(pg_temp.t481_479_in(), 'S 479 is in (481 goes in after it)');
  perform pg_temp.t481_check(not pg_temp.t481_in() and pg_temp.t481_at('before'),
    'S 481 is not in yet and the four functions are at their BEFORE (this suite installs it; use -v nomig=1 where it is in)');
end $$;
insert into t481_fp values ('start', pg_temp.t481_fingerprint()), ('grants', pg_temp.t481_grants());

-- ===== R. Before 481: each case reproduced (undone afterwards) =====
savepoint t481_r;
do $$
declare c record; o jsonb; e record; res text := ''; ores text := '';
begin
  for c in select * from t481_cases order by ord loop
    o := pg_temp.t481_run('before', c.k, c.steps);
    perform pg_temp.t481_check(pg_temp.t481_meets(o, coalesce(c.expect0, c.expect)),
      'R ' || c.kind || ' ' || c.k || ' without 481: ' || coalesce(pg_temp.t481_diff(o, coalesce(c.expect0, c.expect)), '') || ' ' || o::text);
    if c.kind = 'fixed' then res := res || format(E'\n  %s: %s, %s out, %s to take', c.k, o->>'stock', o->>'out', o->>'td'); end if;
  end loop;
  for c in select * from t481_ocases order by ord loop
    o := pg_temp.t481_run('before', c.k, c.steps);
    select * into e from t481_oexp x where x.shape = c.shape and x.first = pg_temp.t481_first('before', c.k);
    perform pg_temp.t481_check(e.shape is not null, 'R ' || c.k || ' without 481: its plan lists first a line no case expects: ' || o::text);
    perform pg_temp.t481_check(pg_temp.t481_meets(o, e.expect0),
      'R ' || c.k || ' without 481 (the ' || e.first || ' line first): ' || coalesce(pg_temp.t481_diff(o, e.expect0), '') || ' ' || o::text);
    ores := ores || format(E'\n  %s (%s first): %s', c.k, e.first, o->>'stock');
  end loop;
  raise notice 'PASS R: without 481 the units a refund by line paid back are taken from stock (the fault reproduced), the controls as expected:%', res;
  raise notice 'PASS R (the cut plans, by the line each lists first):%', ores;
end $$;

-- ===== Q. The header's read-only query, on these states =====
do $$
declare c record; v text; n1 int := 0; n2 int := 0;
begin
  for c in select k, kind from t481_cases union all select k, 'order' from t481_ocases loop
    v := pg_temp.t481_listed(pg_temp.t481_id('before/' || c.k || '/inv'));
    -- a fixed case's unit taken again and with the customer: 1; still to
    -- take or a correction's (PRpd, H3 before its hand-over): 2; a control,
    -- nothing
    if c.k in ('VPR', 'CPR', 'PRxk', 'PRxk2', 'PRn1', 'PRn2', 'PV1', 'P3a', 'P3b', 'PRpp', 'L6', 'PRM', 'L7', 'M2', 'W2', 'H2', 'H4', 'H3',
               'PRpds', 'PRpdd', 'BX1', 'BX2', 'BXD', 'BXF', 'BXW', 'BXM', 'RD1', 'RD4', 'RD10', 'RD6s', 'RD8', 'RW67', 'RW67b', 'RW25')
       or c.k in ('P1a', 'P5a', 'P4a', 'P1b', 'P5b', 'P4b') and pg_temp.t481_first('before', c.k) = 'product' then
      perform pg_temp.t481_check(v like '1/%', 'Q ' || c.k || ' (taken again) is listed as ' || coalesce(v, 'nothing'));
      n1 := n1 + 1;
    elsif c.k = 'PRpd' then
      perform pg_temp.t481_check(v = '2/1', 'Q PRpd (still to take) is listed as ' || coalesce(v, 'nothing'));
      n2 := n2 + 1;
    elsif c.k = 'BXP' then
      -- the box's prize, the socks and the gloves: 2 units
      perform pg_temp.t481_check(v = '2/2', 'Q BXP (still to take) is listed as ' || coalesce(v, 'nothing'));
      n2 := n2 + 1;
    elsif c.k = 'RD6' then
      -- 2 of the 3 units returned with S$66.66 (the review of 2 Nov 2026)
      perform pg_temp.t481_check(v = '2/2', 'Q RD6 (still to take) is listed as ' || coalesce(v, 'nothing'));
      n2 := n2 + 1;
    elsif c.k = 'RDp3' then
      -- 2 units returned with S$33.33: the 1 unit its money pays for
      perform pg_temp.t481_check(v = '2/1', 'Q RDp3 (still to take) is listed as ' || coalesce(v, 'nothing'));
      n2 := n2 + 1;
    elsif c.k = 'F1' then
      -- the line cut to 2 after its refund (NOT COVERED 13): listed under 1,
      -- the correction having taken the line's 2 again; whether that unit is
      -- one too many depends on what the cut meant (the caveat under the
      -- header's query)
      perform pg_temp.t481_check(v = '1/1', 'Q F1 (cut after its refund) is listed as ' || coalesce(v, 'nothing'));
    else
      perform pg_temp.t481_check(v is null, 'Q ' || c.kind || ' ' || c.k || ' is listed as ' || coalesce(v, 'nothing'));
    end if;
  end loop;
  raise notice 'PASS Q (before 481): the header''s query lists under 1 every invoice whose product a refund by line paid back is with the customer again (% of them: taken again by the payment, a correction, a hand-over or a warehouse), under 2 a unit refunded and returned still reported to take (%: PRpd, BXP''s prize, RD6''s 2 units, RDp3''s 1), and no control (F1, a line cut after its refund, under 1: NOT COVERED 13)', n1, n2;
end $$;
select coalesce(jsonb_object_agg(k, v), '{}'::jsonb)::text as t481_rbefore from t481_res where phase = 'before' \gset
select coalesce(jsonb_object_agg(pre, jsonb_build_object('err', err, 'at', at)), '{}'::jsonb)::text as t481_ebefore from t481_err where pre like 'before/%' \gset
select coalesce(jsonb_object_agg(pre, jsonb_build_object('lines', lines, 'first', first)), '{}'::jsonb)::text as t481_pbefore from t481_plan where pre like 'before/%' \gset
rollback to savepoint t481_r;
insert into t481_res select 'before', key, value from jsonb_each(:'t481_rbefore'::jsonb);
insert into t481_err select key, value->>'err', (value->>'at')::int from jsonb_each(:'t481_ebefore'::jsonb);
insert into t481_plan select key, value->>'lines', value->>'first' from jsonb_each(:'t481_pbefore'::jsonb);

-- ===== 9. The refusals, each changing nothing =====
-- 9a One of the four is neither its BEFORE nor its AFTER.
savepoint t481_9;
alter function public.invoice_stock_to_deduct(uuid) set work_mem = '64kB';
\set ON_ERROR_STOP off
\ir ../../../supabase/481_settlement_takes_no_refunded_stock.sql
\set ON_ERROR_STOP on
rollback to savepoint t481_9;
select set_config('t481.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t481_check(current_setting('t481.msg') like '481: public.invoice_stock_to_deduct(uuid) is not the version this was tested against%'
      and not pg_temp.t481_in() and pg_temp.t481_at('before'), '9a refused with: ' || current_setting('t481.msg'));
end $$;
-- 9b A partial install: the new function there, the four at their BEFORE.
savepoint t481_9;
create function public.invoice_refunded_stock(p_invoice_id uuid)
 returns table(invoice_item_id uuid, line_kind text, kind text, item_id uuid, quantity integer)
 language sql stable as $x$ select null::uuid, null::text, null::text, null::uuid, null::integer where false $x$;
\set ON_ERROR_STOP off
\ir ../../../supabase/481_settlement_takes_no_refunded_stock.sql
\set ON_ERROR_STOP on
rollback to savepoint t481_9;
select set_config('t481.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t481_check(current_setting('t481.msg') like '481: of the four functions 4 are at their BEFORE and 0 at their AFTER, and invoice_refunded_stock is there%'
      and not pg_temp.t481_in(), '9b refused with: ' || current_setting('t481.msg'));
end $$;
-- 9c A function it relies on is not as tested: the line's money window, and
-- 479's refund (481 goes in after 479).
savepoint t481_9;
alter function public.invoice_charge_total(uuid) set work_mem = '64kB';
\set ON_ERROR_STOP off
\ir ../../../supabase/481_settlement_takes_no_refunded_stock.sql
\set ON_ERROR_STOP on
rollback to savepoint t481_9;
select set_config('t481.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t481_check(current_setting('t481.msg') like '481: public.invoice_charge_total(uuid) is missing or not the version this was tested against%'
      and not pg_temp.t481_in(), '9c refused with: ' || current_setting('t481.msg'));
end $$;
savepoint t481_9;
alter function public.refund_invoice_therapy_sessions(uuid,numeric,text,uuid) set work_mem = '64kB';
\set ON_ERROR_STOP off
\ir ../../../supabase/481_settlement_takes_no_refunded_stock.sql
\set ON_ERROR_STOP on
rollback to savepoint t481_9;
select set_config('t481.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t481_check(current_setting('t481.msg') like '481: public.refund_invoice_therapy_sessions(uuid,numeric,text,uuid) is missing or not the version this was tested against%(481 goes in after 479).'
      and not pg_temp.t481_in(), '9c2 refused with: ' || current_setting('t481.msg'));
end $$;
-- 9d An overload of a name.
savepoint t481_9;
create function public.invoice_stock_to_deduct(p_invoice_id uuid, p_extra integer) returns integer language sql as $x$ select 0 $x$;
\set ON_ERROR_STOP off
\ir ../../../supabase/481_settlement_takes_no_refunded_stock.sql
\set ON_ERROR_STOP on
rollback to savepoint t481_9;
select set_config('t481.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t481_check(current_setting('t481.msg') like '481: another function takes the name of one this changes or adds: invoice_stock_to_deduct(uuid,integer)%'
      and not pg_temp.t481_in(), '9d refused with: ' || current_setting('t481.msg'));
end $$;
-- 9e A new caller of one of the four.
savepoint t481_9;
create function public.t481_reader(p uuid) returns bigint language sql as $x$ select public.invoice_product_net_deducted(p, p) $x$;
\set ON_ERROR_STOP off
\ir ../../../supabase/481_settlement_takes_no_refunded_stock.sql
\set ON_ERROR_STOP on
rollback to savepoint t481_9;
select set_config('t481.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t481_check(current_setting('t481.msg') like '481: public.invoice_product_net_deducted(uuid,uuid) is called by %t481_reader(uuid)%'
      and not pg_temp.t481_in(), '9e refused with: ' || current_setting('t481.msg'));
end $$;
-- 9f A new writer of refunds, of stock outcomes, a new setter of
-- reopened_at, a new reader of store sales.
savepoint t481_9;
create function public.t481_writer() returns void language sql as $x$ insert into public.invoice_refunds(invoice_id, amount) select null, 0 where false $x$;
\set ON_ERROR_STOP off
\ir ../../../supabase/481_settlement_takes_no_refunded_stock.sql
\set ON_ERROR_STOP on
rollback to savepoint t481_9;
select set_config('t481.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t481_check(current_setting('t481.msg') like '481: what writes a refund (invoice_refunds) is not as read on 30 Oct 2026 (%t481_writer()%'
      and not pg_temp.t481_in(), '9f refused with: ' || current_setting('t481.msg'));
end $$;
savepoint t481_9;
create function public.t481_writer() returns void language sql as $x$ delete from public.invoice_stock_dispositions where false $x$;
\set ON_ERROR_STOP off
\ir ../../../supabase/481_settlement_takes_no_refunded_stock.sql
\set ON_ERROR_STOP on
rollback to savepoint t481_9;
select set_config('t481.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t481_check(current_setting('t481.msg') like '481: what writes a stock outcome (invoice_stock_dispositions) is not as read on 30 Oct 2026 (%t481_writer()%'
      and not pg_temp.t481_in(), '9f2 refused with: ' || current_setting('t481.msg'));
end $$;
savepoint t481_9;
create function public.t481_writer() returns void language sql as $x$ update public.invoices set reopened_at = null where false $x$;
\set ON_ERROR_STOP off
\ir ../../../supabase/481_settlement_takes_no_refunded_stock.sql
\set ON_ERROR_STOP on
rollback to savepoint t481_9;
select set_config('t481.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t481_check(current_setting('t481.msg') like '481: what sets an invoice''s reopened_at is not as read on 30 Oct 2026 (%t481_writer()%'
      and not pg_temp.t481_in(), '9f3 refused with: ' || current_setting('t481.msg'));
end $$;
savepoint t481_9;
create function public.t481_writer() returns bigint language sql as $x$ select count(*) from public.stock_movements where movement_type::text = 'store_sale' $x$;
\set ON_ERROR_STOP off
\ir ../../../supabase/481_settlement_takes_no_refunded_stock.sql
\set ON_ERROR_STOP on
rollback to savepoint t481_9;
select set_config('t481.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t481_check(current_setting('t481.msg') like '481: what names a store sale (stock_movements of kind store_sale) is not as read on 30 Oct 2026 (%t481_writer()%'
      and not pg_temp.t481_in(), '9f4 refused with: ' || current_setting('t481.msg'));
end $$;
-- 9g The triggers not as read; a column read not as read.
savepoint t481_9;
drop trigger fulfil_from_warehouse on public.invoices;
\set ON_ERROR_STOP off
\ir ../../../supabase/481_settlement_takes_no_refunded_stock.sql
\set ON_ERROR_STOP on
rollback to savepoint t481_9;
select set_config('t481.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t481_check(current_setting('t481.msg') = '481: the triggers that run the warehouse fulfilment and the stock backstop when an invoice is settled are not as read on 30 Oct 2026'
      and not pg_temp.t481_in(), '9g refused with: ' || current_setting('t481.msg'));
end $$;
savepoint t481_9;
alter table public.invoice_stock_dispositions alter column not_returned_quantity type bigint;
\set ON_ERROR_STOP off
\ir ../../../supabase/481_settlement_takes_no_refunded_stock.sql
\set ON_ERROR_STOP on
rollback to savepoint t481_9;
select set_config('t481.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t481_check(current_setting('t481.msg') = '481: these columns are missing or not as read on 30 Oct 2026: invoice_stock_dispositions.not_returned_quantity'
      and not pg_temp.t481_in(), '9g2 refused with: ' || current_setting('t481.msg'));
end $$;
-- 9h Other grants; the same grants in another order do not stop it.
savepoint t481_9;
grant execute on function public.invoice_stock_to_deduct(uuid) to authenticated;
\set ON_ERROR_STOP off
\ir ../../../supabase/481_settlement_takes_no_refunded_stock.sql
\set ON_ERROR_STOP on
rollback to savepoint t481_9;
select set_config('t481.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t481_check(current_setting('t481.msg') like '481: who may call public.invoice_stock_to_deduct(uuid) is not as read on 30 Oct 2026 (%)'
      and not pg_temp.t481_in(), '9h refused with: ' || current_setting('t481.msg'));
end $$;
savepoint t481_9;
revoke execute on function public.invoice_goods_status(uuid) from postgres;
grant execute on function public.invoice_goods_status(uuid) to postgres;
select pg_temp.t481_check((select proacl::text from pg_proc where oid = 'public.invoice_goods_status(uuid)'::regprocedure)
         <> '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'
       and pg_temp.t481_grant_set('invoice_goods_status(uuid)') = '{authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres}',
  '9h2 set-up: the same grants in another order');
\ir ../../../supabase/481_settlement_takes_no_refunded_stock.sql
select pg_temp.t481_in() and pg_temp.t481_at('after') as t481_9h2_in \gset
rollback to savepoint t481_9;
select pg_temp.t481_check(:'t481_9h2_in'::boolean and not pg_temp.t481_in(), '9h2 the same grants in another order stopped it');
do $$ begin
  raise notice 'PASS 9: refused, changing nothing, where one of the four is neither its BEFORE nor its AFTER, an install is partial, a function it relies on is not as tested (the money''s window, 479''s refund), another function takes a name, a new function calls one, writes a refund or a stock outcome, sets reopened_at or names a store sale, the triggers or a column read are not as read, or other grants; the same grants in another order do not stop it';
end $$;
\endif

-- ===== 10. Install 481, twice =====
\if :{?nomig}
do $$ begin raise notice 'NOTE 10: -v nomig=1, so 481 is not installed here (R, Q before 481 and 9 are skipped)'; end $$;
\else
\ir ../../../supabase/481_settlement_takes_no_refunded_stock.sql
do $$ begin insert into t481_fp values ('first', pg_temp.t481_fingerprint()); end $$;
\ir ../../../supabase/481_settlement_takes_no_refunded_stock.sql
do $$ begin insert into t481_fp values ('second', pg_temp.t481_fingerprint()); end $$;
\endif
do $$
declare m record;
begin
  perform pg_temp.t481_check(pg_temp.t481_in() and pg_temp.t481_at('after'), '10 481 is not installed as tested');
  perform pg_temp.t481_check((select count(*) from pg_proc where pronamespace = 'public'::regnamespace
                               and proname in ('invoice_stock_to_deduct', 'invoice_product_net_deducted', 'trg_fulfil_from_warehouse',
                                               'invoice_goods_status', 'invoice_refunded_stock')) = 5,
    '10 an overload exists');
  for m in select sig from t481_md5 where sig <> 'invoice_goods_status(uuid)' union all select 'invoice_refunded_stock(uuid)' loop
    perform pg_temp.t481_check(pg_temp.t481_grant_set(m.sig) = '{postgres=X/postgres,service_role=X/postgres}'::text[]
        and not has_function_privilege('anon', 'public.' || m.sig, 'execute')
        and not has_function_privilege('authenticated', 'public.' || m.sig, 'execute'),
      '10 who may call ' || m.sig || ' changed');
  end loop;
  perform pg_temp.t481_check(pg_temp.t481_grant_set('invoice_goods_status(uuid)')
                               = '{authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres}'::text[]
      and not has_function_privilege('anon', 'public.invoice_goods_status(uuid)', 'execute'),
    '10 who may call the Goods panel changed');
  if exists (select 1 from t481_fp where k = 'first') then
    perform pg_temp.t481_check((select fp from t481_fp where k = 'second') = (select fp from t481_fp where k = 'first'),
      '10 the second run of 481 changed functions');
    perform pg_temp.t481_check(split_part((select fp from t481_fp where k = 'first'), ' ', 2)::int
                               = split_part((select fp from t481_fp where k = 'start'), ' ', 2)::int + 1,
      '10 481 did not add exactly one function');
    perform pg_temp.t481_check(pg_temp.t481_grants() = (select fp from t481_fp where k = 'grants'), '10 the grants of the functions before 481 changed');
    -- On a copy of production at 486 with 479 in (3 Nov 2026, this build of
    -- 479 and 481): the AFTER fingerprint. Still accepted: the same build on
    -- a copy at 485 with 479 in (3 Nov 2026), 486 having changed the merge
    -- preview alone. (At 485 with 479's previous builds it was bda210db 1398
    -- -> 3d476df5 1399, 082badac 1398 -> ff40ea0a 1399, ca96dde5 1398 ->
    -- 7987f0d2 1399 and 270aa323 1398 -> 41f202f2 1399; at 478 with 479, 30
    -- Oct 2026, fbc67a29 1390 -> 228bf316 1391; since 481 pins 483's
    -- capture_invoice_stock_components it refuses there.)
    if (select fp from t481_fp where k = 'start') = '8928dd465d7bfd1125d42a983735e226 1398' then
      perform pg_temp.t481_check((select fp from t481_fp where k = 'first') = 'e15db5824bcbea2c4001b047ba151389 1399',
        '10 the fingerprint after 481 is ' || (select fp from t481_fp where k = 'first'));
    elsif (select fp from t481_fp where k = 'start') = '5695d246035dd52d0f16c5f7f92fc5f8 1398' then
      perform pg_temp.t481_check((select fp from t481_fp where k = 'first') = '20ef063d2b8fd638d5b27a6e7188e14a 1399',
        '10 the fingerprint after 481 (at 485) is ' || (select fp from t481_fp where k = 'first'));
    end if;
  end if;
  raise notice 'PASS 10: 481 installed (the four at their AFTER, invoice_refunded_stock added); %; no overload; the grants as before (the four as they were: the Goods panel signed-in staff too; the new one postgres and the service role; never anon)',
    coalesce('the second run changed nothing (' || (select fp from t481_fp where k = 'second') || ')', 'it was in before the suite (nomig)');
end $$;

-- ===== A. After 481: each case =====
do $$
declare c record; o jsonb; b jsonb; e record; res text := ''; ores text := ''; n int := 0;
begin
  for c in select * from t481_cases order by ord loop
    o := pg_temp.t481_run('after', c.k, c.steps);
    perform pg_temp.t481_check(pg_temp.t481_meets(o, c.expect),
      'A ' || c.kind || ' ' || c.k || ': ' || coalesce(pg_temp.t481_diff(o, c.expect), '') || ' ' || o::text);
    if c.kind = 'fixed' then res := res || format(E'\n  %s: %s, %s out, %s to take', c.k, o->>'stock', o->>'out', o->>'td'); end if;
    -- Where R ran: a control or known case exactly as before 481 (but a
    -- known case that differs on purpose, with an 'expect0': F1).
    b := (select v from t481_res where phase = 'before' and k = c.k);
    if b is not null and c.kind <> 'fixed' and c.expect0 is null then
      perform pg_temp.t481_check(o = b, 'A ' || c.kind || ' ' || c.k || ' differs from before 481: ' || b::text || ' / ' || o::text);
      n := n + 1;
    end if;
  end loop;
  for c in select * from t481_ocases order by ord loop
    o := pg_temp.t481_run('after', c.k, c.steps);
    select * into e from t481_oexp x where x.shape = c.shape and x.first = pg_temp.t481_first('after', c.k);
    perform pg_temp.t481_check(e.shape is not null, 'A ' || c.k || ': its plan lists first a line no case expects: ' || o::text);
    perform pg_temp.t481_check(pg_temp.t481_meets(o, e.expect),
      'A ' || c.k || ' (the ' || e.first || ' line first): ' || coalesce(pg_temp.t481_diff(o, e.expect), '') || ' ' || o::text);
    -- where R listed the same line first and 481 changes nothing there
    -- (expect = expect0), exactly as before 481
    b := (select v from t481_res where phase = 'before' and k = c.k);
    if b is not null and pg_temp.t481_first('before', c.k) is not distinct from e.first and e.expect = e.expect0 then
      perform pg_temp.t481_check(o = b, 'A ' || c.k || ' differs from before 481: ' || b::text || ' / ' || o::text);
      n := n + 1;
    end if;
    ores := ores || format(E'\n  %s (%s first): %s', c.k, e.first, o->>'stock');
  end loop;
  raise notice 'PASS A: after 481 no unit a refund by line paid back since the sale or the last reopening is taken from stock:%', res;
  raise notice 'PASS A (the cut plans, by the line each lists first):%', ores;
  raise notice 'PASS A: % controls and known cases compared with before 481: exactly the same, every key (what is taken from the stores and the warehouse, what is out, what is left to take, the Goods panel, the stock reports, the money, the sessions, who holds what, the plans, the refusals)', n;
end $$;
-- Q after 481: no case's product is with the customer again; the units
-- whose figure 481 changed are listed under 2.
do $$
declare c record; v text;
begin
  for c in select k, kind from t481_cases union all select k, 'order' from t481_ocases loop
    v := pg_temp.t481_listed(pg_temp.t481_id('after/' || c.k || '/inv'));
    perform pg_temp.t481_check(v is null or v not like '%1/%' or c.k in ('P1b', 'P5b'),
      'Q after 481: ' || c.k || ' is listed as ' || v);
  end loop;
  perform pg_temp.t481_check(pg_temp.t481_listed(pg_temp.t481_id('after/VPR/inv')) = '2/1'
      and pg_temp.t481_listed(pg_temp.t481_id('after/PRpd/inv')) = '2/1'
      and pg_temp.t481_listed(pg_temp.t481_id('after/L7/inv')) = '2/1'
      and pg_temp.t481_listed(pg_temp.t481_id('after/L1/inv')) is null
      and pg_temp.t481_listed(pg_temp.t481_id('after/L4/inv')) is null
      -- a blind box: its prize refunded by line, not taken (BX1), one of two
      -- (BX2); the controls not at all
      and pg_temp.t481_listed(pg_temp.t481_id('after/BX1/inv')) = '2/2'
      and pg_temp.t481_listed(pg_temp.t481_id('after/BX2/inv')) = '2/2'
      and pg_temp.t481_listed(pg_temp.t481_id('after/BX0/inv')) is null
      and pg_temp.t481_listed(pg_temp.t481_id('after/BXL4/inv')) is null,
    'Q after 481: VPR ' || coalesce(pg_temp.t481_listed(pg_temp.t481_id('after/VPR/inv')), '-')
    || ', PRpd ' || coalesce(pg_temp.t481_listed(pg_temp.t481_id('after/PRpd/inv')), '-')
    || ', BX1 ' || coalesce(pg_temp.t481_listed(pg_temp.t481_id('after/BX1/inv')), '-')
    || ', BX2 ' || coalesce(pg_temp.t481_listed(pg_temp.t481_id('after/BX2/inv')), '-'));
  raise notice 'PASS Q (after 481): no product a refund by line paid back is with the customer again; the units whose figure 481 changes listed under 2 (VPR, PRpd, L7, the blind boxes BX1 and BX2); a control not at all';
end $$;

-- ===== P. Probes =====
-- P1 Each of the four beside 481's parts is exactly as before: its text with
-- each of 481's parts replaced by what was there before gives its BEFORE md5.
create temp table t481_wb(sig text, n int, new text, old text, primary key (sig, n));
insert into t481_wb values ('invoice_stock_to_deduct(uuid)', 1,
$w$ else coalesce((select sum(m.quantity) from public.invoice_voucher_movements m where m.invoice_id=p_invoice_id and m.voucher_id=r.item_id),0) end
 -- 481 (the Owner, 29 Oct 2026, Q2 "Fix it separately"): less the units a
 -- refund by line paid back since the invoice was last reopened (or since the
 -- sale), so the payment that settles it does not take them from stock
 -- (invoice_refunded_stock: none on a cancelled or refunded invoice).
 -coalesce((select sum(u.quantity) from public.invoice_refunded_stock(p_invoice_id) u where u.kind=r.kind and u.item_id=r.item_id),0))::int
$w$,
$w$ else coalesce((select sum(m.quantity) from public.invoice_voucher_movements m where m.invoice_id=p_invoice_id and m.voucher_id=r.item_id),0) end)::int
$w$);
insert into t481_wb values ('invoice_product_net_deducted(uuid,uuid)', 1,
$w$AS $function$
  with n as (
  select coalesce(sum($w$,
$w$AS $function$
  select coalesce(sum($w$);
insert into t481_wb values ('invoice_product_net_deducted(uuid,uuid)', 2,
$w$                      where rl.invoice_id = p_invoice_id and rl.product_id = p_product_id), 0)::bigint as net
    from public.stock_movements sm
   where sm.invoice_id = p_invoice_id
     and sm.product_id = p_product_id)
  -- 481 (the Owner, 29 Oct 2026, Q2 "Fix it separately"): plus the units a
  -- refund by line paid back since the last reopening (or the sale) that the
  -- invoice no longer takes (invoice_stock_to_deduct, less them, says nothing
  -- is left to take of them), counted as taken: so the backstop
  -- (ensure_invoice_stock_deducted) does not take them either, and the stock
  -- reports (invoice_stock_gaps, invoice_stock_diagnostic) do not list them as
  -- missing. With no such refund, as before.
  select n.net + case
           when coalesce((select sum(u.quantity) from public.invoice_refunded_stock(p_invoice_id) u
                           where u.kind = 'product' and u.item_id = p_product_id), 0) > 0
           then greatest(0, coalesce((select sum(r.quantity) from public.invoice_required_stock(p_invoice_id) r
                                       where r.kind = 'product' and r.item_id = p_product_id), 0)
                            - n.net
                            - coalesce((select sum(t.quantity) from public.invoice_stock_to_deduct(p_invoice_id) t
                                         where t.kind = 'product' and t.item_id = p_product_id), 0))
           else 0 end::bigint
    from n
$w$,
$w$                      where rl.invoice_id = p_invoice_id and rl.product_id = p_product_id), 0)::bigint
    from public.stock_movements sm
   where sm.invoice_id = p_invoice_id
     and sm.product_id = p_product_id
$w$);
insert into t481_wb values ('trg_fulfil_from_warehouse()', 1,
$w$  -- 481 (the Owner, 29 Oct 2026, Q2 "Fix it separately"): each product line
  -- less the units a refund by line paid back since the last reopening (or
  -- the sale): the payment took no store stock for them
  -- (invoice_stock_to_deduct), so none comes from the warehouse.
  for v_it in
    select ii.product_id,
           sum(ii.quantity) - coalesce((select sum(u.quantity) from public.invoice_refunded_stock(new.id) u
                                         where u.line_kind = 'product' and u.item_id = ii.product_id), 0) as qty,
           p.name
      from public.invoice_items ii join public.products p on p.id = ii.product_id
     where ii.invoice_id = new.id and ii.line_kind = 'product' and ii.product_id is not null
     group by ii.product_id, p.name
  loop
    continue when v_it.qty <= 0;
$w$,
$w$  for v_it in
    select ii.product_id, sum(ii.quantity) as qty, p.name
      from public.invoice_items ii join public.products p on p.id = ii.product_id
     where ii.invoice_id = new.id and ii.line_kind = 'product' and ii.product_id is not null
     group by ii.product_id, p.name
  loop
$w$);
insert into t481_wb values ('invoice_goods_status(uuid)', 1,
$w$       gone as (select g.product_id, sum(g.quantity)::integer as qty
                  from public.invoice_goods_out(i.id) g group by 1),
       -- 481 (the Owner, 29 Oct 2026, Q2): the units a refund by line paid
       -- back since the last reopening (or the sale), no longer to collect
       -- (invoice_stock_to_deduct takes them off), and those the customer
       -- kept (Not returned).
       refd as (select u.item_id as product_id, sum(u.quantity)::integer as qty
                  from public.invoice_refunded_stock(i.id) u where u.kind = 'product' group by 1),
       kept as (select m.product_id, sum(d.not_returned_quantity)::integer as qty
                  from public.invoice_stock_dispositions d join public.stock_movements m on m.id = d.movement_id
                 where d.invoice_id = i.id group by 1),
$w$,
$w$       gone as (select g.product_id, sum(g.quantity)::integer as qty
                  from public.invoice_goods_out(i.id) g group by 1),
$w$);
insert into t481_wb values ('invoice_goods_status(uuid)', 2,
$w$           -- 481: with a refund by line since the last reopening, what the
           -- customer has (out, or kept as Not returned), up to the lines'.
           'collected', case when coalesce(refd.qty, 0) = 0 then greatest(coalesce(req.qty, 0) - coalesce(tod.qty, 0), 0)
                             else greatest(least(coalesce(req.qty, 0), coalesce(gone.qty, 0) + coalesce(kept.qty, 0)), 0) end,
$w$,
$w$           'collected', greatest(coalesce(req.qty, 0) - coalesce(tod.qty, 0), 0),
$w$);
insert into t481_wb values ('invoice_goods_status(uuid)', 3,
$w$    left join gone on gone.product_id = ids.product_id
    left join refd on refd.product_id = ids.product_id
    left join kept on kept.product_id = ids.product_id
$w$,
$w$    left join gone on gone.product_id = ids.product_id
$w$);
do $$
declare m record; w record; d text;
begin
  for m in select * from t481_md5 loop
    d := pg_get_functiondef(to_regprocedure('public.' || m.sig));
    for w in select * from t481_wb where sig = m.sig order by n loop
      perform pg_temp.t481_check((length(d) - length(replace(d, w.new, ''))) / length(w.new) = 1,
        'P1 ' || m.sig || ': part ' || w.n || ' is not there once');
      d := replace(d, w.new, w.old);
    end loop;
    perform pg_temp.t481_check(md5(d) = m.before, 'P1 ' || m.sig || ' worked back is ' || md5(d) || ', not its BEFORE ' || m.before);
  end loop;
  raise notice 'PASS P1: each of the four, 481''s parts put back as they were, is exactly its BEFORE (by md5)';
end $$;
-- P2 The header's query's rule (its first part) gives what
-- invoice_refunded_stock gives, on every case's state after 481; and on a
-- cancelled or refunded invoice nothing.
do $$
declare c record; a text; b text; n int := 0;
begin
  for c in select k from t481_cases union all select k from t481_ocases loop
    a := pg_temp.t481_query_units(pg_temp.t481_id('after/' || c.k || '/inv'));
    b := pg_temp.t481_function_units(pg_temp.t481_id('after/' || c.k || '/inv'));
    perform pg_temp.t481_check(a = b, 'P2 ' || c.k || ': the header''s query counts ' || a || ', invoice_refunded_stock ' || b);
    if b <> '-' then n := n + 1; end if;
  end loop;
  perform pg_temp.t481_check(pg_temp.t481_function_units(pg_temp.t481_id('after/PRc/inv')) = '-', 'P2 PRc (cancelled) counts units refunded');
  raise notice 'PASS P2: the header''s query and invoice_refunded_stock count the same units on every case (% with units refunded), none on a cancelled invoice', n;
end $$;

-- ===== K. KNOWN (481's NOT COVERED), checked as they are =====
do $$
declare o jsonb; o2 jsonb;
begin
  -- K1: a refund by line of less than a unit's value leaves the unit to be
  -- taken (P1b, P5b the vouchers first: S$10 of S$40; L8 S$20 of a line of
  -- two; PRM2 half of the promotion).
  perform pg_temp.t481_check((select v->>'stock' from t481_res where phase = 'after' and k = 'L8') = 'store_sale 2'
      and (select v->>'stock' from t481_res where phase = 'after' and k = 'PRM2') = 'store_sale 2'
      and (select v->>'stock' from t481_res where phase = 'after' and k = 'BXpt') = 'store_sale 2', 'K1: look at NOT COVERED 1 again');
  raise notice 'KNOWN K1: (481''s NOT COVERED 1) a refund by line of less than a unit''s value leaves the unit taken: L8 (S$20 of a 2-unit S$80 line: both taken), PRM2 (S$35 of the S$70 promotion: both units taken), BXpt (S$25 of the S$50 blind box: its prize taken), and where the guided plan lists the vouchers first P1b, P5b (S$10 of S$40: taken). A unit whose paid value is not whole cents counts at that value cut down to the cent, so none is lost to the cent (RD1, RD4: S$66.66 of a 3-unit S$100.00 line, 2 units; RD10: three refunds of S$33.33, 3; RW67b: S$66.66 of a 2-unit S$66.67 line, 2) and none counted that the money does not pay for (RW25: S$99.98 of four S$25.00 units, 3)';
  -- K2: refunded with the unit returned, cancelled, reopened: Record Payment
  -- delivers it again, Correct payment does not (the backstop counts the
  -- first sale).
  o := (select v from t481_res where phase = 'after' and k = 'CPr');
  o2 := (select v from t481_res where phase = 'after' and k = 'CPd');
  perform pg_temp.t481_check(o->>'stock' = 'invoice_refund_return 1, store_sale 2' and o2->>'stock' = 'invoice_refund_return 1, store_sale 1'
      and (o2->>'td')::int = 1 and o2->>'status' = 'paid', 'K2: look at NOT COVERED 2 again: ' || o::text || ' / ' || o2::text);
  raise notice 'KNOWN K2: (481''s NOT COVERED 2; not 481''s) a product refunded by line with its unit returned, the invoice cancelled and reopened: Record Payment delivers it again (CPr), Correct payment does not (CPd: paid, 1 still reported to take)';
  -- K3: any move back to paid of a settled warehouse invoice sends it again:
  -- cancelled and reopened (W3, W4), and (widened from the review of 2 Nov 2026) among the
  -- routes the review found one Correct payment of a wallet-credit
  -- receipt's date alone (E4w3): the warehouse short two, the store one
  -- over, two sends, the money and the credit unchanged. The header's second
  -- read-only query lists E4w3 under 1 (2 sends since the sale), not W1 or
  -- L1. (This suite is one transaction, so every audit row here has the same
  -- time and W3, W4 are not checked against the query: on copies with each
  -- call committed it lists them under 2, once since the reopening.)
  perform pg_temp.t481_check((select (v->>'dwh')::int = -2 and (v->>'dstore')::int = 1 from t481_res where phase = 'after' and k = 'W3')
      and (select (v->>'dwh')::int = -2 and (v->>'dstore')::int = 1 from t481_res where phase = 'after' and k = 'W4')
      and (select (v->>'dwh')::int = -2 and (v->>'dstore')::int = 1 and (v->>'fulfil')::int = 2 and v->>'holds' = '60.00'
                  and (v->>'net')::numeric = 40 from t481_res where phase = 'after' and k = 'E4w3')
      and (select string_agg(left(q.reason, 1) || '/' || q.since || '/' || q.sends, ',') from pg_temp.t481_warehouse_query() q
            join invoices i on i.invoice_no = q.invoice_no where i.id = pg_temp.t481_id('after/E4w3/inv')) = '1/2/2'
      and not exists (select 1 from pg_temp.t481_warehouse_query() q join invoices i on i.invoice_no = q.invoice_no
                       where i.id in (pg_temp.t481_id('after/W1/inv'), pg_temp.t481_id('after/L1/inv'))),
    'K3: look at NOT COVERED 3 again');
  raise notice 'KNOWN K3: (481''s NOT COVERED 3; not 481''s) a settled warehouse-fulfilled invoice moved back to paid is sent from the warehouse again, the store getting back what it never lost: cancelled and reopened (W3, W4: warehouse -2, store +1, the customer holding 1), and one Correct payment of a wallet-credit receipt''s date alone (E4w3: warehouse -2, store +1, two sends, S$60 of credit left, as before 481); the header''s second query lists E4w3 under 1, not W1';
  -- K4: 479's NOT COVERED 17: the product's line refunded a second time by
  -- the guided flows (S$80 in all on its S$40 line); 481 changes its stock
  -- side only.
  perform pg_temp.t481_check((select (v->>'prref')::numeric = 80 and (v->>'out')::int = 0 from t481_res where phase = 'after' and k = 'P3a')
      and (select (v->>'prref')::numeric = 80 and (v->>'out')::int = 0 from t481_res where phase = 'after' and k = 'P3b'),
    'K4: look at NOT COVERED 4 again');
  raise notice 'KNOWN K4: (481''s NOT COVERED 4, 479''s 17; not 481''s) a product line refunded before the reopening is refunded again by the guided flows (P3a, P3b, and P1a, P4a where the product is listed first: S$80 on the S$40 line; P5a S$40 again); from 481 the payment then takes it from stock no more';
  -- K5: a limited voucher line cannot be refunded by line before its
  -- vouchers are given.
  perform pg_temp.t481_check((select v->>'error' like 'backt 1 30: This sold voucher has no source-linked unused/redemption record.%' from t481_res where phase = 'after' and k = 'LV1'),
    'K5: look at NOT COVERED 5 again');
  raise notice 'KNOWN K5: (481''s NOT COVERED 5) vouchers not changed: a limited voucher line cannot be refunded by line before its vouchers are given (LV1)';
  -- K8: the promotions' stock report counts store sales against what the
  -- lines take, ignoring returns: the promotion refunded by line and not
  -- taken (PRM) is listed as missing its 2 units.
  perform pg_temp.t481_check((select string_agg(g.required || '/' || g.recorded || '/' || g.missing, ',') from promotion_stock_gaps() g
                               where g.invoice_no = (select invoice_no from invoices where id = pg_temp.t481_id('after/PRM/inv'))) = '2/0/2',
    'K8: look at NOT COVERED 8 again');
  raise notice 'KNOWN K8: (481''s NOT COVERED 8) the promotions'' stock report lists a promotion refunded by line and so not taken (PRM) as missing its 2 units';
  -- K10: a line of two blind boxes with different prizes, one box's value
  -- refunded by line: which box is not recorded, so each prize's products
  -- count in proportion, rounded down (one of prize B's two belts is not
  -- taken; prize A's socks and gloves are).
  o := (select v from t481_res where phase = 'after' and k = 'BXM');
  perform pg_temp.t481_check(o->>'stock' = 'store_sale 3' and o->>'goods' = '1/1/0,1/1/0,2/1/0',
    'K10: look at NOT COVERED 10 again: ' || o::text);
  raise notice 'KNOWN K10: (481''s NOT COVERED 10) two blind boxes on one line with different prizes, one box''s S$50 refunded by line: each prize''s products count in proportion, rounded down (BXM: 1 of prize B''s 2 belts not taken, prize A''s socks and gloves taken); which box was refunded is for the Owner';
  -- K12 (checking RD6, 2 Nov 2026; not 481's): more units returned with a
  -- refund by line than its money pays for: the paid invoice still reports
  -- the difference to take, and a store move takes it again.
  perform pg_temp.t481_check((select (v->>'td')::int = 1 and (v->>'out')::int = 0 from t481_res where phase = 'after' and k = 'RDp1')
      and (select v->>'stock' = 'invoice_refund_return 1, store_sale 2' and v->>'gap' = '1/2/-1' from t481_res where phase = 'after' and k = 'RDp2')
      and (select (v->>'td')::int = 1 and (v->>'out')::int = 1 from t481_res where phase = 'after' and k = 'RDp3'),
    'K12: look at NOT COVERED 12 again');
  raise notice 'KNOWN K12: (481''s NOT COVERED 12; not 481''s) a refund by line returning more units than its money pays for: S$10 of the S$40 product with its unit returned (RDp1: 1 still to take on the paid invoice; RDp2: a store move then takes it again, the stock report listing a surplus of 1, as before 481); S$33.33 of the 3-unit S$100.00 line with 2 units returned (RDp3: 1 unit counted, 1 still to take; before 481, 2)';
  -- K13 (the review of 2 Nov 2026; for the Owner): an Edit Invoice that cuts
  -- a line a refund by line paid back. F1: before 481 the correction took the
  -- line's 2 again (2 out, a surplus of 1 listed), from 481 1 (1 out,
  -- nothing listed); the money the same, S$80 net and S$40 shown as due back.
  -- (Before 481 only where R ran: not with -v nomig=1.)
  o := (select v from t481_res where phase = 'after' and k = 'F1');
  o2 := (select v from t481_res where phase = 'before' and k = 'F1');
  perform pg_temp.t481_check((o->>'out')::int = 1 and o->>'gap' = '-' and (o->>'due')::numeric = 40 and (o->>'net')::numeric = 80
      and (o2 is null or (o2->>'out')::int = 2 and o2->>'gap' = '2/3/-1' and (o2->>'due')::numeric = 40 and (o2->>'net')::numeric = 80),
    'K13: look at NOT COVERED 13 again: ' || coalesce(o2::text, '-') || ' / ' || o::text);
  raise notice 'KNOWN K13: (481''s NOT COVERED 13) an Edit Invoice cutting a line a refund by line paid back counts the refund against the line as it reads after the cut: F1 (3 of the product paid, one unit''s S$40 refunded with the unit returned, the line cut to 2): before 481 the correction takes the line''s 2 again (2 out, the stock report a surplus of 1), from 481 1 (1 out, nothing listed); the money the same (S$80 net, S$40 shown as due back). Which is right depends on what the cut meant (a further return, or the invoice tidied to the units kept): for the Owner';
end $$;

rollback;
