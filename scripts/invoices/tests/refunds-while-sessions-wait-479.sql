-- 479: a therapy session waiting for its invoice's reopening to be paid (or
-- once the invoice is cancelled again) can be refunded by line, the
-- sessions refunded coming off what waits, and the invoice's customer can
-- be changed, the waiting sessions going to whoever holds the invoice's
-- benefits; the guided Cancel with "Record refund paid" and the guided
-- Refund in full refund it where their plan comes out in whole sessions and
-- voucher units, are refused as before where their plan was cut to the
-- money held and another of its lines had something to refund, or where it
-- gives money again to a line holding no credit, vouchers or sessions that a
-- refund by line paid back before the reopening (NOT COVERED 17, open), and,
-- as before, offer no session whose money a refund by line paid back before
-- the reopening (475's NOT COVERED 1 and 2, its suite's KNOWN K1 and K2; the
-- Owner, 27 Oct 2026, answer F, and 29 Oct 2026, "Keep today's result" and,
-- ~18:45 SGT, "Keep today's refusal").
-- supabase/479_refunds_and_customer_change_while_sessions_wait.sql (after
-- 476, 477 and 478; production is at 486 since 2 Nov 2026).
--
-- Every step goes through the app's own calls (475's suite harness, its
-- steps and readings, renamed): the invoice form (create_invoice_with_
-- details) and the Pay dialog (record_invoice_settlement), Record Payment,
-- Correct payment (correct_invoice_payment), Cancel, Reopen, the Finance
-- panel's refund by line (of credit, of voucher units: 'backv', of a
-- therapy line's sessions by money: 'backt', of a product line by money with
-- the stock it lists: 'backps') and "Record refund paid", of what is owed
-- back or of an amount (refund_invoice_recorded), the guided Refund in full
-- and Cancel (the plan each reads kept as the case's 'plan'; or the request
-- alone and its approval later, as the plan reads then: 'request',
-- 'approve'), the invoice form's customer change (correct_invoice,
-- 'transfer' or 'keep', its lines as InvoicesPage.tsx sends them: a therapy
-- line with its service), a correction of the notes, the store or the
-- therapy line's quantity, a customer merge. Before each Reopen the Reopen
-- dialog is read as the Finance panel reads it (invoice_reopen_preview).
-- Each app call is followed by what its commit does (462's trigger on the
-- ledger is DEFERRABLE INITIALLY DEFERRED and this suite is one
-- transaction: SET CONSTRAINTS ... IMMEDIATE, then DEFERRED). Steps made by
-- hand, as no function makes them: 'dup' and 'shrink' (475's NOT COVERED 3
-- and 4) and 'hold' (a session held by someone other than its invoice's
-- customer).
--
-- The cases (A the buyer; B, C later customers; K a record a merge keeps;
-- th a therapy line of 3 sessions at S$20, paid S$60; cp the S$100 Credit
-- Package, pbv the S$140 Premium Bundle with 2 vouchers, v a voucher line
-- of 2 units at S$30, pr a S$40 product with stock at the store; S1 a S$20
-- session paid from the package's credit).
-- What a case reads: 475's readings ('sess' each current session as
-- available/purchased, refunded, cancelled and status; 'swait', 'squeued'
-- the waiting rows and what they hold; 'sev' the 'reopen' events; 'sholder'
-- who holds the sessions, 'icust' whose the invoice is; 'sinv' what is
-- wrong with the sessions, as 479 counts it; 'holds' each customer's credit
-- and '/n' held vouchers; the money, the plans, 462's invariants, what
-- Cancel would leave behind; the dialog and what the payment gave; 'stock'
-- the invoice's stock movements by kind; 'plan' the lines of the plan its
-- last guided step read, in their order, and what each refunds: the order
-- is not fixed, so no comparison depends on it).
--   Fixed (before 479 refused at the step 'err0' names; after, as 'expect'):
--   RW, RWp, RW2p a session's refund by line while its reopening waits (one
--               more session; then paid; two more, then paid).
--   RWc, RWw    refunded while it waits, cancelled again, reopened, paid;
--               and refunded again while the second reopening waits.
--   RWpd, RWfx  settled by the Pay dialog; by Correct payment (S$5 -> S$20).
--   RWm, RWmc   the buyer merged into K after the refund; before it, then a
--               second cycle.
--   RF, RFc     refunded in full before the reopening, S$20 (S$40) paid
--               towards it: refunded by line while it waits (before 479:
--               "0 of 3 sessions remain refundable"); a second cycle.
--   RB, RBp, RBw once cancelled again: refunded by line; reopened and paid;
--               refunded while it waited and once cancelled again.
--   GC, GCp     the guided Cancel with "Record refund paid" while it waits;
--               reopened and paid.
--   GRp         the guided Refund in full while it waits, then paid (GR,
--               where it stops, is NOT COVERED 1).
--   KG45, KG45c, KG45p  S$5 paid while it waits (S$45 held): the guided
--               Refund in full and Cancel pay back the S$40 the plan offers
--               (2 whole sessions) and keep the S$5; then paid.
--   KGn40       paid back with no line, reopened, S$40 paid: the guided
--               Refund in full, 2 whole sessions (the plan cut to the money
--               held, but only the therapy line had anything to refund:
--               kept as answer F asked, the Owner, 29 Oct 2026 ~18:45 SGT);
--               then paid.
--   CPw, CPr, CPg, PBw, MXw, MXc  beside a Credit Package refunded by line,
--               the Premium Bundle, a package with a session paid from it and
--               a voucher line.
--   TV, TV2, CPs, PBs  1 of 3 sessions refunded while cancelled, beside a
--               voucher line (either written first), a package or the
--               bundle: the guided Refund in full pays back the sessions'
--               S$40 and the other line's value (the plan not cut), whichever
--               line is listed first; then paid, 1 of 3.
--   TVP, VTP    the same beside a voucher line and a product (two other
--               lines; the therapy line or the voucher line written first).
--   STv         a guided Refund in full requested, S$10 paid, then approved
--               as its plan reads then (not cut), with a voucher line.
--   V4, V5      the same beside a voucher line and a S$40 product refunded
--               by line since the reopening (the Refund in full leaves the
--               product out: one other line), either line written first.
--   Y1s, Y3s, V1s  requested and approved with nothing changed between: a
--               package and a voucher line beside the sessions (the Refund
--               in full; the Cancel), a voucher line and that product (the
--               Cancel, which lists the product at S$0).
--   Z8, Z8c, Z5r, Z5x, Z6, KZ, Z1, Z2  (the third fix review, 3 Nov 2026)
--               only the sessions' line has anything to refund, at their
--               turn and in the plan the request saved, the other lines
--               listed at S$0 (a credit or voucher line refunded by line
--               before the reopening; a product line refunded by line since
--               it, in the guided Cancel): approved after S$10 was paid
--               (Correct payment, Z6; S$5 before the request and S$5 after
--               it, KZ), through, whichever line is listed first.
--   Z9, Z0, Z8s  one S$0 line (a package; the product, the Cancel); nothing
--               changed between: through, as with the builds before.
--   ZGs, ZGsx   the package's S$100 all spent on a session S1 before the
--               cancel, given back between the request and the approval (S1
--               cancelled, its refund recorded), nothing paid between: the
--               package's S$100 and the sessions' S$40 paid back, the
--               package or the sessions written first.
--   ACt, AGCt   a S$100 Credit Package, the sessions and a S$40 product added
--               by a correction ('addlines'), S$20 of the credit spent on
--               another invoice, cancelled, 1 session refunded by line,
--               reopened: the guided Refund in full (Cancel) requested and
--               approved, not cut: the S$160 offered paid back, the S$20
--               kept for the credit spent.
--   VTPd, CTPd, CTP, CTPc, BTP, CFR, BFC, BFR2  the plan not cut beside two
--               other lines, one holding vouchers or credit (an Owner's
--               discount; a package or the bundle and a product; a credit
--               line written first, the rest added by a correction; the
--               guided Cancel): through, whichever line is listed first.
--   WSx         more than the money held, while it waits (now refused for
--               the money).
--   OWak, OWbk, OWbt  the Owner's case (below): after its Refund in full,
--               the S$30 kept refunded by line (before 479: "0 of 3
--               sessions remain refundable"); 'keep' or 'transfer' to B
--               while it waits, then the Refund in full and paid.
--   CTw, CTwp, CTc, CKn, CNN, CNb, CTr  a customer change while it waits,
--               an invoice with only the therapy line (no 'transfer' or
--               'keep' asked): the sessions follow the change.
--   CKv, CTv, CKT, CTK, CKc  with a voucher line: 'keep' (they stay with
--               their holder), 'transfer' (they follow), the two in turn,
--               'keep' then cancelled again.
--   KK2, KK3, KKn, KKs  sessions 'keep' left with A, after the payment: the
--               invoice set back to A; cancelled and reopened; a correction
--               of the notes; a refund by line.
--   Kept (the Owner, 29 Oct 2026, "Keep today's result": exactly the same
--   before 479 and after it, every key, as a control): the therapy line's
--   sessions all refunded by line while the invoice was cancelled, the
--   invoice reopened, another line on it: OWa, OWa2 (the package written
--   first) and OWac (Credit Package, S$30 paid since: the guided Refund in
--   full pays back the S$100, the S$30 kept, the 3 sessions waiting; the
--   guided Cancel the same, S$30 shown due), OWap (then paid: 3 of 3), OWa0
--   (nothing paid since, then paid); OWb, OWb2, OWbc, OWbp, OWb0 (2
--   vouchers, S$20 paid; the voucher line written first; Cancel; then paid;
--   nothing paid since); OWpb, OWpbc (the Premium Bundle; Cancel); OWbm
--   (then merged into K and paid). GRF, GCF (refunded in full before the
--   reopening, S$20 paid since: nothing to refund, no money to return;
--   NOT COVERED 13), GRFk (there the guided Cancel without "Record refund
--   paid", "Record refund paid" with no line, reopened and paid), CRF, VRF
--   (the same for a Credit Package and for vouchers).
--   Controls (the same before 479 and after it): TH0, THc, THcc, RSr, RF0,
--   CSw, CQw (a store or quantity change while it waits: refused), PK, PVK,
--   CNCr, THq, THmg, VQ, K5; (NOT COVERED 16, the review of 2 Nov 2026) A1,
--   AG: a S$100 Credit Package, the sessions and a S$40 product added by a
--   correction, S$20 of the credit spent on another invoice, cancelled, the
--   product's S$40 refunded by line, reopened, S$20 paid, the guided Refund
--   in full (Cancel) requested, the spent S$20 of credit given back (the
--   session invoice cancelled, its refund recorded), approved: the plan
--   carried out cut, the saved one not; A1p (the product added before the
--   sessions), AN (the request raised after the credit came back), A1x (the
--   three lines sold together, the package listed last); ZG, ZGx (the third
--   fix review: ZGs's steps with S$10 paid between, the package written
--   first or the sessions: refused as before 479 whichever line is listed
--   first); and (NOT COVERED
--   17, the fix review of 2 Nov 2026: a product line refunded by line before
--   the reopening, offered again by the guided plan, where the plan reaches
--   a waiting session) AC, AGC (A1's steps with no credit given back: the
--   plan not cut), ACp (AC then paid), AXV, AVX (with a voucher line added
--   after or before the product), TPr, PTr (only the sessions and the
--   product, S$40 paid again: not cut): each refused at the session's turn
--   as before 479, every key.
--   Known (479's NOT COVERED, checked as they are): GR (1), PRn1, PRn2,
--   VPR, PRxk, PRpp (1, a product line: the settling payment takes the
--   product from stock again though its line was refunded; not 479's, 479's
--   Refund in full adding PRn1 and PRn2; 481's), PRT (2), KK1, CKK, CKq (3:
--   once paid; while they wait), Kdup, Kdupc and Kshr (7), KGn, KGnc, TVn
--   (10: paid back with no line, reopened, part paid again: the plan's cut
--   is not whole units, refused before 479 and after it), KRd, KRdc, KRdk,
--   KRd1, KRd2, KRdp (14: half a cent), OWacR, OWac20R, CPs5, CPs5k, OWpbcR,
--   OWpbc20, OWbcR (15: a Cancel's money due on an invoice that issued
--   credit cannot be recorded with no line; not 479's), STvp (16: approved
--   after the invoice changed, two other lines: refused as before 479,
--   though the plan carried out is not cut), Y1 to Y4, V1 to V3 (16, the
--   second fix review, 3 Nov 2026: the same where no other line offers
--   anything at the session's turn, a package and vouchers or vouchers and
--   a product refunded by line since the reopening beside the sessions,
--   each written in two or three orders: refused as before 479 in every
--   order; the build before let Y1, Y3 and V1 through where those lines
--   were listed before the sessions'), P3, ACnC, AGCnC (17: a product
--   line refunded before the reopening refunded again where the plan reaches
--   no waiting session: 478's, the same before 479; ACnC, AGCnC with no
--   sessions keep a S$20 session paid from credit with all the money paid
--   back), TP2c (17: refused as before 479 though the product was charged
--   and paid again since the refund).
--   The cut plans, by line order (479's NOT COVERED 10 and 17, t479_ocases:
--   a plan cut to the money held in the order the lines are listed, each run
--   with its lines written both ways and checked for the line its plan lists
--   first, before 479 and after it the same): TVn60a/b, TVn60ca/cb (3
--   sessions and 2 vouchers paid back with no line, reopened, S$60 paid:
--   Refund in full, then paid; Cancel), TVn20a/b (S$20 paid), PRxr1/2,
--   PRx1/2, PRxc1/2 (a S$40 product refunded by line while cancelled,
--   reopened: Refund in full; then paid; Cancel), PRnl1/2 (the product's S$40
--   paid back with no line instead), VTPc, VTPc2 (vouchers, sessions and a
--   product, S$130 of S$160 paid again): refused as before 479 wherever the
--   cut gives the waiting sessions some of the money; P1a/b, P5a/b, P4a/b (a
--   product refunded before the reopening, with vouchers, or with sessions
--   the cut gives nothing to: as before 479, the product's line refunded
--   again; NOT COVERED 17).
-- In every case 462's invariants (475's reading of them), the sessions' own
-- (above) and Cancel (tried, undone) taking all of the invoice's credit back
-- from whoever holds it.
--
--   S. Where it starts: 475 to 478 in; 479 in (nomig) or not, the three
--      functions at their BEFORE; the refund options as they are (479 does
--      not change them).
--   R. Without 479 (skipped with -v nomig=1), undone: each fixed and known
--      case refused at its step ('err0'), each control, kept and known case
--      as expected; each case of t479_ocases as expected for the line its
--      plan lists first.
--   Q. The read-only query in 479's header (the same text), on states made
--      for it and the R states: what it lists, by reason (1 to 3).
--   9. Refusals, each changing nothing: a function of the three not as
--      tested; a partial install; a function it relies on not as tested
--      (the refund options among them); an overload of a name; a new
--      caller; a new reader or writer of the session queue, of the
--      sessions, of their events, of reopened_at, of 460's row or of the
--      check a guided flow's refund leaves (invoice.therapy_plan_check); the
--      settlement trigger not as read; the events not stamped by
--      clock_timestamp(); the queue's key gone; other grants. The same
--      grants in another order do not stop it.
--   M. Begun before 479 (waiting; cancelled again; a voucher line waiting),
--      finished after it.
--  10. 479 installed twice: as tested, the second run changing nothing,
--      nothing added, the grants as before, the refund options unchanged.
--   A. Each case after 479: as expected; a fixed case up to the step refused
--      before 479 exactly as before 479 (the plans too: 479 changes neither
--      the refund options nor the plans); a control, kept or known case
--      exactly as before 479 (the plan's lines compared in no order; one
--      whose plan was cut in another order before 479, by what does not
--      follow the order).
--   P. Probes: the three texts beside 479's parts exactly as before (worked
--      back, by md5); the Audit Log rows and events 479 writes; nothing
--      added; the grants; the refund options of a session that waits (as
--      before 479).
--   K. KNOWN (479's NOT COVERED), checked as they are: 1 (GR, KG45, TV; a
--      product line: PRn1, PRn2, VPR, PRxk, PRpp, no stock report flagging
--      them), 2 (PRT), 3 (KK1; while they wait CKK, CKT, CKq), 7 (Kdup,
--      Kdupc, Kshr), 10 (KGn, KGnc, TVn: whichever line is listed first; the
--      cases of t479_ocases after 479, each for the line its plan lists
--      first, and exactly as before 479 where R listed the same lines in the
--      same order), 13 (GRF, GCF, CRF, VRF; RF and GRFk go through; the
--      Finance panel's sessions note), 14 (KRd, KRdc, KRdk, KRd1, KRd2,
--      KRdp: half a cent), 15 (OWacR, OWac20R, CPs5, CPs5k, OWpbcR, OWpbc20,
--      OWbcR), 16 (STvp; STv goes through; A1, AG, A1p, AN, A1x, AXV, AVX
--      refused at the session's turn; Y1 to Y4, V1 to V3 refused whichever
--      line is listed first, V4, V5, Y1s, Y3s, V1s through; only the
--      sessions' line having anything to refund, Z8, Z8c, Z5r, Z5x, Z6, KZ,
--      Z1, Z2, Z9, Z0, Z8s, ZGs, ZGsx through, ZG and ZGx refused, whichever
--      line is listed first), 17 (where the
--      plan reaches a waiting session refused as before 479: AC, AGC, ACp,
--      AXV, AVX, TPr, PTr, TP2c;
--      where it does not, as before 479, the product's line refunded again:
--      P3, ACnC, AGCnC; P1, P4, P5 of t479_ocases).
--
-- Run on a copy of production at 486 (2 Nov 2026: 987d9ea6, 1398
-- functions; at 485, d5bcc0ce, it runs the same, 486 having changed the
-- merge preview alone; this build was not run at 478, 29 Oct 2026:
-- eae7f82f, 1390):
--   psql -X -v ON_ERROR_STOP=1 -f scripts/invoices/tests/refunds-while-sessions-wait-479.sql
-- It installs 479 itself (twice) inside its transaction. Where 479 is in
-- already, add -v nomig=1 (S checks it as tested; R, Q, 9 and M are
-- skipped; every case after 479 is still checked). Section 9 lets the
-- install fail on purpose (psql prints its ERROR); the suite then checks
-- that message. Disposable database only; everything is rolled back. Every
-- name, code and amount is invented (@example.com); the phones are numbers
-- kept for fiction (ACMA, +61491570000 to +61491570999).
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '10s';
set local statement_timeout = '1800s';

-- ── Set-up and the app's calls (475's suite harness, for 479) ────────────────
create temp table t479(k text primary key, id uuid);
create temp table t479_res(phase text, k text, v jsonb, primary key (phase, k));
create temp table t479_fp(k text primary key, fp text);
create temp sequence t479_phone;
create function pg_temp.t479_id(p_k text) returns uuid language sql as $f$ select id from t479 where k = p_k $f$;
create function pg_temp.t479_put(p_k text, p_id uuid) returns uuid language sql as $f$
  insert into t479 values (p_k, p_id) on conflict (k) do update set id = excluded.id returning id $f$;
create function pg_temp.t479_check(p_ok boolean, p_label text) returns void language plpgsql as $f$
begin
  if not coalesce(p_ok, false) then raise exception 'FAIL %', p_label; end if;
end $f$;
create function pg_temp.t479_fingerprint() returns text language sql as $f$
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.oid::regprocedure::text)) || ' ' || count(*)
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prokind in ('f', 'p') $f$;
create function pg_temp.t479_462_in() returns boolean language sql as $f$
  select to_regprocedure('public.credit_given_back_follows(uuid)') is not null
     and exists (select 1 from pg_trigger where tgname = 'credit_given_back_follows'
                  and tgrelid = 'public.customer_credit_ledger'::regclass) $f$;
-- What is in (each by the "-- 47N (the Owner" line of a function it wrote):
-- 475 (reopen_invoice), 476 (invoice_transferable_benefits), 477
-- (transfer_invoice_unused_benefit), 478 (the Reopen dialog's preview).
create function pg_temp.t479_475_in() returns boolean language sql as $f$
  select position('-- 475 (the Owner, 27 Oct 2026' in pg_get_functiondef('public.reopen_invoice(uuid,text,uuid)'::regprocedure)) > 0 $f$;
create function pg_temp.t479_476_in() returns boolean language sql as $f$
  select position('-- 476 (the Owner, 27 Oct 2026' in pg_get_functiondef('public.invoice_transferable_benefits(uuid)'::regprocedure)) > 0 $f$;
create function pg_temp.t479_477_in() returns boolean language sql as $f$
  select position('-- 477 (the Owner, 27 Oct 2026' in pg_get_functiondef('public.transfer_invoice_unused_benefit(uuid,uuid,uuid,text,uuid)'::regprocedure)) > 0 $f$;
create function pg_temp.t479_478_in() returns boolean language sql as $f$
  select position('-- 478 (the Owner, 27 Oct 2026' in pg_get_functiondef('public.invoice_reopen_preview_before_sessions(uuid)'::regprocedure)) > 0 $f$;
-- 479 is in: the refund's text says so (S checks all three by md5).
create function pg_temp.t479_in() returns boolean language sql as $f$
  select position('-- 479 (the Owner, 27 Oct 2026' in pg_get_functiondef('public.refund_invoice_therapy_sessions(uuid,numeric,text,uuid)'::regprocedure)) > 0 $f$;
-- What a commit does at the end of each app call (each is its own
-- transaction in the app): 462's deferred trigger on the ledger runs (479
-- adds no trigger, and changes nothing a commit does). Here
-- the suite is one transaction, so the trigger's queued rows are run at this
-- point. (Not where each step really commits: t479.autocommit 'on', for
-- running the same cases one call per transaction on a disposable copy.)
create function pg_temp.t479_commit() returns void language plpgsql as $f$
begin
  if coalesce(current_setting('t479.autocommit', true), '') = 'on' then return; end if;
  if pg_temp.t479_462_in() then
    execute 'set constraints public.credit_given_back_follows immediate';
    execute 'set constraints public.credit_given_back_follows deferred';
  end if;
end $f$;

do $$
declare own uuid := gen_random_uuid(); st uuid; st2 uuid; pm uuid; v uuid; cp uuid; cpb uuid; pbv uuid; svc uuid; svc5 uuid; prod uuid;
begin
  insert into auth.users(id, email) values (own, 't479-owner@example.com');
  insert into profiles(id, full_name, email, role, is_active) values (own, 'T479 Owner', 't479-owner@example.com', 'owner', true);
  perform set_config('request.jwt.claims', json_build_object('sub', own, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', own::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  insert into stores(name, code, country_code) values ('T479 Store', 'T479S1', 'SG') returning id into st;
  insert into stores(name, code, country_code) values ('T479 Other Store', 'T479S2', 'SG') returning id into st2;
  insert into payment_methods(name, is_active) values ('T479 Cash', true) returning id into pm;
  insert into vouchers(name, code, voucher_kind, qty_type, selling_price, is_active)
    values ('T479 Plain 30', 'T479-P30', 'normal', 'unlimited', 30, true) returning id into v;
  insert into voucher_store_prices(voucher_id, store_id, selling_price, available_at_store) values (v, st, 30, true), (v, st2, 30, true);
  insert into credit_packages(name, customer_price, paid_credit_amount, bonus_enabled, allow_product, allow_therapy)
    values ('T479 S$100', 100, 100, false, true, true) returning id into cp;
  insert into credit_package_stores(package_id, store_id) values (cp, st), (cp, st2);
  insert into credit_packages(name, customer_price, paid_credit_amount, bonus_enabled, bonus_value, allow_product, allow_therapy, grants_reward)
    values ('T479 S$100 + S$10', 100, 100, true, 10, true, true, false) returning id into cpb;
  insert into credit_package_stores(package_id, store_id) values (cpb, st), (cpb, st2);
  insert into premium_bundles(name, customer_payment_amount, paid_credit_amount, bonus_credit_amount, free_voucher_qty, grants_reward)
    values ('T479 Bundle S$140 + 2 vouchers', 140, 100, 40, 2, true) returning id into pbv;
  insert into premium_bundle_stores(bundle_id, store_id) values (pbv, st), (pbv, st2);
  insert into premium_bundle_vouchers(bundle_id, voucher_id) values (pbv, v);
  svc := (upsert_therapy_service(null, 'T479-SESSION', 'T479 Session', 20, 30, 'per_hours', 1, 5, null, true, null) ->> 'id')::uuid;
  perform set_therapy_service_store(svc, st, true, null);
  svc5 := (upsert_therapy_service(null, 'T479-SHORT', 'T479 Short session', 5, 15, 'per_hours', 1, 5, null, true, null) ->> 'id')::uuid;
  perform set_therapy_service_store(svc5, st, true, null);
  -- a S$40 product with stock at the store (the review of 29 Oct 2026: a
  -- product line beside the sessions, NOT COVERED 1 and 10)
  insert into products(name, sku, product_type) values ('T479 Socks', 'T479-SOCKS', 'own') returning id into prod;
  insert into store_inventory(store_id, product_id, current_qty) values (st, prod, 100);
  perform set_product_prices(st, prod, 40, 40, 'available');
  insert into t479 values ('own', own), ('store', st), ('store2', st2), ('pm', pm), ('v', v), ('cp', cp), ('cpb', cpb), ('pbv', pbv),
    ('svc', svc), ('svc5', svc5), ('prod', prod),
    ('wallet', (select id from payment_methods where name = 'Wallet — Credit Package Paid' and is_wallet_credit and deleted_at is null)),
    ('bwallet', (select id from payment_methods where name = 'Wallet — Premium Bundle Paid' and is_wallet_credit and deleted_at is null));
  perform pg_temp.t479_check(pg_temp.t479_id('wallet') is not null and pg_temp.t479_id('bwallet') is not null, 'setup: the wallet methods (443) are there');
end $$;

-- A customer of one run of one case: '<phase>/<case>/<role>'.
create function pg_temp.t479_cust(p_k text) returns uuid language plpgsql as $f$
declare c uuid;
begin
  insert into customers(full_name, phone) values ('T479 ' || p_k, '+61491570' || lpad((nextval('t479_phone') % 1000)::text, 3, '0'))
    returning id into c;
  return pg_temp.t479_put(p_k, c);
end $f$;
-- The invoice form with these lines ('cp' / 'cpb' a Credit Package, 'pbv' the
-- Premium Bundle, 'v' a voucher line of p_qty units, 'th' three sessions of
-- S$20, 'th4' four, 'pr' one S$40 product), with an Owner's manual
-- discount of p_discount (its reason given) where one is given, paid through
-- the Pay dialog: in full, or p_first of it (a part-paid package).
create function pg_temp.t479_sale(p_cust uuid, p_kinds text[], p_first numeric default null, p_qty int default 2,
                                  p_discount numeric default null)
  returns uuid language plpgsql as $f$
declare inv uuid; v_lines jsonb := '[]'; i int;
begin
  for i in 1 .. cardinality(p_kinds) loop
    v_lines := v_lines || jsonb_build_array(case
      when p_kinds[i] = 'v' then jsonb_build_object('kind', 'voucher', 'voucher_id', pg_temp.t479_id('v'), 'quantity', p_qty)
      -- a therapy line of three S$20 sessions (the dialog's sessions)
      when p_kinds[i] = 'th' then jsonb_build_object('kind', 'therapy', 'therapy_service_id', pg_temp.t479_id('svc'), 'quantity', 3)
      when p_kinds[i] = 'th4' then jsonb_build_object('kind', 'therapy', 'therapy_service_id', pg_temp.t479_id('svc'), 'quantity', 4)
      when p_kinds[i] = 'pr' then jsonb_build_object('kind', 'product', 'product_id', pg_temp.t479_id('prod'), 'quantity', 1)
      when p_kinds[i] in ('cp', 'cpb') then jsonb_build_object('kind', 'credit_package', 'credit_package_id', pg_temp.t479_id(p_kinds[i]), 'quantity', 1)
      else jsonb_build_object('kind', 'premium_bundle', 'premium_bundle_id', pg_temp.t479_id('pbv'), 'quantity', 1,
        'voucher_selection', jsonb_build_array(jsonb_build_object('voucher_id', pg_temp.t479_id('v'), 'quantity', 2))) end);
  end loop;
  inv := create_invoice_with_details(pg_temp.t479_id('store'), p_cust, v_lines, jsonb_build_object('business_date', sg_today()::text)
           || case when p_discount is not null
                   then jsonb_build_object('manual_discount', p_discount, 'manual_discount_reason', 'T479 discount') else '{}'::jsonb end);
  perform record_invoice_settlement(inv, jsonb_build_object('receipts', jsonb_build_array(jsonb_build_object(
    'key', 'line-0', 'payment_method_id', pg_temp.t479_id('pm'),
    'amount', coalesce(p_first, (select total_amount from invoices where id = inv)),
    'payment_date', sg_today()::text)), 'arrangements', '[]'::jsonb), gen_random_uuid());
  return inv;
end $f$;
-- Record Payment of what is outstanding (nothing when it is settled).
create function pg_temp.t479_pay(p_inv uuid) returns void language plpgsql as $f$
begin
  if (invoice_financial_position(p_inv)->>'outstanding')::numeric > 0 then
    perform record_invoice_payment(p_inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.t479_id('pm'),
      'amount', (invoice_financial_position(p_inv)->>'outstanding')::numeric)), gen_random_uuid());
  end if;
end $f$;
-- The receipts that still hold p_amount between them, as the Finance panel
-- splits a refund across them.
create function pg_temp.t479_sources(p_inv uuid, p_amount numeric) returns jsonb language plpgsql as $f$
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
-- 475: line N of an invoice, its credit lines first, then its voucher lines,
-- then its therapy lines (an invoice's lines have no order of their own;
-- THmix has a package, a voucher and a therapy line, THvs a voucher and a
-- therapy line).
create function pg_temp.t479_line(p_inv uuid, p_n int default 1) returns uuid language sql as $f$
  select id from invoice_items where invoice_id = p_inv
   order by case when line_kind in ('credit_package', 'premium_bundle') then 0 when line_kind = 'voucher' then 1
                 when therapy_service_id is not null then 2 else 3 end, id offset p_n - 1 limit 1 $f$;
-- The Finance panel's refund by line of line p_n: p_amount off its Paid
-- benefit (the one an Owner did not move, or with p_holder the one p_holder
-- holds), or every unused benefit it still holds (p_amount null).
create function pg_temp.t479_back(p_inv uuid, p_n int, p_amount numeric default null, p_holder uuid default null)
  returns void language plpgsql as $f$
declare opts jsonb; ben jsonb; tot numeric; item uuid := pg_temp.t479_line(p_inv, p_n);
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
  if ben is null then raise exception 'T479: nothing to refund on that line'; end if;
  perform refund_invoice_recorded(p_inv, jsonb_build_array(jsonb_build_object('invoice_item_id', item, 'amount', tot, 'benefits', ben)),
    pg_temp.t479_sources(p_inv, tot), '[]'::jsonb, 'T479 by line', gen_random_uuid());
end $f$;
-- The invoice form's customer change, its lines as they are (a therapy
-- line with its service, as InvoicesPage.tsx sends it; and the store, when
-- given), with 'transfer' or 'keep'. The change's Audit Log row is dated
-- now, as a later call's is (the suite is one transaction).
create function pg_temp.t479_lines(p_inv uuid) returns jsonb language sql as $f$
  select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('invoice_item_id', it.id, 'kind', it.line_kind,
           'credit_package_id', it.credit_package_id, 'premium_bundle_id', it.premium_bundle_id, 'voucher_id', it.voucher_id,
           'therapy_service_id', it.therapy_service_id, 'product_id', it.product_id,
           'quantity', it.quantity, 'unit_price', it.unit_price, 'voucher_selection', it.bundle_voucher_selection)) order by it.id)
    from invoice_items it where it.invoice_id = p_inv $f$;
create function pg_temp.t479_change(p_inv uuid, p_cust uuid, p_action text default 'transfer', p_store text default null)
  returns void language plpgsql as $f$
begin
  perform correct_invoice(p_inv, pg_temp.t479_lines(p_inv),
    jsonb_build_object('expected_edit_count', (select edit_count from invoices where id = p_inv),
      'customer_id', p_cust, 'store_id', coalesce(pg_temp.t479_id(p_store), (select store_id from invoices where id = p_inv)),
      'benefit_action', p_action),
    'T479 wrong customer', gen_random_uuid());
  update audit_logs set created_at = clock_timestamp()
   where record_id = p_inv and action = 'invoice_benefits_followed_reassignment' and new_data->>'to_customer' = p_cust::text
     and created_at = now();
end $f$;
create function pg_temp.t479_merge(p_keep uuid, p_dup uuid) returns void language plpgsql as $f$
begin
  perform merge_customer_records(p_keep, p_dup, 'T479 the same person', gen_random_uuid());
end $f$;
-- The invoice form: p_n sessions of S$20 (or S$5 with p_svc 'svc5') for
-- p_cust, paid with the wallet (Credit Package Paid; Premium Bundle Paid with
-- p_wallet 'bwallet') through Record Payment.
create function pg_temp.t479_spend(p_cust uuid, p_n int default 1, p_svc text default 'svc', p_wallet text default 'wallet')
  returns uuid language plpgsql as $f$
declare inv uuid; v_lines jsonb := '[]'; i int;
begin
  for i in 1 .. p_n loop
    v_lines := v_lines || jsonb_build_array(jsonb_build_object('kind', 'therapy', 'therapy_service_id', pg_temp.t479_id(p_svc), 'quantity', 1));
  end loop;
  inv := create_invoice_with_details(pg_temp.t479_id('store'), p_cust, v_lines, jsonb_build_object('business_date', sg_today()::text));
  perform record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.t479_id(p_wallet),
    'amount', (select total_amount from invoices where id = inv))), gen_random_uuid());
  if (select status::text from invoices where id = inv) <> 'paid' then raise exception 'T479: the session paid from credit is not paid'; end if;
  return inv;
end $f$;
-- The session cancelled and "Record refund paid": what its payment took goes
-- back to the lots it came from (refund_invoice_recorded's wallet refund).
create function pg_temp.t479_unspend(p_inv uuid) returns void language plpgsql as $f$
declare due numeric;
begin
  perform cancel_invoice_recorded(p_inv, 'T479 cancel session', gen_random_uuid());
  due := (invoice_financial_position(p_inv)->>'refund_due')::numeric;
  if due is null or due <= 0 then due := (invoice_action_plan(p_inv, 'cancel', '[]')->>'refund_due')::numeric; end if;
  perform refund_invoice_recorded(p_inv, jsonb_build_array(jsonb_build_object('amount', due)), pg_temp.t479_sources(p_inv, due), '[]'::jsonb,
    'T479 refund paid', gen_random_uuid());
end $f$;
-- The guided Refund in full / Cancel as an Owner confirms it, with a reason
-- for every override the plan asks for, the money recorded as paid back (or,
-- with p_record false, not: "Record refund paid" left unticked).
create function pg_temp.t479_guided(p_inv uuid, p_action text, p_record boolean default true) returns void language plpgsql as $f$
declare plan jsonb; req jsonb; ov jsonb;
begin
  plan := invoice_action_plan(p_inv, p_action, '[]');
  req := request_invoice_action_v2(p_inv, p_action, '[]', 'T479 ' || p_action, null, gen_random_uuid());
  select coalesce(jsonb_agg(case when coalesce((o->>'amount_required')::boolean, false)
           then jsonb_build_object('code', o->>'code', 'reason', 'T479 override', 'amount', (o->>'default_amount')::numeric)
           else jsonb_build_object('code', o->>'code', 'reason', 'T479 override') end), '[]'::jsonb)
    into ov from jsonb_array_elements(coalesce(plan->'overrides_required', '[]')) o;
  perform resolve_invoice_action_v2((req->>'request_id')::uuid, true, 'T479 ' || p_action, plan->>'plan_hash', ov, null, p_record);
end $f$;


-- ── What the records say ────────────────────────────────────────────────────
-- The lots an invoice's records name: its benefit values, its sale's lots, a
-- split's issued lot, released credit (credit_package_progress_lots).
create function pg_temp.t479_named(p_inv uuid) returns setof uuid language sql as $f$
  select lot_id from invoice_benefit_values where invoice_id = p_inv and lot_id is not null
  union select x from credit_package_sales s, unnest(array[s.credit_lot_id, s.bonus_credit_lot_id]) x where s.invoice_id = p_inv and x is not null
  union select x from premium_bundle_sales s, unnest(array[s.paid_credit_lot_id, s.bonus_credit_lot_id]) x where s.invoice_id = p_inv and x is not null
  union select issued_lot_id from invoice_credit_splits where invoice_id = p_inv and issued_lot_id is not null
  union select lot_id from credit_package_progress_lots where invoice_id = p_inv $f$;
-- The invoice's lot family (the critic's 6): every lot its records name and
-- each Move's two lots (from the Move's ledger rows), the lots each replaced
-- and every lot reissued from any of them.
create function pg_temp.t479_family(p_inv uuid) returns setof uuid language sql as $f$
  with recursive seed as (
    select x as id from pg_temp.t479_named(p_inv) x
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
create function pg_temp.t479_behind(p_inv uuid) returns setof uuid language sql as $f$
  with recursive c(id, n) as (
    select lot_id, 0 from invoice_benefit_values where invoice_id = p_inv and lot_id is not null
    union select p.id, c.n + 1 from c join customer_credit_lots l on l.id = c.id
            join customer_credit_lots p on p.id = l.reassigned_from_lot_id
             and (p.source_type, p.source_record_id) is not distinct from (l.source_type, l.source_record_id)
           where c.n < 12)
  select distinct id from c $f$;
-- How many lots back a lot's chain goes (reassigned_from_lot_id).
create function pg_temp.t479_depth(p_lot uuid) returns int language sql as $f$
  with recursive c(id, n) as (select p_lot, 0 union all
    select l.reassigned_from_lot_id, c.n + 1 from c join customer_credit_lots l on l.id = c.id
     where l.reassigned_from_lot_id is not null and c.n < 40)
  select max(n) from c $f$;
-- A lot's balance by its ledger rows: credit added (grants, increases,
-- credit returned: the 'reverse' rows that put credit back, as the
-- statement reads them, and 'rental_late_fee'), less credit taken (uses,
-- decreases, real reversals).
create function pg_temp.t479_ledger_balance(p_lot uuid) returns numeric language sql as $f$
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
create function pg_temp.t479_invariants(p_inv uuid) returns text language plpgsql as $f$
declare probs text := ''; l record; root record; v uuid; st text := (select status::text from invoices where id = p_inv);
begin
  for l in select cl.* from customer_credit_lots cl where cl.id in (select pg_temp.t479_family(p_inv)) loop
    if l.remaining_amount > 0 and l.id not in (select pg_temp.t479_named(p_inv)) then
      probs := probs || format(' S$%s on a lot no record names (%s);', l.remaining_amount, (select full_name from customers where id = l.customer_id)); end if;
    if l.id not in (select pg_temp.t479_named(p_inv)) and l.id not in (select pg_temp.t479_behind(p_inv))
       and (exists (select 1 from invoice_line_credit_allocations a where a.lot_id = l.id and a.amount > coalesce(a.reversed_amount, 0))
            or exists (select 1 from special_credit_allocations s where s.lot_id = l.id and s.amount > coalesce(s.reversed_amount, 0))) then
      probs := probs || ' a sale paid from a lot no record names can still be refunded (its credit would stay there);'; end if;
    if pg_temp.t479_ledger_balance(l.id) <> l.remaining_amount then
      probs := probs || format(' lot holds %s, its ledger %s;', l.remaining_amount, pg_temp.t479_ledger_balance(l.id)); end if;
    if pg_temp.t479_depth(l.id) > 12 then probs := probs || format(' chain %s lots deep;', pg_temp.t479_depth(l.id)); end if;
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
  if st = 'refunded' and (select coalesce(sum(remaining_amount), 0) from customer_credit_lots where id in (select pg_temp.t479_family(p_inv))) > 0 then
    probs := probs || format(' refunded, but S$%s of its credit is still held;',
      (select sum(remaining_amount) from customer_credit_lots where id in (select pg_temp.t479_family(p_inv)))); end if;
  return probs;
end $f$;
-- Credit left on the invoice's family once Cancel has run, the Cancel undone
-- (0 when Cancel takes it all back from whoever holds it); null when the
-- invoice cannot be cancelled now, -1 when Cancel is refused.
create function pg_temp.t479_cancel_left(p_inv uuid) returns numeric language plpgsql as $f$
declare v numeric;
begin
  if (select status::text from invoices where id = p_inv) not in ('paid', 'partially_paid', 'unpaid') then return null; end if;
  begin
    perform cancel_invoice_recorded(p_inv, 'T479 probe', gen_random_uuid());
    perform pg_temp.t479_commit();
    v := (select coalesce(sum(remaining_amount), 0) from customer_credit_lots where id in (select pg_temp.t479_family(p_inv)));
    raise exception using errcode = 'P0461', message = v::text;
  exception when sqlstate 'P0461' then return sqlerrm::numeric;
            when others then return -1;
  end;
end $f$;
create function pg_temp.t479_codes(p_inv uuid, p_action text) returns text language plpgsql as $f$
begin
  return (select coalesce(string_agg(o->>'code', ',' order by o->>'code'), '-')
            from jsonb_array_elements(coalesce(invoice_action_plan(p_inv, p_action, '[]')->'overrides_required', '[]')) o);
exception when others then return 'ERR';
end $f$;
create function pg_temp.t479_due(p_inv uuid, p_action text) returns numeric language plpgsql as $f$
begin
  return (invoice_action_plan(p_inv, p_action, '[]')->>case when p_action = 'cancel' then 'refund_due' else 'refund_amount' end)::numeric;
exception when others then return null;
end $f$;
-- The invoice's money: what is owed back (cancel_refund_owed), the Finance
-- panel's refund due, net received and kept for what was used, what a
-- refund by line can still pay back (the refund options' max_refund, every
-- benefit) and Cancel's refund due (the plan's).
create function pg_temp.t479_money(p_inv uuid) returns jsonb language sql as $f$
  select jsonb_build_object('owed', i.cancel_refund_owed,
    'due', (invoice_financial_position(i.id)->>'refund_due')::numeric,
    'net', (invoice_financial_position(i.id)->>'net_received')::numeric,
    'kept', (invoice_financial_position(i.id)->>'kept_for_used')::numeric,
    'by_line', (select coalesce(sum((b->>'max_refund')::numeric), 0)
                  from jsonb_array_elements(invoice_refund_options_before_sessions(i.id)->'benefits') b),
    'plan_due', pg_temp.t479_due(i.id, 'cancel'))
    from invoices i where i.id = p_inv $f$;


-- ── The cases ───────────────────────────────────────────────────────────────
-- A case is a list of steps, each one app call (and its commit), on the
-- case's own customers (A the buyer, B a later customer, K a record a merge
-- keeps). A step refused stops the case, the refusal recorded. Steps:
--   sale R kinds [first]  the invoice (th, th4, cp, pbv, v, pr; part-paid: first)
--   saled R kinds disc    the same, paid in full, with an Owner's manual discount of disc
--   pay                   Record Payment of what is outstanding
--   paydlg                the Pay dialog (record_invoice_settlement) of what is outstanding
--   payamt amt            Record Payment of amt (its receipt kept for fixpay)
--   fixpay amt            Correct payment of that receipt to amt (correct_invoice_payment)
--   back N amt|all [R]    refund by line of line N's credit (R: the benefit R holds)
--   backv N units         a refund by line of that many voucher units of line N
--   backt N amt           a refund by line of a therapy line by money (whole sessions)
--   backps N amt          a refund by line of a product line by money, the stock the
--                         Finance panel lists as not yet resolved returned as sellable
--   cancel, reopen        Cancel; Reopen
--   refundall             the guided Refund in full, recorded
--   guidedcancel          the guided Cancel as an Owner confirms it, "Record refund paid" ticked
--   guidedkeep            the same, "Record refund paid" not ticked
--   request A, approve    the guided request (A: refund_full or cancel) alone; an Owner
--                         approving it later as its plan reads then ("Record refund paid")
--   refundpaid            "Record refund paid" of what the invoice owes back (no line)
--   paidback amt          "Record refund paid" of amt (no line)
--   change R [keep|page]  the customer change ('transfer' unless keep; page: as the invoice
--                         form sends it, a choice only where one is asked, 'transfer')
--   merge KEEP DUP        a customer merge
--   note                  the invoice form: its notes changed, nothing else (correct_invoice)
--   store S2              the invoice form: moved to the other store, nothing else
--   qty N                 the invoice form: the therapy line's quantity set to N
--   addlines kinds        the invoice form: lines added (th, pr, v: 2 vouchers), the others kept
--   hold R                BY HAND (no function did it before 479): the invoice's
--                         current sessions held by R, the invoice still its customer's
--   spend R [n] [bwallet] a session invoice for R paid from credit
--   unspend Sn            that session cancelled and its refund recorded
--   dup                   BY HAND (no function does it since 475): a second waiting
--                         row for each waiting session of the invoice, as a reopening
--                         queued it before 475 (475's NOT COVERED 3)
--   shrink                BY HAND (no function does it): each waiting row of the
--                         invoice one less than its session shows (475's NOT COVERED 4)
create function pg_temp.t479_role(p_pre text, p_r text) returns uuid language plpgsql as $f$
begin
  return coalesce(pg_temp.t479_id(p_pre || '/' || p_r), pg_temp.t479_cust(p_pre || '/' || p_r));
end $f$;
-- One step of a case (one app call, then what its commit does). Null, or
-- the step and the refusal; a refused step changes nothing.
create function pg_temp.t479_step(p_pre text, p_st text) returns text language plpgsql as $f$
declare w text[] := regexp_split_to_array(btrim(p_st), '\s+'); inv uuid := pg_temp.t479_id(p_pre || '/inv'); x uuid; n int;
begin
  case w[1]
  when 'sale' then
    perform pg_temp.t479_put(p_pre || '/inv', pg_temp.t479_sale(pg_temp.t479_role(p_pre, w[2]), string_to_array(w[3], ','), w[4]::numeric));
  when 'saled' then
    perform pg_temp.t479_put(p_pre || '/inv', pg_temp.t479_sale(pg_temp.t479_role(p_pre, w[2]), string_to_array(w[3], ','), null, 2, w[4]::numeric));
  when 'pay' then perform pg_temp.t479_pay(inv);
  when 'paydlg' then
    perform record_invoice_settlement(inv, jsonb_build_object('receipts', jsonb_build_array(jsonb_build_object(
      'key', 'line-0', 'payment_method_id', pg_temp.t479_id('pm'),
      'amount', (invoice_financial_position(inv)->>'outstanding')::numeric, 'payment_date', sg_today()::text)),
      'arrangements', '[]'::jsonb), gen_random_uuid());
  when 'payamt' then
    x := gen_random_uuid();
    perform record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.t479_id('pm'),
      'amount', w[2]::numeric)), x);
    perform pg_temp.t479_put(p_pre || '/pay/receipt',
      (select p.id from invoice_payments p where p.invoice_id = inv and p.entry_kind = 'receipt' and p.amount = w[2]::numeric
          and not exists (select 1 from invoice_payments q where q.corrects_payment_id = p.id)
        order by p.created_at desc, p.id limit 1));
  when 'fixpay' then
    perform correct_invoice_payment(pg_temp.t479_id(p_pre || '/pay/receipt'), w[2]::numeric, sg_today(),
      (select payment_method_id from invoice_payments where id = pg_temp.t479_id(p_pre || '/pay/receipt')),
      'T479 correct payment', gen_random_uuid());
  when 'back' then
    perform pg_temp.t479_back(inv, w[2]::int, case when w[3] = 'all' then null else w[3]::numeric end,
                              case when w[4] is not null then pg_temp.t479_role(p_pre, w[4]) end);
  when 'cancel' then perform cancel_invoice_recorded(inv, 'T479 cancel', gen_random_uuid());
  when 'reopen' then perform reopen_invoice(inv, 'T479 reopen', gen_random_uuid());
  when 'refundall' then perform pg_temp.t479_guided(inv, 'refund_full');
  when 'guidedcancel' then perform pg_temp.t479_guided(inv, 'cancel');
  when 'guidedkeep' then perform pg_temp.t479_guided(inv, 'cancel', false);
  when 'refundpaid' then
    perform refund_invoice_recorded(inv, jsonb_build_array(jsonb_build_object('amount',
        coalesce(nullif((invoice_financial_position(inv)->>'refund_due')::numeric, 0), (invoice_action_plan(inv, 'cancel', '[]')->>'refund_due')::numeric))),
      pg_temp.t479_sources(inv, coalesce(nullif((invoice_financial_position(inv)->>'refund_due')::numeric, 0), (invoice_action_plan(inv, 'cancel', '[]')->>'refund_due')::numeric)),
      '[]'::jsonb, 'T479 refund paid', gen_random_uuid());
  when 'change' then
    -- 'page': as the invoice form sends it (a choice only where
    -- invoice_transferable_benefits lists something, 'transfer' ready).
    perform pg_temp.t479_change(inv, pg_temp.t479_role(p_pre, w[2]),
      case when 'keep' = any (w) then 'keep'
           when 'page' = any (w) then case when exists (select 1 from invoice_transferable_benefits(inv)) then 'transfer' end
           else 'transfer' end);
  when 'merge' then perform pg_temp.t479_merge(pg_temp.t479_role(p_pre, w[2]), pg_temp.t479_role(p_pre, w[3]));
  when 'note' then
    -- the invoice form: its notes changed, nothing else
    perform correct_invoice(inv, pg_temp.t479_lines(inv),
      jsonb_build_object('expected_edit_count', (select edit_count from invoices where id = inv),
        'customer_id', (select customer_id from invoices where id = inv), 'store_id', (select store_id from invoices where id = inv),
        'notes', 'T479 note ' || clock_timestamp()::text), 'T479 note', gen_random_uuid());
  when 'store' then
    -- the invoice form: moved to the other store, nothing else
    perform correct_invoice(inv, pg_temp.t479_lines(inv),
      jsonb_build_object('expected_edit_count', (select edit_count from invoices where id = inv),
        'customer_id', (select customer_id from invoices where id = inv), 'store_id', pg_temp.t479_id('store2')),
      'T479 wrong store', gen_random_uuid());
  when 'qty' then
    -- the invoice form: the therapy line's quantity changed
    perform correct_invoice(inv, (select jsonb_agg(case when l->>'kind' = 'therapy' then jsonb_set(l, '{quantity}', to_jsonb(w[2]::int)) else l end)
                                    from jsonb_array_elements(pg_temp.t479_lines(inv)) l),
      jsonb_build_object('expected_edit_count', (select edit_count from invoices where id = inv),
        'customer_id', (select customer_id from invoices where id = inv), 'store_id', (select store_id from invoices where id = inv)),
      'T479 wrong quantity', gen_random_uuid());
  when 'hold' then
    -- BY HAND (no function did it before 479): the invoice's current sessions
    -- held by R while the invoice stays its customer's
    update customer_therapy_sessions set customer_id = pg_temp.t479_role(p_pre, w[2]) where invoice_id = inv and is_current;
    if not found then raise exception 'T479: no session to hold'; end if;
  when 'spend' then
    n := (select count(*) from t479 where k ~ ('^' || p_pre || '/S[0-9]+$')) + 1;
    perform pg_temp.t479_put(p_pre || '/S' || n,
      pg_temp.t479_spend(pg_temp.t479_role(p_pre, w[2]), case when w[3] ~ '^[0-9]+$' then w[3]::int else 1 end,
        'svc', case when 'bwallet' = any (w) then 'bwallet' else 'wallet' end));
  when 'unspend' then perform pg_temp.t479_unspend(pg_temp.t479_id(p_pre || '/' || w[2]));
  when 'backv' then
    -- the Finance panel's refund by line of N voucher units of line N (at
    -- their paid value).
    x := pg_temp.t479_line(inv, w[2]::int);
    perform refund_invoice_recorded(inv, jsonb_build_array(jsonb_build_object('invoice_item_id', x, 'amount', b.amt,
        'benefits', jsonb_build_array(jsonb_build_object('benefit_id', b.id, 'amount', b.amt)))),
      pg_temp.t479_sources(inv, b.amt), '[]'::jsonb, 'T479 voucher by line', gen_random_uuid())
      from (select o->>'id' as id, round(w[3]::int * (o->>'paid_value')::numeric / (o->>'granted_value')::numeric, 2) as amt
              from jsonb_array_elements(invoice_refund_options_before_sessions(inv)->'benefits') o
             where o->>'invoice_item_id' = x::text and o->>'benefit_kind' = 'voucher' and (o->>'max_refund')::numeric > 0
             order by (o->>'max_refund')::numeric desc limit 1) b;
    if not found then raise exception 'T479: no voucher to refund on that line'; end if;
  when 'backt' then
    -- the Finance panel's refund by line of a therapy line, by money (whole
    -- unused sessions).
    x := pg_temp.t479_line(inv, w[2]::int);
    perform refund_invoice_recorded(inv, jsonb_build_array(jsonb_build_object('invoice_item_id', x, 'amount', w[3]::numeric)),
      pg_temp.t479_sources(inv, w[3]::numeric), '[]'::jsonb, 'T479 sessions by line', gen_random_uuid());
  when 'backps' then
    -- the Finance panel's refund by line of a product line, by money, with
    -- the stock outcomes it asks for: the sale's units it lists as not yet
    -- resolved, returned as sellable (none once a Cancel returned them; the
    -- panel then sends no stock, InvoiceFinancePanel.tsx).
    x := pg_temp.t479_line(inv, w[2]::int);
    perform refund_invoice_recorded(inv, jsonb_build_array(jsonb_build_object('invoice_item_id', x, 'amount', w[3]::numeric)),
      pg_temp.t479_sources(inv, w[3]::numeric),
      (select coalesce(jsonb_agg(jsonb_build_object('movement_id', s->>'movement_id',
                'sellable_quantity', (s->>'quantity')::int - (s->>'resolved_quantity')::int,
                'damaged_quantity', 0, 'not_returned_quantity', 0)), '[]'::jsonb)
         from jsonb_array_elements(invoice_refund_options_before_sessions(inv)->'stock') s
        where (s->>'quantity')::int > (s->>'resolved_quantity')::int),
      'T479 product by line', gen_random_uuid());
  when 'paidback' then
    -- "Record refund paid" with no line, of an amount
    perform refund_invoice_recorded(inv, jsonb_build_array(jsonb_build_object('amount', w[2]::numeric)),
      pg_temp.t479_sources(inv, w[2]::numeric), '[]'::jsonb, 'T479 refund paid', gen_random_uuid());
  when 'request' then
    -- the guided request alone (request_invoice_action_v2, the plan it
    -- saves), approved by a later step ('approve')
    perform pg_temp.t479_put(p_pre || '/req',
      (request_invoice_action_v2(inv, w[2], '[]', 'T479 ' || w[2], null, gen_random_uuid())->>'request_id')::uuid);
  when 'approve' then
    -- an Owner approving it as its plan reads now (the review shows the
    -- current plan and sends its hash: a plan revised since the request,
    -- confirmed), a reason for every override, "Record refund paid" ticked
    perform resolve_invoice_action_v2(pg_temp.t479_id(p_pre || '/req'), true, 'T479 approve', pl->>'plan_hash',
      (select coalesce(jsonb_agg(case when coalesce((o->>'amount_required')::boolean, false)
                then jsonb_build_object('code', o->>'code', 'reason', 'T479 override', 'amount', (o->>'default_amount')::numeric)
                else jsonb_build_object('code', o->>'code', 'reason', 'T479 override') end), '[]'::jsonb)
         from jsonb_array_elements(coalesce(pl->'overrides_required', '[]')) o),
      null, true)
      from (select invoice_action_plan(inv, (select payload->>'action' from approval_requests where id = pg_temp.t479_id(p_pre || '/req')), '[]') as pl) z;
  when 'addlines' then
    -- the invoice form's correction adding lines (th: three S$20 sessions,
    -- pr: one S$40 product, v: 2 vouchers at S$30), its other lines as they
    -- are (the review of 2 Nov 2026: so the package written first is listed
    -- first, NOT COVERED 16)
    perform correct_invoice(inv, pg_temp.t479_lines(inv)
        || (select jsonb_agg(case u.k when 'th' then jsonb_build_object('kind', 'therapy', 'therapy_service_id', pg_temp.t479_id('svc'), 'quantity', 3)
                                      when 'pr' then jsonb_build_object('kind', 'product', 'product_id', pg_temp.t479_id('prod'), 'quantity', 1)
                                      when 'v' then jsonb_build_object('kind', 'voucher', 'voucher_id', pg_temp.t479_id('v'), 'quantity', 2) end order by u.o)
              from unnest(string_to_array(w[2], ',')) with ordinality u(k, o)),
      jsonb_build_object('expected_edit_count', (select edit_count from invoices where id = inv),
        'customer_id', (select customer_id from invoices where id = inv), 'store_id', (select store_id from invoices where id = inv)),
      'T479 lines added', gen_random_uuid());
  when 'dup' then
    -- BY HAND: as a second reopening queued it before 475 (NOT COVERED 3).
    insert into invoice_reopen_sessions(invoice_id, session_id, request_id, quantity)
    select q.invoice_id, q.session_id, gen_random_uuid(), q.quantity from invoice_reopen_sessions q
     where q.invoice_id = inv and q.applied_at is null;
    if not found then raise exception 'T479: no waiting session to queue again'; end if;
  when 'shrink' then
    -- BY HAND: a state no function makes (NOT COVERED 4).
    update invoice_reopen_sessions set quantity = quantity - 1 where invoice_id = inv and applied_at is null and quantity > 1;
    if not found then raise exception 'T479: no waiting session to shrink'; end if;
  else raise exception 'T479: unknown step %', p_st;
  end case;
  perform pg_temp.t479_commit();
  return null;
exception when others then
  return btrim(p_st) || ': ' || sqlerrm;
end $f$;
-- 479: the invoice's therapy sessions: each current one (available of
-- purchased, refunded, cancelled, status), the session queue (waiting rows,
-- what they hold, sessions waiting on more than one row), the reinstatements
-- ('reopen' events), who holds them (a role of the case), and what is wrong
-- with them ('' when nothing):
--   * a waiting session's rows and what was refunded by line since the
--     invoice was last reopened add up to what it shows as refunded and
--     cancelled (what the payment checks; 252's evidence, as 479 counts it);
--   * nothing waits once the invoice is settled again;
--   * no session that is not current waits;
--   * the sessions are held by whoever holds the invoice's benefits now
--     (460's rule as 462 reads it, invoice_credit_live_holder; before 479
--     always the invoice's customer).
create function pg_temp.t479_sessions(p_pre text) returns jsonb language plpgsql as $f$
declare inv uuid := pg_temp.t479_id(p_pre || '/inv'); probs text := ''; s record; st text; v_re timestamptz;
begin
  select status::text, reopened_at into st, v_re from invoices where id = inv;
  for s in select x.*, (select count(*) from invoice_reopen_sessions q where q.session_id = x.id and q.applied_at is null) as nrows,
                  (select coalesce(sum(q.quantity), 0) from invoice_reopen_sessions q where q.session_id = x.id and q.applied_at is null) as qsum,
                  (select coalesce(sum(-e.quantity), 0) from invoice_therapy_session_events e
                    where e.session_id = x.id and e.event_kind = 'refund' and e.created_at > v_re) as since
             from customer_therapy_sessions x where x.invoice_id = inv loop
    if s.nrows > 0 and s.qsum + s.since <> s.quantity_refunded + s.quantity_cancelled then
      probs := probs || format(' a waiting session''s rows hold %s and %s were refunded since the reopening, it shows %s;',
                               s.qsum, s.since, s.quantity_refunded + s.quantity_cancelled); end if;
    if s.nrows > 0 and st in ('paid', 'completed_foc') then probs := probs || ' settled with a session still waiting;'; end if;
    if s.nrows > 0 and not s.is_current then probs := probs || ' a replaced session waits;'; end if;
    if s.is_current and invoice_credit_live_holder(inv, s.customer_id, s.created_at) is distinct from s.customer_id then
      probs := probs || ' the sessions are not held by whoever holds the invoice''s benefits;'; end if;
  end loop;
  return jsonb_build_object(
    'sess', coalesce((select string_agg(format('%s/%s r%s c%s %s', x.quantity_purchased - x.quantity_used - x.quantity_refunded - x.quantity_cancelled,
                                               x.quantity_purchased, x.quantity_refunded, x.quantity_cancelled, x.status), ', ' order by x.created_at, x.id)
                        from customer_therapy_sessions x where x.invoice_id = inv and x.is_current), '-'),
    'swait', (select count(*) from invoice_reopen_sessions q where q.invoice_id = inv and q.applied_at is null),
    'squeued', (select coalesce(sum(q.quantity), 0) from invoice_reopen_sessions q where q.invoice_id = inv and q.applied_at is null),
    'stwice', (select count(*) from (select q.session_id from invoice_reopen_sessions q where q.invoice_id = inv and q.applied_at is null
                                      group by q.session_id having count(*) > 1) z),
    'sev', (select count(*) from invoice_therapy_session_events e join customer_therapy_sessions x on x.id = e.session_id
             where x.invoice_id = inv and e.event_kind = 'reopen'),
    'sholder', (select string_agg(distinct split_part(t.k, '/', 3), ',') from customer_therapy_sessions x join t479 t on t.id = x.customer_id
                 where x.invoice_id = inv and x.is_current and t.k like p_pre || '/%'),
    'icust', (select split_part(t.k, '/', 3) from invoices i join t479 t on t.id = i.customer_id where i.id = inv and t.k like p_pre || '/%' limit 1),
    'sinv', probs);
end $f$;
-- The plan a guided step works from, read just before it (t479_run): its
-- lines in the order invoice_action_plan lists them (the refund options'
-- order, as the table returns the lines: not fixed) and what each refunds,
-- 'kind:amount'; the last guided step of a case (the review of 29 Oct
-- 2026: which line a cut plan refunds follows that order, NOT COVERED 10).
create temp table t479_plan(pre text primary key, lines text);
create function pg_temp.t479_planlines(p_inv uuid, p_action text) returns text language plpgsql as $f$
begin
  return (select coalesce(string_agg((l->>'line_kind') || ':' || ((l->>'amount')::numeric)::text, ' ' order by o), '-')
            from jsonb_array_elements(invoice_action_plan(p_inv, p_action, '[]')->'lines') with ordinality t(l, o));
exception when others then return 'ERR';
end $f$;
-- What a case ends with: the invoice's status and money, who holds what
-- (credit, '/n' held vouchers), the plans' codes and refund due (Cancel's
-- refund due; Refund in full's amount), the refusal that stopped it, what is
-- wrong with its credit, the credit Cancel would leave behind, its stock
-- movements by kind ('stock', '-' with none), the plan its last guided step
-- worked from ('plan', above), and its sessions (above).
create function pg_temp.t479_outcome(p_pre text, p_err text) returns jsonb language sql as $f$
  select jsonb_build_object(
    'status', (select status::text from invoices where id = i.id),
    'net', invoice_net_received(i.id),
    'owed', (select cancel_refund_owed from invoices where id = i.id),
    'fdue', (invoice_financial_position(i.id)->>'refund_due')::numeric,
    'held', (select coalesce(sum(cancelled_unused_value), 0) from invoice_benefit_values where invoice_id = i.id and lot_id is not null),
    'holds', (select jsonb_object_agg(split_part(t.k, '/', 3),
                (select coalesce(sum(l.remaining_amount), 0) from customer_credit_lots l where l.customer_id = t.id)::numeric(12,2)::text
                || coalesce('/' || nullif((select sum(v.quantity) from customer_reward_vouchers v where v.customer_id = t.id and v.status = 'held'), 0)::text, ''))
              from t479 t where t.k like p_pre || '/%' and split_part(t.k, '/', 4) = ''
                and split_part(t.k, '/', 3) !~ '^(inv|S[0-9]+|err)$'),
    'cancel', pg_temp.t479_codes(i.id, 'cancel'),
    'due', pg_temp.t479_due(i.id, 'cancel'),
    'refund', pg_temp.t479_codes(i.id, 'refund_full'),
    'rdue', pg_temp.t479_due(i.id, 'refund_full'),
    'error', p_err,
    'invariants', pg_temp.t479_invariants(i.id),
    'cancel_left', pg_temp.t479_cancel_left(i.id),
    'stock', (select coalesce(string_agg(m.k, ', ' order by m.k), '-')
                from (select x.movement_type::text || ' ' || sum(x.quantity) as k from stock_movements x
                       where x.invoice_id = i.id group by x.movement_type) m),
    'plan', (select p.lines from t479_plan p where p.pre = p_pre)) || pg_temp.t479_sessions(p_pre)
    from (select pg_temp.t479_id(p_pre || '/inv') as id) i $f$;

-- ── The readings: the Reopen dialog, and what the payment gives ─────────────
-- Each Reopen of a case: the dialog read just before it, as the Finance panel
-- reads it (invoice_reopen_preview: every figure it shows), what the Reopen
-- left waiting (or gave back at once, reopened straight to paid): credit,
-- voucher units and (475) sessions.
create temp table t479_dlg(pre text, n int, shown numeric, shownv int, shows int, total numeric, net numeric, required numeric,
                           can boolean, preview jsonb, queued numeric, queuedv int, queueds int, primary key (pre, n));
-- What each step gave back: credit (the payment's 'Reopened invoice settled'
-- rows, apply_reopened_invoice_benefits), voucher units given again
-- (apply_reopened_invoice_vouchers) and sessions reinstated
-- (trg_create_therapy_sessions_on_paid).
create temp table t479_gift(pre text, n int, credit numeric, vouchers int, sessions int, primary key (pre, n));
create temp table t479_err(pre text primary key, err text, at int);
create function pg_temp.t479_dialog(p_pre text) returns jsonb language sql as $f$
  with l as (select * from t479_dlg where pre = p_pre order by n desc limit 1)
  select jsonb_build_object(
    'reopens', (select count(*) from t479_dlg where pre = p_pre),
    'dlg', (select shown from l), 'dlgv', (select shownv from l), 'dlgs', (select shows from l),
    'required', (select required from l),
    'queued', (select queued from l), 'queuedv', (select queuedv from l), 'queueds', (select queueds from l),
    'gave', (select coalesce(sum(g.credit), 0) from t479_gift g, l where g.pre = p_pre and g.n >= l.n),
    'gavev', (select coalesce(sum(g.vouchers), 0) from t479_gift g, l where g.pre = p_pre and g.n >= l.n),
    'gaves', (select coalesce(sum(g.sessions), 0) from t479_gift g, l where g.pre = p_pre and g.n >= l.n),
    'every', (select coalesce(string_agg(format('%s: %s/%s/%s shown, %s/%s/%s queued (credit/vouchers/sessions)',
                                                d.n, d.shown, d.shownv, d.shows, d.queued, d.queuedv, d.queueds), '; ' order by d.n), '')
                from t479_dlg d where d.pre = p_pre and d.queued is not null
                 and (d.shown is distinct from d.queued or d.shownv is distinct from d.queuedv or d.shows is distinct from d.queueds))) $f$;
-- A case's steps p_from to p_to (all by default), stopping at a refusal;
-- with p_to null, its outcome (kept in t479_res under p_phase).
create function pg_temp.t479_run(p_phase text, p_case text, p_steps text, p_from int default 1, p_to int default null)
  returns jsonb language plpgsql as $f$
declare v_pre text := p_phase || '/' || p_case; st text[] := string_to_array(p_steps, ';'); i int; v_err text; v_out jsonb;
  inv uuid; pv jsonb; seq bigint; av uuid[]; ass uuid[]; g numeric; gv int; gs int;
begin
  v_err := (select e.err from t479_err e where e.pre = v_pre);
  for i in p_from .. least(coalesce(p_to, cardinality(st)), cardinality(st)) loop
    exit when v_err is not null;
    continue when btrim(st[i]) = '';
    inv := pg_temp.t479_id(v_pre || '/inv');
    if inv is not null and btrim(st[i]) = 'reopen' then
      pv := invoice_reopen_preview(inv);
      insert into t479_dlg(pre, n, shown, shownv, shows, total, net, required, can, preview)
      values (v_pre, i, (pv->>'credit_to_reinstate_after_settlement')::numeric, (pv->>'voucher_units_to_reinstate_after_settlement')::int,
              coalesce((pv->>'sessions_to_reinstate_after_settlement')::int, 0), (pv->>'total')::numeric, (pv->>'net_received')::numeric,
              greatest(0, (pv->>'total')::numeric - (pv->>'net_received')::numeric), (pv->>'can_reopen')::boolean, pv)
      on conflict (pre, n) do nothing;
    end if;
    select coalesce(max(entry_seq), 0) into seq from customer_credit_ledger;
    select array_agg(id) into av from invoice_reopen_vouchers where invoice_id = inv and applied_at is not null;
    select array_agg(id) into ass from invoice_reopen_sessions where invoice_id = inv and applied_at is not null;
    -- The plan a guided step works from, read as it reads it (kept whether
    -- the step then goes through or is refused).
    if inv is not null and btrim(st[i]) in ('refundall', 'guidedcancel', 'guidedkeep', 'approve') then
      insert into t479_plan values (v_pre, pg_temp.t479_planlines(inv, case btrim(st[i]) when 'refundall' then 'refund_full'
          when 'approve' then (select payload->>'action' from approval_requests where id = pg_temp.t479_id(v_pre || '/req')) else 'cancel' end))
        on conflict (pre) do update set lines = excluded.lines;
    end if;
    v_err := pg_temp.t479_step(v_pre, st[i]);
    if v_err is not null then
      insert into t479_err values (v_pre, v_err, i) on conflict (pre) do update set err = excluded.err, at = excluded.at;
    end if;
    inv := pg_temp.t479_id(v_pre || '/inv');
    g := (select coalesce(sum(e.amount), 0) from customer_credit_ledger e
           where e.entry_seq > seq and e.entry_type = 'reverse' and e.source_type = 'invoice_reopen' and e.reason = 'Reopened invoice settled'
             and e.reverses_entry_id in (select q.source_ledger_id from invoice_reopen_benefits q where q.invoice_id = inv));
    gv := (select coalesce(sum(q.quantity), 0) from invoice_reopen_vouchers q where q.invoice_id = inv and q.applied_at is not null
             and q.replacement_voucher_id is not null and not (q.id = any (coalesce(av, '{}'))));
    gs := (select coalesce(sum(q.quantity), 0) from invoice_reopen_sessions q where q.invoice_id = inv and q.applied_at is not null
             and not (q.id = any (coalesce(ass, '{}'))));
    insert into t479_gift values (v_pre, i, g, gv, gs)
      on conflict (pre, n) do update set credit = excluded.credit, vouchers = excluded.vouchers, sessions = excluded.sessions;
    if btrim(st[i]) = 'reopen' and v_err is null then
      update t479_dlg set queued = g + (select coalesce(sum(q.amount), 0) from invoice_reopen_benefits q where q.invoice_id = inv and q.applied_at is null),
                          queuedv = gv + (select coalesce(sum(q.quantity), 0) from invoice_reopen_vouchers q where q.invoice_id = inv and q.applied_at is null),
                          queueds = gs + (select coalesce(sum(q.quantity), 0) from invoice_reopen_sessions q where q.invoice_id = inv and q.applied_at is null)
       where pre = v_pre and n = i;
    end if;
  end loop;
  insert into t479_err values (v_pre, v_err, (select e.at from t479_err e where e.pre = v_pre))
    on conflict (pre) do update set err = excluded.err;
  if p_to is not null then return null; end if;
  v_out := pg_temp.t479_outcome(v_pre, v_err) || pg_temp.t479_dialog(v_pre);
  insert into t479_res values (p_phase, p_case, v_out) on conflict (phase, k) do update set v = excluded.v;
  return v_out;
end $f$;
-- Whether an outcome has what is expected: each key equal ('holds' as a
-- containment of who holds what), a key ending in '~' as a LIKE pattern of
-- that key's text.
create function pg_temp.t479_meets(p_out jsonb, p_exp jsonb) returns boolean language sql as $f$
  select coalesce(bool_and(case
           when e.key like '%~' then coalesce(p_out->>left(e.key, -1), '') like (e.value #>> '{}')
           when e.key = 'holds' then coalesce(p_out->'holds', '{}') @> e.value
           when jsonb_typeof(e.value) = 'number' then coalesce((p_out->>e.key)::numeric = (e.value #>> '{}')::numeric, false)
           else (p_out->e.key) is not distinct from e.value end), true)
    from jsonb_each(p_exp) e $f$;
-- What differs between an outcome and what is expected (for the FAIL line).
create function pg_temp.t479_diff(p_out jsonb, p_exp jsonb) returns text language sql as $f$
  select string_agg(e.key || ': wanted ' || e.value::text || ', got ' || coalesce(p_out->left(e.key, case when e.key like '%~' then -1 else 1000 end), 'null')::text, '; ')
    from jsonb_each(p_exp) e where not pg_temp.t479_meets(p_out, jsonb_build_object(e.key, e.value)) $f$;
-- 479: an outcome without the refusal, for A against R: up to the step
-- refused before 479 a fixed case is exactly as before 479, the plans' codes
-- and amounts too (479 changes neither the refund options nor the plans).
-- Without the plan a guided step read too: the run up to the step before
-- the refused one has not read the plan of a refused guided step.
create function pg_temp.t479_but_error(p_out jsonb) returns jsonb language sql as $f$
  select p_out - 'error' - 'plan' $f$;
-- An outcome with its plan's lines sorted (the refund options list the
-- lines in an order that is not fixed: the same invoice and steps may list
-- them in another order; the review of 29 Oct 2026, section A).
create function pg_temp.t479_unordered(p_out jsonb) returns jsonb language sql as $f$
  select case when p_out ? 'plan' and jsonb_typeof(p_out->'plan') = 'string'
              then jsonb_set(p_out, '{plan}', to_jsonb((select string_agg(x, ' ' order by x) from unnest(string_to_array(p_out->>'plan', ' ')) x)))
              else p_out end $f$;
-- The unapplied reopening queue of an invoice (credit).
create function pg_temp.t479_waiting(p_inv uuid) returns numeric language sql as $f$
  select coalesce(sum(q.amount), 0) from invoice_reopen_benefits q where q.invoice_id = p_inv and q.applied_at is null $f$;
-- Who may call a function (the set) and the whole grant list (by name).
create function pg_temp.t479_grants() returns text language sql as $f$
  select md5(string_agg(p.oid::regprocedure::text || '=' || coalesce(p.proacl::text, 'null'), '|' order by p.oid::regprocedure::text))
    from pg_proc p where p.pronamespace = 'public'::regnamespace $f$;
create function pg_temp.t479_grant_set(p_sig text) returns text[] language sql as $f$
  select array_agg(x::text order by x::text) from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || p_sig) $f$;
-- The three functions 479 changes: BEFORE (production at 478, 29 Oct 2026,
-- as on its copy) and AFTER.
create temp table t479_md5(sig text primary key, before text, after text);
insert into t479_md5 values
  ('refund_invoice_therapy_sessions(uuid,numeric,text,uuid)', '93739f00ada43b1c3f4177b32c9bdc52', '35d3f1ba4c906a66a8deb131c777dab8'),
  ('correct_invoice_therapy_sessions(uuid,jsonb,uuid,uuid,text,uuid)', '12e1cf25bb069521adfe18809bcef68d', '32df6441a3f5e37e164b1279f8dc502b'),
  ('trg_create_therapy_sessions_on_paid()', 'af85d6800c7d980565ef8d68898b6a38', '15f4bbc260e53ba538debc0947082f43');
create function pg_temp.t479_at(p_col text) returns boolean language sql as $f$
  select bool_and(md5(pg_get_functiondef(to_regprocedure('public.' || m.sig))) = case when p_col = 'before' then m.before else m.after end)
    from t479_md5 m $f$;
-- The refund options are not changed by 479 (the Owner, 29 Oct 2026: what
-- the guided plans offer stays as it is): as 438, 448 and 477 pinned them.
create function pg_temp.t479_options_kept() returns boolean language sql as $f$
  select md5(pg_get_functiondef('public.invoice_refund_options(uuid)'::regprocedure)) = '689a71c246260d2c10ec44dd94eb7139' $f$;
-- Their texts as the suite starts (for a partial install, 9).
create temp table t479_defs(sig text primary key, def text);
insert into t479_defs select m.sig, pg_get_functiondef(to_regprocedure('public.' || m.sig)) from t479_md5 m;
insert into t479_fp values ('start', pg_temp.t479_fingerprint()), ('grants', pg_temp.t479_grants());

-- The read-only query in 479's header (the same text, taken from the file
-- when this suite was written).
create function pg_temp.t479_header_query() returns table(reason text, invoice_no text, n bigint) language sql as $hq$
with
-- therapy sessions waiting for their invoice's reopening to be paid (or once
-- it was cancelled or refunded again): per session, what waits, what was
-- refunded by line since the invoice was last reopened, what it shows as
-- refunded and cancelled
w as (
  select q.invoice_id, q.session_id, q.waits,
         s.quantity_refunded + s.quantity_cancelled as shows,
         coalesce((select sum(-e.quantity) from public.invoice_therapy_session_events e
                    where e.session_id = q.session_id and e.event_kind = 'refund'
                      and e.created_at > i.reopened_at), 0) as since
    from (select invoice_id, session_id, sum(quantity) as waits from public.invoice_reopen_sessions
           where applied_at is null group by invoice_id, session_id) q
    join public.customer_therapy_sessions s on s.id = q.session_id
    join public.invoices i on i.id = q.invoice_id),
found(reason, invoice_id, n) as (
  select '1 changes: a therapy session waiting for its invoice''s reopening to be paid, the invoice part-paid or unpaid, or cancelled or refunded again: its refund by line and a customer change keeping its line and store were refused before 479, and so were the guided Cancel with "Record refund paid" and the guided Refund in full where their plan refunded some of it; from 479 they go through, the refund taking its sessions off what waits, the change giving them to whoever holds the invoice''s benefits, the guided ones where their plan comes out in whole sessions and voucher units at the value 479 gives the sessions (NOT COVERED 14), offering as before no session a refund by line paid back before the reopening (the Owner, 29 Oct 2026), and refused as before 479 where their plan was cut to the money held and another of its lines had something to refund (the Owner, 29 Oct 2026, "Keep today''s refusal") (the count is of sessions)', i.id, count(*)
    from public.invoices i join w on w.invoice_id = i.id
   where i.deleted_at is null and w.waits + w.since = w.shows
   group by i.id
  union all
  select '2 for the Owner (not changed by 479: 475''s NOT COVERED 3 and 4): a waiting therapy session whose waiting rows and refunds since the reopening do not add up to what it shows; the payment that settles the invoice is refused before 479 and after it, and from 479 its refund by line and customer change are too ("Therapy session reopening changed; reload its original evidence") (the count is of sessions)', i.id, count(*)
    from public.invoices i join w on w.invoice_id = i.id
   where i.deleted_at is null and w.waits + w.since <> w.shows
   group by i.id
  union all
  select '3 changes: a current therapy session held by someone other than its invoice''s customer (no function made one before 479): not waiting, a correction of the invoice gave it to the invoice''s customer as new sessions before 479, and from 479 one that changes its line, quantity or store, or moves the invoice to a customer other than its holder, is refused, and one that changes none of them leaves it; still waiting for its reopening''s payment, every correction was refused before 479, and from 479 one that moves the invoice to another customer goes through, the session following 460''s rule, one that changes its line, quantity or store is refused, and one that changes none of them leaves it (the count is of sessions)', i.id, count(*)
    from public.invoices i join public.customer_therapy_sessions s on s.invoice_id = i.id and s.is_current
   where i.deleted_at is null and s.customer_id is distinct from i.customer_id
   group by i.id)
select f.reason, i.invoice_no, f.n
  from found f join public.invoices i on i.id = f.invoice_id
 order by f.reason, i.invoice_no
$hq$;
-- What the header's query lists for an invoice: 'reason/count', by reason.
create function pg_temp.t479_listed(p_inv uuid) returns text language sql as $f$
  select string_agg(left(q.reason, 1) || '/' || q.n, ',' order by q.reason)
    from pg_temp.t479_header_query() q join invoices i on i.invoice_no = q.invoice_no where i.id = p_inv $f$;

-- The cases: (k, kind, steps, what 479 gives, the refusal before 479 (the
-- step and its message, as a LIKE pattern; null: none), what the header's
-- query lists for its state before 479). kind: 'fixed' (refused before 479
-- at err0's step, as 'expect' after it), 'control' (the same with and without
-- 479, every key of the outcome), 'kept' (what the Owner kept on 29 Oct
-- 2026: the same with and without 479, every key, as a control), 'known' (a
-- NOT COVERED item, checked as it is after 479; where err0 is given, refused
-- before 479 as for a fixed case, otherwise the same before and after, as a
-- control). Every case also checks the invariants, the sessions' own, and
-- that Cancel takes everything back from whoever holds it.
create temp table t479_cases(k text primary key, kind text not null, steps text not null, expect jsonb not null, err0 text, q text, ord serial);
insert into t479_cases(k, kind, steps, expect, err0, q) values
-- A session's refund by line while its reopening waits: one more session;
-- then paid; two more, then paid.
('RW', 'fixed', 'sale A th; cancel; backt 1 20; reopen; backt 1 20',
  '{"status":"partially_paid","net":20,"sess":"0/3 r2 c1 refunded","swait":1,"squeued":2,"sholder":"A","sinv":"","error":null}',
  'backt 1 20: Settle the reopened invoice before changing its queued sessions%', '1/1'),
('RWp', 'fixed', 'sale A th; cancel; backt 1 20; reopen; backt 1 20; pay',
  '{"status":"paid","net":40,"sess":"2/3 r1 c0 available","swait":0,"sev":1,"sholder":"A","sinv":"","error":null}',
  'backt 1 20: Settle the reopened invoice before changing its queued sessions%', '1/1'),
('RW2p', 'fixed', 'sale A th; cancel; backt 1 20; reopen; backt 1 40; pay',
  '{"status":"paid","net":20,"sess":"1/3 r2 c0 available","swait":0,"sev":1,"sholder":"A","sinv":"","error":null}',
  'backt 1 40: Settle the reopened invoice before changing its queued sessions%', '1/1'),
-- Refunded while it waits, cancelled again, reopened (the difference queued
-- again: rows 2 and 1), paid; refunded again while the second reopening
-- waits.
('RWc', 'fixed', 'sale A th; cancel; backt 1 20; reopen; backt 1 20; cancel; reopen; pay',
  '{"status":"paid","net":60,"sess":"3/3 r0 c0 available","swait":0,"sev":2,"dlgs":3,"queueds":3,"gaves":3,"every":"","sholder":"A","sinv":"","error":null}',
  'backt 1 20: Settle the reopened invoice before changing its queued sessions%', '1/1'),
('RWw', 'fixed', 'sale A th; cancel; backt 1 20; reopen; backt 1 20; cancel; reopen; backt 1 20; pay',
  '{"status":"paid","net":40,"sess":"2/3 r1 c0 available","swait":0,"sholder":"A","sinv":"","error":null}',
  'backt 1 20: Settle the reopened invoice before changing its queued sessions%', '1/1'),
-- Settled by the Pay dialog; by Correct payment.
('RWpd', 'fixed', 'sale A th; cancel; backt 1 20; reopen; backt 1 20; paydlg',
  '{"status":"paid","net":40,"sess":"2/3 r1 c0 available","swait":0,"sev":1,"sinv":"","error":null}',
  'backt 1 20: Settle the reopened invoice before changing its queued sessions%', '1/1'),
('RWfx', 'fixed', 'sale A th; cancel; backt 1 20; reopen; backt 1 20; payamt 5; fixpay 20',
  '{"status":"paid","net":40,"sess":"2/3 r1 c0 available","swait":0,"sev":1,"sinv":"","error":null}',
  'backt 1 20: Settle the reopened invoice before changing its queued sessions%', '1/1'),
-- The buyer merged into K after the refund; before it, then a second cycle.
('RWm', 'fixed', 'sale A th; cancel; backt 1 20; reopen; backt 1 20; merge K A; pay',
  '{"status":"paid","net":40,"sess":"2/3 r1 c0 available","swait":0,"sholder":"K","sinv":"","error":null}',
  'backt 1 20: Settle the reopened invoice before changing its queued sessions%', '1/1'),
('RWmc', 'fixed', 'sale A th; cancel; backt 1 20; reopen; merge K A; backt 1 20; cancel; reopen; pay',
  '{"status":"paid","net":60,"sess":"3/3 r0 c0 available","swait":0,"sholder":"K","sinv":"","error":null}',
  'backt 1 20: Settle the reopened invoice before changing its queued sessions%', '1/1'),
-- Refunded in full before the reopening (the sessions refunded, not
-- cancelled), S$20 paid towards it: before 479 "0 of 3 sessions remain
-- refundable"; S$40 paid, a second cycle.
('RF', 'fixed', 'sale A th; refundall; reopen; payamt 20; backt 1 20; pay',
  '{"status":"paid","net":40,"sess":"2/3 r1 c0 available","swait":0,"sev":1,"sholder":"A","sinv":"","error":null}',
  'backt 1 20: Refund whole unused therapy sessions at their original paid value; 0 of 3 sessions remain refundable%', '1/1'),
('RFc', 'fixed', 'sale A th; refundall; reopen; payamt 40; backt 1 20; cancel; reopen; pay',
  '{"status":"paid","net":60,"sess":"3/3 r0 c0 available","swait":0,"sholder":"A","sinv":"","error":null}',
  'backt 1 20: Refund whole unused therapy sessions at their original paid value; 0 of 3 sessions remain refundable%', '1/1'),
-- Once cancelled again: refunded by line; reopened and paid; refunded while
-- it waited and once cancelled again.
('RB', 'fixed', 'sale A th; cancel; backt 1 20; reopen; cancel; backt 1 20',
  '{"status":"cancelled","net":20,"sess":"0/3 r2 c1 refunded","swait":1,"squeued":2,"sholder":"A","sinv":"","error":null}',
  'backt 1 20: Settle the reopened invoice before changing its queued sessions%', '1/1'),
('RBp', 'fixed', 'sale A th; cancel; backt 1 20; reopen; cancel; backt 1 20; reopen; pay',
  '{"status":"paid","net":60,"sess":"3/3 r0 c0 available","swait":0,"sev":2,"dlgs":3,"queueds":3,"gaves":3,"every":"","sholder":"A","sinv":"","error":null}',
  'backt 1 20: Settle the reopened invoice before changing its queued sessions%', '1/1'),
('RBw', 'fixed', 'sale A th; cancel; backt 1 20; reopen; backt 1 20; cancel; backt 1 20; reopen; pay',
  '{"status":"paid","net":60,"sess":"3/3 r0 c0 available","swait":0,"every":"","sholder":"A","sinv":"","error":null}',
  'backt 1 20: Settle the reopened invoice before changing its queued sessions%', '1/1'),
-- The guided Cancel with "Record refund paid" while it waits (all the money
-- held back, those sessions off the queue, one still waits for a later
-- reopening); reopened and paid. The guided Refund in full, then paid (GR,
-- where it stops, is NOT COVERED 1).
('GC', 'fixed', 'sale A th; cancel; backt 1 20; reopen; guidedcancel',
  '{"status":"cancelled","net":0,"sess":"0/3 r3 c0 refunded","swait":1,"squeued":1,"sholder":"A","sinv":"","error":null}',
  'guidedcancel: Settle the reopened invoice before changing its queued sessions%', '1/1'),
('GCp', 'fixed', 'sale A th; cancel; backt 1 20; reopen; guidedcancel; reopen; pay',
  '{"status":"paid","net":60,"sess":"3/3 r0 c0 available","swait":0,"every":"","sholder":"A","sinv":"","error":null}',
  'guidedcancel: Settle the reopened invoice before changing its queued sessions%', '1/1'),
('GR', 'known', 'sale A th; cancel; backt 1 20; reopen; refundall',
  '{"status":"partially_paid","net":0,"sess":"0/3 r3 c0 refunded","swait":1,"squeued":1,"sholder":"A","sinv":"","error":null}',
  'refundall: Settle the reopened invoice before changing its queued sessions%', '1/1'),
('GRp', 'fixed', 'sale A th; cancel; backt 1 20; reopen; refundall; pay',
  '{"status":"paid","net":20,"sess":"1/3 r2 c0 available","swait":0,"sev":1,"sholder":"A","sinv":"","error":null}',
  'refundall: Settle the reopened invoice before changing its queued sessions%', '1/1'),
-- S$5 paid while it waits, S$45 held: the plans offer the S$40 the money
-- held covers from before the reopening (2 whole sessions; the refund
-- options as they are), the S$5 kept (shown due once cancelled); then paid.
-- Paid back with no line, reopened, S$40 paid: 2 whole sessions.
('KG45', 'fixed', 'sale A th; cancel; backt 1 20; reopen; payamt 5; refundall',
  '{"status":"partially_paid","net":5,"sess":"0/3 r3 c0 refunded","swait":1,"squeued":1,"sholder":"A","sinv":"","error":null}',
  'refundall: Settle the reopened invoice before changing its queued sessions%', '1/1'),
('KG45c', 'fixed', 'sale A th; cancel; backt 1 20; reopen; payamt 5; guidedcancel',
  '{"status":"cancelled","net":5,"fdue":5,"sess":"0/3 r3 c0 refunded","swait":1,"squeued":1,"sholder":"A","sinv":"","error":null}',
  'guidedcancel: Settle the reopened invoice before changing its queued sessions%', '1/1'),
('KG45p', 'fixed', 'sale A th; cancel; backt 1 20; reopen; payamt 5; refundall; pay',
  '{"status":"paid","net":20,"sess":"1/3 r2 c0 available","swait":0,"sev":1,"sholder":"A","sinv":"","error":null}',
  'refundall: Settle the reopened invoice before changing its queued sessions%', '1/1'),
('KGn40', 'fixed', 'sale A th; cancel; refundpaid; reopen; payamt 40; refundall; pay',
  '{"status":"paid","net":20,"sess":"1/3 r2 c0 available","swait":0,"sev":1,"sholder":"A","sinv":"","error":null}',
  'refundall: Settle the reopened invoice before changing its queued sessions%', '1/1'),
-- Beside a Credit Package (its credit refunded by line before the
-- reopening, waiting), the Premium Bundle, a package with a session paid
-- from it and a voucher line.
('CPw', 'fixed', 'sale A th,cp; cancel; back 1 100; reopen; backt 2 40; pay',
  '{"status":"paid","net":120,"sess":"1/3 r2 c0 available","holds":{"A":"100.00"},"swait":0,"sholder":"A","sinv":"","error":null}',
  'backt 2 40: Settle the reopened invoice before changing its queued sessions%', '1/1'),
('CPr', 'fixed', 'sale A th,cp; cancel; back 1 100; reopen; refundall; pay',
  '{"status":"paid","net":100,"sess":"0/3 r3 c0 refunded","holds":{"A":"100.00"},"swait":0,"sholder":"A","sinv":"","error":null}',
  'refundall: Settle the reopened invoice before changing its queued sessions%', '1/1'),
('CPg', 'fixed', 'sale A th,cp; cancel; back 1 100; reopen; guidedcancel',
  '{"status":"cancelled","net":0,"sess":"0/3 r3 c0 refunded","holds":{"A":"0.00"},"swait":0,"sholder":"A","sinv":"","error":null}',
  'guidedcancel: Settle the reopened invoice before changing its queued sessions%', '1/1'),
('PBw', 'fixed', 'sale A th,pbv; cancel; back 1 42; reopen; backt 2 20; pay',
  '{"status":"paid","net":180,"sess":"2/3 r1 c0 available","holds":{"A":"140.00/2"},"swait":0,"sholder":"A","sinv":"","error":null}',
  'backt 2 20: Settle the reopened invoice before changing its queued sessions%', '1/1'),
('MXw', 'fixed', 'sale A th,cp,v; spend A; cancel; back 1 60; reopen; backt 3 20; pay',
  '{"status":"paid","net":200,"sess":"2/3 r1 c0 available","holds":{"A":"80.00/2"},"swait":0,"sholder":"A","sinv":"","error":null}',
  'backt 3 20: Settle the reopened invoice before changing its queued sessions%', '1/1'),
('MXc', 'fixed', 'sale A th,cp,v; spend A; cancel; back 1 60; reopen; backt 3 20; cancel; reopen; pay',
  '{"status":"paid","net":220,"sess":"3/3 r0 c0 available","holds":{"A":"80.00/2"},"swait":0,"every":"","sholder":"A","sinv":"","error":null}',
  'backt 3 20: Settle the reopened invoice before changing its queued sessions%', '1/1'),
-- 1 of 3 sessions refunded while cancelled, beside a voucher line (either
-- written first), a Credit Package or the Premium Bundle: the guided Refund
-- in full pays back the sessions' S$40 and the other line's value, whichever
-- line is listed first; then paid, 1 of 3 for S$20.
('TV', 'fixed', 'sale A th,v; cancel; backt 2 20; reopen; refundall; pay',
  '{"status":"paid","net":20,"sess":"1/3 r2 c0 available","holds":{"A":"0.00"},"swait":0,"sev":1,"sholder":"A","sinv":"","error":null}',
  'refundall: Settle the reopened invoice before changing its queued sessions%', '1/1'),
('TV2', 'fixed', 'sale A v,th; cancel; backt 2 20; reopen; refundall; pay',
  '{"status":"paid","net":20,"sess":"1/3 r2 c0 available","holds":{"A":"0.00"},"swait":0,"sev":1,"sholder":"A","sinv":"","error":null}',
  'refundall: Settle the reopened invoice before changing its queued sessions%', '1/1'),
('CPs', 'fixed', 'sale A th,cp; cancel; backt 2 20; reopen; refundall; pay',
  '{"status":"paid","net":20,"sess":"1/3 r2 c0 available","holds":{"A":"0.00"},"swait":0,"sev":1,"sholder":"A","sinv":"","error":null}',
  'refundall: Settle the reopened invoice before changing its queued sessions%', '1/1'),
('PBs', 'fixed', 'sale A th,pbv; cancel; backt 2 20; reopen; refundall; pay',
  '{"status":"paid","net":20,"sess":"1/3 r2 c0 available","holds":{"A":"0.00"},"swait":0,"sev":1,"sholder":"A","sinv":"","error":null}',
  'refundall: Settle the reopened invoice before changing its queued sessions%', '1/1'),
-- More than the money held, while it waits: before 479 refused as "2 of 3
-- sessions remain refundable" (the refunds before the reopening counted);
-- now for the money.
('WSx', 'fixed', 'sale A th; cancel; backt 1 20; reopen; backt 1 60',
  '{"status":"partially_paid","net":40,"sess":"0/3 r1 c2 refunded","swait":1,"squeued":3,"sinv":"","error~":"backt 1 60: Refund exceeds net payments still held%"}',
  'backt 1 60: Refund whole unused therapy sessions at their original paid value; 2 of 3 sessions remain refundable%', '1/1'),
-- The Owner's case of 29 Oct 2026 (the therapy line's sessions all refunded
-- by line while cancelled, reopened, another line on it; kept below), and
-- what 479 adds to it: after the guided Refund in full, the S$30 kept
-- refunded by line (before 479: "0 of 3 sessions remain refundable"), 1
-- session off the queue, then paid; 'keep' or 'transfer' to B while it waits
-- (before 479 refused), then the Refund in full (the vouchers' S$60 only)
-- and paid.
('OWak', 'fixed', 'sale A th,cp; cancel; backt 2 60; reopen; payamt 30; refundall; backt 2 20; pay',
  '{"status":"paid","net":40,"sess":"2/3 r1 c0 available","holds":{"A":"0.00"},"swait":0,"sev":1,"sholder":"A","sinv":"","error":null}',
  'backt 2 20: Refund whole unused therapy sessions at their original paid value; 0 of 3 sessions remain refundable%', '1/1'),
('OWbk', 'fixed', 'sale A th,v; cancel; backt 2 60; reopen; payamt 20; change B keep; refundall; pay',
  '{"status":"paid","net":60,"sess":"3/3 r0 c0 available","holds":{"A":"0.00","B":"0.00"},"swait":0,"sholder":"A","icust":"B","sinv":"","error":null}',
  'change B keep: Settle the pending session reopening before changing its allocation%', '1/1'),
('OWbt', 'fixed', 'sale A th,v; cancel; backt 2 60; reopen; payamt 20; change B; refundall; pay',
  '{"status":"paid","net":60,"sess":"3/3 r0 c0 available","holds":{"A":"0.00","B":"0.00"},"swait":0,"sholder":"B","icust":"B","sinv":"","error":null}',
  'change B: Settle the pending session reopening before changing its allocation%', '1/1'),
-- A customer change while it waits, an invoice with only the therapy line
-- (no 'transfer' or 'keep' asked): the sessions follow the change.
('CTw', 'fixed', 'sale A th; cancel; backt 1 20; reopen; change B',
  '{"status":"partially_paid","net":40,"sess":"0/3 r1 c2 refunded","swait":1,"squeued":3,"sholder":"B","icust":"B","sinv":"","error":null}',
  'change B: Settle the pending session reopening before changing its allocation%', '1/1'),
('CTwp', 'fixed', 'sale A th; cancel; backt 1 20; reopen; change B; pay',
  '{"status":"paid","net":60,"sess":"3/3 r0 c0 available","swait":0,"sev":1,"sholder":"B","icust":"B","sinv":"","error":null}',
  'change B: Settle the pending session reopening before changing its allocation%', '1/1'),
('CTc', 'fixed', 'sale A th; cancel; backt 1 20; reopen; cancel; change B; reopen; pay',
  '{"status":"paid","net":60,"sess":"3/3 r0 c0 available","swait":0,"sholder":"B","icust":"B","sinv":"","error":null}',
  'change B: Settle the pending session reopening before changing its allocation%', '1/1'),
('CKn', 'fixed', 'sale A th; cancel; backt 1 20; reopen; change B keep; pay',
  '{"status":"paid","net":60,"sess":"3/3 r0 c0 available","swait":0,"sholder":"B","icust":"B","sinv":"","error":null}',
  'change B keep: Settle the pending session reopening before changing its allocation%', '1/1'),
('CTpg', 'fixed', 'sale A th; cancel; backt 1 20; reopen; change B page; pay',
  '{"status":"paid","net":60,"sess":"3/3 r0 c0 available","swait":0,"sev":1,"sholder":"B","icust":"B","sinv":"","error":null}',
  'change B page: Settle the pending session reopening before changing its allocation%', '1/1'),
('CNN', 'fixed', 'sale A th; cancel; backt 1 20; reopen; change B; change C; pay',
  '{"status":"paid","net":60,"sess":"3/3 r0 c0 available","swait":0,"sholder":"C","icust":"C","sinv":"","error":null}',
  'change B: Settle the pending session reopening before changing its allocation%', '1/1'),
('CNb', 'fixed', 'sale A th; cancel; backt 1 20; reopen; change B; change A; pay',
  '{"status":"paid","net":60,"sess":"3/3 r0 c0 available","swait":0,"sholder":"A","icust":"A","sinv":"","error":null}',
  'change B: Settle the pending session reopening before changing its allocation%', '1/1'),
('CTr', 'fixed', 'sale A th; cancel; backt 1 20; reopen; change B; backt 1 20; pay',
  '{"status":"paid","net":40,"sess":"2/3 r1 c0 available","swait":0,"sholder":"B","icust":"B","sinv":"","error":null}',
  'change B: Settle the pending session reopening before changing its allocation%', '1/1'),
-- With a voucher line ('transfer' or 'keep' asked): 'keep' leaves the
-- sessions and the vouchers with A; 'transfer' moves them to B; the two in
-- turn; 'keep', then cancelled again.
('CKv', 'fixed', 'sale A th,v; cancel; backt 2 20; reopen; change B keep; pay',
  '{"status":"paid","net":120,"sess":"3/3 r0 c0 available","holds":{"A":"0.00/2","B":"0.00"},"swait":0,"sholder":"A","icust":"B","sinv":"","error":null}',
  'change B keep: Settle the pending session reopening before changing its allocation%', '1/1'),
('CTv', 'fixed', 'sale A th,v; cancel; backt 2 20; reopen; change B; pay',
  '{"status":"paid","net":120,"sess":"3/3 r0 c0 available","holds":{"A":"0.00","B":"0.00/2"},"swait":0,"sholder":"B","icust":"B","sinv":"","error":null}',
  'change B: Settle the pending session reopening before changing its allocation%', '1/1'),
('CKT', 'fixed', 'sale A th,v; cancel; backt 2 20; reopen; change B keep; change C; pay',
  '{"status":"paid","net":120,"sess":"3/3 r0 c0 available","holds":{"A":"0.00","B":"0.00","C":"0.00/2"},"swait":0,"sholder":"C","icust":"C","sinv":"","error":null}',
  'change B keep: Settle the pending session reopening before changing its allocation%', '1/1'),
('CTK', 'fixed', 'sale A th,v; cancel; backt 2 20; reopen; change B; change C keep; pay',
  '{"status":"paid","net":120,"sess":"3/3 r0 c0 available","holds":{"A":"0.00","B":"0.00/2","C":"0.00"},"swait":0,"sholder":"B","icust":"C","sinv":"","error":null}',
  'change B: Settle the pending session reopening before changing its allocation%', '1/1'),
('CKc', 'fixed', 'sale A th,v; cancel; backt 2 20; reopen; change B keep; cancel; reopen; pay',
  '{"status":"paid","net":120,"sess":"3/3 r0 c0 available","holds":{"A":"0.00/2","B":"0.00"},"swait":0,"sholder":"A","icust":"B","sinv":"","error":null}',
  'change B keep: Settle the pending session reopening before changing its allocation%', '1/1'),
-- Sessions 'keep' left with A, after the payment: the invoice set back to
-- A; cancelled and reopened; a correction of the notes; a refund by line.
('KK2', 'fixed', 'sale A th,v; cancel; backt 2 20; reopen; change B keep; pay; change A keep',
  '{"status":"paid","net":120,"sess":"3/3 r0 c0 available","holds":{"A":"0.00/2","B":"0.00"},"sholder":"A","icust":"A","sinv":"","error":null}',
  'change B keep: Settle the pending session reopening before changing its allocation%', '1/1'),
('KK3', 'fixed', 'sale A th,v; cancel; backt 2 20; reopen; change B keep; pay; cancel; reopen',
  '{"status":"paid","net":120,"sess":"3/3 r0 c0 available","holds":{"A":"0.00/2","B":"0.00"},"sev":2,"sholder":"A","icust":"B","sinv":"","error":null}',
  'change B keep: Settle the pending session reopening before changing its allocation%', '1/1'),
('KKn', 'fixed', 'sale A th,v; cancel; backt 2 20; reopen; change B keep; pay; note',
  '{"status":"paid","net":120,"sess":"3/3 r0 c0 available","holds":{"A":"0.00/2","B":"0.00"},"sholder":"A","icust":"B","sinv":"","error":null}',
  'change B keep: Settle the pending session reopening before changing its allocation%', '1/1'),
('KKs', 'fixed', 'sale A th,v; cancel; backt 2 20; reopen; change B keep; pay; backt 2 20',
  '{"status":"paid","net":100,"sess":"2/3 r1 c0 available","holds":{"A":"0.00/2","B":"0.00"},"sholder":"A","icust":"B","sinv":"","error":null}',
  'change B keep: Settle the pending session reopening before changing its allocation%', '1/1'),
('KK1', 'known', 'sale A th,v; cancel; backt 2 20; reopen; change B keep; pay; change C keep',
  '{"status":"paid","net":120,"sess":"3/3 r0 c0 available","holds":{"A":"0.00/2","B":"0.00"},"sholder":"A","icust":"B","sinv":"","error~":"change C keep: These therapy sessions were left with T479 after/KK1/A when the invoice''s customer was changed, so their line, quantity or store cannot be changed, nor the invoice moved to another customer, from this invoice: set the invoice''s customer back to them first. Nothing was changed.%"}',
  'change B keep: Settle the pending session reopening before changing its allocation%', '1/1'),
-- Known (479's NOT COVERED 3, while they still wait; the review of 29 Oct
-- 2026): 'keep' to B, then, before the payment, the invoice moved to C with
-- 'keep' (it goes through: the sessions stay with A, the invoice is C's;
-- with 'transfer' they go to C, CKT), or the therapy line's quantity
-- changed (refused as for any waiting session).
('CKK', 'known', 'sale A th,v; cancel; backt 2 20; reopen; change B keep; change C keep; pay',
  '{"status":"paid","net":120,"sess":"3/3 r0 c0 available","holds":{"A":"0.00/2","B":"0.00","C":"0.00"},"swait":0,"sholder":"A","icust":"C","sinv":"","error":null}',
  'change B keep: Settle the pending session reopening before changing its allocation%', '1/1'),
('CKq', 'known', 'sale A th,v; cancel; backt 2 20; reopen; change B keep; qty 2',
  '{"status":"partially_paid","net":100,"sess":"0/3 r1 c2 refunded","swait":1,"squeued":3,"sholder":"A","icust":"B","sinv":"","error~":"qty 2: Settle the pending session reopening before changing its allocation%"}',
  'change B keep: Settle the pending session reopening before changing its allocation%', '1/1'),
-- Kept (the Owner, 29 Oct 2026, "Keep today's result"): the therapy line's
-- sessions all refunded by line while the invoice was cancelled, the invoice
-- reopened, another line on it: the guided Refund in full and the guided
-- Cancel with "Record refund paid" refund the other item and keep the
-- session money, the waiting sessions not offered again; exactly as before
-- 479. A Credit Package, S$30 paid since (the package written first too;
-- the Cancel; then paid; nothing paid since); 2 vouchers, S$20 paid (the
-- voucher line written first; the Cancel; then paid; nothing paid since);
-- the Premium Bundle (then paid; the Cancel); then merged into K and paid.
('OWa', 'kept', 'sale A th,cp; cancel; backt 2 60; reopen; payamt 30; refundall',
  '{"status":"partially_paid","net":30,"rdue":0,"sess":"0/3 r3 c0 refunded","holds":{"A":"0.00"},"swait":1,"squeued":3,"sholder":"A","sinv":"","error":null}', null, '1/1'),
('OWa2', 'kept', 'sale A cp,th; cancel; backt 2 60; reopen; payamt 30; refundall',
  '{"status":"partially_paid","net":30,"rdue":0,"sess":"0/3 r3 c0 refunded","holds":{"A":"0.00"},"swait":1,"squeued":3,"sholder":"A","sinv":"","error":null}', null, '1/1'),
('OWac', 'kept', 'sale A th,cp; cancel; backt 2 60; reopen; payamt 30; guidedcancel',
  '{"status":"cancelled","net":30,"fdue":30,"sess":"0/3 r3 c0 refunded","holds":{"A":"0.00"},"swait":1,"squeued":3,"sholder":"A","sinv":"","error":null}', null, '1/1'),
('OWap', 'kept', 'sale A th,cp; cancel; backt 2 60; reopen; payamt 30; refundall; pay',
  '{"status":"paid","net":60,"sess":"3/3 r0 c0 available","holds":{"A":"0.00"},"swait":0,"sev":1,"sholder":"A","sinv":"","error":null}', null, null),
('OWa0', 'kept', 'sale A th,cp; cancel; backt 2 60; reopen; refundall; pay',
  '{"status":"paid","net":60,"sess":"3/3 r0 c0 available","holds":{"A":"0.00"},"swait":0,"sev":1,"sholder":"A","sinv":"","error":null}', null, null),
('OWb', 'kept', 'sale A th,v; cancel; backt 2 60; reopen; payamt 20; refundall',
  '{"status":"partially_paid","net":20,"rdue":0,"sess":"0/3 r3 c0 refunded","holds":{"A":"0.00"},"swait":1,"squeued":3,"sholder":"A","sinv":"","error":null}', null, '1/1'),
('OWb2', 'kept', 'sale A v,th; cancel; backt 2 60; reopen; payamt 20; refundall',
  '{"status":"partially_paid","net":20,"rdue":0,"sess":"0/3 r3 c0 refunded","holds":{"A":"0.00"},"swait":1,"squeued":3,"sholder":"A","sinv":"","error":null}', null, '1/1'),
('OWbc', 'kept', 'sale A th,v; cancel; backt 2 60; reopen; payamt 20; guidedcancel',
  '{"status":"cancelled","net":20,"fdue":20,"sess":"0/3 r3 c0 refunded","holds":{"A":"0.00"},"swait":1,"squeued":3,"sholder":"A","sinv":"","error":null}', null, '1/1'),
('OWbp', 'kept', 'sale A th,v; cancel; backt 2 60; reopen; payamt 20; refundall; pay',
  '{"status":"paid","net":60,"sess":"3/3 r0 c0 available","holds":{"A":"0.00"},"swait":0,"sev":1,"sholder":"A","sinv":"","error":null}', null, null),
('OWb0', 'kept', 'sale A th,v; cancel; backt 2 60; reopen; refundall; pay',
  '{"status":"paid","net":60,"sess":"3/3 r0 c0 available","holds":{"A":"0.00"},"swait":0,"sev":1,"sholder":"A","sinv":"","error":null}', null, null),
('OWpb', 'kept', 'sale A th,pbv; cancel; backt 2 60; reopen; payamt 20; refundall; pay',
  '{"status":"paid","net":60,"sess":"3/3 r0 c0 available","holds":{"A":"0.00"},"swait":0,"sev":1,"sholder":"A","sinv":"","error":null}', null, null),
('OWpbc', 'kept', 'sale A th,pbv; cancel; backt 2 60; reopen; payamt 20; guidedcancel',
  '{"status":"cancelled","net":20,"fdue":20,"sess":"0/3 r3 c0 refunded","holds":{"A":"0.00"},"swait":1,"squeued":3,"sholder":"A","sinv":"","error":null}', null, '1/1'),
('OWbm', 'kept', 'sale A th,v; cancel; backt 2 60; reopen; payamt 20; refundall; merge K A; pay',
  '{"status":"paid","net":60,"sess":"3/3 r0 c0 available","holds":{"K":"0.00"},"swait":0,"sholder":"K","sinv":"","error":null}', null, null),
-- Kept (NOT COVERED 13): refunded in full before the reopening, S$20 paid
-- since: the guided Refund in full finds nothing to refund and the guided
-- Cancel no money to return (the refund options do not offer what was paid
-- back), as for a Credit Package and for vouchers in that state; the guided
-- Cancel without "Record refund paid", then "Record refund paid" with no
-- line, reopened and paid: 3 of 3.
('GRF', 'kept', 'sale A th; refundall; reopen; payamt 20; refundall',
  '{"status":"partially_paid","net":20,"sess":"0/3 r3 c0 refunded","swait":1,"squeued":3,"sholder":"A","sinv":"","error~":"refundall: There is nothing left to refund on this invoice%"}', null, '1/1'),
('GCF', 'kept', 'sale A th; refundall; reopen; payamt 20; guidedcancel',
  '{"status":"partially_paid","net":20,"sess":"0/3 r3 c0 refunded","swait":1,"squeued":3,"sholder":"A","sinv":"","error~":"guidedcancel: There is no money held on this invoice to return%"}', null, '1/1'),
('GRFk', 'kept', 'sale A th; refundall; reopen; payamt 20; guidedkeep; refundpaid; reopen; pay',
  '{"status":"paid","net":60,"sess":"3/3 r0 c0 available","swait":0,"sholder":"A","sinv":"","error":null}', null, null),
('CRF', 'kept', 'sale A cp; refundall; reopen; payamt 20; refundall',
  '{"status":"partially_paid","net":20,"sess":"-","error~":"refundall: There is nothing left to refund on this invoice%"}', null, null),
('VRF', 'kept', 'sale A v; refundall; reopen; payamt 30; refundall',
  '{"status":"partially_paid","net":30,"sess":"-","error~":"refundall: There is nothing left to refund on this invoice%"}', null, null),
-- Controls: the same with and without 479.
('TH0', 'control', 'sale A th; cancel; backt 1 20; reopen; pay',
  '{"status":"paid","net":60,"required":20,"dlgs":3,"queueds":3,"gaves":3,"sess":"3/3 r0 c0 available","swait":0,"sev":1,"sinv":"","every":"","error":null}', null, null),
('THc', 'control', 'sale A th; cancel; reopen',
  '{"status":"paid","net":60,"required":0,"dlgs":3,"queueds":3,"gaves":3,"sess":"3/3 r0 c0 available","swait":0,"sev":1,"sinv":"","every":"","error":null}', null, null),
('THcc', 'control', 'sale A th; cancel; reopen; cancel; reopen',
  '{"status":"paid","net":60,"required":0,"dlgs":3,"queueds":3,"gaves":3,"sess":"3/3 r0 c0 available","swait":0,"sev":2,"sinv":"","every":"","error":null}', null, null),
('RSr', 'control', 'sale A th; cancel; reopen; backt 1 20',
  '{"status":"paid","net":40,"sess":"2/3 r1 c0 available","swait":0,"sev":1,"sinv":"","error":null}', null, null),
('RF0', 'control', 'sale A th; refundall; reopen; backt 1 20',
  '{"status":"unpaid","net":0,"sess":"0/3 r3 c0 refunded","swait":1,"squeued":3,"sinv":"","error~":"backt 1 20: Allocate the refund to lines and original payment sources%"}', null, '1/1'),
('CSw', 'control', 'sale A th; cancel; backt 1 20; reopen; store S2',
  '{"status":"partially_paid","net":40,"swait":1,"squeued":3,"sholder":"A","sinv":"","error~":"store S2: Settle the pending session reopening before changing its allocation%"}', null, '1/1'),
('CQw', 'control', 'sale A th; cancel; backt 1 20; reopen; qty 2',
  '{"status":"partially_paid","net":40,"swait":1,"squeued":3,"sholder":"A","sinv":"","error~":"qty 2: Settle the pending session reopening before changing its allocation%"}', null, '1/1'),
('PK', 'control', 'sale A th; change B keep',
  '{"status":"paid","net":60,"sess":"3/3 r0 c0 available","sholder":"B","icust":"B","sinv":"","error":null}', null, null),
('PVK', 'control', 'sale A th,v; change B keep',
  '{"status":"paid","net":120,"sess":"3/3 r0 c0 available","holds":{"A":"0.00/2","B":"0.00"},"sholder":"B","icust":"B","sinv":"","error":null}', null, null),
('CNCr', 'control', 'sale A th; cancel; change B; reopen; pay',
  '{"status":"paid","net":60,"sess":"3/3 r0 c0 available","sholder":"B","icust":"B","sinv":"","error":null}', null, null),
('THq', 'control', 'sale A th; cancel; backt 1 20; reopen; cancel; reopen; pay',
  '{"status":"paid","net":60,"required":20,"dlgs":3,"queueds":3,"gaves":3,"sess":"3/3 r0 c0 available","swait":0,"stwice":0,"sev":1,"sholder":"A","sinv":"","every":"","error":null}', null, null),
('THmg', 'control', 'sale A th; cancel; backt 1 20; reopen; merge K A; cancel; reopen; pay',
  '{"status":"paid","net":60,"sess":"3/3 r0 c0 available","swait":0,"sev":1,"sholder":"K","sinv":"","every":"","error":null}', null, null),
('VQ', 'control', 'sale A v; cancel; backv 1 1; reopen; cancel; reopen; pay',
  '{"dlg":0,"gave":0,"dlgv":2,"queuedv":2,"gavev":2,"required":30,"every":"","holds":{"A":"0.00/2"},"status":"paid","net":60,"sess":"-","error":null}', null, null),
('K5', 'control', 'sale A cp; spend A; spend A; cancel; back 1 60; reopen; unspend S2; cancel; reopen; pay',
  '{"dlg":80,"queued":80,"gave":80,"required":60,"every":"","holds":{"A":"80.00"},"status":"paid","net":100,"sess":"-","error":null}', null, null),
-- Known (479's NOT COVERED 2): a customer change of a paid invoice gives
-- the new customer the line's sessions as new; one refunded comes back.
('PRT', 'known', 'sale A th; backt 1 20; change B',
  '{"status":"paid","net":40,"sess":"3/3 r0 c0 available","sholder":"B","icust":"B","sinv":"","error":null}', null, null),
-- Known (479's NOT COVERED 7, 475's NOT COVERED 3 and 4; made by hand): a
-- session queued twice before 475, refunded by line while cancelled again,
-- or its invoice's customer changed: refused (now as its evidence; before,
-- each with its own message); a waiting row one less than its session
-- shows, reopened again (the difference queued) and paid: settled.
('Kdup', 'known', 'sale A th; cancel; backt 1 20; reopen; cancel; dup; backt 1 20',
  '{"status":"cancelled","net":40,"swait":2,"squeued":6,"error~":"backt 1 20: Therapy session reopening changed; reload its original evidence%"}',
  'backt 1 20: Settle the reopened invoice before changing its queued sessions%', '2/1'),
('Kdupc', 'known', 'sale A th; cancel; backt 1 20; reopen; cancel; dup; change B',
  '{"status":"cancelled","net":40,"swait":2,"squeued":6,"sholder":"A","icust":"A","error~":"change B: Therapy session reopening changed; reload its original evidence%"}',
  'change B: Settle the pending session reopening before changing its allocation%', '2/1'),
('Kshr', 'known', 'sale A th; cancel; backt 1 20; reopen; cancel; shrink; reopen; pay',
  '{"status":"paid","net":60,"sess":"3/3 r0 c0 available","swait":0,"sev":2,"sinv":"","error":null}',
  'pay: Therapy session reopening changed; reload its original evidence%', '1/1'),
-- Known (479's NOT COVERED 10; the Owner, 29 Oct 2026 ~18:45 SGT, "Keep
-- today's refusal"): cancelled and its money paid back with no line
-- ("Record refund paid"), reopened, part of it paid again: the plans cut
-- the line to the money held, not whole sessions, and the approval refuses,
-- before 479 and after it the same (the guided Cancel too); with a voucher
-- line, refused whichever line the cut lands on, the same before 479 and
-- after it (K10 checks the message by the line listed first).
('KGn', 'known', 'sale A th; cancel; refundpaid; reopen; payamt 30; refundall',
  '{"status":"partially_paid","net":30,"sess":"0/3 r0 c3 cancelled","swait":1,"squeued":3,"sholder":"A","sinv":"","error~":"refundall: Refund whole unused therapy sessions at their original paid value; 3 of 3 sessions remain refundable%"}', null, '1/1'),
('KGnc', 'known', 'sale A th; cancel; refundpaid; reopen; payamt 30; guidedcancel',
  '{"status":"partially_paid","net":30,"sess":"0/3 r0 c3 cancelled","swait":1,"squeued":3,"sholder":"A","sinv":"","error~":"guidedcancel: Refund whole unused therapy sessions at their original paid value; 3 of 3 sessions remain refundable%"}', null, '1/1'),
('TVn', 'known', 'sale A th,v; cancel; refundpaid; reopen; payamt 50; refundall',
  '{"status":"partially_paid","net":50,"sess":"0/3 r0 c3 cancelled","swait":1,"squeued":3,"sholder":"A","sinv":"","error~":"refundall: %"}', null, '1/1'),
-- Known (479's NOT COVERED 14): half a cent. 4 sessions at S$20 with an
-- Owner's S$0.01 discount (S$79.99), 2 refunded by line while cancelled
-- (S$40.00), reopened (S$39.99 held for the other 2): the guided Refund in
-- full's S$39.99 is not 2 sessions as 479 values those refunded since the
-- reopening (S$40.00), so refused; by line, 1 session (S$20.00) goes
-- through, and the last one, valued at S$20.00 with S$19.99 held, cannot be
-- refunded: S$20.00 is refused for the money ("Refund exceeds net payments
-- still held", KRd1) and S$19.99 by the sessions' rule ("... 3 of 4 sessions
-- remain refundable", KRd2); before 479 refused by 252 (S$20.00 by line
-- there for its own rounding: 1 session after 2 was worth S$19.99). Paid, it
-- settles: 4 of 4 for S$79.99.
('KRd', 'known', 'saled A th4 0.01; cancel; backt 1 40; reopen; refundall',
  '{"status":"partially_paid","net":39.99,"swait":1,"squeued":4,"sholder":"A","sinv":"","error~":"refundall: Refund whole unused therapy sessions at their original paid value; 4 of 4 sessions remain refundable%"}',
  'refundall: Settle the reopened invoice before changing its queued sessions%', '1/1'),
('KRdc', 'known', 'saled A th4 0.01; cancel; backt 1 40; reopen; guidedcancel',
  '{"status":"partially_paid","net":39.99,"swait":1,"squeued":4,"sholder":"A","sinv":"","error~":"guidedcancel: Refund whole unused therapy sessions at their original paid value; 4 of 4 sessions remain refundable%"}',
  'guidedcancel: Settle the reopened invoice before changing its queued sessions%', '1/1'),
('KRdk', 'known', 'saled A th4 0.01; cancel; backt 1 40; reopen; guidedkeep; refundpaid',
  '{"status":"cancelled","net":0,"swait":1,"squeued":4,"sholder":"A","sinv":"","error":null}', null, '1/1'),
('KRd1', 'known', 'saled A th4 0.01; cancel; backt 1 40; reopen; backt 1 20; backt 1 20',
  '{"status":"partially_paid","net":19.99,"swait":1,"squeued":3,"sholder":"A","sinv":"","error~":"backt 1 20: Refund exceeds net payments still held%"}',
  'backt 1 20: Refund whole unused therapy sessions at their original paid value; 2 of 4 sessions remain refundable%', '1/1'),
('KRd2', 'known', 'saled A th4 0.01; cancel; backt 1 40; reopen; backt 1 20; backt 1 19.99',
  '{"status":"partially_paid","net":19.99,"swait":1,"squeued":3,"sholder":"A","sinv":"","error~":"backt 1 19.99: Refund whole unused therapy sessions at their original paid value; 3 of 4 sessions remain refundable%"}',
  'backt 1 20: Refund whole unused therapy sessions at their original paid value; 2 of 4 sessions remain refundable%', '1/1'),
('KRdp', 'known', 'saled A th4 0.01; cancel; backt 1 40; reopen; pay',
  '{"status":"paid","net":79.99,"sess":"4/4 r0 c0 available","swait":0,"sev":1,"sholder":"A","sinv":"","error":null}', null, null),
-- Known (479's NOT COVERED 1, a product line; not 479's, the review of 29
-- Oct 2026): the payment that settles the invoice takes the S$40 product
-- from stock again (a second store_sale) though its line was refunded: a
-- product and 3 sessions, cancelled, 1 session refunded by line, reopened,
-- the guided Refund in full (the product's S$40 and 2 sessions, either line
-- first), paid S$20: 1 of 3 and the product for S$20 net (before 479 the
-- Refund in full was refused; PRn1, PRn2); before 479 already: a voucher
-- line and the product, cancelled, 1 voucher refunded, reopened, the guided
-- Refund in full, paid S$30: 1 voucher and the product (VPR); the product
-- refunded by line while cancelled and again after the reopening, paid: 3
-- sessions and the product for S$60 (PRxk); a part-paid invoice never
-- reopened, the product refunded by line, the rest paid: 2 vouchers and the
-- product for S$60 (PRpp).
('PRn1', 'known', 'sale A pr,th; cancel; backt 1 20; reopen; refundall; pay',
  '{"status":"paid","net":20,"sess":"1/3 r2 c0 available","swait":0,"sev":1,"sholder":"A","stock":"invoice_cancel_return 1, store_sale 2","sinv":"","error":null}',
  'refundall: Settle the reopened invoice before changing its queued sessions%', '1/1'),
('PRn2', 'known', 'sale A th,pr; cancel; backt 1 20; reopen; refundall; pay',
  '{"status":"paid","net":20,"sess":"1/3 r2 c0 available","swait":0,"sev":1,"sholder":"A","stock":"invoice_cancel_return 1, store_sale 2","sinv":"","error":null}',
  'refundall: Settle the reopened invoice before changing its queued sessions%', '1/1'),
('VPR', 'known', 'sale A pr,v; cancel; backv 1 1; reopen; refundall; pay',
  '{"status":"paid","net":30,"sess":"-","holds":{"A":"0.00/1"},"stock":"invoice_cancel_return 1, store_sale 2","error":null}', null, null),
('PRxk', 'known', 'sale A pr,th; cancel; backps 2 40; reopen; backps 2 40; pay',
  '{"status":"paid","net":60,"sess":"3/3 r0 c0 available","swait":0,"stock":"invoice_cancel_return 1, store_sale 2","sinv":"","error":null}', null, null),
('PRpp', 'known', 'sale A pr,v 50; backps 2 40; pay',
  '{"status":"paid","net":60,"sess":"-","holds":{"A":"0.00/2"},"stock":"store_sale 1","error":null}', null, null),
-- Known (479's NOT COVERED 15; not 479's, the review of 29 Oct 2026): money a
-- Cancel leaves due on a reopened invoice that issued credit cannot be
-- recorded as paid back with no line ("Allocate a correction refund ...");
-- only whole sessions by line from 479: the Owner's case (OWac, S$30 due:
-- S$20 by line from 479, S$10 stays due; OWacR, OWac20R); 1 session
-- refunded while cancelled, S$5 paid since, the guided Cancel (refused
-- before 479; S$5 due, CPs5) or the plain Cancel and the package by line
-- (S$45 due before 479, S$5 from 479; CPs5k); the Premium Bundle, S$20 due
-- (OWpbcR; one session by line clears it from 479, OWpbc20); with vouchers
-- instead "Record refund paid" with no line records it (OWbcR).
('OWacR', 'known', 'sale A th,cp; cancel; backt 2 60; reopen; payamt 30; guidedcancel; refundpaid',
  '{"status":"cancelled","net":30,"fdue":30,"sess":"0/3 r3 c0 refunded","holds":{"A":"0.00"},"swait":1,"squeued":3,"sholder":"A","sinv":"","error~":"refundpaid: Allocate a correction refund to the original unused purchased benefits; it cannot be cashed out as an unallocated overpayment%"}', null, '1/1'),
('OWac20R', 'known', 'sale A th,cp; cancel; backt 2 60; reopen; payamt 30; guidedcancel; backt 2 20; refundpaid',
  '{"status":"cancelled","net":10,"fdue":10,"sess":"0/3 r3 c0 refunded","holds":{"A":"0.00"},"swait":1,"squeued":2,"sholder":"A","sinv":"","error~":"refundpaid: Allocate a correction refund to the original unused purchased benefits; it cannot be cashed out as an unallocated overpayment%"}',
  'backt 2 20: Refund whole unused therapy sessions at their original paid value; 0 of 3 sessions remain refundable%', '1/1'),
('CPs5', 'known', 'sale A th,cp; cancel; backt 2 20; reopen; payamt 5; guidedcancel; refundpaid',
  '{"status":"cancelled","net":5,"fdue":5,"sess":"0/3 r3 c0 refunded","holds":{"A":"0.00"},"swait":1,"squeued":1,"sholder":"A","sinv":"","error~":"refundpaid: Allocate a correction refund to the original unused purchased benefits; it cannot be cashed out as an unallocated overpayment%"}',
  'guidedcancel: Settle the reopened invoice before changing its queued sessions%', '1/1'),
('CPs5k', 'known', 'sale A th,cp; cancel; backt 2 20; reopen; payamt 5; guidedkeep; back 1 all; backt 2 40; refundpaid',
  '{"status":"cancelled","net":5,"fdue":5,"sess":"0/3 r3 c0 refunded","holds":{"A":"0.00"},"swait":1,"squeued":1,"sholder":"A","sinv":"","error~":"refundpaid: Allocate a correction refund to the original unused purchased benefits; it cannot be cashed out as an unallocated overpayment%"}',
  'backt 2 40: Settle the reopened invoice before changing its queued sessions%', '1/1'),
('OWpbcR', 'known', 'sale A th,pbv; cancel; backt 2 60; reopen; payamt 20; guidedcancel; refundpaid',
  '{"status":"cancelled","net":20,"fdue":20,"sess":"0/3 r3 c0 refunded","holds":{"A":"0.00"},"swait":1,"squeued":3,"sholder":"A","sinv":"","error~":"refundpaid: Allocate a correction refund to the original unused purchased benefits; it cannot be cashed out as an unallocated overpayment%"}', null, '1/1'),
('OWpbc20', 'known', 'sale A th,pbv; cancel; backt 2 60; reopen; payamt 20; guidedcancel; backt 2 20',
  '{"status":"cancelled","net":0,"fdue":0,"sess":"0/3 r3 c0 refunded","holds":{"A":"0.00"},"swait":1,"squeued":2,"sholder":"A","sinv":"","error":null}',
  'backt 2 20: Refund whole unused therapy sessions at their original paid value; 0 of 3 sessions remain refundable%', '1/1'),
('OWbcR', 'known', 'sale A th,v; cancel; backt 2 60; reopen; payamt 20; guidedcancel; refundpaid',
  '{"status":"cancelled","net":0,"fdue":0,"sess":"0/3 r3 c0 refunded","holds":{"A":"0.00"},"swait":1,"squeued":3,"sholder":"A","sinv":"","error":null}', null, '1/1'),
-- Answer F with two other lines, the plan not cut (the Owner, 29 Oct 2026
-- ~18:45 SGT: only a cut plan with another line to refund is refused): a
-- voucher line and a S$40 product beside the sessions, 1 session refunded
-- by line while cancelled, reopened: the guided Refund in full pays back
-- the S$140 held (the sessions' S$40, the vouchers, the product), the
-- therapy line written first (TVP) or the voucher line (VTP); before 479
-- refused.
('TVP', 'fixed', 'sale A th,v,pr; cancel; backt 2 20; reopen; refundall',
  '{"status":"partially_paid","net":0,"sess":"0/3 r3 c0 refunded","holds":{"A":"0.00"},"swait":1,"squeued":1,"stock":"invoice_cancel_return 1, store_sale 1","sholder":"A","sinv":"","error":null}',
  'refundall: Settle the reopened invoice before changing its queued sessions%', '1/1'),
('VTP', 'fixed', 'sale A v,th,pr; cancel; backt 2 20; reopen; refundall',
  '{"status":"partially_paid","net":0,"sess":"0/3 r3 c0 refunded","holds":{"A":"0.00"},"swait":1,"squeued":1,"stock":"invoice_cancel_return 1, store_sale 1","sholder":"A","sinv":"","error":null}',
  'refundall: Settle the reopened invoice before changing its queued sessions%', '1/1'),
-- A guided request approved after the invoice changed (S$10 paid between
-- the request and the approval; the approver confirms the plan as it reads
-- then): with a voucher line, the plan not cut, it goes through as answer F
-- asked (STv: the S$100 paid back, S$10 kept; before 479 refused); with a
-- voucher line and a product (KNOWN, NOT COVERED 16) it is refused as before
-- 479 whichever line is listed first: the plan the request saved no longer
-- holds the money held, and with two other lines one of which holds
-- vouchers 479 cannot tell from the invoice alone whether the plan carried
-- out was cut (STvp: the S$150 held, the 3 sessions waiting).
('STv', 'fixed', 'sale A th,v; cancel; backt 2 20; reopen; request refund_full; payamt 10; approve',
  '{"status":"partially_paid","net":10,"sess":"0/3 r3 c0 refunded","holds":{"A":"0.00"},"swait":1,"squeued":1,"sholder":"A","sinv":"","error":null}',
  'approve: Settle the reopened invoice before changing its queued sessions%', '1/1'),
('STvp', 'known', 'sale A th,v,pr; cancel; backt 2 20; reopen; request refund_full; payamt 10; approve',
  '{"status":"partially_paid","net":150,"sess":"0/3 r1 c2 refunded","holds":{"A":"0.00"},"swait":1,"squeued":3,"stock":"invoice_cancel_return 1, store_sale 1","sholder":"A","sinv":"","error~":"approve: Settle the reopened invoice before changing its queued sessions%"}', null, '1/1'),
-- The second fix review (3 Nov 2026; KNOWN, NOT COVERED 16): approved after
-- the invoice changed (S$10 paid between the request and the approval), two
-- other lines, one holding credit or vouchers, where no other line offers
-- anything at the session's turn (the credit and vouchers listed before the
-- sessions are taken back first; a product line paid back by line since the
-- reopening offers S$0, and the guided Cancel lists it). The build before
-- let these through where those lines were listed first and refused them
-- otherwise (the line order); refused as before 479 in every order, every
-- key. A S$100 Credit Package, then 2 vouchers at S$30 and the sessions
-- added by a correction (Y1; Y2 the sessions first), paid (S$220),
-- cancelled, 1 session refunded by line, reopened (S$200 held), the guided
-- Refund in full requested (its plan: the package's S$100, the vouchers'
-- S$60, the sessions' S$40, not cut), S$10 paid, approved as it reads then
-- (S$210 held): refused, "Settle the reopened invoice ...", 3 waiting; the
-- guided Cancel (Y3, Y4). A voucher line, the sessions and a S$40 product
-- (written in three orders: V1, V2, V3), 1 session refunded by line while
-- cancelled, reopened, the product's S$40 refunded by line, the guided
-- Cancel requested, S$10 paid, approved: refused, S$110 held. The Refund in
-- full of that state leaves the product out (nothing left to refund), so
-- with one other line it reads the plan carried out exactly and goes
-- through as answer F asked (V4, V5: the S$100 paid back, S$10 kept; before
-- 479 refused). Requested and approved with nothing changed between, they go
-- through as answer F asked (Y1s, Y3s, V1s; before 479 refused).
('Y1', 'known', 'sale A cp; addlines v,th; pay; cancel; backt 3 20; reopen; request refund_full; payamt 10; approve',
  '{"status":"partially_paid","net":210,"held":100,"sess":"0/3 r1 c2 refunded","holds":{"A":"0.00"},"swait":1,"squeued":3,"stock":"-","sholder":"A","sinv":"","error~":"approve: Settle the reopened invoice before changing its queued sessions%"}', null, '1/1'),
('Y2', 'known', 'sale A cp; addlines th,v; pay; cancel; backt 3 20; reopen; request refund_full; payamt 10; approve',
  '{"status":"partially_paid","net":210,"held":100,"sess":"0/3 r1 c2 refunded","holds":{"A":"0.00"},"swait":1,"squeued":3,"stock":"-","sholder":"A","sinv":"","error~":"approve: Settle the reopened invoice before changing its queued sessions%"}', null, '1/1'),
('Y3', 'known', 'sale A cp; addlines v,th; pay; cancel; backt 3 20; reopen; request cancel; payamt 10; approve',
  '{"status":"partially_paid","net":210,"held":100,"sess":"0/3 r1 c2 refunded","holds":{"A":"0.00"},"swait":1,"squeued":3,"stock":"-","sholder":"A","sinv":"","error~":"approve: Settle the reopened invoice before changing its queued sessions%"}', null, '1/1'),
('Y4', 'known', 'sale A cp; addlines th,v; pay; cancel; backt 3 20; reopen; request cancel; payamt 10; approve',
  '{"status":"partially_paid","net":210,"held":100,"sess":"0/3 r1 c2 refunded","holds":{"A":"0.00"},"swait":1,"squeued":3,"stock":"-","sholder":"A","sinv":"","error~":"approve: Settle the reopened invoice before changing its queued sessions%"}', null, '1/1'),
('V1', 'known', 'sale A v,th,pr; cancel; backt 2 20; reopen; backps 3 40; request cancel; payamt 10; approve',
  '{"status":"partially_paid","net":110,"held":0,"sess":"0/3 r1 c2 refunded","holds":{"A":"0.00"},"swait":1,"squeued":3,"stock":"invoice_cancel_return 1, store_sale 1","sholder":"A","sinv":"","error~":"approve: Settle the reopened invoice before changing its queued sessions%"}', null, '1/1'),
('V2', 'known', 'sale A th,v,pr; cancel; backt 2 20; reopen; backps 3 40; request cancel; payamt 10; approve',
  '{"status":"partially_paid","net":110,"held":0,"sess":"0/3 r1 c2 refunded","holds":{"A":"0.00"},"swait":1,"squeued":3,"stock":"invoice_cancel_return 1, store_sale 1","sholder":"A","sinv":"","error~":"approve: Settle the reopened invoice before changing its queued sessions%"}', null, '1/1'),
('V3', 'known', 'sale A pr,th,v; cancel; backt 2 20; reopen; backps 3 40; request cancel; payamt 10; approve',
  '{"status":"partially_paid","net":110,"held":0,"sess":"0/3 r1 c2 refunded","holds":{"A":"0.00"},"swait":1,"squeued":3,"stock":"invoice_cancel_return 1, store_sale 1","sholder":"A","sinv":"","error~":"approve: Settle the reopened invoice before changing its queued sessions%"}', null, '1/1'),
('V4', 'fixed', 'sale A v,th,pr; cancel; backt 2 20; reopen; backps 3 40; request refund_full; payamt 10; approve',
  '{"status":"partially_paid","net":10,"held":0,"sess":"0/3 r3 c0 refunded","holds":{"A":"0.00"},"swait":1,"squeued":1,"stock":"invoice_cancel_return 1, store_sale 1","sholder":"A","sinv":"","error":null}',
  'approve: Settle the reopened invoice before changing its queued sessions%', '1/1'),
('V5', 'fixed', 'sale A th,v,pr; cancel; backt 2 20; reopen; backps 3 40; request refund_full; payamt 10; approve',
  '{"status":"partially_paid","net":10,"held":0,"sess":"0/3 r3 c0 refunded","holds":{"A":"0.00"},"swait":1,"squeued":1,"stock":"invoice_cancel_return 1, store_sale 1","sholder":"A","sinv":"","error":null}',
  'approve: Settle the reopened invoice before changing its queued sessions%', '1/1'),
('Y1s', 'fixed', 'sale A cp; addlines v,th; pay; cancel; backt 3 20; reopen; request refund_full; approve',
  '{"status":"partially_paid","net":0,"held":0,"sess":"0/3 r3 c0 refunded","holds":{"A":"0.00"},"swait":1,"squeued":1,"stock":"-","sholder":"A","sinv":"","error":null}',
  'approve: Settle the reopened invoice before changing its queued sessions%', '1/1'),
('Y3s', 'fixed', 'sale A cp; addlines v,th; pay; cancel; backt 3 20; reopen; request cancel; approve',
  '{"status":"cancelled","net":0,"held":0,"sess":"0/3 r3 c0 refunded","holds":{"A":"0.00"},"swait":1,"squeued":1,"stock":"-","sholder":"A","sinv":"","error":null}',
  'approve: Settle the reopened invoice before changing its queued sessions%', '1/1'),
('V1s', 'fixed', 'sale A v,th,pr; cancel; backt 2 20; reopen; backps 3 40; request cancel; approve',
  '{"status":"cancelled","net":0,"held":0,"sess":"0/3 r3 c0 refunded","holds":{"A":"0.00"},"swait":1,"squeued":1,"stock":"invoice_cancel_return 1, store_sale 1","sholder":"A","sinv":"","error":null}',
  'approve: Settle the reopened invoice before changing its queued sessions%', '1/1'),
-- The third fix review (3 Nov 2026; answer F, and the Owner's Q1 of 29 Oct
-- 2026: a case with no other item to choose between stays as built):
-- approved after the invoice changed, with two other lines listed at S$0 (a
-- credit or voucher line refunded by line before the reopening, which the
-- reopening charges again; a product line refunded by line since it, which
-- the guided Cancel keeps), only the sessions' line has anything to refund,
-- at their turn and in the plan the request saved: through, whichever line
-- is listed first, as answer F asked (the build before refused them, as it
-- read the saved plan, whose money held was no longer the money held). A
-- S$100 Credit Package, then 2 vouchers at S$30 and the sessions added by a
-- correction (Z8; the guided Cancel, Z8c), or the three sold together (Z5r;
-- the sessions written first, Z5x), paid, cancelled, the package's S$100,
-- the vouchers' S$60 and 1 session refunded by line, reopened (S$40 held),
-- the guided Refund in full requested (its plan: the package S$0, the
-- vouchers S$0, the sessions S$40), S$10 paid, approved: the S$40 paid back,
-- S$10 kept, 1 session waiting; Correct payment instead (Z6: S$5 paid before
-- the request, corrected to S$15 after it: S$15 kept); KG45's shape with the
-- two S$0 lines (KZ: S$5 paid before the request, S$5 after it). The
-- vouchers refunded by line while cancelled, the S$40 product refunded by
-- line since the reopening, the guided Cancel (Z1; the sessions written
-- first, Z2): cancelled, S$10 shown due, 1 waiting. With one S$0 line (Z9:
-- a package; Z0: the product, the guided Cancel) and with nothing changed
-- between (Z8s): through, as with the build before.
-- A credit line that gains credit between the request and the approval
-- (found checking it): the package's S$100 all spent on a session invoice
-- S1 before the cancel (so the plan the request saved gives the package
-- S$0), the vouchers' S$60 and 1 session refunded by line while cancelled,
-- reopened, the Refund in full requested, S1 cancelled and its refund
-- recorded (the S$100 back on the package), S$10 paid, approved: refused as
-- before 479 whichever line is listed first (ZG: the package written first;
-- ZGx: the sessions; with the package listed first nothing else offers
-- anything at the sessions' turn, and the check once every line is done
-- refuses the money the package was given; listed after them, the saved
-- plan refuses it at their turn); with nothing paid between (ZGs, ZGsx) the
-- saved plan is the one carried out by what can be compared, not cut: the
-- package's S$100 and the sessions' S$40 paid back, whichever line is
-- listed first.
('Z8', 'fixed', 'sale A cp; addlines v,th; pay; cancel; back 1 all; backv 2 2; backt 3 20; reopen; request refund_full; payamt 10; approve',
  '{"status":"partially_paid","net":10,"held":0,"sess":"0/3 r3 c0 refunded","holds":{"A":"0.00"},"swait":1,"squeued":1,"stock":"-","sholder":"A","sinv":"","error":null}',
  'approve: Settle the reopened invoice before changing its queued sessions%', '1/1'),
('Z8c', 'fixed', 'sale A cp; addlines v,th; pay; cancel; back 1 all; backv 2 2; backt 3 20; reopen; request cancel; payamt 10; approve',
  '{"status":"cancelled","net":10,"fdue":10,"held":0,"sess":"0/3 r3 c0 refunded","holds":{"A":"0.00"},"swait":1,"squeued":1,"stock":"-","sholder":"A","sinv":"","error":null}',
  'approve: Settle the reopened invoice before changing its queued sessions%', '1/1'),
('Z5r', 'fixed', 'sale A cp,v,th; cancel; back 1 all; backv 2 2; backt 3 20; reopen; request refund_full; payamt 10; approve',
  '{"status":"partially_paid","net":10,"held":0,"sess":"0/3 r3 c0 refunded","holds":{"A":"0.00"},"swait":1,"squeued":1,"stock":"-","sholder":"A","sinv":"","error":null}',
  'approve: Settle the reopened invoice before changing its queued sessions%', '1/1'),
('Z5x', 'fixed', 'sale A th,v,cp; cancel; back 1 all; backv 2 2; backt 3 20; reopen; request refund_full; payamt 10; approve',
  '{"status":"partially_paid","net":10,"held":0,"sess":"0/3 r3 c0 refunded","holds":{"A":"0.00"},"swait":1,"squeued":1,"stock":"-","sholder":"A","sinv":"","error":null}',
  'approve: Settle the reopened invoice before changing its queued sessions%', '1/1'),
('Z6', 'fixed', 'sale A cp; addlines v,th; pay; cancel; back 1 all; backv 2 2; backt 3 20; reopen; payamt 5; request refund_full; fixpay 15; approve',
  '{"status":"partially_paid","net":15,"held":0,"sess":"0/3 r3 c0 refunded","holds":{"A":"0.00"},"swait":1,"squeued":1,"stock":"-","sholder":"A","sinv":"","error":null}',
  'approve: Settle the reopened invoice before changing its queued sessions%', '1/1'),
('KZ', 'fixed', 'sale A cp,v,th; cancel; back 1 all; backv 2 2; backt 3 20; reopen; payamt 5; request refund_full; payamt 5; approve',
  '{"status":"partially_paid","net":10,"held":0,"sess":"0/3 r3 c0 refunded","holds":{"A":"0.00"},"swait":1,"squeued":1,"stock":"-","sholder":"A","sinv":"","error":null}',
  'approve: Settle the reopened invoice before changing its queued sessions%', '1/1'),
('Z1', 'fixed', 'sale A v,th,pr; cancel; backv 1 2; backt 2 20; reopen; backps 3 40; request cancel; payamt 10; approve',
  '{"status":"cancelled","net":10,"fdue":10,"held":0,"sess":"0/3 r3 c0 refunded","holds":{"A":"0.00"},"swait":1,"squeued":1,"stock":"invoice_cancel_return 1, store_sale 1","sholder":"A","sinv":"","error":null}',
  'approve: Settle the reopened invoice before changing its queued sessions%', '1/1'),
('Z2', 'fixed', 'sale A th,pr,v; cancel; backv 1 2; backt 2 20; reopen; backps 3 40; request cancel; payamt 10; approve',
  '{"status":"cancelled","net":10,"fdue":10,"held":0,"sess":"0/3 r3 c0 refunded","holds":{"A":"0.00"},"swait":1,"squeued":1,"stock":"invoice_cancel_return 1, store_sale 1","sholder":"A","sinv":"","error":null}',
  'approve: Settle the reopened invoice before changing its queued sessions%', '1/1'),
('Z9', 'fixed', 'sale A cp; addlines th; pay; cancel; back 1 all; backt 2 20; reopen; request refund_full; payamt 10; approve',
  '{"status":"partially_paid","net":10,"held":0,"sess":"0/3 r3 c0 refunded","holds":{"A":"0.00"},"swait":1,"squeued":1,"stock":"-","sholder":"A","sinv":"","error":null}',
  'approve: Settle the reopened invoice before changing its queued sessions%', '1/1'),
('Z0', 'fixed', 'sale A th,pr; cancel; backt 1 20; reopen; backps 2 40; request cancel; payamt 10; approve',
  '{"status":"cancelled","net":10,"fdue":10,"held":0,"sess":"0/3 r3 c0 refunded","holds":{"A":"0.00"},"swait":1,"squeued":1,"stock":"invoice_cancel_return 1, store_sale 1","sholder":"A","sinv":"","error":null}',
  'approve: Settle the reopened invoice before changing its queued sessions%', '1/1'),
('Z8s', 'fixed', 'sale A cp; addlines v,th; pay; cancel; back 1 all; backv 2 2; backt 3 20; reopen; request refund_full; approve',
  '{"status":"partially_paid","net":0,"held":0,"sess":"0/3 r3 c0 refunded","holds":{"A":"0.00"},"swait":1,"squeued":1,"stock":"-","sholder":"A","sinv":"","error":null}',
  'approve: Settle the reopened invoice before changing its queued sessions%', '1/1'),
('ZG', 'control', 'sale A cp; addlines v,th; pay; spend A 5; cancel; backv 2 2; backt 3 20; reopen; request refund_full; unspend S1; payamt 10; approve',
  '{"status":"partially_paid","net":150,"held":0,"sess":"0/3 r1 c2 refunded","holds":{"A":"100.00"},"swait":1,"squeued":3,"stock":"-","sholder":"A","sinv":"","error~":"approve: Settle the reopened invoice before changing its queued sessions%"}', null, '1/1'),
('ZGx', 'control', 'sale A th,v,cp; spend A 5; cancel; backv 2 2; backt 3 20; reopen; request refund_full; unspend S1; payamt 10; approve',
  '{"status":"partially_paid","net":150,"held":0,"sess":"0/3 r1 c2 refunded","holds":{"A":"100.00"},"swait":1,"squeued":3,"stock":"-","sholder":"A","sinv":"","error~":"approve: Settle the reopened invoice before changing its queued sessions%"}', null, '1/1'),
('ZGs', 'fixed', 'sale A cp; addlines v,th; pay; spend A 5; cancel; backv 2 2; backt 3 20; reopen; request refund_full; unspend S1; approve',
  '{"status":"partially_paid","net":0,"held":0,"sess":"0/3 r3 c0 refunded","holds":{"A":"0.00"},"swait":1,"squeued":1,"stock":"-","sholder":"A","sinv":"","error":null}',
  'approve: Settle the reopened invoice before changing its queued sessions%', '1/1'),
('ZGsx', 'fixed', 'sale A th,v,cp; spend A 5; cancel; backv 2 2; backt 3 20; reopen; request refund_full; unspend S1; approve',
  '{"status":"partially_paid","net":0,"held":0,"sess":"0/3 r3 c0 refunded","holds":{"A":"0.00"},"swait":1,"squeued":1,"stock":"-","sholder":"A","sinv":"","error":null}',
  'approve: Settle the reopened invoice before changing its queued sessions%', '1/1'),
-- The review of 2 Nov 2026 (NOT COVERED 16): credit given back to a package
-- between the request and the approval. A S$100 Credit Package sold and
-- paid, the sessions and a S$40 product added by a correction and paid (so
-- the package, written first, is listed first: the package, the sessions,
-- the product), a S$20 session paid from the package's credit (S1),
-- cancelled, the product's S$40 refunded by line, reopened, S$20 paid (S$180
-- held), the guided Refund in full requested (its plan: the package's S$80,
-- the sessions' S$60, the product's S$40, not cut), S1 cancelled and its
-- refund recorded (the S$20 of credit back, held for the package), then an
-- Owner approving the plan as it reads then (the package's S$100: cut, the
-- product given S$20): refused exactly as before 479, every key (A1; the
-- guided Cancel with "Record refund paid", AG). The same refused before 479
-- and after it: the product added before the sessions (A1p: the sessions'
-- line cut), the request raised after the credit came back (AN: its saved
-- plan cut), the three lines sold together (A1x: the package listed last).
-- (From this build each is refused at the session's turn, the product's
-- line, refunded by line before the reopening, being offered again: below.)
('A1', 'control', 'sale A cp; addlines th,pr; pay; spend A; cancel; backps 3 40; reopen; payamt 20; request refund_full; unspend S1; approve',
  '{"status":"partially_paid","net":180,"held":100,"sess":"0/3 r0 c3 cancelled","holds":{"A":"0.00"},"swait":1,"squeued":3,"stock":"invoice_cancel_return 1, store_sale 1","sholder":"A","sinv":"","error~":"approve: Settle the reopened invoice before changing its queued sessions%"}', null, '1/1'),
('AG', 'control', 'sale A cp; addlines th,pr; pay; spend A; cancel; backps 3 40; reopen; payamt 20; request cancel; unspend S1; approve',
  '{"status":"partially_paid","net":180,"held":100,"sess":"0/3 r0 c3 cancelled","holds":{"A":"0.00"},"swait":1,"squeued":3,"stock":"invoice_cancel_return 1, store_sale 1","sholder":"A","sinv":"","error~":"approve: Settle the reopened invoice before changing its queued sessions%"}', null, '1/1'),
('A1p', 'control', 'sale A cp; addlines pr,th; pay; spend A; cancel; backps 3 40; reopen; payamt 20; request refund_full; unspend S1; approve',
  '{"status":"partially_paid","net":180,"held":100,"sess":"0/3 r0 c3 cancelled","holds":{"A":"0.00"},"swait":1,"squeued":3,"stock":"invoice_cancel_return 1, store_sale 1","sholder":"A","sinv":"","error~":"approve: Settle the reopened invoice before changing its queued sessions%"}', null, '1/1'),
('AN', 'control', 'sale A cp; addlines th,pr; pay; spend A; cancel; backps 3 40; reopen; payamt 20; unspend S1; request refund_full; approve',
  '{"status":"partially_paid","net":180,"held":100,"sess":"0/3 r0 c3 cancelled","holds":{"A":"0.00"},"swait":1,"squeued":3,"stock":"invoice_cancel_return 1, store_sale 1","sholder":"A","sinv":"","error~":"approve: Settle the reopened invoice before changing its queued sessions%"}', null, '1/1'),
('A1x', 'control', 'sale A th,pr,cp; spend A; cancel; backps 3 40; reopen; payamt 20; request refund_full; unspend S1; approve',
  '{"status":"partially_paid","net":180,"held":100,"sess":"0/3 r0 c3 cancelled","holds":{"A":"0.00"},"swait":1,"squeued":3,"stock":"invoice_cancel_return 1, store_sale 1","sholder":"A","sinv":"","error~":"approve: Settle the reopened invoice before changing its queued sessions%"}', null, '1/1'),
-- The fix review of 2 Nov 2026 (479's NOT COVERED 17, open for the Owner): a
-- line holding no credit, vouchers or sessions (the product) that a refund by
-- line paid back before the reopening is offered again by the guided plan
-- (its line amount counts only refunds since the reopening); where the plan
-- reaches a waiting session it is refused exactly as before 479, every key,
-- whichever line is listed first (the previous build approved these and
-- refunded the product's S$40 line a second time with the waiting sessions:
-- AC, AGC). AC: the package, then the sessions and the product added by a
-- correction, S$20 of the credit spent (S1), cancelled, the product's S$40
-- refunded by line, reopened, S$20 paid (S$180 held), the guided Refund in
-- full requested and approved (its plan: the package's S$80, the sessions'
-- S$60, the product's S$40: not cut); AGC the guided Cancel; ACp AC then
-- paid; AXV, AVX with 2 vouchers added after or before the product and the
-- spent credit given back between the request and the approval (the
-- previous build refused AXV, with the lines listed as written, with the
-- vouchers' own message: the review's AXV); TPr, PTr only the sessions (1
-- refunded by line while cancelled) and the product, S$40 paid again, the
-- plan not cut (the product written last or first).
('AC', 'control', 'sale A cp; addlines th,pr; pay; spend A; cancel; backps 3 40; reopen; payamt 20; request refund_full; approve',
  '{"status":"partially_paid","net":180,"held":80,"sess":"0/3 r0 c3 cancelled","holds":{"A":"0.00"},"swait":1,"squeued":3,"stock":"invoice_cancel_return 1, store_sale 1","sholder":"A","sinv":"","error~":"approve: Settle the reopened invoice before changing its queued sessions%"}', null, '1/1'),
('AGC', 'control', 'sale A cp; addlines th,pr; pay; spend A; cancel; backps 3 40; reopen; payamt 20; request cancel; approve',
  '{"status":"partially_paid","net":180,"held":80,"sess":"0/3 r0 c3 cancelled","holds":{"A":"0.00"},"swait":1,"squeued":3,"stock":"invoice_cancel_return 1, store_sale 1","sholder":"A","sinv":"","error~":"approve: Settle the reopened invoice before changing its queued sessions%"}', null, '1/1'),
('ACp', 'control', 'sale A cp; addlines th,pr; pay; spend A; cancel; backps 3 40; reopen; payamt 20; request refund_full; approve; pay',
  '{"status":"partially_paid","net":180,"held":80,"sess":"0/3 r0 c3 cancelled","holds":{"A":"0.00"},"swait":1,"squeued":3,"stock":"invoice_cancel_return 1, store_sale 1","sholder":"A","sinv":"","error~":"approve: Settle the reopened invoice before changing its queued sessions%"}', null, '1/1'),
('AXV', 'control', 'sale A cp; addlines th,pr,v; pay; spend A; cancel; backps 4 40; reopen; payamt 20; request refund_full; unspend S1; approve',
  '{"status":"partially_paid","net":240,"held":100,"sess":"0/3 r0 c3 cancelled","holds":{"A":"0.00"},"swait":1,"squeued":3,"stock":"invoice_cancel_return 1, store_sale 1","sholder":"A","sinv":"","error~":"approve: Settle the reopened invoice before changing its queued sessions%"}', null, '1/1'),
('AVX', 'control', 'sale A cp; addlines th,v,pr; pay; spend A; cancel; backps 4 40; reopen; payamt 20; request refund_full; unspend S1; approve',
  '{"status":"partially_paid","net":240,"held":100,"sess":"0/3 r0 c3 cancelled","holds":{"A":"0.00"},"swait":1,"squeued":3,"stock":"invoice_cancel_return 1, store_sale 1","sholder":"A","sinv":"","error~":"approve: Settle the reopened invoice before changing its queued sessions%"}', null, '1/1'),
('TPr', 'control', 'sale A th,pr; cancel; backt 1 20; backps 2 40; reopen; payamt 40; refundall; pay',
  '{"status":"partially_paid","net":80,"sess":"0/3 r1 c2 refunded","holds":{"A":"0.00"},"swait":1,"squeued":3,"stock":"invoice_cancel_return 1, store_sale 1","sholder":"A","sinv":"","error~":"refundall: Settle the reopened invoice before changing its queued sessions%"}', null, '1/1'),
('PTr', 'control', 'sale A pr,th; cancel; backt 1 20; backps 2 40; reopen; payamt 40; refundall; pay',
  '{"status":"partially_paid","net":80,"sess":"0/3 r1 c2 refunded","holds":{"A":"0.00"},"swait":1,"squeued":3,"stock":"invoice_cancel_return 1, store_sale 1","sholder":"A","sinv":"","error~":"refundall: Settle the reopened invoice before changing its queued sessions%"}', null, '1/1'),
-- The A family with the plan not cut and no product offered again (answer
-- F, as asked: before 479 refused): a session refunded by line while
-- cancelled instead of the product. ACt: the guided Refund in full pays back
-- the package's S$80, the sessions' S$40 and the product's S$40 (S$160 of
-- the S$180 held); the S$20 stays held for S1 and 1 session waits for the
-- S$20 still to pay; AGCt: the guided Cancel, the same S$160 back, the S$20
-- kept for S1.
('ACt', 'fixed', 'sale A cp; addlines th,pr; pay; spend A; cancel; backt 2 20; reopen; request refund_full; approve',
  '{"status":"partially_paid","net":20,"held":0,"sess":"0/3 r3 c0 refunded","holds":{"A":"0.00"},"swait":1,"squeued":1,"stock":"invoice_cancel_return 1, store_sale 1","sholder":"A","sinv":"","error":null}',
  'approve: Settle the reopened invoice before changing its queued sessions%', '1/1'),
('AGCt', 'fixed', 'sale A cp; addlines th,pr; pay; spend A; cancel; backt 2 20; reopen; request cancel; approve',
  '{"status":"cancelled","net":20,"held":0,"sess":"0/3 r3 c0 refunded","holds":{"A":"0.00"},"swait":1,"squeued":1,"stock":"invoice_cancel_return 1, store_sale 1","sholder":"A","sinv":"","error":null}',
  'approve: Settle the reopened invoice before changing its queued sessions%', '1/1'),
-- Answer F with two other lines, one holding vouchers or credit, the plan
-- not cut, whichever line is listed first (the first final check of 2 Nov
-- 2026; before 479 refused): an Owner's discount (VTPd: vouchers and a
-- product; CTPd: a package and a product), a package and a product (CTP; the
-- guided Cancel, CTPc), the Premium Bundle and a product (BTP), a credit
-- line written first, then the rest added by a correction (CFR: a package;
-- BFC: the bundle, the guided Cancel; BFR2: the bundle and the sessions
-- alone). Paid afterwards: 1 of 3; without 481 the settling payment takes
-- the product from stock again though the guided flow refunded its line
-- (NOT COVERED 1; 481 below).
('VTPd', 'fixed', 'saled A v,th,pr 30; cancel; backt 2 16.25; reopen; refundall; pay',
  '{"status":"paid","net":16.25,"sess":"1/3 r2 c0 available","holds":{"A":"0.00"},"swait":0,"squeued":0,"stock":"invoice_cancel_return 1, store_sale 2","sholder":"A","sinv":"","error":null}',
  'refundall: Settle the reopened invoice before changing its queued sessions%', '1/1'),
('CTPd', 'fixed', 'saled A cp,th,pr 20; cancel; backt 2 18; reopen; refundall; pay',
  '{"status":"paid","net":18,"held":0,"sess":"1/3 r2 c0 available","holds":{"A":"0.00"},"swait":0,"squeued":0,"stock":"invoice_cancel_return 1, store_sale 2","sholder":"A","sinv":"","error":null}',
  'refundall: Settle the reopened invoice before changing its queued sessions%', '1/1'),
('CTP', 'fixed', 'sale A cp,th,pr; cancel; backt 2 20; reopen; refundall; pay',
  '{"status":"paid","net":20,"held":0,"sess":"1/3 r2 c0 available","holds":{"A":"0.00"},"swait":0,"squeued":0,"stock":"invoice_cancel_return 1, store_sale 2","sholder":"A","sinv":"","error":null}',
  'refundall: Settle the reopened invoice before changing its queued sessions%', '1/1'),
('CTPc', 'fixed', 'sale A cp,th,pr; cancel; backt 2 20; reopen; guidedcancel',
  '{"status":"cancelled","net":0,"held":0,"sess":"0/3 r3 c0 refunded","holds":{"A":"0.00"},"swait":1,"squeued":1,"stock":"invoice_cancel_return 1, store_sale 1","sholder":"A","sinv":"","error":null}',
  'guidedcancel: Settle the reopened invoice before changing its queued sessions%', '1/1'),
('BTP', 'fixed', 'sale A pbv,th,pr; cancel; backt 2 20; reopen; refundall; pay',
  '{"status":"paid","net":20,"held":0,"sess":"1/3 r2 c0 available","holds":{"A":"0.00"},"swait":0,"squeued":0,"stock":"invoice_cancel_return 1, store_sale 2","sholder":"A","sinv":"","error":null}',
  'refundall: Settle the reopened invoice before changing its queued sessions%', '1/1'),
('CFR', 'fixed', 'sale A cp; addlines th,pr; pay; cancel; backt 2 20; reopen; refundall; pay',
  '{"status":"paid","net":20,"held":0,"sess":"1/3 r2 c0 available","holds":{"A":"0.00"},"swait":0,"squeued":0,"stock":"invoice_cancel_return 1, store_sale 2","sholder":"A","sinv":"","error":null}',
  'refundall: Settle the reopened invoice before changing its queued sessions%', '1/1'),
('BFC', 'fixed', 'sale A pbv; addlines th,pr; pay; cancel; backt 2 20; reopen; guidedcancel',
  '{"status":"cancelled","net":0,"held":0,"sess":"0/3 r3 c0 refunded","holds":{"A":"0.00"},"swait":1,"squeued":1,"stock":"invoice_cancel_return 1, store_sale 1","sholder":"A","sinv":"","error":null}',
  'guidedcancel: Settle the reopened invoice before changing its queued sessions%', '1/1'),
('BFR2', 'fixed', 'sale A pbv; addlines th; pay; cancel; backt 2 20; reopen; refundall; pay',
  '{"status":"paid","net":20,"held":0,"sess":"1/3 r2 c0 available","holds":{"A":"0.00"},"swait":0,"squeued":0,"stock":"-","sholder":"A","sinv":"","error":null}',
  'refundall: Settle the reopened invoice before changing its queued sessions%', '1/1'),
-- Known (479's NOT COVERED 17; not 479's, the same before it: the check of
-- 30 Oct 2026): a S$40 product refunded by line while cancelled is offered
-- again by the guided Refund in full once the invoice is reopened (its line
-- is charged again; the refund options count the line's refunds since the
-- reopening): the sessions all refunded by line while cancelled, S$40 paid,
-- the plan gives the product S$40 and the sessions S$0 (either line first;
-- 479's refund is not reached): the product's line refunded a second time
-- (S$80 on the S$40 line), then paid S$60: 3 of 3 and the product taken from
-- stock again (P3). With no sessions at all (AC's steps without them, the
-- same before 479 and after it): the guided Refund in full pays back all the
-- S$160 paid (the package's S$80, the product's S$40 a second time) though
-- S1, a S$20 session paid from the package's credit, stays available, and
-- leaves the invoice part-paid with S$20 outstanding (ACnC); the guided
-- Cancel the same, cancelled, nothing outstanding: S1 kept for S$0 (AGCnC).
('P3', 'known', 'sale A pr,th; cancel; backps 2 40; backt 1 60; reopen; payamt 40; refundall; pay',
  '{"status":"paid","net":60,"sess":"3/3 r0 c0 available","swait":0,"sev":1,"stock":"invoice_cancel_return 1, store_sale 2","sholder":"A","sinv":"","error":null}', null, null),
('ACnC', 'known', 'sale A cp; addlines pr; pay; spend A; cancel; backps 2 40; reopen; payamt 20; request refund_full; approve',
  '{"status":"partially_paid","net":0,"held":0,"sess":"-","holds":{"A":"0.00"},"swait":0,"squeued":0,"stock":"invoice_cancel_return 1, store_sale 1","sinv":"","error":null}', null, null),
('AGCnC', 'known', 'sale A cp; addlines pr; pay; spend A; cancel; backps 2 40; reopen; payamt 20; request cancel; approve',
  '{"status":"cancelled","net":0,"held":0,"sess":"-","holds":{"A":"0.00"},"swait":0,"squeued":0,"stock":"invoice_cancel_return 1, store_sale 1","sinv":"","error":null}', null, null),
-- Known (NOT COVERED 17): the product refunded by line before an earlier
-- reopening, the invoice paid in full since (its line charged and paid
-- again), cancelled, a session refunded by line, reopened again: the guided
-- Refund in full (the sessions' S$40, the product's S$40: the S$80 held, so
-- nothing refunded twice) is refused as before 479, as the rule counts
-- every refund by line before the last reopening (TP2c).
('TP2c', 'known', 'sale A th,pr; cancel; backps 2 40; reopen; pay; cancel; backt 1 20; reopen; refundall; pay',
  '{"status":"partially_paid","net":80,"sess":"0/3 r1 c2 refunded","holds":{"A":"0.00"},"swait":1,"squeued":3,"stock":"invoice_cancel_return 2, store_sale 2","sholder":"A","sinv":"","error~":"refundall: Settle the reopened invoice before changing its queued sessions%"}', null, '1/1');
-- The plans cut to the money held line by line, in the order the refund
-- options list the lines (as the table returns them: not fixed; on the
-- copies mostly the order the invoice form sent them, so each shape is run
-- with its lines written both ways). Each ends as expected for the line its
-- plan lists first ('*': whichever), before 479 (R) and after it (K10), and
-- where both runs listed the same lines in the same order, after 479 exactly
-- as before it, every key (479's NOT COVERED 10: the Owner, 29 Oct 2026
-- ~18:45 SGT, "Keep today's refusal": where the cut gives a waiting session
-- some of the money and another line has something to refund, refused as
-- before 479; where it gives the sessions nothing, as before 479).
-- 3 sessions and 2 vouchers at S$30, cancelled, all S$120 paid back with no
-- line, reopened, S$60 paid, the guided Refund in full, then paid (TVn60), or
-- the guided Cancel (TVn60c); S$20 paid (TVn20); a S$40 product and 3
-- sessions, cancelled, the product's S$40 refunded by line, reopened, the
-- guided Refund in full (PRxr), then paid (PRx); the S$40 paid back with no
-- line instead (PRnl); the guided Cancel (PRxc); the vouchers, the sessions
-- and the product, all S$160 paid back with no line, reopened, S$130 paid
-- (VTPc: refused whichever line is first, 252's message by where the cut
-- lands). Not 479's (NOT COVERED 17, the same before 479 in either order):
-- the product refunded by line while cancelled, with a voucher line, S$10
-- paid, the guided Refund in full, then paid (P1); the S$40 paid back with
-- no line instead (P5); with the sessions, 1 refunded by line while
-- cancelled, nothing paid, then paid (P4: the product first, its line
-- refunded again and the sessions given nothing, as before 479; the therapy
-- line first, refused).
create temp table t479_ocases(k text primary key, shape text not null, steps text not null, ord serial);
insert into t479_ocases(k, shape, steps) values
  ('TVn60a', 'TVn60', 'sale A th,v; cancel; refundpaid; reopen; payamt 60; refundall; pay'),
  ('TVn60b', 'TVn60', 'sale A v,th; cancel; refundpaid; reopen; payamt 60; refundall; pay'),
  ('TVn60ca', 'TVn60c', 'sale A th,v; cancel; refundpaid; reopen; payamt 60; guidedcancel'),
  ('TVn60cb', 'TVn60c', 'sale A v,th; cancel; refundpaid; reopen; payamt 60; guidedcancel'),
  ('TVn20a', 'TVn20', 'sale A th,v; cancel; refundpaid; reopen; payamt 20; refundall; pay'),
  ('TVn20b', 'TVn20', 'sale A v,th; cancel; refundpaid; reopen; payamt 20; refundall; pay'),
  ('PRxr1', 'PRxr', 'sale A pr,th; cancel; backps 2 40; reopen; refundall'),
  ('PRxr2', 'PRxr', 'sale A th,pr; cancel; backps 2 40; reopen; refundall'),
  ('PRx1', 'PRx', 'sale A pr,th; cancel; backps 2 40; reopen; refundall; pay'),
  ('PRx2', 'PRx', 'sale A th,pr; cancel; backps 2 40; reopen; refundall; pay'),
  ('PRnl1', 'PRnl', 'sale A pr,th; cancel; paidback 40; reopen; refundall; pay'),
  ('PRnl2', 'PRnl', 'sale A th,pr; cancel; paidback 40; reopen; refundall; pay'),
  ('PRxc1', 'PRxc', 'sale A pr,th; cancel; backps 2 40; reopen; guidedcancel'),
  ('PRxc2', 'PRxc', 'sale A th,pr; cancel; backps 2 40; reopen; guidedcancel'),
  ('VTPc', 'VTPc', 'sale A v,th,pr; cancel; refundpaid; reopen; payamt 130; refundall'),
  ('VTPc2', 'VTPc', 'sale A th,pr,v; cancel; refundpaid; reopen; payamt 130; refundall'),
  ('P1a', 'P1', 'sale A pr,v; cancel; backps 2 40; reopen; payamt 10; refundall; pay'),
  ('P1b', 'P1', 'sale A v,pr; cancel; backps 2 40; reopen; payamt 10; refundall; pay'),
  ('P5a', 'P5', 'sale A pr,v; cancel; paidback 40; reopen; payamt 10; refundall; pay'),
  ('P5b', 'P5', 'sale A v,pr; cancel; paidback 40; reopen; payamt 10; refundall; pay'),
  ('P4a', 'P4', 'sale A pr,th; cancel; backps 2 40; backt 1 20; reopen; refundall; pay'),
  ('P4b', 'P4', 'sale A th,pr; cancel; backps 2 40; backt 1 20; reopen; refundall; pay');
create temp table t479_oexp(shape text, first text, expect jsonb not null, primary key (shape, first));
insert into t479_oexp values
  -- the therapy line first: refused, as before 479 (the plan gives the
  -- waiting sessions the S$60 held, the vouchers have S$60 to refund); the
  -- voucher line first: the vouchers refunded, the payment gives the 3
  -- sessions, as before 479
  ('TVn60', 'therapy',
    '{"status":"partially_paid","net":60,"sess":"0/3 r0 c3 cancelled","holds":{"A":"0.00"},"swait":1,"squeued":3,"sinv":"","error~":"refundall: Settle the reopened invoice before changing its queued sessions%"}'),
  ('TVn60', 'voucher',
    '{"status":"paid","net":60,"sess":"3/3 r0 c0 available","holds":{"A":"0.00"},"swait":0,"sev":1,"sinv":"","error":null}'),
  ('TVn60c', 'therapy',
    '{"status":"partially_paid","net":60,"sess":"0/3 r0 c3 cancelled","holds":{"A":"0.00"},"swait":1,"squeued":3,"sinv":"","error~":"guidedcancel: Settle the reopened invoice before changing its queued sessions%"}'),
  ('TVn60c', 'voucher',
    '{"status":"cancelled","net":0,"fdue":0,"sess":"0/3 r0 c3 cancelled","holds":{"A":"0.00"},"swait":1,"squeued":3,"sinv":"","error":null}'),
  -- S$20 paid: the therapy line first, refused (1 session of the S$20, the
  -- vouchers to refund too); the voucher line first, refused by the
  -- vouchers' rule; both as before 479
  ('TVn20', 'therapy',
    '{"status":"partially_paid","net":20,"sess":"0/3 r0 c3 cancelled","swait":1,"squeued":3,"sinv":"","error~":"refundall: Settle the reopened invoice before changing its queued sessions%"}'),
  ('TVn20', 'voucher',
    '{"status":"partially_paid","net":20,"sess":"0/3 r0 c3 cancelled","swait":1,"squeued":3,"sinv":"","error~":"refundall: Voucher refund must cover whole unused units at their allocated paid value%"}'),
  -- the product first (S$40, then S$20 for 1 session) or the sessions first
  -- (S$60): refused, as before 479, nothing refunded again
  ('PRxr', 'product',
    '{"status":"partially_paid","net":60,"sess":"0/3 r0 c3 cancelled","swait":1,"squeued":3,"stock":"invoice_cancel_return 1, store_sale 1","sinv":"","error~":"refundall: Settle the reopened invoice before changing its queued sessions%"}'),
  ('PRxr', 'therapy',
    '{"status":"partially_paid","net":60,"sess":"0/3 r0 c3 cancelled","swait":1,"squeued":3,"stock":"invoice_cancel_return 1, store_sale 1","sinv":"","error~":"refundall: Settle the reopened invoice before changing its queued sessions%"}'),
  ('PRx', 'product',
    '{"status":"partially_paid","net":60,"sess":"0/3 r0 c3 cancelled","swait":1,"squeued":3,"stock":"invoice_cancel_return 1, store_sale 1","sinv":"","error~":"refundall: Settle the reopened invoice before changing its queued sessions%"}'),
  ('PRx', 'therapy',
    '{"status":"partially_paid","net":60,"sess":"0/3 r0 c3 cancelled","swait":1,"squeued":3,"stock":"invoice_cancel_return 1, store_sale 1","sinv":"","error~":"refundall: Settle the reopened invoice before changing its queued sessions%"}'),
  ('PRnl', 'product',
    '{"status":"partially_paid","net":60,"sess":"0/3 r0 c3 cancelled","swait":1,"squeued":3,"stock":"invoice_cancel_return 1, store_sale 1","sinv":"","error~":"refundall: Settle the reopened invoice before changing its queued sessions%"}'),
  ('PRnl', 'therapy',
    '{"status":"partially_paid","net":60,"sess":"0/3 r0 c3 cancelled","swait":1,"squeued":3,"stock":"invoice_cancel_return 1, store_sale 1","sinv":"","error~":"refundall: Settle the reopened invoice before changing its queued sessions%"}'),
  ('PRxc', 'product',
    '{"status":"partially_paid","net":60,"sess":"0/3 r0 c3 cancelled","swait":1,"squeued":3,"stock":"invoice_cancel_return 1, store_sale 1","sinv":"","error~":"guidedcancel: Settle the reopened invoice before changing its queued sessions%"}'),
  ('PRxc', 'therapy',
    '{"status":"partially_paid","net":60,"sess":"0/3 r0 c3 cancelled","swait":1,"squeued":3,"stock":"invoice_cancel_return 1, store_sale 1","sinv":"","error~":"guidedcancel: Settle the reopened invoice before changing its queued sessions%"}'),
  -- three lines, S$130 of S$160 held: refused whichever line is first (252's
  -- message by where the cut lands), as before 479
  ('VTPc', '*',
    '{"status":"partially_paid","net":130,"sess":"0/3 r0 c3 cancelled","swait":1,"squeued":3,"stock":"invoice_cancel_return 1, store_sale 1","sinv":"","error~":"refundall: %"}'),
  -- not 479's (NOT COVERED 17): the product first, its line refunded again
  -- (S$40) and 1 voucher, then paid S$30: the other voucher and the product
  -- taken from stock again; the voucher line first, the 2 vouchers and S$10
  -- of the product, then paid S$30: the product; the same before 479
  ('P1', 'product',
    '{"status":"paid","net":30,"holds":{"A":"0.00/1"},"stock":"invoice_cancel_return 1, store_sale 2","sinv":"","error":null}'),
  ('P1', 'voucher',
    '{"status":"paid","net":30,"holds":{"A":"0.00"},"stock":"invoice_cancel_return 1, store_sale 2","sinv":"","error":null}'),
  ('P5', 'product',
    '{"status":"paid","net":30,"holds":{"A":"0.00/1"},"stock":"invoice_cancel_return 1, store_sale 2","sinv":"","error":null}'),
  ('P5', 'voucher',
    '{"status":"paid","net":30,"holds":{"A":"0.00"},"stock":"invoice_cancel_return 1, store_sale 2","sinv":"","error":null}'),
  -- the product first: its line refunded again (S$40), the sessions given
  -- nothing (479's refund not reached), then paid S$60: 3 of 3 and the
  -- product taken from stock again; the therapy line first: refused; the
  -- same before 479
  ('P4', 'product',
    '{"status":"paid","net":60,"sess":"3/3 r0 c0 available","swait":0,"sev":1,"stock":"invoice_cancel_return 1, store_sale 2","sinv":"","error":null}'),
  ('P4', 'therapy',
    '{"status":"partially_paid","net":40,"sess":"0/3 r1 c2 refunded","swait":1,"squeued":3,"stock":"invoice_cancel_return 1, store_sale 1","sinv":"","error~":"refundall: Settle the reopened invoice before changing its queued sessions%"}');
-- 481 (the Owner, 29 Oct 2026 ~18:45 SGT, Q2, "Fix it separately"), where it
-- is in after 479 (-v nomig=1 on a copy with both): the payment that
-- settles an invoice no longer takes from stock a product line refunded by
-- line since the last reopening (or since the sale), so these cases end
-- with the product's first sale and the Cancel's return alone (PRpp: no
-- sale); NOT COVERED 1's product stock and 17's stock side, as 481 fixes
-- them (and answer F's VTPd, CTPd, CTP, BTP, CFR: the product's line
-- refunded by the guided flow, then the invoice paid). Where the vouchers
-- are listed first (P1, P5: S$10 of the product refunded) the product is
-- still taken, as 481 counts whole units.
create function pg_temp.t479_481_in() returns boolean language sql as $f$
  select to_regprocedure('public.invoice_refunded_stock(uuid)') is not null $f$;
update t479_cases set expect = jsonb_set(expect, '{stock}',
                                         to_jsonb(case when k = 'PRpp' then '-' else 'invoice_cancel_return 1, store_sale 1' end))
 where pg_temp.t479_481_in() and k in ('PRn1', 'PRn2', 'VPR', 'PRxk', 'PRpp', 'P3', 'VTPd', 'CTPd', 'CTP', 'BTP', 'CFR');
update t479_oexp set expect = jsonb_set(expect, '{stock}', '"invoice_cancel_return 1, store_sale 1"')
 where pg_temp.t479_481_in() and first = 'product' and shape in ('P1', 'P5', 'P4');
-- The line an outcome's plan lists first (its kind).
create function pg_temp.t479_first(p_out jsonb) returns text language sql as $f$
  select nullif(split_part(split_part(coalesce(p_out->>'plan', ''), ' ', 1), ':', 1), '') $f$;

-- States for the header's query (Q), made before 479 (R): what it lists for
-- each, by reason, with its count (null: not listed).
create temp table t479_qstates(k text primary key, steps text not null, listed text);
insert into t479_qstates values
  ('Q1', 'sale A th; cancel; backt 1 20; reopen', '1/1'),
  ('Q1c', 'sale A th; cancel; backt 1 20; reopen; cancel', '1/1'),
  ('Q1r', 'sale A th; refundall; reopen', '1/1'),
  ('Q1v', 'sale A th,v; cancel; backv 1 1; backt 2 20; reopen; cancel', '1/1'),
  ('Q2s', 'sale A th; cancel; backt 1 20; reopen; cancel; shrink', '2/1'),
  ('Q2d', 'sale A th; cancel; backt 1 20; reopen; cancel; dup', '2/1'),
  ('Q3', 'sale A th; hold B', '3/1'),
  ('Q3c', 'sale A th; cancel; backt 1 20; reopen; hold B', '1/1,3/1'),
  ('Q0', 'sale A th; cancel; backt 1 20', null),
  ('Q0b', 'sale A th; cancel; backt 1 20; reopen; pay', null);
-- A case's steps up to step n.
create function pg_temp.t479_upto(p_steps text, p_n int) returns text language sql as $f$
  select array_to_string((string_to_array(p_steps, ';'))[1:p_n], ';') $f$;
-- The work-back of each of the three (P1): its text with each of 479's parts
-- replaced by what was there before (in this order), as the database prints
-- them. Each new part appears once.
create temp table t479_wb(sig text, n int, new text, old text, primary key (sig, n));
insert into t479_wb values ('refund_invoice_therapy_sessions(uuid,numeric,text,uuid)', 1,
$w$ if s.paid_value_snapshot is null or s.paid_value_snapshot<=0 then raise exception 'Original paid session value requires review before a refund'; end if;
 -- 479 (the Owner, 27 Oct 2026, answer F: "allow refund by line / guided
 -- Cancel with refund recorded / Refund in full ... while reopened therapy
 -- sessions wait (sessions come off the queue)"): a session whose invoice's
 -- reopening waits for its payment (invoice_reopen_sessions, not applied),
 -- or which was cancelled again before it was paid, is refunded by line
 -- here; before, refused ("Settle the reopened invoice before changing its
 -- queued sessions", 252, below). The guided Cancel and Refund in full call
 -- it for what the refund options offer, which still count the sessions
 -- refunded before the reopening as refunded (the Owner, 29 Oct 2026:
 -- "keep today's result", those are not offered again); a refund by line may
 -- take them. Its waiting rows are locked first, then read. With nothing
 -- waiting, as before 479 (below, word for word).
 perform 1 from public.invoice_reopen_sessions where session_id=s.id and applied_at is null order by id for update;
 select coalesce(sum(quantity),0)::int into v479_wait from public.invoice_reopen_sessions where session_id=s.id and applied_at is null;
 -- 479 (the Owner, 29 Oct 2026 ~18:45 SGT, "Keep today's refusal"): in the
 -- guided Refund in full, Cancel with "Record refund paid" or part refund
 -- (resolve_invoice_action_v2 carrying out the approval of request
 -- p_request_id: it names it in invoice.therapy_reviewed), where the plan
 -- was cut to the money held (invoice_action_plan's cap, line by line in an
 -- order that is not fixed) and another of its lines had something to
 -- refund, the waiting session is refused exactly as before 479 (252's
 -- checks, below), so that what the guided flow does never follows the
 -- line order where 478 refused; staff refund item by item. Where only the
 -- session's line had something to refund, or the plan was not cut, it goes
 -- on below, as answer F asked. The plan is read as it stands now: the
 -- refund has paid nothing back yet (its money is recorded once every line
 -- is done, so the money held is the plan's), and has not touched this
 -- session's line or any line it reaches after it; a line it reached before
 -- this one gave all it offered (the cut, if any, came after it, as this
 -- line is given something) and, where it holds credit, vouchers or
 -- sessions, shows less now. So: this line given less than it offers is the
 -- cut, and another line had something where money was left for the lines
 -- before it or another line still offers something; this line given all it
 -- offers, a cut is on a line after it, which still offers what it offered:
 -- with what this line and the others offer more than the money held, a
 -- cut; otherwise no cut where at most one other line is listed or none
 -- holds credit, vouchers or sessions (nothing hidden); else (a line before
 -- this one may have offered more than it shows now; so too where no other
 -- line offers anything now, as one holding credit, vouchers or sessions
 -- that the refund reached first shows nothing: which lines come first
 -- follows the order the lines are listed in, which is not fixed, so this
 -- test does not read that alone; the second fix review, 3 Nov 2026) the
 -- plan the request saved is read. Where it is the one being carried out by
 -- what can be compared (the money held, the lines, this line's amount and
 -- offer, what a line holding no credit, vouchers or sessions offers) and
 -- says not cut, the refund goes on. Where every other line offered nothing
 -- in it (by item, not by line order) and none offers anything now, only
 -- this line has anything to refund (no other item to choose between:
 -- answer F, kept by the Owner's Q1 of 29 Oct 2026, whichever line is
 -- listed first; the third fix review, 3 Nov 2026), so it goes on too.
 -- Otherwise the session is refused as before 479. Where it goes on, the
 -- plan carried out is checked again once every line is done (below, and
 -- trg_create_therapy_sessions_on_paid; NOT COVERED 16).
 if v479_wait>0 and coalesce(current_setting('invoice.therapy_reviewed',true),'')=p_request_id::text then
  select * into v479_req from public.approval_requests r
   where r.id=p_request_id and r.status='pending' and r.related_record_id=s.invoice_id and r.request_type in ('invoice_cancel','invoice_refund');
  if found then
   v479_plan:=public.invoice_action_plan(s.invoice_id,v479_req.payload->>'action',coalesce(v479_req.payload->'lines','[]'::jsonb));
   v479_held:=coalesce((v479_plan->>'net_held')::numeric,0);
   -- What each line offers before the cap, as invoice_action_plan works it
   -- out (its credit and voucher units, else its value up to what it still
   -- holds, a session line up to its sessions' "up to"), now and in the
   -- plan the request saved; whether the refund changes what it offers as it
   -- goes (credit, vouchers or sessions).
   select coalesce(jsonb_agg(jsonb_build_object('src',z.src,'item',z.item,'amount',z.amount,'offer',z.offer,'moving',z.moving)),'[]'::jsonb)
     into v479_offers
     from (select t.src,t.x->>'invoice_item_id' as item,coalesce((t.x->>'amount')::numeric,0) as amount,
                  case when b.ben then coalesce((t.x->>'benefit_backed')::numeric,0)
                       else least(greatest(least(round(coalesce(public.invoice_discounted_line_value((t.x->>'invoice_item_id')::uuid),0)
                                                       *coalesce((t.x->>'selected_quantity')::int,1)/greatest(coalesce((t.x->>'quantity')::int,1),1),2),
                                                 round(coalesce((t.x->>'remaining_value')::numeric,0),2)),0),
                                  case when jsonb_typeof(t.x->'sessions')='object' then round(coalesce((t.x->'sessions'->>'max_refund')::numeric,0),2) end) end as offer,
                  b.ben or jsonb_typeof(t.x->'sessions')='object' as moving
             from (select 'now' as src,x from jsonb_array_elements(coalesce(v479_plan->'lines','[]'::jsonb)) x
                   union all
                   select 'request',x from jsonb_array_elements(coalesce(v479_req.payload->'plan'->'lines','[]'::jsonb)) x) t
             cross join lateral (select coalesce((t.x->>'benefit_backed')::numeric,0)>0 or t.x->>'line_kind' in ('credit_package','premium_bundle')
                                        or exists(select 1 from public.invoice_benefit_values bv
                                                   where bv.invoice_id=s.invoice_id and bv.invoice_item_id::text=t.x->>'invoice_item_id') as ben) b) z;
   select (o->>'offer')::numeric into v479_pre from jsonb_array_elements(v479_offers) o where o->>'src'='now' and o->>'item'=p_item_id::text;
   select coalesce(sum((o->>'offer')::numeric),0),count(*) filter (where (o->>'offer')::numeric>0),count(*),count(*) filter (where (o->>'moving')::boolean)
     into v479_others,v479_pos,v479_lines,v479_moving
     from jsonb_array_elements(v479_offers) o where o->>'src'='now' and o->>'item'<>p_item_id::text;
   -- 479 (the review of 2 Nov 2026; NOT COVERED 17, open for the Owner): a
   -- line holding no credit, vouchers or sessions (a product) that a refund
   -- by line paid back before the invoice was last reopened is offered again
   -- by the plan, for all it holds since the reopening (the reopening charges
   -- the line again); where the plan gives it money its line is refunded a
   -- second time. 478 never does that in a plan that reaches a waiting
   -- session (it refuses the session), and whether it may is the Owner's to
   -- decide: so the session is refused as 478 refuses it, whichever line is
   -- listed first (such a line's offer and its refunds before the reopening
   -- do not change while the approval runs).
   v479_again:=exists(select 1 from jsonb_array_elements(v479_offers) o
                       where o->>'src'='now' and not (o->>'moving')::boolean and (o->>'offer')::numeric>0
                         and exists(select 1 from public.invoice_refunds r cross join lateral jsonb_array_elements(coalesce(r.outcome->'lines','[]'::jsonb)) e
                                     where r.invoice_id=s.invoice_id and e->>'invoice_item_id'=o->>'item'
                                       and r.created_at<=(select i.reopened_at from public.invoices i where i.id=s.invoice_id)));
   if v479_pre is null or v479_again then v479_as478:=true;
   elsif p_amount<v479_pre then v479_as478:=v479_held>p_amount or v479_pos>0;
   elsif v479_pre+v479_others>v479_held then v479_as478:=true;
   elsif v479_lines<2 or v479_moving=0 then v479_as478:=false;
   else
    v479_same:=v479_req.payload->'plan'->>'action' is not distinct from v479_req.payload->>'action'
      and (v479_req.payload->'plan'->>'net_held')::numeric is not distinct from v479_held
      and (select array_agg(o->>'item' order by o->>'item') from jsonb_array_elements(v479_offers) o where o->>'src'='request')
          is not distinct from (select array_agg(o->>'item' order by o->>'item') from jsonb_array_elements(v479_offers) o where o->>'src'='now')
      and exists(select 1 from jsonb_array_elements(v479_offers) o where o->>'src'='request' and o->>'item'=p_item_id::text
                  and (o->>'amount')::numeric=p_amount and (o->>'offer')::numeric=v479_pre)
      and not exists(select 1 from jsonb_array_elements(v479_offers) r join jsonb_array_elements(v479_offers) n on n->>'item'=r->>'item'
                      where r->>'src'='request' and n->>'src'='now' and not (n->>'moving')::boolean
                        and (n->>'offer')::numeric is distinct from (r->>'offer')::numeric)
      and (select sum((o->>'offer')::numeric) from jsonb_array_elements(v479_offers) o where o->>'src'='request')<=v479_held;
    -- 479 (the third fix review, 3 Nov 2026; answer F and the Owner's Q1 of
    -- 29 Oct 2026, a case with no other item to choose between stays as
    -- built): no other line offers anything at this line's turn, and none
    -- offered anything in the plan the request saved. The other lines are
    -- listed at S$0 (a credit or voucher line refunded by line before the
    -- reopening, which the reopening charges again; a product line refunded
    -- by line since, which the guided Cancel keeps), so the outcome does not
    -- follow how many of them there are, nor the line order.
    v479_only:=v479_pos=0 and not exists(select 1 from jsonb_array_elements(v479_offers) o
                                          where o->>'src'='request' and o->>'item'<>p_item_id::text and (o->>'offer')::numeric>0);
    v479_as478:=not (coalesce(v479_same,false) or v479_only);
    -- 479: the saved plan cannot show what a line the refund reached before
    -- this one (one holding credit, vouchers or sessions) offered in the plan
    -- carried out, which may be more than the request saved (credit given
    -- back to it between the request and the approval: the plan carried out
    -- then cut on a line after this one). So where it reads not cut, the
    -- refund goes on and this is checked again once every line is done, at
    -- the refund's own status write (trg_create_therapy_sessions_on_paid),
    -- from the lines the refund recorded it carried out: refused there with
    -- the message 478 refuses it with here (252's checks, as they read here)
    -- where the plan carried out was cut. Where it went on because only this
    -- line has anything to refund but the saved plan is not the one carried
    -- out (by what can be compared), the money that check allows is this
    -- line's own offer: so any money the plan carried out gave another line
    -- refuses it (one that gained credit or vouchers between the request and
    -- the approval and was reached before this one; listed after it, the
    -- saved plan above refuses it), and the line order cannot decide it.
    if not v479_as478 then
     units:=round(p_amount*s.quantity_purchased/s.paid_value_snapshot)::integer;
     v479_chk:=case when coalesce(current_setting('invoice.therapy_plan_check',true),'') like '{%}'
                    then current_setting('invoice.therapy_plan_check',true)::jsonb end;
     perform set_config('invoice.therapy_plan_check',jsonb_build_object('invoice',s.invoice_id,'request',p_request_id,
       'checks',case when v479_chk->>'invoice'=s.invoice_id::text and v479_chk->>'request'=p_request_id::text
                     then v479_chk->'checks' else '[]'::jsonb end
         ||jsonb_build_array(jsonb_build_object('item',p_item_id,'pre',v479_pre,'held',case when v479_same then v479_held else v479_pre end,
             'lines',(select coalesce(jsonb_object_agg(o->>'item',jsonb_build_object('offer',(o->>'offer')::numeric,'moving',(o->>'moving')::boolean)),'{}'::jsonb)
                        from jsonb_array_elements(v479_offers) o where o->>'src'='now' and o->>'item'<>p_item_id::text),
             'message',case when units<=0 or units>s.quantity_purchased-s.quantity_used-s.quantity_refunded
                              or round(s.paid_value_snapshot*(s.quantity_refunded+units)/s.quantity_purchased,2)-round(s.paid_value_snapshot*s.quantity_refunded/s.quantity_purchased,2)<>p_amount
                            then format('Refund whole unused therapy sessions at their original paid value; %s of %s sessions remain refundable',
                                        s.quantity_purchased-s.quantity_used-s.quantity_refunded,s.quantity_purchased)
                            else 'Settle the reopened invoice before changing its queued sessions' end)))::text,true);
    end if;
   end if;
  end if;
 end if;
 if v479_wait>0 and not v479_as478 then
  -- 479: what waits comes back when the invoice is settled: all of what the
  -- session shows as refunded and cancelled but the sessions refunded by
  -- line since the invoice was last reopened (its 'refund' events since
  -- reopened_at). The reopening charges the line again, so here a refund
  -- made before it counts no more (as invoice_charge_total and the refund
  -- options' line amounts count the line's money); one made since does.
  -- The two always add up to what the session shows (the evidence 252's
  -- payment checks); otherwise refused, changing nothing. Whole sessions
  -- are refunded at their original paid value counted from those refunded
  -- since the reopening, up to all but those used and those refunded since:
  -- what the payment would reinstate (and any still available).
  select coalesce(sum(-e.quantity),0)::int into v479_since from public.invoice_therapy_session_events e
   where e.session_id=s.id and e.event_kind='refund'
     and e.created_at>(select i.reopened_at from public.invoices i where i.id=s.invoice_id);
  if v479_wait+v479_since<>s.quantity_refunded+s.quantity_cancelled then
   raise exception 'Therapy session reopening changed; reload its original evidence'; end if;
  units:=round(p_amount*s.quantity_purchased/s.paid_value_snapshot)::integer;
  if units<=0 or units>s.quantity_purchased-s.quantity_used-v479_since
   or round(s.paid_value_snapshot*(v479_since+units)/s.quantity_purchased,2)-round(s.paid_value_snapshot*v479_since/s.quantity_purchased,2)<>p_amount then
   raise exception 'Refund whole unused therapy sessions at their original paid value; % of % sessions remain refundable',s.quantity_purchased-s.quantity_used-v479_since,s.quantity_purchased;
  end if;
  -- 479: the sessions refunded come off what waits, the most recently
  -- queued first (by the reopening's revision), as 446 takes refunded
  -- voucher units off theirs: a row is lowered, or removed when nothing is
  -- left of it (a later reopening queues again what the session shows less
  -- what still waits, 475, so a removed row does not come back whole). Each
  -- change is in the invoice's Audit Log ('reopen_session_refunded'). So the
  -- payment that settles the invoice reinstates only what is still owed.
  v479_take:=least(units,v479_wait);
  v479_left:=v479_take;
  select i.store_id into v479_store from public.invoices i where i.id=s.invoice_id;
  for q479 in select q.* from public.invoice_reopen_sessions q
                left join public.invoice_revisions r on r.invoice_id=q.invoice_id and r.request_id=q.request_id
               where q.session_id=s.id and q.applied_at is null
               order by r.revision_no desc nulls last,q.id desc loop
   exit when v479_left<=0;
   v479_n:=least(q479.quantity,v479_left);
   if v479_n=q479.quantity then
    delete from public.invoice_reopen_sessions where id=q479.id;
   else
    update public.invoice_reopen_sessions set quantity=quantity-v479_n where id=q479.id;
   end if;
   perform public.write_audit_ex('invoices',s.invoice_id,'reopen_session_refunded',to_jsonb(q479),
     jsonb_build_object('reopen_session_id',q479.id,'session_id',s.id,'refunded_units',v479_n,
       'still_waiting',q479.quantity-v479_n,'request_id',p_request_id),
     'refunds',p_reason,v479_store);
   v479_left:=v479_left-v479_n;
  end loop;
  -- 479: a waiting session refunded was cancelled or refunded already: it
  -- now shows as refunded (a cancelled one counted as refunded); one still
  -- available, if any, is refunded as before. The refund's event is written
  -- as before (the settling payment counts it).
  reserve:=least(s.quantity_cancelled,v479_take);
  insert into public.invoice_therapy_session_events(session_id,invoice_id,request_id,event_kind,quantity,before_snapshot,reason,created_by)
  values(s.id,s.invoice_id,p_request_id,'refund',-units,to_jsonb(s),p_reason,auth.uid());
  update public.customer_therapy_sessions set quantity_refunded=quantity_refunded+reserve+units-v479_take,quantity_cancelled=quantity_cancelled-reserve,
   status=case when quantity_purchased-quantity_used-quantity_refunded-quantity_cancelled-units+v479_take>0 then 'available'
     when quantity_used>0 then 'used' else 'refunded' end where id=s.id;
  return;
 end if;
 units:=round(p_amount*s.quantity_purchased/s.paid_value_snapshot)::integer;$w$,
$w$ if s.paid_value_snapshot is null or s.paid_value_snapshot<=0 then raise exception 'Original paid session value requires review before a refund'; end if;
 units:=round(p_amount*s.quantity_purchased/s.paid_value_snapshot)::integer;$w$);
insert into t479_wb values ('refund_invoice_therapy_sessions(uuid,numeric,text,uuid)', 2,
$w$declare s public.customer_therapy_sessions%rowtype; units integer; reserve integer;
 v479_wait integer; v479_since integer; v479_take integer; v479_left integer; v479_n integer; q479 record; v479_store uuid;
 v479_req public.approval_requests%rowtype; v479_plan jsonb; v479_offers jsonb; v479_held numeric; v479_pre numeric;
 v479_others numeric; v479_pos integer; v479_lines integer; v479_moving integer; v479_as478 boolean:=false; v479_chk jsonb;
 v479_again boolean; v479_same boolean; v479_only boolean;
begin$w$,
$w$declare s public.customer_therapy_sessions%rowtype; units integer; reserve integer;
begin$w$);
insert into t479_wb values ('correct_invoice_therapy_sessions(uuid,jsonb,uuid,uuid,text,uuid)', 1,
$w$ end loop;
 -- 479: waiting sessions whose customer changed on an invoice that asks no
 -- 'transfer' or 'keep' (it issued no credit or vouchers: correct_invoice's
 -- own test, invoice_transferable_benefits, as it read before this ran)
 -- follow the change, as on a paid invoice. Recorded as move_invoice_
 -- benefits_to_customer records a change that takes the invoice's benefits
 -- along ('invoice_benefits_followed_reassignment', to_customer), which is
 -- what 460's rule reads.
 if cardinality(v479_follow)>0 and not exists(select 1 from public.invoice_transferable_benefits(p_invoice_id)) then
  perform public.write_audit_ex('invoices',p_invoice_id,'invoice_benefits_followed_reassignment',null,
    jsonb_build_object('vouchers','[]'::jsonb,'credit_lots','[]'::jsonb,'allowances','[]'::jsonb,
      'therapy_sessions',to_jsonb(v479_follow),'to_customer',p_customer,'reason',p_reason),
    'invoices',p_reason,p_store);
 end if;
end $function$$w$,
$w$ end loop;
end $function$$w$);
insert into t479_wb values ('correct_invoice_therapy_sessions(uuid,jsonb,uuid,uuid,text,uuid)', 2,
$w$  if s.quantity_used>0 then raise exception 'Used therapy sessions must keep their original customer, service and invoice allocation; correct only unused purchases'; end if;
  if exists(select 1 from public.invoice_reopen_sessions where session_id=s.id and applied_at is null) then
   -- 479: a session whose reopening waits (or once its invoice was cancelled
   -- again) keeps its line, quantity and store (refused as before 479); its
   -- customer may change. It is not closed and replaced: it waits as it is,
   -- and belongs to whoever holds the invoice's benefits now (460's rule):
   -- the new customer after a 'transfer', the holder after a 'keep', the new
   -- customer where no such choice is asked (below). It follows at this
   -- correction's end, when the invoice's status is written
   -- (trg_create_therapy_sessions_on_paid). What it shows and what waits for
   -- it must still add up (252's evidence, counting refunds since the
   -- reopening); otherwise refused.
   if x is null or (nullif(x->>'therapy_service_id','')::uuid,(x->>'quantity')::integer,p_store)
        is distinct from (s.service_id,s.quantity_purchased,s.store_id) then
    raise exception 'Settle the pending session reopening before changing its allocation'; end if;
   select coalesce(sum(-e.quantity),0)::int into v479_since from public.invoice_therapy_session_events e
    where e.session_id=s.id and e.event_kind='refund'
      and e.created_at>(select i.reopened_at from public.invoices i where i.id=p_invoice_id);
   if (select coalesce(sum(q.quantity),0) from public.invoice_reopen_sessions q where q.session_id=s.id and q.applied_at is null)
      +v479_since<>s.quantity_refunded+s.quantity_cancelled then
    raise exception 'Therapy session reopening changed; reload its original evidence'; end if;
   v479_follow:=v479_follow||s.id;
   continue;
  end if;
  -- 479: sessions a customer change left with their holder ('keep') while
  -- their reopening waited are not the invoice's customer's: changing their
  -- line, quantity or store, or the invoice's customer to someone else,
  -- would give them to the invoice's customer. Refused, changing nothing
  -- (for the Owner); removing their line closes them, as before.
  if s.customer_id is distinct from v479_from and x is not null then
   raise exception 'These therapy sessions were left with % when the invoice''s customer was changed, so their line, quantity or store cannot be changed, nor the invoice moved to another customer, from this invoice: set the invoice''s customer back to them first. Nothing was changed.',
     coalesce((select c.full_name from public.customers c where c.id=s.customer_id),'their holder'); end if;
  insert into public.invoice_therapy_session_events(session_id,invoice_id,request_id,event_kind,quantity,before_snapshot,reason,created_by)$w$,
$w$  if s.quantity_used>0 then raise exception 'Used therapy sessions must keep their original customer, service and invoice allocation; correct only unused purchases'; end if;
  if exists(select 1 from public.invoice_reopen_sessions where session_id=s.id and applied_at is null) then raise exception 'Settle the pending session reopening before changing its allocation'; end if;
  insert into public.invoice_therapy_session_events(session_id,invoice_id,request_id,event_kind,quantity,before_snapshot,reason,created_by)$w$);
insert into t479_wb values ('correct_invoice_therapy_sessions(uuid,jsonb,uuid,uuid,text,uuid)', 3,
$w$  select * into it from public.invoice_items where id=s.invoice_item_id;
  -- 479: the session's customer changes when the correction changes the
  -- invoice's customer to someone other than the session's holder (before
  -- 479, when it is not the session's holder: the invoice's customer was
  -- always the holder then, so it is the same test), so sessions a customer
  -- change left with their holder ('keep', below) are not taken by a later
  -- correction that keeps the invoice's customer, or sets it back to them.
  changed:=x is null or (nullif(x->>'therapy_service_id','')::uuid,(x->>'quantity')::integer,p_store)
    is distinct from (s.service_id,s.quantity_purchased,s.store_id)
    or p_customer is distinct from v479_from and p_customer is distinct from s.customer_id;
  if not changed then continue; end if;$w$,
$w$  select * into it from public.invoice_items where id=s.invoice_item_id;
  changed:=x is null or (nullif(x->>'therapy_service_id','')::uuid,(x->>'quantity')::integer,p_customer,p_store)
    is distinct from (s.service_id,s.quantity_purchased,s.customer_id,s.store_id);
  if not changed then continue; end if;$w$);
insert into t479_wb values ('correct_invoice_therapy_sessions(uuid,jsonb,uuid,uuid,text,uuid)', 4,
$w$begin
 -- 479 (the Owner, 27 Oct 2026, answer F: "allow ... customer change while
 -- reopened therapy sessions wait (sessions ... follow the new customer)"):
 -- the invoice's customer before this correction (correct_invoice saves the
 -- new one after this runs).
 select i.customer_id into v479_from from public.invoices i where i.id=p_invoice_id;
 for s in select * from public.customer_therapy_sessions where invoice_id=p_invoice_id and is_current order by id for update loop$w$,
$w$begin
 for s in select * from public.customer_therapy_sessions where invoice_id=p_invoice_id and is_current order by id for update loop$w$);
insert into t479_wb values ('correct_invoice_therapy_sessions(uuid,jsonb,uuid,uuid,text,uuid)', 5,
$w$declare s public.customer_therapy_sessions%rowtype; x jsonb; changed boolean; it public.invoice_items%rowtype;
 v479_from uuid; v479_since integer; v479_follow uuid[]:='{}';
begin$w$,
$w$declare s public.customer_therapy_sessions%rowtype; x jsonb; changed boolean; it public.invoice_items%rowtype;
begin$w$);
insert into t479_wb values ('trg_create_therapy_sessions_on_paid()', 1,
$w$  -- cannot cause this branch to restore refunded or cancelled rights.
  -- 479: per session, all that waits for it is reinstated but what was
  -- refunded by line since the invoice was last reopened (its 'refund' events
  -- since reopened_at; refund_invoice_therapy_sessions took it off the
  -- queue): those stay refunded, nothing stays cancelled. The evidence is
  -- 252's, counting those refunds: what waits and what was refunded since add
  -- up to what the session shows (with nothing refunded since, as before:
  -- what waits is what it shows); otherwise refused, changing nothing.
  perform 1 from public.invoice_reopen_sessions where invoice_id=new.id and applied_at is null order by id for update;
  for s in select x.* from public.customer_therapy_sessions x
            where x.id in (select w.session_id from public.invoice_reopen_sessions w where w.invoice_id=new.id and w.applied_at is null)
            order by x.id for update loop
   select coalesce(sum(w.quantity),0)::int into v479_wait from public.invoice_reopen_sessions w
    where w.session_id=s.id and w.invoice_id=new.id and w.applied_at is null;
   select coalesce(sum(-e.quantity),0)::int into v479_since from public.invoice_therapy_session_events e
    where e.session_id=s.id and e.event_kind='refund' and e.created_at>new.reopened_at;
   if not s.is_current or v479_wait+v479_since<>s.quantity_refunded+s.quantity_cancelled then raise exception 'Therapy session reopening changed; reload its original evidence'; end if;
   for q in select * from public.invoice_reopen_sessions w where w.session_id=s.id and w.invoice_id=new.id and w.applied_at is null order by w.id loop
    insert into public.invoice_therapy_session_events(session_id,invoice_id,request_id,event_kind,quantity,before_snapshot,reason,created_by)
     values(s.id,new.id,q.request_id,'reopen',q.quantity,to_jsonb(s),'Explicit reopening settled',auth.uid());
    update public.invoice_reopen_sessions set applied_at=clock_timestamp() where id=q.id;
   end loop;
   update public.customer_therapy_sessions set quantity_refunded=v479_since,quantity_cancelled=0,status='available' where id=s.id;
  end loop;$w$,
$w$  -- cannot cause this branch to restore refunded or cancelled rights.
  for q in select * from public.invoice_reopen_sessions where invoice_id=new.id and applied_at is null order by id for update loop
   select * into s from public.customer_therapy_sessions where id=q.session_id for update;
   if not s.is_current or q.quantity<>s.quantity_refunded+s.quantity_cancelled then raise exception 'Therapy session reopening changed; reload its original evidence'; end if;
   insert into public.invoice_therapy_session_events(session_id,invoice_id,request_id,event_kind,quantity,before_snapshot,reason,created_by)
    values(s.id,new.id,q.request_id,'reopen',q.quantity,to_jsonb(s),'Explicit reopening settled',auth.uid());
   update public.customer_therapy_sessions set quantity_refunded=0,quantity_cancelled=0,status='available' where id=s.id;
   update public.invoice_reopen_sessions set applied_at=clock_timestamp() where id=q.id;
  end loop;$w$);
insert into t479_wb values ('trg_create_therapy_sessions_on_paid()', 2,
$w$begin
 -- 479 (the Owner, 29 Oct 2026 ~18:45 SGT, "Keep today's refusal"): a guided
 -- flow's refund of a waiting session that went on because the plan its
 -- request saved was not cut (refund_invoice_therapy_sessions, which leaves
 -- this check in invoice.therapy_plan_check) is checked again at the
 -- refund's own status write, once every line is done: refund_invoice_
 -- recorded has then recorded the lines it carried out, in the order it
 -- carried them out (invoice_refunds, the request's row with the lines). A
 -- line before the session's was given all it offered (at what it was given;
 -- one holding no credit, vouchers or sessions at what it offered at the
 -- session's turn, as the refund changes nothing it holds); a line after it
 -- offered what it offered at the session's turn (the refund had not reached
 -- it). Where those offers come to more than the money held, the plan
 -- carried out was cut and gave the waiting session part of the money while
 -- another line had something to refund: refused with the message 478
 -- refuses it with at the session's turn, changing nothing.
 v479_raw:=current_setting('invoice.therapy_plan_check',true);
 if v479_raw like '{%}' and (v479_raw::jsonb)->>'invoice'=new.id::text then
  select r.outcome->'lines' into v479_lines from public.invoice_refunds r
   where r.invoice_id=new.id and r.request_id=((v479_raw::jsonb)->>'request')::uuid and jsonb_typeof(r.outcome->'lines')='array'
   order by r.created_at limit 1;
  if v479_lines is not null then
   perform set_config('invoice.therapy_plan_check','',true);
   for v479_c in select c from jsonb_array_elements((v479_raw::jsonb)->'checks') c loop
    select coalesce(sum(case when not coalesce((v479_c->'lines'->(x.l->>'invoice_item_id')->>'moving')::boolean,true)
                             then (v479_c->'lines'->(x.l->>'invoice_item_id')->>'offer')::numeric
                             when jsonb_typeof(x.l->'benefits')='array' and jsonb_array_length(x.l->'benefits')>0
                             then (select sum((b->>'amount')::numeric) from jsonb_array_elements(x.l->'benefits') b)
                             else (x.l->>'amount')::numeric end),0),
           coalesce(array_agg(x.l->>'invoice_item_id'),'{}')
      into v479_before,v479_items
      from jsonb_array_elements(v479_lines) with ordinality x(l,o)
     where x.o<(select min(y.o) from jsonb_array_elements(v479_lines) with ordinality y(l,o) where y.l->>'invoice_item_id'=v479_c->>'item');
    select coalesce(sum((e.value->>'offer')::numeric),0) into v479_after
      from jsonb_each(v479_c->'lines') e where not (e.key=any(v479_items));
    if v479_before+(v479_c->>'pre')::numeric+v479_after>(v479_c->>'held')::numeric then
     raise exception '%',v479_c->>'message'; end if;
   end loop;
  end if;
 end if;
 -- 479 (the Owner, 27 Oct 2026, answer F: "customer change while reopened
 -- therapy sessions wait (sessions ... follow the new customer)"): a session
 -- waiting for a reopening's payment, or once its invoice was cancelled again
 -- before it was paid, belongs to whoever holds the invoice's benefits now,
 -- as what a reopening gives back does (460's rule, with 462's fall-backs
 -- for a deleted record: invoice_credit_live_holder): the new customer after
 -- a customer change that took the benefits along ('transfer', or one with
 -- no such choice, correct_invoice_therapy_sessions), its holder after a
 -- 'keep', the record a merge kept. It follows whenever the invoice's status
 -- is written (a correction writes it last, after it moved the benefits), in
 -- place, with its counts and its waiting rows; an event and the invoice's
 -- Audit Log ('reopen_sessions_follow_holder') record it. Read first without
 -- locks: only where a waiting session must follow someone else are its
 -- waiting rows and the sessions locked and read again, so a status write
 -- that moves nothing (a part payment, Correct payment) locks no session, as
 -- before 479 (a merge locks the sessions before the invoice).
 if exists(select 1 from public.invoice_reopen_sessions w
            join public.customer_therapy_sessions x on x.id=w.session_id and x.is_current
            cross join lateral (select public.invoice_credit_live_holder(new.id,x.customer_id,x.created_at) as h) l
            where w.invoice_id=new.id and w.applied_at is null and l.h is not null and l.h<>x.customer_id) then
  perform 1 from public.invoice_reopen_sessions where invoice_id=new.id and applied_at is null order by id for update;
  for s in select x.* from public.customer_therapy_sessions x
            where x.is_current and x.id in (select w.session_id from public.invoice_reopen_sessions w where w.invoice_id=new.id and w.applied_at is null)
            order by x.id for update loop
   v479_to:=public.invoice_credit_live_holder(new.id,s.customer_id,s.created_at);
   continue when v479_to is null or v479_to=s.customer_id;
   insert into public.invoice_therapy_session_events(session_id,invoice_id,event_kind,quantity,before_snapshot,reason,created_by)
    values(s.id,new.id,'reassign',0,to_jsonb(s),'Waiting for a reopening''s payment; follows whoever holds the invoice''s benefits now',auth.uid());
   update public.customer_therapy_sessions set customer_id=v479_to where id=s.id;
   perform public.write_audit_ex('invoices',new.id,'reopen_sessions_follow_holder',
     jsonb_build_object('session_id',s.id,'customer_id',s.customer_id),
     jsonb_build_object('session_id',s.id,'customer_id',v479_to,
       'waiting',(select sum(w.quantity) from public.invoice_reopen_sessions w where w.session_id=s.id and w.applied_at is null)),
     'invoices','Therapy sessions waiting for a reopening''s payment follow whoever holds the invoice''s benefits',new.store_id);
  end loop;
 end if;
 if new.status in ('paid','completed_foc') then$w$,
$w$begin
 if new.status in ('paid','completed_foc') then$w$);
insert into t479_wb values ('trg_create_therapy_sessions_on_paid()', 3,
$w$declare s public.customer_therapy_sessions%rowtype; q record; unused integer;
 v479_wait integer; v479_since integer; v479_to uuid;
 v479_raw text; v479_lines jsonb; v479_c jsonb; v479_items text[]; v479_before numeric; v479_after numeric;
begin$w$,
$w$declare s public.customer_therapy_sessions%rowtype; q record; unused integer;
begin$w$);
-- ===== S. Where it starts =====
do $$ begin
  perform pg_temp.t479_check(pg_temp.t479_462_in() and pg_temp.t479_475_in() and pg_temp.t479_476_in() and pg_temp.t479_477_in()
      and pg_temp.t479_478_in(),
    'S 462, 475, 476, 477 and 478 are in (479 goes in after them)');
  perform pg_temp.t479_check((select string_agg(pg_get_triggerdef(t.oid), E'\n' order by t.tgname) from pg_trigger t
                               where t.tgrelid = 'public.invoices'::regclass and t.tgfoid = 'public.trg_create_therapy_sessions_on_paid()'::regprocedure)
      = 'CREATE TRIGGER create_therapy_sessions_on_paid AFTER UPDATE OF status ON public.invoices FOR EACH ROW EXECUTE FUNCTION trg_create_therapy_sessions_on_paid()',
    'S the trigger that runs the settlement''s step is as read');
end $$;
do $$ begin
  perform pg_temp.t479_check(pg_temp.t479_options_kept(),
    'S the refund options are as 438, 448 and 477 pinned them (479 does not change them)');
end $$;
\if :{?nomig}
do $$ begin
  perform pg_temp.t479_check(pg_temp.t479_in() and pg_temp.t479_at('after'), 'S -v nomig=1: 479 is in, as tested');
end $$;
\else
do $$ begin
  perform pg_temp.t479_check(not pg_temp.t479_in() and pg_temp.t479_at('before'),
    'S 479 is not in yet and the three functions are at their BEFORE (this suite installs it; use -v nomig=1 where it is in)');
end $$;

-- ===== R. Before 479: each case reproduced (undone afterwards) =====
-- A fixed (or known, with err0) case is refused at its step; a control, a
-- kept case (or known, without err0) ends exactly as expected.
savepoint t479_r;
do $$
declare c record; o jsonb; res text := ''; e record; ores text := '';
begin
  for c in select * from t479_cases order by ord loop
    o := pg_temp.t479_run('before', c.k, c.steps);
    if c.err0 is not null then
      perform pg_temp.t479_check(o->>'error' like c.err0 and coalesce(o->>'invariants', '') = '',
        'R ' || c.k || ' without 479 is not refused as ' || c.err0 || ': ' || o::text);
      res := res || format(E'\n  %s: %s', c.k, o->>'error');
    else
      perform pg_temp.t479_check(pg_temp.t479_meets(o, c.expect) and coalesce(o->>'invariants', '') = ''
          and coalesce((o->>'cancel_left')::numeric, 0) = 0,
        'R ' || c.kind || ' ' || c.k || ' without 479: ' || coalesce(pg_temp.t479_diff(o, c.expect), '') || ' ' || o::text);
    end if;
  end loop;
  for c in select * from t479_qstates loop
    perform pg_temp.t479_run('before', c.k, c.steps);
  end loop;
  -- The cut plans (NOT COVERED 10 and 17): as expected for the line their
  -- plan lists first.
  for c in select * from t479_ocases order by ord loop
    o := pg_temp.t479_run('before', c.k, c.steps);
    select * into e from t479_oexp x where x.shape = c.shape and x.first in (pg_temp.t479_first(o), '*')
     order by x.first = '*' limit 1;
    perform pg_temp.t479_check(e.shape is not null,
      'R ' || c.k || ' without 479: its plan lists first a line no case expects: ' || o::text);
    perform pg_temp.t479_check(pg_temp.t479_meets(o, e.expect) and coalesce(o->>'invariants', '') = ''
        and coalesce((o->>'cancel_left')::numeric, 0) = 0,
      'R ' || c.k || ' without 479 (the ' || pg_temp.t479_first(o) || ' line first): ' || coalesce(pg_temp.t479_diff(o, e.expect), '') || ' ' || o::text);
    ores := ores || format(E'\n  %s (%s): %s', c.k, o->>'plan', coalesce(o->>'error', nullif(o->>'sess', '-'), o->>'status'));
  end loop;
  raise notice 'PASS R: without 479 every fixed case is refused at the step it names (the fault reproduced), the controls and what the Owner kept (29 Oct 2026) as expected:%', res;
  raise notice 'PASS R (NOT COVERED 10 and 17): without 479 the plans cut to the money held, by the line each lists first:%', ores;
end $$;

-- ===== Q. The header's read-only query, on these states =====
do $$
declare c record;
begin
  for c in select k, listed from t479_qstates union all select k, q from t479_cases loop
    perform pg_temp.t479_check(pg_temp.t479_listed(pg_temp.t479_id('before/' || c.k || '/inv')) is not distinct from c.listed,
      'Q ' || c.k || ' is listed as ' || coalesce(pg_temp.t479_listed(pg_temp.t479_id('before/' || c.k || '/inv')), 'nothing')
      || ', not ' || coalesce(c.listed, 'nothing'));
  end loop;
  raise notice 'PASS Q: the header''s query lists, by reason, an invoice with a therapy session waiting for its reopening''s payment, the invoice part-paid, unpaid or cancelled again (1: Q1, Q1c, Q1r, Q1v and every fixed case as it ends before 479), a waiting session whose rows and refunds since the reopening do not add up to what it shows (2: Q2s, Q2d, by hand), a session held by someone other than its invoice''s customer (3: Q3, Q3c, by hand); nothing never reopened or settled (Q0, Q0b, the settled controls)';
end $$;
select coalesce(jsonb_object_agg(k, v), '{}'::jsonb)::text as t479_rbefore from t479_res where phase = 'before' \gset
select coalesce(jsonb_object_agg(pre, jsonb_build_object('err', err, 'at', at)), '{}'::jsonb)::text as t479_ebefore from t479_err where pre like 'before/%' \gset
rollback to savepoint t479_r;
insert into t479_res select 'before', key, value from jsonb_each(:'t479_rbefore'::jsonb);
insert into t479_err select key, value->>'err', (value->>'at')::int from jsonb_each(:'t479_ebefore'::jsonb);

-- ===== 9. The refusals, each changing nothing =====
-- 9a One of the three is neither its BEFORE nor its AFTER.
savepoint t479_9;
alter function public.refund_invoice_therapy_sessions(uuid,numeric,text,uuid) set work_mem = '64kB';
\set ON_ERROR_STOP off
\ir ../../../supabase/479_refunds_and_customer_change_while_sessions_wait.sql
\set ON_ERROR_STOP on
rollback to savepoint t479_9;
select set_config('t479.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t479_check(current_setting('t479.msg') like '479: public.refund_invoice_therapy_sessions(uuid,numeric,text,uuid) is not the version this was tested against (md5 %). Re-read it and re-test before applying.'
      and not pg_temp.t479_in() and pg_temp.t479_at('before'), '9a refused with: ' || current_setting('t479.msg'));
end $$;
-- 9a2 A partial install (479 in, then two of the three put back).
savepoint t479_9;
\ir ../../../supabase/479_refunds_and_customer_change_while_sessions_wait.sql
do $$ declare d text; begin
  for d in select def from t479_defs where sig <> 'trg_create_therapy_sessions_on_paid()' loop execute d; end loop;
end $$;
\set ON_ERROR_STOP off
\ir ../../../supabase/479_refunds_and_customer_change_while_sessions_wait.sql
\set ON_ERROR_STOP on
rollback to savepoint t479_9;
select set_config('t479.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t479_check(current_setting('t479.msg') = '479: some of the three functions are at their BEFORE and some at their AFTER (2 and 1); a partial install, not as tested'
      and not pg_temp.t479_in() and pg_temp.t479_at('before'), '9a2 refused with: ' || current_setting('t479.msg'));
end $$;
-- 9b A function it relies on is not as read (a setting added to it): the
-- money the line follows; 476's (what a customer change asks); 478's (the
-- preview); the holder rule; the refund options (what the guided plans
-- offer: the Owner, 29 Oct 2026).
savepoint t479_9;
alter function public.invoice_charge_total(uuid) set work_mem = '64kB';
\set ON_ERROR_STOP off
\ir ../../../supabase/479_refunds_and_customer_change_while_sessions_wait.sql
\set ON_ERROR_STOP on
rollback to savepoint t479_9;
select set_config('t479.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t479_check(current_setting('t479.msg') like '479: public.invoice_charge_total(uuid) is missing or not the version this was tested against (md5 %). Re-read it and re-test before applying (479 goes in after 476, 477 and 478).'
      and not pg_temp.t479_in() and pg_temp.t479_at('before'), '9b refused with: ' || current_setting('t479.msg'));
end $$;
savepoint t479_9;
alter function public.invoice_transferable_benefits(uuid) set work_mem = '64kB';
\set ON_ERROR_STOP off
\ir ../../../supabase/479_refunds_and_customer_change_while_sessions_wait.sql
\set ON_ERROR_STOP on
rollback to savepoint t479_9;
select set_config('t479.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t479_check(current_setting('t479.msg') like '479: public.invoice_transferable_benefits(uuid) is missing or not the version%'
      and not pg_temp.t479_in(), '9b2 refused with: ' || current_setting('t479.msg'));
end $$;
savepoint t479_9;
alter function public.invoice_reopen_preview_before_sessions(uuid) set work_mem = '64kB';
\set ON_ERROR_STOP off
\ir ../../../supabase/479_refunds_and_customer_change_while_sessions_wait.sql
\set ON_ERROR_STOP on
rollback to savepoint t479_9;
select set_config('t479.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t479_check(current_setting('t479.msg') like '479: public.invoice_reopen_preview_before_sessions(uuid) is missing or not the version%'
      and not pg_temp.t479_in(), '9b3 refused with: ' || current_setting('t479.msg'));
end $$;
savepoint t479_9;
alter function public.invoice_credit_live_holder(uuid,uuid,timestamp with time zone) set work_mem = '64kB';
\set ON_ERROR_STOP off
\ir ../../../supabase/479_refunds_and_customer_change_while_sessions_wait.sql
\set ON_ERROR_STOP on
rollback to savepoint t479_9;
select set_config('t479.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t479_check(current_setting('t479.msg') like '479: public.invoice_credit_live_holder(uuid,uuid,timestamp with time zone) is missing or not the version%'
      and not pg_temp.t479_in(), '9b4 refused with: ' || current_setting('t479.msg'));
end $$;
savepoint t479_9;
alter function public.invoice_refund_options(uuid) set work_mem = '64kB';
\set ON_ERROR_STOP off
\ir ../../../supabase/479_refunds_and_customer_change_while_sessions_wait.sql
\set ON_ERROR_STOP on
rollback to savepoint t479_9;
select set_config('t479.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t479_check(current_setting('t479.msg') like '479: public.invoice_refund_options(uuid) is missing or not the version%'
      and not pg_temp.t479_in(), '9b5 refused with: ' || current_setting('t479.msg'));
end $$;
-- 9c Another function takes one of their names (an overload).
savepoint t479_9;
create function public.refund_invoice_therapy_sessions(p text) returns void language plpgsql as $f$ begin end $f$;
\set ON_ERROR_STOP off
\ir ../../../supabase/479_refunds_and_customer_change_while_sessions_wait.sql
\set ON_ERROR_STOP on
rollback to savepoint t479_9;
select set_config('t479.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t479_check(current_setting('t479.msg') = '479: another function takes the name of one this changes: refund_invoice_therapy_sessions(text)'
      and not pg_temp.t479_in(), '9c refused with: ' || current_setting('t479.msg'));
end $$;
-- 9d A new caller of one of them.
savepoint t479_9;
create function public.t479_probe_refund(p uuid) returns void language sql as $f$ select public.refund_invoice_therapy_sessions(p, 1, 'probe', gen_random_uuid()) $f$;
\set ON_ERROR_STOP off
\ir ../../../supabase/479_refunds_and_customer_change_while_sessions_wait.sql
\set ON_ERROR_STOP on
rollback to savepoint t479_9;
select set_config('t479.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t479_check(current_setting('t479.msg') like '479: public.refund_invoice_therapy_sessions(uuid,numeric,text,uuid) is called by %t479_probe_refund(uuid)%'
      and not pg_temp.t479_in(), '9d refused with: ' || current_setting('t479.msg'));
end $$;
-- 9e A new reader of the session queue; a new writer of the sessions; a
-- new reader of their events; a new writer of reopened_at; a new reader of
-- 460's row.
savepoint t479_9;
create function public.t479_probe_queue() returns bigint language sql as $f$ select count(*) from public.invoice_reopen_sessions $f$;
\set ON_ERROR_STOP off
\ir ../../../supabase/479_refunds_and_customer_change_while_sessions_wait.sql
\set ON_ERROR_STOP on
rollback to savepoint t479_9;
select set_config('t479.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t479_check(current_setting('t479.msg') like '479: what reads or writes the session queue (invoice_reopen_sessions) is not as read on 29 Oct 2026 (%t479_probe_queue()%'
      and not pg_temp.t479_in(), '9e refused with: ' || current_setting('t479.msg'));
end $$;
savepoint t479_9;
create function public.t479_probe_sess() returns void language sql as $f$ update public.customer_therapy_sessions set notes = notes where false $f$;
\set ON_ERROR_STOP off
\ir ../../../supabase/479_refunds_and_customer_change_while_sessions_wait.sql
\set ON_ERROR_STOP on
rollback to savepoint t479_9;
select set_config('t479.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t479_check(current_setting('t479.msg') like '479: what updates the therapy sessions (customer_therapy_sessions) is not as read on 29 Oct 2026 (%t479_probe_sess()%'
      and not pg_temp.t479_in(), '9e2 refused with: ' || current_setting('t479.msg'));
end $$;
savepoint t479_9;
create function public.t479_probe_events() returns bigint language sql as $f$ select count(*) from public.invoice_therapy_session_events $f$;
\set ON_ERROR_STOP off
\ir ../../../supabase/479_refunds_and_customer_change_while_sessions_wait.sql
\set ON_ERROR_STOP on
rollback to savepoint t479_9;
select set_config('t479.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t479_check(current_setting('t479.msg') like '479: what reads or writes the therapy session events is not as read on 29 Oct 2026 (%t479_probe_events()%'
      and not pg_temp.t479_in(), '9e3 refused with: ' || current_setting('t479.msg'));
end $$;
savepoint t479_9;
create function public.t479_probe_reopened() returns void language sql as $f$ update public.invoices set reopened_at = now() where false $f$;
\set ON_ERROR_STOP off
\ir ../../../supabase/479_refunds_and_customer_change_while_sessions_wait.sql
\set ON_ERROR_STOP on
rollback to savepoint t479_9;
select set_config('t479.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t479_check(current_setting('t479.msg') like '479: what sets an invoice''s reopened_at is not as read on 29 Oct 2026 (%t479_probe_reopened()%'
      and not pg_temp.t479_in(), '9e4 refused with: ' || current_setting('t479.msg'));
end $$;
savepoint t479_9;
create function public.t479_probe_follow() returns bigint language sql as $f$ select count(*) from public.audit_logs where action = 'invoice_benefits_followed_reassignment' $f$;
\set ON_ERROR_STOP off
\ir ../../../supabase/479_refunds_and_customer_change_while_sessions_wait.sql
\set ON_ERROR_STOP on
rollback to savepoint t479_9;
select set_config('t479.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t479_check(current_setting('t479.msg') like '479: what writes or reads the record of a customer change that takes the benefits along (invoice_benefits_followed_reassignment) is not as read on 29 Oct 2026 (%t479_probe_follow()%'
      and not pg_temp.t479_in(), '9e5 refused with: ' || current_setting('t479.msg'));
end $$;
-- 9e6 A new reader of the check a guided flow's refund leaves for the
-- refund's status write (invoice.therapy_plan_check: 479's two alone).
savepoint t479_9;
create function public.t479_probe_check() returns text language sql as $f$ select current_setting('invoice.therapy_plan_check', true) $f$;
\set ON_ERROR_STOP off
\ir ../../../supabase/479_refunds_and_customer_change_while_sessions_wait.sql
\set ON_ERROR_STOP on
rollback to savepoint t479_9;
select set_config('t479.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t479_check(current_setting('t479.msg') like '479: what reads or writes invoice.therapy_plan_check (%) is not as 479 leaves it (%t479_probe_check()%'
      and not pg_temp.t479_in(), '9e6 refused with: ' || current_setting('t479.msg'));
end $$;
-- 9f The settlement trigger, the events' stamp, the queue's key, a column
-- read, not as read.
savepoint t479_9;
drop trigger create_therapy_sessions_on_paid on public.invoices;
create trigger create_therapy_sessions_on_paid after update of status on public.invoices
  for each row when (new.status is distinct from old.status) execute function public.trg_create_therapy_sessions_on_paid();
\set ON_ERROR_STOP off
\ir ../../../supabase/479_refunds_and_customer_change_while_sessions_wait.sql
\set ON_ERROR_STOP on
rollback to savepoint t479_9;
select set_config('t479.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t479_check(current_setting('t479.msg') = '479: the trigger that runs a reopening''s therapy sessions at settlement is not as read on 29 Oct 2026'
      and not pg_temp.t479_in(), '9f refused with: ' || current_setting('t479.msg'));
end $$;
savepoint t479_9;
alter table public.invoice_therapy_session_events alter column created_at set default now();
\set ON_ERROR_STOP off
\ir ../../../supabase/479_refunds_and_customer_change_while_sessions_wait.sql
\set ON_ERROR_STOP on
rollback to savepoint t479_9;
select set_config('t479.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t479_check(current_setting('t479.msg') like '479: the therapy session events are not stamped by clock_timestamp() as read on 29 Oct 2026%'
      and not pg_temp.t479_in(), '9f2 refused with: ' || current_setting('t479.msg'));
end $$;
savepoint t479_9;
alter table public.invoice_reopen_sessions drop constraint invoice_reopen_sessions_session_id_request_id_key;
\set ON_ERROR_STOP off
\ir ../../../supabase/479_refunds_and_customer_change_while_sessions_wait.sql
\set ON_ERROR_STOP on
rollback to savepoint t479_9;
select set_config('t479.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t479_check(current_setting('t479.msg') like '479: the session queue''s keys are not as read on 29 Oct 2026%'
      and not pg_temp.t479_in(), '9f3 refused with: ' || current_setting('t479.msg'));
end $$;
savepoint t479_9;
alter table public.invoice_therapy_session_events alter column quantity type bigint;
\set ON_ERROR_STOP off
\ir ../../../supabase/479_refunds_and_customer_change_while_sessions_wait.sql
\set ON_ERROR_STOP on
rollback to savepoint t479_9;
select set_config('t479.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t479_check(current_setting('t479.msg') = '479: these columns are missing or not as read on 29 Oct 2026: invoice_therapy_session_events.quantity'
      and not pg_temp.t479_in(), '9f4 refused with: ' || current_setting('t479.msg'));
end $$;
-- 9g Other grants; the same grants in another order do not stop it.
savepoint t479_9;
grant execute on function public.refund_invoice_therapy_sessions(uuid,numeric,text,uuid) to authenticated;
\set ON_ERROR_STOP off
\ir ../../../supabase/479_refunds_and_customer_change_while_sessions_wait.sql
\set ON_ERROR_STOP on
rollback to savepoint t479_9;
select set_config('t479.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t479_check(current_setting('t479.msg') like '479: who may call public.refund_invoice_therapy_sessions(uuid,numeric,text,uuid) is not as read on 29 Oct 2026 (%)'
      and not pg_temp.t479_in(), '9g refused with: ' || current_setting('t479.msg'));
end $$;
savepoint t479_9;
revoke execute on function public.refund_invoice_therapy_sessions(uuid,numeric,text,uuid) from postgres;
grant execute on function public.refund_invoice_therapy_sessions(uuid,numeric,text,uuid) to postgres;
select pg_temp.t479_check((select proacl::text from pg_proc where oid = 'public.refund_invoice_therapy_sessions(uuid,numeric,text,uuid)'::regprocedure)
         <> '{postgres=X/postgres,service_role=X/postgres}'
       and pg_temp.t479_grant_set('refund_invoice_therapy_sessions(uuid,numeric,text,uuid)') = '{postgres=X/postgres,service_role=X/postgres}',
  '9g2 set-up: the same grants in another order');
\ir ../../../supabase/479_refunds_and_customer_change_while_sessions_wait.sql
select pg_temp.t479_in() and pg_temp.t479_at('after') as t479_9g2_in \gset
rollback to savepoint t479_9;
select pg_temp.t479_check(:'t479_9g2_in'::boolean and not pg_temp.t479_in(), '9g2 the same grants in another order stopped it');
do $$ begin
  raise notice 'PASS 9: refused, changing nothing, where one of the three is neither its BEFORE nor its AFTER, an install is partial, a function it relies on is not as tested (the line''s money, 476''s, 478''s, the holder rule, the refund options), another function takes a name, a new function calls one, reads or writes the session queue, updates the sessions, reads or writes their events, sets reopened_at, reads 460''s row or the check a guided flow''s refund leaves for its status write, the settlement trigger, the events'' stamp, the queue''s key or a column read is not as read, or other grants; the same grants in another order do not stop it';
end $$;

-- ===== M. Begun before 479, finished after it =====
-- Waiting (MW); cancelled again (MC); with a voucher line, waiting (MV).
do $$ begin
  perform pg_temp.t479_run('mid', 'MW', 'sale A th; cancel; backt 1 20; reopen; backt 1 20; pay', 1, 4);
  perform pg_temp.t479_run('mid', 'MC', 'sale A th; cancel; backt 1 20; reopen; cancel; change B; reopen; pay', 1, 5);
  perform pg_temp.t479_run('mid', 'MV', 'sale A th,v; cancel; backt 2 20; reopen; change B keep; pay', 1, 4);
  perform pg_temp.t479_check(pg_temp.t479_listed(pg_temp.t479_id('mid/MW/inv')) = '1/1' and pg_temp.t479_listed(pg_temp.t479_id('mid/MC/inv')) = '1/1'
      and pg_temp.t479_listed(pg_temp.t479_id('mid/MV/inv')) = '1/1', 'M the header''s query before 479');
end $$;
\endif

-- ===== 10. Install 479, twice =====
\if :{?nomig}
do $$ begin raise notice 'NOTE 10: -v nomig=1, so 479 is not installed here (R, Q, 9 and M are skipped)'; end $$;
\else
\ir ../../../supabase/479_refunds_and_customer_change_while_sessions_wait.sql
do $$ begin insert into t479_fp values ('first', pg_temp.t479_fingerprint()); end $$;
\ir ../../../supabase/479_refunds_and_customer_change_while_sessions_wait.sql
do $$ begin insert into t479_fp values ('second', pg_temp.t479_fingerprint()); end $$;
\endif
do $$
declare m record;
begin
  perform pg_temp.t479_check(pg_temp.t479_in() and pg_temp.t479_at('after'), '10 479 is not installed as tested');
  perform pg_temp.t479_check(pg_temp.t479_options_kept(), '10 479 changed the refund options');
  perform pg_temp.t479_check((select count(*) from pg_proc where pronamespace = 'public'::regnamespace
                               and proname in ('refund_invoice_therapy_sessions', 'correct_invoice_therapy_sessions',
                                               'trg_create_therapy_sessions_on_paid', 'invoice_refund_options')) = 4,
    '10 an overload exists');
  for m in select sig from t479_md5 loop
    perform pg_temp.t479_check(pg_temp.t479_grant_set(m.sig) = '{postgres=X/postgres,service_role=X/postgres}'::text[]
        and not has_function_privilege('anon', 'public.' || m.sig, 'execute')
        and not has_function_privilege('authenticated', 'public.' || m.sig, 'execute'),
      '10 who may call ' || m.sig || ' changed');
  end loop;
  perform pg_temp.t479_check(pg_temp.t479_grant_set('invoice_refund_options(uuid)')
                               = '{authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres}'::text[],
    '10 who may call the refund options changed');
  if exists (select 1 from t479_fp where k = 'first') then
    perform pg_temp.t479_check((select fp from t479_fp where k = 'second') = (select fp from t479_fp where k = 'first'),
      '10 the second run of 479 changed functions');
    perform pg_temp.t479_check(split_part((select fp from t479_fp where k = 'first'), ' ', 2) = split_part((select fp from t479_fp where k = 'start'), ' ', 2),
      '10 479 changed the number of functions');
    perform pg_temp.t479_check(pg_temp.t479_grants() = (select fp from t479_fp where k = 'grants'), '10 the grants changed');
    -- On a copy of production at 486 (3 Nov 2026): the AFTER fingerprint.
    -- Still accepted: the same build on a copy at 485 (3 Nov 2026), 486
    -- having changed the merge preview alone. (This build was not worked
    -- out on a copy at 478; the previous builds' were fbc67a29 there,
    -- bda210db, 082badac, ca96dde5 and 270aa323 at 485.)
    if (select fp from t479_fp where k = 'start') = '987d9ea60beaec88fb6146d3db6f9441 1398' then
      perform pg_temp.t479_check((select fp from t479_fp where k = 'first') = '8928dd465d7bfd1125d42a983735e226 1398',
        '10 the fingerprint after 479 is ' || (select fp from t479_fp where k = 'first'));
    elsif (select fp from t479_fp where k = 'start') = 'd5bcc0cef63fe73c19cf2c9a949b05d5 1398' then
      perform pg_temp.t479_check((select fp from t479_fp where k = 'first') = '5695d246035dd52d0f16c5f7f92fc5f8 1398',
        '10 the fingerprint after 479 (at 485) is ' || (select fp from t479_fp where k = 'first'));
    end if;
  end if;
  raise notice 'PASS 10: 479 installed (the three at their AFTER, the refund options unchanged); %; no overload; the grants as before (the refund, the correction''s step and the trigger''s function: postgres and the service role; the refund options: signed-in staff too; never anon)',
    coalesce('the second run changed nothing (' || (select fp from t479_fp where k = 'second') || ')', 'it was in before the suite (nomig)');
end $$;

-- ===== M (finished). Begun before 479, finished after it =====
\if :{?nomig}
do $$ begin raise notice 'NOTE M: -v nomig=1 (479 in), so no case was begun before it'; end $$;
\else
do $$
declare o jsonb;
begin
  -- MW: waiting before 479; refunded by line after it and paid.
  o := pg_temp.t479_run('mid', 'MW', 'sale A th; cancel; backt 1 20; reopen; backt 1 20; pay', 5);
  perform pg_temp.t479_check(pg_temp.t479_meets(o, '{"status":"paid","net":40,"sess":"2/3 r1 c0 available","swait":0,"sev":1,"sholder":"A","sinv":"","error":null}')
      and coalesce(o->>'invariants', '') = '', 'M MW ' || o::text);
  -- MC: cancelled again before 479; the customer changed after it,
  -- reopened and paid: B's.
  o := pg_temp.t479_run('mid', 'MC', 'sale A th; cancel; backt 1 20; reopen; cancel; change B; reopen; pay', 6);
  perform pg_temp.t479_check(pg_temp.t479_meets(o, '{"status":"paid","net":60,"sess":"3/3 r0 c0 available","swait":0,"sholder":"B","icust":"B","sinv":"","error":null}')
      and coalesce(o->>'invariants', '') = '', 'M MC ' || o::text);
  -- MV: with a voucher line, waiting before 479; 'keep' after it and paid:
  -- A's.
  o := pg_temp.t479_run('mid', 'MV', 'sale A th,v; cancel; backt 2 20; reopen; change B keep; pay', 5);
  perform pg_temp.t479_check(pg_temp.t479_meets(o, '{"status":"paid","net":120,"sess":"3/3 r0 c0 available","holds":{"A":"0.00/2","B":"0.00"},"swait":0,"sholder":"A","icust":"B","sinv":"","error":null}')
      and coalesce(o->>'invariants', '') = '', 'M MV ' || o::text);
  raise notice 'PASS M: begun before 479 (waiting; cancelled again; with a voucher line, waiting), finished after it: refunded by line and paid, 2 of 3 for S$40; the customer changed, reopened and paid, B holds 3; ''keep'', paid, A holds the sessions and the vouchers';
end $$;
\endif

-- ===== A. After 479: each case =====
do $$
declare c record; o jsonb; b jsonb; pa jsonb; e record; res text := ''; n int := 0; m int := 0;
begin
  for c in select * from t479_cases order by ord loop
    o := pg_temp.t479_run('after', c.k, c.steps);
    perform pg_temp.t479_check(pg_temp.t479_meets(o, c.expect) and coalesce(o->>'invariants', '') = ''
        and coalesce((o->>'cancel_left')::numeric, 0) = 0,
      'A ' || c.kind || ' ' || c.k || ': ' || coalesce(pg_temp.t479_diff(o, c.expect), '') || ' ' || o::text);
    if c.kind <> 'control' then res := res || format(' %s %s;', c.k, coalesce(o->>'sess', '-')); end if;
    b := (select v from t479_res where phase = 'before' and k = c.k);
    select * into e from t479_err where pre = 'before/' || c.k;
    -- Where R ran: a case refused before 479 is, up to the step refused,
    -- exactly as before 479 (the plans too); any other case (a control, what
    -- the Owner kept, a known case without err0) exactly as before 479.
    if b is not null then
      if c.err0 is not null then
        pa := pg_temp.t479_run('after', c.k || '-pre', pg_temp.t479_upto(c.steps, e.at - 1));
        perform pg_temp.t479_check(pg_temp.t479_but_error(pa) = pg_temp.t479_but_error(b),
          'A ' || c.k || ' differs from before 479 up to the step refused before it: before ' || pg_temp.t479_but_error(b)::text
          || ', after ' || pg_temp.t479_but_error(pa)::text);
      elsif pg_temp.t479_unordered(o)->>'plan' is not distinct from pg_temp.t479_unordered(b)->>'plan' then
        perform pg_temp.t479_check(pg_temp.t479_unordered(o) = pg_temp.t479_unordered(b),
          'A ' || c.kind || ' ' || c.k || ' differs from before 479: ' || b::text || ' / ' || o::text);
      else
        -- its plan was cut to the money held and listed its lines in
        -- another order before 479 (TVn: what the cut gives each line
        -- differs), so only what does not follow the order is compared
        perform pg_temp.t479_check((o->>'net', o->>'status', o->>'sess', o->>'squeued', o->>'error' is null)
                                   is not distinct from (b->>'net', b->>'status', b->>'sess', b->>'squeued', b->>'error' is null),
          'A ' || c.kind || ' ' || c.k || ' (its plan listed in another order before 479) differs from before 479: ' || b::text || ' / ' || o::text);
        m := m + 1;
      end if;
      n := n + 1;
    end if;
  end loop;
  raise notice 'PASS A: after 479 every fixed, kept and known case ends as expected (the sessions as they end):%; the controls as expected; % cases compared with before 479: nothing else differs (up to the step refused before 479: who holds what, the money, the plans, the invariants, Cancel, the dialog; what the Owner kept and the controls: every key, the plan''s lines in any order; % listed their lines in another order before 479 and cut them otherwise: the money, the status, the sessions, refused or not)', res, n, m;
end $$;
-- Q after 479: the states 479 makes are listed as the header says.
do $$ begin
  perform pg_temp.t479_check(pg_temp.t479_listed(pg_temp.t479_id('after/RW/inv')) = '1/1'
      and pg_temp.t479_listed(pg_temp.t479_id('after/RB/inv')) = '1/1'
      and pg_temp.t479_listed(pg_temp.t479_id('after/CTw/inv')) = '1/1'
      and pg_temp.t479_listed(pg_temp.t479_id('after/CKv/inv')) = '3/1'
      and pg_temp.t479_listed(pg_temp.t479_id('after/RWp/inv')) is null,
    'Q after 479: RW ' || coalesce(pg_temp.t479_listed(pg_temp.t479_id('after/RW/inv')), '-')
    || ', CKv ' || coalesce(pg_temp.t479_listed(pg_temp.t479_id('after/CKv/inv')), '-'));
  raise notice 'PASS Q (after 479): a session refunded by line while it waits is listed under 1 (its rows and refunds since the reopening add up), sessions left with their holder by ''keep'' under 3; a settled one not at all';
end $$;

-- ===== P. Probes =====
-- P1 Each of the three beside 479's parts is exactly as before: its text
-- with each of 479's parts replaced by what was there before gives its
-- BEFORE md5.
do $$
declare m record; w record; d text;
begin
  for m in select * from t479_md5 loop
    d := pg_get_functiondef(to_regprocedure('public.' || m.sig));
    for w in select * from t479_wb where sig = m.sig order by n loop
      perform pg_temp.t479_check((length(d) - length(replace(d, w.new, ''))) / length(w.new) = 1,
        'P1 ' || m.sig || ': part ' || w.n || ' is not there once');
      d := replace(d, w.new, w.old);
    end loop;
    perform pg_temp.t479_check(md5(d) = m.before, 'P1 ' || m.sig || ' worked back is ' || md5(d) || ', not its BEFORE ' || m.before);
  end loop;
  raise notice 'PASS P1: each of the three, its 479 parts put back, is exactly its BEFORE (the refund with nothing waiting, the correction''s replace path, the cancellation branch); the refund options not changed';
end $$;
-- P2 What 479 records: the refund's Audit Log row ('reopen_session_refunded'),
-- the change's ('reopen_sessions_follow_holder', a 'reassign' event of 0) and
-- the row a change with no choice writes (460's, listing the sessions); the
-- reinstatements, one 'reopen' event per row under its reopening's request.
do $$
declare inv uuid; s uuid;
begin
  inv := pg_temp.t479_id('after/RW/inv');
  select id into s from customer_therapy_sessions where invoice_id = inv and is_current;
  perform pg_temp.t479_check((select count(*) from audit_logs a where a.record_id = inv and a.action = 'reopen_session_refunded') = 1
      and (select (a.new_data->>'refunded_units')::int from audit_logs a where a.record_id = inv and a.action = 'reopen_session_refunded') = 1
      and (select (a.new_data->>'still_waiting')::int from audit_logs a where a.record_id = inv and a.action = 'reopen_session_refunded') = 2
      and (select (a.old_data->>'quantity')::int from audit_logs a where a.record_id = inv and a.action = 'reopen_session_refunded') = 3
      and (select count(*) from invoice_therapy_session_events e where e.session_id = s and e.event_kind = 'refund') = 2,
    'P2 RW: the refund while it waited is not recorded as tested');
  inv := pg_temp.t479_id('after/CTw/inv');
  select id into s from customer_therapy_sessions where invoice_id = inv and is_current;
  perform pg_temp.t479_check((select count(*) from audit_logs a where a.record_id = inv and a.action = 'reopen_sessions_follow_holder'
                               and a.new_data->>'customer_id' = pg_temp.t479_id('after/CTw/B')::text
                               and a.old_data->>'customer_id' = pg_temp.t479_id('after/CTw/A')::text) = 1
      and (select count(*) from invoice_therapy_session_events e where e.session_id = s and e.event_kind = 'reassign' and e.quantity = 0) = 1
      and (select count(*) from audit_logs a where a.record_id = inv and a.action = 'invoice_benefits_followed_reassignment'
             and a.new_data->>'to_customer' = pg_temp.t479_id('after/CTw/B')::text and a.new_data->'therapy_sessions' = jsonb_build_array(s)) = 1,
    'P2 CTw: the customer change while it waited is not recorded as tested');
  inv := pg_temp.t479_id('after/CKv/inv');
  perform pg_temp.t479_check(not exists (select 1 from audit_logs a where a.record_id = inv
                                           and a.action in ('reopen_sessions_follow_holder', 'invoice_benefits_followed_reassignment')),
    'P2 CKv: ''keep'' recorded a move');
  inv := pg_temp.t479_id('after/RWc/inv');
  select id into s from customer_therapy_sessions where invoice_id = inv and is_current;
  perform pg_temp.t479_check((select array_agg(e.quantity order by e.quantity desc) from invoice_therapy_session_events e
                                where e.session_id = s and e.event_kind = 'reopen') = '{2,1}'::int[]
      and (select count(distinct e.request_id) from invoice_therapy_session_events e where e.session_id = s and e.event_kind = 'reopen') = 2
      and not exists (select 1 from invoice_therapy_session_events e where e.session_id = s and e.event_kind = 'reopen'
                       and e.request_id not in (select r.request_id from invoice_revisions r where r.invoice_id = inv and r.snapshot ? 'reopen_preview')),
    'P2 RWc: the reinstatements are not one event per row under each reopening''s request');
  raise notice 'PASS P2: a refund while a session waits writes its Audit Log row (the row as it was, 1 refunded, 2 still waiting) and its event; a customer change moves the session with an event and an Audit Log row, and writes 460''s row (the sessions listed) where no choice is asked; ''keep'' records no move; the payment reinstates each row once, under its reopening''s request';
end $$;
-- P4 The Finance panel's refund options (the guided plans read them; not
-- changed by 479, the Owner, 29 Oct 2026) for a session that waits count as
-- refunded all it shows as refunded: after RW's refund while it waits, 1
-- unused up to S$20 (the S$20 held); refunded in full before the reopening
-- and S$20 paid since, 0 up to S$0 (the line's own "up to" S$60); the
-- Owner's case, after its Refund in full, 0 up to S$0. Settled (RWp): 2 up
-- to S$40.
do $$
declare o jsonb;
begin
  perform pg_temp.t479_run('after', 'OPa', 'sale A th; cancel; backt 1 20; reopen; backt 1 20');
  o := (select x from jsonb_array_elements(invoice_refund_options(pg_temp.t479_id('after/OPa/inv'))->'therapy_sessions') x limit 1);
  perform pg_temp.t479_check((o->>'unused')::int = 1 and (o->>'max_refund')::numeric = 20 and (o->>'used')::int = 0, 'P4 OPa: ' || o::text);
  perform pg_temp.t479_run('after', 'OPb', 'sale A th; refundall; reopen; payamt 20');
  o := (select x from jsonb_array_elements(invoice_refund_options(pg_temp.t479_id('after/OPb/inv'))->'therapy_sessions') x limit 1);
  perform pg_temp.t479_check((o->>'unused')::int = 0 and (o->>'max_refund')::numeric = 0
      and (select (l->>'remaining')::numeric from jsonb_array_elements(invoice_refund_options(pg_temp.t479_id('after/OPb/inv'))->'lines') l) = 60,
    'P4 OPb: ' || o::text);
  o := (select x from jsonb_array_elements(invoice_refund_options(pg_temp.t479_id('after/OWa/inv'))->'therapy_sessions') x limit 1);
  perform pg_temp.t479_check((o->>'unused')::int = 0 and (o->>'max_refund')::numeric = 0, 'P4 OWa: ' || o::text);
  o := (select x from jsonb_array_elements(invoice_refund_options(pg_temp.t479_id('after/RWp/inv'))->'therapy_sessions') x limit 1);
  perform pg_temp.t479_check((o->>'unused')::int = 2 and (o->>'max_refund')::numeric = 40, 'P4 RWp: ' || o::text);
  raise notice 'PASS P4: the refund options of a session that waits are as before 479: they count all it shows as refunded (1 unused up to S$20 after a refund while it waits; 0 up to S$0 after a Refund in full before the reopening and S$20 paid since, and in the Owner''s case); settled, 2 up to S$40';
end $$;
-- P3 Nothing added or dropped; the grants as before.
do $$ begin
  perform pg_temp.t479_check(split_part(pg_temp.t479_fingerprint(), ' ', 2) = split_part((select fp from t479_fp where k = 'start'), ' ', 2)
      and pg_temp.t479_grants() = (select fp from t479_fp where k = 'grants'),
    'P3 the functions or grants changed: ' || pg_temp.t479_fingerprint());
  raise notice 'PASS P3: no function added or dropped; the grant list as before';
end $$;

-- ===== K. KNOWN (479's NOT COVERED), checked as they are =====
do $$
declare o jsonb;
begin
  -- K1 (NOT COVERED 1): the guided Refund in full of a reopened invoice
  -- still waiting pays back the money its plan offers and takes those
  -- sessions off the queue, but leaves the invoice part-paid for the rest
  -- (GR: S$20, 1 session waits; KG45: S$15, the S$5 kept; TV before its
  -- payment), as for credit and vouchers since 446.
  o := (select v from t479_res where phase = 'after' and k = 'GR');
  perform pg_temp.t479_check(o->>'status' = 'partially_paid' and (o->>'net')::numeric = 0 and (o->>'squeued')::int = 1,
    'K1: look at NOT COVERED 1 again: ' || o::text);
  o := (select v from t479_res where phase = 'after' and k = 'KG45');
  perform pg_temp.t479_check(o->>'status' = 'partially_paid' and (o->>'net')::numeric = 5 and (o->>'squeued')::int = 1,
    'K1 (KG45): look at NOT COVERED 1 again: ' || o::text);
  o := pg_temp.t479_run('K', 'TVr', 'sale A th,v; cancel; backt 2 20; reopen; refundall');
  perform pg_temp.t479_check(o->>'status' = 'partially_paid' and (o->>'net')::numeric = 0 and (o->>'squeued')::int = 1 and o->>'error' is null,
    'K1 (TV): look at NOT COVERED 1 again: ' || o::text);
  o := pg_temp.t479_run('K', 'VRF1', 'sale A v; cancel; backv 1 1; reopen; refundall');
  perform pg_temp.t479_check(o->>'status' = 'partially_paid' and (o->>'net')::numeric = 0 and o->>'error' is null,
    'K1 (vouchers, since 446): ' || o::text);
  -- K1 (NOT COVERED 1, a product line; not 479's; the Owner, 29 Oct 2026
  -- ~18:45 SGT, "Fix it separately": 481): the payment that settles the
  -- invoice takes the product from stock again though its line was refunded
  -- (a second store_sale), and no stock report flags it
  -- (invoice_stock_to_deduct: nothing; invoice_stock_gaps: nothing): with
  -- 479's guided Refund in full (PRn1, PRn2: 1 of 3 and the product for
  -- S$20), and before 479 already (VPR, PRxk, PRpp; A compared them with
  -- before 479, every key).
  -- (481, where it is in: the product not taken again: its first sale and
  -- the Cancel's return alone, PRpp no sale.)
  perform pg_temp.t479_check((select count(*) from t479_res where phase = 'after' and k in ('PRn1', 'PRn2', 'VPR', 'PRxk')
                               and v->>'stock' = (case when pg_temp.t479_481_in() then 'invoice_cancel_return 1, store_sale 1'
                                                       else 'invoice_cancel_return 1, store_sale 2' end) and v->>'status' = 'paid') = 4
      and (select v->>'stock' from t479_res where phase = 'after' and k = 'PRpp') = (case when pg_temp.t479_481_in() then '-' else 'store_sale 1' end)
      and (select (v->>'net')::numeric from t479_res where phase = 'after' and k = 'PRn1') = 20
      and not exists (select 1 from invoice_stock_to_deduct(pg_temp.t479_id('after/PRn1/inv')) d where d.quantity > 0)
      and not exists (select 1 from invoice_stock_gaps((select invoice_no from invoices where id = pg_temp.t479_id('after/PRn1/inv')))),
    'K1 (a product line): look at NOT COVERED 1 again');
  -- K2 (NOT COVERED 2): a customer change of a paid invoice gives the new
  -- customer the line's sessions as new, a refunded one coming back.
  o := (select v from t479_res where phase = 'after' and k = 'PRT');
  perform pg_temp.t479_check(o->>'sess' = '3/3 r0 c0 available' and (o->>'net')::numeric = 40 and o->>'sholder' = 'B',
    'K2: look at NOT COVERED 2 again: ' || o::text);
  -- K3 (NOT COVERED 3): sessions 'keep' left with A: a later correction
  -- moving the invoice to a third customer is refused.
  o := (select v from t479_res where phase = 'after' and k = 'KK1');
  perform pg_temp.t479_check(o->>'error' like 'change C keep: These therapy sessions were left with %' and o->>'sholder' = 'A',
    'K3: look at NOT COVERED 3 again: ' || o::text);
  -- K3, while they still wait: the move to C goes through, the sessions
  -- following 460's rule ('keep': A; 'transfer': C, CKT); a change of the
  -- line's quantity is refused as for any waiting session.
  perform pg_temp.t479_check((select v->>'error' is null and v->>'sholder' = 'A' and v->>'icust' = 'C' from t479_res where phase = 'after' and k = 'CKK')
      and (select v->>'error' is null and v->>'sholder' = 'C' and v->>'icust' = 'C' from t479_res where phase = 'after' and k = 'CKT')
      and (select v->>'error' like 'qty 2: Settle the pending session reopening before changing its allocation%' from t479_res where phase = 'after' and k = 'CKq'),
    'K3 (while they wait): look at NOT COVERED 3 again');
  -- K7 (NOT COVERED 7): a session queued twice before 475: its refund and a
  -- customer change now refused as its evidence; a waiting row lowered by
  -- hand, reopened again and paid: settled.
  perform pg_temp.t479_check((select v->>'error' from t479_res where phase = 'after' and k = 'Kdup')
                               like 'backt 1 20: Therapy session reopening changed; reload its original evidence%'
      and (select v->>'error' from t479_res where phase = 'after' and k = 'Kdupc')
                               like 'change B: Therapy session reopening changed; reload its original evidence%'
      and (select v->>'status' from t479_res where phase = 'after' and k = 'Kshr') = 'paid',
    'K7: look at NOT COVERED 7 again');
  raise notice 'KNOWN K: (479''s NOT COVERED) (1) the guided Refund in full while a session waits leaves the invoice part-paid for the rest (GR, KG45, TV; as for vouchers and credit since 446); with a product line the settling payment takes the product from stock again though its line was refunded, and no stock report flags it (not 479''s: VPR, PRxk, PRpp before 479 already; 479''s Refund in full adds PRn1, PRn2: 1 of 3 and the product for S$20; 481''s, the Owner, 29 Oct 2026); (2) a customer change of a paid invoice gives the new customer the line''s sessions as new (a refunded one comes back); (3) sessions ''keep'' left with their holder: once paid, a correction moving the invoice to a third customer, or changing their line or store, is refused (KK1); while they wait, the move goes through, the sessions following 460''s rule (CKK: A; CKT: C), and a line change is refused as for any waiting session (CKq); (7) a session queued twice before 475: its refund and a customer change refused as its evidence (Kdup, Kdupc); a row lowered by hand and topped up by a later reopening: settled%',
    case when pg_temp.t479_481_in() then ' (481 is in: the product of (1) is not taken again, its first sale and the Cancel''s return alone; PRpp no sale)' else '' end;
end $$;
-- K10 (NOT COVERED 10; the Owner, 29 Oct 2026 ~18:45 SGT, "Keep today's
-- refusal"): where a plan offers more than the money held,
-- invoice_action_plan cuts it to the money held line by line in the order
-- the refund options list the lines (not fixed). The plans offer what each
-- line holds from before the reopening (the refund options, as they are),
-- so this is where a line's money was paid back before the reopening
-- without a refund by line the options count (sessions or vouchers paid
-- back with no line; a product line, by line or with no line) and part of
-- it was paid again. With only the therapy line: where the cut is not
-- whole units the approval refuses the plan, before 479 and after it (S$30
-- on 3 sessions at S$20: KGn, KGnc), and where it is it goes through with
-- 479 (KGn40, as answer F asked: no other item to choose between). With a
-- voucher line and S$50 paid (TVn): the S$50 on the line listed first,
-- refused by the sessions' rule or the vouchers' (the same before 479).
-- The cases of t479_ocases (below): with another line to refund, refused as
-- before 479 wherever the cut gives the waiting sessions some of the money,
-- and as before 479 where it gives them nothing.
do $$
declare o jsonb; pl jsonb; inv uuid; v_first text;
begin
  perform pg_temp.t479_check((select v->>'error' from t479_res where phase = 'after' and k = 'KGn')
        like 'refundall: Refund whole unused therapy sessions at their original paid value; 3 of 3 sessions remain refundable%'
      and (select v->>'error' from t479_res where phase = 'after' and k = 'KGnc')
        like 'guidedcancel: Refund whole unused therapy sessions at their original paid value; 3 of 3 sessions remain refundable%'
      and (select (v->>'net')::numeric from t479_res where phase = 'after' and k = 'KGn') = 30
      and (select v->>'error' from t479_res where phase = 'after' and k = 'KGn40') is null,
    'K10 KGn, KGnc, KGn40: look at NOT COVERED 10 again');
  inv := pg_temp.t479_id('after/TVn/inv');
  pl := invoice_action_plan(inv, 'refund_full', '[]');
  -- The line the plan listed first when the case ran (its outcome's plan,
  -- read just before the approval): read again now, the plan may list the
  -- lines in another order (the order is not fixed).
  v_first := pg_temp.t479_first((select v from t479_res where phase = 'after' and k = 'TVn'));
  perform pg_temp.t479_check((pl->>'refund_amount')::numeric = 50 and jsonb_array_length(pl->'lines') = 2
      and (pl->'lines'->0->>'amount')::numeric = 50 and (pl->'lines'->1->>'amount')::numeric = 0
      and v_first in ('therapy', 'voucher'),
    'K10 TVn: the plan is not cut line by line in the options'' order: ' || (pl->'lines')::text);
  o := (select v from t479_res where phase = 'after' and k = 'TVn');
  perform pg_temp.t479_check(o->>'error' like case when v_first = 'therapy'
                                 then 'refundall: Refund whole unused therapy sessions at their original paid value; 3 of 3 sessions remain refundable%'
                                 else 'refundall: Voucher refund must cover whole unused units at their allocated paid value%' end
      and (o->>'net')::numeric = 50 and coalesce(o->>'invariants', '') = '',
    'K10 TVn (the ' || v_first || ' line first): ' || o::text);
  raise notice 'KNOWN K10: (479''s NOT COVERED 10) while a session waits the guided Refund in full and Cancel are refused where their plan, cut to the money held, is not whole units: paid back with no line, reopened, S$30 paid on 3 sessions at S$20 (KGn, KGnc: "Refund whole unused therapy sessions ..."); with a voucher line and S$50 paid (TVn): the plan gives the first line listed the S$50, here the % line, so refused (%); the same before 479; with only the therapy line and S$40 paid, 2 whole sessions, it goes through (KGn40, as answer F asked)',
    v_first, case when v_first = 'therapy' then '"Refund whole unused therapy sessions ..."' else '"Voucher refund must cover whole unused units ..."' end;
end $$;
-- K10 (and K17), the cut plans: each case of t479_ocases after 479, as
-- expected for the line its plan lists first; where R ran and listed the
-- same lines in the same order (the plan the same), exactly as before 479,
-- every key.
do $$
declare c record; e record; o jsonb; b jsonb; res text := ''; n int := 0; v_firsts text;
begin
  for c in select * from t479_ocases order by ord loop
    o := pg_temp.t479_run('after', c.k, c.steps);
    select * into e from t479_oexp x where x.shape = c.shape and x.first in (pg_temp.t479_first(o), '*')
     order by x.first = '*' limit 1;
    perform pg_temp.t479_check(e.shape is not null and pg_temp.t479_meets(o, e.expect) and coalesce(o->>'invariants', '') = ''
        and coalesce((o->>'cancel_left')::numeric, 0) = 0,
      'K10 ' || c.k || ' (the ' || coalesce(pg_temp.t479_first(o), '?') || ' line first): '
      || coalesce(pg_temp.t479_diff(o, e.expect), 'no case expects it') || ' ' || o::text);
    b := (select v from t479_res where phase = 'before' and k = c.k);
    if b is not null and b->>'plan' is not distinct from o->>'plan' then
      perform pg_temp.t479_check(o = b, 'K10 ' || c.k || ' differs from before 479: ' || b::text || ' / ' || o::text);
      n := n + 1;
    end if;
    res := res || format(E'\n  %s (%s): %s, %s, net %s%s', c.k, o->>'plan', coalesce(o->>'error', o->>'status'), coalesce(o->>'sess', '-'),
      o->>'net', case when b is null then '' when b->>'plan' is distinct from o->>'plan' then ' (listed in another order before 479)'
                      else ' (the same before 479)' end);
  end loop;
  v_firsts := (select string_agg(format('%s: %s', z.shape, z.firsts), '; ' order by z.shape)
                 from (select oc.shape, string_agg(distinct pg_temp.t479_first(r.v), ' and ') as firsts
                         from t479_ocases oc join t479_res r on r.phase = 'after' and r.k = oc.k group by oc.shape) z);
  raise notice 'KNOWN K10: (479''s NOT COVERED 10 and 17) a guided plan cut to the money held that gives a waiting session some of it while another line has something to refund is refused as before 479 (the Owner, 29 Oct 2026, "Keep today''s refusal"); one that gives the sessions nothing goes through as before 479, which line it refunds following the order the refund options list the lines (not fixed: 478''s, not 479''s); its first line, by shape: %; % cases listed their lines in the same order before 479 and ended the same, every key; the cases:%', v_firsts, n, res;
end $$;
-- K14 (NOT COVERED 14): half a cent: the guided Refund in full and Cancel
-- refused, 1 session by line through, the last one not (S$20.00 for the
-- money, S$19.99 by the sessions' rule); the guided Cancel without "Record
-- refund paid", then "Record refund paid" with no line, pays it back; paid,
-- it settles.
do $$ begin
  perform pg_temp.t479_check((select v->>'error' from t479_res where phase = 'after' and k = 'KRd')
        like 'refundall: Refund whole unused therapy sessions at their original paid value; 4 of 4 sessions remain refundable%'
      and (select v->>'error' from t479_res where phase = 'after' and k = 'KRdc')
        like 'guidedcancel: Refund whole unused therapy sessions at their original paid value; 4 of 4 sessions remain refundable%'
      and (select v->>'status' from t479_res where phase = 'after' and k = 'KRdk') = 'cancelled'
      and (select (v->>'net')::numeric from t479_res where phase = 'after' and k = 'KRdk') = 0
      and (select v->>'error' from t479_res where phase = 'after' and k = 'KRd1') like 'backt 1 20: Refund exceeds net payments still held%'
      and (select (v->>'net')::numeric from t479_res where phase = 'after' and k = 'KRd1') = 19.99
      and (select v->>'error' from t479_res where phase = 'after' and k = 'KRd2')
        like 'backt 1 19.99: Refund whole unused therapy sessions at their original paid value; 3 of 4 sessions remain refundable%'
      and (select v->>'status' from t479_res where phase = 'after' and k = 'KRdp') = 'paid',
    'K14 KRd, KRd1, KRd2, KRdp: look at NOT COVERED 14 again');
  raise notice 'KNOWN K14: (479''s NOT COVERED 14) half a cent: 4 sessions paid S$79.99, 2 refunded by line while cancelled (S$40.00), reopened, S$39.99 held: the guided Refund in full and Cancel (S$39.99) are refused, as 479 values the 2 sessions refunded since the reopening at S$40.00; by line 1 session (S$20.00) goes through, and the last one, valued at S$20.00 with S$19.99 held, does not: S$20.00 is refused for the money (KRd1), S$19.99 by the sessions'' rule (KRd2); the guided Cancel without "Record refund paid" and "Record refund paid" with no line pay the S$39.99 back; paid, it settles (4 of 4 for S$79.99); before 479 the refunds were refused by 252';
end $$;
-- K15 (NOT COVERED 15; not 479's): money a Cancel leaves due on a reopened
-- invoice that issued credit cannot be recorded as paid back with no line;
-- only by line, the therapy line in whole sessions from 479 (before 479
-- none): the Owner's case, S$30 due (OWacR; S$20 by line, S$10 stays due,
-- OWac20R); 1 session refunded while cancelled, S$5 paid since (CPs5: the
-- guided Cancel, refused before 479, leaves S$5 due; CPs5k: the plain Cancel
-- and the package by line, S$45 due before 479, S$5 from 479); the Premium
-- Bundle (OWpbcR; one session by line clears its S$20 from 479, OWpbc20).
-- With vouchers instead "Record refund paid" with no line works (OWbcR),
-- and with only the therapy line (GRFk, KRdk).
do $$ begin
  perform pg_temp.t479_check((select count(*) from t479_res where phase = 'after' and k in ('OWacR', 'OWac20R', 'CPs5', 'CPs5k', 'OWpbcR')
                               and v->>'error' like 'refundpaid: Allocate a correction refund to the original unused purchased benefits; it cannot be cashed out as an unallocated overpayment%') = 5
      and (select (v->>'fdue')::numeric from t479_res where phase = 'after' and k = 'OWacR') = 30
      and (select (v->>'fdue')::numeric from t479_res where phase = 'after' and k = 'OWac20R') = 10
      and (select (v->>'fdue')::numeric from t479_res where phase = 'after' and k = 'CPs5') = 5
      and (select (v->>'fdue')::numeric from t479_res where phase = 'after' and k = 'CPs5k') = 5
      and (select v->>'error' is null and (v->>'net')::numeric = 0 from t479_res where phase = 'after' and k = 'OWpbc20')
      and (select v->>'error' is null and (v->>'net')::numeric = 0 from t479_res where phase = 'after' and k = 'OWbcR'),
    'K15 OWacR, OWac20R, CPs5, CPs5k, OWpbcR, OWpbc20, OWbcR: look at NOT COVERED 15 again');
  raise notice 'KNOWN K15: (479''s NOT COVERED 15; not 479''s) a Cancel''s money due on a reopened invoice that issued credit cannot be recorded with "Record refund paid" ("Allocate a correction refund to the original unused purchased benefits ..."): the Owner''s case S$30 (OWacR), S$10 after S$20 by line from 479 (OWac20R; before 479 the line takes none); S$5 after the guided Cancel that 479 lets through (CPs5) or after the plain Cancel and the package by line (CPs5k: S$45 before 479); the Premium Bundle''s S$20 (OWpbcR), cleared from 479 by one session by line (OWpbc20); with vouchers instead it is recorded (OWbcR)';
end $$;
-- K13 (NOT COVERED 13): sessions a refund paid back before the reopening,
-- money paid towards them since, the invoice selling only them: the guided
-- Refund in full finds nothing to refund and the guided Cancel no money to
-- return (GRF, GCF: as before 479, every key; the same for a Credit Package
-- and for vouchers, CRF, VRF); the S$20 stays held; its refund by line goes
-- through (RF) and so do the guided Cancel without "Record refund paid" and
-- "Record refund paid" with no line (GRFk); the Finance panel's sessions
-- note there reads 0 unused, up to S$0, the line's own "up to" S$60 (P4,
-- OPb).
do $$
declare o jsonb;
begin
  perform pg_temp.t479_check((select v->>'error' from t479_res where phase = 'after' and k = 'GRF') like 'refundall: There is nothing left to refund on this invoice%'
      and (select v->>'error' from t479_res where phase = 'after' and k = 'GCF') like 'guidedcancel: There is no money held on this invoice to return%'
      and (select v->>'error' from t479_res where phase = 'after' and k = 'CRF') like 'refundall: There is nothing left to refund on this invoice%'
      and (select v->>'error' from t479_res where phase = 'after' and k = 'VRF') like 'refundall: There is nothing left to refund on this invoice%'
      and (select (v->>'net')::numeric from t479_res where phase = 'after' and k = 'GRF') = 20,
    'K13 GRF, GCF, CRF, VRF: look at NOT COVERED 13 again');
  perform pg_temp.t479_check((select v->>'error' from t479_res where phase = 'after' and k = 'RF') is null
      and (select v->>'sess' from t479_res where phase = 'after' and k = 'RF') = '2/3 r1 c0 available'
      and (select v->>'error' from t479_res where phase = 'after' and k = 'GRFk') is null
      and (select v->>'sess' from t479_res where phase = 'after' and k = 'GRFk') = '3/3 r0 c0 available',
    'K13 RF, GRFk: look at NOT COVERED 13 again');
  raise notice 'KNOWN K13: (479''s NOT COVERED 13) refunded in full before the reopening, S$20 paid since, only the therapy line: the guided Refund in full finds nothing to refund and the guided Cancel no money to return, as before 479 and as for a Credit Package and for vouchers (GRF, GCF, CRF, VRF); the refund by line of the S$20 goes through (RF: paid, 2 of 3 for S$40), and so do the guided Cancel without "Record refund paid" and "Record refund paid" with no line (GRFk: reopened and paid, 3 of 3); the Finance panel''s sessions note there says 0 unused, up to S$0';
end $$;
-- K16 (NOT COVERED 16): a guided request approved after the invoice
-- changed (the approver confirming the plan as it reads then): with two
-- other lines, one of them holding vouchers, the plan not cut, refused as
-- before 479 (STvp: the plan the request saved no longer holds the money
-- held); with one other line it goes through (STv). Credit given back to the
-- package between the request and the approval (the review of 2 Nov 2026):
-- the plan carried out is cut and the one the request saved is not; refused
-- as before 479 whichever line is listed first (A1, AG, A1p, AN, A1x; AXV,
-- AVX with a voucher line too, 478's own message). From this build each of
-- them is refused at the session's turn, its product line (refunded by line
-- before the reopening) being offered again (NOT COVERED 17), so none of the
-- suite's cases reaches the check once every line is done with a cut plan;
-- the cases that reach it pass it (TVP, VTP, CTP, CFR, BFC: not cut).
-- The second fix review (3 Nov 2026): with two other lines, one holding
-- credit or vouchers, no other line offering anything at the session's turn
-- (the build before let it through there, so the outcome followed the line
-- order): refused as before 479 in every order the plans listed their lines
-- in (Y1 to Y4, V1 to V3); the Refund in full of V1's state, one other line
-- (V4, V5), and the same approvals with nothing changed between (Y1s, Y3s,
-- V1s) go through, as answer F asked.
-- The third fix review (3 Nov 2026): where only the sessions' line has
-- anything to refund, at their turn and in the plan the request saved (the
-- other lines listed at S$0), the approval goes through after the invoice
-- changed, whichever line is listed first, as answer F asked (Z8, Z8c, Z5r,
-- Z5x, Z6, KZ, Z1, Z2; with one S$0 line, Z9, Z0; nothing changed between,
-- Z8s); a credit line that gained credit between the request and the
-- approval is refused as before 479 in either order (ZG, ZGx: the check
-- once every line is done, or the saved plan), and goes through with
-- nothing else changed (ZGs, ZGsx).
-- Section A compares them with before 479, every key.
do $$
declare v_ord text; v_ord2 text; v_ord3 text;
begin
  perform pg_temp.t479_check((select v->>'error' from t479_res where phase = 'after' and k = 'STvp')
        like 'approve: Settle the reopened invoice before changing its queued sessions%'
      and (select (v->>'net')::numeric = 150 and (v->>'squeued')::int = 3 from t479_res where phase = 'after' and k = 'STvp')
      and (select v->>'error' is null and (v->>'net')::numeric = 10 and (v->>'squeued')::int = 1 from t479_res where phase = 'after' and k = 'STv'),
    'K16 STvp, STv: look at NOT COVERED 16 again');
  perform pg_temp.t479_check((select bool_and(r.v->>'error' like 'approve: Settle the reopened invoice before changing its queued sessions%'
                                              and (r.v->>'net')::numeric = case when r.k in ('AXV', 'AVX') then 240 else 180 end
                                              and (r.v->>'squeued')::int = 3) and count(*) = 7
                                from t479_res r where r.phase = 'after' and r.k in ('A1', 'AG', 'A1p', 'AN', 'A1x', 'AXV', 'AVX')),
    'K16 A1, AG, A1p, AN, A1x, AXV, AVX: look at NOT COVERED 16 again');
  perform pg_temp.t479_check((select bool_and(r.v->>'error' like 'approve: Settle the reopened invoice before changing its queued sessions%'
                                              and (r.v->>'net')::numeric = case when r.k like 'Y%' then 210 else 110 end
                                              and (r.v->>'squeued')::int = 3) and count(*) = 7
                                from t479_res r where r.phase = 'after' and r.k in ('Y1', 'Y2', 'Y3', 'Y4', 'V1', 'V2', 'V3'))
      and (select bool_and(r.v->>'error' is null and (r.v->>'squeued')::int = 1) and count(*) = 5
             from t479_res r where r.phase = 'after' and r.k in ('V4', 'V5', 'Y1s', 'Y3s', 'V1s')),
    'K16 Y1 to Y4, V1 to V5, Y1s, Y3s, V1s: look at NOT COVERED 16 again');
  perform pg_temp.t479_check((select bool_and(r.v->>'error' is null and (r.v->>'squeued')::int = 1
                                              and (r.v->>'net')::numeric = case r.k when 'Z6' then 15 when 'Z8s' then 0 when 'ZGs' then 0
                                                                                    when 'ZGsx' then 0 else 10 end) and count(*) = 13
                                from t479_res r where r.phase = 'after'
                                 and r.k in ('Z8', 'Z8c', 'Z5r', 'Z5x', 'Z6', 'KZ', 'Z1', 'Z2', 'Z9', 'Z0', 'Z8s', 'ZGs', 'ZGsx'))
      and (select bool_and(r.v->>'error' like 'approve: Settle the reopened invoice before changing its queued sessions%'
                           and (r.v->>'net')::numeric = 150 and (r.v->>'squeued')::int = 3) and count(*) = 2
             from t479_res r where r.phase = 'after' and r.k in ('ZG', 'ZGx')),
    'K16 Z8, Z8c, Z5r, Z5x, Z6, KZ, Z1, Z2, Z9, Z0, Z8s, ZG, ZGx, ZGs, ZGsx: look at NOT COVERED 16 again');
  v_ord := (select string_agg(format('%s (%s)', r.k, r.v->>'plan'), ', ' order by r.k) from t479_res r
             where r.phase = 'after' and r.k in ('A1', 'AG', 'A1p', 'AN', 'A1x', 'AXV', 'AVX'));
  v_ord2 := (select string_agg(format('%s (%s)', r.k, r.v->>'plan'), ', ' order by r.k) from t479_res r
              where r.phase = 'after' and r.k in ('Y1', 'Y2', 'Y3', 'Y4', 'V1', 'V2', 'V3'));
  v_ord3 := (select string_agg(format('%s (%s)', r.k, r.v->>'plan'), ', ' order by r.k) from t479_res r
              where r.phase = 'after' and r.k in ('Z8', 'Z8c', 'Z5r', 'Z5x', 'Z6', 'KZ', 'Z1', 'Z2', 'ZG', 'ZGx', 'ZGs', 'ZGsx'));
  raise notice 'KNOWN K16: (479''s NOT COVERED 16) a guided Refund in full requested, S$10 paid, then approved as its plan reads then (not cut): with a voucher line it goes through (STv: S$100 paid back, S$10 kept, 1 session waiting); with a voucher line and a product it is refused as before 479 ("Settle the reopened invoice ..."; STvp: S$150 held, 3 waiting), the plan the request saved no longer holding the money held. Credit given back to the package between the request and the approval, the plan carried out cut: refused as before 479, with 478''s message, at the session''s turn (the product''s line, refunded by line before the reopening, offered again: NOT COVERED 17), by the plans as they listed their lines here: %. With no other line offering anything at the session''s turn (a package and vouchers, or vouchers and a product refunded by line since the reopening, the guided Cancel listing it): refused as before 479 whichever line is listed first (S$210 or S$110 held, 3 waiting), by the plans as they listed their lines here: %; the Refund in full of that state (one other line: V4, V5) and the same approvals with nothing changed between (Y1s, Y3s, V1s) go through. Where only the sessions'' line has anything to refund, at their turn and in the plan the request saved (the other lines listed at S$0: a credit or voucher line refunded by line before the reopening, a product line refunded by line since it), approved after S$10 was paid (or Correct payment): through, as answer F asked, whichever line is listed first (Z8, Z5r, Z5x, KZ: S$40 paid back, S$10 kept, 1 waiting; Z6: S$15 kept; Z8c, Z1, Z2, the guided Cancel: cancelled, S$10 shown due); a credit line given credit back between the request and the approval: refused as before 479 in either order (ZG, ZGx), through with nothing else changed (ZGs, ZGsx); by the plans as they listed their lines here: %', v_ord, v_ord2, v_ord3;
end $$;
-- K17 (NOT COVERED 17, open for the Owner): a product line refunded before
-- the reopening (by line or paid back with no line) is offered again by the
-- guided flows (the reopening charges it again; the refund options count
-- its refunds since the reopening). Where the plan reaches a waiting
-- session, refused as before 479, whichever line is listed first (AC, AGC,
-- ACp, AXV, AVX, TPr, PTr; and the cut plans of K10; section A compares them
-- with before 479, every key); so too where the product was charged and paid
-- again since (TP2c: nothing would be refunded twice). Where it does not
-- (478's own, the same before 479): its line is refunded a second time
-- wherever the plan gives it money: S$80 on the S$40 line (P3, the sessions
-- offering nothing; P1a, P4a, P5a where their plan listed the product first;
-- P1b, P5b the voucher line first: S$10 more; ACnC, AGCnC with no sessions,
-- S1, a S$20 session paid from the package's credit, kept for S$0 with all
-- the money paid back), and the payment that settles the invoice takes the
-- product from stock again (NOT COVERED 1; 481).
do $$
declare v_p3 numeric; v_p1 text; v_nc text;
begin
  v_p3 := (select sum((e->>'amount')::numeric) from invoice_refunds r, jsonb_array_elements(coalesce(r.outcome->'lines', '[]')) e
            where r.invoice_id = pg_temp.t479_id('after/P3/inv')
              and e->>'invoice_item_id' = (select it.id::text from invoice_items it where it.invoice_id = pg_temp.t479_id('after/P3/inv') and it.line_kind::text = 'product'));
  v_p1 := (select string_agg(format('%s %s', z.k, z.amt), ', ' order by z.k)
             from (select r0.k, (select sum((e->>'amount')::numeric) from invoice_refunds r, jsonb_array_elements(coalesce(r.outcome->'lines', '[]')) e
                                  where r.invoice_id = pg_temp.t479_id('after/' || r0.k || '/inv')
                                    and e->>'invoice_item_id' = (select it.id::text from invoice_items it
                                                                  where it.invoice_id = pg_temp.t479_id('after/' || r0.k || '/inv') and it.line_kind::text = 'product')) as amt
                     from t479_res r0 where r0.phase = 'after' and r0.k in ('P1a', 'P1b', 'P4a', 'P4b', 'P5a', 'P5b', 'ACnC', 'AGCnC', 'AC', 'AGC', 'TPr', 'PTr')) z);
  perform pg_temp.t479_check(v_p3 = 80
      and (select v->>'stock' = (case when pg_temp.t479_481_in() then 'invoice_cancel_return 1, store_sale 1' else 'invoice_cancel_return 1, store_sale 2' end)
                  and v->>'error' is null from t479_res where phase = 'after' and k = 'P3'),
    'K17 P3: look at NOT COVERED 17 again (the product line refunded S$' || coalesce(v_p3::text, '-') || ')');
  -- ACnC, AGCnC: all the S$160 paid back (the product's line S$80 in all), S1
  -- still available; ACnC part-paid with S$20 outstanding, AGCnC cancelled.
  perform pg_temp.t479_check((select bool_and(v->>'error' is null and (v->>'net')::numeric = 0) and count(*) = 2
                                from t479_res where phase = 'after' and k in ('ACnC', 'AGCnC'))
      and (select v->>'status' from t479_res where phase = 'after' and k = 'ACnC') = 'partially_paid'
      and (invoice_financial_position(pg_temp.t479_id('after/ACnC/inv'))->>'outstanding')::numeric = 20
      and (select v->>'status' from t479_res where phase = 'after' and k = 'AGCnC') = 'cancelled'
      and (select count(*) from customer_therapy_sessions s where s.invoice_id in (pg_temp.t479_id('after/ACnC/S1'), pg_temp.t479_id('after/AGCnC/S1'))
             and s.is_current and s.status = 'available' and s.quantity_purchased - s.quantity_used - s.quantity_refunded - s.quantity_cancelled = 1) = 2,
    'K17 ACnC, AGCnC: look at NOT COVERED 17 again');
  -- Where the plan reaches a waiting session, the product's line is not
  -- refunded again (only its refund by line before the reopening: S$40).
  perform pg_temp.t479_check(
      (select bool_and(coalesce((select sum((e->>'amount')::numeric) from invoice_refunds r, jsonb_array_elements(coalesce(r.outcome->'lines', '[]')) e
                                  where r.invoice_id = pg_temp.t479_id('after/' || r0.k || '/inv')
                                    and e->>'invoice_item_id' = (select it.id::text from invoice_items it
                                                                  where it.invoice_id = pg_temp.t479_id('after/' || r0.k || '/inv') and it.line_kind::text = 'product')), 0) = 40)
              and count(*) = 7
         from t479_res r0 where r0.phase = 'after' and r0.k in ('AC', 'AGC', 'ACp', 'AXV', 'AVX', 'TPr', 'PTr'))
      and (select v->>'error' like 'refundall: Settle the reopened invoice before changing its queued sessions%' from t479_res where phase = 'after' and k = 'TP2c'),
    'K17 AC, AGC, ACp, AXV, AVX, TPr, PTr, TP2c: look at NOT COVERED 17 again');
  raise notice 'KNOWN K17: (479''s NOT COVERED 17, open for the Owner) a product line refunded before the reopening is offered again by the guided flows; where the plan reaches a waiting session it is refused as before 479, whichever line is listed first (AC, AGC, ACp, AXV, AVX, TPr, PTr: the product''s line refunded S$40 in all, by line before the reopening; and TP2c, the product charged and paid again since, refused too); where it does not, as before 479, its line is refunded a second time: S$% on the S$40 line in P3 (the sessions offer nothing there); the product line''s refunds in all, by case: %; ACnC and AGCnC (no sessions): all S$160 back, S1 (a S$20 session paid from the package''s credit) kept, ACnC part-paid with S$20 outstanding; the payment that settles the invoice then takes the product from stock again (P3, P1, P4a, P5: a second store_sale; NOT COVERED 1, 481)%', v_p3, v_p1,
    case when pg_temp.t479_481_in() then ' (481 is in: not taken again where the product''s line was refunded in full since the reopening)' else '' end;
end $$;

rollback;
