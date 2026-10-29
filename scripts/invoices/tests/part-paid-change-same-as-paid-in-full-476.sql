-- 476: a package paid in part is changed to another customer as the same
-- package paid in full is: a 'transfer' change is refused once any of it
-- was used (TQn2) and moves it when nothing was (TQfix, TQcru); after a
-- 'keep' change all it gives later (its credit and Bonus, its vouchers and
-- allowance, its sale record and so its commission) goes to whoever holds
-- its benefits, with the lines sold with it, while a line a correction
-- added goes to the invoice's customer who pays for it (K1, X1, KAL, KAP,
-- KAL1); and the Pay dialog's read names who receives it (473's NOT COVERED
-- 1 and 2, the review of 475 to 478; the Owner, 27 Oct 2026: "Same as
-- paid-in-full", answers A, B, C and E).
-- supabase/476_part_paid_change_same_as_paid_in_full.sql (after 473, 474
-- and 475).
--
-- Every step goes through the app's own calls (473's suite harness, its
-- steps and readings, renamed): the invoice form (create_invoice_with_
-- details), its edit of an unpaid invoice and its correction of a paid or
-- part-paid one adding a line, alone or with the customer change in the
-- same save (correct_invoice), the Pay dialog (record_invoice_settlement),
-- Record Payment (in full, or of an amount: 'payp'), Correct payment (on a
-- session, or on the invoice's own payment: 'fixinv'), Cancel, Reopen, the
-- Finance panel's refund by line and "Record refund paid", Move
-- (transfer_invoice_unused_benefit), the invoice form's customer change
-- (correct_invoice, 'transfer' or 'keep'), a customer merge,
-- delete_customer, the Pay dialog's read (invoice_credit_receivers); an
-- Owner's reversal is reverse_credit_lot called as an active Owner (no page
-- calls it). Referrers are set on a case's made-up customers by its 'refs'
-- step, as the customer form records one, and the part-payment commission
-- layer registered by its 'layer' step (357's Register), with the commission
-- rates a copy's settings lack. Each app call is followed by what its
-- commit does (462's trigger is deferred; SET CONSTRAINTS ... IMMEDIATE,
-- then DEFERRED).
--
-- The cases (A the buyer, B and C later customers, K a record a merge
-- keeps, F a friend an Owner moved credit to, RA, RB, RC their referrers;
-- cp the S$100 Credit Package, cpb with a S$10 Bonus, pbv the S$140 Premium
-- Bundle with 2 vouchers; S1, S2 S$20 sessions paid from the package's
-- credit; 'cp 40': S$40 of S$100 paid, S$40 of its credit released before
-- full payment):
--   TQn2 and its siblings  473's KNOWN: S1 and S2 paid from the S$40, a
--              'transfer' change to B, paid in full (before 476: B S$60, A had
--              used S$40); the Premium Bundle, the Bonus package, two part
--              payments, a merge, a Cancel and Reopen first, an Owner's
--              reversal.
--   K1, K2 and their siblings  473's KNOWN: a 'keep' change to B before full
--              payment, then paid: the Bonus package, the Premium Bundle and
--              its 2 vouchers (K1v, Kvb: answer B), all released credit spent
--              first, a part payment after the change, two 'keep' changes, a
--              'transfer' then a 'keep', merges, Correct payment, Cancel and
--              Reopen around the change, another store, a session after it.
--   X1 to X10  two or more package or bundle lines of the invoice's own sale
--              ('cp,cp': the money goes to the credit lines one after
--              another, so S$40 paid releases on the first only).
--   KAL, KAL1, KAP, KALp  answer A: a line a correction added after the
--              'keep' change, in the same save as the change, before it, and
--              with a part payment after it (round 1's build: A S$200; now
--              A S$100, B S$100, as their paid-in-full counterparts KALF,
--              KALF1, KAPF); KAE a line an edit added before any money and
--              KAT2 two lines one correction added together (sold with the
--              others: A S$200, A S$300, as KAEF, KAT2F); KAT3 two corrections
--              (two sales: NOT COVERED 1c).
--   TQfix, TQfixp, TQcru, TQcrup  answer C: the payment corrected lower; a
--              Cancel, a reopening and the session refunded: a 'transfer'
--              change moves the lot (then paid in full: B S$100); controls
--              TQfixs (something used) and TQcrc (while cancelled): refused.
--   CK1, CK1v, CKAL, CX1, IK1, IK1m, IKAL, IX1  answer B: the sale records
--              and the commission of the buyer's referrer (RA) at settlement,
--              and on the part-payment layer registered (I...); CKF, CKTF
--              (paid in full, then 'keep' or 'transfer'); CKT (known, NOT
--              COVERED 2).
--   G5, G5p, C3c, C3cp, C5, L4  NOT COVERED 7: changed with 'keep', settled,
--              then part-paid again (a line added, a payment corrected
--              lower) with the layer registered: the sale record the buyer's,
--              the layer's commission the invoice's customer's referrer's
--              until paid in full again; G5F, C3cF their paid-in-full
--              counterparts (controls); P1 (in K) a payout in that window.
--   KV13       NOT COVERED 13 (known, not caused by 476): a package added by
--              a correction to an invoice paid in full releases credit for
--              the money that paid for the vouchers already issued.
--   Controls (the same with and without 476): TQ00, TQu (nothing spent, or
--   the session refunded first: a 'transfer' change moves it all), TQv0
--   (the bundle, nothing spent), W2c, KT ('keep' then 'transfer'), K1t
--   ('keep', paid, then 'transfer'), KF (paid in full, then 'keep'), K1can
--   ('keep', paid, cancelled), K1mv ('keep', paid, Move to F), TQc, TQn, W2
--   (refused as before), TQn2cx, TQcr, TQcc (changed while cancelled, then
--   reopened and paid: 473's NOT COVERED 3, the existing rule), X1F, X1T.
--   Known (476's NOT COVERED, checked as they are): Kdel (the buyer deleted:
--   the invoice's customer; 4); MK1p (a package split before 476: 3); CKT
--   ('transfer' and the sale record: 2); KAT3 (1c); TQcru's lot moved still
--   locked (9).
-- In every case 462's invariants (471's and 473's reading of them: the lots
-- a release record's chain reaches counting as named; a named lot holding
-- credit held by whoever holds the benefits) and Cancel (tried, undone)
-- taking all of the invoice's credit back from whoever holds it.
--
--   S. Where it starts: 462, 463, 470 to 475 in; 476 in (nomig) or not, the
--      six functions at their BEFORE and the three it adds absent.
--   R. Without 476 (skipped with -v nomig=1), undone: each 'fixed' case ends
--      otherwise (the fault reproduced: TQn2 B S$60; K1 A S$40, B S$60; K1v
--      B's vouchers and sale record; KAL B S$160; CK1 B's referrer; TQfix
--      refused ...); each control and known case as expected.
--   Q. The read-only query in 476's header (the same text), on states made
--      for it and the R states: what it lists, by reason (1 to 9).
--   9. Refusals, each changing nothing: a function it changes neither its
--      BEFORE nor its AFTER; one it adds there beside the others at their
--      BEFORE (partly in); a function it relies on not as tested; an
--      overload of a name it changes or adds; a new caller of the release,
--      the mover or update_invoice_internal; a new grant of credit; a new
--      writer of the release record; the trigger on invoices changed; a new
--      way to add invoice lines or to write revisions; a page allowed to
--      write revisions. The same grants in another order do not stop it.
--   M. Begun before 476, finished after it.
--  10. 476 installed twice: as tested, the second run changing nothing, three
--      functions added (two the server's alone, one signed-in staff's), the
--      grants of the others as before.
--   A. Each case after 476: who holds what, the invoice's customer, the
--      list's rows, the refusal's words, the sale records, the commission,
--      the invariants, Cancel; the controls exactly as before.
--   P. Probes: TQn2's list rows and review summary beside the package paid
--      in full's (TQc); the new row's record_id; 'keep' still offered; the
--      form still asked; K1's lots and sale record, K1v's vouchers; whom the
--      helper names; the sale groups; the Pay dialog's read, and its refusal
--      of anyone but staff of the invoice's store (P8); on a reopened
--      invoice the credit its settling payment gives back, by receiver (P7b).
--   K. KNOWN (476's NOT COVERED), checked as they are: 1c (KAT3), 2 (CKT,
--      CKTF), 3 (MK1p), 4 (Kdel), 7 (G5 to L4, G5F, C3cF, P1), 9 (TQcru's
--      lot moved locked), 13 (KV13).
--
-- Run on a copy of production as it is (475 in, 27 Oct 2026: e948504d, 1387
-- functions; 476 makes it cc718597, 1390):
--   psql -X -v ON_ERROR_STOP=1 -f scripts/invoices/tests/part-paid-change-same-as-paid-in-full-476.sql
-- It installs 476 itself (twice) inside its transaction. Where 476 is in
-- already, add -v nomig=1 (S checks it as tested; R, Q, 9 and M are skipped;
-- every case after 476 is still checked). Section 9 lets the install fail on
-- purpose (psql prints its ERROR); the suite then checks that message.
-- Disposable database only; everything is rolled back. Every name, code and
-- amount is invented (@example.com); the phones are numbers kept for fiction
-- (ACMA, +61491570000 to +61491570999).
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '10s';
set local statement_timeout = '1500s';

-- ── Set-up and the app's calls (462's, 470's and 471's suite harness, for 472) ───────
create temp table t476(k text primary key, id uuid);
create temp table t476_res(phase text, k text, v jsonb, primary key (phase, k));
create temp sequence t476_phone;
create function pg_temp.t476_id(p_k text) returns uuid language sql as $f$ select id from t476 where k = p_k $f$;
create function pg_temp.t476_put(p_k text, p_id uuid) returns uuid language sql as $f$
  insert into t476 values (p_k, p_id) on conflict (k) do update set id = excluded.id returning id $f$;
create function pg_temp.t476_check(p_ok boolean, p_label text) returns void language plpgsql as $f$
begin
  if not coalesce(p_ok, false) then raise exception 'FAIL %', p_label; end if;
end $f$;
create function pg_temp.t476_fingerprint() returns text language sql as $f$
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.oid::regprocedure::text)) || ' ' || count(*)
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prokind in ('f', 'p') $f$;
create function pg_temp.t476_463_in() returns boolean language sql as $f$
  select to_regprocedure('public.invoice_benefit_moved_to_other(uuid)') is not null $f$;
create function pg_temp.t476_462_in() returns boolean language sql as $f$
  select to_regprocedure('public.credit_given_back_follows(uuid)') is not null
     and exists (select 1 from pg_trigger where tgname = 'credit_given_back_follows'
                  and tgrelid = 'public.customer_credit_ledger'::regclass) $f$;
-- 471 is in: the forwarder is 471's or keeps its text (472's does).
create function pg_temp.t476_471_in() returns boolean language sql as $f$
  select to_regprocedure('public.credit_given_back_follows(uuid)') is not null
     and position('-- 471 (the Owner, 26 Oct 2026' in pg_get_functiondef('public.credit_given_back_follows(uuid)'::regprocedure)) > 0 $f$;
-- 472 is in: the forwarder is 472's (its text says so; S checks its md5).
create function pg_temp.t476_472_in() returns boolean language sql as $f$
  select to_regprocedure('public.credit_given_back_follows(uuid)') is not null
     and position('-- 472 (the Owner, 26 Oct 2026' in pg_get_functiondef('public.credit_given_back_follows(uuid)'::regprocedure)) > 0 $f$;
-- 473 is in: the list is 473's (its text says so; S checks its md5).
create function pg_temp.t476_473_in() returns boolean language sql as $f$
  select position('-- 473 (the Owner, 26 Oct 2026' in pg_get_functiondef('public.invoice_transferable_benefits(uuid)'::regprocedure)) > 0 $f$;
-- 475 is in: reopen_invoice is 475's (its text says so; S checks its md5).
create function pg_temp.t476_475_in() returns boolean language sql as $f$
  select position('-- 475 (the Owner, 27 Oct 2026' in pg_get_functiondef('public.reopen_invoice(uuid,text,uuid)'::regprocedure)) > 0 $f$;
-- 476 is in: the list, the mover and the release are 476's (their text
-- says so; S checks the md5s) and its three new functions are there.
create function pg_temp.t476_in() returns boolean language sql as $f$
  select position('-- 476 (the Owner, 27 Oct 2026' in pg_get_functiondef('public.invoice_transferable_benefits(uuid)'::regprocedure)) > 0
     and position('-- 476 (the Owner, 27 Oct 2026' in pg_get_functiondef('public.move_invoice_benefits_to_customer(uuid,uuid,uuid,text)'::regprocedure)) > 0
     and position('-- 476 (the Owner, 27 Oct 2026' in pg_get_functiondef('public.release_credit_package_paid_credit(uuid)'::regprocedure)) > 0
     and to_regprocedure('public.credit_line_benefits_holder(uuid)') is not null
     and to_regprocedure('public.credit_line_sale_group(uuid)') is not null
     and to_regprocedure('public.invoice_credit_receivers(uuid)') is not null $f$;
-- 470 is in (its text is in 471's and 472's too).
create function pg_temp.t476_470_in() returns boolean language sql as $f$
  select to_regprocedure('public.credit_given_back_follows(uuid)') is not null
     and position('-- 470 (the Owner, 24 Oct 2026' in pg_get_functiondef('public.credit_given_back_follows(uuid)'::regprocedure)) > 0 $f$;
-- What a commit does at the end of each app call (each is its own
-- transaction in the app): 462's deferred trigger on the ledger runs (471
-- adds no trigger: its change is in the function that trigger runs). Here
-- the suite is one transaction, so the trigger's queued rows are run at this
-- point. (Not where each step really commits: t476.autocommit 'on', for
-- running the same cases one call per transaction on a disposable copy.)
create function pg_temp.t476_commit() returns void language plpgsql as $f$
begin
  if coalesce(current_setting('t476.autocommit', true), '') = 'on' then return; end if;
  if pg_temp.t476_462_in() then
    execute 'set constraints public.credit_given_back_follows immediate';
    execute 'set constraints public.credit_given_back_follows deferred';
  end if;
end $f$;

do $$
declare own uuid := gen_random_uuid(); st uuid; st2 uuid; pm uuid; v uuid; cp uuid; cpb uuid; pbv uuid; svc uuid; svc5 uuid;
begin
  insert into auth.users(id, email) values (own, 't476-owner@example.com');
  insert into profiles(id, full_name, email, role, is_active) values (own, 'T476 Owner', 't476-owner@example.com', 'owner', true);
  perform set_config('request.jwt.claims', json_build_object('sub', own, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', own::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  insert into stores(name, code, country_code) values ('T476 Store', 'T476S1', 'SG') returning id into st;
  insert into stores(name, code, country_code) values ('T476 Other Store', 'T476S2', 'SG') returning id into st2;
  insert into payment_methods(name, is_active) values ('T476 Cash', true) returning id into pm;
  insert into vouchers(name, code, voucher_kind, qty_type, selling_price, is_active)
    values ('T476 Plain 30', 'T476-P30', 'normal', 'unlimited', 30, true) returning id into v;
  insert into voucher_store_prices(voucher_id, store_id, selling_price, available_at_store) values (v, st, 30, true), (v, st2, 30, true);
  insert into credit_packages(name, customer_price, paid_credit_amount, bonus_enabled, allow_product, allow_therapy)
    values ('T476 S$100', 100, 100, false, true, true) returning id into cp;
  insert into credit_package_stores(package_id, store_id) values (cp, st), (cp, st2);
  insert into credit_packages(name, customer_price, paid_credit_amount, bonus_enabled, bonus_value, allow_product, allow_therapy, grants_reward)
    values ('T476 S$100 + S$10', 100, 100, true, 10, true, true, false) returning id into cpb;
  insert into credit_package_stores(package_id, store_id) values (cpb, st), (cpb, st2);
  insert into premium_bundles(name, customer_payment_amount, paid_credit_amount, bonus_credit_amount, free_voucher_qty, grants_reward)
    values ('T476 Bundle S$140 + 2 vouchers', 140, 100, 40, 2, true) returning id into pbv;
  insert into premium_bundle_stores(bundle_id, store_id) values (pbv, st), (pbv, st2);
  insert into premium_bundle_vouchers(bundle_id, voucher_id) values (pbv, v);
  svc := (upsert_therapy_service(null, 'T476-SESSION', 'T476 Session', 20, 30, 'per_hours', 1, 5, null, true, null) ->> 'id')::uuid;
  perform set_therapy_service_store(svc, st, true, null);
  svc5 := (upsert_therapy_service(null, 'T476-SHORT', 'T476 Short session', 5, 15, 'per_hours', 1, 5, null, true, null) ->> 'id')::uuid;
  perform set_therapy_service_store(svc5, st, true, null);
  insert into t476 values ('own', own), ('store', st), ('store2', st2), ('pm', pm), ('v', v), ('cp', cp), ('cpb', cpb), ('pbv', pbv),
    ('svc', svc), ('svc5', svc5),
    ('wallet', (select id from payment_methods where name = 'Wallet — Credit Package Paid' and is_wallet_credit and deleted_at is null)),
    ('bwallet', (select id from payment_methods where name = 'Wallet — Premium Bundle Paid' and is_wallet_credit and deleted_at is null)),
    ('cbonus', (select id from payment_methods where name = 'Wallet — Credit Package Bonus' and is_wallet_credit and deleted_at is null));
  perform pg_temp.t476_check(pg_temp.t476_id('wallet') is not null and pg_temp.t476_id('bwallet') is not null, 'setup: the wallet methods (443) are there');
end $$;
-- 476 (answer B): commission rates, as production's settings have them (a
-- copy of production has no settings row). Staff commission off, and the
-- part-payment layer not registered unless a case's 'layer' step does it;
-- no case's customer has a referrer unless its 'refs' step sets one, so no
-- other case earns commission.
insert into app_settings(id) values (true) on conflict (id) do nothing;
update app_settings set commission_tier1_own_rate = 15, commission_tier1_third_rate = 4.5, commission_tier2_own_rate = 5,
       commission_tier2_third_rate = 5, staff_commission_rate = 0, instalment_commission_from = null where id = true;

-- A customer of one run of one case: '<phase>/<case>/<role>'.
create function pg_temp.t476_cust(p_k text) returns uuid language plpgsql as $f$
declare c uuid;
begin
  insert into customers(full_name, phone) values ('T476 ' || p_k, '+61491570' || lpad((nextval('t476_phone') % 1000)::text, 3, '0'))
    returning id into c;
  return pg_temp.t476_put(p_k, c);
end $f$;
-- The invoice form with these lines ('cp' / 'cpb' a Credit Package, 'pbv' the
-- Premium Bundle, 'v' a voucher line of p_qty units), with an Owner's manual
-- discount of p_discount (its reason given) where one is given, paid through
-- the Pay dialog: in full, or p_first of it (a part-paid package).
create function pg_temp.t476_sale(p_cust uuid, p_kinds text[], p_first numeric default null, p_qty int default 2,
                                  p_discount numeric default null)
  returns uuid language plpgsql as $f$
declare inv uuid; v_lines jsonb := '[]'; i int;
begin
  for i in 1 .. cardinality(p_kinds) loop
    v_lines := v_lines || jsonb_build_array(case
      when p_kinds[i] = 'v' then jsonb_build_object('kind', 'voucher', 'voucher_id', pg_temp.t476_id('v'), 'quantity', p_qty)
      when p_kinds[i] in ('cp', 'cpb') then jsonb_build_object('kind', 'credit_package', 'credit_package_id', pg_temp.t476_id(p_kinds[i]), 'quantity', 1)
      else jsonb_build_object('kind', 'premium_bundle', 'premium_bundle_id', pg_temp.t476_id('pbv'), 'quantity', 1,
        'voucher_selection', jsonb_build_array(jsonb_build_object('voucher_id', pg_temp.t476_id('v'), 'quantity', 2))) end);
  end loop;
  inv := create_invoice_with_details(pg_temp.t476_id('store'), p_cust, v_lines, jsonb_build_object('business_date', sg_today()::text)
           || case when p_discount is not null
                   then jsonb_build_object('manual_discount', p_discount, 'manual_discount_reason', 'T476 discount') else '{}'::jsonb end);
  perform record_invoice_settlement(inv, jsonb_build_object('receipts', jsonb_build_array(jsonb_build_object(
    'key', 'line-0', 'payment_method_id', pg_temp.t476_id('pm'),
    'amount', coalesce(p_first, (select total_amount from invoices where id = inv)),
    'payment_date', sg_today()::text)), 'arrangements', '[]'::jsonb), gen_random_uuid());
  return inv;
end $f$;
-- 476 (answer A): the invoice form with these lines, saved with nothing paid.
create function pg_temp.t476_draft(p_cust uuid, p_kinds text[]) returns uuid language plpgsql as $f$
declare v_lines jsonb := '[]'; i int;
begin
  for i in 1 .. cardinality(p_kinds) loop
    v_lines := v_lines || jsonb_build_array(case
      when p_kinds[i] in ('cp', 'cpb') then jsonb_build_object('kind', 'credit_package', 'credit_package_id', pg_temp.t476_id(p_kinds[i]), 'quantity', 1)
      else jsonb_build_object('kind', 'premium_bundle', 'premium_bundle_id', pg_temp.t476_id('pbv'), 'quantity', 1,
        'voucher_selection', jsonb_build_array(jsonb_build_object('voucher_id', pg_temp.t476_id('v'), 'quantity', 2))) end);
  end loop;
  return create_invoice_with_details(pg_temp.t476_id('store'), p_cust, v_lines, jsonb_build_object('business_date', sg_today()::text));
end $f$;
-- Record Payment of what is outstanding (nothing when it is settled).
create function pg_temp.t476_pay(p_inv uuid) returns void language plpgsql as $f$
begin
  if (invoice_financial_position(p_inv)->>'outstanding')::numeric > 0 then
    perform record_invoice_payment(p_inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.t476_id('pm'),
      'amount', (invoice_financial_position(p_inv)->>'outstanding')::numeric)), gen_random_uuid());
  end if;
end $f$;
-- The receipts that still hold p_amount between them, as the Finance panel
-- splits a refund across them.
create function pg_temp.t476_sources(p_inv uuid, p_amount numeric) returns jsonb language plpgsql as $f$
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
create function pg_temp.t476_line(p_inv uuid, p_n int default 1) returns uuid language sql as $f$
  select id from invoice_items where invoice_id = p_inv order by id offset p_n - 1 limit 1 $f$;
-- The Finance panel's refund by line of line p_n: p_amount off its Paid
-- benefit (the one an Owner did not move, or with p_holder the one p_holder
-- holds), or every unused benefit it still holds (p_amount null).
create function pg_temp.t476_back(p_inv uuid, p_n int, p_amount numeric default null, p_holder uuid default null)
  returns void language plpgsql as $f$
declare opts jsonb; ben jsonb; tot numeric; item uuid := pg_temp.t476_line(p_inv, p_n);
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
  if ben is null then raise exception 'T476: nothing to refund on that line'; end if;
  perform refund_invoice_recorded(p_inv, jsonb_build_array(jsonb_build_object('invoice_item_id', item, 'amount', tot, 'benefits', ben)),
    pg_temp.t476_sources(p_inv, tot), '[]'::jsonb, 'T476 by line', gen_random_uuid());
end $f$;
-- The invoice form's customer change, its lines as they are (and the store,
-- when given), with 'transfer' or 'keep'. The change's Audit Log row is
-- dated now, as a later call's is (the suite is one transaction).
create function pg_temp.t476_lines(p_inv uuid) returns jsonb language sql as $f$
  select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('invoice_item_id', it.id, 'kind', it.line_kind,
           'credit_package_id', it.credit_package_id, 'premium_bundle_id', it.premium_bundle_id, 'voucher_id', it.voucher_id,
           'quantity', it.quantity, 'unit_price', it.unit_price, 'voucher_selection', it.bundle_voucher_selection)) order by it.id)
    from invoice_items it where it.invoice_id = p_inv $f$;
create function pg_temp.t476_change(p_inv uuid, p_cust uuid, p_action text default 'transfer', p_store text default null)
  returns void language plpgsql as $f$
begin
  perform correct_invoice(p_inv, pg_temp.t476_lines(p_inv),
    jsonb_build_object('expected_edit_count', (select edit_count from invoices where id = p_inv),
      'customer_id', p_cust, 'store_id', coalesce(pg_temp.t476_id(p_store), (select store_id from invoices where id = p_inv)),
      'benefit_action', p_action),
    'T476 wrong customer', gen_random_uuid());
  update audit_logs set created_at = clock_timestamp()
   where record_id = p_inv and action = 'invoice_benefits_followed_reassignment' and new_data->>'to_customer' = p_cust::text
     and created_at = now();
end $f$;
create function pg_temp.t476_merge(p_keep uuid, p_dup uuid) returns void language plpgsql as $f$
begin
  perform merge_customer_records(p_keep, p_dup, 'T476 the same person', gen_random_uuid());
end $f$;
-- The Finance panel's Move of line p_n's unused benefit (its Paid credit,
-- or its Bonus with p_kind 'bonus', or a voucher) to p_to, at p_store.
create function pg_temp.t476_move(p_inv uuid, p_n int, p_to uuid, p_kind text default 'paid', p_store text default null)
  returns void language plpgsql as $f$
declare b uuid;
begin
  select bv.id into b from invoice_benefit_values bv
    left join customer_reward_vouchers v on v.id = bv.reward_voucher_id
    left join customer_credit_lots l on l.id = bv.lot_id
   where bv.invoice_item_id = pg_temp.t476_line(p_inv, p_n)
     and (v.status = 'held' and p_kind = 'voucher' or l.remaining_amount > 0 and l.category = p_kind)
   order by bv.granted_value desc limit 1;
  if b is null then raise exception 'T476: nothing to move on that line'; end if;
  perform transfer_invoice_unused_benefit(b, p_to, coalesce(pg_temp.t476_id(p_store), (select store_id from invoices where id = p_inv)),
    'T476 move', gen_random_uuid());
end $f$;
-- The invoice form: p_n sessions of S$20 (or S$5 with p_svc 'svc5') for
-- p_cust, paid with the wallet (Credit Package Paid; Premium Bundle Paid with
-- p_wallet 'bwallet') through Record Payment.
create function pg_temp.t476_spend(p_cust uuid, p_n int default 1, p_svc text default 'svc', p_wallet text default 'wallet')
  returns uuid language plpgsql as $f$
declare inv uuid; v_lines jsonb := '[]'; i int;
begin
  for i in 1 .. p_n loop
    v_lines := v_lines || jsonb_build_array(jsonb_build_object('kind', 'therapy', 'therapy_service_id', pg_temp.t476_id(p_svc), 'quantity', 1));
  end loop;
  inv := create_invoice_with_details(pg_temp.t476_id('store'), p_cust, v_lines, jsonb_build_object('business_date', sg_today()::text));
  perform record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.t476_id(p_wallet),
    'amount', (select total_amount from invoices where id = inv))), gen_random_uuid());
  if (select status::text from invoices where id = inv) <> 'paid' then raise exception 'T476: the session paid from credit is not paid'; end if;
  return inv;
end $f$;
-- The session cancelled and "Record refund paid": what its payment took goes
-- back to the lots it came from (refund_invoice_recorded's wallet refund).
create function pg_temp.t476_unspend(p_inv uuid) returns void language plpgsql as $f$
declare due numeric;
begin
  perform cancel_invoice_recorded(p_inv, 'T476 cancel session', gen_random_uuid());
  due := (invoice_financial_position(p_inv)->>'refund_due')::numeric;
  if due is null or due <= 0 then due := (invoice_action_plan(p_inv, 'cancel', '[]')->>'refund_due')::numeric; end if;
  perform refund_invoice_recorded(p_inv, jsonb_build_array(jsonb_build_object('amount', due)), pg_temp.t476_sources(p_inv, due), '[]'::jsonb,
    'T476 refund paid', gen_random_uuid());
end $f$;
-- The Finance panel's Correct payment on a session's wallet payment: the
-- date only ('date'), a smaller amount ('amount', S$5 less), or another
-- method ('cash').
create function pg_temp.t476_fix(p_inv uuid, p_how text) returns void language plpgsql as $f$
declare p invoice_payments%rowtype;
begin
  select * into p from invoice_payments where invoice_id = p_inv and entry_kind in ('receipt', 'correction_replacement')
     and not exists (select 1 from invoice_payments q where q.corrects_payment_id = invoice_payments.id and q.entry_kind = 'correction_reversal')
   order by created_at desc, id desc limit 1;
  perform correct_invoice_payment(p.id,
    case p_how when 'amount' then p.amount - 5 else p.amount end,
    sg_today() - 1,
    case p_how when 'cash' then pg_temp.t476_id('pm') else p.payment_method_id end,
    'T476 correct payment ' || p_how, gen_random_uuid());
end $f$;
-- A special document's wallet payment as pay_special_with_credit records it
-- (a stand-in: no page calls that function, and no credit category allows a
-- special document today, purchase_category): p_amount off the customer's
-- largest lot ('use', its allocations), so refund_special_credit, the real
-- one, gives it back.
create function pg_temp.t476_special(p_cust uuid, p_kind text, p_doc uuid, p_amount numeric) returns void language plpgsql as $f$
declare l customer_credit_lots%rowtype; e uuid;
begin
  select * into l from customer_credit_lots where customer_id = p_cust and status = 'active' and remaining_amount >= p_amount
   order by remaining_amount desc, id limit 1 for update;
  insert into customer_credit_ledger(wallet_id, customer_id, entry_type, category, amount, lot_id, source_type, source_record_id, store_id, note, created_by)
  values (l.wallet_id, p_cust, 'use', l.category, p_amount, l.id, p_kind, p_doc, l.store_id, 'T476 special', auth.uid()) returning id into e;
  update customer_credit_lots set remaining_amount = remaining_amount - p_amount, updated_at = now() where id = l.id;
  insert into customer_credit_allocations(ledger_entry_id, lot_id, customer_id, amount) values (e, l.id, p_cust, p_amount);
  insert into special_credit_allocations(doc_kind, doc_id, customer_id, lot_id, category, amount, created_by)
  values (p_kind, p_doc, p_cust, l.id, l.category, p_amount, auth.uid());
end $f$;
-- The guided Refund in full / Cancel as an Owner confirms it, with a reason
-- for every override the plan asks for, the money recorded as paid back (or,
-- with p_record false, not: "Record refund paid" left unticked).
create function pg_temp.t476_guided(p_inv uuid, p_action text, p_record boolean default true) returns void language plpgsql as $f$
declare plan jsonb; req jsonb; ov jsonb;
begin
  plan := invoice_action_plan(p_inv, p_action, '[]');
  req := request_invoice_action_v2(p_inv, p_action, '[]', 'T476 ' || p_action, null, gen_random_uuid());
  select coalesce(jsonb_agg(case when coalesce((o->>'amount_required')::boolean, false)
           then jsonb_build_object('code', o->>'code', 'reason', 'T476 override', 'amount', (o->>'default_amount')::numeric)
           else jsonb_build_object('code', o->>'code', 'reason', 'T476 override') end), '[]'::jsonb)
    into ov from jsonb_array_elements(coalesce(plan->'overrides_required', '[]')) o;
  perform resolve_invoice_action_v2((req->>'request_id')::uuid, true, 'T476 ' || p_action, plan->>'plan_hash', ov, null, p_record);
end $f$;


-- ── What the records say ────────────────────────────────────────────────────
-- The lots an invoice's records name: its benefit values, its sale's lots, a
-- split's issued lot, released credit (credit_package_progress_lots) and,
-- 473, the lots a release record's chain reaches (credit_lot_chain: a
-- merge's or customer change's reissue of a lot released before full
-- payment, which the record keeps naming by its first lot; every reader of
-- the record follows the chain: Cancel's write-off, 471's hold,
-- capture_invoice_benefit_values).
create function pg_temp.t476_named(p_inv uuid) returns setof uuid language sql as $f$
  select lot_id from invoice_benefit_values where invoice_id = p_inv and lot_id is not null
  union select x from credit_package_sales s, unnest(array[s.credit_lot_id, s.bonus_credit_lot_id]) x where s.invoice_id = p_inv and x is not null
  union select x from premium_bundle_sales s, unnest(array[s.paid_credit_lot_id, s.bonus_credit_lot_id]) x where s.invoice_id = p_inv and x is not null
  union select issued_lot_id from invoice_credit_splits where invoice_id = p_inv and issued_lot_id is not null
  union select lot_id from credit_package_progress_lots where invoice_id = p_inv
  union select x from credit_package_progress_lots pl, unnest(credit_lot_chain(pl.lot_id)) x where pl.invoice_id = p_inv $f$;
-- The invoice's lot family (the critic's 6): every lot its records name and
-- each Move's two lots (from the Move's ledger rows), the lots each replaced
-- and every lot reissued from any of them.
create function pg_temp.t476_family(p_inv uuid) returns setof uuid language sql as $f$
  with recursive seed as (
    select x as id from pg_temp.t476_named(p_inv) x
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
create function pg_temp.t476_behind(p_inv uuid) returns setof uuid language sql as $f$
  with recursive c(id, n) as (
    select lot_id, 0 from invoice_benefit_values where invoice_id = p_inv and lot_id is not null
    union select p.id, c.n + 1 from c join customer_credit_lots l on l.id = c.id
            join customer_credit_lots p on p.id = l.reassigned_from_lot_id
             and (p.source_type, p.source_record_id) is not distinct from (l.source_type, l.source_record_id)
           where c.n < 12)
  select distinct id from c $f$;
-- How many lots back a lot's chain goes (reassigned_from_lot_id).
create function pg_temp.t476_depth(p_lot uuid) returns int language sql as $f$
  with recursive c(id, n) as (select p_lot, 0 union all
    select l.reassigned_from_lot_id, c.n + 1 from c join customer_credit_lots l on l.id = c.id
     where l.reassigned_from_lot_id is not null and c.n < 40)
  select max(n) from c $f$;
-- A lot's balance by its ledger rows: credit added (grants, increases,
-- credit returned: the 'reverse' rows that put credit back, as the
-- statement reads them, and 'rental_late_fee'), less credit taken (uses,
-- decreases, real reversals).
create function pg_temp.t476_ledger_balance(p_lot uuid) returns numeric language sql as $f$
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
create function pg_temp.t476_invariants(p_inv uuid) returns text language plpgsql as $f$
declare probs text := ''; l record; root record; v uuid; st text := (select status::text from invoices where id = p_inv);
begin
  for l in select cl.* from customer_credit_lots cl where cl.id in (select pg_temp.t476_family(p_inv)) loop
    if l.remaining_amount > 0 and l.id not in (select pg_temp.t476_named(p_inv)) then
      probs := probs || format(' S$%s on a lot no record names (%s);', l.remaining_amount, (select full_name from customers where id = l.customer_id)); end if;
    if l.id not in (select pg_temp.t476_named(p_inv)) and l.id not in (select pg_temp.t476_behind(p_inv))
       and (exists (select 1 from invoice_line_credit_allocations a where a.lot_id = l.id and a.amount > coalesce(a.reversed_amount, 0))
            or exists (select 1 from special_credit_allocations s where s.lot_id = l.id and s.amount > coalesce(s.reversed_amount, 0))) then
      probs := probs || ' a sale paid from a lot no record names can still be refunded (its credit would stay there);'; end if;
    if pg_temp.t476_ledger_balance(l.id) <> l.remaining_amount then
      probs := probs || format(' lot holds %s, its ledger %s;', l.remaining_amount, pg_temp.t476_ledger_balance(l.id)); end if;
    if pg_temp.t476_depth(l.id) > 12 then probs := probs || format(' chain %s lots deep;', pg_temp.t476_depth(l.id)); end if;
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
  if st = 'refunded' and (select coalesce(sum(remaining_amount), 0) from customer_credit_lots where id in (select pg_temp.t476_family(p_inv))) > 0 then
    probs := probs || format(' refunded, but S$%s of its credit is still held;',
      (select sum(remaining_amount) from customer_credit_lots where id in (select pg_temp.t476_family(p_inv)))); end if;
  return probs;
end $f$;
-- Credit left on the invoice's family once Cancel has run, the Cancel undone
-- (0 when Cancel takes it all back from whoever holds it); null when the
-- invoice cannot be cancelled now, -1 when Cancel is refused.
create function pg_temp.t476_cancel_left(p_inv uuid) returns numeric language plpgsql as $f$
declare v numeric;
begin
  if (select status::text from invoices where id = p_inv) not in ('paid', 'partially_paid', 'unpaid') then return null; end if;
  begin
    perform cancel_invoice_recorded(p_inv, 'T476 probe', gen_random_uuid());
    perform pg_temp.t476_commit();
    v := (select coalesce(sum(remaining_amount), 0) from customer_credit_lots where id in (select pg_temp.t476_family(p_inv)));
    raise exception using errcode = 'P0461', message = v::text;
  exception when sqlstate 'P0461' then return sqlerrm::numeric;
            when others then return -1;
  end;
end $f$;
create function pg_temp.t476_codes(p_inv uuid, p_action text) returns text language plpgsql as $f$
begin
  return (select coalesce(string_agg(o->>'code', ',' order by o->>'code'), '-')
            from jsonb_array_elements(coalesce(invoice_action_plan(p_inv, p_action, '[]')->'overrides_required', '[]')) o);
exception when others then return 'ERR';
end $f$;
create function pg_temp.t476_due(p_inv uuid, p_action text) returns numeric language plpgsql as $f$
begin
  return (invoice_action_plan(p_inv, p_action, '[]')->>case when p_action = 'cancel' then 'refund_due' else 'refund_amount' end)::numeric;
exception when others then return null;
end $f$;
-- The invoice's money: what is owed back (cancel_refund_owed), the Finance
-- panel's refund due, net received and kept for what was used, what a
-- refund by line can still pay back (the refund options' max_refund, every
-- benefit) and Cancel's refund due (the plan's).
create function pg_temp.t476_money(p_inv uuid) returns jsonb language sql as $f$
  select jsonb_build_object('owed', i.cancel_refund_owed,
    'due', (invoice_financial_position(i.id)->>'refund_due')::numeric,
    'net', (invoice_financial_position(i.id)->>'net_received')::numeric,
    'kept', (invoice_financial_position(i.id)->>'kept_for_used')::numeric,
    'by_line', (select coalesce(sum((b->>'max_refund')::numeric), 0)
                  from jsonb_array_elements(invoice_refund_options_before_sessions(i.id)->'benefits') b),
    'plan_due', pg_temp.t476_due(i.id, 'cancel'))
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
--   addline cp|cpb        a correction adding a Credit Package line (476's review)
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
--   payout R amt          an Owner's affiliate payout of amt to R for this month (the
--                         Commissions page's Record payout, record_affiliate_payout)
--   repair328             a stand-in for 328's repair of the invoice's first
--                         lot of credit released before full payment (its own
--                         statements: the rest reversed, 'credit_lot_provenance_repair',
--                         locked, granted again as a lot that replaces it)
create function pg_temp.t476_role(p_pre text, p_r text) returns uuid language plpgsql as $f$
begin
  return coalesce(pg_temp.t476_id(p_pre || '/' || p_r), pg_temp.t476_cust(p_pre || '/' || p_r));
end $f$;
-- One step of a case (one app call, then what its commit does). Null, or
-- the step and the refusal; a refused step changes nothing.
create function pg_temp.t476_step(p_pre text, p_st text) returns text language plpgsql as $f$
declare w text[] := regexp_split_to_array(btrim(p_st), '\s+'); inv uuid := pg_temp.t476_id(p_pre || '/inv'); x uuid; i int; n int;
begin
  case w[1]
  when 'sale' then
    perform pg_temp.t476_put(p_pre || '/inv', pg_temp.t476_sale(pg_temp.t476_role(p_pre, w[2]), string_to_array(w[3], ','), w[4]::numeric));
  when 'saled' then
    perform pg_temp.t476_put(p_pre || '/inv', pg_temp.t476_sale(pg_temp.t476_role(p_pre, w[2]), string_to_array(w[3], ','), null, 2, w[4]::numeric));
  when 'sale2' then
    perform pg_temp.t476_put(p_pre || '/inv2', pg_temp.t476_sale(pg_temp.t476_role(p_pre, w[2]), array['cp']));
  when 'pay' then perform pg_temp.t476_pay(inv);
  -- 473: Record Payment of an amount (a further part payment)
  when 'payp' then
    perform record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.t476_id('pm'),
      'amount', w[2]::numeric)), gen_random_uuid());
  when 'back' then
    perform pg_temp.t476_back(inv, w[2]::int, case when w[3] = 'all' then null else w[3]::numeric end,
                              case when w[4] is not null then pg_temp.t476_role(p_pre, w[4]) end);
  when 'move' then
    perform pg_temp.t476_move(inv, w[2]::int, pg_temp.t476_role(p_pre, w[3]),
      case when w[4] in ('bonus', 'voucher') then w[4] else 'paid' end,
      case when 'store2' = any (w) then 'store2' end);
  when 'cancel' then perform cancel_invoice_recorded(inv, 'T476 cancel', gen_random_uuid());
  when 'reopen' then perform reopen_invoice(inv, 'T476 reopen', gen_random_uuid());
  when 'wait' then
    perform cancel_invoice_recorded(inv, 'T476 cancel', gen_random_uuid());
    for i in 1 .. (select count(*)::int from invoice_items where invoice_id = inv) loop
      perform pg_temp.t476_back(inv, i);
    end loop;
    perform reopen_invoice(inv, 'T476 reopen', gen_random_uuid());
  when 'refundall' then perform pg_temp.t476_guided(inv, 'refund_full');
  when 'change' then
    perform pg_temp.t476_change(inv, pg_temp.t476_role(p_pre, w[2]), case when 'keep' = any (w) then 'keep' else 'transfer' end,
                                case when 'store2' = any (w) then 'store2' end);
  when 'merge' then perform pg_temp.t476_merge(pg_temp.t476_role(p_pre, w[2]), pg_temp.t476_role(p_pre, w[3]));
  when 'spend' then
    n := (select count(*) from t476 where k ~ ('^' || p_pre || '/S[0-9]+$')) + 1;
    perform pg_temp.t476_put(p_pre || '/S' || n,
      pg_temp.t476_spend(pg_temp.t476_role(p_pre, w[2]), case when w[3] ~ '^[0-9]+$' then w[3]::int else 1 end,
        case when 'svc5' = any (w) then 'svc5' else 'svc' end,
        case when 'bwallet' = any (w) then 'bwallet' when 'cbonus' = any (w) then 'cbonus' else 'wallet' end));
  when 'unspend' then perform pg_temp.t476_unspend(pg_temp.t476_id(p_pre || '/' || w[2]));
  when 'fix' then perform pg_temp.t476_fix(pg_temp.t476_id(p_pre || '/' || w[2]), w[3]);
  -- 476: the Finance panel's Correct payment on the invoice's own latest payment
  when 'fixinv' then perform pg_temp.t476_fix(inv, w[2]);
  -- 476 (the review): the invoice form's correction adding a Credit Package
  -- line ('cp' or 'cpb'), the customer as it is
  when 'addline' then
    perform correct_invoice(inv, pg_temp.t476_lines(inv)
        || jsonb_build_array(jsonb_build_object('kind', 'credit_package', 'credit_package_id', pg_temp.t476_id(w[2]), 'quantity', 1)),
      jsonb_build_object('expected_edit_count', (select edit_count from invoices where id = inv), 'store_id', (select store_id from invoices where id = inv)),
      'T476 add a line', gen_random_uuid());
  -- 476 (answer A): the invoice made with nothing paid ('draft R kinds'),
  -- then edited or paid; a correction adding two or more Credit Package
  -- lines in one save ('addlines cp,cp'); one save of the invoice form
  -- changing the customer to R and adding a line ('changeadd R cp [keep]')
  when 'draft' then
    perform pg_temp.t476_put(p_pre || '/inv', pg_temp.t476_draft(pg_temp.t476_role(p_pre, w[2]), string_to_array(w[3], ',')));
  when 'addlines' then
    perform correct_invoice(inv, pg_temp.t476_lines(inv)
        || (select jsonb_agg(jsonb_build_object('kind', 'credit_package', 'credit_package_id', pg_temp.t476_id(k), 'quantity', 1))
              from unnest(string_to_array(w[2], ',')) k),
      jsonb_build_object('expected_edit_count', (select edit_count from invoices where id = inv), 'store_id', (select store_id from invoices where id = inv)),
      'T476 add lines', gen_random_uuid());
  when 'changeadd' then
    x := pg_temp.t476_role(p_pre, w[2]);
    perform correct_invoice(inv, pg_temp.t476_lines(inv)
        || jsonb_build_array(jsonb_build_object('kind', 'credit_package', 'credit_package_id', pg_temp.t476_id(w[3]), 'quantity', 1)),
      jsonb_build_object('expected_edit_count', (select edit_count from invoices where id = inv),
        'customer_id', x, 'store_id', (select store_id from invoices where id = inv),
        'benefit_action', case when 'keep' = any (w) then 'keep' else 'transfer' end),
      'T476 wrong customer and a line added', gen_random_uuid());
    update audit_logs set created_at = clock_timestamp()
     where record_id = inv and action = 'invoice_benefits_followed_reassignment' and new_data->>'to_customer' = x::text
       and created_at = now();
  -- 476 (answer B): referrers on the case's customers (A's RA, B's RB, C's
  -- RC), set as the customer form records a referrer; and the part-payment
  -- commission layer registered (357's Register; undone after the case)
  when 'refs' then
    for i in 1 .. 3 loop
      x := pg_temp.t476_role(p_pre, (array['A', 'B', 'C'])[i]);
      update customers set referred_by = pg_temp.t476_role(p_pre, 'R' || (array['A', 'B', 'C'])[i]) where id = x;
    end loop;
  when 'layer' then
    update app_settings set instalment_commission_from = sg_today() - 30 where id = true;
  when 'delete' then
    x := pg_temp.t476_role(p_pre, w[2]);
    perform delete_customer(x, (select full_name from customers where id = x), 'T476 delete');
  when 'special' then
    n := (select count(*) from t476 where k ~ ('^' || p_pre || '/D[0-9]+$')) + 1; x := gen_random_uuid();
    perform pg_temp.t476_put(p_pre || '/D' || n, x);
    perform pg_temp.t476_put(p_pre || '/D' || n || '/kind:' || w[3], null);
    perform pg_temp.t476_special(pg_temp.t476_role(p_pre, w[2]), w[3], x, w[4]::numeric);
  when 'unspecial' then
    perform refund_special_credit((select split_part(k, 'kind:', 2) from t476 where k like p_pre || '/' || w[2] || '/kind:%'),
                                  pg_temp.t476_id(p_pre || '/' || w[2]));
  when 'reverse' then
    if w[2] = 'closed' then
      -- the released lot a Cancel's write-off closed, once a refund opened it again
      perform reverse_credit_lot(pg_temp.t476_closed_lot(inv), 'T476 reversal');
    else
      x := pg_temp.t476_role(p_pre, w[2]);
      perform reverse_credit_lot((select id from customer_credit_lots where customer_id = x and remaining_amount > 0
                                   order by remaining_amount desc, id limit 1), 'T476 reversal');
    end if;
  when 'guidedcancel' then perform pg_temp.t476_guided(inv, 'cancel');
  when 'guidedkeep' then perform pg_temp.t476_guided(inv, 'cancel', false);
  when 'backo' then
    x := pg_temp.t476_line(inv, w[2]::int);
    perform refund_invoice_recorded(inv, jsonb_build_array(jsonb_build_object('invoice_item_id', x,
        'amount', invoice_discounted_line_value(x),
        'benefits', jsonb_build_array(jsonb_build_object('benefit_id', pg_temp.t476_own(inv), 'amount', w[3]::numeric)),
        'override', jsonb_build_object('code', 'larger_refund', 'reason', 'T476 larger refund', 'amount', invoice_discounted_line_value(x)))),
      pg_temp.t476_sources(inv, invoice_net_received(inv)), '[]'::jsonb, 'T476 larger refund', gen_random_uuid());
  when 'refundpaid' then
    perform refund_invoice_recorded(inv, jsonb_build_array(jsonb_build_object('amount',
        coalesce(nullif((invoice_financial_position(inv)->>'refund_due')::numeric, 0), (invoice_action_plan(inv, 'cancel', '[]')->>'refund_due')::numeric))),
      pg_temp.t476_sources(inv, coalesce(nullif((invoice_financial_position(inv)->>'refund_due')::numeric, 0), (invoice_action_plan(inv, 'cancel', '[]')->>'refund_due')::numeric)),
      '[]'::jsonb, 'T476 refund paid', gen_random_uuid());
  when 'backx' then
    x := pg_temp.t476_line(inv, w[2]::int);
    perform refund_invoice_recorded(inv, jsonb_build_array(jsonb_build_object('invoice_item_id', x,
        'amount', invoice_discounted_line_value(x) - coalesce((select sum((e->>'amount')::numeric) from invoice_refunds r,
             jsonb_array_elements(coalesce(r.outcome->'lines', '[]')) e where r.invoice_id = inv and e->>'invoice_item_id' = x::text), 0),
        'benefits', (select jsonb_agg(jsonb_build_object('benefit_id', b->>'id', 'amount', (b->>'max_refund')::numeric))
                       from jsonb_array_elements(invoice_refund_options_before_sessions(inv)->'benefits') b
                      where b->>'invoice_item_id' = x::text and (b->>'max_refund')::numeric > 0),
        'override', jsonb_build_object('code', 'larger_refund', 'reason', 'T476 larger refund',
          'amount', invoice_discounted_line_value(x) - coalesce((select sum((e->>'amount')::numeric) from invoice_refunds r,
             jsonb_array_elements(coalesce(r.outcome->'lines', '[]')) e where r.invoice_id = inv and e->>'invoice_item_id' = x::text), 0)))),
      pg_temp.t476_sources(inv, invoice_net_received(inv)), '[]'::jsonb, 'T476 larger refund', gen_random_uuid());
  when 'legacy' then
    update invoices set status = w[2]::invoice_status where id = inv;
  when 'repair' then perform repair_credit_package_progress_lots();
  when 'repair328' then perform pg_temp.t476_repair328(inv);
  -- 476 (NOT COVERED 7): an Owner's payout to a case's referrer (R) for this
  -- month, as the Commissions page records it
  when 'payout' then
    perform record_affiliate_payout(pg_temp.t476_role(p_pre, w[2]), date_trunc('month', sg_today())::date, w[3]::numeric,
      pg_temp.t476_id('pm'), sg_today(), 'T476 payout', null, gen_random_uuid());
  else raise exception 'T476: unknown step %', p_st;
  end case;
  perform pg_temp.t476_commit();
  return null;
exception when others then
  return btrim(p_st) || ': ' || sqlerrm;
end $f$;
-- What a case ends with: the invoice's status and money, who holds what
-- (credit, '/n' held vouchers), the plans' codes and refund due (Cancel's
-- refund due; Refund in full's amount), the refusal that stopped it, what is
-- wrong with its credit, and the credit Cancel would leave behind.
create function pg_temp.t476_outcome(p_pre text, p_err text) returns jsonb language sql as $f$
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
              from t476 t where t.k like p_pre || '/%' and split_part(t.k, '/', 4) = ''
                and split_part(t.k, '/', 3) !~ '^(inv|inv2|S[0-9]+|D[0-9]+|err)$'),
    'cancel', pg_temp.t476_codes(i.id, 'cancel'),
    'due', pg_temp.t476_due(i.id, 'cancel'),
    'refund', pg_temp.t476_codes(i.id, 'refund_full'),
    'rdue', pg_temp.t476_due(i.id, 'refund_full'),
    'error', p_err,
    -- 473: the invoice's customer now (its role in the case), and what the
    -- list of what a customer change can move says of its credit: the rows
    -- blocking it (with why) and the rows that would move.
    'customer', (select split_part(t.k, '/', 3) from invoices iv join t476 t on t.id = iv.customer_id and t.k like p_pre || '/%'
                  where iv.id = i.id limit 1),
    'blocked', (select coalesce(string_agg(x.description || ' (' || coalesce(x.blocked_reason, '-') || ')', '; ' order by x.description), '-')
                  from invoice_transferable_benefits(i.id) x where x.kind = 'credit' and x.blocking),
    'movable', (select coalesce(string_agg(x.description, '; ' order by x.description), '-')
                  from invoice_transferable_benefits(i.id) x where x.kind = 'credit' and x.movable),
    'invariants', pg_temp.t476_invariants(i.id),
    -- 476 (answer B): whose the invoice's package and bundle sale records
    -- are (their roles, '-' for none), and the commission each referrer of
    -- the case holds on it (earned or paid, net, not zero), at settlement and
    -- on the part-payment layer together.
    'sale', (select coalesce(string_agg(split_part(t.k, '/', 3), ',' order by split_part(t.k, '/', 3)), '-')
               from (select customer_id from credit_package_sales where invoice_id = i.id
                     union all select customer_id from premium_bundle_sales where invoice_id = i.id) s
               join t476 t on t.id = s.customer_id and t.k like p_pre || '/%' and split_part(t.k, '/', 4) = ''),
    'comm', (select coalesce(string_agg(split_part(t.k, '/', 3) || ' ' || x.s::text, ', ' order by split_part(t.k, '/', 3)), '-')
               from (select referrer_customer_id, sum(commission_amount)::numeric(12,2) as s from commissions
                      where invoice_id = i.id and status in ('earned', 'paid') group by 1 having sum(commission_amount) <> 0) x
               join t476 t on t.id = x.referrer_customer_id and t.k like p_pre || '/%' and split_part(t.k, '/', 4) = ''),
    'cancel_left', pg_temp.t476_cancel_left(i.id))
    from (select pg_temp.t476_id(p_pre || '/inv') as id) i $f$;
-- A case's steps p_from to p_to (all by default), stopping at a refusal;
-- with p_to null, its outcome (kept in t476_res under p_phase).
create temp table t476_err(pre text primary key, err text);
create function pg_temp.t476_run(p_phase text, p_case text, p_steps text, p_from int default 1, p_to int default null)
  returns jsonb language plpgsql as $f$
declare v_pre text := p_phase || '/' || p_case; st text[] := string_to_array(p_steps, ';'); i int; v_err text; v_out jsonb;
begin
  v_err := (select e.err from t476_err e where e.pre = v_pre);
  for i in p_from .. least(coalesce(p_to, cardinality(st)), cardinality(st)) loop
    exit when v_err is not null;
    continue when btrim(st[i]) = '';
    v_err := pg_temp.t476_step(v_pre, st[i]);
  end loop;
  insert into t476_err values (v_pre, v_err) on conflict (pre) do update set err = excluded.err;
  -- (476: a case's 'layer' step does not reach the next case)
  update app_settings set instalment_commission_from = null where id = true and instalment_commission_from is not null;
  if p_to is not null then return null; end if;
  v_out := pg_temp.t476_outcome(v_pre, v_err);
  insert into t476_res values (p_phase, p_case, v_out) on conflict (phase, k) do update set v = excluded.v;
  return v_out;
end $f$;

-- Whether an outcome has what is expected: each key equal ('holds' as a
-- containment of who holds what), a key ending in '~' as a LIKE pattern of
-- that key's text.
create function pg_temp.t476_meets(p_out jsonb, p_exp jsonb) returns boolean language sql as $f$
  select coalesce(bool_and(case
           when e.key like '%~' then coalesce(p_out->>left(e.key, -1), '') like (e.value #>> '{}')
           when e.key = 'holds' then coalesce(p_out->'holds', '{}') @> e.value
           when jsonb_typeof(e.value) = 'number' then coalesce((p_out->>e.key)::numeric = (e.value #>> '{}')::numeric, false)
           else (p_out->e.key) is not distinct from e.value end), true)
    from jsonb_each(p_exp) e $f$;
-- What differs between an outcome and what is expected (for the FAIL line).
create function pg_temp.t476_diff(p_out jsonb, p_exp jsonb) returns text language sql as $f$
  select string_agg(e.key || ': wanted ' || e.value::text || ', got ' || coalesce(p_out->left(e.key, case when e.key like '%~' then -1 else 1000 end), 'null')::text, '; ')
    from jsonb_each(p_exp) e where not pg_temp.t476_meets(p_out, jsonb_build_object(e.key, e.value)) $f$;

-- ── 471's own readings ──────────────────────────────────────────────────────
-- The held-back reason (470's, which 471 writes too), and its rows on a lot.
create function pg_temp.t476_held(p_lot uuid) returns numeric language sql as $f$
  select coalesce(sum(e.amount), 0) from customer_credit_ledger e
   where e.lot_id = p_lot and e.entry_type = 'adjust_decrease' and e.source_type = 'invoice_cancel_benefit'
     and e.reason = 'Held back by the invoice''s cancellation for whoever holds its benefits now' $f$;
-- (B) what is held back on a lot of credit released before full payment
-- (Cancel's write-off's kind of row, 471's reason).
create function pg_temp.t476_held_rel(p_lot uuid) returns numeric language sql as $f$
  select coalesce(sum(e.amount), 0) from customer_credit_ledger e
   where e.lot_id = p_lot and e.entry_type = 'adjust_decrease' and e.source_type in ('invoice_cancel_released_credit', 'invoice_refund_released_credit')
     and e.reason = 'Held back by the invoice''s cancellation: credit released before it was paid in full' $f$;
-- The release record of an invoice (its first; the cases have one) and its lot.
create function pg_temp.t476_rel_lot(p_inv uuid) returns uuid language sql as $f$
  select lot_id from credit_package_progress_lots where invoice_id = p_inv order by created_at, lot_id limit 1 $f$;
-- The lot of an invoice's release record that a Cancel's write-off closed
-- (locked; after a reopening the release record has a second, open lot).
create function pg_temp.t476_closed_lot(p_inv uuid) returns uuid language sql as $f$
  select pl.lot_id from credit_package_progress_lots pl join customer_credit_lots l on l.id = pl.lot_id
   where pl.invoice_id = p_inv and l.is_locked order by pl.lot_id limit 1 $f$;
create function pg_temp.t476_held_n(p_lot uuid) returns int language sql as $f$
  select count(*)::int from customer_credit_ledger e
   where e.lot_id = p_lot and e.entry_type = 'adjust_decrease' and e.source_type = 'invoice_cancel_benefit'
     and e.reason = 'Held back by the invoice''s cancellation for whoever holds its benefits now' $f$;
-- The package's own benefit row (the one an Owner did not move in), and the
-- lot it names.
create function pg_temp.t476_own(p_inv uuid) returns uuid language sql as $f$
  select bv.id from invoice_benefit_values bv
   where bv.invoice_id = p_inv and bv.lot_id is not null
     and not exists (select 1 from invoice_benefit_transfers t where t.replacement_benefit_id = bv.id)
   order by bv.created_at, bv.id limit 1 $f$;
create function pg_temp.t476_own_lot(p_inv uuid) returns uuid language sql as $f$
  select lot_id from invoice_benefit_values where id = pg_temp.t476_own(p_inv) $f$;
-- Unapplied queue rows of an invoice on a lot (count, sum, requests).
create function pg_temp.t476_waiting(p_inv uuid, p_lot uuid) returns text language sql as $f$
  select count(*) || '/' || coalesce(sum(q.amount), 0) || '/' || count(distinct q.request_id)
    from invoice_reopen_benefits q join customer_credit_ledger e on e.id = q.source_ledger_id
   where q.invoice_id = p_inv and q.applied_at is null and e.lot_id = p_lot $f$;
-- The triggers on invoices (their definitions, by name; search_path public,
-- as the migration reads them).
create function pg_temp.t476_inv_triggers() returns text language plpgsql as $f$
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
create function pg_temp.t476_repair328(p_inv uuid) returns uuid language plpgsql as $f$
declare r record; pk credit_packages%rowtype; v_new uuid; v_rem numeric;
begin
  select l.*, it.id as invoice_item_id, it.invoice_id, it.credit_package_id into r
    from credit_package_progress_lots pl
    join customer_credit_lots l on l.id = pl.lot_id
    join invoice_items it on it.id = pl.invoice_item_id
   where pl.invoice_id = p_inv order by pl.created_at, pl.lot_id limit 1;
  if r.id is null or r.remaining_amount <= 0 then raise exception 'T476: no released lot holding credit to repair'; end if;
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





-- ── 476's readings ──────────────────────────────────────────────────────────
-- The functions 476 changes and adds: BEFORE (production at 475, 27 Oct
-- 2026) and AFTER.
create temp table t476_md5(sig text primary key, before text, after text);
insert into t476_md5 values
  ('invoice_transferable_benefits(uuid)', 'a2332a22fe9975667e848de0d1e4480b', '1546de1f83d970424d26e65941f4dcb8'),
  ('move_invoice_benefits_to_customer(uuid,uuid,uuid,text)', 'c01606c84ee13ddcd88c15521d6d9aed', '142dd3252911480bd4a17e7c55b488d3'),
  ('release_credit_package_paid_credit(uuid)', '530521c100163445e5a0b99799fbcccc', 'f6685d987e998575c3c1e5917493dc24'),
  ('issue_credit_package(uuid,uuid,uuid,numeric,uuid,uuid)', 'cc3737e39249ea9ebfed729a1e221f84', '5654ef9249cf5c6a943beb7890574f20'),
  ('sell_premium_bundle(uuid,uuid,uuid,jsonb,jsonb,numeric,numeric,uuid,boolean,uuid)', '3cee8de4ce6361744a9d57b172e84563', '72d4ba2c35703b336f3b2e9114a6af6e'),
  ('invoice_package_commission_preview(uuid)', '906791a4de678bd2d1dcac59838d17f1', '5ed13af2d3104dd04b4739b3ab8507bc'),
  ('credit_line_sale_group(uuid)', null, '9c0e2931b672a763235d3d9839b2f02a'),
  ('credit_line_benefits_holder(uuid)', null, '45865ed52a5f24ebe6b8e435ba10e9e9'),
  ('invoice_credit_receivers(uuid)', null, 'ecdd2c5a5051cca33a9cedd0a5c07666');
create function pg_temp.t476_at(p_col text) returns boolean language plpgsql as $f$
declare p text := current_setting('search_path'); v boolean;
begin
  perform set_config('search_path', 'public', true);
  select bool_and(case when p_col = 'before' then
                         case when m.before is null then to_regprocedure('public.' || m.sig) is null
                              else md5(pg_get_functiondef(to_regprocedure('public.' || m.sig))) = m.before end
                       else to_regprocedure('public.' || m.sig) is not null
                            and md5(pg_get_functiondef(to_regprocedure('public.' || m.sig))) = m.after end) into v
    from t476_md5 m;
  perform set_config('search_path', p, true);
  return v;
end $f$;
-- Whom 476's helper names for an invoice's first package line (null where
-- it is not there).
create function pg_temp.t476_holder(p_inv uuid) returns uuid language plpgsql as $f$
declare v uuid;
begin
  if to_regprocedure('public.credit_line_benefits_holder(uuid)') is null then return null; end if;
  execute 'select public.credit_line_benefits_holder($1)' into v
    using (select id from invoice_items where invoice_id = p_inv and line_kind::text in ('credit_package', 'premium_bundle') order by id limit 1);
  return v;
end $f$;
-- (answer A) the sale group of each of an invoice's package and bundle
-- lines, in line order ('-' where 476 is not in).
create function pg_temp.t476_groups(p_inv uuid) returns text language plpgsql as $f$
declare v text;
begin
  if to_regprocedure('public.credit_line_sale_group(uuid)') is null then return '-'; end if;
  execute 'select string_agg(public.credit_line_sale_group(it.id)::text, '','' order by it.id) from invoice_items it
            where it.invoice_id = $1 and it.line_kind::text in (''credit_package'', ''premium_bundle'')' into v using p_inv;
  return v;
end $f$;
-- (answer E) what the Pay dialog reads for an invoice: each listed line's
-- receiver, by the case's role, in line order ('-' for none).
create function pg_temp.t476_recv(p_pre text) returns text language plpgsql as $f$
declare r jsonb;
begin
  r := invoice_credit_receivers(pg_temp.t476_id(p_pre || '/inv'));
  return coalesce((select string_agg(coalesce((select split_part(t.k, '/', 3) from t476 t
                                                where t.id = (x->>'customer_id')::uuid and t.k like p_pre || '/%' limit 1), '?')
                                     || case when (x->>'customer_name') = (select full_name from customers where id = (x->>'customer_id')::uuid)
                                             then '' else '(name?)' end, ',' order by x->>'invoice_item_id')
                     from jsonb_array_elements(r->'lines') x), '-');
end $f$;


-- ── 476's cases ─────────────────────────────────────────────────────────────
-- (k, kind, steps, what 476 gives). kind: 'fixed' (before 476 it ends
-- otherwise: the fault is reproduced first), 'control' (the same with and
-- without 476, every key of the outcome), 'known' (a NOT COVERED item,
-- checked as it is: the same with and without 476). Every case also checks
-- the invariants and that Cancel takes everything back from whoever holds
-- it. A refused step undoes itself (a customer it made is not there
-- afterwards). 'sale' is whose the sale records are; 'comm' the commission
-- each referrer of the case holds on the invoice (net, not zero).
create temp table t476_cases(k text primary key, kind text not null, steps text not null, expect jsonb not null, ord serial);
insert into t476_cases(k, kind, steps, expect) values
-- (1) a 'transfer' change of a package paid in part whose released credit
-- was spent in full, nothing on a lot: refused with the words of the
-- package paid in full; nothing moves (the payment after it is not made).
('TQn2', 'fixed', 'sale A cp 40; spend A; spend A; change B; pay',
  '{"holds":{"A":"0.00"},"status":"partially_paid","customer":"A","blocked":"Paid credit 60.00 (Partly spent)","movable":"-","error~":"change B: These benefits have already been used and cannot move with the invoice: Paid credit 60.00 (Partly spent). Resolve each one through the benefit transfer review before reassigning.%"}'),
('TQn2v', 'fixed', 'sale A pbv 40; spend A 1 svc bwallet; spend A 1 svc bwallet; change B; pay',
  '{"holds":{"A":"0.00"},"status":"partially_paid","customer":"A","blocked":"Paid credit 60.00 (Partly spent)","movable":"-","error~":"change B: These benefits have already been used and cannot move with the invoice: Paid credit 60.00 (Partly spent). Resolve%"}'),
('TQn2b', 'fixed', 'sale A cpb 40; spend A; spend A; change B; pay',
  '{"holds":{"A":"0.00"},"status":"partially_paid","customer":"A","blocked":"Paid credit 60.00 (Partly spent)","movable":"-","error~":"change B: These benefits have already been used and cannot move with the invoice: Paid credit 60.00 (Partly spent). Resolve%"}'),
('TQn2w', 'fixed', 'sale A cp 20; spend A; payp 20; spend A; change B; pay',
  '{"holds":{"A":"0.00"},"status":"partially_paid","customer":"A","blocked":"Paid credit 60.00 (Partly spent)","movable":"-","error~":"change B: These benefits have already been used and cannot move with the invoice: Paid credit 60.00 (Partly spent). Resolve%"}'),
('TQn2w2', 'fixed', 'sale A cp 20; spend A; payp 20; spend A; change B; payp 20',
  '{"holds":{"A":"0.00"},"status":"partially_paid","customer":"A","blocked":"Paid credit 60.00 (Partly spent)","movable":"-","error~":"change B: These benefits have already been used and cannot move with the invoice: Paid credit 60.00 (Partly spent). Resolve%"}'),
('TQn2m', 'fixed', 'sale A cp 40; merge K A; spend K; spend K; change B; pay',
  '{"holds":{"A":"0.00","K":"0.00"},"status":"partially_paid","customer":"K","blocked":"Paid credit 60.00 (Partly spent)","error~":"change B: These benefits have already been used and cannot move with the invoice: Paid credit 60.00 (Partly spent). Resolve%"}'),
('TQn2r', 'fixed', 'sale A cp 40; spend A; spend A; cancel; reopen; change B; pay',
  '{"holds":{"A":"0.00"},"status":"partially_paid","customer":"A","blocked":"Paid credit 60.00 (Partly spent)","error~":"change B: These benefits have already been used and cannot move with the invoice: Paid credit 60.00 (Partly spent). Resolve%"}'),
('TQn2x', 'fixed', 'sale A cp 40; reverse A; change B; pay',
  '{"holds":{"A":"0.00"},"status":"partially_paid","customer":"A","blocked":"Paid credit 60.00 (Partly spent)","error~":"change B: These benefits have already been used and cannot move with the invoice: Paid credit 60.00 (Partly spent). Resolve%"}'),
-- (2) a 'keep' change before full payment: all it gives later goes to
-- whoever holds the package's benefits (answers A and B).
('K1', 'fixed', 'sale A cp 40; change B keep; pay',
  '{"holds":{"A":"100.00","B":"0.00"},"status":"paid","customer":"B","blocked":"-","movable":"Paid credit 40.00; Paid credit 60.00","sale":"A","error":null}'),
('K2', 'fixed', 'sale A cp 20; spend A; payp 20; change B keep; pay',
  '{"holds":{"A":"80.00","B":"0.00"},"status":"paid","customer":"B","blocked":"Paid credit 20.00 (Partly spent); Paid credit 60.00 (Partly spent)","sale":"A","error":null}'),
('K1b', 'fixed', 'sale A cpb 40; change B keep; pay',
  '{"holds":{"A":"110.00","B":"0.00"},"status":"paid","customer":"B","sale":"A","error":null}'),
('K1v', 'fixed', 'sale A pbv 40; change B keep; pay',
  '{"holds":{"A":"140.00/2","B":"0.00"},"status":"paid","customer":"B","sale":"A","error":null}'),
('Kvb', 'fixed', 'sale A pbv 40; spend A 1 svc bwallet; change B keep; pay',
  '{"holds":{"A":"120.00/2","B":"0.00"},"status":"paid","customer":"B","sale":"A","error":null}'),
('K1n2', 'fixed', 'sale A cp 40; spend A; spend A; change B keep; pay',
  '{"holds":{"A":"60.00","B":"0.00"},"status":"paid","customer":"B","blocked":"Paid credit 60.00 (Partly spent)","error":null}'),
('K1p', 'fixed', 'sale A cp 40; change B keep; payp 20',
  '{"holds":{"A":"60.00","B":"0.00"},"status":"partially_paid","customer":"B","error":null}'),
('KK', 'fixed', 'sale A cp 40; change B keep; change C keep; pay',
  '{"holds":{"A":"100.00","B":"0.00","C":"0.00"},"status":"paid","customer":"C","sale":"A","error":null}'),
('TK', 'fixed', 'sale A cp 40; change B; change C keep; pay',
  '{"holds":{"A":"0.00","B":"100.00","C":"0.00"},"status":"paid","customer":"C","sale":"B","error":null}'),
('K1m', 'fixed', 'sale A cp 40; change B keep; merge K A; pay',
  '{"holds":{"A":"0.00","B":"0.00","K":"100.00"},"status":"paid","customer":"B","sale":"K","error":null}'),
('K1mb', 'fixed', 'sale A cp 40; change B keep; merge K B; pay',
  '{"holds":{"A":"100.00","B":"0.00","K":"0.00"},"status":"paid","customer":"K","sale":"A","error":null}'),
('Kmg', 'fixed', 'sale A cp 40; change B keep; merge K A; payp 20; pay',
  '{"holds":{"A":"0.00","B":"0.00","K":"100.00"},"status":"paid","customer":"B","error":null}'),
('Kfix', 'fixed', 'sale A cp 40; change B keep; fixinv amount; pay',
  '{"holds":{"A":"100.00","B":"0.00"},"status":"paid","customer":"B","error":null}'),
('K1cr', 'fixed', 'sale A cp 40; spend A; cancel; change B keep; reopen; pay',
  '{"holds":{"A":"80.00","B":"0.00"},"status":"paid","customer":"B","error":null}'),
('K2c', 'fixed', 'sale A cp 20; spend A; payp 20; change B keep; cancel; reopen; pay',
  '{"holds":{"A":"80.00","B":"0.00"},"status":"paid","customer":"B","error":null}'),
('Kw', 'fixed', 'sale A cp 40; spend A; spend A; cancel; change B keep; reopen; pay',
  '{"holds":{"A":"60.00","B":"0.00"},"status":"paid","customer":"B","error":null}'),
('Kst', 'fixed', 'sale A cp 40; change B keep store2; pay',
  '{"holds":{"A":"100.00","B":"0.00"},"status":"paid","customer":"B","error":null}'),
('K1sp', 'fixed', 'sale A cp 40; change B keep; spend A; pay; change C',
  '{"holds":{"A":"80.00","B":"0.00"},"status":"paid","customer":"B","blocked":"Paid credit 20.00 (Partly spent); Paid credit 60.00 (Partly spent)","error~":"change C: These benefits have already been used and cannot move with the invoice: Paid credit %0.00 (Partly spent); Paid credit %0.00 (Partly spent). Resolve%"}'),
-- (2) two or more package or bundle lines of the invoice's own sale: the
-- line that released nothing goes to the holder too (answer A).
('X1', 'fixed', 'sale A cp,cp 40; change B keep; pay',
  '{"holds":{"A":"200.00","B":"0.00"},"status":"paid","customer":"B","blocked":"-","sale":"A,A","error":null}'),
('X2', 'fixed', 'sale A cp,cp 40; change B; change C keep; pay',
  '{"holds":{"A":"0.00","B":"200.00","C":"0.00"},"status":"paid","customer":"C","sale":"B,B","error":null}'),
('X3', 'fixed', 'sale A cpb,cpb 40; change B keep; pay',
  '{"holds":{"A":"220.00","B":"0.00"},"status":"paid","customer":"B","error":null}'),
('X4', 'fixed', 'sale A cp,pbv 40; change B keep; pay',
  '{"holds":{"A":"240.00/2","B":"0.00"},"status":"paid","customer":"B","sale":"A,A","error":null}'),
('X5', 'fixed', 'sale A cp,cp,cp 40; change B keep; pay',
  '{"holds":{"A":"300.00","B":"0.00"},"status":"paid","customer":"B","error":null}'),
('X6', 'fixed', 'sale A cp,cp 140; change B keep; pay',
  '{"holds":{"A":"200.00","B":"0.00"},"status":"paid","customer":"B","error":null}'),
('X7', 'fixed', 'sale A cp,cp 40; change B keep; payp 80; pay',
  '{"holds":{"A":"200.00","B":"0.00"},"status":"paid","customer":"B","error":null}'),
('X8', 'fixed', 'sale A cp,cp 40; change B keep; merge K A; pay',
  '{"holds":{"A":"0.00","B":"0.00","K":"200.00"},"status":"paid","customer":"B","error":null}'),
('X10', 'fixed', 'sale A cp,cp 40; spend A; spend A; change B keep; pay',
  '{"holds":{"A":"160.00","B":"0.00"},"status":"paid","customer":"B","blocked":"Paid credit 60.00 (Partly spent)","error":null}'),
-- (3) answer A: a line a correction added once money was received, before
-- the change or after it (or in the same save), goes to the invoice's
-- customer who pays for it, as with the first package paid in full (KALF,
-- KALF1, KAPF); a line an edit added before any money, and lines one
-- correction added together, go with the lines of their sale.
('KAL', 'fixed', 'sale A cp 40; change B keep; addline cp; pay',
  '{"holds":{"A":"100.00","B":"100.00"},"status":"paid","customer":"B","sale":"A,B","error":null}'),
('KAL1', 'fixed', 'sale A cp 40; changeadd B cp keep; pay',
  '{"holds":{"A":"100.00","B":"100.00"},"status":"paid","customer":"B","sale":"A,B","error":null}'),
('KAP', 'fixed', 'sale A cp 40; addline cp; change B keep; pay',
  '{"holds":{"A":"100.00","B":"100.00"},"status":"paid","customer":"B","sale":"A,B","error":null}'),
('KALp', 'fixed', 'sale A cp 40; change B keep; addline cp; payp 20; pay',
  '{"holds":{"A":"100.00","B":"100.00"},"status":"paid","customer":"B","error":null}'),
('KAE', 'fixed', 'draft A cp; addline cp; payp 40; change B keep; pay',
  '{"holds":{"A":"200.00","B":"0.00"},"status":"paid","customer":"B","sale":"A,A","error":null}'),
('KAT2', 'fixed', 'sale A cp; addlines cp,cp; payp 40; change B keep; pay',
  '{"holds":{"A":"300.00","B":"0.00"},"status":"paid","customer":"B","sale":"A,A,A","error":null}'),
-- (NOT COVERED 1c) two separate corrections, each once money was received:
-- two sales; the one that released nothing goes to the invoice's customer
-- (paid in full after both: KAT3F, A S$300).
('KAT3', 'fixed', 'sale A cp; addline cp; addline cp; payp 40; change B keep; pay',
  '{"holds":{"A":"200.00","B":"100.00"},"status":"paid","customer":"B","sale":"A,A,B","error":null}'),
-- (4) answer C: a 'transfer' change of a lot nothing on which was used moves
-- it (the payment corrected lower; a Cancel, a reopening and a refund).
('TQfix', 'fixed', 'sale A cp 40; fixinv amount; change B',
  '{"holds":{"A":"0.00","B":"35.00"},"status":"partially_paid","customer":"B","blocked":"-","error":null}'),
('TQfixp', 'fixed', 'sale A cp 40; fixinv amount; change B; pay',
  '{"holds":{"A":"0.00","B":"100.00"},"status":"paid","customer":"B","blocked":"-","sale":"B","error":null}'),
('TQcru', 'fixed', 'sale A cp 40; spend A; cancel; reopen; unspend S1; change B',
  '{"holds":{"A":"0.00","B":"40.00"},"status":"partially_paid","customer":"B","blocked":"-","error":null}'),
('TQcrup', 'fixed', 'sale A cp 40; spend A; cancel; reopen; unspend S1; change B; pay',
  '{"holds":{"A":"0.00","B":"100.00"},"status":"paid","customer":"B","blocked":"-","error":null}'),
-- (5) answer B: the commission at settlement, and on the part-payment
-- layer registered ('layer'), follows the sale record to the holder.
('CK1', 'fixed', 'refs; sale A cp 40; change B keep; pay',
  '{"holds":{"A":"100.00","B":"0.00"},"status":"paid","customer":"B","sale":"A","comm":"RA 4.50","error":null}'),
('CK1v', 'fixed', 'refs; sale A pbv 40; change B keep; pay',
  '{"holds":{"A":"140.00/2","B":"0.00"},"status":"paid","customer":"B","sale":"A","comm":"RA 6.30","error":null}'),
('CKAL', 'fixed', 'refs; sale A cp 40; change B keep; addline cp; pay',
  '{"holds":{"A":"100.00","B":"100.00"},"status":"paid","customer":"B","sale":"A,B","comm":"RA 4.50, RB 4.50","error":null}'),
('CX1', 'fixed', 'refs; sale A cp,cp 40; change B keep; pay',
  '{"holds":{"A":"200.00","B":"0.00"},"status":"paid","customer":"B","sale":"A,A","comm":"RA 9.00","error":null}'),
('IK1', 'fixed', 'refs; layer; sale A cp 40; change B keep; pay',
  '{"holds":{"A":"100.00","B":"0.00"},"status":"paid","customer":"B","sale":"A","comm":"RA 4.50","error":null}'),
('IK1m', 'fixed', 'refs; layer; sale A cp 40; change B keep',
  '{"holds":{"A":"40.00","B":"0.00"},"status":"partially_paid","customer":"B","sale":"-","comm":"RA 1.80","error":null}'),
('IKAL', 'fixed', 'refs; layer; sale A cp 40; change B keep; addline cp; pay',
  '{"holds":{"A":"100.00","B":"100.00"},"status":"paid","customer":"B","sale":"A,B","comm":"RA 4.50, RB 4.50","error":null}'),
('IX1', 'fixed', 'refs; layer; sale A cp,cp 40; change B keep; payp 20; pay',
  '{"holds":{"A":"200.00","B":"0.00"},"status":"paid","customer":"B","sale":"A,A","comm":"RA 9.00","error":null}'),
-- (NOT COVERED 7, checked in K) changed with 'keep', settled, then part-paid
-- again (a line added, a payment corrected lower) with the part-payment
-- layer registered: the credit, the vouchers and the sale record stay the
-- buyer's (fixed: before 476 they were split, B's sale record), while the
-- layer gives the line's commission to the invoice's customer's referrer
-- (RB) until paid in full again (G5p, C3cp: RA's again), as for the
-- package paid in full and then changed (G5F, C3cF, the same before 476).
('G5', 'fixed', 'refs; layer; sale A cp 40; change B keep; pay; addline cp',
  '{"holds":{"A":"100.00","B":"0.00"},"status":"partially_paid","customer":"B","sale":"A","comm":"RB 4.50","error":null}'),
('G5p', 'fixed', 'refs; layer; sale A cp 40; change B keep; pay; addline cp; pay',
  '{"holds":{"A":"100.00","B":"100.00"},"status":"paid","customer":"B","sale":"A,B","comm":"RA 4.50, RB 4.50","error":null}'),
('C3c', 'fixed', 'refs; layer; sale A cp 40; change B keep; pay; fixinv amount',
  '{"holds":{"A":"100.00","B":"0.00"},"status":"partially_paid","customer":"B","sale":"A","comm":"RB 4.28","error":null}'),
('C3cp', 'fixed', 'refs; layer; sale A cp 40; change B keep; pay; fixinv amount; pay',
  '{"holds":{"A":"100.00","B":"0.00"},"status":"paid","customer":"B","sale":"A","comm":"RA 4.50","error":null}'),
('C5', 'fixed', 'refs; layer; sale A cp,cp 140; change B keep; pay; fixinv amount',
  '{"holds":{"A":"200.00","B":"0.00"},"status":"partially_paid","customer":"B","sale":"A,A","comm":"RB 8.78","error":null}'),
('L4', 'fixed', 'refs; layer; sale A pbv 40; change B keep; pay; fixinv amount',
  '{"holds":{"A":"140.00/2","B":"0.00"},"status":"partially_paid","customer":"B","sale":"A","comm":"RB 6.08","error":null}'),
('G5F', 'control', 'refs; layer; sale A cp; change B keep; addline cp',
  '{"holds":{"A":"100.00","B":"0.00"},"status":"partially_paid","customer":"B","sale":"A","comm":"RB 4.50","error":null}'),
('C3cF', 'control', 'refs; layer; sale A cp; change B keep; fixinv amount',
  '{"holds":{"A":"100.00","B":"0.00"},"status":"partially_paid","customer":"B","sale":"A","comm":"RB 4.28","error":null}'),
-- (NOT COVERED 13, not caused by 476) a package line added by a correction
-- to an invoice paid in full releases credit for the money that paid for
-- the vouchers already issued: S$60 of credit and the 2 vouchers for S$60.
('KV13', 'known', 'sale A v; addline cp',
  '{"holds":{"A":"60.00/2"},"status":"partially_paid","net":60,"customer":"A","error":null}'),
-- Controls: the same with and without 476.
('X1F', 'control', 'sale A cp,cp; change B keep',
  '{"holds":{"A":"200.00","B":"0.00"},"status":"paid","customer":"B","error":null}'),
('X1T', 'control', 'sale A cp,cp 40; change B; pay',
  '{"holds":{"A":"0.00","B":"200.00"},"status":"paid","customer":"B","error":null}'),
('KALF', 'control', 'sale A cp; change B keep; addline cp; pay',
  '{"holds":{"A":"100.00","B":"100.00"},"status":"paid","customer":"B","sale":"A,B","error":null}'),
('KALF1', 'control', 'sale A cp; changeadd B cp keep; pay',
  '{"holds":{"A":"100.00","B":"100.00"},"status":"paid","customer":"B","sale":"A,B","error":null}'),
('KAPF', 'control', 'sale A cp; addline cp; change B keep; pay',
  '{"holds":{"A":"100.00","B":"100.00"},"status":"paid","customer":"B","sale":"A,B","error":null}'),
('KAEF', 'control', 'draft A cp; addline cp; pay; change B keep',
  '{"holds":{"A":"200.00","B":"0.00"},"status":"paid","customer":"B","sale":"A,A","error":null}'),
('KAT2F', 'control', 'sale A cp; addlines cp,cp; pay; change B keep',
  '{"holds":{"A":"300.00","B":"0.00"},"status":"paid","customer":"B","sale":"A,A,A","error":null}'),
('KAT3F', 'control', 'sale A cp; addline cp; addline cp; pay; change B keep',
  '{"holds":{"A":"300.00","B":"0.00"},"status":"paid","customer":"B","sale":"A,A,A","error":null}'),
('CKF', 'control', 'refs; sale A cp; change B keep',
  '{"holds":{"A":"100.00","B":"0.00"},"status":"paid","customer":"B","sale":"A","comm":"RA 4.50","error":null}'),
('CKTF', 'control', 'refs; sale A cp; change B',
  '{"holds":{"A":"0.00","B":"100.00"},"status":"paid","customer":"B","sale":"A","comm":"RA 4.50","error":null}'),
('TQ00', 'control', 'sale A cp 40; change B; pay',
  '{"holds":{"A":"0.00","B":"100.00"},"status":"paid","customer":"B","blocked":"-","error":null}'),
('TQu', 'control', 'sale A cp 40; spend A; unspend S1; change B; pay',
  '{"holds":{"A":"0.00","B":"100.00"},"status":"paid","customer":"B","blocked":"-","error":null}'),
('TQv0', 'control', 'sale A pbv 40; change B; pay',
  '{"holds":{"A":"0.00","B":"140.00/2"},"status":"paid","customer":"B","blocked":"-","error":null}'),
('W2c', 'control', 'sale A cp 20; payp 20; change B',
  '{"holds":{"A":"0.00","B":"40.00"},"status":"partially_paid","customer":"B","blocked":"-","error":null}'),
('KT', 'control', 'sale A cp 40; change B keep; change C; pay',
  '{"holds":{"A":"0.00","B":"0.00","C":"100.00"},"status":"paid","customer":"C","sale":"C","error":null}'),
-- (answer B) 'keep', paid, then cancelled, moved or changed with
-- 'transfer': the credit as before, the sale record now the buyer's, as
-- with the package paid in full before the 'keep' change.
('K1t', 'fixed', 'sale A cp 40; change B keep; pay; change C',
  '{"holds":{"A":"0.00","B":"0.00","C":"100.00"},"status":"paid","customer":"C","sale":"A","error":null}'),
('KF', 'control', 'sale A cp; change B keep',
  '{"holds":{"A":"100.00","B":"0.00"},"status":"paid","customer":"B","error":null}'),
('K1can', 'fixed', 'sale A cp 40; change B keep; pay; cancel',
  '{"holds":{"A":"0.00","B":"0.00"},"status":"cancelled","customer":"B","sale":"A","error":null}'),
('K1mv', 'fixed', 'sale A cp 40; change B keep; pay; move 1 F',
  '{"holds":{"A":"40.00","B":"0.00","F":"60.00"},"status":"paid","customer":"B","sale":"A","error":null}'),
('TQc', 'control', 'sale A cp; spend A; spend A; change B',
  '{"holds":{"A":"60.00"},"status":"paid","customer":"A","blocked":"Paid credit 60.00 (Partly spent)","error~":"change B: These benefits have already been used and cannot move with the invoice: Paid credit 60.00 (Partly spent). Resolve%"}'),
('TQn', 'control', 'sale A cp 40; spend A; change B',
  '{"holds":{"A":"20.00"},"status":"partially_paid","customer":"A","blocked":"Paid credit 20.00 (Partly spent)","error~":"change B: These benefits have already been used and cannot move with the invoice: Paid credit 20.00 (Partly spent). Resolve%"}'),
('W2', 'control', 'sale A cp 20; spend A; payp 20; change B',
  '{"holds":{"A":"20.00"},"status":"partially_paid","customer":"A","blocked":"Paid credit 20.00 (Partly spent)","error~":"change B: These benefits have already been used and cannot move with the invoice: Paid credit 20.00 (Partly spent). Resolve%"}'),
-- (answer C's controls) something used: still refused; the session refunded
-- while the invoice is cancelled (471 holds back what that refund gives back
-- on a cancelled package, so the lot holds nothing): the change passes,
-- moving nothing, as before (473's NOT COVERED 3).
('TQfixs', 'control', 'sale A cp 40; spend A; fixinv amount; change B',
  '{"holds":{"A":"15.00"},"status":"partially_paid","customer":"A","blocked":"Paid credit 15.00 (Partly spent)","error~":"change B: These benefits have already been used and cannot move with the invoice: Paid credit 15.00 (Partly spent). Resolve%"}'),
('TQcrc', 'control', 'sale A cp 40; spend A; cancel; unspend S1; change B',
  '{"holds":{"A":"0.00","B":"0.00"},"status":"cancelled","customer":"B","blocked":"-","error":null}'),
('TQn2cx', 'control', 'sale A cp 40; spend A; spend A; cancel; change B; reopen; pay',
  '{"holds":{"A":"0.00","B":"60.00"},"status":"paid","customer":"B","error":null}'),
('TQcr', 'control', 'sale A cp 40; spend A; spend A; cancel; reopen; pay; cancel; change B; reopen; pay',
  '{"holds":{"A":"0.00","B":"60.00"},"status":"paid","customer":"B","error":null}'),
('TQcc', 'control', 'sale A cp; spend A; spend A; cancel; change B; reopen; pay',
  '{"holds":{"A":"0.00","B":"60.00"},"status":"paid","customer":"B","error":null}'),
-- Known (476's NOT COVERED 4): the buyer used everything released and was
-- deleted: the holder is never a deleted record, so the invoice's customer.
('Kdel', 'known', 'sale A cp 40; spend A; spend A; change B keep; delete A; pay',
  '{"holds":{"A":"0.00","B":"60.00"},"status":"paid","customer":"B","error":null}'),
-- Known (476's NOT COVERED 2): changed with 'transfer' before full payment,
-- the settlement makes the sale record the new customer's (the holder's),
-- and the new customer's referrer earns, as before 476; paid in full first,
-- the sale record stays the buyer's (CKTF).
('CKT', 'known', 'refs; sale A cp 40; change B; pay',
  '{"holds":{"A":"0.00","B":"100.00"},"status":"paid","customer":"B","sale":"B","comm":"RB 4.50","error":null}');

-- States made for the header's query (before 476): its reasons and counts
-- ('-': listed nowhere).
create temp table t476_qstates(k text primary key, steps text not null, expect text not null);
insert into t476_qstates values
  ('QA', 'sale A cp 40; spend A; spend A', '1:1'),
  ('QB', 'sale A cp 40; change B keep', '2:1'),
  ('QC', 'sale A pbv 40; change B keep', '2:1,4:1'),
  ('QD', 'sale A cp 40; change B keep; payp 20', '3:1,5:1'),
  ('QE', 'sale A cp 40; change B keep; pay', '5:1'),
  ('QF', 'sale A cp 40', '-'),
  ('QG', 'sale A cp 40; change B', '-'),
  ('QH', 'sale A cp 40; spend A', '-'),
  ('QI', 'sale A cp 40; spend A; spend A; cancel', '-'),
  ('QJ', 'sale A cp 40; spend A; spend A; change B keep', '1:1,2:1'),
  ('QK', 'sale A cpb 40; change B keep', '2:1'),
  ('QL', 'sale A cp 40; change B; change C keep', '2:1'),
  ('QM', 'sale A cp; change B keep', '-'),
  ('QN6', 'sale A cp,cp 40; change B keep', '2:1,6:1'),
  ('QN6t', 'sale A cp,cp 40; change B; change C keep', '2:1,6:1'),
  ('QN6p', 'sale A cp,cp 40', '-'),
  ('QN6f', 'sale A cp,cp 140; change B keep', '2:2'),
  ('QN6e', 'draft A cp; addline cp; payp 40; change B keep', '2:1,6:1'),
  ('QN6c', 'sale A cp; addlines cp,cp; payp 40; change B keep', '2:1,6:1'),
  ('QN7a', 'sale A cp 40; fixinv amount', '7:1'),
  ('QN7b', 'sale A cp 40; spend A; cancel; reopen; unspend S1', '7:1'),
  ('QN7c', 'sale A cp 40; spend A; fixinv amount', '-'),
  ('QN8', 'refs; sale A cp 40; change B keep', '2:1,8:1'),
  ('QN9', 'sale A cp 40; change B keep; addline cp', '2:1,9:1'),
  ('QN9p', 'sale A cp 40; addline cp; change B keep', '2:1,9:1'),
  ('QN9c', 'sale A cp; addline cp; addline cp; payp 40; change B keep', '2:1,9:1');

-- The read-only query in 476's header (the same text).
create function pg_temp.t476_header_query() returns table(reason text, invoice_no text, n bigint) language sql as $hq$
with
-- the release records of package lines not settled, each followed to
-- the lot it reaches now (credit_lot_current), whom 462's rule says
-- holds it, and whether it reads as spent (473's test)
pre as (
  select pl.invoice_id, pl.invoice_item_id, c.customer_id, c.remaining_amount,
         public.invoice_credit_live_holder(pl.invoice_id, c.customer_id, c.created_at) as holder,
         pl.released_amount > 0 and coalesce(case when c.status = 'active' then c.remaining_amount end, 0) < pl.released_amount as spent
    from public.credit_package_progress_lots pl
    join public.invoices i on i.id = pl.invoice_id and i.deleted_at is null
    join public.invoice_items it on it.id = pl.invoice_item_id and it.credit_issued_at is null
    join public.customer_credit_lots c on c.id = public.credit_lot_current(pl.lot_id)
   where not exists (select 1 from public.invoice_benefit_values bv where bv.lot_id = any (public.credit_lot_chain(pl.lot_id)))),
-- each package or bundle line's sale, as 476's credit_line_sale_group works
-- it out (0: the invoice's own sale; else the revision of the correction
-- that added it once money had been received)
grp as (
  select it.invoice_id, it.id as invoice_item_id,
         coalesce((select case when coalesce(r.snapshot->'invoice'->>'status', '') in ('draft', 'unpaid')
                                    and coalesce((r.snapshot->'invoice'->>'paid_amount')::numeric, 0) = 0
                                    and r.snapshot->'invoice'->>'locked_at' is null
                               then 0 else r.revision_no end
                     from public.invoice_revisions r
                    where r.invoice_id = it.invoice_id and jsonb_typeof(r.snapshot->'items') = 'array'
                      and not (r.snapshot->'items' @> jsonb_build_array(jsonb_build_object('id', it.id)))
                    order by r.revision_no desc limit 1), 0) as sale
    from public.invoice_items it
    join public.invoices i on i.id = it.invoice_id and i.deleted_at is null
   where it.line_kind::text in ('credit_package', 'premium_bundle')),
-- the unsettled package and bundle lines that released nothing yet, not
-- split, of an invoice neither cancelled nor refunded
bare0 as (
  select it.invoice_id, it.id as invoice_item_id, g.sale
    from public.invoice_items it
    join grp g on g.invoice_item_id = it.id
    join public.invoices i on i.id = it.invoice_id and i.status::text not in ('cancelled', 'refunded')
   where it.credit_issued_at is null
     and it.credit_split_allocation_id is null and it.bundle_split_allocation_id is null
     and not exists (select 1 from public.invoice_credit_splits sp where sp.invoice_item_id = it.id)
     and not exists (select 1 from public.credit_package_progress_lots x where x.invoice_item_id = it.id)),
-- whom the release records of the lines sold with such a line name (each
-- followed to the lot it reaches now), by 462's rule
bare as (
  select b.invoice_id, b.invoice_item_id, i.customer_id as invoice_customer,
         count(distinct h.holder) as holders, count(*) filter (where h.holder is null) as no_holder,
         (array_agg(h.holder) filter (where h.holder is not null))[1] as holder
    from bare0 b
    join public.invoices i on i.id = b.invoice_id
    join grp o on o.invoice_id = b.invoice_id and o.invoice_item_id <> b.invoice_item_id and o.sale = b.sale
    join public.credit_package_progress_lots pl on pl.invoice_item_id = o.invoice_item_id
    join public.customer_credit_lots c on c.id = public.credit_lot_current(pl.lot_id)
    cross join lateral (select public.invoice_credit_live_holder(pl.invoice_id, c.customer_id, c.created_at) as holder) h
   group by b.invoice_id, b.invoice_item_id, i.customer_id),
-- per line with releases of its own: its holders, whether a release reads as
-- spent or a lot of it holds credit, the credit still to be released
own as (
  select p.invoice_id, p.invoice_item_id, i.customer_id as invoice_customer, i.status::text as status,
         count(distinct p.holder) as holders, count(*) filter (where p.holder is null) as no_holder,
         (array_agg(p.holder) filter (where p.holder is not null))[1] as holder,
         bool_or(p.spent) as spent, bool_or(p.remaining_amount > 0) as holding,
         round(public.credit_line_paid_entitlement(p.invoice_item_id)
               - public.credit_package_released_paid_credit(p.invoice_item_id), 2) as to_come
    from pre p
    join public.invoices i on i.id = p.invoice_id
   group by p.invoice_id, p.invoice_item_id, i.customer_id, i.status),
-- the lines whose later credit, Bonus, vouchers, sale record and commission
-- go to a holder other than the invoice's customer from 476: with releases
-- of their own (held by one customer), or with none, sold with lines whose
-- releases are (one customer); with what that changes for the vouchers and
-- the commission
moved as (
  select x.invoice_id, x.invoice_item_id, x.holder, x.invoice_customer, x.why,
         -- its settlement gives vouchers (a Premium Bundle's, a Credit Package's reward vouchers
         -- as issue_credit_package counts them)
         (it.line_kind::text = 'premium_bundle' and coalesce(pb.free_voucher_qty, 0) > 0
          or it.line_kind::text = 'credit_package' and coalesce(pk.grants_reward, false)
             and floor(coalesce(pk.customer_price, 0)
                       / nullif(coalesce(pk.reward_qualifying_amount,
                                         (public.legacy_lowest_rule(i.store_id, public.sg_today())).qualifying_amount, 994), 0)) >= 1) as vouchers,
         -- the invoice has no affiliate (none chosen, not cleared) and the holder's referrer is not
         -- the invoice's customer's: whose referrer earns changes
         i.affiliate_id is null and not coalesce(i.affiliate_selection_explicit, false)
           and (select c.referred_by from public.customers c where c.id = x.holder)
               is distinct from (select c.referred_by from public.customers c where c.id = x.invoice_customer) as referrer
    from (select o.invoice_id, o.invoice_item_id, o.holder, o.invoice_customer, 2 as why from own o
           where o.holders = 1 and o.no_holder = 0 and o.holder is distinct from o.invoice_customer
          union all
          select b.invoice_id, b.invoice_item_id, b.holder, b.invoice_customer, 6 from bare b
           where b.holders = 1 and b.no_holder = 0 and b.holder is distinct from b.invoice_customer) x
    join public.invoices i on i.id = x.invoice_id
    join public.invoice_items it on it.id = x.invoice_item_id
    left join public.premium_bundles pb on pb.id = it.premium_bundle_id
    left join public.credit_packages pk on pk.id = it.credit_package_id),
-- the package lines whose credit lots (settled: those its benefit rows name,
-- not what an Owner moved to someone else; not settled: its release records'
-- lots now) are held by more than one customer, merges followed
split as (
  select x.invoice_id, x.invoice_item_id
    from (select b.invoice_id, b.invoice_item_id, l.customer_id
            from public.invoice_benefit_values b
            join public.customer_credit_lots l on l.id = b.lot_id
            join public.invoice_items it on it.id = b.invoice_item_id and it.line_kind::text in ('credit_package', 'premium_bundle')
           where not public.invoice_benefit_moved_to_other(b.id)
          union all
          select p.invoice_id, p.invoice_item_id, p.customer_id from pre p) x
    join public.invoices i on i.id = x.invoice_id and i.deleted_at is null and i.status::text not in ('cancelled', 'refunded')
   group by x.invoice_id, x.invoice_item_id
  having count(distinct public.invoice_benefits_holder(x.invoice_id, x.customer_id, 'infinity')) > 1),
-- lots of credit released before full payment that no benefit row names,
-- holding less than they were granted but all that the release records
-- whose lot they are now count as released (nothing on them used), of an
-- invoice neither cancelled nor refunded with no reopening waiting
relunspent as (
  select pl.invoice_id, pl.invoice_item_id, c.id as lot_id
    from public.credit_package_progress_lots pl
    join public.invoices i on i.id = pl.invoice_id and i.deleted_at is null and i.status::text not in ('cancelled', 'refunded')
    join public.customer_credit_lots c on c.id = public.credit_lot_current(pl.lot_id)
   where c.status = 'active' and c.remaining_amount > 0 and c.remaining_amount < c.original_amount
     and not exists (select 1 from public.invoice_benefit_values bv where bv.lot_id = any (public.credit_lot_chain(pl.lot_id)))
     and not exists (select 1 from public.invoice_benefit_values bv where bv.lot_id = c.id and bv.invoice_id = pl.invoice_id)
     and not exists (select 1 from public.invoice_reopen_benefits q where q.invoice_id = pl.invoice_id and q.applied_at is null)
   group by pl.invoice_id, pl.invoice_item_id, c.id, c.remaining_amount
  having c.remaining_amount >= sum(pl.released_amount) and sum(pl.released_amount) > 0),
found(reason, invoice_id, n) as (
  select '1 changes: a package paid in part, not settled, of an invoice neither cancelled nor refunded, whose released credit was spent with nothing left on its lots and more still to be released; a ''transfer'' customer change passed (moving nothing, the later payments giving the rest to the new customer), from 476 it is refused as "Partly spent", as for the same package paid in full (the count is of lines)', o.invoice_id, count(*)
    from own o
   where o.status not in ('cancelled', 'refunded') and o.to_come > 0 and o.spent and not o.holding
   group by o.invoice_id
  union all
  select '2 changes: a package paid in part, not settled, whose released credit is held by one customer other than the invoice''s customer (a ''keep'' change, or a ''transfer'' and then a ''keep''): its next payments, its reopening and its settlement gave the invoice''s customer its credit (paid, and the Bonus), its vouchers and allowance and its sale record, from 476 that holder (the count is of lines)', m.invoice_id, count(*)
    from moved m where m.why = 2
   group by m.invoice_id
  union all
  select '3 for the Owner (not changed by 476: NOT COVERED 3): a package paid in part, not settled, whose released credit is held by more than one customer (split before 476): all it gives later still goes to the invoice''s customer; a data fix, or left as it is (the count is of lines)', o.invoice_id, count(*)
    from own o
   where o.holders > 1
   group by o.invoice_id
  union all
  select '4 changes: of 2 and 6, its settlement gives vouchers (a Premium Bundle''s vouchers and allowance, a Credit Package''s reward vouchers): from 476 to the holder, before to the invoice''s customer (the count is of lines)', m.invoice_id, count(*)
    from moved m where m.vouchers
   group by m.invoice_id
  union all
  select '5 for the Owner (not changed by 476: NOT COVERED 3): a package line, of an invoice neither cancelled nor refunded, whose credit lots are held by more than one customer (split before 476 by a ''keep'' change before full payment, or by a ''transfer'' change of a partly spent package before 473 or 476): a data fix, or left as it is (the count is of lines)', s.invoice_id, count(*)
    from split s
   group by s.invoice_id
  union all
  select '6 changes: a package or bundle line paid in part, not settled, that released nothing yet, sold with lines (the invoice''s own sale, or one correction''s lines) whose released credit is held by one customer other than the invoice''s customer: its payments and settlement gave the invoice''s customer all of it, from 476 that holder (the count is of lines)', m.invoice_id, count(*)
    from moved m where m.why = 6
   group by m.invoice_id
  union all
  select '7 changes: a lot of credit released before full payment that holds less than it was granted though nothing on it was used (a payment corrected lower; a Cancel, a reopening and a refund paid back onto it): a ''transfer'' customer change was refused as "Partly spent", from 476 it moves the lot where nothing else of the line was used (the count is of lots)', r.invoice_id, count(*)
    from relunspent r
   where not exists (select 1 from pre p where p.invoice_item_id = r.invoice_item_id and p.spent)
   group by r.invoice_id
  union all
  select '8 changes: of 2 and 6, the invoice has no affiliate and the holder''s referrer is not the invoice''s customer''s: from 476 the holder''s referrer earns its commission at settlement, and the part-payment commission it holds already moves to them at the next sync (the count is of lines)', m.invoice_id, count(*)
    from moved m where m.referrer
   group by m.invoice_id
  union all
  select '9 not changed (the Owner''s answer A): a package or bundle line a correction added once money had been received, not settled, that released nothing yet, on an invoice whose other lines'' released credit is held by someone other than the invoice''s customer: it goes to the invoice''s customer who pays for it, as before 476 (the count is of lines)', b.invoice_id, count(*)
    from bare0 b
    join public.invoices i on i.id = b.invoice_id
   where b.sale > 0
     and not exists (select 1 from bare x where x.invoice_item_id = b.invoice_item_id)
     and exists (select 1 from pre p where p.invoice_id = b.invoice_id and p.holder is distinct from i.customer_id)
   group by b.invoice_id)
select f.reason, i.invoice_no, f.n
  from found f join public.invoices i on i.id = f.invoice_id
 order by f.reason, i.invoice_no
$hq$;

-- The first run's notice's query in 476's file (the same CTEs).
create function pg_temp.t476_notice_query() returns table(reason int, invoice_id uuid) language sql as $nq$
with
-- the release records of package lines not settled, each followed to
-- the lot it reaches now (credit_lot_current), whom 462's rule says
-- holds it, and whether it reads as spent (473's test)
pre as (
  select pl.invoice_id, pl.invoice_item_id, c.customer_id, c.remaining_amount,
         public.invoice_credit_live_holder(pl.invoice_id, c.customer_id, c.created_at) as holder,
         pl.released_amount > 0 and coalesce(case when c.status = 'active' then c.remaining_amount end, 0) < pl.released_amount as spent
    from public.credit_package_progress_lots pl
    join public.invoices i on i.id = pl.invoice_id and i.deleted_at is null
    join public.invoice_items it on it.id = pl.invoice_item_id and it.credit_issued_at is null
    join public.customer_credit_lots c on c.id = public.credit_lot_current(pl.lot_id)
   where not exists (select 1 from public.invoice_benefit_values bv where bv.lot_id = any (public.credit_lot_chain(pl.lot_id)))),
-- each package or bundle line's sale, as 476's credit_line_sale_group works
-- it out (0: the invoice's own sale; else the revision of the correction
-- that added it once money had been received)
grp as (
  select it.invoice_id, it.id as invoice_item_id,
         coalesce((select case when coalesce(r.snapshot->'invoice'->>'status', '') in ('draft', 'unpaid')
                                    and coalesce((r.snapshot->'invoice'->>'paid_amount')::numeric, 0) = 0
                                    and r.snapshot->'invoice'->>'locked_at' is null
                               then 0 else r.revision_no end
                     from public.invoice_revisions r
                    where r.invoice_id = it.invoice_id and jsonb_typeof(r.snapshot->'items') = 'array'
                      and not (r.snapshot->'items' @> jsonb_build_array(jsonb_build_object('id', it.id)))
                    order by r.revision_no desc limit 1), 0) as sale
    from public.invoice_items it
    join public.invoices i on i.id = it.invoice_id and i.deleted_at is null
   where it.line_kind::text in ('credit_package', 'premium_bundle')),
-- the unsettled package and bundle lines that released nothing yet, not
-- split, of an invoice neither cancelled nor refunded
bare0 as (
  select it.invoice_id, it.id as invoice_item_id, g.sale
    from public.invoice_items it
    join grp g on g.invoice_item_id = it.id
    join public.invoices i on i.id = it.invoice_id and i.status::text not in ('cancelled', 'refunded')
   where it.credit_issued_at is null
     and it.credit_split_allocation_id is null and it.bundle_split_allocation_id is null
     and not exists (select 1 from public.invoice_credit_splits sp where sp.invoice_item_id = it.id)
     and not exists (select 1 from public.credit_package_progress_lots x where x.invoice_item_id = it.id)),
-- whom the release records of the lines sold with such a line name (each
-- followed to the lot it reaches now), by 462's rule
bare as (
  select b.invoice_id, b.invoice_item_id, i.customer_id as invoice_customer,
         count(distinct h.holder) as holders, count(*) filter (where h.holder is null) as no_holder,
         (array_agg(h.holder) filter (where h.holder is not null))[1] as holder
    from bare0 b
    join public.invoices i on i.id = b.invoice_id
    join grp o on o.invoice_id = b.invoice_id and o.invoice_item_id <> b.invoice_item_id and o.sale = b.sale
    join public.credit_package_progress_lots pl on pl.invoice_item_id = o.invoice_item_id
    join public.customer_credit_lots c on c.id = public.credit_lot_current(pl.lot_id)
    cross join lateral (select public.invoice_credit_live_holder(pl.invoice_id, c.customer_id, c.created_at) as holder) h
   group by b.invoice_id, b.invoice_item_id, i.customer_id),
-- per line with releases of its own: its holders, whether a release reads as
-- spent or a lot of it holds credit, the credit still to be released
own as (
  select p.invoice_id, p.invoice_item_id, i.customer_id as invoice_customer, i.status::text as status,
         count(distinct p.holder) as holders, count(*) filter (where p.holder is null) as no_holder,
         (array_agg(p.holder) filter (where p.holder is not null))[1] as holder,
         bool_or(p.spent) as spent, bool_or(p.remaining_amount > 0) as holding,
         round(public.credit_line_paid_entitlement(p.invoice_item_id)
               - public.credit_package_released_paid_credit(p.invoice_item_id), 2) as to_come
    from pre p
    join public.invoices i on i.id = p.invoice_id
   group by p.invoice_id, p.invoice_item_id, i.customer_id, i.status),
-- the lines whose later credit, Bonus, vouchers, sale record and commission
-- go to a holder other than the invoice's customer from 476: with releases
-- of their own (held by one customer), or with none, sold with lines whose
-- releases are (one customer); with what that changes for the vouchers and
-- the commission
moved as (
  select x.invoice_id, x.invoice_item_id, x.holder, x.invoice_customer, x.why,
         -- its settlement gives vouchers (a Premium Bundle's, a Credit Package's reward vouchers
         -- as issue_credit_package counts them)
         (it.line_kind::text = 'premium_bundle' and coalesce(pb.free_voucher_qty, 0) > 0
          or it.line_kind::text = 'credit_package' and coalesce(pk.grants_reward, false)
             and floor(coalesce(pk.customer_price, 0)
                       / nullif(coalesce(pk.reward_qualifying_amount,
                                         (public.legacy_lowest_rule(i.store_id, public.sg_today())).qualifying_amount, 994), 0)) >= 1) as vouchers,
         -- the invoice has no affiliate (none chosen, not cleared) and the holder's referrer is not
         -- the invoice's customer's: whose referrer earns changes
         i.affiliate_id is null and not coalesce(i.affiliate_selection_explicit, false)
           and (select c.referred_by from public.customers c where c.id = x.holder)
               is distinct from (select c.referred_by from public.customers c where c.id = x.invoice_customer) as referrer
    from (select o.invoice_id, o.invoice_item_id, o.holder, o.invoice_customer, 2 as why from own o
           where o.holders = 1 and o.no_holder = 0 and o.holder is distinct from o.invoice_customer
          union all
          select b.invoice_id, b.invoice_item_id, b.holder, b.invoice_customer, 6 from bare b
           where b.holders = 1 and b.no_holder = 0 and b.holder is distinct from b.invoice_customer) x
    join public.invoices i on i.id = x.invoice_id
    join public.invoice_items it on it.id = x.invoice_item_id
    left join public.premium_bundles pb on pb.id = it.premium_bundle_id
    left join public.credit_packages pk on pk.id = it.credit_package_id),
-- the package lines whose credit lots (settled: those its benefit rows name,
-- not what an Owner moved to someone else; not settled: its release records'
-- lots now) are held by more than one customer, merges followed
split as (
  select x.invoice_id, x.invoice_item_id
    from (select b.invoice_id, b.invoice_item_id, l.customer_id
            from public.invoice_benefit_values b
            join public.customer_credit_lots l on l.id = b.lot_id
            join public.invoice_items it on it.id = b.invoice_item_id and it.line_kind::text in ('credit_package', 'premium_bundle')
           where not public.invoice_benefit_moved_to_other(b.id)
          union all
          select p.invoice_id, p.invoice_item_id, p.customer_id from pre p) x
    join public.invoices i on i.id = x.invoice_id and i.deleted_at is null and i.status::text not in ('cancelled', 'refunded')
   group by x.invoice_id, x.invoice_item_id
  having count(distinct public.invoice_benefits_holder(x.invoice_id, x.customer_id, 'infinity')) > 1),
-- lots of credit released before full payment that no benefit row names,
-- holding less than they were granted but all that the release records
-- whose lot they are now count as released (nothing on them used), of an
-- invoice neither cancelled nor refunded with no reopening waiting
relunspent as (
  select pl.invoice_id, pl.invoice_item_id, c.id as lot_id
    from public.credit_package_progress_lots pl
    join public.invoices i on i.id = pl.invoice_id and i.deleted_at is null and i.status::text not in ('cancelled', 'refunded')
    join public.customer_credit_lots c on c.id = public.credit_lot_current(pl.lot_id)
   where c.status = 'active' and c.remaining_amount > 0 and c.remaining_amount < c.original_amount
     and not exists (select 1 from public.invoice_benefit_values bv where bv.lot_id = any (public.credit_lot_chain(pl.lot_id)))
     and not exists (select 1 from public.invoice_benefit_values bv where bv.lot_id = c.id and bv.invoice_id = pl.invoice_id)
     and not exists (select 1 from public.invoice_reopen_benefits q where q.invoice_id = pl.invoice_id and q.applied_at is null)
   group by pl.invoice_id, pl.invoice_item_id, c.id, c.remaining_amount
  having c.remaining_amount >= sum(pl.released_amount) and sum(pl.released_amount) > 0),
found(reason, invoice_id, n) as (
  select '1 changes: a package paid in part, not settled, of an invoice neither cancelled nor refunded, whose released credit was spent with nothing left on its lots and more still to be released; a ''transfer'' customer change passed (moving nothing, the later payments giving the rest to the new customer), from 476 it is refused as "Partly spent", as for the same package paid in full (the count is of lines)', o.invoice_id, count(*)
    from own o
   where o.status not in ('cancelled', 'refunded') and o.to_come > 0 and o.spent and not o.holding
   group by o.invoice_id
  union all
  select '2 changes: a package paid in part, not settled, whose released credit is held by one customer other than the invoice''s customer (a ''keep'' change, or a ''transfer'' and then a ''keep''): its next payments, its reopening and its settlement gave the invoice''s customer its credit (paid, and the Bonus), its vouchers and allowance and its sale record, from 476 that holder (the count is of lines)', m.invoice_id, count(*)
    from moved m where m.why = 2
   group by m.invoice_id
  union all
  select '3 for the Owner (not changed by 476: NOT COVERED 3): a package paid in part, not settled, whose released credit is held by more than one customer (split before 476): all it gives later still goes to the invoice''s customer; a data fix, or left as it is (the count is of lines)', o.invoice_id, count(*)
    from own o
   where o.holders > 1
   group by o.invoice_id
  union all
  select '4 changes: of 2 and 6, its settlement gives vouchers (a Premium Bundle''s vouchers and allowance, a Credit Package''s reward vouchers): from 476 to the holder, before to the invoice''s customer (the count is of lines)', m.invoice_id, count(*)
    from moved m where m.vouchers
   group by m.invoice_id
  union all
  select '5 for the Owner (not changed by 476: NOT COVERED 3): a package line, of an invoice neither cancelled nor refunded, whose credit lots are held by more than one customer (split before 476 by a ''keep'' change before full payment, or by a ''transfer'' change of a partly spent package before 473 or 476): a data fix, or left as it is (the count is of lines)', s.invoice_id, count(*)
    from split s
   group by s.invoice_id
  union all
  select '6 changes: a package or bundle line paid in part, not settled, that released nothing yet, sold with lines (the invoice''s own sale, or one correction''s lines) whose released credit is held by one customer other than the invoice''s customer: its payments and settlement gave the invoice''s customer all of it, from 476 that holder (the count is of lines)', m.invoice_id, count(*)
    from moved m where m.why = 6
   group by m.invoice_id
  union all
  select '7 changes: a lot of credit released before full payment that holds less than it was granted though nothing on it was used (a payment corrected lower; a Cancel, a reopening and a refund paid back onto it): a ''transfer'' customer change was refused as "Partly spent", from 476 it moves the lot where nothing else of the line was used (the count is of lots)', r.invoice_id, count(*)
    from relunspent r
   where not exists (select 1 from pre p where p.invoice_item_id = r.invoice_item_id and p.spent)
   group by r.invoice_id
  union all
  select '8 changes: of 2 and 6, the invoice has no affiliate and the holder''s referrer is not the invoice''s customer''s: from 476 the holder''s referrer earns its commission at settlement, and the part-payment commission it holds already moves to them at the next sync (the count is of lines)', m.invoice_id, count(*)
    from moved m where m.referrer
   group by m.invoice_id
  union all
  select '9 not changed (the Owner''s answer A): a package or bundle line a correction added once money had been received, not settled, that released nothing yet, on an invoice whose other lines'' released credit is held by someone other than the invoice''s customer: it goes to the invoice''s customer who pays for it, as before 476 (the count is of lines)', b.invoice_id, count(*)
    from bare0 b
    join public.invoices i on i.id = b.invoice_id
   where b.sale > 0
     and not exists (select 1 from bare x where x.invoice_item_id = b.invoice_item_id)
     and exists (select 1 from pre p where p.invoice_id = b.invoice_id and p.holder is distinct from i.customer_id)
   group by b.invoice_id)
select distinct left(f.reason, 1)::int, f.invoice_id from found f
$nq$;

-- ===== S. Where it starts =====
create temp table t476_fp(k text primary key, v text);
create function pg_temp.t476_grants(p_without text[] default '{}') returns text language sql as $f$
  select md5(string_agg(p.oid::regprocedure::text || '=' || coalesce(p.proacl::text, ''), '|' order by p.oid::regprocedure::text))
    from pg_proc p where p.pronamespace = 'public'::regnamespace and not (p.proname = any (p_without)) $f$;
create function pg_temp.t476_grant_set(p_sig text) returns text[] language sql as $f$
  select array_agg(x::text order by x::text) from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || p_sig) $f$;
-- The grants of every function as sets (the order production lists them
-- in differs from a copy's).
create function pg_temp.t476_grant_sets(p_without text[] default '{}') returns text language sql as $f$
  select md5(string_agg(s, '|' order by s)) from (
    select p.oid::regprocedure::text || '=' || coalesce((select string_agg(x::text, ',' order by x::text) from unnest(p.proacl) x), '') as s
      from pg_proc p where p.pronamespace = 'public'::regnamespace and not (p.proname = any (p_without))) g $f$;
insert into t476_fp values ('start', pg_temp.t476_fingerprint()), ('grants', pg_temp.t476_grant_sets(array['credit_line_sale_group', 'credit_line_benefits_holder', 'invoice_credit_receivers'])),
  ('triggers', pg_temp.t476_inv_triggers());
do $$ begin
  perform pg_temp.t476_check(pg_temp.t476_462_in() and pg_temp.t476_463_in() and pg_temp.t476_470_in() and pg_temp.t476_471_in()
      and pg_temp.t476_472_in() and pg_temp.t476_473_in() and pg_temp.t476_475_in()
      -- (477's forwarder where 477 is in, special-refund-move-repaired-lot-477.sql:
      -- -v nomig=1 on a copy with 476 and 477)
      and md5(pg_get_functiondef('public.credit_given_back_follows(uuid)'::regprocedure))
          in ('f2a7a4d1ca28f0865b14e3f1e5e02bbb', 'a0f2f5ece30be439049dca275802237a')
      and md5(pg_get_functiondef('public.reopen_invoice(uuid,text,uuid)'::regprocedure)) = '30066e137b9b75b5789a050c14debc04'
      and md5(pg_get_functiondef('public.invoice_reopen_preview(uuid)'::regprocedure)) = 'e09ebf9c0841ef5463f96b26f4933541',
    'S 462, 463 and 470 to 475 are in: the forwarder at 472''s AFTER (477''s where it is in), reopen_invoice at 475''s, the Reopen dialog''s preview at 474''s (476 goes in after them)');
end $$;
\if :{?nomig}
do $$ begin
  perform pg_temp.t476_check(pg_temp.t476_in() and pg_temp.t476_at('after'), 'S -v nomig=1: 476 is in, as tested');
end $$;
\else
do $$ begin
  perform pg_temp.t476_check(not pg_temp.t476_in() and pg_temp.t476_at('before'),
    'S 476 is not in yet and the six functions are at their BEFORE (this suite installs it; use -v nomig=1 where it is in)');
end $$;

-- ===== R. Before 476: each case reproduced (undone afterwards) =====
-- A 'fixed' case does not end as 476 makes it; a control or known case
-- does, exactly.
savepoint t476_r;
do $$
declare c record; o jsonb; res text := '';
begin
  for c in select * from t476_cases order by ord loop
    o := pg_temp.t476_run('before', c.k, c.steps);
    if c.kind = 'fixed' then
      perform pg_temp.t476_check(not (pg_temp.t476_meets(o, c.expect) and coalesce(o->>'invariants', '') = ''),
        'R ' || c.k || ' already ends as 476 makes it, without 476: ' || o::text);
      res := res || format(E'\n  %s: %s; customer %s; blocked %s; sale %s; comm %s%s%s', c.k,
        (select string_agg(h.key || ' ' || (h.value #>> '{}'), ', ' order by h.key) from jsonb_each(o->'holds') h),
        o->>'customer', o->>'blocked', o->>'sale', o->>'comm', coalesce('; ' || nullif(o->>'invariants', ''), ''),
        coalesce('; refused: ' || left(o->>'error', 120), ''));
    else
      perform pg_temp.t476_check(pg_temp.t476_meets(o, c.expect) and coalesce(o->>'invariants', '') = ''
          and coalesce((o->>'cancel_left')::numeric, 0) = 0,
        'R ' || c.kind || ' ' || c.k || ' without 476: ' || coalesce(pg_temp.t476_diff(o, c.expect), '') || ' ' || o::text);
    end if;
  end loop;
  for c in select * from t476_qstates loop
    perform pg_temp.t476_run('before', c.k, c.steps);
  end loop;
  raise notice 'PASS R: without 476 every fixed case ends otherwise (the faults reproduced), the controls and the known cases as expected:%', res;
end $$;
-- The faults, by name: TQn2 B S$60 with A's S$40 used; K1 A S$40, B S$60; K2
-- A S$20, B S$60; TK S$60 held by C, not by the benefits' holder B; K1v the
-- vouchers and the sale record B's; KAL, KAP and KAL1 B S$160 (round 1's
-- build: A S$200); CK1 B's referrer earns; TQfix and TQcru refused.
do $$ begin
  perform pg_temp.t476_check((select v->'holds' from t476_res where phase = 'before' and k = 'TQn2') @> '{"A":"0.00","B":"60.00"}'
      and (select v->>'error' from t476_res where phase = 'before' and k = 'TQn2') is null
      and (select v->'holds' from t476_res where phase = 'before' and k = 'K1') @> '{"A":"40.00","B":"60.00"}'
      and (select v->'holds' from t476_res where phase = 'before' and k = 'K2') @> '{"A":"20.00","B":"60.00"}'
      and (select v->>'invariants' from t476_res where phase = 'before' and k = 'TK') like '%S$60.00 held by T476 before/TK/C, not by the benefits'' holder T476 before/TK/B;%'
      and (select v->'holds' from t476_res where phase = 'before' and k = 'K1v') @> '{"A":"40.00","B":"100.00/2"}'
      and (select v->>'sale' from t476_res where phase = 'before' and k = 'K1v') = 'B'
      and (select v->'holds' from t476_res where phase = 'before' and k = 'KAL') @> '{"A":"40.00","B":"160.00"}'
      and (select v->'holds' from t476_res where phase = 'before' and k = 'KAP') @> '{"A":"40.00","B":"160.00"}'
      and (select v->'holds' from t476_res where phase = 'before' and k = 'KAL1') @> '{"A":"40.00","B":"160.00"}'
      and (select v->>'comm' from t476_res where phase = 'before' and k = 'CK1') = 'RB 4.50'
      and (select v->>'comm' from t476_res where phase = 'before' and k = 'IK1m') = 'RB 1.80'
      and (select v->>'error' from t476_res where phase = 'before' and k = 'TQfix') like 'change B: %Paid credit 35.00 (Partly spent)%'
      and (select v->>'error' from t476_res where phase = 'before' and k = 'TQcru') like 'change B: %Paid credit 20.00 (Partly spent)%',
    'R the faults are not as 473''s NOT COVERED 1 and 2 and the review of 475 to 478 describe them');
end $$;

-- ===== Q. The header's read-only query, on these states =====
create temp table t476_q as select * from pg_temp.t476_header_query();
create function pg_temp.t476_q_of(p_case text) returns text language sql as $f$
  select coalesce(string_agg(left(q.reason, 1) || ':' || q.n, ',' order by q.reason), '-')
    from t476_q q join invoices i on i.invoice_no = q.invoice_no
   where i.id = pg_temp.t476_id('before/' || p_case || '/inv') $f$;
create function pg_temp.t476_q_list(p_reason text) returns text language sql as $f$
  select coalesce(string_agg(c.k, ',' order by c.k), '-')
    from (select k from t476_cases union select k from t476_qstates) c
    join invoices i on i.id = pg_temp.t476_id('before/' || c.k || '/inv')
   where exists (select 1 from t476_q q where q.invoice_no = i.invoice_no and left(q.reason, 1) = p_reason) $f$;
do $$
declare c record;
begin
  for c in select * from t476_qstates order by k loop
    perform pg_temp.t476_check(pg_temp.t476_q_of(c.k) = c.expect,
      'Q ' || c.k || ' is listed as ' || pg_temp.t476_q_of(c.k) || ' (wanted ' || c.expect || ')');
  end loop;
  raise notice 'Q lists: 1 %; 2 %; 3 %; 4 %; 5 %; 6 %; 7 %; 8 %; 9 %', pg_temp.t476_q_list('1'), pg_temp.t476_q_list('2'), pg_temp.t476_q_list('3'),
    pg_temp.t476_q_list('4'), pg_temp.t476_q_list('5'), pg_temp.t476_q_list('6'), pg_temp.t476_q_list('7'), pg_temp.t476_q_list('8'),
    pg_temp.t476_q_list('9');
  -- (each reason's list over every state: 1: not settled, released credit all spent, nothing on a lot, more to come (QA, QJ: the R cases all end paid, refused or holding credit before 476); 2: the release held by one customer other than the invoice's customer, not settled (the states left part-paid after a 'keep' change; IK1m is one); 3: split before 476 (K1p, QD); 4: of 2 and 6, with vouchers (QC, the bundle; the S$100 package's price is under the reward's qualifying amount); 5: lots of one line held by two customers, merges followed, the invoice neither cancelled nor refunded: the R states of every case 476 fixes that end settled and split, QD, QE, the known Kdel, and the controls K1mv (split by the 'keep' before its Move), TQcr and TQn2cx (473's NOT COVERED 3); not K1can (cancelled); 6: a line that released nothing, sold with a line whose release is held by someone else (QN6, QN6t, QN6e: an edit before any money, QN6c: one correction's two lines); 7: a released lot short of what it was granted though nothing was used (QN7a, QN7b, and the R states of TQfix, TQfixp, TQcru, TQcrup, whose change is refused before 476); 8: of 2, the referrers differ (QN8, IK1m: 'refs'); 9: a line a correction added once money was received, not sold with the released line (QN9, QN9p, QN9c))
  perform pg_temp.t476_check(pg_temp.t476_q_list('1') = 'QA,QJ', 'Q 1 lists ' || pg_temp.t476_q_list('1'));
  perform pg_temp.t476_check(pg_temp.t476_q_list('2') = 'IK1m,QB,QC,QJ,QK,QL,QN6,QN6c,QN6e,QN6f,QN6t,QN8,QN9,QN9c,QN9p', 'Q 2 lists ' || pg_temp.t476_q_list('2'));
  perform pg_temp.t476_check(pg_temp.t476_q_list('3') = 'K1p,QD', 'Q 3 lists ' || pg_temp.t476_q_list('3'));
  perform pg_temp.t476_check(pg_temp.t476_q_list('4') = 'QC', 'Q 4 lists ' || pg_temp.t476_q_list('4'));
  perform pg_temp.t476_check(pg_temp.t476_q_list('5') = 'C3c,C3cp,C5,CK1,CK1v,CKAL,CX1,G5,G5p,IK1,IKAL,IX1,K1,K1b,K1cr,K1m,K1mb,K1mv,K1n2,K1p,K1sp,K1v,K2,K2c,KAE,KAL,KAL1,KALp,KAP,KAT2,KAT3,Kdel,Kfix,KK,Kmg,Kst,Kvb,Kw,L4,QD,QE,TK,TQcr,TQn2,TQn2b,TQn2cx,TQn2m,TQn2r,TQn2v,TQn2w,TQn2w2,TQn2x,X1,X10,X2,X3,X4,X5,X6,X7,X8', 'Q 5 lists ' || pg_temp.t476_q_list('5'));
  perform pg_temp.t476_check(pg_temp.t476_q_list('6') = 'QN6,QN6c,QN6e,QN6t', 'Q 6 lists ' || pg_temp.t476_q_list('6'));
  perform pg_temp.t476_check(pg_temp.t476_q_list('7') = 'QN7a,QN7b,TQcru,TQcrup,TQfix,TQfixp', 'Q 7 lists ' || pg_temp.t476_q_list('7'));
  perform pg_temp.t476_check(pg_temp.t476_q_list('8') = 'IK1m,QN8', 'Q 8 lists ' || pg_temp.t476_q_list('8'));
  perform pg_temp.t476_check(pg_temp.t476_q_list('9') = 'QN9,QN9c,QN9p', 'Q 9 lists ' || pg_temp.t476_q_list('9'));
  -- The first run's notice names the same invoices under the same reasons
  -- (its own text of the query, from the migration file).
  perform pg_temp.t476_check(
        (select array_agg(x order by x) from (select distinct left(q.reason, 1) || ' ' || q.invoice_no as x from t476_q q) d)
      is not distinct from (select array_agg(x order by x) from (select f.reason || ' ' || i.invoice_no as x
                                from pg_temp.t476_notice_query() f join invoices i on i.id = f.invoice_id) d),
    'Q the first run''s notice does not name what the header''s query lists');
  raise notice 'PASS Q: the header''s read-only query lists % invoices (%), each reason as expected; the first run''s notice names the same',
    (select count(distinct invoice_no) from t476_q),
    (select string_agg(left(reason, 1) || ' ' || n, ', ' order by left(reason, 1)) from (select reason, count(*) n from t476_q group by reason) x);
end $$;
-- 476 installed on these states (undone): its first run reads them (the
-- notice above, for the Owner) and its self-test runs beside them.
savepoint t476_qn;
\ir ../../../supabase/476_part_paid_change_same_as_paid_in_full.sql
do $$ begin
  perform pg_temp.t476_check(pg_temp.t476_in() and pg_temp.t476_at('after'), 'Q 476 did not install on the R states');
end $$;
rollback to savepoint t476_qn;
-- Keep R's outcomes; undo its records.
select coalesce(jsonb_object_agg(k, v), '{}'::jsonb)::text as t476_rbefore from t476_res where phase = 'before' \gset
rollback to savepoint t476_r;
insert into t476_res select 'before', key, value from jsonb_each(:'t476_rbefore'::jsonb);
do $$ begin
  perform pg_temp.t476_check((select count(*) from t476_res where phase = 'before') = (select count(*) from t476_cases) + (select count(*) from t476_qstates)
      and pg_temp.t476_fingerprint() = (select v from t476_fp where k = 'start'),
    'R undone, its outcomes kept');
end $$;

-- ===== 9. The refusals, each changing nothing =====
-- 9a A function it changes is neither its BEFORE nor its AFTER.
savepoint t476_9;
alter function public.sell_premium_bundle(uuid,uuid,uuid,jsonb,jsonb,numeric,numeric,uuid,boolean,uuid) set work_mem = '64kB';
\set ON_ERROR_STOP off
\ir ../../../supabase/476_part_paid_change_same_as_paid_in_full.sql
\set ON_ERROR_STOP on
rollback to savepoint t476_9;
select set_config('t476.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t476_check(current_setting('t476.msg') like '476: public.sell_premium_bundle(uuid,uuid,uuid,jsonb,jsonb,numeric,numeric,uuid,boolean,uuid) is not the version this was tested against (md5 %). Re-read it and re-test before applying.'
      and not pg_temp.t476_in(), '9a refused with: ' || current_setting('t476.msg'));
end $$;
savepoint t476_9;
alter function public.move_invoice_benefits_to_customer(uuid,uuid,uuid,text) set work_mem = '64kB';
\set ON_ERROR_STOP off
\ir ../../../supabase/476_part_paid_change_same_as_paid_in_full.sql
\set ON_ERROR_STOP on
rollback to savepoint t476_9;
select set_config('t476.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t476_check(current_setting('t476.msg') like '476: public.move_invoice_benefits_to_customer(uuid,uuid,uuid,text) is not the version this was tested against (md5 %). Re-read it and re-test before applying.'
      and not pg_temp.t476_in(), '9a2 refused with: ' || current_setting('t476.msg'));
end $$;
-- 9b Partly in: one of the three it adds made by hand, the six at their BEFORE.
savepoint t476_9;
create or replace function public.credit_line_benefits_holder(p_invoice_item_id uuid) returns uuid language sql stable security definer set search_path to 'public' as $f$ select null::uuid $f$;
\set ON_ERROR_STOP off
\ir ../../../supabase/476_part_paid_change_same_as_paid_in_full.sql
\set ON_ERROR_STOP on
rollback to savepoint t476_9;
select set_config('t476.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t476_check(current_setting('t476.msg') = '476: the functions are partly this version (6 of 6 at their BEFORE, 0 at their AFTER; of the three it adds 0 at their AFTER, 1 present). Re-read them and re-test before applying.'
      and not pg_temp.t476_in(), '9b refused with: ' || current_setting('t476.msg'));
end $$;
-- 9c A function it relies on is not as read (a setting added to it): the
-- settlement, 475's reopening, the line writer the marker reads.
savepoint t476_9;
alter function public.issue_credit_lines_for_invoice(uuid) set work_mem = '64kB';
\set ON_ERROR_STOP off
\ir ../../../supabase/476_part_paid_change_same_as_paid_in_full.sql
\set ON_ERROR_STOP on
rollback to savepoint t476_9;
select set_config('t476.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t476_check(current_setting('t476.msg') like '476: public.issue_credit_lines_for_invoice(uuid) is missing or not the version this was tested against (md5 %). Re-read it and re-test before applying (476 goes in after 475).'
      and not pg_temp.t476_in(), '9c refused with: ' || current_setting('t476.msg'));
end $$;
savepoint t476_9;
alter function public.reopen_invoice(uuid, text, uuid) set work_mem = '64kB';
\set ON_ERROR_STOP off
\ir ../../../supabase/476_part_paid_change_same_as_paid_in_full.sql
\set ON_ERROR_STOP on
rollback to savepoint t476_9;
select set_config('t476.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t476_check(current_setting('t476.msg') like '476: public.reopen_invoice(uuid,text,uuid) is missing or not the version this was tested against (md5 %)%'
      and not pg_temp.t476_in(), '9c2 refused with: ' || current_setting('t476.msg'));
end $$;
savepoint t476_9;
alter function public.update_invoice_internal(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb,text,boolean) set work_mem = '64kB';
\set ON_ERROR_STOP off
\ir ../../../supabase/476_part_paid_change_same_as_paid_in_full.sql
\set ON_ERROR_STOP on
rollback to savepoint t476_9;
select set_config('t476.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t476_check(current_setting('t476.msg') like '476: public.update_invoice_internal(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb,text,boolean) is missing or not the version this was tested against (md5 %)%'
      and not pg_temp.t476_in(), '9c3 refused with: ' || current_setting('t476.msg'));
end $$;
-- 9d Another function takes a name it changes or adds (an overload).
savepoint t476_9;
create function public.release_credit_package_paid_credit(p text) returns text language sql as $f$ select p $f$;
\set ON_ERROR_STOP off
\ir ../../../supabase/476_part_paid_change_same_as_paid_in_full.sql
\set ON_ERROR_STOP on
rollback to savepoint t476_9;
select set_config('t476.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t476_check(current_setting('t476.msg') = '476: another function takes the name of one this changes or adds: release_credit_package_paid_credit(text)'
      and not pg_temp.t476_in(), '9d refused with: ' || current_setting('t476.msg'));
end $$;
savepoint t476_9;
create function public.credit_line_sale_group(p text) returns text language sql as $f$ select p $f$;
\set ON_ERROR_STOP off
\ir ../../../supabase/476_part_paid_change_same_as_paid_in_full.sql
\set ON_ERROR_STOP on
rollback to savepoint t476_9;
select set_config('t476.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t476_check(current_setting('t476.msg') = '476: another function takes the name of one this changes or adds: credit_line_sale_group(text)'
      and not pg_temp.t476_in(), '9d2 refused with: ' || current_setting('t476.msg'));
end $$;
-- 9e A new caller of the release (it would give credit its own way), of the
-- mover, of update_invoice_internal.
savepoint t476_9;
create function public.t476_probe_release(p uuid) returns jsonb language sql as $f$
  select public.release_credit_package_paid_credit(p) $f$;
\set ON_ERROR_STOP off
\ir ../../../supabase/476_part_paid_change_same_as_paid_in_full.sql
\set ON_ERROR_STOP on
rollback to savepoint t476_9;
select set_config('t476.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t476_check(current_setting('t476.msg') like '476: the functions that call release_credit_package_paid_credit are not as read on 27 Oct 2026 (%t476_probe_release(uuid)%'
      and not pg_temp.t476_in(), '9e refused with: ' || current_setting('t476.msg'));
end $$;
savepoint t476_9;
create function public.t476_probe_move(p uuid) returns jsonb language sql as $f$
  select public.move_invoice_benefits_to_customer(p, p, p, 'x') $f$;
\set ON_ERROR_STOP off
\ir ../../../supabase/476_part_paid_change_same_as_paid_in_full.sql
\set ON_ERROR_STOP on
rollback to savepoint t476_9;
select set_config('t476.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t476_check(current_setting('t476.msg') like '476: the functions that call move_invoice_benefits_to_customer are not as read on 27 Oct 2026 (%t476_probe_move(uuid)%'
      and not pg_temp.t476_in(), '9e2 refused with: ' || current_setting('t476.msg'));
end $$;
savepoint t476_9;
create function public.t476_probe_edit(p uuid) returns uuid language sql as $f$
  select public.update_invoice_internal(p, p, p, '[]'::jsonb, 0, null, null, '[]'::jsonb, 'x', false) $f$;
\set ON_ERROR_STOP off
\ir ../../../supabase/476_part_paid_change_same_as_paid_in_full.sql
\set ON_ERROR_STOP on
rollback to savepoint t476_9;
select set_config('t476.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t476_check(current_setting('t476.msg') like '476: what calls update_invoice_internal or writes the package and bundle sale records is not as read on 27 Oct 2026 (%t476_probe_edit(uuid)%'
      and not pg_temp.t476_in(), '9e3 refused with: ' || current_setting('t476.msg'));
end $$;
-- 9f A new grant of credit.
savepoint t476_9;
create function public.t476_probe_grant(p uuid) returns uuid language sql as $f$
  select public.grant_customer_credit(p, 'paid', 1, 'credit_package') $f$;
\set ON_ERROR_STOP off
\ir ../../../supabase/476_part_paid_change_same_as_paid_in_full.sql
\set ON_ERROR_STOP on
rollback to savepoint t476_9;
select set_config('t476.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t476_check(current_setting('t476.msg') like '476: what grants credit or makes a credit lot is not as read on 27 Oct 2026 (%t476_probe_grant(uuid)%'
      and not pg_temp.t476_in(), '9f refused with: ' || current_setting('t476.msg'));
end $$;
-- 9g A new writer of the release record.
savepoint t476_9;
create function public.t476_probe_record() returns void language sql as $f$
  update public.credit_package_progress_lots set released_amount = released_amount where false $f$;
\set ON_ERROR_STOP off
\ir ../../../supabase/476_part_paid_change_same_as_paid_in_full.sql
\set ON_ERROR_STOP on
rollback to savepoint t476_9;
select set_config('t476.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t476_check(current_setting('t476.msg') like '476: what writes the release record, or reads or writes the customer change''s Audit Log row, is not as read on 27 Oct 2026 (%t476_probe_record()%'
      and not pg_temp.t476_in(), '9g refused with: ' || current_setting('t476.msg'));
end $$;
-- 9h The trigger that releases and settles on invoices changed (a second
-- one on the same function).
savepoint t476_9;
create trigger t476_probe_trg after insert on public.invoices for each row execute function public.trg_create_therapy_on_paid();
\set ON_ERROR_STOP off
\ir ../../../supabase/476_part_paid_change_same_as_paid_in_full.sql
\set ON_ERROR_STOP on
rollback to savepoint t476_9;
select set_config('t476.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t476_check(current_setting('t476.msg') = '476: the trigger that releases and settles package credit on invoices is not as read on 27 Oct 2026'
      and not pg_temp.t476_in(), '9h refused with: ' || current_setting('t476.msg'));
end $$;
-- 9j (answer A's marker) a new way to add invoice lines, or to write
-- revisions; a row policy letting a page write revisions.
savepoint t476_9;
create function public.t476_probe_line(p uuid) returns void language sql as $f$
  insert into public.invoice_items (invoice_id, quantity, unit_price, line_total) select p, 1, 0, 0 where false $f$;
\set ON_ERROR_STOP off
\ir ../../../supabase/476_part_paid_change_same_as_paid_in_full.sql
\set ON_ERROR_STOP on
rollback to savepoint t476_9;
select set_config('t476.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t476_check(current_setting('t476.msg') like '476: what adds invoice lines or writes invoice revisions is not as read on 27 Oct 2026 (%t476_probe_line(uuid)%'
      and not pg_temp.t476_in(), '9j refused with: ' || current_setting('t476.msg'));
end $$;
savepoint t476_9;
create function public.t476_probe_rev(p uuid) returns void language sql as $f$
  delete from public.invoice_revisions where invoice_id = p and false $f$;
\set ON_ERROR_STOP off
\ir ../../../supabase/476_part_paid_change_same_as_paid_in_full.sql
\set ON_ERROR_STOP on
rollback to savepoint t476_9;
select set_config('t476.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t476_check(current_setting('t476.msg') like '476: what adds invoice lines or writes invoice revisions is not as read on 27 Oct 2026 (% / %t476_probe_rev(uuid)%'
      and not pg_temp.t476_in(), '9j2 refused with: ' || current_setting('t476.msg'));
end $$;
savepoint t476_9;
create policy t476_probe_policy on public.invoice_revisions for insert to authenticated with check (true);
\set ON_ERROR_STOP off
\ir ../../../supabase/476_part_paid_change_same_as_paid_in_full.sql
\set ON_ERROR_STOP on
rollback to savepoint t476_9;
select set_config('t476.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t476_check(current_setting('t476.msg') = '476: invoice revisions can be written by a page, not as read on 27 Oct 2026'
      and not pg_temp.t476_in(), '9j3 refused with: ' || current_setting('t476.msg'));
end $$;
-- 9i The same grants in another order: installs (compared as sets).
savepoint t476_9;
revoke execute on function public.invoice_transferable_benefits(uuid) from authenticated;
grant execute on function public.invoice_transferable_benefits(uuid) to authenticated;
revoke execute on function public.release_credit_package_paid_credit(uuid) from postgres;
grant execute on function public.release_credit_package_paid_credit(uuid) to postgres;
\ir ../../../supabase/476_part_paid_change_same_as_paid_in_full.sql
do $$ begin
  perform pg_temp.t476_check(pg_temp.t476_in() and pg_temp.t476_at('after'), '9i the same grants in another order stopped it');
end $$;
rollback to savepoint t476_9;
do $$ begin
  perform pg_temp.t476_check(pg_temp.t476_fingerprint() = (select v from t476_fp where k = 'start') and not pg_temp.t476_in()
      and pg_temp.t476_grant_sets(array['credit_line_sale_group', 'credit_line_benefits_holder', 'invoice_credit_receivers']) = (select v from t476_fp where k = 'grants'),
    '9 the refusals left a change');
  raise notice 'PASS 9: refused, changing nothing: a function it changes not as tested (the bundle seller, the mover), one partly in, a function it relies on not as tested (the settlement, 475''s reopening, the line writer), an overload of a name it changes or adds, a new caller of the release, the mover or update_invoice_internal, a new grant of credit, a new writer of the release record, the trigger on invoices changed, a new way to add lines or write revisions, a page allowed to write revisions. The same grants in another order do not stop it';
end $$;

-- ===== M. Begun before 476, finished after it (the mid set) =====
-- TQn2's state, K1's and K2's change and TK's reached before 476, the rest
-- after it: each ends as the whole case does after 476 (so do X1's and X2's,
-- KAL's, a line added before 476, TQfix's corrected payment and CK1's
-- referrers and change). And two cases split before 476: MK1p (a 'keep'
-- change and a part payment before 476: A S$40, B S$20; the rest after: no
-- one holds its benefits, so the invoice's customer, NOT COVERED 3: B S$40
-- more), MTQn2 (the 'transfer' change passed before 476: B, the benefits'
-- holder now, gets the rest, as before).
create temp table t476_mid(k text primary key, ord serial, split int, steps text, expect jsonb);
insert into t476_mid(k, split, steps, expect) select 'm' || k, s, steps, expect from (values
  ('TQn2', 3), ('K1', 2), ('K2', 4), ('TK', 3), ('Kw', 5), ('K1n2', 4), ('X1', 2), ('X2', 3), ('KAL', 3), ('TQfix', 2), ('CK1', 3)) x(k, s)
  join t476_cases c using (k);
insert into t476_mid(k, split, steps, expect) values
  ('MK1p', 3, 'sale A cp 40; change B keep; payp 20; pay',
    '{"holds":{"A":"40.00","B":"60.00"},"status":"paid","customer":"B","error":null}'),
  ('MTQn2', 4, 'sale A cp 40; spend A; spend A; change B; pay',
    '{"holds":{"A":"0.00","B":"60.00"},"status":"paid","customer":"B","blocked":"Paid credit 60.00 (Partly spent)","error":null}');
do $$ declare c record; begin
  for c in select * from t476_mid order by ord loop
    perform pg_temp.t476_run('mid', c.k, c.steps, 1, c.split);
  end loop;
end $$;
\endif

-- ===== 10. Install 476, twice =====
\if :{?nomig}
do $$ begin raise notice 'NOTE 10: -v nomig=1, so 476 is not installed here (R, Q, 9 and M are skipped)'; end $$;
\else
\ir ../../../supabase/476_part_paid_change_same_as_paid_in_full.sql
do $$ begin insert into t476_fp values ('first', pg_temp.t476_fingerprint()); end $$;
\ir ../../../supabase/476_part_paid_change_same_as_paid_in_full.sql
do $$ begin insert into t476_fp values ('second', pg_temp.t476_fingerprint()); end $$;
\endif
do $$
begin
  perform pg_temp.t476_check(pg_temp.t476_in() and pg_temp.t476_at('after'), '10 476 is not installed as tested');
  perform pg_temp.t476_check((select count(*) from pg_proc where pronamespace = 'public'::regnamespace
                               and proname in ('invoice_transferable_benefits', 'move_invoice_benefits_to_customer', 'release_credit_package_paid_credit',
                                               'issue_credit_package', 'sell_premium_bundle', 'invoice_package_commission_preview',
                                               'credit_line_sale_group', 'credit_line_benefits_holder', 'invoice_credit_receivers')) = 9, '10 an overload exists');
  perform pg_temp.t476_check(pg_temp.t476_inv_triggers() = (select v from t476_fp where k = 'triggers'),
    '10 a trigger on invoices was added or changed: ' || pg_temp.t476_inv_triggers());
  perform pg_temp.t476_check(pg_temp.t476_grant_set('invoice_transferable_benefits(uuid)') = '{authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres}'
      and pg_temp.t476_grant_set('move_invoice_benefits_to_customer(uuid,uuid,uuid,text)') = '{postgres=X/postgres,service_role=X/postgres}'
      and pg_temp.t476_grant_set('release_credit_package_paid_credit(uuid)') = '{postgres=X/postgres,service_role=X/postgres}'
      and pg_temp.t476_grant_set('issue_credit_package(uuid,uuid,uuid,numeric,uuid,uuid)') = '{postgres=X/postgres,service_role=X/postgres}'
      and pg_temp.t476_grant_set('sell_premium_bundle(uuid,uuid,uuid,jsonb,jsonb,numeric,numeric,uuid,boolean,uuid)') = '{postgres=X/postgres,service_role=X/postgres}'
      and pg_temp.t476_grant_set('invoice_package_commission_preview(uuid)') = '{postgres=X/postgres,service_role=X/postgres}'
      and pg_temp.t476_grant_set('credit_line_sale_group(uuid)') = '{postgres=X/postgres,service_role=X/postgres}'
      and pg_temp.t476_grant_set('credit_line_benefits_holder(uuid)') = '{postgres=X/postgres,service_role=X/postgres}'
      and pg_temp.t476_grant_set('invoice_credit_receivers(uuid)') = '{authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres}'
      and not has_function_privilege('anon', 'public.credit_line_sale_group(uuid)', 'execute')
      and not has_function_privilege('authenticated', 'public.credit_line_sale_group(uuid)', 'execute')
      and not has_function_privilege('anon', 'public.credit_line_benefits_holder(uuid)', 'execute')
      and not has_function_privilege('authenticated', 'public.credit_line_benefits_holder(uuid)', 'execute')
      and not has_function_privilege('anon', 'public.invoice_credit_receivers(uuid)', 'execute')
      and has_function_privilege('authenticated', 'public.invoice_credit_receivers(uuid)', 'execute')
      and not has_function_privilege('anon', 'public.invoice_transferable_benefits(uuid)', 'execute'),
    '10 who may call them is not as before (the list and the Pay dialog''s read: active staff through authenticated; the rest and the two new helpers: the server''s alone)');
  if exists (select 1 from t476_fp where k = 'first') then
    perform pg_temp.t476_check((select v from t476_fp where k = 'second') = (select v from t476_fp where k = 'first'),
      '10 the second run of 476 changed functions');
    perform pg_temp.t476_check(split_part((select v from t476_fp where k = 'first'), ' ', 2)::int
                               = split_part((select v from t476_fp where k = 'start'), ' ', 2)::int + 3,
      '10 476 did not add exactly three functions');
    perform pg_temp.t476_check(pg_temp.t476_grant_sets(array['credit_line_sale_group', 'credit_line_benefits_holder', 'invoice_credit_receivers']) = (select v from t476_fp where k = 'grants'),
      '10 the grants of the other functions changed');
  end if;
  raise notice 'PASS 10: 476 installed as tested (%); the six at their AFTER, their grants as before; credit_line_sale_group and credit_line_benefits_holder added, the server''s alone; invoice_credit_receivers added, signed-in staff''s and the server''s; no trigger added or changed; %',
    pg_temp.t476_fingerprint(),
    coalesce((select 'the second run changed nothing, the other grants as before' from t476_fp where k = 'first'), 'it was in before the suite (nomig)');
end $$;

-- ===== A. Each case after 476 =====
do $$
declare c record; o jsonb; b jsonb; res text := '';
begin
  for c in select * from t476_cases order by ord loop
    o := pg_temp.t476_run('after', c.k, c.steps);
    perform pg_temp.t476_check(pg_temp.t476_meets(o, c.expect),
      'A ' || c.k || ': ' || coalesce(pg_temp.t476_diff(o, c.expect), '') || ' ' || o::text);
    perform pg_temp.t476_check(coalesce(o->>'invariants', '') = '', 'A ' || c.k || ' invariants: ' || (o->>'invariants'));
    perform pg_temp.t476_check(coalesce((o->>'cancel_left')::numeric, 0) = 0,
      'A ' || c.k || ': Cancel leaves S$' || (o->>'cancel_left') || ' of the invoice''s credit behind');
    b := (select v from t476_res where phase = 'before' and k = c.k);
    -- (a refusal's text names its invoice, numbered differently in each run)
    if c.kind in ('control', 'known') and b is not null then
      perform pg_temp.t476_check(o - 'error' = b - 'error'
          and regexp_replace(coalesce(o->>'error', ''), 'INV-[0-9-]+', 'INV', 'g') = regexp_replace(coalesce(b->>'error', ''), 'INV-[0-9-]+', 'INV', 'g'),
        'A ' || c.kind || ' ' || c.k || ' changed with 476: before ' || b::text || ', after ' || o::text);
    end if;
    res := res || format(E'\n  %s %s: %s; customer %s; blocked %s; sale %s; comm %s%s', c.kind, c.k,
      (select string_agg(h.key || ' ' || (h.value #>> '{}'), ', ' order by h.key) from jsonb_each(o->'holds') h),
      o->>'customer', o->>'blocked', o->>'sale', o->>'comm', coalesce('; refused: ' || left(o->>'error', 60), ''));
  end loop;
  raise notice 'PASS A: after 476 each case ends by the Owner''s rule (a ''transfer'' change refused once any of it was used and moving it when nothing was; after a ''keep'' change all it gives later goes to whoever holds its benefits, with the lines sold with it, a line a correction added to the invoice''s customer who pays for it), the invariants hold in every case and Cancel takes all of it back; the controls and the known cases are exactly as before 476%:%',
    case when exists (select 1 from t476_res where phase = 'before') then '' else ' (no before figures: -v nomig=1)' end, res;
end $$;

-- ===== M (after). The mid set finished with 476 in =====
\if :{?nomig}
\else
do $$
declare c record; o jsonb; res text := '';
begin
  for c in select * from t476_mid order by ord loop
    o := pg_temp.t476_run('mid', c.k, c.steps, c.split + 1);
    perform pg_temp.t476_check(pg_temp.t476_meets(o, c.expect) and coalesce(o->>'invariants', '') = ''
        and coalesce((o->>'cancel_left')::numeric, 0) = 0,
      'M ' || c.k || ': ' || coalesce(pg_temp.t476_diff(o, c.expect), '') || ' ' || o::text);
    res := res || ' ' || c.k;
  end loop;
  raise notice 'PASS M: begun before 476 and finished after it, each ends as the whole case does after 476; split before 476, MK1p''s rest goes to the invoice''s customer (B S$60 in all, NOT COVERED 3) and MTQn2''s to B, the benefits'' holder (as before):%', res;
end $$;
\endif

-- ===== P. Probes =====
do $$
declare inv uuid; invc uuid; rows_ text; m jsonb; mc jsonb; v_err text; rec uuid; a uuid; b uuid; s text; n int;
begin
  -- P1 TQn2 (refused, partly paid): the list's credit rows are what 473's TQ
  -- (the same package paid in part, settled) lists: the released lot spent
  -- in full "Fully spent" (not blocking), and "Paid credit 60.00" "Partly
  -- spent", blocking, not movable; here the S$60 is the credit still to be
  -- released, its record_id the package line. The review summary for a
  -- change to B with 'transfer' has the same blocked items, words and
  -- detail as the package paid in full's (TQc), and nothing moving.
  inv := pg_temp.t476_id('after/TQn2/inv'); invc := pg_temp.t476_id('after/TQc/inv');
  select string_agg(x.description || ':' || x.movable || ':' || x.blocking || ':' || coalesce(x.blocked_reason, '-'), ', ' order by x.units, x.description)
    into rows_ from invoice_transferable_benefits(inv) x where x.kind = 'credit';
  perform pg_temp.t476_check(rows_ = 'Paid credit 0.00:false:false:Fully spent; it stays with the original customer, Paid credit 60.00:false:true:Partly spent',
    'P1 TQn2: the list reads ' || coalesce(rows_, '(nothing)'));
  select x.record_id into rec from invoice_transferable_benefits(inv) x where x.kind = 'credit' and x.blocking;
  perform pg_temp.t476_check(rec = pg_temp.t476_line(inv, 1) and not exists (select 1 from customer_credit_lots where id = rec),
    'P1 TQn2: the blocking row''s record_id is not the package line');
  m := preview_invoice_correction(inv, jsonb_build_object('customer_id', pg_temp.t476_cust('P/TQn2/B'),
         'store_id', pg_temp.t476_id('store'), 'benefit_action', 'transfer'));
  mc := preview_invoice_correction(invc, jsonb_build_object('customer_id', pg_temp.t476_cust('P/TQc/B'),
         'store_id', pg_temp.t476_id('store'), 'benefit_action', 'transfer'));
  perform pg_temp.t476_check(
        (select jsonb_agg(r) from jsonb_array_elements(m->'needs_review') r where r->>'area' = 'benefits')
        = '[{"area": "benefits", "items": [{"why": "Partly spent", "kind": "credit", "what": "Paid credit 60.00"}], "detail": "These have already been used and will not move. The correction is refused until each is resolved through the benefit transfer review."}]'::jsonb
    and not exists (select 1 from jsonb_array_elements(m->'effects') e where e->>'area' = 'benefits' and e->>'change' = 'transferring')
    and (select jsonb_agg(r) from jsonb_array_elements(m->'needs_review') r where r->>'area' = 'benefits')
        = (select jsonb_agg(r) from jsonb_array_elements(mc->'needs_review') r where r->>'area' = 'benefits'),
    'P1 TQn2: the review summary is not the paid-in-full package''s: ' || coalesce((m->'needs_review')::text, 'null') || ' / ' || coalesce((mc->'needs_review')::text, 'null'));
  -- P2 the 'keep' the refusal leaves: its summary says the benefits stay
  -- (nothing blocked), and it goes through (K1n2 is that case to the end).
  m := preview_invoice_correction(inv, jsonb_build_object('customer_id', pg_temp.t476_id('P/TQn2/B'),
         'store_id', pg_temp.t476_id('store'), 'benefit_action', 'keep'));
  perform pg_temp.t476_check(exists (select 1 from jsonb_array_elements(m->'effects') e where e->>'area' = 'benefits' and e->>'change' = 'kept')
      and not exists (select 1 from jsonb_array_elements(coalesce(m->'needs_review', '[]')) r where r->>'area' = 'benefits'),
    'P2 TQn2: ''keep'' is not offered as it was: ' || m::text);
  -- P3 The form still asks 'transfer' or 'keep' for TQn2's state (the list
  -- has rows): neither is refused with BENEFIT_ACTION_REQUIRED.
  begin
    perform correct_invoice(inv, pg_temp.t476_lines(inv),
      jsonb_build_object('expected_edit_count', (select edit_count from invoices where id = inv),
        'customer_id', pg_temp.t476_cust('P/TQn2/C'), 'store_id', (select store_id from invoices where id = inv)),
      'T476 wrong customer', gen_random_uuid());
    v_err := null;
  exception when others then v_err := sqlerrm;
  end;
  perform pg_temp.t476_check(v_err like 'BENEFIT_ACTION_REQUIRED:%', 'P3 TQn2: the form is not asked to choose: ' || coalesce(v_err, 'no refusal'));
  -- P4 K1: the release lot and the settlement's lot are A's and the benefit
  -- rows name them; the sale record is A's too (answer B), its credit lot
  -- A's; K1v's vouchers A's, and the voucher allowance none (both chosen).
  inv := pg_temp.t476_id('after/K1/inv'); a := pg_temp.t476_id('after/K1/A'); b := pg_temp.t476_id('after/K1/B');
  perform pg_temp.t476_check(
        (select count(*) from invoice_benefit_values bv join customer_credit_lots l on l.id = bv.lot_id
          where bv.invoice_id = inv and l.customer_id = a) = 2
    and not exists (select 1 from invoice_benefit_values bv join customer_credit_lots l on l.id = bv.lot_id
                     where bv.invoice_id = inv and l.customer_id <> a)
    and (select customer_id from credit_package_sales where invoice_id = inv) = a
    and (select l.customer_id from credit_package_sales s join customer_credit_lots l on l.id = s.credit_lot_id where s.invoice_id = inv) = a
    and (select l.customer_id from credit_package_progress_lots pl join customer_credit_lots l on l.id = pl.lot_id where pl.invoice_id = inv) = a,
    'P4 K1: the lots, benefit rows or sale record are not as 476 makes them');
  inv := pg_temp.t476_id('after/K1v/inv');
  perform pg_temp.t476_check(
        (select customer_id from premium_bundle_sales where invoice_id = inv) = pg_temp.t476_id('after/K1v/A')
    and (select coalesce(sum(quantity), 0) from customer_reward_vouchers where source_id = (select id from premium_bundle_sales where invoice_id = inv)
          and customer_id = pg_temp.t476_id('after/K1v/A')) = 2
    and not exists (select 1 from therapy_entitlements e where e.claim_source_invoice_id = inv and e.customer_id <> pg_temp.t476_id('after/K1v/A')),
    'P4 K1v: the bundle''s sale record, vouchers or allowance are not the buyer''s');
  -- P5 Whom the helper names: K1 before its payment (A), KT ('keep' then
  -- 'transfer': C), TK ('transfer' then 'keep': B), K1m (merged into K), a
  -- package with nothing released (none), MK1p (split before 476: none).
  perform pg_temp.t476_check(pg_temp.t476_holder(pg_temp.t476_id('after/K1/inv')) = pg_temp.t476_id('after/K1/A')
      and pg_temp.t476_holder(pg_temp.t476_id('after/KT/inv')) = pg_temp.t476_id('after/KT/C')
      and pg_temp.t476_holder(pg_temp.t476_id('after/TK/inv')) = pg_temp.t476_id('after/TK/B')
      and pg_temp.t476_holder(pg_temp.t476_id('after/K1m/inv')) = pg_temp.t476_id('after/K1m/K'),
    'P5 the helper does not name the benefits'' holder');
  -- (made once: called in a WHERE clause it ran once per invoice scanned)
  inv := create_invoice_with_details(pg_temp.t476_id('store'), pg_temp.t476_cust('P/none/A'),
           jsonb_build_array(jsonb_build_object('kind', 'credit_package', 'credit_package_id', pg_temp.t476_id('cp'), 'quantity', 1)),
           jsonb_build_object('business_date', sg_today()::text));
  perform pg_temp.t476_check(pg_temp.t476_holder(inv) is null, 'P5 the helper names someone for a package that released nothing');
  if exists (select 1 from t476_res where phase = 'mid' and k = 'MK1p') then
    perform pg_temp.t476_check(pg_temp.t476_holder(pg_temp.t476_id('mid/MK1p/inv')) is null, 'P5 the helper names one holder for MK1p, split before 476');
  end if;
  -- the second line of X1 and X2, which released nothing before full
  -- payment (no release record of its own): the holder of the first line's
  -- releases (A; after 'transfer' then 'keep', B); a line of an invoice none
  -- of whose lines released anything: none.
  perform pg_temp.t476_check(
        not exists (select 1 from credit_package_progress_lots pl where pl.invoice_item_id = pg_temp.t476_line(pg_temp.t476_id('after/X1/inv'), 2))
          and credit_line_benefits_holder(pg_temp.t476_line(pg_temp.t476_id('after/X1/inv'), 2)) = pg_temp.t476_id('after/X1/A')
        or not exists (select 1 from credit_package_progress_lots pl where pl.invoice_item_id = pg_temp.t476_line(pg_temp.t476_id('after/X1/inv'), 1))
          and credit_line_benefits_holder(pg_temp.t476_line(pg_temp.t476_id('after/X1/inv'), 1)) = pg_temp.t476_id('after/X1/A'),
    'P5 the helper does not name the first line''s holder for X1''s line that released nothing');
  perform pg_temp.t476_check(
        (select count(distinct credit_line_benefits_holder(it.id)) from invoice_items it where it.invoice_id = pg_temp.t476_id('after/X2/inv')) = 1
    and (select credit_line_benefits_holder(it.id) from invoice_items it where it.invoice_id = pg_temp.t476_id('after/X2/inv') limit 1) = pg_temp.t476_id('after/X2/B'),
    'P5 the helper does not name B for both of X2''s lines');
  inv := create_invoice_with_details(pg_temp.t476_id('store'), pg_temp.t476_cust('P/none2/A'),
           jsonb_build_array(jsonb_build_object('kind', 'credit_package', 'credit_package_id', pg_temp.t476_id('cp'), 'quantity', 1),
                             jsonb_build_object('kind', 'credit_package', 'credit_package_id', pg_temp.t476_id('cp'), 'quantity', 1)),
           jsonb_build_object('business_date', sg_today()::text));
  perform pg_temp.t476_check(credit_line_benefits_holder(pg_temp.t476_line(inv, 1)) is null and credit_line_benefits_holder(pg_temp.t476_line(inv, 2)) is null,
    'P5 the helper names someone for an invoice none of whose lines released anything');
  -- P6 (answer A) the sale groups: lines the invoice was made with, and one
  -- an edit added before any money, 0 (X1, KAE); one a correction added once
  -- money was received, that correction's revision (KAL: 0, n); two one
  -- correction added, the same (KAT2); two corrections, two (KAT3).
  perform pg_temp.t476_check(pg_temp.t476_groups(pg_temp.t476_id('after/X1/inv')) = '0,0'
      and pg_temp.t476_groups(pg_temp.t476_id('after/KAE/inv')) = '0,0',
    'P6 X1 and KAE are not one sale: ' || pg_temp.t476_groups(pg_temp.t476_id('after/X1/inv')) || ' / ' || pg_temp.t476_groups(pg_temp.t476_id('after/KAE/inv')));
  inv := pg_temp.t476_id('after/KAL/inv');
  perform pg_temp.t476_check(
        credit_line_sale_group((select it.id from invoice_items it where it.invoice_id = inv and it.id in (select pl.invoice_item_id from credit_package_progress_lots pl))) = 0
    and credit_line_sale_group((select it.id from invoice_items it where it.invoice_id = inv and it.id not in (select pl.invoice_item_id from credit_package_progress_lots pl)))
        = (select max(r.revision_no) from invoice_revisions r where r.invoice_id = inv and r.edit_reason = 'T476 add a line'),
    'P6 KAL: the added line is not the correction''s sale: ' || pg_temp.t476_groups(inv));
  inv := pg_temp.t476_id('after/KAT2/inv');
  select count(distinct credit_line_sale_group(it.id)) into n
    from invoice_items it where it.invoice_id = inv and credit_line_sale_group(it.id) > 0;
  perform pg_temp.t476_check(n = 1, 'P6 KAT2: the two lines one correction added are not one sale: ' || pg_temp.t476_groups(inv));
  inv := pg_temp.t476_id('after/KAT3/inv');
  perform pg_temp.t476_check((select count(distinct credit_line_sale_group(it.id)) from invoice_items it where it.invoice_id = inv) = 3,
    'P6 KAT3: two corrections are not two sales: ' || pg_temp.t476_groups(inv));
  -- P7 (answer E) the Pay dialog's read: after a 'keep' change before full
  -- payment, each line whose credit goes to the buyer names the buyer (K1:
  -- A; X1: A for both); a line a correction added is the invoice's
  -- customer's, not listed (KAL: the first line, A); a 'transfer' change, or
  -- nothing changed: nothing listed; a settled invoice: nothing.
  perform pg_temp.t476_run('P7', 'K1', 'sale A cp 40; change B keep');
  perform pg_temp.t476_run('P7', 'X1', 'sale A cp,cp 40; change B keep');
  perform pg_temp.t476_run('P7', 'KAL', 'sale A cp 40; change B keep; addline cp');
  perform pg_temp.t476_run('P7', 'TQ00', 'sale A cp 40; change B');
  perform pg_temp.t476_run('P7', 'F', 'sale A cp 40');
  perform pg_temp.t476_check(pg_temp.t476_recv('P7/K1') = 'A' and pg_temp.t476_recv('P7/X1') = 'A,A' and pg_temp.t476_recv('P7/KAL') = 'A'
      and pg_temp.t476_recv('P7/TQ00') = '-' and pg_temp.t476_recv('P7/F') = '-' and pg_temp.t476_recv('after/K1') = '-',
    'P7 the Pay dialog''s read: K1 ' || pg_temp.t476_recv('P7/K1') || ', X1 ' || pg_temp.t476_recv('P7/X1') || ', KAL ' || pg_temp.t476_recv('P7/KAL')
      || ', TQ00 ' || pg_temp.t476_recv('P7/TQ00') || ', F ' || pg_temp.t476_recv('P7/F') || ', K1 settled ' || pg_temp.t476_recv('after/K1'));
  perform pg_temp.t476_check((invoice_credit_receivers(pg_temp.t476_id('P7/K1/inv'))->>'customer_id')::uuid = pg_temp.t476_id('P7/K1/B'),
    'P7 the Pay dialog''s read does not give the invoice''s customer');
  raise notice 'PASS P: TQn2''s list ("Fully spent", then the S$60 still to be released "Partly spent", its record_id the line) and its review summary the same as the package paid in full''s; ''keep'' still offered and the form still asked; K1''s lots, benefit rows and sale record A''s; K1v''s sale record, vouchers and allowance A''s; the helper names the benefits'' holder (for a line that released nothing, the holder of the lines of its sale: X1 A, X2 B; none with nothing released on the invoice, or split before 476); the sale groups (X1 and KAE one sale, KAL''s added line its correction''s, KAT2''s two lines one sale, KAT3''s two); the Pay dialog''s read names the buyer for K1 and X1, the first line of KAL alone, nothing for a ''transfer'' change, an unchanged or a settled invoice';
end $$;
-- P7b (answer E; staff are told what the payment will give): on a reopened
-- invoice the Pay dialog's read names who receives the credit the payment
-- that settles it gives back, and that payment gives it to them: after a
-- 'keep' change, the buyer (A S$100, with S$20 to pay); after a merge since,
-- the record it kept (K); nothing where that is the invoice's customer (no
-- change; a 'transfer' change).
create function pg_temp.t476_recv_back(p_pre text) returns text language plpgsql as $f$
declare r jsonb;
begin
  r := invoice_credit_receivers(pg_temp.t476_id(p_pre || '/inv'));
  return coalesce((select string_agg(coalesce((select split_part(t.k, '/', 3) from t476 t
                                                where t.id = (x->>'customer_id')::uuid and t.k like p_pre || '/%' limit 1), '?')
                                     || case when (x->>'customer_name') = (select full_name from customers where id = (x->>'customer_id')::uuid)
                                             then '' else '(name?)' end || ' ' || (x->>'amount'), ',' order by x->>'customer_id')
                     from jsonb_array_elements(r->'reinstated') x), '-');
end $f$;
do $$
declare o jsonb; c record;
begin
  for c in select * from (values
      ('K', 'sale A cp; change B keep; cancel; back 1 20; reopen; pay', 5, 'A 100.00', '{"A":"100.00","B":"0.00"}'),
      ('M', 'sale A cp; change B keep; cancel; back 1 20; reopen; merge K A; pay', 6, 'K 100.00', '{"A":"0.00","B":"0.00","K":"100.00"}'),
      ('N', 'sale A cp; cancel; back 1 20; reopen; pay', 4, '-', '{"A":"100.00"}'),
      ('T', 'sale A cp; change B; cancel; back 1 20; reopen; pay', 5, '-', '{"A":"0.00","B":"100.00"}')) x(k, steps, upto, recv, holds) loop
    perform pg_temp.t476_run('P7b', c.k, c.steps, 1, c.upto);
    perform pg_temp.t476_check((select err from t476_err where pre = 'P7b/' || c.k) is null
        and (select status::text from invoices where id = pg_temp.t476_id('P7b/' || c.k || '/inv')) = 'partially_paid'
        and pg_temp.t476_recv_back('P7b/' || c.k) = c.recv and pg_temp.t476_recv('P7b/' || c.k) = '-',
      'P7b ' || c.k || ': the Pay dialog''s read of the credit given back is ' || pg_temp.t476_recv_back('P7b/' || c.k) || ' (wanted ' || c.recv || ')');
    o := pg_temp.t476_run('P7b', c.k, c.steps, c.upto + 1);
    perform pg_temp.t476_check(o->>'status' = 'paid' and o->'holds' @> c.holds::jsonb and coalesce(o->>'invariants', '') = ''
        and pg_temp.t476_recv_back('P7b/' || c.k) = '-',
      'P7b ' || c.k || ': the settling payment did not give what the read said: ' || o::text);
  end loop;
  raise notice 'PASS P7b: on a reopened invoice the Pay dialog''s read names who receives the credit the settling payment gives back, and the payment gives it to them (''keep'': the buyer A S$100; merged since: K S$100); nothing when that is the invoice''s customer (no change, ''transfer'')';
end $$;
-- P8 (answer E) the Pay dialog's read refuses anyone but active staff of
-- the invoice's store (406's require_store_access, as the list does): a
-- login with no profile, and staff of another store; staff of the store
-- reads it.
do $$
declare own text := current_setting('request.jwt.claim.sub'); inv uuid := pg_temp.t476_id('P7/K1/inv'); u uuid; e text; r jsonb;
begin
  u := gen_random_uuid();
  insert into auth.users(id, email) values (u, 't476-nobody@example.com');
  perform set_config('request.jwt.claim.sub', u::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', u, 'role', 'authenticated')::text, true);
  begin r := invoice_credit_receivers(inv); e := null; exception when others then e := sqlstate; end;
  perform pg_temp.t476_check(e = '42501', 'P8 a login with no profile was not refused (' || coalesce(e, 'answered') || ')');
  u := gen_random_uuid();
  insert into auth.users(id, email) values (u, 't476-staff2@example.com');
  insert into profiles(id, full_name, email, role, is_active) values (u, 'T476 Staff other store', 't476-staff2@example.com', 'staff', true);
  insert into user_store_assignments(user_id, store_id) values (u, pg_temp.t476_id('store2'));
  perform set_config('request.jwt.claim.sub', u::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', u, 'role', 'authenticated')::text, true);
  begin r := invoice_credit_receivers(inv); e := null; exception when others then e := sqlstate; end;
  perform pg_temp.t476_check(e = '42501', 'P8 staff of another store was not refused (' || coalesce(e, 'answered') || ')');
  delete from user_store_assignments where user_id = u;
  insert into user_store_assignments(user_id, store_id) values (u, pg_temp.t476_id('store'));
  begin r := invoice_credit_receivers(inv); e := null; exception when others then e := sqlerrm; end;
  perform pg_temp.t476_check(e is null and jsonb_array_length(r->'lines') = 1, 'P8 staff of the store could not read it (' || coalesce(e, r::text) || ')');
  perform set_config('request.jwt.claim.sub', own, true);
  perform set_config('request.jwt.claims', json_build_object('sub', own, 'role', 'authenticated')::text, true);
  raise notice 'PASS P8: the Pay dialog''s read refuses a login with no profile and staff of another store (42501), and answers staff of the store';
end $$;

-- ===== K. KNOWN: 476's NOT COVERED (each checked as it is) =====
do $$
declare inv uuid; lot uuid; e text; ben uuid; f uuid; v_msg text;
begin
  -- K1 (NOT COVERED 1c): two corrections, each once money was received, are
  -- two sales: the line that released nothing goes to the invoice's customer
  -- (KAT3: A S$200, B S$100), where paid in full after both: A S$300 (KAT3F).
  perform pg_temp.t476_check((select v->'holds' from t476_res where phase = 'after' and k = 'KAT3') @> '{"A":"200.00","B":"100.00"}'
      and (select v->'holds' from t476_res where phase = 'after' and k = 'KAT3F') @> '{"A":"300.00","B":"0.00"}',
    'K1 KAT3, KAT3F: look at NOT COVERED 1 again');
  -- K2 (NOT COVERED 2): with 'transfer' before full payment the sale record
  -- is the new customer's and their referrer earns (CKT); paid in full and
  -- then 'transfer', the buyer's (CKTF).
  perform pg_temp.t476_check((select v->>'sale' from t476_res where phase = 'after' and k = 'CKT') = 'B'
      and (select v->>'comm' from t476_res where phase = 'after' and k = 'CKT') = 'RB 4.50'
      and (select v->>'sale' from t476_res where phase = 'after' and k = 'CKTF') = 'A'
      and (select v->>'comm' from t476_res where phase = 'after' and k = 'CKTF') = 'RA 4.50',
    'K2 CKT, CKTF: look at NOT COVERED 2 again');
  -- K3 (NOT COVERED 3): split before 476 (MK1p): no one holds its
  -- benefits, so all it gives later goes to the invoice's customer.
  if exists (select 1 from t476_res where phase = 'mid' and k = 'MK1p') then
    perform pg_temp.t476_check((select v->'holds' from t476_res where phase = 'mid' and k = 'MK1p') @> '{"A":"40.00","B":"60.00"}',
      'K3 MK1p: look at NOT COVERED 3 again');
  end if;
  -- K4 (NOT COVERED 4): the buyer deleted: the invoice's customer (Kdel: B
  -- S$60), before 476 and after.
  perform pg_temp.t476_check((select v->'holds' from t476_res where phase = 'after' and k = 'Kdel') @> '{"A":"0.00","B":"60.00"}',
    'K4 Kdel: look at NOT COVERED 4 again');
  -- K9 (NOT COVERED 9): TQcru's lot Cancel locked moved to B still locked;
  -- B can spend it; an Owner's Move of it is refused ("locked or reversed").
  inv := pg_temp.t476_id('after/TQcru/inv');
  select l.id into lot from customer_credit_lots l
   where l.customer_id = pg_temp.t476_id('after/TQcru/B') and l.is_locked and l.remaining_amount > 0;
  perform pg_temp.t476_check(lot is not null and (select remaining_amount from customer_credit_lots where id = lot) = 20,
    'K9 TQcru: the lot Cancel locked did not move to B locked');
  -- And once paid (TQcrup) an Owner's Move of that lot of B's to F (tried,
  -- undone): refused, "This credit lot is locked or reversed"; where 477 is
  -- in (special-refund-move-repaired-lot-477.sql, the Owner's answer D: a
  -- lot only Cancel's write-off locked may be moved), F gets its S$20.
  inv := pg_temp.t476_id('after/TQcrup/inv');
  select bv.id into ben from invoice_benefit_values bv join customer_credit_lots l on l.id = bv.lot_id
   where bv.invoice_id = inv and l.customer_id = pg_temp.t476_id('after/TQcrup/B') and l.is_locked and l.remaining_amount > 0;
  f := pg_temp.t476_cust('K/TQcrup/F');
  begin
    begin
      perform transfer_invoice_unused_benefit(ben, f, (select store_id from invoices where id = inv), 'T476 move', gen_random_uuid());
      e := null;
    exception when others then e := sqlerrm;
    end;
    raise exception using errcode = 'P0476', message = coalesce(e, 'moved') || '|'
      || (select coalesce(sum(remaining_amount), 0) from customer_credit_lots where customer_id = f);
  exception when sqlstate 'P0476' then v_msg := sqlerrm;
  end;
  if position('answer D, 477''s NOT COVERED 1' in pg_get_functiondef('public.transfer_invoice_unused_benefit(uuid,uuid,uuid,text,uuid)'::regprocedure)) > 0 then
    perform pg_temp.t476_check(ben is not null and v_msg = 'moved|20.00',
      'K9 TQcrup (477 in): the Move of B''s lot Cancel''s write-off locked was not made: ' || coalesce(v_msg, 'no lot'));
  else
    perform pg_temp.t476_check(ben is not null and v_msg = 'This credit lot is locked or reversed|0',
      'K9 TQcrup: the Move of B''s lot Cancel''s write-off locked was not refused: ' || coalesce(v_msg, 'no lot'));
  end if;
  -- K7 (NOT COVERED 7): changed with 'keep', settled, then part-paid
  -- again (the part-payment layer registered): the credit, the vouchers and
  -- the sale record stay the buyer's, while the layer gives the line's
  -- commission to the invoice's customer's referrer (RB) until it is paid in
  -- full again; the same as the package paid in full and then changed
  -- (G5F, C3cF: controls, the same before 476).
  perform pg_temp.t476_check((select v->>'comm' from t476_res where phase = 'after' and k = 'G5') = 'RB 4.50'
      and (select v->>'sale' from t476_res where phase = 'after' and k = 'G5') = 'A'
      and (select v->>'comm' from t476_res where phase = 'after' and k = 'C3c') = 'RB 4.28'
      and (select v->>'comm' from t476_res where phase = 'after' and k = 'C5') = 'RB 8.78'
      and (select v->>'comm' from t476_res where phase = 'after' and k = 'L4') = 'RB 6.08'
      and (select v->>'comm' from t476_res where phase = 'after' and k = 'G5p') = 'RA 4.50, RB 4.50'
      and (select v->>'comm' from t476_res where phase = 'after' and k = 'C3cp') = 'RA 4.50'
      and (select v->>'comm' from t476_res where phase = 'after' and k = 'G5F') = 'RB 4.50'
      and (select v->>'comm' from t476_res where phase = 'after' and k = 'C3cF') = 'RB 4.28',
    'K7 G5, C3c, C5, L4, G5p, C3cp, G5F, C3cF: look at NOT COVERED 7 again');
  -- (before 476, where R ran: the same steps paid the invoice's customer's
  -- referrer throughout, the sale record theirs)
  if exists (select 1 from t476_res where phase = 'before' and k = 'G5') then
    perform pg_temp.t476_check((select v->>'sale' from t476_res where phase = 'before' and k = 'G5') = 'B'
        and (select v->>'comm' from t476_res where phase = 'before' and k = 'G5') = 'RB 4.50'
        and (select v->>'comm' from t476_res where phase = 'before' and k = 'C3cp') = 'RB 4.50',
      'K7 before 476: G5''s sale record and commission, C3cp''s commission, are not the invoice''s customer''s');
  end if;
  -- And a payout in that window (P1): RB is paid the S$4.28 the layer gave
  -- them; paid in full again, RA is owed the settlement's S$4.50 and RB owes
  -- the S$4.28 back (a deduction from their later commission, 357, 410).
  perform pg_temp.t476_run('K', 'P1', 'refs; layer; sale A cp 40; change B keep; pay; fixinv amount; payout RB 4.28; pay');
  perform pg_temp.t476_check((select v->>'error' from t476_res where phase = 'K' and k = 'P1') is null
      and (select v->>'comm' from t476_res where phase = 'K' and k = 'P1') = 'RA 4.50'
      and (select b.payable from affiliate_referrer_balances() b where b.referrer = pg_temp.t476_id('K/P1/RA')) = 4.50
      and (select b.deduction from affiliate_referrer_balances() b where b.referrer = pg_temp.t476_id('K/P1/RB')) = 4.28
      and (select b.payable from affiliate_referrer_balances() b where b.referrer = pg_temp.t476_id('K/P1/RB')) = 0,
    'K7 P1, a payout in the window: ' || coalesce((select v::text from t476_res where phase = 'K' and k = 'P1'), 'not run'));
  -- K13 (NOT COVERED 13, not caused by 476): a package line added by a
  -- correction to an invoice paid in full releases credit for the money that
  -- paid for the vouchers already issued (KV13: S$60 and the 2 vouchers for
  -- S$60), the same before 476 and after it.
  perform pg_temp.t476_check((select v->'holds' from t476_res where phase = 'after' and k = 'KV13') @> '{"A":"60.00/2"}'
      and (select (v->>'net')::numeric from t476_res where phase = 'after' and k = 'KV13') = 60,
    'K13 KV13: look at NOT COVERED 13 again');
  raise notice 'KNOWN K: (476''s NOT COVERED) (1c) two corrections are two sales (KAT3: A S$200, B S$100; paid in full after both: A S$300); (2) changed with ''transfer'' before full payment, the sale record and the commission are the new customer''s (CKT), paid in full first the buyer''s (CKTF); (3) split before 476: all it gives later goes to the invoice''s customer%; (4) the buyer deleted: the invoice''s customer (Kdel: B S$60); (7) changed with ''keep'', settled, then part-paid again: the part-payment layer gives the line''s commission to the invoice''s customer''s referrer while the sale record stays the buyer''s (G5 RB S$4.50, C3c RB S$4.28, C5 RB S$8.78, L4 RB S$6.08; paid in full again, the buyer''s referrer: G5p, C3cp RA S$4.50), as for the package paid in full and then changed (G5F, C3cF); a payout in that window is owed back (P1: RB S$4.28 deducted, RA owed S$4.50); (9) TQcru''s lot moves to B still locked by Cancel''s write-off (S$20), and an Owner''s Move of it once paid is %; (13) a package added by a correction to an invoice paid in full releases credit for money that paid for vouchers already issued (KV13: S$60 and 2 vouchers for S$60)',
    case when exists (select 1 from t476_res where phase = 'mid' and k = 'MK1p') then ' (MK1p: B S$60)' else ' (not tried: -v nomig=1)' end,
    case when v_msg like 'moved|%' then 'made where 477 is in (F S$20, answer D)' else 'refused (477 not in)' end;
end $$;

rollback;
