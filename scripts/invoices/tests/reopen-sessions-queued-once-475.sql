-- 475: a therapy session an earlier reopening queued, still waiting because
-- the invoice was cancelled again before it was settled, is not queued again
-- by the next reopening, so the payment that settles the invoice reinstates
-- it once instead of being refused (474's NOT COVERED 1, its suite's KNOWN
-- K1, THq; the Owner, 27 Oct 2026: "Yes, fix it next").
-- supabase/475_reopen_sessions_queued_once.sql (after 474).
--
-- Every step goes through the app's own calls (474's suite harness, its
-- steps and readings, renamed): the invoice form (create_invoice_with_
-- details) and the Pay dialog (record_invoice_settlement), Record Payment,
-- Correct payment (correct_invoice_payment), Cancel, Reopen, the Finance
-- panel's refund by line (of credit, of voucher
-- units: 'backv', of a therapy line's sessions by money: 'backt') and
-- "Record refund paid" (refund_invoice_recorded), the guided Refund in full
-- and Cancel, the invoice form's customer change (correct_invoice,
-- 'transfer' or 'keep'), a customer merge. Before each Reopen the Reopen
-- dialog is read as the Finance panel reads it (invoice_reopen_preview:
-- every figure it shows, InvoiceFinancePanel.tsx), and after each step what
-- the reopening queued and what the payment that settles it gave back
-- (sessions reinstated, trg_create_therapy_sessions_on_paid; credit, the
-- 'Reopened invoice settled' rows; voucher units given again). Each app
-- call is followed by what its commit does (462's trigger on the ledger is
-- DEFERRABLE INITIALLY DEFERRED and this suite is one transaction: SET
-- CONSTRAINTS ... IMMEDIATE, then DEFERRED). Two steps are made by hand, as
-- no function makes them today: 'dup' (a second waiting row for each
-- waiting session, as a reopening queued it before 475) and 'shrink' (a
-- waiting row one less than its session shows).
--
-- The cases (A the buyer; B a later customer; K a record a merge keeps; th
-- a therapy line of 3 sessions at S$20, paid S$60; cp the S$100 Credit
-- Package, pbv the S$140 Premium Bundle with 2 vouchers, v a voucher line
-- of 2 units at S$30; S1 a S$20 session paid from the package's credit).
-- What a case reads: 'dlgs' the dialog's sessions at its last Reopen,
-- 'queueds' what that Reopen left waiting (or reinstated at once), 'gaves'
-- what was reinstated from it to the end; 'dlg'/'queued'/'gave' and
-- 'dlgv'/'queuedv'/'gavev' the same for credit and voucher units;
-- 'required' the payment required to settle again; 'sess' each current
-- session (available/purchased, refunded, cancelled, status), 'swait' and
-- 'squeued' the waiting rows and what they hold, 'stwice' the sessions
-- waiting on more than one row, 'sev' the 'reopen' events (reinstatements),
-- 'sholder' who holds the sessions, 'sinv' what is wrong with them; 'every'
-- each Reopen whose dialog said other than what it queued:
--   THq, THq3   474's K1: cancelled, S$20 refunded by line, reopened (it
--               waits), cancelled again, reopened, paid; a third reopening.
--   TH2c, THall S$40, or all S$60, refunded by line first.
--   THr         refunded in full first (sessions refunded, not cancelled).
--   THrp, THgk  "Record refund paid" (no line) once cancelled again; the
--               guided Cancel with it not ticked, the second time.
--   THmg, THmgc the buyer merged into K while it waited; once cancelled again.
--   THcpw, THpb, THmix, THvs  beside a Credit Package (its credit refunded by
--               line, the sessions only cancelled), the Premium Bundle, a
--               package with a session paid from it and a voucher line, a
--               voucher line with a unit refunded.
--   THq2p       settled once through two reopenings, then the same again.
--   THpd, THfix THq settled by the Pay dialog (record_invoice_settlement),
--               or by Correct payment (correct_invoice_payment: a S$5
--               payment corrected to S$20) instead of Record Payment.
--   Controls (the same with and without 475): TH0, THcp0 (a first reopening
--   paid), THc, THcc (reopened straight to paid; twice), THr1, THgc1
--   (refunded in full, the guided Cancel, then reopened and paid), K5 and VQ
--   (474's credit and voucher cases, no therapy line).
--   Known (475's NOT COVERED, the same with and without 475): THw, THb, THgc,
--   THrf (a session's refund by line, the guided Cancel with the money
--   recorded and Refund in full, while it waits or once cancelled again:
--   refused), THchw, THchc, THchk (a customer change: refused).
-- In every case 462's invariants (474's reading of them), the sessions'
-- own (one waiting row per session, of what it shows; nothing waits once
-- settled; held by the invoice's customer) and Cancel (tried, undone)
-- taking all of the invoice's credit back from whoever holds it.
--
--   S. Where it starts: 462, 463, 470 to 474 in; 475 in (nomig) or not,
--      reopen_invoice at 458's AFTER.
--   R. Without 475 (skipped with -v nomig=1), undone: each 'fixed' case's
--      payment refused ("Therapy session reopening changed"), the session
--      queued twice (or three times) while the dialog said 3; each control
--      and known case as expected; and each fixed case up to its payment.
--   Q. The read-only query in 475's header (the same text), on states made
--      for it and the R states: what it lists, by reason (1 to 3).
--   9. Refusals, each changing nothing: reopen_invoice neither 458's nor
--      475's; a function it relies on not as tested; an overload of its
--      name; a new caller of it; a new reader or writer of the session
--      queue; a new writer of the sessions; the settlement trigger not as
--      read; the queue's unique key gone; other grants. The same grants in
--      another order do not stop it.
--   M. Begun before 475 (cancelled again with a session waiting; waiting;
--      queued twice), finished after it.
--  10. 475 installed twice: as tested, the second run changing nothing,
--      nothing added, the grants as before.
--   A. Each case after 475: paid, each session reinstated once, the
--      dialog's count what was queued and reinstated; for a fixed case
--      everything up to its payment exactly as before 475 but the queue;
--      controls and known cases exactly as before 475.
--   P. Probes: reopen_invoice's text beside the sessions step exactly 458's
--      (worked back, by md5); what a reopening records (its revision's
--      snapshot, its Audit Log row); the one reinstatement and its request;
--      nothing added; the grants.
--   K. KNOWN (475's NOT COVERED), checked as they are: 1 (THw, THb, THgc,
--      THrf), 2 (THchw, THchc, THchk), 3 (a session queued twice before 475:
--      'dup'), 4 (a waiting row no longer what its session shows: 'shrink').
--
-- Run on a copy of production as it is (474 in, 27 Oct 2026: c1940191, 1387
-- functions):
--   psql -X -v ON_ERROR_STOP=1 -f scripts/invoices/tests/reopen-sessions-queued-once-475.sql
-- It installs 475 itself (twice) inside its transaction. Where 475 is in
-- already, add -v nomig=1 (S checks it as tested; R, Q, 9 and M are skipped;
-- every case after 475 is still checked). Section 9 lets the install fail on
-- purpose (psql prints its ERROR); the suite then checks that message.
-- Disposable database only; everything is rolled back. Every name, code and
-- amount is invented (@example.com); the phones are numbers kept for fiction
-- (ACMA, +61491570000 to +61491570999).
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '10s';
set local statement_timeout = '900s';

-- ── Set-up and the app's calls (474's suite harness, for 475) ────────────────
create temp table t475(k text primary key, id uuid);
create temp table t475_res(phase text, k text, v jsonb, primary key (phase, k));
create temp table t475_fp(k text primary key, fp text);
create temp sequence t475_phone;
create function pg_temp.t475_id(p_k text) returns uuid language sql as $f$ select id from t475 where k = p_k $f$;
create function pg_temp.t475_put(p_k text, p_id uuid) returns uuid language sql as $f$
  insert into t475 values (p_k, p_id) on conflict (k) do update set id = excluded.id returning id $f$;
create function pg_temp.t475_check(p_ok boolean, p_label text) returns void language plpgsql as $f$
begin
  if not coalesce(p_ok, false) then raise exception 'FAIL %', p_label; end if;
end $f$;
create function pg_temp.t475_fingerprint() returns text language sql as $f$
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.oid::regprocedure::text)) || ' ' || count(*)
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prokind in ('f', 'p') $f$;
create function pg_temp.t475_463_in() returns boolean language sql as $f$
  select to_regprocedure('public.invoice_benefit_moved_to_other(uuid)') is not null $f$;
create function pg_temp.t475_462_in() returns boolean language sql as $f$
  select to_regprocedure('public.credit_given_back_follows(uuid)') is not null
     and exists (select 1 from pg_trigger where tgname = 'credit_given_back_follows'
                  and tgrelid = 'public.customer_credit_ledger'::regclass) $f$;
create function pg_temp.t475_470_in() returns boolean language sql as $f$
  select to_regprocedure('public.credit_given_back_follows(uuid)') is not null
     and position('-- 470 (the Owner, 24 Oct 2026' in pg_get_functiondef('public.credit_given_back_follows(uuid)'::regprocedure)) > 0 $f$;
create function pg_temp.t475_471_in() returns boolean language sql as $f$
  select to_regprocedure('public.credit_given_back_follows(uuid)') is not null
     and position('-- 471 (the Owner, 26 Oct 2026' in pg_get_functiondef('public.credit_given_back_follows(uuid)'::regprocedure)) > 0 $f$;
create function pg_temp.t475_472_in() returns boolean language sql as $f$
  select to_regprocedure('public.credit_given_back_follows(uuid)') is not null
     and position('-- 472 (the Owner, 26 Oct 2026' in pg_get_functiondef('public.credit_given_back_follows(uuid)'::regprocedure)) > 0 $f$;
create function pg_temp.t475_473_in() returns boolean language sql as $f$
  select position('-- 473 (the Owner, 26 Oct 2026' in pg_get_functiondef('public.invoice_transferable_benefits(uuid)'::regprocedure)) > 0 $f$;
create function pg_temp.t475_474_in() returns boolean language sql as $f$
  select position('-- 474 (the Owner, 26 Oct 2026' in pg_get_functiondef('public.invoice_reopen_preview_before_sessions(uuid)'::regprocedure)) > 0 $f$;
-- 475 is in: reopen_invoice is 475's (its text says so; S checks its md5).
create function pg_temp.t475_in() returns boolean language sql as $f$
  select position('-- 475 (the Owner, 27 Oct 2026' in pg_get_functiondef('public.reopen_invoice(uuid,text,uuid)'::regprocedure)) > 0 $f$;
-- What a commit does at the end of each app call (each is its own
-- transaction in the app): 462's deferred trigger on the ledger runs (475
-- adds no trigger, and changes nothing a commit does). Here
-- the suite is one transaction, so the trigger's queued rows are run at this
-- point. (Not where each step really commits: t475.autocommit 'on', for
-- running the same cases one call per transaction on a disposable copy.)
create function pg_temp.t475_commit() returns void language plpgsql as $f$
begin
  if coalesce(current_setting('t475.autocommit', true), '') = 'on' then return; end if;
  if pg_temp.t475_462_in() then
    execute 'set constraints public.credit_given_back_follows immediate';
    execute 'set constraints public.credit_given_back_follows deferred';
  end if;
end $f$;

do $$
declare own uuid := gen_random_uuid(); st uuid; st2 uuid; pm uuid; v uuid; cp uuid; cpb uuid; pbv uuid; svc uuid; svc5 uuid;
begin
  insert into auth.users(id, email) values (own, 't475-owner@example.com');
  insert into profiles(id, full_name, email, role, is_active) values (own, 'T475 Owner', 't475-owner@example.com', 'owner', true);
  perform set_config('request.jwt.claims', json_build_object('sub', own, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', own::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  insert into stores(name, code, country_code) values ('T475 Store', 'T475S1', 'SG') returning id into st;
  insert into stores(name, code, country_code) values ('T475 Other Store', 'T475S2', 'SG') returning id into st2;
  insert into payment_methods(name, is_active) values ('T475 Cash', true) returning id into pm;
  insert into vouchers(name, code, voucher_kind, qty_type, selling_price, is_active)
    values ('T475 Plain 30', 'T475-P30', 'normal', 'unlimited', 30, true) returning id into v;
  insert into voucher_store_prices(voucher_id, store_id, selling_price, available_at_store) values (v, st, 30, true), (v, st2, 30, true);
  insert into credit_packages(name, customer_price, paid_credit_amount, bonus_enabled, allow_product, allow_therapy)
    values ('T475 S$100', 100, 100, false, true, true) returning id into cp;
  insert into credit_package_stores(package_id, store_id) values (cp, st), (cp, st2);
  insert into credit_packages(name, customer_price, paid_credit_amount, bonus_enabled, bonus_value, allow_product, allow_therapy, grants_reward)
    values ('T475 S$100 + S$10', 100, 100, true, 10, true, true, false) returning id into cpb;
  insert into credit_package_stores(package_id, store_id) values (cpb, st), (cpb, st2);
  insert into premium_bundles(name, customer_payment_amount, paid_credit_amount, bonus_credit_amount, free_voucher_qty, grants_reward)
    values ('T475 Bundle S$140 + 2 vouchers', 140, 100, 40, 2, true) returning id into pbv;
  insert into premium_bundle_stores(bundle_id, store_id) values (pbv, st), (pbv, st2);
  insert into premium_bundle_vouchers(bundle_id, voucher_id) values (pbv, v);
  svc := (upsert_therapy_service(null, 'T475-SESSION', 'T475 Session', 20, 30, 'per_hours', 1, 5, null, true, null) ->> 'id')::uuid;
  perform set_therapy_service_store(svc, st, true, null);
  svc5 := (upsert_therapy_service(null, 'T475-SHORT', 'T475 Short session', 5, 15, 'per_hours', 1, 5, null, true, null) ->> 'id')::uuid;
  perform set_therapy_service_store(svc5, st, true, null);
  insert into t475 values ('own', own), ('store', st), ('store2', st2), ('pm', pm), ('v', v), ('cp', cp), ('cpb', cpb), ('pbv', pbv),
    ('svc', svc), ('svc5', svc5),
    ('wallet', (select id from payment_methods where name = 'Wallet — Credit Package Paid' and is_wallet_credit and deleted_at is null)),
    ('bwallet', (select id from payment_methods where name = 'Wallet — Premium Bundle Paid' and is_wallet_credit and deleted_at is null));
  perform pg_temp.t475_check(pg_temp.t475_id('wallet') is not null and pg_temp.t475_id('bwallet') is not null, 'setup: the wallet methods (443) are there');
end $$;

-- A customer of one run of one case: '<phase>/<case>/<role>'.
create function pg_temp.t475_cust(p_k text) returns uuid language plpgsql as $f$
declare c uuid;
begin
  insert into customers(full_name, phone) values ('T475 ' || p_k, '+61491570' || lpad((nextval('t475_phone') % 1000)::text, 3, '0'))
    returning id into c;
  return pg_temp.t475_put(p_k, c);
end $f$;
-- The invoice form with these lines ('cp' / 'cpb' a Credit Package, 'pbv' the
-- Premium Bundle, 'v' a voucher line of p_qty units, 'th' three sessions of
-- S$20), with an Owner's manual
-- discount of p_discount (its reason given) where one is given, paid through
-- the Pay dialog: in full, or p_first of it (a part-paid package).
create function pg_temp.t475_sale(p_cust uuid, p_kinds text[], p_first numeric default null, p_qty int default 2,
                                  p_discount numeric default null)
  returns uuid language plpgsql as $f$
declare inv uuid; v_lines jsonb := '[]'; i int;
begin
  for i in 1 .. cardinality(p_kinds) loop
    v_lines := v_lines || jsonb_build_array(case
      when p_kinds[i] = 'v' then jsonb_build_object('kind', 'voucher', 'voucher_id', pg_temp.t475_id('v'), 'quantity', p_qty)
      -- a therapy line of three S$20 sessions (the dialog's sessions)
      when p_kinds[i] = 'th' then jsonb_build_object('kind', 'therapy', 'therapy_service_id', pg_temp.t475_id('svc'), 'quantity', 3)
      when p_kinds[i] in ('cp', 'cpb') then jsonb_build_object('kind', 'credit_package', 'credit_package_id', pg_temp.t475_id(p_kinds[i]), 'quantity', 1)
      else jsonb_build_object('kind', 'premium_bundle', 'premium_bundle_id', pg_temp.t475_id('pbv'), 'quantity', 1,
        'voucher_selection', jsonb_build_array(jsonb_build_object('voucher_id', pg_temp.t475_id('v'), 'quantity', 2))) end);
  end loop;
  inv := create_invoice_with_details(pg_temp.t475_id('store'), p_cust, v_lines, jsonb_build_object('business_date', sg_today()::text)
           || case when p_discount is not null
                   then jsonb_build_object('manual_discount', p_discount, 'manual_discount_reason', 'T475 discount') else '{}'::jsonb end);
  perform record_invoice_settlement(inv, jsonb_build_object('receipts', jsonb_build_array(jsonb_build_object(
    'key', 'line-0', 'payment_method_id', pg_temp.t475_id('pm'),
    'amount', coalesce(p_first, (select total_amount from invoices where id = inv)),
    'payment_date', sg_today()::text)), 'arrangements', '[]'::jsonb), gen_random_uuid());
  return inv;
end $f$;
-- Record Payment of what is outstanding (nothing when it is settled).
create function pg_temp.t475_pay(p_inv uuid) returns void language plpgsql as $f$
begin
  if (invoice_financial_position(p_inv)->>'outstanding')::numeric > 0 then
    perform record_invoice_payment(p_inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.t475_id('pm'),
      'amount', (invoice_financial_position(p_inv)->>'outstanding')::numeric)), gen_random_uuid());
  end if;
end $f$;
-- The receipts that still hold p_amount between them, as the Finance panel
-- splits a refund across them.
create function pg_temp.t475_sources(p_inv uuid, p_amount numeric) returns jsonb language plpgsql as $f$
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
create function pg_temp.t475_line(p_inv uuid, p_n int default 1) returns uuid language sql as $f$
  select id from invoice_items where invoice_id = p_inv
   order by case when line_kind in ('credit_package', 'premium_bundle') then 0 when line_kind = 'voucher' then 1
                 when therapy_service_id is not null then 2 else 3 end, id offset p_n - 1 limit 1 $f$;
-- The Finance panel's refund by line of line p_n: p_amount off its Paid
-- benefit (the one an Owner did not move, or with p_holder the one p_holder
-- holds), or every unused benefit it still holds (p_amount null).
create function pg_temp.t475_back(p_inv uuid, p_n int, p_amount numeric default null, p_holder uuid default null)
  returns void language plpgsql as $f$
declare opts jsonb; ben jsonb; tot numeric; item uuid := pg_temp.t475_line(p_inv, p_n);
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
  if ben is null then raise exception 'T475: nothing to refund on that line'; end if;
  perform refund_invoice_recorded(p_inv, jsonb_build_array(jsonb_build_object('invoice_item_id', item, 'amount', tot, 'benefits', ben)),
    pg_temp.t475_sources(p_inv, tot), '[]'::jsonb, 'T475 by line', gen_random_uuid());
end $f$;
-- The invoice form's customer change, its lines as they are (and the store,
-- when given), with 'transfer' or 'keep'. The change's Audit Log row is
-- dated now, as a later call's is (the suite is one transaction).
create function pg_temp.t475_lines(p_inv uuid) returns jsonb language sql as $f$
  select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('invoice_item_id', it.id, 'kind', it.line_kind,
           'credit_package_id', it.credit_package_id, 'premium_bundle_id', it.premium_bundle_id, 'voucher_id', it.voucher_id,
           'quantity', it.quantity, 'unit_price', it.unit_price, 'voucher_selection', it.bundle_voucher_selection)) order by it.id)
    from invoice_items it where it.invoice_id = p_inv $f$;
create function pg_temp.t475_change(p_inv uuid, p_cust uuid, p_action text default 'transfer', p_store text default null)
  returns void language plpgsql as $f$
begin
  perform correct_invoice(p_inv, pg_temp.t475_lines(p_inv),
    jsonb_build_object('expected_edit_count', (select edit_count from invoices where id = p_inv),
      'customer_id', p_cust, 'store_id', coalesce(pg_temp.t475_id(p_store), (select store_id from invoices where id = p_inv)),
      'benefit_action', p_action),
    'T475 wrong customer', gen_random_uuid());
  update audit_logs set created_at = clock_timestamp()
   where record_id = p_inv and action = 'invoice_benefits_followed_reassignment' and new_data->>'to_customer' = p_cust::text
     and created_at = now();
end $f$;
create function pg_temp.t475_merge(p_keep uuid, p_dup uuid) returns void language plpgsql as $f$
begin
  perform merge_customer_records(p_keep, p_dup, 'T475 the same person', gen_random_uuid());
end $f$;
-- The invoice form: p_n sessions of S$20 (or S$5 with p_svc 'svc5') for
-- p_cust, paid with the wallet (Credit Package Paid; Premium Bundle Paid with
-- p_wallet 'bwallet') through Record Payment.
create function pg_temp.t475_spend(p_cust uuid, p_n int default 1, p_svc text default 'svc', p_wallet text default 'wallet')
  returns uuid language plpgsql as $f$
declare inv uuid; v_lines jsonb := '[]'; i int;
begin
  for i in 1 .. p_n loop
    v_lines := v_lines || jsonb_build_array(jsonb_build_object('kind', 'therapy', 'therapy_service_id', pg_temp.t475_id(p_svc), 'quantity', 1));
  end loop;
  inv := create_invoice_with_details(pg_temp.t475_id('store'), p_cust, v_lines, jsonb_build_object('business_date', sg_today()::text));
  perform record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.t475_id(p_wallet),
    'amount', (select total_amount from invoices where id = inv))), gen_random_uuid());
  if (select status::text from invoices where id = inv) <> 'paid' then raise exception 'T475: the session paid from credit is not paid'; end if;
  return inv;
end $f$;
-- The session cancelled and "Record refund paid": what its payment took goes
-- back to the lots it came from (refund_invoice_recorded's wallet refund).
create function pg_temp.t475_unspend(p_inv uuid) returns void language plpgsql as $f$
declare due numeric;
begin
  perform cancel_invoice_recorded(p_inv, 'T475 cancel session', gen_random_uuid());
  due := (invoice_financial_position(p_inv)->>'refund_due')::numeric;
  if due is null or due <= 0 then due := (invoice_action_plan(p_inv, 'cancel', '[]')->>'refund_due')::numeric; end if;
  perform refund_invoice_recorded(p_inv, jsonb_build_array(jsonb_build_object('amount', due)), pg_temp.t475_sources(p_inv, due), '[]'::jsonb,
    'T475 refund paid', gen_random_uuid());
end $f$;
-- The guided Refund in full / Cancel as an Owner confirms it, with a reason
-- for every override the plan asks for, the money recorded as paid back (or,
-- with p_record false, not: "Record refund paid" left unticked).
create function pg_temp.t475_guided(p_inv uuid, p_action text, p_record boolean default true) returns void language plpgsql as $f$
declare plan jsonb; req jsonb; ov jsonb;
begin
  plan := invoice_action_plan(p_inv, p_action, '[]');
  req := request_invoice_action_v2(p_inv, p_action, '[]', 'T475 ' || p_action, null, gen_random_uuid());
  select coalesce(jsonb_agg(case when coalesce((o->>'amount_required')::boolean, false)
           then jsonb_build_object('code', o->>'code', 'reason', 'T475 override', 'amount', (o->>'default_amount')::numeric)
           else jsonb_build_object('code', o->>'code', 'reason', 'T475 override') end), '[]'::jsonb)
    into ov from jsonb_array_elements(coalesce(plan->'overrides_required', '[]')) o;
  perform resolve_invoice_action_v2((req->>'request_id')::uuid, true, 'T475 ' || p_action, plan->>'plan_hash', ov, null, p_record);
end $f$;


-- ── What the records say ────────────────────────────────────────────────────
-- The lots an invoice's records name: its benefit values, its sale's lots, a
-- split's issued lot, released credit (credit_package_progress_lots).
create function pg_temp.t475_named(p_inv uuid) returns setof uuid language sql as $f$
  select lot_id from invoice_benefit_values where invoice_id = p_inv and lot_id is not null
  union select x from credit_package_sales s, unnest(array[s.credit_lot_id, s.bonus_credit_lot_id]) x where s.invoice_id = p_inv and x is not null
  union select x from premium_bundle_sales s, unnest(array[s.paid_credit_lot_id, s.bonus_credit_lot_id]) x where s.invoice_id = p_inv and x is not null
  union select issued_lot_id from invoice_credit_splits where invoice_id = p_inv and issued_lot_id is not null
  union select lot_id from credit_package_progress_lots where invoice_id = p_inv $f$;
-- The invoice's lot family (the critic's 6): every lot its records name and
-- each Move's two lots (from the Move's ledger rows), the lots each replaced
-- and every lot reissued from any of them.
create function pg_temp.t475_family(p_inv uuid) returns setof uuid language sql as $f$
  with recursive seed as (
    select x as id from pg_temp.t475_named(p_inv) x
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
create function pg_temp.t475_behind(p_inv uuid) returns setof uuid language sql as $f$
  with recursive c(id, n) as (
    select lot_id, 0 from invoice_benefit_values where invoice_id = p_inv and lot_id is not null
    union select p.id, c.n + 1 from c join customer_credit_lots l on l.id = c.id
            join customer_credit_lots p on p.id = l.reassigned_from_lot_id
             and (p.source_type, p.source_record_id) is not distinct from (l.source_type, l.source_record_id)
           where c.n < 12)
  select distinct id from c $f$;
-- How many lots back a lot's chain goes (reassigned_from_lot_id).
create function pg_temp.t475_depth(p_lot uuid) returns int language sql as $f$
  with recursive c(id, n) as (select p_lot, 0 union all
    select l.reassigned_from_lot_id, c.n + 1 from c join customer_credit_lots l on l.id = c.id
     where l.reassigned_from_lot_id is not null and c.n < 40)
  select max(n) from c $f$;
-- A lot's balance by its ledger rows: credit added (grants, increases,
-- credit returned: the 'reverse' rows that put credit back, as the
-- statement reads them, and 'rental_late_fee'), less credit taken (uses,
-- decreases, real reversals).
create function pg_temp.t475_ledger_balance(p_lot uuid) returns numeric language sql as $f$
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
create function pg_temp.t475_invariants(p_inv uuid) returns text language plpgsql as $f$
declare probs text := ''; l record; root record; v uuid; st text := (select status::text from invoices where id = p_inv);
begin
  for l in select cl.* from customer_credit_lots cl where cl.id in (select pg_temp.t475_family(p_inv)) loop
    if l.remaining_amount > 0 and l.id not in (select pg_temp.t475_named(p_inv)) then
      probs := probs || format(' S$%s on a lot no record names (%s);', l.remaining_amount, (select full_name from customers where id = l.customer_id)); end if;
    if l.id not in (select pg_temp.t475_named(p_inv)) and l.id not in (select pg_temp.t475_behind(p_inv))
       and (exists (select 1 from invoice_line_credit_allocations a where a.lot_id = l.id and a.amount > coalesce(a.reversed_amount, 0))
            or exists (select 1 from special_credit_allocations s where s.lot_id = l.id and s.amount > coalesce(s.reversed_amount, 0))) then
      probs := probs || ' a sale paid from a lot no record names can still be refunded (its credit would stay there);'; end if;
    if pg_temp.t475_ledger_balance(l.id) <> l.remaining_amount then
      probs := probs || format(' lot holds %s, its ledger %s;', l.remaining_amount, pg_temp.t475_ledger_balance(l.id)); end if;
    if pg_temp.t475_depth(l.id) > 12 then probs := probs || format(' chain %s lots deep;', pg_temp.t475_depth(l.id)); end if;
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
  if st = 'refunded' and (select coalesce(sum(remaining_amount), 0) from customer_credit_lots where id in (select pg_temp.t475_family(p_inv))) > 0 then
    probs := probs || format(' refunded, but S$%s of its credit is still held;',
      (select sum(remaining_amount) from customer_credit_lots where id in (select pg_temp.t475_family(p_inv)))); end if;
  return probs;
end $f$;
-- Credit left on the invoice's family once Cancel has run, the Cancel undone
-- (0 when Cancel takes it all back from whoever holds it); null when the
-- invoice cannot be cancelled now, -1 when Cancel is refused.
create function pg_temp.t475_cancel_left(p_inv uuid) returns numeric language plpgsql as $f$
declare v numeric;
begin
  if (select status::text from invoices where id = p_inv) not in ('paid', 'partially_paid', 'unpaid') then return null; end if;
  begin
    perform cancel_invoice_recorded(p_inv, 'T475 probe', gen_random_uuid());
    perform pg_temp.t475_commit();
    v := (select coalesce(sum(remaining_amount), 0) from customer_credit_lots where id in (select pg_temp.t475_family(p_inv)));
    raise exception using errcode = 'P0461', message = v::text;
  exception when sqlstate 'P0461' then return sqlerrm::numeric;
            when others then return -1;
  end;
end $f$;
create function pg_temp.t475_codes(p_inv uuid, p_action text) returns text language plpgsql as $f$
begin
  return (select coalesce(string_agg(o->>'code', ',' order by o->>'code'), '-')
            from jsonb_array_elements(coalesce(invoice_action_plan(p_inv, p_action, '[]')->'overrides_required', '[]')) o);
exception when others then return 'ERR';
end $f$;
create function pg_temp.t475_due(p_inv uuid, p_action text) returns numeric language plpgsql as $f$
begin
  return (invoice_action_plan(p_inv, p_action, '[]')->>case when p_action = 'cancel' then 'refund_due' else 'refund_amount' end)::numeric;
exception when others then return null;
end $f$;
-- The invoice's money: what is owed back (cancel_refund_owed), the Finance
-- panel's refund due, net received and kept for what was used, what a
-- refund by line can still pay back (the refund options' max_refund, every
-- benefit) and Cancel's refund due (the plan's).
create function pg_temp.t475_money(p_inv uuid) returns jsonb language sql as $f$
  select jsonb_build_object('owed', i.cancel_refund_owed,
    'due', (invoice_financial_position(i.id)->>'refund_due')::numeric,
    'net', (invoice_financial_position(i.id)->>'net_received')::numeric,
    'kept', (invoice_financial_position(i.id)->>'kept_for_used')::numeric,
    'by_line', (select coalesce(sum((b->>'max_refund')::numeric), 0)
                  from jsonb_array_elements(invoice_refund_options_before_sessions(i.id)->'benefits') b),
    'plan_due', pg_temp.t475_due(i.id, 'cancel'))
    from invoices i where i.id = p_inv $f$;


-- ── The cases ───────────────────────────────────────────────────────────────
-- A case is a list of steps, each one app call (and its commit), on the
-- case's own customers (A the buyer, B a later customer, K a record a merge
-- keeps). A step refused stops the case, the refusal recorded. Steps:
--   sale R kinds [first]  the invoice (th, cp, pbv, v; part-paid: first)
--   pay                   Record Payment of what is outstanding
--   paydlg                the Pay dialog (record_invoice_settlement) of what is outstanding
--   payamt amt            Record Payment of amt (its receipt kept for fixpay)
--   fixpay amt            Correct payment of that receipt to amt (correct_invoice_payment)
--   back N amt|all [R]    refund by line of line N's credit (R: the benefit R holds)
--   backv N units         a refund by line of that many voucher units of line N
--   backt N amt           a refund by line of a therapy line by money (whole sessions)
--   cancel, reopen        Cancel; Reopen
--   refundall             the guided Refund in full, recorded
--   guidedcancel          the guided Cancel as an Owner confirms it, "Record refund paid" ticked
--   guidedkeep            the same, "Record refund paid" not ticked
--   refundpaid            "Record refund paid" of what the invoice owes back (no line)
--   change R [keep]       the customer change ('transfer' unless keep)
--   merge KEEP DUP        a customer merge
--   spend R [n] [bwallet] a session invoice for R paid from credit
--   unspend Sn            that session cancelled and its refund recorded
--   dup                   BY HAND (no function does it since 475): a second waiting
--                         row for each waiting session of the invoice, as a reopening
--                         queued it before 475 (NOT COVERED 3)
--   shrink                BY HAND (no function does it): each waiting row of the
--                         invoice one less than its session shows (NOT COVERED 4)
create function pg_temp.t475_role(p_pre text, p_r text) returns uuid language plpgsql as $f$
begin
  return coalesce(pg_temp.t475_id(p_pre || '/' || p_r), pg_temp.t475_cust(p_pre || '/' || p_r));
end $f$;
-- One step of a case (one app call, then what its commit does). Null, or
-- the step and the refusal; a refused step changes nothing.
create function pg_temp.t475_step(p_pre text, p_st text) returns text language plpgsql as $f$
declare w text[] := regexp_split_to_array(btrim(p_st), '\s+'); inv uuid := pg_temp.t475_id(p_pre || '/inv'); x uuid; n int;
begin
  case w[1]
  when 'sale' then
    perform pg_temp.t475_put(p_pre || '/inv', pg_temp.t475_sale(pg_temp.t475_role(p_pre, w[2]), string_to_array(w[3], ','), w[4]::numeric));
  when 'pay' then perform pg_temp.t475_pay(inv);
  when 'paydlg' then
    perform record_invoice_settlement(inv, jsonb_build_object('receipts', jsonb_build_array(jsonb_build_object(
      'key', 'line-0', 'payment_method_id', pg_temp.t475_id('pm'),
      'amount', (invoice_financial_position(inv)->>'outstanding')::numeric, 'payment_date', sg_today()::text)),
      'arrangements', '[]'::jsonb), gen_random_uuid());
  when 'payamt' then
    x := gen_random_uuid();
    perform record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.t475_id('pm'),
      'amount', w[2]::numeric)), x);
    perform pg_temp.t475_put(p_pre || '/pay/receipt',
      (select p.id from invoice_payments p where p.invoice_id = inv and p.entry_kind = 'receipt' and p.amount = w[2]::numeric
          and not exists (select 1 from invoice_payments q where q.corrects_payment_id = p.id)
        order by p.created_at desc, p.id limit 1));
  when 'fixpay' then
    perform correct_invoice_payment(pg_temp.t475_id(p_pre || '/pay/receipt'), w[2]::numeric, sg_today(),
      (select payment_method_id from invoice_payments where id = pg_temp.t475_id(p_pre || '/pay/receipt')),
      'T475 correct payment', gen_random_uuid());
  when 'back' then
    perform pg_temp.t475_back(inv, w[2]::int, case when w[3] = 'all' then null else w[3]::numeric end,
                              case when w[4] is not null then pg_temp.t475_role(p_pre, w[4]) end);
  when 'cancel' then perform cancel_invoice_recorded(inv, 'T475 cancel', gen_random_uuid());
  when 'reopen' then perform reopen_invoice(inv, 'T475 reopen', gen_random_uuid());
  when 'refundall' then perform pg_temp.t475_guided(inv, 'refund_full');
  when 'guidedcancel' then perform pg_temp.t475_guided(inv, 'cancel');
  when 'guidedkeep' then perform pg_temp.t475_guided(inv, 'cancel', false);
  when 'refundpaid' then
    perform refund_invoice_recorded(inv, jsonb_build_array(jsonb_build_object('amount',
        coalesce(nullif((invoice_financial_position(inv)->>'refund_due')::numeric, 0), (invoice_action_plan(inv, 'cancel', '[]')->>'refund_due')::numeric))),
      pg_temp.t475_sources(inv, coalesce(nullif((invoice_financial_position(inv)->>'refund_due')::numeric, 0), (invoice_action_plan(inv, 'cancel', '[]')->>'refund_due')::numeric)),
      '[]'::jsonb, 'T475 refund paid', gen_random_uuid());
  when 'change' then
    perform pg_temp.t475_change(inv, pg_temp.t475_role(p_pre, w[2]), case when 'keep' = any (w) then 'keep' else 'transfer' end);
  when 'merge' then perform pg_temp.t475_merge(pg_temp.t475_role(p_pre, w[2]), pg_temp.t475_role(p_pre, w[3]));
  when 'spend' then
    n := (select count(*) from t475 where k ~ ('^' || p_pre || '/S[0-9]+$')) + 1;
    perform pg_temp.t475_put(p_pre || '/S' || n,
      pg_temp.t475_spend(pg_temp.t475_role(p_pre, w[2]), case when w[3] ~ '^[0-9]+$' then w[3]::int else 1 end,
        'svc', case when 'bwallet' = any (w) then 'bwallet' else 'wallet' end));
  when 'unspend' then perform pg_temp.t475_unspend(pg_temp.t475_id(p_pre || '/' || w[2]));
  when 'backv' then
    -- the Finance panel's refund by line of N voucher units of line N (at
    -- their paid value).
    x := pg_temp.t475_line(inv, w[2]::int);
    perform refund_invoice_recorded(inv, jsonb_build_array(jsonb_build_object('invoice_item_id', x, 'amount', b.amt,
        'benefits', jsonb_build_array(jsonb_build_object('benefit_id', b.id, 'amount', b.amt)))),
      pg_temp.t475_sources(inv, b.amt), '[]'::jsonb, 'T475 voucher by line', gen_random_uuid())
      from (select o->>'id' as id, round(w[3]::int * (o->>'paid_value')::numeric / (o->>'granted_value')::numeric, 2) as amt
              from jsonb_array_elements(invoice_refund_options_before_sessions(inv)->'benefits') o
             where o->>'invoice_item_id' = x::text and o->>'benefit_kind' = 'voucher' and (o->>'max_refund')::numeric > 0
             order by (o->>'max_refund')::numeric desc limit 1) b;
    if not found then raise exception 'T475: no voucher to refund on that line'; end if;
  when 'backt' then
    -- the Finance panel's refund by line of a therapy line, by money (whole
    -- unused sessions).
    x := pg_temp.t475_line(inv, w[2]::int);
    perform refund_invoice_recorded(inv, jsonb_build_array(jsonb_build_object('invoice_item_id', x, 'amount', w[3]::numeric)),
      pg_temp.t475_sources(inv, w[3]::numeric), '[]'::jsonb, 'T475 sessions by line', gen_random_uuid());
  when 'dup' then
    -- BY HAND: as a second reopening queued it before 475 (NOT COVERED 3).
    insert into invoice_reopen_sessions(invoice_id, session_id, request_id, quantity)
    select q.invoice_id, q.session_id, gen_random_uuid(), q.quantity from invoice_reopen_sessions q
     where q.invoice_id = inv and q.applied_at is null;
    if not found then raise exception 'T475: no waiting session to queue again'; end if;
  when 'shrink' then
    -- BY HAND: a state no function makes (NOT COVERED 4).
    update invoice_reopen_sessions set quantity = quantity - 1 where invoice_id = inv and applied_at is null and quantity > 1;
    if not found then raise exception 'T475: no waiting session to shrink'; end if;
  else raise exception 'T475: unknown step %', p_st;
  end case;
  perform pg_temp.t475_commit();
  return null;
exception when others then
  return btrim(p_st) || ': ' || sqlerrm;
end $f$;
-- 475: the invoice's therapy sessions: each current one (available of
-- purchased, refunded, cancelled, status), the session queue (waiting rows,
-- what they hold, sessions waiting on more than one row), the reinstatements
-- ('reopen' events), who holds them (a role of the case), and what is wrong
-- with them ('' when nothing):
--   * no session waits on more than one row;
--   * a waiting session's row holds what the session shows as refunded and
--     cancelled (what the payment checks);
--   * nothing waits once the invoice is settled again;
--   * no session that is not current waits;
--   * the sessions are held by the invoice's customer.
create function pg_temp.t475_sessions(p_pre text) returns jsonb language plpgsql as $f$
declare inv uuid := pg_temp.t475_id(p_pre || '/inv'); probs text := ''; s record; st text;
begin
  st := (select status::text from invoices where id = inv);
  for s in select x.*, (select count(*) from invoice_reopen_sessions q where q.session_id = x.id and q.applied_at is null) as nrows,
                  (select coalesce(sum(q.quantity), 0) from invoice_reopen_sessions q where q.session_id = x.id and q.applied_at is null) as qsum
             from customer_therapy_sessions x where x.invoice_id = inv loop
    if s.nrows > 1 then probs := probs || format(' a session waits on %s rows (%s);', s.nrows, s.qsum); end if;
    if s.nrows > 0 and s.qsum <> s.quantity_refunded + s.quantity_cancelled then
      probs := probs || format(' a waiting session''s rows hold %s, it shows %s;', s.qsum, s.quantity_refunded + s.quantity_cancelled); end if;
    if s.nrows > 0 and st in ('paid', 'completed_foc') then probs := probs || ' settled with a session still waiting;'; end if;
    if s.nrows > 0 and not s.is_current then probs := probs || ' a replaced session waits;'; end if;
    if s.is_current and s.customer_id is distinct from (select customer_id from invoices where id = inv) then
      probs := probs || ' the sessions are not held by the invoice''s customer;'; end if;
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
    'sholder', (select string_agg(distinct split_part(t.k, '/', 3), ',') from customer_therapy_sessions x join t475 t on t.id = x.customer_id
                 where x.invoice_id = inv and x.is_current and t.k like p_pre || '/%'),
    'sinv', probs);
end $f$;
-- What a case ends with: the invoice's status and money, who holds what
-- (credit, '/n' held vouchers), the plans' codes and refund due (Cancel's
-- refund due; Refund in full's amount), the refusal that stopped it, what is
-- wrong with its credit, the credit Cancel would leave behind, and its
-- sessions (above).
create function pg_temp.t475_outcome(p_pre text, p_err text) returns jsonb language sql as $f$
  select jsonb_build_object(
    'status', (select status::text from invoices where id = i.id),
    'net', invoice_net_received(i.id),
    'owed', (select cancel_refund_owed from invoices where id = i.id),
    'fdue', (invoice_financial_position(i.id)->>'refund_due')::numeric,
    'held', (select coalesce(sum(cancelled_unused_value), 0) from invoice_benefit_values where invoice_id = i.id and lot_id is not null),
    'holds', (select jsonb_object_agg(split_part(t.k, '/', 3),
                (select coalesce(sum(l.remaining_amount), 0) from customer_credit_lots l where l.customer_id = t.id)::numeric(12,2)::text
                || coalesce('/' || nullif((select sum(v.quantity) from customer_reward_vouchers v where v.customer_id = t.id and v.status = 'held'), 0)::text, ''))
              from t475 t where t.k like p_pre || '/%' and split_part(t.k, '/', 4) = ''
                and split_part(t.k, '/', 3) !~ '^(inv|S[0-9]+|err)$'),
    'cancel', pg_temp.t475_codes(i.id, 'cancel'),
    'due', pg_temp.t475_due(i.id, 'cancel'),
    'refund', pg_temp.t475_codes(i.id, 'refund_full'),
    'rdue', pg_temp.t475_due(i.id, 'refund_full'),
    'error', p_err,
    'invariants', pg_temp.t475_invariants(i.id),
    'cancel_left', pg_temp.t475_cancel_left(i.id)) || pg_temp.t475_sessions(p_pre)
    from (select pg_temp.t475_id(p_pre || '/inv') as id) i $f$;

-- ── The readings: the Reopen dialog, and what the payment gives ─────────────
-- Each Reopen of a case: the dialog read just before it, as the Finance panel
-- reads it (invoice_reopen_preview: every figure it shows), what the Reopen
-- left waiting (or gave back at once, reopened straight to paid): credit,
-- voucher units and (475) sessions.
create temp table t475_dlg(pre text, n int, shown numeric, shownv int, shows int, total numeric, net numeric, required numeric,
                           can boolean, preview jsonb, queued numeric, queuedv int, queueds int, primary key (pre, n));
-- What each step gave back: credit (the payment's 'Reopened invoice settled'
-- rows, apply_reopened_invoice_benefits), voucher units given again
-- (apply_reopened_invoice_vouchers) and sessions reinstated
-- (trg_create_therapy_sessions_on_paid).
create temp table t475_gift(pre text, n int, credit numeric, vouchers int, sessions int, primary key (pre, n));
create temp table t475_err(pre text primary key, err text);
create function pg_temp.t475_dialog(p_pre text) returns jsonb language sql as $f$
  with l as (select * from t475_dlg where pre = p_pre order by n desc limit 1)
  select jsonb_build_object(
    'reopens', (select count(*) from t475_dlg where pre = p_pre),
    'dlg', (select shown from l), 'dlgv', (select shownv from l), 'dlgs', (select shows from l),
    'required', (select required from l),
    'queued', (select queued from l), 'queuedv', (select queuedv from l), 'queueds', (select queueds from l),
    'gave', (select coalesce(sum(g.credit), 0) from t475_gift g, l where g.pre = p_pre and g.n >= l.n),
    'gavev', (select coalesce(sum(g.vouchers), 0) from t475_gift g, l where g.pre = p_pre and g.n >= l.n),
    'gaves', (select coalesce(sum(g.sessions), 0) from t475_gift g, l where g.pre = p_pre and g.n >= l.n),
    'every', (select coalesce(string_agg(format('%s: %s/%s/%s shown, %s/%s/%s queued (credit/vouchers/sessions)',
                                                d.n, d.shown, d.shownv, d.shows, d.queued, d.queuedv, d.queueds), '; ' order by d.n), '')
                from t475_dlg d where d.pre = p_pre and d.queued is not null
                 and (d.shown is distinct from d.queued or d.shownv is distinct from d.queuedv or d.shows is distinct from d.queueds))) $f$;
-- A case's steps p_from to p_to (all by default), stopping at a refusal;
-- with p_to null, its outcome (kept in t475_res under p_phase).
create function pg_temp.t475_run(p_phase text, p_case text, p_steps text, p_from int default 1, p_to int default null)
  returns jsonb language plpgsql as $f$
declare v_pre text := p_phase || '/' || p_case; st text[] := string_to_array(p_steps, ';'); i int; v_err text; v_out jsonb;
  inv uuid; pv jsonb; seq bigint; av uuid[]; ass uuid[]; g numeric; gv int; gs int;
begin
  v_err := (select e.err from t475_err e where e.pre = v_pre);
  for i in p_from .. least(coalesce(p_to, cardinality(st)), cardinality(st)) loop
    exit when v_err is not null;
    continue when btrim(st[i]) = '';
    inv := pg_temp.t475_id(v_pre || '/inv');
    if inv is not null and btrim(st[i]) = 'reopen' then
      pv := invoice_reopen_preview(inv);
      insert into t475_dlg(pre, n, shown, shownv, shows, total, net, required, can, preview)
      values (v_pre, i, (pv->>'credit_to_reinstate_after_settlement')::numeric, (pv->>'voucher_units_to_reinstate_after_settlement')::int,
              coalesce((pv->>'sessions_to_reinstate_after_settlement')::int, 0), (pv->>'total')::numeric, (pv->>'net_received')::numeric,
              greatest(0, (pv->>'total')::numeric - (pv->>'net_received')::numeric), (pv->>'can_reopen')::boolean, pv)
      on conflict (pre, n) do nothing;
    end if;
    select coalesce(max(entry_seq), 0) into seq from customer_credit_ledger;
    select array_agg(id) into av from invoice_reopen_vouchers where invoice_id = inv and applied_at is not null;
    select array_agg(id) into ass from invoice_reopen_sessions where invoice_id = inv and applied_at is not null;
    v_err := pg_temp.t475_step(v_pre, st[i]);
    inv := pg_temp.t475_id(v_pre || '/inv');
    g := (select coalesce(sum(e.amount), 0) from customer_credit_ledger e
           where e.entry_seq > seq and e.entry_type = 'reverse' and e.source_type = 'invoice_reopen' and e.reason = 'Reopened invoice settled'
             and e.reverses_entry_id in (select q.source_ledger_id from invoice_reopen_benefits q where q.invoice_id = inv));
    gv := (select coalesce(sum(q.quantity), 0) from invoice_reopen_vouchers q where q.invoice_id = inv and q.applied_at is not null
             and q.replacement_voucher_id is not null and not (q.id = any (coalesce(av, '{}'))));
    gs := (select coalesce(sum(q.quantity), 0) from invoice_reopen_sessions q where q.invoice_id = inv and q.applied_at is not null
             and not (q.id = any (coalesce(ass, '{}'))));
    insert into t475_gift values (v_pre, i, g, gv, gs)
      on conflict (pre, n) do update set credit = excluded.credit, vouchers = excluded.vouchers, sessions = excluded.sessions;
    if btrim(st[i]) = 'reopen' and v_err is null then
      update t475_dlg set queued = g + (select coalesce(sum(q.amount), 0) from invoice_reopen_benefits q where q.invoice_id = inv and q.applied_at is null),
                          queuedv = gv + (select coalesce(sum(q.quantity), 0) from invoice_reopen_vouchers q where q.invoice_id = inv and q.applied_at is null),
                          queueds = gs + (select coalesce(sum(q.quantity), 0) from invoice_reopen_sessions q where q.invoice_id = inv and q.applied_at is null)
       where pre = v_pre and n = i;
    end if;
  end loop;
  insert into t475_err values (v_pre, v_err) on conflict (pre) do update set err = excluded.err;
  if p_to is not null then return null; end if;
  v_out := pg_temp.t475_outcome(v_pre, v_err) || pg_temp.t475_dialog(v_pre);
  insert into t475_res values (p_phase, p_case, v_out) on conflict (phase, k) do update set v = excluded.v;
  return v_out;
end $f$;
-- Whether an outcome has what is expected: each key equal ('holds' as a
-- containment of who holds what), a key ending in '~' as a LIKE pattern of
-- that key's text.
create function pg_temp.t475_meets(p_out jsonb, p_exp jsonb) returns boolean language sql as $f$
  select coalesce(bool_and(case
           when e.key like '%~' then coalesce(p_out->>left(e.key, -1), '') like (e.value #>> '{}')
           when e.key = 'holds' then coalesce(p_out->'holds', '{}') @> e.value
           when jsonb_typeof(e.value) = 'number' then coalesce((p_out->>e.key)::numeric = (e.value #>> '{}')::numeric, false)
           else (p_out->e.key) is not distinct from e.value end), true)
    from jsonb_each(p_exp) e $f$;
-- What differs between an outcome and what is expected (for the FAIL line).
create function pg_temp.t475_diff(p_out jsonb, p_exp jsonb) returns text language sql as $f$
  select string_agg(e.key || ': wanted ' || e.value::text || ', got ' || coalesce(p_out->left(e.key, case when e.key like '%~' then -1 else 1000 end), 'null')::text, '; ')
    from jsonb_each(p_exp) e where not pg_temp.t475_meets(p_out, jsonb_build_object(e.key, e.value)) $f$;
-- 475: an outcome without what 475 changes in the queue before the payment
-- (the second reopening's rows, and what reads them), for A against R: up
-- to its payment a fixed case is otherwise exactly as before 475.
create function pg_temp.t475_but_queue(p_out jsonb) returns jsonb language sql as $f$
  select p_out - 'swait' - 'squeued' - 'stwice' - 'sinv' - 'queueds' - 'every' $f$;
-- The unapplied reopening queue of an invoice (credit).
create function pg_temp.t475_waiting(p_inv uuid) returns numeric language sql as $f$
  select coalesce(sum(q.amount), 0) from invoice_reopen_benefits q where q.invoice_id = p_inv and q.applied_at is null $f$;
-- Who may call a function (the set) and the whole grant list (by name).
create function pg_temp.t475_grants() returns text language sql as $f$
  select md5(string_agg(p.oid::regprocedure::text || '=' || coalesce(p.proacl::text, 'null'), '|' order by p.oid::regprocedure::text))
    from pg_proc p where p.pronamespace = 'public'::regnamespace $f$;
create function pg_temp.t475_grant_set(p_sig text) returns text[] language sql as $f$
  select array_agg(x::text order by x::text) from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || p_sig) $f$;
-- The function 475 changes: BEFORE (production, 27 Oct 2026: 458's AFTER)
-- and AFTER.
create temp table t475_md5(sig text primary key, before text, after text);
insert into t475_md5 values
  ('reopen_invoice(uuid,text,uuid)', '0ff61e4ead121c198ea7f90a7fc78274', '30066e137b9b75b5789a050c14debc04');
create function pg_temp.t475_at(p_col text) returns boolean language sql as $f$
  select bool_and(md5(pg_get_functiondef(to_regprocedure('public.' || m.sig))) = case when p_col = 'before' then m.before else m.after end)
    from t475_md5 m $f$;
insert into t475_fp values ('start', pg_temp.t475_fingerprint()), ('grants', pg_temp.t475_grants());

-- The read-only query in 475's header (the same text, taken from the file
-- when this suite was written).
create function pg_temp.t475_header_query() returns table(reason text, invoice_no text, n bigint) language sql as $hq$
with
-- therapy sessions waiting for a reopening's payment: per session,
-- its waiting rows, what they hold and what the session shows as
-- refunded and cancelled
w as (
  select q.invoice_id, q.session_id, count(*) as n_rows, sum(q.quantity) as queued,
         max(s.quantity_refunded + s.quantity_cancelled) as shows
    from public.invoice_reopen_sessions q
    join public.customer_therapy_sessions s on s.id = q.session_id
   where q.applied_at is null
   group by q.invoice_id, q.session_id),
found(reason, invoice_id, n) as (
  select '1 changes: cancelled or refunded with a therapy session an earlier reopening queued still waiting; reopened again, before 475 the session was queued again and the payment that settles it refused, from 475 it is not queued again and that payment reinstates it once (the count is of sessions)', i.id, count(*)
    from public.invoices i join w on w.invoice_id = i.id
   where i.deleted_at is null and i.status::text in ('cancelled', 'refunded') and w.n_rows = 1
   group by i.id
  union all
  select '2 for the Owner (not changed by 475: NOT COVERED 3): a therapy session queued by two or more reopenings still waiting; the payment that settles the invoice is refused ("Therapy session reopening changed; reload its original evidence"), before 475 and after it (the count is of sessions)', i.id, count(*)
    from public.invoices i join w on w.invoice_id = i.id
   where i.deleted_at is null and w.n_rows > 1
   group by i.id
  union all
  select '3 for the Owner (not changed by 475: NOT COVERED 4): a therapy session waiting once whose refunded and cancelled count is no longer what its row holds; the payment that settles the invoice is refused, before 475 and after it (the count is of sessions)', i.id, count(*)
    from public.invoices i join w on w.invoice_id = i.id
   where i.deleted_at is null and w.n_rows = 1 and w.queued <> w.shows
   group by i.id)
select f.reason, i.invoice_no, f.n
  from found f join public.invoices i on i.id = f.invoice_id
 order by f.reason, i.invoice_no
$hq$;
-- What the header's query lists for an invoice: 'reason/count', by reason.
create function pg_temp.t475_listed(p_inv uuid) returns text language sql as $f$
  select string_agg(left(q.reason, 1) || '/' || q.n, ',' order by q.reason)
    from pg_temp.t475_header_query() q join invoices i on i.invoice_no = q.invoice_no where i.id = p_inv $f$;

-- The cases: (k, kind, steps, what 475 gives, what the header's query lists
-- for its state before 475, the steps compared with before 475 for a fixed
-- case). kind: 'fixed' (before 475 the payment that settles the invoice is
-- refused, a session queued twice: the fault is reproduced first),
-- 'control' (the same with and without 475, every key of the outcome),
-- 'known' (a NOT COVERED item, checked as it is: the same with and without
-- 475, as a control). Every case also checks the invariants, the sessions'
-- own, and that Cancel takes everything back from whoever holds it.
create temp table t475_cases(k text primary key, kind text not null, steps text not null, expect jsonb not null, q text, pre int, ord serial);
insert into t475_cases(k, kind, steps, expect, q, pre) values
-- 474's K1: a 3-session line, cancelled, S$20 refunded by line, reopened (it
-- waits), cancelled again, reopened, paid; a third reopening.
('THq', 'fixed', 'sale A th; cancel; backt 1 20; reopen; cancel; reopen; pay',
  '{"status":"paid","net":60,"required":20,"dlgs":3,"queueds":3,"gaves":3,"sess":"3/3 r0 c0 available","swait":0,"stwice":0,"sev":1,"sholder":"A","sinv":"","every":"","error":null}', '2/1', null),
('THq3', 'fixed', 'sale A th; cancel; backt 1 20; reopen; cancel; reopen; cancel; reopen; pay',
  '{"status":"paid","net":60,"required":20,"dlgs":3,"queueds":3,"gaves":3,"sess":"3/3 r0 c0 available","swait":0,"stwice":0,"sev":1,"sholder":"A","sinv":"","every":"","error":null}', '2/1', null),
-- S$40, or all S$60, refunded by line first.
('TH2c', 'fixed', 'sale A th; cancel; backt 1 40; reopen; cancel; reopen; pay',
  '{"status":"paid","net":60,"required":40,"dlgs":3,"queueds":3,"gaves":3,"sess":"3/3 r0 c0 available","swait":0,"stwice":0,"sev":1,"sholder":"A","sinv":"","every":"","error":null}', '2/1', null),
('THall', 'fixed', 'sale A th; cancel; backt 1 60; reopen; cancel; reopen; pay',
  '{"status":"paid","net":60,"required":60,"dlgs":3,"queueds":3,"gaves":3,"sess":"3/3 r0 c0 available","swait":0,"stwice":0,"sev":1,"sholder":"A","sinv":"","every":"","error":null}', '2/1', null),
-- Refunded in full first (the sessions refunded, not cancelled).
('THr', 'fixed', 'sale A th; refundall; reopen; cancel; reopen; pay',
  '{"status":"paid","net":60,"required":60,"dlgs":3,"queueds":3,"gaves":3,"sess":"3/3 r0 c0 available","swait":0,"stwice":0,"sev":1,"sholder":"A","sinv":"","every":"","error":null}', '2/1', null),
-- "Record refund paid" (no line) once cancelled again; the guided Cancel
-- with it not ticked, the second time.
('THrp', 'fixed', 'sale A th; cancel; backt 1 20; reopen; cancel; refundpaid; reopen; pay',
  '{"status":"paid","net":60,"required":60,"dlgs":3,"queueds":3,"gaves":3,"sess":"3/3 r0 c0 available","swait":0,"stwice":0,"sev":1,"sholder":"A","sinv":"","every":"","error":null}', '2/1', null),
('THgk', 'fixed', 'sale A th; cancel; backt 1 20; reopen; guidedkeep; reopen; pay',
  '{"status":"paid","net":60,"required":20,"dlgs":3,"queueds":3,"gaves":3,"sess":"3/3 r0 c0 available","swait":0,"stwice":0,"sev":1,"sholder":"A","sinv":"","every":"","error":null}', '2/1', null),
-- The buyer merged into K while it waited; once cancelled again (the
-- sessions follow to K).
('THmg', 'fixed', 'sale A th; cancel; backt 1 20; reopen; merge K A; cancel; reopen; pay',
  '{"status":"paid","net":60,"required":20,"dlgs":3,"queueds":3,"gaves":3,"sess":"3/3 r0 c0 available","swait":0,"stwice":0,"sev":1,"sholder":"K","sinv":"","every":"","error":null}', '2/1', null),
('THmgc', 'fixed', 'sale A th; cancel; backt 1 20; reopen; cancel; merge K A; reopen; pay',
  '{"status":"paid","net":60,"required":20,"dlgs":3,"queueds":3,"gaves":3,"sess":"3/3 r0 c0 available","swait":0,"stwice":0,"sev":1,"sholder":"K","sinv":"","every":"","error":null}', '2/1', null),
-- Beside a S$100 Credit Package (its credit refunded by line, the sessions
-- only cancelled), the S$140 Premium Bundle (2 vouchers), a package with a
-- session paid from it and a voucher line, a voucher line with a unit
-- refunded: the credit and vouchers waiting for the payment are given with it.
('THcpw', 'fixed', 'sale A th,cp; cancel; back 1 100; reopen; cancel; reopen; pay',
  '{"status":"paid","net":160,"required":100,"dlg":100,"gave":100,"holds":{"A":"100.00"},"dlgs":3,"queueds":3,"gaves":3,"sess":"3/3 r0 c0 available","swait":0,"stwice":0,"sev":1,"sholder":"A","sinv":"","every":"","error":null}', '2/1', null),
('THpb', 'fixed', 'sale A th,pbv; cancel; back 1 42; reopen; cancel; reopen; pay',
  '{"status":"paid","net":200,"required":42,"dlg":140,"gave":140,"dlgv":2,"gavev":2,"holds":{"A":"140.00/2"},"dlgs":3,"queueds":3,"gaves":3,"sess":"3/3 r0 c0 available","swait":0,"stwice":0,"sev":1,"sholder":"A","sinv":"","every":"","error":null}', '2/1', null),
('THmix', 'fixed', 'sale A th,cp,v; spend A; cancel; back 1 60; reopen; cancel; reopen; pay',
  '{"status":"paid","net":220,"required":60,"dlg":80,"gave":80,"dlgv":2,"gavev":2,"holds":{"A":"80.00/2"},"dlgs":3,"queueds":3,"gaves":3,"sess":"3/3 r0 c0 available","swait":0,"stwice":0,"sev":1,"sholder":"A","sinv":"","every":"","error":null}', '2/1', null),
('THvs', 'fixed', 'sale A th,v; cancel; backv 1 1; backt 2 20; reopen; cancel; reopen; pay',
  '{"status":"paid","net":120,"required":50,"dlgv":2,"gavev":2,"holds":{"A":"0.00/2"},"dlgs":3,"queueds":3,"gaves":3,"sess":"3/3 r0 c0 available","swait":0,"stwice":0,"sev":1,"sholder":"A","sinv":"","every":"","error":null}', '2/1', null),
-- Settled once through two reopenings, then the same again (before 475 the
-- first payment is refused already: compared up to it).
('THq2p', 'fixed', 'sale A th; cancel; backt 1 20; reopen; cancel; reopen; pay; cancel; backt 1 20; reopen; cancel; reopen; pay',
  '{"status":"paid","net":60,"required":20,"dlgs":3,"queueds":3,"gaves":3,"sess":"3/3 r0 c0 available","swait":0,"stwice":0,"sev":2,"sholder":"A","sinv":"","every":"","error":null}', '2/1', 6),
-- THq settled by the Pay dialog, or by Correct payment (a S$5 payment
-- corrected to S$20): the same trigger reinstates the sessions.
('THpd', 'fixed', 'sale A th; cancel; backt 1 20; reopen; cancel; reopen; paydlg',
  '{"status":"paid","net":60,"required":20,"dlgs":3,"queueds":3,"gaves":3,"sess":"3/3 r0 c0 available","swait":0,"stwice":0,"sev":1,"sholder":"A","sinv":"","every":"","error":null}', '2/1', null),
('THfix', 'fixed', 'sale A th; cancel; backt 1 20; reopen; cancel; reopen; payamt 5; fixpay 20',
  '{"status":"paid","net":60,"required":20,"dlgs":3,"queueds":3,"gaves":3,"sess":"3/3 r0 c0 available","swait":0,"stwice":0,"sev":1,"sholder":"A","sinv":"","every":"","error":null}', '2/1', null),
-- Controls: the same with and without 475.
('TH0', 'control', 'sale A th; cancel; backt 1 20; reopen; pay',
  '{"status":"paid","net":60,"required":20,"dlgs":3,"queueds":3,"gaves":3,"sess":"3/3 r0 c0 available","swait":0,"sev":1,"sinv":"","every":"","error":null}', null, null),
('THcp0', 'control', 'sale A th,cp; cancel; back 1 100; reopen; pay',
  '{"status":"paid","net":160,"required":100,"dlg":100,"gave":100,"holds":{"A":"100.00"},"dlgs":3,"queueds":3,"gaves":3,"sess":"3/3 r0 c0 available","swait":0,"sev":1,"sinv":"","every":"","error":null}', null, null),
('THc', 'control', 'sale A th; cancel; reopen',
  '{"status":"paid","net":60,"required":0,"dlgs":3,"queueds":3,"gaves":3,"sess":"3/3 r0 c0 available","swait":0,"sev":1,"sinv":"","every":"","error":null}', null, null),
('THcc', 'control', 'sale A th; cancel; reopen; cancel; reopen',
  '{"status":"paid","net":60,"required":0,"dlgs":3,"queueds":3,"gaves":3,"sess":"3/3 r0 c0 available","swait":0,"sev":2,"sinv":"","every":"","error":null}', null, null),
('THr1', 'control', 'sale A th; refundall; reopen; pay',
  '{"status":"paid","net":60,"required":60,"dlgs":3,"queueds":3,"gaves":3,"sess":"3/3 r0 c0 available","swait":0,"sev":1,"sinv":"","every":"","error":null}', null, null),
('THgc1', 'control', 'sale A th; guidedcancel; reopen; pay',
  '{"status":"paid","net":60,"required":60,"dlgs":3,"queueds":3,"gaves":3,"sess":"3/3 r0 c0 available","swait":0,"sev":1,"sinv":"","every":"","error":null}', null, null),
('K5', 'control', 'sale A cp; spend A; spend A; cancel; back 1 60; reopen; unspend S2; cancel; reopen; pay',
  '{"dlg":80,"queued":80,"gave":80,"required":60,"every":"","holds":{"A":"80.00"},"status":"paid","net":100,"sess":"-","error":null}', null, null),
('VQ', 'control', 'sale A v; cancel; backv 1 1; reopen; cancel; reopen; pay',
  '{"dlg":0,"gave":0,"dlgv":2,"queuedv":2,"gavev":2,"required":30,"every":"","holds":{"A":"0.00/2"},"status":"paid","net":60,"sess":"-","error":null}', null, null),
-- Known (475's NOT COVERED, the same with and without 475): 1 a session's
-- refund by line, the guided Cancel with the money recorded and Refund in
-- full, while it waits or once cancelled again; 2 a customer change.
('THw', 'known', 'sale A th; cancel; backt 1 20; reopen; backt 1 20',
  '{"status":"partially_paid","error~":"backt 1 20: Settle the reopened invoice before changing its queued sessions%","swait":1,"squeued":3,"stwice":0,"sinv":"","sess":"0/3 r1 c2 refunded"}', null, null),
('THb', 'known', 'sale A th; cancel; backt 1 20; reopen; cancel; backt 1 20',
  '{"status":"cancelled","error~":"backt 1 20: Settle the reopened invoice before changing its queued sessions%","swait":1,"squeued":3,"stwice":0,"sinv":"","sess":"0/3 r1 c2 refunded"}', '1/1', null),
('THgc', 'known', 'sale A th; cancel; backt 1 20; reopen; guidedcancel',
  '{"status":"partially_paid","error~":"guidedcancel: Settle the reopened invoice before changing its queued sessions%","swait":1,"squeued":3,"stwice":0,"sinv":""}', null, null),
('THrf', 'known', 'sale A th; cancel; backt 1 20; reopen; refundall',
  '{"status":"partially_paid","error~":"refundall: Settle the reopened invoice before changing its queued sessions%","swait":1,"squeued":3,"stwice":0,"sinv":""}', null, null),
('THchw', 'known', 'sale A th; cancel; backt 1 20; reopen; change B',
  '{"status":"partially_paid","error~":"change B: Settle the pending session reopening before changing its allocation%","swait":1,"squeued":3,"sholder":"A","sinv":""}', null, null),
('THchc', 'known', 'sale A th; cancel; backt 1 20; reopen; cancel; change B',
  '{"status":"cancelled","error~":"change B: Settle the pending session reopening before changing its allocation%","swait":1,"squeued":3,"sholder":"A","sinv":""}', '1/1', null),
('THchk', 'known', 'sale A th; cancel; backt 1 20; reopen; change B keep',
  '{"status":"partially_paid","error~":"change B keep: Settle the pending session reopening before changing its allocation%","swait":1,"squeued":3,"sholder":"A","sinv":""}', null, null);

-- States for the header's query (Q), made before 475 (R): what it lists for
-- each, by reason, with its count (null: not listed).
create temp table t475_qstates(k text primary key, steps text not null, listed text);
insert into t475_qstates values
  ('Q1', 'sale A th; cancel; backt 1 20; reopen; cancel', '1/1'),
  ('Q1r', 'sale A th; refundall; reopen; cancel', '1/1'),
  ('Q1v', 'sale A th,v; cancel; backv 1 1; backt 2 20; reopen; cancel', '1/1'),
  ('Q2', 'sale A th; cancel; backt 1 20; reopen; cancel; reopen', '2/1'),
  ('Q2c', 'sale A th; cancel; backt 1 20; reopen; cancel; reopen; cancel', '2/1'),
  ('Q3', 'sale A th; cancel; backt 1 20; reopen; cancel; shrink', '1/1,3/1'),
  ('Q0', 'sale A th; cancel; backt 1 20', null),
  ('Q0b', 'sale A th; cancel; backt 1 20; reopen', null),
  ('Q0c', 'sale A th; cancel; backt 1 20; reopen; pay', null);
-- A case's steps with its last one (its payment) left out, or up to step n.
create function pg_temp.t475_upto(p_steps text, p_n int) returns text language sql as $f$
  select array_to_string((string_to_array(p_steps, ';'))[1:coalesce(p_n, cardinality(string_to_array(p_steps, ';')) - 1)], ';') $f$;

-- ===== S. Where it starts =====
do $$ begin
  perform pg_temp.t475_check(pg_temp.t475_462_in() and pg_temp.t475_463_in() and pg_temp.t475_470_in() and pg_temp.t475_471_in()
      and pg_temp.t475_472_in() and pg_temp.t475_473_in() and pg_temp.t475_474_in(),
    'S 462, 463, 470, 471, 472, 473 and 474 are in (475 goes in after them)');
  perform pg_temp.t475_check((select string_agg(pg_get_triggerdef(t.oid), E'\n' order by t.tgname) from pg_trigger t
                               where t.tgrelid = 'public.invoices'::regclass and t.tgfoid = 'public.trg_create_therapy_sessions_on_paid()'::regprocedure)
      = 'CREATE TRIGGER create_therapy_sessions_on_paid AFTER UPDATE OF status ON public.invoices FOR EACH ROW EXECUTE FUNCTION trg_create_therapy_sessions_on_paid()',
    'S the trigger that reinstates a reopening''s sessions at settlement is as read');
end $$;
\if :{?nomig}
do $$ begin
  perform pg_temp.t475_check(pg_temp.t475_in() and pg_temp.t475_at('after'), 'S -v nomig=1: 475 is in, as tested');
end $$;
\else
do $$ begin
  perform pg_temp.t475_check(not pg_temp.t475_in() and pg_temp.t475_at('before'),
    'S 475 is not in yet and reopen_invoice is 458''s (this suite installs it; use -v nomig=1 where it is in)');
end $$;

-- ===== R. Before 475: each case reproduced (undone afterwards) =====
-- A 'fixed' case's payment is refused ("Therapy session reopening
-- changed"), its session queued twice (or three times) while the dialog
-- said 3; a control and a known case end exactly as expected. Each fixed
-- case is also run up to its payment (compared in A).
savepoint t475_r;
do $$
declare c record; o jsonb; res text := '';
begin
  for c in select * from t475_cases order by ord loop
    o := pg_temp.t475_run('before', c.k, c.steps);
    if c.kind = 'fixed' then
      -- refused at its payment (THpd, THfix: the Pay dialog, Correct payment)
      perform pg_temp.t475_check(o->>'error' like case when c.k = 'THpd' then 'paydlg' when c.k = 'THfix' then 'fixpay 20' else 'pay' end
                                                  || ': Therapy session reopening changed; reload its original evidence%'
          and (o->>'stwice')::int = 1 and coalesce(o->>'every', '') <> '' and (o->>'dlgs')::int = 3
          and (o->>'squeued')::int > (o->>'dlgs')::int and coalesce(o->>'invariants', '') = '',
        'R ' || c.k || ' without 475 the payment is not refused, or something else differs: ' || o::text);
      res := res || format(E'\n  %s: %s sessions shown, %s queued, the payment refused (%s)', c.k, o->>'dlgs', o->>'squeued', o->>'status');
      perform pg_temp.t475_run('before', c.k || '-pre', pg_temp.t475_upto(c.steps, c.pre));
    else
      perform pg_temp.t475_check(pg_temp.t475_meets(o, c.expect) and coalesce(o->>'invariants', '') = ''
          and coalesce((o->>'cancel_left')::numeric, 0) = 0,
        'R ' || c.kind || ' ' || c.k || ' without 475: ' || coalesce(pg_temp.t475_diff(o, c.expect), '') || ' ' || o::text);
    end if;
  end loop;
  for c in select * from t475_qstates loop
    perform pg_temp.t475_run('before', c.k, c.steps);
  end loop;
  raise notice 'PASS R: without 475 every fixed case''s session is queued again by its second reopening and the payment that settles it is refused ("Therapy session reopening changed; reload its original evidence"; the fault reproduced), the controls and the known cases as expected:%', res;
end $$;

-- ===== Q. The header's read-only query, on these states =====
do $$
declare c record;
begin
  for c in select k, listed from t475_qstates union all select k, q from t475_cases loop
    perform pg_temp.t475_check(pg_temp.t475_listed(pg_temp.t475_id('before/' || c.k || '/inv')) is not distinct from c.listed,
      'Q ' || c.k || ' is listed as ' || coalesce(pg_temp.t475_listed(pg_temp.t475_id('before/' || c.k || '/inv')), 'nothing')
      || ', not ' || coalesce(c.listed, 'nothing'));
  end loop;
  raise notice 'PASS Q: the header''s query lists, by reason, a cancelled or refunded invoice with a session waiting once (1: Q1, Q1r, Q1v, THb, THchc), a session queued twice (2: Q2, Q2c, every fixed case as it ends before 475), a waiting row no longer what its session shows (3: Q3, by hand); nothing never reopened, waiting once or settled (Q0, Q0b, Q0c, the controls)';
end $$;
select coalesce(jsonb_object_agg(k, v), '{}'::jsonb)::text as t475_rbefore from t475_res where phase = 'before' \gset
rollback to savepoint t475_r;
insert into t475_res select 'before', key, value from jsonb_each(:'t475_rbefore'::jsonb);

-- ===== 9. The refusals, each changing nothing =====
-- 9a reopen_invoice is neither 458's nor 475's.
savepoint t475_9;
alter function public.reopen_invoice(uuid,text,uuid) set work_mem = '64kB';
\set ON_ERROR_STOP off
\ir ../../../supabase/475_reopen_sessions_queued_once.sql
\set ON_ERROR_STOP on
rollback to savepoint t475_9;
select set_config('t475.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t475_check(current_setting('t475.msg') like '475: public.reopen_invoice(uuid,text,uuid) is not the version this was tested against (md5 %). Re-read it and re-test before applying.'
      and not pg_temp.t475_in() and pg_temp.t475_at('before'), '9a refused with: ' || current_setting('t475.msg'));
end $$;
-- 9b A function it relies on is not as read (a setting added to it): what
-- reinstates at settlement, what refuses to touch a waiting session, the
-- dialog's preview.
savepoint t475_9;
alter function public.trg_create_therapy_sessions_on_paid() set work_mem = '64kB';
\set ON_ERROR_STOP off
\ir ../../../supabase/475_reopen_sessions_queued_once.sql
\set ON_ERROR_STOP on
rollback to savepoint t475_9;
select set_config('t475.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t475_check(current_setting('t475.msg') like '475: public.trg_create_therapy_sessions_on_paid() is missing or not the version this was tested against (md5 %). Re-read it and re-test before applying (475 goes in after 474).'
      and not pg_temp.t475_in(), '9b refused with: ' || current_setting('t475.msg'));
end $$;
savepoint t475_9;
alter function public.refund_invoice_therapy_sessions(uuid,numeric,text,uuid) set work_mem = '64kB';
\set ON_ERROR_STOP off
\ir ../../../supabase/475_reopen_sessions_queued_once.sql
\set ON_ERROR_STOP on
rollback to savepoint t475_9;
select set_config('t475.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t475_check(current_setting('t475.msg') like '475: public.refund_invoice_therapy_sessions(uuid,numeric,text,uuid) is missing or not the version%'
      and not pg_temp.t475_in(), '9b2 refused with: ' || current_setting('t475.msg'));
end $$;
savepoint t475_9;
alter function public.invoice_reopen_preview_before_sessions(uuid) set work_mem = '64kB';
\set ON_ERROR_STOP off
\ir ../../../supabase/475_reopen_sessions_queued_once.sql
\set ON_ERROR_STOP on
rollback to savepoint t475_9;
select set_config('t475.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t475_check(current_setting('t475.msg') like '475: public.invoice_reopen_preview_before_sessions(uuid) is missing or not the version%'
      and not pg_temp.t475_in(), '9b3 refused with: ' || current_setting('t475.msg'));
end $$;
-- 9c Another function takes its name (an overload).
savepoint t475_9;
create function public.reopen_invoice(p text) returns jsonb language sql as $f$ select null::jsonb $f$;
\set ON_ERROR_STOP off
\ir ../../../supabase/475_reopen_sessions_queued_once.sql
\set ON_ERROR_STOP on
rollback to savepoint t475_9;
select set_config('t475.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t475_check(current_setting('t475.msg') = '475: another function takes the name of the one this changes: reopen_invoice(text)'
      and not pg_temp.t475_in(), '9c refused with: ' || current_setting('t475.msg'));
end $$;
-- 9d A new caller of reopen_invoice.
savepoint t475_9;
create function public.t475_probe_reopen(p uuid) returns jsonb language sql as $f$ select public.reopen_invoice(p, 'probe', gen_random_uuid()) $f$;
\set ON_ERROR_STOP off
\ir ../../../supabase/475_reopen_sessions_queued_once.sql
\set ON_ERROR_STOP on
rollback to savepoint t475_9;
select set_config('t475.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t475_check(current_setting('t475.msg') like '475: functions call reopen_invoice (%t475_probe_reopen(uuid)%), not as read on 27 Oct 2026%'
      and not pg_temp.t475_in(), '9d refused with: ' || current_setting('t475.msg'));
end $$;
-- 9e A new reader, or writer, of the session queue; a new writer of the
-- sessions.
savepoint t475_9;
create function public.t475_probe_queue() returns bigint language sql as $f$ select count(*) from public.invoice_reopen_sessions $f$;
\set ON_ERROR_STOP off
\ir ../../../supabase/475_reopen_sessions_queued_once.sql
\set ON_ERROR_STOP on
rollback to savepoint t475_9;
select set_config('t475.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t475_check(current_setting('t475.msg') like '475: what reads or writes the session queue (invoice_reopen_sessions) is not as read on 27 Oct 2026 (%t475_probe_queue()%'
      and not pg_temp.t475_in(), '9e refused with: ' || current_setting('t475.msg'));
end $$;
savepoint t475_9;
create function public.t475_probe_queue2() returns void language sql as $f$ update public.invoice_reopen_sessions set quantity = quantity where false $f$;
\set ON_ERROR_STOP off
\ir ../../../supabase/475_reopen_sessions_queued_once.sql
\set ON_ERROR_STOP on
rollback to savepoint t475_9;
select set_config('t475.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t475_check(current_setting('t475.msg') like '475: what reads or writes the session queue (invoice_reopen_sessions) is not as read on 27 Oct 2026 (%t475_probe_queue2()% / %t475_probe_queue2()%'
      and not pg_temp.t475_in(), '9e2 refused with: ' || current_setting('t475.msg'));
end $$;
savepoint t475_9;
create function public.t475_probe_sessions() returns void language sql as $f$ update public.customer_therapy_sessions set notes = notes where false $f$;
\set ON_ERROR_STOP off
\ir ../../../supabase/475_reopen_sessions_queued_once.sql
\set ON_ERROR_STOP on
rollback to savepoint t475_9;
select set_config('t475.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t475_check(current_setting('t475.msg') like '475: what updates the therapy sessions (customer_therapy_sessions) is not as read on 27 Oct 2026 (%t475_probe_sessions()%'
      and not pg_temp.t475_in(), '9e3 refused with: ' || current_setting('t475.msg'));
end $$;
-- 9f The trigger that reinstates at settlement is not as read.
savepoint t475_9;
drop trigger create_therapy_sessions_on_paid on public.invoices;
create trigger create_therapy_sessions_on_paid after update of status, paid_amount on public.invoices
  for each row execute function public.trg_create_therapy_sessions_on_paid();
\set ON_ERROR_STOP off
\ir ../../../supabase/475_reopen_sessions_queued_once.sql
\set ON_ERROR_STOP on
rollback to savepoint t475_9;
select set_config('t475.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t475_check(current_setting('t475.msg') = '475: the trigger that reinstates a reopening''s therapy sessions at settlement is not as read on 27 Oct 2026'
      and not pg_temp.t475_in(), '9f refused with: ' || current_setting('t475.msg'));
end $$;
-- 9g The queue no longer holds one row per session and reopening; a column
-- read is not of its type.
savepoint t475_9;
alter table public.invoice_reopen_sessions drop constraint invoice_reopen_sessions_session_id_request_id_key;
\set ON_ERROR_STOP off
\ir ../../../supabase/475_reopen_sessions_queued_once.sql
\set ON_ERROR_STOP on
rollback to savepoint t475_9;
select set_config('t475.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t475_check(current_setting('t475.msg') like '475: the session queue''s keys are not as read on 27 Oct 2026%'
      and not pg_temp.t475_in(), '9g refused with: ' || current_setting('t475.msg'));
end $$;
savepoint t475_9;
alter table public.invoice_reopen_sessions alter column quantity type bigint;
\set ON_ERROR_STOP off
\ir ../../../supabase/475_reopen_sessions_queued_once.sql
\set ON_ERROR_STOP on
rollback to savepoint t475_9;
select set_config('t475.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t475_check(current_setting('t475.msg') = '475: these columns are missing or not as read on 27 Oct 2026: invoice_reopen_sessions.quantity'
      and not pg_temp.t475_in(), '9g2 refused with: ' || current_setting('t475.msg'));
end $$;
-- 9h Other grants: refused. The same grants in another order: not.
savepoint t475_9;
grant execute on function public.reopen_invoice(uuid,text,uuid) to anon;
\set ON_ERROR_STOP off
\ir ../../../supabase/475_reopen_sessions_queued_once.sql
\set ON_ERROR_STOP on
rollback to savepoint t475_9;
select set_config('t475.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t475_check(current_setting('t475.msg') like '475: who may call public.reopen_invoice(uuid,text,uuid) is not as read on 27 Oct 2026 (%)'
      and not pg_temp.t475_in(), '9h refused with: ' || current_setting('t475.msg'));
end $$;
savepoint t475_9;
revoke execute on function public.reopen_invoice(uuid,text,uuid) from postgres;
grant execute on function public.reopen_invoice(uuid,text,uuid) to postgres;
select pg_temp.t475_check((select proacl::text from pg_proc where oid = 'public.reopen_invoice(uuid,text,uuid)'::regprocedure)
         <> '{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}'
       and pg_temp.t475_grant_set('reopen_invoice(uuid,text,uuid)') = '{authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres}',
  '9h2 set-up: the same grants in another order');
\ir ../../../supabase/475_reopen_sessions_queued_once.sql
select pg_temp.t475_in() and pg_temp.t475_at('after') as t475_9h2_in \gset
rollback to savepoint t475_9;
select pg_temp.t475_check(:'t475_9h2_in'::boolean and not pg_temp.t475_in(), '9h2 the same grants in another order stopped it');
do $$ begin
  raise notice 'PASS 9: refused, changing nothing, where reopen_invoice is neither 458''s nor 475''s, a function it relies on is not as tested (what reinstates at settlement, what refuses to touch a waiting session, the dialog''s preview), another function takes its name, a new function calls it, reads or writes the session queue or updates the sessions, the settlement trigger, the queue''s unique key or a column read is not as read, or other grants; the same grants in another order do not stop it';
end $$;

-- ===== M. Begun before 475, finished after it =====
-- Cancelled again with a session waiting (MQ1), waiting (MW), queued twice
-- (MQ2: NOT COVERED 3).
do $$ begin
  perform pg_temp.t475_run('mid', 'MQ1', 'sale A th; cancel; backt 1 20; reopen; cancel; reopen; pay', 1, 5);
  perform pg_temp.t475_run('mid', 'MW', 'sale A th; cancel; backt 1 20; reopen; cancel; reopen; pay', 1, 4);
  perform pg_temp.t475_run('mid', 'MQ2', 'sale A th; cancel; backt 1 20; reopen; cancel; reopen; pay', 1, 6);
  perform pg_temp.t475_check(pg_temp.t475_listed(pg_temp.t475_id('mid/MQ1/inv')) = '1/1' and pg_temp.t475_listed(pg_temp.t475_id('mid/MW/inv')) is null
      and pg_temp.t475_listed(pg_temp.t475_id('mid/MQ2/inv')) = '2/1', 'M the header''s query before 475');
end $$;
\endif

-- ===== 10. Install 475, twice =====
\if :{?nomig}
do $$ begin raise notice 'NOTE 10: -v nomig=1, so 475 is not installed here (R, Q, 9 and M are skipped)'; end $$;
\else
\ir ../../../supabase/475_reopen_sessions_queued_once.sql
do $$ begin insert into t475_fp values ('first', pg_temp.t475_fingerprint()); end $$;
\ir ../../../supabase/475_reopen_sessions_queued_once.sql
do $$ begin insert into t475_fp values ('second', pg_temp.t475_fingerprint()); end $$;
\endif
do $$
begin
  perform pg_temp.t475_check(pg_temp.t475_in() and pg_temp.t475_at('after'), '10 475 is not installed as tested');
  perform pg_temp.t475_check((select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'reopen_invoice') = 1,
    '10 an overload exists');
  perform pg_temp.t475_check(pg_temp.t475_grant_set('reopen_invoice(uuid,text,uuid)') = '{authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres}'
      and not has_function_privilege('anon', 'public.reopen_invoice(uuid,text,uuid)', 'execute'),
    '10 who may call reopen_invoice changed');
  if exists (select 1 from t475_fp where k = 'first') then
    perform pg_temp.t475_check((select fp from t475_fp where k = 'second') = (select fp from t475_fp where k = 'first'),
      '10 the second run of 475 changed functions');
    perform pg_temp.t475_check(split_part((select fp from t475_fp where k = 'first'), ' ', 2) = split_part((select fp from t475_fp where k = 'start'), ' ', 2),
      '10 475 changed the number of functions');
    perform pg_temp.t475_check(pg_temp.t475_grants() = (select fp from t475_fp where k = 'grants'), '10 the grants changed');
    -- On a copy of production at 474: the AFTER fingerprint.
    if (select fp from t475_fp where k = 'start') = 'c19401919a0a8b67746e18b8f7a78639 1387' then
      perform pg_temp.t475_check((select fp from t475_fp where k = 'first') = 'e948504da4c17c1c15ff871fcb1e5631 1387',
        '10 the fingerprint after 475 is ' || (select fp from t475_fp where k = 'first'));
    end if;
  end if;
  raise notice 'PASS 10: 475 installed (reopen_invoice %); %; no overload; the grants as before (signed-in staff and the service role, never anon)',
    md5(pg_get_functiondef('public.reopen_invoice(uuid,text,uuid)'::regprocedure)),
    coalesce('the second run changed nothing (' || (select fp from t475_fp where k = 'second') || ')', 'it was in before the suite (nomig)');
end $$;

-- ===== M (finished). Begun before 475, finished after it =====
\if :{?nomig}
do $$ begin raise notice 'NOTE M: -v nomig=1 (475 in), so no case was begun before it'; end $$;
\else
do $$
declare o jsonb;
begin
  -- MQ1: cancelled again before 475 with the session waiting once;
  -- reopened after it: queued once, the payment reinstates it once.
  o := pg_temp.t475_run('mid', 'MQ1', 'sale A th; cancel; backt 1 20; reopen; cancel; reopen; pay', 6);
  perform pg_temp.t475_check(pg_temp.t475_meets(o, '{"status":"paid","dlgs":3,"queueds":3,"gaves":3,"sess":"3/3 r0 c0 available","swait":0,"sev":1,"sinv":"","every":"","error":null}'),
    'M MQ1 ' || o::text);
  -- MW: waiting before 475; cancelled and reopened after it: the same.
  o := pg_temp.t475_run('mid', 'MW', 'sale A th; cancel; backt 1 20; reopen; cancel; reopen; pay', 5);
  perform pg_temp.t475_check(pg_temp.t475_meets(o, '{"status":"paid","dlgs":3,"queueds":3,"gaves":3,"sess":"3/3 r0 c0 available","swait":0,"sev":1,"sinv":"","every":"","error":null}'),
    'M MW ' || o::text);
  -- MQ2: queued twice before 475: its payment is still refused (NOT
  -- COVERED 3; 475 repairs no row), and a further reopening queues nothing.
  o := pg_temp.t475_run('mid', 'MQ2', 'sale A th; cancel; backt 1 20; reopen; cancel; reopen; pay', 7);
  perform pg_temp.t475_check(o->>'error' like 'pay: Therapy session reopening changed; reload its original evidence%' and (o->>'swait')::int = 2
      and (o->>'squeued')::int = 6 and pg_temp.t475_listed(pg_temp.t475_id('mid/MQ2/inv')) = '2/1', 'M MQ2 ' || o::text);
  perform pg_temp.t475_put('mid/MQ2b/inv', pg_temp.t475_id('mid/MQ2/inv'));
  o := pg_temp.t475_run('mid', 'MQ2b', 'cancel; reopen; pay');
  perform pg_temp.t475_check(o->>'error' like 'pay: Therapy session reopening changed; reload its original evidence%' and (o->>'swait')::int = 2
      and (o->>'squeued')::int = 6, 'M MQ2 cancelled and reopened after 475 ' || o::text);
  raise notice 'PASS M: begun before 475 (cancelled again with a session waiting; waiting), finished after it: the session queued once and reinstated once; queued twice before 475 (MQ2): still refused, and a further reopening queues nothing more (NOT COVERED 3)';
end $$;
\endif

-- ===== A. After 475: each case =====
do $$
declare c record; o jsonb; b jsonb; pa jsonb; pb jsonb; res text := ''; n int := 0;
begin
  for c in select * from t475_cases order by ord loop
    o := pg_temp.t475_run('after', c.k, c.steps);
    perform pg_temp.t475_check(pg_temp.t475_meets(o, c.expect) and coalesce(o->>'invariants', '') = '' and coalesce(o->>'sinv', '') = ''
        and coalesce((o->>'cancel_left')::numeric, 0) = 0,
      'A ' || c.kind || ' ' || c.k || ': ' || coalesce(pg_temp.t475_diff(o, c.expect), '') || ' ' || o::text);
    b := (select v from t475_res where phase = 'before' and k = c.k);
    if c.kind = 'fixed' then
      pa := pg_temp.t475_run('after', c.k || '-pre', pg_temp.t475_upto(c.steps, c.pre));
      perform pg_temp.t475_check((pa->>'swait')::int = 1 and (pa->>'stwice')::int = 0 and coalesce(pa->>'sinv', '') = '' and pa->>'every' = '',
        'A ' || c.k || ' before its payment: ' || pa::text);
      res := res || format(' %s %s/%s;', c.k, o->>'dlgs', o->>'gaves');
    end if;
    -- Where R ran: a fixed case up to its payment as before 475 but the
    -- queue; a control or known case exactly as before 475.
    if b is not null then
      if c.kind = 'fixed' then
        pb := (select v from t475_res where phase = 'before' and k = c.k || '-pre');
        perform pg_temp.t475_check(pg_temp.t475_but_queue(pa) = pg_temp.t475_but_queue(pb),
          'A ' || c.k || ' differs from before 475 up to its payment beyond the queue: before ' || pg_temp.t475_but_queue(pb)::text
          || ', after ' || pg_temp.t475_but_queue(pa)::text);
      else
        perform pg_temp.t475_check(o = b, 'A ' || c.kind || ' ' || c.k || ' differs from before 475: ' || b::text || ' / ' || o::text);
      end if;
      n := n + 1;
    end if;
  end loop;
  raise notice 'PASS A: after 475 every fixed case is paid, each session reinstated once, the dialog''s sessions what was queued and reinstated (shown/reinstated):%; the controls and known cases as before; % cases compared with before 475: nothing else differs (up to the payment for a fixed case: who holds what, the money, the plans, the invariants, Cancel, the dialog)', res, n;
end $$;

-- ===== P. Probes =====
-- P1 reopen_invoice's text beside the sessions step is exactly 458's: 458's
-- text worked back from 475's (its sessions step put back; by md5).
create function pg_temp.t475_def458() returns text language plpgsql as $f$
declare d text := pg_get_functiondef('public.reopen_invoice(uuid,text,uuid)'::regprocedure);
  a int; z int; m text := E'quantity_cancelled-coalesce(w.quantity,0)>0;\n';
begin
  a := position(E' -- 475 (the Owner' in d);
  z := position(m in d);
  if a = 0 or z = 0 then return null; end if;
  return substr(d, 1, a - 1)
    || E' insert into public.invoice_reopen_sessions(invoice_id,session_id,request_id,quantity)\n'
    || E' select i.id,s.id,p_request_id,s.quantity_refunded+s.quantity_cancelled from public.customer_therapy_sessions s\n'
    || E' where s.invoice_id=i.id and s.is_current and s.quantity_refunded+s.quantity_cancelled>0;\n'
    || substr(d, z + length(m));
end $f$;
do $$ begin
  perform pg_temp.t475_check(md5(pg_temp.t475_def458()) = '0ff61e4ead121c198ea7f90a7fc78274',
    'P1 458''s text is not what 475''s gives back with its sessions step put back: ' || coalesce(md5(pg_temp.t475_def458()), 'null'));
  raise notice 'PASS P1: reopen_invoice beside its sessions step is exactly 458''s (the blockers, the revision, the credit and voucher queues, the stock, the status, the special items, the commissions, the Audit Log row)';
end $$;
-- P2 What a reopening records: the revision's snapshot ('reopen_preview')
-- and its Audit Log row ('invoice_reopened') carry the dialog's sessions
-- (THq: 3 each time); P3 the one reinstatement: one 'reopen' event of 3,
-- under the request of the first reopening (its queue row), applied.
do $$
declare inv uuid := pg_temp.t475_id('after/THq/inv'); s uuid;
begin
  perform pg_temp.t475_check((select array_agg((r.snapshot->'reopen_preview'->>'sessions_to_reinstate_after_settlement')::int order by r.revision_no)
                                from invoice_revisions r where r.invoice_id = inv and r.snapshot ? 'reopen_preview') = '{3,3}'
      and (select array_agg((a.new_data->>'sessions_to_reinstate_after_settlement')::int) from audit_logs a
            where a.record_id = inv and a.action = 'invoice_reopened') = '{3,3}',
    'P2 THq: the reopenings recorded other session counts');
  select id into s from customer_therapy_sessions where invoice_id = inv and is_current;
  perform pg_temp.t475_check((select count(*) from invoice_therapy_session_events e where e.session_id = s and e.event_kind = 'reopen') = 1
      and (select e.quantity from invoice_therapy_session_events e where e.session_id = s and e.event_kind = 'reopen') = 3
      and (select e.request_id from invoice_therapy_session_events e where e.session_id = s and e.event_kind = 'reopen')
          = (select r.request_id from invoice_revisions r where r.invoice_id = inv and r.snapshot ? 'reopen_preview' order by r.revision_no limit 1)
      and (select count(*) from invoice_reopen_sessions q where q.session_id = s) = 1
      and (select count(*) from invoice_reopen_sessions q where q.session_id = s and q.applied_at is not null) = 1,
    'P3 THq: the reinstatement is not one event of 3 under the first reopening''s request');
  raise notice 'PASS P2, P3: a reopening records the dialog''s sessions (its revision''s snapshot and its Audit Log row: 3, 3 for THq); the payment reinstated the session once (one event of 3), under the first reopening''s request, its one queue row applied';
end $$;
-- P4 Nothing added or dropped; the grants as before.
do $$ begin
  perform pg_temp.t475_check(split_part(pg_temp.t475_fingerprint(), ' ', 2) = split_part((select fp from t475_fp where k = 'start'), ' ', 2)
      and pg_temp.t475_grants() = (select fp from t475_fp where k = 'grants'),
    'P4 the functions or grants changed: ' || pg_temp.t475_fingerprint());
  raise notice 'PASS P4: no function added or dropped; the grant list as before';
end $$;

-- ===== K. KNOWN (475's NOT COVERED), checked as they are =====
do $$
declare o jsonb; inv uuid;
begin
  -- K1 (NOT COVERED 1): a session's refund by line while its reopening
  -- waits or once cancelled again, the guided Cancel with the money recorded
  -- and Refund in full while it waits: refused (252's rule), after 475 as
  -- before; "Record refund paid" with no line then works (THrp).
  perform pg_temp.t475_check((select bool_and(v->>'error' like '%: Settle the reopened invoice before changing its queued sessions%')
                                from t475_res where phase = 'after' and k in ('THw', 'THb', 'THgc', 'THrf'))
      and (select count(*) from t475_res where phase = 'after' and k in ('THw', 'THb', 'THgc', 'THrf')) = 4
      and (select v->>'status' from t475_res where phase = 'after' and k = 'THrp') = 'paid',
    'K1: look at NOT COVERED 1 again');
  -- K2 (NOT COVERED 2): a customer change while a session waits, or once
  -- cancelled again: refused (252's rule).
  perform pg_temp.t475_check((select bool_and(v->>'error' like '%: Settle the pending session reopening before changing its allocation%')
                                from t475_res where phase = 'after' and k in ('THchw', 'THchc', 'THchk'))
      and (select count(*) from t475_res where phase = 'after' and k in ('THchw', 'THchc', 'THchk')) = 3,
    'K2: look at NOT COVERED 2 again');
  -- K3 (NOT COVERED 3): a session queued twice before 475 (made by hand,
  -- 'dup'): listed by the header's query (2); reopened again after 475,
  -- nothing more is queued; its payment is still refused.
  perform pg_temp.t475_run('K', 'THdup', 'sale A th; cancel; backt 1 20; reopen; cancel; dup; reopen; pay', 1, 7);
  inv := pg_temp.t475_id('K/THdup/inv');
  perform pg_temp.t475_check(pg_temp.t475_listed(inv) = '2/1'
      and (select count(*) from invoice_reopen_sessions q where q.invoice_id = inv and q.applied_at is null) = 2, 'K3 THdup: look at NOT COVERED 3 again');
  o := pg_temp.t475_run('K', 'THdup', 'sale A th; cancel; backt 1 20; reopen; cancel; dup; reopen; pay', 8);
  perform pg_temp.t475_check(o->>'error' like 'pay: Therapy session reopening changed; reload its original evidence%'
      and (o->>'swait')::int = 2 and (o->>'squeued')::int = 6, 'K3 THdup paid: ' || o::text);
  -- K4 (NOT COVERED 4): a waiting row no longer what its session shows (by
  -- hand, 'shrink': 2 of 3): listed (1 and 3); the next reopening queues the
  -- difference (1), and the payment's evidence check refuses it.
  perform pg_temp.t475_run('K', 'THshr', 'sale A th; cancel; backt 1 20; reopen; cancel; shrink; reopen; pay', 1, 6);
  inv := pg_temp.t475_id('K/THshr/inv');
  perform pg_temp.t475_check(pg_temp.t475_listed(inv) = '1/1,3/1', 'K4 THshr listed as ' || coalesce(pg_temp.t475_listed(inv), 'nothing'));
  o := pg_temp.t475_run('K', 'THshr', 'sale A th; cancel; backt 1 20; reopen; cancel; shrink; reopen; pay', 7);
  perform pg_temp.t475_check(o->>'error' like 'pay: Therapy session reopening changed; reload its original evidence%'
      and (select array_agg(q.quantity order by q.quantity desc) from invoice_reopen_sessions q where q.invoice_id = inv and q.applied_at is null) = '{2,1}',
    'K4 THshr: ' || o::text);
  raise notice 'KNOWN K: (475''s NOT COVERED) (1) a session''s refund by line, the guided Cancel with the money recorded and Refund in full while its reopening waits or once cancelled again: refused, "Settle the reopened invoice before changing its queued sessions" ("Record refund paid" with no line works); (2) a customer change then: refused, "Settle the pending session reopening before changing its allocation"; (3) a session queued twice before 475: still refused, nothing more queued; (4) a waiting row no longer what its session shows: the difference queued, the payment refused';
end $$;

rollback;
