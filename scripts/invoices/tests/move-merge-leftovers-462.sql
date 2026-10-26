-- 462: credit an Owner moved, merged or reinstated follows its records, and
-- credit a refunded or corrected sale gives back follows to whoever holds
-- the invoice's benefits now (460's NOT COVERED 4, 461's NOT COVERED 3,
-- 445's moved lot partly taken back; the Owner, 24 Oct 2026: "B, the
-- package's holder now"). supabase/462_moved_and_merged_credit_follows_its_records.sql.
--
-- Every step goes through the app's own calls: the invoice form
-- (create_invoice_with_details) and the Pay dialog (record_invoice_settlement),
-- Record Payment (record_invoice_payment), Cancel (cancel_invoice_recorded),
-- the Finance panel's refund by line and "Record refund paid"
-- (refund_invoice_recorded), its Correct payment (correct_invoice_payment),
-- Reopen (reopen_invoice), Move (transfer_invoice_unused_benefit), the
-- guided Refund in full (invoice_action_plan, request_invoice_action_v2,
-- resolve_invoice_action_v2), the invoice form's customer change
-- (correct_invoice, 'transfer' or 'keep'), a customer merge
-- (merge_customer_records), Delete customer (delete_customer), a reversal
-- (reverse_credit_lot) and the provenance repair; a special document's
-- wallet payment is a stand-in (no page calls pay_special_with_credit, and no
-- credit category allows one), its refund the real refund_special_credit.
-- Each app call is followed by what its commit does: 462's trigger is
-- DEFERRABLE INITIALLY DEFERRED, and this suite is one transaction, so its
-- queued rows are run at that point (SET CONSTRAINTS ... IMMEDIATE, then
-- DEFERRED again). A customer change's Audit Log row is dated at the call
-- (clock_timestamp), as a later call's is.
--
-- The cases (A the buyer; B, C later customers; K, K2 records a merge keeps;
-- F, G friends an Owner moved credit to; cp a S$100 Credit Package, cpb one
-- with a S$10 Bonus, pbv a S$140 Premium Bundle with two vouchers; a S$20
-- session paid from the wallet). The catalogue's case numbers:
--   1  K5, K5c, K5g, K5s, K5k, L4: reinstated credit stays with the old
--      customer after a change (the change before or after the cancel; the
--      guided Refund in full; the old customer then spends it; then merged;
--      a part-paid package).
--   2  K5b, X9b, M7c: the change refused on a moved-on lot after the credit
--      came back.
--   3  K6, K6b, K6c: reinstated credit on the retired record after a merge.
--   4  K9, K9r, K9b, M7b, X9c: a merge after the reinstatement moves the
--      credit without its records (false credit_used, due S$60).
--   5  M7: a merge chain while it waits.  6/7  X10 to X13: the benefits
--      leave the named lot's holder after the Move (a merge, a change).
--   8  S1, S2, R4: credit a refunded sale gave back on a moved-on lot
--      blocked a change. R3c: a lot a reopening reissued to the new
--      customer after a session was paid from the package read as untouched
--      and moved with a second change (462's P3b: it blocks).
--   9  S4, S4m (the Owner: "B, the package's holder now"), with D1d, D1a,
--      D1c: the session's wallet payment corrected instead (date only; a
--      smaller amount; to cash).
--   G1b, G1c (no Move: a change while the reopening waits, then the session
--      refunded), with G1d, G1a, G1x: the payment corrected instead.
--   L13: a 13-line session paid from the package, refunded at once: one new
--      lot (the chain stays short).
--   DH1, DH2: the benefits' holder deleted (not merged): never credit on a
--      deleted record (the invoice's customer, else the lot's holder).
--   The second review (24 Oct 2026): CW1 (V1), CW1r/m/c/x, CW3 (V3), CW3r,
--      X1, X1p, X2, X2p, X2m, X2c, W3p, W3F, W3l, W3c: credit given back
--      while the package's invoice is cancelled or its reopening waits
--      stays where it went back until the reopening is paid, the reserve
--      released on the row the chain leads to (each then refunded in full,
--      by line, moved, changed, cancelled); CH1, CH2, CH2b, CH3: many
--      refunds, each its own commit, after a change (and a Move): the chain
--      stays short; DH3, DH3b: the benefits' holder deleted after a reissued
--      lot of its was emptied; K9s: K9's merge, the kept record spends the
--      reissued lot to S$0, the session refunded.
--   10 R1, R1b, R2, L3, R5, R1y: the reopening was refused (S$50 or more
--      refunded before the reissue).  11 R3, R3b, S3, S3w, R3n: refused
--      while lot credit paid for another sale; the session refunded after
--      (and while it waits); R3n without a Move.
--   12 F3a: merged moved credit partly taken back could not be spent.
--   13 T1r: a Move to the same customer at another store, then a change
--      (the reinstated part follows; the moved part stays: 463).
--   SS1 to SS3: a special document's credit refunded (special_sale, rental,
--      rental_late_fee).
--   Controls (the same with and without 462): K8, K5d, K1, K3, X3, M1,
--   M8a, M8b, F1, F2, L1, L2, L5, S1k, S1m, S3zd, T1, T2, T2c, V3, V4, V6,
--   V1w; the sources the trigger leaves alone: PX1 (446's pair, a refund
--   while a reopening waits), PX2 (a reversal), PX3 (the provenance repair).
--   (Catalogue 14 to 16 and decisions 2 and 3 are 463's; 18 is not
--   reachable on a copy; 19 is S3w.)
-- In every case (the critic's 6): no lot of the invoice's family (the lots
-- its records name and each Move's two lots, read from the Move's ledger
-- rows, with the lots each replaced and every lot reissued from them) holds
-- credit unless one of its records names it; each lot's balance is what
-- its ledger rows say; no chain is more than 12 lots deep; a moved lot
-- holding credit traces to its origin and can be spent; a named lot keeps
-- the origin of the lot it replaced; a named lot holding credit is held by
-- whoever holds the benefits; no sale paid from a lot no record names,
-- behind no lot a benefit row names, can still be refunded; no benefit row
-- holds back more than it granted, nor anything once settled again with no
-- reopening waiting; a refunded invoice leaves no credit on its family; and
-- Cancel (tried, undone) takes all of the invoice's credit back from
-- whoever holds it.
--
--   S. Where it starts: 462 in (nomig) or not, the six at 464's texts.
--   R. Without 462 (skipped with -v nomig=1), undone: each 'fixed' case
--      ends otherwise (the faults reproduced); each control as expected.
--   Q. The read-only query in 462's header (the same text), on those
--      states: what it lists, by reason; the controls not listed.
--   9. Refusals, each changing nothing: the R states (credit on a lot no
--      record names: exactly the invoices Q lists); K5's state (credit on a
--      named lot held by someone other than the benefits' holder); a Move
--      with a third ledger row; a lot 13 reissues down; K9s's state before
--      its refund (the reissued lot spent to S$0); a changed function,
--      a changed function it relies on, a new way of writing credit back.
--      Installs over a moved lot held for review (F3a), which can then be
--      spent; the same grants in another order do not stop it.
--   M. The mid set (K5, X13, R4, S4, G1b, F3a, R1, X12, L13; M8a, M8b, F1,
--      T1r, K8, which the install's trace check reads; CW1, X2p, DH3, CH2,
--      CH1): begun before 462, finished after it.
--  10. 462 installed twice: as tested, the second run changing nothing, four
--      functions added, the other grants as before (as sets), the trigger
--      deferred with its five sources, the index.
--   A. Each case after 462: who holds what, the plans' codes and refund due,
--      the invariants, Cancel; the controls exactly as before 462.
--   P. The forwarder: it runs at commit (S4), the statements, one new lot
--      for 13 lines (L13), nothing for the sources it leaves alone, no
--      credit on a deleted record; separate refunds keep the chain short
--      (CH1, CH2, CH3); nothing forwarded while cancelled or waiting (CW1,
--      CW3, W3p, X1p, X2p); the chain limit refused at commit (P8a to P8d);
--      every record deleted: refused (P9).
--   K. KNOWN (not covered by 462), checked as they are: T1, V3/V4 (the
--      Owner's decisions 2 and 3, for 463), W1's summary (463), an invoice
--      for a retired record (K6s, 463's optional guard), S1m (445's NOT
--      COVERED 1), a moved lot's "Fully spent" label (461's NOT COVERED 2),
--      credit given back while the package stays cancelled (K7b, 462's NOT
--      COVERED 10).
--
-- Where 463 is in too (-v nomig=1), four of 462's functions are at 463's
-- AFTERs, and T1, T1r, T2, T2c, V3, V4 and KNOWN 1 to 4 end the 463 way (the
-- Owner's decisions 2 and 3, the summary while a reopening waits, the
-- guard); 463's own suite checks them.
-- Where 470 is in too (-v nomig=1), the forwarder is at 470's AFTER: credit
-- given back while the package's invoice is cancelled, or its reopening
-- waits, is held back by the cancellation for the benefits' holder, on the
-- lot the records name (P7: CW1, CW3, W3p and X1p once each, X2p after its
-- forward while paid; each case ends as before), and KNOWN K7b (462's NOT
-- COVERED 10) ends the 470 way: all of it paid back, nothing on a lot no
-- record names. 470's own suite (cancelled-package-refund-470) checks it and
-- its siblings.
-- Where 471 is in too (-v nomig=1), the forwarder is at 471's AFTER (470's
-- rules, and without a reissue credit given back while the package is
-- cancelled, refunded or its reopening waits is held back in place too):
-- every case here ends as with 470 (S takes 471's AFTER); 471's own suite
-- (plain-cancelled-package-credit-471) checks the plain case.
-- Run on a copy of production as it is (464 in: 432fcb99, 1379 functions;
-- 465 and 467, TikTok only, do not change what it checks):
--   psql -X -v ON_ERROR_STOP=1 -f scripts/invoices/tests/move-merge-leftovers-462.sql
-- It installs 462 itself (twice) inside its transaction. Where 462 is in
-- already, add -v nomig=1 (S checks it as tested; R, Q, 9, M and the
-- before/after comparison are skipped; every case after 462 is still
-- checked). Sections 9 let the install fail on purpose (psql prints its
-- ERROR); the suite then checks that message. Disposable database only;
-- everything is rolled back. Every name, code and amount is invented
-- (@example.com); the phones are numbers kept for fiction (ACMA,
-- +61491570000 to +61491570999).
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '10s';
set local statement_timeout = '900s';

-- ── Set-up and the app's calls (462 suite harness) ─────────────────────────
create temp table t462(k text primary key, id uuid);
create temp table t462_res(phase text, k text, v jsonb, primary key (phase, k));
create temp sequence t462_phone;
create function pg_temp.t462_id(p_k text) returns uuid language sql as $f$ select id from t462 where k = p_k $f$;
create function pg_temp.t462_put(p_k text, p_id uuid) returns uuid language sql as $f$
  insert into t462 values (p_k, p_id) on conflict (k) do update set id = excluded.id returning id $f$;
create function pg_temp.t462_check(p_ok boolean, p_label text) returns void language plpgsql as $f$
begin
  if not coalesce(p_ok, false) then raise exception 'FAIL %', p_label; end if;
end $f$;
create function pg_temp.t462_fingerprint() returns text language sql as $f$
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.oid::regprocedure::text)) || ' ' || count(*)
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prokind in ('f', 'p') $f$;
create function pg_temp.t462_463_in() returns boolean language sql as $f$
  select to_regprocedure('public.invoice_benefit_moved_to_other(uuid)') is not null $f$;
create function pg_temp.t462_in() returns boolean language sql as $f$
  select to_regprocedure('public.credit_given_back_follows(uuid)') is not null
     and exists (select 1 from pg_trigger where tgname = 'credit_given_back_follows'
                  and tgrelid = 'public.customer_credit_ledger'::regclass) $f$;
-- 470 is in: the forwarder at 470's AFTER (470 adds nothing), or at 471's
-- (which keeps 470's rules and adds nothing).
create function pg_temp.t462_470_in() returns boolean language sql as $f$
  select to_regprocedure('public.credit_given_back_follows(uuid)') is not null
     and md5(pg_get_functiondef('public.credit_given_back_follows(uuid)'::regprocedure))
         in ('b7720a148f5371bd2bd844d3076ea3b2', '1417d83e7d7be49209f5cd1369d07ec7') $f$;
-- 471 is in: the forwarder at 471's AFTER.
create function pg_temp.t462_471_in() returns boolean language sql as $f$
  select to_regprocedure('public.credit_given_back_follows(uuid)') is not null
     and md5(pg_get_functiondef('public.credit_given_back_follows(uuid)'::regprocedure)) = '1417d83e7d7be49209f5cd1369d07ec7' $f$;
-- What a commit does at the end of each app call (each is its own
-- transaction in the app): 462's deferred trigger runs. Here the suite is
-- one transaction, so the trigger's queued rows are run at this point.
-- (Not where each step really commits: t462.autocommit 'on', for running
-- the same cases one call per transaction on a disposable copy.)
create function pg_temp.t462_commit() returns void language plpgsql as $f$
begin
  if pg_temp.t462_in() and coalesce(current_setting('t462.autocommit', true), '') <> 'on' then
    execute 'set constraints public.credit_given_back_follows immediate';
    execute 'set constraints public.credit_given_back_follows deferred';
  end if;
end $f$;

do $$
declare own uuid := gen_random_uuid(); st uuid; st2 uuid; pm uuid; v uuid; cp uuid; cpb uuid; pbv uuid; svc uuid; svc5 uuid;
begin
  insert into auth.users(id, email) values (own, 't462-owner@example.com');
  insert into profiles(id, full_name, email, role, is_active) values (own, 'T462 Owner', 't462-owner@example.com', 'owner', true);
  perform set_config('request.jwt.claims', json_build_object('sub', own, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', own::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  insert into stores(name, code, country_code) values ('T462 Store', 'T462S1', 'SG') returning id into st;
  insert into stores(name, code, country_code) values ('T462 Other Store', 'T462S2', 'SG') returning id into st2;
  insert into payment_methods(name, is_active) values ('T462 Cash', true) returning id into pm;
  insert into vouchers(name, code, voucher_kind, qty_type, selling_price, is_active)
    values ('T462 Plain 30', 'T462-P30', 'normal', 'unlimited', 30, true) returning id into v;
  insert into voucher_store_prices(voucher_id, store_id, selling_price, available_at_store) values (v, st, 30, true), (v, st2, 30, true);
  insert into credit_packages(name, customer_price, paid_credit_amount, bonus_enabled, allow_product, allow_therapy)
    values ('T462 S$100', 100, 100, false, true, true) returning id into cp;
  insert into credit_package_stores(package_id, store_id) values (cp, st), (cp, st2);
  insert into credit_packages(name, customer_price, paid_credit_amount, bonus_enabled, bonus_value, allow_product, allow_therapy, grants_reward)
    values ('T462 S$100 + S$10', 100, 100, true, 10, true, true, false) returning id into cpb;
  insert into credit_package_stores(package_id, store_id) values (cpb, st), (cpb, st2);
  insert into premium_bundles(name, customer_payment_amount, paid_credit_amount, bonus_credit_amount, free_voucher_qty, grants_reward)
    values ('T462 Bundle S$140 + 2 vouchers', 140, 100, 40, 2, true) returning id into pbv;
  insert into premium_bundle_stores(bundle_id, store_id) values (pbv, st), (pbv, st2);
  insert into premium_bundle_vouchers(bundle_id, voucher_id) values (pbv, v);
  svc := (upsert_therapy_service(null, 'T462-SESSION', 'T462 Session', 20, 30, 'per_hours', 1, 5, null, true, null) ->> 'id')::uuid;
  perform set_therapy_service_store(svc, st, true, null);
  svc5 := (upsert_therapy_service(null, 'T462-SHORT', 'T462 Short session', 5, 15, 'per_hours', 1, 5, null, true, null) ->> 'id')::uuid;
  perform set_therapy_service_store(svc5, st, true, null);
  insert into t462 values ('own', own), ('store', st), ('store2', st2), ('pm', pm), ('v', v), ('cp', cp), ('cpb', cpb), ('pbv', pbv),
    ('svc', svc), ('svc5', svc5),
    ('wallet', (select id from payment_methods where name = 'Wallet — Credit Package Paid' and is_wallet_credit and deleted_at is null)),
    ('bwallet', (select id from payment_methods where name = 'Wallet — Premium Bundle Paid' and is_wallet_credit and deleted_at is null));
  perform pg_temp.t462_check(pg_temp.t462_id('wallet') is not null and pg_temp.t462_id('bwallet') is not null, 'setup: the wallet methods (443) are there');
end $$;

-- A customer of one run of one case: '<phase>/<case>/<role>'.
create function pg_temp.t462_cust(p_k text) returns uuid language plpgsql as $f$
declare c uuid;
begin
  insert into customers(full_name, phone) values ('T462 ' || p_k, '+61491570' || lpad((nextval('t462_phone') % 1000)::text, 3, '0'))
    returning id into c;
  return pg_temp.t462_put(p_k, c);
end $f$;
-- The invoice form with these lines ('cp' / 'cpb' a Credit Package, 'pbv' the
-- Premium Bundle, 'v' a voucher line of p_qty units), paid through the Pay
-- dialog: in full, or p_first of it (a part-paid package).
create function pg_temp.t462_sale(p_cust uuid, p_kinds text[], p_first numeric default null, p_qty int default 2)
  returns uuid language plpgsql as $f$
declare inv uuid; v_lines jsonb := '[]'; i int;
begin
  for i in 1 .. cardinality(p_kinds) loop
    v_lines := v_lines || jsonb_build_array(case
      when p_kinds[i] = 'v' then jsonb_build_object('kind', 'voucher', 'voucher_id', pg_temp.t462_id('v'), 'quantity', p_qty)
      when p_kinds[i] in ('cp', 'cpb') then jsonb_build_object('kind', 'credit_package', 'credit_package_id', pg_temp.t462_id(p_kinds[i]), 'quantity', 1)
      else jsonb_build_object('kind', 'premium_bundle', 'premium_bundle_id', pg_temp.t462_id('pbv'), 'quantity', 1,
        'voucher_selection', jsonb_build_array(jsonb_build_object('voucher_id', pg_temp.t462_id('v'), 'quantity', 2))) end);
  end loop;
  inv := create_invoice_with_details(pg_temp.t462_id('store'), p_cust, v_lines, jsonb_build_object('business_date', sg_today()::text));
  perform record_invoice_settlement(inv, jsonb_build_object('receipts', jsonb_build_array(jsonb_build_object(
    'key', 'line-0', 'payment_method_id', pg_temp.t462_id('pm'),
    'amount', coalesce(p_first, (select total_amount from invoices where id = inv)),
    'payment_date', sg_today()::text)), 'arrangements', '[]'::jsonb), gen_random_uuid());
  return inv;
end $f$;
-- Record Payment of what is outstanding (nothing when it is settled).
create function pg_temp.t462_pay(p_inv uuid) returns void language plpgsql as $f$
begin
  if (invoice_financial_position(p_inv)->>'outstanding')::numeric > 0 then
    perform record_invoice_payment(p_inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.t462_id('pm'),
      'amount', (invoice_financial_position(p_inv)->>'outstanding')::numeric)), gen_random_uuid());
  end if;
end $f$;
-- The receipts that still hold p_amount between them, as the Finance panel
-- splits a refund across them.
create function pg_temp.t462_sources(p_inv uuid, p_amount numeric) returns jsonb language plpgsql as $f$
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
create function pg_temp.t462_line(p_inv uuid, p_n int default 1) returns uuid language sql as $f$
  select id from invoice_items where invoice_id = p_inv order by id offset p_n - 1 limit 1 $f$;
-- The Finance panel's refund by line of line p_n: p_amount off its Paid
-- benefit (the one an Owner did not move, or with p_holder the one p_holder
-- holds), or every unused benefit it still holds (p_amount null).
create function pg_temp.t462_back(p_inv uuid, p_n int, p_amount numeric default null, p_holder uuid default null)
  returns void language plpgsql as $f$
declare opts jsonb; ben jsonb; tot numeric; item uuid := pg_temp.t462_line(p_inv, p_n);
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
  if ben is null then raise exception 'T462: nothing to refund on that line'; end if;
  perform refund_invoice_recorded(p_inv, jsonb_build_array(jsonb_build_object('invoice_item_id', item, 'amount', tot, 'benefits', ben)),
    pg_temp.t462_sources(p_inv, tot), '[]'::jsonb, 'T462 by line', gen_random_uuid());
end $f$;
-- The invoice form's customer change, its lines as they are (and the store,
-- when given), with 'transfer' or 'keep'. The change's Audit Log row is
-- dated now, as a later call's is (the suite is one transaction).
create function pg_temp.t462_lines(p_inv uuid) returns jsonb language sql as $f$
  select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('invoice_item_id', it.id, 'kind', it.line_kind,
           'credit_package_id', it.credit_package_id, 'premium_bundle_id', it.premium_bundle_id, 'voucher_id', it.voucher_id,
           'quantity', it.quantity, 'unit_price', it.unit_price, 'voucher_selection', it.bundle_voucher_selection)) order by it.id)
    from invoice_items it where it.invoice_id = p_inv $f$;
create function pg_temp.t462_change(p_inv uuid, p_cust uuid, p_action text default 'transfer', p_store text default null)
  returns void language plpgsql as $f$
begin
  perform correct_invoice(p_inv, pg_temp.t462_lines(p_inv),
    jsonb_build_object('expected_edit_count', (select edit_count from invoices where id = p_inv),
      'customer_id', p_cust, 'store_id', coalesce(pg_temp.t462_id(p_store), (select store_id from invoices where id = p_inv)),
      'benefit_action', p_action),
    'T462 wrong customer', gen_random_uuid());
  update audit_logs set created_at = clock_timestamp()
   where record_id = p_inv and action = 'invoice_benefits_followed_reassignment' and new_data->>'to_customer' = p_cust::text
     and created_at = now();
end $f$;
create function pg_temp.t462_merge(p_keep uuid, p_dup uuid) returns void language plpgsql as $f$
begin
  perform merge_customer_records(p_keep, p_dup, 'T462 the same person', gen_random_uuid());
end $f$;
-- The Finance panel's Move of line p_n's unused benefit (its Paid credit,
-- or its Bonus with p_kind 'bonus', or a voucher) to p_to, at p_store.
create function pg_temp.t462_move(p_inv uuid, p_n int, p_to uuid, p_kind text default 'paid', p_store text default null)
  returns void language plpgsql as $f$
declare b uuid;
begin
  select bv.id into b from invoice_benefit_values bv
    left join customer_reward_vouchers v on v.id = bv.reward_voucher_id
    left join customer_credit_lots l on l.id = bv.lot_id
   where bv.invoice_item_id = pg_temp.t462_line(p_inv, p_n)
     and (v.status = 'held' and p_kind = 'voucher' or l.remaining_amount > 0 and l.category = p_kind)
   order by bv.granted_value desc limit 1;
  if b is null then raise exception 'T462: nothing to move on that line'; end if;
  perform transfer_invoice_unused_benefit(b, p_to, coalesce(pg_temp.t462_id(p_store), (select store_id from invoices where id = p_inv)),
    'T462 move', gen_random_uuid());
end $f$;
-- The invoice form: p_n sessions of S$20 (or S$5 with p_svc 'svc5') for
-- p_cust, paid with the wallet (Credit Package Paid) through Record Payment.
create function pg_temp.t462_spend(p_cust uuid, p_n int default 1, p_svc text default 'svc') returns uuid language plpgsql as $f$
declare inv uuid; v_lines jsonb := '[]'; i int;
begin
  for i in 1 .. p_n loop
    v_lines := v_lines || jsonb_build_array(jsonb_build_object('kind', 'therapy', 'therapy_service_id', pg_temp.t462_id(p_svc), 'quantity', 1));
  end loop;
  inv := create_invoice_with_details(pg_temp.t462_id('store'), p_cust, v_lines, jsonb_build_object('business_date', sg_today()::text));
  perform record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.t462_id('wallet'),
    'amount', (select total_amount from invoices where id = inv))), gen_random_uuid());
  if (select status::text from invoices where id = inv) <> 'paid' then raise exception 'T462: the session paid from credit is not paid'; end if;
  return inv;
end $f$;
-- The session cancelled and "Record refund paid": what its payment took goes
-- back to the lots it came from (refund_invoice_recorded's wallet refund).
create function pg_temp.t462_unspend(p_inv uuid) returns void language plpgsql as $f$
declare due numeric;
begin
  perform cancel_invoice_recorded(p_inv, 'T462 cancel session', gen_random_uuid());
  due := (invoice_financial_position(p_inv)->>'refund_due')::numeric;
  if due is null or due <= 0 then due := (invoice_action_plan(p_inv, 'cancel', '[]')->>'refund_due')::numeric; end if;
  perform refund_invoice_recorded(p_inv, jsonb_build_array(jsonb_build_object('amount', due)), pg_temp.t462_sources(p_inv, due), '[]'::jsonb,
    'T462 refund paid', gen_random_uuid());
end $f$;
-- The Finance panel's Correct payment on a session's wallet payment: the
-- date only ('date'), a smaller amount ('amount', S$5 less), or another
-- method ('cash').
create function pg_temp.t462_fix(p_inv uuid, p_how text) returns void language plpgsql as $f$
declare p invoice_payments%rowtype;
begin
  select * into p from invoice_payments where invoice_id = p_inv and entry_kind in ('receipt', 'correction_replacement')
     and not exists (select 1 from invoice_payments q where q.corrects_payment_id = invoice_payments.id and q.entry_kind = 'correction_reversal')
   order by created_at desc, id desc limit 1;
  perform correct_invoice_payment(p.id,
    case p_how when 'amount' then p.amount - 5 else p.amount end,
    sg_today() - 1,
    case p_how when 'cash' then pg_temp.t462_id('pm') else p.payment_method_id end,
    'T462 correct payment ' || p_how, gen_random_uuid());
end $f$;
-- A special document's wallet payment as pay_special_with_credit records it
-- (a stand-in: no page calls that function, and no credit category allows a
-- special document today, purchase_category): p_amount off the customer's
-- largest lot ('use', its allocations), so refund_special_credit, the real
-- one, gives it back.
create function pg_temp.t462_special(p_cust uuid, p_kind text, p_doc uuid, p_amount numeric) returns void language plpgsql as $f$
declare l customer_credit_lots%rowtype; e uuid;
begin
  select * into l from customer_credit_lots where customer_id = p_cust and status = 'active' and remaining_amount >= p_amount
   order by remaining_amount desc, id limit 1 for update;
  insert into customer_credit_ledger(wallet_id, customer_id, entry_type, category, amount, lot_id, source_type, source_record_id, store_id, note, created_by)
  values (l.wallet_id, p_cust, 'use', l.category, p_amount, l.id, p_kind, p_doc, l.store_id, 'T462 special', auth.uid()) returning id into e;
  update customer_credit_lots set remaining_amount = remaining_amount - p_amount, updated_at = now() where id = l.id;
  insert into customer_credit_allocations(ledger_entry_id, lot_id, customer_id, amount) values (e, l.id, p_cust, p_amount);
  insert into special_credit_allocations(doc_kind, doc_id, customer_id, lot_id, category, amount, created_by)
  values (p_kind, p_doc, p_cust, l.id, l.category, p_amount, auth.uid());
end $f$;
-- The guided Refund in full / Cancel as an Owner confirms it, with a reason
-- for every override the plan asks for, the money recorded as paid back.
create function pg_temp.t462_guided(p_inv uuid, p_action text) returns void language plpgsql as $f$
declare plan jsonb; req jsonb; ov jsonb;
begin
  plan := invoice_action_plan(p_inv, p_action, '[]');
  req := request_invoice_action_v2(p_inv, p_action, '[]', 'T462 ' || p_action, null, gen_random_uuid());
  select coalesce(jsonb_agg(case when coalesce((o->>'amount_required')::boolean, false)
           then jsonb_build_object('code', o->>'code', 'reason', 'T462 override', 'amount', (o->>'default_amount')::numeric)
           else jsonb_build_object('code', o->>'code', 'reason', 'T462 override') end), '[]'::jsonb)
    into ov from jsonb_array_elements(coalesce(plan->'overrides_required', '[]')) o;
  perform resolve_invoice_action_v2((req->>'request_id')::uuid, true, 'T462 ' || p_action, plan->>'plan_hash', ov, null, true);
end $f$;


-- ── What the records say ────────────────────────────────────────────────────
-- The lots an invoice's records name: its benefit values, its sale's lots, a
-- split's issued lot, released credit (credit_package_progress_lots).
create function pg_temp.t462_named(p_inv uuid) returns setof uuid language sql as $f$
  select lot_id from invoice_benefit_values where invoice_id = p_inv and lot_id is not null
  union select x from credit_package_sales s, unnest(array[s.credit_lot_id, s.bonus_credit_lot_id]) x where s.invoice_id = p_inv and x is not null
  union select x from premium_bundle_sales s, unnest(array[s.paid_credit_lot_id, s.bonus_credit_lot_id]) x where s.invoice_id = p_inv and x is not null
  union select issued_lot_id from invoice_credit_splits where invoice_id = p_inv and issued_lot_id is not null
  union select lot_id from credit_package_progress_lots where invoice_id = p_inv $f$;
-- The invoice's lot family (the critic's 6): every lot its records name and
-- each Move's two lots (from the Move's ledger rows), the lots each replaced
-- and every lot reissued from any of them.
create function pg_temp.t462_family(p_inv uuid) returns setof uuid language sql as $f$
  with recursive seed as (
    select x as id from pg_temp.t462_named(p_inv) x
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
create function pg_temp.t462_behind(p_inv uuid) returns setof uuid language sql as $f$
  with recursive c(id, n) as (
    select lot_id, 0 from invoice_benefit_values where invoice_id = p_inv and lot_id is not null
    union select p.id, c.n + 1 from c join customer_credit_lots l on l.id = c.id
            join customer_credit_lots p on p.id = l.reassigned_from_lot_id
             and (p.source_type, p.source_record_id) is not distinct from (l.source_type, l.source_record_id)
           where c.n < 12)
  select distinct id from c $f$;
-- How many lots back a lot's chain goes (reassigned_from_lot_id).
create function pg_temp.t462_depth(p_lot uuid) returns int language sql as $f$
  with recursive c(id, n) as (select p_lot, 0 union all
    select l.reassigned_from_lot_id, c.n + 1 from c join customer_credit_lots l on l.id = c.id
     where l.reassigned_from_lot_id is not null and c.n < 40)
  select max(n) from c $f$;
-- A lot's balance by its ledger rows: credit added (grants, increases,
-- credit returned: the 'reverse' rows that put credit back, as the
-- statement reads them, and 'rental_late_fee'), less credit taken (uses,
-- decreases, real reversals).
create function pg_temp.t462_ledger_balance(p_lot uuid) returns numeric language sql as $f$
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
create function pg_temp.t462_invariants(p_inv uuid) returns text language plpgsql as $f$
declare probs text := ''; l record; root record; v uuid; st text := (select status::text from invoices where id = p_inv);
begin
  for l in select cl.* from customer_credit_lots cl where cl.id in (select pg_temp.t462_family(p_inv)) loop
    if l.remaining_amount > 0 and l.id not in (select pg_temp.t462_named(p_inv)) then
      probs := probs || format(' S$%s on a lot no record names (%s);', l.remaining_amount, (select full_name from customers where id = l.customer_id)); end if;
    if l.id not in (select pg_temp.t462_named(p_inv)) and l.id not in (select pg_temp.t462_behind(p_inv))
       and (exists (select 1 from invoice_line_credit_allocations a where a.lot_id = l.id and a.amount > coalesce(a.reversed_amount, 0))
            or exists (select 1 from special_credit_allocations s where s.lot_id = l.id and s.amount > coalesce(s.reversed_amount, 0))) then
      probs := probs || ' a sale paid from a lot no record names can still be refunded (its credit would stay there);'; end if;
    if pg_temp.t462_ledger_balance(l.id) <> l.remaining_amount then
      probs := probs || format(' lot holds %s, its ledger %s;', l.remaining_amount, pg_temp.t462_ledger_balance(l.id)); end if;
    if pg_temp.t462_depth(l.id) > 12 then probs := probs || format(' chain %s lots deep;', pg_temp.t462_depth(l.id)); end if;
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
  if st = 'refunded' and (select coalesce(sum(remaining_amount), 0) from customer_credit_lots where id in (select pg_temp.t462_family(p_inv))) > 0 then
    probs := probs || format(' refunded, but S$%s of its credit is still held;',
      (select sum(remaining_amount) from customer_credit_lots where id in (select pg_temp.t462_family(p_inv)))); end if;
  return probs;
end $f$;
-- Credit left on the invoice's family once Cancel has run, the Cancel undone
-- (0 when Cancel takes it all back from whoever holds it); null when the
-- invoice cannot be cancelled now, -1 when Cancel is refused.
create function pg_temp.t462_cancel_left(p_inv uuid) returns numeric language plpgsql as $f$
declare v numeric;
begin
  if (select status::text from invoices where id = p_inv) not in ('paid', 'partially_paid', 'unpaid') then return null; end if;
  begin
    perform cancel_invoice_recorded(p_inv, 'T462 probe', gen_random_uuid());
    perform pg_temp.t462_commit();
    v := (select coalesce(sum(remaining_amount), 0) from customer_credit_lots where id in (select pg_temp.t462_family(p_inv)));
    raise exception using errcode = 'P0462', message = v::text;
  exception when sqlstate 'P0462' then return sqlerrm::numeric;
            when others then return -1;
  end;
end $f$;
create function pg_temp.t462_codes(p_inv uuid, p_action text) returns text language plpgsql as $f$
begin
  return (select coalesce(string_agg(o->>'code', ',' order by o->>'code'), '-')
            from jsonb_array_elements(coalesce(invoice_action_plan(p_inv, p_action, '[]')->'overrides_required', '[]')) o);
exception when others then return 'ERR';
end $f$;
create function pg_temp.t462_due(p_inv uuid, p_action text) returns numeric language plpgsql as $f$
begin
  return (invoice_action_plan(p_inv, p_action, '[]')->>case when p_action = 'cancel' then 'refund_due' else 'refund_amount' end)::numeric;
exception when others then return null;
end $f$;

-- ── The cases ───────────────────────────────────────────────────────────────
-- A case is a list of steps, each one app call (and its commit), on the
-- case's own customers (A the buyer, B and C later customers, K and K2
-- records a merge keeps, F and G friends an Owner moved credit to). A step
-- refused stops the case, the refusal recorded. Steps:
--   sale R kinds [first]  the invoice (cp, cpb, pbv, v; part-paid: first)
--   pay                   Record Payment of what is outstanding
--   back N amt|all [R]    refund by line of line N (R: the benefit R holds)
--   move N R [kind] [store2]  an Owner's Move of line N's credit (or voucher)
--   cancel, reopen, wait  Cancel; Reopen; Cancel + every line paid back + Reopen
--   refundall             the guided Refund in full, recorded
--   change R [keep] [store2]  the customer change ('transfer' unless keep)
--   merge KEEP DUP        a customer merge
--   spend R [n] [svc5]    a session invoice (n lines) for R paid from credit
--   unspend Sn            that session cancelled and its refund recorded
--   fix Sn date|amount|cash   the Finance panel's Correct payment on it
--   sale2 R               another S$100 package for R (paid)
--   delete R              delete_customer
--   special R kind amt / unspecial Dn  special-document credit and its refund
--   reverse R             an Owner's reversal of R's largest lot
--   repair                repair_credit_package_progress_lots()
create function pg_temp.t462_role(p_pre text, p_r text) returns uuid language plpgsql as $f$
begin
  return coalesce(pg_temp.t462_id(p_pre || '/' || p_r), pg_temp.t462_cust(p_pre || '/' || p_r));
end $f$;
-- One step of a case (one app call, then what its commit does). Null, or
-- the step and the refusal; a refused step changes nothing.
create function pg_temp.t462_step(p_pre text, p_st text) returns text language plpgsql as $f$
declare w text[] := regexp_split_to_array(btrim(p_st), '\s+'); inv uuid := pg_temp.t462_id(p_pre || '/inv'); x uuid; i int; n int;
begin
  case w[1]
  when 'sale' then
    perform pg_temp.t462_put(p_pre || '/inv', pg_temp.t462_sale(pg_temp.t462_role(p_pre, w[2]), string_to_array(w[3], ','), w[4]::numeric));
  when 'sale2' then
    perform pg_temp.t462_put(p_pre || '/inv2', pg_temp.t462_sale(pg_temp.t462_role(p_pre, w[2]), array['cp']));
  when 'pay' then perform pg_temp.t462_pay(inv);
  when 'back' then
    perform pg_temp.t462_back(inv, w[2]::int, case when w[3] = 'all' then null else w[3]::numeric end,
                              case when w[4] is not null then pg_temp.t462_role(p_pre, w[4]) end);
  when 'move' then
    perform pg_temp.t462_move(inv, w[2]::int, pg_temp.t462_role(p_pre, w[3]),
      case when w[4] in ('bonus', 'voucher') then w[4] else 'paid' end,
      case when 'store2' = any (w) then 'store2' end);
  when 'cancel' then perform cancel_invoice_recorded(inv, 'T462 cancel', gen_random_uuid());
  when 'reopen' then perform reopen_invoice(inv, 'T462 reopen', gen_random_uuid());
  when 'wait' then
    perform cancel_invoice_recorded(inv, 'T462 cancel', gen_random_uuid());
    for i in 1 .. (select count(*)::int from invoice_items where invoice_id = inv) loop
      perform pg_temp.t462_back(inv, i);
    end loop;
    perform reopen_invoice(inv, 'T462 reopen', gen_random_uuid());
  when 'refundall' then perform pg_temp.t462_guided(inv, 'refund_full');
  when 'change' then
    perform pg_temp.t462_change(inv, pg_temp.t462_role(p_pre, w[2]), case when 'keep' = any (w) then 'keep' else 'transfer' end,
                                case when 'store2' = any (w) then 'store2' end);
  when 'merge' then perform pg_temp.t462_merge(pg_temp.t462_role(p_pre, w[2]), pg_temp.t462_role(p_pre, w[3]));
  when 'spend' then
    n := (select count(*) from t462 where k ~ ('^' || p_pre || '/S[0-9]+$')) + 1;
    perform pg_temp.t462_put(p_pre || '/S' || n,
      pg_temp.t462_spend(pg_temp.t462_role(p_pre, w[2]), coalesce(w[3]::int, 1), coalesce(w[4], 'svc')));
  when 'unspend' then perform pg_temp.t462_unspend(pg_temp.t462_id(p_pre || '/' || w[2]));
  when 'fix' then perform pg_temp.t462_fix(pg_temp.t462_id(p_pre || '/' || w[2]), w[3]);
  when 'delete' then
    x := pg_temp.t462_role(p_pre, w[2]);
    perform delete_customer(x, (select full_name from customers where id = x), 'T462 delete');
  when 'special' then
    n := (select count(*) from t462 where k ~ ('^' || p_pre || '/D[0-9]+$')) + 1; x := gen_random_uuid();
    perform pg_temp.t462_put(p_pre || '/D' || n, x);
    perform pg_temp.t462_put(p_pre || '/D' || n || '/kind:' || w[3], null);
    perform pg_temp.t462_special(pg_temp.t462_role(p_pre, w[2]), w[3], x, w[4]::numeric);
  when 'unspecial' then
    perform refund_special_credit((select split_part(k, 'kind:', 2) from t462 where k like p_pre || '/' || w[2] || '/kind:%'),
                                  pg_temp.t462_id(p_pre || '/' || w[2]));
  when 'reverse' then
    x := pg_temp.t462_role(p_pre, w[2]);
    perform reverse_credit_lot((select id from customer_credit_lots where customer_id = x and remaining_amount > 0
                                 order by remaining_amount desc, id limit 1), 'T462 reversal');
  when 'repair' then perform repair_credit_package_progress_lots();
  else raise exception 'T462: unknown step %', p_st;
  end case;
  perform pg_temp.t462_commit();
  return null;
exception when others then
  return btrim(p_st) || ': ' || sqlerrm;
end $f$;
-- What a case ends with: the invoice's status and money, who holds what
-- (credit, '/n' held vouchers), the plans' codes and refund due (Cancel's
-- refund due; Refund in full's amount), the refusal that stopped it, what is
-- wrong with its credit, and the credit Cancel would leave behind.
create function pg_temp.t462_outcome(p_pre text, p_err text) returns jsonb language sql as $f$
  select jsonb_build_object(
    'status', (select status::text from invoices where id = i.id),
    'net', invoice_net_received(i.id),
    'holds', (select jsonb_object_agg(split_part(t.k, '/', 3),
                (select coalesce(sum(l.remaining_amount), 0) from customer_credit_lots l where l.customer_id = t.id)::numeric(12,2)::text
                || coalesce('/' || nullif((select sum(v.quantity) from customer_reward_vouchers v where v.customer_id = t.id and v.status = 'held'), 0)::text, ''))
              from t462 t where t.k like p_pre || '/%' and split_part(t.k, '/', 4) = ''
                and split_part(t.k, '/', 3) !~ '^(inv|inv2|S[0-9]+|D[0-9]+|err)$'),
    'cancel', pg_temp.t462_codes(i.id, 'cancel'),
    'due', pg_temp.t462_due(i.id, 'cancel'),
    'refund', pg_temp.t462_codes(i.id, 'refund_full'),
    'rdue', pg_temp.t462_due(i.id, 'refund_full'),
    'error', p_err,
    'invariants', pg_temp.t462_invariants(i.id),
    'cancel_left', pg_temp.t462_cancel_left(i.id))
    from (select pg_temp.t462_id(p_pre || '/inv') as id) i $f$;
-- A case's steps p_from to p_to (all by default), stopping at a refusal;
-- with p_to null, its outcome (kept in t462_res under p_phase).
create temp table t462_err(pre text primary key, err text);
create function pg_temp.t462_run(p_phase text, p_case text, p_steps text, p_from int default 1, p_to int default null)
  returns jsonb language plpgsql as $f$
declare v_pre text := p_phase || '/' || p_case; st text[] := string_to_array(p_steps, ';'); i int; v_err text; v_out jsonb;
begin
  v_err := (select e.err from t462_err e where e.pre = v_pre);
  for i in p_from .. least(coalesce(p_to, cardinality(st)), cardinality(st)) loop
    exit when v_err is not null;
    continue when btrim(st[i]) = '';
    v_err := pg_temp.t462_step(v_pre, st[i]);
  end loop;
  insert into t462_err values (v_pre, v_err) on conflict (pre) do update set err = excluded.err;
  if p_to is not null then return null; end if;
  v_out := pg_temp.t462_outcome(v_pre, v_err);
  insert into t462_res values (p_phase, p_case, v_out) on conflict (phase, k) do update set v = excluded.v;
  return v_out;
end $f$;

-- Whether an outcome has what is expected: each key equal ('holds' as a
-- containment of who holds what), a key ending in '~' as a LIKE pattern of
-- that key's text.
create function pg_temp.t462_meets(p_out jsonb, p_exp jsonb) returns boolean language sql as $f$
  select coalesce(bool_and(case
           when e.key like '%~' then coalesce(p_out->>left(e.key, -1), '') like (e.value #>> '{}')
           when e.key = 'holds' then coalesce(p_out->'holds', '{}') @> e.value
           when jsonb_typeof(e.value) = 'number' then (p_out->>e.key)::numeric = (e.value #>> '{}')::numeric
           else (p_out->e.key) is not distinct from e.value end), true)
    from jsonb_each(p_exp) e $f$;
-- What differs between an outcome and what is expected (for the FAIL line).
create function pg_temp.t462_diff(p_out jsonb, p_exp jsonb) returns text language sql as $f$
  select string_agg(e.key || ': wanted ' || e.value::text || ', got ' || coalesce(p_out->left(e.key, case when e.key like '%~' then -1 else 1000 end), 'null')::text, '; ')
    from jsonb_each(p_exp) e where not pg_temp.t462_meets(p_out, jsonb_build_object(e.key, e.value)) $f$;

-- The cases: (k, kind, steps, what 462 gives). kind: 'fixed' (before 462 it
-- ends otherwise: the fault is reproduced first), 'control' (the same with
-- and without 462), 'new' (only after 462). The expected outcome lists who
-- holds what (credit, '/n' held vouchers), the cancel plan's codes and
-- refund due, and so on; every case also checks the invariants and that
-- Cancel takes everything back from whoever holds it.
create temp table t462_cases(k text primary key, kind text not null, steps text not null, expect jsonb not null, ord serial);
insert into t462_cases(k, kind, steps, expect) values
-- 1 K5: reinstated credit stays with the old customer after a change.
('K5', 'fixed', 'sale A cp; back 1 40; move 1 F; cancel; reopen; change B; pay',
  '{"holds":{"A":"0.00","B":"40.00","F":"60.00"},"cancel":"-","due":100,"refund":"-","rdue":100}'),
('K5c', 'fixed', 'sale A cp; back 1 40; move 1 F; change B; cancel; reopen; pay',
  '{"holds":{"A":"0.00","B":"40.00","F":"60.00"},"cancel":"-","due":100}'),
('K5g', 'fixed', 'sale A cp; back 1 40; move 1 F; refundall; reopen; change B; pay',
  '{"holds":{"A":"0.00","B":"40.00","F":"60.00"},"cancel":"-","due":100}'),
('K5s', 'fixed', 'sale A cp; back 1 40; move 1 F; cancel; reopen; change B; pay; spend A',
  '{"holds":{"A":"0.00","B":"40.00","F":"60.00"},"cancel":"-","due":100,"error~":"spend A: Only 0 of the requested 20.00 could be funded%"}'),
('K5k', 'fixed', 'sale A cp; back 1 40; move 1 F; cancel; reopen; change B; pay; merge K A',
  '{"holds":{"A":"0.00","B":"40.00","F":"60.00","K":"0.00"},"cancel":"-","due":100}'),
('L4', 'fixed', 'sale A cp 40; pay; back 1 30; move 1 F; cancel; reopen; change B; pay; merge K B',
  '{"holds":{"A":"0.00","B":"0.00","F":"30.00","K":"70.00"},"cancel":"-","due":100}'),
-- 2 K5b / X9b / M7c: the change was refused on a moved-on lot.
('K5b', 'fixed', 'sale A cp; back 1 40; move 1 F; cancel; reopen; pay; change B',
  '{"holds":{"A":"0.00","B":"40.00","F":"60.00"},"cancel":"-","due":100}'),
('X9b', 'fixed', 'sale A cpb; back 1 40; change B; move 1 F; cancel; reopen; pay; change C',
  '{"holds":{"A":"0.00","B":"0.00","C":"54.00","F":"56.00"},"cancel":"-","due":100}'),
('M7c', 'fixed', 'sale A cp; back 1 40; merge K A; move 1 F; cancel; reopen; pay; change B',
  '{"holds":{"A":"0.00","B":"40.00","F":"60.00","K":"0.00"},"cancel":"-","due":100}'),
-- 3 K6 / K6b / K6c: reinstated credit went to the retired record.
('K6', 'fixed', 'sale A cp; back 1 40; move 1 F; cancel; reopen; merge K A; pay',
  '{"holds":{"A":"0.00","F":"60.00","K":"40.00"},"cancel":"-","due":100}'),
('K6b', 'fixed', 'sale A cp; back 1 40; move 1 F; merge K A; cancel; reopen; pay',
  '{"holds":{"A":"0.00","F":"60.00","K":"40.00"},"cancel":"-","due":100}'),
('K6c', 'fixed', 'sale A cp; back 1 40; move 1 F; cancel; reopen; merge F A; pay',
  '{"holds":{"A":"0.00","F":"100.00"},"cancel":"-","due":100}'),
-- 4 K9 family: a merge after the reinstatement moved it without its records.
('K9', 'fixed', 'sale A cp; back 1 40; move 1 F; cancel; reopen; pay; merge K A',
  '{"holds":{"A":"0.00","F":"60.00","K":"40.00"},"cancel":"-","due":100,"refund":"-","rdue":100}'),
('K9r', 'fixed', 'sale A cp; back 1 40; move 1 F; cancel; reopen; pay; merge K A; back 1 all',
  '{"holds":{"A":"0.00","F":"0.00","K":"0.00"},"net":0}'),
('K9b', 'fixed', 'sale A cp; back 1 40; move 1 F; cancel; reopen; pay; merge K A; change B',
  '{"holds":{"A":"0.00","B":"40.00","F":"60.00","K":"0.00"},"cancel":"-","due":100}'),
('M7b', 'fixed', 'sale A cp; back 1 40; merge K A; move 1 F; cancel; reopen; pay; merge K2 K',
  '{"holds":{"A":"0.00","F":"60.00","K":"0.00","K2":"40.00"},"cancel":"-","due":100}'),
('X9c', 'fixed', 'sale A cpb; back 1 40; change B; move 1 F; cancel; reopen; pay; merge K B',
  '{"holds":{"A":"0.00","B":"0.00","F":"56.00","K":"54.00"},"cancel":"-","due":100}'),
-- 5 M7: a merge chain while the reopening waits.
('M7', 'fixed', 'sale A cp; back 1 40; merge K A; move 1 F; cancel; reopen; merge K2 K; pay',
  '{"holds":{"A":"0.00","F":"60.00","K":"0.00","K2":"40.00"},"cancel":"-","due":100}'),
-- 6, 7 X10 to X13: the benefits left the holder of the named lot after the Move.
('X10', 'fixed', 'sale A cpb; back 1 40; change B; move 1 F; merge K B; cancel; reopen; pay',
  '{"holds":{"A":"0.00","B":"0.00","F":"56.00","K":"54.00"},"cancel":"-","due":100}'),
('X13', 'fixed', 'sale A cpb; back 1 40; change B; move 1 F; cancel; reopen; merge K B; pay',
  '{"holds":{"A":"0.00","B":"0.00","F":"56.00","K":"54.00"},"cancel":"-","due":100}'),
('X11', 'fixed', 'sale A cpb; back 1 40; change B; move 1 F; change C; cancel; reopen; pay',
  '{"holds":{"A":"0.00","B":"0.00","C":"54.00","F":"56.00"},"cancel":"-","due":100}'),
('X12', 'fixed', 'sale A cpb; back 1 40; change B; move 1 F; cancel; reopen; change C; pay',
  '{"holds":{"A":"0.00","B":"0.00","C":"54.00","F":"56.00"},"cancel":"-","due":100}'),
-- 8 S1 / S2 / R4: credit a refunded sale gave back on a moved-on lot blocked a change.
('S1', 'fixed', 'sale A cp; spend A; move 1 F; unspend S1; change B',
  '{"holds":{"A":"0.00","B":"20.00","F":"80.00"},"cancel":"-","due":100}'),
('S2', 'fixed', 'sale A cp; back 1 40; merge K A; spend K; move 1 F; unspend S1; change B',
  '{"holds":{"A":"0.00","B":"20.00","F":"40.00","K":"0.00"},"cancel":"-","due":60}'),
('R4', 'fixed', 'sale A cpb; back 1 20; change B; spend B; move 1 F; cancel; reopen; pay; unspend S1; change C',
  '{"holds":{"A":"0.00","B":"0.00","C":"52.00","F":"58.00"},"cancel":"-","due":100}'),
-- P3b: a lot a reopening's payment reissued to the new customer after a
-- session was paid from the package read as untouched (it was granted only
-- what was left), so a second change moved the S$80 as if nothing had been
-- spent; now it blocks as "Partly spent" (461's rule for real spending).
('R3c', 'fixed', 'sale A cp; spend A; cancel; back 1 40; reopen; change B; pay; change C',
  '{"holds":{"A":"0.00","B":"80.00"},"error~":"change C: These benefits have already been used and cannot move with the invoice: Paid credit 80.00 (Partly spent).%"}'),
-- 9 S4 / S4m (the Owner, 24 Oct 2026: "B, the package's holder now").
('S4', 'fixed', 'sale A cp; spend A; move 1 F; change B; unspend S1',
  '{"holds":{"A":"0.00","B":"20.00","F":"80.00"},"cancel":"-","due":100}'),
('S4m', 'fixed', 'sale A cp; back 1 40; spend A; move 1 F; change B; unspend S1',
  '{"holds":{"A":"0.00","B":"20.00","F":"40.00"},"cancel":"-","due":60}'),
-- D1 (the critic's): S4 with the session's wallet payment corrected instead.
('D1d', 'control', 'sale A cp; spend A; move 1 F; change B; fix S1 date',
  '{"holds":{"A":"0.00","B":"0.00","F":"80.00"},"error":null}'),
('D1a', 'fixed', 'sale A cp; spend A; move 1 F; change B; fix S1 amount',
  '{"holds":{"A":"0.00","B":"5.00","F":"80.00"},"error":null}'),
('D1c', 'fixed', 'sale A cp; spend A; move 1 F; change B; fix S1 cash',
  '{"holds":{"A":"0.00","B":"20.00","F":"80.00"},"cancel":"-","due":100,"error":null}'),
-- G1b (no Move): a change while the reopening waits, then the session refunded.
('G1b', 'fixed', 'sale A cp; spend A; cancel; back 1 40; reopen; change B; pay; unspend S1',
  '{"holds":{"A":"0.00","B":"100.00"},"cancel":"-","due":100}'),
('G1c', 'fixed', 'sale A cp; back 1 40; spend A; cancel; reopen; change B; pay; unspend S1',
  '{"holds":{"A":"0.00","B":"100.00"},"cancel":"-","due":100}'),
('G1d', 'control', 'sale A cp; back 1 40; spend A; cancel; reopen; change B; pay; fix S1 date',
  '{"holds":{"A":"0.00","B":"80.00"},"error":null}'),
('G1a', 'fixed', 'sale A cp; back 1 40; spend A; cancel; reopen; change B; pay; fix S1 amount',
  '{"holds":{"A":"0.00","B":"85.00"},"error":null}'),
('G1x', 'fixed', 'sale A cp; back 1 40; spend A; cancel; reopen; change B; pay; fix S1 cash',
  '{"holds":{"A":"0.00","B":"100.00"},"cancel":"-","due":100,"error":null}'),
-- 13 lines refunded at once: one new lot, the chain stays short.
('L13', 'fixed', 'sale A cp; back 1 10; spend A 13 svc5; cancel; reopen; change B; pay; back 1 10; unspend S1',
  '{"holds":{"A":"0.00","B":"90.00"},"cancel":"-","due":90}'),
-- The deleted holder (the critic's 5): never credit on a deleted record.
('DH1', 'control', 'sale A cp; spend A; move 1 F; change B; delete B; unspend S1',
  '{"holds":{"A":"20.00","B":"0.00","F":"80.00"}}'),
('DH2', 'fixed', 'sale A cp; spend A; move 1 F; change B; change C keep; delete B; unspend S1',
  '{"holds":{"A":"0.00","B":"0.00","C":"20.00","F":"80.00"}}'),
-- 10 R1 / R1b / R2 / L3 / R5: the reopening was refused.
('R1', 'fixed', 'sale A cp; back 1 60; merge K A; move 1 F; cancel; reopen; pay',
  '{"holds":{"A":"0.00","F":"40.00","K":"60.00"},"cancel":"-","due":100}'),
('R1b', 'fixed', 'sale A cp; back 1 50; merge K A; move 1 F; cancel; reopen; pay',
  '{"holds":{"A":"0.00","F":"50.00","K":"50.00"},"cancel":"-","due":100}'),
('R2', 'fixed', 'sale A cpb; back 1 50; change B; move 1 F; cancel; reopen; pay',
  '{"holds":{"A":"0.00","B":"65.00","F":"45.00"},"cancel":"-","due":100}'),
('L3', 'fixed', 'sale A cp 40; pay; back 1 30; change B; move 1 F; cancel; reopen; pay',
  '{"holds":{"A":"0.00","B":"70.00","F":"30.00"},"cancel":"-","due":100}'),
('R5', 'fixed', 'sale A cp; back 1 60; merge K A; move 1 F; back 1 40 F; cancel; reopen; pay',
  '{"holds":{"A":"0.00","F":"40.00","K":"60.00"},"cancel":"-","due":100}'),
('R1y', 'fixed', 'sale A cp; back 1 60; merge K A; move 1 F; cancel; reopen; pay; change B; cancel; reopen; pay; refundall',
  '{"holds":{"A":"0.00","B":"0.00","F":"0.00","K":"0.00"},"net":0}'),
-- 11 R3 / R3b / S3: refused while lot credit paid for another sale.
('R3', 'fixed', 'sale A cpb; back 1 40; change B; spend B; move 1 F; cancel; reopen; pay',
  '{"holds":{"A":"0.00","B":"54.00","F":"36.00"},"cancel":"credit_used","due":81.82}'),
('R3b', 'fixed', 'sale A cp; back 1 40; merge K A; spend K; move 1 F; cancel; reopen; pay',
  '{"holds":{"A":"0.00","F":"40.00","K":"40.00"},"cancel":"credit_used","due":80}'),
('S3', 'fixed', 'sale A cp; back 1 40; merge K A; spend K; move 1 F; cancel; reopen; pay; unspend S1',
  '{"holds":{"A":"0.00","F":"40.00","K":"60.00"},"cancel":"-","due":100}'),
('S3w', 'fixed', 'sale A cp; back 1 40; merge K A; spend K; move 1 F; cancel; reopen; unspend S1; pay',
  '{"holds":{"A":"0.00","F":"40.00","K":"60.00"},"cancel":"-","due":100}'),
('R3n', 'fixed', 'sale A cp; back 1 40; merge K A; spend K; cancel; reopen; pay; unspend S1',
  '{"holds":{"A":"0.00","K":"100.00"},"cancel":"-","due":100}'),
-- 12 F3a: merged moved credit partly taken back could not be spent.
('F3a', 'fixed', 'sale A cp; move 1 F; back 1 30 F; merge K F; spend K',
  '{"holds":{"A":"0.00","F":"0.00","K":"50.00"},"cancel":"credit_used","due":50,"error":null}'),
-- 13 T1r: a Move to the same customer at another store, then a change
-- (462: the reinstated part follows; the moved part stays, 463's decision).
('T1r', 'fixed', 'sale A cp; back 1 40; move 1 A store2; change B; cancel; reopen; pay',
  '{"holds":{"A":"60.00","B":"40.00"},"cancel":"-","due":100}'),
-- The special documents' credit refunded (refund_special_credit), dormant.
('SS1', 'fixed', 'sale A cp; special A special_sale 20; move 1 F; change B; unspecial D1',
  '{"holds":{"A":"0.00","B":"20.00","F":"80.00"},"cancel":"-","due":100}'),
('SS2', 'fixed', 'sale A cp; special A rental 20; move 1 F; change B; unspecial D1',
  '{"holds":{"A":"0.00","B":"20.00","F":"80.00"},"cancel":"-","due":100}'),
('SS3', 'fixed', 'sale A cp; special A rental_late_fee 20; move 1 F; change B; unspecial D1',
  '{"holds":{"A":"0.00","B":"20.00","F":"80.00"},"cancel":"-","due":100}'),
-- The critics' review of 462 (24 Oct 2026). CW1 to W3: credit given back
-- while the package's invoice is cancelled or its reopening waits stays
-- where it went back (the reopening's records read the lots its
-- cancellation took from), and the payment that settles the reopening gives
-- it to the benefits' holder; a reserve released on the row the chain
-- leads to. Each then refunded in full, refunded by line, moved, changed,
-- cancelled: before, a stale reserve let Refund in full leave B credit, a
-- Move or a change be refused, a cancel hold back S$140 of S$100.
('CW1', 'control', 'sale A cp; spend A; cancel; back 1 40; reopen; change B; unspend S1; pay',
  '{"holds":{"A":"0.00","B":"100.00"},"cancel":"-","due":100}'),
('CW1r', 'control', 'sale A cp; spend A; cancel; back 1 40; reopen; change B; unspend S1; pay; refundall',
  '{"holds":{"A":"0.00","B":"0.00"},"status":"refunded","net":0}'),
('CW1m', 'control', 'sale A cp; spend A; cancel; back 1 40; reopen; change B; unspend S1; pay; move 1 G',
  '{"holds":{"A":"0.00","B":"0.00","G":"100.00"},"cancel":"-","due":100}'),
('CW1c', 'control', 'sale A cp; spend A; cancel; back 1 40; reopen; change B; unspend S1; pay; change C',
  '{"holds":{"A":"0.00","B":"0.00","C":"100.00"},"cancel":"-","due":100}'),
('CW1x', 'control', 'sale A cp; spend A; cancel; back 1 40; reopen; change B; unspend S1; pay; cancel',
  '{"holds":{"A":"0.00","B":"0.00"},"status":"cancelled"}'),
('CW3', 'control', 'sale A cp; spend A; cancel; back 1 40; reopen; change B; unspend S1; back 1 20; pay',
  '{"holds":{"A":"0.00","B":"80.00"},"net":80,"cancel":"-","due":80}'),
('CW3r', 'control', 'sale A cp; spend A; cancel; back 1 40; reopen; change B; unspend S1; back 1 20; pay; refundall',
  '{"holds":{"A":"0.00","B":"0.00"},"status":"refunded","net":0}'),
('X1p', 'fixed', 'sale A cp; spend A; cancel; back 1 40; reopen; change B; pay; cancel; unspend S1; reopen; pay',
  '{"holds":{"A":"0.00","B":"100.00"},"cancel":"-","due":100}'),
('X1', 'fixed', 'sale A cp; spend A; cancel; back 1 40; reopen; change B; pay; cancel; unspend S1; reopen; pay; refundall',
  '{"holds":{"A":"0.00","B":"0.00"},"status":"refunded","net":0}'),
('X2p', 'fixed', 'sale A cp; spend A; spend A; move 1 F; change B; unspend S1; cancel; unspend S2; reopen; pay',
  '{"holds":{"A":"0.00","B":"40.00","F":"60.00"},"cancel":"-","due":100}'),
('X2', 'control', 'sale A cp; spend A; spend A; move 1 F; change B; unspend S1; cancel; unspend S2; reopen; pay; refundall',
  '{"holds":{"A":"0.00","B":"0.00","F":"0.00"},"status":"refunded","net":0}'),
('X2m', 'control', 'sale A cp; spend A; spend A; move 1 F; change B; unspend S1; cancel; unspend S2; reopen; pay; move 1 G',
  '{"holds":{"A":"0.00","B":"0.00","F":"60.00","G":"40.00"},"cancel":"-","due":100}'),
('X2c', 'fixed', 'sale A cp; spend A; spend A; move 1 F; change B; unspend S1; cancel; unspend S2; reopen; pay; change C',
  '{"holds":{"A":"0.00","B":"0.00","C":"40.00","F":"60.00"},"cancel":"-","due":100,"error":null}'),
('W3p', 'control', 'sale A cp; back 1 40; spend A; cancel; reopen; change B; unspend S1; pay',
  '{"holds":{"A":"0.00","B":"100.00"},"cancel":"-","due":100}'),
('W3F', 'control', 'sale A cp; back 1 40; spend A; cancel; reopen; change B; unspend S1; pay; refundall',
  '{"holds":{"A":"0.00","B":"0.00"},"status":"refunded","net":0}'),
('W3l', 'control', 'sale A cp; back 1 40; spend A; cancel; reopen; change B; unspend S1; pay; back 1 all',
  '{"holds":{"A":"0.00","B":"0.00"},"status":"refunded","net":0}'),
('W3c', 'control', 'sale A cp; back 1 40; spend A; cancel; reopen; change B; unspend S1; pay; change C',
  '{"holds":{"A":"0.00","B":"0.00","C":"100.00"},"cancel":"-","due":100}'),
-- CH: many refunds, each its own commit, after a change (and a Move): the
-- chain stays short (the forwarder's untouched lot is taken over, not
-- extended), the moved credit keeps its origin and can be spent. CH3: the
-- holder spends between the refunds.
('CH1', 'fixed', 'sale A cp; spend A 1 svc5; spend A 1 svc5; spend A 1 svc5; spend A 1 svc5; spend A 1 svc5; spend A 1 svc5; spend A 1 svc5; spend A 1 svc5; spend A 1 svc5; spend A 1 svc5; spend A 1 svc5; spend A 1 svc5; spend A 1 svc5; spend A 1 svc5; spend A 1 svc5; spend A 1 svc5; spend A 1 svc5; spend A 1 svc5; spend A 1 svc5; spend A 1 svc5; change B; unspend S1; unspend S2; unspend S3; unspend S4; unspend S5; unspend S6; unspend S7; unspend S8; unspend S9; unspend S10; unspend S11; unspend S12; unspend S13; unspend S14',
  '{"holds":{"A":"0.00","B":"70.00"},"cancel":"credit_used","due":70}'),
('CH2', 'fixed', 'sale A cp; spend A 1 svc5; spend A 1 svc5; spend A 1 svc5; spend A 1 svc5; spend A 1 svc5; spend A 1 svc5; spend A 1 svc5; spend A 1 svc5; spend A 1 svc5; spend A 1 svc5; spend A 1 svc5; spend A 1 svc5; spend A 1 svc5; move 1 F; change B; unspend S1; unspend S2; unspend S3; unspend S4; unspend S5; unspend S6; unspend S7; unspend S8; unspend S9; unspend S10; unspend S11; unspend S12; unspend S13; spend F',
  '{"holds":{"A":"0.00","B":"65.00","F":"15.00"},"cancel":"credit_used","due":80,"error":null}'),
('CH2b', 'fixed', 'sale A cp; spend A 1 svc5; spend A 1 svc5; spend A 1 svc5; spend A 1 svc5; spend A 1 svc5; spend A 1 svc5; spend A 1 svc5; spend A 1 svc5; spend A 1 svc5; spend A 1 svc5; spend A 1 svc5; spend A 1 svc5; spend A 1 svc5; spend A 1 svc5; move 1 F; change B; unspend S1; unspend S2; unspend S3; unspend S4; unspend S5; unspend S6; unspend S7; unspend S8; unspend S9; unspend S10; unspend S11; unspend S12; unspend S13; unspend S14; spend F',
  '{"holds":{"A":"0.00","B":"70.00","F":"10.00"},"cancel":"credit_used","due":80,"error":null}'),
('CH3', 'fixed', 'sale A cp; spend A 1 svc5; spend A 1 svc5; spend A 1 svc5; spend A 1 svc5; spend A 1 svc5; spend A 1 svc5; spend A 1 svc5; spend A 1 svc5; spend A 1 svc5; spend A 1 svc5; spend A 1 svc5; spend A 1 svc5; spend A 1 svc5; spend A 1 svc5; spend A 1 svc5; spend A 1 svc5; spend A 1 svc5; spend A 1 svc5; spend A 1 svc5; spend A 1 svc5; change B; unspend S1; spend B 1 svc5; unspend S2; spend B 1 svc5; unspend S3; unspend S4',
  '{"holds":{"A":"0.00","B":"10.00"},"cancel":"credit_used","due":10,"error":null}'),
-- DH3: the benefits' holder deleted after a reissued lot of its was
-- emptied: the credit goes to the customer it went back to (live), on a lot
-- the records name. DH3b: the holder spent it instead.
('DH3', 'control', 'sale A cp; spend A; spend A; move 1 F; change B; unspend S1; move 1 G; delete B; unspend S2',
  '{"holds":{"A":"20.00","B":"0.00","F":"60.00","G":"20.00"},"cancel":"-","due":100}'),
('DH3b', 'fixed', 'sale A cp; spend A; spend A; move 1 F; change B; unspend S1; spend B; delete B; unspend S2',
  '{"holds":{"A":"20.00","B":"0.00","F":"60.00"},"cancel":"credit_used","due":80,"error":null}'),
-- K9s: K9's merge, then the kept record spends the reissued lot to S$0 and
-- that session is refunded (before 462 the install refuses this state).
('K9s', 'fixed', 'sale A cp; back 1 40; move 1 F; cancel; reopen; pay; merge K A; spend K 2; unspend S1',
  '{"holds":{"A":"0.00","F":"60.00","K":"40.00"},"cancel":"-","due":100}'),
-- Controls: the same with and without 462.
('K8', 'control', 'sale A cp; back 1 40; move 1 F; cancel; reopen; pay',
  '{"holds":{"A":"40.00","F":"60.00"},"cancel":"-","due":100}'),
('K5d', 'control', 'sale A cp; back 1 40; move 1 F; cancel; reopen; pay; change B keep',
  '{"holds":{"A":"40.00","B":"0.00","F":"60.00"},"cancel":"-","due":100}'),
('K1', 'control', 'sale A cpb,v; wait; change B keep; pay',
  '{"holds":{"A":"110.00/2","B":"0.00"}}'),
('K3', 'control', 'sale A cpb; back 1 40; cancel; reopen; pay',
  '{"holds":{"A":"110.00"},"cancel":"-","due":100}'),
('X3', 'control', 'sale A cpb,v; wait; change B; pay',
  '{"holds":{"A":"0.00","B":"110.00/2"}}'),
('M1', 'control', 'sale A cp; back 1 40; merge K A; cancel; reopen; pay',
  '{"holds":{"A":"0.00","K":"100.00"},"cancel":"-","due":100}'),
('M8a', 'control', 'sale A cp; move 1 F; move 1 G',
  '{"holds":{"A":"0.00","F":"0.00","G":"100.00"},"cancel":"-","due":100}'),
('M8b', 'control', 'sale A cp; back 1 40; move 1 F; move 1 G',
  '{"holds":{"A":"0.00","F":"0.00","G":"60.00"},"cancel":"-","due":60}'),
('F1', 'control', 'sale A cp; move 1 F; merge K F; spend K',
  '{"holds":{"A":"0.00","F":"0.00","K":"80.00"},"error":null}'),
('F2', 'control', 'sale A cp; move 1 F; change B',
  '{"holds":{"A":"0.00","B":"0.00","F":"100.00"},"cancel":"-","due":100}'),
('L1', 'control', 'sale A cp 40; pay; change B',
  '{"holds":{"A":"0.00","B":"100.00"},"cancel":"-","due":100}'),
('L2', 'control', 'sale A cp 40; change B; pay',
  '{"holds":{"A":"0.00","B":"100.00"},"cancel":"-","due":100}'),
('L5', 'control', 'sale A cp; spend A; change B',
  '{"holds":{"A":"80.00"},"error~":"change B: These benefits have already been used and cannot move with the invoice: Paid credit 80.00 (Partly spent).%"}'),
('S1k', 'control', 'sale A cp; spend A; move 1 F; unspend S1; change B keep',
  '{"holds":{"A":"20.00","B":"0.00","F":"80.00"},"cancel":"-","due":100}'),
('S1m', 'control', 'sale A cp; spend A; move 1 F; unspend S1; merge K A',
  '{"holds":{"A":"20.00","F":"80.00"},"error~":"merge K A: Credit allocations cannot be changed once recorded%"}'),
('S3zd', 'control', 'sale A cp; spend A; cancel; unspend S1; back 1 all',
  '{"holds":{"A":"0.00"}}'),
('T1', 'control', 'sale A cp; move 1 A store2; change B',
  '{"holds":{"A":"100.00","B":"0.00"}}'),
('T2', 'control', 'sale A v; move 1 A voucher store2; change B',
  '{"holds":{"A":"0.00/2","B":"0.00"}}'),
('T2c', 'control', 'sale A v; move 1 A voucher store2; change B; cancel; reopen',
  '{"holds":{"A":"0.00/2","B":"0.00"}}'),
('V3', 'control', 'sale A pbv; change B',
  '{"holds":{"A":"0.00/2","B":"140.00"}}'),
('V4', 'control', 'sale A pbv; wait; change B; pay',
  '{"holds":{"A":"0.00/2","B":"140.00"}}'),
('V6', 'control', 'sale A pbv; merge K A',
  '{"holds":{"A":"0.00","K":"140.00/2"}}'),
('V1w', 'control', 'sale A v; move 1 F voucher; change B',
  '{"holds":{"A":"0.00","B":"0.00","F":"0.00/2"}}'),
-- The sources the trigger leaves alone: the 446 pair (a refund while a
-- reopening waits), a reversal, the provenance repair.
('PX1', 'control', 'sale A cp; back 1 40; cancel; reopen; change B; back 1 20; pay',
  '{"error":null}'),
('PX2', 'control', 'sale A cp; spend A; move 1 F; change B; reverse F',
  '{"holds":{"A":"0.00","B":"0.00","F":"0.00"},"error":null}'),
('PX3', 'control', 'sale A cp; spend A; move 1 F; change B; repair',
  '{"holds":{"A":"0.00","B":"0.00","F":"80.00"},"error":null}');

-- Where 463 is in (the Owner's decisions 2 and 3 of 24 Oct 2026): a Move to
-- the same customer at another store is taken along by a change, and a
-- Premium Bundle's vouchers follow a change. These cases end so.
create temp table t462_case463(k text primary key, expect jsonb not null);
insert into t462_case463 values
('T1r', '{"holds":{"A":"0.00","B":"100.00"},"cancel":"-","due":100}'),
('T1', '{"holds":{"A":"0.00","B":"100.00"}}'),
('T2', '{"holds":{"A":"0.00","B":"0.00/2"}}'),
('T2c', '{"holds":{"A":"0.00","B":"0.00/2"}}'),
('V3', '{"holds":{"A":"0.00","B":"140.00/2"}}'),
('V4', '{"holds":{"A":"0.00","B":"140.00/2"}}');
create function pg_temp.t462_expect(p_k text) returns jsonb language sql as $f$
  select coalesce(case when pg_temp.t462_463_in() then (select expect from t462_case463 where k = p_k) end,
                  (select expect from t462_cases where k = p_k)) $f$;

-- The read-only query in 462's header (the same text): what 462 would
-- refuse to install over, and what it reads differently.
create function pg_temp.t462_header_query() returns table(reason text, invoice_no text, n bigint) language sql as $hq$
with recursive
named(invoice_id, id) as (
  select b.invoice_id, b.lot_id from public.invoice_benefit_values b where b.lot_id is not null
  union select s.invoice_id, x from public.credit_package_sales s, unnest(array[s.credit_lot_id, s.bonus_credit_lot_id]) x where x is not null
  union select s.invoice_id, x from public.premium_bundle_sales s, unnest(array[s.paid_credit_lot_id, s.bonus_credit_lot_id]) x where x is not null
  union select c.invoice_id, c.issued_lot_id from public.invoice_credit_splits c where c.issued_lot_id is not null
  union select p.invoice_id, p.lot_id from public.credit_package_progress_lots p),
seed(invoice_id, id) as (
  select invoice_id, id from named
  union select t.invoice_id, e.lot_id from public.invoice_benefit_transfers t
          join public.customer_credit_ledger e on e.source_record_id = t.id
         where e.source_type in ('invoice_benefit_transfer_out', 'invoice_benefit_transfer_in')),
up(invoice_id, id, depth) as (
  select invoice_id, id, 0 from seed
  union select up.invoice_id, l.reassigned_from_lot_id, up.depth + 1 from up join public.customer_credit_lots l on l.id = up.id
         where l.reassigned_from_lot_id is not null and up.depth < 30),
down(invoice_id, id, depth) as (
  select invoice_id, id, 0 from up
  union select down.invoice_id, l.id, down.depth + 1 from down join public.customer_credit_lots l on l.reassigned_from_lot_id = down.id
         where down.depth < 30),
behind(invoice_id, id, depth) as (
  select b.invoice_id, b.lot_id, 0 from public.invoice_benefit_values b where b.lot_id is not null
  union select behind.invoice_id, p.id, behind.depth + 1 from behind join public.customer_credit_lots l on l.id = behind.id
          join public.customer_credit_lots p on p.id = l.reassigned_from_lot_id
           and (p.source_type, p.source_record_id) is not distinct from (l.source_type, l.source_record_id)
         where behind.depth < 12),
chain(start, id, depth) as (
  select l.id, l.id, 0 from public.customer_credit_lots l where l.reassigned_from_lot_id is not null
  union all
  select chain.start, l.reassigned_from_lot_id, chain.depth + 1 from chain join public.customer_credit_lots l on l.id = chain.id
   where l.reassigned_from_lot_id is not null and chain.depth < 13),
holder as (
  select b.id as benefit_id, b.invoice_id, l.id as lot_id, l.customer_id, l.remaining_amount, l.status,
         exists (select 1 from public.invoice_benefit_transfers t where t.replacement_benefit_id = b.id) as moved_in,
         coalesce((select c.id from public.customers c where c.deleted_at is null and c.id = public.invoice_benefits_holder(b.invoice_id, l.customer_id,
                     case when exists (select 1 from public.invoice_benefit_transfers t where t.replacement_benefit_id = b.id)
                          then 'infinity'::timestamptz else l.created_at end)),
                  (select c.id from public.invoices iv join public.customers c on c.id = iv.customer_id and c.deleted_at is null where iv.id = b.invoice_id),
                  (select c.id from public.customers c where c.id = l.customer_id and c.deleted_at is null)) as live_holder
    from public.invoice_benefit_values b join public.customer_credit_lots l on l.id = b.lot_id),
found(reason, invoice_id, n) as (
  -- 462 refuses to install (each needs a decision first; a data fix):
  select '1 refuses: an Owner''s Move of credit without exactly its two ledger rows', t.invoice_id, count(*)
    from public.invoice_benefit_transfers t left join public.invoice_benefit_values rb on rb.id = t.replacement_benefit_id
   where (rb.lot_id is not null or t.before_snapshot ? 'remaining_amount')
     and not ((select count(*) from public.customer_credit_ledger e where e.source_type = 'invoice_benefit_transfer_out' and e.source_record_id = t.id) = 1
          and (select count(*) from public.customer_credit_ledger e where e.source_type = 'invoice_benefit_transfer_in' and e.source_record_id = t.id) = 1
          and exists (select 1 from public.customer_credit_ledger e where e.source_type = 'invoice_benefit_transfer_out' and e.source_record_id = t.id
                       and e.lot_id::text = t.before_snapshot->>'id' and e.amount = t.transferred_value)
          and exists (select 1 from public.customer_credit_ledger e where e.source_type = 'invoice_benefit_transfer_in' and e.source_record_id = t.id
                       and e.lot_id::text = t.after_snapshot->>'id' and e.amount = t.transferred_value and rb.lot_id is not null))
   group by t.invoice_id
  union all
  select '2 refuses: credit on a lot of the invoice none of its records names, or a sale paid from such a lot (behind no lot a benefit row names) that a refund would give back there', f.invoice_id, count(*)
    from (select distinct invoice_id, id from down) f join public.customer_credit_lots l on l.id = f.id
   where not exists (select 1 from named nm where nm.invoice_id = f.invoice_id and nm.id = f.id)
     and (l.remaining_amount > 0
          or not exists (select 1 from behind bh where bh.invoice_id = f.invoice_id and bh.id = f.id)
             and (exists (select 1 from public.invoice_line_credit_allocations a where a.lot_id = f.id and a.amount > coalesce(a.reversed_amount, 0))
                  or exists (select 1 from public.special_credit_allocations s where s.lot_id = f.id and s.amount > coalesce(s.reversed_amount, 0))))
   group by f.invoice_id
  union all
  select '3 refuses: a lot more than 12 reissues down its chain', f.invoice_id, count(distinct c.start)
    from chain c join (select distinct invoice_id, id from down) f on f.id = c.start where c.depth >= 13 group by f.invoice_id
  union all
  select '4 refuses: credit on a lot the records name held by someone other than whoever holds the benefits now', h.invoice_id, count(*)
    from holder h where h.remaining_amount > 0 and h.status = 'active' and h.customer_id is distinct from h.live_holder
   group by h.invoice_id
  union all
  -- 462 changes the answer (no refusal):
  select '5 changes: a moved lot held for review now traced to its origin (spendable)', t.invoice_id, count(*)
    from public.customer_credit_lots l join public.invoice_benefit_transfers t on t.id = l.source_record_id
   where l.source_type = 'invoice_benefit_transfer' and l.remaining_amount > 0 and public.invoice_credit_transfer_origin(l.id) is null
   group by t.invoice_id
  union all
  select '6 changes: a reopening waiting on an invoice whose benefit an Owner moved (its payment gives back to the benefits'' holder on a new lot)', q.invoice_id, count(*)
    from public.invoice_reopen_benefits q
   where q.applied_at is null
     and exists (select 1 from public.invoice_benefit_values b join public.invoice_benefit_transfers t on t.source_benefit_id = b.id where b.invoice_id = q.invoice_id)
   group by q.invoice_id
  union all
  select '7 changes: a lot the records name held by someone other than the benefits'' holder, with sales paid from it that can still be refunded (their credit then goes to the holder)', h.invoice_id, count(*)
    from holder h
   where h.customer_id is distinct from h.live_holder
     and (exists (select 1 from public.invoice_line_credit_allocations a where a.lot_id = h.lot_id and a.amount > coalesce(a.reversed_amount, 0))
          or exists (select 1 from public.special_credit_allocations s where s.lot_id = h.lot_id and s.amount > coalesce(s.reversed_amount, 0)))
   group by h.invoice_id
  union all
  select '8 changes: the customer-change list (a lot whose benefit an Owner moved now moves; a reissued lot with spending on an earlier lot now "Partly spent")', b.invoice_id, count(*)
    from public.invoice_benefit_values b
    join public.customer_credit_lots l on l.id = b.lot_id
    join public.invoices iv on iv.id = b.invoice_id
   where l.status = 'active' and l.remaining_amount > 0 and iv.deleted_at is null
     and l.id in (select x.lot_id from public.invoice_credit_lot_ids(b.invoice_id) x)
     and ((exists (select 1 from public.invoice_benefit_transfers t where t.source_benefit_id = b.id)
           and l.remaining_amount < l.original_amount
           and l.remaining_amount + b.cancelled_unused_value + public.invoice_benefit_unused_elsewhere(b.id) >= b.granted_value
           and b.cancelled_unused_value = 0 and iv.status not in ('cancelled', 'refunded')
           and not exists (select 1 from public.invoice_reopen_benefits q where q.invoice_id = iv.id and q.applied_at is null))
       or (l.reassigned_from_lot_id is not null and l.remaining_amount = l.original_amount
           and l.remaining_amount + b.cancelled_unused_value + public.invoice_benefit_unused_elsewhere(b.id) < b.granted_value))
   group by b.invoice_id
  union all
  select '9 changes: a cancelled or refunded invoice whose benefit an Owner moved after a merge or a change reissued its lot (460 may refuse to reopen it; 462 does not)', b.invoice_id, count(*)
    from public.invoice_benefit_values b
    join public.customer_credit_lots l on l.id = b.lot_id
    join public.invoices iv on iv.id = b.invoice_id
   where iv.status in ('cancelled', 'refunded') and iv.deleted_at is null and l.reassigned_from_lot_id is not null
     and exists (select 1 from public.invoice_benefit_transfers t where t.source_benefit_id = b.id)
   group by b.invoice_id)
select f.reason, i.invoice_no, f.n
  from found f join public.invoices i on i.id = f.invoice_id
 order by f.reason, i.invoice_no
$hq$;

-- ===== S. Where it starts =====
create temp table t462_fp(k text primary key, v text);
create function pg_temp.t462_grants(p_without text[] default '{}') returns text language sql as $f$
  select md5(string_agg(p.oid::regprocedure::text || '=' || coalesce(p.proacl::text, ''), '|' order by p.oid::regprocedure::text))
    from pg_proc p where p.pronamespace = 'public'::regnamespace and not (p.proname = any (p_without)) $f$;
create function pg_temp.t462_grant_set(p_sig text) returns text[] language sql as $f$
  select array_agg(x::text order by x::text) from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || p_sig) $f$;
insert into t462_fp values ('start', pg_temp.t462_fingerprint()), ('grants', pg_temp.t462_grants());
-- The six functions 462 changes: BEFORE (production, 24 Oct 2026, at 464)
-- and AFTER; the four it adds.
create temp table t462_md5(sig text primary key, before text, after text, after463 text, after470 text, after471 text);
insert into t462_md5 values
  ('invoice_credit_transfer_origin(uuid)', 'e778a9e4ff81567a493b8ca479d8222b', '1e8beeccfbf7e432edffc1598acddb53', null, null, null),
  ('apply_reopened_invoice_benefits()', '3e659dafdbacb00ad953f99d00c3c6c9', '4efef2f1e97bed6a3f0eed0df4e2df51', '36eaa7224e514d3e7e42e3eeb51acfb5', null, null),
  ('invoice_reopen_preview(uuid)', '4b49c0c64eeb1b5962b605bbf56ea159', 'e09ebf9c0841ef5463f96b26f4933541', null, null, null),
  ('merge_customer_records(uuid,uuid,text,uuid)', '2e0c9852099ab88d8f27827b5f9a3846', 'ba05c2b1fb4c0e14d369c01d06a635b0', null, null, null),
  ('move_invoice_benefits_to_customer(uuid,uuid,uuid,text)', 'c1827889748d29f7a6626294333bd94f', '130c25c6ce3d91b7b421e6f4c3d02353', 'c01606c84ee13ddcd88c15521d6d9aed', null, null),
  ('invoice_transferable_benefits(uuid)', '362d6d076c4751ab5dbe760f6d7a0d37', 'd0d19b7c765337c3cd68096fdc6de7dd', '68736a39ed765ee787242bc62bbaeebb', null, null),
  ('credit_lot_ancestry(uuid)', null, '52b3cae789b6b52a12bb2f798af40cbe', null, null, null),
  ('invoice_credit_live_holder(uuid,uuid,timestamp with time zone)', null, 'a5692590ef3e8a7a7dd7e8ff7cfa9568', null, null, null),
  ('credit_given_back_follows(uuid)', null, '9d75978de5b247a8de1aaee4e894a698', '844b73106bbf362768ed4a899ceb00d5', 'b7720a148f5371bd2bd844d3076ea3b2', '1417d83e7d7be49209f5cd1369d07ec7'),
  ('trg_credit_given_back_follows()', null, '84e2d978b74b56a9508e4f4f5b518c22', null, null, null);
-- (463, where it is in, changes four of them: its AFTERs, after463; 470,
-- where it is in, the forwarder: after470; 471 the forwarder again: after471.)
create function pg_temp.t462_at(p_col text) returns boolean language sql as $f$
  select bool_and(case when p_col = 'before' then (m.before is null and to_regprocedure('public.' || m.sig) is null)
                                                  or md5(pg_get_functiondef(to_regprocedure('public.' || m.sig))) = m.before
                       else to_regprocedure('public.' || m.sig) is not null
                            and md5(pg_get_functiondef(to_regprocedure('public.' || m.sig)))
                                = case when pg_temp.t462_471_in() then coalesce(m.after471, m.after470, m.after463, m.after)
                                       when pg_temp.t462_470_in() then coalesce(m.after470, m.after463, m.after)
                                       when pg_temp.t462_463_in() then coalesce(m.after463, m.after) else m.after end end)
    from t462_md5 m $f$;
\if :{?nomig}
do $$ begin
  perform pg_temp.t462_check(pg_temp.t462_in() and pg_temp.t462_at('after'), 'S -v nomig=1: 462 is in, as tested');
end $$;
\else
do $$ begin
  perform pg_temp.t462_check(not pg_temp.t462_in() and pg_temp.t462_at('before'),
    'S 462 is not in yet and its six functions are at 464 (this suite installs it; use -v nomig=1 where it is in)');
end $$;

-- ===== R. Before 462: each case reproduced (undone afterwards) =====
-- A 'fixed' case does not end as 462 makes it; a control does, exactly.
savepoint t462_r;
do $$
declare c record; o jsonb; res text := '';
begin
  for c in select * from t462_cases order by ord loop
    o := pg_temp.t462_run('before', c.k, c.steps);
    if c.kind = 'fixed' then
      perform pg_temp.t462_check(not (pg_temp.t462_meets(o, c.expect) and coalesce(o->>'invariants', '') = ''),
        'R ' || c.k || ' already ends as 462 makes it, without 462: ' || o::text);
      res := res || format(E'\n  %s: %s%s%s', c.k, (select string_agg(h.key || ' ' || (h.value #>> '{}'), ', ' order by h.key) from jsonb_each(o->'holds') h),
        coalesce('; cancel ' || nullif(o->>'cancel', '-') || ' due ' || (o->>'due'), ''),
        coalesce('; ' || nullif(o->>'invariants', ''), '') || coalesce('; refused: ' || left(o->>'error', 120), ''));
    else
      perform pg_temp.t462_check(pg_temp.t462_meets(o, c.expect) and coalesce(o->>'invariants', '') = ''
          and coalesce((o->>'cancel_left')::numeric, 0) = 0,
        'R control ' || c.k || ' without 462: ' || coalesce(pg_temp.t462_diff(o, c.expect), '') || ' ' || o::text);
    end if;
  end loop;
  raise notice 'PASS R: without 462 every case ends otherwise (the faults reproduced):%', res;
end $$;

-- ===== Q. The header's read-only query, on these states =====
create temp table t462_q as select * from pg_temp.t462_header_query();
create function pg_temp.t462_q_has(p_reason text, p_case text) returns boolean language sql as $f$
  select exists (select 1 from t462_q q join invoices i on i.invoice_no = q.invoice_no
                  where left(q.reason, 1) = p_reason and i.id = pg_temp.t462_id('before/' || p_case || '/inv')) $f$;
do $$
declare v_want text; v_got text; c record;
begin
  -- 2: exactly the cases whose credit sits on a lot no record names, or
  -- with a sale paid from such a lot that a refund would give back there.
  select string_agg(i.invoice_no, ', ' order by i.invoice_no) into v_want
    from t462_res r join invoices i on i.id = pg_temp.t462_id('before/' || r.k || '/inv')
   where r.phase = 'before' and (r.v->>'invariants' like '%no record names%' or r.v->>'invariants' like '%can still be refunded%');
  select string_agg(invoice_no, ', ' order by invoice_no) into v_got from t462_q where left(reason, 1) = '2';
  perform pg_temp.t462_check(v_want is not null and v_got = v_want, 'Q 2 lists ' || coalesce(v_got, '-') || ', not ' || coalesce(v_want, '-'));
  -- 4: the reinstated credit with the old holder or a retired record; 5:
  -- the moved lot held for review; 7: a lot with sales paid from it held by
  -- the old customer; 8: the list's answer; 9: the reopenings 460 refuses.
  foreach v_want in array array['4:K5', '4:K6', '4:K6c', '4:X10', '4:X11', '4:X12', '4:X13', '4:S4', '4:D1c', '4:SS1',
                                '5:F3a', '7:D1d', '7:K5s', '8:K8', '8:S1k', '8:K5b', '8:S1', '8:R3c',
                                '9:R1', '9:R1b', '9:R2', '9:L3', '9:R5', '9:R3', '9:R3b', '9:S3', '9:S3w'] loop
    perform pg_temp.t462_check(pg_temp.t462_q_has(split_part(v_want, ':', 1), split_part(v_want, ':', 2)),
      'Q ' || v_want || ' is not listed');
  end loop;
  -- The controls whose answers 462 does not change are not listed.
  for c in select * from t462_cases where k in ('K1', 'K3', 'X3', 'M1', 'M8a', 'M8b', 'F1', 'F2', 'L1', 'L2', 'L5', 'T1', 'T2', 'V3', 'V6') loop
    perform pg_temp.t462_check(not exists (select 1 from t462_q q join invoices i on i.invoice_no = q.invoice_no
                                            where i.id = pg_temp.t462_id('before/' || c.k || '/inv')),
      'Q control ' || c.k || ' is listed');
  end loop;
  raise notice 'PASS Q: the header''s read-only query lists % invoices (%), each reason as expected; the controls 462 does not change are not listed',
    (select count(distinct invoice_no) from t462_q),
    (select string_agg(left(reason, 1) || ' ' || n, ', ' order by left(reason, 1)) from (select reason, count(*) n from t462_q group by reason) x);
end $$;

-- ===== 9. The refusals, each changing nothing =====
-- 9a With these states in (credit on a lot no record names, among others):
-- refused, naming those invoices.
savepoint t462_9;
\set ON_ERROR_STOP off
\ir ../../../supabase/462_moved_and_merged_credit_follows_its_records.sql
\set ON_ERROR_STOP on
rollback to savepoint t462_9;
select :'LAST_ERROR_MESSAGE' as t462_9a \gset
select set_config('t462.msg', :'t462_9a', false);
do $$
declare m text := current_setting('t462.msg'); v text;
begin
  select string_agg(invoice_no, ', ' order by invoice_no) into v from t462_q where left(reason, 1) = '2';
  perform pg_temp.t462_check(m = format('462: %s invoice(s) have credit on a lot none of their records names, or a sale paid from such a lot that a refund would give back there (%s): Cancel and Refund in full read it as spent. Decide where it belongs (a data fix), then apply. Nothing was changed.',
                                        (select count(*) from t462_q where left(reason, 1) = '2'), v)
      and not pg_temp.t462_in() and pg_temp.t462_at('before'),
    '9a refused with: ' || m);
end $$;
-- Keep R's outcomes; undo its records.
select coalesce(jsonb_object_agg(k, v), '{}'::jsonb)::text as t462_rbefore from t462_res where phase = 'before' \gset
rollback to savepoint t462_r;
insert into t462_res select 'before', key, value from jsonb_each(:'t462_rbefore'::jsonb);
do $$ begin
  perform pg_temp.t462_check((select count(*) from t462_res where phase = 'before') = (select count(*) from t462_cases)
      and pg_temp.t462_fingerprint() = (select v from t462_fp where k = 'start'),
    'R undone, its outcomes kept');
end $$;

-- 9b Credit on the lot the records name held by someone other than the
-- benefits' holder (K5 without 462): refused, naming it.
savepoint t462_9;
do $$ begin perform pg_temp.t462_run('9b', 'K5', (select steps from t462_cases where k = 'K5')); end $$;
select invoice_no as t462_9inv from invoices where id = pg_temp.t462_id('9b/K5/inv') \gset
\set ON_ERROR_STOP off
\ir ../../../supabase/462_moved_and_merged_credit_follows_its_records.sql
\set ON_ERROR_STOP on
rollback to savepoint t462_9;
select :'LAST_ERROR_MESSAGE' as t462_9 \gset
select set_config('t462.msg', :'t462_9', false), set_config('t462.inv', :'t462_9inv', false);
do $$
declare m text := current_setting('t462.msg');
begin
  perform pg_temp.t462_check(m = format('462: 1 invoice(s) have credit on a lot their records name held by someone other than whoever holds their benefits now (%s): a merge or a customer change after an Owner''s Move, or a deleted record. Decide where it belongs (a data fix), then apply. Nothing was changed.',
                                        current_setting('t462.inv'))
      and not pg_temp.t462_in(), '9b refused with: ' || m);
end $$;
-- 9c An Owner's Move of credit with a third ledger row: refused.
savepoint t462_9;
do $$
declare inv uuid; t invoice_benefit_transfers%rowtype;
begin
  perform pg_temp.t462_run('9c', 'M', 'sale A cp; move 1 F');
  inv := pg_temp.t462_id('9c/M/inv');
  select * into t from invoice_benefit_transfers where invoice_id = inv;
  insert into customer_credit_ledger(wallet_id, customer_id, entry_type, category, amount, lot_id, source_type, source_record_id, store_id, reason)
  select l.wallet_id, l.customer_id, 'grant', l.category, 1, l.id, 'invoice_benefit_transfer_in', t.id, l.store_id, 'T462 a third row'
    from customer_credit_lots l where l.id = (t.after_snapshot->>'id')::uuid;
end $$;
select invoice_no as t462_9inv from invoices where id = pg_temp.t462_id('9c/M/inv') \gset
\set ON_ERROR_STOP off
\ir ../../../supabase/462_moved_and_merged_credit_follows_its_records.sql
\set ON_ERROR_STOP on
rollback to savepoint t462_9;
select :'LAST_ERROR_MESSAGE' as t462_9 \gset
select set_config('t462.msg', :'t462_9', false), set_config('t462.inv', :'t462_9inv', false);
do $$
declare m text := current_setting('t462.msg');
begin
  perform pg_temp.t462_check(m = format('462: 1 invoice(s) have an Owner''s Move of credit whose two ledger rows are not as every Move writes them (%s): the new trace reads them. Nothing was changed.',
                                        current_setting('t462.inv'))
      and not pg_temp.t462_in(), '9c refused with: ' || m);
end $$;
-- 9d A lot thirteen reissues down its chain (thirteen merges): refused.
savepoint t462_9;
do $$
declare i int; st text := 'sale A cp';
begin
  for i in 1 .. 13 loop
    st := st || '; merge M' || i || ' ' || case when i = 1 then 'A' else 'M' || (i - 1) end;
  end loop;
  perform pg_temp.t462_run('9d', 'M', st);
  perform pg_temp.t462_check((select err from t462_err where pre = '9d/M') is null
      and pg_temp.t462_depth((select lot_id from invoice_benefit_values where invoice_id = pg_temp.t462_id('9d/M/inv'))) = 13,
    '9d the fixture: thirteen merges');
end $$;
\set ON_ERROR_STOP off
\ir ../../../supabase/462_moved_and_merged_credit_follows_its_records.sql
\set ON_ERROR_STOP on
rollback to savepoint t462_9;
select :'LAST_ERROR_MESSAGE' as t462_9 \gset
select set_config('t462.msg', :'t462_9', false);
do $$ begin
  perform pg_temp.t462_check(current_setting('t462.msg') = '462: 1 credit lot(s) are more than 12 reissues down their chain, further than the readers follow. Nothing was changed.'
      and not pg_temp.t462_in(), '9d refused with: ' || current_setting('t462.msg'));
end $$;
-- 9e A moved lot partly taken back, then merged (F3a's state, held for
-- review): installs, naming the lot it now traces; the kept record can
-- then spend it. Undone.
savepoint t462_9;
do $$ begin perform pg_temp.t462_run('9e', 'F3a', 'sale A cp; move 1 F; back 1 30 F; merge K F'); end $$;
\ir ../../../supabase/462_moved_and_merged_credit_follows_its_records.sql
do $$
declare o jsonb;
begin
  o := pg_temp.t462_run('9e', 'F3a', 'sale A cp; move 1 F; back 1 30 F; merge K F; spend K', 5);
  perform pg_temp.t462_check(pg_temp.t462_in() and o->'holds' @> '{"K":"50.00"}' and o->>'error' is null and o->>'invariants' = '',
    '9e installed over a moved lot held for review, then spent: ' || o::text);
end $$;
rollback to savepoint t462_9;
-- 9h K9's merge, then the kept record spent the reissued lot to S$0 (no
-- credit on it, but a sale paid from it that a refund would give back there,
-- behind no lot a benefit row names): refused, naming it (the critics' 6).
savepoint t462_9;
do $$ begin perform pg_temp.t462_run('9h', 'K9s', 'sale A cp; back 1 40; move 1 F; cancel; reopen; pay; merge K A; spend K 2'); end $$;
select invoice_no as t462_9inv from invoices where id = pg_temp.t462_id('9h/K9s/inv') \gset
do $$ begin
  perform pg_temp.t462_check((select err from t462_err where pre = '9h/K9s') is null
      and (select v.inv from (select pg_temp.t462_id('9h/K9s/inv') as inv) v) is not null
      and exists (select 1 from pg_temp.t462_header_query() q where left(q.reason, 1) = '2'
                     and q.invoice_no = (select invoice_no from invoices where id = pg_temp.t462_id('9h/K9s/inv')))
      and (select coalesce(sum(remaining_amount), 0) from customer_credit_lots
            where id in (select pg_temp.t462_family(pg_temp.t462_id('9h/K9s/inv')))
              and id not in (select pg_temp.t462_named(pg_temp.t462_id('9h/K9s/inv')))) = 0,
    '9h the fixture: the kept record''s lot spent to S$0, listed by the header''s query (2)');
end $$;
\set ON_ERROR_STOP off
\ir ../../../supabase/462_moved_and_merged_credit_follows_its_records.sql
\set ON_ERROR_STOP on
rollback to savepoint t462_9;
select :'LAST_ERROR_MESSAGE' as t462_9 \gset
select set_config('t462.msg', :'t462_9', false), set_config('t462.inv', :'t462_9inv', false);
do $$
declare m text := current_setting('t462.msg');
begin
  perform pg_temp.t462_check(m = format('462: 1 invoice(s) have credit on a lot none of their records names, or a sale paid from such a lot that a refund would give back there (%s): Cancel and Refund in full read it as spent. Decide where it belongs (a data fix), then apply. Nothing was changed.',
                                        current_setting('t462.inv'))
      and not pg_temp.t462_in(), '9h refused with: ' || m);
end $$;
-- 9f A function it changes, or one it relies on, not as tested; a new way
-- of writing credit back on a lot: refused, changing nothing.
savepoint t462_9;
do $$ begin
  execute replace(pg_get_functiondef('public.merge_customer_records(uuid,uuid,text,uuid)'::regprocedure),
                  'declare v_preview jsonb;', 'declare /* another version */ v_preview jsonb;');
end $$;
\set ON_ERROR_STOP off
\ir ../../../supabase/462_moved_and_merged_credit_follows_its_records.sql
\set ON_ERROR_STOP on
rollback to savepoint t462_9;
select :'LAST_ERROR_MESSAGE' as t462_9 \gset
select set_config('t462.msg', :'t462_9', false);
do $$ begin
  perform pg_temp.t462_check(current_setting('t462.msg') like '462: public.merge_customer_records(uuid,uuid,text,uuid) is not the version this was tested against (md5 %',
    '9f a changed function: ' || current_setting('t462.msg'));
end $$;
savepoint t462_9;
do $$ begin
  execute replace(pg_get_functiondef('public.refund_special_credit(text,uuid)'::regprocedure),
                  'declare v_a record;', 'declare /* another version */ v_a record;');
end $$;
\set ON_ERROR_STOP off
\ir ../../../supabase/462_moved_and_merged_credit_follows_its_records.sql
\set ON_ERROR_STOP on
rollback to savepoint t462_9;
select :'LAST_ERROR_MESSAGE' as t462_9 \gset
select set_config('t462.msg', :'t462_9', false);
do $$ begin
  perform pg_temp.t462_check(current_setting('t462.msg') like '462: public.refund_special_credit(text,uuid) is missing or not the version this was tested against (md5 %',
    '9f a function it relies on: ' || current_setting('t462.msg'));
end $$;
savepoint t462_9;
create function public.t462_another_writer(p_lot uuid) returns void language sql as $f$
  insert into public.customer_credit_ledger(wallet_id, customer_id, entry_type, category, amount, lot_id, source_type)
  select wallet_id, customer_id, 'reverse', category, 1, id, 't462' from public.customer_credit_lots where id = p_lot $f$;
\set ON_ERROR_STOP off
\ir ../../../supabase/462_moved_and_merged_credit_follows_its_records.sql
\set ON_ERROR_STOP on
rollback to savepoint t462_9;
select :'LAST_ERROR_MESSAGE' as t462_9 \gset
select set_config('t462.msg', :'t462_9', false);
do $$ begin
  perform pg_temp.t462_check(current_setting('t462.msg') like '462: what writes credit back on a lot is not as read on 24 Oct 2026 (%t462_another_writer(uuid)%',
    '9f a new way of writing credit back: ' || current_setting('t462.msg'));
end $$;
-- 9g The same grants listed in another order: not a refusal.
savepoint t462_9;
revoke execute on function public.invoice_transferable_benefits(uuid) from authenticated;
grant execute on function public.invoice_transferable_benefits(uuid) to authenticated;
\ir ../../../supabase/462_moved_and_merged_credit_follows_its_records.sql
do $$ begin
  perform pg_temp.t462_check(pg_temp.t462_in(), '9g the same grants in another order stopped it');
end $$;
rollback to savepoint t462_9;
do $$ begin
  perform pg_temp.t462_check(pg_temp.t462_fingerprint() = (select v from t462_fp where k = 'start') and not pg_temp.t462_in()
      and pg_temp.t462_grants() = (select v from t462_fp where k = 'grants'),
    '9 the refusals left a change');
  raise notice 'PASS 9: refused, changing nothing: credit on a lot no record names (the R states: the invoices the header''s query lists), credit on a named lot held by someone other than the benefits'' holder (K5), a Move with a third ledger row, a lot 13 reissues down, a sale paid from a reissued lot no record names (K9s, spent to S$0); a function changed or relied on not as tested; a new way of writing credit back. Installed over a moved lot held for review (F3a), which the kept record can then spend. The same grants in another order do not stop it';
end $$;

-- ===== M. Begun before 462, finished after it (the mid set) =====
create temp table t462_mid(k text primary key, ord serial, split int, steps text, expect jsonb);
insert into t462_mid(k, split, steps, expect) select 'm' || k, s, steps, expect from (values
  ('K5', 5), ('X13', 6), ('R4', 8), ('S4', 4), ('G1b', 7), ('F3a', 4), ('R1', 5), ('X12', 6), ('L13', 7),
  -- and states the install's trace check reads (a second Move, a Move of a
  -- replacement, a merged recipient, a Move to the same customer, K8's).
  ('M8a', 3), ('M8b', 4), ('F1', 3), ('T1r', 3), ('K8', 6),
  -- and the critics' cases: a reopening waiting (CW1), a change after a
  -- Move (X2p, DH3, CH2), a change after the package was spent (CH1).
  ('CW1', 6), ('X2p', 5), ('DH3', 5), ('CH2', 16), ('CH1', 22)) x(k, s)
  join t462_cases c using (k);
do $$ declare c record; begin
  for c in select * from t462_mid order by ord loop
    perform pg_temp.t462_run('mid', c.k, c.steps, 1, c.split);
  end loop;
end $$;
\endif

-- ===== 10. Install 462, twice =====
\if :{?nomig}
do $$ begin raise notice 'NOTE 10: -v nomig=1, so 462 is not installed here (R, Q, 9 and M are skipped)'; end $$;
\else
\ir ../../../supabase/462_moved_and_merged_credit_follows_its_records.sql
do $$ begin insert into t462_fp values ('first', pg_temp.t462_fingerprint()); end $$;
\ir ../../../supabase/462_moved_and_merged_credit_follows_its_records.sql
do $$ begin insert into t462_fp values ('second', pg_temp.t462_fingerprint()); end $$;
\endif
do $$
declare v_def text;
begin
  perform pg_temp.t462_check(pg_temp.t462_in() and pg_temp.t462_at('after'), '10 462 is not installed as tested');
  perform pg_temp.t462_check((select count(*) from pg_proc where pronamespace = 'public'::regnamespace
                               and proname in ('invoice_credit_transfer_origin', 'apply_reopened_invoice_benefits', 'invoice_reopen_preview',
                                               'merge_customer_records', 'move_invoice_benefits_to_customer', 'invoice_transferable_benefits',
                                               'credit_lot_ancestry', 'invoice_credit_live_holder', 'credit_given_back_follows',
                                               'trg_credit_given_back_follows')) = 10, '10 an overload exists');
  -- The trigger runs at commit, for the 'reverse' rows of the four sources
  -- that give credit back (and the dormant rental_late_fee), not the
  -- reopening's own, a reversal or a provenance repair.
  select pg_get_triggerdef(oid) into v_def from pg_trigger where tgname = 'credit_given_back_follows' and tgrelid = 'public.customer_credit_ledger'::regclass;
  perform pg_temp.t462_check(v_def like 'CREATE CONSTRAINT TRIGGER credit_given_back_follows AFTER INSERT ON public.customer_credit_ledger DEFERRABLE INITIALLY DEFERRED FOR EACH ROW WHEN (%'
      and v_def like '%''invoice_payment_refund''::text, ''payment_correction''::text, ''special_sale''::text, ''rental''::text, ''rental_late_fee''::text%'
      and v_def not like '%invoice_reopen%' and v_def not like '%reversal%' and v_def not like '%provenance%',
    '10 the trigger is not as tested: ' || coalesce(v_def, '<none>'));
  perform pg_temp.t462_check(exists (select 1 from pg_indexes where indexname = 'customer_credit_ledger_transfer_lots_idx'), '10 the index is missing');
  -- Who may call each: the six as before (sets), the four the server's alone.
  perform pg_temp.t462_check(
        pg_temp.t462_grant_set('invoice_credit_transfer_origin(uuid)') = '{postgres=X/postgres,service_role=X/postgres}'
    and pg_temp.t462_grant_set('apply_reopened_invoice_benefits()') = '{postgres=X/postgres,service_role=X/postgres}'
    and pg_temp.t462_grant_set('invoice_reopen_preview(uuid)') = '{authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres}'
    and pg_temp.t462_grant_set('merge_customer_records(uuid,uuid,text,uuid)') = '{postgres=X/postgres,service_role=X/postgres}'
    and pg_temp.t462_grant_set('move_invoice_benefits_to_customer(uuid,uuid,uuid,text)') = '{postgres=X/postgres,service_role=X/postgres}'
    and pg_temp.t462_grant_set('invoice_transferable_benefits(uuid)') = '{authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres}'
    and pg_temp.t462_grant_set('credit_lot_ancestry(uuid)') = '{postgres=X/postgres,service_role=X/postgres}'
    and pg_temp.t462_grant_set('invoice_credit_live_holder(uuid,uuid,timestamp with time zone)') = '{postgres=X/postgres,service_role=X/postgres}'
    and pg_temp.t462_grant_set('credit_given_back_follows(uuid)') = '{postgres=X/postgres,service_role=X/postgres}'
    and pg_temp.t462_grant_set('trg_credit_given_back_follows()') = '{postgres=X/postgres,service_role=X/postgres}',
    '10 who may call them is not as intended');
  if exists (select 1 from t462_fp where k = 'first') then
    perform pg_temp.t462_check((select v from t462_fp where k = 'second') = (select v from t462_fp where k = 'first'),
      '10 the second run of 462 changed functions');
    perform pg_temp.t462_check(split_part((select v from t462_fp where k = 'first'), ' ', 2)::int
                               = split_part((select v from t462_fp where k = 'start'), ' ', 2)::int + 4,
      '10 462 did not add exactly four functions');
    perform pg_temp.t462_check(pg_temp.t462_grants(array['credit_lot_ancestry', 'invoice_credit_live_holder', 'credit_given_back_follows',
                                                          'trg_credit_given_back_follows']) = (select v from t462_fp where k = 'grants'),
      '10 the grants of the functions already there changed');
  end if;
  raise notice 'PASS 10: 462 installed as tested (%); the six functions at their AFTERs, the four helpers the server''s alone, the deferred trigger and the index in; %',
    pg_temp.t462_fingerprint(),
    coalesce('the second run changed nothing, four functions added, the other grants as before', 'it was in before the suite (nomig)');
end $$;

-- ===== A. Each case after 462 =====
do $$
declare c record; o jsonb; b jsonb; res text := '';
begin
  for c in select * from t462_cases order by ord loop
    o := pg_temp.t462_run('after', c.k, c.steps);
    c.expect := pg_temp.t462_expect(c.k);
    perform pg_temp.t462_check(pg_temp.t462_meets(o, c.expect),
      'A ' || c.k || ': ' || coalesce(pg_temp.t462_diff(o, c.expect), '') || ' ' || o::text);
    perform pg_temp.t462_check(coalesce(o->>'invariants', '') = '', 'A ' || c.k || ' invariants: ' || (o->>'invariants'));
    perform pg_temp.t462_check(coalesce((o->>'cancel_left')::numeric, 0) = 0,
      'A ' || c.k || ': Cancel leaves S$' || (o->>'cancel_left') || ' of the invoice''s credit behind');
    b := (select v from t462_res where phase = 'before' and k = c.k);
    if c.kind = 'control' and b is not null and not (pg_temp.t462_463_in() and c.k in (select k from t462_case463)) then
      perform pg_temp.t462_check(o = b, 'A control ' || c.k || ' changed with 462: before ' || b::text || ', after ' || o::text);
    end if;
    res := res || format(E'\n  %s %s: %s%s', c.kind, c.k,
      (select string_agg(h.key || ' ' || (h.value #>> '{}'), ', ' order by h.key) from jsonb_each(o->'holds') h),
      coalesce('; cancel ' || (o->>'cancel') || ' due ' || (o->>'due'), '') || coalesce('; refused: ' || left(o->>'error', 100), ''));
  end loop;
  raise notice 'PASS A: after 462 each case ends by the Owner''s rules, and in every case the invariants hold (no credit on a lot of the invoice''s family that no record names; each lot''s ledger balanced; no chain over 12; moved lots traced; origins kept; named credit with the benefits'' holder) and Cancel takes all the invoice''s credit back from whoever holds it; the controls are exactly as before 462%:%',
    case when exists (select 1 from t462_res where phase = 'before') then '' else ' (no before figures: -v nomig=1)' end, res;
end $$;

-- ===== M (after). The mid set finished with 462 in =====
\if :{?nomig}
\else
do $$
declare c record; o jsonb; res text := '';
begin
  for c in select * from t462_mid order by ord loop
    o := pg_temp.t462_run('mid', c.k, c.steps, c.split + 1);
    c.expect := coalesce(pg_temp.t462_expect(substr(c.k, 2)), c.expect);
    perform pg_temp.t462_check(pg_temp.t462_meets(o, c.expect) and coalesce(o->>'invariants', '') = ''
        and coalesce((o->>'cancel_left')::numeric, 0) = 0,
      'M ' || c.k || ': ' || coalesce(pg_temp.t462_diff(o, c.expect), '') || ' ' || o::text);
    res := res || ' ' || c.k;
  end loop;
  raise notice 'PASS M: begun before 462 and finished after it, each ends as the whole case does after 462:%', res;
end $$;
\endif

-- ===== P. Probes of the forwarder =====
do $$
declare inv uuid; a uuid; b uuid; lot uuid; o jsonb; n int; v_who text;
begin
  -- P1 It runs at commit, not inside the call: S4's session refund puts
  -- the S$20 back on the lot the invoice names (still A's) until the call
  -- commits; then it is B's.
  perform pg_temp.t462_run('P', 'S4', 'sale A cp; spend A; move 1 F; change B', 1, 4);
  inv := pg_temp.t462_id('P/S4/inv'); a := pg_temp.t462_id('P/S4/A'); b := pg_temp.t462_id('P/S4/B');
  select lot_id into lot from invoice_benefit_values bv
   where bv.invoice_id = inv and not exists (select 1 from invoice_benefit_transfers t where t.replacement_benefit_id = bv.id);
  perform pg_temp.t462_unspend(pg_temp.t462_id('P/S4/S1'));
  perform pg_temp.t462_check((select remaining_amount from customer_credit_lots where id = lot) = 20
      and coalesce((select sum(remaining_amount) from customer_credit_lots where customer_id = b), 0) = 0,
    'P1 the forwarder ran before the commit');
  perform pg_temp.t462_commit();
  perform pg_temp.t462_check((select remaining_amount from customer_credit_lots where id = lot) = 0
      and (select sum(remaining_amount) from customer_credit_lots where customer_id = b) = 20
      and (select count(*) from audit_logs where record_id = inv and action = 'credit_given_back_followed'
            and new_data->>'to_customer' = b::text and (new_data->>'amount')::numeric = 20) = 1,
    'P1 at commit the S$20 did not go to B, recorded in the invoice''s Audit Log');
  -- P2 A's statement shows the S$20 returned and then taken off; B's the S$20 added.
  perform pg_temp.t462_check(
    (select string_agg(coalesce(credit_added::text, '-') || '/' || coalesce(credit_used::text, '-'), ' ' order by entry_seq)
       from customer_credit_statement(a) where source in ('invoice_payment_refund', 'credit_given_back_reassignment_out')) = '20.00/- -/20.00'
    and (select wallet_balance from customer_credit_statement(a) order by entry_date desc, entry_seq desc limit 1) = 0
    and (select string_agg(description, ' | ') from customer_credit_statement(b) where source = 'credit_given_back_reassignment_in')
        = 'Credit added — Credit given back goes to whoever holds the invoice''s benefits now',
    'P2 the credit statements');
  -- P3 Thirteen lines refunded at once (L13): one new lot, two lots down.
  inv := pg_temp.t462_id('after/L13/inv');
  select count(*) into n from customer_credit_ledger where source_record_id = inv and source_type = 'credit_given_back_reassignment_in';
  perform pg_temp.t462_check(n = 1 and pg_temp.t462_depth((select lot_id from invoice_benefit_values where invoice_id = inv)) = 2,
    'P3 L13: ' || n || ' lots granted, the named lot ' || pg_temp.t462_depth((select lot_id from invoice_benefit_values where invoice_id = inv)) || ' down');
  -- P4 The sources it leaves alone: nothing forwarded for PX1 (the 446
  -- pair), PX2 (a reversal), PX3 (a provenance repair).
  perform pg_temp.t462_check(not exists (select 1 from customer_credit_ledger e
                                          where e.source_type like 'credit_given_back_reassignment_%'
                                            and e.source_record_id in (pg_temp.t462_id('after/PX1/inv'), pg_temp.t462_id('after/PX2/inv'),
                                                                       pg_temp.t462_id('after/PX3/inv'))),
    'P4 credit was forwarded for a source the trigger leaves alone');
  -- P5 No credit on a deleted record that was not merged, in any case.
  select string_agg(t.k, ', ') into v_who from t462 t join customers c on c.id = t.id
   where t.k like 'after/%' and c.deleted_at is not null
     and (select coalesce(sum(remaining_amount), 0) from customer_credit_lots where customer_id = c.id) > 0;
  perform pg_temp.t462_check(v_who is null, 'P5 credit on a deleted record: ' || v_who);
  -- P6 Separate refunds, each its own commit (the critics' 2): CH1's
  -- fourteen give fourteen lots, but each takes the place of the one before
  -- (untouched), so the lot the records name stays one down and no lot of
  -- the family is deeper; CH2's moved lot keeps its origin; CH3 (the holder
  -- spends between them): the chain grows only where it spent, three down.
  inv := pg_temp.t462_id('after/CH1/inv');
  perform pg_temp.t462_check(
        (select count(*) from customer_credit_ledger where source_record_id = inv and source_type = 'credit_given_back_reassignment_in') = 14
    and pg_temp.t462_depth((select lot_id from invoice_benefit_values where invoice_id = inv)) = 1
    and (select max(pg_temp.t462_depth(x)) from pg_temp.t462_family(inv) x) = 1,
    'P6 CH1: the chain grew with separate refunds: named lot ' || pg_temp.t462_depth((select lot_id from invoice_benefit_values where invoice_id = inv)) || ' down');
  inv := pg_temp.t462_id('after/CH2/inv');
  perform pg_temp.t462_check(
        (select max(pg_temp.t462_depth(x)) from pg_temp.t462_family(inv) x) = 1
    and (select bool_and(invoice_credit_transfer_origin(l.id) is not null and credit_lot_policy_for(l.id) = 'package_paid')
           from customer_credit_lots l where l.customer_id = pg_temp.t462_id('after/CH2/F') and l.remaining_amount > 0),
    'P6 CH2: the chain grew, or the moved lot lost its origin');
  inv := pg_temp.t462_id('after/CH3/inv');
  perform pg_temp.t462_check(pg_temp.t462_depth((select lot_id from invoice_benefit_values where invoice_id = inv)) = 3,
    'P6 CH3: the named lot is ' || pg_temp.t462_depth((select lot_id from invoice_benefit_values where invoice_id = inv)) || ' down, not 3');
  -- P7 Nothing is forwarded while the invoice is cancelled or its reopening
  -- waits (the critics' 1): CW1, CW3, W3p and X1p forward nothing (the
  -- payment that settles the reopening gives it to the holder); X2p only
  -- the refund made while it was paid. Where 470 is in, credit given back
  -- while the invoice is cancelled or its reopening waits is held back by
  -- the cancellation for the holder at that commit, on a lot the records
  -- name (CW1, CW3, W3p and X1p once each, X2p a second time, each with its
  -- two held-back rows and its Audit Log row); each case ends as before (A).
  if pg_temp.t462_470_in() then
    perform pg_temp.t462_check(
          (select bool_and((select count(*) from customer_credit_ledger e where e.source_type = 'credit_given_back_reassignment_in'
                              and e.source_record_id = pg_temp.t462_id('after/' || k || '/inv')) = case when k = 'X2p' then 2 else 1 end
                       and (select count(*) from customer_credit_ledger e where e.source_type = 'invoice_cancel_benefit'
                              and e.reason = 'Held back by the invoice''s cancellation for whoever holds its benefits now'
                              and e.source_record_id = pg_temp.t462_id('after/' || k || '/inv')) = 2
                       and (select count(*) from audit_logs a where a.action = 'credit_given_back_followed' and a.new_data ? 'held_back'
                              and a.record_id = pg_temp.t462_id('after/' || k || '/inv')) = 1)
             from unnest(array['CW1', 'CW3', 'W3p', 'X1p', 'X2p']) k),
      'P7 (470 in) credit given back while the invoice was cancelled or its reopening waited was not held back once for the holder');
  else
    perform pg_temp.t462_check(
          not exists (select 1 from customer_credit_ledger e where e.source_type like 'credit_given_back_reassignment_%'
                       and e.source_record_id in (pg_temp.t462_id('after/CW1/inv'), pg_temp.t462_id('after/CW3/inv'),
                                                  pg_temp.t462_id('after/W3p/inv'), pg_temp.t462_id('after/X1p/inv')))
      and (select count(*) from customer_credit_ledger e where e.source_type = 'credit_given_back_reassignment_in'
            and e.source_record_id = pg_temp.t462_id('after/X2p/inv')) = 1,
      'P7 credit was forwarded while the invoice was cancelled or its reopening waited');
  end if;
  -- P8 The chain limit (the critics' 2): (a) a lot twelve reissues down
  -- (twelve merges), the last record spent from it, the rest moved, the
  -- benefits changed, that session refunded: refused at commit, naming the
  -- invoice, nothing recorded (here the session's cancel with it: one
  -- step); (b) the same lot thirteen down (a thirteenth
  -- merge, which does not check): a refund of a session the buyer paid
  -- before is refused (more than 12 down); (c) a thirteenth reopening, each
  -- paid with the benefits changed: the payment is refused; (d) eleven:
  -- the session's refund still follows.
  o := pg_temp.t462_run('P', 'P8a', 'sale A cp; merge M1 A; ' || (select string_agg(format('merge M%s M%s', i, i - 1), '; ' order by i) from generate_series(2, 12) i)
         || '; spend M12 1 svc5; move 1 F; change B; unspend S1');
  perform pg_temp.t462_check(o->>'error' like 'unspend S1: Credit given back on lot % would make the chain of lots of invoice % longer than 12, further than the app follows. Nothing was recorded; ask the Owner.'
      and o->'holds' @> '{"B":"0.00","F":"95.00","M12":"0.00"}'
      and (select status::text from invoices where id = pg_temp.t462_id('P/P8a/S1')) = 'paid'
      and (select remaining_amount from customer_credit_lots where id = (select lot_id from invoice_benefit_values bv where bv.invoice_id = pg_temp.t462_id('P/P8a/inv')
            and not exists (select 1 from invoice_benefit_transfers t where t.replacement_benefit_id = bv.id))) = 0,
    'P8a ' || o::text);
  o := pg_temp.t462_run('P', 'P8b', 'sale A cp; spend A 1 svc5; ' || (select string_agg(format('cancel; back 1 1; reopen; change C%s; pay', i), '; ' order by i) from generate_series(1, 12) i)
         || '; merge K C12; unspend S1');
  perform pg_temp.t462_check(o->>'error' like 'unspend S1: Credit given back on lot % is more than 12 lots down from the lot invoice % names for it, further than the app follows. Nothing was recorded; ask the Owner.'
      and o->'holds' @> '{"A":"0.00","K":"95.00"}', 'P8b ' || o::text);
  o := pg_temp.t462_run('P', 'P8c', 'sale A cp; spend A 1 svc5; ' || (select string_agg(format('cancel; back 1 1; reopen; change C%s; pay', i), '; ' order by i) from generate_series(1, 13) i));
  perform pg_temp.t462_check(o->>'error' like 'pay: Reopened invoice %: giving back its credit would make its chain of lots longer than 12, further than the app follows. Nothing was recorded; ask the Owner.'
      and o->>'status' = 'partially_paid' and o->>'invariants' = '', 'P8c ' || o::text);
  o := pg_temp.t462_run('P', 'P8d', 'sale A cp; spend A 1 svc5; ' || (select string_agg(format('cancel; back 1 1; reopen; change C%s; pay', i), '; ' order by i) from generate_series(1, 11) i)
         || '; unspend S1');
  perform pg_temp.t462_check(o->>'error' is null and o->'holds' @> '{"C11":"100.00"}' and o->>'invariants' = '' and (o->>'cancel_left')::numeric = 0,
    'P8d ' || o::text);
  -- P9 The benefits' holder, the invoice's customer and the customer the
  -- credit went back to all deleted (the critics' 5): refused, for the Owner.
  o := pg_temp.t462_run('P', 'P9', 'sale A cp; spend A; spend A; move 1 F; change B; unspend S1; move 1 G; delete B; delete A; unspend S2');
  perform pg_temp.t462_check(o->>'error' like 'unspend S2: Credit given back on lot % belongs with the benefits of invoice %, but whoever holds them, the invoice''s customer and the customer it went back to are all deleted. Nothing was recorded; ask the Owner.'
      and o->'holds' @> '{"A":"0.00","B":"0.00","F":"60.00","G":"20.00"}', 'P9 ' || o::text);
  raise notice 'PASS P: the forwarder runs at commit (S4: the S$20 stays on the lot the invoice names until the call commits, then it is B''s, recorded in the invoice''s Audit Log; A''s statement shows it returned and taken off, B''s it added); thirteen lines refunded at once give one new lot two lots down (L13); nothing is forwarded for the 446 pair, a reversal or a provenance repair; no deleted record holds credit; fourteen separate refunds keep the chain one lot down (CH1, CH2 with its moved lot traced; CH3 grows only where the holder spent); nothing is forwarded while the invoice is cancelled or its reopening waits%; a chain past 12 is refused at commit (P8a, P8b), a thirteenth reopening''s payment too (P8c), eleven follow (P8d); with every record deleted the refund is refused (P9)',
    case when pg_temp.t462_470_in() then ' (470 in: it is held back for the holder instead, CW1, CW3, W3p, X1p, X2p)'
         else ' (CW1, CW3, W3p, X1p; X2p only while paid)' end;
end $$;

-- ===== K. KNOWN: not covered by 462 (each checked as it is) =====
do $$
declare inv uuid; b uuid; r jsonb; v_msg text;
begin
  -- K1 (463, the Owner's decision 2 of 24 Oct 2026): a Move to the same
  -- customer at another store stays with A after a change (T1: A S$100).
  -- (463, where it is in, settles K1 to K4: checked the 463 way.)
  perform pg_temp.t462_check((select v->'holds' from t462_res where phase = 'after' and k = 'T1')
      @> case when pg_temp.t462_463_in() then '{"A":"0.00","B":"100.00"}'::jsonb else '{"A":"100.00","B":"0.00"}'::jsonb end,
    'K1 T1: look at 463 again');
  -- K2 (463, decision 3): a Premium Bundle's vouchers stay with A after a
  -- change (V3, V4: A holds 2).
  perform pg_temp.t462_check((select v->'holds' from t462_res where phase = 'after' and k = 'V3')
        @> case when pg_temp.t462_463_in() then '{"B":"140.00/2"}'::jsonb else '{"A":"0.00/2"}'::jsonb end
      and (select v->'holds' from t462_res where phase = 'after' and k = 'V4')
        @> case when pg_temp.t462_463_in() then '{"B":"140.00/2"}'::jsonb else '{"A":"0.00/2"}'::jsonb end, 'K2 V3/V4: look at 463 again');
  -- K3 (463, W1; 460's NOT COVERED 7): the review summary of a change while
  -- a reopening waits lists no benefits.
  perform pg_temp.t462_run('K', 'W1', 'sale A cpb,v; wait', 1, 2);
  inv := pg_temp.t462_id('K/W1/inv'); b := pg_temp.t462_cust('K/W1/B');
  r := preview_invoice_correction(inv, jsonb_build_object('expected_edit_count', (select edit_count from invoices where id = inv),
         'customer_id', b, 'store_id', (select store_id from invoices where id = inv), 'benefit_action', 'transfer'));
  perform pg_temp.t462_check(exists (select 1 from jsonb_array_elements(r->'effects') e where e->>'area' = 'benefits') = pg_temp.t462_463_in(),
    'K3 W1 summary: ' || coalesce((r->'effects')::text, '-') || ': look at 463 again');
  -- K4 (463 optional, K6s): create_invoice_with_details takes a retired customer.
  perform pg_temp.t462_run('K', 'K6s', 'sale A cp; merge K A', 1, 2);
  begin
    perform create_invoice_with_details(pg_temp.t462_id('store'), pg_temp.t462_id('K/K6s/A'),
      jsonb_build_array(jsonb_build_object('kind', 'therapy', 'therapy_service_id', pg_temp.t462_id('svc'), 'quantity', 1)),
      jsonb_build_object('business_date', sg_today()::text));
    v_msg := 'accepted';
  exception when others then v_msg := sqlerrm;
  end;
  perform pg_temp.t462_check(v_msg = case when pg_temp.t462_463_in()
                                          then 'This customer''s record was merged into another or deleted. Choose the customer again.'
                                          else 'accepted' end, 'K4 an invoice for a retired record: ' || v_msg || ': look at 463 again');
  -- K5 (445's NOT COVERED 1): a merge of a record that spent wallet credit is refused (S1m).
  perform pg_temp.t462_check((select v->>'error' from t462_res where phase = 'after' and k = 'S1m') like 'merge K A: Credit allocations cannot be changed once recorded%',
    'K5 S1m: look at 445''s NOT COVERED 1 again');
  -- K6 (461's NOT COVERED 2): a lot an Owner moved still reads "Fully spent".
  perform pg_temp.t462_run('K', 'L', 'sale A cp; move 1 F', 1, 2);
  perform pg_temp.t462_check(exists (select 1 from invoice_transferable_benefits(pg_temp.t462_id('K/L/inv')) x
                                      where x.blocked_reason = 'Fully spent; it stays with the original customer'),
    'K6 the moved lot''s label: look at 461''s NOT COVERED 2 again');
  -- K7 (462's NOT COVERED 10): credit a refunded sale gives back while the
  -- package's invoice is cancelled, onto a lot a reissue replaced, stays
  -- there with that lot's holder: the reopening's payment then gives it to
  -- the benefits' holder (X2p), but a refund by line of the cancelled
  -- package does not reach it (K7b: S$80 of S$100 paid back, A keeps S$20).
  -- 470, where it is in, settles it: held back by the cancellation for B on
  -- a lot the records name, so the refund by line pays back all S$100,
  -- nobody keeps anything and no lot no record names holds credit (470's
  -- suite checks it and its siblings).
  r := pg_temp.t462_run('K', 'K7b', 'sale A cp; spend A; spend A; move 1 F; change B; unspend S1; cancel; unspend S2; back 1 all');
  if pg_temp.t462_470_in() then
    perform pg_temp.t462_check(r->'holds' @> '{"A":"0.00","B":"0.00","F":"0.00"}' and (r->>'net')::numeric = 0 and r->>'status' = 'cancelled'
        and coalesce(r->>'invariants', '') = '' and r->>'error' is null, 'K7 K7b (470 in): ' || r::text || ': look at 470 again');
  else
    perform pg_temp.t462_check(r->'holds' @> '{"A":"20.00","B":"0.00","F":"0.00"}' and (r->>'net')::numeric = 20 and r->>'status' = 'cancelled'
        and r->>'invariants' like '%S$20.00 on a lot no record names%', 'K7 K7b: ' || r::text || ': look at 462''s NOT COVERED 10 again');
  end if;
  if pg_temp.t462_463_in() then
    raise notice 'NOTE K: 463 is in: (1) T1 B S$100, (2) V3/V4 B holds the two vouchers, (3) the W1 summary lists what the payment gives, (4) the retired record refused (463''s suite checks each)';
  end if;
  if pg_temp.t462_470_in() then
    raise notice 'NOTE K: 470 is in: (7) K7b pays back all S$100, nobody keeps anything (470''s suite checks it and its siblings)';
  end if;
  raise notice 'KNOWN K: (not covered by 462) (7) %; (1) a Move to the same customer at another store stays with A after a customer change (T1: A S$100), and (2) a Premium Bundle''s vouchers stay with A (V3, V4): the Owner''s decisions 2 and 3 of 24 Oct 2026, for 463; (3) the review summary of a change while a reopening waits lists no benefits (W1, 460''s NOT COVERED 7, for 463); (4) create_invoice_with_details takes a retired record (K6s, 463''s optional guard); (5) a merge of a record that spent wallet credit is refused (S1m, 445''s NOT COVERED 1); (6) a lot an Owner moved still reads "Fully spent; it stays with the original customer" (461''s NOT COVERED 2; no page shows it)',
    case when pg_temp.t462_470_in() then 'credit a refunded sale gives back while the package''s invoice is cancelled: settled by 470 (K7b pays back all S$100)'
         else 'credit a refunded sale gives back while the package''s invoice is cancelled stays on the lot it went back to: a refund by line of the cancelled package does not reach it (K7b: A keeps S$20, S$80 of S$100 paid back; reopened and paid, it goes to the holder, X2p)' end;
end $$;

rollback;
