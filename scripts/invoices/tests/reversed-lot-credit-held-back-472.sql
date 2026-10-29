-- 472: credit a refunded or corrected sale gives back on a lot an Owner
-- reversed (reverse_credit_lot: 'reversed', locked, its 'reversal' ledger
-- row), which the refund or correction opens again ('active', still locked),
-- is held back while its package is cancelled, refunded or waiting for its
-- reopening's payment, and follows whoever holds the benefits while it is
-- paid, as 471 does for any other lot; and credit given back on a lot
-- behind a lot the records name that is closed at S$0 follows too (471's NOT
-- COVERED 10; the Owner, 26 Oct 2026: "fix the leftover gaps too").
-- supabase/472_reversed_lot_credit_held_back.sql (after 462, 463, 470 and 471).
--
-- Every step goes through the app's own calls (471's suite harness, its
-- steps and readings, renamed): the invoice form (create_invoice_with_details)
-- and the Pay dialog (record_invoice_settlement), Record Payment, Cancel,
-- the Finance panel's refund by line and "Record refund paid"
-- (refund_invoice_recorded), its Correct payment (correct_invoice_payment),
-- Reopen, Move (transfer_invoice_unused_benefit), the guided Cancel, the
-- invoice form's customer change (correct_invoice, 'transfer'); an Owner's
-- reversal is reverse_credit_lot called as an active Owner (no page calls
-- it: a stand-in for a direct call); a special document's wallet payment is
-- 462's stand-in, its refund the real refund_special_credit; 328's repair of
-- a released lot is a stand-in made with its own statements (327's lots,
-- which the real repair reads, can no longer be made: released-credit-paths'
-- shape, a lot that keeps the package as its source). Each app call is
-- followed by what its commit does (462's trigger is deferred; SET
-- CONSTRAINTS ... IMMEDIATE, then DEFERRED).
--
-- The cases (A the buyer, B a later customer after a 'transfer' change, F a
-- friend an Owner moved the package's remaining credit to; cp the S$100
-- Credit Package; S1, S2 S$20 sessions paid from it, svc5 S$5):
--   PX, PXs    paid in full, both sessions spent, the S$60 left reversed by
--              an Owner, cancelled, S1 refunded (A tries to spend it).
--   PXc        the same with S2's wallet payment corrected to cash instead.
--   PXw        S1 refunded, refunded by line, reopened (it waits), S2
--              refunded while it waits (A tries to spend it).
--   PXx        refunded by line in full with an Owner's override after S1's
--              refund, then S2 refunded (held back, owed to nobody).
--   PXpc       S1 refunded while paid, cancelled, S2 refunded; PXrr the S$20
--              S1 gave back reversed again before the Cancel.
--   S8g, S8gb, S8gs  paid in part, the released lot's S$15 reversed,
--              cancelled, reopened and paid, a guided Cancel (S$0 owed
--              back), S1 refunded (then refunded by line; A tries to spend).
--   S2g, S2gb  the released lot a Cancel closed, opened by S1's refund while
--              paid, then reversed, a guided Cancel, S2 refunded.
--   O1o        the original lot of 471's O1 (an Owner reversed it), its
--              session refunded while cancelled (471 held back only its copy).
--   RV1, RV1b, RV1r, RV1p  cancelled, a 'transfer' change to B, reopened
--              (the reopening gives B a lot replacing A's), an Owner reverses
--              B's S$80 (the lot the records name, closed at S$0), cancelled
--              again (RV1p: still paid), S1, paid from A's lot behind it,
--              refunded (then refunded by line; reopened and paid).
--   PXh, PXhc  an Owner reversed A's lot, cancelled, a 'transfer' change to
--              B, reopened and paid (then cancelled again), S1 refunded.
--   Controls (the same with and without 472): PXb (the plain refund by line
--   takes it back), PXp, PXr, PXra, PXwp, PXrp (paid: A keeps what the
--   session gave back; reopened and paid; cancelled again; a reopening
--   waiting then paid; reversed twice while paid), PXg (the guided Cancel
--   refused once all is used or reversed), MV1, MV1b, MV1p (the friend's
--   moved lot reversed: the package's own lot is not), 471's O1, PTsp, PC
--   and G2.
--   Known (472's NOT COVERED, the same with and without 472): PTsx, PTsxs,
--   PTsxp a special document's refund after the reversal puts credit back
--   on the closed lot without opening it (no one can spend it); R328,
--   R328s, R328p, R328c, R328cc credit given back on a lot 328's repair replaced
--   (the stand-in keeps the package's source; 327's lots could never be
--   spent from) stays where it went.
-- In every case 462's invariants (471's reading of them) and Cancel (tried,
-- undone) taking all of the invoice's credit back from whoever holds it,
-- but where a known case says what it leaves (R328p, R328c, R328cc).
-- Where 473 is in too (-v nomig=1; 471's NOT COVERED 9: a 'transfer' change
-- of a partly spent package paid in part is refused as "Partly spent", as
-- for the package paid in full), R328c's change is refused, so it ends
-- there (A S$80); R328cc makes the same change while the package is
-- cancelled (473 allows it, as for a package paid in full) and ends as
-- R328c did. Every other case ends as with 472 alone (473's suite,
-- part-paid-package-change-partly-spent-473, checks it).
-- Where 477 is in too (-v nomig=1; 472's NOT COVERED 1, 2 and 4, the Owner,
-- 27 Oct 2026): the known cases end as 477 settles them: PTsx and PTsxs
-- held back (A S$0, S$20 held back), PTsxp A spends it; R328 and R328s held
-- back (S$100 held back), R328p A S$100 and Cancel takes it all, R328cc B
-- S$100 (R328c as 473 leaves it); K1, K2 and K4 check that, and P6 lets the
-- R328 cases reissue (477 reads 328's link as a reissue's). Every other case
-- ends as with 472 alone (477's suite, special-refund-move-repaired-lot-477,
-- checks it).
--
--   S. Where it starts: 462, 463, 470 and 471 in, the triggers on invoices
--      as read; 472 in (nomig) or not, the forwarder at 471's AFTER.
--   R. Without 472 (skipped with -v nomig=1), undone: each 'fixed' case ends
--      otherwise (the fault reproduced: PX A S$20 of a cancelled package;
--      S8gb refused, "That is more than the S$0.00 still owed back"; RV1p A
--      S$20 of B's package; ...); each control and known case as expected.
--   Q. The read-only query in 472's header (the same text), on states made
--      for it and the R states: what it lists, by reason (1 to 5).
--   9. Refusals, each changing nothing (471's set, and a new writer of
--      328's repair row; a new pin, credit_lot_line_allowed); the same grants
--      in another order do not stop it.
--   M. Begun before 472 (cancelled, waiting, paid), finished after it; and
--      credit given back before 472: left as it is, then held back, or moved,
--      with the next refund of a sale paid from that chain.
--  10. 472 installed twice: as tested, the second run changing nothing,
--      nothing added, the grants as before.
--   A. Each case after 472: who holds what, the money, the invariants,
--      Cancel; the controls and the known cases exactly as before.
--   P. Probes: held back in place on the lot an Owner reversed (the reversal
--      row as it was, the Audit Log, the statement); the amount owed back
--      by its money; the queue while a reopening waits; B's new lot
--      replacing the closed lot; nothing more for the controls.
--   K. KNOWN (472's NOT COVERED), checked as they are: a lot 328's repair
--      replaced passed over (the stand-in), and 327's source spends nothing
--      (1); credit on a closed lot (2); credit given back before 472 (3); a
--      Move of credit on such a lot refused (4).
--
-- Run on a copy of production as it is (471 in, 26 Oct 2026: fd61e1a1, 1387
-- functions):
--   psql -X -v ON_ERROR_STOP=1 -f scripts/invoices/tests/reversed-lot-credit-held-back-472.sql
-- It installs 472 itself (twice) inside its transaction. Where 472 is in
-- already, add -v nomig=1 (S checks it as tested; R, Q, 9 and M are skipped;
-- every case after 472 is still checked). Section 9 lets the install fail on
-- purpose (psql prints its ERROR); the suite then checks that message.
-- Disposable database only; everything is rolled back. Every name, code and
-- amount is invented (@example.com); the phones are numbers kept for fiction
-- (ACMA, +61491570000 to +61491570999).
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '10s';
set local statement_timeout = '900s';

-- ── Set-up and the app's calls (462's, 470's and 471's suite harness, for 472) ───────
create temp table t472(k text primary key, id uuid);
create temp table t472_res(phase text, k text, v jsonb, primary key (phase, k));
create temp sequence t472_phone;
create function pg_temp.t472_id(p_k text) returns uuid language sql as $f$ select id from t472 where k = p_k $f$;
create function pg_temp.t472_put(p_k text, p_id uuid) returns uuid language sql as $f$
  insert into t472 values (p_k, p_id) on conflict (k) do update set id = excluded.id returning id $f$;
create function pg_temp.t472_check(p_ok boolean, p_label text) returns void language plpgsql as $f$
begin
  if not coalesce(p_ok, false) then raise exception 'FAIL %', p_label; end if;
end $f$;
create function pg_temp.t472_fingerprint() returns text language sql as $f$
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.oid::regprocedure::text)) || ' ' || count(*)
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prokind in ('f', 'p') $f$;
create function pg_temp.t472_463_in() returns boolean language sql as $f$
  select to_regprocedure('public.invoice_benefit_moved_to_other(uuid)') is not null $f$;
create function pg_temp.t472_462_in() returns boolean language sql as $f$
  select to_regprocedure('public.credit_given_back_follows(uuid)') is not null
     and exists (select 1 from pg_trigger where tgname = 'credit_given_back_follows'
                  and tgrelid = 'public.customer_credit_ledger'::regclass) $f$;
-- 471 is in: the forwarder is 471's or keeps its text (472's does).
create function pg_temp.t472_471_in() returns boolean language sql as $f$
  select to_regprocedure('public.credit_given_back_follows(uuid)') is not null
     and position('-- 471 (the Owner, 26 Oct 2026' in pg_get_functiondef('public.credit_given_back_follows(uuid)'::regprocedure)) > 0 $f$;
-- 472 is in: the forwarder is 472's (its text says so; S checks its md5).
create function pg_temp.t472_in() returns boolean language sql as $f$
  select to_regprocedure('public.credit_given_back_follows(uuid)') is not null
     and position('-- 472 (the Owner, 26 Oct 2026' in pg_get_functiondef('public.credit_given_back_follows(uuid)'::regprocedure)) > 0 $f$;
-- 473 is in too: the list of what a customer change can move is 473's (a
-- 'transfer' change of a partly spent package paid in part is refused).
create function pg_temp.t472_473_in() returns boolean language sql as $f$
  select position('-- 473 (the Owner, 26 Oct 2026' in pg_get_functiondef('public.invoice_transferable_benefits(uuid)'::regprocedure)) > 0 $f$;
-- 477 is in too: the forwarder is 477's (its text says so; it keeps 472's),
-- and so are the special document's refund and the Move.
create function pg_temp.t472_477_in() returns boolean language sql as $f$
  select position('-- 477 (the Owner, 27 Oct 2026' in pg_get_functiondef('public.credit_given_back_follows(uuid)'::regprocedure)) > 0
     and position('-- 477 (the Owner, 27 Oct 2026' in pg_get_functiondef('public.refund_special_credit(text,uuid)'::regprocedure)) > 0
     and position('-- 477 (the Owner, 27 Oct 2026' in pg_get_functiondef('public.transfer_invoice_unused_benefit(uuid,uuid,uuid,text,uuid)'::regprocedure)) > 0 $f$;
-- 470 is in (its text is in 471's and 472's too).
create function pg_temp.t472_470_in() returns boolean language sql as $f$
  select to_regprocedure('public.credit_given_back_follows(uuid)') is not null
     and position('-- 470 (the Owner, 24 Oct 2026' in pg_get_functiondef('public.credit_given_back_follows(uuid)'::regprocedure)) > 0 $f$;
-- What a commit does at the end of each app call (each is its own
-- transaction in the app): 462's deferred trigger on the ledger runs (471
-- adds no trigger: its change is in the function that trigger runs). Here
-- the suite is one transaction, so the trigger's queued rows are run at this
-- point. (Not where each step really commits: t472.autocommit 'on', for
-- running the same cases one call per transaction on a disposable copy.)
create function pg_temp.t472_commit() returns void language plpgsql as $f$
begin
  if coalesce(current_setting('t472.autocommit', true), '') = 'on' then return; end if;
  if pg_temp.t472_462_in() then
    execute 'set constraints public.credit_given_back_follows immediate';
    execute 'set constraints public.credit_given_back_follows deferred';
  end if;
end $f$;

do $$
declare own uuid := gen_random_uuid(); st uuid; st2 uuid; pm uuid; v uuid; cp uuid; cpb uuid; pbv uuid; svc uuid; svc5 uuid;
begin
  insert into auth.users(id, email) values (own, 't472-owner@example.com');
  insert into profiles(id, full_name, email, role, is_active) values (own, 'T472 Owner', 't472-owner@example.com', 'owner', true);
  perform set_config('request.jwt.claims', json_build_object('sub', own, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', own::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  insert into stores(name, code, country_code) values ('T472 Store', 'T472S1', 'SG') returning id into st;
  insert into stores(name, code, country_code) values ('T472 Other Store', 'T472S2', 'SG') returning id into st2;
  insert into payment_methods(name, is_active) values ('T472 Cash', true) returning id into pm;
  insert into vouchers(name, code, voucher_kind, qty_type, selling_price, is_active)
    values ('T472 Plain 30', 'T472-P30', 'normal', 'unlimited', 30, true) returning id into v;
  insert into voucher_store_prices(voucher_id, store_id, selling_price, available_at_store) values (v, st, 30, true), (v, st2, 30, true);
  insert into credit_packages(name, customer_price, paid_credit_amount, bonus_enabled, allow_product, allow_therapy)
    values ('T472 S$100', 100, 100, false, true, true) returning id into cp;
  insert into credit_package_stores(package_id, store_id) values (cp, st), (cp, st2);
  insert into credit_packages(name, customer_price, paid_credit_amount, bonus_enabled, bonus_value, allow_product, allow_therapy, grants_reward)
    values ('T472 S$100 + S$10', 100, 100, true, 10, true, true, false) returning id into cpb;
  insert into credit_package_stores(package_id, store_id) values (cpb, st), (cpb, st2);
  insert into premium_bundles(name, customer_payment_amount, paid_credit_amount, bonus_credit_amount, free_voucher_qty, grants_reward)
    values ('T472 Bundle S$140 + 2 vouchers', 140, 100, 40, 2, true) returning id into pbv;
  insert into premium_bundle_stores(bundle_id, store_id) values (pbv, st), (pbv, st2);
  insert into premium_bundle_vouchers(bundle_id, voucher_id) values (pbv, v);
  svc := (upsert_therapy_service(null, 'T472-SESSION', 'T472 Session', 20, 30, 'per_hours', 1, 5, null, true, null) ->> 'id')::uuid;
  perform set_therapy_service_store(svc, st, true, null);
  svc5 := (upsert_therapy_service(null, 'T472-SHORT', 'T472 Short session', 5, 15, 'per_hours', 1, 5, null, true, null) ->> 'id')::uuid;
  perform set_therapy_service_store(svc5, st, true, null);
  insert into t472 values ('own', own), ('store', st), ('store2', st2), ('pm', pm), ('v', v), ('cp', cp), ('cpb', cpb), ('pbv', pbv),
    ('svc', svc), ('svc5', svc5),
    ('wallet', (select id from payment_methods where name = 'Wallet — Credit Package Paid' and is_wallet_credit and deleted_at is null)),
    ('bwallet', (select id from payment_methods where name = 'Wallet — Premium Bundle Paid' and is_wallet_credit and deleted_at is null));
  perform pg_temp.t472_check(pg_temp.t472_id('wallet') is not null and pg_temp.t472_id('bwallet') is not null, 'setup: the wallet methods (443) are there');
end $$;

-- A customer of one run of one case: '<phase>/<case>/<role>'.
create function pg_temp.t472_cust(p_k text) returns uuid language plpgsql as $f$
declare c uuid;
begin
  insert into customers(full_name, phone) values ('T472 ' || p_k, '+61491570' || lpad((nextval('t472_phone') % 1000)::text, 3, '0'))
    returning id into c;
  return pg_temp.t472_put(p_k, c);
end $f$;
-- The invoice form with these lines ('cp' / 'cpb' a Credit Package, 'pbv' the
-- Premium Bundle, 'v' a voucher line of p_qty units), with an Owner's manual
-- discount of p_discount (its reason given) where one is given, paid through
-- the Pay dialog: in full, or p_first of it (a part-paid package).
create function pg_temp.t472_sale(p_cust uuid, p_kinds text[], p_first numeric default null, p_qty int default 2,
                                  p_discount numeric default null)
  returns uuid language plpgsql as $f$
declare inv uuid; v_lines jsonb := '[]'; i int;
begin
  for i in 1 .. cardinality(p_kinds) loop
    v_lines := v_lines || jsonb_build_array(case
      when p_kinds[i] = 'v' then jsonb_build_object('kind', 'voucher', 'voucher_id', pg_temp.t472_id('v'), 'quantity', p_qty)
      when p_kinds[i] in ('cp', 'cpb') then jsonb_build_object('kind', 'credit_package', 'credit_package_id', pg_temp.t472_id(p_kinds[i]), 'quantity', 1)
      else jsonb_build_object('kind', 'premium_bundle', 'premium_bundle_id', pg_temp.t472_id('pbv'), 'quantity', 1,
        'voucher_selection', jsonb_build_array(jsonb_build_object('voucher_id', pg_temp.t472_id('v'), 'quantity', 2))) end);
  end loop;
  inv := create_invoice_with_details(pg_temp.t472_id('store'), p_cust, v_lines, jsonb_build_object('business_date', sg_today()::text)
           || case when p_discount is not null
                   then jsonb_build_object('manual_discount', p_discount, 'manual_discount_reason', 'T472 discount') else '{}'::jsonb end);
  perform record_invoice_settlement(inv, jsonb_build_object('receipts', jsonb_build_array(jsonb_build_object(
    'key', 'line-0', 'payment_method_id', pg_temp.t472_id('pm'),
    'amount', coalesce(p_first, (select total_amount from invoices where id = inv)),
    'payment_date', sg_today()::text)), 'arrangements', '[]'::jsonb), gen_random_uuid());
  return inv;
end $f$;
-- Record Payment of what is outstanding (nothing when it is settled).
create function pg_temp.t472_pay(p_inv uuid) returns void language plpgsql as $f$
begin
  if (invoice_financial_position(p_inv)->>'outstanding')::numeric > 0 then
    perform record_invoice_payment(p_inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.t472_id('pm'),
      'amount', (invoice_financial_position(p_inv)->>'outstanding')::numeric)), gen_random_uuid());
  end if;
end $f$;
-- The receipts that still hold p_amount between them, as the Finance panel
-- splits a refund across them.
create function pg_temp.t472_sources(p_inv uuid, p_amount numeric) returns jsonb language plpgsql as $f$
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
create function pg_temp.t472_line(p_inv uuid, p_n int default 1) returns uuid language sql as $f$
  select id from invoice_items where invoice_id = p_inv order by id offset p_n - 1 limit 1 $f$;
-- The Finance panel's refund by line of line p_n: p_amount off its Paid
-- benefit (the one an Owner did not move, or with p_holder the one p_holder
-- holds), or every unused benefit it still holds (p_amount null).
create function pg_temp.t472_back(p_inv uuid, p_n int, p_amount numeric default null, p_holder uuid default null)
  returns void language plpgsql as $f$
declare opts jsonb; ben jsonb; tot numeric; item uuid := pg_temp.t472_line(p_inv, p_n);
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
  if ben is null then raise exception 'T472: nothing to refund on that line'; end if;
  perform refund_invoice_recorded(p_inv, jsonb_build_array(jsonb_build_object('invoice_item_id', item, 'amount', tot, 'benefits', ben)),
    pg_temp.t472_sources(p_inv, tot), '[]'::jsonb, 'T472 by line', gen_random_uuid());
end $f$;
-- The invoice form's customer change, its lines as they are (and the store,
-- when given), with 'transfer' or 'keep'. The change's Audit Log row is
-- dated now, as a later call's is (the suite is one transaction).
create function pg_temp.t472_lines(p_inv uuid) returns jsonb language sql as $f$
  select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('invoice_item_id', it.id, 'kind', it.line_kind,
           'credit_package_id', it.credit_package_id, 'premium_bundle_id', it.premium_bundle_id, 'voucher_id', it.voucher_id,
           'quantity', it.quantity, 'unit_price', it.unit_price, 'voucher_selection', it.bundle_voucher_selection)) order by it.id)
    from invoice_items it where it.invoice_id = p_inv $f$;
create function pg_temp.t472_change(p_inv uuid, p_cust uuid, p_action text default 'transfer', p_store text default null)
  returns void language plpgsql as $f$
begin
  perform correct_invoice(p_inv, pg_temp.t472_lines(p_inv),
    jsonb_build_object('expected_edit_count', (select edit_count from invoices where id = p_inv),
      'customer_id', p_cust, 'store_id', coalesce(pg_temp.t472_id(p_store), (select store_id from invoices where id = p_inv)),
      'benefit_action', p_action),
    'T472 wrong customer', gen_random_uuid());
  update audit_logs set created_at = clock_timestamp()
   where record_id = p_inv and action = 'invoice_benefits_followed_reassignment' and new_data->>'to_customer' = p_cust::text
     and created_at = now();
end $f$;
create function pg_temp.t472_merge(p_keep uuid, p_dup uuid) returns void language plpgsql as $f$
begin
  perform merge_customer_records(p_keep, p_dup, 'T472 the same person', gen_random_uuid());
end $f$;
-- The Finance panel's Move of line p_n's unused benefit (its Paid credit,
-- or its Bonus with p_kind 'bonus', or a voucher) to p_to, at p_store.
create function pg_temp.t472_move(p_inv uuid, p_n int, p_to uuid, p_kind text default 'paid', p_store text default null)
  returns void language plpgsql as $f$
declare b uuid;
begin
  select bv.id into b from invoice_benefit_values bv
    left join customer_reward_vouchers v on v.id = bv.reward_voucher_id
    left join customer_credit_lots l on l.id = bv.lot_id
   where bv.invoice_item_id = pg_temp.t472_line(p_inv, p_n)
     and (v.status = 'held' and p_kind = 'voucher' or l.remaining_amount > 0 and l.category = p_kind)
   order by bv.granted_value desc limit 1;
  if b is null then raise exception 'T472: nothing to move on that line'; end if;
  perform transfer_invoice_unused_benefit(b, p_to, coalesce(pg_temp.t472_id(p_store), (select store_id from invoices where id = p_inv)),
    'T472 move', gen_random_uuid());
end $f$;
-- The invoice form: p_n sessions of S$20 (or S$5 with p_svc 'svc5') for
-- p_cust, paid with the wallet (Credit Package Paid; Premium Bundle Paid with
-- p_wallet 'bwallet') through Record Payment.
create function pg_temp.t472_spend(p_cust uuid, p_n int default 1, p_svc text default 'svc', p_wallet text default 'wallet')
  returns uuid language plpgsql as $f$
declare inv uuid; v_lines jsonb := '[]'; i int;
begin
  for i in 1 .. p_n loop
    v_lines := v_lines || jsonb_build_array(jsonb_build_object('kind', 'therapy', 'therapy_service_id', pg_temp.t472_id(p_svc), 'quantity', 1));
  end loop;
  inv := create_invoice_with_details(pg_temp.t472_id('store'), p_cust, v_lines, jsonb_build_object('business_date', sg_today()::text));
  perform record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.t472_id(p_wallet),
    'amount', (select total_amount from invoices where id = inv))), gen_random_uuid());
  if (select status::text from invoices where id = inv) <> 'paid' then raise exception 'T472: the session paid from credit is not paid'; end if;
  return inv;
end $f$;
-- The session cancelled and "Record refund paid": what its payment took goes
-- back to the lots it came from (refund_invoice_recorded's wallet refund).
create function pg_temp.t472_unspend(p_inv uuid) returns void language plpgsql as $f$
declare due numeric;
begin
  perform cancel_invoice_recorded(p_inv, 'T472 cancel session', gen_random_uuid());
  due := (invoice_financial_position(p_inv)->>'refund_due')::numeric;
  if due is null or due <= 0 then due := (invoice_action_plan(p_inv, 'cancel', '[]')->>'refund_due')::numeric; end if;
  perform refund_invoice_recorded(p_inv, jsonb_build_array(jsonb_build_object('amount', due)), pg_temp.t472_sources(p_inv, due), '[]'::jsonb,
    'T472 refund paid', gen_random_uuid());
end $f$;
-- The Finance panel's Correct payment on a session's wallet payment: the
-- date only ('date'), a smaller amount ('amount', S$5 less), or another
-- method ('cash').
create function pg_temp.t472_fix(p_inv uuid, p_how text) returns void language plpgsql as $f$
declare p invoice_payments%rowtype;
begin
  select * into p from invoice_payments where invoice_id = p_inv and entry_kind in ('receipt', 'correction_replacement')
     and not exists (select 1 from invoice_payments q where q.corrects_payment_id = invoice_payments.id and q.entry_kind = 'correction_reversal')
   order by created_at desc, id desc limit 1;
  perform correct_invoice_payment(p.id,
    case p_how when 'amount' then p.amount - 5 else p.amount end,
    sg_today() - 1,
    case p_how when 'cash' then pg_temp.t472_id('pm') else p.payment_method_id end,
    'T472 correct payment ' || p_how, gen_random_uuid());
end $f$;
-- A special document's wallet payment as pay_special_with_credit records it
-- (a stand-in: no page calls that function, and no credit category allows a
-- special document today, purchase_category): p_amount off the customer's
-- largest lot ('use', its allocations), so refund_special_credit, the real
-- one, gives it back.
create function pg_temp.t472_special(p_cust uuid, p_kind text, p_doc uuid, p_amount numeric) returns void language plpgsql as $f$
declare l customer_credit_lots%rowtype; e uuid;
begin
  select * into l from customer_credit_lots where customer_id = p_cust and status = 'active' and remaining_amount >= p_amount
   order by remaining_amount desc, id limit 1 for update;
  insert into customer_credit_ledger(wallet_id, customer_id, entry_type, category, amount, lot_id, source_type, source_record_id, store_id, note, created_by)
  values (l.wallet_id, p_cust, 'use', l.category, p_amount, l.id, p_kind, p_doc, l.store_id, 'T472 special', auth.uid()) returning id into e;
  update customer_credit_lots set remaining_amount = remaining_amount - p_amount, updated_at = now() where id = l.id;
  insert into customer_credit_allocations(ledger_entry_id, lot_id, customer_id, amount) values (e, l.id, p_cust, p_amount);
  insert into special_credit_allocations(doc_kind, doc_id, customer_id, lot_id, category, amount, created_by)
  values (p_kind, p_doc, p_cust, l.id, l.category, p_amount, auth.uid());
end $f$;
-- The guided Refund in full / Cancel as an Owner confirms it, with a reason
-- for every override the plan asks for, the money recorded as paid back (or,
-- with p_record false, not: "Record refund paid" left unticked).
create function pg_temp.t472_guided(p_inv uuid, p_action text, p_record boolean default true) returns void language plpgsql as $f$
declare plan jsonb; req jsonb; ov jsonb;
begin
  plan := invoice_action_plan(p_inv, p_action, '[]');
  req := request_invoice_action_v2(p_inv, p_action, '[]', 'T472 ' || p_action, null, gen_random_uuid());
  select coalesce(jsonb_agg(case when coalesce((o->>'amount_required')::boolean, false)
           then jsonb_build_object('code', o->>'code', 'reason', 'T472 override', 'amount', (o->>'default_amount')::numeric)
           else jsonb_build_object('code', o->>'code', 'reason', 'T472 override') end), '[]'::jsonb)
    into ov from jsonb_array_elements(coalesce(plan->'overrides_required', '[]')) o;
  perform resolve_invoice_action_v2((req->>'request_id')::uuid, true, 'T472 ' || p_action, plan->>'plan_hash', ov, null, p_record);
end $f$;


-- ── What the records say ────────────────────────────────────────────────────
-- The lots an invoice's records name: its benefit values, its sale's lots, a
-- split's issued lot, released credit (credit_package_progress_lots).
create function pg_temp.t472_named(p_inv uuid) returns setof uuid language sql as $f$
  select lot_id from invoice_benefit_values where invoice_id = p_inv and lot_id is not null
  union select x from credit_package_sales s, unnest(array[s.credit_lot_id, s.bonus_credit_lot_id]) x where s.invoice_id = p_inv and x is not null
  union select x from premium_bundle_sales s, unnest(array[s.paid_credit_lot_id, s.bonus_credit_lot_id]) x where s.invoice_id = p_inv and x is not null
  union select issued_lot_id from invoice_credit_splits where invoice_id = p_inv and issued_lot_id is not null
  union select lot_id from credit_package_progress_lots where invoice_id = p_inv $f$;
-- The invoice's lot family (the critic's 6): every lot its records name and
-- each Move's two lots (from the Move's ledger rows), the lots each replaced
-- and every lot reissued from any of them.
create function pg_temp.t472_family(p_inv uuid) returns setof uuid language sql as $f$
  with recursive seed as (
    select x as id from pg_temp.t472_named(p_inv) x
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
create function pg_temp.t472_behind(p_inv uuid) returns setof uuid language sql as $f$
  with recursive c(id, n) as (
    select lot_id, 0 from invoice_benefit_values where invoice_id = p_inv and lot_id is not null
    union select p.id, c.n + 1 from c join customer_credit_lots l on l.id = c.id
            join customer_credit_lots p on p.id = l.reassigned_from_lot_id
             and (p.source_type, p.source_record_id) is not distinct from (l.source_type, l.source_record_id)
           where c.n < 12)
  select distinct id from c $f$;
-- How many lots back a lot's chain goes (reassigned_from_lot_id).
create function pg_temp.t472_depth(p_lot uuid) returns int language sql as $f$
  with recursive c(id, n) as (select p_lot, 0 union all
    select l.reassigned_from_lot_id, c.n + 1 from c join customer_credit_lots l on l.id = c.id
     where l.reassigned_from_lot_id is not null and c.n < 40)
  select max(n) from c $f$;
-- A lot's balance by its ledger rows: credit added (grants, increases,
-- credit returned: the 'reverse' rows that put credit back, as the
-- statement reads them, and 'rental_late_fee'), less credit taken (uses,
-- decreases, real reversals).
create function pg_temp.t472_ledger_balance(p_lot uuid) returns numeric language sql as $f$
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
create function pg_temp.t472_invariants(p_inv uuid) returns text language plpgsql as $f$
declare probs text := ''; l record; root record; v uuid; st text := (select status::text from invoices where id = p_inv);
begin
  for l in select cl.* from customer_credit_lots cl where cl.id in (select pg_temp.t472_family(p_inv)) loop
    if l.remaining_amount > 0 and l.id not in (select pg_temp.t472_named(p_inv)) then
      probs := probs || format(' S$%s on a lot no record names (%s);', l.remaining_amount, (select full_name from customers where id = l.customer_id)); end if;
    if l.id not in (select pg_temp.t472_named(p_inv)) and l.id not in (select pg_temp.t472_behind(p_inv))
       and (exists (select 1 from invoice_line_credit_allocations a where a.lot_id = l.id and a.amount > coalesce(a.reversed_amount, 0))
            or exists (select 1 from special_credit_allocations s where s.lot_id = l.id and s.amount > coalesce(s.reversed_amount, 0))) then
      probs := probs || ' a sale paid from a lot no record names can still be refunded (its credit would stay there);'; end if;
    if pg_temp.t472_ledger_balance(l.id) <> l.remaining_amount then
      probs := probs || format(' lot holds %s, its ledger %s;', l.remaining_amount, pg_temp.t472_ledger_balance(l.id)); end if;
    if pg_temp.t472_depth(l.id) > 12 then probs := probs || format(' chain %s lots deep;', pg_temp.t472_depth(l.id)); end if;
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
  if st = 'refunded' and (select coalesce(sum(remaining_amount), 0) from customer_credit_lots where id in (select pg_temp.t472_family(p_inv))) > 0 then
    probs := probs || format(' refunded, but S$%s of its credit is still held;',
      (select sum(remaining_amount) from customer_credit_lots where id in (select pg_temp.t472_family(p_inv)))); end if;
  return probs;
end $f$;
-- Credit left on the invoice's family once Cancel has run, the Cancel undone
-- (0 when Cancel takes it all back from whoever holds it); null when the
-- invoice cannot be cancelled now, -1 when Cancel is refused.
create function pg_temp.t472_cancel_left(p_inv uuid) returns numeric language plpgsql as $f$
declare v numeric;
begin
  if (select status::text from invoices where id = p_inv) not in ('paid', 'partially_paid', 'unpaid') then return null; end if;
  begin
    perform cancel_invoice_recorded(p_inv, 'T472 probe', gen_random_uuid());
    perform pg_temp.t472_commit();
    v := (select coalesce(sum(remaining_amount), 0) from customer_credit_lots where id in (select pg_temp.t472_family(p_inv)));
    raise exception using errcode = 'P0461', message = v::text;
  exception when sqlstate 'P0461' then return sqlerrm::numeric;
            when others then return -1;
  end;
end $f$;
create function pg_temp.t472_codes(p_inv uuid, p_action text) returns text language plpgsql as $f$
begin
  return (select coalesce(string_agg(o->>'code', ',' order by o->>'code'), '-')
            from jsonb_array_elements(coalesce(invoice_action_plan(p_inv, p_action, '[]')->'overrides_required', '[]')) o);
exception when others then return 'ERR';
end $f$;
create function pg_temp.t472_due(p_inv uuid, p_action text) returns numeric language plpgsql as $f$
begin
  return (invoice_action_plan(p_inv, p_action, '[]')->>case when p_action = 'cancel' then 'refund_due' else 'refund_amount' end)::numeric;
exception when others then return null;
end $f$;
-- The invoice's money: what is owed back (cancel_refund_owed), the Finance
-- panel's refund due, net received and kept for what was used, what a
-- refund by line can still pay back (the refund options' max_refund, every
-- benefit) and Cancel's refund due (the plan's).
create function pg_temp.t472_money(p_inv uuid) returns jsonb language sql as $f$
  select jsonb_build_object('owed', i.cancel_refund_owed,
    'due', (invoice_financial_position(i.id)->>'refund_due')::numeric,
    'net', (invoice_financial_position(i.id)->>'net_received')::numeric,
    'kept', (invoice_financial_position(i.id)->>'kept_for_used')::numeric,
    'by_line', (select coalesce(sum((b->>'max_refund')::numeric), 0)
                  from jsonb_array_elements(invoice_refund_options_before_sessions(i.id)->'benefits') b),
    'plan_due', pg_temp.t472_due(i.id, 'cancel'))
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
create function pg_temp.t472_role(p_pre text, p_r text) returns uuid language plpgsql as $f$
begin
  return coalesce(pg_temp.t472_id(p_pre || '/' || p_r), pg_temp.t472_cust(p_pre || '/' || p_r));
end $f$;
-- One step of a case (one app call, then what its commit does). Null, or
-- the step and the refusal; a refused step changes nothing.
create function pg_temp.t472_step(p_pre text, p_st text) returns text language plpgsql as $f$
declare w text[] := regexp_split_to_array(btrim(p_st), '\s+'); inv uuid := pg_temp.t472_id(p_pre || '/inv'); x uuid; i int; n int;
begin
  case w[1]
  when 'sale' then
    perform pg_temp.t472_put(p_pre || '/inv', pg_temp.t472_sale(pg_temp.t472_role(p_pre, w[2]), string_to_array(w[3], ','), w[4]::numeric));
  when 'saled' then
    perform pg_temp.t472_put(p_pre || '/inv', pg_temp.t472_sale(pg_temp.t472_role(p_pre, w[2]), string_to_array(w[3], ','), null, 2, w[4]::numeric));
  when 'sale2' then
    perform pg_temp.t472_put(p_pre || '/inv2', pg_temp.t472_sale(pg_temp.t472_role(p_pre, w[2]), array['cp']));
  when 'pay' then perform pg_temp.t472_pay(inv);
  when 'back' then
    perform pg_temp.t472_back(inv, w[2]::int, case when w[3] = 'all' then null else w[3]::numeric end,
                              case when w[4] is not null then pg_temp.t472_role(p_pre, w[4]) end);
  when 'move' then
    perform pg_temp.t472_move(inv, w[2]::int, pg_temp.t472_role(p_pre, w[3]),
      case when w[4] in ('bonus', 'voucher') then w[4] else 'paid' end,
      case when 'store2' = any (w) then 'store2' end);
  when 'cancel' then perform cancel_invoice_recorded(inv, 'T472 cancel', gen_random_uuid());
  when 'reopen' then perform reopen_invoice(inv, 'T472 reopen', gen_random_uuid());
  when 'wait' then
    perform cancel_invoice_recorded(inv, 'T472 cancel', gen_random_uuid());
    for i in 1 .. (select count(*)::int from invoice_items where invoice_id = inv) loop
      perform pg_temp.t472_back(inv, i);
    end loop;
    perform reopen_invoice(inv, 'T472 reopen', gen_random_uuid());
  when 'refundall' then perform pg_temp.t472_guided(inv, 'refund_full');
  when 'change' then
    perform pg_temp.t472_change(inv, pg_temp.t472_role(p_pre, w[2]), case when 'keep' = any (w) then 'keep' else 'transfer' end,
                                case when 'store2' = any (w) then 'store2' end);
  when 'merge' then perform pg_temp.t472_merge(pg_temp.t472_role(p_pre, w[2]), pg_temp.t472_role(p_pre, w[3]));
  when 'spend' then
    n := (select count(*) from t472 where k ~ ('^' || p_pre || '/S[0-9]+$')) + 1;
    perform pg_temp.t472_put(p_pre || '/S' || n,
      pg_temp.t472_spend(pg_temp.t472_role(p_pre, w[2]), case when w[3] ~ '^[0-9]+$' then w[3]::int else 1 end,
        case when 'svc5' = any (w) then 'svc5' else 'svc' end, case when 'bwallet' = any (w) then 'bwallet' else 'wallet' end));
  when 'unspend' then perform pg_temp.t472_unspend(pg_temp.t472_id(p_pre || '/' || w[2]));
  when 'fix' then perform pg_temp.t472_fix(pg_temp.t472_id(p_pre || '/' || w[2]), w[3]);
  when 'delete' then
    x := pg_temp.t472_role(p_pre, w[2]);
    perform delete_customer(x, (select full_name from customers where id = x), 'T472 delete');
  when 'special' then
    n := (select count(*) from t472 where k ~ ('^' || p_pre || '/D[0-9]+$')) + 1; x := gen_random_uuid();
    perform pg_temp.t472_put(p_pre || '/D' || n, x);
    perform pg_temp.t472_put(p_pre || '/D' || n || '/kind:' || w[3], null);
    perform pg_temp.t472_special(pg_temp.t472_role(p_pre, w[2]), w[3], x, w[4]::numeric);
  when 'unspecial' then
    perform refund_special_credit((select split_part(k, 'kind:', 2) from t472 where k like p_pre || '/' || w[2] || '/kind:%'),
                                  pg_temp.t472_id(p_pre || '/' || w[2]));
  when 'reverse' then
    if w[2] = 'closed' then
      -- the released lot a Cancel's write-off closed, once a refund opened it again
      perform reverse_credit_lot(pg_temp.t472_closed_lot(inv), 'T472 reversal');
    else
      x := pg_temp.t472_role(p_pre, w[2]);
      perform reverse_credit_lot((select id from customer_credit_lots where customer_id = x and remaining_amount > 0
                                   order by remaining_amount desc, id limit 1), 'T472 reversal');
    end if;
  when 'guidedcancel' then perform pg_temp.t472_guided(inv, 'cancel');
  when 'guidedkeep' then perform pg_temp.t472_guided(inv, 'cancel', false);
  when 'backo' then
    x := pg_temp.t472_line(inv, w[2]::int);
    perform refund_invoice_recorded(inv, jsonb_build_array(jsonb_build_object('invoice_item_id', x,
        'amount', invoice_discounted_line_value(x),
        'benefits', jsonb_build_array(jsonb_build_object('benefit_id', pg_temp.t472_own(inv), 'amount', w[3]::numeric)),
        'override', jsonb_build_object('code', 'larger_refund', 'reason', 'T472 larger refund', 'amount', invoice_discounted_line_value(x)))),
      pg_temp.t472_sources(inv, invoice_net_received(inv)), '[]'::jsonb, 'T472 larger refund', gen_random_uuid());
  when 'refundpaid' then
    perform refund_invoice_recorded(inv, jsonb_build_array(jsonb_build_object('amount',
        coalesce(nullif((invoice_financial_position(inv)->>'refund_due')::numeric, 0), (invoice_action_plan(inv, 'cancel', '[]')->>'refund_due')::numeric))),
      pg_temp.t472_sources(inv, coalesce(nullif((invoice_financial_position(inv)->>'refund_due')::numeric, 0), (invoice_action_plan(inv, 'cancel', '[]')->>'refund_due')::numeric)),
      '[]'::jsonb, 'T472 refund paid', gen_random_uuid());
  when 'backx' then
    x := pg_temp.t472_line(inv, w[2]::int);
    perform refund_invoice_recorded(inv, jsonb_build_array(jsonb_build_object('invoice_item_id', x,
        'amount', invoice_discounted_line_value(x) - coalesce((select sum((e->>'amount')::numeric) from invoice_refunds r,
             jsonb_array_elements(coalesce(r.outcome->'lines', '[]')) e where r.invoice_id = inv and e->>'invoice_item_id' = x::text), 0),
        'benefits', (select jsonb_agg(jsonb_build_object('benefit_id', b->>'id', 'amount', (b->>'max_refund')::numeric))
                       from jsonb_array_elements(invoice_refund_options_before_sessions(inv)->'benefits') b
                      where b->>'invoice_item_id' = x::text and (b->>'max_refund')::numeric > 0),
        'override', jsonb_build_object('code', 'larger_refund', 'reason', 'T472 larger refund',
          'amount', invoice_discounted_line_value(x) - coalesce((select sum((e->>'amount')::numeric) from invoice_refunds r,
             jsonb_array_elements(coalesce(r.outcome->'lines', '[]')) e where r.invoice_id = inv and e->>'invoice_item_id' = x::text), 0)))),
      pg_temp.t472_sources(inv, invoice_net_received(inv)), '[]'::jsonb, 'T472 larger refund', gen_random_uuid());
  when 'legacy' then
    update invoices set status = w[2]::invoice_status where id = inv;
  when 'repair' then perform repair_credit_package_progress_lots();
  when 'repair328' then perform pg_temp.t472_repair328(inv);
  else raise exception 'T472: unknown step %', p_st;
  end case;
  perform pg_temp.t472_commit();
  return null;
exception when others then
  return btrim(p_st) || ': ' || sqlerrm;
end $f$;
-- What a case ends with: the invoice's status and money, who holds what
-- (credit, '/n' held vouchers), the plans' codes and refund due (Cancel's
-- refund due; Refund in full's amount), the refusal that stopped it, what is
-- wrong with its credit, and the credit Cancel would leave behind.
create function pg_temp.t472_outcome(p_pre text, p_err text) returns jsonb language sql as $f$
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
              from t472 t where t.k like p_pre || '/%' and split_part(t.k, '/', 4) = ''
                and split_part(t.k, '/', 3) !~ '^(inv|inv2|S[0-9]+|D[0-9]+|err)$'),
    'cancel', pg_temp.t472_codes(i.id, 'cancel'),
    'due', pg_temp.t472_due(i.id, 'cancel'),
    'refund', pg_temp.t472_codes(i.id, 'refund_full'),
    'rdue', pg_temp.t472_due(i.id, 'refund_full'),
    'error', p_err,
    'invariants', pg_temp.t472_invariants(i.id),
    'cancel_left', pg_temp.t472_cancel_left(i.id))
    from (select pg_temp.t472_id(p_pre || '/inv') as id) i $f$;
-- A case's steps p_from to p_to (all by default), stopping at a refusal;
-- with p_to null, its outcome (kept in t472_res under p_phase).
create temp table t472_err(pre text primary key, err text);
create function pg_temp.t472_run(p_phase text, p_case text, p_steps text, p_from int default 1, p_to int default null)
  returns jsonb language plpgsql as $f$
declare v_pre text := p_phase || '/' || p_case; st text[] := string_to_array(p_steps, ';'); i int; v_err text; v_out jsonb;
begin
  v_err := (select e.err from t472_err e where e.pre = v_pre);
  for i in p_from .. least(coalesce(p_to, cardinality(st)), cardinality(st)) loop
    exit when v_err is not null;
    continue when btrim(st[i]) = '';
    v_err := pg_temp.t472_step(v_pre, st[i]);
  end loop;
  insert into t472_err values (v_pre, v_err) on conflict (pre) do update set err = excluded.err;
  if p_to is not null then return null; end if;
  v_out := pg_temp.t472_outcome(v_pre, v_err);
  insert into t472_res values (p_phase, p_case, v_out) on conflict (phase, k) do update set v = excluded.v;
  return v_out;
end $f$;

-- Whether an outcome has what is expected: each key equal ('holds' as a
-- containment of who holds what), a key ending in '~' as a LIKE pattern of
-- that key's text.
create function pg_temp.t472_meets(p_out jsonb, p_exp jsonb) returns boolean language sql as $f$
  select coalesce(bool_and(case
           when e.key like '%~' then coalesce(p_out->>left(e.key, -1), '') like (e.value #>> '{}')
           when e.key = 'holds' then coalesce(p_out->'holds', '{}') @> e.value
           when jsonb_typeof(e.value) = 'number' then coalesce((p_out->>e.key)::numeric = (e.value #>> '{}')::numeric, false)
           else (p_out->e.key) is not distinct from e.value end), true)
    from jsonb_each(p_exp) e $f$;
-- What differs between an outcome and what is expected (for the FAIL line).
create function pg_temp.t472_diff(p_out jsonb, p_exp jsonb) returns text language sql as $f$
  select string_agg(e.key || ': wanted ' || e.value::text || ', got ' || coalesce(p_out->left(e.key, case when e.key like '%~' then -1 else 1000 end), 'null')::text, '; ')
    from jsonb_each(p_exp) e where not pg_temp.t472_meets(p_out, jsonb_build_object(e.key, e.value)) $f$;

-- ── 471's own readings ──────────────────────────────────────────────────────
-- The held-back reason (470's, which 471 writes too), and its rows on a lot.
create function pg_temp.t472_held(p_lot uuid) returns numeric language sql as $f$
  select coalesce(sum(e.amount), 0) from customer_credit_ledger e
   where e.lot_id = p_lot and e.entry_type = 'adjust_decrease' and e.source_type = 'invoice_cancel_benefit'
     and e.reason = 'Held back by the invoice''s cancellation for whoever holds its benefits now' $f$;
-- (B) what is held back on a lot of credit released before full payment
-- (Cancel's write-off's kind of row, 471's reason).
create function pg_temp.t472_held_rel(p_lot uuid) returns numeric language sql as $f$
  select coalesce(sum(e.amount), 0) from customer_credit_ledger e
   where e.lot_id = p_lot and e.entry_type = 'adjust_decrease' and e.source_type in ('invoice_cancel_released_credit', 'invoice_refund_released_credit')
     and e.reason = 'Held back by the invoice''s cancellation: credit released before it was paid in full' $f$;
-- The release record of an invoice (its first; the cases have one) and its lot.
create function pg_temp.t472_rel_lot(p_inv uuid) returns uuid language sql as $f$
  select lot_id from credit_package_progress_lots where invoice_id = p_inv order by created_at, lot_id limit 1 $f$;
-- The lot of an invoice's release record that a Cancel's write-off closed
-- (locked; after a reopening the release record has a second, open lot).
create function pg_temp.t472_closed_lot(p_inv uuid) returns uuid language sql as $f$
  select pl.lot_id from credit_package_progress_lots pl join customer_credit_lots l on l.id = pl.lot_id
   where pl.invoice_id = p_inv and l.is_locked order by pl.lot_id limit 1 $f$;
create function pg_temp.t472_held_n(p_lot uuid) returns int language sql as $f$
  select count(*)::int from customer_credit_ledger e
   where e.lot_id = p_lot and e.entry_type = 'adjust_decrease' and e.source_type = 'invoice_cancel_benefit'
     and e.reason = 'Held back by the invoice''s cancellation for whoever holds its benefits now' $f$;
-- The package's own benefit row (the one an Owner did not move in), and the
-- lot it names.
create function pg_temp.t472_own(p_inv uuid) returns uuid language sql as $f$
  select bv.id from invoice_benefit_values bv
   where bv.invoice_id = p_inv and bv.lot_id is not null
     and not exists (select 1 from invoice_benefit_transfers t where t.replacement_benefit_id = bv.id)
   order by bv.created_at, bv.id limit 1 $f$;
create function pg_temp.t472_own_lot(p_inv uuid) returns uuid language sql as $f$
  select lot_id from invoice_benefit_values where id = pg_temp.t472_own(p_inv) $f$;
-- Unapplied queue rows of an invoice on a lot (count, sum, requests).
create function pg_temp.t472_waiting(p_inv uuid, p_lot uuid) returns text language sql as $f$
  select count(*) || '/' || coalesce(sum(q.amount), 0) || '/' || count(distinct q.request_id)
    from invoice_reopen_benefits q join customer_credit_ledger e on e.id = q.source_ledger_id
   where q.invoice_id = p_inv and q.applied_at is null and e.lot_id = p_lot $f$;
-- The triggers on invoices (their definitions, by name; search_path public,
-- as the migration reads them).
create function pg_temp.t472_inv_triggers() returns text language plpgsql as $f$
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
create function pg_temp.t472_repair328(p_inv uuid) returns uuid language plpgsql as $f$
declare r record; pk credit_packages%rowtype; v_new uuid; v_rem numeric;
begin
  select l.*, it.id as invoice_item_id, it.invoice_id, it.credit_package_id into r
    from credit_package_progress_lots pl
    join customer_credit_lots l on l.id = pl.lot_id
    join invoice_items it on it.id = pl.invoice_item_id
   where pl.invoice_id = p_inv order by pl.created_at, pl.lot_id limit 1;
  if r.id is null or r.remaining_amount <= 0 then raise exception 'T472: no released lot holding credit to repair'; end if;
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

-- ── 472's cases ─────────────────────────────────────────────────────────────
-- (k, kind, steps, what 472 gives). kind: 'fixed' (before 472 it ends
-- otherwise: the fault is reproduced first), 'control' (the same with and
-- without 472, every key of the outcome), 'known' (a NOT COVERED item,
-- checked as it is: the same with and without 472, as a control). Every
-- case also checks the invariants and that Cancel takes everything back
-- from whoever holds it (but where the case says what it leaves:
-- 'cancel_left').
create temp table t472_cases(k text primary key, kind text not null, steps text not null, expect jsonb not null, ord serial);
insert into t472_cases(k, kind, steps, expect) values
-- 471's NOT COVERED 10: paid in full, an Owner reversed the S$60 left on the
-- package's own lot, cancelled, S1 refunded (A tries to spend it); S2's
-- payment corrected to cash instead.
('PX', 'fixed', 'sale A cp; spend A; spend A; reverse A; cancel; unspend S1',
  '{"holds":{"A":"0.00"},"status":"cancelled","net":100,"held":20,"error":null}'),
('PXs', 'fixed', 'sale A cp; spend A; spend A; reverse A; cancel; unspend S1; spend A',
  '{"holds":{"A":"0.00"},"status":"cancelled","net":100,"held":20,"error~":"spend A: Only 0 of the requested 20.00 could be funded by eligible credit%"}'),
('PXc', 'fixed', 'sale A cp; spend A; spend A; reverse A; cancel; fix S2 cash',
  '{"holds":{"A":"0.00"},"status":"cancelled","net":100,"held":20,"error":null}'),
-- while a reopening waits (S1's S$20 refunded by line first); refunded in
-- full with an override, then S2 refunded (held back, owed to nobody).
('PXw', 'fixed', 'sale A cp; spend A; spend A; reverse A; cancel; unspend S1; back 1 all; reopen; unspend S2; spend A',
  '{"holds":{"A":"0.00"},"status":"partially_paid","net":80,"held":20,"error~":"spend A: Only 0 of the requested 20.00 could be funded by eligible credit%"}'),
('PXx', 'fixed', 'sale A cp; spend A; spend A; reverse A; cancel; unspend S1; backx 1; unspend S2',
  '{"holds":{"A":"0.00"},"status":"cancelled","net":0,"held":20,"error":null}'),
-- S1 refunded while paid (A S$20, then taken by the Cancel), S2 refunded
-- after the Cancel; and with S1's S$20 reversed again before the Cancel.
('PXpc', 'fixed', 'sale A cp; spend A; spend A; reverse A; unspend S1; cancel; unspend S2',
  '{"holds":{"A":"0.00"},"status":"cancelled","net":100,"held":40,"error":null}'),
('PXrr', 'fixed', 'sale A cp; spend A; spend A; reverse A; unspend S1; reverse A; cancel; unspend S2',
  '{"holds":{"A":"0.00"},"status":"cancelled","net":100,"held":20,"error":null}'),
-- paid in part, the released lot's S$15 reversed, cancelled, reopened and
-- paid, a guided Cancel (S$0 owed back), S1 refunded.
('S8g', 'fixed', 'sale A cp 40; spend A; spend A 1 svc5; reverse A; cancel; reopen; pay; guidedcancel; unspend S1',
  '{"holds":{"A":"0.00"},"status":"cancelled","net":40,"owed":20,"fdue":20,"held":20,"error":null}'),
('S8gb', 'fixed', 'sale A cp 40; spend A; spend A 1 svc5; reverse A; cancel; reopen; pay; guidedcancel; unspend S1; back 1 all',
  '{"holds":{"A":"0.00"},"status":"cancelled","net":20,"owed":0,"fdue":0,"held":0,"error":null}'),
('S8gs', 'fixed', 'sale A cp 40; spend A; spend A 1 svc5; reverse A; cancel; reopen; pay; guidedcancel; unspend S1; spend A',
  '{"holds":{"A":"0.00"},"status":"cancelled","net":40,"owed":20,"held":20,"error~":"spend A: Only 0 of the requested 20.00 could be funded by eligible credit%"}'),
-- the released lot a Cancel closed, opened by S1's refund while paid, then
-- reversed (S$20), a guided Cancel, S2 refunded.
('S2g', 'fixed', 'sale A cp 40; spend A; spend A 1 svc5; cancel; reopen; pay; unspend S1; reverse closed; guidedcancel; unspend S2',
  '{"holds":{"A":"0.00"},"status":"cancelled","net":25,"owed":5,"fdue":5,"held":5,"error":null}'),
('S2gb', 'fixed', 'sale A cp 40; spend A; spend A 1 svc5; cancel; reopen; pay; unspend S1; reverse closed; guidedcancel; unspend S2; back 1 all',
  '{"holds":{"A":"0.00"},"status":"cancelled","net":20,"owed":0,"fdue":0,"held":0,"error":null}'),
-- 471's O1 inconsistency: its original lot, which an Owner reversed (471
-- held back only the copy a reissue made of it).
('O1o', 'fixed', 'sale A cp 40; spend A; spend A 1 svc5; reverse A; cancel; reopen; pay; cancel; unspend S1',
  '{"holds":{"A":"0.00"},"status":"cancelled","net":100,"held":80,"error":null}'),
-- the lot the records name closed at S$0 (an Owner reversed B's S$80 the
-- reopening gave), S1 paid from A's lot behind it refunded: cancelled
-- (held back for B; then refunded by line; reopened and paid) or paid (B's).
('RV1', 'fixed', 'sale A cp; spend A; cancel; change B; reopen; pay; reverse B; cancel; unspend S1',
  '{"holds":{"A":"0.00","B":"0.00"},"status":"cancelled","net":100,"held":20,"error":null}'),
('RV1b', 'fixed', 'sale A cp; spend A; cancel; change B; reopen; pay; reverse B; cancel; unspend S1; back 1 all',
  '{"holds":{"A":"0.00","B":"0.00"},"status":"cancelled","net":80,"held":0,"error":null}'),
('RV1r', 'fixed', 'sale A cp; spend A; cancel; change B; reopen; pay; reverse B; cancel; unspend S1; reopen; pay',
  '{"holds":{"A":"0.00","B":"20.00"},"status":"paid","net":100,"held":0,"error":null}'),
('RV1p', 'fixed', 'sale A cp; spend A; cancel; change B; reopen; pay; reverse B; unspend S1',
  '{"holds":{"A":"0.00","B":"20.00"},"status":"paid","net":100,"held":0,"error":null}'),
-- an Owner reversed A's lot, cancelled, a 'transfer' change to B, reopened
-- and paid (cancelled again), S1 refunded: B's (held back for B).
('PXh', 'fixed', 'sale A cp; spend A; spend A; reverse A; cancel; change B; reopen; pay; unspend S1',
  '{"holds":{"A":"0.00","B":"20.00"},"status":"paid","net":100,"held":0,"error":null}'),
('PXhc', 'fixed', 'sale A cp; spend A; spend A; reverse A; cancel; change B; reopen; pay; cancel; unspend S1',
  '{"holds":{"A":"0.00","B":"0.00"},"status":"cancelled","net":100,"held":20,"error":null}'),
-- Controls: the same with and without 472.
('PXb', 'control', 'sale A cp; spend A; spend A; reverse A; cancel; unspend S1; back 1 all',
  '{"holds":{"A":"0.00"},"status":"cancelled","net":80,"held":0,"error":null}'),
('PXp', 'control', 'sale A cp; spend A; spend A; reverse A; unspend S1',
  '{"holds":{"A":"20.00"},"status":"paid","net":100,"held":0,"error":null}'),
('PXr', 'control', 'sale A cp; spend A; spend A; reverse A; cancel; unspend S1; reopen; pay',
  '{"holds":{"A":"20.00"},"status":"paid","net":100,"held":0,"error":null}'),
('PXra', 'control', 'sale A cp; spend A; spend A; reverse A; cancel; unspend S1; reopen; pay; cancel',
  '{"holds":{"A":"0.00"},"status":"cancelled","net":100,"held":20,"error":null}'),
('PXwp', 'control', 'sale A cp; spend A; spend A; reverse A; cancel; unspend S1; back 1 all; reopen; unspend S2; pay',
  '{"holds":{"A":"40.00"},"status":"paid","net":100,"held":0,"error":null}'),
('PXrp', 'control', 'sale A cp; spend A; spend A; reverse A; unspend S1; reverse A; unspend S2',
  '{"holds":{"A":"20.00"},"status":"paid","net":100,"held":0,"error":null}'),
('PXg', 'control', 'sale A cp; spend A; spend A; reverse A; guidedcancel',
  '{"holds":{"A":"0.00"},"status":"paid","net":100,"error~":"guidedcancel: There is no money held on this invoice to return%"}'),
('MV1', 'control', 'sale A cp; spend A; move 1 F; reverse F; cancel; unspend S1',
  '{"holds":{"A":"0.00","F":"0.00"},"status":"cancelled","net":100,"held":20,"error":null}'),
('MV1b', 'control', 'sale A cp; spend A; spend A; move 1 F; reverse F; cancel; unspend S1; back 1 all',
  '{"holds":{"A":"0.00","F":"0.00"},"status":"cancelled","net":80,"held":0,"error":null}'),
('MV1p', 'control', 'sale A cp; spend A; spend A; move 1 F; reverse F; unspend S1',
  '{"holds":{"A":"20.00","F":"0.00"},"status":"paid","net":100,"held":0,"error":null}'),
('O1', 'control', 'sale A cp 40; spend A; spend A 1 svc5; reverse A; cancel; reopen; pay; unspend S1; cancel; change B; reopen; pay; spend B 4; cancel; unspend S3',
  '{"holds":{"A":"0.00","B":"0.00"},"status":"cancelled","net":100,"held":80,"error":null}'),
('PTsp', 'control', 'sale A cp 40; special A special_sale 20; cancel; unspecial D1; refundpaid',
  '{"holds":{"A":"0.00"},"status":"cancelled","net":0,"error":null}'),
('PC', 'control', 'sale A cp; spend A; spend A; cancel; unspend S1; back 1 all',
  '{"holds":{"A":"0.00"},"status":"cancelled","net":20,"held":0,"error":null}'),
('G2', 'control', 'sale A cp; spend A; spend A; move 1 F; unspend S1; guidedcancel; unspend S2',
  '{"holds":{"A":"0.00","F":"0.00"},"status":"cancelled","net":20,"owed":20,"fdue":20,"held":20,"error":null}'),
-- Known (472's NOT COVERED 2): a special document's refund after the
-- reversal puts the S$20 back on the closed lot without opening it: no one
-- can spend it, cancelled or paid.
('PTsx', 'known', 'sale A cp; special A special_sale 20; spend A; reverse A; cancel; unspecial D1',
  '{"holds":{"A":"20.00"},"status":"cancelled","net":100,"held":0,"error":null}'),
('PTsxs', 'known', 'sale A cp; special A special_sale 20; spend A; reverse A; cancel; unspecial D1; spend A',
  '{"holds":{"A":"20.00"},"status":"cancelled","net":100,"held":0,"error~":"spend A: Only 0 of the requested 20.00 could be funded by eligible credit%"}'),
('PTsxp', 'known', 'sale A cp; special A special_sale 20; spend A; reverse A; unspecial D1; spend A',
  '{"holds":{"A":"20.00"},"status":"paid","net":100,"held":0,"error~":"spend A: Only 0 of the requested 20.00 could be funded by eligible credit%"}'),
-- Known (472's NOT COVERED 1): paid in part, S1 paid from the released lot,
-- 328's repair of that lot (the stand-in), paid in full, S1 refunded: the
-- S$20 stays on the repaired lot (cancelled: A can spend it; paid: Cancel
-- leaves it; changed: it stays A's).
('R328', 'known', 'sale A cp 40; spend A; repair328; pay; cancel; unspend S1',
  '{"holds":{"A":"20.00"},"status":"cancelled","net":100,"held":80,"error":null}'),
('R328s', 'known', 'sale A cp 40; spend A; repair328; pay; cancel; unspend S1; spend A',
  '{"holds":{"A":"0.00"},"status":"cancelled","net":100,"held":80,"error":null}'),
('R328p', 'known', 'sale A cp 40; spend A; repair328; pay; unspend S1',
  '{"holds":{"A":"100.00"},"status":"paid","net":100,"held":0,"cancel_left":20,"error":null}'),
('R328c', 'known', 'sale A cp 40; spend A; repair328; pay; change B; unspend S1',
  '{"holds":{"A":"20.00","B":"80.00"},"status":"paid","net":100,"held":0,"cancel_left":20,"error":null}'),
-- (the same change made while cancelled, then reopened and paid: B holds
-- what the reopening gives, the S$20 stays on the repaired lot, A's; the way
-- R328c's change is reached where 473 is in, which refuses R328c's)
('R328cc', 'known', 'sale A cp 40; spend A; repair328; pay; cancel; change B; reopen; pay; unspend S1',
  '{"holds":{"A":"20.00","B":"80.00"},"status":"paid","net":100,"held":0,"cancel_left":20,"error":null}');
-- Where 473 is in too (-v nomig=1): R328c's 'transfer' change of a package
-- paid in part whose released credit was partly spent is refused, as for
-- the same package paid in full (473; 471's NOT COVERED 9), so it ends there.
-- Where 477 is in too (-v nomig=1): the known cases as 477 settles them
-- (472's NOT COVERED 1 and 2): a special document's refund opens the lot,
-- so the S$20 is held back while cancelled (PTsx, PTsxs) and A's to spend
-- while paid (PTsxp); credit given back on the lot 328's repair replaced
-- goes to the lot the records name: held back while cancelled (R328,
-- R328s), A's on that lot while paid, Cancel taking it all (R328p), B's
-- after the change made while cancelled (R328cc). R328c stays as 473
-- leaves it (the change refused; nothing given back).
create temp table t472_exp477(k text primary key, expect jsonb not null);
insert into t472_exp477 values
  ('PTsx', '{"holds":{"A":"0.00"},"status":"cancelled","net":100,"held":20,"error":null}'),
  ('PTsxs', '{"holds":{"A":"0.00"},"status":"cancelled","net":100,"held":20,"error~":"spend A: Only 0 of the requested 20.00 could be funded by eligible credit%"}'),
  ('PTsxp', '{"holds":{"A":"0.00"},"status":"paid","net":100,"held":0,"error":null}'),
  ('R328', '{"holds":{"A":"0.00"},"status":"cancelled","net":100,"held":100,"error":null}'),
  ('R328s', '{"holds":{"A":"0.00"},"status":"cancelled","net":100,"held":100,"error~":"spend A: Only 0 of the requested 20.00 could be funded by eligible credit%"}'),
  ('R328p', '{"holds":{"A":"100.00"},"status":"paid","net":100,"held":0,"error":null}'),
  ('R328cc', '{"holds":{"A":"0.00","B":"100.00"},"status":"paid","net":100,"held":0,"error":null}');
create temp table t472_exp473(k text primary key, expect jsonb not null);
insert into t472_exp473 values
  ('R328c', '{"holds":{"A":"80.00"},"status":"paid","net":100,"held":0,"error~":"change B: These benefits have already been used and cannot move with the invoice: Paid credit %0.00 (Partly spent); Paid credit %0.00 (Partly spent). Resolve%"}');

-- States made for the header's query (each before its last refund or
-- correction): cancelled with sales paid from the lot an Owner reversed
-- still refundable (1), also while a reopening waits and after a part
-- payment; paid, the same holder (none); a closed named lot with a sale paid
-- from A's lot behind it, cancelled (1) or paid (2); after a change (2); a
-- lot 328's repair replaced with a sale refundable (5).
create temp table t472_qstates(k text primary key, steps text not null, reason text, n int);
insert into t472_qstates values
  ('QX', 'sale A cp; spend A; spend A; reverse A; cancel', '1', 2),
  ('QXw', 'sale A cp; spend A; spend A; reverse A; cancel; unspend S1; back 1 all; reopen', '1', 1),
  ('QXg', 'sale A cp 40; spend A; spend A 1 svc5; reverse A; cancel; reopen; pay; guidedcancel', '1', 2),
  ('QXp', 'sale A cp; spend A; spend A; reverse A', null, null),
  ('QRV', 'sale A cp; spend A; cancel; change B; reopen; pay; reverse B; cancel', '1', 1),
  ('QRVp', 'sale A cp; spend A; cancel; change B; reopen; pay; reverse B', '2', 1),
  ('QXh', 'sale A cp; spend A; spend A; reverse A; cancel; change B; reopen; pay', '2', 2),
  ('QR', 'sale A cp 40; spend A; repair328; pay; cancel', '5', 1);

-- The read-only query in 472's header (the same text).
create function pg_temp.t472_header_query() returns table(reason text, invoice_no text, n bigint) language sql as $hq$
with
st as (
  select i.id, i.status::text as status, i.cancel_refund_owed is not null as owed_stated,
         i.status::text in ('cancelled', 'refunded')
         or exists (select 1 from public.invoice_reopen_benefits q where q.invoice_id = i.id and q.applied_at is null) as held
    from public.invoices i where i.deleted_at is null),
-- what 471 reads past: the locked lots of an invoice's credit released
-- before full payment that a Cancel's write-off closed, or a copy of one a
-- reissue made (no ledger row of an Owner's reversal or 328's repair)
wo as (
  select pl.invoice_id, w.lot_id
    from public.credit_package_progress_lots pl
    cross join lateral unnest(public.credit_lot_chain(pl.lot_id)) w(lot_id)
    join public.customer_credit_lots c on c.id = w.lot_id
   where c.is_locked
     and not exists (select 1 from public.customer_credit_ledger e
                      where e.customer_id = c.customer_id and e.lot_id = c.id
                        and e.source_type in ('reversal', 'credit_lot_provenance_repair'))),
-- lots 328's repair replaced (its ledger row)
rp as (
  select distinct e.lot_id from public.customer_credit_ledger e
   where e.source_type = 'credit_lot_provenance_repair' and e.lot_id is not null),
-- each lot a benefit row names and each lot it replaced (credit_lot_ancestry),
-- with whoever holds the benefits, and whether 472 reads where 471 passed it
-- over: a sale paid from the named lot, refunded, opens it; 471 passed it over
-- where it is locked (not 471's wo); a sale paid from a lot behind it: 471
-- passed it over where the named lot is closed or locked so, or that lot is
-- locked so; 472 passes over only a lot 328's repair replaced, and a named lot
-- that is closed and holds credit
x as (
  select b.invoice_id, nl.id as named_id, p.id as lot_id, p.customer_id, p.status as lot_status, p.remaining_amount,
         coalesce(public.invoice_credit_live_holder(b.invoice_id, nl.customer_id,
           case when public.invoice_benefit_moved_to_other(b.id) then 'infinity'::timestamptz else nl.created_at end),
           nl.customer_id) as holder,
         case when p.id = nl.id
              then nl.is_locked and not exists (select 1 from wo where wo.invoice_id = b.invoice_id and wo.lot_id = nl.id)
                   and nl.id not in (select lot_id from rp)
              else not (nl.status <> 'active' and nl.remaining_amount > 0)
                   and nl.id not in (select lot_id from rp) and p.id not in (select lot_id from rp)
                   and (nl.status <> 'active'
                        or nl.is_locked and not exists (select 1 from wo where wo.invoice_id = b.invoice_id and wo.lot_id = nl.id)
                        or p.is_locked and not exists (select 1 from wo where wo.invoice_id = b.invoice_id and wo.lot_id = p.id))
         end as reads_now
    from public.invoice_benefit_values b
    join public.customer_credit_lots nl on nl.id = b.lot_id
    cross join lateral unnest(public.credit_lot_ancestry(nl.id)) a(lot_id)
    join public.customer_credit_lots p on p.id = a.lot_id
   where nl.is_locked or nl.status <> 'active' or p.is_locked or p.status <> 'active'),
sold as (
  select x.*, st.held,
         (select count(*) from public.invoice_line_credit_allocations a where a.lot_id = x.lot_id and a.amount > coalesce(a.reversed_amount, 0))
         + (select count(*) from public.special_credit_allocations s where s.lot_id = x.lot_id and s.amount > coalesce(s.reversed_amount, 0)) as n
    from x join st on st.id = x.invoice_id
   where x.reads_now),
found(reason, invoice_id, n) as (
  select '1 changes: cancelled, refunded or waiting for a reopening''s payment, with sales paid from a lot an Owner reversed that its records name, or from a lot behind such a lot or behind one they name that is closed, that can still be refunded or corrected (the credit they give back is now held back, its money added to what is owed back where that is stated; before, the customer could spend it, or it stayed with whoever it went back to) (the count is of sales)', s.invoice_id, sum(s.n)
    from sold s where s.n > 0 and s.held
   group by s.invoice_id
  union all
  select '2 changes: paid, with sales paid from such a lot that can still be refunded or corrected, where it is behind the lot the records name or held by someone other than whoever holds the benefits now (the credit they give back now goes to whoever holds the benefits; before, it stayed with whoever it went back to) (the count is of sales)', s.invoice_id, sum(s.n)
    from sold s where s.n > 0 and not s.held and (s.lot_id <> s.named_id or s.customer_id <> s.holder)
   group by s.invoice_id
  union all
  select '3 for the Owner (not changed by 472): credit spendable today on such a lot, given back before 472, while the invoice is cancelled, refunded or waiting, or behind the lot the records name, or held by someone other than whoever holds the benefits: a data fix, or left with the customer; until then the next refund or correction of a sale paid from that chain holds it back, or moves it, with the new credit (the count is of lots)', s.invoice_id, count(*)
    from sold s where s.lot_status = 'active' and s.remaining_amount > 0 and (s.held or s.lot_id <> s.named_id or s.customer_id <> s.holder)
   group by s.invoice_id
  union all
  select '4 for the Owner (not changed by 472: NOT COVERED 2): credit on a closed lot its records name, or one behind it (refund_special_credit gives credit back without opening the lot), which no one can spend (the count is of lots)', x.invoice_id, count(distinct x.lot_id)
    from x where x.lot_status <> 'active' and x.remaining_amount > 0
   group by x.invoice_id
  union all
  select '5 for the Owner (not changed by 472: NOT COVERED 1): a lot of its credit released before full payment that 328''s repair replaced, holding credit or with sales paid from it that can still be refunded or corrected (the count is of such sales, and of such lots holding credit)', pl.invoice_id,
         sum((select count(*) from public.invoice_line_credit_allocations a where a.lot_id = l.id and a.amount > coalesce(a.reversed_amount, 0))
             + (select count(*) from public.special_credit_allocations s where s.lot_id = l.id and s.amount > coalesce(s.reversed_amount, 0))
             + case when l.remaining_amount > 0 then 1 else 0 end)
    from rp join public.customer_credit_lots l on l.id = rp.lot_id
    join public.credit_package_progress_lots pl on pl.lot_id = l.id
   group by pl.invoice_id
  having sum((select count(*) from public.invoice_line_credit_allocations a where a.lot_id = l.id and a.amount > coalesce(a.reversed_amount, 0))
             + (select count(*) from public.special_credit_allocations s where s.lot_id = l.id and s.amount > coalesce(s.reversed_amount, 0))
             + case when l.remaining_amount > 0 then 1 else 0 end) > 0)
select f.reason, i.invoice_no, f.n
  from found f join public.invoices i on i.id = f.invoice_id
 order by f.reason, i.invoice_no
$hq$;

-- ===== S. Where it starts =====
create temp table t472_fp(k text primary key, v text);
create function pg_temp.t472_grants(p_without text[] default '{}') returns text language sql as $f$
  select md5(string_agg(p.oid::regprocedure::text || '=' || coalesce(p.proacl::text, ''), '|' order by p.oid::regprocedure::text))
    from pg_proc p where p.pronamespace = 'public'::regnamespace and not (p.proname = any (p_without)) $f$;
create function pg_temp.t472_grant_set(p_sig text) returns text[] language sql as $f$
  select array_agg(x::text order by x::text) from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || p_sig) $f$;
insert into t472_fp values ('start', pg_temp.t472_fingerprint()), ('grants', pg_temp.t472_grants()), ('triggers', pg_temp.t472_inv_triggers());
-- The function 472 changes: BEFORE (production, 26 Oct 2026: 471's AFTER)
-- and AFTER. It adds nothing. (477, where it is in, changes it again:
-- after477.)
create temp table t472_md5(sig text primary key, before text, after text, after477 text);
insert into t472_md5 values
  ('credit_given_back_follows(uuid)', '1417d83e7d7be49209f5cd1369d07ec7', 'f2a7a4d1ca28f0865b14e3f1e5e02bbb', 'a0f2f5ece30be439049dca275802237a');
create function pg_temp.t472_at(p_col text) returns boolean language sql as $f$
  select bool_and(case when p_col = 'before' then md5(pg_get_functiondef(to_regprocedure('public.' || m.sig))) = m.before
                       else md5(pg_get_functiondef(to_regprocedure('public.' || m.sig)))
                            = case when pg_temp.t472_477_in() then m.after477 else m.after end end)
    from t472_md5 m $f$;
do $$ begin
  perform pg_temp.t472_check(pg_temp.t472_462_in() and pg_temp.t472_463_in() and pg_temp.t472_470_in() and pg_temp.t472_471_in(),
    'S 462, 463, 470 and 471 are in (472 goes in after them)');
  perform pg_temp.t472_check(split_part(pg_temp.t472_inv_triggers(), ' ', 1) = '92c94e3ebc6113a68d972330bbca8938',
    'S the triggers on invoices are as read on production (26 Oct 2026): ' || pg_temp.t472_inv_triggers());
end $$;
\if :{?nomig}
do $$ begin
  perform pg_temp.t472_check(pg_temp.t472_in() and pg_temp.t472_at('after'), 'S -v nomig=1: 472 is in, as tested');
end $$;
\else
do $$ begin
  perform pg_temp.t472_check(not pg_temp.t472_in() and pg_temp.t472_at('before'),
    'S 472 is not in yet and the forwarder is 471''s (this suite installs it; use -v nomig=1 where it is in)');
end $$;

-- ===== R. Before 472: each case reproduced (undone afterwards) =====
-- A 'fixed' case does not end as 472 makes it; a control or known case
-- does, exactly.
savepoint t472_r;
do $$
declare c record; o jsonb; res text := '';
begin
  for c in select * from t472_cases order by ord loop
    o := pg_temp.t472_run('before', c.k, c.steps);
    if c.kind = 'fixed' then
      perform pg_temp.t472_check(not (pg_temp.t472_meets(o, c.expect) and coalesce(o->>'invariants', '') = ''),
        'R ' || c.k || ' already ends as 472 makes it, without 472: ' || o::text);
      res := res || format(E'\n  %s: %s; net %s; owed %s; held back %s%s%s', c.k,
        (select string_agg(h.key || ' ' || (h.value #>> '{}'), ', ' order by h.key) from jsonb_each(o->'holds') h),
        o->>'net', coalesce(o->>'owed', '-'), o->>'held', coalesce('; ' || nullif(o->>'invariants', ''), ''),
        coalesce('; refused: ' || left(o->>'error', 100), ''));
    else
      perform pg_temp.t472_check(pg_temp.t472_meets(o, c.expect) and coalesce(o->>'invariants', '') = ''
          and (c.expect ? 'cancel_left' or coalesce((o->>'cancel_left')::numeric, 0) = 0),
        'R ' || c.kind || ' ' || c.k || ' without 472: ' || coalesce(pg_temp.t472_diff(o, c.expect), '') || ' ' || o::text);
    end if;
  end loop;
  for c in select * from t472_qstates loop
    perform pg_temp.t472_run('before', c.k, c.steps);
  end loop;
  raise notice 'PASS R: without 472 every fixed case ends otherwise (the faults reproduced), the controls and the known cases as expected:%', res;
end $$;

-- ===== Q. The header's read-only query, on these states =====
create temp table t472_q as select * from pg_temp.t472_header_query();
create function pg_temp.t472_q_n(p_reason text, p_case text) returns bigint language sql as $f$
  select q.n from t472_q q join invoices i on i.invoice_no = q.invoice_no
   where left(q.reason, 1) = p_reason and i.id = pg_temp.t472_id('before/' || p_case || '/inv') $f$;
create function pg_temp.t472_q_list(p_reason text) returns text language sql as $f$
  select coalesce(string_agg(c.k, ',' order by c.k), '-')
    from (select k from t472_cases union select k from t472_qstates) c
    join invoices i on i.id = pg_temp.t472_id('before/' || c.k || '/inv')
   where exists (select 1 from t472_q q where q.invoice_no = i.invoice_no and left(q.reason, 1) = p_reason) $f$;
do $$
declare c record;
begin
  -- 1, 2 and 5: the states made for it, each under its reason with its
  -- count of sales still refundable; a paid package with the same holder
  -- nowhere.
  for c in select * from t472_qstates loop
    if c.reason is null then
      perform pg_temp.t472_check(not exists (select 1 from t472_q q join invoices i on i.invoice_no = q.invoice_no
                                              where i.id = pg_temp.t472_id('before/' || c.k || '/inv')), 'Q ' || c.k || ' (paid, the same holder) is listed');
    else
      perform pg_temp.t472_check(pg_temp.t472_q_n(c.reason, c.k) = c.n,
        'Q ' || c.k || ' is not listed under ' || c.reason || ' with ' || c.n || ' (' || coalesce(pg_temp.t472_q_n(c.reason, c.k)::text, 'not listed') || ')');
    end if;
  end loop;
  -- 1 and 2 list exactly the states made for them and the R states with a
  -- sale still refundable from such a lot.
  raise notice 'Q lists: 1 %; 2 %; 3 %; 4 %; 5 %', pg_temp.t472_q_list('1'), pg_temp.t472_q_list('2'), pg_temp.t472_q_list('3'),
    pg_temp.t472_q_list('4'), pg_temp.t472_q_list('5');
  perform pg_temp.t472_check(pg_temp.t472_q_list('1') = 'O1,O1o,PTsx,PTsxs,PX,PXb,PXc,PXhc,PXra,PXs,PXw,QRV,QX,QXg,QXw,S8g,S8gb,S8gs',
    'Q 1 lists ' || pg_temp.t472_q_list('1'));
  perform pg_temp.t472_check(pg_temp.t472_q_list('2') = 'PXh,QRVp,QXh',
    'Q 2 lists ' || pg_temp.t472_q_list('2'));
  -- 3: credit spendable today on such a lot (given back before 472) where
  -- 472 holds it back or moves it at the next refund: the R fixed states
  -- that end with credit there.
  perform pg_temp.t472_check(pg_temp.t472_q_list('3') = 'O1o,PX,PXc,PXh,PXhc,PXpc,PXrr,PXx,RV1,RV1b,RV1p,RV1r,S2g,S2gb,S8g,S8gb',
    'Q 3 lists ' || pg_temp.t472_q_list('3'));
  -- 4: a closed lot holding credit (PTsx...); 5: a lot 328's repair
  -- replaced (the stand-in) holding credit or with a sale refundable.
  perform pg_temp.t472_check(pg_temp.t472_q_list('4') = 'PTsx,PTsxp,PTsxs', 'Q 4 lists ' || pg_temp.t472_q_list('4'));
  perform pg_temp.t472_check(pg_temp.t472_q_list('5') = 'QR,R328,R328c,R328cc,R328p,R328s', 'Q 5 lists ' || pg_temp.t472_q_list('5'));
  -- the controls paid with the same holder, or whose package's own lot no
  -- Owner reversed, are listed nowhere (O1 and PXra are listed under 1: a
  -- sale paid from the lot an Owner reversed can still be refunded there)
  perform pg_temp.t472_check(not exists (select 1 from t472_q q join invoices i on i.invoice_no = q.invoice_no
                                          join t472_cases tc on i.id = pg_temp.t472_id('before/' || tc.k || '/inv')
                                         where tc.k in ('PXp', 'PXr', 'PXrp', 'PXwp', 'PXg', 'MV1', 'MV1b', 'MV1p', 'PTsp', 'PC', 'G2')),
    'Q a control is listed');
  raise notice 'PASS Q: the header''s read-only query lists % invoices (%), each reason as expected',
    (select count(distinct invoice_no) from t472_q),
    (select string_agg(left(reason, 1) || ' ' || n, ', ' order by left(reason, 1)) from (select reason, count(*) n from t472_q group by reason) x);
end $$;
-- Keep R's outcomes; undo its records.
select coalesce(jsonb_object_agg(k, v), '{}'::jsonb)::text as t472_rbefore from t472_res where phase = 'before' \gset
rollback to savepoint t472_r;
insert into t472_res select 'before', key, value from jsonb_each(:'t472_rbefore'::jsonb);
do $$ begin
  perform pg_temp.t472_check((select count(*) from t472_res where phase = 'before') = (select count(*) from t472_cases) + (select count(*) from t472_qstates)
      and pg_temp.t472_fingerprint() = (select v from t472_fp where k = 'start'),
    'R undone, its outcomes kept');
end $$;

-- ===== 9. The refusals, each changing nothing =====
-- 9a The forwarder is neither 471's nor 472's.
savepoint t472_9;
alter function public.credit_given_back_follows(uuid) set work_mem = '64kB';
\set ON_ERROR_STOP off
\ir ../../../supabase/472_reversed_lot_credit_held_back.sql
\set ON_ERROR_STOP on
rollback to savepoint t472_9;
select set_config('t472.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t472_check(current_setting('t472.msg') like '472: public.credit_given_back_follows(uuid) is not the version this was tested against (md5 %). Re-read it and re-test before applying.'
      and not pg_temp.t472_in(), '9a refused with: ' || current_setting('t472.msg'));
end $$;
-- 9b A function it relies on is not as read (a setting added to it): the
-- financial position, 462's trigger function, and what refuses 327's source.
savepoint t472_9;
alter function public.invoice_financial_position(uuid) set work_mem = '64kB';
\set ON_ERROR_STOP off
\ir ../../../supabase/472_reversed_lot_credit_held_back.sql
\set ON_ERROR_STOP on
rollback to savepoint t472_9;
select set_config('t472.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t472_check(current_setting('t472.msg') like '472: public.invoice_financial_position(uuid) is missing or not the version this was tested against (md5 %). Re-read it and re-test before applying.'
      and not pg_temp.t472_in(), '9b refused with: ' || current_setting('t472.msg'));
end $$;
savepoint t472_9;
alter function public.trg_credit_given_back_follows() set work_mem = '64kB';
\set ON_ERROR_STOP off
\ir ../../../supabase/472_reversed_lot_credit_held_back.sql
\set ON_ERROR_STOP on
rollback to savepoint t472_9;
select set_config('t472.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t472_check(current_setting('t472.msg') like '472: public.trg_credit_given_back_follows() is missing or not the version this was tested against (md5 %)%'
      and not pg_temp.t472_in(), '9b2 refused with: ' || current_setting('t472.msg'));
end $$;
savepoint t472_9;
alter function public.credit_lot_line_allowed(uuid, uuid) set work_mem = '64kB';
\set ON_ERROR_STOP off
\ir ../../../supabase/472_reversed_lot_credit_held_back.sql
\set ON_ERROR_STOP on
rollback to savepoint t472_9;
select set_config('t472.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t472_check(current_setting('t472.msg') like '472: public.credit_lot_line_allowed(uuid,uuid) is missing or not the version this was tested against (md5 %)%'
      and not pg_temp.t472_in(), '9b3 refused with: ' || current_setting('t472.msg'));
end $$;
-- 9c Another function takes its name (an overload).
savepoint t472_9;
create function public.credit_given_back_follows(p text) returns void language sql as $f$ select $f$;
\set ON_ERROR_STOP off
\ir ../../../supabase/472_reversed_lot_credit_held_back.sql
\set ON_ERROR_STOP on
rollback to savepoint t472_9;
select set_config('t472.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t472_check(current_setting('t472.msg') = '472: another function takes the name of the one this changes: credit_given_back_follows(text)'
      and not pg_temp.t472_in(), '9c refused with: ' || current_setting('t472.msg'));
end $$;
-- 9d A new reader or writer of a cancellation's ledger rows.
savepoint t472_9;
create function public.t472_probe_cancel_rows() returns text language sql as $f$ select 'invoice_cancel_benefit'::text $f$;
\set ON_ERROR_STOP off
\ir ../../../supabase/472_reversed_lot_credit_held_back.sql
\set ON_ERROR_STOP on
rollback to savepoint t472_9;
select set_config('t472.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t472_check(current_setting('t472.msg') like '472: what reads or writes a cancellation''s ledger rows is not as read on 26 Oct 2026 (%t472_probe_cancel_rows()%)'
      and not pg_temp.t472_in(), '9d refused with: ' || current_setting('t472.msg'));
end $$;
-- 9e A trigger on invoices that was not there when this was read.
savepoint t472_9;
create trigger t472_probe after update on public.invoices for each row execute function public.trg_lock_on_settle();
\set ON_ERROR_STOP off
\ir ../../../supabase/472_reversed_lot_credit_held_back.sql
\set ON_ERROR_STOP on
rollback to savepoint t472_9;
select set_config('t472.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t472_check(current_setting('t472.msg') like '472: the triggers on invoices are not as read on 26 Oct 2026 (20 triggers, md5 %)%'
      and not pg_temp.t472_in(), '9e refused with: ' || current_setting('t472.msg'));
end $$;
-- 9f A new way to raise a lot's balance (it would need the same care).
savepoint t472_9;
create function public.t472_probe_raise(p uuid) returns void language sql as $f$
  update public.customer_credit_lots set remaining_amount = remaining_amount + 0 where id = p $f$;
\set ON_ERROR_STOP off
\ir ../../../supabase/472_reversed_lot_credit_held_back.sql
\set ON_ERROR_STOP on
rollback to savepoint t472_9;
select set_config('t472.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t472_check(current_setting('t472.msg') like '472: what gives credit back on a lot is not as read on 26 Oct 2026 (% / %t472_probe_raise(uuid)%)%'
      and not pg_temp.t472_in(), '9f refused with: ' || current_setting('t472.msg'));
end $$;
-- 9h A new reader or writer of the release record.
savepoint t472_9;
create function public.t472_probe_release() returns bigint language sql as $f$ select count(*) from public.credit_package_progress_lots $f$;
\set ON_ERROR_STOP off
\ir ../../../supabase/472_reversed_lot_credit_held_back.sql
\set ON_ERROR_STOP on
rollback to savepoint t472_9;
select set_config('t472.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t472_check(current_setting('t472.msg') like '472: what reads or writes the release record of credit released before full payment, or its write-off rows, is not as read on 26 Oct 2026 (%t472_probe_release()%'
      and not pg_temp.t472_in(), '9h refused with: ' || current_setting('t472.msg'));
end $$;
-- 9i A new way to lock a lot (the forwarder now reads past every lock but
-- 328's repair's).
savepoint t472_9;
create function public.t472_probe_lock(p uuid) returns void language sql as $f$
  update public.customer_credit_lots set is_locked = true where id = p $f$;
\set ON_ERROR_STOP off
\ir ../../../supabase/472_reversed_lot_credit_held_back.sql
\set ON_ERROR_STOP on
rollback to savepoint t472_9;
select set_config('t472.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t472_check(current_setting('t472.msg') like '472: what locks a credit lot, or writes 328''s repair row, is not as read on 26 Oct 2026 (%t472_probe_lock(uuid)%'
      and not pg_temp.t472_in(), '9i refused with: ' || current_setting('t472.msg'));
end $$;
-- 9j A new writer of 328's repair row (by which the forwarder tells the one
-- lock it still passes over).
savepoint t472_9;
create function public.t472_probe_repair_row() returns text language sql as $f$ select 'credit_lot_provenance_repair'::text $f$;
\set ON_ERROR_STOP off
\ir ../../../supabase/472_reversed_lot_credit_held_back.sql
\set ON_ERROR_STOP on
rollback to savepoint t472_9;
select set_config('t472.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t472_check(current_setting('t472.msg') like '472: what locks a credit lot, or writes 328''s repair row, is not as read on 26 Oct 2026 (% / %t472_probe_repair_row()%'
      and not pg_temp.t472_in(), '9j refused with: ' || current_setting('t472.msg'));
end $$;
-- 9g The same grants in another order: installs (compared as sets).
savepoint t472_9;
revoke execute on function public.credit_given_back_follows(uuid) from postgres;
grant execute on function public.credit_given_back_follows(uuid) to postgres;
\ir ../../../supabase/472_reversed_lot_credit_held_back.sql
do $$ begin
  perform pg_temp.t472_check(pg_temp.t472_in() and pg_temp.t472_at('after'), '9g the same grants in another order stopped it');
end $$;
rollback to savepoint t472_9;
do $$ begin
  perform pg_temp.t472_check(pg_temp.t472_fingerprint() = (select v from t472_fp where k = 'start') and not pg_temp.t472_in()
      and pg_temp.t472_grants() = (select v from t472_fp where k = 'grants'),
    '9 the refusals left a change');
  raise notice 'PASS 9: refused, changing nothing: the forwarder not 471''s, a function it relies on not as tested (the financial position, 462''s trigger function, what refuses 327''s source), an overload of its name, a new reader of a cancellation''s rows, a new trigger on invoices, a new way to raise a lot, a new reader of the release record, a new way to lock a lot, a new writer of 328''s repair row. The same grants in another order do not stop it';
end $$;

-- ===== M. Begun before 472, finished after it (the mid set) =====
-- Cancelled, waiting or paid when it goes in, the session refunded or
-- corrected after; and credit given back before 472 on such a lot: left as
-- it is (MPXs: A spends it), then held back, or moved to B, with the next
-- refund of a sale paid from that chain (MPX2, MRV2).
create temp table t472_mid(k text primary key, ord serial, split int, steps text, expect jsonb);
insert into t472_mid(k, split, steps, expect) select 'm' || k, s, steps, expect from (values
  ('PX', 5), ('PXc', 5), ('PXw', 8), ('S8g', 8), ('S2g', 9), ('O1o', 8), ('RV1', 8), ('RV1p', 7), ('PXh', 8)) x(k, s)
  join t472_cases c using (k);
insert into t472_mid(k, split, steps, expect) values
  ('MPX2', 6, 'sale A cp; spend A; spend A; reverse A; cancel; unspend S1; unspend S2',
    '{"holds":{"A":"0.00"},"status":"cancelled","net":100,"held":40,"error":null}'),
  ('MPXs', 6, 'sale A cp; spend A; spend A; reverse A; cancel; unspend S1; spend A',
    '{"holds":{"A":"0.00"},"status":"cancelled","net":100,"held":0,"error":null}'),
  ('MRV2', 10, 'sale A cp; spend A; spend A; cancel; change B; reopen; pay; reverse B; cancel; unspend S1; unspend S2',
    '{"holds":{"A":"0.00","B":"0.00"},"status":"cancelled","net":100,"held":40,"error":null}'),
  ('MRV2p', 9, 'sale A cp; spend A; spend A; cancel; change B; reopen; pay; reverse B; unspend S1; unspend S2',
    '{"holds":{"A":"0.00","B":"40.00"},"status":"paid","net":100,"held":0,"error":null}');
do $$ declare c record; begin
  for c in select * from t472_mid order by ord loop
    perform pg_temp.t472_run('mid', c.k, c.steps, 1, c.split);
  end loop;
end $$;
\endif

-- ===== 10. Install 472, twice =====
\if :{?nomig}
do $$ begin raise notice 'NOTE 10: -v nomig=1, so 472 is not installed here (R, Q, 9 and M are skipped)'; end $$;
\else
\ir ../../../supabase/472_reversed_lot_credit_held_back.sql
do $$ begin insert into t472_fp values ('first', pg_temp.t472_fingerprint()); end $$;
\ir ../../../supabase/472_reversed_lot_credit_held_back.sql
do $$ begin insert into t472_fp values ('second', pg_temp.t472_fingerprint()); end $$;
\endif
do $$
begin
  perform pg_temp.t472_check(pg_temp.t472_in() and pg_temp.t472_at('after'), '10 472 is not installed as tested');
  perform pg_temp.t472_check((select count(*) from pg_proc where pronamespace = 'public'::regnamespace
                               and proname = 'credit_given_back_follows') = 1, '10 an overload exists');
  perform pg_temp.t472_check(pg_temp.t472_inv_triggers() = (select v from t472_fp where k = 'triggers')
      and (select count(*) from pg_trigger where tgrelid = 'public.customer_credit_ledger'::regclass and not tgisinternal and tgname like 'credit_given_back%') = 1,
    '10 a trigger was added or changed: ' || pg_temp.t472_inv_triggers());
  perform pg_temp.t472_check(pg_temp.t472_grant_set('credit_given_back_follows(uuid)') = '{postgres=X/postgres,service_role=X/postgres}'
      and not has_function_privilege('anon', 'public.credit_given_back_follows(uuid)', 'execute')
      and not has_function_privilege('authenticated', 'public.credit_given_back_follows(uuid)', 'execute'),
    '10 who may call it is not as intended');
  if exists (select 1 from t472_fp where k = 'first') then
    perform pg_temp.t472_check((select v from t472_fp where k = 'second') = (select v from t472_fp where k = 'first'),
      '10 the second run of 472 changed functions');
    perform pg_temp.t472_check(split_part((select v from t472_fp where k = 'first'), ' ', 2)::int
                               = split_part((select v from t472_fp where k = 'start'), ' ', 2)::int,
      '10 472 added or dropped a function');
    perform pg_temp.t472_check(pg_temp.t472_grants() = (select v from t472_fp where k = 'grants'),
      '10 the grants changed');
  end if;
  raise notice 'PASS 10: 472 installed as tested (%); the forwarder at its AFTER, the server''s alone; nothing added (no function, no trigger); %',
    pg_temp.t472_fingerprint(),
    coalesce((select 'the second run changed nothing, the grants as before' from t472_fp where k = 'first'), 'it was in before the suite (nomig)');
end $$;

-- ===== A. Each case after 472 =====
do $$
declare c record; o jsonb; b jsonb; res text := ''; v_exp jsonb;
begin
  for c in select * from t472_cases order by ord loop
    o := pg_temp.t472_run('after', c.k, c.steps);
    v_exp := case when pg_temp.t472_473_in() then coalesce((select e.expect from t472_exp473 e where e.k = c.k), c.expect) else c.expect end;
    if pg_temp.t472_477_in() then v_exp := coalesce((select e.expect from t472_exp477 e where e.k = c.k), v_exp); end if;
    perform pg_temp.t472_check(pg_temp.t472_meets(o, v_exp),
      'A ' || c.k || ': ' || coalesce(pg_temp.t472_diff(o, v_exp), '') || ' ' || o::text);
    perform pg_temp.t472_check(coalesce(o->>'invariants', '') = '', 'A ' || c.k || ' invariants: ' || (o->>'invariants'));
    perform pg_temp.t472_check(v_exp ? 'cancel_left' or coalesce((o->>'cancel_left')::numeric, 0) = 0,
      'A ' || c.k || ': Cancel leaves S$' || (o->>'cancel_left') || ' of the invoice''s credit behind');
    b := (select v from t472_res where phase = 'before' and k = c.k);
    -- (a refusal's text names its invoice, numbered differently in each run;
    -- an amount owed back on an invoice that is no longer cancelled is read
    -- by nothing, so it is not compared)
    if c.kind in ('control', 'known') and b is not null
       and not (pg_temp.t472_473_in() and exists (select 1 from t472_exp473 e where e.k = c.k))
       and not (pg_temp.t472_477_in() and exists (select 1 from t472_exp477 e where e.k = c.k)) then
      perform pg_temp.t472_check(o - 'error' - case when o->>'status' = 'cancelled' then '' else 'owed' end
                                 = b - 'error' - case when b->>'status' = 'cancelled' then '' else 'owed' end
          and regexp_replace(coalesce(o->>'error', ''), 'INV-[0-9-]+', 'INV', 'g') = regexp_replace(coalesce(b->>'error', ''), 'INV-[0-9-]+', 'INV', 'g'),
        'A ' || c.kind || ' ' || c.k || ' changed with 472: before ' || b::text || ', after ' || o::text);
    end if;
    res := res || format(E'\n  %s %s: %s; net %s; owed %s; held back %s%s', c.kind, c.k,
      (select string_agg(h.key || ' ' || (h.value #>> '{}'), ', ' order by h.key) from jsonb_each(o->'holds') h), o->>'net',
      coalesce(o->>'owed', '-'), o->>'held', coalesce('; refused: ' || left(o->>'error', 100), ''));
  end loop;
  raise notice 'PASS A: after 472 each case ends by the Owner''s rules (the known cases as NOT COVERED 1 and 2 say), the invariants hold in every case and Cancel takes all of it back (but R328p, R328c: NOT COVERED 1); the controls and the known cases are exactly as before 472%:%',
    case when exists (select 1 from t472_res where phase = 'before') then '' else ' (no before figures: -v nomig=1)' end, res;
end $$;

-- ===== M (after). The mid set finished with 472 in =====
\if :{?nomig}
\else
do $$
declare c record; o jsonb; res text := '';
begin
  for c in select * from t472_mid order by ord loop
    o := pg_temp.t472_run('mid', c.k, c.steps, c.split + 1);
    perform pg_temp.t472_check(pg_temp.t472_meets(o, c.expect) and coalesce(o->>'invariants', '') = ''
        and (c.expect ? 'cancel_left' or coalesce((o->>'cancel_left')::numeric, 0) = 0),
      'M ' || c.k || ': ' || coalesce(pg_temp.t472_diff(o, c.expect), '') || ' ' || o::text);
    res := res || ' ' || c.k;
  end loop;
  raise notice 'PASS M: begun before 472 and finished after it, each ends as the whole case does after 472; credit given back before 472 is left spendable (MPXs) until a refund or correction of a sale paid from that chain holds it back, or moves it to B, with the new credit (MPX2 S$40, MRV2 S$40 held back, MRV2p B S$40):%', res;
end $$;
\endif

-- ===== P. Probes =====
do $$
declare inv uuid; a uuid; b uuid; lot uuid; lot1 uuid; m jsonb; v_req uuid;
begin
  -- P1 PX: held back where it is, on the package's own lot (the sale's lot,
  -- never reissued: no reassignment row, A has that one lot): 'active' (the
  -- refund opened it), still locked, S$0, one held-back row of S$20 (A's,
  -- not queued); the Owner's reversal row as it was (S$60: what it took
  -- stays taken), the lot's balance its ledger's; the row holds back S$20;
  -- the Audit Log says so (in place, S$20); A's statement ends at S$0.
  inv := pg_temp.t472_id('after/PX/inv'); a := pg_temp.t472_id('after/PX/A'); lot := pg_temp.t472_own_lot(inv);
  perform pg_temp.t472_check(
        lot = (select s.credit_lot_id from credit_package_sales s where s.invoice_id = inv)
    and (select count(*) from customer_credit_lots where customer_id = a) = 1
    and not exists (select 1 from customer_credit_ledger x where x.source_record_id = inv and x.source_type like 'credit_given_back_reassignment_%')
    and (select remaining_amount from customer_credit_lots where id = lot) = 0
    and (select status from customer_credit_lots where id = lot) = 'active' and (select is_locked from customer_credit_lots where id = lot)
    and (select count(*) from customer_credit_ledger x where x.lot_id = lot and x.source_type = 'reversal' and x.entry_type = 'reverse' and x.amount = 60) = 1
    and pg_temp.t472_ledger_balance(lot) = 0
    and pg_temp.t472_held_n(lot) = 1 and pg_temp.t472_held(lot) = 20
    and (select x.customer_id from customer_credit_ledger x where x.lot_id = lot and x.reason like 'Held back by%') = a
    and not exists (select 1 from invoice_reopen_benefits q join customer_credit_ledger x on x.id = q.source_ledger_id
                     where x.lot_id = lot and x.reason like 'Held back by%')
    and (select cancelled_unused_value from invoice_benefit_values where id = pg_temp.t472_own(inv)) = 20,
    'P1 PX: not held back where it is on the lot an Owner reversed');
  perform pg_temp.t472_check((select count(*) from audit_logs al where al.record_id = inv and al.action = 'credit_given_back_followed'
            and (al.new_data->>'held_in_place')::boolean and (al.new_data->>'held_back')::numeric = 20
            and (al.new_data->>'lot_id')::uuid = lot and al.new_data->>'to_customer' = a::text) = 1
      and (select wallet_balance from customer_credit_statement(a) order by entry_date desc, entry_seq desc limit 1) = 0
      and (select count(*) from customer_credit_statement(a)
            where description = 'Adjustment — decrease — Held back by the invoice''s cancellation for whoever holds its benefits now' and credit_used = 20) = 1,
    'P1 PX: the Audit Log or the credit statement');
  -- P2 S8g: what is owed back grows by the money a refund by line of the
  -- released lot's row pays back for the S$20 (S$0 -> S$20), what the refund
  -- options offer, the Finance panel's and Cancel's refund due; the S$15 the
  -- Owner reversed stays kept; after the refund by line (S8gb) nothing is
  -- owed back. S2g: S$5 the same way.
  inv := pg_temp.t472_id('after/S8g/inv'); m := pg_temp.t472_money(inv);
  perform pg_temp.t472_check((m->>'owed')::numeric = 20 and (m->>'due')::numeric = 20 and (m->>'by_line')::numeric = 20
      and (m->>'plan_due')::numeric = 20
      and (select count(*) from audit_logs al where al.record_id = inv and al.action = 'credit_given_back_followed'
            and (al.new_data->>'held_in_place')::boolean and (al.new_data->>'refund_owed')::numeric = 0
            and (al.new_data->>'refund_owed_added')::numeric = 20 and (al.new_data->>'refund_owed_now')::numeric = 20) = 1,
    'P2 S8g: what is owed back is not what the refund by line can pay back: ' || m::text);
  m := pg_temp.t472_money(pg_temp.t472_id('after/S8gb/inv'));
  perform pg_temp.t472_check((m->>'owed')::numeric = 0 and (m->>'due')::numeric = 0 and (m->>'by_line')::numeric = 0,
    'P2 S8gb: after the refund by line something is still owed back: ' || m::text);
  m := pg_temp.t472_money(pg_temp.t472_id('after/S2g/inv'));
  perform pg_temp.t472_check((m->>'owed')::numeric = 5 and (m->>'due')::numeric = 5 and (m->>'by_line')::numeric = 5,
    'P2 S2g: ' || m::text);
  -- P3 RV1p: the lot the records name (B's, closed at S$0 by an Owner's
  -- reversal of S$80) is replaced by one new lot of B's holding the S$20
  -- given back on A's lot behind it (unlocked, 'active', naming the closed
  -- lot as the one it replaces); the records name the new lot; the closed
  -- lot stays closed with its reversal row; A's lot at S$0; the Audit Log
  -- names the closed lot replaced. RV1: the same lot made for B holds
  -- nothing, the S$20 held back on it; the row holds it back.
  inv := pg_temp.t472_id('after/RV1p/inv'); a := pg_temp.t472_id('after/RV1p/A'); b := pg_temp.t472_id('after/RV1p/B');
  lot := pg_temp.t472_own_lot(inv);
  select reassigned_from_lot_id into lot1 from customer_credit_lots where id = lot;
  perform pg_temp.t472_check(
        (select customer_id from customer_credit_lots where id = lot) = b
    and (select remaining_amount from customer_credit_lots where id = lot) = 20
    and (select status from customer_credit_lots where id = lot) = 'active' and not (select is_locked from customer_credit_lots where id = lot)
    and (select customer_id from customer_credit_lots where id = lot1) = b
    and (select status from customer_credit_lots where id = lot1) = 'reversed' and (select remaining_amount from customer_credit_lots where id = lot1) = 0
    and (select count(*) from customer_credit_ledger x where x.lot_id = lot1 and x.source_type = 'reversal' and x.amount = 80) = 1
    and (select s.credit_lot_id from credit_package_sales s where s.invoice_id = inv) = lot
    and (select coalesce(sum(remaining_amount), 0) from customer_credit_lots where customer_id = a) = 0
    and (select count(*) from audit_logs al where al.record_id = inv and al.action = 'credit_given_back_followed'
          and (al.new_data->>'replaces_lot_id')::uuid = lot1 and (al.new_data->>'lot_id')::uuid = lot and al.new_data->>'held_back' is null) = 1,
    'P3 RV1p: the closed lot was not replaced by B''s new lot');
  inv := pg_temp.t472_id('after/RV1/inv'); b := pg_temp.t472_id('after/RV1/B'); lot := pg_temp.t472_own_lot(inv);
  perform pg_temp.t472_check(
        (select customer_id from customer_credit_lots where id = lot) = b
    and (select remaining_amount from customer_credit_lots where id = lot) = 0
    and pg_temp.t472_held(lot) = 20
    and (select status from customer_credit_lots c where c.id = (select reassigned_from_lot_id from customer_credit_lots where id = lot)) = 'reversed'
    and (select cancelled_unused_value from invoice_benefit_values where id = pg_temp.t472_own(inv)) = 20,
    'P3 RV1: not held back for B on the lot that replaces the closed one');
  -- P4 O1o: held back where it is on the original lot an Owner reversed
  -- (one held-back row of S$20 on it, its reversal row of S$15 as it was).
  inv := pg_temp.t472_id('after/O1o/inv');
  select l.id into lot from invoice_benefit_values bv join customer_credit_lots l on l.id = bv.lot_id
   where bv.invoice_id = inv and exists (select 1 from customer_credit_ledger x where x.lot_id = l.id and x.source_type = 'reversal');
  perform pg_temp.t472_check(lot is not null and pg_temp.t472_held(lot) = 20 and pg_temp.t472_held_n(lot) = 1
      and (select remaining_amount from customer_credit_lots where id = lot) = 0
      and (select count(*) from customer_credit_ledger x where x.lot_id = lot and x.source_type = 'reversal' and x.amount = 15) = 1,
    'P4 O1o: not held back on the original lot an Owner reversed');
  -- P5 PXw: while the reopening waits, S2's S$20 is held back on the lot an
  -- Owner reversed and queued for that reopening's request, with S1's S$20
  -- held back at the Cancel, refunded by line and queued by the Reopen (its
  -- payment gives back what the money paid again buys); paid, A S$40 (S$100
  -- less what was used, S$0, less the S$60 the reversal took).
  perform pg_temp.t472_run('P', 'PXw', 'sale A cp; spend A; spend A; reverse A; cancel; unspend S1; back 1 all; reopen; unspend S2');
  inv := pg_temp.t472_id('P/PXw/inv'); a := pg_temp.t472_id('P/PXw/A'); lot := pg_temp.t472_own_lot(inv);
  select q.request_id into v_req from invoice_reopen_benefits q where q.invoice_id = inv and q.applied_at is null order by q.created_at desc limit 1;
  perform pg_temp.t472_check((select err from t472_err where pre = 'P/PXw') is null
      and pg_temp.t472_waiting(inv, lot) = '2/40.00/1'
      and (select count(*) from invoice_reopen_benefits q join customer_credit_ledger x on x.id = q.source_ledger_id
            where q.invoice_id = inv and q.applied_at is null and x.lot_id = lot and q.request_id = v_req
              and x.reason like 'Held back by%' and q.amount = 20) = 2
      and (select count(*) from audit_logs al where al.record_id = inv and al.action = 'credit_given_back_followed'
            and (al.new_data->>'held_in_place')::boolean and al.new_data->>'queued_for_request' = v_req::text) = 1
      and (select coalesce(sum(remaining_amount), 0) from customer_credit_lots where customer_id = a) = 0,
    'P5 PXw: not queued for the reopening''s payment: ' || pg_temp.t472_waiting(inv, lot));
  perform pg_temp.t472_pay(inv);
  perform pg_temp.t472_commit();
  perform pg_temp.t472_check((select coalesce(sum(remaining_amount), 0) from customer_credit_lots where customer_id = a) = 40
      and not exists (select 1 from invoice_reopen_benefits q where q.invoice_id = inv and q.applied_at is null)
      and pg_temp.t472_invariants(inv) = '',
    'P5 PXw: the payment did not give A S$40');
  -- P6 Nothing held back where the package stayed paid (PXp, PXrp, MV1p),
  -- and no lot reissued by the forwarder but where the records name a
  -- closed lot with credit behind it (RV1..., PXh, PXhc).
  perform pg_temp.t472_check(not exists (select 1 from customer_credit_ledger x
                   where x.source_record_id in (select pg_temp.t472_id('after/' || k || '/inv') from unnest(array['PXp', 'PXrp', 'MV1p']) k)
                     and x.reason like 'Held back by%'),
    'P6 PXp/PXrp/MV1p: something was held back');
  perform pg_temp.t472_check(not exists (select 1 from customer_credit_ledger x
                   where x.source_record_id in (select pg_temp.t472_id('after/' || k || '/inv') from t472_cases
                                                 where k not in ('RV1', 'RV1b', 'RV1r', 'RV1p', 'PXh', 'PXhc', 'O1')
                                                   -- 477, where it is in: credit given back on the lot 328's
                                                   -- repair replaced goes to the lot the records name
                                                   and not (pg_temp.t472_477_in() and k like 'R328%'))
                     and x.source_type like 'credit_given_back_reassignment_%'),
    'P6 a case forwarded credit to a new lot (other than RV1..., PXh, PXhc and O1; and R328... where 477 is in)');
  raise notice 'PASS P: PX held back where it is on the lot an Owner reversed (the package''s own lot, opened and still locked, one held-back row, the reversal''s S$60 still taken, the Audit Log, the statement at S$0); S8g owed back S$0 -> S$20 by its money (the refund options, refund due and Cancel''s), nothing after the refund by line, S2g S$5; RV1p the closed lot B holds replaced by a new lot of B''s with the S$20 (RV1: held back on it); O1o held back on the original reversed lot; PXw queued for the reopening''s payment, then A S$40; nothing more for the controls';
end $$;

-- ===== K. KNOWN: 472's NOT COVERED (each checked as it is) =====
do $$
declare o jsonb; inv uuid; lot uuid; c uuid; it uuid; v_err text;
begin
  -- K1 (NOT COVERED 1): a lot 328's repair replaced is passed over as
  -- before: with the stand-in (a lot that keeps the package's source) the
  -- S$20 given back stays on it: cancelled, A can spend it (R328, R328s);
  -- paid, Cancel leaves it (R328p); after a 'transfer' change it stays A's
  -- (R328c). A lot with 327's source (what the real repair replaced) cannot
  -- be spent from, so no sale is paid from one and nothing is given back on
  -- it: a S$50 lot of that source for a new customer funds nothing.
  -- Where 477 is in (it settles NOT COVERED 1): the S$20 goes to the lot the
  -- records name: held back while cancelled (R328: A S$0, S$100 held back;
  -- R328s refused), A's on that lot while paid with Cancel taking it all
  -- (R328p), B's after the change made while cancelled (R328cc).
  if pg_temp.t472_477_in() then
    perform pg_temp.t472_check((select v->'holds'->>'A' from t472_res where phase = 'after' and k = 'R328') = '0.00'
        and (select (v->>'held')::numeric from t472_res where phase = 'after' and k = 'R328') = 100
        and (select v->>'error' from t472_res where phase = 'after' and k = 'R328s') like 'spend A: Only 0 of the requested 20.00%'
        and coalesce((select (v->>'cancel_left')::numeric from t472_res where phase = 'after' and k = 'R328p'), 0) = 0
        and (select v->'holds' from t472_res where phase = 'after' and k = 'R328c') @> '{"A":"80.00"}'
        and (select v->'holds' from t472_res where phase = 'after' and k = 'R328cc') @> '{"A":"0.00","B":"100.00"}'
        and coalesce((select (v->>'cancel_left')::numeric from t472_res where phase = 'after' and k = 'R328cc'), 0) = 0,
      'K1 R328 (477 in): NOT COVERED 1 is not settled as 477 settles it');
  else
  perform pg_temp.t472_check((select v->'holds'->>'A' from t472_res where phase = 'after' and k = 'R328') = '20.00'
      and (select v->>'error' from t472_res where phase = 'after' and k = 'R328s') is null
      and (select (v->>'cancel_left')::numeric from t472_res where phase = 'after' and k = 'R328p') = 20
      and (select v->'holds' from t472_res where phase = 'after' and k = 'R328c')
          @> case when pg_temp.t472_473_in() then '{"A":"80.00"}'::jsonb else '{"A":"20.00","B":"80.00"}'::jsonb end
      and (select v->'holds' from t472_res where phase = 'after' and k = 'R328cc') @> '{"A":"20.00","B":"80.00"}',
    'K1 R328: look at NOT COVERED 1 again');
  end if;
  c := pg_temp.t472_cust('K/L327/A');
  inv := pg_temp.t472_id('after/R328/inv'); it := (select id from invoice_items where invoice_id = inv limit 1);
  lot := grant_customer_credit(c, 'paid', 50, 'credit_package_progress', it, pg_temp.t472_id('store'), sg_today(), null,
    'T472 a lot as 327 released it', 'T472 stand-in', sg_today(), auth.uid(), null);
  begin
    perform pg_temp.t472_spend(c);
    v_err := null;
  exception when others then v_err := sqlerrm;
  end;
  perform pg_temp.t472_check(v_err like 'Only 0 of the requested 20.00 could be funded by eligible credit%'
      and (select remaining_amount from customer_credit_lots where id = lot) = 50,
    'K1 L327: a lot with 327''s source could be spent from: ' || coalesce(v_err, 'spent'));
  -- K2 (NOT COVERED 2): a special document's refund after an Owner's
  -- reversal puts the S$20 on the closed lot ('reversed') without opening
  -- it: no one can spend it, cancelled or paid; 472 passes it over.
  -- Where 477 is in (it settles NOT COVERED 2): the refund opens the lot
  -- ('active', still locked), the S$20 held back there while cancelled, A's
  -- to spend while paid (PTsxp spends it).
  inv := pg_temp.t472_id('after/PTsx/inv'); lot := pg_temp.t472_own_lot(inv);
  if pg_temp.t472_477_in() then
    perform pg_temp.t472_check((select status from customer_credit_lots where id = lot) = 'active'
        and (select is_locked from customer_credit_lots where id = lot)
        and (select remaining_amount from customer_credit_lots where id = lot) = 0
        and pg_temp.t472_held(lot) = 20
        and (select v->>'error' from t472_res where phase = 'after' and k = 'PTsxs') like 'spend A: Only 0 of the requested 20.00%'
        and (select v->>'error' from t472_res where phase = 'after' and k = 'PTsxp') is null,
      'K2 PTsx (477 in): NOT COVERED 2 is not settled as 477 settles it');
  else
  perform pg_temp.t472_check((select status from customer_credit_lots where id = lot) = 'reversed'
      and (select remaining_amount from customer_credit_lots where id = lot) = 20
      and pg_temp.t472_held(lot) = 0
      and (select v->>'error' from t472_res where phase = 'after' and k = 'PTsxs') like 'spend A: Only 0 of the requested 20.00%'
      and (select v->>'error' from t472_res where phase = 'after' and k = 'PTsxp') like 'spend A: Only 0 of the requested 20.00%',
    'K2 PTsx: look at NOT COVERED 2 again');
  end if;
  -- K3 (NOT COVERED 3): credit given back before 472 on such a lot stays
  -- spendable (MPXs: A spent it after 472) until the next refund holds it
  -- back with the new credit (MPX2: S$40).
  if exists (select 1 from t472_res where phase = 'mid' and k = 'MPXs') then
    perform pg_temp.t472_check((select v->>'error' from t472_res where phase = 'mid' and k = 'MPXs') is null
        and (select (v->>'held')::numeric from t472_res where phase = 'mid' and k = 'MPXs') = 0
        and (select (v->>'held')::numeric from t472_res where phase = 'mid' and k = 'MPX2') = 40,
      'K3 MPXs/MPX2: look at NOT COVERED 3 again');
  end if;
  -- K4 (NOT COVERED 4): the lot stays locked once a refund opened it: its
  -- holder can spend it (PXp: S$20 A's), but a Move of it is refused, as for
  -- 471's lots a Cancel closed.
  -- Where 477 is in (it settles NOT COVERED 4): the Move takes what the lot
  -- holds now (A S$0, F S$20).
  o := pg_temp.t472_run('K', 'MVX', 'sale A cp; spend A; spend A; reverse A; unspend S1; move 1 F');
  if pg_temp.t472_477_in() then
    perform pg_temp.t472_check(o->>'error' is null and o->'holds' @> '{"A":"0.00","F":"20.00"}' and coalesce(o->>'invariants', '') = ''
        and coalesce((o->>'cancel_left')::numeric, 0) = 0,
      'K4 MVX (477 in): NOT COVERED 4 is not settled as 477 settles it: ' || o::text);
  else
  perform pg_temp.t472_check(o->>'error' like 'move 1 F: This credit lot is locked or reversed%' and o->'holds' @> '{"A":"20.00"}',
    'K4 MVX: look at NOT COVERED 4 again: ' || o::text);
  end if;
  if pg_temp.t472_477_in() then
    raise notice 'KNOWN K: 477 is in: 472''s NOT COVERED 1 (R328: held back, A S$100 on the named lot, B S$100), 2 (PTsx: held back on the opened lot, PTsxp spent) and 4 (MVX: moved, F S$20) are settled as 477 settles them; a lot with 327''s source funds nothing (L327); (3) credit given back before 472 left spendable until the next refund of a sale paid from that chain%',
      case when exists (select 1 from t472_res where phase = 'mid' and k = 'MPXs') then ' (MPXs, then MPX2 S$40)' else ' (not tried: -v nomig=1)' end;
  else
  raise notice 'KNOWN K: (472''s NOT COVERED) (1) a lot 328''s repair replaced passed over (the stand-in R328: A S$20 of a cancelled package, Cancel leaving S$20 when paid, A''s after a change), and a lot with 327''s source funds nothing (L327), so on production no sale is paid from one; (2) a special document''s refund leaves the credit on the closed lot, which no one can spend (PTsx, PTsxs, PTsxp); (3) credit given back before 472 left spendable until the next refund of a sale paid from that chain%; (4) a Move of credit on a lot an Owner reversed and a refund opened again refused (MVX: locked)',
    case when exists (select 1 from t472_res where phase = 'mid' and k = 'MPXs') then ' (MPXs, then MPX2 S$40)' else ' (not tried: -v nomig=1)' end;
  end if;
end $$;

rollback;
