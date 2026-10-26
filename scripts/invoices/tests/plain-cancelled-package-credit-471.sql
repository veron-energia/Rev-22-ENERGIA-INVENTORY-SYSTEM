-- 471: credit a refunded or corrected sale gives back while its package is
-- cancelled, refunded or waiting for its reopening's payment is held back by
-- the cancellation also where the package never changed hands: the lot its
-- records name, held by its buyer (470's NOT COVERED 1: G2, G3, RX0; the
-- Owner, 26 Oct 2026: "Yes, fix it after 470"); and where the package was
-- paid in part, its credit released before full payment (no benefit row
-- names that lot), as Cancel's write-off takes it.
-- supabase/471_plain_cancelled_package_credit_held_back.sql (after 462, 463 and 470).
--
-- Every step goes through the app's own calls (462's and 470's suite
-- harness): the invoice form (create_invoice_with_details) and the Pay
-- dialog (record_invoice_settlement), Record Payment, Cancel, the Finance
-- panel's refund by line and "Record refund paid" (refund_invoice_recorded),
-- its Correct payment (correct_invoice_payment), Reopen, Move
-- (transfer_invoice_unused_benefit), the guided Refund in full and Cancel
-- (invoice_action_plan, request_invoice_action_v2, resolve_invoice_action_v2,
-- "Record refund paid" ticked, or not: 'guidedkeep'), the invoice form's customer change
-- (correct_invoice, 'transfer'), a customer merge, Delete customer; a special
-- document's wallet payment is 462's stand-in, its refund the real
-- refund_special_credit; the legacy statuses are set directly (a stand-in).
-- Each app call is followed by what its commit does: 462's trigger on the
-- ledger is DEFERRABLE INITIALLY DEFERRED and this suite is one transaction,
-- so its queued rows are run at that point (SET CONSTRAINTS ... IMMEDIATE,
-- then DEFERRED again). 471 adds no trigger.
--
-- The cases (A the buyer; B a later customer; K a record a merge keeps; F a
-- friend an Owner moved the package's remaining credit to; cp a S$100 Credit
-- Package, cpb one with a S$10 Bonus, pbv the S$140 Premium Bundle; S1, S2
-- S$20 sessions paid from the package's credit (svc5: S$5); no Move, no
-- customer change, no merge of the package's own lot unless it says so: its
-- named lot is the buyer's, who holds the benefits):
--   G2, G3    the guided Cancel with "Record refund paid", S2 refunded (then
--             refunded by line): 470's KNOWN K (1). G2s A tries to spend it;
--             GN, GNb the same without the Move; P2s two sessions refunded.
--   RX0       refunded by line in full with an Owner's 'larger_refund', then
--             S1 refunded (ends as 470's RX1: held back, owed to nobody).
--   PCs       a plain Cancel, S1 refunded, A tries to spend it.
--   PCx, PCv, PCd (and ...b, refunded by line)  the Bonus package, the
--             Premium Bundle and that bundle S$7 off: what is owed back grows
--             by the money of S$20 (S$18.18, S$14.00, S$13.64).
--   PFc, PFa (and ...b)  Correct payment of S2 (to cash; S$5 less) while
--             cancelled instead of its refund.
--   PWs       cancelled, S$60 refunded by line, reopened (it waits), S2
--             refunded while it waits, A tries to spend it.
--   PCh, PChg a 'transfer' customer change of the cancelled package after the
--             hold (then reopened and paid; refunded by line).
--   PM, PMg   a merge of A after the hold: refused as before (445's NOT
--             COVERED 1). PMb, PMbb: the buyer merged before the sessions
--             (the kept record's reissued lot is then the plain one).
--   PCa       Cancel again after the hold: nothing more.
--   SSp, SSpb a special document's credit given back instead (then refunded
--             by line); L13p a 13-line sale refunded at once; CH5p five
--             sessions refunded one by one.
--   PDel      the buyer deleted while cancelled (held for no one: in place).
--   Paid in part (sale A cp 40: S$40 of S$100 paid, S$40 of credit released
--   before full payment; B in 471's header):
--   PT1, PT1r a plain Cancel, S1 refunded (then "Record refund paid" of the
--             S$40 held); PTs A tries to spend it; PT2, PT2u two sessions
--             (both refunded; one); PTg, PTgr the guided Cancel that kept it
--             all (S$0 owed back), S1 refunded (then recorded); PTf, PTfa
--             Correct payment of S2 (to cash; S$5 less); PTv the Premium
--             Bundle; PTch a customer change after the hold; PTm a merge
--             after it (refused as before); PTmb, PTcb the buyer merged or
--             the customer changed before the session; PTsp a special
--             document's credit; PTd the buyer deleted while cancelled; PTca
--             Cancel again after the hold.
--   Paid in part, cancelled, reopened and paid in full (a benefit row then
--   names the released lot the first Cancel's write-off closed: 'reversed',
--   locked), then given back on that lot (B's lock, 471's review): PTRc,
--   PTRcs Cancel again, S1 refunded (A tries to spend it); PTRa Cancel once
--   more; PTRg, PTRgb, PTRgs the guided Cancel (then refunded by line; A
--   tries to spend it); PTRx refunded in full with an override; PTRw a
--   reopening waiting (A tries to spend it); PTRf, PTRfb Correct payment of
--   S2 to cash; PTRv, PTRvb the Premium Bundle; PTRh, PTRhp a 'transfer'
--   customer change after the payment (then cancelled; or still paid: it
--   follows B).
--   A lot an Owner reversed (NOT COVERED 10, 'known': the same with and
--   without 471): PX, PXs paid in full, the S$60 left reversed, cancelled,
--   S1 refunded (A tries to spend it); S8gb, S8gs paid in part, the released
--   lot's S$15 reversed, reopened and paid, a guided Cancel, S1 refunded
--   (refunded by line; A tries to spend it); S2gb the released lot a Cancel
--   closed reversed once S1's refund opened it. O1 ('fixed'): a copy of the
--   reversed lot (B's, the reopening's payment after a 'transfer' change),
--   B's session refunded while cancelled: held back.
--   Controls (the same with and without 471): PC (a plain Cancel, the
--   refund by line pays it all), PW, PWb, PWc, PWfa (a reopening waiting
--   then paid; refunded by line while it waits; Cancel again; Correct
--   payment while it waits), PR, PRg (cancelled, reopened and paid at once;
--   after a guided Cancel), PRx (refunded, reopened, paid), PB, PBr (a
--   session refunded BEFORE the cancel stays as today), PP, PPr, PPf, PRF,
--   PFd, LGp (paid, refunded with used credit kept, a date-only correction,
--   the legacy statuses: followed as paid), and 470's C0, C0r, C2; paid in
--   part: PTB (S1 refunded before the Cancel), PTr, PTr2, PTrc (reopened
--   after the hold, or before S1's refund; cancelled again), PTp, PTpf (not
--   cancelled), PTRp, PTRr, PTRwp (reopened and paid in full: S1 refunded
--   while paid; cancelled again, S1 refunded, reopened and paid; a
--   reopening waiting, then paid).
-- In every case (462's invariants): no lot of the invoice's family holds
-- credit unless a record names it; each lot's balance is its ledger's; no
-- chain over 12; moved lots traced; origins kept; a named lot holding credit
-- is held by whoever holds the benefits; no benefit row holds back more than
-- it granted, nor anything once settled with no reopening waiting; a
-- refunded invoice leaves no credit; and Cancel (tried, undone) takes all of
-- the invoice's credit back from whoever holds it.
--
--   S. Where it starts: 462, 463 and 470 in, the triggers on invoices as
--      read; 471 in (nomig) or not, the forwarder at 470's AFTER.
--   R. Without 471 (skipped with -v nomig=1), undone: each 'fixed' case ends
--      otherwise (the fault reproduced: G2 A S$20 net S$20; G3 refused, "That
--      is more than the S$0.00 still owed back"; RX0 A S$20 of a refunded
--      invoice; ...); each control as expected.
--   Q. The read-only query in 471's header (the same text), on states made
--      for it and the R states: what it lists, by reason (1 to 9; also the
--      released lot a Cancel closed behind the lot the records name: HQ1,
--      HQ3, HQ1u, HQ3u).
--   9. Refusals, each changing nothing: the forwarder neither 470's nor
--      471's; a function it relies on not as tested; an overload of its
--      name; a new reader of a cancellation's rows; a new trigger on
--      invoices; a new way to raise a lot; a new reader of the release
--      record; a new way to lock a lot. The same grants in another order do
--      not stop it.
--   M. The mid set: begun before 471 (cancelled, refunded, waiting), finished
--      after it; and credit given back before 471 (G2's state today): left
--      as it is, then held back with the next refund or correction; behind
--      the lot the records name (MHQ3, MHQ3s, MHQ3r).
--  10. 471 installed twice: as tested, the second run changing nothing,
--      nothing added (no function, no trigger), the grants as before.
--   A. Each case after 471: who holds what, the money, the plans' codes and
--      refund due, the invariants, Cancel; the controls exactly as before.
--   P. Probes: the held-back row in place (no lot reissued, the Audit Log,
--      the statement); the amount owed back by its money (what the refund
--      options offer, the Finance panel's and Cancel's refund due, S$0 after
--      the refund by line); the queue while a reopening waits and its
--      payment; 446's matching; one held row for a 13-line refund, five for
--      five; the Reopen dialog's credit to reinstate; nothing held for the
--      controls; the buyer deleted.
--   K. KNOWN (471's NOT COVERED), checked as they are: RX0 held back, owed
--      to nobody, the refund by line refused (1); not spendable while a
--      reopening waits (2); a merge of the buyer refused (3); credit given
--      back before 471 left spendable (4), and credit an override's refund
--      left swept at the next session's refund (K6); the Reopen dialog
--      leaving out credit queued for an earlier reopening (K5, NOT COVERED
--      7); paid in part: S$1 owed back for S$1, also past the paid credit,
--      and nothing held once reopened (K8, NOT COVERED 8); a 'transfer'
--      customer change allowed though credit released before full payment
--      was spent (K9, NOT COVERED 9); a lot an Owner reversed passed over,
--      the credit given back on it spendable on a cancelled package, the
--      same with and without 471 (K10, NOT COVERED 10: PX, PXs, S8gb, S8gs,
--      S2gb), its copy read as Cancel's write-off's (O1).
--
-- Run on a copy of production as it is (470 in, 26 Oct 2026: 0f581614,
-- 1387 functions):
--   psql -X -v ON_ERROR_STOP=1 -f scripts/invoices/tests/plain-cancelled-package-credit-471.sql
-- It installs 471 itself (twice) inside its transaction. Where 471 is in
-- already, add -v nomig=1 (S checks it as tested; R, Q, 9 and M are skipped;
-- every case after 471 is still checked). Section 9 lets the install fail
-- on purpose (psql prints its ERROR); the suite then checks that message.
-- Disposable database only; everything is rolled back. Every name, code and
-- amount is invented (@example.com); the phones are numbers kept for fiction
-- (ACMA, +61491570000 to +61491570999).
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '10s';
set local statement_timeout = '900s';

-- ── Set-up and the app's calls (462's and 470's suite harness, for 471) ───────────────
create temp table t471(k text primary key, id uuid);
create temp table t471_res(phase text, k text, v jsonb, primary key (phase, k));
create temp sequence t471_phone;
create function pg_temp.t471_id(p_k text) returns uuid language sql as $f$ select id from t471 where k = p_k $f$;
create function pg_temp.t471_put(p_k text, p_id uuid) returns uuid language sql as $f$
  insert into t471 values (p_k, p_id) on conflict (k) do update set id = excluded.id returning id $f$;
create function pg_temp.t471_check(p_ok boolean, p_label text) returns void language plpgsql as $f$
begin
  if not coalesce(p_ok, false) then raise exception 'FAIL %', p_label; end if;
end $f$;
create function pg_temp.t471_fingerprint() returns text language sql as $f$
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.oid::regprocedure::text)) || ' ' || count(*)
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prokind in ('f', 'p') $f$;
create function pg_temp.t471_463_in() returns boolean language sql as $f$
  select to_regprocedure('public.invoice_benefit_moved_to_other(uuid)') is not null $f$;
create function pg_temp.t471_462_in() returns boolean language sql as $f$
  select to_regprocedure('public.credit_given_back_follows(uuid)') is not null
     and exists (select 1 from pg_trigger where tgname = 'credit_given_back_follows'
                  and tgrelid = 'public.customer_credit_ledger'::regclass) $f$;
-- 471 is in: the forwarder is 471's (its text says so; S checks its md5).
create function pg_temp.t471_in() returns boolean language sql as $f$
  select to_regprocedure('public.credit_given_back_follows(uuid)') is not null
     and position('-- 471 (the Owner, 26 Oct 2026' in pg_get_functiondef('public.credit_given_back_follows(uuid)'::regprocedure)) > 0 $f$;
-- 470 is in (its text is in 471's too).
create function pg_temp.t471_470_in() returns boolean language sql as $f$
  select to_regprocedure('public.credit_given_back_follows(uuid)') is not null
     and position('-- 470 (the Owner, 24 Oct 2026' in pg_get_functiondef('public.credit_given_back_follows(uuid)'::regprocedure)) > 0 $f$;
-- What a commit does at the end of each app call (each is its own
-- transaction in the app): 462's deferred trigger on the ledger runs (471
-- adds no trigger: its change is in the function that trigger runs). Here
-- the suite is one transaction, so the trigger's queued rows are run at this
-- point. (Not where each step really commits: t471.autocommit 'on', for
-- running the same cases one call per transaction on a disposable copy.)
create function pg_temp.t471_commit() returns void language plpgsql as $f$
begin
  if coalesce(current_setting('t471.autocommit', true), '') = 'on' then return; end if;
  if pg_temp.t471_462_in() then
    execute 'set constraints public.credit_given_back_follows immediate';
    execute 'set constraints public.credit_given_back_follows deferred';
  end if;
end $f$;

do $$
declare own uuid := gen_random_uuid(); st uuid; st2 uuid; pm uuid; v uuid; cp uuid; cpb uuid; pbv uuid; svc uuid; svc5 uuid;
begin
  insert into auth.users(id, email) values (own, 't471-owner@example.com');
  insert into profiles(id, full_name, email, role, is_active) values (own, 'T471 Owner', 't471-owner@example.com', 'owner', true);
  perform set_config('request.jwt.claims', json_build_object('sub', own, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', own::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  insert into stores(name, code, country_code) values ('T471 Store', 'T471S1', 'SG') returning id into st;
  insert into stores(name, code, country_code) values ('T471 Other Store', 'T471S2', 'SG') returning id into st2;
  insert into payment_methods(name, is_active) values ('T471 Cash', true) returning id into pm;
  insert into vouchers(name, code, voucher_kind, qty_type, selling_price, is_active)
    values ('T471 Plain 30', 'T471-P30', 'normal', 'unlimited', 30, true) returning id into v;
  insert into voucher_store_prices(voucher_id, store_id, selling_price, available_at_store) values (v, st, 30, true), (v, st2, 30, true);
  insert into credit_packages(name, customer_price, paid_credit_amount, bonus_enabled, allow_product, allow_therapy)
    values ('T471 S$100', 100, 100, false, true, true) returning id into cp;
  insert into credit_package_stores(package_id, store_id) values (cp, st), (cp, st2);
  insert into credit_packages(name, customer_price, paid_credit_amount, bonus_enabled, bonus_value, allow_product, allow_therapy, grants_reward)
    values ('T471 S$100 + S$10', 100, 100, true, 10, true, true, false) returning id into cpb;
  insert into credit_package_stores(package_id, store_id) values (cpb, st), (cpb, st2);
  insert into premium_bundles(name, customer_payment_amount, paid_credit_amount, bonus_credit_amount, free_voucher_qty, grants_reward)
    values ('T471 Bundle S$140 + 2 vouchers', 140, 100, 40, 2, true) returning id into pbv;
  insert into premium_bundle_stores(bundle_id, store_id) values (pbv, st), (pbv, st2);
  insert into premium_bundle_vouchers(bundle_id, voucher_id) values (pbv, v);
  svc := (upsert_therapy_service(null, 'T471-SESSION', 'T471 Session', 20, 30, 'per_hours', 1, 5, null, true, null) ->> 'id')::uuid;
  perform set_therapy_service_store(svc, st, true, null);
  svc5 := (upsert_therapy_service(null, 'T471-SHORT', 'T471 Short session', 5, 15, 'per_hours', 1, 5, null, true, null) ->> 'id')::uuid;
  perform set_therapy_service_store(svc5, st, true, null);
  insert into t471 values ('own', own), ('store', st), ('store2', st2), ('pm', pm), ('v', v), ('cp', cp), ('cpb', cpb), ('pbv', pbv),
    ('svc', svc), ('svc5', svc5),
    ('wallet', (select id from payment_methods where name = 'Wallet — Credit Package Paid' and is_wallet_credit and deleted_at is null)),
    ('bwallet', (select id from payment_methods where name = 'Wallet — Premium Bundle Paid' and is_wallet_credit and deleted_at is null));
  perform pg_temp.t471_check(pg_temp.t471_id('wallet') is not null and pg_temp.t471_id('bwallet') is not null, 'setup: the wallet methods (443) are there');
end $$;

-- A customer of one run of one case: '<phase>/<case>/<role>'.
create function pg_temp.t471_cust(p_k text) returns uuid language plpgsql as $f$
declare c uuid;
begin
  insert into customers(full_name, phone) values ('T471 ' || p_k, '+61491570' || lpad((nextval('t471_phone') % 1000)::text, 3, '0'))
    returning id into c;
  return pg_temp.t471_put(p_k, c);
end $f$;
-- The invoice form with these lines ('cp' / 'cpb' a Credit Package, 'pbv' the
-- Premium Bundle, 'v' a voucher line of p_qty units), with an Owner's manual
-- discount of p_discount (its reason given) where one is given, paid through
-- the Pay dialog: in full, or p_first of it (a part-paid package).
create function pg_temp.t471_sale(p_cust uuid, p_kinds text[], p_first numeric default null, p_qty int default 2,
                                  p_discount numeric default null)
  returns uuid language plpgsql as $f$
declare inv uuid; v_lines jsonb := '[]'; i int;
begin
  for i in 1 .. cardinality(p_kinds) loop
    v_lines := v_lines || jsonb_build_array(case
      when p_kinds[i] = 'v' then jsonb_build_object('kind', 'voucher', 'voucher_id', pg_temp.t471_id('v'), 'quantity', p_qty)
      when p_kinds[i] in ('cp', 'cpb') then jsonb_build_object('kind', 'credit_package', 'credit_package_id', pg_temp.t471_id(p_kinds[i]), 'quantity', 1)
      else jsonb_build_object('kind', 'premium_bundle', 'premium_bundle_id', pg_temp.t471_id('pbv'), 'quantity', 1,
        'voucher_selection', jsonb_build_array(jsonb_build_object('voucher_id', pg_temp.t471_id('v'), 'quantity', 2))) end);
  end loop;
  inv := create_invoice_with_details(pg_temp.t471_id('store'), p_cust, v_lines, jsonb_build_object('business_date', sg_today()::text)
           || case when p_discount is not null
                   then jsonb_build_object('manual_discount', p_discount, 'manual_discount_reason', 'T471 discount') else '{}'::jsonb end);
  perform record_invoice_settlement(inv, jsonb_build_object('receipts', jsonb_build_array(jsonb_build_object(
    'key', 'line-0', 'payment_method_id', pg_temp.t471_id('pm'),
    'amount', coalesce(p_first, (select total_amount from invoices where id = inv)),
    'payment_date', sg_today()::text)), 'arrangements', '[]'::jsonb), gen_random_uuid());
  return inv;
end $f$;
-- Record Payment of what is outstanding (nothing when it is settled).
create function pg_temp.t471_pay(p_inv uuid) returns void language plpgsql as $f$
begin
  if (invoice_financial_position(p_inv)->>'outstanding')::numeric > 0 then
    perform record_invoice_payment(p_inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.t471_id('pm'),
      'amount', (invoice_financial_position(p_inv)->>'outstanding')::numeric)), gen_random_uuid());
  end if;
end $f$;
-- The receipts that still hold p_amount between them, as the Finance panel
-- splits a refund across them.
create function pg_temp.t471_sources(p_inv uuid, p_amount numeric) returns jsonb language plpgsql as $f$
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
create function pg_temp.t471_line(p_inv uuid, p_n int default 1) returns uuid language sql as $f$
  select id from invoice_items where invoice_id = p_inv order by id offset p_n - 1 limit 1 $f$;
-- The Finance panel's refund by line of line p_n: p_amount off its Paid
-- benefit (the one an Owner did not move, or with p_holder the one p_holder
-- holds), or every unused benefit it still holds (p_amount null).
create function pg_temp.t471_back(p_inv uuid, p_n int, p_amount numeric default null, p_holder uuid default null)
  returns void language plpgsql as $f$
declare opts jsonb; ben jsonb; tot numeric; item uuid := pg_temp.t471_line(p_inv, p_n);
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
  if ben is null then raise exception 'T471: nothing to refund on that line'; end if;
  perform refund_invoice_recorded(p_inv, jsonb_build_array(jsonb_build_object('invoice_item_id', item, 'amount', tot, 'benefits', ben)),
    pg_temp.t471_sources(p_inv, tot), '[]'::jsonb, 'T471 by line', gen_random_uuid());
end $f$;
-- The invoice form's customer change, its lines as they are (and the store,
-- when given), with 'transfer' or 'keep'. The change's Audit Log row is
-- dated now, as a later call's is (the suite is one transaction).
create function pg_temp.t471_lines(p_inv uuid) returns jsonb language sql as $f$
  select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('invoice_item_id', it.id, 'kind', it.line_kind,
           'credit_package_id', it.credit_package_id, 'premium_bundle_id', it.premium_bundle_id, 'voucher_id', it.voucher_id,
           'quantity', it.quantity, 'unit_price', it.unit_price, 'voucher_selection', it.bundle_voucher_selection)) order by it.id)
    from invoice_items it where it.invoice_id = p_inv $f$;
create function pg_temp.t471_change(p_inv uuid, p_cust uuid, p_action text default 'transfer', p_store text default null)
  returns void language plpgsql as $f$
begin
  perform correct_invoice(p_inv, pg_temp.t471_lines(p_inv),
    jsonb_build_object('expected_edit_count', (select edit_count from invoices where id = p_inv),
      'customer_id', p_cust, 'store_id', coalesce(pg_temp.t471_id(p_store), (select store_id from invoices where id = p_inv)),
      'benefit_action', p_action),
    'T471 wrong customer', gen_random_uuid());
  update audit_logs set created_at = clock_timestamp()
   where record_id = p_inv and action = 'invoice_benefits_followed_reassignment' and new_data->>'to_customer' = p_cust::text
     and created_at = now();
end $f$;
create function pg_temp.t471_merge(p_keep uuid, p_dup uuid) returns void language plpgsql as $f$
begin
  perform merge_customer_records(p_keep, p_dup, 'T471 the same person', gen_random_uuid());
end $f$;
-- The Finance panel's Move of line p_n's unused benefit (its Paid credit,
-- or its Bonus with p_kind 'bonus', or a voucher) to p_to, at p_store.
create function pg_temp.t471_move(p_inv uuid, p_n int, p_to uuid, p_kind text default 'paid', p_store text default null)
  returns void language plpgsql as $f$
declare b uuid;
begin
  select bv.id into b from invoice_benefit_values bv
    left join customer_reward_vouchers v on v.id = bv.reward_voucher_id
    left join customer_credit_lots l on l.id = bv.lot_id
   where bv.invoice_item_id = pg_temp.t471_line(p_inv, p_n)
     and (v.status = 'held' and p_kind = 'voucher' or l.remaining_amount > 0 and l.category = p_kind)
   order by bv.granted_value desc limit 1;
  if b is null then raise exception 'T471: nothing to move on that line'; end if;
  perform transfer_invoice_unused_benefit(b, p_to, coalesce(pg_temp.t471_id(p_store), (select store_id from invoices where id = p_inv)),
    'T471 move', gen_random_uuid());
end $f$;
-- The invoice form: p_n sessions of S$20 (or S$5 with p_svc 'svc5') for
-- p_cust, paid with the wallet (Credit Package Paid; Premium Bundle Paid with
-- p_wallet 'bwallet') through Record Payment.
create function pg_temp.t471_spend(p_cust uuid, p_n int default 1, p_svc text default 'svc', p_wallet text default 'wallet')
  returns uuid language plpgsql as $f$
declare inv uuid; v_lines jsonb := '[]'; i int;
begin
  for i in 1 .. p_n loop
    v_lines := v_lines || jsonb_build_array(jsonb_build_object('kind', 'therapy', 'therapy_service_id', pg_temp.t471_id(p_svc), 'quantity', 1));
  end loop;
  inv := create_invoice_with_details(pg_temp.t471_id('store'), p_cust, v_lines, jsonb_build_object('business_date', sg_today()::text));
  perform record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.t471_id(p_wallet),
    'amount', (select total_amount from invoices where id = inv))), gen_random_uuid());
  if (select status::text from invoices where id = inv) <> 'paid' then raise exception 'T471: the session paid from credit is not paid'; end if;
  return inv;
end $f$;
-- The session cancelled and "Record refund paid": what its payment took goes
-- back to the lots it came from (refund_invoice_recorded's wallet refund).
create function pg_temp.t471_unspend(p_inv uuid) returns void language plpgsql as $f$
declare due numeric;
begin
  perform cancel_invoice_recorded(p_inv, 'T471 cancel session', gen_random_uuid());
  due := (invoice_financial_position(p_inv)->>'refund_due')::numeric;
  if due is null or due <= 0 then due := (invoice_action_plan(p_inv, 'cancel', '[]')->>'refund_due')::numeric; end if;
  perform refund_invoice_recorded(p_inv, jsonb_build_array(jsonb_build_object('amount', due)), pg_temp.t471_sources(p_inv, due), '[]'::jsonb,
    'T471 refund paid', gen_random_uuid());
end $f$;
-- The Finance panel's Correct payment on a session's wallet payment: the
-- date only ('date'), a smaller amount ('amount', S$5 less), or another
-- method ('cash').
create function pg_temp.t471_fix(p_inv uuid, p_how text) returns void language plpgsql as $f$
declare p invoice_payments%rowtype;
begin
  select * into p from invoice_payments where invoice_id = p_inv and entry_kind in ('receipt', 'correction_replacement')
     and not exists (select 1 from invoice_payments q where q.corrects_payment_id = invoice_payments.id and q.entry_kind = 'correction_reversal')
   order by created_at desc, id desc limit 1;
  perform correct_invoice_payment(p.id,
    case p_how when 'amount' then p.amount - 5 else p.amount end,
    sg_today() - 1,
    case p_how when 'cash' then pg_temp.t471_id('pm') else p.payment_method_id end,
    'T471 correct payment ' || p_how, gen_random_uuid());
end $f$;
-- A special document's wallet payment as pay_special_with_credit records it
-- (a stand-in: no page calls that function, and no credit category allows a
-- special document today, purchase_category): p_amount off the customer's
-- largest lot ('use', its allocations), so refund_special_credit, the real
-- one, gives it back.
create function pg_temp.t471_special(p_cust uuid, p_kind text, p_doc uuid, p_amount numeric) returns void language plpgsql as $f$
declare l customer_credit_lots%rowtype; e uuid;
begin
  select * into l from customer_credit_lots where customer_id = p_cust and status = 'active' and remaining_amount >= p_amount
   order by remaining_amount desc, id limit 1 for update;
  insert into customer_credit_ledger(wallet_id, customer_id, entry_type, category, amount, lot_id, source_type, source_record_id, store_id, note, created_by)
  values (l.wallet_id, p_cust, 'use', l.category, p_amount, l.id, p_kind, p_doc, l.store_id, 'T471 special', auth.uid()) returning id into e;
  update customer_credit_lots set remaining_amount = remaining_amount - p_amount, updated_at = now() where id = l.id;
  insert into customer_credit_allocations(ledger_entry_id, lot_id, customer_id, amount) values (e, l.id, p_cust, p_amount);
  insert into special_credit_allocations(doc_kind, doc_id, customer_id, lot_id, category, amount, created_by)
  values (p_kind, p_doc, p_cust, l.id, l.category, p_amount, auth.uid());
end $f$;
-- The guided Refund in full / Cancel as an Owner confirms it, with a reason
-- for every override the plan asks for, the money recorded as paid back (or,
-- with p_record false, not: "Record refund paid" left unticked).
create function pg_temp.t471_guided(p_inv uuid, p_action text, p_record boolean default true) returns void language plpgsql as $f$
declare plan jsonb; req jsonb; ov jsonb;
begin
  plan := invoice_action_plan(p_inv, p_action, '[]');
  req := request_invoice_action_v2(p_inv, p_action, '[]', 'T471 ' || p_action, null, gen_random_uuid());
  select coalesce(jsonb_agg(case when coalesce((o->>'amount_required')::boolean, false)
           then jsonb_build_object('code', o->>'code', 'reason', 'T471 override', 'amount', (o->>'default_amount')::numeric)
           else jsonb_build_object('code', o->>'code', 'reason', 'T471 override') end), '[]'::jsonb)
    into ov from jsonb_array_elements(coalesce(plan->'overrides_required', '[]')) o;
  perform resolve_invoice_action_v2((req->>'request_id')::uuid, true, 'T471 ' || p_action, plan->>'plan_hash', ov, null, p_record);
end $f$;


-- ── What the records say ────────────────────────────────────────────────────
-- The lots an invoice's records name: its benefit values, its sale's lots, a
-- split's issued lot, released credit (credit_package_progress_lots).
create function pg_temp.t471_named(p_inv uuid) returns setof uuid language sql as $f$
  select lot_id from invoice_benefit_values where invoice_id = p_inv and lot_id is not null
  union select x from credit_package_sales s, unnest(array[s.credit_lot_id, s.bonus_credit_lot_id]) x where s.invoice_id = p_inv and x is not null
  union select x from premium_bundle_sales s, unnest(array[s.paid_credit_lot_id, s.bonus_credit_lot_id]) x where s.invoice_id = p_inv and x is not null
  union select issued_lot_id from invoice_credit_splits where invoice_id = p_inv and issued_lot_id is not null
  union select lot_id from credit_package_progress_lots where invoice_id = p_inv $f$;
-- The invoice's lot family (the critic's 6): every lot its records name and
-- each Move's two lots (from the Move's ledger rows), the lots each replaced
-- and every lot reissued from any of them.
create function pg_temp.t471_family(p_inv uuid) returns setof uuid language sql as $f$
  with recursive seed as (
    select x as id from pg_temp.t471_named(p_inv) x
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
create function pg_temp.t471_behind(p_inv uuid) returns setof uuid language sql as $f$
  with recursive c(id, n) as (
    select lot_id, 0 from invoice_benefit_values where invoice_id = p_inv and lot_id is not null
    union select p.id, c.n + 1 from c join customer_credit_lots l on l.id = c.id
            join customer_credit_lots p on p.id = l.reassigned_from_lot_id
             and (p.source_type, p.source_record_id) is not distinct from (l.source_type, l.source_record_id)
           where c.n < 12)
  select distinct id from c $f$;
-- How many lots back a lot's chain goes (reassigned_from_lot_id).
create function pg_temp.t471_depth(p_lot uuid) returns int language sql as $f$
  with recursive c(id, n) as (select p_lot, 0 union all
    select l.reassigned_from_lot_id, c.n + 1 from c join customer_credit_lots l on l.id = c.id
     where l.reassigned_from_lot_id is not null and c.n < 40)
  select max(n) from c $f$;
-- A lot's balance by its ledger rows: credit added (grants, increases,
-- credit returned: the 'reverse' rows that put credit back, as the
-- statement reads them, and 'rental_late_fee'), less credit taken (uses,
-- decreases, real reversals).
create function pg_temp.t471_ledger_balance(p_lot uuid) returns numeric language sql as $f$
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
create function pg_temp.t471_invariants(p_inv uuid) returns text language plpgsql as $f$
declare probs text := ''; l record; root record; v uuid; st text := (select status::text from invoices where id = p_inv);
begin
  for l in select cl.* from customer_credit_lots cl where cl.id in (select pg_temp.t471_family(p_inv)) loop
    if l.remaining_amount > 0 and l.id not in (select pg_temp.t471_named(p_inv)) then
      probs := probs || format(' S$%s on a lot no record names (%s);', l.remaining_amount, (select full_name from customers where id = l.customer_id)); end if;
    if l.id not in (select pg_temp.t471_named(p_inv)) and l.id not in (select pg_temp.t471_behind(p_inv))
       and (exists (select 1 from invoice_line_credit_allocations a where a.lot_id = l.id and a.amount > coalesce(a.reversed_amount, 0))
            or exists (select 1 from special_credit_allocations s where s.lot_id = l.id and s.amount > coalesce(s.reversed_amount, 0))) then
      probs := probs || ' a sale paid from a lot no record names can still be refunded (its credit would stay there);'; end if;
    if pg_temp.t471_ledger_balance(l.id) <> l.remaining_amount then
      probs := probs || format(' lot holds %s, its ledger %s;', l.remaining_amount, pg_temp.t471_ledger_balance(l.id)); end if;
    if pg_temp.t471_depth(l.id) > 12 then probs := probs || format(' chain %s lots deep;', pg_temp.t471_depth(l.id)); end if;
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
  if st = 'refunded' and (select coalesce(sum(remaining_amount), 0) from customer_credit_lots where id in (select pg_temp.t471_family(p_inv))) > 0 then
    probs := probs || format(' refunded, but S$%s of its credit is still held;',
      (select sum(remaining_amount) from customer_credit_lots where id in (select pg_temp.t471_family(p_inv)))); end if;
  return probs;
end $f$;
-- Credit left on the invoice's family once Cancel has run, the Cancel undone
-- (0 when Cancel takes it all back from whoever holds it); null when the
-- invoice cannot be cancelled now, -1 when Cancel is refused.
create function pg_temp.t471_cancel_left(p_inv uuid) returns numeric language plpgsql as $f$
declare v numeric;
begin
  if (select status::text from invoices where id = p_inv) not in ('paid', 'partially_paid', 'unpaid') then return null; end if;
  begin
    perform cancel_invoice_recorded(p_inv, 'T471 probe', gen_random_uuid());
    perform pg_temp.t471_commit();
    v := (select coalesce(sum(remaining_amount), 0) from customer_credit_lots where id in (select pg_temp.t471_family(p_inv)));
    raise exception using errcode = 'P0461', message = v::text;
  exception when sqlstate 'P0461' then return sqlerrm::numeric;
            when others then return -1;
  end;
end $f$;
create function pg_temp.t471_codes(p_inv uuid, p_action text) returns text language plpgsql as $f$
begin
  return (select coalesce(string_agg(o->>'code', ',' order by o->>'code'), '-')
            from jsonb_array_elements(coalesce(invoice_action_plan(p_inv, p_action, '[]')->'overrides_required', '[]')) o);
exception when others then return 'ERR';
end $f$;
create function pg_temp.t471_due(p_inv uuid, p_action text) returns numeric language plpgsql as $f$
begin
  return (invoice_action_plan(p_inv, p_action, '[]')->>case when p_action = 'cancel' then 'refund_due' else 'refund_amount' end)::numeric;
exception when others then return null;
end $f$;
-- The invoice's money: what is owed back (cancel_refund_owed), the Finance
-- panel's refund due, net received and kept for what was used, what a
-- refund by line can still pay back (the refund options' max_refund, every
-- benefit) and Cancel's refund due (the plan's).
create function pg_temp.t471_money(p_inv uuid) returns jsonb language sql as $f$
  select jsonb_build_object('owed', i.cancel_refund_owed,
    'due', (invoice_financial_position(i.id)->>'refund_due')::numeric,
    'net', (invoice_financial_position(i.id)->>'net_received')::numeric,
    'kept', (invoice_financial_position(i.id)->>'kept_for_used')::numeric,
    'by_line', (select coalesce(sum((b->>'max_refund')::numeric), 0)
                  from jsonb_array_elements(invoice_refund_options_before_sessions(i.id)->'benefits') b),
    'plan_due', pg_temp.t471_due(i.id, 'cancel'))
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
create function pg_temp.t471_role(p_pre text, p_r text) returns uuid language plpgsql as $f$
begin
  return coalesce(pg_temp.t471_id(p_pre || '/' || p_r), pg_temp.t471_cust(p_pre || '/' || p_r));
end $f$;
-- One step of a case (one app call, then what its commit does). Null, or
-- the step and the refusal; a refused step changes nothing.
create function pg_temp.t471_step(p_pre text, p_st text) returns text language plpgsql as $f$
declare w text[] := regexp_split_to_array(btrim(p_st), '\s+'); inv uuid := pg_temp.t471_id(p_pre || '/inv'); x uuid; i int; n int;
begin
  case w[1]
  when 'sale' then
    perform pg_temp.t471_put(p_pre || '/inv', pg_temp.t471_sale(pg_temp.t471_role(p_pre, w[2]), string_to_array(w[3], ','), w[4]::numeric));
  when 'saled' then
    perform pg_temp.t471_put(p_pre || '/inv', pg_temp.t471_sale(pg_temp.t471_role(p_pre, w[2]), string_to_array(w[3], ','), null, 2, w[4]::numeric));
  when 'sale2' then
    perform pg_temp.t471_put(p_pre || '/inv2', pg_temp.t471_sale(pg_temp.t471_role(p_pre, w[2]), array['cp']));
  when 'pay' then perform pg_temp.t471_pay(inv);
  when 'back' then
    perform pg_temp.t471_back(inv, w[2]::int, case when w[3] = 'all' then null else w[3]::numeric end,
                              case when w[4] is not null then pg_temp.t471_role(p_pre, w[4]) end);
  when 'move' then
    perform pg_temp.t471_move(inv, w[2]::int, pg_temp.t471_role(p_pre, w[3]),
      case when w[4] in ('bonus', 'voucher') then w[4] else 'paid' end,
      case when 'store2' = any (w) then 'store2' end);
  when 'cancel' then perform cancel_invoice_recorded(inv, 'T471 cancel', gen_random_uuid());
  when 'reopen' then perform reopen_invoice(inv, 'T471 reopen', gen_random_uuid());
  when 'wait' then
    perform cancel_invoice_recorded(inv, 'T471 cancel', gen_random_uuid());
    for i in 1 .. (select count(*)::int from invoice_items where invoice_id = inv) loop
      perform pg_temp.t471_back(inv, i);
    end loop;
    perform reopen_invoice(inv, 'T471 reopen', gen_random_uuid());
  when 'refundall' then perform pg_temp.t471_guided(inv, 'refund_full');
  when 'change' then
    perform pg_temp.t471_change(inv, pg_temp.t471_role(p_pre, w[2]), case when 'keep' = any (w) then 'keep' else 'transfer' end,
                                case when 'store2' = any (w) then 'store2' end);
  when 'merge' then perform pg_temp.t471_merge(pg_temp.t471_role(p_pre, w[2]), pg_temp.t471_role(p_pre, w[3]));
  when 'spend' then
    n := (select count(*) from t471 where k ~ ('^' || p_pre || '/S[0-9]+$')) + 1;
    perform pg_temp.t471_put(p_pre || '/S' || n,
      pg_temp.t471_spend(pg_temp.t471_role(p_pre, w[2]), case when w[3] ~ '^[0-9]+$' then w[3]::int else 1 end,
        case when 'svc5' = any (w) then 'svc5' else 'svc' end, case when 'bwallet' = any (w) then 'bwallet' else 'wallet' end));
  when 'unspend' then perform pg_temp.t471_unspend(pg_temp.t471_id(p_pre || '/' || w[2]));
  when 'fix' then perform pg_temp.t471_fix(pg_temp.t471_id(p_pre || '/' || w[2]), w[3]);
  when 'delete' then
    x := pg_temp.t471_role(p_pre, w[2]);
    perform delete_customer(x, (select full_name from customers where id = x), 'T471 delete');
  when 'special' then
    n := (select count(*) from t471 where k ~ ('^' || p_pre || '/D[0-9]+$')) + 1; x := gen_random_uuid();
    perform pg_temp.t471_put(p_pre || '/D' || n, x);
    perform pg_temp.t471_put(p_pre || '/D' || n || '/kind:' || w[3], null);
    perform pg_temp.t471_special(pg_temp.t471_role(p_pre, w[2]), w[3], x, w[4]::numeric);
  when 'unspecial' then
    perform refund_special_credit((select split_part(k, 'kind:', 2) from t471 where k like p_pre || '/' || w[2] || '/kind:%'),
                                  pg_temp.t471_id(p_pre || '/' || w[2]));
  when 'reverse' then
    if w[2] = 'closed' then
      -- the released lot a Cancel's write-off closed, once a refund opened it again
      perform reverse_credit_lot(pg_temp.t471_closed_lot(inv), 'T471 reversal');
    else
      x := pg_temp.t471_role(p_pre, w[2]);
      perform reverse_credit_lot((select id from customer_credit_lots where customer_id = x and remaining_amount > 0
                                   order by remaining_amount desc, id limit 1), 'T471 reversal');
    end if;
  when 'guidedcancel' then perform pg_temp.t471_guided(inv, 'cancel');
  when 'guidedkeep' then perform pg_temp.t471_guided(inv, 'cancel', false);
  when 'backo' then
    x := pg_temp.t471_line(inv, w[2]::int);
    perform refund_invoice_recorded(inv, jsonb_build_array(jsonb_build_object('invoice_item_id', x,
        'amount', invoice_discounted_line_value(x),
        'benefits', jsonb_build_array(jsonb_build_object('benefit_id', pg_temp.t471_own(inv), 'amount', w[3]::numeric)),
        'override', jsonb_build_object('code', 'larger_refund', 'reason', 'T471 larger refund', 'amount', invoice_discounted_line_value(x)))),
      pg_temp.t471_sources(inv, invoice_net_received(inv)), '[]'::jsonb, 'T471 larger refund', gen_random_uuid());
  when 'refundpaid' then
    perform refund_invoice_recorded(inv, jsonb_build_array(jsonb_build_object('amount',
        coalesce(nullif((invoice_financial_position(inv)->>'refund_due')::numeric, 0), (invoice_action_plan(inv, 'cancel', '[]')->>'refund_due')::numeric))),
      pg_temp.t471_sources(inv, coalesce(nullif((invoice_financial_position(inv)->>'refund_due')::numeric, 0), (invoice_action_plan(inv, 'cancel', '[]')->>'refund_due')::numeric)),
      '[]'::jsonb, 'T471 refund paid', gen_random_uuid());
  when 'backx' then
    x := pg_temp.t471_line(inv, w[2]::int);
    perform refund_invoice_recorded(inv, jsonb_build_array(jsonb_build_object('invoice_item_id', x,
        'amount', invoice_discounted_line_value(x) - coalesce((select sum((e->>'amount')::numeric) from invoice_refunds r,
             jsonb_array_elements(coalesce(r.outcome->'lines', '[]')) e where r.invoice_id = inv and e->>'invoice_item_id' = x::text), 0),
        'benefits', (select jsonb_agg(jsonb_build_object('benefit_id', b->>'id', 'amount', (b->>'max_refund')::numeric))
                       from jsonb_array_elements(invoice_refund_options_before_sessions(inv)->'benefits') b
                      where b->>'invoice_item_id' = x::text and (b->>'max_refund')::numeric > 0),
        'override', jsonb_build_object('code', 'larger_refund', 'reason', 'T471 larger refund',
          'amount', invoice_discounted_line_value(x) - coalesce((select sum((e->>'amount')::numeric) from invoice_refunds r,
             jsonb_array_elements(coalesce(r.outcome->'lines', '[]')) e where r.invoice_id = inv and e->>'invoice_item_id' = x::text), 0)))),
      pg_temp.t471_sources(inv, invoice_net_received(inv)), '[]'::jsonb, 'T471 larger refund', gen_random_uuid());
  when 'legacy' then
    update invoices set status = w[2]::invoice_status where id = inv;
  when 'repair' then perform repair_credit_package_progress_lots();
  else raise exception 'T471: unknown step %', p_st;
  end case;
  perform pg_temp.t471_commit();
  return null;
exception when others then
  return btrim(p_st) || ': ' || sqlerrm;
end $f$;
-- What a case ends with: the invoice's status and money, who holds what
-- (credit, '/n' held vouchers), the plans' codes and refund due (Cancel's
-- refund due; Refund in full's amount), the refusal that stopped it, what is
-- wrong with its credit, and the credit Cancel would leave behind.
create function pg_temp.t471_outcome(p_pre text, p_err text) returns jsonb language sql as $f$
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
              from t471 t where t.k like p_pre || '/%' and split_part(t.k, '/', 4) = ''
                and split_part(t.k, '/', 3) !~ '^(inv|inv2|S[0-9]+|D[0-9]+|err)$'),
    'cancel', pg_temp.t471_codes(i.id, 'cancel'),
    'due', pg_temp.t471_due(i.id, 'cancel'),
    'refund', pg_temp.t471_codes(i.id, 'refund_full'),
    'rdue', pg_temp.t471_due(i.id, 'refund_full'),
    'error', p_err,
    'invariants', pg_temp.t471_invariants(i.id),
    'cancel_left', pg_temp.t471_cancel_left(i.id))
    from (select pg_temp.t471_id(p_pre || '/inv') as id) i $f$;
-- A case's steps p_from to p_to (all by default), stopping at a refusal;
-- with p_to null, its outcome (kept in t471_res under p_phase).
create temp table t471_err(pre text primary key, err text);
create function pg_temp.t471_run(p_phase text, p_case text, p_steps text, p_from int default 1, p_to int default null)
  returns jsonb language plpgsql as $f$
declare v_pre text := p_phase || '/' || p_case; st text[] := string_to_array(p_steps, ';'); i int; v_err text; v_out jsonb;
begin
  v_err := (select e.err from t471_err e where e.pre = v_pre);
  for i in p_from .. least(coalesce(p_to, cardinality(st)), cardinality(st)) loop
    exit when v_err is not null;
    continue when btrim(st[i]) = '';
    v_err := pg_temp.t471_step(v_pre, st[i]);
  end loop;
  insert into t471_err values (v_pre, v_err) on conflict (pre) do update set err = excluded.err;
  if p_to is not null then return null; end if;
  v_out := pg_temp.t471_outcome(v_pre, v_err);
  insert into t471_res values (p_phase, p_case, v_out) on conflict (phase, k) do update set v = excluded.v;
  return v_out;
end $f$;

-- Whether an outcome has what is expected: each key equal ('holds' as a
-- containment of who holds what), a key ending in '~' as a LIKE pattern of
-- that key's text.
create function pg_temp.t471_meets(p_out jsonb, p_exp jsonb) returns boolean language sql as $f$
  select coalesce(bool_and(case
           when e.key like '%~' then coalesce(p_out->>left(e.key, -1), '') like (e.value #>> '{}')
           when e.key = 'holds' then coalesce(p_out->'holds', '{}') @> e.value
           when jsonb_typeof(e.value) = 'number' then coalesce((p_out->>e.key)::numeric = (e.value #>> '{}')::numeric, false)
           else (p_out->e.key) is not distinct from e.value end), true)
    from jsonb_each(p_exp) e $f$;
-- What differs between an outcome and what is expected (for the FAIL line).
create function pg_temp.t471_diff(p_out jsonb, p_exp jsonb) returns text language sql as $f$
  select string_agg(e.key || ': wanted ' || e.value::text || ', got ' || coalesce(p_out->left(e.key, case when e.key like '%~' then -1 else 1000 end), 'null')::text, '; ')
    from jsonb_each(p_exp) e where not pg_temp.t471_meets(p_out, jsonb_build_object(e.key, e.value)) $f$;

-- ── 471's own readings ──────────────────────────────────────────────────────
-- The held-back reason (470's, which 471 writes too), and its rows on a lot.
create function pg_temp.t471_held(p_lot uuid) returns numeric language sql as $f$
  select coalesce(sum(e.amount), 0) from customer_credit_ledger e
   where e.lot_id = p_lot and e.entry_type = 'adjust_decrease' and e.source_type = 'invoice_cancel_benefit'
     and e.reason = 'Held back by the invoice''s cancellation for whoever holds its benefits now' $f$;
-- (B) what is held back on a lot of credit released before full payment
-- (Cancel's write-off's kind of row, 471's reason).
create function pg_temp.t471_held_rel(p_lot uuid) returns numeric language sql as $f$
  select coalesce(sum(e.amount), 0) from customer_credit_ledger e
   where e.lot_id = p_lot and e.entry_type = 'adjust_decrease' and e.source_type in ('invoice_cancel_released_credit', 'invoice_refund_released_credit')
     and e.reason = 'Held back by the invoice''s cancellation: credit released before it was paid in full' $f$;
-- The release record of an invoice (its first; the cases have one) and its lot.
create function pg_temp.t471_rel_lot(p_inv uuid) returns uuid language sql as $f$
  select lot_id from credit_package_progress_lots where invoice_id = p_inv order by created_at, lot_id limit 1 $f$;
-- The lot of an invoice's release record that a Cancel's write-off closed
-- (locked; after a reopening the release record has a second, open lot).
create function pg_temp.t471_closed_lot(p_inv uuid) returns uuid language sql as $f$
  select pl.lot_id from credit_package_progress_lots pl join customer_credit_lots l on l.id = pl.lot_id
   where pl.invoice_id = p_inv and l.is_locked order by pl.lot_id limit 1 $f$;
create function pg_temp.t471_held_n(p_lot uuid) returns int language sql as $f$
  select count(*)::int from customer_credit_ledger e
   where e.lot_id = p_lot and e.entry_type = 'adjust_decrease' and e.source_type = 'invoice_cancel_benefit'
     and e.reason = 'Held back by the invoice''s cancellation for whoever holds its benefits now' $f$;
-- The package's own benefit row (the one an Owner did not move in), and the
-- lot it names.
create function pg_temp.t471_own(p_inv uuid) returns uuid language sql as $f$
  select bv.id from invoice_benefit_values bv
   where bv.invoice_id = p_inv and bv.lot_id is not null
     and not exists (select 1 from invoice_benefit_transfers t where t.replacement_benefit_id = bv.id)
   order by bv.created_at, bv.id limit 1 $f$;
create function pg_temp.t471_own_lot(p_inv uuid) returns uuid language sql as $f$
  select lot_id from invoice_benefit_values where id = pg_temp.t471_own(p_inv) $f$;
-- Unapplied queue rows of an invoice on a lot (count, sum, requests).
create function pg_temp.t471_waiting(p_inv uuid, p_lot uuid) returns text language sql as $f$
  select count(*) || '/' || coalesce(sum(q.amount), 0) || '/' || count(distinct q.request_id)
    from invoice_reopen_benefits q join customer_credit_ledger e on e.id = q.source_ledger_id
   where q.invoice_id = p_inv and q.applied_at is null and e.lot_id = p_lot $f$;
-- The triggers on invoices (their definitions, by name; search_path public,
-- as the migration reads them).
create function pg_temp.t471_inv_triggers() returns text language plpgsql as $f$
declare v text; p text := current_setting('search_path');
begin
  perform set_config('search_path', 'public', true);
  select md5(string_agg(pg_get_triggerdef(oid), E'\n' order by tgname)) || ' ' || count(*) into v
    from pg_trigger where tgrelid = 'public.invoices'::regclass and not tgisinternal;
  perform set_config('search_path', p, true);
  return v;
end $f$;

-- The cases: (k, kind, steps, what 471 gives). kind: 'fixed' (before 471 it
-- ends otherwise: the fault is reproduced first), 'control' (the same with
-- and without 471, every key of the outcome), 'known' (a NOT COVERED item,
-- checked as it is: the same with and without 471, as a control). Every
-- case also checks the invariants and that Cancel takes everything back
-- from whoever holds it.
create temp table t471_cases(k text primary key, kind text not null, steps text not null, expect jsonb not null, ord serial);
insert into t471_cases(k, kind, steps, expect) values
-- 470's KNOWN K (1): the guided Cancel with "Record refund paid", S2 refunded.
('G2', 'fixed', 'sale A cp; spend A; spend A; move 1 F; unspend S1; guidedcancel; unspend S2',
  '{"holds":{"A":"0.00","F":"0.00"},"status":"cancelled","net":20,"owed":20,"fdue":20,"held":20,"error":null}'),
('G3', 'fixed', 'sale A cp; spend A; spend A; move 1 F; unspend S1; guidedcancel; unspend S2; back 1 all',
  '{"holds":{"A":"0.00","F":"0.00"},"status":"cancelled","net":0,"owed":0,"fdue":0,"held":0,"error":null}'),
('G2s', 'fixed', 'sale A cp; spend A; spend A; move 1 F; unspend S1; guidedcancel; unspend S2; spend A',
  '{"holds":{"A":"0.00","F":"0.00"},"status":"cancelled","net":20,"owed":20,"held":20,"error~":"spend A: Only 0 of the requested 20.00 could be funded by eligible credit%"}'),
('GN', 'fixed', 'sale A cp; spend A; spend A; guidedcancel; unspend S2',
  '{"holds":{"A":"0.00"},"status":"cancelled","net":40,"owed":20,"fdue":20,"held":20,"error":null}'),
('GNb', 'fixed', 'sale A cp; spend A; spend A; guidedcancel; unspend S2; back 1 all',
  '{"holds":{"A":"0.00"},"status":"cancelled","net":20,"owed":0,"fdue":0,"held":0,"error":null}'),
('P2s', 'fixed', 'sale A cp; spend A; spend A; spend A; guidedcancel; unspend S2; unspend S3; back 1 all',
  '{"holds":{"A":"0.00"},"status":"cancelled","net":20,"owed":0,"fdue":0,"held":0,"error":null}'),
-- 470's KNOWN K (1): refunded in full with an override, then S1 refunded
-- (ends as 470's RX1: held back, owed to nobody).
('RX0', 'fixed', 'sale A cp; spend A; backx 1; unspend S1',
  '{"holds":{"A":"0.00"},"status":"refunded","net":0,"held":20,"error":null}'),
-- A plain Cancel: S1 refunded, A tries to spend it.
('PCs', 'fixed', 'sale A cp; spend A; spend A; cancel; unspend S1; spend A',
  '{"holds":{"A":"0.00"},"status":"cancelled","net":100,"held":80,"error~":"spend A: Only 0 of the requested 20.00 could be funded by eligible credit%"}'),
-- Where S$20 of credit is worth less than S$20 (a third session kept for,
-- as spent): the Bonus package (S$90.91 for 100 credit: S$18.18), the
-- Premium Bundle (S$70 for 100: S$14.00), it S$7 off (S$64.79 for 95: S$13.64).
('PCx', 'fixed', 'sale A cpb; spend A; spend A; spend A; guidedcancel; unspend S2',
  '{"holds":{"A":"0.00"},"status":"cancelled","net":54.55,"owed":18.18,"fdue":18.18,"held":20,"error":null}'),
('PCxb', 'fixed', 'sale A cpb; spend A; spend A; spend A; guidedcancel; unspend S2; back 1 all',
  '{"holds":{"A":"0.00"},"status":"cancelled","net":36.37,"owed":0,"fdue":0,"held":0,"error":null}'),
('PCv', 'fixed', 'sale A pbv; spend A 1 bwallet; spend A 1 bwallet; spend A 1 bwallet; guidedcancel; unspend S2',
  '{"holds":{"A":"0.00"},"status":"cancelled","net":42,"owed":14,"fdue":14,"held":20,"error":null}'),
('PCvb', 'fixed', 'sale A pbv; spend A 1 bwallet; spend A 1 bwallet; spend A 1 bwallet; guidedcancel; unspend S2; back 1 all',
  '{"holds":{"A":"0.00"},"status":"cancelled","net":28,"owed":0,"fdue":0,"held":0,"error":null}'),
('PCd', 'fixed', 'saled A pbv 7; spend A 1 bwallet; spend A 1 bwallet; spend A 1 bwallet; guidedcancel; unspend S2',
  '{"holds":{"A":"0.00"},"status":"cancelled","net":40.92,"owed":13.64,"fdue":13.64,"held":20,"error":null}'),
('PCdb', 'fixed', 'saled A pbv 7; spend A 1 bwallet; spend A 1 bwallet; spend A 1 bwallet; guidedcancel; unspend S2; back 1 all',
  '{"holds":{"A":"0.00"},"status":"cancelled","net":27.28,"owed":0,"fdue":0,"held":0,"error":null}'),
-- Correct payment of S2 while cancelled instead of its refund (to cash; S$5 less).
('PFc', 'fixed', 'sale A cp; spend A; spend A; guidedcancel; fix S2 cash',
  '{"holds":{"A":"0.00"},"status":"cancelled","net":40,"owed":20,"fdue":20,"held":20,"error":null}'),
('PFcb', 'fixed', 'sale A cp; spend A; spend A; guidedcancel; fix S2 cash; back 1 all',
  '{"holds":{"A":"0.00"},"status":"cancelled","net":20,"owed":0,"fdue":0,"held":0,"error":null}'),
('PFa', 'fixed', 'sale A cp; spend A; spend A; guidedcancel; fix S2 amount',
  '{"holds":{"A":"0.00"},"status":"cancelled","net":40,"owed":5,"fdue":5,"held":5,"error":null}'),
('PFab', 'fixed', 'sale A cp; spend A; spend A; guidedcancel; fix S2 amount; back 1 all',
  '{"holds":{"A":"0.00"},"status":"cancelled","net":35,"owed":0,"fdue":0,"held":0,"error":null}'),
-- While a reopening waits: S2 refunded, A tries to spend it.
('PWs', 'fixed', 'sale A cp; spend A; spend A; cancel; back 1 60; reopen; unspend S2; spend A',
  '{"holds":{"A":"0.00"},"status":"partially_paid","net":40,"held":20,"error~":"spend A: Only 0 of the requested 20.00 could be funded by eligible credit%"}'),
-- A 'transfer' customer change of the cancelled package after the hold.
('PCh', 'fixed', 'sale A cp; spend A; spend A; move 1 F; unspend S1; cancel; unspend S2; change B; reopen; pay',
  '{"holds":{"A":"0.00","B":"40.00","F":"60.00"},"status":"paid","net":100,"held":0,"cancel":"-","due":100,"error":null}'),
('PChg', 'fixed', 'sale A cp; spend A; spend A; move 1 F; unspend S1; guidedcancel; unspend S2; change B; back 1 all',
  '{"holds":{"A":"0.00","B":"0.00","F":"0.00"},"status":"cancelled","net":0,"owed":0,"held":0,"error":null}'),
-- A merge of the buyer after the hold: refused as before (445's NOT
-- COVERED 1); the buyer merged before the sessions (the kept record's lot).
('PM', 'fixed', 'sale A cp; spend A; spend A; move 1 F; unspend S1; cancel; unspend S2; merge K A',
  '{"holds":{"A":"0.00","F":"0.00"},"status":"cancelled","net":100,"held":100,"error~":"merge K A: Credit allocations cannot be changed once recorded%"}'),
('PMg', 'fixed', 'sale A cp; spend A; spend A; move 1 F; unspend S1; guidedcancel; unspend S2; merge K A',
  '{"holds":{"A":"0.00","F":"0.00"},"status":"cancelled","net":20,"owed":20,"held":20,"error~":"merge K A: Credit allocations cannot be changed once recorded%"}'),
('PMb', 'fixed', 'sale A cp; merge K A; spend K; spend K; guidedcancel; unspend S2',
  '{"holds":{"A":"0.00","K":"0.00"},"status":"cancelled","net":40,"owed":20,"fdue":20,"held":20,"error":null}'),
('PMbb', 'fixed', 'sale A cp; merge K A; spend K; spend K; guidedcancel; unspend S2; back 1 all',
  '{"holds":{"A":"0.00","K":"0.00"},"status":"cancelled","net":20,"owed":0,"fdue":0,"held":0,"error":null}'),
-- Cancel again after the hold: nothing more.
('PCa', 'fixed', 'sale A cp; spend A; spend A; guidedcancel; unspend S2; cancel',
  '{"holds":{"A":"0.00"},"status":"cancelled","net":40,"owed":20,"fdue":20,"held":20,"error":null}'),
-- A special document's credit given back instead; a 13-line sale refunded
-- at once; five sessions refunded one by one.
('SSp', 'fixed', 'sale A cp; special A special_sale 20; spend A; guidedcancel; unspecial D1',
  '{"holds":{"A":"0.00"},"status":"cancelled","net":40,"owed":20,"fdue":20,"held":20,"error":null}'),
('SSpb', 'fixed', 'sale A cp; special A special_sale 20; spend A; guidedcancel; unspecial D1; back 1 all',
  '{"holds":{"A":"0.00"},"status":"cancelled","net":20,"owed":0,"fdue":0,"held":0,"error":null}'),
('L13p', 'fixed', 'sale A cp; spend A 13 svc5; guidedcancel; unspend S1',
  '{"holds":{"A":"0.00"},"status":"cancelled","net":65,"owed":65,"fdue":65,"held":65,"error":null}'),
('L13pb', 'fixed', 'sale A cp; spend A 13 svc5; guidedcancel; unspend S1; back 1 all',
  '{"holds":{"A":"0.00"},"status":"cancelled","net":0,"owed":0,"fdue":0,"held":0,"error":null}'),
('CH5p', 'fixed', 'sale A cp; spend A 1 svc5; spend A 1 svc5; spend A 1 svc5; spend A 1 svc5; spend A 1 svc5; spend A 1 svc5; guidedcancel; unspend S1; unspend S2; unspend S3; unspend S4; unspend S5; back 1 all',
  '{"holds":{"A":"0.00"},"status":"cancelled","net":5,"owed":0,"fdue":0,"held":0,"error":null}'),
-- The buyer deleted while cancelled (no live record: held where it is).
('PDel', 'fixed', 'sale A cp; spend A; spend A; cancel; delete A; unspend S2',
  '{"holds":{"A":"0.00"},"status":"cancelled","net":100,"held":80,"error":null}'),
-- Controls: the same with and without 471.
('PC', 'control', 'sale A cp; spend A; spend A; cancel; unspend S1; back 1 all',
  '{"holds":{"A":"0.00"},"status":"cancelled","net":20,"held":0,"error":null}'),
('PW', 'control', 'sale A cp; spend A; spend A; cancel; back 1 60; reopen; unspend S2; pay',
  '{"holds":{"A":"80.00"},"status":"paid","net":100,"held":0,"error":null}'),
('PWb', 'control', 'sale A cp; spend A; spend A; cancel; back 1 60; reopen; unspend S2; back 1 all; pay',
  '{"holds":{"A":"60.00"},"status":"paid","net":80,"held":0,"error":null}'),
('PWc', 'control', 'sale A cp; spend A; spend A; cancel; back 1 60; reopen; unspend S2; cancel; back 1 all',
  '{"holds":{"A":"0.00"},"status":"cancelled","net":20,"held":0,"error":null}'),
('PWfa', 'control', 'sale A cp; spend A; spend A; cancel; back 1 60; reopen; fix S2 amount; back 1 all; pay',
  '{"holds":{"A":"60.00"},"status":"paid","net":95,"held":0,"error":null}'),
('PWg', 'control', 'sale A cp; spend A; spend A; cancel; back 1 60; reopen; unspend S2; refundall',
  '{"holds":{"A":"0.00"},"status":"partially_paid","net":20,"error":null}'),
('PWgc', 'control', 'sale A cp; spend A; spend A; cancel; back 1 60; reopen; unspend S2; guidedcancel',
  '{"holds":{"A":"0.00"},"status":"cancelled","net":20,"owed":0,"error":null}'),
('PR', 'control', 'sale A cp; spend A; spend A; cancel; unspend S2; reopen',
  '{"holds":{"A":"80.00"},"status":"paid","net":100,"held":0,"due":80,"error":null}'),
('PRg', 'control', 'sale A cp; spend A; spend A; guidedcancel; unspend S2; reopen; pay',
  '{"holds":{"A":"80.00"},"status":"paid","net":100,"held":0,"error":null}'),
('PRx', 'control', 'sale A cp; spend A; backx 1; unspend S1; reopen; pay',
  '{"holds":{"A":"100.00"},"status":"paid","net":100,"held":0,"error":null}'),
('PB', 'control', 'sale A cp; spend A; spend A; unspend S2; guidedcancel',
  '{"holds":{"A":"0.00"},"status":"cancelled","net":20,"owed":0,"held":0,"error":null}'),
('PBr', 'control', 'sale A cp; spend A; spend A; unspend S2; guidedcancel; back 1 all',
  '{"holds":{"A":"0.00"},"status":"cancelled","net":20,"error~":"back 1 all: T471: nothing to refund on that line%"}'),
('PP', 'control', 'sale A cp; spend A; unspend S1',
  '{"holds":{"A":"100.00"},"status":"paid","net":100,"held":0,"error":null}'),
('PPr', 'control', 'sale A cp; spend A; spend A; refundall; unspend S2',
  '{"holds":{"A":"20.00"},"status":"paid","net":40,"held":0,"error":null}'),
('PPf', 'control', 'sale A cp; spend A; fix S1 amount',
  '{"holds":{"A":"85.00"},"status":"paid","net":100,"held":0,"error":null}'),
('PRF', 'control', 'sale A cp; spend A; spend A; refundall; unspend S2; refundall',
  '{"holds":{"A":"0.00"},"status":"paid","net":20,"error":null}'),
('PFd', 'control', 'sale A cp; spend A; spend A; guidedcancel; fix S2 date',
  '{"holds":{"A":"0.00"},"status":"cancelled","net":40,"owed":0,"held":0,"error":null}'),
('LGp', 'control', 'sale A cp; spend A; spend A; legacy cancellation_requested; unspend S2; legacy paid',
  '{"holds":{"A":"80.00"},"status":"paid","net":100,"held":0,"error":null}'),
('PDelb', 'control', 'sale A cp; spend A; spend A; cancel; delete A; unspend S2; back 1 all',
  '{"holds":{"A":"0.00"},"status":"cancelled","net":20,"error":null}'),
('C0', 'control', 'sale A cp; spend A; spend A; move 1 F; unspend S1; cancel; unspend S2; back 1 all',
  '{"holds":{"A":"0.00","F":"0.00"},"status":"cancelled","net":0,"error":null}'),
('C0r', 'control', 'sale A cp; spend A; spend A; move 1 F; unspend S1; cancel; unspend S2; reopen; pay',
  '{"holds":{"A":"40.00","F":"60.00"},"status":"paid","net":100,"error":null}'),
('C2', 'control', 'sale A cp; spend A; cancel; unspend S1; back 1 all',
  '{"holds":{"A":"0.00"},"status":"cancelled","net":0,"error":null}'),
-- Paid in part (B): S$40 of S$100 paid, so S$40 of its credit released
-- before full payment; a S$20 session paid from it. Held back as Cancel's
-- write-off takes it: A holds nothing, and once nothing released is spent
-- the money held can be recorded as paid back.
('PT1', 'fixed', 'sale A cp 40; spend A; cancel; unspend S1',
  '{"holds":{"A":"0.00"},"status":"cancelled","net":40,"fdue":40,"held":0,"error":null}'),
('PT1r', 'fixed', 'sale A cp 40; spend A; cancel; unspend S1; refundpaid',
  '{"holds":{"A":"0.00"},"status":"cancelled","net":0,"fdue":0,"error":null}'),
('PTs', 'fixed', 'sale A cp 40; spend A; cancel; unspend S1; spend A',
  '{"holds":{"A":"0.00"},"status":"cancelled","net":40,"error~":"spend A: Only 0 of the requested 20.00 could be funded by eligible credit%"}'),
('PT2', 'fixed', 'sale A cp 40; spend A; spend A; cancel; unspend S1; unspend S2; refundpaid',
  '{"holds":{"A":"0.00"},"status":"cancelled","net":0,"error":null}'),
('PT2u', 'fixed', 'sale A cp 40; spend A; spend A; cancel; unspend S1; refundpaid',
  '{"holds":{"A":"0.00"},"status":"cancelled","net":40,"error~":"refundpaid: Part of what % sold has been used (credit spent)%"}'),
('PTg', 'fixed', 'sale A cp 40; spend A; guidedkeep; unspend S1',
  '{"holds":{"A":"0.00"},"status":"cancelled","net":40,"owed":20,"fdue":20,"error":null}'),
('PTgr', 'fixed', 'sale A cp 40; spend A; guidedkeep; unspend S1; refundpaid',
  '{"holds":{"A":"0.00"},"status":"cancelled","net":20,"owed":0,"fdue":0,"error":null}'),
('PTf', 'fixed', 'sale A cp 40; spend A; spend A; cancel; fix S2 cash',
  '{"holds":{"A":"0.00"},"status":"cancelled","net":40,"error":null}'),
('PTfa', 'fixed', 'sale A cp 40; spend A; spend A; cancel; fix S2 amount',
  '{"holds":{"A":"0.00"},"status":"cancelled","net":40,"error":null}'),
('PTv', 'fixed', 'sale A pbv 40; spend A 1 bwallet; cancel; unspend S1; refundpaid',
  '{"holds":{"A":"0.00"},"status":"cancelled","net":0,"error":null}'),
('PTch', 'fixed', 'sale A cp 40; spend A; cancel; unspend S1; change B',
  '{"holds":{"A":"0.00","B":"0.00"},"status":"cancelled","net":40,"error":null}'),
('PTm', 'fixed', 'sale A cp 40; spend A; cancel; unspend S1; merge K A',
  '{"holds":{"A":"0.00"},"status":"cancelled","net":40,"error~":"merge K A: Credit allocations cannot be changed once recorded%"}'),
('PTmb', 'fixed', 'sale A cp 40; merge K A; spend K; cancel; unspend S1; refundpaid',
  '{"holds":{"A":"0.00","K":"0.00"},"status":"cancelled","net":0,"error":null}'),
('PTcb', 'fixed', 'sale A cp 40; change B; spend B; cancel; unspend S1; refundpaid',
  '{"holds":{"A":"0.00","B":"0.00"},"status":"cancelled","net":0,"error":null}'),
('PTsp', 'fixed', 'sale A cp 40; special A special_sale 20; cancel; unspecial D1; refundpaid',
  '{"holds":{"A":"0.00"},"status":"cancelled","net":0,"error":null}'),
('PTd', 'fixed', 'sale A cp 40; spend A; cancel; delete A; unspend S1',
  '{"holds":{"A":"0.00"},"status":"cancelled","net":40,"error":null}'),
-- Cancel again after the hold: nothing more (before 471 it left A S$20).
('PTca', 'fixed', 'sale A cp 40; spend A; cancel; unspend S1; cancel',
  '{"holds":{"A":"0.00"},"status":"cancelled","net":40,"error":null}'),
-- Paid in part, the controls: S1 refunded before the Cancel; reopened after
-- the hold, or before S1's refund (nothing held while open), and cancelled
-- again; not cancelled.
('PTB', 'control', 'sale A cp 40; spend A; unspend S1; cancel; refundpaid',
  '{"holds":{"A":"0.00"},"status":"cancelled","net":0,"error":null}'),
('PTr', 'control', 'sale A cp 40; spend A; cancel; unspend S1; reopen; pay',
  '{"holds":{"A":"100.00"},"status":"paid","net":100,"error":null}'),
('PTr2', 'control', 'sale A cp 40; spend A; cancel; reopen; unspend S1',
  '{"holds":{"A":"40.00"},"status":"partially_paid","net":40,"error":null}'),
('PTrc', 'control', 'sale A cp 40; spend A; cancel; unspend S1; reopen; cancel; refundpaid',
  '{"holds":{"A":"0.00"},"status":"cancelled","net":0,"error":null}'),
('PTp', 'control', 'sale A cp 40; spend A; unspend S1',
  '{"holds":{"A":"40.00"},"status":"partially_paid","net":40,"error":null}'),
('PTpf', 'control', 'sale A cp 40; spend A; fix S1 amount',
  '{"holds":{"A":"25.00"},"status":"partially_paid","net":40,"error":null}'),
-- Paid in part, cancelled, reopened and paid in full: a benefit row names
-- the released lot the first Cancel's write-off closed ('reversed',
-- locked); a refund or correction of a session paid from it opens it again
-- ('active', still locked). Held back where it is while cancelled, refunded
-- or waiting; it follows a 'transfer' change while paid.
('PTRc', 'fixed', 'sale A cp 40; spend A; cancel; reopen; pay; cancel; unspend S1',
  '{"holds":{"A":"0.00"},"status":"cancelled","net":100,"held":100,"error":null}'),
('PTRcs', 'fixed', 'sale A cp 40; spend A; cancel; reopen; pay; cancel; unspend S1; spend A',
  '{"holds":{"A":"0.00"},"status":"cancelled","net":100,"held":100,"error~":"spend A: Only 0 of the requested 20.00 could be funded by eligible credit%"}'),
('PTRa', 'fixed', 'sale A cp 40; spend A; cancel; reopen; pay; cancel; unspend S1; cancel',
  '{"holds":{"A":"0.00"},"status":"cancelled","net":100,"held":100,"error":null}'),
('PTRg', 'fixed', 'sale A cp 40; spend A; cancel; reopen; pay; guidedcancel; unspend S1',
  '{"holds":{"A":"0.00"},"status":"cancelled","net":20,"owed":20,"fdue":20,"held":20,"error":null}'),
('PTRgb', 'fixed', 'sale A cp 40; spend A; cancel; reopen; pay; guidedcancel; unspend S1; back 1 all',
  '{"holds":{"A":"0.00"},"status":"cancelled","net":0,"owed":0,"fdue":0,"held":0,"error":null}'),
('PTRgs', 'fixed', 'sale A cp 40; spend A; cancel; reopen; pay; guidedcancel; unspend S1; spend A',
  '{"holds":{"A":"0.00"},"status":"cancelled","net":20,"owed":20,"held":20,"error~":"spend A: Only 0 of the requested 20.00 could be funded by eligible credit%"}'),
('PTRx', 'fixed', 'sale A cp 40; spend A; cancel; reopen; pay; backx 1; unspend S1',
  '{"holds":{"A":"0.00"},"status":"refunded","net":0,"held":20,"error":null}'),
('PTRw', 'fixed', 'sale A cp 40; spend A; spend A; cancel; reopen; pay; cancel; back 1 20; reopen; unspend S1; spend A',
  '{"holds":{"A":"0.00"},"status":"partially_paid","net":80,"held":60,"error~":"spend A: Only 0 of the requested 20.00 could be funded by eligible credit%"}'),
('PTRf', 'fixed', 'sale A cp 40; spend A; spend A; cancel; reopen; pay; guidedcancel; fix S2 cash',
  '{"holds":{"A":"0.00"},"status":"cancelled","net":40,"owed":20,"fdue":20,"held":20,"error":null}'),
('PTRfb', 'fixed', 'sale A cp 40; spend A; spend A; cancel; reopen; pay; guidedcancel; fix S2 cash; back 1 all',
  '{"holds":{"A":"0.00"},"status":"cancelled","net":20,"owed":0,"fdue":0,"held":0,"error":null}'),
('PTRv', 'fixed', 'sale A pbv 40; spend A 1 bwallet; cancel; reopen; pay; guidedcancel; unspend S1',
  '{"holds":{"A":"0.00"},"status":"cancelled","net":14,"owed":14,"fdue":14,"held":20,"error":null}'),
('PTRvb', 'fixed', 'sale A pbv 40; spend A 1 bwallet; cancel; reopen; pay; guidedcancel; unspend S1; back 1 all',
  '{"holds":{"A":"0.00"},"status":"cancelled","net":0,"owed":0,"fdue":0,"held":0,"error":null}'),
('PTRh', 'fixed', 'sale A cp 40; spend A; cancel; reopen; pay; change B; cancel; unspend S1',
  '{"holds":{"A":"0.00","B":"0.00"},"status":"cancelled","net":100,"held":100,"error":null}'),
('PTRhp', 'fixed', 'sale A cp 40; spend A; cancel; reopen; pay; change B; unspend S1',
  '{"holds":{"A":"0.00","B":"100.00"},"status":"paid","net":100,"held":0,"error":null}'),
('PTRp', 'control', 'sale A cp 40; spend A; cancel; reopen; pay; unspend S1',
  '{"holds":{"A":"100.00"},"status":"paid","net":100,"held":0,"error":null}'),
('PTRr', 'control', 'sale A cp 40; spend A; cancel; reopen; pay; cancel; unspend S1; reopen; pay',
  '{"holds":{"A":"100.00"},"status":"paid","net":100,"held":0,"error":null}'),
('PTRwp', 'control', 'sale A cp 40; spend A; spend A; cancel; reopen; pay; cancel; back 1 20; reopen; unspend S1; pay',
  '{"holds":{"A":"80.00"},"status":"paid","net":100,"held":0,"error":null}'),
-- A lot an Owner reversed (reverse_credit_lot: 'reversed', locked, its
-- 'reversal' ledger row), then opened again by a session's refund: passed
-- over as before (NOT COVERED 10), so the credit given back stays
-- spendable on a cancelled package: paid in full, the S$60 left reversed
-- (PX; PXs A spends it); paid in part, the released lot's S$15 reversed,
-- reopened and paid, a guided Cancel (S8gb the refund by line refused; S8gs
-- A spends it); the released lot a Cancel closed, opened while paid by S1's
-- refund, then reversed (S2gb).
('PX', 'known', 'sale A cp; spend A; spend A; reverse A; cancel; unspend S1',
  '{"holds":{"A":"20.00"},"status":"cancelled","net":100,"held":0,"error":null}'),
('PXs', 'known', 'sale A cp; spend A; spend A; reverse A; cancel; unspend S1; spend A',
  '{"holds":{"A":"0.00"},"status":"cancelled","net":100,"held":0,"error":null}'),
('S8gb', 'known', 'sale A cp 40; spend A; spend A 1 svc5; reverse A; cancel; reopen; pay; guidedcancel; unspend S1; back 1 all',
  '{"holds":{"A":"20.00"},"status":"cancelled","net":40,"owed":0,"fdue":0,"held":0,"error~":"back 1 all: That is more than the S$0.00 still owed back%"}'),
('S8gs', 'known', 'sale A cp 40; spend A; spend A 1 svc5; reverse A; cancel; reopen; pay; guidedcancel; unspend S1; spend A',
  '{"holds":{"A":"0.00"},"status":"cancelled","net":40,"owed":0,"held":0,"error":null}'),
('S2gb', 'known', 'sale A cp 40; spend A; spend A 1 svc5; cancel; reopen; pay; unspend S1; reverse closed; guidedcancel; unspend S2; back 1 all',
  '{"holds":{"A":"5.00"},"status":"cancelled","net":25,"owed":0,"fdue":0,"held":0,"error~":"back 1 all: That is more than the S$0.00 still owed back%"}'),
-- Its copy: the released lot an Owner reversed, reissued to B by the
-- reopening's payment after a 'transfer' change (is_locked copied, no
-- 'reversal' row of its own), B's S$80 session paid from all B holds (S$20
-- of it from that copy: all of it, so which lot pays what does not depend
-- on the order of lots made at the same moment), cancelled, that session
-- refunded: the S$20 on the copy is read as Cancel's write-off's lock and
-- held back, the S$60 on B's other lot as the plain case (before 471 B
-- kept all S$80).
('O1', 'fixed', 'sale A cp 40; spend A; spend A 1 svc5; reverse A; cancel; reopen; pay; unspend S1; cancel; change B; reopen; pay; spend B 4; cancel; unspend S3',
  '{"holds":{"A":"0.00","B":"0.00"},"status":"cancelled","net":100,"held":80,"error":null}');

-- States made for the header's query (each before its last refund or
-- correction): a guided Cancel with S1 and S2 still refundable (1); a plain
-- Cancel and a refund in full with an override, S1 refundable (2); a
-- reopening waiting, S1 and S2 refundable (3); paid (none); after a merge of
-- the buyer before the sessions (1); paid in part and cancelled (5); paid in
-- part, cancelled, reopened and paid in full, then cancelled (1, 2) or its
-- customer changed (7); and the released lot the Cancel closed behind the
-- lot the records name (a 'transfer' change, then the reopening's payment
-- reissues A's lot to B, lock and all): S2 refundable (7), or given back
-- before 471 (8).
create temp table t471_qstates(k text primary key, steps text not null, reason text, n int);
insert into t471_qstates values
  ('Qg', 'sale A cp; spend A; spend A; guidedcancel', '1', 2),
  ('Qc', 'sale A cp; spend A; cancel', '2', 1),
  ('Qr', 'sale A cp; spend A; backx 1', '2', 1),
  ('Qw', 'sale A cp; spend A; spend A; cancel; back 1 60; reopen', '3', 2),
  ('Qp', 'sale A cp; spend A', null, null),
  ('Qm', 'sale A cp; merge K A; spend K; guidedcancel', '1', 1),
  -- (B) paid in part, cancelled (plain; guided, S$0 owed back), sessions
  -- paid from the released credit refundable (5).
  ('Qpt', 'sale A cp 40; spend A; cancel', '5', 1),
  ('Qptk', 'sale A cp 40; spend A; spend A; guidedkeep', '5', 2),
  -- paid in part, cancelled, reopened and paid in full (a benefit row names
  -- the released lot the Cancel closed), then cancelled (2) or after a
  -- guided Cancel (1), sessions paid from that lot refundable; or a
  -- 'transfer' change while paid (7).
  ('Qrv', 'sale A cp 40; spend A; cancel; reopen; pay; cancel', '2', 1),
  ('Qrvg', 'sale A cp 40; spend A; spend A; cancel; reopen; pay; guidedcancel', '1', 2),
  ('Qrvb', 'sale A cp 40; spend A; cancel; reopen; pay; change B', '7', 1),
  -- behind the lot the records name: paid (HQ1), cancelled again (HQ3);
  -- S2 then refunded before 471 (HQ1u: A S$20, B S$80, Cancel cannot take
  -- A's S$20 back; HQ3u: A S$20 of a cancelled package)
  ('HQ1', 'sale A cp 40; spend A; spend A; cancel; reopen; pay; unspend S1; cancel; change B; reopen; pay', '7', 1),
  ('HQ3', 'sale A cp 40; spend A; spend A; cancel; reopen; pay; unspend S1; cancel; change B; reopen; pay; cancel', '7', 1),
  ('HQ1u', 'sale A cp 40; spend A; spend A; cancel; reopen; pay; unspend S1; cancel; change B; reopen; pay; unspend S2', '8', 1),
  ('HQ3u', 'sale A cp 40; spend A; spend A; cancel; reopen; pay; unspend S1; cancel; change B; reopen; pay; cancel; unspend S2', '8', 1);

-- The read-only query in 471's header (the same text).
create function pg_temp.t471_header_query() returns table(reason text, invoice_no text, n bigint) language sql as $hq$
with recursive
st as (
  select i.id, i.status::text as status, i.cancel_refund_owed is not null as owed_stated,
         exists (select 1 from public.invoice_reopen_benefits q where q.invoice_id = i.id and q.applied_at is null) as waiting
    from public.invoices i where i.deleted_at is null),
-- the lots of an invoice's credit released before full payment that a
-- Cancel's write-off closed (locked; not an Owner's reversal nor 328's
-- repair): 471 reads them as any other lot (a refund opens them again);
-- also a copy of one that a reissue made (the reopening's payment, a
-- customer change, a merge: each copies the lot whole, its lock with it)
wo as (
  select pl.invoice_id, w.lot_id
    from public.credit_package_progress_lots pl
    cross join lateral unnest(public.credit_lot_chain(pl.lot_id)) w(lot_id)
    join public.customer_credit_lots c on c.id = w.lot_id
   where c.is_locked
     and not exists (select 1 from public.customer_credit_ledger e
                      where e.customer_id = c.customer_id and e.lot_id = c.id
                        and e.source_type in ('reversal', 'credit_lot_provenance_repair'))),
-- the lots an invoice's benefit rows name on which 471 holds back where
-- it is: no lot they replaced holds credit, held by whoever holds the
-- benefits (or by the last live record), the invoice cancelled,
-- refunded or waiting for a reopening's payment
plain as (
  select b.invoice_id, l.id as lot_id, l.remaining_amount, st.status, st.owed_stated, st.waiting
    from public.invoice_benefit_values b
    join st on st.id = b.invoice_id
    join public.customer_credit_lots l on l.id = b.lot_id
   where (st.status in ('cancelled', 'refunded') or st.waiting)
     and (l.status = 'active' and not l.is_locked
          or exists (select 1 from wo where wo.invoice_id = b.invoice_id and wo.lot_id = l.id))
     and not exists (select 1 from public.customer_credit_lots p
                      where p.id = any (public.credit_lot_ancestry(l.id)) and p.id <> l.id
                        and p.remaining_amount > 0 and p.status = 'active'
                        and (not p.is_locked or exists (select 1 from wo where wo.invoice_id = b.invoice_id and wo.lot_id = p.id)))
     and coalesce(public.invoice_credit_live_holder(b.invoice_id, l.customer_id,
           case when public.invoice_benefit_moved_to_other(b.id) then 'infinity'::timestamptz else l.created_at end),
           l.customer_id) = l.customer_id),
-- such a closed lot (or its copy) behind the lot a benefit row names (one
-- the named lot replaced), the named lot one 471 reads, the invoice
-- cancelled, refunded or waiting, or that lot held by someone other than
-- whoever holds the benefits now: what it holds is drawn with the named
-- lot (before, the lock kept it where it was)
behind as (
  select b.invoice_id, p.id as lot_id, p.remaining_amount, p.status as lot_status, st.status, st.owed_stated, st.waiting,
         p.customer_id <> h.holder as elsewhere
    from public.invoice_benefit_values b
    join st on st.id = b.invoice_id
    join public.customer_credit_lots l on l.id = b.lot_id
    cross join lateral (select coalesce(public.invoice_credit_live_holder(b.invoice_id, l.customer_id,
                          case when public.invoice_benefit_moved_to_other(b.id) then 'infinity'::timestamptz else l.created_at end),
                          l.customer_id) as holder) h
    join public.customer_credit_lots p on p.id = any (public.credit_lot_ancestry(l.id)) and p.id <> l.id
   where exists (select 1 from wo where wo.invoice_id = b.invoice_id and wo.lot_id = p.id)
     and l.status = 'active'
     and (not l.is_locked or exists (select 1 from wo where wo.invoice_id = b.invoice_id and wo.lot_id = l.id))
     and (st.status in ('cancelled', 'refunded') or st.waiting or p.customer_id <> h.holder)),
-- such a closed lot a benefit row names (paid in part, cancelled, reopened
-- and paid in full since), held by someone other than whoever holds the
-- benefits now (a 'transfer' customer change, a merge), any status; and
-- such a lot behind it held so
other as (
  select b.invoice_id, l.id as lot_id, l.remaining_amount, l.status as lot_status
    from public.invoice_benefit_values b
    join st on st.id = b.invoice_id
    join public.customer_credit_lots l on l.id = b.lot_id
   where exists (select 1 from wo where wo.invoice_id = b.invoice_id and wo.lot_id = l.id)
     and coalesce(public.invoice_credit_live_holder(b.invoice_id, l.customer_id,
           case when public.invoice_benefit_moved_to_other(b.id) then 'infinity'::timestamptz else l.created_at end),
           l.customer_id) <> l.customer_id
  union all
  select x.invoice_id, x.lot_id, x.remaining_amount, x.lot_status from behind x where x.elsewhere),
osold(invoice_id, n) as (
  select o.invoice_id,
         (select count(*) from public.invoice_line_credit_allocations a where a.lot_id = o.lot_id and a.amount > coalesce(a.reversed_amount, 0))
         + (select count(*) from public.special_credit_allocations s where s.lot_id = o.lot_id and s.amount > coalesce(s.reversed_amount, 0))
    from other o),
-- (B) the release records of cancelled or refunded invoices (paid
-- credit released before full payment) that Cancel's write-off reads
-- (no benefit row names a lot of their chain), with each chain's lots
rel as (
  select pl.invoice_id, x.lot_id, l.remaining_amount, l.status as lot_status
    from public.credit_package_progress_lots pl
    join st on st.id = pl.invoice_id
    cross join lateral unnest(public.credit_lot_chain(pl.lot_id)) x(lot_id)
    join public.customer_credit_lots l on l.id = x.lot_id
   where pl.released_amount > 0 and st.status in ('cancelled', 'refunded')
     and not exists (select 1 from public.invoice_benefit_values b where b.lot_id = any (public.credit_lot_chain(pl.lot_id)))),
rsold(invoice_id, n) as (
  select r.invoice_id,
         (select count(*) from public.invoice_line_credit_allocations a where a.lot_id = r.lot_id and a.amount > coalesce(a.reversed_amount, 0))
         + (select count(*) from public.special_credit_allocations s where s.lot_id = r.lot_id and s.amount > coalesce(s.reversed_amount, 0))
    from rel r),
sold(invoice_id, lot_id, status, owed_stated, waiting, n) as (
  select p.invoice_id, p.lot_id, p.status, p.owed_stated, p.waiting,
         (select count(*) from public.invoice_line_credit_allocations a where a.lot_id = p.lot_id and a.amount > coalesce(a.reversed_amount, 0))
         + (select count(*) from public.special_credit_allocations s where s.lot_id = p.lot_id and s.amount > coalesce(s.reversed_amount, 0))
    from plain p
  union all
  select x.invoice_id, x.lot_id, x.status, x.owed_stated, x.waiting,
         (select count(*) from public.invoice_line_credit_allocations a where a.lot_id = x.lot_id and a.amount > coalesce(a.reversed_amount, 0))
         + (select count(*) from public.special_credit_allocations s where s.lot_id = x.lot_id and s.amount > coalesce(s.reversed_amount, 0))
    from behind x where not x.elsewhere),
-- the lots an invoice's benefit rows name, or lots they replaced, that an
-- Owner reversed or 328's repair replaced (locked, with that ledger row),
-- holding credit again (a refund or correction gave it back since) while
-- the invoice is cancelled, refunded or waiting: 471 passes them over
rv as (
  select distinct b.invoice_id, p.id as lot_id
    from public.invoice_benefit_values b
    join st on st.id = b.invoice_id
    join public.customer_credit_lots p on p.id = any (public.credit_lot_ancestry(b.lot_id))
   where (st.status in ('cancelled', 'refunded') or st.waiting)
     and p.is_locked and p.status = 'active' and p.remaining_amount > 0
     and exists (select 1 from public.customer_credit_ledger e
                  where e.customer_id = p.customer_id and e.lot_id = p.id
                    and e.source_type in ('reversal', 'credit_lot_provenance_repair'))),
found(reason, invoice_id, n) as (
  select '1 changes: cancelled, with an amount owed back stated (a guided Cancel), and sales paid from the lot its records name (or, behind it, a lot of its credit released before full payment that a Cancel closed) that can still be refunded or corrected (the credit they give back is now held back and its money added to what is owed back; before, the customer could spend it and nothing more could be paid back)', s.invoice_id, sum(s.n)
    from sold s where s.n > 0 and s.status = 'cancelled' and s.owed_stated
   group by s.invoice_id
  union all
  select '2 changes: cancelled with no amount owed back stated, or refunded, and sales paid from the lot its records name (or, behind it, a lot of its credit released before full payment that a Cancel closed) that can still be refunded or corrected (the credit they give back is now held back: a refund by line pays it back; on a refunded invoice it is owed to nobody, 470''s NOT COVERED 2; before, the customer could spend it)', s.invoice_id, sum(s.n)
    from sold s where s.n > 0 and (s.status = 'cancelled' and not s.owed_stated or s.status = 'refunded')
   group by s.invoice_id
  union all
  select '3 changes: waiting for a reopening''s payment, with sales paid from the lot its records name (or, behind it, a lot of its credit released before full payment that a Cancel closed) that can still be refunded or corrected (the credit they give back is now held back and queued for that payment, which gives it back; before, the customer could spend it while it waited)', s.invoice_id, sum(s.n)
    from sold s where s.n > 0 and s.status not in ('cancelled', 'refunded') and s.waiting
   group by s.invoice_id
  union all
  select '4 for the Owner (not changed by 471): cancelled, refunded or waiting for a reopening''s payment, with credit spendable today on the lot its records name, or behind it on a lot of its credit released before full payment that a Cancel closed (given back after the cancel before 471, or left on a refunded package by an Owner''s ''larger_refund'' override): a data fix, or left with the customer; until then the next refund or correction of a sale paid from that lot holds it back with the new credit (on a refunded invoice owed to nobody) (the count is of lots)', p.invoice_id, count(*)
    from (select p.invoice_id from plain p where p.remaining_amount > 0
          union all
          select x.invoice_id from behind x where not x.elsewhere and x.remaining_amount > 0 and x.lot_status = 'active') p
   group by p.invoice_id
  union all
  select '5 changes: cancelled or refunded, paid in part, with sales paid from its credit released before full payment that can still be refunded or corrected (the credit they give back is now taken back as Cancel''s write-off and no longer counted as spent, so the money held can be recorded as paid back once nothing released is spent; where an amount owed back was stated, S$1 is added to it for each S$1; before, the customer could spend it and the package read as used)', r.invoice_id, sum(r.n)
    from rsold r where r.n > 0
   group by r.invoice_id
  union all
  select '6 for the Owner (not changed by 471): cancelled or refunded, paid in part, with credit spendable today on a lot of its credit released before full payment (given back after the cancel, before 471): a data fix, or left with the customer; until then the next refund or correction of a sale paid from that lot holds it back with the new credit (the count is of lots)', r.invoice_id, count(*)
    from rel r where r.remaining_amount > 0 and r.lot_status = 'active'
   group by r.invoice_id
  union all
  select '7 changes: paid in part, cancelled, reopened and paid in full since (a benefit row names the lot of its credit released before full payment that the Cancel closed, or a copy of it that a reissue made, with that lot behind it), that lot held by someone other than whoever holds the benefits now, with sales paid from it that can still be refunded or corrected (the credit they give back now goes to whoever holds the benefits, held back while the invoice is cancelled, refunded or waiting; before, it stayed with the customer it went back to) (the count is of sales)', o.invoice_id, sum(o.n)
    from osold o where o.n > 0
   group by o.invoice_id
  union all
  select '8 for the Owner (not changed by 471): as 7, with credit spendable today on that lot (given back before 471): a data fix, or left with the customer; until then the next refund or correction of a sale paid from that lot moves it with the new credit (the count is of lots)', o.invoice_id, count(*)
    from other o where o.remaining_amount > 0 and o.lot_status = 'active'
   group by o.invoice_id
  union all
  select '9 for the Owner (not changed by 471: NOT COVERED 10): cancelled, refunded or waiting for a reopening''s payment, with credit spendable today on the lot its records name, or one it replaced, that an Owner reversed (reverse_credit_lot) or 328''s repair replaced, given back on it since by a refund or correction: 471 passes such a lot over, so that credit stays spendable, and so does what the next refund or correction of a sale paid from it gives back: a data fix, or left with the customer (the count is of lots)', r.invoice_id, count(*)
    from rv r
   group by r.invoice_id)
select f.reason, i.invoice_no, f.n
  from found f join public.invoices i on i.id = f.invoice_id
 order by f.reason, i.invoice_no
$hq$;

-- ===== S. Where it starts =====
create temp table t471_fp(k text primary key, v text);
create function pg_temp.t471_grants(p_without text[] default '{}') returns text language sql as $f$
  select md5(string_agg(p.oid::regprocedure::text || '=' || coalesce(p.proacl::text, ''), '|' order by p.oid::regprocedure::text))
    from pg_proc p where p.pronamespace = 'public'::regnamespace and not (p.proname = any (p_without)) $f$;
create function pg_temp.t471_grant_set(p_sig text) returns text[] language sql as $f$
  select array_agg(x::text order by x::text) from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || p_sig) $f$;
insert into t471_fp values ('start', pg_temp.t471_fingerprint()), ('grants', pg_temp.t471_grants()), ('triggers', pg_temp.t471_inv_triggers());
-- The function 471 changes: BEFORE (production, 26 Oct 2026: 470's AFTER)
-- and AFTER. It adds nothing.
create temp table t471_md5(sig text primary key, before text, after text);
insert into t471_md5 values
  ('credit_given_back_follows(uuid)', 'b7720a148f5371bd2bd844d3076ea3b2', '1417d83e7d7be49209f5cd1369d07ec7');
create function pg_temp.t471_at(p_col text) returns boolean language sql as $f$
  select bool_and(case when p_col = 'before' then md5(pg_get_functiondef(to_regprocedure('public.' || m.sig))) = m.before
                       else md5(pg_get_functiondef(to_regprocedure('public.' || m.sig))) = m.after end)
    from t471_md5 m $f$;
do $$ begin
  perform pg_temp.t471_check(pg_temp.t471_462_in() and pg_temp.t471_463_in() and pg_temp.t471_470_in(),
    'S 462, 463 and 470 are in (471 goes in after them)');
  perform pg_temp.t471_check(split_part(pg_temp.t471_inv_triggers(), ' ', 1) = '92c94e3ebc6113a68d972330bbca8938',
    'S the triggers on invoices are as read on production (26 Oct 2026): ' || pg_temp.t471_inv_triggers());
end $$;
\if :{?nomig}
do $$ begin
  perform pg_temp.t471_check(pg_temp.t471_in() and pg_temp.t471_at('after'), 'S -v nomig=1: 471 is in, as tested');
end $$;
\else
do $$ begin
  perform pg_temp.t471_check(not pg_temp.t471_in() and pg_temp.t471_at('before'),
    'S 471 is not in yet and the forwarder is 470''s (this suite installs it; use -v nomig=1 where it is in)');
end $$;

-- ===== R. Before 471: each case reproduced (undone afterwards) =====
-- A 'fixed' case does not end as 471 makes it; a control does, exactly.
savepoint t471_r;
do $$
declare c record; o jsonb; res text := '';
begin
  for c in select * from t471_cases order by ord loop
    o := pg_temp.t471_run('before', c.k, c.steps);
    if c.kind = 'fixed' then
      perform pg_temp.t471_check(not (pg_temp.t471_meets(o, c.expect) and coalesce(o->>'invariants', '') = ''),
        'R ' || c.k || ' already ends as 471 makes it, without 471: ' || o::text);
      res := res || format(E'\n  %s: %s; net %s; owed %s%s%s', c.k,
        (select string_agg(h.key || ' ' || (h.value #>> '{}'), ', ' order by h.key) from jsonb_each(o->'holds') h),
        o->>'net', coalesce(o->>'owed', '-'), coalesce('; ' || nullif(o->>'invariants', ''), ''), coalesce('; refused: ' || left(o->>'error', 100), ''));
    else
      perform pg_temp.t471_check(pg_temp.t471_meets(o, c.expect) and coalesce(o->>'invariants', '') = ''
          and coalesce((o->>'cancel_left')::numeric, 0) = 0,
        'R ' || c.kind || ' ' || c.k || ' without 471: ' || coalesce(pg_temp.t471_diff(o, c.expect), '') || ' ' || o::text);
    end if;
  end loop;
  for c in select * from t471_qstates loop
    perform pg_temp.t471_run('before', c.k, c.steps);
  end loop;
  raise notice 'PASS R: without 471 every fixed case ends otherwise (the faults reproduced), the controls and the known cases as expected:%', res;
end $$;

-- ===== Q. The header's read-only query, on these states =====
create temp table t471_q as select * from pg_temp.t471_header_query();
create function pg_temp.t471_q_n(p_reason text, p_case text) returns bigint language sql as $f$
  select q.n from t471_q q join invoices i on i.invoice_no = q.invoice_no
   where left(q.reason, 1) = p_reason and i.id = pg_temp.t471_id('before/' || p_case || '/inv') $f$;
do $$
declare c record; v_want text; v_got text;
begin
  -- 1 to 3: the states made for it, each under its reason with its count of
  -- sales still refundable; a paid package nowhere.
  for c in select * from t471_qstates loop
    if c.reason is null then
      perform pg_temp.t471_check(not exists (select 1 from t471_q q join invoices i on i.invoice_no = q.invoice_no
                                              where i.id = pg_temp.t471_id('before/' || c.k || '/inv')), 'Q ' || c.k || ' (paid) is listed');
    else
      perform pg_temp.t471_check(pg_temp.t471_q_n(c.reason, c.k) = c.n,
        'Q ' || c.k || ' is not listed under ' || c.reason || ' with ' || c.n || ' (' || coalesce(pg_temp.t471_q_n(c.reason, c.k)::text, 'not listed') || ')');
    end if;
  end loop;
  -- 4: exactly the R states where a cancelled, refunded or waiting package's
  -- customer (the buyer, the record a merge kept, B after a change) holds
  -- credit on a lot a benefit row names, as whoever holds the benefits
  -- (paid in full; also once reopened and paid in full after a part
  -- payment: the released lot the Cancel closed, or its copy, O1), but not
  -- on a lot an Owner reversed (9).
  select string_agg(i.invoice_no, ', ' order by i.invoice_no) into v_want
    from t471_res r join invoices i on i.id = pg_temp.t471_id('before/' || r.k || '/inv')
   where r.phase = 'before'
     and (r.v->>'status' in ('cancelled', 'refunded')
          or exists (select 1 from invoice_reopen_benefits q where q.invoice_id = i.id and q.applied_at is null))
     and (select coalesce(sum(split_part(h.value #>> '{}', '/', 1)::numeric), 0) from jsonb_each(r.v->'holds') h) > 0
     and exists (select 1 from invoice_benefit_values bv join customer_credit_lots l on l.id = bv.lot_id
                  where bv.invoice_id = i.id and l.remaining_amount > 0 and l.status = 'active'
                    and not (l.is_locked and exists (select 1 from customer_credit_ledger e where e.lot_id = l.id
                                                      and e.source_type in ('reversal', 'credit_lot_provenance_repair')))
                    and coalesce(invoice_credit_live_holder(i.id, l.customer_id,
                          case when invoice_benefit_moved_to_other(bv.id) then 'infinity'::timestamptz else l.created_at end),
                          l.customer_id) = l.customer_id);
  select string_agg(invoice_no, ', ' order by invoice_no) into v_got from t471_q where left(reason, 1) = '4';
  perform pg_temp.t471_check(v_want is not null and v_got = v_want, 'Q 4 lists ' || coalesce(v_got, '-') || ', not ' || coalesce(v_want, '-'));
  -- 6: exactly the R states paid in part, cancelled or refunded, where a
  -- lot of the invoice's family holds credit that can be spent (an active
  -- lot; a special document's refund puts credit back on the closed lot
  -- without opening it: PTsp, not listed, though 471 holds that back too).
  select string_agg(i.invoice_no, ', ' order by i.invoice_no) into v_want
    from t471_res r join invoices i on i.id = pg_temp.t471_id('before/' || r.k || '/inv')
   where r.phase = 'before'
     and exists (select 1 from credit_package_progress_lots pl where pl.invoice_id = i.id)
     and not exists (select 1 from invoice_benefit_values bv where bv.invoice_id = i.id)
     and r.v->>'status' in ('cancelled', 'refunded')
     and exists (select 1 from customer_credit_lots l where l.id in (select pg_temp.t471_family(i.id))
                  and l.remaining_amount > 0 and l.status = 'active');
  select string_agg(invoice_no, ', ' order by invoice_no) into v_got from t471_q where left(reason, 1) = '6';
  perform pg_temp.t471_check(v_want is not null and v_got = v_want, 'Q 6 lists ' || coalesce(v_got, '-') || ', not ' || coalesce(v_want, '-'));
  perform pg_temp.t471_check(pg_temp.t471_q_n('6', 'PT1') = 1 and pg_temp.t471_q_n('6', 'PTmb') = 1 and pg_temp.t471_q_n('4', 'PT1') is null
      and pg_temp.t471_q_n('6', 'PTsp') is null,
    'Q 6 does not list PT1 (A''s released lot) and PTmb (the lot the merge made), or lists PTsp, or 4 lists PT1');
  perform pg_temp.t471_check(pg_temp.t471_q_n('4', 'G2') = 1 and pg_temp.t471_q_n('4', 'RX0') = 1 and pg_temp.t471_q_n('4', 'PDel') = 1,
    'Q 4 does not list G2 (cancelled), RX0 (refunded) and PDel (the buyer deleted)');
  -- Reopened and paid in full after a part payment: credit given back on
  -- the released lot the Cancel closed is listed under 4 (PTRc, PTRg, PTRx:
  -- the lock no longer hides it); 8 lists exactly PTRh and PTRhp (that lot
  -- A's, the benefits B's).
  perform pg_temp.t471_check(pg_temp.t471_q_n('4', 'PTRc') = 1 and pg_temp.t471_q_n('4', 'PTRg') = 1 and pg_temp.t471_q_n('4', 'PTRx') = 1
      and pg_temp.t471_q_n('4', 'PTRh') is null and pg_temp.t471_q_n('6', 'PTRc') is null,
    'Q 4 does not list PTRc, PTRg and PTRx (the released lot the Cancel closed), or lists PTRh, or 6 lists PTRc');
  -- 8 lists exactly PTRh and PTRhp, and HQ1u and HQ3u (A's S$20 on the
  -- released lot the Cancel closed, behind B's lot the records name).
  select string_agg(invoice_no, ', ' order by invoice_no) into v_got from t471_q where left(reason, 1) = '8';
  select string_agg(i.invoice_no, ', ' order by i.invoice_no) into v_want
    from invoices i where i.id in (pg_temp.t471_id('before/PTRh/inv'), pg_temp.t471_id('before/PTRhp/inv'),
                                   pg_temp.t471_id('before/HQ1u/inv'), pg_temp.t471_id('before/HQ3u/inv'));
  perform pg_temp.t471_check(v_got = v_want, 'Q 8 lists ' || coalesce(v_got, '-') || ', not ' || coalesce(v_want, '-'));
  -- O1 is listed under 4 with both of B's lots (S$20 on B's copy of the lot
  -- an Owner reversed, which has no reversal row of its own, and S$60 on
  -- B's other lot), not under 9; HQ3 (cancelled, S2 paid from A's lot
  -- behind B's) under 7, not under 2.
  perform pg_temp.t471_check(pg_temp.t471_q_n('4', 'O1') = 2 and pg_temp.t471_q_n('9', 'O1') is null
      and pg_temp.t471_q_n('7', 'HQ3') = 1 and pg_temp.t471_q_n('2', 'HQ3') is null,
    'Q O1 is not listed under 4 (or is under 9), or HQ3 is not under 7 alone');
  -- 9: exactly the R states cancelled, refunded or waiting where a lot of
  -- the invoice's family that an Owner reversed holds credit given back
  -- since (PX, S8gb, S2gb; not PXs, S8gs: spent), none of them under 4.
  select string_agg(i.invoice_no, ', ' order by i.invoice_no) into v_want
    from t471_res r join invoices i on i.id = pg_temp.t471_id('before/' || r.k || '/inv')
   where r.phase = 'before'
     and (r.v->>'status' in ('cancelled', 'refunded')
          or exists (select 1 from invoice_reopen_benefits q where q.invoice_id = i.id and q.applied_at is null))
     and exists (select 1 from customer_credit_lots l where l.id in (select pg_temp.t471_family(i.id))
                  and l.remaining_amount > 0 and l.status = 'active' and l.is_locked
                  and exists (select 1 from customer_credit_ledger e where e.lot_id = l.id
                               and e.source_type in ('reversal', 'credit_lot_provenance_repair')));
  select string_agg(invoice_no, ', ' order by invoice_no) into v_got from t471_q where left(reason, 1) = '9';
  perform pg_temp.t471_check(v_want is not null and v_got = v_want, 'Q 9 lists ' || coalesce(v_got, '-') || ', not ' || coalesce(v_want, '-'));
  perform pg_temp.t471_check(pg_temp.t471_q_n('9', 'PX') = 1 and pg_temp.t471_q_n('9', 'S8gb') = 1 and pg_temp.t471_q_n('9', 'S2gb') = 1
      and pg_temp.t471_q_n('4', 'PX') is null and pg_temp.t471_q_n('4', 'S8gb') is null and pg_temp.t471_q_n('4', 'S2gb') is null,
    'Q 9 does not list PX, S8gb and S2gb (a lot an Owner reversed), or 4 lists one');
  raise notice 'PASS Q: the header''s read-only query lists % invoices (%), each reason as expected',
    (select count(distinct invoice_no) from t471_q),
    (select string_agg(left(reason, 1) || ' ' || n, ', ' order by left(reason, 1)) from (select reason, count(*) n from t471_q group by reason) x);
end $$;
-- Keep R's outcomes; undo its records.
select coalesce(jsonb_object_agg(k, v), '{}'::jsonb)::text as t471_rbefore from t471_res where phase = 'before' \gset
rollback to savepoint t471_r;
insert into t471_res select 'before', key, value from jsonb_each(:'t471_rbefore'::jsonb);
do $$ begin
  perform pg_temp.t471_check((select count(*) from t471_res where phase = 'before') = (select count(*) from t471_cases) + (select count(*) from t471_qstates)
      and pg_temp.t471_fingerprint() = (select v from t471_fp where k = 'start'),
    'R undone, its outcomes kept');
end $$;

-- ===== 9. The refusals, each changing nothing =====
-- 9a The forwarder is neither 470's nor 471's.
savepoint t471_9;
alter function public.credit_given_back_follows(uuid) set work_mem = '64kB';
\set ON_ERROR_STOP off
\ir ../../../supabase/471_plain_cancelled_package_credit_held_back.sql
\set ON_ERROR_STOP on
rollback to savepoint t471_9;
select set_config('t471.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t471_check(current_setting('t471.msg') like '471: public.credit_given_back_follows(uuid) is not the version this was tested against (md5 %). Re-read it and re-test before applying.'
      and not pg_temp.t471_in(), '9a refused with: ' || current_setting('t471.msg'));
end $$;
-- 9b A function it relies on is not as read (a setting added to it): the
-- refund options' reader, and 462's trigger function.
savepoint t471_9;
alter function public.invoice_financial_position(uuid) set work_mem = '64kB';
\set ON_ERROR_STOP off
\ir ../../../supabase/471_plain_cancelled_package_credit_held_back.sql
\set ON_ERROR_STOP on
rollback to savepoint t471_9;
select set_config('t471.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t471_check(current_setting('t471.msg') like '471: public.invoice_financial_position(uuid) is missing or not the version this was tested against (md5 %). Re-read it and re-test before applying.'
      and not pg_temp.t471_in(), '9b refused with: ' || current_setting('t471.msg'));
end $$;
savepoint t471_9;
alter function public.trg_credit_given_back_follows() set work_mem = '64kB';
\set ON_ERROR_STOP off
\ir ../../../supabase/471_plain_cancelled_package_credit_held_back.sql
\set ON_ERROR_STOP on
rollback to savepoint t471_9;
select set_config('t471.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t471_check(current_setting('t471.msg') like '471: public.trg_credit_given_back_follows() is missing or not the version this was tested against (md5 %)%'
      and not pg_temp.t471_in(), '9b2 refused with: ' || current_setting('t471.msg'));
end $$;
-- 9c Another function takes its name (an overload).
savepoint t471_9;
create function public.credit_given_back_follows(p text) returns void language sql as $f$ select $f$;
\set ON_ERROR_STOP off
\ir ../../../supabase/471_plain_cancelled_package_credit_held_back.sql
\set ON_ERROR_STOP on
rollback to savepoint t471_9;
select set_config('t471.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t471_check(current_setting('t471.msg') = '471: another function takes the name of the one this changes: credit_given_back_follows(text)'
      and not pg_temp.t471_in(), '9c refused with: ' || current_setting('t471.msg'));
end $$;
-- 9d A new reader or writer of a cancellation's ledger rows.
savepoint t471_9;
create function public.t471_probe_cancel_rows() returns text language sql as $f$ select 'invoice_cancel_benefit'::text $f$;
\set ON_ERROR_STOP off
\ir ../../../supabase/471_plain_cancelled_package_credit_held_back.sql
\set ON_ERROR_STOP on
rollback to savepoint t471_9;
select set_config('t471.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t471_check(current_setting('t471.msg') like '471: what reads or writes a cancellation''s ledger rows is not as read on 26 Oct 2026 (%t471_probe_cancel_rows()%)'
      and not pg_temp.t471_in(), '9d refused with: ' || current_setting('t471.msg'));
end $$;
-- 9e A trigger on invoices that was not there when this was read.
savepoint t471_9;
create trigger t471_probe after update on public.invoices for each row execute function public.trg_lock_on_settle();
\set ON_ERROR_STOP off
\ir ../../../supabase/471_plain_cancelled_package_credit_held_back.sql
\set ON_ERROR_STOP on
rollback to savepoint t471_9;
select set_config('t471.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t471_check(current_setting('t471.msg') like '471: the triggers on invoices are not as read on 26 Oct 2026 (20 triggers, md5 %)%'
      and not pg_temp.t471_in(), '9e refused with: ' || current_setting('t471.msg'));
end $$;
-- 9f A new way to raise a lot's balance (it would need the same care).
savepoint t471_9;
create function public.t471_probe_raise(p uuid) returns void language sql as $f$
  update public.customer_credit_lots set remaining_amount = remaining_amount + 0 where id = p $f$;
\set ON_ERROR_STOP off
\ir ../../../supabase/471_plain_cancelled_package_credit_held_back.sql
\set ON_ERROR_STOP on
rollback to savepoint t471_9;
select set_config('t471.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t471_check(current_setting('t471.msg') like '471: what gives credit back on a lot is not as read on 26 Oct 2026 (% / %t471_probe_raise(uuid)%)%'
      and not pg_temp.t471_in(), '9f refused with: ' || current_setting('t471.msg'));
end $$;
-- 9h A new reader or writer of the release record (credit released before
-- full payment).
savepoint t471_9;
create function public.t471_probe_release() returns bigint language sql as $f$ select count(*) from public.credit_package_progress_lots $f$;
\set ON_ERROR_STOP off
\ir ../../../supabase/471_plain_cancelled_package_credit_held_back.sql
\set ON_ERROR_STOP on
rollback to savepoint t471_9;
select set_config('t471.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t471_check(current_setting('t471.msg') like '471: what reads or writes the release record of credit released before full payment, or its write-off rows, is not as read on 26 Oct 2026 (%t471_probe_release()%'
      and not pg_temp.t471_in(), '9h refused with: ' || current_setting('t471.msg'));
end $$;
-- 9i A new way to lock a lot (the forwarder reads past Cancel's write-off's
-- lock on a lot of the release record, telling it from the others).
savepoint t471_9;
create function public.t471_probe_lock(p uuid) returns void language sql as $f$
  update public.customer_credit_lots set is_locked = true where id = p $f$;
\set ON_ERROR_STOP off
\ir ../../../supabase/471_plain_cancelled_package_credit_held_back.sql
\set ON_ERROR_STOP on
rollback to savepoint t471_9;
select set_config('t471.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t471_check(current_setting('t471.msg') like '471: what locks a credit lot is not as read on 26 Oct 2026 (%t471_probe_lock(uuid)%)%'
      and not pg_temp.t471_in(), '9i refused with: ' || current_setting('t471.msg'));
end $$;
-- 9g The same grants in another order: installs (compared as sets).
savepoint t471_9;
revoke execute on function public.credit_given_back_follows(uuid) from postgres;
grant execute on function public.credit_given_back_follows(uuid) to postgres;
\ir ../../../supabase/471_plain_cancelled_package_credit_held_back.sql
do $$ begin
  perform pg_temp.t471_check(pg_temp.t471_in() and pg_temp.t471_at('after'), '9g the same grants in another order stopped it');
end $$;
rollback to savepoint t471_9;
do $$ begin
  perform pg_temp.t471_check(pg_temp.t471_fingerprint() = (select v from t471_fp where k = 'start') and not pg_temp.t471_in()
      and pg_temp.t471_grants() = (select v from t471_fp where k = 'grants'),
    '9 the refusals left a change');
  raise notice 'PASS 9: refused, changing nothing: the forwarder not 470''s, a function it relies on not as tested (the financial position, 462''s trigger function), an overload of its name, a new reader of a cancellation''s rows, a new trigger on invoices, a new way to raise a lot, a new reader of the release record, a new way to lock a lot. The same grants in another order do not stop it';
end $$;

-- ===== M. Begun before 471, finished after it (the mid set) =====
-- Cancelled (guided or plain), refunded or waiting when it goes in, the
-- session refunded or corrected after; and credit given back before 471
-- (G2's state on production today: MG2a, MG2x, MG2d, MG2b, MPWx).
create temp table t471_mid(k text primary key, ord serial, split int, steps text, expect jsonb);
insert into t471_mid(k, split, steps, expect) select 'm' || k, s, steps, expect from (values
  ('G2', 6), ('GN', 4), ('RX0', 3), ('PFa', 4), ('PCs', 4), ('PCh', 6), ('PW', 6), ('PWs', 6), ('PCx', 5),
  ('PT1r', 3), ('PTg', 3), ('PTf', 4), ('PTRg', 6), ('PTRhp', 6)) x(k, s)
  join t471_cases c using (k);
insert into t471_mid(k, split, steps, expect) values
  ('MG2a', 6, 'sale A cp; spend A; spend A; spend A; guidedcancel; unspend S2',
    '{"holds":{"A":"20.00"},"status":"cancelled","net":60,"owed":0,"held":0,"error":null}'),
  ('MG2x', 6, 'sale A cp; spend A; spend A; spend A; guidedcancel; unspend S2; unspend S3',
    '{"holds":{"A":"0.00"},"status":"cancelled","net":60,"owed":40,"fdue":40,"held":40,"error":null}'),
  ('MG2d', 6, 'sale A cp; spend A; spend A; spend A; guidedcancel; unspend S2; fix S3 date',
    '{"holds":{"A":"0.00"},"status":"cancelled","net":60,"owed":20,"fdue":20,"held":20,"error":null}'),
  ('MG2b', 6, 'sale A cp; spend A; spend A; spend A; guidedcancel; unspend S2; back 1 all',
    '{"holds":{"A":"20.00"},"status":"cancelled","net":60,"owed":0,"held":0,"error~":"back 1 all: That is more than the S$0.00 still owed back%"}'),
  ('MPWx', 7, 'sale A cp; spend A; spend A; cancel; back 1 60; reopen; unspend S2; spend A',
    '{"holds":{"A":"0.00"},"status":"partially_paid","net":40,"held":0,"error":null}'),
  -- (B) paid in part: S1's credit given back before 471 stays spendable
  -- (MPTs); held back with S2's at S2's refund after it, and the money held
  -- then recorded as paid back (MPTa).
  ('MPTs', 4, 'sale A cp 40; spend A; cancel; unspend S1; spend A',
    '{"holds":{"A":"0.00"},"status":"cancelled","net":40,"error":null}'),
  ('MPTa', 5, 'sale A cp 40; spend A; spend A; cancel; unspend S1; unspend S2; refundpaid',
    '{"holds":{"A":"0.00"},"status":"cancelled","net":0,"error":null}'),
  -- reopened and paid in full after a part payment, then a guided Cancel:
  -- S1's credit given back before 471 on the released lot the Cancel closed
  -- stays spendable (MPTRs); held back with S2's at S2's refund after it
  -- (MPTRa: S$40 owed back).
  ('MPTRs', 8, 'sale A cp 40; spend A; spend A; cancel; reopen; pay; guidedcancel; unspend S1; spend A',
    '{"holds":{"A":"0.00"},"status":"cancelled","net":40,"owed":0,"held":0,"error":null}'),
  ('MPTRa', 8, 'sale A cp 40; spend A; spend A; cancel; reopen; pay; guidedcancel; unspend S1; unspend S2',
    '{"holds":{"A":"0.00"},"status":"cancelled","net":40,"owed":40,"fdue":40,"held":40,"error":null}'),
  -- the released lot the Cancel closed behind B's lot the records name (a
  -- 'transfer' change, then the reopening's payment reissued A's lot to
  -- B), cancelled again before 471: S2, paid from A's lot, refunded after
  -- it is held back (MHQ3: S$100 held); refunded before it, A's S$20 stays
  -- (NOT COVERED 4): A spends it (MHQ3s), or reopened and paid it stays
  -- with A, B S$80, and Cancel cannot take A's S$20 back (MHQ3r, its
  -- cancel_left checked as it is).
  ('MHQ3', 12, 'sale A cp 40; spend A; spend A; cancel; reopen; pay; unspend S1; cancel; change B; reopen; pay; cancel; unspend S2',
    '{"holds":{"A":"0.00","B":"0.00"},"status":"cancelled","net":100,"held":100,"error":null}'),
  ('MHQ3s', 13, 'sale A cp 40; spend A; spend A; cancel; reopen; pay; unspend S1; cancel; change B; reopen; pay; cancel; unspend S2; spend A',
    '{"holds":{"A":"0.00","B":"0.00"},"status":"cancelled","net":100,"held":80,"error":null}'),
  ('MHQ3r', 13, 'sale A cp 40; spend A; spend A; cancel; reopen; pay; unspend S1; cancel; change B; reopen; pay; cancel; unspend S2; reopen; pay',
    '{"holds":{"A":"20.00","B":"80.00"},"status":"paid","net":100,"held":0,"cancel_left":20,"error":null}'),
  -- a lot an Owner reversed holding credit given back before 471 (the
  -- first run names it, the query's 9): passed over after 471 too, A
  -- spends it (NOT COVERED 10).
  ('MPX', 6, 'sale A cp; spend A; spend A; reverse A; cancel; unspend S1; spend A',
    '{"holds":{"A":"0.00"},"status":"cancelled","net":100,"held":0,"error":null}');
do $$ declare c record; begin
  for c in select * from t471_mid order by ord loop
    perform pg_temp.t471_run('mid', c.k, c.steps, 1, c.split);
  end loop;
end $$;
\endif

-- ===== 10. Install 471, twice =====
\if :{?nomig}
do $$ begin raise notice 'NOTE 10: -v nomig=1, so 471 is not installed here (R, Q, 9 and M are skipped)'; end $$;
\else
\ir ../../../supabase/471_plain_cancelled_package_credit_held_back.sql
do $$ begin insert into t471_fp values ('first', pg_temp.t471_fingerprint()); end $$;
\ir ../../../supabase/471_plain_cancelled_package_credit_held_back.sql
do $$ begin insert into t471_fp values ('second', pg_temp.t471_fingerprint()); end $$;
\endif
do $$
begin
  perform pg_temp.t471_check(pg_temp.t471_in() and pg_temp.t471_at('after'), '10 471 is not installed as tested');
  perform pg_temp.t471_check((select count(*) from pg_proc where pronamespace = 'public'::regnamespace
                               and proname = 'credit_given_back_follows') = 1, '10 an overload exists');
  -- Nothing added: no function, no trigger (the triggers on invoices and
  -- 462's ledger trigger exactly as before).
  perform pg_temp.t471_check(pg_temp.t471_inv_triggers() = (select v from t471_fp where k = 'triggers')
      and (select count(*) from pg_trigger where tgrelid = 'public.customer_credit_ledger'::regclass and not tgisinternal and tgname like 'credit_given_back%') = 1,
    '10 a trigger was added or changed: ' || pg_temp.t471_inv_triggers());
  perform pg_temp.t471_check(pg_temp.t471_grant_set('credit_given_back_follows(uuid)') = '{postgres=X/postgres,service_role=X/postgres}'
      and not has_function_privilege('anon', 'public.credit_given_back_follows(uuid)', 'execute')
      and not has_function_privilege('authenticated', 'public.credit_given_back_follows(uuid)', 'execute'),
    '10 who may call it is not as intended');
  if exists (select 1 from t471_fp where k = 'first') then
    perform pg_temp.t471_check((select v from t471_fp where k = 'second') = (select v from t471_fp where k = 'first'),
      '10 the second run of 471 changed functions');
    perform pg_temp.t471_check(split_part((select v from t471_fp where k = 'first'), ' ', 2)::int
                               = split_part((select v from t471_fp where k = 'start'), ' ', 2)::int,
      '10 471 added or dropped a function');
    perform pg_temp.t471_check(pg_temp.t471_grants() = (select v from t471_fp where k = 'grants'),
      '10 the grants changed');
  end if;
  raise notice 'PASS 10: 471 installed as tested (%); the forwarder at its AFTER, the server''s alone; nothing added (no function, no trigger); %',
    pg_temp.t471_fingerprint(),
    coalesce((select 'the second run changed nothing, the grants as before' from t471_fp where k = 'first'), 'it was in before the suite (nomig)');
end $$;

-- ===== A. Each case after 471 =====
do $$
declare c record; o jsonb; b jsonb; res text := '';
begin
  for c in select * from t471_cases order by ord loop
    o := pg_temp.t471_run('after', c.k, c.steps);
    perform pg_temp.t471_check(pg_temp.t471_meets(o, c.expect),
      'A ' || c.k || ': ' || coalesce(pg_temp.t471_diff(o, c.expect), '') || ' ' || o::text);
    perform pg_temp.t471_check(coalesce(o->>'invariants', '') = '', 'A ' || c.k || ' invariants: ' || (o->>'invariants'));
    perform pg_temp.t471_check(coalesce((o->>'cancel_left')::numeric, 0) = 0,
      'A ' || c.k || ': Cancel leaves S$' || (o->>'cancel_left') || ' of the invoice''s credit behind');
    b := (select v from t471_res where phase = 'before' and k = c.k);
    -- (a refusal's text names its invoice, numbered differently in each run;
    -- an amount owed back left on an invoice that is no longer cancelled is
    -- read by nothing, and a new Cancel states it again: PRg keeps S$20 from
    -- its hold, as 470's G1 does after a reissue, so it is not compared)
    if c.kind in ('control', 'known') and b is not null then
      perform pg_temp.t471_check(o - 'error' - case when o->>'status' = 'cancelled' then '' else 'owed' end
                                 = b - 'error' - case when b->>'status' = 'cancelled' then '' else 'owed' end
          and regexp_replace(coalesce(o->>'error', ''), 'INV-[0-9-]+', 'INV', 'g') = regexp_replace(coalesce(b->>'error', ''), 'INV-[0-9-]+', 'INV', 'g'),
        'A ' || c.kind || ' ' || c.k || ' changed with 471: before ' || b::text || ', after ' || o::text);
    end if;
    res := res || format(E'\n  %s %s: %s; net %s; owed %s; held back %s%s', c.kind, c.k,
      (select string_agg(h.key || ' ' || (h.value #>> '{}'), ', ' order by h.key) from jsonb_each(o->'holds') h), o->>'net',
      coalesce(o->>'owed', '-'), o->>'held', coalesce('; refused: ' || left(o->>'error', 100), ''));
  end loop;
  raise notice 'PASS A: after 471 each case ends by the Owner''s rules (the known cases as NOT COVERED 10 says), the invariants hold in every case and Cancel takes all of it back; the controls and the known cases are exactly as before 471%:%',
    case when exists (select 1 from t471_res where phase = 'before') then '' else ' (no before figures: -v nomig=1)' end, res;
end $$;

-- ===== M (after). The mid set finished with 471 in =====
\if :{?nomig}
\else
do $$
declare c record; o jsonb; res text := '';
begin
  for c in select * from t471_mid order by ord loop
    o := pg_temp.t471_run('mid', c.k, c.steps, c.split + 1);
    -- (Cancel takes it all back, but where the case says what it leaves:
    -- MHQ3r, NOT COVERED 4, checked as it is.)
    perform pg_temp.t471_check(pg_temp.t471_meets(o, c.expect) and coalesce(o->>'invariants', '') = ''
        and (c.expect ? 'cancel_left' or coalesce((o->>'cancel_left')::numeric, 0) = 0),
      'M ' || c.k || ': ' || coalesce(pg_temp.t471_diff(o, c.expect), '') || ' ' || o::text);
    res := res || ' ' || c.k;
  end loop;
  raise notice 'PASS M: begun before 471 and finished after it, each ends as the whole case does after 471; credit given back before 471 is left spendable (MG2a, MG2b, MPWx; paid in part MPTs; reopened and paid in full MPTRs; behind the lot the records name MHQ3s, and reopened and paid it stays, Cancel leaving S$20: MHQ3r) until a refund or correction of a sale paid from that lot holds it back with the new credit (MG2x S$40, MG2d S$20 by a date-only correction; paid in part MPTa S$40, then recorded as paid back; MPTRa S$40 owed back); behind the lot the records name, held back after 471 (MHQ3: S$100):%', res;
end $$;
\endif

-- ===== P. Probes =====
do $$
declare inv uuid; a uuid; lot uuid; lot0 uuid; o jsonb; m jsonb; v_req uuid; e record;
begin
  -- P1 G2: held back where it is: the lot the records name is the package's
  -- own (the sale's lot, never reissued: no reassignment row, A has that one
  -- lot), S$0, with one held-back row of S$20 (A's, not queued); the row
  -- holds back S$20; S$20 owed back; the Audit Log says so (in place, held
  -- back S$20, owed S$0 -> S$20); A's statement: S2's credit returned, then
  -- taken off, a balance of S$0.
  inv := pg_temp.t471_id('after/G2/inv'); a := pg_temp.t471_id('after/G2/A'); lot := pg_temp.t471_own_lot(inv);
  perform pg_temp.t471_check(
        lot = (select s.credit_lot_id from credit_package_sales s where s.invoice_id = inv)
    and (select count(*) from customer_credit_lots where customer_id = a) = 1
    and not exists (select 1 from customer_credit_ledger x where x.source_record_id = inv and x.source_type like 'credit_given_back_reassignment_%')
    and (select remaining_amount from customer_credit_lots where id = lot) = 0
    and (select original_amount from customer_credit_lots where id = lot) = 100
    and pg_temp.t471_held_n(lot) = 1 and pg_temp.t471_held(lot) = 20
    and (select x.customer_id from customer_credit_ledger x where x.lot_id = lot and x.reason like 'Held back by%') = a
    and not exists (select 1 from invoice_reopen_benefits q join customer_credit_ledger x on x.id = q.source_ledger_id
                     where x.lot_id = lot and x.reason like 'Held back by%')
    and (select cancelled_unused_value from invoice_benefit_values where id = pg_temp.t471_own(inv)) = 20
    and (select cancel_refund_owed from invoices where id = inv) = 20,
    'P1 G2: not held back where it is');
  perform pg_temp.t471_check((select count(*) from audit_logs al where al.record_id = inv and al.action = 'credit_given_back_followed'
            and (al.new_data->>'held_in_place')::boolean and (al.new_data->>'held_back')::numeric = 20
            and (al.new_data->>'lot_id')::uuid = lot and al.new_data->>'to_customer' = a::text
            and al.new_data->>'queued_for_request' is null
            and (al.new_data->>'refund_owed')::numeric = 0 and (al.new_data->>'refund_owed_added')::numeric = 20
            and (al.new_data->>'refund_owed_now')::numeric = 20) = 1,
    'P1 G2: the Audit Log');
  perform pg_temp.t471_check(
        (select wallet_balance from customer_credit_statement(a) order by entry_date desc, entry_seq desc limit 1) = 0
    and (select count(*) from customer_credit_statement(a)
          where description = 'Adjustment — decrease — Held back by the invoice''s cancellation for whoever holds its benefits now' and credit_used = 20) = 1
    and (select count(*) from customer_credit_statement(a) where description like 'Credit returned%' and credit_added = 20) = 2,
    'P1 G2: the credit statement');
  -- P2 What is owed back grows by the money a refund by line of the row
  -- pays back for what is held back (S$20, S$18.18, S$14.00, S$13.64 for
  -- S$20 of credit): what the refund options offer, the Finance panel's and
  -- Cancel's refund due; the Finance panel keeps the rest for what was used;
  -- the Audit Log gives both. After the refund by line nothing is owed back.
  for o in select x from jsonb_array_elements('[["G2", "G3", 20], ["PCx", "PCxb", 18.18],
                                               ["PCv", "PCvb", 14], ["PCd", "PCdb", 13.64]]'::jsonb) x loop
    inv := pg_temp.t471_id('after/' || (o->>0) || '/inv'); m := pg_temp.t471_money(inv);
    perform pg_temp.t471_check((m->>'owed')::numeric = (o->>2)::numeric and (m->>'due')::numeric = (o->>2)::numeric
        and (m->>'by_line')::numeric = (o->>2)::numeric and (m->>'plan_due')::numeric = (o->>2)::numeric
        and (m->>'kept')::numeric = (m->>'net')::numeric - (o->>2)::numeric
        and (select count(*) from audit_logs al where al.record_id = inv and al.action = 'credit_given_back_followed'
              and (al.new_data->>'held_in_place')::boolean
              and (al.new_data->>'refund_owed')::numeric = 0 and (al.new_data->>'refund_owed_added')::numeric = (o->>2)::numeric
              and (al.new_data->>'refund_owed_now')::numeric = (o->>2)::numeric and (al.new_data->>'held_back')::numeric = 20) = 1,
      'P2 ' || (o->>0) || ': what is owed back is not what the refund by line can pay back: ' || m::text);
    inv := pg_temp.t471_id('after/' || (o->>1) || '/inv'); m := pg_temp.t471_money(inv);
    perform pg_temp.t471_check((m->>'owed')::numeric = 0 and (m->>'due')::numeric = 0 and (m->>'by_line')::numeric = 0
        and (m->>'kept')::numeric = (m->>'net')::numeric,
      'P2 ' || (o->>1) || ': after the refund by line something is still owed back: ' || m::text);
  end loop;
  -- P3 While a reopening waits, at commit: S2's refund goes back on A's lot
  -- (until the commit point), then is held back there and queued for the
  -- reopening's payment (its request), with the cancellation's own row
  -- queued at Reopen; paid: A S$80, nothing waiting or held back.
  perform pg_temp.t471_run('P', 'PWx', 'sale A cp; spend A; spend A; cancel; back 1 60; reopen');
  inv := pg_temp.t471_id('P/PWx/inv'); a := pg_temp.t471_id('P/PWx/A'); lot := pg_temp.t471_own_lot(inv);
  select q.request_id into v_req from invoice_reopen_benefits q where q.invoice_id = inv and q.applied_at is null limit 1;
  perform pg_temp.t471_check(pg_temp.t471_waiting(inv, lot) = '1/60.00/1', 'P3 PWx: before, the cancellation''s S$60 waits: ' || pg_temp.t471_waiting(inv, lot));
  perform pg_temp.t471_unspend(pg_temp.t471_id('P/PWx/S2'));
  perform pg_temp.t471_check((select remaining_amount from customer_credit_lots where id = lot) = 20, 'P3 PWx: the forwarder ran before the commit');
  perform pg_temp.t471_commit();
  perform pg_temp.t471_check((select remaining_amount from customer_credit_lots where id = lot) = 0
      and pg_temp.t471_own_lot(inv) = lot
      and pg_temp.t471_waiting(inv, lot) = '2/80.00/1'
      and not exists (select 1 from invoice_reopen_benefits q where q.invoice_id = inv and q.applied_at is null and q.request_id <> v_req)
      and (select cancelled_unused_value from invoice_benefit_values where id = pg_temp.t471_own(inv)) = 20
      and (select count(*) from audit_logs al where al.record_id = inv and al.action = 'credit_given_back_followed'
            and al.new_data->>'queued_for_request' = v_req::text and (al.new_data->>'held_in_place')::boolean) = 1
      and (invoice_reopen_preview(inv)->>'credit_to_reinstate_after_settlement')::numeric = 0,
    'P3 PWx: at commit it was not held back where it is and queued for the reopening''s payment: ' || pg_temp.t471_waiting(inv, lot));
  perform pg_temp.t471_pay(inv);
  perform pg_temp.t471_commit();
  perform pg_temp.t471_check((select sum(remaining_amount) from customer_credit_lots where customer_id = a) = 80
      and not exists (select 1 from invoice_reopen_benefits q where q.invoice_id = inv and q.applied_at is null)
      and (select cancelled_unused_value from invoice_benefit_values where id = pg_temp.t471_own(inv)) = 0
      and invoice_net_received(inv) = 100 and pg_temp.t471_invariants(inv) = '',
    'P3 PWx: the payment did not give A S$80');
  -- P4 446: a refund by line while the reopening waited closed the held-back
  -- row's queue row on the lot it names (PWb: S$20 refunded, the payment gave
  -- the S$60 alone).
  inv := pg_temp.t471_id('after/PWb/inv');
  perform pg_temp.t471_check((select count(*) from audit_logs al where al.record_id = inv and al.action = 'reopen_credit_refunded'
                               and al.new_data->>'benefit_id' = pg_temp.t471_own(inv)::text and (al.new_data->>'refunded_amount')::numeric = 20) = 1
      and exists (select 1 from invoice_reopen_benefits q join customer_credit_ledger x on x.id = q.source_ledger_id
                   where q.invoice_id = inv and x.reason like 'Held back by%' and q.applied_at is not null),
    'P4 PWb: 446''s matching did not find the held-back credit queued on the lot it names');
  -- P5 One held-back row for a 13-line sale's refund (13 rows given back at
  -- one commit), five for five refunds; all on the package's own lot, no lot
  -- reissued.
  inv := pg_temp.t471_id('after/L13p/inv'); lot := pg_temp.t471_own_lot(inv);
  perform pg_temp.t471_check(pg_temp.t471_held_n(lot) = 1 and pg_temp.t471_held(lot) = 65
      and (select count(*) from customer_credit_ledger x where x.lot_id = lot and x.entry_type = 'reverse' and x.source_type = 'invoice_payment_refund') = 13
      and lot = (select s.credit_lot_id from credit_package_sales s where s.invoice_id = inv),
    'P5 L13p: ' || pg_temp.t471_held_n(lot) || ' held-back rows');
  inv := pg_temp.t471_id('after/CH5p/inv'); lot := pg_temp.t471_own_lot(inv);
  perform pg_temp.t471_check(pg_temp.t471_held_n(lot) = 5 and pg_temp.t471_held(lot) = 25
      and lot = (select s.credit_lot_id from credit_package_sales s where s.invoice_id = inv)
      and (select count(*) from customer_credit_lots where customer_id = pg_temp.t471_id('after/CH5p/A')) = 1,
    'P5 CH5p: ' || pg_temp.t471_held_n(lot) || ' held-back rows');
  -- P6 The Reopen dialog's "credit to reinstate" counts what is held back:
  -- cancelled (S$60), S2 refunded (S$20 held back): S$80.
  perform pg_temp.t471_run('P', 'PRp', 'sale A cp; spend A; spend A; cancel; unspend S2');
  inv := pg_temp.t471_id('P/PRp/inv');
  perform pg_temp.t471_check((invoice_reopen_preview(inv)->>'credit_to_reinstate_after_settlement')::numeric = 80
      and (invoice_reopen_preview(inv)->>'can_reopen')::boolean,
    'P6 PRp: the Reopen dialog''s credit to reinstate is ' || (invoice_reopen_preview(inv)->>'credit_to_reinstate_after_settlement'));
  -- P7 Nothing more than before for the controls: nothing held back where
  -- the package stayed paid, where the session was refunded before the
  -- cancel, or where a correction moved nothing; and nothing forwarded (no
  -- lot reissued by the forwarder) in any case.
  perform pg_temp.t471_check(not exists (select 1 from customer_credit_ledger x
                   where x.source_record_id in (select pg_temp.t471_id('after/' || k || '/inv')
                                                from unnest(array['PP', 'PPr', 'PPf', 'PRF', 'LGp', 'PB', 'PFd', 'PTB', 'PTr2', 'PTp', 'PTpf', 'PTRp']) k)
                     and x.reason like 'Held back by%'),
    'P7 PP/PPr/PPf/PRF/LGp/PB/PFd/PTB/PTr2/PTp/PTpf/PTRp: something was held back');
  perform pg_temp.t471_check(not exists (select 1 from customer_credit_ledger x
                   where x.source_record_id in (select pg_temp.t471_id('after/' || k || '/inv') from t471_cases where k not in ('PTRh', 'PTRhp'))
                     and x.source_type like 'credit_given_back_reassignment_%'),
    'P7 a case forwarded credit to a new lot (other than PTRh and PTRhp, where the benefits are B''s)');
  -- P8 The buyer deleted while cancelled: held back where it is, on the
  -- deleted record's lot (no live record to give it to; before, it stayed
  -- there as credit of a deleted record).
  inv := pg_temp.t471_id('after/PDel/inv'); lot := pg_temp.t471_own_lot(inv);
  perform pg_temp.t471_check(pg_temp.t471_held(lot) = 20 and (select remaining_amount from customer_credit_lots where id = lot) = 0
      and (select deleted_at is not null from customers where id = pg_temp.t471_id('after/PDel/A')),
    'P8 PDel: not held back where it is');
  -- P9 (B) paid in part (PT1): held back as Cancel's write-off on the
  -- released lot (the release record's own lot, no lot made): closed again
  -- ('reversed', locked), one held-back row of S$20 (A's) after Cancel's own
  -- write-off row, the release record at S$0, nothing reads as used; the
  -- Audit Log says so (released credit, S$20 counted as spent before, S$0
  -- after, nothing owed back stated); A's statement ends at S$0. After a
  -- guided Cancel that stated S$0 owed back (PTg): S$0 -> S$20. The Premium
  -- Bundle's (PTv) the same on its own lot; the buyer merged before (PTmb):
  -- on the lot the merge made (K's).
  inv := pg_temp.t471_id('after/PT1/inv'); a := pg_temp.t471_id('after/PT1/A'); lot := pg_temp.t471_rel_lot(inv);
  perform pg_temp.t471_check(
        lot is not null and (select count(*) from customer_credit_lots where customer_id = a) = 1
    and (select remaining_amount from customer_credit_lots where id = lot) = 0
    and (select status from customer_credit_lots where id = lot) = 'reversed' and (select is_locked from customer_credit_lots where id = lot)
    and pg_temp.t471_held_rel(lot) = 20 and pg_temp.t471_held(lot) = 0
    and (select x.customer_id from customer_credit_ledger x where x.lot_id = lot and x.reason like 'Held back by%') = a
    and (select count(*) from customer_credit_ledger x where x.lot_id = lot and x.entry_type = 'adjust_decrease'
          and x.source_type = 'invoice_cancel_released_credit' and x.reason = 'T471 cancel' and x.amount = 20) = 1
    and (select released_amount from credit_package_progress_lots where lot_id = lot) = 0
    and cardinality(cancelled_invoice_used_value(inv)) = 0
    and not exists (select 1 from invoice_benefit_values where invoice_id = inv),
    'P9 PT1: not held back as Cancel''s write-off on the released lot');
  perform pg_temp.t471_check((select count(*) from audit_logs al where al.record_id = inv and al.action = 'credit_given_back_followed'
            and (al.new_data->>'held_in_place')::boolean and (al.new_data->>'released_credit')::boolean
            and (al.new_data->>'held_back')::numeric = 20 and (al.new_data->>'lot_id')::uuid = lot
            and (al.new_data->>'release_lot_id')::uuid = lot
            and (al.new_data->>'released_before')::numeric = 20 and (al.new_data->>'released_after')::numeric = 0
            and al.new_data->>'refund_owed' is null and al.new_data->>'refund_owed_added' is null) = 1,
    'P9 PT1: the Audit Log');
  perform pg_temp.t471_check(
        (select wallet_balance from customer_credit_statement(a) order by entry_date desc, entry_seq desc limit 1) = 0
    and (select count(*) from customer_credit_statement(a)
          where description = 'Adjustment — decrease — Held back by the invoice''s cancellation: credit released before it was paid in full' and credit_used = 20) = 1,
    'P9 PT1: the credit statement');
  inv := pg_temp.t471_id('after/PTg/inv');
  perform pg_temp.t471_check((select count(*) from audit_logs al where al.record_id = inv and al.action = 'credit_given_back_followed'
            and (al.new_data->>'released_credit')::boolean
            and (al.new_data->>'refund_owed')::numeric = 0 and (al.new_data->>'refund_owed_added')::numeric = 20
            and (al.new_data->>'refund_owed_now')::numeric = 20) = 1
      and (pg_temp.t471_money(inv)->>'kept')::numeric = 20,
    'P9 PTg: what is owed back did not grow S$1 for S$1 (S$0 -> S$20, S$20 kept): ' || pg_temp.t471_money(inv)::text);
  inv := pg_temp.t471_id('after/PTv/inv'); lot := pg_temp.t471_rel_lot(inv);
  perform pg_temp.t471_check(pg_temp.t471_held_rel(lot) = 20 and (select source_type from customer_credit_lots where id = lot) = 'premium_bundle',
    'P9 PTv: not held back on the bundle''s released lot');
  inv := pg_temp.t471_id('after/PTmb/inv');
  perform pg_temp.t471_check((select sum(pg_temp.t471_held_rel(l.id)) from customer_credit_lots l
                               where l.customer_id = pg_temp.t471_id('after/PTmb/K')) = 20
      and (select coalesce(sum(remaining_amount), 0) from customer_credit_lots where customer_id = pg_temp.t471_id('after/PTmb/K')) = 0,
    'P9 PTmb: not held back on the lot the merge made');
  -- P10 Reopened and paid in full after a part payment (PTRc): the released
  -- lot the first Cancel's write-off closed is the one a benefit row names
  -- ('active' again by S1's refund, still locked); held back there (one
  -- held-back row of S$20, no lot made, the row holds back S$20, the Audit
  -- Log in place). With the benefits B's while paid (PTRhp): forwarded to B
  -- as one new lot that replaces it (the records name the new lot), A
  -- holds nothing; the lot stays locked at S$0.
  inv := pg_temp.t471_id('after/PTRc/inv'); a := pg_temp.t471_id('after/PTRc/A'); lot := pg_temp.t471_closed_lot(inv);
  perform pg_temp.t471_check(
        lot is not null
    and exists (select 1 from invoice_benefit_values bv where bv.invoice_id = inv and bv.lot_id = lot and bv.cancelled_unused_value = 20)
    and (select status from customer_credit_lots where id = lot) = 'active' and (select is_locked from customer_credit_lots where id = lot)
    and (select remaining_amount from customer_credit_lots where id = lot) = 0
    and pg_temp.t471_held_n(lot) = 1 and pg_temp.t471_held(lot) = 20 and pg_temp.t471_held_rel(lot) = 0
    and not exists (select 1 from customer_credit_ledger x where x.source_record_id = inv and x.source_type like 'credit_given_back_reassignment_%')
    and (select count(*) from audit_logs al where al.record_id = inv and al.action = 'credit_given_back_followed'
          and (al.new_data->>'held_in_place')::boolean and (al.new_data->>'lot_id')::uuid = lot
          and (al.new_data->>'held_back')::numeric = 20 and al.new_data->>'to_customer' = a::text) = 1,
    'P10 PTRc: not held back where it is on the released lot the Cancel closed');
  inv := pg_temp.t471_id('after/PTRhp/inv'); lot := pg_temp.t471_closed_lot(inv);
  perform pg_temp.t471_check(
        (select remaining_amount from customer_credit_lots where id = lot) = 0 and (select is_locked from customer_credit_lots where id = lot)
    and not exists (select 1 from invoice_benefit_values bv where bv.invoice_id = inv and bv.lot_id = lot)
    and exists (select 1 from invoice_benefit_values bv join customer_credit_lots l on l.id = bv.lot_id
                 where bv.invoice_id = inv and l.reassigned_from_lot_id = lot and l.customer_id = pg_temp.t471_id('after/PTRhp/B')
                   and l.remaining_amount = 20 and not l.is_locked)
    and (select count(*) from audit_logs al where al.record_id = inv and al.action = 'credit_given_back_followed'
          and (al.new_data->>'replaces_lot_id')::uuid = lot and al.new_data->>'held_back' is null) = 1
    and (select coalesce(sum(remaining_amount), 0) from customer_credit_lots where customer_id = pg_temp.t471_id('after/PTRhp/A')) = 0,
    'P10 PTRhp: not forwarded to B from the released lot the Cancel closed');
  raise notice 'PASS P: G2 held back where it is (the package''s own lot, one held-back row, no lot reissued, the Audit Log, the statement at S$0); the amount owed back grows by the money a refund by line pays back (G2 S$20, PCx S$18.18, PCv S$14.00, PCd S$13.64: the refund options, refund due and Cancel''s), nothing owed back after the refund by line; while a reopening waits, held back at commit and queued for its payment, which gives it to A (PWx); 446''s matching found it (PWb); one held-back row for a 13-line refund, five for five; the Reopen dialog counts it (S$80); nothing more for the controls, nothing forwarded; the buyer deleted: held back in place; paid in part (PT1) held back as Cancel''s write-off on the released lot (closed again, the release record at S$0, nothing used, the Audit Log, the statement), a guided Cancel''s S$0 owed back -> S$20 (PTg), the bundle (PTv), the lot a merge made (PTmb); reopened and paid in full after a part payment, held back on the released lot the Cancel closed (PTRc) or forwarded from it to B (PTRhp)';
end $$;

-- ===== K. KNOWN: 471's NOT COVERED (each checked as it is) =====
do $$
declare o jsonb; inv uuid; lot uuid;
begin
  -- K1 (NOT COVERED 1; 470's 2, accepted): RX0 ends as RX1: held back (S$20),
  -- owed to nobody (net S$0, refunded); the Finance panel offers S$20 by
  -- line, and that refund is refused.
  inv := pg_temp.t471_id('after/RX0/inv');
  perform pg_temp.t471_check((select cancelled_unused_value from invoice_benefit_values where id = pg_temp.t471_own(inv)) = 20
      and invoice_net_received(inv) = 0 and (pg_temp.t471_money(inv)->>'by_line')::numeric = 20,
    'K1 RX0: look at NOT COVERED 1 again');
  o := pg_temp.t471_run('K', 'RX0b', 'sale A cp; spend A; backx 1; unspend S1; back 1 all');
  perform pg_temp.t471_check(o->>'error' like 'back 1 all: %' and (o->>'held')::numeric = 20 and (o->>'net')::numeric = 0,
    'K1 RX0b: the refund by line was not refused: ' || o::text);
  -- K2 (NOT COVERED 2; 470's 3, accepted): not spendable while a reopening
  -- waits (PWs).
  perform pg_temp.t471_check((select v->>'error' from t471_res where phase = 'after' and k = 'PWs') like 'spend A: Only 0 of the requested 20.00 could be funded by eligible credit%',
    'K2 PWs: look at NOT COVERED 2 again');
  -- K3 (NOT COVERED 3; 445's 1): a merge of the buyer is refused, after the
  -- hold as before it (PM, PMg).
  perform pg_temp.t471_check((select v->>'error' from t471_res where phase = 'after' and k = 'PM') like 'merge K A: Credit allocations cannot be changed once recorded%'
      and (select v->>'error' from t471_res where phase = 'after' and k = 'PMg') like 'merge K A: Credit allocations cannot be changed once recorded%',
    'K3 PM: look at NOT COVERED 3 again');
  -- K4 (NOT COVERED 4): credit given back before 471 stays spendable (M:
  -- MG2a A S$20; MG2b the refund by line still refused; MPWx A spent it).
  if exists (select 1 from t471_res where phase = 'mid' and k = 'MG2a') then
    perform pg_temp.t471_check((select v->'holds'->>'A' from t471_res where phase = 'mid' and k = 'MG2a') = '20.00'
        and (select v->>'error' from t471_res where phase = 'mid' and k = 'MG2b') like 'back 1 all: That is more than the S$0.00 still owed back%',
      'K4 MG2a: look at NOT COVERED 4 again');
    -- behind the lot the records name: A's S$20 given back before 471 is
    -- not repaired (MHQ3s A spent it; MHQ3r reopened and paid: A S$20, B
    -- S$80, Cancel leaves A's S$20).
    perform pg_temp.t471_check((select v->>'error' from t471_res where phase = 'mid' and k = 'MHQ3s') is null
        and (select v->'holds' from t471_res where phase = 'mid' and k = 'MHQ3r') @> '{"A":"20.00","B":"80.00"}'
        and (select (v->>'cancel_left')::numeric from t471_res where phase = 'mid' and k = 'MHQ3r') = 20,
      'K4 MHQ3s/MHQ3r: look at NOT COVERED 4 again');
  end if;
  -- K5 (NOT COVERED 7): cancelled, S$60 refunded by line, reopened (S$60
  -- queued), S2 refunded while it waits (S$20 held back, queued for that
  -- reopening), cancelled again: the Reopen dialog's credit to reinstate
  -- leaves out what the earlier reopening queued (S$0.00 shown); reopened
  -- and paid, A holds S$80.
  perform pg_temp.t471_run('K', 'RD', 'sale A cp; spend A; spend A; cancel; back 1 60; reopen; unspend S2; cancel', 1, 8);
  inv := pg_temp.t471_id('K/RD/inv');
  perform pg_temp.t471_check((select err from t471_err where pre = 'K/RD') is null
      and (invoice_reopen_preview(inv)->>'credit_to_reinstate_after_settlement')::numeric = 0
      and (select coalesce(sum(q.amount), 0) from invoice_reopen_benefits q where q.invoice_id = inv and q.applied_at is null) = 80,
    'K5 RD: look at NOT COVERED 7 again (the dialog says ' || coalesce(invoice_reopen_preview(inv)->>'credit_to_reinstate_after_settlement', '?') || ')');
  o := pg_temp.t471_run('K', 'RD', 'sale A cp; spend A; spend A; cancel; back 1 60; reopen; unspend S2; cancel; reopen; pay', 9);
  perform pg_temp.t471_check(o->'holds' @> '{"A":"80.00"}' and o->>'status' = 'paid' and coalesce(o->>'invariants', '') = '',
    'K5 RD: the payment did not give A S$80: ' || o::text);
  -- K6 (NOT COVERED 4): a refund in full with an Owner's override that took
  -- back S$30 of the S$80 unused credit (refunded, S$50 left on the lot),
  -- then S1 refunded: all S$70 held back, owed to nobody.
  o := pg_temp.t471_run('K', 'OV', 'sale A cp; spend A; backo 1 30', 1, 3);
  inv := pg_temp.t471_id('K/OV/inv');
  perform pg_temp.t471_check((select status::text from invoices where id = inv) = 'refunded'
      and (select remaining_amount from customer_credit_lots where id = pg_temp.t471_own_lot(inv)) = 50,
    'K6 OV: the override refund did not leave S$50 on a refunded package');
  o := pg_temp.t471_run('K', 'OV', 'sale A cp; spend A; backo 1 30; unspend S1', 4);
  perform pg_temp.t471_check(o->'holds' @> '{"A":"0.00"}' and o->>'status' = 'refunded' and (o->>'held')::numeric = 70
      and (o->>'net')::numeric = 0 and o->>'owed' is null and pg_temp.t471_held(pg_temp.t471_own_lot(inv)) = 70,
    'K6 OV: look at NOT COVERED 4 again: ' || o::text);
  -- K8 (NOT COVERED 8): paid in part, S$1 owed back for each S$1 held back,
  -- also where the money paid was more than the paid credit released (the
  -- Premium Bundle S$120 of S$140 released S$100: S$100 owed, S$20 kept); a
  -- guided Cancel of a part-paid package states S$0 owed back (PTg: then
  -- S$20); reopened before S1's refund, nothing is held (PTr2: A S$40).
  o := pg_temp.t471_run('K', 'CAP', 'sale A pbv 120; spend A 5 bwallet; guidedkeep; unspend S1');
  perform pg_temp.t471_check(o->>'error' is null and o->'holds' @> '{"A":"0.00"}' and (o->>'owed')::numeric = 100
      and (o->>'net')::numeric = 120 and (pg_temp.t471_money(pg_temp.t471_id('K/CAP/inv'))->>'kept')::numeric = 20,
    'K8 CAP: look at NOT COVERED 8 again: ' || o::text);
  perform pg_temp.t471_check((select (v->>'owed')::numeric from t471_res where phase = 'after' and k = 'PTg') = 20
      and (select v->'holds' from t471_res where phase = 'after' and k = 'PTr2') @> '{"A":"40.00"}',
    'K8 PTg/PTr2: look at NOT COVERED 8 again');
  -- K9 (NOT COVERED 9): paid in part, both S$20 sessions paid from its
  -- released credit, cancelled, reopened and paid in full: a 'transfer'
  -- customer change is allowed (the released lot the Cancel closed does not
  -- read as "Partly spent"; B gets the S$60 left), where the paid-in-full
  -- package with the same spending is refused (invoice_transferable_benefits,
  -- pinned; the same with and without 471).
  o := pg_temp.t471_run('K', 'TQ', 'sale A cp 40; spend A; spend A; cancel; reopen; pay; change B');
  perform pg_temp.t471_check(o->>'error' is null and o->'holds' @> '{"A":"0.00","B":"60.00"}' and o->>'status' = 'paid',
    'K9 TQ: look at NOT COVERED 9 again: ' || o::text);
  o := pg_temp.t471_run('K', 'TQc', 'sale A cp; spend A; spend A; change B');
  perform pg_temp.t471_check(o->>'error' like 'change B: These benefits have already been used and cannot move with the invoice: Paid credit 60.00 (Partly spent)%',
    'K9 TQc: the paid-in-full control was not refused: ' || o::text);
  -- K10 (NOT COVERED 10): a lot an Owner reversed, opened again by a
  -- session's refund, is passed over: the credit stays spendable on a
  -- cancelled package (PX: A S$20 on the package's own lot, 'active',
  -- locked, its 'reversal' row, nothing held back; PXs A spent it; S8gb and
  -- S2gb the refund by line refused at S$0.00 owed back; S8gs A spent it).
  -- Its copy (O1): B's lot, reissued by the reopening's payment, locked with
  -- no reversal row of its own, held back where it is (S$20), the lot it
  -- copies keeping its reversal row.
  inv := pg_temp.t471_id('after/PX/inv'); lot := pg_temp.t471_own_lot(inv);
  perform pg_temp.t471_check(
        (select remaining_amount from customer_credit_lots where id = lot) = 20
    and (select status from customer_credit_lots where id = lot) = 'active' and (select is_locked from customer_credit_lots where id = lot)
    and exists (select 1 from customer_credit_ledger e where e.lot_id = lot and e.source_type = 'reversal')
    and pg_temp.t471_held(lot) = 0
    and (select v->'holds'->>'A' from t471_res where phase = 'after' and k = 'PXs') = '0.00'
    and (select v->>'error' from t471_res where phase = 'after' and k = 'PXs') is null
    and (select v->>'error' from t471_res where phase = 'after' and k = 'S8gb') like 'back 1 all: That is more than the S$0.00 still owed back%'
    and (select v->>'error' from t471_res where phase = 'after' and k = 'S2gb') like 'back 1 all: That is more than the S$0.00 still owed back%'
    and (select v->>'error' from t471_res where phase = 'after' and k = 'S8gs') is null,
    'K10 PX/S8gb/S2gb: look at NOT COVERED 10 again');
  -- (the package has two benefit rows once paid in full after a part
  -- payment: the released lot's, which a reissue copied with its lock, and
  -- the rest's)
  inv := pg_temp.t471_id('after/O1/inv');
  select bv.lot_id into lot from invoice_benefit_values bv join customer_credit_lots l on l.id = bv.lot_id
   where bv.invoice_id = inv and l.is_locked;
  perform pg_temp.t471_check(
        (select customer_id from customer_credit_lots where id = lot) = pg_temp.t471_id('after/O1/B')
    and (select is_locked from customer_credit_lots where id = lot)
    and not exists (select 1 from customer_credit_ledger e where e.lot_id = lot and e.source_type = 'reversal')
    and pg_temp.t471_held(lot) = 20 and (select remaining_amount from customer_credit_lots where id = lot) = 0
    and exists (select 1 from customer_credit_lots l join customer_credit_ledger e on e.lot_id = l.id and e.source_type = 'reversal'
                 where l.id = any (credit_lot_ancestry(lot)) and l.customer_id = pg_temp.t471_id('after/O1/A')),
    'K10 O1: B''s copy of the lot an Owner reversed was not read as Cancel''s write-off''s (held back there)');
  raise notice 'KNOWN K: (471''s NOT COVERED) (1) RX0 held back, owed to nobody, its refund by line refused (as RX1); (2) not spendable while a reopening waits (PWs); (3) a merge of the buyer refused (PM, PMg; 445''s NOT COVERED 1); (4) credit given back before 471 left spendable until the next refund or correction of a sale paid from that lot%, and credit an override''s refund left held back with the next (K6: S$70, owed to nobody); (7) the Reopen dialog leaves out credit queued for an earlier reopening (K5: S$0.00 shown, A S$80 paid); (8) paid in part, S$1 owed back for S$1 also past the paid credit (K8: S$100 owed of S$120, S$20 kept), a guided Cancel''s S$0 then S$20 (PTg), nothing held once reopened (PTr2); (9) a ''transfer'' change allowed though credit released before full payment was spent (K9: B S$60), the paid-in-full control refused; (10) a lot an Owner reversed passed over, its credit given back spendable on a cancelled package (PX, PXs; S8gb, S2gb the refund by line refused), its copy read as Cancel''s write-off''s (O1: S$20 held back on it)',
    case when exists (select 1 from t471_res where phase = 'mid' and k = 'MG2a') then ' (MG2a, MG2b, MPWx; MPTs)' else ' (not tried: -v nomig=1)' end;
end $$;

rollback;
