-- 474: the Reopen dialog's "Revoked credit to reinstate after settlement"
-- also counts the credit an earlier reopening queued that still waits, so it
-- says what the payment that settles the invoice gives back (471's NOT
-- COVERED 7, its suite's KNOWN K5; an older gap, 417 and 451; the Owner, 26
-- Oct 2026: "fix the leftover gaps too").
-- supabase/474_reopen_dialog_counts_waiting_credit.sql (after 462, 463, 470,
-- 471, 472 and 473).
--
-- Every step goes through the app's own calls (471's suite harness, its
-- steps and readings, renamed): the invoice form (create_invoice_with_
-- details) and the Pay dialog (record_invoice_settlement), Record Payment,
-- Cancel, Reopen, the Finance panel's refund by line (of credit, of voucher
-- units: 'backv', of a therapy line's sessions by money: 'backt') and
-- "Record refund paid" (refund_invoice_recorded), its Correct payment
-- (correct_invoice_payment), the guided Refund in full and Cancel, the
-- invoice form's customer change (correct_invoice, 'transfer'), a customer
-- merge. Before each Reopen the Reopen dialog is read as the Finance panel
-- reads it (invoice_reopen_preview: every figure it shows, InvoiceFinance
-- Panel.tsx), and after each step what the reopening queued and what the
-- payment that settles it gave back (credit: the 'Reopened invoice settled'
-- rows, apply_reopened_invoice_benefits; voucher units given again,
-- apply_reopened_invoice_vouchers; sessions reinstated, trg_create_therapy_
-- sessions_on_paid). Each app call is followed by what its commit does
-- (462's trigger on the ledger is DEFERRABLE INITIALLY DEFERRED and this
-- suite is one transaction: SET CONSTRAINTS ... IMMEDIATE, then DEFERRED).
--
-- The cases (A the buyer; B a later customer; K a record a merge keeps; cp
-- the S$100 Credit Package, pbv the S$140 Premium Bundle with 2 vouchers, v
-- a voucher line of 2 units at S$30, th a therapy line of 3 sessions at
-- S$20; S1, S2 S$20 sessions paid from the package's credit; 'cp 40': S$40
-- of S$100 paid). What a case reads: 'dlg' the dialog's credit to reinstate
-- at its last Reopen, 'queued' what that Reopen left waiting (or gave at
-- once, reopened straight to paid), 'gave' what was given back from it to
-- the end; 'dlgv'/'queuedv'/'gavev' the same for voucher units, 'dlgs' and
-- 'gaves' for sessions, 'required' the payment required to settle again;
-- 'every' each Reopen whose dialog said other than what it queued:
--   K5          471's K5: cancelled, S$60 refunded by line, reopened (it
--               waits), S2 refunded (held back, queued), cancelled again,
--               reopened, paid.
--   CQ, CQ3, CQ3s  Cancel's own row an earlier reopening queued (the older
--               gap); a third reopening; with S2 refunded.
--   WB, WB10, WBc, WBc10  a refund by line while it waited, or once cancelled
--               again (S$20; S$10).
--   WG, WK      the guided Cancel the second time ("Record refund paid"
--               ticked; not).
--   WFa, WX     S2's payment corrected to S$5 less while it waited; a refund
--               in full with an override after the second Cancel.
--   CHw, CHws, MGw  a 'transfer' change to B while it waited (with S2
--               refunded); the buyer merged into K while it waited.
--   RXq, RXqs, GCq  refunded in full first (with S1 refunded while it
--               waited); a guided Cancel first.
--   PBq, PBqs, MIX  the Premium Bundle (with S2 refunded); with a voucher
--               line beside it.
--   PTF, PTF2   paid in part, cancelled, reopened and paid in full, then
--               K5's steps (with S1 refunded while it waited).
--   Controls (the same with and without 474): CTL0 (reopened straight to
--   paid), CTL1, CTL2 (a first reopening; S2 refunded while it waits adds to
--   the queue after the dialog), PRc (S2 refunded while cancelled), VQ, VQ3,
--   VQ0 (voucher units), TH0 (sessions, a first reopening), PT0, PTq (paid
--   in part).
--   Known (474's NOT COVERED, the same with and without 474): THq (sessions
--   queued twice: the payment refused), PT0 (paid in part: released again
--   at the reopening itself, not counted after settlement).
-- In every case 462's invariants (471's reading of them) and Cancel (tried,
-- undone) taking all of the invoice's credit back from whoever holds it.
--
--   S. Where it starts: 462, 463, 470, 471, 472 and 473 in; 474 in (nomig)
--      or not, the preview at 451's AFTER.
--   R. Without 474 (skipped with -v nomig=1), undone: each 'fixed' case's
--      dialog says other than what the payment gives (the fault reproduced:
--      K5 S$0.00 shown, S$80 given; ...); each control and known case as
--      expected.
--   Q. The read-only query in 474's header (the same text), on states made
--      for it and the R states: what it lists, by reason (1 to 4).
--   9. Refusals, each changing nothing: the preview neither 451's nor 474's;
--      a function it relies on not as tested; an overload of its name; a new
--      caller of the preview; a new writer of the reopening queue; the
--      settlement trigger not as read; the queue's unique key gone; other
--      grants. The same grants in another order do not stop it.
--   M. Begun before 474 (a reopening cancelled again, one waiting, one
--      changed to B while it waited), the dialog read after it.
--  10. 474 installed twice: as tested, the second run changing nothing,
--      nothing added, the grants as before.
--   A. Each case after 474: the dialog's credit is what its Reopen queued
--      and what the payment gives; who holds what, the money, the plans, the
--      invariants and Cancel exactly as before 474 (every key but the
--      dialog's credit, where R ran).
--   P. Probes: the preview's other figures exactly 451's (its text worked
--      back from 474's, by md5), its credit 451's plus what waits; what a
--      reopening records (its revision's snapshot, its Audit Log row); a
--      waiting invoice's preview; the grants.
--   K. KNOWN (474's NOT COVERED), checked as they are: 1 (THq), 2 (PT0);
--      where 475 or 478 is in, 1 or 2 is checked as it settles it.
--
-- Run on a copy of production as it is with 472 and 473 applied (471 in, 26
-- Oct 2026: fd61e1a1; 472: 84308fd1; 473: eb7399d1, 1387 functions):
--   psql -X -v ON_ERROR_STOP=1 -f scripts/invoices/tests/reopen-dialog-waiting-credit-474.sql
-- It installs 474 itself (twice) inside its transaction. Where 474 is in
-- already, add -v nomig=1 (S checks it as tested; R, Q, 9 and M are skipped;
-- every case after 474 is still checked). Section 9 lets the install fail on
-- purpose (psql prints its ERROR); the suite then checks that message.
-- Disposable database only; everything is rolled back. Every name, code and
-- amount is invented (@example.com); the phones are numbers kept for fiction
-- (ACMA, +61491570000 to +61491570999).
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '10s';
set local statement_timeout = '900s';

-- ── Set-up and the app's calls (471's suite harness, for 474) ────────────────
create temp table t474(k text primary key, id uuid);
create temp table t474_res(phase text, k text, v jsonb, primary key (phase, k));
create temp table t474_fp(k text primary key, fp text);
create temp sequence t474_phone;
create function pg_temp.t474_id(p_k text) returns uuid language sql as $f$ select id from t474 where k = p_k $f$;
create function pg_temp.t474_put(p_k text, p_id uuid) returns uuid language sql as $f$
  insert into t474 values (p_k, p_id) on conflict (k) do update set id = excluded.id returning id $f$;
create function pg_temp.t474_check(p_ok boolean, p_label text) returns void language plpgsql as $f$
begin
  if not coalesce(p_ok, false) then raise exception 'FAIL %', p_label; end if;
end $f$;
create function pg_temp.t474_fingerprint() returns text language sql as $f$
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.oid::regprocedure::text)) || ' ' || count(*)
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prokind in ('f', 'p') $f$;
create function pg_temp.t474_463_in() returns boolean language sql as $f$
  select to_regprocedure('public.invoice_benefit_moved_to_other(uuid)') is not null $f$;
create function pg_temp.t474_462_in() returns boolean language sql as $f$
  select to_regprocedure('public.credit_given_back_follows(uuid)') is not null
     and exists (select 1 from pg_trigger where tgname = 'credit_given_back_follows'
                  and tgrelid = 'public.customer_credit_ledger'::regclass) $f$;
create function pg_temp.t474_470_in() returns boolean language sql as $f$
  select to_regprocedure('public.credit_given_back_follows(uuid)') is not null
     and position('-- 470 (the Owner, 24 Oct 2026' in pg_get_functiondef('public.credit_given_back_follows(uuid)'::regprocedure)) > 0 $f$;
create function pg_temp.t474_471_in() returns boolean language sql as $f$
  select to_regprocedure('public.credit_given_back_follows(uuid)') is not null
     and position('-- 471 (the Owner, 26 Oct 2026' in pg_get_functiondef('public.credit_given_back_follows(uuid)'::regprocedure)) > 0 $f$;
create function pg_temp.t474_472_in() returns boolean language sql as $f$
  select to_regprocedure('public.credit_given_back_follows(uuid)') is not null
     and position('-- 472 (the Owner, 26 Oct 2026' in pg_get_functiondef('public.credit_given_back_follows(uuid)'::regprocedure)) > 0 $f$;
create function pg_temp.t474_473_in() returns boolean language sql as $f$
  select position('-- 473 (the Owner, 26 Oct 2026' in pg_get_functiondef('public.invoice_transferable_benefits(uuid)'::regprocedure)) > 0 $f$;
-- 474 is in: the preview is 474's (its text says so; S checks its md5).
create function pg_temp.t474_in() returns boolean language sql as $f$
  select position('-- 474 (the Owner, 26 Oct 2026' in pg_get_functiondef('public.invoice_reopen_preview_before_sessions(uuid)'::regprocedure)) > 0 $f$;
-- 475 is in (it goes in after 474): reopen_invoice queues a session an
-- earlier reopening queued, still waiting, only once (NOT COVERED 1: THq,
-- K1, are then checked as 475 settles them).
create function pg_temp.t474_475_in() returns boolean language sql as $f$
  select position('-- 475 (the Owner, 27 Oct 2026' in pg_get_functiondef('public.reopen_invoice(uuid,text,uuid)'::regprocedure)) > 0 $f$;
-- 478 is in (it goes in after 474 to 477): the preview, 474's text with
-- 478's lines added (by its AFTER md5), also names the credit a reopening
-- gives at once for a package paid in part, and its explanation says so
-- (NOT COVERED 2: PT0, K2, is then checked as 478 settles it), and (the
-- Owner's answer E, 27 Oct 2026) what the settling payment gives and who
-- receives the credit (NOT COVERED 3: K2 checks PT0's receiver), and (as the
-- Owner ticked answer E) the vouchers the settling payment gives and a
-- Credit Package's reward units; every other figure is 474's (P1 works
-- 474's text back from 478's).
create function pg_temp.t474_478_in() returns boolean language sql as $f$
  select position('-- 478 (the Owner, 27 Oct 2026' in pg_get_functiondef('public.invoice_reopen_preview_before_sessions(uuid)'::regprocedure)) > 0
     and md5(pg_get_functiondef('public.invoice_reopen_preview_before_sessions(uuid)'::regprocedure)) = 'acbfc38a20a000e1af0e78d26fc7fc4c' $f$;
-- What a commit does at the end of each app call (each is its own
-- transaction in the app): 462's deferred trigger on the ledger runs (474
-- adds no trigger, and changes nothing a commit does). Here
-- the suite is one transaction, so the trigger's queued rows are run at this
-- point. (Not where each step really commits: t474.autocommit 'on', for
-- running the same cases one call per transaction on a disposable copy.)
create function pg_temp.t474_commit() returns void language plpgsql as $f$
begin
  if coalesce(current_setting('t474.autocommit', true), '') = 'on' then return; end if;
  if pg_temp.t474_462_in() then
    execute 'set constraints public.credit_given_back_follows immediate';
    execute 'set constraints public.credit_given_back_follows deferred';
  end if;
end $f$;

do $$
declare own uuid := gen_random_uuid(); st uuid; st2 uuid; pm uuid; v uuid; cp uuid; cpb uuid; pbv uuid; svc uuid; svc5 uuid;
begin
  insert into auth.users(id, email) values (own, 't474-owner@example.com');
  insert into profiles(id, full_name, email, role, is_active) values (own, 'T474 Owner', 't474-owner@example.com', 'owner', true);
  perform set_config('request.jwt.claims', json_build_object('sub', own, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', own::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  insert into stores(name, code, country_code) values ('T474 Store', 'T474S1', 'SG') returning id into st;
  insert into stores(name, code, country_code) values ('T474 Other Store', 'T474S2', 'SG') returning id into st2;
  insert into payment_methods(name, is_active) values ('T474 Cash', true) returning id into pm;
  insert into vouchers(name, code, voucher_kind, qty_type, selling_price, is_active)
    values ('T474 Plain 30', 'T474-P30', 'normal', 'unlimited', 30, true) returning id into v;
  insert into voucher_store_prices(voucher_id, store_id, selling_price, available_at_store) values (v, st, 30, true), (v, st2, 30, true);
  insert into credit_packages(name, customer_price, paid_credit_amount, bonus_enabled, allow_product, allow_therapy)
    values ('T474 S$100', 100, 100, false, true, true) returning id into cp;
  insert into credit_package_stores(package_id, store_id) values (cp, st), (cp, st2);
  insert into credit_packages(name, customer_price, paid_credit_amount, bonus_enabled, bonus_value, allow_product, allow_therapy, grants_reward)
    values ('T474 S$100 + S$10', 100, 100, true, 10, true, true, false) returning id into cpb;
  insert into credit_package_stores(package_id, store_id) values (cpb, st), (cpb, st2);
  insert into premium_bundles(name, customer_payment_amount, paid_credit_amount, bonus_credit_amount, free_voucher_qty, grants_reward)
    values ('T474 Bundle S$140 + 2 vouchers', 140, 100, 40, 2, true) returning id into pbv;
  insert into premium_bundle_stores(bundle_id, store_id) values (pbv, st), (pbv, st2);
  insert into premium_bundle_vouchers(bundle_id, voucher_id) values (pbv, v);
  svc := (upsert_therapy_service(null, 'T474-SESSION', 'T474 Session', 20, 30, 'per_hours', 1, 5, null, true, null) ->> 'id')::uuid;
  perform set_therapy_service_store(svc, st, true, null);
  svc5 := (upsert_therapy_service(null, 'T474-SHORT', 'T474 Short session', 5, 15, 'per_hours', 1, 5, null, true, null) ->> 'id')::uuid;
  perform set_therapy_service_store(svc5, st, true, null);
  insert into t474 values ('own', own), ('store', st), ('store2', st2), ('pm', pm), ('v', v), ('cp', cp), ('cpb', cpb), ('pbv', pbv),
    ('svc', svc), ('svc5', svc5),
    ('wallet', (select id from payment_methods where name = 'Wallet — Credit Package Paid' and is_wallet_credit and deleted_at is null)),
    ('bwallet', (select id from payment_methods where name = 'Wallet — Premium Bundle Paid' and is_wallet_credit and deleted_at is null));
  perform pg_temp.t474_check(pg_temp.t474_id('wallet') is not null and pg_temp.t474_id('bwallet') is not null, 'setup: the wallet methods (443) are there');
end $$;

-- A customer of one run of one case: '<phase>/<case>/<role>'.
create function pg_temp.t474_cust(p_k text) returns uuid language plpgsql as $f$
declare c uuid;
begin
  insert into customers(full_name, phone) values ('T474 ' || p_k, '+61491570' || lpad((nextval('t474_phone') % 1000)::text, 3, '0'))
    returning id into c;
  return pg_temp.t474_put(p_k, c);
end $f$;
-- The invoice form with these lines ('cp' / 'cpb' a Credit Package, 'pbv' the
-- Premium Bundle, 'v' a voucher line of p_qty units, 'th' three sessions of
-- S$20), with an Owner's manual
-- discount of p_discount (its reason given) where one is given, paid through
-- the Pay dialog: in full, or p_first of it (a part-paid package).
create function pg_temp.t474_sale(p_cust uuid, p_kinds text[], p_first numeric default null, p_qty int default 2,
                                  p_discount numeric default null)
  returns uuid language plpgsql as $f$
declare inv uuid; v_lines jsonb := '[]'; i int;
begin
  for i in 1 .. cardinality(p_kinds) loop
    v_lines := v_lines || jsonb_build_array(case
      when p_kinds[i] = 'v' then jsonb_build_object('kind', 'voucher', 'voucher_id', pg_temp.t474_id('v'), 'quantity', p_qty)
      -- 474: a therapy line of three S$20 sessions (the dialog's sessions)
      when p_kinds[i] = 'th' then jsonb_build_object('kind', 'therapy', 'therapy_service_id', pg_temp.t474_id('svc'), 'quantity', 3)
      when p_kinds[i] in ('cp', 'cpb') then jsonb_build_object('kind', 'credit_package', 'credit_package_id', pg_temp.t474_id(p_kinds[i]), 'quantity', 1)
      else jsonb_build_object('kind', 'premium_bundle', 'premium_bundle_id', pg_temp.t474_id('pbv'), 'quantity', 1,
        'voucher_selection', jsonb_build_array(jsonb_build_object('voucher_id', pg_temp.t474_id('v'), 'quantity', 2))) end);
  end loop;
  inv := create_invoice_with_details(pg_temp.t474_id('store'), p_cust, v_lines, jsonb_build_object('business_date', sg_today()::text)
           || case when p_discount is not null
                   then jsonb_build_object('manual_discount', p_discount, 'manual_discount_reason', 'T474 discount') else '{}'::jsonb end);
  perform record_invoice_settlement(inv, jsonb_build_object('receipts', jsonb_build_array(jsonb_build_object(
    'key', 'line-0', 'payment_method_id', pg_temp.t474_id('pm'),
    'amount', coalesce(p_first, (select total_amount from invoices where id = inv)),
    'payment_date', sg_today()::text)), 'arrangements', '[]'::jsonb), gen_random_uuid());
  return inv;
end $f$;
-- Record Payment of what is outstanding (nothing when it is settled).
create function pg_temp.t474_pay(p_inv uuid) returns void language plpgsql as $f$
begin
  if (invoice_financial_position(p_inv)->>'outstanding')::numeric > 0 then
    perform record_invoice_payment(p_inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.t474_id('pm'),
      'amount', (invoice_financial_position(p_inv)->>'outstanding')::numeric)), gen_random_uuid());
  end if;
end $f$;
-- The receipts that still hold p_amount between them, as the Finance panel
-- splits a refund across them.
create function pg_temp.t474_sources(p_inv uuid, p_amount numeric) returns jsonb language plpgsql as $f$
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
create function pg_temp.t474_line(p_inv uuid, p_n int default 1) returns uuid language sql as $f$
  select id from invoice_items where invoice_id = p_inv
   order by case when line_kind in ('credit_package', 'premium_bundle') then 0 else 1 end, id offset p_n - 1 limit 1 $f$;
-- The Finance panel's refund by line of line p_n: p_amount off its Paid
-- benefit (the one an Owner did not move, or with p_holder the one p_holder
-- holds), or every unused benefit it still holds (p_amount null).
create function pg_temp.t474_back(p_inv uuid, p_n int, p_amount numeric default null, p_holder uuid default null)
  returns void language plpgsql as $f$
declare opts jsonb; ben jsonb; tot numeric; item uuid := pg_temp.t474_line(p_inv, p_n);
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
  if ben is null then raise exception 'T474: nothing to refund on that line'; end if;
  perform refund_invoice_recorded(p_inv, jsonb_build_array(jsonb_build_object('invoice_item_id', item, 'amount', tot, 'benefits', ben)),
    pg_temp.t474_sources(p_inv, tot), '[]'::jsonb, 'T474 by line', gen_random_uuid());
end $f$;
-- The invoice form's customer change, its lines as they are (and the store,
-- when given), with 'transfer' or 'keep'. The change's Audit Log row is
-- dated now, as a later call's is (the suite is one transaction).
create function pg_temp.t474_lines(p_inv uuid) returns jsonb language sql as $f$
  select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('invoice_item_id', it.id, 'kind', it.line_kind,
           'credit_package_id', it.credit_package_id, 'premium_bundle_id', it.premium_bundle_id, 'voucher_id', it.voucher_id,
           'quantity', it.quantity, 'unit_price', it.unit_price, 'voucher_selection', it.bundle_voucher_selection)) order by it.id)
    from invoice_items it where it.invoice_id = p_inv $f$;
create function pg_temp.t474_change(p_inv uuid, p_cust uuid, p_action text default 'transfer', p_store text default null)
  returns void language plpgsql as $f$
begin
  perform correct_invoice(p_inv, pg_temp.t474_lines(p_inv),
    jsonb_build_object('expected_edit_count', (select edit_count from invoices where id = p_inv),
      'customer_id', p_cust, 'store_id', coalesce(pg_temp.t474_id(p_store), (select store_id from invoices where id = p_inv)),
      'benefit_action', p_action),
    'T474 wrong customer', gen_random_uuid());
  update audit_logs set created_at = clock_timestamp()
   where record_id = p_inv and action = 'invoice_benefits_followed_reassignment' and new_data->>'to_customer' = p_cust::text
     and created_at = now();
end $f$;
create function pg_temp.t474_merge(p_keep uuid, p_dup uuid) returns void language plpgsql as $f$
begin
  perform merge_customer_records(p_keep, p_dup, 'T474 the same person', gen_random_uuid());
end $f$;
-- The Finance panel's Move of line p_n's unused benefit (its Paid credit,
-- or its Bonus with p_kind 'bonus', or a voucher) to p_to, at p_store.
create function pg_temp.t474_move(p_inv uuid, p_n int, p_to uuid, p_kind text default 'paid', p_store text default null)
  returns void language plpgsql as $f$
declare b uuid;
begin
  select bv.id into b from invoice_benefit_values bv
    left join customer_reward_vouchers v on v.id = bv.reward_voucher_id
    left join customer_credit_lots l on l.id = bv.lot_id
   where bv.invoice_item_id = pg_temp.t474_line(p_inv, p_n)
     and (v.status = 'held' and p_kind = 'voucher' or l.remaining_amount > 0 and l.category = p_kind)
   order by bv.granted_value desc limit 1;
  if b is null then raise exception 'T474: nothing to move on that line'; end if;
  perform transfer_invoice_unused_benefit(b, p_to, coalesce(pg_temp.t474_id(p_store), (select store_id from invoices where id = p_inv)),
    'T474 move', gen_random_uuid());
end $f$;
-- The invoice form: p_n sessions of S$20 (or S$5 with p_svc 'svc5') for
-- p_cust, paid with the wallet (Credit Package Paid; Premium Bundle Paid with
-- p_wallet 'bwallet') through Record Payment.
create function pg_temp.t474_spend(p_cust uuid, p_n int default 1, p_svc text default 'svc', p_wallet text default 'wallet')
  returns uuid language plpgsql as $f$
declare inv uuid; v_lines jsonb := '[]'; i int;
begin
  for i in 1 .. p_n loop
    v_lines := v_lines || jsonb_build_array(jsonb_build_object('kind', 'therapy', 'therapy_service_id', pg_temp.t474_id(p_svc), 'quantity', 1));
  end loop;
  inv := create_invoice_with_details(pg_temp.t474_id('store'), p_cust, v_lines, jsonb_build_object('business_date', sg_today()::text));
  perform record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.t474_id(p_wallet),
    'amount', (select total_amount from invoices where id = inv))), gen_random_uuid());
  if (select status::text from invoices where id = inv) <> 'paid' then raise exception 'T474: the session paid from credit is not paid'; end if;
  return inv;
end $f$;
-- The session cancelled and "Record refund paid": what its payment took goes
-- back to the lots it came from (refund_invoice_recorded's wallet refund).
create function pg_temp.t474_unspend(p_inv uuid) returns void language plpgsql as $f$
declare due numeric;
begin
  perform cancel_invoice_recorded(p_inv, 'T474 cancel session', gen_random_uuid());
  due := (invoice_financial_position(p_inv)->>'refund_due')::numeric;
  if due is null or due <= 0 then due := (invoice_action_plan(p_inv, 'cancel', '[]')->>'refund_due')::numeric; end if;
  perform refund_invoice_recorded(p_inv, jsonb_build_array(jsonb_build_object('amount', due)), pg_temp.t474_sources(p_inv, due), '[]'::jsonb,
    'T474 refund paid', gen_random_uuid());
end $f$;
-- The Finance panel's Correct payment on a session's wallet payment: the
-- date only ('date'), a smaller amount ('amount', S$5 less), or another
-- method ('cash').
create function pg_temp.t474_fix(p_inv uuid, p_how text) returns void language plpgsql as $f$
declare p invoice_payments%rowtype;
begin
  select * into p from invoice_payments where invoice_id = p_inv and entry_kind in ('receipt', 'correction_replacement')
     and not exists (select 1 from invoice_payments q where q.corrects_payment_id = invoice_payments.id and q.entry_kind = 'correction_reversal')
   order by created_at desc, id desc limit 1;
  perform correct_invoice_payment(p.id,
    case p_how when 'amount' then p.amount - 5 else p.amount end,
    sg_today() - 1,
    case p_how when 'cash' then pg_temp.t474_id('pm') else p.payment_method_id end,
    'T474 correct payment ' || p_how, gen_random_uuid());
end $f$;
-- A special document's wallet payment as pay_special_with_credit records it
-- (a stand-in: no page calls that function, and no credit category allows a
-- special document today, purchase_category): p_amount off the customer's
-- largest lot ('use', its allocations), so refund_special_credit, the real
-- one, gives it back.
create function pg_temp.t474_special(p_cust uuid, p_kind text, p_doc uuid, p_amount numeric) returns void language plpgsql as $f$
declare l customer_credit_lots%rowtype; e uuid;
begin
  select * into l from customer_credit_lots where customer_id = p_cust and status = 'active' and remaining_amount >= p_amount
   order by remaining_amount desc, id limit 1 for update;
  insert into customer_credit_ledger(wallet_id, customer_id, entry_type, category, amount, lot_id, source_type, source_record_id, store_id, note, created_by)
  values (l.wallet_id, p_cust, 'use', l.category, p_amount, l.id, p_kind, p_doc, l.store_id, 'T474 special', auth.uid()) returning id into e;
  update customer_credit_lots set remaining_amount = remaining_amount - p_amount, updated_at = now() where id = l.id;
  insert into customer_credit_allocations(ledger_entry_id, lot_id, customer_id, amount) values (e, l.id, p_cust, p_amount);
  insert into special_credit_allocations(doc_kind, doc_id, customer_id, lot_id, category, amount, created_by)
  values (p_kind, p_doc, p_cust, l.id, l.category, p_amount, auth.uid());
end $f$;
-- The guided Refund in full / Cancel as an Owner confirms it, with a reason
-- for every override the plan asks for, the money recorded as paid back (or,
-- with p_record false, not: "Record refund paid" left unticked).
create function pg_temp.t474_guided(p_inv uuid, p_action text, p_record boolean default true) returns void language plpgsql as $f$
declare plan jsonb; req jsonb; ov jsonb;
begin
  plan := invoice_action_plan(p_inv, p_action, '[]');
  req := request_invoice_action_v2(p_inv, p_action, '[]', 'T474 ' || p_action, null, gen_random_uuid());
  select coalesce(jsonb_agg(case when coalesce((o->>'amount_required')::boolean, false)
           then jsonb_build_object('code', o->>'code', 'reason', 'T474 override', 'amount', (o->>'default_amount')::numeric)
           else jsonb_build_object('code', o->>'code', 'reason', 'T474 override') end), '[]'::jsonb)
    into ov from jsonb_array_elements(coalesce(plan->'overrides_required', '[]')) o;
  perform resolve_invoice_action_v2((req->>'request_id')::uuid, true, 'T474 ' || p_action, plan->>'plan_hash', ov, null, p_record);
end $f$;


-- ── What the records say ────────────────────────────────────────────────────
-- The lots an invoice's records name: its benefit values, its sale's lots, a
-- split's issued lot, released credit (credit_package_progress_lots).
create function pg_temp.t474_named(p_inv uuid) returns setof uuid language sql as $f$
  select lot_id from invoice_benefit_values where invoice_id = p_inv and lot_id is not null
  union select x from credit_package_sales s, unnest(array[s.credit_lot_id, s.bonus_credit_lot_id]) x where s.invoice_id = p_inv and x is not null
  union select x from premium_bundle_sales s, unnest(array[s.paid_credit_lot_id, s.bonus_credit_lot_id]) x where s.invoice_id = p_inv and x is not null
  union select issued_lot_id from invoice_credit_splits where invoice_id = p_inv and issued_lot_id is not null
  union select lot_id from credit_package_progress_lots where invoice_id = p_inv $f$;
-- The invoice's lot family (the critic's 6): every lot its records name and
-- each Move's two lots (from the Move's ledger rows), the lots each replaced
-- and every lot reissued from any of them.
create function pg_temp.t474_family(p_inv uuid) returns setof uuid language sql as $f$
  with recursive seed as (
    select x as id from pg_temp.t474_named(p_inv) x
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
create function pg_temp.t474_behind(p_inv uuid) returns setof uuid language sql as $f$
  with recursive c(id, n) as (
    select lot_id, 0 from invoice_benefit_values where invoice_id = p_inv and lot_id is not null
    union select p.id, c.n + 1 from c join customer_credit_lots l on l.id = c.id
            join customer_credit_lots p on p.id = l.reassigned_from_lot_id
             and (p.source_type, p.source_record_id) is not distinct from (l.source_type, l.source_record_id)
           where c.n < 12)
  select distinct id from c $f$;
-- How many lots back a lot's chain goes (reassigned_from_lot_id).
create function pg_temp.t474_depth(p_lot uuid) returns int language sql as $f$
  with recursive c(id, n) as (select p_lot, 0 union all
    select l.reassigned_from_lot_id, c.n + 1 from c join customer_credit_lots l on l.id = c.id
     where l.reassigned_from_lot_id is not null and c.n < 40)
  select max(n) from c $f$;
-- A lot's balance by its ledger rows: credit added (grants, increases,
-- credit returned: the 'reverse' rows that put credit back, as the
-- statement reads them, and 'rental_late_fee'), less credit taken (uses,
-- decreases, real reversals).
create function pg_temp.t474_ledger_balance(p_lot uuid) returns numeric language sql as $f$
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
create function pg_temp.t474_invariants(p_inv uuid) returns text language plpgsql as $f$
declare probs text := ''; l record; root record; v uuid; st text := (select status::text from invoices where id = p_inv);
begin
  for l in select cl.* from customer_credit_lots cl where cl.id in (select pg_temp.t474_family(p_inv)) loop
    if l.remaining_amount > 0 and l.id not in (select pg_temp.t474_named(p_inv)) then
      probs := probs || format(' S$%s on a lot no record names (%s);', l.remaining_amount, (select full_name from customers where id = l.customer_id)); end if;
    if l.id not in (select pg_temp.t474_named(p_inv)) and l.id not in (select pg_temp.t474_behind(p_inv))
       and (exists (select 1 from invoice_line_credit_allocations a where a.lot_id = l.id and a.amount > coalesce(a.reversed_amount, 0))
            or exists (select 1 from special_credit_allocations s where s.lot_id = l.id and s.amount > coalesce(s.reversed_amount, 0))) then
      probs := probs || ' a sale paid from a lot no record names can still be refunded (its credit would stay there);'; end if;
    if pg_temp.t474_ledger_balance(l.id) <> l.remaining_amount then
      probs := probs || format(' lot holds %s, its ledger %s;', l.remaining_amount, pg_temp.t474_ledger_balance(l.id)); end if;
    if pg_temp.t474_depth(l.id) > 12 then probs := probs || format(' chain %s lots deep;', pg_temp.t474_depth(l.id)); end if;
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
  if st = 'refunded' and (select coalesce(sum(remaining_amount), 0) from customer_credit_lots where id in (select pg_temp.t474_family(p_inv))) > 0 then
    probs := probs || format(' refunded, but S$%s of its credit is still held;',
      (select sum(remaining_amount) from customer_credit_lots where id in (select pg_temp.t474_family(p_inv)))); end if;
  return probs;
end $f$;
-- Credit left on the invoice's family once Cancel has run, the Cancel undone
-- (0 when Cancel takes it all back from whoever holds it); null when the
-- invoice cannot be cancelled now, -1 when Cancel is refused.
create function pg_temp.t474_cancel_left(p_inv uuid) returns numeric language plpgsql as $f$
declare v numeric;
begin
  if (select status::text from invoices where id = p_inv) not in ('paid', 'partially_paid', 'unpaid') then return null; end if;
  begin
    perform cancel_invoice_recorded(p_inv, 'T474 probe', gen_random_uuid());
    perform pg_temp.t474_commit();
    v := (select coalesce(sum(remaining_amount), 0) from customer_credit_lots where id in (select pg_temp.t474_family(p_inv)));
    raise exception using errcode = 'P0461', message = v::text;
  exception when sqlstate 'P0461' then return sqlerrm::numeric;
            when others then return -1;
  end;
end $f$;
create function pg_temp.t474_codes(p_inv uuid, p_action text) returns text language plpgsql as $f$
begin
  return (select coalesce(string_agg(o->>'code', ',' order by o->>'code'), '-')
            from jsonb_array_elements(coalesce(invoice_action_plan(p_inv, p_action, '[]')->'overrides_required', '[]')) o);
exception when others then return 'ERR';
end $f$;
create function pg_temp.t474_due(p_inv uuid, p_action text) returns numeric language plpgsql as $f$
begin
  return (invoice_action_plan(p_inv, p_action, '[]')->>case when p_action = 'cancel' then 'refund_due' else 'refund_amount' end)::numeric;
exception when others then return null;
end $f$;
-- The invoice's money: what is owed back (cancel_refund_owed), the Finance
-- panel's refund due, net received and kept for what was used, what a
-- refund by line can still pay back (the refund options' max_refund, every
-- benefit) and Cancel's refund due (the plan's).
create function pg_temp.t474_money(p_inv uuid) returns jsonb language sql as $f$
  select jsonb_build_object('owed', i.cancel_refund_owed,
    'due', (invoice_financial_position(i.id)->>'refund_due')::numeric,
    'net', (invoice_financial_position(i.id)->>'net_received')::numeric,
    'kept', (invoice_financial_position(i.id)->>'kept_for_used')::numeric,
    'by_line', (select coalesce(sum((b->>'max_refund')::numeric), 0)
                  from jsonb_array_elements(invoice_refund_options_before_sessions(i.id)->'benefits') b),
    'plan_due', pg_temp.t474_due(i.id, 'cancel'))
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
--   backv N units         a refund by line of that many voucher units of line N (474)
--   backt N amt           a refund by line of a therapy line by money (474)
--   legacy STATUS         a stand-in for the legacy statuses (no page sets them now)
--   repair                repair_credit_package_progress_lots()
create function pg_temp.t474_role(p_pre text, p_r text) returns uuid language plpgsql as $f$
begin
  return coalesce(pg_temp.t474_id(p_pre || '/' || p_r), pg_temp.t474_cust(p_pre || '/' || p_r));
end $f$;
-- One step of a case (one app call, then what its commit does). Null, or
-- the step and the refusal; a refused step changes nothing.
create function pg_temp.t474_step(p_pre text, p_st text) returns text language plpgsql as $f$
declare w text[] := regexp_split_to_array(btrim(p_st), '\s+'); inv uuid := pg_temp.t474_id(p_pre || '/inv'); x uuid; i int; n int;
begin
  case w[1]
  when 'sale' then
    perform pg_temp.t474_put(p_pre || '/inv', pg_temp.t474_sale(pg_temp.t474_role(p_pre, w[2]), string_to_array(w[3], ','), w[4]::numeric));
  when 'saled' then
    perform pg_temp.t474_put(p_pre || '/inv', pg_temp.t474_sale(pg_temp.t474_role(p_pre, w[2]), string_to_array(w[3], ','), null, 2, w[4]::numeric));
  when 'sale2' then
    perform pg_temp.t474_put(p_pre || '/inv2', pg_temp.t474_sale(pg_temp.t474_role(p_pre, w[2]), array['cp']));
  when 'pay' then perform pg_temp.t474_pay(inv);
  when 'back' then
    perform pg_temp.t474_back(inv, w[2]::int, case when w[3] = 'all' then null else w[3]::numeric end,
                              case when w[4] is not null then pg_temp.t474_role(p_pre, w[4]) end);
  when 'move' then
    perform pg_temp.t474_move(inv, w[2]::int, pg_temp.t474_role(p_pre, w[3]),
      case when w[4] in ('bonus', 'voucher') then w[4] else 'paid' end,
      case when 'store2' = any (w) then 'store2' end);
  when 'cancel' then perform cancel_invoice_recorded(inv, 'T474 cancel', gen_random_uuid());
  when 'reopen' then perform reopen_invoice(inv, 'T474 reopen', gen_random_uuid());
  when 'wait' then
    perform cancel_invoice_recorded(inv, 'T474 cancel', gen_random_uuid());
    for i in 1 .. (select count(*)::int from invoice_items where invoice_id = inv) loop
      perform pg_temp.t474_back(inv, i);
    end loop;
    perform reopen_invoice(inv, 'T474 reopen', gen_random_uuid());
  when 'refundall' then perform pg_temp.t474_guided(inv, 'refund_full');
  when 'change' then
    perform pg_temp.t474_change(inv, pg_temp.t474_role(p_pre, w[2]), case when 'keep' = any (w) then 'keep' else 'transfer' end,
                                case when 'store2' = any (w) then 'store2' end);
  when 'merge' then perform pg_temp.t474_merge(pg_temp.t474_role(p_pre, w[2]), pg_temp.t474_role(p_pre, w[3]));
  when 'spend' then
    n := (select count(*) from t474 where k ~ ('^' || p_pre || '/S[0-9]+$')) + 1;
    perform pg_temp.t474_put(p_pre || '/S' || n,
      pg_temp.t474_spend(pg_temp.t474_role(p_pre, w[2]), case when w[3] ~ '^[0-9]+$' then w[3]::int else 1 end,
        case when 'svc5' = any (w) then 'svc5' else 'svc' end, case when 'bwallet' = any (w) then 'bwallet' else 'wallet' end));
  when 'unspend' then perform pg_temp.t474_unspend(pg_temp.t474_id(p_pre || '/' || w[2]));
  when 'fix' then perform pg_temp.t474_fix(pg_temp.t474_id(p_pre || '/' || w[2]), w[3]);
  when 'delete' then
    x := pg_temp.t474_role(p_pre, w[2]);
    perform delete_customer(x, (select full_name from customers where id = x), 'T474 delete');
  when 'special' then
    n := (select count(*) from t474 where k ~ ('^' || p_pre || '/D[0-9]+$')) + 1; x := gen_random_uuid();
    perform pg_temp.t474_put(p_pre || '/D' || n, x);
    perform pg_temp.t474_put(p_pre || '/D' || n || '/kind:' || w[3], null);
    perform pg_temp.t474_special(pg_temp.t474_role(p_pre, w[2]), w[3], x, w[4]::numeric);
  when 'unspecial' then
    perform refund_special_credit((select split_part(k, 'kind:', 2) from t474 where k like p_pre || '/' || w[2] || '/kind:%'),
                                  pg_temp.t474_id(p_pre || '/' || w[2]));
  when 'reverse' then
    if w[2] = 'closed' then
      -- the released lot a Cancel's write-off closed, once a refund opened it again
      perform reverse_credit_lot(pg_temp.t474_closed_lot(inv), 'T474 reversal');
    else
      x := pg_temp.t474_role(p_pre, w[2]);
      perform reverse_credit_lot((select id from customer_credit_lots where customer_id = x and remaining_amount > 0
                                   order by remaining_amount desc, id limit 1), 'T474 reversal');
    end if;
  when 'guidedcancel' then perform pg_temp.t474_guided(inv, 'cancel');
  when 'guidedkeep' then perform pg_temp.t474_guided(inv, 'cancel', false);
  when 'backo' then
    x := pg_temp.t474_line(inv, w[2]::int);
    perform refund_invoice_recorded(inv, jsonb_build_array(jsonb_build_object('invoice_item_id', x,
        'amount', invoice_discounted_line_value(x),
        'benefits', jsonb_build_array(jsonb_build_object('benefit_id', pg_temp.t474_own(inv), 'amount', w[3]::numeric)),
        'override', jsonb_build_object('code', 'larger_refund', 'reason', 'T474 larger refund', 'amount', invoice_discounted_line_value(x)))),
      pg_temp.t474_sources(inv, invoice_net_received(inv)), '[]'::jsonb, 'T474 larger refund', gen_random_uuid());
  when 'refundpaid' then
    perform refund_invoice_recorded(inv, jsonb_build_array(jsonb_build_object('amount',
        coalesce(nullif((invoice_financial_position(inv)->>'refund_due')::numeric, 0), (invoice_action_plan(inv, 'cancel', '[]')->>'refund_due')::numeric))),
      pg_temp.t474_sources(inv, coalesce(nullif((invoice_financial_position(inv)->>'refund_due')::numeric, 0), (invoice_action_plan(inv, 'cancel', '[]')->>'refund_due')::numeric)),
      '[]'::jsonb, 'T474 refund paid', gen_random_uuid());
  when 'backx' then
    x := pg_temp.t474_line(inv, w[2]::int);
    perform refund_invoice_recorded(inv, jsonb_build_array(jsonb_build_object('invoice_item_id', x,
        'amount', invoice_discounted_line_value(x) - coalesce((select sum((e->>'amount')::numeric) from invoice_refunds r,
             jsonb_array_elements(coalesce(r.outcome->'lines', '[]')) e where r.invoice_id = inv and e->>'invoice_item_id' = x::text), 0),
        'benefits', (select jsonb_agg(jsonb_build_object('benefit_id', b->>'id', 'amount', (b->>'max_refund')::numeric))
                       from jsonb_array_elements(invoice_refund_options_before_sessions(inv)->'benefits') b
                      where b->>'invoice_item_id' = x::text and (b->>'max_refund')::numeric > 0),
        'override', jsonb_build_object('code', 'larger_refund', 'reason', 'T474 larger refund',
          'amount', invoice_discounted_line_value(x) - coalesce((select sum((e->>'amount')::numeric) from invoice_refunds r,
             jsonb_array_elements(coalesce(r.outcome->'lines', '[]')) e where r.invoice_id = inv and e->>'invoice_item_id' = x::text), 0)))),
      pg_temp.t474_sources(inv, invoice_net_received(inv)), '[]'::jsonb, 'T474 larger refund', gen_random_uuid());
  when 'backv' then
    -- 474: the Finance panel's refund by line of N voucher units of line N
    -- (at their paid value).
    x := pg_temp.t474_line(inv, w[2]::int);
    perform refund_invoice_recorded(inv, jsonb_build_array(jsonb_build_object('invoice_item_id', x, 'amount', b.amt,
        'benefits', jsonb_build_array(jsonb_build_object('benefit_id', b.id, 'amount', b.amt)))),
      pg_temp.t474_sources(inv, b.amt), '[]'::jsonb, 'T474 voucher by line', gen_random_uuid())
      from (select o->>'id' as id, round(w[3]::int * (o->>'paid_value')::numeric / (o->>'granted_value')::numeric, 2) as amt
              from jsonb_array_elements(invoice_refund_options_before_sessions(inv)->'benefits') o
             where o->>'invoice_item_id' = x::text and o->>'benefit_kind' = 'voucher' and (o->>'max_refund')::numeric > 0
             order by (o->>'max_refund')::numeric desc limit 1) b;
    if not found then raise exception 'T474: no voucher to refund on that line'; end if;
  when 'backt' then
    -- 474: the Finance panel's refund by line of a therapy line, by money
    -- (whole unused sessions).
    x := pg_temp.t474_line(inv, w[2]::int);
    perform refund_invoice_recorded(inv, jsonb_build_array(jsonb_build_object('invoice_item_id', x, 'amount', w[3]::numeric)),
      pg_temp.t474_sources(inv, w[3]::numeric), '[]'::jsonb, 'T474 sessions by line', gen_random_uuid());
  when 'legacy' then
    update invoices set status = w[2]::invoice_status where id = inv;
  when 'repair' then perform repair_credit_package_progress_lots();
  else raise exception 'T474: unknown step %', p_st;
  end case;
  perform pg_temp.t474_commit();
  return null;
exception when others then
  return btrim(p_st) || ': ' || sqlerrm;
end $f$;
-- What a case ends with: the invoice's status and money, who holds what
-- (credit, '/n' held vouchers), the plans' codes and refund due (Cancel's
-- refund due; Refund in full's amount), the refusal that stopped it, what is
-- wrong with its credit, and the credit Cancel would leave behind.
create function pg_temp.t474_outcome(p_pre text, p_err text) returns jsonb language sql as $f$
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
              from t474 t where t.k like p_pre || '/%' and split_part(t.k, '/', 4) = ''
                and split_part(t.k, '/', 3) !~ '^(inv|inv2|S[0-9]+|D[0-9]+|err)$'),
    'cancel', pg_temp.t474_codes(i.id, 'cancel'),
    'due', pg_temp.t474_due(i.id, 'cancel'),
    'refund', pg_temp.t474_codes(i.id, 'refund_full'),
    'rdue', pg_temp.t474_due(i.id, 'refund_full'),
    'error', p_err,
    'invariants', pg_temp.t474_invariants(i.id),
    'cancel_left', pg_temp.t474_cancel_left(i.id))
    from (select pg_temp.t474_id(p_pre || '/inv') as id) i $f$;

-- ── 474's readings: the Reopen dialog, and what the payment gives ───────────
-- Each Reopen of a case: the dialog read just before it, as the Finance panel
-- reads it (invoice_reopen_preview: every figure it shows), what the Reopen
-- left waiting (or gave back at once, reopened straight to paid).
create temp table t474_dlg(pre text, n int, shown numeric, shownv int, shows int, total numeric, net numeric, required numeric,
                           can boolean, preview jsonb, queued numeric, queuedv int, primary key (pre, n));
-- What each step gave back: credit (the payment's 'Reopened invoice settled'
-- rows, apply_reopened_invoice_benefits), voucher units given again
-- (apply_reopened_invoice_vouchers) and sessions reinstated
-- (trg_create_therapy_sessions_on_paid).
create temp table t474_gift(pre text, n int, credit numeric, vouchers int, sessions int, primary key (pre, n));
-- A case's steps p_from to p_to (all by default), stopping at a refusal;
-- with p_to null, its outcome (kept in t474_res under p_phase): 471's, and
-- the dialog's (t474_dialog).
create temp table t474_err(pre text primary key, err text);
create function pg_temp.t474_dialog(p_pre text) returns jsonb language sql as $f$
  with l as (select * from t474_dlg where pre = p_pre order by n desc limit 1)
  select jsonb_build_object(
    'reopens', (select count(*) from t474_dlg where pre = p_pre),
    'dlg', (select shown from l), 'dlgv', (select shownv from l), 'dlgs', (select shows from l),
    'required', (select required from l),
    'queued', (select queued from l), 'queuedv', (select queuedv from l),
    'gave', (select coalesce(sum(g.credit), 0) from t474_gift g, l where g.pre = p_pre and g.n >= l.n),
    'gavev', (select coalesce(sum(g.vouchers), 0) from t474_gift g, l where g.pre = p_pre and g.n >= l.n),
    'gaves', (select coalesce(sum(g.sessions), 0) from t474_gift g, l where g.pre = p_pre and g.n >= l.n),
    'every', (select coalesce(string_agg(format('%s: %s shown, %s queued', d.n, d.shown, d.queued), '; ' order by d.n), '')
                from t474_dlg d where d.pre = p_pre and d.queued is not null
                 and (d.shown is distinct from d.queued or d.shownv is distinct from d.queuedv))) $f$;
create function pg_temp.t474_run(p_phase text, p_case text, p_steps text, p_from int default 1, p_to int default null)
  returns jsonb language plpgsql as $f$
declare v_pre text := p_phase || '/' || p_case; st text[] := string_to_array(p_steps, ';'); i int; v_err text; v_out jsonb;
  inv uuid; pv jsonb; seq bigint; av uuid[]; ass uuid[]; g numeric; gv int; gs int;
begin
  v_err := (select e.err from t474_err e where e.pre = v_pre);
  for i in p_from .. least(coalesce(p_to, cardinality(st)), cardinality(st)) loop
    exit when v_err is not null;
    continue when btrim(st[i]) = '';
    inv := pg_temp.t474_id(v_pre || '/inv');
    if inv is not null and btrim(st[i]) = 'reopen' then
      pv := invoice_reopen_preview(inv);
      insert into t474_dlg(pre, n, shown, shownv, shows, total, net, required, can, preview)
      values (v_pre, i, (pv->>'credit_to_reinstate_after_settlement')::numeric, (pv->>'voucher_units_to_reinstate_after_settlement')::int,
              coalesce((pv->>'sessions_to_reinstate_after_settlement')::int, 0), (pv->>'total')::numeric, (pv->>'net_received')::numeric,
              greatest(0, (pv->>'total')::numeric - (pv->>'net_received')::numeric), (pv->>'can_reopen')::boolean, pv)
      on conflict (pre, n) do nothing;
    end if;
    select coalesce(max(entry_seq), 0) into seq from customer_credit_ledger;
    select array_agg(id) into av from invoice_reopen_vouchers where invoice_id = inv and applied_at is not null;
    select array_agg(id) into ass from invoice_reopen_sessions where invoice_id = inv and applied_at is not null;
    v_err := pg_temp.t474_step(v_pre, st[i]);
    inv := pg_temp.t474_id(v_pre || '/inv');
    g := (select coalesce(sum(e.amount), 0) from customer_credit_ledger e
           where e.entry_seq > seq and e.entry_type = 'reverse' and e.source_type = 'invoice_reopen' and e.reason = 'Reopened invoice settled'
             and e.reverses_entry_id in (select q.source_ledger_id from invoice_reopen_benefits q where q.invoice_id = inv));
    gv := (select coalesce(sum(q.quantity), 0) from invoice_reopen_vouchers q where q.invoice_id = inv and q.applied_at is not null
             and q.replacement_voucher_id is not null and not (q.id = any (coalesce(av, '{}'))));
    gs := (select coalesce(sum(q.quantity), 0) from invoice_reopen_sessions q where q.invoice_id = inv and q.applied_at is not null
             and not (q.id = any (coalesce(ass, '{}'))));
    insert into t474_gift values (v_pre, i, g, gv, gs)
      on conflict (pre, n) do update set credit = excluded.credit, vouchers = excluded.vouchers, sessions = excluded.sessions;
    if btrim(st[i]) = 'reopen' and v_err is null then
      update t474_dlg set queued = g + (select coalesce(sum(q.amount), 0) from invoice_reopen_benefits q where q.invoice_id = inv and q.applied_at is null),
                          queuedv = gv + (select coalesce(sum(q.quantity), 0) from invoice_reopen_vouchers q where q.invoice_id = inv and q.applied_at is null)
       where pre = v_pre and n = i;
    end if;
  end loop;
  insert into t474_err values (v_pre, v_err) on conflict (pre) do update set err = excluded.err;
  if p_to is not null then return null; end if;
  v_out := pg_temp.t474_outcome(v_pre, v_err) || pg_temp.t474_dialog(v_pre);
  insert into t474_res values (p_phase, p_case, v_out) on conflict (phase, k) do update set v = excluded.v;
  return v_out;
end $f$;
-- Whether an outcome has what is expected: each key equal ('holds' as a
-- containment of who holds what), a key ending in '~' as a LIKE pattern of
-- that key's text.
create function pg_temp.t474_meets(p_out jsonb, p_exp jsonb) returns boolean language sql as $f$
  select coalesce(bool_and(case
           when e.key like '%~' then coalesce(p_out->>left(e.key, -1), '') like (e.value #>> '{}')
           when e.key = 'holds' then coalesce(p_out->'holds', '{}') @> e.value
           when jsonb_typeof(e.value) = 'number' then coalesce((p_out->>e.key)::numeric = (e.value #>> '{}')::numeric, false)
           else (p_out->e.key) is not distinct from e.value end), true)
    from jsonb_each(p_exp) e $f$;
-- What differs between an outcome and what is expected (for the FAIL line).
create function pg_temp.t474_diff(p_out jsonb, p_exp jsonb) returns text language sql as $f$
  select string_agg(e.key || ': wanted ' || e.value::text || ', got ' || coalesce(p_out->left(e.key, case when e.key like '%~' then -1 else 1000 end), 'null')::text, '; ')
    from jsonb_each(p_exp) e where not pg_temp.t474_meets(p_out, jsonb_build_object(e.key, e.value)) $f$;
-- An outcome without the dialog's credit (what 474 changes) and the
-- comparison of it (for A against R: every other key as before 474).
create function pg_temp.t474_but_dialog(p_out jsonb) returns jsonb language sql as $f$
  select p_out - 'dlg' - 'every' $f$;
-- The unapplied reopening queue of an invoice (credit).
create function pg_temp.t474_waiting(p_inv uuid) returns numeric language sql as $f$
  select coalesce(sum(q.amount), 0) from invoice_reopen_benefits q where q.invoice_id = p_inv and q.applied_at is null $f$;
-- Who may call a function (the set) and the whole grant list (by name).
create function pg_temp.t474_grants() returns text language sql as $f$
  select md5(string_agg(p.oid::regprocedure::text || '=' || coalesce(p.proacl::text, 'null'), '|' order by p.oid::regprocedure::text))
    from pg_proc p where p.pronamespace = 'public'::regnamespace $f$;
create function pg_temp.t474_grant_set(p_sig text) returns text[] language sql as $f$
  select array_agg(x::text order by x::text) from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || p_sig) $f$;
-- The function 474 changes: BEFORE (production, 26 Oct 2026: 451's AFTER)
-- and AFTER.
create temp table t474_md5(sig text primary key, before text, after text);
insert into t474_md5 values
  ('invoice_reopen_preview_before_sessions(uuid)', '12206ed066495024421b3b44a6a9d8e2', '7e1ef2d25415e69b3f770fe2efd45190');
create function pg_temp.t474_at(p_col text) returns boolean language sql as $f$
  select bool_and(md5(pg_get_functiondef(to_regprocedure('public.' || m.sig))) = case when p_col = 'before' then m.before else m.after end)
    from t474_md5 m $f$;
insert into t474_fp values ('start', pg_temp.t474_fingerprint()), ('grants', pg_temp.t474_grants());

-- The read-only query in 474's header (the same text, taken from the file
-- when this suite was written).
create function pg_temp.t474_header_query() returns table(reason text, invoice_no text, n bigint) language sql as $hq$
with
-- the reopening queue's rows still waiting, by invoice
q as (
  select q.invoice_id, count(*) as n from public.invoice_reopen_benefits q
   where q.applied_at is null group by q.invoice_id),
-- therapy sessions waiting for a reopening's payment, by invoice: all,
-- and those queued more than once
s as (
  select s.invoice_id, count(distinct s.session_id) as n,
         count(distinct s.session_id) filter (where s.k > 1) as twice
    from (select s.invoice_id, s.session_id, count(*) over (partition by s.session_id) as k
            from public.invoice_reopen_sessions s where s.applied_at is null) s
   group by s.invoice_id),
found(reason, invoice_id, n) as (
  select '1 changes: cancelled or refunded (the Reopen dialog is offered), with credit an earlier reopening queued still waiting; from 474 the dialog''s "Revoked credit to reinstate after settlement" counts it, as the payment that settles it gives it (the count is of queue rows)', i.id, q.n
    from public.invoices i join q on q.invoice_id = i.id
   where i.deleted_at is null and i.status::text in ('cancelled', 'refunded')
  union all
  select '2 changes (not shown: the dialog is offered for a cancelled or refunded invoice alone): a reopening waiting for its payment; from 474 its preview counts the credit queued for it (the count is of queue rows)', i.id, q.n
    from public.invoices i join q on q.invoice_id = i.id
   where i.deleted_at is null and i.status::text not in ('cancelled', 'refunded')
  union all
  select '3 for the Owner (not changed by 474: NOT COVERED 1): cancelled or refunded with a therapy session''s reopening still waiting; reopened again, the session is queued again and the payment that settles it is refused (the count is of sessions)', i.id, s.n
    from public.invoices i join s on s.invoice_id = i.id
   where i.deleted_at is null and i.status::text in ('cancelled', 'refunded')
  union all
  select '4 for the Owner (not changed by 474: NOT COVERED 1): a therapy session queued by two reopenings still waiting; the payment that settles the invoice is refused ("Therapy session reopening changed; reload its original evidence") (the count is of sessions)', i.id, s.twice
    from public.invoices i join s on s.invoice_id = i.id
   where i.deleted_at is null and s.twice > 0)
select f.reason, i.invoice_no, f.n
  from found f join public.invoices i on i.id = f.invoice_id
 order by f.reason, i.invoice_no
$hq$;

-- The cases: (k, kind, steps, what 474 gives). kind: 'fixed' (before 474 the
-- dialog says other than what the Reopen queues and the payment gives: the
-- fault is reproduced first), 'control' (the same with and without 474,
-- every key of the outcome), 'known' (a NOT COVERED item, checked as it is:
-- the same with and without 474, as a control). Every case also checks the
-- invariants and that Cancel takes everything back from whoever holds it.
create temp table t474_cases(k text primary key, kind text not null, steps text not null, expect jsonb not null, ord serial);
insert into t474_cases(k, kind, steps, expect) values
-- 471's K5: cancelled, S$60 refunded by line, reopened (S$60 queued), S2
-- refunded while it waits (S$20 held back, queued), cancelled again.
('K5', 'fixed', 'sale A cp; spend A; spend A; cancel; back 1 60; reopen; unspend S2; cancel; reopen; pay',
  '{"dlg":80,"queued":80,"gave":80,"required":60,"every":"","holds":{"A":"80.00"},"status":"paid","net":100,"error":null}'),
-- Cancel's own row an earlier reopening queued (417's and 451's older gap);
-- a third reopening; with S2 refunded.
('CQ', 'fixed', 'sale A cp; spend A; spend A; cancel; back 1 60; reopen; cancel; reopen; pay',
  '{"dlg":60,"queued":60,"gave":60,"required":60,"every":"","holds":{"A":"60.00"},"status":"paid","net":100,"error":null}'),
('CQ3', 'fixed', 'sale A cp; spend A; spend A; cancel; back 1 60; reopen; cancel; reopen; cancel; reopen; pay',
  '{"dlg":60,"queued":60,"gave":60,"required":60,"every":"","holds":{"A":"60.00"},"status":"paid","net":100,"error":null}'),
('CQ3s', 'fixed', 'sale A cp; spend A; spend A; cancel; back 1 60; reopen; unspend S2; cancel; reopen; cancel; reopen; pay',
  '{"dlg":80,"queued":80,"gave":80,"required":60,"every":"","holds":{"A":"80.00"},"status":"paid","net":100,"error":null}'),
-- A refund by line while it waited, or once cancelled again (446 takes it off
-- the queue; the refund's own row is queued by the next reopening).
('WB', 'fixed', 'sale A cp; spend A; spend A; cancel; back 1 60; reopen; unspend S2; back 1 all; cancel; reopen; pay',
  '{"dlg":80,"queued":80,"gave":80,"required":80,"every":"","holds":{"A":"80.00"},"status":"paid","net":100,"error":null}'),
('WB10', 'fixed', 'sale A cp; spend A; spend A; cancel; back 1 60; reopen; unspend S2; back 1 10; cancel; reopen; pay',
  '{"dlg":80,"queued":80,"gave":80,"required":70,"every":"","holds":{"A":"80.00"},"status":"paid","net":100,"error":null}'),
('WBc', 'fixed', 'sale A cp; spend A; spend A; cancel; back 1 60; reopen; unspend S2; cancel; back 1 all; reopen; pay',
  '{"dlg":80,"queued":80,"gave":80,"required":80,"every":"","holds":{"A":"80.00"},"status":"paid","net":100,"error":null}'),
('WBc10', 'fixed', 'sale A cp; spend A; spend A; cancel; back 1 60; reopen; unspend S2; cancel; back 1 10; reopen; pay',
  '{"dlg":80,"queued":80,"gave":80,"required":70,"every":"","holds":{"A":"80.00"},"status":"paid","net":100,"error":null}'),
-- The guided Cancel the second time ("Record refund paid" ticked; not).
('WG', 'fixed', 'sale A cp; spend A; spend A; cancel; back 1 60; reopen; unspend S2; guidedcancel; reopen; pay',
  '{"dlg":80,"queued":80,"gave":80,"required":80,"every":"","holds":{"A":"80.00"},"status":"paid","net":100,"error":null}'),
('WK', 'fixed', 'sale A cp; spend A; spend A; cancel; back 1 60; reopen; unspend S2; guidedkeep; reopen; pay',
  '{"dlg":80,"queued":80,"gave":80,"required":60,"every":"","holds":{"A":"80.00"},"status":"paid","net":100,"error":null}'),
-- S2's wallet payment corrected to S$5 less while it waited; a refund in
-- full with an Owner's override after the second Cancel.
('WFa', 'fixed', 'sale A cp; spend A; spend A; cancel; back 1 60; reopen; fix S2 amount; cancel; reopen; pay',
  '{"dlg":65,"queued":65,"gave":65,"required":60,"every":"","holds":{"A":"65.00"},"status":"paid","net":100,"error":null}'),
('WX', 'fixed', 'sale A cp; spend A; spend A; cancel; back 1 60; reopen; unspend S2; cancel; backx 1; reopen; pay',
  '{"dlg":80,"queued":80,"gave":80,"required":100,"every":"","holds":{"A":"80.00"},"status":"paid","net":100,"error":null}'),
-- A 'transfer' customer change to B while it waited (with S2 refunded); the
-- buyer merged into K while it waited (nothing spent).
('CHw', 'fixed', 'sale A cp; spend A; spend A; cancel; back 1 60; reopen; change B; cancel; reopen; pay',
  '{"dlg":60,"queued":60,"gave":60,"required":60,"every":"","holds":{"A":"0.00","B":"60.00"},"status":"paid","net":100,"error":null}'),
('CHws', 'fixed', 'sale A cp; spend A; spend A; cancel; back 1 60; reopen; change B; unspend S2; cancel; reopen; pay',
  '{"dlg":80,"queued":80,"gave":80,"required":60,"every":"","holds":{"A":"0.00","B":"80.00"},"status":"paid","net":100,"error":null}'),
('MGw', 'fixed', 'sale A cp; cancel; back 1 60; reopen; merge K A; cancel; reopen; pay',
  '{"dlg":100,"queued":100,"gave":100,"required":60,"every":"","holds":{"A":"0.00","K":"100.00"},"status":"paid","net":100,"error":null}'),
-- Refunded in full with an override first (one session; S1 refunded while it
-- waited); a guided Cancel first.
('RXq', 'fixed', 'sale A cp; spend A; backx 1; reopen; cancel; reopen; pay',
  '{"dlg":80,"queued":80,"gave":80,"required":100,"every":"","holds":{"A":"80.00"},"status":"paid","net":100,"error":null}'),
('RXqs', 'fixed', 'sale A cp; spend A; backx 1; reopen; unspend S1; cancel; reopen; pay',
  '{"dlg":100,"queued":100,"gave":100,"required":100,"every":"","holds":{"A":"100.00"},"status":"paid","net":100,"error":null}'),
('GCq', 'fixed', 'sale A cp; spend A; spend A; guidedcancel; reopen; unspend S2; cancel; reopen; pay',
  '{"dlg":80,"queued":80,"gave":80,"required":60,"every":"","holds":{"A":"80.00"},"status":"paid","net":100,"error":null}'),
-- The Premium Bundle (S$100 paid credit, S$40 Bonus, 2 vouchers; with S2
-- refunded while it waited); one session, with a voucher line beside it.
('PBq', 'fixed', 'sale A pbv; spend A 1 bwallet; spend A 1 bwallet; cancel; back 1 42; reopen; cancel; reopen; pay',
  '{"dlg":100,"queued":100,"gave":100,"dlgv":2,"queuedv":2,"gavev":2,"required":42,"every":"","holds":{"A":"100.00/2"},"status":"paid","error":null}'),
('PBqs', 'fixed', 'sale A pbv; spend A 1 bwallet; spend A 1 bwallet; cancel; back 1 42; reopen; unspend S2; cancel; reopen; pay',
  '{"dlg":120,"queued":120,"gave":120,"dlgv":2,"queuedv":2,"gavev":2,"required":42,"every":"","holds":{"A":"120.00/2"},"status":"paid","error":null}'),
('MIX', 'fixed', 'sale A pbv,v; spend A 1 bwallet; cancel; back 1 42; reopen; cancel; reopen; pay',
  '{"dlg":120,"queued":120,"gave":120,"dlgv":4,"queuedv":4,"gavev":4,"required":42,"every":"","holds":{"A":"120.00/4"},"status":"paid","error":null}'),
-- Paid in part, cancelled, reopened and paid in full, then K5's steps (with
-- S1 refunded while it waited).
('PTF', 'fixed', 'sale A cp 40; spend A; cancel; reopen; pay; cancel; back 1 40; reopen; cancel; reopen; pay',
  '{"dlg":80,"queued":80,"gave":80,"required":40,"every":"","holds":{"A":"80.00"},"status":"paid","net":100,"error":null}'),
('PTF2', 'fixed', 'sale A cp 40; spend A; cancel; reopen; pay; cancel; back 1 40; reopen; unspend S1; cancel; reopen; pay',
  '{"dlg":100,"queued":100,"gave":100,"required":40,"every":"","holds":{"A":"100.00"},"status":"paid","net":100,"error":null}'),
-- Controls: the same with and without 474.
('CTL0', 'control', 'sale A cp; spend A; spend A; cancel; reopen',
  '{"dlg":60,"queued":60,"gave":60,"required":0,"every":"","holds":{"A":"60.00"},"status":"paid","net":100,"error":null}'),
('CTL1', 'control', 'sale A cp; spend A; spend A; cancel; back 1 60; reopen; pay',
  '{"dlg":60,"queued":60,"gave":60,"required":60,"every":"","holds":{"A":"60.00"},"status":"paid","net":100,"error":null}'),
('CTL2', 'control', 'sale A cp; spend A; spend A; cancel; back 1 60; reopen; unspend S2; pay',
  '{"dlg":60,"queued":60,"gave":80,"required":60,"every":"","holds":{"A":"80.00"},"status":"paid","net":100,"error":null}'),
('PRc', 'control', 'sale A cp; spend A; spend A; cancel; unspend S2; reopen',
  '{"dlg":80,"queued":80,"gave":80,"required":0,"every":"","holds":{"A":"80.00"},"status":"paid","net":100,"error":null}'),
('VQ', 'control', 'sale A v; cancel; backv 1 1; reopen; cancel; reopen; pay',
  '{"dlg":0,"gave":0,"dlgv":2,"queuedv":2,"gavev":2,"required":30,"every":"","holds":{"A":"0.00/2"},"status":"paid","net":60,"error":null}'),
('VQ3', 'control', 'sale A v; cancel; backv 1 1; reopen; cancel; reopen; cancel; reopen; pay',
  '{"dlg":0,"gave":0,"dlgv":2,"queuedv":2,"gavev":2,"required":30,"every":"","holds":{"A":"0.00/2"},"status":"paid","net":60,"error":null}'),
('VQ0', 'control', 'sale A v; cancel; backv 1 1; reopen; pay',
  '{"dlg":0,"gave":0,"dlgv":2,"queuedv":2,"gavev":2,"required":30,"every":"","holds":{"A":"0.00/2"},"status":"paid","net":60,"error":null}'),
('TH0', 'control', 'sale A th; cancel; backt 1 20; reopen; pay',
  '{"dlg":0,"gave":0,"dlgs":3,"gaves":3,"required":20,"every":"","status":"paid","net":60,"error":null}'),
('PTq', 'control', 'sale A cp 40; spend A; cancel; reopen; cancel; reopen; pay',
  '{"dlg":0,"queued":0,"gave":0,"required":60,"every":"","holds":{"A":"80.00"},"status":"paid","net":100,"error":null}'),
-- Known (474's NOT COVERED, the same with and without 474): 1 a session
-- queued by two reopenings, the payment refused; 2 paid in part, released
-- again at the reopening itself.
('THq', 'known', 'sale A th; cancel; backt 1 20; reopen; cancel; reopen; pay',
  '{"dlg":0,"gave":0,"dlgs":3,"gaves":0,"required":20,"every":"","status":"partially_paid","net":40,"error~":"pay: Therapy session reopening changed; reload its original evidence%"}'),
('PT0', 'known', 'sale A cp 40; spend A; cancel; reopen; pay',
  '{"dlg":0,"queued":0,"gave":0,"required":60,"every":"","holds":{"A":"80.00"},"status":"paid","net":100,"error":null}');
-- 475 (the Owner, 27 Oct 2026: "Yes, fix it next"; NOT COVERED 1): where 475
-- is in, THq's second reopening queues nothing more for its session, and the
-- payment reinstates the 3 sessions once: THq is checked as 475 settles it
-- (paid, S$60 net, the dialog's 3 sessions reinstated). Where 475 is in, 474
-- is in too, so R never runs (-v nomig=1) and nothing compares THq with
-- before 474.
update t474_cases set expect = '{"dlg":0,"gave":0,"dlgs":3,"gaves":3,"required":20,"every":"","status":"paid","net":60,"error":null}'
 where k = 'THq' and pg_temp.t474_475_in();

-- States for the header's query (Q), made before 474 (R): what it lists, by
-- reason, with its count (null: not listed).
create temp table t474_qstates(k text primary key, steps text not null, reason text, n bigint);
insert into t474_qstates values
  ('Q1', 'sale A cp; spend A; spend A; cancel; back 1 60; reopen; unspend S2; cancel', '1', 2),
  ('Q1b', 'sale A cp; spend A; spend A; cancel; back 1 60; reopen; cancel', '1', 1),
  ('Q2', 'sale A cp; spend A; spend A; cancel; back 1 60; reopen; unspend S2', '2', 2),
  ('Q3', 'sale A th; cancel; backt 1 20; reopen; cancel', '3', 1),
  ('Q4', 'sale A th; cancel; backt 1 20; reopen; cancel; reopen', '4', 1),
  ('Q0', 'sale A cp; spend A; spend A; cancel', null, null),
  ('Q0b', 'sale A cp; spend A; spend A; cancel; back 1 60; reopen; pay', null, null);

-- ===== S. Where it starts =====
do $$ begin
  perform pg_temp.t474_check(pg_temp.t474_462_in() and pg_temp.t474_463_in() and pg_temp.t474_470_in() and pg_temp.t474_471_in()
      and pg_temp.t474_472_in() and pg_temp.t474_473_in(),
    'S 462, 463, 470, 471, 472 and 473 are in (474 goes in after them)');
  perform pg_temp.t474_check((select string_agg(pg_get_triggerdef(t.oid), E'\n' order by t.tgname) from pg_trigger t
                               where t.tgrelid = 'public.invoices'::regclass and t.tgfoid = 'public.apply_reopened_invoice_benefits()'::regprocedure)
      = 'CREATE TRIGGER invoice_reopen_benefits_settled AFTER UPDATE OF status ON public.invoices FOR EACH ROW EXECUTE FUNCTION apply_reopened_invoice_benefits()',
    'S the trigger that gives a reopening''s credit back at settlement is as read');
end $$;
\if :{?nomig}
do $$ begin
  perform pg_temp.t474_check(pg_temp.t474_in() and (pg_temp.t474_at('after') or pg_temp.t474_478_in()),
    'S -v nomig=1: 474 is in, as tested (or 478''s text on it)');
end $$;
\else
do $$ begin
  perform pg_temp.t474_check(not pg_temp.t474_in() and pg_temp.t474_at('before'),
    'S 474 is not in yet and the preview is 451''s (this suite installs it; use -v nomig=1 where it is in)');
end $$;

-- ===== R. Before 474: each case reproduced (undone afterwards) =====
-- A 'fixed' case's dialog says other than what its Reopen queues and the
-- payment gives; a control and a known case end exactly as expected.
savepoint t474_r;
do $$
declare c record; o jsonb; res text := '';
begin
  for c in select * from t474_cases order by ord loop
    o := pg_temp.t474_run('before', c.k, c.steps);
    if c.kind = 'fixed' then
      perform pg_temp.t474_check(not pg_temp.t474_meets(o, c.expect) and coalesce(o->>'every', '') <> ''
          and pg_temp.t474_meets(o, c.expect - 'dlg' - 'every') and coalesce(o->>'invariants', '') = '',
        'R ' || c.k || ' without 474 the dialog already says what is given, or something else differs: '
        || coalesce(pg_temp.t474_diff(o, c.expect), '') || ' ' || o::text);
      res := res || format(E'\n  %s: S$%s shown, S$%s given (%s)', c.k, o->>'dlg', o->>'gave', o->>'every');
    else
      perform pg_temp.t474_check(pg_temp.t474_meets(o, c.expect) and coalesce(o->>'invariants', '') = ''
          and coalesce((o->>'cancel_left')::numeric, 0) = 0,
        'R ' || c.kind || ' ' || c.k || ' without 474: ' || coalesce(pg_temp.t474_diff(o, c.expect), '') || ' ' || o::text);
    end if;
  end loop;
  for c in select * from t474_qstates loop
    perform pg_temp.t474_run('before', c.k, c.steps);
  end loop;
  raise notice 'PASS R: without 474 every fixed case''s Reopen dialog says other than what its Reopen queues and the payment gives (the fault reproduced; everything else as 474 leaves it), the controls and the known cases as expected:%', res;
end $$;

-- ===== Q. The header's read-only query, on these states =====
create temp table t474_q as select * from pg_temp.t474_header_query();
do $$
declare c record;
begin
  for c in select * from t474_qstates loop
    if c.reason is null then
      perform pg_temp.t474_check(not exists (select 1 from t474_q q join invoices i on i.invoice_no = q.invoice_no
                                              where i.id = pg_temp.t474_id('before/' || c.k || '/inv')), 'Q ' || c.k || ' is listed');
    else
      perform pg_temp.t474_check((select string_agg(left(q.reason, 1) || '/' || q.n, ',' order by q.reason) from t474_q q join invoices i on i.invoice_no = q.invoice_no
                                   where i.id = pg_temp.t474_id('before/' || c.k || '/inv')) = c.reason || '/' || c.n,
        'Q ' || c.k || ' is listed as ' || coalesce((select string_agg(left(q.reason, 1) || '/' || q.n, ',' order by q.reason) from t474_q q
                                                      join invoices i on i.invoice_no = q.invoice_no
                                                     where i.id = pg_temp.t474_id('before/' || c.k || '/inv')), 'nothing')
        || ', not ' || c.reason || '/' || c.n);
    end if;
  end loop;
  -- Of the cases, only the known THq (a session queued by two reopenings, its
  -- payment refused: 4) is left in a state the query lists; every other
  -- ended settled or with nothing waiting.
  perform pg_temp.t474_check((select string_agg(x.k || ':' || left(q.reason, 1), ',' order by x.k) from t474_q q join invoices i on i.invoice_no = q.invoice_no
                               join (select split_part(t.k, '/', 2) as k, t.id from t474 t where t.k ~ '^before/[^/]+/inv$') x on x.id = i.id
                              where x.k not in (select k from t474_qstates)) = 'THq:4',
    'Q the cases listed: ' || coalesce((select string_agg(x.k || ':' || left(q.reason, 1), ',' order by x.k) from t474_q q join invoices i on i.invoice_no = q.invoice_no
                               join (select split_part(t.k, '/', 2) as k, t.id from t474 t where t.k ~ '^before/[^/]+/inv$') x on x.id = i.id
                              where x.k not in (select k from t474_qstates)), 'none'));
  raise notice 'PASS Q: the header''s query lists, by reason, a cancelled invoice with credit still waiting (1: Q1 2 rows, Q1b 1), a reopening waiting (2: Q2), a cancelled invoice with a session waiting (3: Q3) and a session queued twice (4: Q4, and the known THq); nothing with nothing waiting (Q0, Q0b, every settled case)';
end $$;
select coalesce(jsonb_object_agg(k, v), '{}'::jsonb)::text as t474_rbefore from t474_res where phase = 'before' \gset
rollback to savepoint t474_r;
insert into t474_res select 'before', key, value from jsonb_each(:'t474_rbefore'::jsonb);

-- ===== 9. The refusals, each changing nothing =====
-- 9a The preview is neither 451's nor 474's.
savepoint t474_9;
alter function public.invoice_reopen_preview_before_sessions(uuid) set work_mem = '64kB';
\set ON_ERROR_STOP off
\ir ../../../supabase/474_reopen_dialog_counts_waiting_credit.sql
\set ON_ERROR_STOP on
rollback to savepoint t474_9;
select set_config('t474.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t474_check(current_setting('t474.msg') like '474: public.invoice_reopen_preview_before_sessions(uuid) is not the version this was tested against (md5 %). Re-read it and re-test before applying.'
      and not pg_temp.t474_in() and pg_temp.t474_at('before'), '9a refused with: ' || current_setting('t474.msg'));
end $$;
-- 9b A function it relies on is not as read (a setting added to it): its
-- caller, what gives the queue back at settlement, 472's forwarder.
savepoint t474_9;
alter function public.invoice_reopen_preview(uuid) set work_mem = '64kB';
\set ON_ERROR_STOP off
\ir ../../../supabase/474_reopen_dialog_counts_waiting_credit.sql
\set ON_ERROR_STOP on
rollback to savepoint t474_9;
select set_config('t474.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t474_check(current_setting('t474.msg') like '474: public.invoice_reopen_preview(uuid) is missing or not the version this was tested against (md5 %). Re-read it and re-test before applying (474 goes in after 472).'
      and not pg_temp.t474_in(), '9b refused with: ' || current_setting('t474.msg'));
end $$;
savepoint t474_9;
alter function public.apply_reopened_invoice_benefits() set work_mem = '64kB';
\set ON_ERROR_STOP off
\ir ../../../supabase/474_reopen_dialog_counts_waiting_credit.sql
\set ON_ERROR_STOP on
rollback to savepoint t474_9;
select set_config('t474.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t474_check(current_setting('t474.msg') like '474: public.apply_reopened_invoice_benefits() is missing or not the version this was tested against (md5 %)%'
      and not pg_temp.t474_in(), '9b2 refused with: ' || current_setting('t474.msg'));
end $$;
savepoint t474_9;
alter function public.credit_given_back_follows(uuid) set work_mem = '64kB';
\set ON_ERROR_STOP off
\ir ../../../supabase/474_reopen_dialog_counts_waiting_credit.sql
\set ON_ERROR_STOP on
rollback to savepoint t474_9;
select set_config('t474.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t474_check(current_setting('t474.msg') like '474: public.credit_given_back_follows(uuid) is missing or not the version this was tested against (md5 %)%'
      and not pg_temp.t474_in(), '9b3 refused with: ' || current_setting('t474.msg'));
end $$;
-- 9c Another function takes its name (an overload).
savepoint t474_9;
create function public.invoice_reopen_preview_before_sessions(p text) returns jsonb language sql as $f$ select null::jsonb $f$;
\set ON_ERROR_STOP off
\ir ../../../supabase/474_reopen_dialog_counts_waiting_credit.sql
\set ON_ERROR_STOP on
rollback to savepoint t474_9;
select set_config('t474.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t474_check(current_setting('t474.msg') = '474: another function takes the name of the one this changes: invoice_reopen_preview_before_sessions(text)'
      and not pg_temp.t474_in(), '9c refused with: ' || current_setting('t474.msg'));
end $$;
-- 9d A new caller of the preview (it would read the larger figure).
savepoint t474_9;
create function public.t474_probe_preview(p uuid) returns jsonb language sql as $f$ select public.invoice_reopen_preview_before_sessions(p) $f$;
\set ON_ERROR_STOP off
\ir ../../../supabase/474_reopen_dialog_counts_waiting_credit.sql
\set ON_ERROR_STOP on
rollback to savepoint t474_9;
select set_config('t474.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t474_check(current_setting('t474.msg') like '474: the functions that call the Reopen dialog''s preview are not as read on 26 Oct 2026 (%t474_probe_preview(uuid)%)%'
      and not pg_temp.t474_in(), '9d refused with: ' || current_setting('t474.msg'));
end $$;
savepoint t474_9;
create function public.t474_probe_reopen(p uuid) returns jsonb language sql as $f$ select public.invoice_reopen_preview(p) $f$;
\set ON_ERROR_STOP off
\ir ../../../supabase/474_reopen_dialog_counts_waiting_credit.sql
\set ON_ERROR_STOP on
rollback to savepoint t474_9;
select set_config('t474.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t474_check(current_setting('t474.msg') like '474: the functions that call the Reopen dialog''s preview are not as read on 26 Oct 2026 (invoice_reopen_preview(uuid) / %t474_probe_reopen(uuid)%)%'
      and not pg_temp.t474_in(), '9d2 refused with: ' || current_setting('t474.msg'));
end $$;
-- 9e A new writer of the reopening queue.
savepoint t474_9;
create function public.t474_probe_queue() returns void language sql as $f$ update public.invoice_reopen_benefits set amount = amount where false $f$;
\set ON_ERROR_STOP off
\ir ../../../supabase/474_reopen_dialog_counts_waiting_credit.sql
\set ON_ERROR_STOP on
rollback to savepoint t474_9;
select set_config('t474.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t474_check(current_setting('t474.msg') like '474: what writes the reopening queue (invoice_reopen_benefits) is not as read on 26 Oct 2026 (%t474_probe_queue()%)%'
      and not pg_temp.t474_in(), '9e refused with: ' || current_setting('t474.msg'));
end $$;
-- 9f The trigger that gives the queue back at settlement is not as read.
savepoint t474_9;
drop trigger invoice_reopen_benefits_settled on public.invoices;
create trigger invoice_reopen_benefits_settled after update of status, paid_amount on public.invoices
  for each row execute function public.apply_reopened_invoice_benefits();
\set ON_ERROR_STOP off
\ir ../../../supabase/474_reopen_dialog_counts_waiting_credit.sql
\set ON_ERROR_STOP on
rollback to savepoint t474_9;
select set_config('t474.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t474_check(current_setting('t474.msg') = '474: the trigger that gives a reopening''s credit back at settlement is not as read on 26 Oct 2026'
      and not pg_temp.t474_in(), '9f refused with: ' || current_setting('t474.msg'));
end $$;
-- 9g The queue no longer holds one row per ledger row.
savepoint t474_9;
alter table public.invoice_reopen_benefits drop constraint invoice_reopen_benefits_source_ledger_id_key;
\set ON_ERROR_STOP off
\ir ../../../supabase/474_reopen_dialog_counts_waiting_credit.sql
\set ON_ERROR_STOP on
rollback to savepoint t474_9;
select set_config('t474.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t474_check(current_setting('t474.msg') like '474: the reopening queue no longer holds one row per ledger row%'
      and not pg_temp.t474_in(), '9g refused with: ' || current_setting('t474.msg'));
end $$;
-- 9h Other grants: refused. The same grants in another order: not.
savepoint t474_9;
grant execute on function public.invoice_reopen_preview_before_sessions(uuid) to authenticated;
\set ON_ERROR_STOP off
\ir ../../../supabase/474_reopen_dialog_counts_waiting_credit.sql
\set ON_ERROR_STOP on
rollback to savepoint t474_9;
select set_config('t474.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t474_check(current_setting('t474.msg') like '474: who may call public.invoice_reopen_preview_before_sessions(uuid) is not as read on 26 Oct 2026 (%)'
      and not pg_temp.t474_in(), '9h refused with: ' || current_setting('t474.msg'));
end $$;
savepoint t474_9;
revoke execute on function public.invoice_reopen_preview_before_sessions(uuid) from postgres;
grant execute on function public.invoice_reopen_preview_before_sessions(uuid) to postgres;
select pg_temp.t474_check((select proacl::text from pg_proc where oid = 'public.invoice_reopen_preview_before_sessions(uuid)'::regprocedure)
         <> '{postgres=X/postgres,service_role=X/postgres}'
       and pg_temp.t474_grant_set('invoice_reopen_preview_before_sessions(uuid)') = '{postgres=X/postgres,service_role=X/postgres}',
  '9h2 set-up: the same grants in another order');
\ir ../../../supabase/474_reopen_dialog_counts_waiting_credit.sql
select pg_temp.t474_in() and pg_temp.t474_at('after') as t474_9h2_in \gset
rollback to savepoint t474_9;
select pg_temp.t474_check(:'t474_9h2_in'::boolean and not pg_temp.t474_in(), '9h2 the same grants in another order stopped it');
do $$ begin
  raise notice 'PASS 9: refused, changing nothing, where the preview is neither 451''s nor 474''s, a function it relies on is not as tested (its caller, what gives back at settlement, 472''s forwarder), another function takes its name, a new function calls the preview or invoice_reopen_preview, a new function writes the reopening queue, the settlement trigger or the queue''s unique key is not as read, or other grants; the same grants in another order do not stop it';
end $$;

-- ===== M. Begun before 474, the dialog read after it =====
-- A reopening cancelled again (MK5), one changed to B while it waited and
-- cancelled again (MCH), one still waiting (MW).
do $$ begin
  perform pg_temp.t474_run('mid', 'MK5', 'sale A cp; spend A; spend A; cancel; back 1 60; reopen; unspend S2; cancel', 1, 8);
  perform pg_temp.t474_run('mid', 'MCH', 'sale A cp; spend A; spend A; cancel; back 1 60; reopen; change B; unspend S2; cancel', 1, 9);
  perform pg_temp.t474_run('mid', 'MW', 'sale A cp; spend A; spend A; cancel; back 1 60; reopen; unspend S2', 1, 7);
  perform pg_temp.t474_check((invoice_reopen_preview(pg_temp.t474_id('mid/MK5/inv'))->>'credit_to_reinstate_after_settlement')::numeric = 0,
    'M MK5 before 474 the dialog already counts what waits');
end $$;
\endif

-- ===== 10. Install 474, twice =====
\if :{?nomig}
do $$ begin raise notice 'NOTE 10: -v nomig=1, so 474 is not installed here (R, Q, 9 and M are skipped)'; end $$;
\else
\ir ../../../supabase/474_reopen_dialog_counts_waiting_credit.sql
do $$ begin insert into t474_fp values ('first', pg_temp.t474_fingerprint()); end $$;
\ir ../../../supabase/474_reopen_dialog_counts_waiting_credit.sql
do $$ begin insert into t474_fp values ('second', pg_temp.t474_fingerprint()); end $$;
\endif
do $$
begin
  perform pg_temp.t474_check(pg_temp.t474_in() and (pg_temp.t474_at('after') or pg_temp.t474_478_in()), '10 474 is not installed as tested');
  perform pg_temp.t474_check((select count(*) from pg_proc where pronamespace = 'public'::regnamespace
                               and proname = 'invoice_reopen_preview_before_sessions') = 1, '10 an overload exists');
  perform pg_temp.t474_check(pg_temp.t474_grant_set('invoice_reopen_preview_before_sessions(uuid)') = '{postgres=X/postgres,service_role=X/postgres}'
      and pg_temp.t474_grant_set('invoice_reopen_preview(uuid)') = '{authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres}'
      and not has_function_privilege('anon', 'public.invoice_reopen_preview_before_sessions(uuid)', 'execute')
      and not has_function_privilege('authenticated', 'public.invoice_reopen_preview_before_sessions(uuid)', 'execute')
      and not has_function_privilege('anon', 'public.invoice_reopen_preview(uuid)', 'execute'),
    '10 who may call the previews changed');
  if exists (select 1 from t474_fp where k = 'first') then
    perform pg_temp.t474_check((select fp from t474_fp where k = 'second') = (select fp from t474_fp where k = 'first'),
      '10 the second run of 474 changed functions');
    perform pg_temp.t474_check(split_part((select fp from t474_fp where k = 'first'), ' ', 2) = split_part((select fp from t474_fp where k = 'start'), ' ', 2),
      '10 474 changed the number of functions');
    perform pg_temp.t474_check(pg_temp.t474_grants() = (select fp from t474_fp where k = 'grants'), '10 the grants changed');
    -- On a copy of production at 471 with 472 and 473 in: the AFTER fingerprint.
    if (select fp from t474_fp where k = 'start') = 'eb7399d17225fcc55142a773e35b12b6 1387' then
      perform pg_temp.t474_check((select fp from t474_fp where k = 'first') = 'c19401919a0a8b67746e18b8f7a78639 1387',
        '10 the fingerprint after 474 is ' || (select fp from t474_fp where k = 'first'));
    end if;
  end if;
  raise notice 'PASS 10: 474 installed (the preview %); %; no overload; the grants as before (the preview for the service role alone, invoice_reopen_preview for signed-in staff)',
    md5(pg_get_functiondef('public.invoice_reopen_preview_before_sessions(uuid)'::regprocedure)),
    coalesce('the second run changed nothing (' || (select fp from t474_fp where k = 'second') || ')', 'it was in before the suite (nomig)');
end $$;

-- ===== M (finished). Begun before 474, the dialog read after it =====
\if :{?nomig}
do $$ begin raise notice 'NOTE M: -v nomig=1 (474 in), so no case was begun before it'; end $$;
\else
do $$
declare o jsonb; inv uuid;
begin
  -- MW: the reopening still waits (S$60 queued at Reopen, S2's S$20 held
  -- back and queued for it): its preview now shows S$80, what its payment
  -- gives; paid, A S$80.
  inv := pg_temp.t474_id('mid/MW/inv');
  perform pg_temp.t474_check((invoice_reopen_preview(inv)->>'credit_to_reinstate_after_settlement')::numeric = 80
      and pg_temp.t474_waiting(inv) = 80 and not (invoice_reopen_preview(inv)->>'can_reopen')::boolean,
    'M MW the waiting reopening''s preview reads ' || (invoice_reopen_preview(inv)->>'credit_to_reinstate_after_settlement'));
  o := pg_temp.t474_run('mid', 'MW', 'sale A cp; spend A; spend A; cancel; back 1 60; reopen; unspend S2; pay', 8);
  perform pg_temp.t474_check(o->'holds' @> '{"A":"80.00"}' and o->>'status' = 'paid' and (o->>'gave')::numeric = 80 and coalesce(o->>'invariants', '') = '',
    'M MW ' || o::text);
  -- MK5, MCH: cancelled again before 474; reopened after it: the dialog says
  -- what the payment gives (A S$80; B S$80).
  o := pg_temp.t474_run('mid', 'MK5', 'sale A cp; spend A; spend A; cancel; back 1 60; reopen; unspend S2; cancel; reopen; pay', 9);
  perform pg_temp.t474_check(pg_temp.t474_meets(o, '{"dlg":80,"queued":80,"gave":80,"every":"","holds":{"A":"80.00"},"status":"paid","error":null}')
      and coalesce(o->>'invariants', '') = '',
    'M MK5 ' || o::text);
  o := pg_temp.t474_run('mid', 'MCH', 'sale A cp; spend A; spend A; cancel; back 1 60; reopen; change B; unspend S2; cancel; reopen; pay', 10);
  perform pg_temp.t474_check(pg_temp.t474_meets(o, '{"dlg":80,"queued":80,"gave":80,"every":"","holds":{"A":"0.00","B":"80.00"},"status":"paid","error":null}')
      and coalesce(o->>'invariants', '') = '',
    'M MCH ' || o::text);
  raise notice 'PASS M: begun before 474 (a reopening cancelled again, one changed to B while it waited, one still waiting), read after it: the dialog says what the payment gives (A S$80; B S$80; the waiting one''s preview S$80)';
end $$;
\endif

-- ===== A. After 474: each case =====
do $$
declare c record; o jsonb; b jsonb; res text := ''; n int := 0;
begin
  for c in select * from t474_cases order by ord loop
    o := pg_temp.t474_run('after', c.k, c.steps);
    perform pg_temp.t474_check(pg_temp.t474_meets(o, c.expect) and coalesce(o->>'invariants', '') = ''
        and coalesce((o->>'cancel_left')::numeric, 0) = 0,
      'A ' || c.kind || ' ' || c.k || ': ' || coalesce(pg_temp.t474_diff(o, c.expect), '') || ' ' || o::text);
    -- Where R ran: every key but the dialog's credit as before 474.
    b := (select v from t474_res where phase = 'before' and k = c.k);
    if b is not null then
      perform pg_temp.t474_check(pg_temp.t474_but_dialog(o) = pg_temp.t474_but_dialog(b),
        'A ' || c.k || ' differs from before 474 beyond the dialog''s credit: before ' || pg_temp.t474_but_dialog(b)::text
        || ', after ' || pg_temp.t474_but_dialog(o)::text);
      if c.kind <> 'fixed' then
        perform pg_temp.t474_check(o = b, 'A ' || c.kind || ' ' || c.k || ' differs from before 474: ' || b::text || ' / ' || o::text);
      end if;
      n := n + 1;
    end if;
    if c.kind = 'fixed' then res := res || format(' %s S$%s;', c.k, o->>'dlg'); end if;
  end loop;
  raise notice 'PASS A: after 474 every case''s Reopen dialog says what its Reopen queues and the payment gives:%; the controls and known cases as before; % cases compared with before 474: nothing else differs (who holds what, the money, the plans, the invariants, Cancel)', res, n;
end $$;

-- ===== P. Probes =====
-- P1 The preview's other figures are exactly 451's, and its credit is 451's
-- plus what still waits: 451's text worked back from 474's (the lines 474
-- adds taken out; by md5), installed in a block that is undone, on states
-- just before the last Reopen of K5, CQ, WB10, CHws, MGw, RXqs, PBqs, MIX,
-- PTF2, VQ, TH0, THq, PT0, CTL0 and PRc.
-- 478 (the Owner, 27 Oct 2026): where 478 is in, 474's text is first worked
-- back from 478's (the lines 478 adds taken out: its block, its variables,
-- its keys and its sentence; by md5), and 474's own figures are read from it
-- in the same undone block.
create function pg_temp.t474_def474() returns text language plpgsql as $f$
declare d text := pg_get_functiondef('public.invoice_reopen_preview_before_sessions(uuid)'::regprocedure);
  a int; z int;
begin
  if not pg_temp.t474_478_in() then return d; end if;
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
create function pg_temp.t474_def451() returns text language plpgsql as $f$
declare d text := pg_temp.t474_def474();
  a int; z int; m text := E'q.applied_at is null),0);\n';
begin
  a := position(E' -- 474 (the Owner' in d);
  z := position(m in d);
  if a = 0 or z = 0 then return null; end if;
  return substr(d, 1, a - 1) || substr(d, z + length(m));
end $f$;
do $$
declare c record; inv uuid; p474 jsonb; p451 jsonb; d text := pg_temp.t474_def451(); i int; res text := '';
  d474 text := pg_temp.t474_def474(); p478 jsonb;
begin
  perform pg_temp.t474_check(md5(d474) = '7e1ef2d25415e69b3f770fe2efd45190', 'P1 474''s text is not what 478''s gives back with its lines taken out: ' || md5(d474));
  perform pg_temp.t474_check(md5(d) = '12206ed066495024421b3b44a6a9d8e2', 'P1 451''s text is not what 474''s gives back with its lines taken out: ' || md5(d));
  for c in select x.k, x.steps, x.upto from (values
      ('K5', 'sale A cp; spend A; spend A; cancel; back 1 60; reopen; unspend S2; cancel', 8),
      ('CQ', 'sale A cp; spend A; spend A; cancel; back 1 60; reopen; cancel', 7),
      ('WB10', 'sale A cp; spend A; spend A; cancel; back 1 60; reopen; unspend S2; back 1 10; cancel', 9),
      ('CHws', 'sale A cp; spend A; spend A; cancel; back 1 60; reopen; change B; unspend S2; cancel', 9),
      ('MGw', 'sale A cp; cancel; back 1 60; reopen; merge K A; cancel', 6),
      ('RXqs', 'sale A cp; spend A; backx 1; reopen; unspend S1; cancel', 6),
      ('PBqs', 'sale A pbv; spend A 1 bwallet; spend A 1 bwallet; cancel; back 1 42; reopen; unspend S2; cancel', 8),
      ('MIX', 'sale A pbv,v; spend A 1 bwallet; cancel; back 1 42; reopen; cancel', 6),
      ('PTF2', 'sale A cp 40; spend A; cancel; reopen; pay; cancel; back 1 40; reopen; unspend S1; cancel', 10),
      ('VQ', 'sale A v; cancel; backv 1 1; reopen; cancel', 5),
      ('TH0', 'sale A th; cancel; backt 1 20', 3),
      ('THq', 'sale A th; cancel; backt 1 20; reopen; cancel', 5),
      ('PT0', 'sale A cp 40; spend A; cancel', 3),
      ('CTL0', 'sale A cp; spend A; spend A; cancel', 4),
      ('PRc', 'sale A cp; spend A; spend A; cancel; unspend S2', 5)) x(k, steps, upto) loop
    perform pg_temp.t474_run('P1', c.k, c.steps, 1, c.upto);
    perform pg_temp.t474_check((select err from t474_err where pre = 'P1/' || c.k) is null, 'P1 ' || c.k || ' refused: ' || (select err from t474_err where pre = 'P1/' || c.k));
    inv := pg_temp.t474_id('P1/' || c.k || '/inv');
    p474 := invoice_reopen_preview(inv); p478 := p474;
    begin
      if pg_temp.t474_478_in() then
        execute d474;
        p474 := invoice_reopen_preview(inv);
      end if;
      execute d;
      p451 := invoice_reopen_preview(inv);
      raise exception using errcode = 'P4741', message = 'undo';
    exception when sqlstate 'P4741' then null;
    end;
    perform pg_temp.t474_check(pg_temp.t474_in() and (pg_temp.t474_at('after') or pg_temp.t474_478_in()), 'P1 451''s text was left in');
    -- 478: where it is in, every figure but its own and its explanation is 474's.
    perform pg_temp.t474_check(p478 - array['credit_released_on_reopen', 'bundle_vouchers_given_on_reopen', 'bundle_vouchers_to_choose_on_reopen',
                                            'credit_from_settling_payment', 'credit_receivers', 'reward_units_given_on_reopen',
                                            'bundle_vouchers_from_settling_payment', 'bundle_vouchers_to_choose_from_settling_payment',
                                            'reward_units_from_settling_payment'] - 'explanation' = p474 - 'explanation',
      'P1 ' || c.k || ': 478 ' || p478::text || ' / 474 ' || p474::text);
    perform pg_temp.t474_check(p474 - 'credit_to_reinstate_after_settlement' = p451 - 'credit_to_reinstate_after_settlement'
        and (p474->>'credit_to_reinstate_after_settlement')::numeric
            = (p451->>'credit_to_reinstate_after_settlement')::numeric + pg_temp.t474_waiting(inv),
      'P1 ' || c.k || ': 474 ' || p474::text || ' / 451 ' || p451::text);
    res := res || format(' %s %s=%s+%s;', c.k, p474->>'credit_to_reinstate_after_settlement', p451->>'credit_to_reinstate_after_settlement', pg_temp.t474_waiting(inv));
  end loop;
  raise notice 'PASS P1: every other figure of the Reopen dialog is 451''s (blockers, voucher units, sessions, stock, the money, the explanation); its credit is 451''s plus what still waits:%', res;
end $$;
-- P2 What a reopening records: the revision's snapshot ('reopen_preview')
-- and its Audit Log row ('invoice_reopened') carry the figure the dialog
-- showed (K5's first Reopen S$60, its last S$80).
do $$
declare inv uuid := pg_temp.t474_id('after/K5/inv');
begin
  perform pg_temp.t474_check((select (r.snapshot->'reopen_preview'->>'credit_to_reinstate_after_settlement')::numeric
                                from invoice_revisions r where r.invoice_id = inv and r.snapshot ? 'reopen_preview'
                               order by r.revision_no desc limit 1) = 80
      and (select array_agg((a.new_data->>'credit_to_reinstate_after_settlement')::numeric order by (a.new_data->>'credit_to_reinstate_after_settlement')::numeric)
             from audit_logs a where a.record_id = inv and a.action = 'invoice_reopened') = '{60,80}'::numeric[],
    'P2 K5: the reopening recorded ' || coalesce((select r.snapshot->'reopen_preview'->>'credit_to_reinstate_after_settlement'
                                                   from invoice_revisions r where r.invoice_id = inv and r.snapshot ? 'reopen_preview'
                                                  order by r.revision_no desc limit 1), '?'));
  raise notice 'PASS P2: a reopening records the figure the dialog showed (its revision''s snapshot and its Audit Log row: S$60, then S$80 for K5)';
end $$;
-- P3 A waiting reopening (the dialog is not offered: can_reopen false): its
-- preview shows the credit its payment gives (471's P3: S$80 where it showed
-- S$0.00).
do $$
declare inv uuid; pv jsonb;
begin
  perform pg_temp.t474_run('P3', 'W', 'sale A cp; spend A; spend A; cancel; back 1 60; reopen; unspend S2', 1, 7);
  inv := pg_temp.t474_id('P3/W/inv'); pv := invoice_reopen_preview(inv);
  perform pg_temp.t474_check((pv->>'credit_to_reinstate_after_settlement')::numeric = 80 and pg_temp.t474_waiting(inv) = 80
      and not (pv->>'can_reopen')::boolean and pv->'blockers' @> '["Only cancelled or refunded invoices can be reopened"]'
      and (select status::text from invoices where id = inv) = 'partially_paid',
    'P3 W: ' || pv::text);
  raise notice 'PASS P3: a waiting reopening''s preview shows S$80, what its payment gives; it cannot be reopened ("Only cancelled or refunded invoices can be reopened")';
end $$;
-- P4 Nothing added or dropped; the grants as before.
do $$ begin
  perform pg_temp.t474_check(split_part(pg_temp.t474_fingerprint(), ' ', 2) = split_part((select fp from t474_fp where k = 'start'), ' ', 2)
      and pg_temp.t474_grants() = (select fp from t474_fp where k = 'grants'),
    'P4 the functions or grants changed: ' || pg_temp.t474_fingerprint());
  raise notice 'PASS P4: no function added or dropped; the grant list as before';
end $$;

-- ===== K. KNOWN (474's NOT COVERED), checked as they are =====
do $$
declare inv uuid; o jsonb;
begin
  -- K1 (NOT COVERED 1): a 3-session line, cancelled, S$20 refunded by line,
  -- reopened, cancelled, reopened: the session is queued by both reopenings,
  -- and the payment is refused (THq, the same before 474 and after it).
  o := (select v from t474_res where phase = 'after' and k = 'THq'); inv := pg_temp.t474_id('after/THq/inv');
  if pg_temp.t474_475_in() then
    -- 475 (the Owner, 27 Oct 2026: "Yes, fix it next"): fixed where 475 is
    -- in: the second reopening queued nothing more, the payment reinstated
    -- the 3 sessions once (one queue row, applied) and settled the invoice.
    perform pg_temp.t474_check(o->>'error' is null and o->>'status' = 'paid' and (o->>'dlgs')::int = 3 and (o->>'gaves')::int = 3
        and (select count(*) from invoice_reopen_sessions q where q.invoice_id = inv) = 1
        and not exists (select 1 from invoice_reopen_sessions q where q.invoice_id = inv and q.applied_at is null),
      'K1 THq (475 in): ' || o::text);
  else
  perform pg_temp.t474_check(o->>'error' like 'pay: Therapy session reopening changed; reload its original evidence%'
      and (o->>'dlgs')::int = 3
      and (select count(*) from invoice_reopen_sessions q where q.invoice_id = inv and q.applied_at is null) = 2
      and (select count(distinct q.session_id) from invoice_reopen_sessions q where q.invoice_id = inv and q.applied_at is null) = 1,
    'K1 THq: look at NOT COVERED 1 again: ' || o::text);
  end if;
  -- K2 (NOT COVERED 2): S$40 paid of the S$100 package, S1 paid from it,
  -- cancelled: the dialog says S$0.00 to reinstate after settlement and S$60
  -- to pay; the Reopen itself gives A S$20 at once (what S$40 buys less the
  -- S$20 spent); paid, A S$80.
  perform pg_temp.t474_run('K', 'PT0', 'sale A cp 40; spend A; cancel; reopen; pay', 1, 4);
  inv := pg_temp.t474_id('K/PT0/inv');
  if pg_temp.t474_478_in() then
    -- 478 (the Owner, 27 Oct 2026, answering NOT COVERED 2): fixed where 478
    -- is in: the dialog shows the S$20 the Reopen gives at once as its own
    -- figure ("Credit released at once on reopening"), beside S$0.00 to
    -- reinstate after settlement, and its explanation says when each comes;
    -- and (answer E, NOT COVERED 3) the S$60 the settling payment gives, and
    -- A, the invoice's customer, as the one who receives it all.
    perform pg_temp.t474_check((select shown from t474_dlg where pre = 'K/PT0' and n = 4) = 0
        and (select required from t474_dlg where pre = 'K/PT0' and n = 4) = 60
        and (select (preview->>'credit_released_on_reopen')::numeric from t474_dlg where pre = 'K/PT0' and n = 4) = 20
        and (select (preview->>'credit_from_settling_payment')::numeric from t474_dlg where pre = 'K/PT0' and n = 4) = 60
        and (select jsonb_array_length(preview->'credit_receivers') from t474_dlg where pre = 'K/PT0' and n = 4) = 1
        and (select (preview->'credit_receivers'->0->>'customer_id')::uuid from t474_dlg where pre = 'K/PT0' and n = 4) = pg_temp.t474_id('K/PT0/A')
        and (select (preview->'credit_receivers'->0->>'invoice_customer')::boolean from t474_dlg where pre = 'K/PT0' and n = 4)
        and (select preview->>'explanation' from t474_dlg where pre = 'K/PT0' and n = 4)
            = 'Existing refunds remain recorded. Only net unrefunded payments settle the reopened invoice. Package or bundle credit the net payments already pay for is released at once when the invoice is reopened. Previously revoked credit is reinstated once the reopened invoice is fully settled.'
        and (select status::text from invoices where id = inv) = 'partially_paid'
        and (select coalesce(sum(remaining_amount), 0) from customer_credit_lots where customer_id = pg_temp.t474_id('K/PT0/A')) = 20,
      'K2 PT0 (478 in): ' || (select preview::text from t474_dlg where pre = 'K/PT0' and n = 4));
  else
  perform pg_temp.t474_check((select shown from t474_dlg where pre = 'K/PT0' and n = 4) = 0
      and (select required from t474_dlg where pre = 'K/PT0' and n = 4) = 60
      and (select preview->>'explanation' from t474_dlg where pre = 'K/PT0' and n = 4)
          = 'Existing refunds remain recorded. Only net unrefunded payments settle the reopened invoice. Previously revoked credit is reinstated once the reopened invoice is fully settled.'
      and (select status::text from invoices where id = inv) = 'partially_paid'
      and (select coalesce(sum(remaining_amount), 0) from customer_credit_lots where customer_id = pg_temp.t474_id('K/PT0/A')) = 20,
    'K2 PT0: look at NOT COVERED 2 again');
  end if;
  o := pg_temp.t474_run('K', 'PT0', 'sale A cp 40; spend A; cancel; reopen; pay', 5);
  perform pg_temp.t474_check(o->'holds' @> '{"A":"80.00"}' and o->>'status' = 'paid' and (o->>'gave')::numeric = 0,
    'K2 PT0: paid ' || o::text);
  raise notice 'KNOWN K: (474''s NOT COVERED) (1) a session queued by two reopenings: %',
    case when pg_temp.t474_475_in() then 'fixed by 475 (THq: queued once, the dialog''s 3 sessions reinstated once, paid)'
         else 'the payment refused, "Therapy session reopening changed" (THq: the dialog says 3 sessions)' end;
  raise notice 'KNOWN K: (474''s NOT COVERED) (2) paid in part, the Reopen itself releases S$20 at once: %',
    case when pg_temp.t474_478_in() then 'fixed by 478 (PT0: "Credit released at once on reopening: S$20.00" beside S$0.00 after settlement, S$60 from the settling payment, A its receiver; S$80 once paid)'
         else 'the dialog''s credit to reinstate after settlement S$0.00 (PT0; S$80 once paid)' end;
end $$;

rollback;
