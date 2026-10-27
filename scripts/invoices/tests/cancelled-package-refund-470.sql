-- 470: credit a refunded sale gives back while its package is cancelled,
-- refunded or waiting for its reopening's payment is held back by the
-- cancellation for whoever holds the package's benefits, on the lot the
-- records name, so a refund by line of the package pays it back and the
-- reopening's payment gives it to them (462's NOT COVERED 10, K7b; the
-- Owner, 24 Oct 2026: "Go live now, fix the gap next").
-- supabase/470_cancelled_package_refund_reaches_given_back_credit.sql (after 462 and 463).
--
-- Every step goes through the app's own calls (462's suite harness): the
-- invoice form (create_invoice_with_details) and the Pay dialog
-- (record_invoice_settlement), Record Payment, Cancel, the Finance panel's
-- refund by line and "Record refund paid" (refund_invoice_recorded), its
-- Correct payment (correct_invoice_payment), Reopen, Move
-- (transfer_invoice_unused_benefit), the guided Refund in full and Cancel
-- (invoice_action_plan, request_invoice_action_v2, resolve_invoice_action_v2,
-- "Record refund paid" ticked), the invoice form's customer change
-- (correct_invoice, 'transfer'), a customer merge, Delete customer; a special
-- document's wallet payment is 462's stand-in, its refund the real
-- refund_special_credit; the legacy statuses are set directly (a stand-in: no
-- page sets them any more). Each app call is followed by what its commit
-- does: 462's trigger on the ledger is DEFERRABLE INITIALLY DEFERRED, and this
-- suite is one transaction, so its queued rows are run at that point (SET
-- CONSTRAINTS ... IMMEDIATE, then DEFERRED again). 470 adds no trigger.
--
-- The cases (A the buyer; B, C later customers; K a record a merge keeps; F
-- a friend an Owner moved credit to; cp a S$100 Credit Package, cpb one with
-- a S$10 Bonus, pbv the S$140 Premium Bundle (S$100 Paid and S$40 Bonus
-- credit, two vouchers); S1, S2 S$20 sessions paid from the package's
-- credit; the common start: the package sold to A, two sessions paid from
-- it, the S$60 left moved to F, the customer changed to B with 'transfer',
-- S1 refunded: B S$20):
--   K7b   cancelled, S2 refunded while cancelled, the package refunded by
--         line ('back 1 all'): 462's KNOWN K7b. K7p the state before the
--         refund; K7n2 three sessions; K7bx the S$100 + S$10 package; K7b2
--         S$10 refunded by line first; SS4 a special document's credit.
--   K7mb, K7mr, K7cm, K7cc, K7cb  the merge and change siblings: the new
--         holder merged before the cancel (and a merge of the buyer before
--         the sessions), a merge or a customer change while cancelled (after
--         or before S2's refund).
--   K7rp, K7g  cancelled, S2 refunded, then "Record refund paid" (the app
--         asks for the refund by line on a package) or the guided Refund in
--         full (refused: already cancelled): nothing stranded meanwhile.
--   K7gc, K7gcb, K7gcr  the guided Cancel with "Record refund paid", S2
--         refunded (then refunded by line; then reopened and paid).
--         K7gcx, K7gcbx (cpb), K7gcv, K7gcbv (pbv), K7gcd, K7gcbd (pbv S$7
--         off): the same with a third session, where S$20 of credit is worth
--         less than S$20 (S$18.18, S$14.00, S$13.64).
--   K7fc, K7fa  Correct payment of S2 (to cash; S$5 less) instead of its
--         refund; K7fd the date only (a control).
--   RX1   the package refunded by line in full with an Owner's
--         'larger_refund' (status 'refunded'), then S2 refunded.
--   K7wc, K7wg, K7w2, K7wfa  cancelled, F's S$60 refunded, reopened (it
--         waits), S2 refunded while it waits: then cancelled again and
--         refunded by line; the guided Refund in full; B tries to spend it;
--         S2's payment corrected to S$5 less instead, refunded by line, paid.
--         K7c2: B tries to spend it while cancelled.
--   Z1, Z2, Z5  S2 refunded while cancelled, F's S$60 refunded, reopened (it
--         waits), B's part refunded by line while it waits (all, S$20; then
--         Refund in full after the payment): 446's matching. Z1w, Z1wr the
--         same with S2 refunded while it waits. M1, M1p a merge while
--         cancelled after S2's refund (then the same wait and refund).
--   CH5   five sessions refunded while cancelled (the chain stays short).
--   DHc, DHr  the holder deleted while cancelled (held back for the customer
--         it went back to: then refunded by line, or reopened and paid).
--   LG1, LG2  asked to be cancelled or refunded (the legacy statuses): S2
--         refunded follows as for a paid invoice.
--   Z3    changed (consistent before and after, another answer): S2
--         refunded while cancelled, S$10 refunded, reopened, refunded by
--         line while it waits, paid.
--   Controls (the same with and without 470): K7r (462's X2p), K7rr, K7w,
--   K7wf, K7wch, K7wm, K7wcr, K7b3, Z4, M2, G1, W2, K7cmr, K7cbr, K7fd, K7gr,
--   L13c, L13w, and without a reissue C0, C0r, C1, C2, G2, G3.
-- In every case (462's invariants): no lot of the invoice's family holds
-- credit unless a record names it; each lot's balance is its ledger's; no
-- chain over 12; moved lots traced; origins kept; a named lot holding credit
-- is held by whoever holds the benefits; no benefit row holds back more than
-- it granted, nor anything once settled with no reopening waiting; a
-- refunded invoice leaves no credit; and Cancel (tried, undone) takes all of
-- the invoice's credit back from whoever holds it.
--
--   S. Where it starts: 462 and 463 in, the triggers on invoices as read;
--      470 in (nomig) or not, the forwarder at 463's AFTER.
--   R. Without 470 (skipped with -v nomig=1), undone: each 'fixed' case ends
--      otherwise (the fault reproduced); each control as expected; 'changed'
--      its old answer.
--   Q. The read-only query in 470's header (the same text), on those states:
--      what it lists, by reason; the controls not listed under 1 and 2.
--   9. Refusals, each changing nothing: the R states (credit on a lot the
--      records replaced: exactly the invoices Q lists under 1); a
--      cancellation's rows on a replaced lot (a stand-in); a function it
--      relies on not as tested; a new reader of a cancellation's rows; a new
--      trigger on invoices; the forwarder not as tested; an overload of its
--      name. The same grants in another order do not stop it.
--   M. The mid set: begun before 470 (cancelled; waiting, before S2's
--      refund), finished after it.
--  10. 470 installed twice: as tested, the second run changing nothing,
--      nothing added (no function, no trigger), the grants as before.
--   A. Each case after 470: who holds what, the plans' codes and refund due,
--      the invariants, Cancel; the controls exactly as before 470.
--   P. Probes: the held-back rows and the statements (K7p); the amount owed
--      back, by the money a refund by line pays back for what is held back
--      (K7gc, K7gcx, K7gcv, K7gcd: what the refund options offer, the Finance
--      panel's and Cancel's refund due; nothing owed back after the refund by
--      line, K7gcb, K7gcbx, K7gcbv, K7gcbd); 446's matching (Z1, M1, Z1w);
--      the chain (CH5); held back and queued at commit while a reopening
--      waits, then given by its payment (K7wx); nothing more for the
--      controls; every record deleted:
--      refused at commit; no event left on invoices (ALTER TABLE invoices with
--      a reopened invoice paid in the same transaction).
--   K. KNOWN (not covered by 470), checked as they are: no reissue (G2, G3,
--      RX0: NOT COVERED 1); held back on a refunded invoice, owed to nobody
--      (RX1: NOT COVERED 2); not spendable while a reopening waits (K7w2: NOT
--      COVERED 3).
--
-- Run on a copy of production as it is (469 in, 26 Oct 2026: f9d0ddcb,
-- 1387 functions; built on 463 with 466 and 467, 6d96407c, before 468 and
-- 469 went in, which changed none of what this reads):
--   psql -X -v ON_ERROR_STOP=1 -f scripts/invoices/tests/cancelled-package-refund-470.sql
-- It installs 470 itself (twice) inside its transaction. Where 470 is in
-- already, add -v nomig=1 (S checks it as tested; R, Q, 9 and M are skipped;
-- every case after 470 is still checked). Sections 9 let the install fail on
-- purpose (psql prints its ERROR); the suite then checks that message.
-- Where 471 is in too (-v nomig=1; the Owner, 26 Oct 2026, answering NOT
-- COVERED 1: "Yes, fix it after 470"), the forwarder is at 471's AFTER (S),
-- and without a reissue credit given back while the package is cancelled or
-- refunded is held back too, in place: G2 and G3 (controls here) and KNOWN K
-- (1) end the 471 way (A holds nothing; G3 pays it all back; RX0 ends as
-- RX1), and P6 finds C0's held-back row on A's own lot. Every other case
-- ends as with 470 alone. 471's own suite
-- (plain-cancelled-package-credit-471) checks those cases and their siblings.
-- Where 472 is in too (-v nomig=1; the Owner, 26 Oct 2026: "fix the
-- leftover gaps too"), the forwarder is at 472's AFTER (S); 472 changes only
-- credit given back on a lot an Owner reversed, or behind a closed lot the
-- records name, which no case here has, so every case ends as with 471
-- (472's suite, reversed-lot-credit-held-back-472, checks those).
-- Disposable database only; everything is rolled back. Every name, code and
-- amount is invented (@example.com); the phones are numbers kept for fiction
-- (ACMA, +61491570000 to +61491570999).
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '10s';
set local statement_timeout = '900s';

-- ── Set-up and the app's calls (462's suite harness, for 470) ─────────────────────────
create temp table t470(k text primary key, id uuid);
create temp table t470_res(phase text, k text, v jsonb, primary key (phase, k));
create temp sequence t470_phone;
create function pg_temp.t470_id(p_k text) returns uuid language sql as $f$ select id from t470 where k = p_k $f$;
create function pg_temp.t470_put(p_k text, p_id uuid) returns uuid language sql as $f$
  insert into t470 values (p_k, p_id) on conflict (k) do update set id = excluded.id returning id $f$;
create function pg_temp.t470_check(p_ok boolean, p_label text) returns void language plpgsql as $f$
begin
  if not coalesce(p_ok, false) then raise exception 'FAIL %', p_label; end if;
end $f$;
create function pg_temp.t470_fingerprint() returns text language sql as $f$
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.oid::regprocedure::text)) || ' ' || count(*)
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prokind in ('f', 'p') $f$;
create function pg_temp.t470_463_in() returns boolean language sql as $f$
  select to_regprocedure('public.invoice_benefit_moved_to_other(uuid)') is not null $f$;
create function pg_temp.t470_462_in() returns boolean language sql as $f$
  select to_regprocedure('public.credit_given_back_follows(uuid)') is not null
     and exists (select 1 from pg_trigger where tgname = 'credit_given_back_follows'
                  and tgrelid = 'public.customer_credit_ledger'::regclass) $f$;
-- 470 is in: the forwarder is 470's (its text says so; S checks its md5).
create function pg_temp.t470_in() returns boolean language sql as $f$
  select to_regprocedure('public.credit_given_back_follows(uuid)') is not null
     and position('-- 470 (the Owner, 24 Oct 2026' in pg_get_functiondef('public.credit_given_back_follows(uuid)'::regprocedure)) > 0 $f$;
-- 471 is in too: the forwarder is 471's (its text says so; S checks its md5;
-- 472's keeps 471's text).
create function pg_temp.t470_471_in() returns boolean language sql as $f$
  select to_regprocedure('public.credit_given_back_follows(uuid)') is not null
     and position('-- 471 (the Owner, 26 Oct 2026' in pg_get_functiondef('public.credit_given_back_follows(uuid)'::regprocedure)) > 0 $f$;
-- 472 is in too: the forwarder is 472's (its text says so; S checks its md5).
create function pg_temp.t470_472_in() returns boolean language sql as $f$
  select to_regprocedure('public.credit_given_back_follows(uuid)') is not null
     and position('-- 472 (the Owner, 26 Oct 2026' in pg_get_functiondef('public.credit_given_back_follows(uuid)'::regprocedure)) > 0 $f$;
-- What a commit does at the end of each app call (each is its own
-- transaction in the app): 462's deferred trigger on the ledger runs (470
-- adds no trigger: its change is in the function that trigger runs). Here
-- the suite is one transaction, so the trigger's queued rows are run at this
-- point. (Not where each step really commits: t470.autocommit 'on', for
-- running the same cases one call per transaction on a disposable copy.)
create function pg_temp.t470_commit() returns void language plpgsql as $f$
begin
  if coalesce(current_setting('t470.autocommit', true), '') = 'on' then return; end if;
  if pg_temp.t470_462_in() then
    execute 'set constraints public.credit_given_back_follows immediate';
    execute 'set constraints public.credit_given_back_follows deferred';
  end if;
end $f$;

do $$
declare own uuid := gen_random_uuid(); st uuid; st2 uuid; pm uuid; v uuid; cp uuid; cpb uuid; pbv uuid; svc uuid; svc5 uuid;
begin
  insert into auth.users(id, email) values (own, 't470-owner@example.com');
  insert into profiles(id, full_name, email, role, is_active) values (own, 'T470 Owner', 't470-owner@example.com', 'owner', true);
  perform set_config('request.jwt.claims', json_build_object('sub', own, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', own::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  insert into stores(name, code, country_code) values ('T470 Store', 'T470S1', 'SG') returning id into st;
  insert into stores(name, code, country_code) values ('T470 Other Store', 'T470S2', 'SG') returning id into st2;
  insert into payment_methods(name, is_active) values ('T470 Cash', true) returning id into pm;
  insert into vouchers(name, code, voucher_kind, qty_type, selling_price, is_active)
    values ('T470 Plain 30', 'T470-P30', 'normal', 'unlimited', 30, true) returning id into v;
  insert into voucher_store_prices(voucher_id, store_id, selling_price, available_at_store) values (v, st, 30, true), (v, st2, 30, true);
  insert into credit_packages(name, customer_price, paid_credit_amount, bonus_enabled, allow_product, allow_therapy)
    values ('T470 S$100', 100, 100, false, true, true) returning id into cp;
  insert into credit_package_stores(package_id, store_id) values (cp, st), (cp, st2);
  insert into credit_packages(name, customer_price, paid_credit_amount, bonus_enabled, bonus_value, allow_product, allow_therapy, grants_reward)
    values ('T470 S$100 + S$10', 100, 100, true, 10, true, true, false) returning id into cpb;
  insert into credit_package_stores(package_id, store_id) values (cpb, st), (cpb, st2);
  insert into premium_bundles(name, customer_payment_amount, paid_credit_amount, bonus_credit_amount, free_voucher_qty, grants_reward)
    values ('T470 Bundle S$140 + 2 vouchers', 140, 100, 40, 2, true) returning id into pbv;
  insert into premium_bundle_stores(bundle_id, store_id) values (pbv, st), (pbv, st2);
  insert into premium_bundle_vouchers(bundle_id, voucher_id) values (pbv, v);
  svc := (upsert_therapy_service(null, 'T470-SESSION', 'T470 Session', 20, 30, 'per_hours', 1, 5, null, true, null) ->> 'id')::uuid;
  perform set_therapy_service_store(svc, st, true, null);
  svc5 := (upsert_therapy_service(null, 'T470-SHORT', 'T470 Short session', 5, 15, 'per_hours', 1, 5, null, true, null) ->> 'id')::uuid;
  perform set_therapy_service_store(svc5, st, true, null);
  insert into t470 values ('own', own), ('store', st), ('store2', st2), ('pm', pm), ('v', v), ('cp', cp), ('cpb', cpb), ('pbv', pbv),
    ('svc', svc), ('svc5', svc5),
    ('wallet', (select id from payment_methods where name = 'Wallet — Credit Package Paid' and is_wallet_credit and deleted_at is null)),
    ('bwallet', (select id from payment_methods where name = 'Wallet — Premium Bundle Paid' and is_wallet_credit and deleted_at is null));
  perform pg_temp.t470_check(pg_temp.t470_id('wallet') is not null and pg_temp.t470_id('bwallet') is not null, 'setup: the wallet methods (443) are there');
end $$;

-- A customer of one run of one case: '<phase>/<case>/<role>'.
create function pg_temp.t470_cust(p_k text) returns uuid language plpgsql as $f$
declare c uuid;
begin
  insert into customers(full_name, phone) values ('T470 ' || p_k, '+61491570' || lpad((nextval('t470_phone') % 1000)::text, 3, '0'))
    returning id into c;
  return pg_temp.t470_put(p_k, c);
end $f$;
-- The invoice form with these lines ('cp' / 'cpb' a Credit Package, 'pbv' the
-- Premium Bundle, 'v' a voucher line of p_qty units), with an Owner's manual
-- discount of p_discount (its reason given) where one is given, paid through
-- the Pay dialog: in full, or p_first of it (a part-paid package).
create function pg_temp.t470_sale(p_cust uuid, p_kinds text[], p_first numeric default null, p_qty int default 2,
                                  p_discount numeric default null)
  returns uuid language plpgsql as $f$
declare inv uuid; v_lines jsonb := '[]'; i int;
begin
  for i in 1 .. cardinality(p_kinds) loop
    v_lines := v_lines || jsonb_build_array(case
      when p_kinds[i] = 'v' then jsonb_build_object('kind', 'voucher', 'voucher_id', pg_temp.t470_id('v'), 'quantity', p_qty)
      when p_kinds[i] in ('cp', 'cpb') then jsonb_build_object('kind', 'credit_package', 'credit_package_id', pg_temp.t470_id(p_kinds[i]), 'quantity', 1)
      else jsonb_build_object('kind', 'premium_bundle', 'premium_bundle_id', pg_temp.t470_id('pbv'), 'quantity', 1,
        'voucher_selection', jsonb_build_array(jsonb_build_object('voucher_id', pg_temp.t470_id('v'), 'quantity', 2))) end);
  end loop;
  inv := create_invoice_with_details(pg_temp.t470_id('store'), p_cust, v_lines, jsonb_build_object('business_date', sg_today()::text)
           || case when p_discount is not null
                   then jsonb_build_object('manual_discount', p_discount, 'manual_discount_reason', 'T470 discount') else '{}'::jsonb end);
  perform record_invoice_settlement(inv, jsonb_build_object('receipts', jsonb_build_array(jsonb_build_object(
    'key', 'line-0', 'payment_method_id', pg_temp.t470_id('pm'),
    'amount', coalesce(p_first, (select total_amount from invoices where id = inv)),
    'payment_date', sg_today()::text)), 'arrangements', '[]'::jsonb), gen_random_uuid());
  return inv;
end $f$;
-- Record Payment of what is outstanding (nothing when it is settled).
create function pg_temp.t470_pay(p_inv uuid) returns void language plpgsql as $f$
begin
  if (invoice_financial_position(p_inv)->>'outstanding')::numeric > 0 then
    perform record_invoice_payment(p_inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.t470_id('pm'),
      'amount', (invoice_financial_position(p_inv)->>'outstanding')::numeric)), gen_random_uuid());
  end if;
end $f$;
-- The receipts that still hold p_amount between them, as the Finance panel
-- splits a refund across them.
create function pg_temp.t470_sources(p_inv uuid, p_amount numeric) returns jsonb language plpgsql as $f$
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
create function pg_temp.t470_line(p_inv uuid, p_n int default 1) returns uuid language sql as $f$
  select id from invoice_items where invoice_id = p_inv order by id offset p_n - 1 limit 1 $f$;
-- The Finance panel's refund by line of line p_n: p_amount off its Paid
-- benefit (the one an Owner did not move, or with p_holder the one p_holder
-- holds), or every unused benefit it still holds (p_amount null).
create function pg_temp.t470_back(p_inv uuid, p_n int, p_amount numeric default null, p_holder uuid default null)
  returns void language plpgsql as $f$
declare opts jsonb; ben jsonb; tot numeric; item uuid := pg_temp.t470_line(p_inv, p_n);
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
  if ben is null then raise exception 'T470: nothing to refund on that line'; end if;
  perform refund_invoice_recorded(p_inv, jsonb_build_array(jsonb_build_object('invoice_item_id', item, 'amount', tot, 'benefits', ben)),
    pg_temp.t470_sources(p_inv, tot), '[]'::jsonb, 'T470 by line', gen_random_uuid());
end $f$;
-- The invoice form's customer change, its lines as they are (and the store,
-- when given), with 'transfer' or 'keep'. The change's Audit Log row is
-- dated now, as a later call's is (the suite is one transaction).
create function pg_temp.t470_lines(p_inv uuid) returns jsonb language sql as $f$
  select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('invoice_item_id', it.id, 'kind', it.line_kind,
           'credit_package_id', it.credit_package_id, 'premium_bundle_id', it.premium_bundle_id, 'voucher_id', it.voucher_id,
           'quantity', it.quantity, 'unit_price', it.unit_price, 'voucher_selection', it.bundle_voucher_selection)) order by it.id)
    from invoice_items it where it.invoice_id = p_inv $f$;
create function pg_temp.t470_change(p_inv uuid, p_cust uuid, p_action text default 'transfer', p_store text default null)
  returns void language plpgsql as $f$
begin
  perform correct_invoice(p_inv, pg_temp.t470_lines(p_inv),
    jsonb_build_object('expected_edit_count', (select edit_count from invoices where id = p_inv),
      'customer_id', p_cust, 'store_id', coalesce(pg_temp.t470_id(p_store), (select store_id from invoices where id = p_inv)),
      'benefit_action', p_action),
    'T470 wrong customer', gen_random_uuid());
  update audit_logs set created_at = clock_timestamp()
   where record_id = p_inv and action = 'invoice_benefits_followed_reassignment' and new_data->>'to_customer' = p_cust::text
     and created_at = now();
end $f$;
create function pg_temp.t470_merge(p_keep uuid, p_dup uuid) returns void language plpgsql as $f$
begin
  perform merge_customer_records(p_keep, p_dup, 'T470 the same person', gen_random_uuid());
end $f$;
-- The Finance panel's Move of line p_n's unused benefit (its Paid credit,
-- or its Bonus with p_kind 'bonus', or a voucher) to p_to, at p_store.
create function pg_temp.t470_move(p_inv uuid, p_n int, p_to uuid, p_kind text default 'paid', p_store text default null)
  returns void language plpgsql as $f$
declare b uuid;
begin
  select bv.id into b from invoice_benefit_values bv
    left join customer_reward_vouchers v on v.id = bv.reward_voucher_id
    left join customer_credit_lots l on l.id = bv.lot_id
   where bv.invoice_item_id = pg_temp.t470_line(p_inv, p_n)
     and (v.status = 'held' and p_kind = 'voucher' or l.remaining_amount > 0 and l.category = p_kind)
   order by bv.granted_value desc limit 1;
  if b is null then raise exception 'T470: nothing to move on that line'; end if;
  perform transfer_invoice_unused_benefit(b, p_to, coalesce(pg_temp.t470_id(p_store), (select store_id from invoices where id = p_inv)),
    'T470 move', gen_random_uuid());
end $f$;
-- The invoice form: p_n sessions of S$20 (or S$5 with p_svc 'svc5') for
-- p_cust, paid with the wallet (Credit Package Paid; Premium Bundle Paid with
-- p_wallet 'bwallet') through Record Payment.
create function pg_temp.t470_spend(p_cust uuid, p_n int default 1, p_svc text default 'svc', p_wallet text default 'wallet')
  returns uuid language plpgsql as $f$
declare inv uuid; v_lines jsonb := '[]'; i int;
begin
  for i in 1 .. p_n loop
    v_lines := v_lines || jsonb_build_array(jsonb_build_object('kind', 'therapy', 'therapy_service_id', pg_temp.t470_id(p_svc), 'quantity', 1));
  end loop;
  inv := create_invoice_with_details(pg_temp.t470_id('store'), p_cust, v_lines, jsonb_build_object('business_date', sg_today()::text));
  perform record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.t470_id(p_wallet),
    'amount', (select total_amount from invoices where id = inv))), gen_random_uuid());
  if (select status::text from invoices where id = inv) <> 'paid' then raise exception 'T470: the session paid from credit is not paid'; end if;
  return inv;
end $f$;
-- The session cancelled and "Record refund paid": what its payment took goes
-- back to the lots it came from (refund_invoice_recorded's wallet refund).
create function pg_temp.t470_unspend(p_inv uuid) returns void language plpgsql as $f$
declare due numeric;
begin
  perform cancel_invoice_recorded(p_inv, 'T470 cancel session', gen_random_uuid());
  due := (invoice_financial_position(p_inv)->>'refund_due')::numeric;
  if due is null or due <= 0 then due := (invoice_action_plan(p_inv, 'cancel', '[]')->>'refund_due')::numeric; end if;
  perform refund_invoice_recorded(p_inv, jsonb_build_array(jsonb_build_object('amount', due)), pg_temp.t470_sources(p_inv, due), '[]'::jsonb,
    'T470 refund paid', gen_random_uuid());
end $f$;
-- The Finance panel's Correct payment on a session's wallet payment: the
-- date only ('date'), a smaller amount ('amount', S$5 less), or another
-- method ('cash').
create function pg_temp.t470_fix(p_inv uuid, p_how text) returns void language plpgsql as $f$
declare p invoice_payments%rowtype;
begin
  select * into p from invoice_payments where invoice_id = p_inv and entry_kind in ('receipt', 'correction_replacement')
     and not exists (select 1 from invoice_payments q where q.corrects_payment_id = invoice_payments.id and q.entry_kind = 'correction_reversal')
   order by created_at desc, id desc limit 1;
  perform correct_invoice_payment(p.id,
    case p_how when 'amount' then p.amount - 5 else p.amount end,
    sg_today() - 1,
    case p_how when 'cash' then pg_temp.t470_id('pm') else p.payment_method_id end,
    'T470 correct payment ' || p_how, gen_random_uuid());
end $f$;
-- A special document's wallet payment as pay_special_with_credit records it
-- (a stand-in: no page calls that function, and no credit category allows a
-- special document today, purchase_category): p_amount off the customer's
-- largest lot ('use', its allocations), so refund_special_credit, the real
-- one, gives it back.
create function pg_temp.t470_special(p_cust uuid, p_kind text, p_doc uuid, p_amount numeric) returns void language plpgsql as $f$
declare l customer_credit_lots%rowtype; e uuid;
begin
  select * into l from customer_credit_lots where customer_id = p_cust and status = 'active' and remaining_amount >= p_amount
   order by remaining_amount desc, id limit 1 for update;
  insert into customer_credit_ledger(wallet_id, customer_id, entry_type, category, amount, lot_id, source_type, source_record_id, store_id, note, created_by)
  values (l.wallet_id, p_cust, 'use', l.category, p_amount, l.id, p_kind, p_doc, l.store_id, 'T470 special', auth.uid()) returning id into e;
  update customer_credit_lots set remaining_amount = remaining_amount - p_amount, updated_at = now() where id = l.id;
  insert into customer_credit_allocations(ledger_entry_id, lot_id, customer_id, amount) values (e, l.id, p_cust, p_amount);
  insert into special_credit_allocations(doc_kind, doc_id, customer_id, lot_id, category, amount, created_by)
  values (p_kind, p_doc, p_cust, l.id, l.category, p_amount, auth.uid());
end $f$;
-- The guided Refund in full / Cancel as an Owner confirms it, with a reason
-- for every override the plan asks for, the money recorded as paid back.
create function pg_temp.t470_guided(p_inv uuid, p_action text) returns void language plpgsql as $f$
declare plan jsonb; req jsonb; ov jsonb;
begin
  plan := invoice_action_plan(p_inv, p_action, '[]');
  req := request_invoice_action_v2(p_inv, p_action, '[]', 'T470 ' || p_action, null, gen_random_uuid());
  select coalesce(jsonb_agg(case when coalesce((o->>'amount_required')::boolean, false)
           then jsonb_build_object('code', o->>'code', 'reason', 'T470 override', 'amount', (o->>'default_amount')::numeric)
           else jsonb_build_object('code', o->>'code', 'reason', 'T470 override') end), '[]'::jsonb)
    into ov from jsonb_array_elements(coalesce(plan->'overrides_required', '[]')) o;
  perform resolve_invoice_action_v2((req->>'request_id')::uuid, true, 'T470 ' || p_action, plan->>'plan_hash', ov, null, true);
end $f$;


-- ── What the records say ────────────────────────────────────────────────────
-- The lots an invoice's records name: its benefit values, its sale's lots, a
-- split's issued lot, released credit (credit_package_progress_lots).
create function pg_temp.t470_named(p_inv uuid) returns setof uuid language sql as $f$
  select lot_id from invoice_benefit_values where invoice_id = p_inv and lot_id is not null
  union select x from credit_package_sales s, unnest(array[s.credit_lot_id, s.bonus_credit_lot_id]) x where s.invoice_id = p_inv and x is not null
  union select x from premium_bundle_sales s, unnest(array[s.paid_credit_lot_id, s.bonus_credit_lot_id]) x where s.invoice_id = p_inv and x is not null
  union select issued_lot_id from invoice_credit_splits where invoice_id = p_inv and issued_lot_id is not null
  union select lot_id from credit_package_progress_lots where invoice_id = p_inv $f$;
-- The invoice's lot family (the critic's 6): every lot its records name and
-- each Move's two lots (from the Move's ledger rows), the lots each replaced
-- and every lot reissued from any of them.
create function pg_temp.t470_family(p_inv uuid) returns setof uuid language sql as $f$
  with recursive seed as (
    select x as id from pg_temp.t470_named(p_inv) x
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
create function pg_temp.t470_behind(p_inv uuid) returns setof uuid language sql as $f$
  with recursive c(id, n) as (
    select lot_id, 0 from invoice_benefit_values where invoice_id = p_inv and lot_id is not null
    union select p.id, c.n + 1 from c join customer_credit_lots l on l.id = c.id
            join customer_credit_lots p on p.id = l.reassigned_from_lot_id
             and (p.source_type, p.source_record_id) is not distinct from (l.source_type, l.source_record_id)
           where c.n < 12)
  select distinct id from c $f$;
-- How many lots back a lot's chain goes (reassigned_from_lot_id).
create function pg_temp.t470_depth(p_lot uuid) returns int language sql as $f$
  with recursive c(id, n) as (select p_lot, 0 union all
    select l.reassigned_from_lot_id, c.n + 1 from c join customer_credit_lots l on l.id = c.id
     where l.reassigned_from_lot_id is not null and c.n < 40)
  select max(n) from c $f$;
-- A lot's balance by its ledger rows: credit added (grants, increases,
-- credit returned: the 'reverse' rows that put credit back, as the
-- statement reads them, and 'rental_late_fee'), less credit taken (uses,
-- decreases, real reversals).
create function pg_temp.t470_ledger_balance(p_lot uuid) returns numeric language sql as $f$
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
create function pg_temp.t470_invariants(p_inv uuid) returns text language plpgsql as $f$
declare probs text := ''; l record; root record; v uuid; st text := (select status::text from invoices where id = p_inv);
begin
  for l in select cl.* from customer_credit_lots cl where cl.id in (select pg_temp.t470_family(p_inv)) loop
    if l.remaining_amount > 0 and l.id not in (select pg_temp.t470_named(p_inv)) then
      probs := probs || format(' S$%s on a lot no record names (%s);', l.remaining_amount, (select full_name from customers where id = l.customer_id)); end if;
    if l.id not in (select pg_temp.t470_named(p_inv)) and l.id not in (select pg_temp.t470_behind(p_inv))
       and (exists (select 1 from invoice_line_credit_allocations a where a.lot_id = l.id and a.amount > coalesce(a.reversed_amount, 0))
            or exists (select 1 from special_credit_allocations s where s.lot_id = l.id and s.amount > coalesce(s.reversed_amount, 0))) then
      probs := probs || ' a sale paid from a lot no record names can still be refunded (its credit would stay there);'; end if;
    if pg_temp.t470_ledger_balance(l.id) <> l.remaining_amount then
      probs := probs || format(' lot holds %s, its ledger %s;', l.remaining_amount, pg_temp.t470_ledger_balance(l.id)); end if;
    if pg_temp.t470_depth(l.id) > 12 then probs := probs || format(' chain %s lots deep;', pg_temp.t470_depth(l.id)); end if;
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
  if st = 'refunded' and (select coalesce(sum(remaining_amount), 0) from customer_credit_lots where id in (select pg_temp.t470_family(p_inv))) > 0 then
    probs := probs || format(' refunded, but S$%s of its credit is still held;',
      (select sum(remaining_amount) from customer_credit_lots where id in (select pg_temp.t470_family(p_inv)))); end if;
  return probs;
end $f$;
-- Credit left on the invoice's family once Cancel has run, the Cancel undone
-- (0 when Cancel takes it all back from whoever holds it); null when the
-- invoice cannot be cancelled now, -1 when Cancel is refused.
create function pg_temp.t470_cancel_left(p_inv uuid) returns numeric language plpgsql as $f$
declare v numeric;
begin
  if (select status::text from invoices where id = p_inv) not in ('paid', 'partially_paid', 'unpaid') then return null; end if;
  begin
    perform cancel_invoice_recorded(p_inv, 'T470 probe', gen_random_uuid());
    perform pg_temp.t470_commit();
    v := (select coalesce(sum(remaining_amount), 0) from customer_credit_lots where id in (select pg_temp.t470_family(p_inv)));
    raise exception using errcode = 'P0462', message = v::text;
  exception when sqlstate 'P0462' then return sqlerrm::numeric;
            when others then return -1;
  end;
end $f$;
create function pg_temp.t470_codes(p_inv uuid, p_action text) returns text language plpgsql as $f$
begin
  return (select coalesce(string_agg(o->>'code', ',' order by o->>'code'), '-')
            from jsonb_array_elements(coalesce(invoice_action_plan(p_inv, p_action, '[]')->'overrides_required', '[]')) o);
exception when others then return 'ERR';
end $f$;
create function pg_temp.t470_due(p_inv uuid, p_action text) returns numeric language plpgsql as $f$
begin
  return (invoice_action_plan(p_inv, p_action, '[]')->>case when p_action = 'cancel' then 'refund_due' else 'refund_amount' end)::numeric;
exception when others then return null;
end $f$;
-- The invoice's money: what is owed back (cancel_refund_owed), the Finance
-- panel's refund due, net received and kept for what was used, what a
-- refund by line can still pay back (the refund options' max_refund, every
-- benefit) and Cancel's refund due (the plan's).
create function pg_temp.t470_money(p_inv uuid) returns jsonb language sql as $f$
  select jsonb_build_object('owed', i.cancel_refund_owed,
    'due', (invoice_financial_position(i.id)->>'refund_due')::numeric,
    'net', (invoice_financial_position(i.id)->>'net_received')::numeric,
    'kept', (invoice_financial_position(i.id)->>'kept_for_used')::numeric,
    'by_line', (select coalesce(sum((b->>'max_refund')::numeric), 0)
                  from jsonb_array_elements(invoice_refund_options_before_sessions(i.id)->'benefits') b),
    'plan_due', pg_temp.t470_due(i.id, 'cancel'))
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
--   reverse R             an Owner's reversal of R's largest lot
--   guidedcancel          the guided Cancel as an Owner confirms it, "Record refund paid" ticked
--   refundpaid            "Record refund paid" of what the invoice owes back (no line)
--   backx N               a refund by line of all line N still holds in money, above
--                         its unused benefits (an Owner's 'larger_refund')
--   legacy STATUS         a stand-in for the legacy statuses (no page sets them now)
--   repair                repair_credit_package_progress_lots()
create function pg_temp.t470_role(p_pre text, p_r text) returns uuid language plpgsql as $f$
begin
  return coalesce(pg_temp.t470_id(p_pre || '/' || p_r), pg_temp.t470_cust(p_pre || '/' || p_r));
end $f$;
-- One step of a case (one app call, then what its commit does). Null, or
-- the step and the refusal; a refused step changes nothing.
create function pg_temp.t470_step(p_pre text, p_st text) returns text language plpgsql as $f$
declare w text[] := regexp_split_to_array(btrim(p_st), '\s+'); inv uuid := pg_temp.t470_id(p_pre || '/inv'); x uuid; i int; n int;
begin
  case w[1]
  when 'sale' then
    perform pg_temp.t470_put(p_pre || '/inv', pg_temp.t470_sale(pg_temp.t470_role(p_pre, w[2]), string_to_array(w[3], ','), w[4]::numeric));
  when 'saled' then
    perform pg_temp.t470_put(p_pre || '/inv', pg_temp.t470_sale(pg_temp.t470_role(p_pre, w[2]), string_to_array(w[3], ','), null, 2, w[4]::numeric));
  when 'sale2' then
    perform pg_temp.t470_put(p_pre || '/inv2', pg_temp.t470_sale(pg_temp.t470_role(p_pre, w[2]), array['cp']));
  when 'pay' then perform pg_temp.t470_pay(inv);
  when 'back' then
    perform pg_temp.t470_back(inv, w[2]::int, case when w[3] = 'all' then null else w[3]::numeric end,
                              case when w[4] is not null then pg_temp.t470_role(p_pre, w[4]) end);
  when 'move' then
    perform pg_temp.t470_move(inv, w[2]::int, pg_temp.t470_role(p_pre, w[3]),
      case when w[4] in ('bonus', 'voucher') then w[4] else 'paid' end,
      case when 'store2' = any (w) then 'store2' end);
  when 'cancel' then perform cancel_invoice_recorded(inv, 'T470 cancel', gen_random_uuid());
  when 'reopen' then perform reopen_invoice(inv, 'T470 reopen', gen_random_uuid());
  when 'wait' then
    perform cancel_invoice_recorded(inv, 'T470 cancel', gen_random_uuid());
    for i in 1 .. (select count(*)::int from invoice_items where invoice_id = inv) loop
      perform pg_temp.t470_back(inv, i);
    end loop;
    perform reopen_invoice(inv, 'T470 reopen', gen_random_uuid());
  when 'refundall' then perform pg_temp.t470_guided(inv, 'refund_full');
  when 'change' then
    perform pg_temp.t470_change(inv, pg_temp.t470_role(p_pre, w[2]), case when 'keep' = any (w) then 'keep' else 'transfer' end,
                                case when 'store2' = any (w) then 'store2' end);
  when 'merge' then perform pg_temp.t470_merge(pg_temp.t470_role(p_pre, w[2]), pg_temp.t470_role(p_pre, w[3]));
  when 'spend' then
    n := (select count(*) from t470 where k ~ ('^' || p_pre || '/S[0-9]+$')) + 1;
    perform pg_temp.t470_put(p_pre || '/S' || n,
      pg_temp.t470_spend(pg_temp.t470_role(p_pre, w[2]), case when w[3] ~ '^[0-9]+$' then w[3]::int else 1 end,
        case when 'svc5' = any (w) then 'svc5' else 'svc' end, case when 'bwallet' = any (w) then 'bwallet' else 'wallet' end));
  when 'unspend' then perform pg_temp.t470_unspend(pg_temp.t470_id(p_pre || '/' || w[2]));
  when 'fix' then perform pg_temp.t470_fix(pg_temp.t470_id(p_pre || '/' || w[2]), w[3]);
  when 'delete' then
    x := pg_temp.t470_role(p_pre, w[2]);
    perform delete_customer(x, (select full_name from customers where id = x), 'T470 delete');
  when 'special' then
    n := (select count(*) from t470 where k ~ ('^' || p_pre || '/D[0-9]+$')) + 1; x := gen_random_uuid();
    perform pg_temp.t470_put(p_pre || '/D' || n, x);
    perform pg_temp.t470_put(p_pre || '/D' || n || '/kind:' || w[3], null);
    perform pg_temp.t470_special(pg_temp.t470_role(p_pre, w[2]), w[3], x, w[4]::numeric);
  when 'unspecial' then
    perform refund_special_credit((select split_part(k, 'kind:', 2) from t470 where k like p_pre || '/' || w[2] || '/kind:%'),
                                  pg_temp.t470_id(p_pre || '/' || w[2]));
  when 'reverse' then
    x := pg_temp.t470_role(p_pre, w[2]);
    perform reverse_credit_lot((select id from customer_credit_lots where customer_id = x and remaining_amount > 0
                                 order by remaining_amount desc, id limit 1), 'T470 reversal');
  when 'guidedcancel' then perform pg_temp.t470_guided(inv, 'cancel');
  when 'refundpaid' then
    perform refund_invoice_recorded(inv, jsonb_build_array(jsonb_build_object('amount',
        coalesce(nullif((invoice_financial_position(inv)->>'refund_due')::numeric, 0), (invoice_action_plan(inv, 'cancel', '[]')->>'refund_due')::numeric))),
      pg_temp.t470_sources(inv, coalesce(nullif((invoice_financial_position(inv)->>'refund_due')::numeric, 0), (invoice_action_plan(inv, 'cancel', '[]')->>'refund_due')::numeric)),
      '[]'::jsonb, 'T470 refund paid', gen_random_uuid());
  when 'backx' then
    x := pg_temp.t470_line(inv, w[2]::int);
    perform refund_invoice_recorded(inv, jsonb_build_array(jsonb_build_object('invoice_item_id', x,
        'amount', invoice_discounted_line_value(x) - coalesce((select sum((e->>'amount')::numeric) from invoice_refunds r,
             jsonb_array_elements(coalesce(r.outcome->'lines', '[]')) e where r.invoice_id = inv and e->>'invoice_item_id' = x::text), 0),
        'benefits', (select jsonb_agg(jsonb_build_object('benefit_id', b->>'id', 'amount', (b->>'max_refund')::numeric))
                       from jsonb_array_elements(invoice_refund_options_before_sessions(inv)->'benefits') b
                      where b->>'invoice_item_id' = x::text and (b->>'max_refund')::numeric > 0),
        'override', jsonb_build_object('code', 'larger_refund', 'reason', 'T470 larger refund',
          'amount', invoice_discounted_line_value(x) - coalesce((select sum((e->>'amount')::numeric) from invoice_refunds r,
             jsonb_array_elements(coalesce(r.outcome->'lines', '[]')) e where r.invoice_id = inv and e->>'invoice_item_id' = x::text), 0)))),
      pg_temp.t470_sources(inv, invoice_net_received(inv)), '[]'::jsonb, 'T470 larger refund', gen_random_uuid());
  when 'legacy' then
    update invoices set status = w[2]::invoice_status where id = inv;
  when 'repair' then perform repair_credit_package_progress_lots();
  else raise exception 'T470: unknown step %', p_st;
  end case;
  perform pg_temp.t470_commit();
  return null;
exception when others then
  return btrim(p_st) || ': ' || sqlerrm;
end $f$;
-- What a case ends with: the invoice's status and money, who holds what
-- (credit, '/n' held vouchers), the plans' codes and refund due (Cancel's
-- refund due; Refund in full's amount), the refusal that stopped it, what is
-- wrong with its credit, and the credit Cancel would leave behind.
create function pg_temp.t470_outcome(p_pre text, p_err text) returns jsonb language sql as $f$
  select jsonb_build_object(
    'status', (select status::text from invoices where id = i.id),
    'net', invoice_net_received(i.id),
    'holds', (select jsonb_object_agg(split_part(t.k, '/', 3),
                (select coalesce(sum(l.remaining_amount), 0) from customer_credit_lots l where l.customer_id = t.id)::numeric(12,2)::text
                || coalesce('/' || nullif((select sum(v.quantity) from customer_reward_vouchers v where v.customer_id = t.id and v.status = 'held'), 0)::text, ''))
              from t470 t where t.k like p_pre || '/%' and split_part(t.k, '/', 4) = ''
                and split_part(t.k, '/', 3) !~ '^(inv|inv2|S[0-9]+|D[0-9]+|err)$'),
    'cancel', pg_temp.t470_codes(i.id, 'cancel'),
    'due', pg_temp.t470_due(i.id, 'cancel'),
    'refund', pg_temp.t470_codes(i.id, 'refund_full'),
    'rdue', pg_temp.t470_due(i.id, 'refund_full'),
    'error', p_err,
    'invariants', pg_temp.t470_invariants(i.id),
    'cancel_left', pg_temp.t470_cancel_left(i.id))
    from (select pg_temp.t470_id(p_pre || '/inv') as id) i $f$;
-- A case's steps p_from to p_to (all by default), stopping at a refusal;
-- with p_to null, its outcome (kept in t470_res under p_phase).
create temp table t470_err(pre text primary key, err text);
create function pg_temp.t470_run(p_phase text, p_case text, p_steps text, p_from int default 1, p_to int default null)
  returns jsonb language plpgsql as $f$
declare v_pre text := p_phase || '/' || p_case; st text[] := string_to_array(p_steps, ';'); i int; v_err text; v_out jsonb;
begin
  v_err := (select e.err from t470_err e where e.pre = v_pre);
  for i in p_from .. least(coalesce(p_to, cardinality(st)), cardinality(st)) loop
    exit when v_err is not null;
    continue when btrim(st[i]) = '';
    v_err := pg_temp.t470_step(v_pre, st[i]);
  end loop;
  insert into t470_err values (v_pre, v_err) on conflict (pre) do update set err = excluded.err;
  if p_to is not null then return null; end if;
  v_out := pg_temp.t470_outcome(v_pre, v_err);
  insert into t470_res values (p_phase, p_case, v_out) on conflict (phase, k) do update set v = excluded.v;
  return v_out;
end $f$;

-- Whether an outcome has what is expected: each key equal ('holds' as a
-- containment of who holds what), a key ending in '~' as a LIKE pattern of
-- that key's text.
create function pg_temp.t470_meets(p_out jsonb, p_exp jsonb) returns boolean language sql as $f$
  select coalesce(bool_and(case
           when e.key like '%~' then coalesce(p_out->>left(e.key, -1), '') like (e.value #>> '{}')
           when e.key = 'holds' then coalesce(p_out->'holds', '{}') @> e.value
           when jsonb_typeof(e.value) = 'number' then (p_out->>e.key)::numeric = (e.value #>> '{}')::numeric
           else (p_out->e.key) is not distinct from e.value end), true)
    from jsonb_each(p_exp) e $f$;
-- What differs between an outcome and what is expected (for the FAIL line).
create function pg_temp.t470_diff(p_out jsonb, p_exp jsonb) returns text language sql as $f$
  select string_agg(e.key || ': wanted ' || e.value::text || ', got ' || coalesce(p_out->left(e.key, case when e.key like '%~' then -1 else 1000 end), 'null')::text, '; ')
    from jsonb_each(p_exp) e where not pg_temp.t470_meets(p_out, jsonb_build_object(e.key, e.value)) $f$;

-- The cases: (k, kind, steps, what 470 gives). kind: 'fixed' (before 470 it
-- ends otherwise: the fault is reproduced first), 'control' (the same with
-- and without 470), 'changed' (a different, consistent answer before:
-- expect_before). Every case also checks the invariants and that Cancel takes
-- everything back from whoever holds it.
create temp table t470_cases(k text primary key, kind text not null, steps text not null, expect jsonb not null,
  expect_before jsonb, ord serial);
insert into t470_cases(k, kind, steps, expect, expect_before) values
-- K7b (462's KNOWN): cancelled, S2 refunded while cancelled, refunded by line.
('K7b', 'fixed', 'sale A cp; spend A; spend A; move 1 F; change B; unspend S1; cancel; unspend S2; back 1 all',
  '{"holds":{"A":"0.00","B":"0.00","F":"0.00"},"status":"cancelled","net":0}', null),
('K7p', 'fixed', 'sale A cp; spend A; spend A; move 1 F; change B; unspend S1; cancel; unspend S2',
  '{"holds":{"A":"0.00","B":"0.00","F":"0.00"},"status":"cancelled","net":100,"cancel":"-","due":100}', null),
('K7n2', 'fixed', 'sale A cp; spend A; spend A; spend A; move 1 F; change B; unspend S1; cancel; unspend S2; unspend S3; back 1 all',
  '{"holds":{"A":"0.00","B":"0.00","F":"0.00"},"status":"cancelled","net":0}', null),
('K7bx', 'fixed', 'sale A cpb; spend A; spend A; move 1 F; change B; unspend S1; cancel; unspend S2; back 1 all',
  '{"holds":{"A":"0.00","B":"0.00","F":"0.00"},"status":"cancelled","net":0}', null),
('K7b2', 'fixed', 'sale A cp; spend A; spend A; move 1 F; change B; unspend S1; cancel; back 1 10; unspend S2; back 1 all',
  '{"holds":{"A":"0.00","B":"0.00","F":"0.00"},"status":"cancelled","net":0}', null),
('SS4', 'fixed', 'sale A cp; special A special_sale 20; spend A; move 1 F; change B; unspend S1; cancel; unspecial D1; back 1 all',
  '{"holds":{"A":"0.00","B":"0.00","F":"0.00"},"status":"cancelled","net":0}', null),
-- The merge sibling: the new holder merged into a kept record (before the
-- cancel, while cancelled), and a merge of the buyer before the sessions.
('K7mb', 'fixed', 'sale A cp; spend A; spend A; move 1 F; change B; unspend S1; merge K B; cancel; unspend S2; back 1 all',
  '{"holds":{"A":"0.00","B":"0.00","F":"0.00","K":"0.00"},"status":"cancelled","net":0}', null),
('K7mr', 'fixed', 'sale A cp; back 1 20; merge K A; spend K; spend K; move 1 F; change B; unspend S1; cancel; unspend S2; back 1 all',
  '{"holds":{"A":"0.00","B":"0.00","F":"0.00","K":"0.00"},"status":"cancelled","net":0}', null),
('K7cm', 'fixed', 'sale A cp; spend A; spend A; move 1 F; change B; unspend S1; cancel; unspend S2; merge K B; back 1 all',
  '{"holds":{"A":"0.00","B":"0.00","F":"0.00","K":"0.00"},"status":"cancelled","net":0}', null),
('K7cc', 'fixed', 'sale A cp; spend A; spend A; move 1 F; change B; unspend S1; cancel; unspend S2; change C; back 1 all',
  '{"holds":{"A":"0.00","B":"0.00","C":"0.00","F":"0.00"},"status":"cancelled","net":0,"error":null}', null),
('K7cb', 'fixed', 'sale A cp; spend A; spend A; move 1 F; change B; unspend S1; cancel; change C; unspend S2; back 1 all',
  '{"holds":{"A":"0.00","B":"0.00","C":"0.00","F":"0.00"},"status":"cancelled","net":0}', null),
-- Cancel then "Record refund paid" (the app asks for the refund by line on a
-- package; nothing is stranded meanwhile); the guided Refund in full after
-- the cancel (refused: already cancelled).
('K7rp', 'fixed', 'sale A cp; spend A; spend A; move 1 F; change B; unspend S1; cancel; unspend S2; refundpaid',
  '{"holds":{"A":"0.00","B":"0.00","F":"0.00"},"status":"cancelled","net":100,"due":100,"error~":"refundpaid: Allocate a correction refund to the original unused purchased benefits%"}', null),
('K7g', 'fixed', 'sale A cp; spend A; spend A; move 1 F; change B; unspend S1; cancel; unspend S2; refundall',
  '{"holds":{"A":"0.00","B":"0.00","F":"0.00"},"status":"cancelled","net":100,"due":100,"error~":"refundall: Invoice is already cancelled%"}', null),
-- The guided Cancel with "Record refund paid" (S$80 paid back, S$0 owed after), then S2 refunded.
('K7gc', 'fixed', 'sale A cp; spend A; spend A; move 1 F; change B; unspend S1; guidedcancel; unspend S2',
  '{"holds":{"A":"0.00","B":"0.00","F":"0.00"},"status":"cancelled","net":20,"due":20}', null),
('K7gcb', 'fixed', 'sale A cp; spend A; spend A; move 1 F; change B; unspend S1; guidedcancel; unspend S2; back 1 all',
  '{"holds":{"A":"0.00","B":"0.00","F":"0.00"},"status":"cancelled","net":0,"error":null}', null),
('K7gcr', 'fixed', 'sale A cp; spend A; spend A; move 1 F; change B; unspend S1; guidedcancel; unspend S2; back 1 all; reopen; pay',
  '{"holds":{"A":"0.00","B":"40.00","F":"60.00"},"net":100,"cancel":"-","due":100,"error":null}', null),
-- The same where S$20 of credit is worth less than S$20 (a third session
-- kept for, as spent): the S$100 + S$10 Bonus package (the Paid row S$90.91
-- for 100 credit: S$18.18), the S$140 Premium Bundle (S$70 for 100: S$14.00)
-- and that bundle S$7 off by an Owner's manual discount (S$64.79 for 95:
-- S$13.64). What is owed back grows by that money, not by S$20 (P2); the
-- refund by line then pays it all back and nothing stays owed.
('K7gcx', 'fixed', 'sale A cpb; spend A; spend A; spend A; move 1 F; change B; unspend S1; guidedcancel; unspend S2',
  '{"holds":{"A":"0.00","B":"0.00","F":"0.00"},"status":"cancelled","net":36.37,"due":18.18,"error":null}', null),
('K7gcbx', 'fixed', 'sale A cpb; spend A; spend A; spend A; move 1 F; change B; unspend S1; guidedcancel; unspend S2; back 1 all',
  '{"holds":{"A":"0.00","B":"0.00","F":"0.00"},"status":"cancelled","net":18.19,"due":0,"error":null}', null),
('K7gcv', 'fixed', 'sale A pbv; spend A 1 bwallet; spend A 1 bwallet; spend A 1 bwallet; move 1 F; change B; unspend S1; guidedcancel; unspend S2',
  '{"holds":{"A":"0.00","B":"0.00","F":"0.00"},"status":"cancelled","net":28,"due":14,"error":null}', null),
('K7gcbv', 'fixed', 'sale A pbv; spend A 1 bwallet; spend A 1 bwallet; spend A 1 bwallet; move 1 F; change B; unspend S1; guidedcancel; unspend S2; back 1 all',
  '{"holds":{"A":"0.00","B":"0.00","F":"0.00"},"status":"cancelled","net":14,"due":0,"error":null}', null),
('K7gcd', 'fixed', 'saled A pbv 7; spend A 1 bwallet; spend A 1 bwallet; spend A 1 bwallet; move 1 F; change B; unspend S1; guidedcancel; unspend S2',
  '{"holds":{"A":"0.00","B":"0.00","F":"0.00"},"status":"cancelled","net":27.28,"due":13.64,"error":null}', null),
('K7gcbd', 'fixed', 'saled A pbv 7; spend A 1 bwallet; spend A 1 bwallet; spend A 1 bwallet; move 1 F; change B; unspend S1; guidedcancel; unspend S2; back 1 all',
  '{"holds":{"A":"0.00","B":"0.00","F":"0.00"},"status":"cancelled","net":13.64,"due":0,"error":null}', null),
-- Correct payment of S2 instead of its refund (to cash; S$5 less).
('K7fc', 'fixed', 'sale A cp; spend A; spend A; move 1 F; change B; unspend S1; cancel; fix S2 cash; back 1 all',
  '{"holds":{"A":"0.00","B":"0.00","F":"0.00"},"status":"cancelled","net":0,"error":null}', null),
('K7fa', 'fixed', 'sale A cp; spend A; spend A; move 1 F; change B; unspend S1; cancel; fix S2 amount; back 1 all',
  '{"holds":{"A":"0.00","B":"0.00","F":"0.00"},"status":"cancelled","net":15,"error":null}', null),
-- Refund in full with an Owner's override (what was spent paid back too),
-- then S2 refunded: held back for B (owed to nobody: NOT COVERED 2).
('RX1', 'fixed', 'sale A cp; spend A; spend A; move 1 F; change B; unspend S1; backx 1; unspend S2',
  '{"holds":{"A":"0.00","B":"0.00","F":"0.00"},"status":"refunded","net":0}', null),
-- While a reopening waits: S2 refunded while it waits, then cancelled again
-- and refunded by line; the guided Refund in full; the holder spends; paid
-- after a customer change or a merge; a refund by line while it waits.
('K7wc', 'fixed', 'sale A cp; spend A; spend A; move 1 F; change B; unspend S1; cancel; back 1 60 F; reopen; unspend S2; cancel; back 1 all',
  '{"holds":{"A":"0.00","B":"0.00","F":"0.00"},"status":"cancelled","net":0}', null),
('K7wg', 'fixed', 'sale A cp; spend A; spend A; move 1 F; change B; unspend S1; cancel; back 1 60 F; reopen; unspend S2; refundall',
  '{"holds":{"A":"0.00","B":"0.00","F":"0.00"},"net":0,"error":null}', null),
('K7w2', 'fixed', 'sale A cp; spend A; spend A; move 1 F; change B; unspend S1; cancel; back 1 60 F; reopen; unspend S2; spend B',
  '{"holds":{"A":"0.00","B":"0.00","F":"0.00"},"net":40,"error~":"spend B: Only 0 of the requested 20.00 could be funded by eligible credit%"}', null),
('K7wfa', 'fixed', 'sale A cp; spend A; spend A; move 1 F; change B; unspend S1; cancel; back 1 60 F; reopen; fix S2 amount; back 1 all; pay',
  '{"holds":{"A":"0.00","B":"0.00","F":"60.00"},"net":75,"due":60,"error":null}', null),
('K7c2', 'fixed', 'sale A cp; spend A; spend A; move 1 F; change B; unspend S1; cancel; unspend S2; spend B',
  '{"holds":{"A":"0.00","B":"0.00","F":"0.00"},"status":"cancelled","net":100,"due":100,"error~":"spend B: Only 0 of the requested 20.00 could be funded by eligible credit%"}', null),
-- 446's matching: a refund by line while the reopening waits.
('Z1', 'fixed', 'sale A cp; spend A; spend A; move 1 F; change B; unspend S1; cancel; unspend S2; back 1 60 F; reopen; back 1 all; pay',
  '{"holds":{"A":"0.00","B":"0.00","F":"60.00"},"net":60,"cancel":"-","due":60}', null),
('Z2', 'fixed', 'sale A cp; spend A; spend A; move 1 F; change B; unspend S1; cancel; unspend S2; back 1 60 F; reopen; back 1 20; pay',
  '{"holds":{"A":"0.00","B":"20.00","F":"60.00"},"net":80,"cancel":"-","due":80}', null),
('Z5', 'fixed', 'sale A cp; spend A; spend A; move 1 F; change B; unspend S1; cancel; unspend S2; back 1 60 F; reopen; back 1 all; pay; refundall',
  '{"holds":{"A":"0.00","B":"0.00","F":"0.00"},"status":"refunded","net":0}', null),
('Z1w', 'fixed', 'sale A cp; spend A; spend A; move 1 F; change B; unspend S1; cancel; back 1 60 F; reopen; unspend S2; back 1 all; pay',
  '{"holds":{"A":"0.00","B":"0.00","F":"60.00"},"net":60,"cancel":"-","due":60}', null),
('Z1wr', 'fixed', 'sale A cp; spend A; spend A; move 1 F; change B; unspend S1; cancel; back 1 60 F; reopen; unspend S2; back 1 all; pay; refundall',
  '{"holds":{"A":"0.00","B":"0.00","F":"0.00"},"status":"refunded","net":0}', null),
('M1', 'fixed', 'sale A cp; spend A; spend A; move 1 F; change B; unspend S1; cancel; unspend S2; merge K B; back 1 60 F; reopen; back 1 all; pay',
  '{"holds":{"A":"0.00","B":"0.00","F":"60.00","K":"0.00"},"net":60,"cancel":"-","due":60}', null),
('M1p', 'fixed', 'sale A cp; spend A; spend A; move 1 F; change B; unspend S1; cancel; unspend S2; merge K B',
  '{"holds":{"A":"0.00","B":"0.00","F":"0.00","K":"0.00"},"status":"cancelled","due":100}', null),
-- Five sessions refunded while cancelled; the holder deleted while cancelled
-- (refunded by line; reopened and paid: the customer it went back to, 462's
-- NOT COVERED 7).
('CH5', 'fixed', 'sale A cp; spend A 1 svc5; spend A 1 svc5; spend A 1 svc5; spend A 1 svc5; spend A 1 svc5; spend A 1 svc5; move 1 F; change B; unspend S1; cancel; unspend S2; unspend S3; unspend S4; unspend S5; unspend S6; back 1 all',
  '{"holds":{"A":"0.00","B":"0.00","F":"0.00"},"status":"cancelled","net":0}', null),
('DHc', 'fixed', 'sale A cp; spend A; spend A; move 1 F; change B; unspend S1; cancel; delete B; unspend S2; back 1 all',
  '{"holds":{"A":"0.00","B":"0.00","F":"0.00"},"status":"cancelled","net":0,"error":null}', null),
('DHr', 'fixed', 'sale A cp; spend A; spend A; move 1 F; change B; unspend S1; cancel; delete B; unspend S2; reopen; pay',
  '{"holds":{"A":"40.00","B":"0.00","F":"60.00"},"net":100,"cancel":"-","due":100,"error":null}', null),
-- The legacy statuses (asked to be cancelled or refunded): followed as paid.
('LG1', 'fixed', 'sale A cp; spend A; spend A; move 1 F; change B; unspend S1; legacy cancellation_requested; unspend S2; cancel; back 1 all',
  '{"holds":{"A":"0.00","B":"0.00","F":"0.00"},"status":"cancelled","net":0,"error":null}', null),
('LG2', 'fixed', 'sale A cp; spend A; spend A; move 1 F; change B; unspend S1; legacy refund_requested; unspend S2; legacy paid',
  '{"holds":{"A":"0.00","B":"40.00","F":"60.00"},"net":100,"cancel":"-","due":100,"error":null}', null),
-- Changed: consistent before and after, another answer (before, the S$20
-- stranded on A's lot was out of reach of the refund by line while waiting).
('Z3', 'changed', 'sale A cp; spend A; spend A; move 1 F; change B; unspend S1; cancel; unspend S2; back 1 10; reopen; back 1 all; pay',
  '{"holds":{"A":"0.00","B":"10.00","F":"0.00"},"net":10,"cancel":"-","due":10}',
  '{"holds":{"A":"0.00","B":"30.00","F":"0.00"},"net":30,"cancel":"-","due":30}'),
-- Controls: the same with and without 470.
('K7r', 'control', 'sale A cp; spend A; spend A; move 1 F; change B; unspend S1; cancel; unspend S2; reopen; pay',
  '{"holds":{"A":"0.00","B":"40.00","F":"60.00"},"net":100,"cancel":"-","due":100}', null),
('K7rr', 'control', 'sale A cp; spend A; spend A; move 1 F; change B; unspend S1; cancel; unspend S2; reopen; pay; refundall',
  '{"holds":{"A":"0.00","B":"0.00","F":"0.00"},"status":"refunded","net":0}', null),
('K7w', 'control', 'sale A cp; spend A; spend A; move 1 F; change B; unspend S1; cancel; back 1 60 F; reopen; unspend S2; pay',
  '{"holds":{"A":"0.00","B":"40.00","F":"60.00"},"net":100,"cancel":"-","due":100}', null),
('K7wf', 'control', 'sale A cp; spend A; spend A; move 1 F; change B; unspend S1; cancel; back 1 60 F; reopen; fix S2 cash; pay',
  '{"holds":{"A":"0.00","B":"40.00","F":"60.00"},"net":100,"cancel":"-","due":100,"error":null}', null),
('K7wch', 'control', 'sale A cp; spend A; spend A; move 1 F; change B; unspend S1; cancel; back 1 60 F; reopen; unspend S2; change C; pay',
  '{"holds":{"A":"0.00","B":"0.00","C":"40.00","F":"60.00"},"net":100,"cancel":"-","due":100,"error":null}', null),
('K7wm', 'control', 'sale A cp; spend A; spend A; move 1 F; change B; unspend S1; cancel; back 1 60 F; reopen; unspend S2; merge K B; pay',
  '{"holds":{"A":"0.00","B":"0.00","F":"60.00","K":"40.00"},"net":100,"cancel":"-","due":100,"error":null}', null),
('K7wcr', 'control', 'sale A cp; spend A; spend A; move 1 F; change B; unspend S1; cancel; back 1 60 F; reopen; unspend S2; cancel; reopen; pay',
  '{"holds":{"A":"0.00","B":"40.00","F":"60.00"},"net":100,"cancel":"-","due":100}', null),
('K7b3', 'control', 'sale A cp; spend A; spend A; move 1 F; change B; unspend S1; cancel; back 1 10; unspend S2; reopen; pay',
  '{"holds":{"A":"0.00","B":"40.00","F":"60.00"},"net":100,"cancel":"-","due":100}', null),
('Z4', 'control', 'sale A cp; spend A; spend A; move 1 F; change B; unspend S1; cancel; unspend S2; back 1 all; reopen; pay',
  '{"holds":{"A":"0.00","B":"40.00","F":"60.00"},"net":100,"cancel":"-","due":100}', null),
('M2', 'control', 'sale A cp; spend A; spend A; move 1 F; change B; unspend S1; cancel; unspend S2; merge K B; back 1 60 F; reopen; pay',
  '{"holds":{"A":"0.00","B":"0.00","F":"60.00","K":"40.00"},"net":100,"cancel":"-","due":100}', null),
('G1', 'control', 'sale A cp; spend A; spend A; move 1 F; change B; unspend S1; guidedcancel; unspend S2; reopen; pay',
  '{"holds":{"A":"0.00","B":"40.00","F":"60.00"},"net":100,"cancel":"-","due":100}', null),
('W2', 'control', 'sale A cp; spend A; spend A; move 1 F; change B; unspend S1; cancel; back 1 60 F; reopen; unspend S2; cancel; back 1 all; reopen; pay',
  '{"holds":{"A":"0.00","B":"40.00","F":"60.00"},"net":100,"cancel":"-","due":100}', null),
('K7cmr', 'control', 'sale A cp; spend A; spend A; move 1 F; change B; unspend S1; cancel; unspend S2; merge K B; reopen; pay',
  '{"holds":{"A":"0.00","B":"0.00","F":"60.00","K":"40.00"},"net":100,"cancel":"-","due":100}', null),
('K7cbr', 'control', 'sale A cp; spend A; spend A; move 1 F; change B; unspend S1; cancel; change C; unspend S2; reopen; pay',
  '{"holds":{"A":"0.00","B":"0.00","C":"40.00","F":"60.00"},"net":100,"cancel":"-","due":100}', null),
('K7fd', 'control', 'sale A cp; spend A; spend A; move 1 F; change B; unspend S1; cancel; fix S2 date; back 1 all',
  '{"holds":{"A":"0.00","B":"0.00","F":"0.00"},"status":"cancelled","net":20,"error":null}', null),
('K7gr', 'control', 'sale A cp; spend A; spend A; move 1 F; change B; unspend S1; refundall; unspend S2',
  '{"holds":{"A":"0.00","B":"20.00","F":"0.00"},"net":20}', null),
('L13c', 'control', 'sale A cp; back 1 10; spend A 13 svc5; move 1 F; change B; cancel; unspend S1; back 1 all',
  '{"holds":{"A":"0.00","B":"0.00","F":"0.00"},"status":"cancelled","net":0}', null),
('L13w', 'control', 'sale A cp; back 1 10; spend A 13 svc5; move 1 F; change B; cancel; back 1 10 F; reopen; unspend S1; back 1 all; pay',
  '{"holds":{"A":"0.00","B":"10.00","F":"10.00"},"net":20,"cancel":"-","due":20}', null),
-- Without a reissue (the package's own lot): as before 462 and 470.
('C0', 'control', 'sale A cp; spend A; spend A; move 1 F; unspend S1; cancel; unspend S2; back 1 all',
  '{"holds":{"A":"0.00","F":"0.00"},"status":"cancelled","net":0}', null),
('C0r', 'control', 'sale A cp; spend A; spend A; move 1 F; unspend S1; cancel; unspend S2; reopen; pay',
  '{"holds":{"A":"40.00","F":"60.00"},"net":100,"cancel":"-","due":100}', null),
('C1', 'control', 'sale A cp; spend A; spend A; move 1 F; change B; unspend S1; unspend S2; cancel; back 1 all',
  '{"holds":{"A":"0.00","B":"0.00","F":"0.00"},"status":"cancelled","net":0}', null),
('C2', 'control', 'sale A cp; spend A; cancel; unspend S1; back 1 all',
  '{"holds":{"A":"0.00"},"status":"cancelled","net":0}', null),
('G2', 'control', 'sale A cp; spend A; spend A; move 1 F; unspend S1; guidedcancel; unspend S2',
  '{"holds":{"A":"20.00","F":"0.00"},"status":"cancelled","net":20}', null),
('G3', 'control', 'sale A cp; spend A; spend A; move 1 F; unspend S1; guidedcancel; unspend S2; back 1 all',
  '{"holds":{"A":"20.00","F":"0.00"},"status":"cancelled","net":20,"error~":"back 1 all: That is more than the S$0.00 still owed back%"}', null);

-- The read-only query in 470's header (the same text): what 470 would
-- refuse to install over, and what it reads differently.
create function pg_temp.t470_header_query() returns table(reason text, invoice_no text, n bigint) language sql as $hq$
with recursive
st as (
  select i.id, i.status::text as status,
         exists (select 1 from public.invoice_reopen_benefits q where q.invoice_id = i.id and q.applied_at is null) as waiting
    from public.invoices i where i.deleted_at is null),
chain(benefit_id, invoice_id, named_lot, id, depth) as (
  select b.id, b.invoice_id, b.lot_id, b.lot_id, 0 from public.invoice_benefit_values b where b.lot_id is not null
  union all
  select c.benefit_id, c.invoice_id, c.named_lot, p.id, c.depth + 1
    from chain c join public.customer_credit_lots l on l.id = c.id
    join public.customer_credit_lots p on p.id = l.reassigned_from_lot_id
     and (p.source_type, p.source_record_id) is not distinct from (l.source_type, l.source_record_id)
   where c.depth < 12),
found(reason, invoice_id, n) as (
  -- 470 refuses to install (each needs a decision first; a data fix):
  select '1 refuses: credit on a lot its records replaced (no record names it: a refund by line, a Cancel or a refund in full of the invoice does not reach it)', c.invoice_id, count(*)
    from chain c join st on st.id = c.invoice_id join public.customer_credit_lots l on l.id = c.id
   where c.depth > 0 and l.remaining_amount > 0 and l.status = 'active'
   group by c.invoice_id
  union all
  select '2 refuses: cancelled, refunded or waiting for a reopening''s payment, with what its cancellation holds back on a lot its records replaced (a refund by line while a reopening waits would not find it)', c.invoice_id, count(*)
    from chain c join st on st.id = c.invoice_id
    join public.customer_credit_ledger e on e.lot_id = c.id and e.entry_type = 'adjust_decrease'
     and e.source_type = 'invoice_cancel_benefit' and e.source_record_id = c.invoice_id
    left join public.invoice_reopen_benefits q on q.source_ledger_id = e.id
   where c.depth > 0 and (st.status in ('cancelled', 'refunded') or st.waiting) and q.applied_at is null
   group by c.invoice_id
  union all
  -- 470 changes the answer (no refusal):
  select '3 changes: cancelled, refunded or waiting for a reopening''s payment, with credit on the lot its records name held by someone other than whoever holds the benefits (the next credit given back on its lots is held back for the holder, with it)', b.invoice_id, count(*)
    from public.invoice_benefit_values b join st on st.id = b.invoice_id join public.customer_credit_lots l on l.id = b.lot_id
   where (st.status in ('cancelled', 'refunded') or st.waiting) and l.remaining_amount > 0 and l.status = 'active'
     and l.customer_id is distinct from public.invoice_credit_live_holder(b.invoice_id, l.customer_id,
           case when public.invoice_benefit_moved_to_other(b.id) then 'infinity'::timestamptz else l.created_at end)
   group by b.invoice_id
  union all
  select '4 changes: cancelled, refunded or waiting for a reopening''s payment, with sales paid from a lot its records replaced that can still be refunded or corrected (their credit is now held back for whoever holds the benefits: on a cancelled invoice it adds to an amount owed back an Owner or Manager stated; while a reopening waits it is queued for its payment)', c.invoice_id, count(distinct c.id)
    from chain c join st on st.id = c.invoice_id
   where c.depth > 0 and (st.status in ('cancelled', 'refunded') or st.waiting)
     and (exists (select 1 from public.invoice_line_credit_allocations a where a.lot_id = c.id and a.amount > coalesce(a.reversed_amount, 0))
          or exists (select 1 from public.special_credit_allocations s where s.lot_id = c.id and s.amount > coalesce(s.reversed_amount, 0)))
   group by c.invoice_id
  union all
  select '5 changes: asked to be cancelled or refunded (the legacy statuses), with sales paid from its lots that can still be refunded or corrected (their credit now follows to whoever holds the benefits as for a paid invoice; before, it stayed where it went back)', c.invoice_id, count(distinct c.id)
    from chain c join st on st.id = c.invoice_id
   where st.status in ('cancellation_requested', 'refund_requested')
     and (exists (select 1 from public.invoice_line_credit_allocations a where a.lot_id = c.id and a.amount > coalesce(a.reversed_amount, 0))
          or exists (select 1 from public.special_credit_allocations s where s.lot_id = c.id and s.amount > coalesce(s.reversed_amount, 0)))
   group by c.invoice_id)
select f.reason, i.invoice_no, f.n
  from found f join public.invoices i on i.id = f.invoice_id
 order by f.reason, i.invoice_no
$hq$;
-- The held-back reason 470 writes, and its rows on a lot.
create function pg_temp.t470_held(p_lot uuid) returns numeric language sql as $f$
  select coalesce(sum(e.amount), 0) from customer_credit_ledger e
   where e.lot_id = p_lot and e.entry_type = 'adjust_decrease' and e.source_type = 'invoice_cancel_benefit'
     and e.reason = 'Held back by the invoice''s cancellation for whoever holds its benefits now' $f$;
-- The package's own benefit row (the one an Owner did not move in).
create function pg_temp.t470_own(p_inv uuid) returns uuid language sql as $f$
  select bv.id from invoice_benefit_values bv
   where bv.invoice_id = p_inv and bv.lot_id is not null
     and not exists (select 1 from invoice_benefit_transfers t where t.replacement_benefit_id = bv.id)
   order by bv.created_at, bv.id limit 1 $f$;


-- Unapplied queue rows of an invoice on a lot (count, sum, requests).
create function pg_temp.t470_waiting(p_inv uuid, p_lot uuid) returns text language sql as $f$
  select count(*) || '/' || coalesce(sum(q.amount), 0) || '/' || count(distinct q.request_id)
    from invoice_reopen_benefits q join customer_credit_ledger e on e.id = q.source_ledger_id
   where q.invoice_id = p_inv and q.applied_at is null and e.lot_id = p_lot $f$;
-- The triggers on invoices (their definitions, by name).
create function pg_temp.t470_inv_triggers() returns text language sql as $f$
  select md5(string_agg(pg_get_triggerdef(oid), E'\n' order by tgname)) || ' ' || count(*)
    from pg_trigger where tgrelid = 'public.invoices'::regclass and not tgisinternal $f$;

-- ===== S. Where it starts =====
create temp table t470_fp(k text primary key, v text);
create function pg_temp.t470_grants(p_without text[] default '{}') returns text language sql as $f$
  select md5(string_agg(p.oid::regprocedure::text || '=' || coalesce(p.proacl::text, ''), '|' order by p.oid::regprocedure::text))
    from pg_proc p where p.pronamespace = 'public'::regnamespace and not (p.proname = any (p_without)) $f$;
create function pg_temp.t470_grant_set(p_sig text) returns text[] language sql as $f$
  select array_agg(x::text order by x::text) from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || p_sig) $f$;
insert into t470_fp values ('start', pg_temp.t470_fingerprint()), ('grants', pg_temp.t470_grants()), ('triggers', pg_temp.t470_inv_triggers());
-- The function 470 changes: BEFORE (production, 24 Oct 2026: 463's AFTER)
-- and AFTER. It adds nothing.
-- (471, where it is in, changes it again: after471; 472, where it is in,
-- again: after472.)
create temp table t470_md5(sig text primary key, before text, after text, after471 text, after472 text);
insert into t470_md5 values
  ('credit_given_back_follows(uuid)', '844b73106bbf362768ed4a899ceb00d5', 'b7720a148f5371bd2bd844d3076ea3b2', '1417d83e7d7be49209f5cd1369d07ec7',
   'f2a7a4d1ca28f0865b14e3f1e5e02bbb');
create function pg_temp.t470_at(p_col text) returns boolean language sql as $f$
  select bool_and(case when p_col = 'before' then md5(pg_get_functiondef(to_regprocedure('public.' || m.sig))) = m.before
                       else md5(pg_get_functiondef(to_regprocedure('public.' || m.sig)))
                            = case when pg_temp.t470_472_in() then m.after472
                                   when pg_temp.t470_471_in() then m.after471 else m.after end end)
    from t470_md5 m $f$;
do $$ begin
  perform pg_temp.t470_check(pg_temp.t470_462_in() and pg_temp.t470_463_in(), 'S 462 and 463 are in (470 goes in after them)');
  perform pg_temp.t470_check(split_part(pg_temp.t470_inv_triggers(), ' ', 1) = '92c94e3ebc6113a68d972330bbca8938',
    'S the triggers on invoices are as read on production (24 Oct 2026): ' || pg_temp.t470_inv_triggers());
end $$;
\if :{?nomig}
do $$ begin
  perform pg_temp.t470_check(pg_temp.t470_in() and pg_temp.t470_at('after'), 'S -v nomig=1: 470 is in, as tested');
end $$;
\else
do $$ begin
  perform pg_temp.t470_check(not pg_temp.t470_in() and pg_temp.t470_at('before'),
    'S 470 is not in yet and the forwarder is 463''s (this suite installs it; use -v nomig=1 where it is in)');
end $$;

-- ===== R. Before 470: each case reproduced (undone afterwards) =====
-- A 'fixed' case does not end as 470 makes it; a control does, exactly; a
-- 'changed' one gives its old answer.
savepoint t470_r;
do $$
declare c record; o jsonb; res text := '';
begin
  for c in select * from t470_cases order by ord loop
    o := pg_temp.t470_run('before', c.k, c.steps);
    if c.kind = 'fixed' then
      perform pg_temp.t470_check(not (pg_temp.t470_meets(o, c.expect) and coalesce(o->>'invariants', '') = ''),
        'R ' || c.k || ' already ends as 470 makes it, without 470: ' || o::text);
      res := res || format(E'\n  %s: %s; net %s%s%s', c.k, (select string_agg(h.key || ' ' || (h.value #>> '{}'), ', ' order by h.key) from jsonb_each(o->'holds') h),
        o->>'net', coalesce('; ' || nullif(o->>'invariants', ''), ''), coalesce('; refused: ' || left(o->>'error', 100), ''));
    elsif c.kind = 'changed' then
      perform pg_temp.t470_check(pg_temp.t470_meets(o, c.expect_before) and coalesce(o->>'invariants', '') = '',
        'R changed ' || c.k || ' without 470: ' || coalesce(pg_temp.t470_diff(o, c.expect_before), '') || ' ' || o::text);
    else
      perform pg_temp.t470_check(pg_temp.t470_meets(o, c.expect) and coalesce(o->>'invariants', '') = ''
          and coalesce((o->>'cancel_left')::numeric, 0) = 0,
        'R control ' || c.k || ' without 470: ' || coalesce(pg_temp.t470_diff(o, c.expect), '') || ' ' || o::text);
    end if;
  end loop;
  -- And two states for the header's query: a reopening still waiting with
  -- S2's credit on the lot it went back to (1), and the legacy status with
  -- S2 still to be refunded (5).
  perform pg_temp.t470_run('before', 'K7wq', 'sale A cp; spend A; spend A; move 1 F; change B; unspend S1; cancel; back 1 60 F; reopen; unspend S2');
  perform pg_temp.t470_run('before', 'LGq', 'sale A cp; spend A; spend A; move 1 F; change B; unspend S1; legacy cancellation_requested');
  raise notice 'PASS R: without 470 every fixed case ends otherwise (the faults reproduced), the changed one gives its old answer, the controls as expected:%', res;
end $$;

-- ===== Q. The header's read-only query, on these states =====
create temp table t470_q as select * from pg_temp.t470_header_query();
create function pg_temp.t470_q_has(p_reason text, p_case text) returns boolean language sql as $f$
  select exists (select 1 from t470_q q join invoices i on i.invoice_no = q.invoice_no
                  where left(q.reason, 1) = p_reason and i.id = pg_temp.t470_id('before/' || p_case || '/inv')) $f$;
do $$
declare v_want text; v_got text; c record;
begin
  -- 1: exactly the states with credit on a lot no record names (any status:
  -- cancelled, paid after a refund by line while it waited, waiting).
  select string_agg(i.invoice_no, ', ' order by i.invoice_no) into v_want
    from t470_res r join invoices i on i.id = pg_temp.t470_id('before/' || r.k || '/inv')
   where r.phase = 'before' and r.v->>'invariants' like '%no record names%';
  select string_agg(invoice_no, ', ' order by invoice_no) into v_got from t470_q where left(reason, 1) = '1';
  perform pg_temp.t470_check(v_want is not null and v_got = v_want, 'Q 1 lists ' || coalesce(v_got, '-') || ', not ' || coalesce(v_want, '-'));
  perform pg_temp.t470_check(pg_temp.t470_q_has('1', 'K7b') and pg_temp.t470_q_has('1', 'Z1') and pg_temp.t470_q_has('1', 'K7wq'),
    'Q 1 does not list K7b (cancelled), Z1 (paid) and K7wq (waiting)');
  -- 2: none of these states (each cancellation's rows are on the lot the records name).
  perform pg_temp.t470_check(not exists (select 1 from t470_q where left(reason, 1) = '2'), 'Q 2 lists invoices');
  -- 4: sales still refundable from a replaced lot of a cancelled package;
  -- 5: the legacy status with a sale still refundable.
  foreach v_want in array array['4:K7fa', '4:K7fd', '5:LGq'] loop
    perform pg_temp.t470_check(pg_temp.t470_q_has(split_part(v_want, ':', 1), split_part(v_want, ':', 2)), 'Q ' || v_want || ' is not listed');
  end loop;
  -- The controls are not listed under 1 or 2.
  for c in select * from t470_cases where kind = 'control' loop
    perform pg_temp.t470_check(not exists (select 1 from t470_q q join invoices i on i.invoice_no = q.invoice_no
                                            where left(q.reason, 1) in ('1', '2') and i.id = pg_temp.t470_id('before/' || c.k || '/inv')),
      'Q control ' || c.k || ' is listed');
  end loop;
  raise notice 'PASS Q: the header''s read-only query lists % invoices (%), each reason as expected; the controls not listed under 1 or 2',
    (select count(distinct invoice_no) from t470_q),
    (select string_agg(left(reason, 1) || ' ' || n, ', ' order by left(reason, 1)) from (select reason, count(*) n from t470_q group by reason) x);
end $$;

-- ===== 9. The refusals, each changing nothing =====
-- 9a With these states in (credit on a lot the records replaced): refused,
-- naming exactly the invoices Q lists under 1.
savepoint t470_9;
\set ON_ERROR_STOP off
\ir ../../../supabase/470_cancelled_package_refund_reaches_given_back_credit.sql
\set ON_ERROR_STOP on
rollback to savepoint t470_9;
select :'LAST_ERROR_MESSAGE' as t470_9a \gset
select set_config('t470.msg', :'t470_9a', false);
do $$
declare m text := current_setting('t470.msg'); v text;
begin
  select string_agg(invoice_no, ', ' order by invoice_no) into v from t470_q where left(reason, 1) = '1';
  perform pg_temp.t470_check(m = format('470: %s invoice(s) have credit on a lot their records replaced (%s): no record names it, so a refund by line, a Cancel or a refund in full of the invoice does not reach it. Decide where it belongs (a data fix), then apply. Nothing was changed.',
                                        (select count(*) from t470_q where left(reason, 1) = '1'), v)
      and not pg_temp.t470_in() and pg_temp.t470_at('before'),
    '9a refused with: ' || m);
end $$;
-- Keep R's outcomes; undo its records.
select coalesce(jsonb_object_agg(k, v), '{}'::jsonb)::text as t470_rbefore from t470_res where phase = 'before' \gset
rollback to savepoint t470_r;
insert into t470_res select 'before', key, value from jsonb_each(:'t470_rbefore'::jsonb);
do $$ begin
  perform pg_temp.t470_check((select count(*) from t470_res where phase = 'before') = (select count(*) from t470_cases) + 2
      and pg_temp.t470_fingerprint() = (select v from t470_fp where k = 'start'),
    'R undone, its outcomes kept');
end $$;

-- 9b A cancellation's rows on a lot the records replaced (a stand-in: the
-- benefit row repointed to a new empty lot reissued from the one the cancel
-- took from): refused, naming it.
savepoint t470_9;
do $$
declare inv uuid; b uuid; old uuid; nu uuid := gen_random_uuid();
begin
  perform pg_temp.t470_run('9b', 'X', 'sale A cp; spend A; spend A; move 1 F; change B; unspend S1; cancel');
  inv := pg_temp.t470_id('9b/X/inv'); b := pg_temp.t470_own(inv);
  select lot_id into old from invoice_benefit_values where id = b;
  insert into customer_credit_lots
  select (jsonb_populate_record(null::customer_credit_lots, to_jsonb(l) || jsonb_build_object('id', nu, 'original_amount', 1,
            'remaining_amount', 0, 'reassigned_from_lot_id', l.id, 'created_at', clock_timestamp()))).*
    from customer_credit_lots l where l.id = old;
  update invoice_benefit_values set lot_id = nu where id = b;
end $$;
select invoice_no as t470_9inv from invoices where id = pg_temp.t470_id('9b/X/inv') \gset
\set ON_ERROR_STOP off
\ir ../../../supabase/470_cancelled_package_refund_reaches_given_back_credit.sql
\set ON_ERROR_STOP on
rollback to savepoint t470_9;
select set_config('t470.msg', :'LAST_ERROR_MESSAGE', false), set_config('t470.inv', :'t470_9inv', false);
do $$ begin
  perform pg_temp.t470_check(current_setting('t470.msg') = format('470: 1 invoice(s) cancelled, refunded or waiting for a reopening''s payment have what their cancellation holds back on a lot their records replaced (%s). Decide where it belongs (a data fix), then apply. Nothing was changed.', current_setting('t470.inv'))
      and not pg_temp.t470_in(), '9b refused with: ' || current_setting('t470.msg'));
end $$;
-- 9c A function it relies on is not as read (a setting added to it).
savepoint t470_9;
alter function public.invoice_financial_position(uuid) set work_mem = '64kB';
\set ON_ERROR_STOP off
\ir ../../../supabase/470_cancelled_package_refund_reaches_given_back_credit.sql
\set ON_ERROR_STOP on
rollback to savepoint t470_9;
select set_config('t470.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t470_check(current_setting('t470.msg') like '470: public.invoice_financial_position(uuid) is missing or not the version this was tested against (md5 %). Re-read it and re-test before applying.'
      and not pg_temp.t470_in(), '9c refused with: ' || current_setting('t470.msg'));
end $$;
-- 9d A new reader or writer of a cancellation's ledger rows.
savepoint t470_9;
create function public.t470_probe_cancel_rows() returns text language sql as $f$ select 'invoice_cancel_benefit'::text $f$;
\set ON_ERROR_STOP off
\ir ../../../supabase/470_cancelled_package_refund_reaches_given_back_credit.sql
\set ON_ERROR_STOP on
rollback to savepoint t470_9;
select set_config('t470.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t470_check(current_setting('t470.msg') like '470: what reads or writes a cancellation''s ledger rows is not as read on 24 Oct 2026 (%t470_probe_cancel_rows()%)'
      and not pg_temp.t470_in(), '9d refused with: ' || current_setting('t470.msg'));
end $$;
-- 9e A trigger on invoices that was not there when this was read (an update
-- of an invoice's amount owed back would run it).
savepoint t470_9;
create trigger t470_probe after update on public.invoices for each row execute function public.trg_lock_on_settle();
\set ON_ERROR_STOP off
\ir ../../../supabase/470_cancelled_package_refund_reaches_given_back_credit.sql
\set ON_ERROR_STOP on
rollback to savepoint t470_9;
select set_config('t470.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t470_check(current_setting('t470.msg') like '470: the triggers on invoices are not as read on 24 Oct 2026 (20 triggers, md5 %)%'
      and not pg_temp.t470_in(), '9e refused with: ' || current_setting('t470.msg'));
end $$;
-- 9f The forwarder is neither 463's nor 470's.
savepoint t470_9;
alter function public.credit_given_back_follows(uuid) set work_mem = '64kB';
\set ON_ERROR_STOP off
\ir ../../../supabase/470_cancelled_package_refund_reaches_given_back_credit.sql
\set ON_ERROR_STOP on
rollback to savepoint t470_9;
select set_config('t470.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t470_check(current_setting('t470.msg') like '470: public.credit_given_back_follows(uuid) is not the version this was tested against (md5 %). Re-read it and re-test before applying.'
      and not pg_temp.t470_in(), '9f refused with: ' || current_setting('t470.msg'));
end $$;
-- 9h Another function takes its name (an overload).
savepoint t470_9;
create function public.credit_given_back_follows(p text) returns void language sql as $f$ select $f$;
\set ON_ERROR_STOP off
\ir ../../../supabase/470_cancelled_package_refund_reaches_given_back_credit.sql
\set ON_ERROR_STOP on
rollback to savepoint t470_9;
select set_config('t470.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t470_check(current_setting('t470.msg') = '470: another function takes the name of the one this changes: credit_given_back_follows(text)'
      and not pg_temp.t470_in(), '9h refused with: ' || current_setting('t470.msg'));
end $$;
-- 9g The same grants in another order: installs (compared as sets).
savepoint t470_9;
revoke execute on function public.credit_given_back_follows(uuid) from postgres;
grant execute on function public.credit_given_back_follows(uuid) to postgres;
\ir ../../../supabase/470_cancelled_package_refund_reaches_given_back_credit.sql
do $$ begin
  perform pg_temp.t470_check(pg_temp.t470_in() and pg_temp.t470_at('after'), '9g the same grants in another order stopped it');
end $$;
rollback to savepoint t470_9;
do $$ begin
  perform pg_temp.t470_check(pg_temp.t470_fingerprint() = (select v from t470_fp where k = 'start') and not pg_temp.t470_in()
      and pg_temp.t470_grants() = (select v from t470_fp where k = 'grants'),
    '9 the refusals left a change');
  raise notice 'PASS 9: refused, changing nothing: credit on a lot the records replaced (the R states: the invoices the header''s query lists under 1), a cancellation''s rows on a lot the records replaced (9b), a function it relies on not as tested, a new reader of a cancellation''s rows, a new trigger on invoices, the forwarder not as tested, an overload of its name. The same grants in another order do not stop it';
end $$;

-- ===== M. Begun before 470, finished after it (the mid set) =====
-- Cancelled when it goes in (S2 refunded after); the guided Cancel's state;
-- waiting for its reopening's payment (S2 refunded after; a waiting
-- reopening with S2's credit already on the lot it went back to is refused,
-- 9a).
create temp table t470_mid(k text primary key, ord serial, split int, steps text, expect jsonb);
insert into t470_mid(k, split, steps, expect) select 'm' || k, s, steps, expect from (values
  ('K7b', 7), ('Z1', 7), ('K7r', 7), ('M1', 7), ('K7gc', 7), ('K7gcx', 8), ('K7gcv', 8), ('C0', 6), ('K7fa', 7),
  ('K7wc', 9), ('Z1w', 9), ('K7w', 9), ('K7wg', 9)) x(k, s)
  join t470_cases c using (k);
do $$ declare c record; begin
  for c in select * from t470_mid order by ord loop
    perform pg_temp.t470_run('mid', c.k, c.steps, 1, c.split);
  end loop;
end $$;
\endif

-- Where 471 is in too (-v nomig=1): without a reissue, credit given back
-- while the package is cancelled is held back in place too (471), so the
-- controls G2 and G3 end the 471 way: A holds nothing, and G3's refund by
-- line pays it back (net S$0). (471's suite checks them and their siblings.)
do $$ begin
  if pg_temp.t470_471_in() then
    update t470_cases set expect = '{"holds":{"A":"0.00","F":"0.00"},"status":"cancelled","net":20}' where k = 'G2';
    update t470_cases set expect = '{"holds":{"A":"0.00","F":"0.00"},"status":"cancelled","net":0,"error":null}' where k = 'G3';
    raise notice 'NOTE 471: 471 is in: G2 and G3 end the 471 way (A S$0; G3 net S$0), KNOWN K (1) is checked as 471 settles it, P6 finds C0''s held-back row in place';
  end if;
end $$;

-- ===== 10. Install 470, twice =====
\if :{?nomig}
do $$ begin raise notice 'NOTE 10: -v nomig=1, so 470 is not installed here (R, Q, 9 and M are skipped)'; end $$;
\else
\ir ../../../supabase/470_cancelled_package_refund_reaches_given_back_credit.sql
do $$ begin insert into t470_fp values ('first', pg_temp.t470_fingerprint()); end $$;
\ir ../../../supabase/470_cancelled_package_refund_reaches_given_back_credit.sql
do $$ begin insert into t470_fp values ('second', pg_temp.t470_fingerprint()); end $$;
\endif
do $$
begin
  perform pg_temp.t470_check(pg_temp.t470_in() and pg_temp.t470_at('after'), '10 470 is not installed as tested');
  perform pg_temp.t470_check((select count(*) from pg_proc where pronamespace = 'public'::regnamespace
                               and proname = 'credit_given_back_follows') = 1, '10 an overload exists');
  -- Nothing added: no function, no trigger on invoices (the triggers there
  -- exactly as before), the forwarder's callers 462's trigger alone.
  perform pg_temp.t470_check(pg_temp.t470_inv_triggers() = (select v from t470_fp where k = 'triggers')
      and not exists (select 1 from pg_trigger where tgrelid = 'public.invoices'::regclass and tgname = 'invoice_status_credit_follows')
      and to_regprocedure('public.trg_invoice_credit_follows_status()') is null,
    '10 a trigger on invoices was added or changed: ' || pg_temp.t470_inv_triggers());
  perform pg_temp.t470_check(pg_temp.t470_grant_set('credit_given_back_follows(uuid)') = '{postgres=X/postgres,service_role=X/postgres}'
      and not has_function_privilege('anon', 'public.credit_given_back_follows(uuid)', 'execute')
      and not has_function_privilege('authenticated', 'public.credit_given_back_follows(uuid)', 'execute'),
    '10 who may call it is not as intended');
  if exists (select 1 from t470_fp where k = 'first') then
    perform pg_temp.t470_check((select v from t470_fp where k = 'second') = (select v from t470_fp where k = 'first'),
      '10 the second run of 470 changed functions');
    perform pg_temp.t470_check(split_part((select v from t470_fp where k = 'first'), ' ', 2)::int
                               = split_part((select v from t470_fp where k = 'start'), ' ', 2)::int,
      '10 470 added or dropped a function');
    perform pg_temp.t470_check(pg_temp.t470_grants() = (select v from t470_fp where k = 'grants'),
      '10 the grants changed');
  end if;
  raise notice 'PASS 10: 470 installed as tested (%); the forwarder at its AFTER, the server''s alone; nothing added (no function, no trigger: the triggers on invoices as before); %',
    pg_temp.t470_fingerprint(),
    coalesce((select 'the second run changed nothing, the grants as before' from t470_fp where k = 'first'), 'it was in before the suite (nomig)');
end $$;

-- ===== A. Each case after 470 =====
do $$
declare c record; o jsonb; b jsonb; res text := '';
begin
  for c in select * from t470_cases order by ord loop
    o := pg_temp.t470_run('after', c.k, c.steps);
    perform pg_temp.t470_check(pg_temp.t470_meets(o, c.expect),
      'A ' || c.k || ': ' || coalesce(pg_temp.t470_diff(o, c.expect), '') || ' ' || o::text);
    perform pg_temp.t470_check(coalesce(o->>'invariants', '') = '', 'A ' || c.k || ' invariants: ' || (o->>'invariants'));
    perform pg_temp.t470_check(coalesce((o->>'cancel_left')::numeric, 0) = 0,
      'A ' || c.k || ': Cancel leaves S$' || (o->>'cancel_left') || ' of the invoice''s credit behind');
    b := (select v from t470_res where phase = 'before' and k = c.k);
    -- (a refusal's text names its invoice, numbered differently in each run)
    if c.kind = 'control' and b is not null then
      perform pg_temp.t470_check(o - 'error' = b - 'error'
          and regexp_replace(coalesce(o->>'error', ''), 'INV-[0-9-]+', 'INV', 'g') = regexp_replace(coalesce(b->>'error', ''), 'INV-[0-9-]+', 'INV', 'g'),
        'A control ' || c.k || ' changed with 470: before ' || b::text || ', after ' || o::text);
    end if;
    res := res || format(E'\n  %s %s: %s; net %s%s', c.kind, c.k,
      (select string_agg(h.key || ' ' || (h.value #>> '{}'), ', ' order by h.key) from jsonb_each(o->'holds') h), o->>'net',
      coalesce('; cancel ' || (o->>'cancel') || ' due ' || (o->>'due'), '') || coalesce('; refused: ' || left(o->>'error', 100), ''));
  end loop;
  raise notice 'PASS A: after 470 each case ends by the Owner''s rules, the invariants hold in every case (no credit on a lot of the invoice''s family that no record names; ledgers balanced; no chain over 12; moved lots traced; named credit with the benefits'' holder; nothing held back once settled) and Cancel takes all of it back; the controls are exactly as before 470%:%',
    case when exists (select 1 from t470_res where phase = 'before') then '' else ' (no before figures: -v nomig=1)' end, res;
end $$;

-- ===== M (after). The mid set finished with 470 in =====
\if :{?nomig}
\else
do $$
declare c record; o jsonb; res text := '';
begin
  for c in select * from t470_mid order by ord loop
    o := pg_temp.t470_run('mid', c.k, c.steps, c.split + 1);
    perform pg_temp.t470_check(pg_temp.t470_meets(o, c.expect) and coalesce(o->>'invariants', '') = ''
        and coalesce((o->>'cancel_left')::numeric, 0) = 0,
      'M ' || c.k || ': ' || coalesce(pg_temp.t470_diff(o, c.expect), '') || ' ' || o::text);
    res := res || ' ' || c.k;
  end loop;
  raise notice 'PASS M: begun before 470 and finished after it, each ends as the whole case does after 470:%', res;
end $$;
\endif

-- ===== P. Probes =====
do $$
declare inv uuid; a uuid; b uuid; f uuid; ben uuid; lot customer_credit_lots%rowtype; prev uuid; o jsonb; m jsonb; n int; v_req uuid; v_msg text;
begin
  -- P1 K7p: held back for B on a lot the records name: B's, granted S$40
  -- (S$20 the cancellation already held, S$20 given back), holding S$0,
  -- both taken back on it with the held reason; the row holds back S$40;
  -- the cancellation's row on the lot it replaced is closed (its queue row
  -- applied); A's lot drawn down by S$20; the invoice's Audit Log says so;
  -- the statements: A's balance S$0 (credit returned, then taken off), B's
  -- S$0 (credit added, then held back).
  inv := pg_temp.t470_id('after/K7p/inv'); a := pg_temp.t470_id('after/K7p/A'); b := pg_temp.t470_id('after/K7p/B');
  ben := pg_temp.t470_own(inv);
  select l.* into lot from invoice_benefit_values bv join customer_credit_lots l on l.id = bv.lot_id where bv.id = ben;
  prev := lot.reassigned_from_lot_id;
  perform pg_temp.t470_check(lot.customer_id = b and lot.original_amount = 40 and lot.remaining_amount = 0
      and pg_temp.t470_held(lot.id) = 40
      and (select count(*) from customer_credit_ledger e where e.lot_id = lot.id and e.entry_type = 'adjust_decrease' and e.source_type = 'invoice_cancel_benefit') = 2
      and (select count(*) from customer_credit_ledger e where e.lot_id = lot.id and e.entry_type = 'grant'
            and e.source_type = 'credit_given_back_reassignment_in' and e.amount = 40) = 1
      and (select cancelled_unused_value from invoice_benefit_values where id = ben) = 40
      and (select s.credit_lot_id from credit_package_sales s where s.invoice_id = inv) = lot.id,
    'P1 K7p: the held-back lot ' || to_jsonb(lot)::text);
  perform pg_temp.t470_check(exists (select 1 from customer_credit_ledger e join invoice_reopen_benefits q on q.source_ledger_id = e.id
                                      where e.lot_id = prev and e.source_type = 'invoice_cancel_benefit' and q.applied_at is not null)
      and not exists (select 1 from invoice_reopen_benefits q where q.invoice_id = inv and q.applied_at is null)
      and (select count(*) from customer_credit_ledger e join customer_credit_lots l on l.id = e.lot_id
            where e.source_record_id = inv and e.source_type = 'credit_given_back_reassignment_out' and l.customer_id = a and e.amount = 20) = 2
      and (select count(*) from audit_logs al where al.record_id = inv and al.action = 'credit_given_back_followed'
            and (al.new_data->>'held_back')::numeric = 20 and (al.new_data->>'held_back_before')::numeric = 20
            and al.new_data->>'to_customer' = b::text and al.new_data->>'queued_for_request' is null) = 1,
    'P1 K7p: the cancellation''s row it replaced, A''s draw-downs or the Audit Log');
  perform pg_temp.t470_check(
        (select wallet_balance from customer_credit_statement(a) order by entry_date desc, entry_seq desc limit 1) = 0
    and (select wallet_balance from customer_credit_statement(b) order by entry_date desc, entry_seq desc limit 1) = 0
    and (select count(*) from customer_credit_statement(b)
          where description = 'Adjustment — decrease — Held back by the invoice''s cancellation for whoever holds its benefits now') = 2
    and (select count(*) from customer_credit_statement(b)
          where description = 'Credit added — Credit given back goes to whoever holds the invoice''s benefits now' and credit_added = 40) = 1,
    'P1 K7p: the credit statements');
  -- P2 What is owed back grows by the money a refund by line of the row
  -- pays back for what is held back, not by its credit: S$0 -> S$20 on the
  -- S$100 package (K7gc), S$18.18 on the Bonus package (K7gcx), S$14.00 on
  -- the Premium Bundle (K7gcv), S$13.64 on that bundle discounted (K7gcd),
  -- for S$20 of credit each; in the Audit Log (the credit held back and the
  -- money added). It is what the refund options offer, the Finance panel's
  -- and Cancel's refund due, and the Finance panel keeps the rest of what
  -- was received for what was used. After the refund by line (K7gcb,
  -- K7gcbx, K7gcbv, K7gcbd) nothing is owed back and nothing more can be
  -- paid back.
  for o in select x from jsonb_array_elements('[["K7gc", "K7gcb", 20], ["K7gcx", "K7gcbx", 18.18],
                                               ["K7gcv", "K7gcbv", 14], ["K7gcd", "K7gcbd", 13.64]]'::jsonb) x loop
    inv := pg_temp.t470_id('after/' || (o->>0) || '/inv'); m := pg_temp.t470_money(inv);
    perform pg_temp.t470_check((m->>'owed')::numeric = (o->>2)::numeric and (m->>'due')::numeric = (o->>2)::numeric
        and (m->>'by_line')::numeric = (o->>2)::numeric and (m->>'plan_due')::numeric = (o->>2)::numeric
        and (m->>'kept')::numeric = (m->>'net')::numeric - (o->>2)::numeric
        and (select count(*) from audit_logs al where al.record_id = inv and al.action = 'credit_given_back_followed'
              and (al.new_data->>'refund_owed')::numeric = 0 and (al.new_data->>'refund_owed_added')::numeric = (o->>2)::numeric
              and (al.new_data->>'refund_owed_now')::numeric = (o->>2)::numeric and (al.new_data->>'held_back')::numeric = 20) = 1,
      'P2 ' || (o->>0) || ': what is owed back is not what the refund by line can pay back: ' || m::text);
    inv := pg_temp.t470_id('after/' || (o->>1) || '/inv'); m := pg_temp.t470_money(inv);
    perform pg_temp.t470_check((m->>'owed')::numeric = 0 and (m->>'due')::numeric = 0 and (m->>'by_line')::numeric = 0
        and (m->>'kept')::numeric = (m->>'net')::numeric,
      'P2 ' || (o->>1) || ': after the refund by line something is still owed back: ' || m::text);
  end loop;
  -- P3 446: a refund by line while the reopening waited closed both of the
  -- row's queued rows on the lot it names (the cancellation's S$20 and the
  -- held S$20), so the payment gave F alone: Z1 (S2 refunded while
  -- cancelled), M1 (then a merge while cancelled), Z1w (S2 refunded while it
  -- waited).
  foreach o in array array['"Z1"'::jsonb, '"M1"'::jsonb, '"Z1w"'::jsonb] loop
    inv := pg_temp.t470_id('after/' || (o #>> '{}') || '/inv'); ben := pg_temp.t470_own(inv);
    perform pg_temp.t470_check((select count(*) from audit_logs al where al.record_id = inv and al.action = 'reopen_credit_refunded'
                                 and al.new_data->>'benefit_id' = ben::text) = 2
        and (select coalesce(sum((al.new_data->>'refunded_amount')::numeric), 0) from audit_logs al where al.record_id = inv
              and al.action = 'reopen_credit_refunded' and al.new_data->>'benefit_id' = ben::text) = 40
        and (select coalesce(sum(remaining_amount), 0) from customer_credit_lots where id in (select pg_temp.t470_family(inv))
              and customer_id <> pg_temp.t470_id('after/' || (o #>> '{}') || '/F')) = 0,
      'P3 ' || (o #>> '{}') || ': 446''s matching did not find all of the row''s queued credit on the lot it names');
  end loop;
  -- P4 CH5: five refunds while cancelled, each its own commit: one held-back
  -- lot each, each taking the place of the one before, so the lot the
  -- records name stays two lots down and no lot of the family is deeper.
  inv := pg_temp.t470_id('after/CH5/inv');
  perform pg_temp.t470_check(
        (select count(*) from customer_credit_ledger where source_record_id = inv and source_type = 'credit_given_back_reassignment_in') = 6
    and pg_temp.t470_depth((select lot_id from invoice_benefit_values where id = pg_temp.t470_own(inv))) = 2
    and (select max(pg_temp.t470_depth(x)) from pg_temp.t470_family(inv) x) = 2,
    'P4 CH5: the chain grew: the named lot ' || pg_temp.t470_depth((select lot_id from invoice_benefit_values where id = pg_temp.t470_own(inv))) || ' down');
  -- P5 While a reopening waits, at commit: S2's refund goes back on A's lot
  -- (until the commit point), then is held back for B on the lot the records
  -- name, with the cancellation's S$20 there, both queued for the reopening's
  -- payment (its request); the cancellation's row on the lot it replaced is
  -- closed; F's queued S$60 is left as it was. Paid: B S$40, F S$60.
  perform pg_temp.t470_run('P', 'K7wx', 'sale A cp; spend A; spend A; move 1 F; change B; unspend S1; cancel; back 1 60 F; reopen');
  inv := pg_temp.t470_id('P/K7wx/inv'); a := pg_temp.t470_id('P/K7wx/A'); b := pg_temp.t470_id('P/K7wx/B'); f := pg_temp.t470_id('P/K7wx/F');
  ben := pg_temp.t470_own(inv);
  select q.request_id into v_req from invoice_reopen_benefits q where q.invoice_id = inv and q.applied_at is null limit 1;
  select lot_id into prev from invoice_benefit_values where id = ben;
  perform pg_temp.t470_check(pg_temp.t470_waiting(inv, prev) = '1/20.00/1', 'P5 K7wx: before, the cancellation''s S$20 waits on B''s lot: ' || pg_temp.t470_waiting(inv, prev));
  perform pg_temp.t470_unspend(pg_temp.t470_id('P/K7wx/S2'));
  perform pg_temp.t470_check((select sum(remaining_amount) from customer_credit_lots where customer_id = a) = 20, 'P5 K7wx: the forwarder ran before the commit');
  perform pg_temp.t470_commit();
  select l.* into lot from invoice_benefit_values bv join customer_credit_lots l on l.id = bv.lot_id where bv.id = ben;
  perform pg_temp.t470_check((select sum(remaining_amount) from customer_credit_lots where customer_id in (a, b)) = 0
      and lot.customer_id = b and lot.original_amount = 40 and lot.remaining_amount = 0 and lot.id <> prev
      and pg_temp.t470_waiting(inv, lot.id) = '2/40.00/1'
      and pg_temp.t470_waiting(inv, prev) = '0/0/0'
      and not exists (select 1 from invoice_reopen_benefits q where q.invoice_id = inv and q.applied_at is null and q.request_id <> v_req)
      and (select sum(q.amount) from invoice_reopen_benefits q join customer_credit_ledger e on e.id = q.source_ledger_id
            join customer_credit_lots l on l.id = e.lot_id where q.invoice_id = inv and q.applied_at is null and l.customer_id = f) = 60
      and (select cancelled_unused_value from invoice_benefit_values where id = ben) = 40
      and (select count(*) from audit_logs al where al.record_id = inv and al.action = 'credit_given_back_followed'
            and al.new_data->>'queued_for_request' = v_req::text) = 1,
    'P5 K7wx: at commit it was not held back for B and queued for the reopening''s payment: ' || pg_temp.t470_waiting(inv, lot.id));
  perform pg_temp.t470_pay(inv);
  perform pg_temp.t470_commit();
  perform pg_temp.t470_check((select sum(remaining_amount) from customer_credit_lots where customer_id = b) = 40
      and (select sum(remaining_amount) from customer_credit_lots where customer_id = f) = 60
      and (select coalesce(sum(remaining_amount), 0) from customer_credit_lots where customer_id = a) = 0
      and not exists (select 1 from invoice_reopen_benefits q where q.invoice_id = inv and q.applied_at is null)
      and (select cancelled_unused_value from invoice_benefit_values where id = ben) = 0
      and pg_temp.t470_invariants(inv) = '',
    'P5 K7wx: the payment did not give B S$40 and F S$60');
  -- P6 Nothing more than before for the controls: nothing forwarded without
  -- a reissue (C0, C2), nothing held where a correction moved nothing (K7fd:
  -- S1's forward alone) or the package stayed paid (K7gr: two forwards).
  -- Where 471 is in, C0's S2 refunded while cancelled (no reissue) is held
  -- back in place: one held-back row, on A's own lot (the lot the sale
  -- names), and still nothing forwarded.
  perform pg_temp.t470_check(
        not exists (select 1 from customer_credit_ledger e where e.source_type like 'credit_given_back_reassignment_%'
                     and e.source_record_id in (pg_temp.t470_id('after/C0/inv'), pg_temp.t470_id('after/C2/inv'))),
    'P6 C0/C2: credit was forwarded without a reissue');
  perform pg_temp.t470_check(
        (select count(*) from customer_credit_ledger e where e.source_type = 'credit_given_back_reassignment_in'
          and e.source_record_id = pg_temp.t470_id('after/K7fd/inv')) = 1
    and (select count(*) from customer_credit_ledger e where e.source_type = 'credit_given_back_reassignment_in'
          and e.source_record_id = pg_temp.t470_id('after/K7gr/inv')) = 2
    and not exists (select 1 from customer_credit_ledger e where e.source_record_id in (pg_temp.t470_id('after/K7fd/inv'), pg_temp.t470_id('after/K7gr/inv'),
                                                                                       pg_temp.t470_id('after/LG2/inv'))
                     and e.reason = 'Held back by the invoice''s cancellation for whoever holds its benefits now')
    and (select count(*) from customer_credit_ledger e
          where e.source_record_id = pg_temp.t470_id('after/C0/inv')
            and e.reason = 'Held back by the invoice''s cancellation for whoever holds its benefits now'
            and e.lot_id = (select s.credit_lot_id from credit_package_sales s where s.invoice_id = pg_temp.t470_id('after/C0/inv'))
            and e.customer_id = pg_temp.t470_id('after/C0/A') and e.amount = 20)
        = case when pg_temp.t470_471_in() then 1 else 0 end
    and (select count(*) from customer_credit_ledger e
          where e.source_record_id = pg_temp.t470_id('after/C0/inv')
            and e.reason = 'Held back by the invoice''s cancellation for whoever holds its benefits now')
        = case when pg_temp.t470_471_in() then 1 else 0 end,
    'P6 K7fd/K7gr/C0/LG2: something was held back' || case when pg_temp.t470_471_in() then ' (471 in: C0''s one held-back row in place expected)' else '' end);
  -- P7 Every record deleted while cancelled: S2's refund is refused at
  -- commit, for the Owner, nothing recorded (462's P9 while paid).
  o := pg_temp.t470_run('P', 'P9c', 'sale A cp; spend A; spend A; move 1 F; change B; unspend S1; cancel; delete B; delete A; unspend S2');
  perform pg_temp.t470_check(o->>'error' like 'unspend S2: Credit given back on lot % belongs with the benefits of invoice %, but whoever holds them, the invoice''s customer and the customer it went back to are all deleted. Nothing was recorded; ask the Owner.'
      and o->'holds' @> '{"A":"0.00","B":"0.00","F":"0.00"}'
      and (select status::text from invoices where id = pg_temp.t470_id('P/P9c/S2')) = 'paid', 'P7 ' || o::text);
  -- P8 No event is left on invoices: with a reopened invoice paid (and its
  -- credit given back while it waited held back and queued) in this
  -- transaction, before its commit point, ALTER TABLE invoices works (a
  -- deferred trigger on invoices would refuse it: "pending trigger events").
  perform pg_temp.t470_run('P', 'AT', 'sale A cp; spend A; spend A; move 1 F; change B; unspend S1; cancel; back 1 60 F; reopen; unspend S2');
  perform pg_temp.t470_pay(pg_temp.t470_id('P/AT/inv'));
  begin
    execute 'alter table public.invoices disable trigger lock_on_settle';
    execute 'alter table public.invoices enable trigger lock_on_settle';
    v_msg := 'altered';
  exception when others then v_msg := sqlerrm;
  end;
  perform pg_temp.t470_check(v_msg = 'altered', 'P8 ALTER TABLE invoices with a reopened invoice paid: ' || v_msg);
  perform pg_temp.t470_commit();
  raise notice 'PASS P: K7p held back for B on a lot the records name (S$40 granted, S$0 held, two held-back rows; the cancellation''s row it replaced closed; A drawn down twice; the Audit Log; both statements at S$0); the amount owed back grows by the money a refund by line pays back for what is held back, not its credit (K7gc S$20, K7gcx S$18.18, K7gcv S$14.00, K7gcd S$13.64, each its refund options, refund due and Cancel''s), nothing owed back after the refund by line; 446''s matching found all of the row''s queued credit on the lot it names (Z1, M1, Z1w); CH5 two lots down after five refunds; while a reopening waits, at commit, held back for B and queued for its payment, which gives it to B (K7wx); nothing more for the controls; every record deleted: refused at commit; no event left on invoices (ALTER TABLE invoices works)';
end $$;

-- ===== K. KNOWN: not covered by 470 (each checked as it is) =====
do $$
declare o jsonb;
begin
  -- K1 (NOT COVERED 1): without a reissue, credit given back while the
  -- package is cancelled or refunded stays spendable on the package's own
  -- lot: after a guided Cancel that recorded the refund (G2, G3: A S$20, net
  -- S$20), and on a package refunded in full with an override (RX0: A S$20 of
  -- a refunded invoice).
  -- Where 471 is in (the Owner's answer to it, 26 Oct 2026), it is settled:
  -- held back in place, so A holds nothing; G3's refund by line pays it all
  -- back (net S$0); RX0 ends as RX1 (held back, owed to nobody: NOT COVERED
  -- 2, accepted).
  o := pg_temp.t470_run('K', 'RX0', 'sale A cp; spend A; backx 1; unspend S1');
  if pg_temp.t470_471_in() then
    perform pg_temp.t470_check((select v->'holds' from t470_res where phase = 'after' and k = 'G2') @> '{"A":"0.00"}'
        and (select (v->>'net')::numeric from t470_res where phase = 'after' and k = 'G2') = 20
        and (select (v->>'net')::numeric from t470_res where phase = 'after' and k = 'G3') = 0
        and (select v->>'error' from t470_res where phase = 'after' and k = 'G3') is null,
      'K1 (471 in) G2/G3: not held back in place: look at 471 again');
    perform pg_temp.t470_check(o->'holds' @> '{"A":"0.00"}' and o->>'status' = 'refunded' and (o->>'net')::numeric = 0
        and coalesce(o->>'invariants', '') = ''
        and (select cancelled_unused_value from invoice_benefit_values where id = pg_temp.t470_own(pg_temp.t470_id('K/RX0/inv'))) = 20,
      'K1 (471 in) RX0: ' || o::text || ': look at 471 again');
  else
    perform pg_temp.t470_check((select v->'holds' from t470_res where phase = 'after' and k = 'G2') @> '{"A":"20.00"}'
        and (select (v->>'net')::numeric from t470_res where phase = 'after' and k = 'G3') = 20, 'K1 G2/G3: look at 470''s NOT COVERED 1 again');
    perform pg_temp.t470_check(o->'holds' @> '{"A":"20.00"}' and o->>'status' = 'refunded' and (o->>'net')::numeric = 0
        and o->>'invariants' like '%refunded, but S$20.00 of its credit is still held%', 'K1 RX0: ' || o::text || ': look at 470''s NOT COVERED 1 again');
  end if;
  -- K2 (NOT COVERED 2): held back on a refunded invoice, owed to nobody (RX1:
  -- the row holds back S$20, net S$0).
  perform pg_temp.t470_check((select cancelled_unused_value from invoice_benefit_values where id = pg_temp.t470_own(pg_temp.t470_id('after/RX1/inv'))) = 20
      and (select (v->>'net')::numeric from t470_res where phase = 'after' and k = 'RX1') = 0, 'K2 RX1: look at 470''s NOT COVERED 2 again');
  -- K3 (NOT COVERED 3): credit given back while a reopening waits is not
  -- spendable until its payment (K7w2: B cannot spend it).
  perform pg_temp.t470_check((select v->>'error' from t470_res where phase = 'after' and k = 'K7w2') like 'spend B: Only 0 of the requested 20.00 could be funded by eligible credit%',
    'K3 K7w2: look at 470''s NOT COVERED 3 again');
  raise notice 'KNOWN K: (not covered by 470) (1) %; (2) held back on a refunded invoice, owed to nobody (RX1); (3) credit given back while a reopening waits is not spendable until its payment (K7w2)',
    case when pg_temp.t470_471_in()
         then 'without a reissue: settled by 471 (G2, G3: held back in place, A S$0, G3 paid back in full; RX0 ends as RX1)'
         else 'without a reissue, credit given back while the package is cancelled or refunded stays spendable on the package''s own lot (G2, G3: A S$20 after a guided Cancel that recorded the refund; RX0: A S$20 of a package refunded in full with an override)' end;
end $$;

rollback;
