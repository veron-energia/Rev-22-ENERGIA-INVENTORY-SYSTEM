-- 477: credit given back on a closed, locked or repaired lot follows the
-- same rules as any other: a special document's wallet refund opens the lot
-- it gives back on (refund_special_credit), an Owner may Move credit a
-- refund put back on a lot an Owner had reversed or Cancel's write-off of
-- credit released before full payment had locked
-- (transfer_invoice_unused_benefit), and credit given back on a lot 328's
-- repair replaced goes to the lot the records name (credit_given_back_
-- follows) (472's NOT COVERED 2, 4 and 1, and 477's first build's NOT
-- COVERED 1; the Owner, 27 Oct 2026: answer D for the last).
-- supabase/477_special_refund_move_repaired_lot.sql (after 462 to 476).
--
-- Every step goes through the app's own calls (472's suite harness, its
-- steps and readings, renamed; 473's reading of what an invoice's records
-- name: its release records' chains too): the invoice form
-- (create_invoice_with_details) and the Pay dialog
-- (record_invoice_settlement), Record Payment, Cancel, the Finance panel's
-- refund by line and "Record refund paid" (refund_invoice_recorded), its
-- Correct payment (correct_invoice_payment), Reopen, Move
-- (transfer_invoice_unused_benefit), the guided Cancel, the invoice form's
-- customer change (correct_invoice, 'transfer' or 'keep'); an Owner's
-- reversal is reverse_credit_lot called as an active Owner (no page calls
-- it); a special document's wallet payment is 462's stand-in (no page calls
-- pay_special_with_credit), its refund the real refund_special_credit;
-- 328's repair of a released lot is 472's stand-in made with its own
-- statements (a lot that keeps the package as its source, so a sale can be
-- paid from it; 327's lots can no longer be made). Each app call is
-- followed by what its commit does (462's trigger is deferred; SET
-- CONSTRAINTS ... IMMEDIATE, then DEFERRED).
--
-- The cases (A the buyer, B a later customer after a customer change, F a
-- friend an Owner moves credit to; cp the S$100 Credit Package; S1, S2 S$20
-- sessions paid from it, svc5 S$5; D1 a S$20 special document paid from it):
--   (a) PTsx, PTsxs, PTsxr, PTsxl  paid in full, D1 and S1, the S$60 left
--             reversed by an Owner, cancelled, D1 refunded (A tries to
--             spend; a rental or a rental's late fee instead of a sale).
--       PTsxp, PTsxo  the same, still paid (reopened and paid at once
--             first) (A spends it).
--       PTsxh, PTsxhc  cancelled, a 'transfer' change to B, reopened and
--             paid (cancelled again), D1 refunded.
--   (b) MVX   paid, two sessions, the S$60 left reversed, S1 refunded, an
--             Owner's Move of A's S$20 to F; MVXs, MVXsf then S2 refunded,
--             or F spends it; MVXr, MVXc after a reopening's payment;
--             MVXh on B's copy the reopening made after a 'transfer'
--             change; MVXrr reversed twice; MVS2 the released lot a Cancel
--             closed, opened by S1's refund, reversed, S2 refunded, moved;
--             MVXd the S$20 D1's refund put back on the reversed lot;
--             MVXcc, MVXcr moved, then cancelled (S2 refunded; reopened and
--             paid).
--   (c) R328, R328s, R328b  paid in part S$40, S1 from the released lot,
--             328's repair of it (the stand-in), paid in full, cancelled,
--             S1 refunded (A tries to spend; refunded by line); R328p still
--             paid; R328k after a 'keep' change; R328cc changed to B while
--             cancelled, reopened and paid; R3282 two S$5 sessions refunded;
--             R328f Correct payment instead of the refund; R328u, R328uf,
--             R328u2 not paid in full (refunded; corrected; two refunds);
--             R328up, R328uk then paid (after a 'keep' change); R328ur,
--             R328urp cancelled and reopened first (then paid); R328r
--             settled, cancelled, S1 refunded, reopened and paid; R328w,
--             R328wp refunded by line and reopened (waiting) before S1's
--             refund (A tries to spend; paid); R328x the guided Refund in
--             full first; R328g, R328gb the guided Cancel first (S$0 owed
--             back; then refunded by line).
--   (d) TQx1, TQx1p, TQx2, TQx1f, TQx1cc  (the review of 475 to 478) two
--             S$100 packages on one invoice, S$100 paid (the first released
--             in full), five S$20 sessions paid from it, a 'transfer' change
--             to B (nothing to move, nothing blocks), S1 refunded before
--             settlement (then paid; S2 refunded too; Correct payment
--             instead); a package paid in part, both sessions, cancelled,
--             changed to B, reopened, S1 refunded, paid.
--   Controls (the same with and without 477): PTsxb (the refund by line pays
--   the closed lot's S$20 back either way), PTsxw, PTsxwp (D1 refunded while
--   a reopening waits: the lot was open already), PTsp (a lot a Cancel's
--   write-off closed: taken back as 471 does), PTs0 (no reversal), MVXx
--   (nothing left to move), R328c (the 'transfer' change refused, 476),
--   R328uc (not paid in full, cancelled: taken back as 471 does), and 472's
--   PX, PXp, MV1p, RV1p, O1, PC, G2, S8gb; TQx1c (TQx1, then cancelled),
--   TQx1k ('keep' instead), TQx1F (one package paid in full, the same
--   spending, change and refund: B's), TQx0 (no change).
--   (e) MVW, MVW0, MVWt, MVWs, MVWsf, MVWcc, MVWcr, MVWf, MVWh, MVWk
--             (answer D, 477's first build's NOT COVERED 1) paid in part S$40,
--             S1 S$20 and S2 S$5 from the released lot, cancelled (the
--             write-off closes and locks it), reopened, paid, S1 refunded (the
--             lot open again, still locked), an Owner's Move of A's S$20 to F
--             (all of it spent when cancelled, so the write-off wrote no row
--             on it; B's copy after 476's TQcru 'transfer' change, then paid;
--             then S2 refunded, or F spends it; then cancelled and S2
--             refunded, or cancelled, reopened and paid; Correct payment
--             instead of the refund; S2 refunded while cancelled first; after
--             a 'keep' change). Its control MVL: a lock no Owner's reversal
--             and no release record explains (a stand-in, no function makes
--             one): the Move still refused.
-- In every case 462's invariants (473's reading) and Cancel (tried, undone)
-- taking all of the invoice's credit back from whoever holds it.
--
--   S. Where it starts: 462 to 476 in, the triggers on invoices as read;
--      477 in (nomig) or not, the three functions at their BEFORE.
--   R. Without 477 (skipped with -v nomig=1), undone: each 'fixed' case ends
--      otherwise (the faults reproduced: PTsx A S$20 on a closed lot of a
--      cancelled package; MVX refused; R328 A S$20 of a cancelled package;
--      R328p Cancel leaves S$20; ...; MVW refused); each control as
--      expected.
--   Q. The read-only query in 477's header (the same text), on states made
--      for it and the R states: what it lists, by reason (1 to 9).
--   9. Refusals, each changing nothing: a function at neither version, the
--      three at a mix of versions, a function relied on changed, a new
--      writer of 328's link, a function calling one of the two app
--      functions; the same grants in another order do not stop it.
--   M. Begun before 477, finished after it; and credit given back before
--      477 on a closed lot, or on a lot 328's repair replaced: left as it
--      is, then read with the next refund.
--  10. 477 installed twice: as tested, the second run changing nothing,
--      nothing added, the grants as before (as sets).
--   A. Each case after 477: who holds what, the money, the invariants,
--      Cancel; the controls exactly as before.
--   P. Probes: the lot a special document's refund opened (held back in
--      place, its reversal row as it was, the Audit Log, the statement); the
--      moved lot (unlocked, traced to its origin, spendable; the lot moved
--      from locked at S$0, its reversal's or write-off's row as it was); a
--      lot the write-off locked without a row of its own, moved by its
--      release record (MVW0); 328's repair on the history of a lot the
--      write-off locked, refused (P10, a stand-in row); the new lot
--      replacing the repair's lot (the
--      records name it, the Audit Log; before settlement, the lot the
--      release record reaches now, which the write-off reads); a lot
--      outside any invoice opened by a special document's refund.
--   K. KNOWN (477's NOT COVERED 1 to 3), checked as they are.
--
-- Run on a copy of production at 475 with 476 applied (27 Oct 2026:
-- cc718597, 1390 functions):
--   psql -X -v ON_ERROR_STOP=1 -f scripts/invoices/tests/special-refund-move-repaired-lot-477.sql
-- It installs 477 itself (twice) inside its transaction. Where 477 is in
-- already, add -v nomig=1 (S checks it as tested; R, Q, 9 and M are skipped;
-- every case after 477 is still checked). Section 9 lets the install fail on
-- purpose (psql prints its ERROR); the suite then checks that message.
-- Disposable database only; everything is rolled back. Every name, code and
-- amount is invented (@example.com); the phones are numbers kept for fiction
-- (ACMA, +61491570000 to +61491570999).
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '10s';
set local statement_timeout = '900s';

-- ── Set-up and the app's calls (472's suite harness, renamed, for 477) ──────
create temp table t477(k text primary key, id uuid);
create temp table t477_res(phase text, k text, v jsonb, primary key (phase, k));
create temp sequence t477_phone;
create function pg_temp.t477_id(p_k text) returns uuid language sql as $f$ select id from t477 where k = p_k $f$;
create function pg_temp.t477_put(p_k text, p_id uuid) returns uuid language sql as $f$
  insert into t477 values (p_k, p_id) on conflict (k) do update set id = excluded.id returning id $f$;
create function pg_temp.t477_check(p_ok boolean, p_label text) returns void language plpgsql as $f$
begin
  if not coalesce(p_ok, false) then raise exception 'FAIL %', p_label; end if;
end $f$;
create function pg_temp.t477_fingerprint() returns text language sql as $f$
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.oid::regprocedure::text)) || ' ' || count(*)
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prokind in ('f', 'p') $f$;
create function pg_temp.t477_463_in() returns boolean language sql as $f$
  select to_regprocedure('public.invoice_benefit_moved_to_other(uuid)') is not null $f$;
create function pg_temp.t477_462_in() returns boolean language sql as $f$
  select to_regprocedure('public.credit_given_back_follows(uuid)') is not null
     and exists (select 1 from pg_trigger where tgname = 'credit_given_back_follows'
                  and tgrelid = 'public.customer_credit_ledger'::regclass) $f$;
-- 471 is in: the forwarder keeps 471's text (472's and 477's do).
create function pg_temp.t477_471_in() returns boolean language sql as $f$
  select to_regprocedure('public.credit_given_back_follows(uuid)') is not null
     and position('-- 471 (the Owner, 26 Oct 2026' in pg_get_functiondef('public.credit_given_back_follows(uuid)'::regprocedure)) > 0 $f$;
-- 472 is in: the forwarder keeps 472's text (477's does).
create function pg_temp.t477_472_in() returns boolean language sql as $f$
  select to_regprocedure('public.credit_given_back_follows(uuid)') is not null
     and position('-- 472 (the Owner, 26 Oct 2026' in pg_get_functiondef('public.credit_given_back_follows(uuid)'::regprocedure)) > 0 $f$;
-- 473 is in: the list of what a customer change can move keeps 473's text
-- (476's does).
create function pg_temp.t477_473_in() returns boolean language sql as $f$
  select position('-- 473 (the Owner, 26 Oct 2026' in pg_get_functiondef('public.invoice_transferable_benefits(uuid)'::regprocedure)) > 0 $f$;
-- 470 is in (its text is in 471's, 472's and 477's too).
create function pg_temp.t477_470_in() returns boolean language sql as $f$
  select to_regprocedure('public.credit_given_back_follows(uuid)') is not null
     and position('-- 470 (the Owner, 24 Oct 2026' in pg_get_functiondef('public.credit_given_back_follows(uuid)'::regprocedure)) > 0 $f$;
-- 475 is in: reopen_invoice is 475's (its text says so).
create function pg_temp.t477_475_in() returns boolean language sql as $f$
  select position('-- 475 (the Owner, 27 Oct 2026' in pg_get_functiondef('public.reopen_invoice(uuid,text,uuid)'::regprocedure)) > 0 $f$;
-- 476 is in: the list is 476's (its text says so) and its helper is there.
create function pg_temp.t477_476_in() returns boolean language sql as $f$
  select position('-- 476 (the Owner, 27 Oct 2026' in pg_get_functiondef('public.invoice_transferable_benefits(uuid)'::regprocedure)) > 0
     and to_regprocedure('public.credit_line_benefits_holder(uuid)') is not null $f$;
-- 477 is in: the three functions it changes say so (S checks their md5s).
create function pg_temp.t477_in() returns boolean language sql as $f$
  select position('-- 477 (the Owner, 27 Oct 2026' in pg_get_functiondef('public.credit_given_back_follows(uuid)'::regprocedure)) > 0
     and position('-- 477 (the Owner, 27 Oct 2026' in pg_get_functiondef('public.refund_special_credit(text,uuid)'::regprocedure)) > 0
     and position('-- 477 (the Owner, 27 Oct 2026' in pg_get_functiondef('public.transfer_invoice_unused_benefit(uuid,uuid,uuid,text,uuid)'::regprocedure)) > 0 $f$;
-- What a commit does at the end of each app call (each is its own
-- transaction in the app): 462's deferred trigger on the ledger runs (471
-- adds no trigger: its change is in the function that trigger runs). Here
-- the suite is one transaction, so the trigger's queued rows are run at this
-- point. (Not where each step really commits: t477.autocommit 'on', for
-- running the same cases one call per transaction on a disposable copy.)
create function pg_temp.t477_commit() returns void language plpgsql as $f$
begin
  if coalesce(current_setting('t477.autocommit', true), '') = 'on' then return; end if;
  if pg_temp.t477_462_in() then
    execute 'set constraints public.credit_given_back_follows immediate';
    execute 'set constraints public.credit_given_back_follows deferred';
  end if;
end $f$;

do $$
declare own uuid := gen_random_uuid(); st uuid; st2 uuid; pm uuid; v uuid; cp uuid; cpb uuid; pbv uuid; svc uuid; svc5 uuid;
begin
  insert into auth.users(id, email) values (own, 't477-owner@example.com');
  insert into profiles(id, full_name, email, role, is_active) values (own, 'T477 Owner', 't477-owner@example.com', 'owner', true);
  perform set_config('request.jwt.claims', json_build_object('sub', own, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', own::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  insert into stores(name, code, country_code) values ('T477 Store', 'T477S1', 'SG') returning id into st;
  insert into stores(name, code, country_code) values ('T477 Other Store', 'T477S2', 'SG') returning id into st2;
  insert into payment_methods(name, is_active) values ('T477 Cash', true) returning id into pm;
  insert into vouchers(name, code, voucher_kind, qty_type, selling_price, is_active)
    values ('T477 Plain 30', 'T477-P30', 'normal', 'unlimited', 30, true) returning id into v;
  insert into voucher_store_prices(voucher_id, store_id, selling_price, available_at_store) values (v, st, 30, true), (v, st2, 30, true);
  insert into credit_packages(name, customer_price, paid_credit_amount, bonus_enabled, allow_product, allow_therapy)
    values ('T477 S$100', 100, 100, false, true, true) returning id into cp;
  insert into credit_package_stores(package_id, store_id) values (cp, st), (cp, st2);
  insert into credit_packages(name, customer_price, paid_credit_amount, bonus_enabled, bonus_value, allow_product, allow_therapy, grants_reward)
    values ('T477 S$100 + S$10', 100, 100, true, 10, true, true, false) returning id into cpb;
  insert into credit_package_stores(package_id, store_id) values (cpb, st), (cpb, st2);
  insert into premium_bundles(name, customer_payment_amount, paid_credit_amount, bonus_credit_amount, free_voucher_qty, grants_reward)
    values ('T477 Bundle S$140 + 2 vouchers', 140, 100, 40, 2, true) returning id into pbv;
  insert into premium_bundle_stores(bundle_id, store_id) values (pbv, st), (pbv, st2);
  insert into premium_bundle_vouchers(bundle_id, voucher_id) values (pbv, v);
  svc := (upsert_therapy_service(null, 'T477-SESSION', 'T477 Session', 20, 30, 'per_hours', 1, 5, null, true, null) ->> 'id')::uuid;
  perform set_therapy_service_store(svc, st, true, null);
  svc5 := (upsert_therapy_service(null, 'T477-SHORT', 'T477 Short session', 5, 15, 'per_hours', 1, 5, null, true, null) ->> 'id')::uuid;
  perform set_therapy_service_store(svc5, st, true, null);
  insert into t477 values ('own', own), ('store', st), ('store2', st2), ('pm', pm), ('v', v), ('cp', cp), ('cpb', cpb), ('pbv', pbv),
    ('svc', svc), ('svc5', svc5),
    ('wallet', (select id from payment_methods where name = 'Wallet — Credit Package Paid' and is_wallet_credit and deleted_at is null)),
    ('bwallet', (select id from payment_methods where name = 'Wallet — Premium Bundle Paid' and is_wallet_credit and deleted_at is null));
  perform pg_temp.t477_check(pg_temp.t477_id('wallet') is not null and pg_temp.t477_id('bwallet') is not null, 'setup: the wallet methods (443) are there');
end $$;

-- A customer of one run of one case: '<phase>/<case>/<role>'.
create function pg_temp.t477_cust(p_k text) returns uuid language plpgsql as $f$
declare c uuid;
begin
  insert into customers(full_name, phone) values ('T477 ' || p_k, '+61491570' || lpad((nextval('t477_phone') % 1000)::text, 3, '0'))
    returning id into c;
  return pg_temp.t477_put(p_k, c);
end $f$;
-- The invoice form with these lines ('cp' / 'cpb' a Credit Package, 'pbv' the
-- Premium Bundle, 'v' a voucher line of p_qty units), with an Owner's manual
-- discount of p_discount (its reason given) where one is given, paid through
-- the Pay dialog: in full, or p_first of it (a part-paid package).
create function pg_temp.t477_sale(p_cust uuid, p_kinds text[], p_first numeric default null, p_qty int default 2,
                                  p_discount numeric default null)
  returns uuid language plpgsql as $f$
declare inv uuid; v_lines jsonb := '[]'; i int;
begin
  for i in 1 .. cardinality(p_kinds) loop
    v_lines := v_lines || jsonb_build_array(case
      when p_kinds[i] = 'v' then jsonb_build_object('kind', 'voucher', 'voucher_id', pg_temp.t477_id('v'), 'quantity', p_qty)
      when p_kinds[i] in ('cp', 'cpb') then jsonb_build_object('kind', 'credit_package', 'credit_package_id', pg_temp.t477_id(p_kinds[i]), 'quantity', 1)
      else jsonb_build_object('kind', 'premium_bundle', 'premium_bundle_id', pg_temp.t477_id('pbv'), 'quantity', 1,
        'voucher_selection', jsonb_build_array(jsonb_build_object('voucher_id', pg_temp.t477_id('v'), 'quantity', 2))) end);
  end loop;
  inv := create_invoice_with_details(pg_temp.t477_id('store'), p_cust, v_lines, jsonb_build_object('business_date', sg_today()::text)
           || case when p_discount is not null
                   then jsonb_build_object('manual_discount', p_discount, 'manual_discount_reason', 'T477 discount') else '{}'::jsonb end);
  perform record_invoice_settlement(inv, jsonb_build_object('receipts', jsonb_build_array(jsonb_build_object(
    'key', 'line-0', 'payment_method_id', pg_temp.t477_id('pm'),
    'amount', coalesce(p_first, (select total_amount from invoices where id = inv)),
    'payment_date', sg_today()::text)), 'arrangements', '[]'::jsonb), gen_random_uuid());
  return inv;
end $f$;
-- Record Payment of what is outstanding (nothing when it is settled).
create function pg_temp.t477_pay(p_inv uuid) returns void language plpgsql as $f$
begin
  if (invoice_financial_position(p_inv)->>'outstanding')::numeric > 0 then
    perform record_invoice_payment(p_inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.t477_id('pm'),
      'amount', (invoice_financial_position(p_inv)->>'outstanding')::numeric)), gen_random_uuid());
  end if;
end $f$;
-- The receipts that still hold p_amount between them, as the Finance panel
-- splits a refund across them.
create function pg_temp.t477_sources(p_inv uuid, p_amount numeric) returns jsonb language plpgsql as $f$
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
create function pg_temp.t477_line(p_inv uuid, p_n int default 1) returns uuid language sql as $f$
  select id from invoice_items where invoice_id = p_inv order by id offset p_n - 1 limit 1 $f$;
-- The Finance panel's refund by line of line p_n: p_amount off its Paid
-- benefit (the one an Owner did not move, or with p_holder the one p_holder
-- holds), or every unused benefit it still holds (p_amount null).
create function pg_temp.t477_back(p_inv uuid, p_n int, p_amount numeric default null, p_holder uuid default null)
  returns void language plpgsql as $f$
declare opts jsonb; ben jsonb; tot numeric; item uuid := pg_temp.t477_line(p_inv, p_n);
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
  if ben is null then raise exception 'T477: nothing to refund on that line'; end if;
  perform refund_invoice_recorded(p_inv, jsonb_build_array(jsonb_build_object('invoice_item_id', item, 'amount', tot, 'benefits', ben)),
    pg_temp.t477_sources(p_inv, tot), '[]'::jsonb, 'T477 by line', gen_random_uuid());
end $f$;
-- The invoice form's customer change, its lines as they are (and the store,
-- when given), with 'transfer' or 'keep'. The change's Audit Log row is
-- dated now, as a later call's is (the suite is one transaction).
create function pg_temp.t477_lines(p_inv uuid) returns jsonb language sql as $f$
  select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('invoice_item_id', it.id, 'kind', it.line_kind,
           'credit_package_id', it.credit_package_id, 'premium_bundle_id', it.premium_bundle_id, 'voucher_id', it.voucher_id,
           'quantity', it.quantity, 'unit_price', it.unit_price, 'voucher_selection', it.bundle_voucher_selection)) order by it.id)
    from invoice_items it where it.invoice_id = p_inv $f$;
create function pg_temp.t477_change(p_inv uuid, p_cust uuid, p_action text default 'transfer', p_store text default null)
  returns void language plpgsql as $f$
begin
  perform correct_invoice(p_inv, pg_temp.t477_lines(p_inv),
    jsonb_build_object('expected_edit_count', (select edit_count from invoices where id = p_inv),
      'customer_id', p_cust, 'store_id', coalesce(pg_temp.t477_id(p_store), (select store_id from invoices where id = p_inv)),
      'benefit_action', p_action),
    'T477 wrong customer', gen_random_uuid());
  update audit_logs set created_at = clock_timestamp()
   where record_id = p_inv and action = 'invoice_benefits_followed_reassignment' and new_data->>'to_customer' = p_cust::text
     and created_at = now();
end $f$;
create function pg_temp.t477_merge(p_keep uuid, p_dup uuid) returns void language plpgsql as $f$
begin
  perform merge_customer_records(p_keep, p_dup, 'T477 the same person', gen_random_uuid());
end $f$;
-- The Finance panel's Move of line p_n's unused benefit (its Paid credit,
-- or its Bonus with p_kind 'bonus', or a voucher) to p_to, at p_store.
create function pg_temp.t477_move(p_inv uuid, p_n int, p_to uuid, p_kind text default 'paid', p_store text default null)
  returns void language plpgsql as $f$
declare b uuid;
begin
  select bv.id into b from invoice_benefit_values bv
    left join customer_reward_vouchers v on v.id = bv.reward_voucher_id
    left join customer_credit_lots l on l.id = bv.lot_id
   where bv.invoice_item_id = pg_temp.t477_line(p_inv, p_n)
     and (v.status = 'held' and p_kind = 'voucher' or l.remaining_amount > 0 and l.category = p_kind)
   order by bv.granted_value desc limit 1;
  if b is null then raise exception 'T477: nothing to move on that line'; end if;
  perform transfer_invoice_unused_benefit(b, p_to, coalesce(pg_temp.t477_id(p_store), (select store_id from invoices where id = p_inv)),
    'T477 move', gen_random_uuid());
end $f$;
-- The invoice form: p_n sessions of S$20 (or S$5 with p_svc 'svc5') for
-- p_cust, paid with the wallet (Credit Package Paid; Premium Bundle Paid with
-- p_wallet 'bwallet') through Record Payment.
create function pg_temp.t477_spend(p_cust uuid, p_n int default 1, p_svc text default 'svc', p_wallet text default 'wallet')
  returns uuid language plpgsql as $f$
declare inv uuid; v_lines jsonb := '[]'; i int;
begin
  for i in 1 .. p_n loop
    v_lines := v_lines || jsonb_build_array(jsonb_build_object('kind', 'therapy', 'therapy_service_id', pg_temp.t477_id(p_svc), 'quantity', 1));
  end loop;
  inv := create_invoice_with_details(pg_temp.t477_id('store'), p_cust, v_lines, jsonb_build_object('business_date', sg_today()::text));
  perform record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.t477_id(p_wallet),
    'amount', (select total_amount from invoices where id = inv))), gen_random_uuid());
  if (select status::text from invoices where id = inv) <> 'paid' then raise exception 'T477: the session paid from credit is not paid'; end if;
  return inv;
end $f$;
-- The session cancelled and "Record refund paid": what its payment took goes
-- back to the lots it came from (refund_invoice_recorded's wallet refund).
create function pg_temp.t477_unspend(p_inv uuid) returns void language plpgsql as $f$
declare due numeric;
begin
  perform cancel_invoice_recorded(p_inv, 'T477 cancel session', gen_random_uuid());
  due := (invoice_financial_position(p_inv)->>'refund_due')::numeric;
  if due is null or due <= 0 then due := (invoice_action_plan(p_inv, 'cancel', '[]')->>'refund_due')::numeric; end if;
  perform refund_invoice_recorded(p_inv, jsonb_build_array(jsonb_build_object('amount', due)), pg_temp.t477_sources(p_inv, due), '[]'::jsonb,
    'T477 refund paid', gen_random_uuid());
end $f$;
-- The Finance panel's Correct payment on a session's wallet payment: the
-- date only ('date'), a smaller amount ('amount', S$5 less), or another
-- method ('cash').
create function pg_temp.t477_fix(p_inv uuid, p_how text) returns void language plpgsql as $f$
declare p invoice_payments%rowtype;
begin
  select * into p from invoice_payments where invoice_id = p_inv and entry_kind in ('receipt', 'correction_replacement')
     and not exists (select 1 from invoice_payments q where q.corrects_payment_id = invoice_payments.id and q.entry_kind = 'correction_reversal')
   order by created_at desc, id desc limit 1;
  perform correct_invoice_payment(p.id,
    case p_how when 'amount' then p.amount - 5 else p.amount end,
    sg_today() - 1,
    case p_how when 'cash' then pg_temp.t477_id('pm') else p.payment_method_id end,
    'T477 correct payment ' || p_how, gen_random_uuid());
end $f$;
-- A special document's wallet payment as pay_special_with_credit records it
-- (a stand-in: no page calls that function, and no credit category allows a
-- special document today, purchase_category): p_amount off the customer's
-- largest lot ('use', its allocations), so refund_special_credit, the real
-- one, gives it back.
create function pg_temp.t477_special(p_cust uuid, p_kind text, p_doc uuid, p_amount numeric) returns void language plpgsql as $f$
declare l customer_credit_lots%rowtype; e uuid;
begin
  select * into l from customer_credit_lots where customer_id = p_cust and status = 'active' and remaining_amount >= p_amount
   order by remaining_amount desc, id limit 1 for update;
  insert into customer_credit_ledger(wallet_id, customer_id, entry_type, category, amount, lot_id, source_type, source_record_id, store_id, note, created_by)
  values (l.wallet_id, p_cust, 'use', l.category, p_amount, l.id, p_kind, p_doc, l.store_id, 'T477 special', auth.uid()) returning id into e;
  update customer_credit_lots set remaining_amount = remaining_amount - p_amount, updated_at = now() where id = l.id;
  insert into customer_credit_allocations(ledger_entry_id, lot_id, customer_id, amount) values (e, l.id, p_cust, p_amount);
  insert into special_credit_allocations(doc_kind, doc_id, customer_id, lot_id, category, amount, created_by)
  values (p_kind, p_doc, p_cust, l.id, l.category, p_amount, auth.uid());
end $f$;
-- The guided Refund in full / Cancel as an Owner confirms it, with a reason
-- for every override the plan asks for, the money recorded as paid back (or,
-- with p_record false, not: "Record refund paid" left unticked).
create function pg_temp.t477_guided(p_inv uuid, p_action text, p_record boolean default true) returns void language plpgsql as $f$
declare plan jsonb; req jsonb; ov jsonb;
begin
  plan := invoice_action_plan(p_inv, p_action, '[]');
  req := request_invoice_action_v2(p_inv, p_action, '[]', 'T477 ' || p_action, null, gen_random_uuid());
  select coalesce(jsonb_agg(case when coalesce((o->>'amount_required')::boolean, false)
           then jsonb_build_object('code', o->>'code', 'reason', 'T477 override', 'amount', (o->>'default_amount')::numeric)
           else jsonb_build_object('code', o->>'code', 'reason', 'T477 override') end), '[]'::jsonb)
    into ov from jsonb_array_elements(coalesce(plan->'overrides_required', '[]')) o;
  perform resolve_invoice_action_v2((req->>'request_id')::uuid, true, 'T477 ' || p_action, plan->>'plan_hash', ov, null, p_record);
end $f$;


-- ── What the records say ────────────────────────────────────────────────────
-- The lots an invoice's records name: its benefit values, its sale's lots, a
-- split's issued lot, released credit (credit_package_progress_lots).
create function pg_temp.t477_named(p_inv uuid) returns setof uuid language sql as $f$
  select lot_id from invoice_benefit_values where invoice_id = p_inv and lot_id is not null
  union select x from credit_package_sales s, unnest(array[s.credit_lot_id, s.bonus_credit_lot_id]) x where s.invoice_id = p_inv and x is not null
  union select x from premium_bundle_sales s, unnest(array[s.paid_credit_lot_id, s.bonus_credit_lot_id]) x where s.invoice_id = p_inv and x is not null
  union select issued_lot_id from invoice_credit_splits where invoice_id = p_inv and issued_lot_id is not null
  union select lot_id from credit_package_progress_lots where invoice_id = p_inv
  -- (473's reading: and each lot its release records' chains reach, which
  -- Cancel's write-off and the settlement read: credit_lot_chain)
  union select x from credit_package_progress_lots pl, unnest(credit_lot_chain(pl.lot_id)) x where pl.invoice_id = p_inv $f$;
-- The invoice's lot family (the critic's 6): every lot its records name and
-- each Move's two lots (from the Move's ledger rows), the lots each replaced
-- and every lot reissued from any of them.
create function pg_temp.t477_family(p_inv uuid) returns setof uuid language sql as $f$
  with recursive seed as (
    select x as id from pg_temp.t477_named(p_inv) x
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
create function pg_temp.t477_behind(p_inv uuid) returns setof uuid language sql as $f$
  with recursive c(id, n) as (
    select lot_id, 0 from invoice_benefit_values where invoice_id = p_inv and lot_id is not null
    union select p.id, c.n + 1 from c join customer_credit_lots l on l.id = c.id
            join customer_credit_lots p on p.id = l.reassigned_from_lot_id
             and (p.source_type, p.source_record_id) is not distinct from (l.source_type, l.source_record_id)
           where c.n < 12)
  select distinct id from c $f$;
-- How many lots back a lot's chain goes (reassigned_from_lot_id).
create function pg_temp.t477_depth(p_lot uuid) returns int language sql as $f$
  with recursive c(id, n) as (select p_lot, 0 union all
    select l.reassigned_from_lot_id, c.n + 1 from c join customer_credit_lots l on l.id = c.id
     where l.reassigned_from_lot_id is not null and c.n < 40)
  select max(n) from c $f$;
-- A lot's balance by its ledger rows: credit added (grants, increases,
-- credit returned: the 'reverse' rows that put credit back, as the
-- statement reads them, and 'rental_late_fee'), less credit taken (uses,
-- decreases, real reversals).
create function pg_temp.t477_ledger_balance(p_lot uuid) returns numeric language sql as $f$
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
--     (462's rule; a Move's lot by its recipient, following merges);
--   * no sale paid from a lot no record names, behind no lot a benefit row
--     names, can still be refunded (its credit would go back there);
--   * no benefit row holds back more than it granted, nor anything once
--     the invoice is settled again with no reopening waiting (the critics'
--     V1 to X2: a stale reserve let a later Refund in full leave credit);
--   * a refunded invoice leaves no credit on its family.
create function pg_temp.t477_invariants(p_inv uuid) returns text language plpgsql as $f$
declare probs text := ''; l record; root record; v uuid; st text := (select status::text from invoices where id = p_inv);
begin
  for l in select cl.* from customer_credit_lots cl where cl.id in (select pg_temp.t477_family(p_inv)) loop
    if l.remaining_amount > 0 and l.id not in (select pg_temp.t477_named(p_inv)) then
      probs := probs || format(' S$%s on a lot no record names (%s);', l.remaining_amount, (select full_name from customers where id = l.customer_id)); end if;
    if l.id not in (select pg_temp.t477_named(p_inv)) and l.id not in (select pg_temp.t477_behind(p_inv))
       and (exists (select 1 from invoice_line_credit_allocations a where a.lot_id = l.id and a.amount > coalesce(a.reversed_amount, 0))
            or exists (select 1 from special_credit_allocations s where s.lot_id = l.id and s.amount > coalesce(s.reversed_amount, 0))) then
      probs := probs || ' a sale paid from a lot no record names can still be refunded (its credit would stay there);'; end if;
    if pg_temp.t477_ledger_balance(l.id) <> l.remaining_amount then
      probs := probs || format(' lot holds %s, its ledger %s;', l.remaining_amount, pg_temp.t477_ledger_balance(l.id)); end if;
    if pg_temp.t477_depth(l.id) > 12 then probs := probs || format(' chain %s lots deep;', pg_temp.t477_depth(l.id)); end if;
    if l.remaining_amount > 0 and l.source_type = 'invoice_benefit_transfer'
       and (invoice_credit_transfer_origin(l.id) is null or credit_lot_policy_for(l.id) = 'needs_review') then
      probs := probs || ' a moved lot lost its origin;'; end if;
  end loop;
  for l in select bv.id as bid, bv.lot_id, cl.customer_id, cl.remaining_amount, cl.created_at, cl.source_type, cl.source_record_id,
                  cl.category, cl.usage_restrictions,
                  exists (select 1 from invoice_benefit_transfers t where t.replacement_benefit_id = bv.id) as moved_in
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
  if st = 'refunded' and (select coalesce(sum(remaining_amount), 0) from customer_credit_lots where id in (select pg_temp.t477_family(p_inv))) > 0 then
    probs := probs || format(' refunded, but S$%s of its credit is still held;',
      (select sum(remaining_amount) from customer_credit_lots where id in (select pg_temp.t477_family(p_inv)))); end if;
  return probs;
end $f$;
-- Credit left on the invoice's family once Cancel has run, the Cancel undone
-- (0 when Cancel takes it all back from whoever holds it); null when the
-- invoice cannot be cancelled now, -1 when Cancel is refused.
create function pg_temp.t477_cancel_left(p_inv uuid) returns numeric language plpgsql as $f$
declare v numeric;
begin
  if (select status::text from invoices where id = p_inv) not in ('paid', 'partially_paid', 'unpaid') then return null; end if;
  begin
    perform cancel_invoice_recorded(p_inv, 'T477 probe', gen_random_uuid());
    perform pg_temp.t477_commit();
    v := (select coalesce(sum(remaining_amount), 0) from customer_credit_lots where id in (select pg_temp.t477_family(p_inv)));
    raise exception using errcode = 'P0461', message = v::text;
  exception when sqlstate 'P0461' then return sqlerrm::numeric;
            when others then return -1;
  end;
end $f$;
create function pg_temp.t477_codes(p_inv uuid, p_action text) returns text language plpgsql as $f$
begin
  return (select coalesce(string_agg(o->>'code', ',' order by o->>'code'), '-')
            from jsonb_array_elements(coalesce(invoice_action_plan(p_inv, p_action, '[]')->'overrides_required', '[]')) o);
exception when others then return 'ERR';
end $f$;
create function pg_temp.t477_due(p_inv uuid, p_action text) returns numeric language plpgsql as $f$
begin
  return (invoice_action_plan(p_inv, p_action, '[]')->>case when p_action = 'cancel' then 'refund_due' else 'refund_amount' end)::numeric;
exception when others then return null;
end $f$;
-- The invoice's money: what is owed back (cancel_refund_owed), the Finance
-- panel's refund due, net received and kept for what was used, what a
-- refund by line can still pay back (the refund options' max_refund, every
-- benefit) and Cancel's refund due (the plan's).
create function pg_temp.t477_money(p_inv uuid) returns jsonb language sql as $f$
  select jsonb_build_object('owed', i.cancel_refund_owed,
    'due', (invoice_financial_position(i.id)->>'refund_due')::numeric,
    'net', (invoice_financial_position(i.id)->>'net_received')::numeric,
    'kept', (invoice_financial_position(i.id)->>'kept_for_used')::numeric,
    'by_line', (select coalesce(sum((b->>'max_refund')::numeric), 0)
                  from jsonb_array_elements(invoice_refund_options_before_sessions(i.id)->'benefits') b),
    'plan_due', pg_temp.t477_due(i.id, 'cancel'))
    from invoices i where i.id = p_inv $f$;


-- ── The cases ───────────────────────────────────────────────────────────────
-- A case is a list of steps, each one app call (and its commit), on the
-- case's own customers (A the buyer, B and C later customers, K and K2
-- records a merge keeps, F and G friends an Owner moved credit to). A step
-- refused stops the case, the refusal recorded. Steps:
--   sale R kinds [first]  the invoice (cp, cpb, pbv, v; part-paid: first)
--   saled R kinds disc    the invoice with an Owner's manual discount of disc, paid in full
--   pay                   Record Payment of what is outstanding
--   back N amt|all [R]    refund by line of line N (R: the benefit R holds)
--   move N R [kind] [store2]  an Owner's Move of line N's credit (or voucher)
--   cancel, reopen, wait  Cancel; Reopen; Cancel + every line paid back + Reopen
--   refundall             the guided Refund in full, recorded
--   change R [keep] [store2]  the customer change ('transfer' unless keep)
--   merge KEEP DUP        a customer merge
--   spend R [n] [svc5] [bwallet]  a session invoice (n lines) for R paid from credit
--                         (Credit Package Paid; Premium Bundle Paid with bwallet)
--   unspend Sn            that session cancelled and its refund recorded
--   fix Sn date|amount|cash   the Finance panel's Correct payment on it
--   sale2 R               another S$100 package for R (paid)
--   delete R              delete_customer
--   special R kind amt / unspecial Dn  special-document credit and its refund
--   reverse R | closed    an Owner's reversal of R's largest lot (or of the
--                         released lot a Cancel closed, a refund having opened it again)
--   guidedcancel          the guided Cancel as an Owner confirms it, "Record refund paid" ticked
--   guidedkeep            the same, "Record refund paid" not ticked
--   refundpaid            "Record refund paid" of what the invoice owes back (no line)
--   backx N               a refund by line of all line N still holds in money, above
--                         its unused benefits (an Owner's 'larger_refund')
--   backo N amt           a refund by line of all line N cost in money, taking back only amt of
--                         its credit (an Owner's 'larger_refund' covering the rest; an API call)
--   legacy STATUS         a stand-in for the legacy statuses (no page sets them now)
--   repair                repair_credit_package_progress_lots()
--   repair328             a stand-in for 328's repair of the invoice's first
--                         lot of credit released before full payment (its own
--                         statements: the rest reversed, 'credit_lot_provenance_repair',
--                         locked, granted again as a lot that replaces it)
--   lock R                a stand-in for a lock that no Owner's reversal and no
--                         release record explains (no function makes one): R's
--                         largest lot holding credit locked, no ledger row
create function pg_temp.t477_role(p_pre text, p_r text) returns uuid language plpgsql as $f$
begin
  return coalesce(pg_temp.t477_id(p_pre || '/' || p_r), pg_temp.t477_cust(p_pre || '/' || p_r));
end $f$;
-- One step of a case (one app call, then what its commit does). Null, or
-- the step and the refusal; a refused step changes nothing.
create function pg_temp.t477_step(p_pre text, p_st text) returns text language plpgsql as $f$
declare w text[] := regexp_split_to_array(btrim(p_st), '\s+'); inv uuid := pg_temp.t477_id(p_pre || '/inv'); x uuid; i int; n int;
begin
  case w[1]
  when 'sale' then
    perform pg_temp.t477_put(p_pre || '/inv', pg_temp.t477_sale(pg_temp.t477_role(p_pre, w[2]), string_to_array(w[3], ','), w[4]::numeric));
  when 'saled' then
    perform pg_temp.t477_put(p_pre || '/inv', pg_temp.t477_sale(pg_temp.t477_role(p_pre, w[2]), string_to_array(w[3], ','), null, 2, w[4]::numeric));
  when 'sale2' then
    perform pg_temp.t477_put(p_pre || '/inv2', pg_temp.t477_sale(pg_temp.t477_role(p_pre, w[2]), array['cp']));
  when 'pay' then perform pg_temp.t477_pay(inv);
  when 'back' then
    perform pg_temp.t477_back(inv, w[2]::int, case when w[3] = 'all' then null else w[3]::numeric end,
                              case when w[4] is not null then pg_temp.t477_role(p_pre, w[4]) end);
  when 'movel' then
    -- 477: an Owner's Move of line N's benefit whose lot is locked (opened
    -- again by a refund: an Owner's reversal, or Cancel's write-off)
    perform transfer_invoice_unused_benefit(
      (select bv.id from invoice_benefit_values bv join customer_credit_lots l on l.id = bv.lot_id
        where bv.invoice_item_id = pg_temp.t477_line(inv, w[2]::int) and l.is_locked and l.remaining_amount > 0
        order by bv.created_at, bv.id limit 1),
      pg_temp.t477_role(p_pre, w[3]), (select store_id from invoices where id = inv), 'T477 move', gen_random_uuid());
  when 'move' then
    perform pg_temp.t477_move(inv, w[2]::int, pg_temp.t477_role(p_pre, w[3]),
      case when w[4] in ('bonus', 'voucher') then w[4] else 'paid' end,
      case when 'store2' = any (w) then 'store2' end);
  when 'cancel' then perform cancel_invoice_recorded(inv, 'T477 cancel', gen_random_uuid());
  when 'reopen' then perform reopen_invoice(inv, 'T477 reopen', gen_random_uuid());
  when 'wait' then
    perform cancel_invoice_recorded(inv, 'T477 cancel', gen_random_uuid());
    for i in 1 .. (select count(*)::int from invoice_items where invoice_id = inv) loop
      perform pg_temp.t477_back(inv, i);
    end loop;
    perform reopen_invoice(inv, 'T477 reopen', gen_random_uuid());
  when 'refundall' then perform pg_temp.t477_guided(inv, 'refund_full');
  when 'change' then
    perform pg_temp.t477_change(inv, pg_temp.t477_role(p_pre, w[2]), case when 'keep' = any (w) then 'keep' else 'transfer' end,
                                case when 'store2' = any (w) then 'store2' end);
  when 'merge' then perform pg_temp.t477_merge(pg_temp.t477_role(p_pre, w[2]), pg_temp.t477_role(p_pre, w[3]));
  when 'spend' then
    n := (select count(*) from t477 where k ~ ('^' || p_pre || '/S[0-9]+$')) + 1;
    perform pg_temp.t477_put(p_pre || '/S' || n,
      pg_temp.t477_spend(pg_temp.t477_role(p_pre, w[2]), case when w[3] ~ '^[0-9]+$' then w[3]::int else 1 end,
        case when 'svc5' = any (w) then 'svc5' else 'svc' end, case when 'bwallet' = any (w) then 'bwallet' else 'wallet' end));
  when 'unspend' then perform pg_temp.t477_unspend(pg_temp.t477_id(p_pre || '/' || w[2]));
  when 'fix' then perform pg_temp.t477_fix(pg_temp.t477_id(p_pre || '/' || w[2]), w[3]);
  when 'delete' then
    x := pg_temp.t477_role(p_pre, w[2]);
    perform delete_customer(x, (select full_name from customers where id = x), 'T477 delete');
  when 'special' then
    n := (select count(*) from t477 where k ~ ('^' || p_pre || '/D[0-9]+$')) + 1; x := gen_random_uuid();
    perform pg_temp.t477_put(p_pre || '/D' || n, x);
    perform pg_temp.t477_put(p_pre || '/D' || n || '/kind:' || w[3], null);
    perform pg_temp.t477_special(pg_temp.t477_role(p_pre, w[2]), w[3], x, w[4]::numeric);
  when 'unspecial' then
    perform refund_special_credit((select split_part(k, 'kind:', 2) from t477 where k like p_pre || '/' || w[2] || '/kind:%'),
                                  pg_temp.t477_id(p_pre || '/' || w[2]));
  when 'reverse' then
    if w[2] = 'closed' then
      -- the released lot a Cancel's write-off closed, once a refund opened it again
      perform reverse_credit_lot(pg_temp.t477_closed_lot(inv), 'T477 reversal');
    else
      x := pg_temp.t477_role(p_pre, w[2]);
      perform reverse_credit_lot((select id from customer_credit_lots where customer_id = x and remaining_amount > 0
                                   order by remaining_amount desc, id limit 1), 'T477 reversal');
    end if;
  when 'lock' then
    -- 477 (answer D's control): a lock no record explains (a stand-in)
    x := pg_temp.t477_role(p_pre, w[2]);
    update customer_credit_lots set is_locked = true, updated_at = now()
     where id = (select id from customer_credit_lots where customer_id = x and remaining_amount > 0 and status = 'active'
                  order by remaining_amount desc, id limit 1);
  when 'grant' then
    -- 477: wallet credit of another kind (an Owner's S$amt grant, no invoice)
    perform grant_customer_credit(pg_temp.t477_role(p_pre, w[2]), 'paid', w[3]::numeric, 'manual', null, pg_temp.t477_id('store'),
      sg_today(), null, 'T477 grant', 'T477 grant', sg_today(), auth.uid(), null);
  when 'guidedcancel' then perform pg_temp.t477_guided(inv, 'cancel');
  when 'guidedkeep' then perform pg_temp.t477_guided(inv, 'cancel', false);
  when 'backo' then
    x := pg_temp.t477_line(inv, w[2]::int);
    perform refund_invoice_recorded(inv, jsonb_build_array(jsonb_build_object('invoice_item_id', x,
        'amount', invoice_discounted_line_value(x),
        'benefits', jsonb_build_array(jsonb_build_object('benefit_id', pg_temp.t477_own(inv), 'amount', w[3]::numeric)),
        'override', jsonb_build_object('code', 'larger_refund', 'reason', 'T477 larger refund', 'amount', invoice_discounted_line_value(x)))),
      pg_temp.t477_sources(inv, invoice_net_received(inv)), '[]'::jsonb, 'T477 larger refund', gen_random_uuid());
  when 'refundpaid' then
    perform refund_invoice_recorded(inv, jsonb_build_array(jsonb_build_object('amount',
        coalesce(nullif((invoice_financial_position(inv)->>'refund_due')::numeric, 0), (invoice_action_plan(inv, 'cancel', '[]')->>'refund_due')::numeric))),
      pg_temp.t477_sources(inv, coalesce(nullif((invoice_financial_position(inv)->>'refund_due')::numeric, 0), (invoice_action_plan(inv, 'cancel', '[]')->>'refund_due')::numeric)),
      '[]'::jsonb, 'T477 refund paid', gen_random_uuid());
  when 'backx' then
    x := pg_temp.t477_line(inv, w[2]::int);
    perform refund_invoice_recorded(inv, jsonb_build_array(jsonb_build_object('invoice_item_id', x,
        'amount', invoice_discounted_line_value(x) - coalesce((select sum((e->>'amount')::numeric) from invoice_refunds r,
             jsonb_array_elements(coalesce(r.outcome->'lines', '[]')) e where r.invoice_id = inv and e->>'invoice_item_id' = x::text), 0),
        'benefits', (select jsonb_agg(jsonb_build_object('benefit_id', b->>'id', 'amount', (b->>'max_refund')::numeric))
                       from jsonb_array_elements(invoice_refund_options_before_sessions(inv)->'benefits') b
                      where b->>'invoice_item_id' = x::text and (b->>'max_refund')::numeric > 0),
        'override', jsonb_build_object('code', 'larger_refund', 'reason', 'T477 larger refund',
          'amount', invoice_discounted_line_value(x) - coalesce((select sum((e->>'amount')::numeric) from invoice_refunds r,
             jsonb_array_elements(coalesce(r.outcome->'lines', '[]')) e where r.invoice_id = inv and e->>'invoice_item_id' = x::text), 0)))),
      pg_temp.t477_sources(inv, invoice_net_received(inv)), '[]'::jsonb, 'T477 larger refund', gen_random_uuid());
  when 'legacy' then
    update invoices set status = w[2]::invoice_status where id = inv;
  when 'repair' then perform repair_credit_package_progress_lots();
  when 'repair328' then perform pg_temp.t477_repair328(inv);
  else raise exception 'T477: unknown step %', p_st;
  end case;
  perform pg_temp.t477_commit();
  return null;
exception when others then
  return btrim(p_st) || ': ' || sqlerrm;
end $f$;
-- What a case ends with: the invoice's status and money, who holds what
-- (credit, '/n' held vouchers), the plans' codes and refund due (Cancel's
-- refund due; Refund in full's amount), the refusal that stopped it, what is
-- wrong with its credit, and the credit Cancel would leave behind.
create function pg_temp.t477_outcome(p_pre text, p_err text) returns jsonb language sql as $f$
  select jsonb_build_object(
    'status', (select status::text from invoices where id = i.id),
    'net', invoice_net_received(i.id),
    -- 471: what is owed back (stated), the Finance panel's refund due, and
    -- what the invoice's credit rows hold back for its cancellation.
    'owed', (select cancel_refund_owed from invoices where id = i.id),
    'fdue', (invoice_financial_position(i.id)->>'refund_due')::numeric,
    'held', (select coalesce(sum(cancelled_unused_value), 0) from invoice_benefit_values where invoice_id = i.id and lot_id is not null),
    'holds', (select jsonb_object_agg(split_part(t.k, '/', 3),
                (select coalesce(sum(l.remaining_amount), 0) from customer_credit_lots l where l.customer_id = t.id)::numeric(12,2)::text
                || coalesce('/' || nullif((select sum(v.quantity) from customer_reward_vouchers v where v.customer_id = t.id and v.status = 'held'), 0)::text, ''))
              from t477 t where t.k like p_pre || '/%' and split_part(t.k, '/', 4) = ''
                and split_part(t.k, '/', 3) !~ '^(inv|inv2|S[0-9]+|D[0-9]+|err)$'),
    'cancel', pg_temp.t477_codes(i.id, 'cancel'),
    'due', pg_temp.t477_due(i.id, 'cancel'),
    'refund', pg_temp.t477_codes(i.id, 'refund_full'),
    'rdue', pg_temp.t477_due(i.id, 'refund_full'),
    'error', p_err,
    'invariants', pg_temp.t477_invariants(i.id),
    'cancel_left', pg_temp.t477_cancel_left(i.id))
    from (select pg_temp.t477_id(p_pre || '/inv') as id) i $f$;
-- A case's steps p_from to p_to (all by default), stopping at a refusal;
-- with p_to null, its outcome (kept in t477_res under p_phase).
create temp table t477_err(pre text primary key, err text);
create function pg_temp.t477_run(p_phase text, p_case text, p_steps text, p_from int default 1, p_to int default null)
  returns jsonb language plpgsql as $f$
declare v_pre text := p_phase || '/' || p_case; st text[] := string_to_array(p_steps, ';'); i int; v_err text; v_out jsonb;
begin
  v_err := (select e.err from t477_err e where e.pre = v_pre);
  for i in p_from .. least(coalesce(p_to, cardinality(st)), cardinality(st)) loop
    exit when v_err is not null;
    continue when btrim(st[i]) = '';
    v_err := pg_temp.t477_step(v_pre, st[i]);
  end loop;
  insert into t477_err values (v_pre, v_err) on conflict (pre) do update set err = excluded.err;
  if p_to is not null then return null; end if;
  v_out := pg_temp.t477_outcome(v_pre, v_err);
  insert into t477_res values (p_phase, p_case, v_out) on conflict (phase, k) do update set v = excluded.v;
  return v_out;
end $f$;

-- Whether an outcome has what is expected: each key equal ('holds' as a
-- containment of who holds what), a key ending in '~' as a LIKE pattern of
-- that key's text.
create function pg_temp.t477_meets(p_out jsonb, p_exp jsonb) returns boolean language sql as $f$
  select coalesce(bool_and(case
           when e.key like '%~' then coalesce(p_out->>left(e.key, -1), '') like (e.value #>> '{}')
           when e.key = 'holds' then coalesce(p_out->'holds', '{}') @> e.value
           when jsonb_typeof(e.value) = 'number' then coalesce((p_out->>e.key)::numeric = (e.value #>> '{}')::numeric, false)
           else (p_out->e.key) is not distinct from e.value end), true)
    from jsonb_each(p_exp) e $f$;
-- What differs between an outcome and what is expected (for the FAIL line).
create function pg_temp.t477_diff(p_out jsonb, p_exp jsonb) returns text language sql as $f$
  select string_agg(e.key || ': wanted ' || e.value::text || ', got ' || coalesce(p_out->left(e.key, case when e.key like '%~' then -1 else 1000 end), 'null')::text, '; ')
    from jsonb_each(p_exp) e where not pg_temp.t477_meets(p_out, jsonb_build_object(e.key, e.value)) $f$;

-- ── 471's own readings ──────────────────────────────────────────────────────
-- The held-back reason (470's, which 471 writes too), and its rows on a lot.
create function pg_temp.t477_held(p_lot uuid) returns numeric language sql as $f$
  select coalesce(sum(e.amount), 0) from customer_credit_ledger e
   where e.lot_id = p_lot and e.entry_type = 'adjust_decrease' and e.source_type = 'invoice_cancel_benefit'
     and e.reason = 'Held back by the invoice''s cancellation for whoever holds its benefits now' $f$;
-- (B) what is held back on a lot of credit released before full payment
-- (Cancel's write-off's kind of row, 471's reason).
create function pg_temp.t477_held_rel(p_lot uuid) returns numeric language sql as $f$
  select coalesce(sum(e.amount), 0) from customer_credit_ledger e
   where e.lot_id = p_lot and e.entry_type = 'adjust_decrease' and e.source_type in ('invoice_cancel_released_credit', 'invoice_refund_released_credit')
     and e.reason = 'Held back by the invoice''s cancellation: credit released before it was paid in full' $f$;
-- The release record of an invoice (its first; the cases have one) and its lot.
create function pg_temp.t477_rel_lot(p_inv uuid) returns uuid language sql as $f$
  select lot_id from credit_package_progress_lots where invoice_id = p_inv order by created_at, lot_id limit 1 $f$;
-- The lot of an invoice's release record that a Cancel's write-off closed
-- (locked; after a reopening the release record has a second, open lot).
create function pg_temp.t477_closed_lot(p_inv uuid) returns uuid language sql as $f$
  select pl.lot_id from credit_package_progress_lots pl join customer_credit_lots l on l.id = pl.lot_id
   where pl.invoice_id = p_inv and l.is_locked order by pl.lot_id limit 1 $f$;
create function pg_temp.t477_held_n(p_lot uuid) returns int language sql as $f$
  select count(*)::int from customer_credit_ledger e
   where e.lot_id = p_lot and e.entry_type = 'adjust_decrease' and e.source_type = 'invoice_cancel_benefit'
     and e.reason = 'Held back by the invoice''s cancellation for whoever holds its benefits now' $f$;
-- The package's own benefit row (the one an Owner did not move in), and the
-- lot it names.
create function pg_temp.t477_own(p_inv uuid) returns uuid language sql as $f$
  select bv.id from invoice_benefit_values bv
   where bv.invoice_id = p_inv and bv.lot_id is not null
     and not exists (select 1 from invoice_benefit_transfers t where t.replacement_benefit_id = bv.id)
   order by bv.created_at, bv.id limit 1 $f$;
create function pg_temp.t477_own_lot(p_inv uuid) returns uuid language sql as $f$
  select lot_id from invoice_benefit_values where id = pg_temp.t477_own(p_inv) $f$;
-- Unapplied queue rows of an invoice on a lot (count, sum, requests).
create function pg_temp.t477_waiting(p_inv uuid, p_lot uuid) returns text language sql as $f$
  select count(*) || '/' || coalesce(sum(q.amount), 0) || '/' || count(distinct q.request_id)
    from invoice_reopen_benefits q join customer_credit_ledger e on e.id = q.source_ledger_id
   where q.invoice_id = p_inv and q.applied_at is null and e.lot_id = p_lot $f$;
-- The triggers on invoices (their definitions, by name; search_path public,
-- as the migration reads them).
create function pg_temp.t477_inv_triggers() returns text language plpgsql as $f$
declare v text; p text := current_setting('search_path');
begin
  perform set_config('search_path', 'public', true);
  select md5(string_agg(pg_get_triggerdef(oid), E'\n' order by tgname)) || ' ' || count(*) into v
    from pg_trigger where tgrelid = 'public.invoices'::regclass and not tgisinternal;
  perform set_config('search_path', p, true);
  return v;
end $f$;-- 328's repair of the invoice's first lot of credit released before full
-- payment, with its own statements (a stand-in: 327's lots, which the real
-- repair reads, can no longer be made; this lot keeps the package as its
-- source, so unlike 327's it can be spent from: released-credit-paths' shape).
create function pg_temp.t477_repair328(p_inv uuid) returns uuid language plpgsql as $f$
declare r record; pk credit_packages%rowtype; v_new uuid; v_rem numeric;
begin
  select l.*, it.id as invoice_item_id, it.invoice_id, it.credit_package_id into r
    from credit_package_progress_lots pl
    join customer_credit_lots l on l.id = pl.lot_id
    join invoice_items it on it.id = pl.invoice_item_id
   where pl.invoice_id = p_inv order by pl.created_at, pl.lot_id limit 1;
  if r.id is null or r.remaining_amount <= 0 then raise exception 'T477: no released lot holding credit to repair'; end if;
  select * into pk from credit_packages where id = r.credit_package_id;
  update credit_package_progress_lots set released_amount = r.original_amount where lot_id = r.id;
  v_rem := r.remaining_amount;
  insert into customer_credit_ledger (wallet_id, customer_id, entry_type, category, amount, lot_id,
    source_type, source_record_id, store_id, effective_date, reason, created_by, approved_by)
  values (r.wallet_id, r.customer_id, 'reverse', r.category, v_rem, r.id,
    'credit_lot_provenance_repair', r.id, r.store_id, sg_today(),
    'Replaced by a lot that carries its package (328)', auth.uid(), auth.uid());
  update customer_credit_lots set remaining_amount = 0, status = 'reversed', is_locked = true, updated_at = now() where id = r.id;
  v_new := grant_customer_credit(r.customer_id, r.category, v_rem, 'credit_package', pk.id, r.store_id,
    r.effective_date, r.reference_no, 'Credit package (paid so far): ' || pk.name,
    'Replaces lot ' || r.id || ', which carried the wrong source (328)', r.original_purchase_date, auth.uid(), r.usage_restrictions);
  insert into credit_package_progress_lots (lot_id, invoice_item_id, invoice_id, released_amount, replaces_lot_id)
  values (v_new, r.invoice_item_id, r.invoice_id, 0, r.id);
  return v_new;
end $f$;


-- ── 477's cases ─────────────────────────────────────────────────────────────
-- (k, kind, steps, what 477 gives). kind: 'fixed' (before 477 it ends
-- otherwise: the fault is reproduced first), 'control' (the same with and
-- without 477, every key of the outcome), 'known' (a NOT COVERED item,
-- checked as it is: the same with and without 477, as a control). Every
-- case also checks the invariants and that Cancel takes everything back
-- from whoever holds it (but where the case says what it leaves:
-- 'cancel_left').
create temp table t477_cases(k text primary key, kind text not null, steps text not null, expect jsonb not null, ord serial);
insert into t477_cases(k, kind, steps, expect) values
-- (a) 472's NOT COVERED 2: paid in full, D1 and S1, the S$60 left reversed
-- by an Owner, cancelled, D1 refunded: held back (A tries to spend it; a
-- rental); still paid: A's to spend; after a 'transfer' change: B's.
('PTsx', 'fixed', 'sale A cp; special A special_sale 20; spend A; reverse A; cancel; unspecial D1',
  '{"holds":{"A":"0.00"},"status":"cancelled","net":100,"held":20,"error":null}'),
('PTsxs', 'fixed', 'sale A cp; special A special_sale 20; spend A; reverse A; cancel; unspecial D1; spend A',
  '{"holds":{"A":"0.00"},"status":"cancelled","net":100,"held":20,"error~":"spend A: Only 0 of the requested 20.00 could be funded by eligible credit%"}'),
('PTsxp', 'fixed', 'sale A cp; special A special_sale 20; spend A; reverse A; unspecial D1; spend A',
  '{"holds":{"A":"0.00"},"status":"paid","net":100,"held":0,"error":null}'),
('PTsxr', 'fixed', 'sale A cp; special A rental 20; spend A; reverse A; cancel; unspecial D1',
  '{"holds":{"A":"0.00"},"status":"cancelled","net":100,"held":20,"error":null}'),
('PTsxh', 'fixed', 'sale A cp; special A special_sale 20; spend A; reverse A; cancel; change B; reopen; pay; unspecial D1',
  '{"holds":{"A":"0.00","B":"20.00"},"status":"paid","net":100,"held":0,"error":null}'),
('PTsxhc', 'fixed', 'sale A cp; special A special_sale 20; spend A; reverse A; cancel; change B; reopen; pay; cancel; unspecial D1',
  '{"holds":{"A":"0.00","B":"0.00"},"status":"cancelled","net":100,"held":20,"error":null}'),
-- (reopened, paid at once, then D1 refunded and A spends it; a rental's
-- late fee instead of a special sale)
('PTsxo', 'fixed', 'sale A cp; special A special_sale 20; spend A; reverse A; cancel; reopen; unspecial D1; spend A',
  '{"holds":{"A":"0.00"},"status":"paid","net":100,"held":0,"error":null}'),
('PTsxl', 'fixed', 'sale A cp; special A rental_late_fee 20; spend A; reverse A; cancel; unspecial D1',
  '{"holds":{"A":"0.00"},"status":"cancelled","net":100,"held":20,"error":null}'),
-- (b) 472's NOT COVERED 4: S1 refunded after the reversal, an Owner's Move
-- of A's S$20 to F (then S2 refunded; F spends it); after a reopening's
-- payment; on B's copy of A's lot; reversed twice; the released lot a
-- Cancel closed, opened, reversed, S2 refunded, moved.
('MVX', 'fixed', 'sale A cp; spend A; spend A; reverse A; unspend S1; move 1 F',
  '{"holds":{"A":"0.00","F":"20.00"},"status":"paid","net":100,"held":0,"error":null}'),
('MVXs', 'fixed', 'sale A cp; spend A; spend A; reverse A; unspend S1; move 1 F; unspend S2',
  '{"holds":{"A":"20.00","F":"20.00"},"status":"paid","net":100,"held":0,"error":null}'),
('MVXsf', 'fixed', 'sale A cp; spend A; spend A; reverse A; unspend S1; move 1 F; spend F',
  '{"holds":{"A":"0.00","F":"0.00"},"status":"paid","net":100,"held":0,"error":null}'),
('MVXr', 'fixed', 'sale A cp; spend A; spend A; reverse A; cancel; unspend S1; reopen; pay; move 1 F',
  '{"holds":{"A":"0.00","F":"20.00"},"status":"paid","net":100,"held":0,"error":null}'),
('MVXc', 'fixed', 'sale A cp; spend A; spend A; reverse A; unspend S1; cancel; reopen; pay; move 1 F',
  '{"holds":{"A":"0.00","F":"20.00"},"status":"paid","net":100,"held":0,"error":null}'),
('MVXh', 'fixed', 'sale A cp; spend A; spend A; reverse A; cancel; unspend S1; change B; reopen; pay; move 1 F',
  '{"holds":{"A":"0.00","B":"0.00","F":"20.00"},"status":"paid","net":100,"held":0,"error":null}'),
('MVXrr', 'fixed', 'sale A cp; spend A; spend A; reverse A; unspend S1; reverse A; unspend S2; move 1 F',
  '{"holds":{"A":"0.00","F":"20.00"},"status":"paid","net":100,"held":0,"error":null}'),
('MVS2', 'fixed', 'sale A cp 40; spend A; spend A 1 svc5; cancel; reopen; pay; unspend S1; reverse closed; unspend S2; movel 1 F',
  '{"holds":{"A":"75.00","F":"5.00"},"status":"paid","net":100,"held":0,"error":null}'),
-- (moved, then cancelled: Cancel takes it back from F, and S2 refunded is
-- held back; reopened and paid: F's again)
('MVXcc', 'fixed', 'sale A cp; spend A; spend A; reverse A; unspend S1; move 1 F; cancel; unspend S2',
  '{"holds":{"A":"0.00","F":"0.00"},"status":"cancelled","net":100,"held":40,"error":null}'),
('MVXcr', 'fixed', 'sale A cp; spend A; spend A; reverse A; unspend S1; move 1 F; cancel; reopen; pay',
  '{"holds":{"A":"0.00","F":"20.00"},"status":"paid","net":100,"held":0,"error":null}'),
-- (the credit a special document's refund put back, then moved)
('MVXd', 'fixed', 'sale A cp; special A special_sale 20; spend A; reverse A; unspecial D1; move 1 F',
  '{"holds":{"A":"0.00","F":"20.00"},"status":"paid","net":100,"held":0,"error":null}'),
-- (d) (the review of 475 to 478) before settlement, credit given back on
-- the lot the release record reaches now, after a 'transfer' change made
-- once that lot held nothing: B's, as for the same package paid in full.
('TQx1', 'fixed', 'sale A cp,cp 100; spend A; spend A 4; change B; unspend S1',
  '{"holds":{"A":"0.00","B":"20.00"},"status":"partially_paid","net":100,"held":0,"error":null}'),
('TQx1p', 'fixed', 'sale A cp,cp 100; spend A; spend A 4; change B; unspend S1; pay',
  '{"holds":{"A":"0.00","B":"120.00"},"status":"paid","net":200,"held":0,"error":null}'),
('TQx2', 'fixed', 'sale A cp,cp 100; spend A; spend A; spend A 3; change B; unspend S1; unspend S2',
  '{"holds":{"A":"0.00","B":"40.00"},"status":"partially_paid","net":100,"held":0,"error":null}'),
('TQx1f', 'fixed', 'sale A cp,cp 100; spend A; spend A 4; change B; fix S1 cash',
  '{"holds":{"A":"0.00","B":"20.00"},"status":"partially_paid","net":100,"held":0,"error":null}'),
('TQx1cc', 'fixed', 'sale A cp 40; spend A; spend A; cancel; change B; reopen; unspend S1; pay',
  '{"holds":{"A":"0.00","B":"80.00"},"status":"paid","net":100,"held":0,"error":null}'),
-- (c) 472's NOT COVERED 1: paid in part S$40, S1 from the released lot,
-- 328's repair of it (the stand-in), then: paid in full, cancelled, S1
-- refunded (A tries to spend; refunded by line); still paid; after a 'keep'
-- change; changed to B while cancelled, reopened and paid; two S$5
-- sessions; Correct payment; not paid in full (refunded, corrected, two
-- refunds; then paid; after a 'keep' change; cancelled and reopened first).
('R328', 'fixed', 'sale A cp 40; spend A; repair328; pay; cancel; unspend S1',
  '{"holds":{"A":"0.00"},"status":"cancelled","net":100,"held":100,"error":null}'),
('R328s', 'fixed', 'sale A cp 40; spend A; repair328; pay; cancel; unspend S1; spend A',
  '{"holds":{"A":"0.00"},"status":"cancelled","net":100,"held":100,"error~":"spend A: Only 0 of the requested 20.00 could be funded by eligible credit%"}'),
('R328b', 'fixed', 'sale A cp 40; spend A; repair328; pay; cancel; unspend S1; back 1 all',
  '{"holds":{"A":"0.00"},"status":"cancelled","net":0,"held":0,"error":null}'),
('R328p', 'fixed', 'sale A cp 40; spend A; repair328; pay; unspend S1',
  '{"holds":{"A":"100.00"},"status":"paid","net":100,"held":0,"error":null}'),
('R328k', 'fixed', 'sale A cp 40; spend A; repair328; pay; change B keep; unspend S1',
  '{"holds":{"A":"100.00","B":"0.00"},"status":"paid","net":100,"held":0,"error":null}'),
('R328cc', 'fixed', 'sale A cp 40; spend A; repair328; pay; cancel; change B; reopen; pay; unspend S1',
  '{"holds":{"A":"0.00","B":"100.00"},"status":"paid","net":100,"held":0,"error":null}'),
('R3282', 'fixed', 'sale A cp 40; spend A 1 svc5; spend A 1 svc5; repair328; pay; unspend S1; unspend S2',
  '{"holds":{"A":"100.00"},"status":"paid","net":100,"held":0,"error":null}'),
('R328f', 'fixed', 'sale A cp 40; spend A; repair328; pay; fix S1 cash',
  '{"holds":{"A":"100.00"},"status":"paid","net":100,"held":0,"error":null}'),
('R328u', 'fixed', 'sale A cp 40; spend A; repair328; unspend S1',
  '{"holds":{"A":"40.00"},"status":"partially_paid","net":40,"error":null}'),
('R328uf', 'fixed', 'sale A cp 40; spend A; repair328; fix S1 cash',
  '{"holds":{"A":"40.00"},"status":"partially_paid","net":40,"error":null}'),
('R328u2', 'fixed', 'sale A cp 40; spend A 1 svc5; spend A 1 svc5; repair328; unspend S1; unspend S2',
  '{"holds":{"A":"40.00"},"status":"partially_paid","net":40,"error":null}'),
('R328up', 'fixed', 'sale A cp 40; spend A; repair328; unspend S1; pay',
  '{"holds":{"A":"100.00"},"status":"paid","net":100,"held":0,"error":null}'),
('R328uk', 'fixed', 'sale A cp 40; spend A; repair328; change B keep; unspend S1; pay',
  '{"holds":{"A":"100.00","B":"0.00"},"status":"paid","net":100,"held":0,"error":null}'),
('R328ur', 'fixed', 'sale A cp 40; spend A; repair328; cancel; reopen; unspend S1',
  '{"holds":{"A":"40.00"},"status":"partially_paid","net":40,"error":null}'),
('R328urp', 'fixed', 'sale A cp 40; spend A; repair328; cancel; reopen; unspend S1; pay',
  '{"holds":{"A":"100.00"},"status":"paid","net":100,"held":0,"error":null}'),
-- (settled, then: cancelled, S1 refunded, reopened and paid; refunded by
-- line, reopened (it waits), S1 refunded (A tries to spend; then paid); the
-- guided Refund in full first; the guided Cancel first (S$0 owed back; then
-- refunded by line))
('R328r', 'fixed', 'sale A cp 40; spend A; repair328; pay; cancel; unspend S1; reopen; pay',
  '{"holds":{"A":"100.00"},"status":"paid","net":100,"held":0,"error":null}'),
('R328w', 'fixed', 'sale A cp 40; spend A; repair328; pay; cancel; back 1 all; reopen; unspend S1; spend A',
  '{"holds":{"A":"0.00"},"status":"partially_paid","net":20,"held":20,"error~":"spend A: Only 0 of the requested 20.00 could be funded by eligible credit%"}'),
('R328wp', 'fixed', 'sale A cp 40; spend A; repair328; pay; cancel; back 1 all; reopen; unspend S1; pay',
  '{"holds":{"A":"100.00"},"status":"paid","net":100,"held":0,"error":null}'),
('R328x', 'fixed', 'sale A cp 40; spend A; repair328; pay; refundall; unspend S1',
  '{"holds":{"A":"20.00"},"status":"paid","net":20,"held":0,"error":null}'),
('R328g', 'fixed', 'sale A cp 40; spend A; repair328; pay; guidedcancel; unspend S1',
  '{"holds":{"A":"0.00"},"status":"cancelled","net":20,"owed":20,"fdue":20,"held":20,"error":null}'),
('R328gb', 'fixed', 'sale A cp 40; spend A; repair328; pay; guidedcancel; unspend S1; back 1 all',
  '{"holds":{"A":"0.00"},"status":"cancelled","net":0,"owed":0,"fdue":0,"held":0,"error":null}'),
-- Controls: the same with and without 477.
('PTsxb', 'control', 'sale A cp; special A special_sale 20; spend A; reverse A; cancel; unspecial D1; back 1 all',
  '{"holds":{"A":"0.00"},"status":"cancelled","net":80,"held":0,"error":null}'),
('PTsxw', 'control', 'sale A cp; special A special_sale 20; spend A; reverse A; cancel; unspend S1; back 1 all; reopen; unspecial D1; spend A',
  '{"holds":{"A":"0.00"},"status":"partially_paid","net":80,"held":20,"error~":"spend A: Only 0 of the requested 20.00 could be funded by eligible credit%"}'),
('PTsxwp', 'control', 'sale A cp; special A special_sale 20; spend A; reverse A; cancel; unspend S1; back 1 all; reopen; unspecial D1; pay',
  '{"holds":{"A":"40.00"},"status":"paid","net":100,"held":0,"error":null}'),
('PTsp', 'control', 'sale A cp 40; special A special_sale 20; cancel; unspecial D1; refundpaid',
  '{"holds":{"A":"0.00"},"status":"cancelled","net":0,"error":null}'),
('PTs0', 'control', 'sale A cp; special A special_sale 20; spend A; cancel; unspecial D1',
  '{"holds":{"A":"0.00"},"status":"cancelled","net":100,"held":80,"error":null}'),
('MVXx', 'control', 'sale A cp; spend A; spend A; reverse A; move 1 F',
  '{"holds":{"A":"0.00"},"status":"paid","net":100,"error~":"move 1 F: T477: nothing to move on that line%"}'),
('R328c', 'control', 'sale A cp 40; spend A; repair328; pay; change B; unspend S1',
  '{"holds":{"A":"80.00"},"status":"paid","net":100,"held":0,"error~":"change B: These benefits have already been used and cannot move with the invoice:%"}'),
('R328uc', 'control', 'sale A cp 40; spend A; repair328; cancel; unspend S1',
  '{"holds":{"A":"0.00"},"status":"cancelled","net":40,"error":null}'),
('PX', 'control', 'sale A cp; spend A; spend A; reverse A; cancel; unspend S1',
  '{"holds":{"A":"0.00"},"status":"cancelled","net":100,"held":20,"error":null}'),
('PXp', 'control', 'sale A cp; spend A; spend A; reverse A; unspend S1',
  '{"holds":{"A":"20.00"},"status":"paid","net":100,"held":0,"error":null}'),
('MV1p', 'control', 'sale A cp; spend A; spend A; move 1 F; reverse F; unspend S1',
  '{"holds":{"A":"20.00","F":"0.00"},"status":"paid","net":100,"held":0,"error":null}'),
('RV1p', 'control', 'sale A cp; spend A; cancel; change B; reopen; pay; reverse B; unspend S1',
  '{"holds":{"A":"0.00","B":"20.00"},"status":"paid","net":100,"held":0,"error":null}'),
('O1', 'control', 'sale A cp 40; spend A; spend A 1 svc5; reverse A; cancel; reopen; pay; unspend S1; cancel; change B; reopen; pay; spend B 4; cancel; unspend S3',
  '{"holds":{"A":"0.00","B":"0.00"},"status":"cancelled","net":100,"held":80,"error":null}'),
('PC', 'control', 'sale A cp; spend A; spend A; cancel; unspend S1; back 1 all',
  '{"holds":{"A":"0.00"},"status":"cancelled","net":20,"held":0,"error":null}'),
('G2', 'control', 'sale A cp; spend A; spend A; move 1 F; unspend S1; guidedcancel; unspend S2',
  '{"holds":{"A":"0.00","F":"0.00"},"status":"cancelled","net":20,"owed":20,"fdue":20,"held":20,"error":null}'),
('S8gb', 'control', 'sale A cp 40; spend A; spend A 1 svc5; reverse A; cancel; reopen; pay; guidedcancel; unspend S1; back 1 all',
  '{"holds":{"A":"0.00"},"status":"cancelled","net":20,"owed":0,"fdue":0,"held":0,"error":null}'),
-- (d)'s controls: then cancelled (Cancel's write-off takes it back either
-- way); a 'keep' change instead (the buyer holds the benefits); the S$100
-- package paid in full, the same spending, change and refund (the benefit
-- row's path: B's); no change.
('TQx1c', 'control', 'sale A cp,cp 100; spend A; spend A 4; change B; unspend S1; cancel',
  '{"holds":{"A":"0.00","B":"0.00"},"status":"cancelled","net":100,"error":null}'),
('TQx1k', 'control', 'sale A cp,cp 100; spend A; spend A 4; change B keep; unspend S1; pay',
  '{"holds":{"A":"120.00","B":"0.00"},"status":"paid","net":200,"held":0,"error":null}'),
('TQx1F', 'control', 'sale A cp; spend A; spend A 4; change B; unspend S1',
  '{"holds":{"A":"0.00","B":"20.00"},"status":"paid","net":100,"held":0,"error":null}'),
('TQx0', 'control', 'sale A cp 40; spend A; cancel; reopen; unspend S1',
  '{"holds":{"A":"40.00"},"status":"partially_paid","net":40,"error":null}'),
-- (e) answer D (477's NOT COVERED 1, 27 Oct 2026): the released lot a
-- Cancel closed, opened by S1's refund while paid (locked by the write-off
-- alone): an Owner's Move of it to F (F S$20, A the rest); all of it spent
-- when cancelled, so the write-off took nothing and wrote no row (MVW0);
-- B's copy after a 'transfer' change of the lot nothing on which was used
-- (476's TQcru, then paid: MVWt); then S2 refunded (MVWs) or F spends it
-- (MVWsf); moved, then cancelled and S2 refunded (MVWcc), or cancelled,
-- reopened and paid (MVWcr); Correct payment instead of the refund (MVWf);
-- S2 refunded while cancelled first (the forwarder's hold locks it again:
-- MVWh); after a 'keep' change (MVWk).
('MVW', 'fixed', 'sale A cp 40; spend A; spend A 1 svc5; cancel; reopen; pay; unspend S1; movel 1 F',
  '{"holds":{"A":"75.00","F":"20.00"},"status":"paid","net":100,"held":0,"error":null}'),
('MVW0', 'fixed', 'sale A cp 40; spend A; spend A; cancel; reopen; pay; unspend S1; movel 1 F',
  '{"holds":{"A":"60.00","F":"20.00"},"status":"paid","net":100,"held":0,"error":null}'),
('MVWt', 'fixed', 'sale A cp 40; spend A; cancel; reopen; unspend S1; change B; pay; movel 1 F',
  '{"holds":{"A":"0.00","B":"80.00","F":"20.00"},"status":"paid","net":100,"held":0,"error":null}'),
('MVWs', 'fixed', 'sale A cp 40; spend A; spend A 1 svc5; cancel; reopen; pay; unspend S1; movel 1 F; unspend S2',
  '{"holds":{"A":"80.00","F":"20.00"},"status":"paid","net":100,"held":0,"error":null}'),
('MVWsf', 'fixed', 'sale A cp 40; spend A; spend A 1 svc5; cancel; reopen; pay; unspend S1; movel 1 F; spend F',
  '{"holds":{"A":"75.00","F":"0.00"},"status":"paid","net":100,"held":0,"error":null}'),
('MVWcc', 'fixed', 'sale A cp 40; spend A; spend A 1 svc5; cancel; reopen; pay; unspend S1; movel 1 F; cancel; unspend S2',
  '{"holds":{"A":"0.00","F":"0.00"},"status":"cancelled","net":100,"held":100,"error":null}'),
('MVWcr', 'fixed', 'sale A cp 40; spend A; spend A 1 svc5; cancel; reopen; pay; unspend S1; movel 1 F; cancel; reopen; pay',
  '{"holds":{"A":"75.00","F":"20.00"},"status":"paid","net":100,"held":0,"error":null}'),
('MVWf', 'fixed', 'sale A cp 40; spend A; spend A 1 svc5; cancel; reopen; pay; fix S1 cash; movel 1 F',
  '{"holds":{"A":"75.00","F":"20.00"},"status":"paid","net":100,"held":0,"error":null}'),
('MVWh', 'fixed', 'sale A cp 40; spend A; spend A 1 svc5; cancel; unspend S2; reopen; pay; unspend S1; movel 1 F',
  '{"holds":{"A":"80.00","F":"20.00"},"status":"paid","net":100,"held":0,"error":null}'),
('MVWk', 'fixed', 'sale A cp 40; spend A; spend A 1 svc5; cancel; reopen; pay; change B keep; unspend S1; movel 1 F',
  '{"holds":{"A":"75.00","B":"0.00","F":"20.00"},"status":"paid","net":100,"held":0,"error":null}'),
-- (e)'s control (477's NOT COVERED 1 now): a lock no Owner's reversal and no
-- release record explains (a stand-in: no function makes one): the Move is
-- still refused, with and without 477.
('MVL', 'control', 'sale A cp; spend A; spend A; lock A; unspend S1; move 1 F',
  '{"holds":{"A":"80.00"},"status":"paid","net":100,"held":0,"error~":"move 1 F: This credit lot is locked or reversed%"}');

-- States made for the header's query: a special document paid from a lot
-- now closed, still refundable (1: cancelled, paid, and a lot a Cancel
-- closed); credit an Owner reversed and a refund put back, on a named lot
-- (2); a sale paid from a lot 328's repair replaced, refundable (3, settled
-- or not); a lot only a Cancel's write-off locked, holding credit (6); a
-- sale paid from a lot of credit released before full payment whose
-- customer no longer holds the benefits, refundable (7: S1 and S2's four
-- lines), and credit given back there before 477 (8).
create temp table t477_qstates(k text primary key, steps text not null, reason text, n int);
insert into t477_qstates values
  ('QPT', 'sale A cp; special A special_sale 20; spend A; reverse A; cancel', '1', 1),
  ('QPTp', 'sale A cp; special A special_sale 20; spend A; reverse A', '1', 1),
  ('QPTw', 'sale A cp 40; special A special_sale 20; cancel', '1', 1),
  ('QMV', 'sale A cp; spend A; spend A; reverse A; unspend S1', '2', 1),
  ('QR', 'sale A cp 40; spend A; repair328; pay', '3', 1),
  ('QRu', 'sale A cp 40; spend A; spend A 1 svc5; repair328', '3', 2),
  ('QW', 'sale A cp 40; spend A; spend A 1 svc5; cancel; reopen; pay; unspend S1', '6', 1),
  ('QW0', 'sale A cp 40; spend A; spend A; cancel; reopen; pay; unspend S1', '6', 1),
  ('QL', 'sale A cp; spend A; lock A', '9', 1),
  ('QN', 'sale A cp; spend A; spend A', null, null),
  ('QTX', 'sale A cp,cp 100; spend A; spend A 4; change B', '7', 5),
  ('QTX8', 'sale A cp,cp 100; spend A; spend A 4; change B; unspend S1', '8', 1);

-- The read-only query in 477's header (the same text).
create function pg_temp.t477_header_query() returns table(reason text, invoice_no text, n bigint) language sql as $hq$
with
-- lots 328's repair replaced (its ledger row), and lots an Owner reversed
-- (reverse_credit_lot's 'reversal' row)
rp as (
  select distinct e.lot_id from public.customer_credit_ledger e
   where e.source_type = 'credit_lot_provenance_repair' and e.lot_id is not null),
rv as (
  select distinct e.lot_id from public.customer_credit_ledger e
   where e.entry_type = 'reverse' and e.source_type = 'reversal' and e.lot_id is not null),
-- the invoice whose records reach a lot: a benefit row that names it or a
-- lot reissued from it, or a release record whose chain reaches it
own as (
  select b.invoice_id, a.lot_id
    from public.invoice_benefit_values b
    cross join lateral unnest(public.credit_lot_ancestry(b.lot_id)) a(lot_id)
   where b.lot_id is not null
  union
  select pl.invoice_id, c.lot_id
    from public.credit_package_progress_lots pl
    cross join lateral unnest(public.credit_lot_chain(pl.lot_id)) c(lot_id)),
-- the lots a benefit row names that are open, locked and hold credit, and
-- whether an Owner's reversal, a release record (a lot of credit released
-- before full payment: what Cancel's write-off locks) or 328's repair is on
-- them or a lot they were reissued from
locked as (
  select b.invoice_id, l.id,
         exists (select 1 from unnest(public.credit_lot_ancestry(l.id)) a(id) join rv on rv.lot_id = a.id) as reversed,
         exists (select 1 from unnest(public.credit_lot_ancestry(l.id)) a(id)
                  join public.credit_package_progress_lots pl on pl.lot_id = a.id) as released,
         exists (select 1 from unnest(public.credit_lot_ancestry(l.id)) a(id) join rp on rp.lot_id = a.id) as repaired
    from public.invoice_benefit_values b
    join public.customer_credit_lots l on l.id = b.lot_id
   where l.status = 'active' and l.is_locked and l.remaining_amount > 0),
-- (4) the lots of credit released before full payment of package lines not
-- settled, of invoices neither cancelled nor refunded, behind the lot their
-- release record reaches now (not 328's: 3), or that lot where its customer
-- no longer holds the invoice's benefits (462's rule)
astray as (
  select pl.invoice_id, l.id
    from public.credit_package_progress_lots pl
    join public.invoices i on i.id = pl.invoice_id and i.deleted_at is null and i.status::text not in ('cancelled', 'refunded')
    join public.invoice_items it on it.id = pl.invoice_item_id and it.credit_issued_at is null
    cross join lateral unnest(public.credit_lot_chain(pl.lot_id)) c(lot_id)
    join public.customer_credit_lots l on l.id = c.lot_id
   where not exists (select 1 from public.invoice_benefit_values bv where bv.lot_id = any (public.credit_lot_chain(pl.lot_id)))
     and not exists (select 1 from rp where rp.lot_id = l.id)
     and (l.id <> public.credit_lot_current(pl.lot_id)
          or coalesce(public.invoice_credit_live_holder(pl.invoice_id, l.customer_id, l.created_at), l.customer_id) <> l.customer_id)),
found(reason, invoice_id, n) as (
  select '1 changes: special documents paid with credit from a lot that is closed now, which can still be refunded (their refund now opens the lot: the credit is then held back, goes to whoever holds the benefits, or is spendable, by the forwarder''s rules; on a lot a Cancel closed while the package is still cancelled it is taken back as before; before, it stayed on the closed lot, which no one could spend) (the count is of documents'' allocations)', o.invoice_id, count(*)
    from public.special_credit_allocations s
    join public.customer_credit_lots l on l.id = s.lot_id
    left join own o on o.lot_id = l.id
   where s.amount > coalesce(s.reversed_amount, 0) and l.status <> 'active'
   group by o.invoice_id
  union all
  select '2 changes: credit an Owner reversed and a refund or correction then put back, held on a lot the records name (locked): an Owner''s Move of it is now allowed (before, refused: "This credit lot is locked or reversed") (the count is of lots)', k.invoice_id, count(*)
    from locked k where k.reversed and not k.repaired
   group by k.invoice_id
  union all
  select '3 changes: sales paid from a lot 328''s repair replaced that can still be refunded or corrected (the credit they give back now goes to the lot the records name, and is held back there or goes to whoever holds the benefits; before, it stayed on the replaced lot) (the count is of sales)', o.invoice_id,
         sum((select count(*) from public.invoice_line_credit_allocations a where a.lot_id = rp.lot_id and a.amount > coalesce(a.reversed_amount, 0))
             + (select count(*) from public.special_credit_allocations s where s.lot_id = rp.lot_id and s.amount > coalesce(s.reversed_amount, 0)))
    from rp left join own o on o.lot_id = rp.lot_id
   group by o.invoice_id
  having sum((select count(*) from public.invoice_line_credit_allocations a where a.lot_id = rp.lot_id and a.amount > coalesce(a.reversed_amount, 0))
             + (select count(*) from public.special_credit_allocations s where s.lot_id = rp.lot_id and s.amount > coalesce(s.reversed_amount, 0))) > 0
  union all
  select '4 for the Owner (not changed by 477: NOT COVERED 2): credit on a closed lot today (a special document''s refund before 477), which no one can spend; it stays until a refund of a sale paid from that lot opens it (the count is of lots)', o.invoice_id, count(distinct l.id)
    from public.customer_credit_lots l
    left join own o on o.lot_id = l.id
   where l.status <> 'active' and l.remaining_amount > 0
   group by o.invoice_id
  union all
  select '5 for the Owner (not changed by 477: NOT COVERED 3): credit on a lot 328''s repair replaced today, given back before 477; it stays until the next refund or correction of a sale paid from that lot or a lot that replaced it, which takes it along (the count is of lots)', o.invoice_id, count(distinct l.id)
    from rp join public.customer_credit_lots l on l.id = rp.lot_id
    left join own o on o.lot_id = l.id
   where l.status = 'active' and l.remaining_amount > 0
   group by o.invoice_id
  union all
  select '6 changes (the Owner''s answer D): credit held on a lot the records name that a Cancel''s write-off of credit released before full payment locked (a release record names it or a lot it was reissued from; no Owner''s reversal, no 328 repair): an Owner''s Move of it is now allowed (before, refused: "This credit lot is locked or reversed") (the count is of lots)', k.invoice_id, count(*)
    from locked k where k.released and not k.reversed and not k.repaired
   group by k.invoice_id
  union all
  select '7 changes: sales paid from a lot of credit released before full payment, of a package not settled on an invoice neither cancelled nor refunded, that is behind the lot its release record reaches now or held by someone other than whoever holds the invoice''s benefits now (a ''transfer'' change made once it held nothing), which can still be refunded or corrected (the credit they give back now goes to whoever holds the benefits, on the lot the release record reaches; before, it stayed on that lot with its customer) (the count is of sales)', a.invoice_id,
         sum((select count(*) from public.invoice_line_credit_allocations x where x.lot_id = a.id and x.amount > coalesce(x.reversed_amount, 0))
             + (select count(*) from public.special_credit_allocations s where s.lot_id = a.id and s.amount > coalesce(s.reversed_amount, 0)))
    from astray a
   group by a.invoice_id
  having sum((select count(*) from public.invoice_line_credit_allocations x where x.lot_id = a.id and x.amount > coalesce(x.reversed_amount, 0))
             + (select count(*) from public.special_credit_allocations s where s.lot_id = a.id and s.amount > coalesce(s.reversed_amount, 0))) > 0
  union all
  select '8 for the Owner (not changed by 477: NOT COVERED 3): credit on such a lot today, given back before 477 and kept by a customer who no longer holds the benefits (or behind the lot the release record reaches); it stays until the next refund or correction of a sale paid from that lot, which takes it along (the count is of lots)', a.invoice_id, count(*)
    from astray a join public.customer_credit_lots l on l.id = a.id
   where l.status = 'active' and l.remaining_amount > 0
   group by a.invoice_id
  union all
  select '9 for the Owner (not changed by 477: NOT COVERED 1): credit held on a lot the records name that 328''s repair locked, or that is locked with no Owner''s reversal and no release record to explain it: an Owner''s Move of it is still refused (the count is of lots)', k.invoice_id, count(*)
    from locked k where k.repaired or not (k.reversed or k.released)
   group by k.invoice_id)
select f.reason, coalesce(i.invoice_no, '(no invoice)') as invoice_no, f.n
  from found f left join public.invoices i on i.id = f.invoice_id
 order by f.reason, 2
$hq$;

-- ===== S. Where it starts =====
create temp table t477_fp(k text primary key, v text);
-- The grant list, each function's grants as a set (production lists them in
-- another order).
create function pg_temp.t477_grant_sets() returns text language sql as $f$
  select md5(string_agg(g.sig || '=' || g.acl, '|' order by g.sig))
    from (select p.oid::regprocedure::text as sig,
                 coalesce((select string_agg(x::text, ',' order by x::text) from unnest(p.proacl) x), 'null') as acl
            from pg_proc p where p.pronamespace = 'public'::regnamespace) g $f$;
create function pg_temp.t477_grant_set(p_sig text) returns text[] language sql as $f$
  select array_agg(x::text order by x::text) from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || p_sig) $f$;
insert into t477_fp values ('start', pg_temp.t477_fingerprint()), ('grants', pg_temp.t477_grant_sets()), ('triggers', pg_temp.t477_inv_triggers());
-- The functions 477 changes: BEFORE (a copy of production at 474 with 475
-- and 476 applied, 27 Oct 2026) and AFTER, and who may call each. It adds
-- nothing.
create temp table t477_md5(sig text primary key, before text, after text, acl text[]);
insert into t477_md5 values
  ('refund_special_credit(text,uuid)', 'e019e28ad79539d771376c9b38d7e27e', '42e436aa44046d4cb1748641cd8a5257',
   '{postgres=X/postgres,service_role=X/postgres}'),
  ('transfer_invoice_unused_benefit(uuid,uuid,uuid,text,uuid)', '7aebd7120bc3928db46df0941cb20889', '720d296a43524e7ac8843c6062030819',
   '{authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres}'),
  ('credit_given_back_follows(uuid)', 'f2a7a4d1ca28f0865b14e3f1e5e02bbb', 'a0f2f5ece30be439049dca275802237a',
   '{postgres=X/postgres,service_role=X/postgres}');
create function pg_temp.t477_at(p_col text) returns boolean language sql as $f$
  select bool_and(case when p_col = 'before' then md5(pg_get_functiondef(to_regprocedure('public.' || m.sig))) = m.before
                       else md5(pg_get_functiondef(to_regprocedure('public.' || m.sig))) = m.after end)
    from t477_md5 m $f$;
-- Their texts as found (9 puts one back to make a mix).
create temp table t477_saved(sig text primary key, def text);
insert into t477_saved select sig, pg_get_functiondef(to_regprocedure('public.' || sig)) from t477_md5;
do $$ begin
  perform pg_temp.t477_check(pg_temp.t477_462_in() and pg_temp.t477_463_in() and pg_temp.t477_470_in() and pg_temp.t477_471_in()
      and pg_temp.t477_472_in() and pg_temp.t477_473_in() and pg_temp.t477_475_in() and pg_temp.t477_476_in()
      and md5(pg_get_functiondef('public.reopen_invoice(uuid,text,uuid)'::regprocedure)) = '30066e137b9b75b5789a050c14debc04'
      and md5(pg_get_functiondef('public.invoice_transferable_benefits(uuid)'::regprocedure)) = '1546de1f83d970424d26e65941f4dcb8',
    'S 462, 463 and 470 to 476 are in: reopen_invoice at 475''s AFTER, the list at 476''s (477 goes in after them)');
  perform pg_temp.t477_check(split_part(pg_temp.t477_inv_triggers(), ' ', 1) = '92c94e3ebc6113a68d972330bbca8938',
    'S the triggers on invoices are as read (27 Oct 2026): ' || pg_temp.t477_inv_triggers());
  perform pg_temp.t477_check((select bool_and(pg_temp.t477_grant_set(sig) = acl) from t477_md5),
    'S who may call the three is not as read');
end $$;
\if :{?nomig}
do $$ begin
  perform pg_temp.t477_check(pg_temp.t477_in() and pg_temp.t477_at('after'), 'S -v nomig=1: 477 is in, as tested');
end $$;
\else
do $$ begin
  perform pg_temp.t477_check(not pg_temp.t477_in() and pg_temp.t477_at('before'),
    'S 477 is not in yet and the three are at their BEFORE (this suite installs it; use -v nomig=1 where it is in)');
end $$;

-- ===== R. Before 477: each case reproduced (undone afterwards) =====
-- A 'fixed' case does not end as 477 makes it (its outcome, the invariants
-- and Cancel); a control or known case does, exactly.
savepoint t477_r;
do $$
declare c record; o jsonb; res text := '';
begin
  for c in select * from t477_cases order by ord loop
    o := pg_temp.t477_run('before', c.k, c.steps);
    if c.kind = 'fixed' then
      perform pg_temp.t477_check(not (pg_temp.t477_meets(o, c.expect) and coalesce(o->>'invariants', '') = ''
                                      and (c.expect ? 'cancel_left' or coalesce((o->>'cancel_left')::numeric, 0) = 0)),
        'R ' || c.k || ' already ends as 477 makes it, without 477: ' || o::text);
      res := res || format(E'\n  %s: %s; net %s; held back %s%s%s%s', c.k,
        (select string_agg(h.key || ' ' || (h.value #>> '{}'), ', ' order by h.key) from jsonb_each(o->'holds') h),
        o->>'net', o->>'held', coalesce('; Cancel leaves S$' || nullif(o->>'cancel_left', '0.00'), ''),
        coalesce('; ' || nullif(o->>'invariants', ''), ''), coalesce('; refused: ' || left(o->>'error', 90), ''));
    else
      perform pg_temp.t477_check(pg_temp.t477_meets(o, c.expect) and coalesce(o->>'invariants', '') = ''
          and (c.expect ? 'cancel_left' or coalesce((o->>'cancel_left')::numeric, 0) = 0),
        'R ' || c.kind || ' ' || c.k || ' without 477: ' || coalesce(pg_temp.t477_diff(o, c.expect), '') || ' ' || o::text);
    end if;
  end loop;
  for c in select * from t477_qstates loop
    perform pg_temp.t477_run('before', c.k, c.steps);
  end loop;
  raise notice 'PASS R: without 477 every fixed case ends otherwise (the faults reproduced), the controls as expected:%', res;
end $$;

-- ===== Q. The header's read-only query, on these states =====
create temp table t477_q as select * from pg_temp.t477_header_query();
create function pg_temp.t477_q_n(p_reason text, p_case text) returns bigint language sql as $f$
  select q.n from t477_q q join invoices i on i.invoice_no = q.invoice_no
   where left(q.reason, 1) = p_reason and i.id = pg_temp.t477_id('before/' || p_case || '/inv') $f$;
create function pg_temp.t477_q_list(p_reason text) returns text language sql as $f$
  select coalesce(string_agg(c.k, ',' order by c.k), '-')
    from (select k from t477_cases union select k from t477_qstates) c
    join invoices i on i.id = pg_temp.t477_id('before/' || c.k || '/inv')
   where exists (select 1 from t477_q q where q.invoice_no = i.invoice_no and left(q.reason, 1) = p_reason) $f$;
do $$
declare c record;
begin
  for c in select * from t477_qstates loop
    if c.reason is null then
      perform pg_temp.t477_check(not exists (select 1 from t477_q q join invoices i on i.invoice_no = q.invoice_no
                                              where i.id = pg_temp.t477_id('before/' || c.k || '/inv')), 'Q ' || c.k || ' (nothing reversed, repaired or locked) is listed');
    else
      perform pg_temp.t477_check(pg_temp.t477_q_n(c.reason, c.k) = c.n,
        'Q ' || c.k || ' is not listed under ' || c.reason || ' with ' || c.n || ' (' || coalesce(pg_temp.t477_q_n(c.reason, c.k)::text, 'not listed') || ')');
    end if;
  end loop;
  raise notice 'Q lists: 1 %; 2 %; 3 %; 4 %; 5 %; 6 %; 7 %; 8 %; 9 %', pg_temp.t477_q_list('1'), pg_temp.t477_q_list('2'), pg_temp.t477_q_list('3'),
    pg_temp.t477_q_list('4'), pg_temp.t477_q_list('5'), pg_temp.t477_q_list('6'), pg_temp.t477_q_list('7'), pg_temp.t477_q_list('8'),
    pg_temp.t477_q_list('9');
  perform pg_temp.t477_check(pg_temp.t477_q_list('1') = 'QPT,QPTp,QPTw', 'Q 1 lists ' || pg_temp.t477_q_list('1'));
  perform pg_temp.t477_check(pg_temp.t477_q_list('2') = 'MVS2,MVX,MVXc,MVXcc,MVXcr,MVXh,MVXr,MVXrr,MVXs,MVXsf,PTsxwp,PXp,QMV', 'Q 2 lists ' || pg_temp.t477_q_list('2'));
  perform pg_temp.t477_check(pg_temp.t477_q_list('3') = 'QR,QRu,R328c,R328s,R328w', 'Q 3 lists ' || pg_temp.t477_q_list('3'));
  perform pg_temp.t477_check(pg_temp.t477_q_list('4') = 'MVXd,PTsx,PTsxh,PTsxhc,PTsxl,PTsxo,PTsxp,PTsxr,PTsxs', 'Q 4 lists ' || pg_temp.t477_q_list('4'));
  perform pg_temp.t477_check(pg_temp.t477_q_list('5') = 'R328,R3282,R328b,R328cc,R328f,R328g,R328gb,R328k,R328p,R328r,R328u,R328u2,R328uf,R328uk,R328up,R328ur,R328urp,R328wp,R328x', 'Q 5 lists ' || pg_temp.t477_q_list('5'));
  -- (6: the (e) states before 477, where the Move was refused, the lot
  -- Cancel's write-off locked holding S$20 (B's copy of it in MVWt), and
  -- also TQx1cc's state before 477: paid, A's S$20 on the lot Cancel's
  -- write-off locked; 7: the (d) states before 477, whose sales can still
  -- be refunded; 8: those where a refund already gave credit back to A; 9:
  -- a lock nothing explains, the stand-in)
  perform pg_temp.t477_check(pg_temp.t477_q_list('6') = 'MVW,MVW0,MVWcc,MVWcr,MVWf,MVWh,MVWk,MVWs,MVWsf,MVWt,QW,QW0,TQx1cc', 'Q 6 lists ' || pg_temp.t477_q_list('6'));
  perform pg_temp.t477_check(pg_temp.t477_q_list('9') = 'MVL,QL', 'Q 9 lists ' || pg_temp.t477_q_list('9'));
  perform pg_temp.t477_check(pg_temp.t477_q_list('7') = 'QTX,QTX8,TQx1,TQx1f,TQx2', 'Q 7 lists ' || pg_temp.t477_q_list('7'));
  perform pg_temp.t477_check(pg_temp.t477_q_list('8') = 'QTX8,TQx1,TQx1f,TQx2', 'Q 8 lists ' || pg_temp.t477_q_list('8'));
  -- the controls that never reverse, repair or lock anything are listed nowhere
  perform pg_temp.t477_check(not exists (select 1 from t477_q q join invoices i on i.invoice_no = q.invoice_no
                                          join t477_cases tc on i.id = pg_temp.t477_id('before/' || tc.k || '/inv')
                                         where tc.k in ('PTs0', 'PC', 'G2')),
    'Q a control is listed');
  raise notice 'PASS Q: the header''s read-only query lists % invoices (%), each reason as expected',
    (select count(distinct invoice_no) from t477_q),
    (select string_agg(left(reason, 1) || ' ' || n, ', ' order by left(reason, 1)) from (select reason, count(*) n from t477_q group by reason) x);
end $$;
-- Keep R's outcomes; undo its records.
select coalesce(jsonb_object_agg(k, v), '{}'::jsonb)::text as t477_rbefore from t477_res where phase = 'before' \gset
rollback to savepoint t477_r;
insert into t477_res select 'before', key, value from jsonb_each(:'t477_rbefore'::jsonb);
do $$ begin
  perform pg_temp.t477_check((select count(*) from t477_res where phase = 'before') = (select count(*) from t477_cases) + (select count(*) from t477_qstates)
      and pg_temp.t477_fingerprint() = (select v from t477_fp where k = 'start'),
    'R undone, its outcomes kept');
end $$;

-- ===== 9. The refusals, each changing nothing =====
-- 9a One of the three at neither version.
savepoint t477_9;
alter function public.refund_special_credit(text, uuid) set work_mem = '64kB';
\set ON_ERROR_STOP off
\ir ../../../supabase/477_special_refund_move_repaired_lot.sql
\set ON_ERROR_STOP on
rollback to savepoint t477_9;
select set_config('t477.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t477_check(current_setting('t477.msg') like '477: the functions this changes are not the versions this was tested against (%: %, before, before). Re-read them and re-test before applying.'
      and not pg_temp.t477_in() and pg_temp.t477_at('before'), '9a refused with: ' || current_setting('t477.msg'));
end $$;
-- 9b A mix: 477 in, then refund_special_credit put back as it was.
savepoint t477_9;
\ir ../../../supabase/477_special_refund_move_repaired_lot.sql
do $$ begin execute (select def from t477_saved where sig = 'refund_special_credit(text,uuid)'); end $$;
\set ON_ERROR_STOP off
\ir ../../../supabase/477_special_refund_move_repaired_lot.sql
\set ON_ERROR_STOP on
rollback to savepoint t477_9;
select set_config('t477.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t477_check(current_setting('t477.msg') like '477: the functions this changes are not the versions this was tested against (%: before, after, after). Re-read them and re-test before applying.'
      and not pg_temp.t477_in() and pg_temp.t477_at('before'), '9b refused with: ' || current_setting('t477.msg'));
end $$;
-- 9c A function it relies on is not as read: the chain back, and 476's holder.
savepoint t477_9;
alter function public.credit_lot_ancestry(uuid) set work_mem = '64kB';
\set ON_ERROR_STOP off
\ir ../../../supabase/477_special_refund_move_repaired_lot.sql
\set ON_ERROR_STOP on
rollback to savepoint t477_9;
select set_config('t477.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t477_check(current_setting('t477.msg') like '477: public.credit_lot_ancestry(uuid) is missing or not the version this was tested against (md5 %). Re-read it and re-test before applying.'
      and not pg_temp.t477_in(), '9c refused with: ' || current_setting('t477.msg'));
end $$;
savepoint t477_9;
alter function public.credit_line_benefits_holder(uuid) set work_mem = '64kB';
\set ON_ERROR_STOP off
\ir ../../../supabase/477_special_refund_move_repaired_lot.sql
\set ON_ERROR_STOP on
rollback to savepoint t477_9;
select set_config('t477.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t477_check(current_setting('t477.msg') like '477: public.credit_line_benefits_holder(uuid) is missing or not the version this was tested against (md5 %)%'
      and not pg_temp.t477_in(), '9c2 refused with: ' || current_setting('t477.msg'));
end $$;
-- 9d A new reader or writer of 328's link.
savepoint t477_9;
create function public.t477_probe_link() returns uuid language sql as $f$ select null::uuid as replaces_lot_id $f$;
\set ON_ERROR_STOP off
\ir ../../../supabase/477_special_refund_move_repaired_lot.sql
\set ON_ERROR_STOP on
rollback to savepoint t477_9;
select set_config('t477.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t477_check(current_setting('t477.msg') like '477: what reads or writes 328''s link, or names an Owner''s reversal row, is not as read on 27 Oct 2026 (%t477_probe_link()%'
      and not pg_temp.t477_in(), '9d refused with: ' || current_setting('t477.msg'));
end $$;
-- 9e A function calling one of the two app functions.
savepoint t477_9;
create function public.t477_probe_call() returns numeric language sql as $f$ select public.refund_special_credit('special_sale', null) $f$;
\set ON_ERROR_STOP off
\ir ../../../supabase/477_special_refund_move_repaired_lot.sql
\set ON_ERROR_STOP on
rollback to savepoint t477_9;
select set_config('t477.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t477_check(current_setting('t477.msg') like '477: a function calls refund_special_credit or transfer_invoice_unused_benefit (t477_probe_call())%'
      and not pg_temp.t477_in(), '9e refused with: ' || current_setting('t477.msg'));
end $$;
-- 9f The same grants listed in another order do not stop it.
savepoint t477_9;
revoke execute on function public.transfer_invoice_unused_benefit(uuid, uuid, uuid, text, uuid) from service_role;
grant execute on function public.transfer_invoice_unused_benefit(uuid, uuid, uuid, text, uuid) to service_role;
select proacl::text as t477_9f_acl from pg_proc where oid = 'public.transfer_invoice_unused_benefit(uuid,uuid,uuid,text,uuid)'::regprocedure \gset
\set ON_ERROR_STOP off
\ir ../../../supabase/477_special_refund_move_repaired_lot.sql
\set t477_9f_failed :ERROR
\set ON_ERROR_STOP on
select (pg_temp.t477_in() and pg_temp.t477_at('after'))::text as t477_9f_ok \gset
rollback to savepoint t477_9;
select set_config('t477.f9f', :'t477_9f_failed', false), set_config('t477.ok9f', :'t477_9f_ok', false),
       set_config('t477.acl9f', :'t477_9f_acl', false);
do $$ begin
  perform pg_temp.t477_check(current_setting('t477.f9f') = 'false' and current_setting('t477.ok9f') = 'true'
      and current_setting('t477.acl9f') <> '{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}',
    '9f the same grants in another order stopped it (' || current_setting('t477.acl9f') || ')');
  perform pg_temp.t477_check(not pg_temp.t477_in() and pg_temp.t477_at('before') and pg_temp.t477_fingerprint() = (select v from t477_fp where k = 'start'),
    '9 a refusal changed something');
  raise notice 'PASS 9: refused, changing nothing: a function at neither version; a mix (one put back); a pin changed (the chain back, 476''s holder); a new reader of 328''s link; a function calling an app function changed; the same grants in another order do not stop it';
end $$;

-- ===== M (before). Begun before 477 =====
-- The mid set: a case's first steps run before 477, the rest after it. And
-- credit given back before 477 on a closed lot (MPTs1, MPTs2), on a lot
-- 328's repair replaced (MR328ps, MR328p) or on a released lot whose
-- customer no longer holds the benefits (MTQx): left as it is, then read
-- with the next refund.
create temp table t477_mid(k text primary key, ord serial, split int, steps text, expect jsonb);
insert into t477_mid(k, split, steps, expect) select 'm' || k, s, steps, expect from (values
  ('PTsx', 5), ('PTsxh', 8), ('MVX', 5), ('MVXh', 9), ('R328', 5), ('R328p', 4), ('R328u', 3), ('R328cc', 8),
  ('MVW', 7), ('MVWt', 7)) x(k, s)
  join t477_cases c using (k);
insert into t477_mid(k, split, steps, expect) values
  ('MPTs1', 6, 'sale A cp; special A special_sale 20; spend A; reverse A; cancel; unspecial D1',
    '{"holds":{"A":"20.00"},"status":"cancelled","net":100,"held":0,"error":null}'),
  ('MPTs2', 7, 'sale A cp; special A special_sale 20; special A special_sale 10; spend A; reverse A; cancel; unspecial D1; unspecial D2',
    '{"holds":{"A":"0.00"},"status":"cancelled","net":100,"held":30,"error":null}'),
  ('MR328ps', 5, 'sale A cp 40; spend A; repair328; pay; unspend S1',
    '{"holds":{"A":"100.00"},"status":"paid","net":100,"held":0,"cancel_left":20,"error":null}'),
  ('MR328p', 6, 'sale A cp 40; spend A; spend A 1 svc5; repair328; pay; unspend S1; unspend S2',
    '{"holds":{"A":"100.00"},"status":"paid","net":100,"held":0,"error":null}'),
  -- (d) S1 refunded before 477 (A keeps S$20 on the lot), S2 after it: the
  -- next refund takes it along (B S$40 on one lot; NOT COVERED 3).
  ('MTQx', 6, 'sale A cp,cp 100; spend A; spend A; spend A 3; change B; unspend S1; unspend S2',
    '{"holds":{"A":"0.00","B":"40.00"},"status":"partially_paid","net":100,"error":null}');
do $$ declare c record; begin
  for c in select * from t477_mid order by ord loop
    perform pg_temp.t477_run('mid', c.k, c.steps, 1, c.split);
  end loop;
end $$;
\endif

-- ===== 10. Install 477, twice =====
\if :{?nomig}
do $$ begin raise notice 'NOTE 10: -v nomig=1, so 477 is not installed here (R, Q, 9 and M are skipped)'; end $$;
\else
\ir ../../../supabase/477_special_refund_move_repaired_lot.sql
do $$ begin insert into t477_fp values ('first', pg_temp.t477_fingerprint()); end $$;
\ir ../../../supabase/477_special_refund_move_repaired_lot.sql
do $$ begin insert into t477_fp values ('second', pg_temp.t477_fingerprint()); end $$;
\endif
do $$
begin
  perform pg_temp.t477_check(pg_temp.t477_in() and pg_temp.t477_at('after'), '10 477 is not installed as tested');
  perform pg_temp.t477_check((select count(*) from pg_proc where pronamespace = 'public'::regnamespace
                               and proname in ('refund_special_credit', 'transfer_invoice_unused_benefit', 'credit_given_back_follows')) = 3,
    '10 an overload exists');
  perform pg_temp.t477_check(pg_temp.t477_inv_triggers() = (select v from t477_fp where k = 'triggers')
      and (select count(*) from pg_trigger where tgrelid = 'public.customer_credit_ledger'::regclass and not tgisinternal and tgname like 'credit_given_back%') = 1,
    '10 a trigger was added or changed: ' || pg_temp.t477_inv_triggers());
  perform pg_temp.t477_check((select bool_and(pg_temp.t477_grant_set(sig) = acl) from t477_md5)
      and not has_function_privilege('anon', 'public.refund_special_credit(text,uuid)', 'execute')
      and not has_function_privilege('authenticated', 'public.refund_special_credit(text,uuid)', 'execute')
      and not has_function_privilege('anon', 'public.credit_given_back_follows(uuid)', 'execute')
      and not has_function_privilege('authenticated', 'public.credit_given_back_follows(uuid)', 'execute')
      and has_function_privilege('authenticated', 'public.transfer_invoice_unused_benefit(uuid,uuid,uuid,text,uuid)', 'execute'),
    '10 who may call them is not as intended');
  if exists (select 1 from t477_fp where k = 'first') then
    perform pg_temp.t477_check((select v from t477_fp where k = 'second') = (select v from t477_fp where k = 'first'),
      '10 the second run of 477 changed functions');
    perform pg_temp.t477_check(split_part((select v from t477_fp where k = 'first'), ' ', 2)::int
                               = split_part((select v from t477_fp where k = 'start'), ' ', 2)::int,
      '10 477 added or dropped a function');
    perform pg_temp.t477_check(pg_temp.t477_grant_sets() = (select v from t477_fp where k = 'grants'),
      '10 the grants changed');
  end if;
  raise notice 'PASS 10: 477 installed as tested (%); the three at their AFTER, their grants as read (as sets); nothing added (no function, no trigger); %',
    pg_temp.t477_fingerprint(),
    coalesce((select 'the second run changed nothing, the grants as before' from t477_fp where k = 'first'), 'it was in before the suite (nomig)');
end $$;

-- ===== A. Each case after 477 =====
do $$
declare c record; o jsonb; b jsonb; res text := '';
begin
  for c in select * from t477_cases order by ord loop
    o := pg_temp.t477_run('after', c.k, c.steps);
    perform pg_temp.t477_check(pg_temp.t477_meets(o, c.expect),
      'A ' || c.k || ': ' || coalesce(pg_temp.t477_diff(o, c.expect), '') || ' ' || o::text);
    perform pg_temp.t477_check(coalesce(o->>'invariants', '') = '', 'A ' || c.k || ' invariants: ' || (o->>'invariants'));
    perform pg_temp.t477_check(c.expect ? 'cancel_left' or coalesce((o->>'cancel_left')::numeric, 0) = 0,
      'A ' || c.k || ': Cancel leaves S$' || (o->>'cancel_left') || ' of the invoice''s credit behind');
    b := (select v from t477_res where phase = 'before' and k = c.k);
    -- (a refusal's text names its invoice, numbered differently in each run;
    -- an amount owed back on an invoice that is no longer cancelled is read
    -- by nothing, so it is not compared)
    if c.kind in ('control', 'known') and b is not null then
      perform pg_temp.t477_check(o - 'error' - case when o->>'status' = 'cancelled' then '' else 'owed' end
                                 = b - 'error' - case when b->>'status' = 'cancelled' then '' else 'owed' end
          and regexp_replace(coalesce(o->>'error', ''), 'INV-[0-9-]+', 'INV', 'g') = regexp_replace(coalesce(b->>'error', ''), 'INV-[0-9-]+', 'INV', 'g'),
        'A ' || c.kind || ' ' || c.k || ' changed with 477: before ' || b::text || ', after ' || o::text);
    end if;
    res := res || format(E'\n  %s %s: %s; net %s; held back %s%s', c.kind, c.k,
      (select string_agg(h.key || ' ' || (h.value #>> '{}'), ', ' order by h.key) from jsonb_each(o->'holds') h), o->>'net',
      o->>'held', coalesce('; refused: ' || left(o->>'error', 90), ''));
  end loop;
  raise notice 'PASS A: after 477 each case ends by the Owner''s rules, the invariants hold in every case and Cancel takes all of it back; the controls are exactly as before 477%:%',
    case when exists (select 1 from t477_res where phase = 'before') then '' else ' (no before figures: -v nomig=1)' end, res;
end $$;

-- ===== M (after). The mid set finished with 477 in =====
\if :{?nomig}
\else
do $$
declare c record; o jsonb; res text := '';
begin
  for c in select * from t477_mid order by ord loop
    o := pg_temp.t477_run('mid', c.k, c.steps, c.split + 1);
    perform pg_temp.t477_check(pg_temp.t477_meets(o, c.expect) and coalesce(o->>'invariants', '') = ''
        and (c.expect ? 'cancel_left' or coalesce((o->>'cancel_left')::numeric, 0) = 0),
      'M ' || c.k || ': ' || coalesce(pg_temp.t477_diff(o, c.expect), '') || ' ' || o::text);
    res := res || ' ' || c.k;
  end loop;
  raise notice 'PASS M: begun before 477 and finished after it, each ends as the whole case does after 477; credit given back before 477 on a closed lot stays (MPTs1) until the lot''s next refund opens it (MPTs2: S$30 held back), on a lot 328''s repair replaced stays (MR328ps: Cancel leaves S$20) until the next refund takes it along (MR328p: A S$100, Cancel takes it all):%', res;
end $$;
\endif

-- ===== P. Probes =====
-- The lot of an invoice's release record that 328's repair replaced (its
-- repair row).
create function pg_temp.t477_repaired(p_inv uuid) returns uuid language sql as $f$
  select pl.lot_id from credit_package_progress_lots pl
   where pl.invoice_id = p_inv
     and exists (select 1 from customer_credit_ledger e where e.lot_id = pl.lot_id and e.source_type = 'credit_lot_provenance_repair') $f$;
do $$
declare inv uuid; a uuid; b uuid; f uuid; lot uuid; lot1 uuid; lot2 uuid; nl uuid; c uuid; v_err text;
begin
  -- P1 PTsx: the package's own lot, which an Owner reversed, opened by the
  -- special document's refund ('active', still locked), S$0, one held-back
  -- row of S$20 (A's, not queued); the reversal's S$60 row as it was; the
  -- document's allocation paid back; the lot's balance its ledger's; the
  -- row holds back S$20; the Audit Log says so; A's statement ends at S$0.
  inv := pg_temp.t477_id('after/PTsx/inv'); a := pg_temp.t477_id('after/PTsx/A'); lot := pg_temp.t477_own_lot(inv);
  perform pg_temp.t477_check(
        (select status from customer_credit_lots where id = lot) = 'active' and (select is_locked from customer_credit_lots where id = lot)
    and (select remaining_amount from customer_credit_lots where id = lot) = 0
    and (select count(*) from customer_credit_ledger x where x.lot_id = lot and x.source_type = 'reversal' and x.entry_type = 'reverse' and x.amount = 60) = 1
    and (select count(*) from customer_credit_ledger x where x.lot_id = lot and x.source_type = 'special_sale' and x.entry_type = 'reverse' and x.amount = 20) = 1
    and not exists (select 1 from special_credit_allocations s where s.lot_id = lot and s.amount > coalesce(s.reversed_amount, 0))
    and pg_temp.t477_ledger_balance(lot) = 0
    and pg_temp.t477_held_n(lot) = 1 and pg_temp.t477_held(lot) = 20
    and (select x.customer_id from customer_credit_ledger x where x.lot_id = lot and x.reason like 'Held back by%') = a
    and (select cancelled_unused_value from invoice_benefit_values where id = pg_temp.t477_own(inv)) = 20
    and (select count(*) from audit_logs al where al.record_id = inv and al.action = 'credit_given_back_followed'
          and (al.new_data->>'held_in_place')::boolean and (al.new_data->>'held_back')::numeric = 20) = 1
    and (select wallet_balance from customer_credit_statement(a) order by entry_date desc, entry_seq desc limit 1) = 0,
    'P1 PTsx: the special document''s refund did not open the lot and hold the S$20 back there');
  -- P2 PTsxp: paid, the S$20 back on the opened lot, A spent it (S2 paid
  -- from it); PTsxh: the S$20 went to B as one new lot that replaces the
  -- lot the records name; A's lot at S$0.
  inv := pg_temp.t477_id('after/PTsxp/inv'); lot := pg_temp.t477_own_lot(inv);
  perform pg_temp.t477_check((select status from customer_credit_lots where id = lot) = 'active'
      and exists (select 1 from invoice_line_credit_allocations x join invoice_items it on it.id = x.invoice_item_id
                   where x.lot_id = lot and it.invoice_id = pg_temp.t477_id('after/PTsxp/S2') and x.amount = 20),
    'P2 PTsxp: A did not spend the S$20 from the opened lot');
  inv := pg_temp.t477_id('after/PTsxh/inv'); b := pg_temp.t477_id('after/PTsxh/B'); lot := pg_temp.t477_own_lot(inv);
  perform pg_temp.t477_check((select customer_id from customer_credit_lots where id = lot) = b
      and (select remaining_amount from customer_credit_lots where id = lot) = 20
      and not (select is_locked from customer_credit_lots where id = lot)
      and (select count(*) from audit_logs al where al.record_id = inv and al.action = 'credit_given_back_followed'
            and (al.new_data->>'lot_id')::uuid = lot and al.new_data->>'to_customer' = b::text) = 1,
    'P2 PTsxh: the S$20 did not go to B');
  -- P3 MVX: the Move took what A's lot holds now (S$20); F's lot is a Move's
  -- (its source the transfer), not locked, traced to A's lot as its origin,
  -- spendable by its policy; A's lot S$0, still locked, the reversal's S$60
  -- row as it was; one transfer and one new benefit row for F; the Audit
  -- Log row of the Move.
  inv := pg_temp.t477_id('after/MVX/inv'); a := pg_temp.t477_id('after/MVX/A'); f := pg_temp.t477_id('after/MVX/F');
  lot := pg_temp.t477_own_lot(inv);
  select l.id into nl from customer_credit_lots l where l.customer_id = f;
  perform pg_temp.t477_check(
        (select remaining_amount from customer_credit_lots where id = nl) = 20 and (select original_amount from customer_credit_lots where id = nl) = 20
    and not (select is_locked from customer_credit_lots where id = nl) and (select status from customer_credit_lots where id = nl) = 'active'
    and (select source_type from customer_credit_lots where id = nl) = 'invoice_benefit_transfer'
    and invoice_credit_transfer_origin(nl) = lot and credit_lot_policy_for(nl) <> 'needs_review'
    and (select remaining_amount from customer_credit_lots where id = lot) = 0 and (select is_locked from customer_credit_lots where id = lot)
    and (select count(*) from customer_credit_ledger x where x.lot_id = lot and x.source_type = 'reversal' and x.amount = 60) = 1
    and (select count(*) from invoice_benefit_transfers t where t.invoice_id = inv and t.transferred_value = 20) = 1
    and (select count(*) from invoice_benefit_values bv where bv.invoice_id = inv and bv.lot_id = nl) = 1
    and (select count(*) from audit_logs al where al.record_id = inv and al.action = 'unused_benefit_recipient_corrected') = 1,
    'P3 MVX: the Move of the credit given back on the lot an Owner reversed is not as tested');
  -- P4 R328p: the S$20 given back on the lot 328's repair replaced and the
  -- S$20 its replacement held went to A as one new lot (S$40, not locked)
  -- replacing the replacement (reassigned_from_lot_id), with its source;
  -- the benefit row names the new lot; the old lot S$0, still locked, its
  -- repair row as it was; the release record unchanged (S$40 released); the
  -- Audit Log names the lot replaced.
  inv := pg_temp.t477_id('after/R328p/inv'); a := pg_temp.t477_id('after/R328p/A');
  lot1 := pg_temp.t477_repaired(inv);
  select pl.lot_id into lot2 from credit_package_progress_lots pl where pl.replaces_lot_id = lot1;
  select bv.lot_id into nl from invoice_benefit_values bv where bv.invoice_id = inv and bv.lot_id = any (credit_lot_chain(lot2));
  perform pg_temp.t477_check(nl is not null and nl <> lot2
    and (select reassigned_from_lot_id from customer_credit_lots where id = nl) = lot2
    and (select customer_id from customer_credit_lots where id = nl) = a
    and (select remaining_amount from customer_credit_lots where id = nl) = 40 and not (select is_locked from customer_credit_lots where id = nl)
    and (select (source_type, source_record_id) from customer_credit_lots where id = nl) = (select (source_type, source_record_id) from customer_credit_lots where id = lot2)
    and (select remaining_amount from customer_credit_lots where id = lot1) = 0 and (select is_locked from customer_credit_lots where id = lot1)
    and (select remaining_amount from customer_credit_lots where id = lot2) = 0
    and (select count(*) from customer_credit_ledger x where x.lot_id = lot1 and x.source_type = 'credit_lot_provenance_repair' and x.amount = 20) = 1
    and (select released_amount from credit_package_progress_lots where lot_id = lot1) = 40
    and (select count(*) from audit_logs al where al.record_id = inv and al.action = 'credit_given_back_followed'
          and (al.new_data->>'replaces_lot_id')::uuid = lot2 and (al.new_data->>'lot_id')::uuid = nl and (al.new_data->>'amount')::numeric = 40) = 1,
    'P4 R328p: the credit given back on the lot 328''s repair replaced did not follow to the lot the records name');
  -- P5 R328u (not paid in full): the new lot replaces the lot the release
  -- record reached (credit_lot_current reaches the new lot, which holds
  -- S$40), the Audit Log says it is released credit; R328u2's second refund
  -- takes the place of the first new lot (the chain grows by one lot only).
  inv := pg_temp.t477_id('after/R328u/inv'); lot1 := pg_temp.t477_repaired(inv);
  select pl.lot_id into lot2 from credit_package_progress_lots pl where pl.replaces_lot_id = lot1;
  nl := credit_lot_current(lot1);
  perform pg_temp.t477_check(nl <> lot2 and (select reassigned_from_lot_id from customer_credit_lots where id = nl) = lot2
      and (select remaining_amount from customer_credit_lots where id = nl) = 40
      and (select count(*) from audit_logs al where al.record_id = inv and al.action = 'credit_given_back_followed'
            and (al.new_data->>'released_credit')::boolean and (al.new_data->>'release_lot_id')::uuid = lot1
            and (al.new_data->>'lot_id')::uuid = nl) = 1,
    'P5 R328u: not on the lot the release record reaches now');
  inv := pg_temp.t477_id('after/R328u2/inv'); lot1 := pg_temp.t477_repaired(inv);
  select pl.lot_id into lot2 from credit_package_progress_lots pl where pl.replaces_lot_id = lot1;
  perform pg_temp.t477_check(cardinality(credit_lot_chain(lot1)) = 3
      and (select reassigned_from_lot_id from customer_credit_lots where id = credit_lot_current(lot1)) = lot2
      and (select remaining_amount from customer_credit_lots where id = credit_lot_current(lot1)) = 40,
    'P5 R328u2: the second refund lengthened the chain: ' || cardinality(credit_lot_chain(lot1)));
  -- P6 a lot outside any invoice (an Owner's S$50 grant to a new customer),
  -- S$20 of it paid to a special document, the S$30 left reversed, the
  -- document refunded: the lot is open with S$20 (before 477 it stayed
  -- closed); nothing else is done with it (no invoice names it).
  c := pg_temp.t477_cust('P/P6/A');
  perform pg_temp.t477_step('P/P6', 'grant A 50');
  perform pg_temp.t477_step('P/P6', 'special A special_sale 20');
  perform pg_temp.t477_step('P/P6', 'reverse A');
  v_err := pg_temp.t477_step('P/P6', 'unspecial D1');
  select l.id into lot from customer_credit_lots l where l.customer_id = c;
  perform pg_temp.t477_check(v_err is null and (select status from customer_credit_lots where id = lot) = 'active'
      and (select remaining_amount from customer_credit_lots where id = lot) = 20 and (select is_locked from customer_credit_lots where id = lot)
      and not exists (select 1 from customer_credit_ledger x where x.lot_id = lot and x.source_type like 'credit_given_back%'),
    'P6 a lot no invoice names was not opened by the special document''s refund: ' || coalesce(v_err, ''));
  -- P7 TQx1 (not paid in full, after a 'transfer' change): the S$20 went to
  -- B as one new lot that replaces the release record's lot (A's, S$0 now),
  -- which the release record reaches now (credit_lot_current), with its
  -- source; the release record unchanged (S$100 released); the Audit Log
  -- says it is released credit and to whom; TQx2's second refund takes the
  -- place of the first new lot (one lot of S$40).
  inv := pg_temp.t477_id('after/TQx1/inv'); a := pg_temp.t477_id('after/TQx1/A'); b := pg_temp.t477_id('after/TQx1/B');
  select pl.lot_id into lot1 from credit_package_progress_lots pl where pl.invoice_id = inv;
  nl := credit_lot_current(lot1);
  perform pg_temp.t477_check(nl <> lot1 and (select reassigned_from_lot_id from customer_credit_lots where id = nl) = lot1
      and (select customer_id from customer_credit_lots where id = nl) = b
      and (select remaining_amount from customer_credit_lots where id = nl) = 20 and not (select is_locked from customer_credit_lots where id = nl)
      and (select (source_type, source_record_id, category) from customer_credit_lots where id = nl)
          = (select (source_type, source_record_id, category) from customer_credit_lots where id = lot1)
      and (select customer_id from customer_credit_lots where id = lot1) = a
      and (select remaining_amount from customer_credit_lots where id = lot1) = 0
      and (select released_amount from credit_package_progress_lots where lot_id = lot1) = 100
      and (select count(*) from audit_logs al where al.record_id = inv and al.action = 'credit_given_back_followed'
            and (al.new_data->>'released_credit')::boolean and (al.new_data->>'release_lot_id')::uuid = lot1
            and (al.new_data->>'lot_id')::uuid = nl and al.new_data->>'to_customer' = b::text) = 1,
    'P7 TQx1: the S$20 did not go to B on the lot the release record reaches now');
  inv := pg_temp.t477_id('after/TQx2/inv'); b := pg_temp.t477_id('after/TQx2/B');
  select pl.lot_id into lot1 from credit_package_progress_lots pl where pl.invoice_id = inv;
  perform pg_temp.t477_check((select count(*) from customer_credit_lots where customer_id = b and remaining_amount > 0) = 1
      and (select remaining_amount from customer_credit_lots where id = credit_lot_current(lot1)) = 40
      and (select customer_id from customer_credit_lots where id = credit_lot_current(lot1)) = b
      and (select reassigned_from_lot_id from customer_credit_lots where id = credit_lot_current(lot1)) = lot1,
    'P7 TQx2: the second refund did not take the place of the first new lot');
  -- P8 MVW (answer D): F's lot is a Move's, not locked, traced to A's lot
  -- (the one Cancel's write-off locked) as its origin, spendable by its
  -- policy; A's lot S$0, open and still locked; the write-off's S$15 row on
  -- it as it was; one transfer of S$20, one new benefit row for F; the Audit
  -- Log row of the Move.
  inv := pg_temp.t477_id('after/MVW/inv'); f := pg_temp.t477_id('after/MVW/F');
  lot := pg_temp.t477_closed_lot(inv);
  select l.id into nl from customer_credit_lots l where l.customer_id = f;
  perform pg_temp.t477_check(lot is not null and nl is not null
    and (select remaining_amount from customer_credit_lots where id = nl) = 20 and not (select is_locked from customer_credit_lots where id = nl)
    and (select source_type from customer_credit_lots where id = nl) = 'invoice_benefit_transfer'
    and invoice_credit_transfer_origin(nl) = lot and credit_lot_policy_for(nl) <> 'needs_review'
    and (select remaining_amount from customer_credit_lots where id = lot) = 0 and (select is_locked from customer_credit_lots where id = lot)
    and (select status from customer_credit_lots where id = lot) = 'active'
    and (select count(*) from customer_credit_ledger x where x.lot_id = lot and x.entry_type = 'adjust_decrease'
          and x.source_type = 'invoice_cancel_released_credit' and x.amount = 15) = 1
    and (select count(*) from invoice_benefit_transfers t where t.invoice_id = inv and t.transferred_value = 20) = 1
    and (select count(*) from invoice_benefit_values bv where bv.invoice_id = inv and bv.lot_id = nl) = 1
    and (select count(*) from audit_logs al where al.record_id = inv and al.action = 'unused_benefit_recipient_corrected') = 1,
    'P8 MVW: the Move of the credit given back on the lot Cancel''s write-off locked is not as tested');
  -- P9 MVW0: all of the lot was spent when the invoice was cancelled, so the
  -- write-off took nothing and wrote no row on it (it still locked it); the
  -- Move went through all the same (F S$20), by the release record.
  inv := pg_temp.t477_id('after/MVW0/inv'); lot := pg_temp.t477_closed_lot(inv);
  perform pg_temp.t477_check(lot is not null
      and not exists (select 1 from customer_credit_ledger x where x.lot_id = lot and x.source_type like 'invoice\_%\_released\_credit')
      and not exists (select 1 from customer_credit_ledger x where x.lot_id = lot and x.source_type in ('reversal', 'credit_lot_provenance_repair'))
      and (select remaining_amount from customer_credit_lots where id = lot) = 0 and (select is_locked from customer_credit_lots where id = lot)
      and (select v->'holds'->>'F' from t477_res where phase = 'after' and k = 'MVW0') = '20.00',
    'P9 MVW0: the lot the write-off locked without a row of its own was not moved by its release record');
  -- P10 MVWt's state before the Move, with a 328 repair row (a stand-in) on
  -- A's lot, the one B's lot was reissued from: the Move of B's locked lot is
  -- refused, changing nothing (328's repair is still refused).
  perform pg_temp.t477_run('P', 'P10', 'sale A cp 40; spend A; cancel; reopen; unspend S1; change B; pay');
  inv := pg_temp.t477_id('P/P10/inv'); b := pg_temp.t477_id('P/P10/B');
  -- (A's lot: the last of the history of B's locked lot, the one a release
  -- record names; not picked by time, which ties within the suite's one
  -- transaction)
  select a.id into lot
    from customer_credit_lots l, unnest(credit_lot_ancestry(l.id)) with ordinality a(id, n)
   where l.customer_id = b and l.is_locked and l.remaining_amount > 0
   order by a.n desc limit 1;
  perform pg_temp.t477_check(lot is not null and exists (select 1 from credit_package_progress_lots pl where pl.lot_id = lot)
      and (select customer_id from customer_credit_lots where id = lot) = pg_temp.t477_id('P/P10/A'),
    'P10 set-up: B''s locked lot is not a copy of A''s released lot');
  insert into customer_credit_ledger (wallet_id, customer_id, entry_type, category, amount, lot_id, source_type, source_record_id, store_id, reason, created_by, approved_by)
  select l.wallet_id, l.customer_id, 'reverse', l.category, 0.01, l.id, 'credit_lot_provenance_repair', l.id, l.store_id, 'T477 stand-in', auth.uid(), auth.uid()
    from customer_credit_lots l where l.id = lot;
  v_err := pg_temp.t477_step('P/P10', 'movel 1 F');
  perform pg_temp.t477_check(v_err like 'movel 1 F: This credit lot is locked or reversed%'
      and exists (select 1 from customer_credit_lots l where l.customer_id = b and l.is_locked and l.remaining_amount = 20
                     and lot = any (credit_lot_ancestry(l.id)))
      and not exists (select 1 from customer_credit_lots l where l.customer_id = pg_temp.t477_id('P/P10/F'))
      and not exists (select 1 from invoice_benefit_transfers t where t.invoice_id = inv),
    'P10 a lot with 328''s repair on its history was moved: ' || coalesce(v_err, 'moved'));
  raise notice 'PASS P: PTsx''s lot opened by the special document''s refund and the S$20 held back there (the reversal''s S$60 still taken, the Audit Log, the statement at S$0); PTsxp spent from it; PTsxh B''s; MVX F''s lot not locked, traced to its origin, A''s lot S$0 and locked; R328p one new lot of S$40 replacing the repair''s lot, the records naming it, the release record unchanged; R328u the lot the release record reaches now, R328u2 one lot more only; a lot outside any invoice opened; TQx1 B''s new lot the release record reaches now, TQx2 one lot of S$40; MVW F''s lot not locked, traced to the lot Cancel''s write-off locked, which stays locked at S$0 with the write-off''s row; MVW0 moved by its release record though the write-off wrote no row; with 328''s repair on the lot''s history, refused (P10)';
end $$;

-- ===== K. KNOWN: 477's NOT COVERED (each checked as it is) =====
do $$
declare inv uuid; c uuid; it uuid; lot uuid; v_err text;
begin
  -- K1 (NOT COVERED 1): answer D settles the Move of a lot only Cancel's
  -- write-off locked (MVW: F S$20; locked by the write-off and then an
  -- Owner's reversal, MVS2: F S$5); a lock that no Owner's reversal and no
  -- release record explains is still refused (MVL, the stand-in), and so is
  -- one with 328's repair on the lot's history (P10).
  perform pg_temp.t477_check((select v->>'error' from t477_res where phase = 'after' and k = 'MVW') is null
      and (select v->'holds'->>'F' from t477_res where phase = 'after' and k = 'MVW') = '20.00'
      and (select v->'holds'->>'F' from t477_res where phase = 'after' and k = 'MVS2') = '5.00'
      and (select v->>'error' from t477_res where phase = 'after' and k = 'MVL') like 'move 1 F: This credit lot is locked or reversed%',
    'K1 MVW/MVL: look at NOT COVERED 1 again');
  -- K2 (NOT COVERED 2): credit a special document's refund put on a closed
  -- lot before 477 stays there (MPTs1: A S$20 no one can spend), until the
  -- lot's next refund opens it (MPTs2).
  if exists (select 1 from t477_res where phase = 'mid' and k = 'MPTs1') then
    inv := pg_temp.t477_id('mid/MPTs1/inv'); lot := pg_temp.t477_own_lot(inv);
    perform pg_temp.t477_check((select status from customer_credit_lots where id = lot) = 'reversed'
        and (select remaining_amount from customer_credit_lots where id = lot) = 20
        and (select (v->>'held')::numeric from t477_res where phase = 'mid' and k = 'MPTs2') = 30,
      'K2 MPTs1: look at NOT COVERED 2 again');
  end if;
  -- K3 (NOT COVERED 3): credit given back before 477 on a lot 328's repair
  -- replaced stays there (MR328ps: Cancel leaves S$20) until the next
  -- refund takes it along (MR328p).
  if exists (select 1 from t477_res where phase = 'mid' and k = 'MR328ps') then
    perform pg_temp.t477_check((select (v->>'cancel_left')::numeric from t477_res where phase = 'mid' and k = 'MR328ps') = 20
        and coalesce((select (v->>'cancel_left')::numeric from t477_res where phase = 'mid' and k = 'MR328p'), 0) = 0,
      'K3 MR328ps: look at NOT COVERED 3 again');
    -- and before settlement (d): what S1's refund gave back before 477 stays
    -- with A until S2's refund takes it along (MTQx: B S$40).
    perform pg_temp.t477_check((select v->'holds' from t477_res where phase = 'mid' and k = 'MTQx') @> '{"A":"0.00","B":"40.00"}',
      'K3 MTQx: look at NOT COVERED 3 again');
  end if;
  -- K4 (472's K1 L327, why (c) is defensive): a lot with 327's source (what
  -- the real repair replaced) funds nothing, so no sale is paid from one.
  c := pg_temp.t477_cust('K/L327/A');
  inv := pg_temp.t477_id('after/R328/inv'); it := (select id from invoice_items where invoice_id = inv limit 1);
  lot := grant_customer_credit(c, 'paid', 50, 'credit_package_progress', it, pg_temp.t477_id('store'), sg_today(), null,
    'T477 a lot as 327 released it', 'T477 stand-in', sg_today(), auth.uid(), null);
  begin
    perform pg_temp.t477_spend(c);
    v_err := null;
  exception when others then v_err := sqlerrm;
  end;
  perform pg_temp.t477_check(v_err like 'Only 0 of the requested 20.00 could be funded by eligible credit%'
      and (select remaining_amount from customer_credit_lots where id = lot) = 50,
    'K4 L327: a lot with 327''s source could be spent from: ' || coalesce(v_err, 'spent'));
  raise notice 'KNOWN K: (477''s NOT COVERED) (1) a Move of a lot Cancel''s write-off locked now allowed (MVW: F S$20; MVS2: F S$5), a lock nothing explains still refused (MVL, the stand-in), and 328''s (P10); (2) credit on a closed lot from before 477 stays there until the lot''s next refund%; (3) credit on a lot 328''s repair replaced from before 477 stays until the next refund%; a lot with 327''s source funds nothing (L327), so on production no sale is paid from one',
    case when exists (select 1 from t477_res where phase = 'mid' and k = 'MPTs1') then ' (MPTs1 S$20, then MPTs2 S$30 held back)' else ' (not tried: -v nomig=1)' end,
    case when exists (select 1 from t477_res where phase = 'mid' and k = 'MR328ps') then ' (MR328ps Cancel leaves S$20, then MR328p S$0)' else ' (not tried: -v nomig=1)' end;
end $$;

rollback;
