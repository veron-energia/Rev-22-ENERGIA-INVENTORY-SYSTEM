-- 478: the Reopen dialog says what the reopening and the payment that
-- settles it give, and to whom: as its own figure and line, the credit the
-- reopening itself gives at once for a Credit Package or Premium Bundle paid
-- in part ("Credit released at once on reopening"), beside the credit to
-- reinstate after settlement, and its explanation says when each comes back
-- (474's NOT COVERED 2, its suite's KNOWN K2, PT0; the Owner, 27 Oct 2026);
-- and (the Owner's answer E, 27 Oct 2026, "Dialogs name the receiver"; 474's
-- NOT COVERED 3; the first build's NOT COVERED 2 to 4) a Premium Bundle's
-- vouchers given at once, what the settling payment gives (the paid credit
-- not yet released, and the Bonus) and who receives each, by customer; and
-- (answer E as the Owner ticked it, "plus the vouchers and extra credit the
-- payment will give"; the second build's NOT COVERED 2, its KNOWN K2a and
-- K2b) the vouchers the settling payment gives (a bundle's free vouchers,
-- chosen at the till or to choose later) and a Credit Package's reward
-- units, at once or with the settling payment, to the same receivers; the
-- receivers cover all of the dialog's credit (the Owner, 28 Oct 2026).
-- supabase/478_reopen_dialog_credit_released_at_once.sql (after 475, 476
-- and 477). The page: src/components/invoices/InvoiceFinancePanel.tsx and
-- src/lib/invoices/reopenReceivers.mjs, their test
-- scripts/invoices/tests/reopen-dialog-478.test.mjs.
--
-- Every step goes through the app's own calls (474's suite harness, its
-- steps and readings, renamed, with Record Payment of an amount, Correct
-- payment raising a receipt, a sale with a discount paid in part and a
-- correction adding a line): the invoice form (create_invoice_with_details)
-- and the Pay dialog (record_invoice_settlement), Record Payment, Cancel,
-- the guided Cancel, Reopen, the Finance panel's "Record refund paid",
-- Correct payment (correct_invoice_payment) and an Owner's Move, a session
-- paid from the package's credit and its refund, the invoice form's
-- customer change (correct_invoice, 'transfer' or 'keep') and a correction
-- adding a line, a customer merge. Before each Reopen the Reopen dialog is
-- read as the Finance panel reads it (invoice_reopen_preview: every figure
-- it shows, InvoiceFinancePanel.tsx; 478's 'credit_released_on_reopen',
-- 'bundle_vouchers_given_on_reopen', 'bundle_vouchers_to_choose_on_reopen',
-- 'credit_from_settling_payment', 'credit_receivers' and the explanation),
-- and at each step what each customer got: the credit granted to the
-- invoice's release records' lots and sale records' lots (released as paid,
-- or given at settlement, the Bonus included), a bundle's vouchers and its
-- allowance to choose later, a package's reward units, and the credit the
-- reopening queue gave back (on the lot it went back on, or where 460's rule
-- moved it on, the lot it was moved to); and what the trim took back; after
-- each step what the payment that settles it gave back (474's readings).
-- Each app call is followed by what its commit does (462's trigger on the
-- ledger is DEFERRABLE INITIALLY DEFERRED and this suite is one transaction:
-- SET CONSTRAINTS ... IMMEDIATE, then DEFERRED).
--
-- The cases (A the buyer; B a later customer; K a record a merge keeps; F a
-- friend an Owner moved credit to; cp the S$100 Credit Package, cpb the
-- S$100 + S$10 Bonus package, pbv the S$140 Premium Bundle (S$100 paid
-- credit, S$40 Bonus, 2 vouchers, both chosen at the till; pbv1 one chosen,
-- one to choose later), th a therapy line of 3 sessions at S$20, v a voucher
-- line; 'cp 40': S$40 of S$100 paid; S1, S2 S$20 sessions paid from the
-- package's credit). What a case reads: 'dlgr' the dialog's figure at its
-- last Reopen (null where the preview has no such key), 'atonce' what that
-- Reopen gave at once, 'everyr' each Reopen whose figure (none counted as
-- S$0.00) was not what it gave at once, 'expl' the explanation at its last
-- Reopen ('474' 474's words, '478' with 478's sentence), 'trimmed' what any
-- Reopen took back; 'dlgvo', 'dlgao' and 'dlgl' the bundle vouchers given
-- at once, those to choose later and the settling payment's credit at the
-- last Reopen; 'rcv' its receivers ('A*:20.00/0/0/60.00/0.00': A, the
-- invoice's customer (*), S$20 at once, 0 vouchers given at once, 0 to
-- choose later, S$60 from the settling payment, S$0 reinstated after
-- settlement; by role), 'got' the same figures as given (at the last Reopen,
-- and the credit given by the steps after it), 'everyrc' each Reopen whose
-- receivers' at-once parts are not what it gave at once to each, 'unsaid'
-- what was given that 474's dialog does not show (credit or vouchers at
-- once, credit from the settling payment, anything to a customer other than
-- the invoice's); 'dlgru' a package's reward units at once, 'dlgsv',
-- 'dlgsa' and 'dlgsu' the bundle's vouchers, those to choose later and a
-- package's reward units from the settling payment, at the last Reopen
-- (null where the preview has no such key), each in 'rcv' and 'got' after
-- a '|' where any is above 0 ('A*:20.00/0/0/100.00/0.00|0/2/0/0': no reward
-- units at once, 2 bundle vouchers, none to choose later and no reward
-- units from the settling payment); and 474's: 'dlg' the credit to
-- reinstate after settlement, 'queued', 'gave', 'required' (the payment
-- required to settle again):
--   PT0         474's K2: S$40 paid, S1, cancelled, reopened, paid.
--   PTn, PTb, PTv, PTd, PT2, PTth, PTth2  nothing spent; the Bonus package;
--               the Premium Bundle; a S$20 discount; two packages; beside a
--               therapy line (after it, before it).
--   PTp, PTvp   released in two payments (the bundle too).
--   PTv1, PTkvl, PTr2, PTr2p, PTkr, PTkrp, PTnp  the vouchers the settling
--               payment gives: the bundle with one voucher to choose later;
--               after a 'keep' change (A's); a Credit Package granting 2
--               reward units (cpr: one for each S$50 of its S$100 price),
--               settled at once by the reopening (PTr2, the second build's
--               KNOWN K2b) or left to be paid; after a 'keep' change (A's);
--               never paid towards before the cancellation (PTnp).
--   PTq, PTqp, PTqk, PTuq, PTq2, PTkw  cancelled again (S$20 more paid, a
--               'keep' change, S1 refunded while it waited; S2 spent after
--               the first reopening; a 'keep' change and S$20 more paid).
--   PTk, PTkc, PTt, PTtc, PTm, PTm2  'keep' or 'transfer' to B before the
--               session or while cancelled; merged into K while cancelled or
--               before the session.
--   PTu, PTgk   S1 refunded while cancelled; the guided Cancel, "Record
--               refund paid" not ticked.
--   PTr, PTs, PTsb, PTks, PTsv, PTkv, PTsv1, PTdb  Correct payment raising
--               the S$40 receipt while cancelled: to S$70; to the total (the
--               reopening settles it at once), the Bonus package (after a
--               'keep' change), the bundle (after a 'keep' change; one
--               voucher to choose later), with a discount.
--   PTcr        a correction took the therapy line off while cancelled
--               (the reopening settles it at once).
--   AL          a correction added a second package to a paid package
--               invoice: both figures.
--   KAL, KALr, KALv  a 'keep' change, then a correction added a package (B
--               pays for it): two receivers; the first package paid in part,
--               or in full (its credit reinstated to A); the added line the
--               bundle (its vouchers from the settling payment B's).
--   CTLk, CTLmv a package paid in full: a 'keep' change while cancelled
--               (reinstated to A); an Owner's Move to F (reinstated to F).
--   RFk, RFkb   a package paid in full, a 'keep' change, refunded (the guided
--               Refund in full; a refund by line), reopened (reinstated to A).
--   PTF, PTrpq  settled once since (its first reopening gave at once).
--   PTall, PTrp all released credit spent; the money paid back while
--               cancelled (nothing at once; the settling payment gives).
--   Controls (nothing more to show than 474's dialog did): CTL0, CTL1 (a
--   package paid in full), CTLv (a bundle paid in full), RF0 (refunded in
--   full), CTLt ('transfer' while cancelled: B, the invoice's customer), CTLm
--   (a merge while cancelled: K), VQ, TH0.
-- (cp, the S$100 package, grants rewards by default but no unit on these
-- copies: they hold no Legacy rule, so its threshold is 994.)
-- In every case 462's invariants (471's reading of them) and Cancel (tried,
-- undone; a package's reward units resolved first, as the Finance panel asks)
-- taking all of the invoice's credit back from whoever holds it.
--
--   S. Where it starts: 462, 463 and 470 to 477 in; 478 in (nomig) or not,
--      the preview at 474's AFTER.
--   R. Without 478 (skipped with -v nomig=1), undone: the preview has none
--      of 478's keys; each 'fixed' case gives what the dialog does not show
--      (credit, vouchers or reward units at once, credit, vouchers or reward
--      units from the settling payment, or something to a customer other
--      than the invoice's: 'unsaid', or an earlier Reopen's 'everyr'); each
--      control gives nothing it does not show; everything else as 478
--      leaves it.
--   Q. The read-only query in 478's header (the same text), on states made
--      for it (two by hand, for NOT COVERED 1 and 5) and the R states: what
--      it lists, by reason (1 to 7).
--   9. Refusals, each changing nothing: the preview neither 474's nor
--      478's; a function it relies on not as tested (its caller, the
--      reopening, the release, the money toward a line, the settlement, the
--      receiver, the reward units' rule); an overload of its name; a new
--      caller of the preview, of
--      the release, a new writer of the release records or of the reopening
--      queue; the triggers on invoices not as read; the queue's unique key
--      gone; other grants. The same grants in another order do not stop it.
--   M. Begun before 478 (cancelled, one reopened and cancelled again, one
--      after a 'keep' change, a bundle), the dialog read after it.
--  10. 478 installed twice: as tested, the second run changing nothing,
--      nothing added, the grants as before.
--   A. Each case after 478: at every Reopen the figure is what it gave at
--      once and the receivers' at-once parts what each got; at the last
--      Reopen every figure and each receiver's part is what was given, the
--      vouchers and reward units included (the receivers' parts add up to
--      the figures); the explanation has 478's
--      sentence where credit comes at once and is 474's otherwise; who holds
--      what, the money, the plans, the invariants and Cancel exactly as
--      before 478 (every key but the dialog's, where R ran).
--   P. Probes: the preview's other figures exactly 474's (its text worked
--      back from 478's, by md5); what a reopening records (its revision's
--      snapshot, its Audit Log row: the figures, the vouchers and reward
--      units, the receivers); a waiting reopening's preview; the grants.
--   K. KNOWN (478's NOT COVERED), checked as they are: 2 (the sale record
--      and its commission not named: not asked), 5 (a trim by hand), 9 (the
--      receivers' names recorded), 10 (the voucher units to replace after
--      settlement not named by receiver, CTLvk). The second build's KNOWN
--      K2a and K2b (the vouchers the settling payment gives; a package's
--      reward units) are fixed cases now (PTv, PTr2 and their siblings).
--
-- Run on a copy of production as it is with 476 and 477 applied (475 in,
-- 27 Oct 2026: e948504d; 476: cc718597; 477: 88ba82cc, 1390 functions;
-- 478: eae7f82f):
--   psql -X -v ON_ERROR_STOP=1 -f scripts/invoices/tests/reopen-dialog-credit-released-478.sql
-- It installs 478 itself (twice) inside its transaction. Where 478 is in
-- already, add -v nomig=1 (S checks it as tested; R, Q, 9 and M are skipped;
-- every case after 478 is still checked). Section 9 lets the install fail on
-- purpose (psql prints its ERROR); the suite then checks that message.
-- Disposable database only; everything is rolled back. Every name, code and
-- amount is invented (@example.com); the phones are numbers kept for fiction
-- (ACMA, +61491570000 to +61491570999).
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '10s';
set local statement_timeout = '900s';

-- ── Set-up and the app's calls (474's suite harness, for 478) ────────────────
create temp table t478(k text primary key, id uuid);
create temp table t478_res(phase text, k text, v jsonb, primary key (phase, k));
create temp table t478_fp(k text primary key, fp text);
create temp sequence t478_phone;
create function pg_temp.t478_id(p_k text) returns uuid language sql as $f$ select id from t478 where k = p_k $f$;
create function pg_temp.t478_put(p_k text, p_id uuid) returns uuid language sql as $f$
  insert into t478 values (p_k, p_id) on conflict (k) do update set id = excluded.id returning id $f$;
create function pg_temp.t478_check(p_ok boolean, p_label text) returns void language plpgsql as $f$
begin
  if not coalesce(p_ok, false) then raise exception 'FAIL %', p_label; end if;
end $f$;
create function pg_temp.t478_fingerprint() returns text language sql as $f$
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.oid::regprocedure::text)) || ' ' || count(*)
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prokind in ('f', 'p') $f$;
create function pg_temp.t478_463_in() returns boolean language sql as $f$
  select to_regprocedure('public.invoice_benefit_moved_to_other(uuid)') is not null $f$;
create function pg_temp.t478_462_in() returns boolean language sql as $f$
  select to_regprocedure('public.credit_given_back_follows(uuid)') is not null
     and exists (select 1 from pg_trigger where tgname = 'credit_given_back_follows'
                  and tgrelid = 'public.customer_credit_ledger'::regclass) $f$;
create function pg_temp.t478_470_in() returns boolean language sql as $f$
  select to_regprocedure('public.credit_given_back_follows(uuid)') is not null
     and position('-- 470 (the Owner, 24 Oct 2026' in pg_get_functiondef('public.credit_given_back_follows(uuid)'::regprocedure)) > 0 $f$;
create function pg_temp.t478_471_in() returns boolean language sql as $f$
  select to_regprocedure('public.credit_given_back_follows(uuid)') is not null
     and position('-- 471 (the Owner, 26 Oct 2026' in pg_get_functiondef('public.credit_given_back_follows(uuid)'::regprocedure)) > 0 $f$;
create function pg_temp.t478_472_in() returns boolean language sql as $f$
  select to_regprocedure('public.credit_given_back_follows(uuid)') is not null
     and position('-- 472 (the Owner, 26 Oct 2026' in pg_get_functiondef('public.credit_given_back_follows(uuid)'::regprocedure)) > 0 $f$;
create function pg_temp.t478_473_in() returns boolean language sql as $f$
  select position('-- 473 (the Owner, 26 Oct 2026' in pg_get_functiondef('public.invoice_transferable_benefits(uuid)'::regprocedure)) > 0 $f$;
-- 474 is in: the preview counts the credit still waiting (its text says so).
create function pg_temp.t478_474_in() returns boolean language sql as $f$
  select position('-- 474 (the Owner, 26 Oct 2026' in pg_get_functiondef('public.invoice_reopen_preview_before_sessions(uuid)'::regprocedure)) > 0 $f$;
-- 475 is in: reopen_invoice queues a session still waiting only once.
create function pg_temp.t478_475_in() returns boolean language sql as $f$
  select position('-- 475 (the Owner, 27 Oct 2026' in pg_get_functiondef('public.reopen_invoice(uuid,text,uuid)'::regprocedure)) > 0 $f$;
-- 476 is in: credit a package paid in part releases later goes to whoever
-- holds its benefits (release_credit_package_paid_credit).
create function pg_temp.t478_476_in() returns boolean language sql as $f$
  select position('-- 476 (the Owner, 27 Oct 2026' in pg_get_functiondef('public.release_credit_package_paid_credit(uuid)'::regprocedure)) > 0
     and to_regprocedure('public.credit_line_benefits_holder(uuid)') is not null $f$;
-- 477 is in: refund_special_credit opens the lot it gives back onto.
create function pg_temp.t478_477_in() returns boolean language sql as $f$
  select position('-- 477 (the Owner, 27 Oct 2026' in pg_get_functiondef('public.refund_special_credit(text,uuid)'::regprocedure)) > 0 $f$;
-- 478 is in: the preview names the credit the reopening itself gives at once
-- (its text says so; S checks its md5).
create function pg_temp.t478_in() returns boolean language sql as $f$
  select position('-- 478 (the Owner, 27 Oct 2026' in pg_get_functiondef('public.invoice_reopen_preview_before_sessions(uuid)'::regprocedure)) > 0 $f$;
-- What a commit does at the end of each app call (each is its own
-- transaction in the app): 462's deferred trigger on the ledger runs (478
-- adds no trigger, and changes nothing a commit does). Here
-- the suite is one transaction, so the trigger's queued rows are run at this
-- point. (Not where each step really commits: t478.autocommit 'on', for
-- running the same cases one call per transaction on a disposable copy.)
create function pg_temp.t478_commit() returns void language plpgsql as $f$
begin
  if coalesce(current_setting('t478.autocommit', true), '') = 'on' then return; end if;
  if pg_temp.t478_462_in() then
    execute 'set constraints public.credit_given_back_follows immediate';
    execute 'set constraints public.credit_given_back_follows deferred';
  end if;
end $f$;

do $$
declare own uuid := gen_random_uuid(); st uuid; st2 uuid; pm uuid; v uuid; cp uuid; cpb uuid; cpr uuid; pbv uuid; svc uuid; svc5 uuid;
begin
  insert into auth.users(id, email) values (own, 't478-owner@example.com');
  insert into profiles(id, full_name, email, role, is_active) values (own, 'T478 Owner', 't478-owner@example.com', 'owner', true);
  perform set_config('request.jwt.claims', json_build_object('sub', own, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', own::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  insert into stores(name, code, country_code) values ('T478 Store', 'T478S1', 'SG') returning id into st;
  insert into stores(name, code, country_code) values ('T478 Other Store', 'T478S2', 'SG') returning id into st2;
  insert into payment_methods(name, is_active) values ('T478 Cash', true) returning id into pm;
  insert into vouchers(name, code, voucher_kind, qty_type, selling_price, is_active)
    values ('T478 Plain 30', 'T478-P30', 'normal', 'unlimited', 30, true) returning id into v;
  insert into voucher_store_prices(voucher_id, store_id, selling_price, available_at_store) values (v, st, 30, true), (v, st2, 30, true);
  insert into credit_packages(name, customer_price, paid_credit_amount, bonus_enabled, allow_product, allow_therapy)
    values ('T478 S$100', 100, 100, false, true, true) returning id into cp;
  insert into credit_package_stores(package_id, store_id) values (cp, st), (cp, st2);
  insert into credit_packages(name, customer_price, paid_credit_amount, bonus_enabled, bonus_value, allow_product, allow_therapy, grants_reward)
    values ('T478 S$100 + S$10', 100, 100, true, 10, true, true, false) returning id into cpb;
  insert into credit_package_stores(package_id, store_id) values (cpb, st), (cpb, st2);
  -- 478 (K, NOT COVERED 2): a S$100 package that grants rewards, a reward
  -- unit for each S$50 of its price.
  insert into credit_packages(name, customer_price, paid_credit_amount, bonus_enabled, allow_product, allow_therapy, grants_reward, reward_qualifying_amount)
    values ('T478 S$100 rewards', 100, 100, false, true, true, true, 50) returning id into cpr;
  insert into credit_package_stores(package_id, store_id) values (cpr, st), (cpr, st2);
  insert into premium_bundles(name, customer_payment_amount, paid_credit_amount, bonus_credit_amount, free_voucher_qty, grants_reward)
    values ('T478 Bundle S$140 + 2 vouchers', 140, 100, 40, 2, true) returning id into pbv;
  insert into premium_bundle_stores(bundle_id, store_id) values (pbv, st), (pbv, st2);
  insert into premium_bundle_vouchers(bundle_id, voucher_id) values (pbv, v);
  svc := (upsert_therapy_service(null, 'T478-SESSION', 'T478 Session', 20, 30, 'per_hours', 1, 5, null, true, null) ->> 'id')::uuid;
  perform set_therapy_service_store(svc, st, true, null);
  svc5 := (upsert_therapy_service(null, 'T478-SHORT', 'T478 Short session', 5, 15, 'per_hours', 1, 5, null, true, null) ->> 'id')::uuid;
  perform set_therapy_service_store(svc5, st, true, null);
  insert into t478 values ('own', own), ('store', st), ('store2', st2), ('pm', pm), ('v', v), ('cp', cp), ('cpb', cpb), ('cpr', cpr), ('pbv', pbv),
    ('svc', svc), ('svc5', svc5),
    ('wallet', (select id from payment_methods where name = 'Wallet — Credit Package Paid' and is_wallet_credit and deleted_at is null)),
    ('bwallet', (select id from payment_methods where name = 'Wallet — Premium Bundle Paid' and is_wallet_credit and deleted_at is null));
  perform pg_temp.t478_check(pg_temp.t478_id('wallet') is not null and pg_temp.t478_id('bwallet') is not null, 'setup: the wallet methods (443) are there');
end $$;

-- A customer of one run of one case: '<phase>/<case>/<role>'.
create function pg_temp.t478_cust(p_k text) returns uuid language plpgsql as $f$
declare c uuid;
begin
  insert into customers(full_name, phone) values ('T478 ' || p_k, '+61491570' || lpad((nextval('t478_phone') % 1000)::text, 3, '0'))
    returning id into c;
  return pg_temp.t478_put(p_k, c);
end $f$;
-- The invoice form with these lines ('cp' / 'cpb' a Credit Package, 'pbv' the
-- Premium Bundle, 'v' a voucher line of p_qty units, 'th' three sessions of
-- S$20), with an Owner's manual
-- discount of p_discount (its reason given) where one is given, paid through
-- the Pay dialog: in full, or p_first of it (a part-paid package; 478: 0,
-- nothing paid).
create function pg_temp.t478_sale(p_cust uuid, p_kinds text[], p_first numeric default null, p_qty int default 2,
                                  p_discount numeric default null)
  returns uuid language plpgsql as $f$
declare inv uuid; v_lines jsonb := '[]'; i int;
begin
  for i in 1 .. cardinality(p_kinds) loop
    v_lines := v_lines || jsonb_build_array(case
      when p_kinds[i] = 'v' then jsonb_build_object('kind', 'voucher', 'voucher_id', pg_temp.t478_id('v'), 'quantity', p_qty)
      -- 474: a therapy line of three S$20 sessions (the dialog's sessions)
      when p_kinds[i] = 'th' then jsonb_build_object('kind', 'therapy', 'therapy_service_id', pg_temp.t478_id('svc'), 'quantity', 3)
      when p_kinds[i] in ('cp', 'cpb', 'cpr') then jsonb_build_object('kind', 'credit_package', 'credit_package_id', pg_temp.t478_id(p_kinds[i]), 'quantity', 1)
      -- 478: pbv1, one of the bundle's two vouchers chosen at the till (the
      -- other to choose later)
      else jsonb_build_object('kind', 'premium_bundle', 'premium_bundle_id', pg_temp.t478_id('pbv'), 'quantity', 1,
        'voucher_selection', jsonb_build_array(jsonb_build_object('voucher_id', pg_temp.t478_id('v'),
          'quantity', case when p_kinds[i] = 'pbv1' then 1 else 2 end))) end);
  end loop;
  inv := create_invoice_with_details(pg_temp.t478_id('store'), p_cust, v_lines, jsonb_build_object('business_date', sg_today()::text)
           || case when p_discount is not null
                   then jsonb_build_object('manual_discount', p_discount, 'manual_discount_reason', 'T478 discount') else '{}'::jsonb end);
  if p_first is distinct from 0 then
    perform record_invoice_settlement(inv, jsonb_build_object('receipts', jsonb_build_array(jsonb_build_object(
      'key', 'line-0', 'payment_method_id', pg_temp.t478_id('pm'),
      'amount', coalesce(p_first, (select total_amount from invoices where id = inv)),
      'payment_date', sg_today()::text)), 'arrangements', '[]'::jsonb), gen_random_uuid());
  end if;
  return inv;
end $f$;
-- Record Payment of what is outstanding (nothing when it is settled).
create function pg_temp.t478_pay(p_inv uuid) returns void language plpgsql as $f$
begin
  if (invoice_financial_position(p_inv)->>'outstanding')::numeric > 0 then
    perform record_invoice_payment(p_inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.t478_id('pm'),
      'amount', (invoice_financial_position(p_inv)->>'outstanding')::numeric)), gen_random_uuid());
  end if;
end $f$;
-- The receipts that still hold p_amount between them, as the Finance panel
-- splits a refund across them.
create function pg_temp.t478_sources(p_inv uuid, p_amount numeric) returns jsonb language plpgsql as $f$
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
-- 474: line N of an invoice, its credit lines first (an invoice's lines have
-- no order of their own; MIX has a bundle and a voucher line).
create function pg_temp.t478_line(p_inv uuid, p_n int default 1) returns uuid language sql as $f$
  select id from invoice_items where invoice_id = p_inv
   order by case when line_kind in ('credit_package', 'premium_bundle') then 0 else 1 end, id offset p_n - 1 limit 1 $f$;
-- The Finance panel's refund by line of line p_n: p_amount off its Paid
-- benefit (the one an Owner did not move, or with p_holder the one p_holder
-- holds), or every unused benefit it still holds (p_amount null).
create function pg_temp.t478_back(p_inv uuid, p_n int, p_amount numeric default null, p_holder uuid default null)
  returns void language plpgsql as $f$
declare opts jsonb; ben jsonb; tot numeric; item uuid := pg_temp.t478_line(p_inv, p_n);
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
  if ben is null then raise exception 'T478: nothing to refund on that line'; end if;
  perform refund_invoice_recorded(p_inv, jsonb_build_array(jsonb_build_object('invoice_item_id', item, 'amount', tot, 'benefits', ben)),
    pg_temp.t478_sources(p_inv, tot), '[]'::jsonb, 'T478 by line', gen_random_uuid());
end $f$;
-- The invoice form's customer change, its lines as they are (and the store,
-- when given), with 'transfer' or 'keep'. The change's Audit Log row is
-- dated now, as a later call's is (the suite is one transaction).
create function pg_temp.t478_lines(p_inv uuid) returns jsonb language sql as $f$
  select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('invoice_item_id', it.id, 'kind', it.line_kind,
           'credit_package_id', it.credit_package_id, 'premium_bundle_id', it.premium_bundle_id, 'voucher_id', it.voucher_id,
           'quantity', it.quantity, 'unit_price', it.unit_price, 'voucher_selection', it.bundle_voucher_selection)) order by it.id)
    from invoice_items it where it.invoice_id = p_inv $f$;
create function pg_temp.t478_change(p_inv uuid, p_cust uuid, p_action text default 'transfer', p_store text default null)
  returns void language plpgsql as $f$
begin
  perform correct_invoice(p_inv, pg_temp.t478_lines(p_inv),
    jsonb_build_object('expected_edit_count', (select edit_count from invoices where id = p_inv),
      'customer_id', p_cust, 'store_id', coalesce(pg_temp.t478_id(p_store), (select store_id from invoices where id = p_inv)),
      'benefit_action', p_action),
    'T478 wrong customer', gen_random_uuid());
  update audit_logs set created_at = clock_timestamp()
   where record_id = p_inv and action = 'invoice_benefits_followed_reassignment' and new_data->>'to_customer' = p_cust::text
     and created_at = now();
end $f$;
create function pg_temp.t478_merge(p_keep uuid, p_dup uuid) returns void language plpgsql as $f$
begin
  perform merge_customer_records(p_keep, p_dup, 'T478 the same person', gen_random_uuid());
end $f$;
-- The Finance panel's Move of line p_n's unused benefit (its Paid credit,
-- or its Bonus with p_kind 'bonus', or a voucher) to p_to, at p_store.
create function pg_temp.t478_move(p_inv uuid, p_n int, p_to uuid, p_kind text default 'paid', p_store text default null)
  returns void language plpgsql as $f$
declare b uuid;
begin
  select bv.id into b from invoice_benefit_values bv
    left join customer_reward_vouchers v on v.id = bv.reward_voucher_id
    left join customer_credit_lots l on l.id = bv.lot_id
   where bv.invoice_item_id = pg_temp.t478_line(p_inv, p_n)
     and (v.status = 'held' and p_kind = 'voucher' or l.remaining_amount > 0 and l.category = p_kind)
   order by bv.granted_value desc limit 1;
  if b is null then raise exception 'T478: nothing to move on that line'; end if;
  perform transfer_invoice_unused_benefit(b, p_to, coalesce(pg_temp.t478_id(p_store), (select store_id from invoices where id = p_inv)),
    'T478 move', gen_random_uuid());
end $f$;
-- The invoice form: p_n sessions of S$20 (or S$5 with p_svc 'svc5') for
-- p_cust, paid with the wallet (Credit Package Paid; Premium Bundle Paid with
-- p_wallet 'bwallet') through Record Payment.
create function pg_temp.t478_spend(p_cust uuid, p_n int default 1, p_svc text default 'svc', p_wallet text default 'wallet')
  returns uuid language plpgsql as $f$
declare inv uuid; v_lines jsonb := '[]'; i int;
begin
  for i in 1 .. p_n loop
    v_lines := v_lines || jsonb_build_array(jsonb_build_object('kind', 'therapy', 'therapy_service_id', pg_temp.t478_id(p_svc), 'quantity', 1));
  end loop;
  inv := create_invoice_with_details(pg_temp.t478_id('store'), p_cust, v_lines, jsonb_build_object('business_date', sg_today()::text));
  perform record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.t478_id(p_wallet),
    'amount', (select total_amount from invoices where id = inv))), gen_random_uuid());
  if (select status::text from invoices where id = inv) <> 'paid' then raise exception 'T478: the session paid from credit is not paid'; end if;
  return inv;
end $f$;
-- The session cancelled and "Record refund paid": what its payment took goes
-- back to the lots it came from (refund_invoice_recorded's wallet refund).
create function pg_temp.t478_unspend(p_inv uuid) returns void language plpgsql as $f$
declare due numeric;
begin
  perform cancel_invoice_recorded(p_inv, 'T478 cancel session', gen_random_uuid());
  due := (invoice_financial_position(p_inv)->>'refund_due')::numeric;
  if due is null or due <= 0 then due := (invoice_action_plan(p_inv, 'cancel', '[]')->>'refund_due')::numeric; end if;
  perform refund_invoice_recorded(p_inv, jsonb_build_array(jsonb_build_object('amount', due)), pg_temp.t478_sources(p_inv, due), '[]'::jsonb,
    'T478 refund paid', gen_random_uuid());
end $f$;
-- The Finance panel's Correct payment on a session's wallet payment: the
-- date only ('date'), a smaller amount ('amount', S$5 less), or another
-- method ('cash').
create function pg_temp.t478_fix(p_inv uuid, p_how text) returns void language plpgsql as $f$
declare p invoice_payments%rowtype;
begin
  select * into p from invoice_payments where invoice_id = p_inv and entry_kind in ('receipt', 'correction_replacement')
     and not exists (select 1 from invoice_payments q where q.corrects_payment_id = invoice_payments.id and q.entry_kind = 'correction_reversal')
   order by created_at desc, id desc limit 1;
  perform correct_invoice_payment(p.id,
    case p_how when 'amount' then p.amount - 5 else p.amount end,
    sg_today() - 1,
    case p_how when 'cash' then pg_temp.t478_id('pm') else p.payment_method_id end,
    'T478 correct payment ' || p_how, gen_random_uuid());
end $f$;
-- A special document's wallet payment as pay_special_with_credit records it
-- (a stand-in: no page calls that function, and no credit category allows a
-- special document today, purchase_category): p_amount off the customer's
-- largest lot ('use', its allocations), so refund_special_credit, the real
-- one, gives it back.
create function pg_temp.t478_special(p_cust uuid, p_kind text, p_doc uuid, p_amount numeric) returns void language plpgsql as $f$
declare l customer_credit_lots%rowtype; e uuid;
begin
  select * into l from customer_credit_lots where customer_id = p_cust and status = 'active' and remaining_amount >= p_amount
   order by remaining_amount desc, id limit 1 for update;
  insert into customer_credit_ledger(wallet_id, customer_id, entry_type, category, amount, lot_id, source_type, source_record_id, store_id, note, created_by)
  values (l.wallet_id, p_cust, 'use', l.category, p_amount, l.id, p_kind, p_doc, l.store_id, 'T478 special', auth.uid()) returning id into e;
  update customer_credit_lots set remaining_amount = remaining_amount - p_amount, updated_at = now() where id = l.id;
  insert into customer_credit_allocations(ledger_entry_id, lot_id, customer_id, amount) values (e, l.id, p_cust, p_amount);
  insert into special_credit_allocations(doc_kind, doc_id, customer_id, lot_id, category, amount, created_by)
  values (p_kind, p_doc, p_cust, l.id, l.category, p_amount, auth.uid());
end $f$;
-- The guided Refund in full / Cancel as an Owner confirms it, with a reason
-- for every override the plan asks for, the money recorded as paid back (or,
-- with p_record false, not: "Record refund paid" left unticked).
create function pg_temp.t478_guided(p_inv uuid, p_action text, p_record boolean default true) returns void language plpgsql as $f$
declare plan jsonb; req jsonb; ov jsonb;
begin
  plan := invoice_action_plan(p_inv, p_action, '[]');
  req := request_invoice_action_v2(p_inv, p_action, '[]', 'T478 ' || p_action, null, gen_random_uuid());
  select coalesce(jsonb_agg(case when coalesce((o->>'amount_required')::boolean, false)
           then jsonb_build_object('code', o->>'code', 'reason', 'T478 override', 'amount', (o->>'default_amount')::numeric)
           else jsonb_build_object('code', o->>'code', 'reason', 'T478 override') end), '[]'::jsonb)
    into ov from jsonb_array_elements(coalesce(plan->'overrides_required', '[]')) o;
  perform resolve_invoice_action_v2((req->>'request_id')::uuid, true, 'T478 ' || p_action, plan->>'plan_hash', ov, null, p_record);
end $f$;


-- ── What the records say ────────────────────────────────────────────────────
-- The lots an invoice's records name: its benefit values, its sale's lots, a
-- split's issued lot, released credit (credit_package_progress_lots).
create function pg_temp.t478_named(p_inv uuid) returns setof uuid language sql as $f$
  select lot_id from invoice_benefit_values where invoice_id = p_inv and lot_id is not null
  union select x from credit_package_sales s, unnest(array[s.credit_lot_id, s.bonus_credit_lot_id]) x where s.invoice_id = p_inv and x is not null
  union select x from premium_bundle_sales s, unnest(array[s.paid_credit_lot_id, s.bonus_credit_lot_id]) x where s.invoice_id = p_inv and x is not null
  union select issued_lot_id from invoice_credit_splits where invoice_id = p_inv and issued_lot_id is not null
  union select lot_id from credit_package_progress_lots where invoice_id = p_inv $f$;
-- The invoice's lot family (the critic's 6): every lot its records name and
-- each Move's two lots (from the Move's ledger rows), the lots each replaced
-- and every lot reissued from any of them.
create function pg_temp.t478_family(p_inv uuid) returns setof uuid language sql as $f$
  with recursive seed as (
    select x as id from pg_temp.t478_named(p_inv) x
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
create function pg_temp.t478_behind(p_inv uuid) returns setof uuid language sql as $f$
  with recursive c(id, n) as (
    select lot_id, 0 from invoice_benefit_values where invoice_id = p_inv and lot_id is not null
    union select p.id, c.n + 1 from c join customer_credit_lots l on l.id = c.id
            join customer_credit_lots p on p.id = l.reassigned_from_lot_id
             and (p.source_type, p.source_record_id) is not distinct from (l.source_type, l.source_record_id)
           where c.n < 12)
  select distinct id from c $f$;
-- How many lots back a lot's chain goes (reassigned_from_lot_id).
create function pg_temp.t478_depth(p_lot uuid) returns int language sql as $f$
  with recursive c(id, n) as (select p_lot, 0 union all
    select l.reassigned_from_lot_id, c.n + 1 from c join customer_credit_lots l on l.id = c.id
     where l.reassigned_from_lot_id is not null and c.n < 40)
  select max(n) from c $f$;
-- A lot's balance by its ledger rows: credit added (grants, increases,
-- credit returned: the 'reverse' rows that put credit back, as the
-- statement reads them, and 'rental_late_fee'), less credit taken (uses,
-- decreases, real reversals).
create function pg_temp.t478_ledger_balance(p_lot uuid) returns numeric language sql as $f$
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
create function pg_temp.t478_invariants(p_inv uuid) returns text language plpgsql as $f$
declare probs text := ''; l record; root record; v uuid; st text := (select status::text from invoices where id = p_inv);
begin
  for l in select cl.* from customer_credit_lots cl where cl.id in (select pg_temp.t478_family(p_inv)) loop
    if l.remaining_amount > 0 and l.id not in (select pg_temp.t478_named(p_inv)) then
      probs := probs || format(' S$%s on a lot no record names (%s);', l.remaining_amount, (select full_name from customers where id = l.customer_id)); end if;
    if l.id not in (select pg_temp.t478_named(p_inv)) and l.id not in (select pg_temp.t478_behind(p_inv))
       and (exists (select 1 from invoice_line_credit_allocations a where a.lot_id = l.id and a.amount > coalesce(a.reversed_amount, 0))
            or exists (select 1 from special_credit_allocations s where s.lot_id = l.id and s.amount > coalesce(s.reversed_amount, 0))) then
      probs := probs || ' a sale paid from a lot no record names can still be refunded (its credit would stay there);'; end if;
    if pg_temp.t478_ledger_balance(l.id) <> l.remaining_amount then
      probs := probs || format(' lot holds %s, its ledger %s;', l.remaining_amount, pg_temp.t478_ledger_balance(l.id)); end if;
    if pg_temp.t478_depth(l.id) > 12 then probs := probs || format(' chain %s lots deep;', pg_temp.t478_depth(l.id)); end if;
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
  if st = 'refunded' and (select coalesce(sum(remaining_amount), 0) from customer_credit_lots where id in (select pg_temp.t478_family(p_inv))) > 0 then
    probs := probs || format(' refunded, but S$%s of its credit is still held;',
      (select sum(remaining_amount) from customer_credit_lots where id in (select pg_temp.t478_family(p_inv)))); end if;
  return probs;
end $f$;
-- Credit left on the invoice's family once Cancel has run, the Cancel undone
-- (0 when Cancel takes it all back from whoever holds it); null when the
-- invoice cannot be cancelled now, -1 when Cancel is refused. (478: a
-- package's reward units are resolved first, as the Finance panel asks
-- before a Cancel, resolve_invoice_credit_rewards; undone with it.)
create function pg_temp.t478_cancel_left(p_inv uuid) returns numeric language plpgsql as $f$
declare v numeric;
begin
  if (select status::text from invoices where id = p_inv) not in ('paid', 'partially_paid', 'unpaid') then return null; end if;
  begin
    if exists (select 1 from credit_package_sales s where s.invoice_id = p_inv and s.reward_units > 0 and s.rewards_resolved_at is null) then
      perform resolve_invoice_credit_rewards(p_inv, 'T478 probe', null, true, gen_random_uuid());
    end if;
    perform cancel_invoice_recorded(p_inv, 'T478 probe', gen_random_uuid());
    perform pg_temp.t478_commit();
    v := (select coalesce(sum(remaining_amount), 0) from customer_credit_lots where id in (select pg_temp.t478_family(p_inv)));
    raise exception using errcode = 'P0461', message = v::text;
  exception when sqlstate 'P0461' then return sqlerrm::numeric;
            when others then return -1;
  end;
end $f$;
create function pg_temp.t478_codes(p_inv uuid, p_action text) returns text language plpgsql as $f$
begin
  return (select coalesce(string_agg(o->>'code', ',' order by o->>'code'), '-')
            from jsonb_array_elements(coalesce(invoice_action_plan(p_inv, p_action, '[]')->'overrides_required', '[]')) o);
exception when others then return 'ERR';
end $f$;
create function pg_temp.t478_due(p_inv uuid, p_action text) returns numeric language plpgsql as $f$
begin
  return (invoice_action_plan(p_inv, p_action, '[]')->>case when p_action = 'cancel' then 'refund_due' else 'refund_amount' end)::numeric;
exception when others then return null;
end $f$;
-- The invoice's money: what is owed back (cancel_refund_owed), the Finance
-- panel's refund due, net received and kept for what was used, what a
-- refund by line can still pay back (the refund options' max_refund, every
-- benefit) and Cancel's refund due (the plan's).
create function pg_temp.t478_money(p_inv uuid) returns jsonb language sql as $f$
  select jsonb_build_object('owed', i.cancel_refund_owed,
    'due', (invoice_financial_position(i.id)->>'refund_due')::numeric,
    'net', (invoice_financial_position(i.id)->>'net_received')::numeric,
    'kept', (invoice_financial_position(i.id)->>'kept_for_used')::numeric,
    'by_line', (select coalesce(sum((b->>'max_refund')::numeric), 0)
                  from jsonb_array_elements(invoice_refund_options_before_sessions(i.id)->'benefits') b),
    'plan_due', pg_temp.t478_due(i.id, 'cancel'))
    from invoices i where i.id = p_inv $f$;


-- ── The cases ───────────────────────────────────────────────────────────────
-- A case is a list of steps, each one app call (and its commit), on the
-- case's own customers (A the buyer, B and C later customers, K and K2
-- records a merge keeps, F and G friends an Owner moved credit to). A step
-- refused stops the case, the refusal recorded. Steps:
--   sale R kinds [first]  the invoice (cp, cpb, pbv, v; part-paid: first; 0: nothing paid)
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
--   backv N units         a refund by line of that many voucher units of line N (474)
--   backt N amt           a refund by line of a therapy line by money (474)
--   payp amt              Record Payment of amt (478)
--   raise amt             Correct payment raising the latest receipt to amt (478)
--   saledp R kinds disc first  the invoice with an Owner's manual discount, paid in part (478)
--   addline cp|pbv        the invoice form's correction adding a S$100 Credit Package line, or the
--                         Premium Bundle with its 2 vouchers chosen (478)
--   dropline th           the invoice form's correction taking the therapy line off (478)
--   legacy STATUS         a stand-in for the legacy statuses (no page sets them now)
--   repair                repair_credit_package_progress_lots()
create function pg_temp.t478_role(p_pre text, p_r text) returns uuid language plpgsql as $f$
begin
  return coalesce(pg_temp.t478_id(p_pre || '/' || p_r), pg_temp.t478_cust(p_pre || '/' || p_r));
end $f$;
-- One step of a case (one app call, then what its commit does). Null, or
-- the step and the refusal; a refused step changes nothing.
create function pg_temp.t478_step(p_pre text, p_st text) returns text language plpgsql as $f$
declare w text[] := regexp_split_to_array(btrim(p_st), '\s+'); inv uuid := pg_temp.t478_id(p_pre || '/inv'); x uuid; i int; n int;
begin
  case w[1]
  when 'sale' then
    perform pg_temp.t478_put(p_pre || '/inv', pg_temp.t478_sale(pg_temp.t478_role(p_pre, w[2]), string_to_array(w[3], ','), w[4]::numeric));
  when 'saled' then
    perform pg_temp.t478_put(p_pre || '/inv', pg_temp.t478_sale(pg_temp.t478_role(p_pre, w[2]), string_to_array(w[3], ','), null, 2, w[4]::numeric));
  when 'sale2' then
    perform pg_temp.t478_put(p_pre || '/inv2', pg_temp.t478_sale(pg_temp.t478_role(p_pre, w[2]), array['cp']));
  when 'pay' then perform pg_temp.t478_pay(inv);
  when 'payp' then
    -- 478: Record Payment of an amount (a package paid in part again).
    perform record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.t478_id('pm'),
      'amount', w[2]::numeric)), gen_random_uuid());
  when 'raise' then
    -- 478: the Finance panel's Correct payment raising the invoice's latest
    -- receipt to amt (same date and method), here while it is cancelled.
    perform correct_invoice_payment(p.id, w[2]::numeric, sg_today(), p.payment_method_id,
                                    'T478 correct payment raise', gen_random_uuid())
       from (select q.* from invoice_payments q where q.invoice_id = inv and q.entry_kind in ('receipt', 'correction_replacement')
                and not exists (select 1 from invoice_payments r where r.corrects_payment_id = q.id and r.entry_kind = 'correction_reversal')
              order by q.created_at desc, q.id desc limit 1) p;
  when 'addline' then
    -- 478: the invoice form's correction adding a line (cp: a S$100 Credit
    -- Package; pbv: the Premium Bundle, its 2 vouchers chosen at the till),
    -- its other lines as they are.
    perform correct_invoice(inv, pg_temp.t478_lines(inv) || jsonb_build_array(case when w[2] = 'pbv'
        then jsonb_build_object('kind', 'premium_bundle', 'premium_bundle_id', pg_temp.t478_id('pbv'), 'quantity', 1,
               'voucher_selection', jsonb_build_array(jsonb_build_object('voucher_id', pg_temp.t478_id('v'), 'quantity', 2)))
        else jsonb_build_object('kind', 'credit_package', 'credit_package_id', pg_temp.t478_id(w[2]), 'quantity', 1) end),
      jsonb_build_object('expected_edit_count', (select edit_count from invoices where id = inv),
        'customer_id', (select customer_id from invoices where id = inv), 'store_id', (select store_id from invoices where id = inv)),
      'T478 add a line', gen_random_uuid());
  when 'dropline' then
    -- 478: the invoice form's correction taking off the lines of that kind
    -- (th: the therapy line), its other lines as they are.
    perform correct_invoice(inv, (select jsonb_agg(e) from jsonb_array_elements(pg_temp.t478_lines(inv)) e
                                   where e->>'kind' <> case w[2] when 'th' then 'therapy' when 'v' then 'voucher' else w[2] end),
      jsonb_build_object('expected_edit_count', (select edit_count from invoices where id = inv),
        'customer_id', (select customer_id from invoices where id = inv), 'store_id', (select store_id from invoices where id = inv)),
      'T478 take a line off', gen_random_uuid());
  when 'saledp' then
    -- 478: the invoice with an Owner's manual discount of disc, paid in part (first).
    perform pg_temp.t478_put(p_pre || '/inv', pg_temp.t478_sale(pg_temp.t478_role(p_pre, w[2]), string_to_array(w[3], ','), w[5]::numeric, 2, w[4]::numeric));
  when 'back' then
    perform pg_temp.t478_back(inv, w[2]::int, case when w[3] = 'all' then null else w[3]::numeric end,
                              case when w[4] is not null then pg_temp.t478_role(p_pre, w[4]) end);
  when 'move' then
    perform pg_temp.t478_move(inv, w[2]::int, pg_temp.t478_role(p_pre, w[3]),
      case when w[4] in ('bonus', 'voucher') then w[4] else 'paid' end,
      case when 'store2' = any (w) then 'store2' end);
  when 'cancel' then perform cancel_invoice_recorded(inv, 'T478 cancel', gen_random_uuid());
  when 'reopen' then perform reopen_invoice(inv, 'T478 reopen', gen_random_uuid());
  when 'wait' then
    perform cancel_invoice_recorded(inv, 'T478 cancel', gen_random_uuid());
    for i in 1 .. (select count(*)::int from invoice_items where invoice_id = inv) loop
      perform pg_temp.t478_back(inv, i);
    end loop;
    perform reopen_invoice(inv, 'T478 reopen', gen_random_uuid());
  when 'refundall' then perform pg_temp.t478_guided(inv, 'refund_full');
  when 'change' then
    perform pg_temp.t478_change(inv, pg_temp.t478_role(p_pre, w[2]), case when 'keep' = any (w) then 'keep' else 'transfer' end,
                                case when 'store2' = any (w) then 'store2' end);
  when 'merge' then perform pg_temp.t478_merge(pg_temp.t478_role(p_pre, w[2]), pg_temp.t478_role(p_pre, w[3]));
  when 'spend' then
    n := (select count(*) from t478 where k ~ ('^' || p_pre || '/S[0-9]+$')) + 1;
    perform pg_temp.t478_put(p_pre || '/S' || n,
      pg_temp.t478_spend(pg_temp.t478_role(p_pre, w[2]), case when w[3] ~ '^[0-9]+$' then w[3]::int else 1 end,
        case when 'svc5' = any (w) then 'svc5' else 'svc' end, case when 'bwallet' = any (w) then 'bwallet' else 'wallet' end));
  when 'unspend' then perform pg_temp.t478_unspend(pg_temp.t478_id(p_pre || '/' || w[2]));
  when 'fix' then perform pg_temp.t478_fix(pg_temp.t478_id(p_pre || '/' || w[2]), w[3]);
  when 'delete' then
    x := pg_temp.t478_role(p_pre, w[2]);
    perform delete_customer(x, (select full_name from customers where id = x), 'T478 delete');
  when 'special' then
    n := (select count(*) from t478 where k ~ ('^' || p_pre || '/D[0-9]+$')) + 1; x := gen_random_uuid();
    perform pg_temp.t478_put(p_pre || '/D' || n, x);
    perform pg_temp.t478_put(p_pre || '/D' || n || '/kind:' || w[3], null);
    perform pg_temp.t478_special(pg_temp.t478_role(p_pre, w[2]), w[3], x, w[4]::numeric);
  when 'unspecial' then
    perform refund_special_credit((select split_part(k, 'kind:', 2) from t478 where k like p_pre || '/' || w[2] || '/kind:%'),
                                  pg_temp.t478_id(p_pre || '/' || w[2]));
  when 'reverse' then
    if w[2] = 'closed' then
      -- the released lot a Cancel's write-off closed, once a refund opened it again
      perform reverse_credit_lot(pg_temp.t478_closed_lot(inv), 'T478 reversal');
    else
      x := pg_temp.t478_role(p_pre, w[2]);
      perform reverse_credit_lot((select id from customer_credit_lots where customer_id = x and remaining_amount > 0
                                   order by remaining_amount desc, id limit 1), 'T478 reversal');
    end if;
  when 'guidedcancel' then perform pg_temp.t478_guided(inv, 'cancel');
  when 'guidedkeep' then perform pg_temp.t478_guided(inv, 'cancel', false);
  when 'backo' then
    x := pg_temp.t478_line(inv, w[2]::int);
    perform refund_invoice_recorded(inv, jsonb_build_array(jsonb_build_object('invoice_item_id', x,
        'amount', invoice_discounted_line_value(x),
        'benefits', jsonb_build_array(jsonb_build_object('benefit_id', pg_temp.t478_own(inv), 'amount', w[3]::numeric)),
        'override', jsonb_build_object('code', 'larger_refund', 'reason', 'T478 larger refund', 'amount', invoice_discounted_line_value(x)))),
      pg_temp.t478_sources(inv, invoice_net_received(inv)), '[]'::jsonb, 'T478 larger refund', gen_random_uuid());
  when 'refundpaid' then
    perform refund_invoice_recorded(inv, jsonb_build_array(jsonb_build_object('amount',
        coalesce(nullif((invoice_financial_position(inv)->>'refund_due')::numeric, 0), (invoice_action_plan(inv, 'cancel', '[]')->>'refund_due')::numeric))),
      pg_temp.t478_sources(inv, coalesce(nullif((invoice_financial_position(inv)->>'refund_due')::numeric, 0), (invoice_action_plan(inv, 'cancel', '[]')->>'refund_due')::numeric)),
      '[]'::jsonb, 'T478 refund paid', gen_random_uuid());
  when 'backx' then
    x := pg_temp.t478_line(inv, w[2]::int);
    perform refund_invoice_recorded(inv, jsonb_build_array(jsonb_build_object('invoice_item_id', x,
        'amount', invoice_discounted_line_value(x) - coalesce((select sum((e->>'amount')::numeric) from invoice_refunds r,
             jsonb_array_elements(coalesce(r.outcome->'lines', '[]')) e where r.invoice_id = inv and e->>'invoice_item_id' = x::text), 0),
        'benefits', (select jsonb_agg(jsonb_build_object('benefit_id', b->>'id', 'amount', (b->>'max_refund')::numeric))
                       from jsonb_array_elements(invoice_refund_options_before_sessions(inv)->'benefits') b
                      where b->>'invoice_item_id' = x::text and (b->>'max_refund')::numeric > 0),
        'override', jsonb_build_object('code', 'larger_refund', 'reason', 'T478 larger refund',
          'amount', invoice_discounted_line_value(x) - coalesce((select sum((e->>'amount')::numeric) from invoice_refunds r,
             jsonb_array_elements(coalesce(r.outcome->'lines', '[]')) e where r.invoice_id = inv and e->>'invoice_item_id' = x::text), 0)))),
      pg_temp.t478_sources(inv, invoice_net_received(inv)), '[]'::jsonb, 'T478 larger refund', gen_random_uuid());
  when 'backv' then
    -- 474: the Finance panel's refund by line of N voucher units of line N
    -- (at their paid value).
    x := pg_temp.t478_line(inv, w[2]::int);
    perform refund_invoice_recorded(inv, jsonb_build_array(jsonb_build_object('invoice_item_id', x, 'amount', b.amt,
        'benefits', jsonb_build_array(jsonb_build_object('benefit_id', b.id, 'amount', b.amt)))),
      pg_temp.t478_sources(inv, b.amt), '[]'::jsonb, 'T478 voucher by line', gen_random_uuid())
      from (select o->>'id' as id, round(w[3]::int * (o->>'paid_value')::numeric / (o->>'granted_value')::numeric, 2) as amt
              from jsonb_array_elements(invoice_refund_options_before_sessions(inv)->'benefits') o
             where o->>'invoice_item_id' = x::text and o->>'benefit_kind' = 'voucher' and (o->>'max_refund')::numeric > 0
             order by (o->>'max_refund')::numeric desc limit 1) b;
    if not found then raise exception 'T478: no voucher to refund on that line'; end if;
  when 'backt' then
    -- 474: the Finance panel's refund by line of a therapy line, by money
    -- (whole unused sessions).
    x := pg_temp.t478_line(inv, w[2]::int);
    perform refund_invoice_recorded(inv, jsonb_build_array(jsonb_build_object('invoice_item_id', x, 'amount', w[3]::numeric)),
      pg_temp.t478_sources(inv, w[3]::numeric), '[]'::jsonb, 'T478 sessions by line', gen_random_uuid());
  when 'legacy' then
    update invoices set status = w[2]::invoice_status where id = inv;
  when 'repair' then perform repair_credit_package_progress_lots();
  else raise exception 'T478: unknown step %', p_st;
  end case;
  perform pg_temp.t478_commit();
  return null;
exception when others then
  return btrim(p_st) || ': ' || sqlerrm;
end $f$;
-- What a case ends with: the invoice's status and money, who holds what
-- (credit, '/n' held vouchers), the plans' codes and refund due (Cancel's
-- refund due; Refund in full's amount), the refusal that stopped it, what is
-- wrong with its credit, and the credit Cancel would leave behind.
create function pg_temp.t478_outcome(p_pre text, p_err text) returns jsonb language sql as $f$
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
              from t478 t where t.k like p_pre || '/%' and split_part(t.k, '/', 4) = ''
                and split_part(t.k, '/', 3) !~ '^(inv|inv2|S[0-9]+|D[0-9]+|err)$'),
    'cancel', pg_temp.t478_codes(i.id, 'cancel'),
    'due', pg_temp.t478_due(i.id, 'cancel'),
    'refund', pg_temp.t478_codes(i.id, 'refund_full'),
    'rdue', pg_temp.t478_due(i.id, 'refund_full'),
    'error', p_err,
    'invariants', pg_temp.t478_invariants(i.id),
    'cancel_left', pg_temp.t478_cancel_left(i.id))
    from (select pg_temp.t478_id(p_pre || '/inv') as id) i $f$;

-- ── The readings: the Reopen dialog, and what the reopening gives ───────────
-- Each Reopen of a case: the dialog read just before it, as the Finance panel
-- reads it (invoice_reopen_preview: every figure it shows; 478's figure,
-- 'credit_released_on_reopen', null where the key is not there, and the
-- explanation), what the Reopen left waiting (or gave back at once,
-- reopened straight to paid: 474's 'queued'), and (478) the credit the
-- Reopen itself gave at once for package and bundle lines: the paid credit
-- release_credit_package_paid_credit granted (the lots of the invoice's
-- release records) and what a settlement at the Reopen granted (the sale
-- records' lots), with what trim_released_paid_credit took back at it.
create temp table t478_dlg(pre text, n int, shown numeric, shownv int, shows int, total numeric, net numeric, required numeric,
                           can boolean, preview jsonb, queued numeric, queuedv int,
                           shownr numeric, expl text, atonce numeric, trimmed numeric,
                           -- 478 (answer E): the bundle's vouchers at once, to choose later, the
                           -- settling payment's credit, the receivers, the invoice's customer then
                           shownvo int, shownao int, shownl numeric, rcv jsonb, cust uuid,
                           -- 478 (answer E as ticked, the vouchers): a package's reward units at
                           -- once; the bundle's vouchers, those to choose later and a package's
                           -- reward units from the settling payment
                           shownru int, shownsv int, shownsa int, shownsu int, primary key (pre, n));
-- The explanation as 474 wrote it, and 478's sentence for credit given at once.
create function pg_temp.t478_expl474() returns text language sql as $f$
  select 'Existing refunds remain recorded. Only net unrefunded payments settle the reopened invoice. Previously revoked credit is reinstated once the reopened invoice is fully settled.'::text $f$;
create function pg_temp.t478_expl478() returns text language sql as $f$
  select 'Existing refunds remain recorded. Only net unrefunded payments settle the reopened invoice. Package or bundle credit the net payments already pay for is released at once when the invoice is reopened. Previously revoked credit is reinstated once the reopened invoice is fully settled.'::text $f$;
-- What each step gave back: credit (the payment's 'Reopened invoice settled'
-- rows, apply_reopened_invoice_benefits), voucher units given again
-- (apply_reopened_invoice_vouchers) and sessions reinstated
-- (trg_create_therapy_sessions_on_paid).
create temp table t478_gift(pre text, n int, credit numeric, vouchers int, sessions int, primary key (pre, n));
-- A case's steps p_from to p_to (all by default), stopping at a refusal;
-- with p_to null, its outcome (kept in t478_res under p_phase): 471's, and
-- the dialog's (t478_dialog).
create temp table t478_err(pre text primary key, err text);
-- 478: the credit granted since ledger row p_seq for the invoice's package
-- and bundle lines (its release records' lots: released as paid; its sale
-- records' lots: given at settlement; the grants of a package's or bundle's
-- own source, not a reissue such as 460's, which a sale record can name
-- once it moved the credit on), and what trim_released_paid_credit took
-- back since then.
create function pg_temp.t478_atonce(p_inv uuid, p_seq bigint) returns numeric language sql as $f$
  select coalesce(sum(e.amount), 0) from customer_credit_ledger e
   where e.entry_seq > p_seq and e.entry_type = 'grant' and e.source_type in ('credit_package', 'premium_bundle')
     and (e.lot_id in (select pl.lot_id from credit_package_progress_lots pl where pl.invoice_id = p_inv)
          or e.lot_id in (select x from credit_package_sales s, unnest(array[s.credit_lot_id, s.bonus_credit_lot_id]) x where s.invoice_id = p_inv)
          or e.lot_id in (select x from premium_bundle_sales s, unnest(array[s.paid_credit_lot_id, s.bonus_credit_lot_id]) x where s.invoice_id = p_inv)) $f$;
create function pg_temp.t478_trimmed(p_inv uuid, p_seq bigint) returns numeric language sql as $f$
  select coalesce(sum(e.amount), 0) from customer_credit_ledger e
   where e.entry_seq > p_seq and e.source_type = 'invoice_payment_released_credit' and e.source_record_id = p_inv $f$;
-- 478 (answer E): what each customer got at a step (p_n): the credit
-- granted on the invoice's package and bundle lots (its release records'
-- lots and its sale records' lots: released as paid, or given at
-- settlement, the Bonus included), the vouchers a bundle's settlement gave
-- (chosen at the till) and its allowance to choose later, the reward units
-- a package's settlement gave, and the credit the reopening queue gave back
-- (to the customer of the lot it went back on, or, where 460's rule moved
-- that lot's credit on, of the lot it was moved to). p_sales and p_ents: the
-- bundle sales and the entitlements the invoice had before the step.
create temp table t478_got(pre text, n int, cust uuid, credit numeric, vouchers int, allowance int, units int, back numeric,
                           primary key (pre, n, cust));
create function pg_temp.t478_take(p_pre text, p_n int, p_inv uuid, p_seq bigint, p_sales uuid[], p_ents uuid[])
  returns void language sql as $f$
  insert into t478_got(pre, n, cust, credit, vouchers, allowance, units, back)
  select p_pre, p_n, x.cust, sum(x.credit), sum(x.vouchers)::int, sum(x.allowance)::int, sum(x.units)::int, sum(x.back)
    from (
      select e.customer_id as cust, e.amount as credit, 0 as vouchers, 0 as allowance, 0 as units, 0::numeric as back
        from customer_credit_ledger e
       where e.entry_seq > p_seq and e.entry_type = 'grant' and e.source_type in ('credit_package', 'premium_bundle')
         and (e.lot_id in (select pl.lot_id from credit_package_progress_lots pl where pl.invoice_id = p_inv)
              or e.lot_id in (select x from credit_package_sales s, unnest(array[s.credit_lot_id, s.bonus_credit_lot_id]) x where s.invoice_id = p_inv)
              or e.lot_id in (select x from premium_bundle_sales s, unnest(array[s.paid_credit_lot_id, s.bonus_credit_lot_id]) x where s.invoice_id = p_inv))
      union all
      select v.customer_id, 0, v.quantity, 0, 0, 0 from customer_reward_vouchers v
       where v.source_type = 'premium_bundle'
         and v.source_id in (select s.id from premium_bundle_sales s where s.invoice_id = p_inv and not (s.id = any (coalesce(p_sales, '{}'))))
      union all
      select t.customer_id, 0, 0, case when t.earner_kind = 'premium_bundle' then t.voucher_qty else 0 end,
             case when t.earner_kind = 'credit_package' then 1 else 0 end, 0
        from therapy_entitlements t
       where t.claim_source_invoice_id = p_inv and t.entitlement_kind = 'voucher' and t.earner_kind in ('premium_bundle', 'credit_package')
         and not (t.id = any (coalesce(p_ents, '{}')))
      union all
      select coalesce((select nl.customer_id from customer_credit_ledger gi join customer_credit_lots nl on nl.id = gi.lot_id
                        where gi.entry_seq > p_seq and gi.source_type = 'invoice_reopen_reassignment_in' and gi.source_record_id = p_inv
                          and e.lot_id = any (credit_lot_ancestry(nl.id))
                          and exists (select 1 from customer_credit_ledger go where go.entry_seq > p_seq and go.lot_id = e.lot_id
                                       and go.source_type = 'invoice_reopen_reassignment_out' and go.source_record_id = p_inv)
                        order by gi.entry_seq limit 1),
                      (select l.customer_id from customer_credit_lots l where l.id = e.lot_id)), 0, 0, 0, 0, e.amount
        from customer_credit_ledger e
       where e.entry_seq > p_seq and e.entry_type = 'reverse' and e.source_type = 'invoice_reopen' and e.reason = 'Reopened invoice settled'
         and e.reverses_entry_id in (select q.source_ledger_id from invoice_reopen_benefits q where q.invoice_id = p_inv)) x
   where x.cust is not null
   group by x.cust
  on conflict (pre, n, cust) do update set credit = excluded.credit, vouchers = excluded.vouchers, allowance = excluded.allowance,
    units = excluded.units, back = excluded.back $f$;
-- A customer's role in a case ('A', 'B', 'K', 'F', ...; '?' when none).
create function pg_temp.t478_role_of(p_pre text, p_cust uuid) returns text language sql as $f$
  select coalesce((select split_part(t.k, '/', 3) from t478 t
                    where t.k like p_pre || '/%' and t.id = p_cust and split_part(t.k, '/', 4) = ''
                      and split_part(t.k, '/', 3) !~ '^(inv|inv2|S[0-9]+|D[0-9]+|err)$'
                    order by t.k limit 1), '?') $f$;
-- One receiver, as 'rcv' and 'got' write it: role, '*' for the invoice's
-- customer, then credit at once / bundle vouchers given at once / to choose
-- later / credit from the settling payment / credit reinstated after
-- settlement; and, where any is above 0, '|' reward units given at once /
-- bundle vouchers from the settling payment / to choose later from it /
-- reward units from it ('A*:20.00/0/0/100.00/0.00|0/2/0/0').
create function pg_temp.t478_fmt(p_role text, p_own boolean, p_at numeric, p_v int, p_a int, p_later numeric, p_back numeric,
                                 p_u int default 0, p_lv int default 0, p_la int default 0, p_lu int default 0)
  returns text language sql as $f$
  select p_role || case when p_own then '*' else '' end || ':' || coalesce(p_at, 0)::numeric(12,2)::text || '/' || coalesce(p_v, 0)::text
         || '/' || coalesce(p_a, 0)::text || '/' || coalesce(p_later, 0)::numeric(12,2)::text || '/' || coalesce(p_back, 0)::numeric(12,2)::text
         || case when coalesce(p_u, 0) > 0 or coalesce(p_lv, 0) > 0 or coalesce(p_la, 0) > 0 or coalesce(p_lu, 0) > 0
                 then '|' || coalesce(p_u, 0)::text || '/' || coalesce(p_lv, 0)::text || '/' || coalesce(p_la, 0)::text || '/' || coalesce(p_lu, 0)::text
                 else '' end $f$;
-- The dialog's receivers (the preview's 'credit_receivers'), by role; null
-- where the preview has no such key.
create function pg_temp.t478_rcv(p_pre text, p_rcv jsonb) returns text language sql as $f$
  select case when p_rcv is null or jsonb_typeof(p_rcv) <> 'array' then null else
    coalesce((select string_agg(pg_temp.t478_fmt(pg_temp.t478_role_of(p_pre, (r->>'customer_id')::uuid), (r->>'invoice_customer')::boolean,
                                                 (r->>'credit_released_on_reopen')::numeric, (r->>'bundle_vouchers_given_on_reopen')::int,
                                                 (r->>'bundle_vouchers_to_choose_on_reopen')::int, (r->>'credit_from_settling_payment')::numeric,
                                                 (r->>'credit_to_reinstate_after_settlement')::numeric,
                                                 (r->>'reward_units_given_on_reopen')::int, (r->>'bundle_vouchers_from_settling_payment')::int,
                                                 (r->>'bundle_vouchers_to_choose_from_settling_payment')::int,
                                                 (r->>'reward_units_from_settling_payment')::int),
                                ' ' order by pg_temp.t478_role_of(p_pre, (r->>'customer_id')::uuid))
                from jsonb_array_elements(p_rcv) r), '') end $f$;
-- What was given, as the dialog's receivers say it: at the case's last
-- Reopen (credit, vouchers, the allowance, a package's reward units), what
-- the steps after it gave (credit, vouchers, the allowance, reward units),
-- and the credit the queue gave back from it on; each customer with
-- something, by role ('*' the invoice's customer at that Reopen).
create function pg_temp.t478_got_text(p_pre text) returns text language sql as $f$
  with n0 as (select max(n) as n from t478_dlg where pre = p_pre and atonce is not null),
  g as (select x.cust, sum(case when x.n = n0.n then x.credit else 0 end) as at_once,
               sum(case when x.n = n0.n then x.vouchers else 0 end)::int as v,
               sum(case when x.n = n0.n then x.allowance else 0 end)::int as a,
               sum(case when x.n > n0.n then x.credit else 0 end) as later, sum(x.back) as back,
               sum(case when x.n = n0.n then x.units else 0 end)::int as u,
               sum(case when x.n > n0.n then x.vouchers else 0 end)::int as lv,
               sum(case when x.n > n0.n then x.allowance else 0 end)::int as la,
               sum(case when x.n > n0.n then x.units else 0 end)::int as lu
          from t478_got x, n0 where x.pre = p_pre and x.n >= n0.n group by x.cust)
  select case when (select n from n0) is null then null else
    coalesce((select string_agg(pg_temp.t478_fmt(pg_temp.t478_role_of(p_pre, g.cust),
                                                 g.cust = (select d.cust from t478_dlg d, n0 where d.pre = p_pre and d.n = n0.n),
                                                 g.at_once, g.v, g.a, g.later, g.back, g.u, g.lv, g.la, g.lu), ' ' order by pg_temp.t478_role_of(p_pre, g.cust))
                from g where g.at_once > 0 or g.v > 0 or g.a > 0 or g.later > 0 or g.back > 0
                          or g.u > 0 or g.lv > 0 or g.la > 0 or g.lu > 0), '') end $f$;
-- What was given that 474's dialog does not show (at the last Reopen and
-- after it): credit, vouchers or reward units at once, credit, vouchers or
-- reward units from the settling payment, anything to a customer other than
-- the invoice's.
create function pg_temp.t478_unsaid(p_pre text) returns text language sql as $f$
  with n0 as (select max(n) as n from t478_dlg where pre = p_pre and atonce is not null),
  c as (select d.cust from t478_dlg d, n0 where d.pre = p_pre and d.n = n0.n),
  g as (select x.cust, sum(case when x.n = n0.n then x.credit else 0 end) as at_once,
               sum(case when x.n = n0.n then x.vouchers + x.allowance else 0 end) as v,
               sum(case when x.n = n0.n then x.units else 0 end) as u,
               sum(case when x.n > n0.n then x.credit else 0 end) as later,
               sum(case when x.n > n0.n then x.vouchers + x.allowance else 0 end) as lv,
               sum(case when x.n > n0.n then x.units else 0 end) as lu, sum(x.back) as back
          from t478_got x, n0 where x.pre = p_pre and x.n >= n0.n group by x.cust)
  select coalesce(string_agg(concat_ws(' ', pg_temp.t478_role_of(p_pre, g.cust) || ':',
                    case when g.at_once > 0 then 'credit at once' end, case when g.v > 0 then 'vouchers at once' end,
                    case when g.u > 0 then 'reward units at once' end,
                    case when g.later > 0 then 'credit from the settling payment' end,
                    case when g.lv > 0 then 'vouchers from the settling payment' end,
                    case when g.lu > 0 then 'reward units from the settling payment' end,
                    case when g.cust is distinct from (select cust from c) then 'not the invoice''s customer' end),
                  '; ' order by pg_temp.t478_role_of(p_pre, g.cust)), '')
    from g
   where g.at_once > 0 or g.v > 0 or g.u > 0 or g.later > 0 or g.lv > 0 or g.lu > 0
      or (g.back > 0 and g.cust is distinct from (select cust from c)) $f$;
-- Each Reopen whose receivers' at-once parts (credit, vouchers, the
-- allowance, a package's reward units) are not what it gave at once to each
-- customer.
create function pg_temp.t478_everyrc(p_pre text) returns text language sql as $f$
  select coalesce(string_agg(format('%s: %s shown, %s given', d.n, coalesce(x.shown, 'none'), x.given), '; ' order by d.n), '')
    from t478_dlg d
    cross join lateral (
      select (select string_agg(pg_temp.t478_role_of(p_pre, (r->>'customer_id')::uuid) || ':' || (r->>'credit_released_on_reopen')::numeric(12,2)::text
                                || '/' || (r->>'bundle_vouchers_given_on_reopen') || '/' || (r->>'bundle_vouchers_to_choose_on_reopen')
                                || '/' || coalesce(r->>'reward_units_given_on_reopen', '0'),
                                ' ' order by pg_temp.t478_role_of(p_pre, (r->>'customer_id')::uuid))
                from jsonb_array_elements(case when jsonb_typeof(d.rcv) = 'array' then d.rcv else '[]'::jsonb end) r
               where (r->>'credit_released_on_reopen')::numeric > 0 or (r->>'bundle_vouchers_given_on_reopen')::int > 0
                  or (r->>'bundle_vouchers_to_choose_on_reopen')::int > 0 or coalesce((r->>'reward_units_given_on_reopen')::int, 0) > 0) as shown,
             coalesce((select string_agg(pg_temp.t478_role_of(p_pre, g.cust) || ':' || g.credit::numeric(12,2)::text || '/' || g.vouchers || '/' || g.allowance
                                         || '/' || g.units,
                                         ' ' order by pg_temp.t478_role_of(p_pre, g.cust))
                         from t478_got g where g.pre = p_pre and g.n = d.n and (g.credit > 0 or g.vouchers > 0 or g.allowance > 0 or g.units > 0)), '') as given) x
   where d.pre = p_pre and d.atonce is not null and coalesce(x.shown, '') <> x.given $f$;
create function pg_temp.t478_dialog(p_pre text) returns jsonb language sql as $f$
  with l as (select * from t478_dlg where pre = p_pre order by n desc limit 1)
  select jsonb_build_object(
    'reopens', (select count(*) from t478_dlg where pre = p_pre),
    'dlg', (select shown from l), 'dlgv', (select shownv from l), 'dlgs', (select shows from l),
    'required', (select required from l),
    'queued', (select queued from l), 'queuedv', (select queuedv from l),
    'gave', (select coalesce(sum(g.credit), 0) from t478_gift g, l where g.pre = p_pre and g.n >= l.n),
    'gavev', (select coalesce(sum(g.vouchers), 0) from t478_gift g, l where g.pre = p_pre and g.n >= l.n),
    'gaves', (select coalesce(sum(g.sessions), 0) from t478_gift g, l where g.pre = p_pre and g.n >= l.n),
    'every', (select coalesce(string_agg(format('%s: %s shown, %s queued', d.n, d.shown, d.queued), '; ' order by d.n), '')
                from t478_dlg d where d.pre = p_pre and d.queued is not null
                 and (d.shown is distinct from d.queued or d.shownv is distinct from d.queuedv)),
    -- 478: its figure at the last Reopen (null: not in the dialog), what that
    -- Reopen gave at once, each Reopen whose figure (none counted as S$0.00)
    -- is not what it gave at once, the explanation at the last Reopen ('474'
    -- its text, '478' with 478's sentence), and what any Reopen trimmed.
    'dlgr', (select shownr from l), 'atonce', (select atonce from l),
    'everyr', (select coalesce(string_agg(format('%s: %s shown, %s at once', d.n, coalesce(d.shownr::text, 'none'), d.atonce), '; ' order by d.n), '')
                 from t478_dlg d where d.pre = p_pre and d.atonce is not null and coalesce(d.shownr, 0) <> d.atonce),
    'expl', (select case when expl = pg_temp.t478_expl474() then '474' when expl = pg_temp.t478_expl478() then '478' else expl end from l),
    'trimmed', (select coalesce(sum(d.trimmed), 0) from t478_dlg d where d.pre = p_pre),
    -- 478 (answer E): at the last Reopen, the bundle's vouchers given at once
    -- and to choose later, the settling payment's credit and the receivers
    -- (null: not in the dialog); what was given, the same way; each Reopen
    -- whose receivers' at-once parts are not what it gave; and what was given
    -- that 474's dialog does not show.
    'dlgvo', (select shownvo from l), 'dlgao', (select shownao from l), 'dlgl', (select shownl from l),
    -- 478 (answer E as ticked): a package's reward units at once, and the
    -- bundle's vouchers, those to choose later and a package's reward units
    -- from the settling payment, at the last Reopen (null: not in the dialog)
    'dlgru', (select shownru from l), 'dlgsv', (select shownsv from l), 'dlgsa', (select shownsa from l),
    'dlgsu', (select shownsu from l),
    'rcv', (select pg_temp.t478_rcv(p_pre, l.rcv) from l),
    'got', pg_temp.t478_got_text(p_pre),
    'everyrc', pg_temp.t478_everyrc(p_pre),
    'unsaid', pg_temp.t478_unsaid(p_pre)) $f$;
create function pg_temp.t478_run(p_phase text, p_case text, p_steps text, p_from int default 1, p_to int default null)
  returns jsonb language plpgsql as $f$
declare v_pre text := p_phase || '/' || p_case; st text[] := string_to_array(p_steps, ';'); i int; v_err text; v_out jsonb;
  inv uuid; pv jsonb; seq bigint; av uuid[]; ass uuid[]; g numeric; gv int; gs int; sales uuid[]; ents uuid[];
begin
  v_err := (select e.err from t478_err e where e.pre = v_pre);
  for i in p_from .. least(coalesce(p_to, cardinality(st)), cardinality(st)) loop
    exit when v_err is not null;
    continue when btrim(st[i]) = '';
    inv := pg_temp.t478_id(v_pre || '/inv');
    if inv is not null and btrim(st[i]) = 'reopen' then
      pv := invoice_reopen_preview(inv);
      insert into t478_dlg(pre, n, shown, shownv, shows, total, net, required, can, preview, shownr, expl,
                           shownvo, shownao, shownl, rcv, cust, shownru, shownsv, shownsa, shownsu)
      values (v_pre, i, (pv->>'credit_to_reinstate_after_settlement')::numeric, (pv->>'voucher_units_to_reinstate_after_settlement')::int,
              coalesce((pv->>'sessions_to_reinstate_after_settlement')::int, 0), (pv->>'total')::numeric, (pv->>'net_received')::numeric,
              greatest(0, (pv->>'total')::numeric - (pv->>'net_received')::numeric), (pv->>'can_reopen')::boolean, pv,
              (pv->>'credit_released_on_reopen')::numeric, pv->>'explanation',
              (pv->>'bundle_vouchers_given_on_reopen')::int, (pv->>'bundle_vouchers_to_choose_on_reopen')::int,
              (pv->>'credit_from_settling_payment')::numeric, pv->'credit_receivers', (select customer_id from invoices where id = inv),
              (pv->>'reward_units_given_on_reopen')::int, (pv->>'bundle_vouchers_from_settling_payment')::int,
              (pv->>'bundle_vouchers_to_choose_from_settling_payment')::int, (pv->>'reward_units_from_settling_payment')::int)
      on conflict (pre, n) do nothing;
    end if;
    select coalesce(max(entry_seq), 0) into seq from customer_credit_ledger;
    select array_agg(id) into av from invoice_reopen_vouchers where invoice_id = inv and applied_at is not null;
    select array_agg(id) into ass from invoice_reopen_sessions where invoice_id = inv and applied_at is not null;
    select array_agg(id) into sales from premium_bundle_sales where invoice_id = inv;
    select array_agg(id) into ents from therapy_entitlements where claim_source_invoice_id = inv;
    v_err := pg_temp.t478_step(v_pre, st[i]);
    inv := pg_temp.t478_id(v_pre || '/inv');
    perform pg_temp.t478_take(v_pre, i, inv, seq, sales, ents);
    g := (select coalesce(sum(e.amount), 0) from customer_credit_ledger e
           where e.entry_seq > seq and e.entry_type = 'reverse' and e.source_type = 'invoice_reopen' and e.reason = 'Reopened invoice settled'
             and e.reverses_entry_id in (select q.source_ledger_id from invoice_reopen_benefits q where q.invoice_id = inv));
    gv := (select coalesce(sum(q.quantity), 0) from invoice_reopen_vouchers q where q.invoice_id = inv and q.applied_at is not null
             and q.replacement_voucher_id is not null and not (q.id = any (coalesce(av, '{}'))));
    gs := (select coalesce(sum(q.quantity), 0) from invoice_reopen_sessions q where q.invoice_id = inv and q.applied_at is not null
             and not (q.id = any (coalesce(ass, '{}'))));
    insert into t478_gift values (v_pre, i, g, gv, gs)
      on conflict (pre, n) do update set credit = excluded.credit, vouchers = excluded.vouchers, sessions = excluded.sessions;
    if btrim(st[i]) = 'reopen' and v_err is null then
      update t478_dlg set queued = g + (select coalesce(sum(q.amount), 0) from invoice_reopen_benefits q where q.invoice_id = inv and q.applied_at is null),
                          queuedv = gv + (select coalesce(sum(q.quantity), 0) from invoice_reopen_vouchers q where q.invoice_id = inv and q.applied_at is null),
                          atonce = pg_temp.t478_atonce(inv, seq), trimmed = pg_temp.t478_trimmed(inv, seq)
       where pre = v_pre and n = i;
    end if;
  end loop;
  insert into t478_err values (v_pre, v_err) on conflict (pre) do update set err = excluded.err;
  if p_to is not null then return null; end if;
  v_out := pg_temp.t478_outcome(v_pre, v_err) || pg_temp.t478_dialog(v_pre);
  insert into t478_res values (p_phase, p_case, v_out) on conflict (phase, k) do update set v = excluded.v;
  return v_out;
end $f$;
-- Whether an outcome has what is expected: each key equal ('holds' as a
-- containment of who holds what), a key ending in '~' as a LIKE pattern of
-- that key's text.
create function pg_temp.t478_meets(p_out jsonb, p_exp jsonb) returns boolean language sql as $f$
  select coalesce(bool_and(case
           when e.key like '%~' then coalesce(p_out->>left(e.key, -1), '') like (e.value #>> '{}')
           when e.key = 'holds' then coalesce(p_out->'holds', '{}') @> e.value
           when jsonb_typeof(e.value) = 'number' then coalesce((p_out->>e.key)::numeric = (e.value #>> '{}')::numeric, false)
           else (p_out->e.key) is not distinct from e.value end), true)
    from jsonb_each(p_exp) e $f$;
-- What differs between an outcome and what is expected (for the FAIL line).
create function pg_temp.t478_diff(p_out jsonb, p_exp jsonb) returns text language sql as $f$
  select string_agg(e.key || ': wanted ' || e.value::text || ', got ' || coalesce(p_out->left(e.key, case when e.key like '%~' then -1 else 1000 end), 'null')::text, '; ')
    from jsonb_each(p_exp) e where not pg_temp.t478_meets(p_out, jsonb_build_object(e.key, e.value)) $f$;
-- An outcome without the dialog's figure and explanation (what 478 changes),
-- for A against R: every other key as before 478.
create function pg_temp.t478_but_dialog(p_out jsonb) returns jsonb language sql as $f$
  select p_out - 'dlgr' - 'everyr' - 'expl' - 'dlgvo' - 'dlgao' - 'dlgl' - 'rcv' - 'everyrc' - 'dlgru' - 'dlgsv' - 'dlgsa' - 'dlgsu' $f$;
-- 478's keys of the preview.
create function pg_temp.t478_keys() returns text[] language sql as $f$
  select array['credit_released_on_reopen', 'bundle_vouchers_given_on_reopen', 'bundle_vouchers_to_choose_on_reopen',
               'credit_from_settling_payment', 'credit_receivers', 'reward_units_given_on_reopen',
               'bundle_vouchers_from_settling_payment', 'bundle_vouchers_to_choose_from_settling_payment',
               'reward_units_from_settling_payment'] $f$;
-- The unapplied reopening queue of an invoice (credit).
create function pg_temp.t478_waiting(p_inv uuid) returns numeric language sql as $f$
  select coalesce(sum(q.amount), 0) from invoice_reopen_benefits q where q.invoice_id = p_inv and q.applied_at is null $f$;
-- Who may call a function (the set) and the whole grant list (by name).
create function pg_temp.t478_grants() returns text language sql as $f$
  select md5(string_agg(p.oid::regprocedure::text || '=' || coalesce(p.proacl::text, 'null'), '|' order by p.oid::regprocedure::text))
    from pg_proc p where p.pronamespace = 'public'::regnamespace $f$;
create function pg_temp.t478_grant_set(p_sig text) returns text[] language sql as $f$
  select array_agg(x::text order by x::text) from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || p_sig) $f$;

-- The function 478 changes: BEFORE (474's AFTER, as 475 to 477 pinned it)
-- and AFTER.
create temp table t478_md5(sig text primary key, before text, after text);
insert into t478_md5 values
  ('invoice_reopen_preview_before_sessions(uuid)', '7e1ef2d25415e69b3f770fe2efd45190', 'acbfc38a20a000e1af0e78d26fc7fc4c');
create function pg_temp.t478_at(p_col text) returns boolean language sql as $f$
  select bool_and(md5(pg_get_functiondef(to_regprocedure('public.' || m.sig))) = case when p_col = 'before' then m.before else m.after end)
    from t478_md5 m $f$;
insert into t478_fp values ('start', pg_temp.t478_fingerprint()), ('grants', pg_temp.t478_grants());

-- The read-only query in 478's header (the same text, taken from the file
-- when this suite was written).
create function pg_temp.t478_header_query() returns table(reason text, invoice_no text, n bigint) language sql as $hq$
with
-- Credit Package and Premium Bundle lines of cancelled or refunded invoices
-- (the Reopen dialog is offered for them), in the order the money toward
-- them is counted (credit_package_money_toward_line)
l as (
  select i.id as invoice_id, i.customer_id, i.store_id, x.id, x.line_kind, x.credit_package_id, x.premium_bundle_id,
         x.credit_issued_at is null as unsettled,
         (x.credit_split_allocation_id is not null or x.bundle_split_allocation_id is not null
          or exists (select 1 from public.invoice_credit_splits c where c.invoice_item_id = x.id)) as split,
         public.invoice_item_external_value(x.id) as line_value,
         (select min(pl.created_at) from public.credit_package_progress_lots pl where pl.invoice_item_id = x.id) as first_release,
         public.invoice_net_received(i.id) as n,
         (i.total_amount = 0 and i.has_foc) or public.invoice_net_received(i.id) >= i.total_amount as settles
    from public.invoices i join public.invoice_items x on x.invoice_id = i.id
   where i.deleted_at is null and i.status::text in ('cancelled', 'refunded') and i.customer_id is not null
     and x.line_kind in ('credit_package', 'premium_bundle')),
q as (
  select l.*, coalesce(sum(l.line_value) over (partition by l.invoice_id order by l.unsettled, l.first_release nulls last, l.id
                                               rows between unbounded preceding and 1 preceding), 0) as ahead
    from l),
-- for each line, as 478's preview works them out: what a reopening gives at
-- once, what the payment that settles it gives, a bundle's free vouchers
-- given at once or with the settling payment, a package's reward units, and
-- to whom; and the released credit it still counts above what the net
-- payments buy
r as (
  select q.invoice_id, q.customer_id, q.id, q.unsettled, q.split, q.settles,
         case when q.settles then greatest(round(e.entitled - e.released, 2), 0) + e.bonus
              when e.entitled > 0 then greatest(round(e.bought - e.released, 2), 0) else 0 end as at_once,
         case when q.settles then 0
              else greatest(round(e.entitled - case when e.entitled > 0 then greatest(e.released, e.bought) else e.released end, 2), 0)
                   + e.bonus end as later,
         case when q.settles and q.line_kind = 'premium_bundle'
              then coalesce((select pb.free_voucher_qty from public.premium_bundles pb where pb.id = q.premium_bundle_id), 0)
              else 0 end as vouchers,
         case when not q.settles and q.line_kind = 'premium_bundle'
              then coalesce((select pb.free_voucher_qty from public.premium_bundles pb where pb.id = q.premium_bundle_id), 0)
              else 0 end as later_vouchers,
         case when q.line_kind = 'credit_package'
              then coalesce((select case when coalesce(pk.grants_reward, false) and u.qual > 0
                                         then floor(coalesce(pk.customer_price, 0) / u.qual)::int else 0 end
                               from public.credit_packages pk
                               cross join lateral (select coalesce(pk.reward_qualifying_amount,
                                                                   (public.legacy_lowest_rule(q.store_id, public.sg_today())).qualifying_amount, 994) as qual) u
                              where pk.id = q.credit_package_id and pk.deleted_at is null), 0)
              else 0 end as units,
         round(e.released - e.bought, 2) as above,
         case when q.unsettled and not q.split then coalesce(public.credit_line_benefits_holder(q.id), q.customer_id) end as receiver
    from q cross join lateral (
      select x.entitled, x.released, least(least(greatest(q.n - q.ahead, 0), q.line_value), x.entitled) as bought,
             case when q.line_kind = 'credit_package'
                  then greatest(coalesce(public.credit_package_bonus_amount(q.credit_package_id), 0), 0)
                  else greatest(coalesce((select pb.bonus_credit_amount from public.premium_bundles pb where pb.id = q.premium_bundle_id), 0), 0) end as bonus
        from (select public.credit_line_paid_entitlement(q.id) as entitled,
                     public.credit_package_released_paid_credit(q.id) as released) x) e),
-- the credit to reinstate after settlement (474's figure), row by row: each
-- ledger row's credit goes back on its lot, grouped by the lot a benefit row
-- of the invoice names whose chain holds it, and on to that group's holder
-- (apply_reopened_invoice_benefits, as 478's preview reads it)
w as (
  select i.id as invoice_id, i.customer_id, lg.lot_id, lg.amount
    from public.invoices i
    join public.customer_credit_ledger lg
      on lg.source_type = 'invoice_cancel_benefit' and lg.source_record_id = i.id
         or lg.source_type = 'invoice_benefit_refund'
            and exists (select 1 from public.invoice_refunds f where f.invoice_id = i.id and f.request_id = lg.source_record_id)
   where i.deleted_at is null and i.status::text in ('cancelled', 'refunded') and i.customer_id is not null
     and not exists (select 1 from public.invoice_reopen_benefits rb where rb.source_ledger_id = lg.id)
  union all
  select i.id, i.customer_id, lg.lot_id, rb.amount
    from public.invoices i
    join public.invoice_reopen_benefits rb on rb.invoice_id = i.id and rb.applied_at is null
    join public.customer_credit_ledger lg on lg.id = rb.source_ledger_id
   where i.deleted_at is null and i.status::text in ('cancelled', 'refunded') and i.customer_id is not null),
k as (
  select t.invoice_id, t.customer_id, t.target, sum(t.amount) as amount, array_agg(t.lot_id) as lots
    from (select w.*, coalesce((select bv.lot_id from public.invoice_benefit_values bv
                                 where bv.invoice_id = w.invoice_id and bv.lot_id is not null
                                   and w.lot_id = any (public.credit_lot_ancestry(bv.lot_id))
                                 order by (bv.lot_id = w.lot_id) desc, bv.created_at, bv.id limit 1), w.lot_id) as target
            from w) t
   group by t.invoice_id, t.customer_id, t.target),
bk as (
  select k.invoice_id, k.customer_id, k.amount,
         coalesce(public.invoice_credit_live_holder(k.invoice_id, tl.customer_id,
                    case when exists (select 1 from public.invoice_benefit_values bv
                                       where bv.invoice_id = k.invoice_id and bv.lot_id = tl.id
                                         and public.invoice_benefit_moved_to_other(bv.id)) then 'infinity'::timestamptz
                         else tl.created_at end),
                  (select c.id from public.customer_credit_lots pl join public.customers c on c.id = pl.customer_id
                    where pl.id = any (k.lots) and c.deleted_at is null order by pl.created_at, pl.id limit 1),
                  tl.customer_id) as receiver
    from k join public.customer_credit_lots tl on tl.id = k.target),
found(reason, invoice_id, n) as (
  select '1 changes: cancelled or refunded, with a package or bundle line paid in part whose reopening gives credit at once (released again, or the line settled where the net payments cover the invoice); from 478 the Reopen dialog shows it as "Credit released at once on reopening" and its explanation says so (the count is of lines)', r.invoice_id, count(*)
    from r where r.unsettled and not r.split and r.at_once > 0 group by r.invoice_id
  union all
  select '2 for the Owner (not changed by 478: NOT COVERED 1): cancelled or refunded, with a split package or bundle line not settled whose reopening would settle it at once (the net payments cover the invoice); the dialog''s figures do not count it (the count is of lines)', r.invoice_id, count(*)
    from r where r.unsettled and r.split and r.settles group by r.invoice_id
  union all
  select '3 for the Owner (not changed by 478: NOT COVERED 5): cancelled or refunded, with a package or bundle line paid in part whose released credit still counted is above what the net payments buy while one of its release lots holds credit; the reopening would take that credit back (trim_released_paid_credit), which the dialog does not show (the count is of lines)', r.invoice_id, count(*)
    from r
   where r.unsettled and not r.split and not r.settles and r.above > 0
     and exists (select 1 from public.credit_package_progress_lots pl
                   join public.customer_credit_lots cl on cl.id = public.credit_lot_current(pl.lot_id)
                  where pl.invoice_item_id = r.id and pl.released_amount > 0 and cl.status = 'active' and cl.remaining_amount > 0)
   group by r.invoice_id
  union all
  select '4 changes: cancelled or refunded, with a package or bundle line not settled that the reopening leaves to be paid: from 478 the Reopen dialog shows what the payment that settles it gives (its paid credit not yet released, and the Bonus) as "Credit the settling payment gives" (the count is of lines)', r.invoice_id, count(*)
    from r where r.unsettled and not r.split and not r.settles and r.later > 0 group by r.invoice_id
  union all
  select '5 changes: cancelled or refunded, with a Premium Bundle line the reopening would settle at once: from 478 the Reopen dialog shows the free vouchers it gives then, as "Bundle vouchers given at once on reopening" (the count is of lines)', r.invoice_id, count(*)
    from r where r.unsettled and not r.split and r.settles and r.vouchers > 0 group by r.invoice_id
  union all
  select '6 changes: cancelled or refunded, whose reopening or settling payment gives credit, a Bonus, vouchers or reward units, or whose credit to reinstate after settlement goes, to a customer other than the invoice''s (whoever holds the benefits: the buyer after a ''keep'' change, someone an Owner moved credit to): from 478 the Reopen dialog names them (the count is of customers)', x.invoice_id, count(distinct x.receiver)
    from (select r.invoice_id, r.customer_id, r.receiver from r
           where r.unsettled and not r.split and (r.at_once > 0 or r.later > 0 or r.vouchers > 0 or r.later_vouchers > 0 or r.units > 0)
          union all
          select bk.invoice_id, bk.customer_id, bk.receiver from bk where bk.amount > 0) x
   where x.receiver is distinct from x.customer_id
   group by x.invoice_id
  union all
  select '7 changes: cancelled or refunded, with a Premium Bundle line not settled that the reopening leaves to be paid (its free vouchers come with the settling payment), or a Credit Package line not settled that grants reward units (given at once where the reopening settles it, else with the settling payment): from 478 the Reopen dialog shows them, as "Vouchers the settling payment gives" and "Credit Package reward units given at once on reopening" (the count is of lines)', r.invoice_id, count(*)
    from r where r.unsettled and not r.split and (r.later_vouchers > 0 or r.units > 0) group by r.invoice_id)
select f.reason, i.invoice_no, f.n
  from found f join public.invoices i on i.id = f.invoice_id
 order by f.reason, i.invoice_no
$hq$;

-- The cases: (k, kind, steps, what 478 gives). kind: 'fixed' (before 478 a
-- Reopen of the case gives credit at once the dialog does not show: the
-- fault is reproduced first), 'control' (nothing given at once, before 478
-- and after: every key of the outcome but the figure, absent before 478 and
-- S$0.00 after). Every case also checks the invariants and that Cancel takes
-- everything back from whoever holds it.
create temp table t478_cases(k text primary key, kind text not null, steps text not null, expect jsonb not null, ord serial);
insert into t478_cases(k, kind, steps, expect) values
-- 474's K2: S$40 paid of S$100, S1 paid from it, cancelled: the reopening
-- gives A S$20 at once (S$40's credit less the S$20 spent); the S$60 payment
-- then gives the S$60 not released yet; paid, A S$80.
('PT0', 'fixed', 'sale A cp 40; spend A; cancel; reopen; pay',
  '{"dlgr":20,"atonce":20,"everyr":"","expl":"478","trimmed":0,"dlg":0,"required":60,"dlgvo":0,"dlgao":0,"dlgl":60,"rcv":"A*:20.00/0/0/60.00/0.00","holds":{"A":"80.00"},"status":"paid","net":100,"error":null}'),
-- Nothing spent; the Bonus package (the Bonus with the settling payment);
-- the Premium Bundle (its S$40 Bonus too, and its 2 vouchers, which the
-- settling payment gives: the second build's KNOWN K2a, now its own
-- figure); a S$20 discount (the entitlement S$80); two packages; beside a
-- therapy line.
('PTn', 'fixed', 'sale A cp 40; cancel; reopen; pay',
  '{"dlgr":40,"atonce":40,"everyr":"","expl":"478","trimmed":0,"dlg":0,"required":60,"dlgl":60,"rcv":"A*:40.00/0/0/60.00/0.00","holds":{"A":"100.00"},"status":"paid","net":100,"error":null}'),
('PTb', 'fixed', 'sale A cpb 40; spend A; cancel; reopen; pay',
  '{"dlgr":20,"atonce":20,"everyr":"","expl":"478","trimmed":0,"dlg":0,"required":60,"dlgl":70,"rcv":"A*:20.00/0/0/70.00/0.00","holds":{"A":"90.00"},"status":"paid","net":100,"error":null}'),
('PTv', 'fixed', 'sale A pbv 40; spend A 1 bwallet; cancel; reopen; pay',
  '{"dlgr":20,"atonce":20,"everyr":"","expl":"478","trimmed":0,"dlg":0,"required":100,"dlgvo":0,"dlgao":0,"dlgl":100,"dlgru":0,"dlgsv":2,"dlgsa":0,"dlgsu":0,"rcv":"A*:20.00/0/0/100.00/0.00|0/2/0/0","holds":{"A":"120.00/2"},"status":"paid","net":140,"error":null}'),
('PTd', 'fixed', 'saledp A cp 20 40; spend A; cancel; reopen; pay',
  '{"dlgr":20,"atonce":20,"everyr":"","expl":"478","trimmed":0,"dlg":0,"required":40,"dlgl":40,"rcv":"A*:20.00/0/0/40.00/0.00","holds":{"A":"60.00"},"status":"paid","net":80,"error":null}'),
('PT2', 'fixed', 'sale A cp,cp 140; spend A; cancel; reopen; pay',
  '{"dlgr":120,"atonce":120,"everyr":"","expl":"478","trimmed":0,"dlg":0,"required":60,"dlgl":60,"rcv":"A*:120.00/0/0/60.00/0.00","holds":{"A":"180.00"},"status":"paid","net":200,"error":null}'),
('PTth', 'fixed', 'sale A th,cp 40; spend A; cancel; reopen; pay',
  '{"dlgr":20,"atonce":20,"everyr":"","expl":"478","trimmed":0,"dlg":0,"required":120,"dlgl":60,"rcv":"A*:20.00/0/0/60.00/0.00","holds":{"A":"80.00"},"status":"paid","net":160,"error":null}'),
('PTth2', 'fixed', 'sale A cp,th 120; spend A; cancel; reopen; pay',
  '{"dlgr":80,"atonce":80,"everyr":"","expl":"478","trimmed":0,"dlg":0,"required":40,"dlgl":0,"rcv":"A*:80.00/0/0/0.00/0.00","holds":{"A":"80.00"},"status":"paid","net":160,"error":null}'),
-- Released in two payments (S$20 and S$20; the bundle S$30 and S$30).
('PTp', 'fixed', 'sale A cp 20; payp 20; spend A; cancel; reopen; pay',
  '{"dlgr":20,"atonce":20,"everyr":"","expl":"478","trimmed":0,"dlg":0,"required":60,"dlgl":60,"rcv":"A*:20.00/0/0/60.00/0.00","holds":{"A":"80.00"},"status":"paid","net":100,"error":null}'),
('PTvp', 'fixed', 'sale A pbv 30; payp 30; spend A 1 bwallet; cancel; reopen; pay',
  '{"dlgr":40,"atonce":40,"everyr":"","expl":"478","trimmed":0,"dlg":0,"required":80,"dlgl":80,"dlgsv":2,"rcv":"A*:40.00/0/0/80.00/0.00|0/2/0/0","holds":{"A":"120.00/2"},"status":"paid","net":140,"error":null}'),
-- 478 (the Owner's answer E as ticked, 27 Oct 2026: "... plus the vouchers
-- and extra credit the payment will give"): the vouchers the settling
-- payment gives, beside its credit: the bundle with one voucher chosen at
-- the till and one to choose later (PTv1); after a 'keep' change, A's, whom
-- the dialog names (PTkvl); a Credit Package granting 2 reward units (a
-- unit for each S$50 of its S$100 price), settled at once by the reopening
-- after Correct payment raised its receipt (PTr2, the second build's KNOWN
-- K2b: its 2 units at once) or left to be paid (PTr2p: with the settling
-- payment); and after a 'keep' change (PTkr, PTkrp: A's, named).
('PTv1', 'fixed', 'sale A pbv1 40; spend A 1 bwallet; cancel; reopen; pay',
  '{"dlgr":20,"atonce":20,"everyr":"","expl":"478","trimmed":0,"dlg":0,"required":100,"dlgvo":0,"dlgao":0,"dlgl":100,"dlgru":0,"dlgsv":1,"dlgsa":1,"dlgsu":0,"rcv":"A*:20.00/0/0/100.00/0.00|0/1/1/0","holds":{"A":"120.00/1"},"status":"paid","net":140,"error":null}'),
('PTkvl', 'fixed', 'sale A pbv 40; change B keep; spend A 1 bwallet; cancel; reopen; pay',
  '{"dlgr":20,"atonce":20,"everyr":"","expl":"478","trimmed":0,"dlg":0,"required":100,"dlgl":100,"dlgsv":2,"dlgsa":0,"rcv":"A:20.00/0/0/100.00/0.00|0/2/0/0","holds":{"A":"120.00/2","B":"0.00"},"status":"paid","net":140,"error":null}'),
('PTr2', 'fixed', 'sale A cpr 40; spend A; cancel; raise 100; reopen',
  '{"dlgr":80,"atonce":80,"everyr":"","expl":"478","trimmed":0,"dlg":0,"required":0,"dlgl":0,"dlgru":2,"dlgsv":0,"dlgsa":0,"dlgsu":0,"rcv":"A*:80.00/0/0/0.00/0.00|2/0/0/0","holds":{"A":"80.00"},"status":"paid","net":100,"error":null}'),
('PTr2p', 'fixed', 'sale A cpr 40; spend A; cancel; reopen; pay',
  '{"dlgr":20,"atonce":20,"everyr":"","expl":"478","trimmed":0,"dlg":0,"required":60,"dlgl":60,"dlgru":0,"dlgsu":2,"rcv":"A*:20.00/0/0/60.00/0.00|0/0/0/2","holds":{"A":"80.00"},"status":"paid","net":100,"error":null}'),
('PTkr', 'fixed', 'sale A cpr 40; change B keep; spend A; cancel; raise 100; reopen',
  '{"dlgr":80,"atonce":80,"everyr":"","expl":"478","trimmed":0,"dlg":0,"required":0,"dlgl":0,"dlgru":2,"rcv":"A:80.00/0/0/0.00/0.00|2/0/0/0","holds":{"A":"80.00","B":"0.00"},"status":"paid","net":100,"error":null}'),
('PTkrp', 'fixed', 'sale A cpr 40; change B keep; spend A; cancel; reopen; pay',
  '{"dlgr":20,"atonce":20,"everyr":"","expl":"478","trimmed":0,"dlg":0,"required":60,"dlgl":60,"dlgsu":2,"rcv":"A:20.00/0/0/60.00/0.00|0/0/0/2","holds":{"A":"80.00","B":"0.00"},"status":"paid","net":100,"error":null}'),
-- Nothing ever paid towards it: cancelled unpaid, the payment that settles
-- it gives all its credit and its 2 reward units (PTnp).
('PTnp', 'fixed', 'sale A cpr 0; cancel; reopen; pay',
  '{"dlgr":0,"atonce":0,"everyr":"","expl":"474","trimmed":0,"dlg":0,"required":100,"dlgl":100,"dlgsu":2,"rcv":"A*:0.00/0/0/100.00/0.00|0/0/0/2","holds":{"A":"100.00"},"status":"paid","net":100,"error":null}'),
-- Cancelled again: each reopening gives at once; S$20 more paid while it
-- waited; a 'keep' change while it waited; S1 refunded while it waited; S2
-- spent after the first reopening (the second gives nothing at once); a
-- 'keep' change and S$20 more paid while it waited (A, not B, receives).
('PTq', 'fixed', 'sale A cp 40; spend A; cancel; reopen; cancel; reopen; pay',
  '{"dlgr":20,"atonce":20,"everyr":"","expl":"478","trimmed":0,"dlg":0,"required":60,"dlgl":60,"rcv":"A*:20.00/0/0/60.00/0.00","holds":{"A":"80.00"},"status":"paid","net":100,"error":null}'),
('PTqp', 'fixed', 'sale A cp 40; spend A; cancel; reopen; payp 20; cancel; reopen; pay',
  '{"dlgr":40,"atonce":40,"everyr":"","expl":"478","trimmed":0,"dlg":0,"required":40,"dlgl":40,"rcv":"A*:40.00/0/0/40.00/0.00","holds":{"A":"80.00"},"status":"paid","net":100,"error":null}'),
('PTqk', 'fixed', 'sale A cp 40; spend A; cancel; reopen; change B keep; cancel; reopen; pay',
  '{"dlgr":20,"atonce":20,"everyr":"","expl":"478","trimmed":0,"dlg":0,"required":60,"dlgl":60,"rcv":"A:20.00/0/0/60.00/0.00","holds":{"A":"80.00","B":"0.00"},"status":"paid","net":100,"error":null}'),
('PTuq', 'fixed', 'sale A cp 40; spend A; cancel; reopen; unspend S1; cancel; reopen; pay',
  '{"dlgr":40,"atonce":40,"everyr":"","expl":"478","trimmed":0,"dlg":0,"required":60,"dlgl":60,"rcv":"A*:40.00/0/0/60.00/0.00","holds":{"A":"100.00"},"status":"paid","net":100,"error":null}'),
('PTq2', 'fixed', 'sale A cp 40; spend A; cancel; reopen; spend A; cancel; reopen; pay',
  '{"dlgr":0,"atonce":0,"everyr":"","expl":"474","trimmed":0,"dlg":0,"required":60,"dlgl":60,"rcv":"A*:0.00/0/0/60.00/0.00","holds":{"A":"60.00"},"status":"paid","net":100,"error":null}'),
('PTkw', 'fixed', 'sale A cp 40; spend A; cancel; reopen; change B keep; payp 20; cancel; reopen; pay',
  '{"dlgr":40,"atonce":40,"everyr":"","expl":"478","trimmed":0,"dlg":0,"required":40,"dlgl":40,"rcv":"A:40.00/0/0/40.00/0.00","holds":{"A":"80.00","B":"0.00"},"status":"paid","net":100,"error":null}'),
-- A customer change: 'keep' to B before the session or while cancelled (A
-- holds the benefits: all of it goes to A, whom the dialog names); 'transfer'
-- to B (to B, the invoice's customer); the buyer merged into K while
-- cancelled, or before the session (to K, the invoice's customer).
('PTk', 'fixed', 'sale A cp 40; change B keep; spend A; cancel; reopen; pay',
  '{"dlgr":20,"atonce":20,"everyr":"","expl":"478","trimmed":0,"dlg":0,"required":60,"dlgl":60,"rcv":"A:20.00/0/0/60.00/0.00","holds":{"A":"80.00","B":"0.00"},"status":"paid","net":100,"error":null}'),
('PTkc', 'fixed', 'sale A cp 40; spend A; cancel; change B keep; reopen; pay',
  '{"dlgr":20,"atonce":20,"everyr":"","expl":"478","trimmed":0,"dlg":0,"required":60,"dlgl":60,"rcv":"A:20.00/0/0/60.00/0.00","holds":{"A":"80.00","B":"0.00"},"status":"paid","net":100,"error":null}'),
('PTt', 'fixed', 'sale A cp 40; change B; spend B; cancel; reopen; pay',
  '{"dlgr":20,"atonce":20,"everyr":"","expl":"478","trimmed":0,"dlg":0,"required":60,"dlgl":60,"rcv":"B*:20.00/0/0/60.00/0.00","holds":{"A":"0.00","B":"80.00"},"status":"paid","net":100,"error":null}'),
('PTtc', 'fixed', 'sale A cp 40; spend A; cancel; change B; reopen; pay',
  '{"dlgr":20,"atonce":20,"everyr":"","expl":"478","trimmed":0,"dlg":0,"required":60,"dlgl":60,"rcv":"B*:20.00/0/0/60.00/0.00","holds":{"A":"0.00","B":"80.00"},"status":"paid","net":100,"error":null}'),
('PTm', 'fixed', 'sale A cp 40; cancel; merge K A; reopen; pay',
  '{"dlgr":40,"atonce":40,"everyr":"","expl":"478","trimmed":0,"dlg":0,"required":60,"dlgl":60,"rcv":"K*:40.00/0/0/60.00/0.00","holds":{"A":"0.00","K":"100.00"},"status":"paid","net":100,"error":null}'),
('PTm2', 'fixed', 'sale A cp 40; merge K A; spend K; cancel; reopen; pay',
  '{"dlgr":20,"atonce":20,"everyr":"","expl":"478","trimmed":0,"dlg":0,"required":60,"dlgl":60,"rcv":"K*:20.00/0/0/60.00/0.00","holds":{"A":"0.00","K":"80.00"},"status":"paid","net":100,"error":null}'),
-- S1 refunded while cancelled (its S$20 held back: S$40 at once); the guided
-- Cancel, "Record refund paid" not ticked.
('PTu', 'fixed', 'sale A cp 40; spend A; cancel; unspend S1; reopen; pay',
  '{"dlgr":40,"atonce":40,"everyr":"","expl":"478","trimmed":0,"dlg":0,"required":60,"dlgl":60,"rcv":"A*:40.00/0/0/60.00/0.00","holds":{"A":"100.00"},"status":"paid","net":100,"error":null}'),
('PTgk', 'fixed', 'sale A cp 40; spend A; guidedkeep; reopen; pay',
  '{"dlgr":20,"atonce":20,"everyr":"","expl":"478","trimmed":0,"dlg":0,"required":60,"dlgl":60,"rcv":"A*:20.00/0/0/60.00/0.00","holds":{"A":"80.00"},"status":"paid","net":100,"error":null}'),
-- Correct payment raising the S$40 receipt while cancelled: to S$70; to the
-- total, so the reopening settles the invoice at once (the paid credit not
-- released yet, and the Bonus; nothing from a later payment); with a 'keep'
-- change first (A named); the bundle (its 2 vouchers given at once; after a
-- 'keep' change, A named; one voucher chosen at the till, one to choose
-- later); with a discount (the total S$80).
('PTr', 'fixed', 'sale A cp 40; spend A; cancel; raise 70; reopen; pay',
  '{"dlgr":50,"atonce":50,"everyr":"","expl":"478","trimmed":0,"dlg":0,"required":30,"dlgl":30,"rcv":"A*:50.00/0/0/30.00/0.00","holds":{"A":"80.00"},"status":"paid","net":100,"error":null}'),
('PTs', 'fixed', 'sale A cp 40; spend A; cancel; raise 100; reopen',
  '{"dlgr":80,"atonce":80,"everyr":"","expl":"478","trimmed":0,"dlg":0,"required":0,"dlgl":0,"rcv":"A*:80.00/0/0/0.00/0.00","holds":{"A":"80.00"},"status":"paid","net":100,"error":null}'),
('PTsb', 'fixed', 'sale A cpb 40; spend A; cancel; raise 100; reopen',
  '{"dlgr":90,"atonce":90,"everyr":"","expl":"478","trimmed":0,"dlg":0,"required":0,"dlgl":0,"rcv":"A*:90.00/0/0/0.00/0.00","holds":{"A":"90.00"},"status":"paid","net":100,"error":null}'),
('PTks', 'fixed', 'sale A cpb 40; change B keep; spend A; cancel; raise 100; reopen',
  '{"dlgr":90,"atonce":90,"everyr":"","expl":"478","trimmed":0,"dlg":0,"required":0,"dlgl":0,"rcv":"A:90.00/0/0/0.00/0.00","holds":{"A":"90.00","B":"0.00"},"status":"paid","net":100,"error":null}'),
('PTsv', 'fixed', 'sale A pbv 40; spend A 1 bwallet; cancel; raise 140; reopen',
  '{"dlgr":120,"atonce":120,"everyr":"","expl":"478","trimmed":0,"dlg":0,"dlgv":0,"dlgvo":2,"dlgao":0,"dlgl":0,"rcv":"A*:120.00/2/0/0.00/0.00","required":0,"holds":{"A":"120.00/2"},"status":"paid","net":140,"error":null}'),
('PTkv', 'fixed', 'sale A pbv 40; change B keep; spend A 1 bwallet; cancel; raise 140; reopen',
  '{"dlgr":120,"atonce":120,"everyr":"","expl":"478","trimmed":0,"dlg":0,"dlgv":0,"dlgvo":2,"dlgao":0,"dlgl":0,"rcv":"A:120.00/2/0/0.00/0.00","required":0,"holds":{"A":"120.00/2","B":"0.00"},"status":"paid","net":140,"error":null}'),
('PTsv1', 'fixed', 'sale A pbv1 40; spend A 1 bwallet; cancel; raise 140; reopen',
  '{"dlgr":120,"atonce":120,"everyr":"","expl":"478","trimmed":0,"dlg":0,"dlgv":0,"dlgvo":1,"dlgao":1,"dlgl":0,"rcv":"A*:120.00/1/1/0.00/0.00","required":0,"holds":{"A":"120.00/1"},"status":"paid","net":140,"error":null}'),
('PTdb', 'fixed', 'saledp A cpb 20 40; spend A; cancel; raise 80; reopen',
  '{"dlgr":70,"atonce":70,"everyr":"","expl":"478","trimmed":0,"dlg":0,"required":0,"dlgl":0,"rcv":"A*:70.00/0/0/0.00/0.00","holds":{"A":"70.00"},"status":"paid","net":80,"error":null}'),
-- A correction took the therapy line off while cancelled (the S$120 paid
-- then covers the S$100 left): the reopening settles it at once.
('PTcr', 'fixed', 'sale A cp,th 120; spend A; cancel; dropline th; reopen',
  '{"dlgr":80,"atonce":80,"everyr":"","expl":"478","trimmed":0,"dlg":0,"required":0,"dlgl":0,"rcv":"A*:80.00/0/0/0.00/0.00","holds":{"A":"80.00"},"status":"paid","net":120,"error":null}'),
-- A correction added a second package to a paid package invoice, S$40 more
-- paid, S2, cancelled: S$40 at once, S$60 to reinstate after settlement, S$60
-- from the settling payment.
('AL', 'fixed', 'sale A cp; spend A; addline cp; payp 40; spend A; cancel; reopen; pay',
  '{"dlgr":40,"atonce":40,"everyr":"","expl":"478","trimmed":0,"dlg":60,"queued":60,"gave":60,"required":60,"dlgl":60,"rcv":"A*:40.00/0/0/60.00/60.00","holds":{"A":"160.00"},"status":"paid","net":200,"error":null}'),
-- 'keep' to B, then a correction added a package B pays for (476's answer A:
-- B's): the first package's credit at once and from the settling payment
-- goes to A, the added one's to B (KAL); the first package paid in full, the
-- added one paid in part: its credit to reinstate goes to A, the added
-- line's to B (KALr).
('KAL', 'fixed', 'sale A cp 40; change B keep; addline cp; spend A; cancel; reopen; pay',
  '{"dlgr":20,"atonce":20,"everyr":"","expl":"478","trimmed":0,"dlg":0,"required":160,"dlgl":160,"rcv":"A:20.00/0/0/60.00/0.00 B*:0.00/0/0/100.00/0.00","holds":{"A":"80.00","B":"100.00"},"status":"paid","net":200,"error":null}'),
('KALr', 'fixed', 'sale A cp; spend A; change B keep; addline cp; payp 40; cancel; reopen; pay',
  '{"dlgr":40,"atonce":40,"everyr":"","expl":"478","trimmed":0,"dlg":80,"queued":80,"gave":80,"required":60,"dlgl":60,"rcv":"A:0.00/0/0/0.00/80.00 B*:40.00/0/0/60.00/0.00","holds":{"A":"80.00","B":"100.00"},"status":"paid","net":200,"error":null}'),
-- 478 (answer E as ticked): 'keep' to B, then a correction added the
-- Premium Bundle B pays for: its credit, Bonus and 2 vouchers from the
-- settling payment go to B, the first package's to A (KALv).
('KALv', 'fixed', 'sale A cp 40; change B keep; addline pbv; spend A; cancel; reopen; pay',
  '{"dlgr":20,"atonce":20,"everyr":"","expl":"478","trimmed":0,"dlg":0,"required":200,"dlgl":200,"dlgsv":2,"rcv":"A:20.00/0/0/60.00/0.00 B*:0.00/0/0/140.00/0.00|0/2/0/0","holds":{"A":"80.00","B":"140.00/2"},"status":"paid","net":240,"error":null}'),
-- A package paid in full: a 'keep' change while cancelled (the credit to
-- reinstate goes to A, who holds the benefits); an Owner's Move of its
-- unused credit to F before the cancellation (to F, the Move's recipient).
('CTLk', 'fixed', 'sale A cp; spend A; spend A; cancel; change B keep; reopen',
  '{"dlgr":0,"atonce":0,"everyr":"","expl":"474","trimmed":0,"dlg":60,"queued":60,"gave":60,"required":0,"dlgl":0,"rcv":"A:0.00/0/0/0.00/60.00","holds":{"A":"60.00","B":"0.00"},"status":"paid","net":100,"error":null}'),
('CTLmv', 'fixed', 'sale A cp; spend A; move 1 F; cancel; reopen',
  '{"dlgr":0,"atonce":0,"everyr":"","expl":"474","trimmed":0,"dlg":80,"queued":80,"gave":80,"required":0,"dlgl":0,"rcv":"F:0.00/0/0/0.00/80.00","holds":{"A":"0.00","F":"80.00"},"status":"paid","net":100,"error":null}'),
-- A package paid in full refunded (the guided Refund in full; a refund by
-- line of all it holds), reopened: its credit to reinstate after settlement
-- goes to whoever holds the benefits: A after a 'keep' change, while the
-- invoice shows B (RFk, RFkb).
('RFk', 'fixed', 'sale A cp; change B keep; refundall; reopen; pay',
  '{"dlgr":0,"atonce":0,"everyr":"","expl":"474","trimmed":0,"dlg":100,"queued":100,"gave":100,"required":100,"dlgl":0,"rcv":"A:0.00/0/0/0.00/100.00","holds":{"A":"100.00","B":"0.00"},"status":"paid","net":100,"error":null}'),
('RFkb', 'fixed', 'sale A cp; change B keep; back 1 all; reopen; pay',
  '{"dlgr":0,"atonce":0,"everyr":"","expl":"474","trimmed":0,"dlg":100,"queued":100,"gave":100,"required":100,"dlgl":0,"rcv":"A:0.00/0/0/0.00/100.00","holds":{"A":"100.00","B":"0.00"},"status":"paid","net":100,"error":null}'),
-- Settled once since: the last Reopen gives nothing at once, the first did.
('PTF', 'fixed', 'sale A cp 40; spend A; cancel; reopen; pay; cancel; back 1 40; reopen; cancel; reopen; pay',
  '{"dlgr":0,"atonce":0,"everyr":"","expl":"474","trimmed":0,"dlg":80,"queued":80,"gave":80,"required":40,"dlgl":0,"rcv":"A*:0.00/0/0/0.00/80.00","holds":{"A":"80.00"},"status":"paid","net":100,"error":null}'),
('PTrpq', 'fixed', 'sale A cp 40; spend A; cancel; reopen; pay; cancel; reopen; pay',
  '{"dlgr":0,"atonce":0,"everyr":"","expl":"474","trimmed":0,"dlg":80,"queued":80,"gave":80,"required":0,"dlgl":0,"rcv":"A*:0.00/0/0/0.00/80.00","holds":{"A":"80.00"},"status":"paid","net":100,"error":null}'),
-- Nothing at once (all released credit spent; the money paid back while
-- cancelled): the settling payment gives the rest (the first build's
-- controls; now the dialog says what that payment gives).
('PTall', 'fixed', 'sale A cp 40; spend A; spend A; cancel; reopen; pay',
  '{"dlgr":0,"atonce":0,"everyr":"","expl":"474","trimmed":0,"dlg":0,"required":60,"dlgl":60,"rcv":"A*:0.00/0/0/60.00/0.00","holds":{"A":"60.00"},"status":"paid","net":100,"error":null}'),
('PTrp', 'fixed', 'sale A cp 40; cancel; refundpaid; reopen; pay',
  '{"dlgr":0,"atonce":0,"everyr":"","expl":"474","trimmed":0,"dlg":0,"required":100,"dlgl":100,"rcv":"A*:0.00/0/0/100.00/0.00","holds":{"A":"100.00"},"status":"paid","net":100,"error":null}'),
-- Controls: nothing more to show than 474's dialog did, before 478 and
-- after (whatever is given goes to the invoice's customer and 474's figures
-- say it).
('CTL0', 'control', 'sale A cp; spend A; spend A; cancel; reopen',
  '{"dlgr":0,"atonce":0,"everyr":"","expl":"474","trimmed":0,"dlg":60,"queued":60,"gave":60,"required":0,"dlgl":0,"rcv":"A*:0.00/0/0/0.00/60.00","holds":{"A":"60.00"},"status":"paid","net":100,"error":null}'),
-- 478 (answer E as ticked): a bundle paid in full (its vouchers given at
-- its settlement before; 451's voucher units to replace after settlement).
('CTLv', 'control', 'sale A pbv; spend A 1 bwallet; cancel; reopen',
  '{"dlgr":0,"atonce":0,"everyr":"","expl":"474","trimmed":0,"dlg":120,"dlgv":2,"queued":120,"gave":120,"gavev":2,"required":0,"dlgl":0,"dlgru":0,"dlgsv":0,"dlgsa":0,"dlgsu":0,"rcv":"A*:0.00/0/0/0.00/120.00","holds":{"A":"120.00/2"},"status":"paid","net":140,"error":null}'),
('CTL1', 'control', 'sale A cp; spend A; spend A; cancel; back 1 60; reopen; pay',
  '{"dlgr":0,"atonce":0,"everyr":"","expl":"474","trimmed":0,"dlg":60,"queued":60,"gave":60,"required":60,"dlgl":0,"rcv":"A*:0.00/0/0/0.00/60.00","holds":{"A":"60.00"},"status":"paid","net":100,"error":null}'),
('CTLt', 'control', 'sale A cp; spend A; spend A; cancel; change B; reopen',
  '{"dlgr":0,"atonce":0,"everyr":"","expl":"474","trimmed":0,"dlg":60,"queued":60,"gave":60,"required":0,"dlgl":0,"rcv":"B*:0.00/0/0/0.00/60.00","holds":{"A":"0.00","B":"60.00"},"status":"paid","net":100,"error":null}'),
('RF0', 'control', 'sale A cp; refundall; reopen; pay',
  '{"dlgr":0,"atonce":0,"everyr":"","expl":"474","trimmed":0,"dlg":100,"queued":100,"gave":100,"required":100,"dlgl":0,"rcv":"A*:0.00/0/0/0.00/100.00","holds":{"A":"100.00"},"status":"paid","net":100,"error":null}'),
('CTLm', 'control', 'sale A cp; cancel; merge K A; reopen',
  '{"dlgr":0,"atonce":0,"everyr":"","expl":"474","trimmed":0,"dlg":100,"queued":100,"gave":100,"required":0,"dlgl":0,"rcv":"K*:0.00/0/0/0.00/100.00","holds":{"A":"0.00","K":"100.00"},"status":"paid","net":100,"error":null}'),
('VQ', 'control', 'sale A v; cancel; backv 1 1; reopen; cancel; reopen; pay',
  '{"dlgr":0,"atonce":0,"everyr":"","expl":"474","trimmed":0,"dlg":0,"dlgv":2,"gavev":2,"required":30,"dlgl":0,"rcv":"","holds":{"A":"0.00/2"},"status":"paid","net":60,"error":null}'),
('TH0', 'control', 'sale A th; cancel; backt 1 20; reopen; pay',
  '{"dlgr":0,"atonce":0,"everyr":"","expl":"474","trimmed":0,"dlg":0,"dlgs":3,"gaves":3,"required":20,"dlgl":0,"rcv":"","status":"paid","net":60,"error":null}');

-- States for the header's query (Q), made before 478 (R): what it lists, by
-- reason and count ('1/1,4/1': one line under 1 and one under 4; null: not
-- listed). Q2 and Q3 are finished by hand in R (NOT COVERED 1 and 5: no
-- page reaches them).
create temp table t478_qstates(k text primary key, steps text not null, want text);
insert into t478_qstates values
  ('Q1', 'sale A cp 40; spend A; cancel', '1/1,4/1'),
  ('Q1b', 'sale A cp,cp 140; spend A; cancel', '1/2,4/1'),
  ('Q1s', 'sale A cpb 40; spend A; cancel; raise 100', '1/1'),
  ('Q2', 'sale A cp 40; cancel; raise 100', '2/1'),
  ('Q3', 'sale A cp 40; cancel; refundpaid', '3/1,4/1'),
  ('Q4', 'sale A cp 40; spend A; spend A; cancel', '4/1'),
  ('Q5', 'sale A pbv 40; spend A 1 bwallet; cancel; raise 140', '1/1,5/1'),
  ('Q6', 'sale A cp 40; change B keep; spend A; cancel', '1/1,4/1,6/1'),
  ('Q6r', 'sale A cp; spend A; spend A; cancel; change B keep', '6/1'),
  ('Q6m', 'sale A cp; spend A; move 1 F; cancel', '6/1'),
  -- 478 (answer E as ticked): a bundle left to be paid (its vouchers with the
  -- settling payment); a package granting reward units, settled at once or
  -- left to be paid; after a 'keep' change (A, not B).
  ('Q7v', 'sale A pbv 40; spend A 1 bwallet; cancel', '1/1,4/1,7/1'),
  ('Q7r', 'sale A cpr 40; spend A; cancel; raise 100', '1/1,7/1'),
  ('Q7rp', 'sale A cpr 40; spend A; cancel', '1/1,4/1,7/1'),
  ('Q7k', 'sale A cpr 40; change B keep; spend A; cancel; raise 100', '1/1,6/1,7/1'),
  -- a package never paid towards, cancelled: its settling payment gives all
  -- of it, and its reward units
  ('Q4n', 'sale A cpr 0; cancel', '4/1,7/1'),
  ('Q0w', 'sale A cp 40; spend A; cancel; reopen', null),
  ('Q0p', 'sale A cp; spend A; cancel', null),
  ('Q0t', 'sale A cp; spend A; spend A; cancel; change B', null);
-- Q2: a split line (141's legacy split, by hand: a split row for the line).
-- Q3: a release lot holding S$10 again, the line counting S$10 released, the
-- money all paid back (by hand: no page reaches it).
create function pg_temp.t478_by_hand(p_pre text, p_how text) returns void language plpgsql as $f$
declare inv uuid := pg_temp.t478_id(p_pre || '/inv'); it uuid; pl record;
begin
  it := (select id from invoice_items where invoice_id = inv and line_kind = 'credit_package' order by id limit 1);
  if p_how = 'split' then
    insert into invoice_credit_splits(invoice_id, invoice_item_id, customer_id, amount)
    values (inv, it, (select customer_id from invoices where id = inv), 100);
  elsif p_how = 'trim' then
    select * into pl from credit_package_progress_lots where invoice_item_id = it order by created_at limit 1;
    update credit_package_progress_lots set released_amount = 10 where lot_id = pl.lot_id;
    update customer_credit_lots set status = 'active', is_locked = false, remaining_amount = 10 where id = credit_lot_current(pl.lot_id);
  end if;
end $f$;

-- ===== S. Where it starts =====
do $$ begin
  perform pg_temp.t478_check(pg_temp.t478_462_in() and pg_temp.t478_463_in() and pg_temp.t478_470_in() and pg_temp.t478_471_in()
      and pg_temp.t478_472_in() and pg_temp.t478_473_in() and pg_temp.t478_474_in() and pg_temp.t478_475_in()
      and pg_temp.t478_476_in() and pg_temp.t478_477_in(),
    'S 462, 463 and 470 to 477 are in (478 goes in after them)');
  perform pg_temp.t478_check((select pg_get_triggerdef(t.oid) from pg_trigger t
                               where t.tgrelid = 'public.invoices'::regclass and t.tgname = 'create_therapy_on_paid')
      = 'CREATE TRIGGER create_therapy_on_paid AFTER UPDATE ON public.invoices FOR EACH ROW EXECUTE FUNCTION trg_create_therapy_on_paid()',
    'S the trigger that releases and settles a package line''s credit is as read');
end $$;
\if :{?nomig}
do $$ begin
  perform pg_temp.t478_check(pg_temp.t478_in() and pg_temp.t478_at('after'), 'S -v nomig=1: 478 is in, as tested');
end $$;
\else
do $$ begin
  perform pg_temp.t478_check(not pg_temp.t478_in() and pg_temp.t478_at('before'),
    'S 478 is not in yet and the preview is 474''s (this suite installs it; use -v nomig=1 where it is in)');
end $$;

-- ===== R. Before 478: each case reproduced (undone afterwards) =====
-- Without 478 the preview has none of 478's keys. A 'fixed' case gives
-- what the dialog does not show (credit or vouchers at once, credit from the
-- settling payment, anything to a customer other than the invoice's:
-- 'unsaid'; or credit at once at an earlier Reopen: 'everyr'); a control
-- gives nothing it does not show. Everything else as 478 leaves it.
savepoint t478_r;
do $$
declare c record; o jsonb; res text := '';
begin
  for c in select * from t478_cases order by ord loop
    o := pg_temp.t478_run('before', c.k, c.steps);
    perform pg_temp.t478_check(o->'dlgr' = 'null'::jsonb and o->'dlgvo' = 'null'::jsonb and o->'dlgao' = 'null'::jsonb
        and o->'dlgl' = 'null'::jsonb and o->'rcv' = 'null'::jsonb and o->>'expl' = '474'
        and o->'dlgru' = 'null'::jsonb and o->'dlgsv' = 'null'::jsonb and o->'dlgsa' = 'null'::jsonb and o->'dlgsu' = 'null'::jsonb
        and pg_temp.t478_meets(o, pg_temp.t478_but_dialog(c.expect)) and coalesce(o->>'invariants', '') = ''
        and coalesce((o->>'cancel_left')::numeric, 0) = 0,
      'R ' || c.kind || ' ' || c.k || ' without 478: ' || coalesce(pg_temp.t478_diff(o, pg_temp.t478_but_dialog(c.expect)), '') || ' ' || o::text);
    if c.kind = 'fixed' then
      perform pg_temp.t478_check(coalesce(o->>'everyr', '') <> '' or coalesce(o->>'unsaid', '') <> '',
        'R fixed ' || c.k || ' without 478 the dialog already says all the reopening and the settling payment give, and to whom: ' || o::text);
      res := res || format(E'\n  %s: %s', c.k, concat_ws('; ', nullif(o->>'everyr', ''), nullif(o->>'unsaid', '')));
    else
      perform pg_temp.t478_check(coalesce(o->>'everyr', '') = '' and coalesce(o->>'unsaid', '') = '',
        'R control ' || c.k || ' gives something 474''s dialog does not show: ' || o::text);
    end if;
  end loop;
  for c in select * from t478_qstates loop
    perform pg_temp.t478_run('before', c.k, c.steps);
    perform pg_temp.t478_check((select err from t478_err where pre = 'before/' || c.k) is null,
      'R the state ' || c.k || ' was refused: ' || (select err from t478_err where pre = 'before/' || c.k));
    perform pg_temp.t478_by_hand('before/' || c.k, case c.k when 'Q2' then 'split' when 'Q3' then 'trim' end);
  end loop;
  raise notice 'PASS R: without 478 every fixed case gives what the Reopen dialog does not show (credit, vouchers or reward units at once, credit, vouchers or reward units from the settling payment, something to a customer other than the invoice''s; the fault reproduced; everything else as 478 leaves it), the controls nothing it does not show:%', res;
end $$;

-- ===== Q. The header's read-only query, on these states =====
create temp table t478_q as select * from pg_temp.t478_header_query();
do $$
declare c record;
begin
  for c in select * from t478_qstates loop
    perform pg_temp.t478_check((select string_agg(left(q.reason, 1) || '/' || q.n, ',' order by q.reason) from t478_q q
                                  join invoices i on i.invoice_no = q.invoice_no
                                 where i.id = pg_temp.t478_id('before/' || c.k || '/inv')) is not distinct from c.want,
      'Q ' || c.k || ' is listed as ' || coalesce((select string_agg(left(q.reason, 1) || '/' || q.n, ',' order by q.reason) from t478_q q
                                                    join invoices i on i.invoice_no = q.invoice_no
                                                   where i.id = pg_temp.t478_id('before/' || c.k || '/inv')), 'nothing')
      || ', not ' || coalesce(c.want, 'nothing'));
  end loop;
  -- Of the cases, none is left in a state the query lists (each ended
  -- settled again).
  perform pg_temp.t478_check(not exists (select 1 from t478_q q join invoices i on i.invoice_no = q.invoice_no
                                          join t478 t on t.id = i.id and t.k ~ '^before/[^/]+/inv$'
                                         where split_part(t.k, '/', 2) not in (select k from t478_qstates)),
    'Q a case is listed');
  raise notice 'PASS Q: the header''s query lists, by reason, a cancelled package paid in part whose reopening gives credit at once (1: Q1, Q1b 2 lines, Q1s and Q5 settled at once), a split line it would settle at once (2: Q2, by hand), a line whose reopening would trim credit back (3: Q3, by hand), a line the settling payment gives credit for (4: Q1, Q1b, Q3, Q4, Q6), a bundle settled at once with its vouchers (5: Q5), a receiver other than the invoice''s customer (6: Q6 after a ''keep'' change, Q6r credit to reinstate after a ''keep'' change while cancelled, Q6m after an Owner''s Move, Q7k) and the vouchers of a bundle left to be paid or a package''s reward units (7: Q7v, Q7r settled at once, Q7rp, Q7k, Q4n never paid towards, also under 4); nothing where it waits (Q0w), was paid in full (Q0p) or after a ''transfer'' change while cancelled (Q0t), nor any case';
end $$;
select coalesce(jsonb_object_agg(k, v), '{}'::jsonb)::text as t478_rbefore from t478_res where phase = 'before' \gset
rollback to savepoint t478_r;
insert into t478_res select 'before', key, value from jsonb_each(:'t478_rbefore'::jsonb);

-- ===== 9. The refusals, each changing nothing =====
-- 9a The preview is neither 474's nor 478's.
savepoint t478_9;
alter function public.invoice_reopen_preview_before_sessions(uuid) set work_mem = '64kB';
\set ON_ERROR_STOP off
\ir ../../../supabase/478_reopen_dialog_credit_released_at_once.sql
\set ON_ERROR_STOP on
rollback to savepoint t478_9;
select set_config('t478.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t478_check(current_setting('t478.msg') like '478: public.invoice_reopen_preview_before_sessions(uuid) is not the version this was tested against (md5 %). Re-read it and re-test before applying.'
      and not pg_temp.t478_in() and pg_temp.t478_at('before'), '9a refused with: ' || current_setting('t478.msg'));
end $$;
-- 9b A function it relies on is not as read (a setting added to it): its
-- caller, the reopening, the release, the money toward a line (the figure
-- works it out the same way), the settlement of a package.
savepoint t478_9;
alter function public.invoice_reopen_preview(uuid) set work_mem = '64kB';
\set ON_ERROR_STOP off
\ir ../../../supabase/478_reopen_dialog_credit_released_at_once.sql
\set ON_ERROR_STOP on
rollback to savepoint t478_9;
select set_config('t478.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t478_check(current_setting('t478.msg') like '478: public.invoice_reopen_preview(uuid) is missing or not the version this was tested against (md5 %). Re-read it and re-test before applying (478 goes in after 475, 476 and 477).'
      and not pg_temp.t478_in(), '9b refused with: ' || current_setting('t478.msg'));
end $$;
savepoint t478_9;
alter function public.reopen_invoice(uuid,text,uuid) set work_mem = '64kB';
\set ON_ERROR_STOP off
\ir ../../../supabase/478_reopen_dialog_credit_released_at_once.sql
\set ON_ERROR_STOP on
rollback to savepoint t478_9;
select set_config('t478.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t478_check(current_setting('t478.msg') like '478: public.reopen_invoice(uuid,text,uuid) is missing or not the version this was tested against (md5 %)%'
      and not pg_temp.t478_in(), '9b2 refused with: ' || current_setting('t478.msg'));
end $$;
savepoint t478_9;
alter function public.release_credit_package_paid_credit(uuid) set work_mem = '64kB';
\set ON_ERROR_STOP off
\ir ../../../supabase/478_reopen_dialog_credit_released_at_once.sql
\set ON_ERROR_STOP on
rollback to savepoint t478_9;
select set_config('t478.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t478_check(current_setting('t478.msg') like '478: public.release_credit_package_paid_credit(uuid) is missing or not the version this was tested against (md5 %)%'
      and not pg_temp.t478_in(), '9b3 refused with: ' || current_setting('t478.msg'));
end $$;
savepoint t478_9;
alter function public.credit_package_money_toward_line(uuid) set work_mem = '64kB';
\set ON_ERROR_STOP off
\ir ../../../supabase/478_reopen_dialog_credit_released_at_once.sql
\set ON_ERROR_STOP on
rollback to savepoint t478_9;
select set_config('t478.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t478_check(current_setting('t478.msg') like '478: public.credit_package_money_toward_line(uuid) is missing or not the version this was tested against (md5 %)%'
      and not pg_temp.t478_in(), '9b4 refused with: ' || current_setting('t478.msg'));
end $$;
savepoint t478_9;
alter function public.issue_credit_package(uuid,uuid,uuid,numeric,uuid,uuid) set work_mem = '64kB';
\set ON_ERROR_STOP off
\ir ../../../supabase/478_reopen_dialog_credit_released_at_once.sql
\set ON_ERROR_STOP on
rollback to savepoint t478_9;
select set_config('t478.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t478_check(current_setting('t478.msg') like '478: public.issue_credit_package(uuid,uuid,uuid,numeric,uuid,uuid) is missing or not the version this was tested against (md5 %)%'
      and not pg_temp.t478_in(), '9b5 refused with: ' || current_setting('t478.msg'));
end $$;
-- 9b6 (answer E) What names the receivers is not as read: 476's holder, 462's
-- live holder.
savepoint t478_9;
alter function public.credit_line_benefits_holder(uuid) set work_mem = '64kB';
\set ON_ERROR_STOP off
\ir ../../../supabase/478_reopen_dialog_credit_released_at_once.sql
\set ON_ERROR_STOP on
rollback to savepoint t478_9;
select set_config('t478.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t478_check(current_setting('t478.msg') like '478: public.credit_line_benefits_holder(uuid) is missing or not the version this was tested against (md5 %)%'
      and not pg_temp.t478_in(), '9b6 refused with: ' || current_setting('t478.msg'));
end $$;
savepoint t478_9;
alter function public.invoice_credit_live_holder(uuid,uuid,timestamp with time zone) set work_mem = '64kB';
\set ON_ERROR_STOP off
\ir ../../../supabase/478_reopen_dialog_credit_released_at_once.sql
\set ON_ERROR_STOP on
rollback to savepoint t478_9;
select set_config('t478.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t478_check(current_setting('t478.msg') like '478: public.invoice_credit_live_holder(uuid,uuid,timestamp with time zone) is missing or not the version this was tested against (md5 %)%'
      and not pg_temp.t478_in(), '9b7 refused with: ' || current_setting('t478.msg'));
end $$;
-- 9b8 (answer E as ticked) What the reward units read is not as read: the
-- store's lowest Legacy rule on the day (issue_credit_package's threshold
-- where the package has none).
savepoint t478_9;
alter function public.legacy_lowest_rule(uuid,date) set work_mem = '64kB';
\set ON_ERROR_STOP off
\ir ../../../supabase/478_reopen_dialog_credit_released_at_once.sql
\set ON_ERROR_STOP on
rollback to savepoint t478_9;
select set_config('t478.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t478_check(current_setting('t478.msg') like '478: public.legacy_lowest_rule(uuid,date) is missing or not the version this was tested against (md5 %)%'
      and not pg_temp.t478_in(), '9b8 refused with: ' || current_setting('t478.msg'));
end $$;
-- 9c Another function takes its name (an overload).
savepoint t478_9;
create function public.invoice_reopen_preview_before_sessions(p text) returns jsonb language sql as $f$ select null::jsonb $f$;
\set ON_ERROR_STOP off
\ir ../../../supabase/478_reopen_dialog_credit_released_at_once.sql
\set ON_ERROR_STOP on
rollback to savepoint t478_9;
select set_config('t478.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t478_check(current_setting('t478.msg') = '478: another function takes the name of the one this changes: invoice_reopen_preview_before_sessions(text)'
      and not pg_temp.t478_in(), '9c refused with: ' || current_setting('t478.msg'));
end $$;
-- 9d A new caller of the preview (it would read the new key).
savepoint t478_9;
create function public.t478_probe_preview(p uuid) returns jsonb language sql as $f$ select public.invoice_reopen_preview_before_sessions(p) $f$;
\set ON_ERROR_STOP off
\ir ../../../supabase/478_reopen_dialog_credit_released_at_once.sql
\set ON_ERROR_STOP on
rollback to savepoint t478_9;
select set_config('t478.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t478_check(current_setting('t478.msg') like '478: the functions that call the Reopen dialog''s preview are not as read on 27 Oct 2026 (%t478_probe_preview(uuid)%)%'
      and not pg_temp.t478_in(), '9d refused with: ' || current_setting('t478.msg'));
end $$;
-- 9e A new caller of the release, a new writer of the release records.
savepoint t478_9;
create function public.t478_probe_release(p uuid) returns jsonb language sql as $f$ select public.release_credit_package_paid_credit(p) $f$;
\set ON_ERROR_STOP off
\ir ../../../supabase/478_reopen_dialog_credit_released_at_once.sql
\set ON_ERROR_STOP on
rollback to savepoint t478_9;
select set_config('t478.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t478_check(current_setting('t478.msg') like '478: what releases or settles a package line''s credit is not as read on 27 Oct 2026 (%t478_probe_release(uuid)%)%'
      and not pg_temp.t478_in(), '9e refused with: ' || current_setting('t478.msg'));
end $$;
savepoint t478_9;
create function public.t478_probe_progress() returns void language sql as $f$ update public.credit_package_progress_lots set released_amount = released_amount where false $f$;
\set ON_ERROR_STOP off
\ir ../../../supabase/478_reopen_dialog_credit_released_at_once.sql
\set ON_ERROR_STOP on
rollback to savepoint t478_9;
select set_config('t478.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t478_check(current_setting('t478.msg') like '478: what writes the release records (credit_package_progress_lots) is not as read on 27 Oct 2026 (%t478_probe_progress()%)%'
      and not pg_temp.t478_in(), '9e2 refused with: ' || current_setting('t478.msg'));
end $$;
-- 9e3 (answer E) A new writer of the reopening queue (what the settling
-- payment gives back, and to whom).
savepoint t478_9;
create function public.t478_probe_queue() returns void language sql as $f$ update public.invoice_reopen_benefits set amount = amount where false $f$;
\set ON_ERROR_STOP off
\ir ../../../supabase/478_reopen_dialog_credit_released_at_once.sql
\set ON_ERROR_STOP on
rollback to savepoint t478_9;
select set_config('t478.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t478_check(current_setting('t478.msg') like '478: what writes the reopening queue (invoice_reopen_benefits) is not as read on 27 Oct 2026 (%t478_probe_queue()%)%'
      and not pg_temp.t478_in(), '9e3 refused with: ' || current_setting('t478.msg'));
end $$;
-- 9f A trigger on invoices that is not as read (a reopening's status change
-- would run it).
savepoint t478_9;
create function public.t478_probe_trg() returns trigger language plpgsql as $f$ begin return null; end $f$;
create trigger t478_probe after update of status on public.invoices for each row execute function public.t478_probe_trg();
\set ON_ERROR_STOP off
\ir ../../../supabase/478_reopen_dialog_credit_released_at_once.sql
\set ON_ERROR_STOP on
rollback to savepoint t478_9;
select set_config('t478.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t478_check(current_setting('t478.msg') like '478: the triggers on invoices are not as read on 27 Oct 2026 (20 triggers, md5 %)%'
      and not pg_temp.t478_in(), '9f refused with: ' || current_setting('t478.msg'));
end $$;
-- 9g The queue no longer holds one row per ledger row.
savepoint t478_9;
alter table public.invoice_reopen_benefits drop constraint invoice_reopen_benefits_source_ledger_id_key;
\set ON_ERROR_STOP off
\ir ../../../supabase/478_reopen_dialog_credit_released_at_once.sql
\set ON_ERROR_STOP on
rollback to savepoint t478_9;
select set_config('t478.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t478_check(current_setting('t478.msg') like '478: the reopening queue no longer holds one row per ledger row%'
      and not pg_temp.t478_in(), '9g refused with: ' || current_setting('t478.msg'));
end $$;
-- 9h Other grants: refused. The same grants in another order: not.
savepoint t478_9;
grant execute on function public.invoice_reopen_preview_before_sessions(uuid) to authenticated;
\set ON_ERROR_STOP off
\ir ../../../supabase/478_reopen_dialog_credit_released_at_once.sql
\set ON_ERROR_STOP on
rollback to savepoint t478_9;
select set_config('t478.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t478_check(current_setting('t478.msg') like '478: who may call public.invoice_reopen_preview_before_sessions(uuid) is not as read on 27 Oct 2026 (%)'
      and not pg_temp.t478_in(), '9h refused with: ' || current_setting('t478.msg'));
end $$;
savepoint t478_9;
revoke execute on function public.invoice_reopen_preview_before_sessions(uuid) from postgres;
grant execute on function public.invoice_reopen_preview_before_sessions(uuid) to postgres;
select pg_temp.t478_check((select proacl::text from pg_proc where oid = 'public.invoice_reopen_preview_before_sessions(uuid)'::regprocedure)
         <> '{postgres=X/postgres,service_role=X/postgres}'
       and pg_temp.t478_grant_set('invoice_reopen_preview_before_sessions(uuid)') = '{postgres=X/postgres,service_role=X/postgres}',
  '9h2 set-up: the same grants in another order');
\ir ../../../supabase/478_reopen_dialog_credit_released_at_once.sql
select pg_temp.t478_in() and pg_temp.t478_at('after') as t478_9h2_in \gset
rollback to savepoint t478_9;
select pg_temp.t478_check(:'t478_9h2_in'::boolean and not pg_temp.t478_in(), '9h2 the same grants in another order stopped it');
do $$ begin
  raise notice 'PASS 9: refused, changing nothing, where the preview is neither 474''s nor 478''s, a function it relies on is not as tested (its caller, the reopening, the release, the money toward a line, the settlement, what names the receivers, the reward units'' rule), another function takes its name, a new function calls the preview or the release or writes the release records or the reopening queue, a trigger on invoices or the queue''s unique key is not as read, or other grants; the same grants in another order do not stop it';
end $$;

-- ===== M. Begun before 478, the dialog read after it =====
-- Cancelled before 478 (MPT0); reopened, cancelled again before it (MPTq);
-- Correct payment raised before it (MPTs); a 'keep' change and cancelled
-- before it (MPTk); a bundle paid in part, cancelled before it (MPTv).
do $$ begin
  perform pg_temp.t478_run('mid', 'MPT0', 'sale A cp 40; spend A; cancel; reopen; pay', 1, 3);
  perform pg_temp.t478_run('mid', 'MPTq', 'sale A cp 40; spend A; cancel; reopen; cancel; reopen; pay', 1, 5);
  perform pg_temp.t478_run('mid', 'MPTs', 'sale A cpb 40; spend A; cancel; raise 100; reopen', 1, 4);
  perform pg_temp.t478_run('mid', 'MPTk', 'sale A cp 40; change B keep; spend A; cancel; reopen; pay', 1, 4);
  perform pg_temp.t478_run('mid', 'MPTv', 'sale A pbv 40; spend A 1 bwallet; cancel; reopen; pay', 1, 3);
  perform pg_temp.t478_check(not (invoice_reopen_preview(pg_temp.t478_id('mid/MPT0/inv')) ?| pg_temp.t478_keys()),
    'M MPT0 before 478 the dialog already has 478''s figures');
end $$;
\endif

-- ===== 10. Install 478, twice =====
\if :{?nomig}
do $$ begin raise notice 'NOTE 10: -v nomig=1, so 478 is not installed here (R, Q, 9 and M are skipped)'; end $$;
\else
\ir ../../../supabase/478_reopen_dialog_credit_released_at_once.sql
do $$ begin insert into t478_fp values ('first', pg_temp.t478_fingerprint()); end $$;
\ir ../../../supabase/478_reopen_dialog_credit_released_at_once.sql
do $$ begin insert into t478_fp values ('second', pg_temp.t478_fingerprint()); end $$;
\endif
do $$
begin
  perform pg_temp.t478_check(pg_temp.t478_in() and pg_temp.t478_at('after'), '10 478 is not installed as tested');
  perform pg_temp.t478_check((select count(*) from pg_proc where pronamespace = 'public'::regnamespace
                               and proname = 'invoice_reopen_preview_before_sessions') = 1, '10 an overload exists');
  perform pg_temp.t478_check(pg_temp.t478_grant_set('invoice_reopen_preview_before_sessions(uuid)') = '{postgres=X/postgres,service_role=X/postgres}'
      and pg_temp.t478_grant_set('invoice_reopen_preview(uuid)') = '{authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres}'
      and not has_function_privilege('anon', 'public.invoice_reopen_preview_before_sessions(uuid)', 'execute')
      and not has_function_privilege('authenticated', 'public.invoice_reopen_preview_before_sessions(uuid)', 'execute')
      and not has_function_privilege('anon', 'public.invoice_reopen_preview(uuid)', 'execute'),
    '10 who may call the previews changed');
  if exists (select 1 from t478_fp where k = 'first') then
    perform pg_temp.t478_check((select fp from t478_fp where k = 'second') = (select fp from t478_fp where k = 'first'),
      '10 the second run of 478 changed functions');
    perform pg_temp.t478_check(split_part((select fp from t478_fp where k = 'first'), ' ', 2) = split_part((select fp from t478_fp where k = 'start'), ' ', 2),
      '10 478 changed the number of functions');
    perform pg_temp.t478_check(pg_temp.t478_grants() = (select fp from t478_fp where k = 'grants'), '10 the grants changed');
    -- On a copy of production at 475 with 476 and 477 in: the AFTER
    -- fingerprint.
    if (select fp from t478_fp where k = 'start') = '88ba82ccc06315d862081fba55ce725d 1390' then
      perform pg_temp.t478_check((select fp from t478_fp where k = 'first') = 'eae7f82fcf73b53d97945020e755721a 1390',
        '10 the fingerprint after 478 is ' || (select fp from t478_fp where k = 'first'));
    end if;
  end if;
  raise notice 'PASS 10: 478 installed (the preview %); %; no overload; the grants as before (the preview for the service role alone, invoice_reopen_preview for signed-in staff)',
    md5(pg_get_functiondef('public.invoice_reopen_preview_before_sessions(uuid)'::regprocedure)),
    coalesce('the second run changed nothing (' || (select fp from t478_fp where k = 'second') || ')', 'it was in before the suite (nomig)');
end $$;

-- ===== M (finished). Begun before 478, the dialog read after it =====
\if :{?nomig}
do $$ begin raise notice 'NOTE M: -v nomig=1 (478 in), so no case was begun before it'; end $$;
\else
do $$
declare o jsonb;
begin
  o := pg_temp.t478_run('mid', 'MPT0', 'sale A cp 40; spend A; cancel; reopen; pay', 4);
  perform pg_temp.t478_check(pg_temp.t478_meets(o, '{"dlgr":20,"atonce":20,"everyr":"","expl":"478","dlgl":60,"rcv":"A*:20.00/0/0/60.00/0.00","got":"A*:20.00/0/0/60.00/0.00","holds":{"A":"80.00"},"status":"paid","error":null}')
      and coalesce(o->>'invariants', '') = '', 'M MPT0 ' || o::text);
  o := pg_temp.t478_run('mid', 'MPTq', 'sale A cp 40; spend A; cancel; reopen; cancel; reopen; pay', 6);
  -- (its first Reopen, before 478, had no figure and no receivers: 'everyr'
  -- and 'everyrc' name it)
  perform pg_temp.t478_check(pg_temp.t478_meets(o, '{"dlgr":20,"atonce":20,"everyr":"4: none shown, 20.00 at once","everyrc":"4: none shown, A:20.00/0/0/0 given","expl":"478","dlgl":60,"rcv":"A*:20.00/0/0/60.00/0.00","got":"A*:20.00/0/0/60.00/0.00","holds":{"A":"80.00"},"status":"paid","error":null}')
      and coalesce(o->>'invariants', '') = '', 'M MPTq ' || o::text);
  o := pg_temp.t478_run('mid', 'MPTs', 'sale A cpb 40; spend A; cancel; raise 100; reopen', 5);
  perform pg_temp.t478_check(pg_temp.t478_meets(o, '{"dlgr":90,"atonce":90,"everyr":"","expl":"478","dlgl":0,"rcv":"A*:90.00/0/0/0.00/0.00","got":"A*:90.00/0/0/0.00/0.00","holds":{"A":"90.00"},"status":"paid","error":null}')
      and coalesce(o->>'invariants', '') = '', 'M MPTs ' || o::text);
  o := pg_temp.t478_run('mid', 'MPTk', 'sale A cp 40; change B keep; spend A; cancel; reopen; pay', 5);
  perform pg_temp.t478_check(pg_temp.t478_meets(o, '{"dlgr":20,"atonce":20,"everyr":"","expl":"478","dlgl":60,"rcv":"A:20.00/0/0/60.00/0.00","got":"A:20.00/0/0/60.00/0.00","holds":{"A":"80.00","B":"0.00"},"status":"paid","error":null}')
      and coalesce(o->>'invariants', '') = '', 'M MPTk ' || o::text);
  o := pg_temp.t478_run('mid', 'MPTv', 'sale A pbv 40; spend A 1 bwallet; cancel; reopen; pay', 4);
  perform pg_temp.t478_check(pg_temp.t478_meets(o, '{"dlgr":20,"atonce":20,"everyr":"","expl":"478","dlgl":100,"dlgsv":2,"rcv":"A*:20.00/0/0/100.00/0.00|0/2/0/0","got":"A*:20.00/0/0/100.00/0.00|0/2/0/0","holds":{"A":"120.00/2"},"status":"paid","error":null}')
      and coalesce(o->>'invariants', '') = '', 'M MPTv ' || o::text);
  raise notice 'PASS M: begun before 478 (cancelled; reopened and cancelled again; Correct payment raised; a ''keep'' change; a bundle), read after it: the dialog says what the reopening gives at once (S$20; S$20; S$90; S$20; S$20), what the settling payment gives (S$60; S$60; nothing; S$60; S$100 and the bundle''s 2 vouchers) and to whom (A; A; A; A, not the invoice''s customer; A)';
end $$;
\endif

-- ===== A. After 478: each case =====
do $$
declare c record; o jsonb; b jsonb; res text := ''; n int := 0; dl record;
begin
  for c in select * from t478_cases order by ord loop
    o := pg_temp.t478_run('after', c.k, c.steps);
    perform pg_temp.t478_check(pg_temp.t478_meets(o, c.expect) and coalesce(o->>'invariants', '') = ''
        and coalesce((o->>'cancel_left')::numeric, 0) = 0,
      'A ' || c.kind || ' ' || c.k || ': ' || coalesce(pg_temp.t478_diff(o, c.expect), '') || ' ' || o::text);
    -- Every Reopen of the case: the figure is what it gave at once, and the
    -- explanation has 478's sentence exactly where that is above 0; its
    -- receivers' at-once parts are what each customer got at once.
    perform pg_temp.t478_check(not exists (select 1 from t478_dlg d where d.pre = 'after/' || c.k and d.atonce is not null
                                             and (d.shownr is distinct from d.atonce
                                                  or d.expl is distinct from case when d.atonce > 0 then pg_temp.t478_expl478() else pg_temp.t478_expl474() end)),
      'A ' || c.k || ': a Reopen''s figure or explanation is not what it gave at once');
    perform pg_temp.t478_check(coalesce(o->>'everyrc', '') = '',
      'A ' || c.k || ': a Reopen''s receivers are not whom it gave to at once: ' || coalesce(o->>'everyrc', 'null'));
    -- Every Reopen: the receivers' parts add up to the dialog's figures (the
    -- credit to reinstate after settlement, 474's, among them); the
    -- invoice's customer is the one marked so, and each name is the
    -- customer's.
    for dl in select * from t478_dlg where pre = 'after/' || c.k loop
      perform pg_temp.t478_check(jsonb_typeof(dl.rcv) = 'array'
          and (select coalesce(sum((r->>'credit_released_on_reopen')::numeric), 0) from jsonb_array_elements(dl.rcv) r) = dl.shownr
          and (select coalesce(sum((r->>'bundle_vouchers_given_on_reopen')::int), 0) from jsonb_array_elements(dl.rcv) r) = dl.shownvo
          and (select coalesce(sum((r->>'bundle_vouchers_to_choose_on_reopen')::int), 0) from jsonb_array_elements(dl.rcv) r) = dl.shownao
          and (select coalesce(sum((r->>'credit_from_settling_payment')::numeric), 0) from jsonb_array_elements(dl.rcv) r) = dl.shownl
          and (select coalesce(sum((r->>'credit_to_reinstate_after_settlement')::numeric), 0) from jsonb_array_elements(dl.rcv) r) = dl.shown
          and (select coalesce(sum((r->>'reward_units_given_on_reopen')::int), 0) from jsonb_array_elements(dl.rcv) r) = dl.shownru
          and (select coalesce(sum((r->>'bundle_vouchers_from_settling_payment')::int), 0) from jsonb_array_elements(dl.rcv) r) = dl.shownsv
          and (select coalesce(sum((r->>'bundle_vouchers_to_choose_from_settling_payment')::int), 0) from jsonb_array_elements(dl.rcv) r) = dl.shownsa
          and (select coalesce(sum((r->>'reward_units_from_settling_payment')::int), 0) from jsonb_array_elements(dl.rcv) r) = dl.shownsu
          and not exists (select 1 from jsonb_array_elements(dl.rcv) r
                           where (r->>'invoice_customer')::boolean is distinct from ((r->>'customer_id')::uuid = dl.cust)
                              or r->>'customer_name' is distinct from (select full_name from customers where id = (r->>'customer_id')::uuid)),
        'A ' || c.k || ': at Reopen ' || dl.n || ' the receivers do not add up to the dialog''s figures: ' || dl.preview::text);
    end loop;
    -- At the last Reopen: each receiver's part is what was given, to whom (at
    -- once, by the payments that settled it, and reinstated after settlement).
    perform pg_temp.t478_check(o->>'rcv' = o->>'got',
      'A ' || c.k || ': the dialog says ' || coalesce(o->>'rcv', 'null') || ', given ' || coalesce(o->>'got', 'null'));
    -- Where R ran: every key but the dialog's (what was given and to whom
    -- among them) as before 478.
    b := (select v from t478_res where phase = 'before' and k = c.k);
    if b is not null then
      perform pg_temp.t478_check(pg_temp.t478_but_dialog(o) = pg_temp.t478_but_dialog(b),
        'A ' || c.k || ' differs from before 478 beyond the dialog: before ' || pg_temp.t478_but_dialog(b)::text
        || ', after ' || pg_temp.t478_but_dialog(o)::text);
      n := n + 1;
    end if;
    if c.kind = 'fixed' then res := res || format(' %s %s;', c.k, o->>'rcv'); end if;
  end loop;
  raise notice 'PASS A: after 478 every Reopen''s dialog says what the reopening gives at once and to whom, and at the last one what the settling payment gives and to whom the credit to reinstate goes, each as given (receivers by role: * the invoice''s customer; at once / vouchers / to choose / settling / reinstated, then | reward units at once / bundle vouchers, to choose and reward units from the settling payment):%; the controls nothing new; % cases compared with before 478: nothing else differs (who holds what, the money, the queue, the plans, the invariants, Cancel, what was given)', res, n;
end $$;

-- ===== P. Probes =====
-- P1 The preview's other figures are exactly 474's, and its explanation is
-- 474's with 478's sentence only where its figure is above 0: 474's text
-- worked back from 478's (the lines 478 adds taken out; by md5), installed
-- in a block that is undone, on states just before the last Reopen of PT0,
-- PTn, PTsb, PTsv, AL, PT2, PTq, PTk, PTu, PTall, PTF, CTL0, VQ, TH0, PTv
-- and PTr2.
create function pg_temp.t478_def474() returns text language plpgsql as $f$
declare d text := pg_get_functiondef('public.invoice_reopen_preview_before_sessions(uuid)'::regprocedure);
  a int; z int;
begin
  a := position(E' -- 478 (the Owner' in d);
  if a = 0 then return null; end if;
  z := a + position(E'\n end if;\n' in substr(d, a)) - 1;
  d := substr(d, 1, a - 1) || substr(d, z + length(E'\n end if;\n'));
  d := replace(d, ' v478 numeric:=0;', '');
  d := replace(d, E'\n v478s numeric:=0; v478v int:=0; v478a int:=0; v478r jsonb:=''[]''::jsonb;  -- 478', '');
  d := replace(d, E'\n v478u int:=0; v478sv int:=0; v478sa int:=0; v478su int:=0;  -- 478 (vouchers and reward units)', '');
  d := replace(d, E'''credit_released_on_reopen'',v478,\n   ''bundle_vouchers_given_on_reopen'',v478v,''bundle_vouchers_to_choose_on_reopen'',v478a,''credit_from_settling_payment'',v478s,''credit_receivers'',v478r,\n   ''reward_units_given_on_reopen'',v478u,''bundle_vouchers_from_settling_payment'',v478sv,\n   ''bundle_vouchers_to_choose_from_settling_payment'',v478sa,''reward_units_from_settling_payment'',v478su,\n   ', '');
  d := replace(d, E'''Existing refunds remain recorded. Only net unrefunded payments settle the reopened invoice. ''\n     ||case when v478>0 then ''Package or bundle credit the net payments already pay for is released at once when the invoice is reopened. '' else '''' end\n     ||''Previously revoked credit is reinstated once the reopened invoice is fully settled.''',
                  '''Existing refunds remain recorded. Only net unrefunded payments settle the reopened invoice. Previously revoked credit is reinstated once the reopened invoice is fully settled.''');
  return d;
end $f$;
do $$
declare c record; inv uuid; p478 jsonb; p474 jsonb; d text := pg_temp.t478_def474(); res text := '';
begin
  perform pg_temp.t478_check(md5(d) = '7e1ef2d25415e69b3f770fe2efd45190', 'P1 474''s text is not what 478''s gives back with its lines taken out: ' || md5(d));
  for c in select x.k, x.steps, x.upto from (values
      ('PT0', 'sale A cp 40; spend A; cancel', 3),
      ('PTn', 'sale A cp 40; cancel', 2),
      ('PTsb', 'sale A cpb 40; spend A; cancel; raise 100', 4),
      ('PTsv', 'sale A pbv 40; spend A 1 bwallet; cancel; raise 140', 4),
      ('AL', 'sale A cp; spend A; addline cp; payp 40; spend A; cancel', 6),
      ('PT2', 'sale A cp,cp 140; spend A; cancel', 3),
      ('PTq', 'sale A cp 40; spend A; cancel; reopen; cancel', 5),
      ('PTk', 'sale A cp 40; change B keep; spend A; cancel', 4),
      ('PTu', 'sale A cp 40; spend A; cancel; unspend S1', 4),
      ('PTall', 'sale A cp 40; spend A; spend A; cancel', 4),
      ('PTF', 'sale A cp 40; spend A; cancel; reopen; pay; cancel; back 1 40; reopen; cancel', 9),
      ('CTL0', 'sale A cp; spend A; spend A; cancel', 4),
      ('VQ', 'sale A v; cancel; backv 1 1; reopen; cancel', 5),
      ('TH0', 'sale A th; cancel; backt 1 20', 3),
      ('PTv', 'sale A pbv 40; spend A 1 bwallet; cancel', 3),
      ('PTr2', 'sale A cpr 40; spend A; cancel; raise 100', 4)) x(k, steps, upto) loop
    perform pg_temp.t478_run('P1', c.k, c.steps, 1, c.upto);
    perform pg_temp.t478_check((select err from t478_err where pre = 'P1/' || c.k) is null, 'P1 ' || c.k || ' refused: ' || (select err from t478_err where pre = 'P1/' || c.k));
    inv := pg_temp.t478_id('P1/' || c.k || '/inv');
    p478 := invoice_reopen_preview(inv);
    begin
      execute d;
      p474 := invoice_reopen_preview(inv);
      raise exception using errcode = 'P4781', message = 'undo';
    exception when sqlstate 'P4781' then null;
    end;
    perform pg_temp.t478_check(pg_temp.t478_in() and pg_temp.t478_at('after'), 'P1 474''s text was left in');
    perform pg_temp.t478_check(p478 - pg_temp.t478_keys() - 'explanation' = p474 - 'explanation'
        and not (p474 ?| pg_temp.t478_keys()) and p474->>'explanation' = pg_temp.t478_expl474()
        and p478->>'explanation' = case when (p478->>'credit_released_on_reopen')::numeric > 0 then pg_temp.t478_expl478() else pg_temp.t478_expl474() end,
      'P1 ' || c.k || ': 478 ' || p478::text || ' / 474 ' || p474::text);
    res := res || format(' %s S$%s at once, S$%s settling%s;', c.k, p478->>'credit_released_on_reopen', p478->>'credit_from_settling_payment',
      case when (p478->>'reward_units_given_on_reopen')::int > 0 or (p478->>'bundle_vouchers_from_settling_payment')::int > 0
                or (p478->>'bundle_vouchers_to_choose_from_settling_payment')::int > 0 or (p478->>'reward_units_from_settling_payment')::int > 0
           then format(' (%s reward units at once; %s vouchers, %s to choose, %s reward units settling)', p478->>'reward_units_given_on_reopen',
                       p478->>'bundle_vouchers_from_settling_payment', p478->>'bundle_vouchers_to_choose_from_settling_payment',
                       p478->>'reward_units_from_settling_payment') else '' end);
  end loop;
  raise notice 'PASS P1: every other figure of the Reopen dialog is 474''s (blockers, the credit to reinstate after settlement, voucher units, sessions, stock, the money); its explanation 474''s, with 478''s sentence only where its credit at once is above 0:%', res;
end $$;
-- P2 What a reopening records: the revision's snapshot ('reopen_preview')
-- and its Audit Log row ('invoice_reopened') carry the figure the dialog
-- showed (PT0: S$20; AL: S$40 beside S$60), and what else it showed: the
-- settling payment's figure and the receivers (PTk: A, not the invoice's
-- customer, S$20 at once and S$60 from the settling payment), the vouchers
-- the settling payment gives (PTv: 2) and a package's reward units at once
-- (PTr2: 2).
do $$
declare inv uuid;
begin
  foreach inv in array array[pg_temp.t478_id('after/PT0/inv'), pg_temp.t478_id('after/AL/inv')] loop
    perform pg_temp.t478_check((select (r.snapshot->'reopen_preview'->>'credit_released_on_reopen')::numeric
                                  from invoice_revisions r where r.invoice_id = inv and r.snapshot ? 'reopen_preview'
                                 order by r.revision_no desc limit 1)
                               = case when inv = pg_temp.t478_id('after/PT0/inv') then 20 else 40 end
        and (select (a.new_data->>'credit_released_on_reopen')::numeric from audit_logs a
              where a.record_id = inv and a.action = 'invoice_reopened' order by a.created_at desc limit 1)
            = case when inv = pg_temp.t478_id('after/PT0/inv') then 20 else 40 end,
      'P2 the reopening recorded ' || coalesce((select r.snapshot->'reopen_preview'->>'credit_released_on_reopen'
                                                 from invoice_revisions r where r.invoice_id = inv and r.snapshot ? 'reopen_preview'
                                                order by r.revision_no desc limit 1), '?'));
  end loop;
  inv := pg_temp.t478_id('after/PTk/inv');
  perform pg_temp.t478_check(
    (select pg_temp.t478_rcv('after/PTk', r.snapshot->'reopen_preview'->'credit_receivers') from invoice_revisions r
      where r.invoice_id = inv and r.snapshot ? 'reopen_preview' order by r.revision_no desc limit 1) = 'A:20.00/0/0/60.00/0.00'
    and (select pg_temp.t478_rcv('after/PTk', a.new_data->'credit_receivers') from audit_logs a
          where a.record_id = inv and a.action = 'invoice_reopened' order by a.created_at desc limit 1) = 'A:20.00/0/0/60.00/0.00'
    and (select (r.snapshot->'reopen_preview'->>'credit_from_settling_payment')::numeric from invoice_revisions r
          where r.invoice_id = inv and r.snapshot ? 'reopen_preview' order by r.revision_no desc limit 1) = 60,
    'P2 PTk: the reopening recorded ' || coalesce((select (r.snapshot->'reopen_preview'->'credit_receivers')::text from invoice_revisions r
                                                     where r.invoice_id = inv and r.snapshot ? 'reopen_preview' order by r.revision_no desc limit 1), '?'));
  perform pg_temp.t478_check(
    (select (r.snapshot->'reopen_preview'->>'bundle_vouchers_from_settling_payment')::int from invoice_revisions r
      where r.invoice_id = pg_temp.t478_id('after/PTv/inv') and r.snapshot ? 'reopen_preview' order by r.revision_no desc limit 1) = 2
    and (select (a.new_data->>'bundle_vouchers_from_settling_payment')::int from audit_logs a
          where a.record_id = pg_temp.t478_id('after/PTv/inv') and a.action = 'invoice_reopened' order by a.created_at desc limit 1) = 2
    and (select (r.snapshot->'reopen_preview'->>'reward_units_given_on_reopen')::int from invoice_revisions r
          where r.invoice_id = pg_temp.t478_id('after/PTr2/inv') and r.snapshot ? 'reopen_preview' order by r.revision_no desc limit 1) = 2
    and (select (a.new_data->>'reward_units_given_on_reopen')::int from audit_logs a
          where a.record_id = pg_temp.t478_id('after/PTr2/inv') and a.action = 'invoice_reopened' order by a.created_at desc limit 1) = 2,
    'P2 PTv, PTr2: the reopening did not record the vouchers and reward units the dialog showed');
  raise notice 'PASS P2: a reopening records what the dialog showed (its revision''s snapshot and its Audit Log row: S$20 for PT0, S$40 for AL; for PTk A as the receiver of S$20 at once and S$60 from the settling payment; the 2 vouchers from PTv''s settling payment; PTr2''s 2 reward units at once)';
end $$;
-- P3 A waiting reopening (the dialog is not offered: can_reopen false): its
-- preview shows nothing at once and 474's words.
do $$
declare inv uuid; pv jsonb;
begin
  perform pg_temp.t478_run('P3', 'W', 'sale A cp 40; spend A; cancel; reopen', 1, 4);
  inv := pg_temp.t478_id('P3/W/inv'); pv := invoice_reopen_preview(inv);
  perform pg_temp.t478_check((pv->>'credit_released_on_reopen')::numeric = 0 and pv->>'explanation' = pg_temp.t478_expl474()
      and (pv->>'credit_from_settling_payment')::numeric = 0 and (pv->>'bundle_vouchers_given_on_reopen')::int = 0
      and (pv->>'bundle_vouchers_to_choose_on_reopen')::int = 0 and pv->'credit_receivers' = '[]'::jsonb
      and (pv->>'reward_units_given_on_reopen')::int = 0 and (pv->>'bundle_vouchers_from_settling_payment')::int = 0
      and (pv->>'bundle_vouchers_to_choose_from_settling_payment')::int = 0 and (pv->>'reward_units_from_settling_payment')::int = 0
      and not (pv->>'can_reopen')::boolean and (select status::text from invoices where id = inv) = 'partially_paid',
    'P3 W: ' || pv::text);
  raise notice 'PASS P3: a waiting reopening''s preview shows nothing given at once or by a settling payment (credit, vouchers, reward units), no receiver and 474''s words; it cannot be reopened';
end $$;
-- P4 Nothing added or dropped; the grants as before.
do $$ begin
  perform pg_temp.t478_check(split_part(pg_temp.t478_fingerprint(), ' ', 2) = split_part((select fp from t478_fp where k = 'start'), ' ', 2)
      and pg_temp.t478_grants() = (select fp from t478_fp where k = 'grants'),
    'P4 the functions or grants changed: ' || pg_temp.t478_fingerprint());
  raise notice 'PASS P4: no function added or dropped; the grant list as before';
end $$;

-- ===== K. KNOWN (478's NOT COVERED), checked as they are =====
-- (The second build's KNOWN K2a and K2b, the vouchers the settling payment
-- gives and a package's reward units, are fixed now: PTv, PTr2 and their
-- siblings in A.)
do $$
declare o jsonb; a uuid;
begin
  -- K2 (NOT COVERED 2): the sale record and its commission are not in the
  -- dialog (not asked): after a 'keep' change the bundle's sale record is
  -- A's, the buyer's, as 476 makes it (PTkvl), and no key of the preview
  -- names a sale record or a commission.
  perform pg_temp.t478_check((select customer_id from premium_bundle_sales where invoice_id = pg_temp.t478_id('after/PTkvl/inv'))
        = pg_temp.t478_id('after/PTkvl/A')
      and not exists (select 1 from jsonb_object_keys((select preview from t478_dlg where pre = 'after/PTkvl' order by n desc limit 1)) k
                       where k ~ '(sale|commission|referrer)'),
    'K2 PTkvl: look at NOT COVERED 2 again');
  -- K5 (NOT COVERED 5), by hand (no page reaches it): S$40 paid, cancelled,
  -- the S$40 paid back; a release lot holding S$10 again with the line
  -- counting S$10 released. The dialog says S$0.00 given at once (474's
  -- words) and S$90 from the settling payment; the reopening takes the S$10
  -- back (trim) and gives nothing; the S$100 payment then gives S$100.
  perform pg_temp.t478_run('K', 'T5', 'sale A cp 40; cancel; refundpaid; reopen; pay', 1, 3);
  perform pg_temp.t478_by_hand('K/T5', 'trim');
  perform pg_temp.t478_run('K', 'T5', 'sale A cp 40; cancel; refundpaid; reopen; pay', 4, 5);
  perform pg_temp.t478_check((select shownr from t478_dlg where pre = 'K/T5' and n = 4) = 0
      and (select expl from t478_dlg where pre = 'K/T5' and n = 4) = pg_temp.t478_expl474()
      and (select atonce from t478_dlg where pre = 'K/T5' and n = 4) = 0
      and (select trimmed from t478_dlg where pre = 'K/T5' and n = 4) = 10
      and (select shownl from t478_dlg where pre = 'K/T5' and n = 4) = 90
      and (select coalesce(sum(g.credit), 0) from t478_got g where g.pre = 'K/T5' and g.n = 5) = 100,
    'K5 T5: look at NOT COVERED 5 again: ' || (select row_to_json(d)::text from t478_dlg d where pre = 'K/T5' and n = 4));
  -- K10 (NOT COVERED 10): the voucher units to replace after settlement
  -- (451 and 474's figure) are counted, not named by receiver: a bundle paid
  -- in full, a session, cancelled, a 'keep' change to B, reopened (CTLvk):
  -- the note names A for the S$120 reinstated, and the 2 vouchers given again
  -- are A's too (apply_reopened_invoice_vouchers: whoever holds the
  -- benefits, 460 and 463), which the dialog does not say.
  o := pg_temp.t478_run('K', 'CTLvk', 'sale A pbv; spend A 1 bwallet; cancel; change B keep; reopen');
  perform pg_temp.t478_check(pg_temp.t478_meets(o, '{"dlg":120,"dlgv":2,"gavev":2,"rcv":"A:0.00/0/0/0.00/120.00","holds":{"A":"120.00/2","B":"0.00"},"status":"paid","error":null}')
      and coalesce(o->>'invariants', '') = '' and coalesce((o->>'cancel_left')::numeric, 0) = 0
      and not exists (select 1 from jsonb_array_elements((select rcv from t478_dlg where pre = 'K/CTLvk' order by n desc limit 1)) r,
                             jsonb_object_keys(r) k where k ~ 'voucher_units'),
    'K10 CTLvk: look at NOT COVERED 10 again: ' || o::text);
  -- K9 (NOT COVERED 9): the receivers' names, as the customer records have
  -- them when the dialog is opened, are recorded with the preview (PTk: A's).
  a := pg_temp.t478_id('after/PTk/A');
  perform pg_temp.t478_check((select r.snapshot->'reopen_preview'->'credit_receivers'->0->>'customer_name' from invoice_revisions r
                                where r.invoice_id = pg_temp.t478_id('after/PTk/inv') and r.snapshot ? 'reopen_preview'
                               order by r.revision_no desc limit 1) = (select full_name from customers where id = a),
    'K9 PTk: look at NOT COVERED 9 again');
  raise notice 'KNOWN K: (478''s NOT COVERED) (2) the sale record and its commission are not named in the dialog (not asked; PTkvl''s sale record is A''s, the buyer''s)';
  raise notice 'KNOWN K: (478''s NOT COVERED) (5) by hand: a release lot holding S$10 with the line counting S$10 released, the money paid back: the dialog says S$0.00 at once and S$90 from the settling payment; the reopening trims S$10 back and the payment gives S$100';
  raise notice 'KNOWN K: (478''s NOT COVERED) (9) the receivers'' names are recorded with the preview in the reopening''s revision and Audit Log row';
  raise notice 'KNOWN K: (478''s NOT COVERED) (10) the voucher units to replace after settlement are not named by receiver: after a ''keep'' change while cancelled the 2 vouchers given again are A''s (CTLvk), the note names A for the S$120 credit only';
end $$;

rollback;
