-- 460: what a reopened invoice gives back, and the vouchers it gives again,
-- go to whoever the invoice's benefits belong to now: the record a merge
-- kept, or the customer a change of the invoice's customer moved them to
-- (benefit_action 'transfer'); never the record they left. Not when staff
-- left them with their holder ('keep'). (The Owner, 22 Oct 2026: "fix the
-- other two rare gaps too": 448's NOT COVERED 2 with 446's NOT COVERED 5 and
-- the 447 items found when 446 and 447 were checked together.)
--
-- Every step goes through the app's own calls: the invoice form
-- (create_invoice_with_details) and the Pay dialog (record_invoice_settlement),
-- Cancel (cancel_invoice_recorded), the Finance panel's refund by line and
-- "Record refund paid" (refund_invoice_recorded), its Reopen
-- (reopen_invoice), Record Payment (record_invoice_payment), its Move
-- (transfer_invoice_unused_benefit), the invoice form's customer change and
-- its review summary (correct_invoice and preview_invoice_correction, with
-- 'transfer' or 'keep'), and a customer merge (merge_customer_records).
--
-- Cases (A the buyer, B a new customer, K the record a merge keeps, F a
-- friend an Owner moved credit to):
--   M1 448's NOT COVERED 2: S$40 of a S$100 package refunded by line, A
--      merged into K, cancelled, reopened, paid.
--   M2 A merged into K while the reopened invoice waits (a S$100 + S$10
--      package and two S$30 vouchers; cancelled, all of it paid back by
--      line, reopened).
--   M3 two packages, line 1 refunded whole, A merged into K, cancelled,
--      reopened, paid.
--   M4 the wait of M2, A merged into K and K into K2.
--   M5 A's package credit moved to F (Move), cancelled, paid back,
--      reopened, F merged into K while it waits, paid.
--   X1 446's NOT COVERED 5 (credit): two S$100 + S$10 packages, line 1
--      refunded, the customer changed to B ('transfer'), cancelled,
--      reopened, paid.
--   X2 the same with two voucher lines of one.
--   X3 the wait of M2, the customer changed to B ('transfer') while it
--      waits, paid (447's item: before, everything went to A).
--   X4 two vouchers cancelled and reopened (given again to A), then the
--      customer changed to B ('transfer') (447's item: the reopening's
--      vouchers did not move); the review summary lists them as moving.
--   X5 X4 with a limited voucher and the store changed too: the stock
--      moves with them.
--   X6 the wait of M2, changed to B ('transfer'), then to C ('keep'), paid.
--   X7 the wait of M2, changed to B ('transfer'), B merged into K, paid.
--   X8 a Premium Bundle (S$100 Paid, S$40 Bonus, two vouchers) waiting,
--      changed to B ('transfer'), paid: the bundle's credit to B; its
--      vouchers, which a customer change has never taken along (not
--      transferable), stay with A, as before (NOT COVERED 2).
--   M6 THE GAP the check of 460 and 461 together found (24 Oct 2026), by
--      the merge (there at 455; it was K7, NOT COVERED 4): S$40 refunded
--      by line, A merged into K, K's S$60 moved to F (Move), cancelled,
--      reopened, paid. Before, the S$40 went back on A's old lot, which the
--      merge replaced and no record names: Cancel asked credit_used, its
--      refund due was S$60 and it did not take the S$40 back. Now it goes on
--      K's lot, which the benefit row and the sale name.
--   X9 THE GAP by a customer change (461 makes it reachable; checked where
--      461 is in): S$40 of a S$100 + S$10 package refunded (S$44 of credit),
--      changed to B ('transfer': 461 moves the S$56 left), B's S$56 moved
--      to F, cancelled, reopened, paid: the S$44 on B's lot.
--   X10 X9 with B merged into K after the Move (461 in): the S$44 on B's
--      lot, which the records name; B is the retired record (NOT COVERED 4).
-- Controls (the same outcome with and without 460):
--   K1 the wait of M2, changed to B with 'keep', paid: A holds all.
--   K2 two packages, line 1 refunded, changed to B with 'keep', cancelled,
--      reopened, paid: A holds all.
--   K3 a plain cycle: S$40 refunded, cancelled, reopened, paid: A holds all
--      on the lots it had; no lot is added.
--   K4 A's credit moved to F, cancelled and reopened: F keeps it.
--   K5 460's NOT COVERED 4 (a review of 460, 24 Oct 2026): S$40 of a S$100
--      package refunded by line, the S$60 left moved to F (Move), cancelled,
--      reopened, changed to B ('transfer'), paid: the S$40 goes back on A's
--      lot, which the benefit row and the sale name, as before 460 (the
--      first draft gave it to B on a lot no record named: Cancel then asked
--      a false credit_used override, its refund due fell from S$100 to S$60
--      and Cancel did not take the S$40 back). Nothing reads as spent, the
--      cancel's refund due is S$100, and Cancel takes it all back.
--   K6 K5 with A merged into K instead of the change: the S$40 goes back on
--      A's lot (the retired record), as before 460.
--   K8 the plain Move: S$40 refunded, the S$60 left moved to F, cancelled,
--      reopened, paid (no change, no merge): the S$40 back on A's lot, as
--      at 455.
--   K9 K8, then A merged into K after it was settled: the merge moves the
--      lot's S$40 to K without its records (445), as at 455 (NOT COVERED 4).
-- KNOWN (460's NOT COVERED 4 (b), named by the review of 24 Oct 2026; run
-- in 8 only): the benefits leave the holder of the lot the records name
-- after the Move, and the S$40 (S$44) stays on that lot:
--   M7 M6 with K merged into K2 while it waits.
--   X11 X9 with B changed to C ('transfer') after the Move, before the cancel.
--   X12 X9 with B changed to C ('transfer') while it waits.
--   X13 X9 with B merged into K while it waits; an Owner's Move of that
--      benefit row to K then puts it right.
-- Section 6 (the review of 24 Oct 2026): the holder of that lot pays a S$20
-- session from it (the wallet) before the Move.
--
--   R. Without 460 (skipped with -v nomig=1), undone: each case gives back
--      to the record the benefits left (the faults reproduced).
--   0. The controls before 460: outcomes recorded.
--   9. The refusal: on a database where a reopening already gave credit
--      back to a record its benefits had left (M1, X1), gave a voucher again
--      to the old customer after a change that took the benefits along
--      (X2), or where a reopened invoice waits with its credit and vouchers
--      held by someone other than its customer (X3), or gave credit back on
--      a lot a merge or a change replaced before a Move (M6, and X9 where 461
--      is in), 460 refuses, names the invoice and changes nothing; the
--      controls' states (K1 to K9) are not listed (the real install below
--      goes through with them there; K6's S$40 on the retired record's lot,
--      which the records name, is NOT COVERED 4, which 460 leaves as it is,
--      so it does not refuse over it).
--   3. Either order with 461: with the lots' selection of
--      move_invoice_benefits_to_customer and the credit rows of
--      invoice_transferable_benefits changed (a stand-in for 461, on top of
--      the real 461 where it is in), 460 installs, keeps the change and
--      works; changed anywhere else, it refuses.
--  10. 460 installed twice: the second run changes nothing; two functions
--      added (the server's alone), none dropped; grants as before, as sets;
--      the two functions 461 also changes are 460's AFTER (with 461's part
--      left out where 461 is in).
--   1. Each case after 460: who holds what; the lots the invoice's
--      records name hold it (benefit values, sale lots), each new lot keeps
--      the origin of the one it replaces and names it; the commission
--      source is found; nothing reads as spent or redeemed; and a further
--      cancel and reopen takes it back from, and gives it back to, the same
--      holder, adding no lot.
--   2. The controls after 460: outcomes identical, whole (with the cancel
--      plan's refund due); K5, K6 and K8 then cancelled: nothing reads as
--      spent and Cancel takes everything back.
--   4. A change that takes the benefits along is recorded even when
--      nothing is left to move; 'keep' records none.
--   5. M6 (and X9 where 461 is in) with more refunded: where what would go
--      back is as much as the lot the records name was granted, or more
--      (S$60 or S$50 of S$100; with 461, S$55 of credit), the reopening is
--      refused with its reason and nothing changes; at S$49.99 it goes on
--      that lot and a later customer change refuses the lot as partly
--      spent. Without 461 the change route is refused at the change.
--   6. Credit of that lot that paid for another sale (a S$20 session from
--      the wallet, before the Move) counts as taken, by the merge and, where
--      461 is in, by the change: (a) S$44 to go back with S$20 of S$56 paid
--      for the session (the reviewer's AA4 / AA1): refused, naming the S$20;
--      the session's refund then goes through, back on that lot; (b) S$22
--      with S$20 of S$78: reopened, then the session refunded: the lot stays
--      below what it was granted, nothing reads as spent, the refund due is
--      S$100, a customer change refuses it as partly spent, Cancel takes it
--      all back; (c) a S$100 package, S$40 with S$20 of S$60: refused. (e) A
--      stand-in for credit come back on that lot while it waits: the payment
--      that would settle it is refused with its reason, nothing recorded.
--   8. KNOWN (460's NOT COVERED 2, 3, 4 (K5, K6, K9, M7; X10 to X13 where
--      461 is in) and 7, checked as they are; 1 printed).
--
-- Run on a copy of production as it is (455 in: b43a0781, 1372 functions):
--   psql -X -v ON_ERROR_STOP=1 -f scripts/invoices/tests/reopen-follows-customer-460.sql
-- It installs 460 itself, twice, inside its transaction. Where 460 is in
-- already, add -v nomig=1 (R, 0, 9, 3 and the before/after comparison are
-- then skipped with a notice; every figure after 460 is still checked).
-- Sections 9 and 3 let a statement fail on purpose (psql prints its ERROR);
-- the suite then checks that message. Where 461 (another builder's) is in
-- already (a copy of production with 461 live first), run it the same way:
-- 3 puts its stand-in on top of 461's text, and 10 checks the two functions
-- both change with 461's part left out. Disposable database only;
-- everything is rolled back. Every name, code and amount is invented
-- (@example.com); the phones are numbers kept for fiction (ACMA,
-- +61491570601 to 699).
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '10s';

create temp table t460(k text primary key, id uuid);
create temp table t460_before(k text primary key, v jsonb);
create temp table t460_fp(k text primary key, fp text);
create temp sequence t460_phone;
create function pg_temp.t460_id(p_k text) returns uuid language sql as $f$ select id from t460 where k = p_k $f$;
create function pg_temp.t460_put(p_k text, p_id uuid) returns uuid language sql as $f$
  insert into t460 values (p_k, p_id) on conflict (k) do update set id = excluded.id returning id $f$;
create function pg_temp.t460_check(p_ok boolean, p_label text) returns void language plpgsql as $f$
begin
  if not coalesce(p_ok, false) then raise exception 'FAIL %', p_label; end if;
end $f$;
create function pg_temp.t460_fingerprint() returns text language sql as $f$
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.oid::regprocedure::text)) || ' ' || count(*)
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prokind in ('f', 'p') $f$;
create function pg_temp.t460_in() returns boolean language sql as $f$
  select to_regprocedure('public.invoice_benefits_holder(uuid,uuid,timestamp with time zone)') is not null
     and position('-- 460 (the Owner' in pg_get_functiondef('public.apply_reopened_invoice_benefits()'::regprocedure)) > 0 $f$;
-- 461 (another builder's: what a customer change moves), where it is in.
create function pg_temp.t460_461_in() returns boolean language sql as $f$
  select position('-- 461 (the Owner' in pg_get_functiondef('public.invoice_transferable_benefits(uuid)'::regprocedure)) > 0
     and position('-- 461 (the Owner' in pg_get_functiondef('public.move_invoice_benefits_to_customer(uuid,uuid,uuid,text)'::regprocedure)) > 0 $f$;
-- The two functions 461 also changes, with 461's part left out, as 460
-- compares them (the lots' selection; the list's second of four parts).
create function pg_temp.t460_no461(p_sig text) returns text language plpgsql as $f$
declare d text := pg_get_functiondef(to_regprocedure('public.' || p_sig)); v_parts text[];
  c_mv_s constant text := E'  for r_lot in\n    select l.* from public.customer_credit_lots l\n';
  c_mv_e constant text := E'     for update\n  loop\n';
begin
  if p_sig = 'move_invoice_benefits_to_customer(uuid,uuid,uuid,text)' then
    return md5(left(d, strpos(d, c_mv_s) + length(c_mv_s) - 1) || '…' || substr(d, strpos(d, c_mv_e)));
  end if;
  v_parts := string_to_array(d, E'\n  union all\n'); v_parts[2] := '…';
  return md5(array_to_string(v_parts, E'\n  union all\n'));
end $f$;
create function pg_temp.t460_grants(p_sig text) returns text language sql as $f$
  select coalesce(string_agg(x::text, ',' order by x::text), '') from pg_proc p, unnest(p.proacl) x
   where p.oid = to_regprocedure('public.' || p_sig) $f$;

do $$
declare own uuid := gen_random_uuid(); st uuid; st2 uuid; pm uuid; v uuid; vl uuid; cp uuid; cpb uuid; pbv uuid;
begin
  insert into auth.users(id, email) values (own, 't460-owner@example.com');
  insert into profiles(id, full_name, email, role, is_active) values (own, 'T460 Owner', 't460-owner@example.com', 'owner', true);
  perform set_config('request.jwt.claims', json_build_object('sub', own, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', own::text, true);
  insert into stores(name, code, country_code) values ('T460 Store', 'T460S1', 'SG') returning id into st;
  insert into stores(name, code, country_code) values ('T460 Other Store', 'T460S2', 'SG') returning id into st2;
  insert into payment_methods(name, is_active) values ('T460 Cash', true) returning id into pm;
  -- A plain S$30 voucher, and a limited one (100 in stock at each store).
  insert into vouchers(name, code, voucher_kind, qty_type, selling_price, is_active)
    values ('T460 Plain 30', 'T460-P30', 'normal', 'unlimited', 30, true) returning id into v;
  insert into voucher_store_prices(voucher_id, store_id, selling_price, available_at_store) values (v, st, 30, true), (v, st2, 30, true);
  insert into vouchers(name, code, voucher_kind, qty_type, selling_price, is_active)
    values ('T460 Limited 30', 'T460-L30', 'normal', 'limited', 30, true) returning id into vl;
  insert into voucher_store_prices(voucher_id, store_id, selling_price, available_at_store) values (vl, st, 30, true), (vl, st2, 30, true);
  insert into voucher_store_stock(voucher_id, store_id, current_qty) values (vl, st, 100), (vl, st2, 100);
  -- A S$100 Credit Package (S$100 Paid), one with a S$10 Bonus, and a
  -- Premium Bundle of S$140: S$100 Paid, S$40 Bonus and two S$30 vouchers.
  insert into credit_packages(name, customer_price, paid_credit_amount, bonus_enabled, allow_product, allow_therapy)
    values ('T460 S$100', 100, 100, false, true, true) returning id into cp;
  insert into credit_package_stores(package_id, store_id) values (cp, st), (cp, st2);
  insert into credit_packages(name, customer_price, paid_credit_amount, bonus_enabled, bonus_value, allow_product, allow_therapy, grants_reward)
    values ('T460 S$100 + S$10', 100, 100, true, 10, true, true, false) returning id into cpb;
  insert into credit_package_stores(package_id, store_id) values (cpb, st), (cpb, st2);
  insert into premium_bundles(name, customer_payment_amount, paid_credit_amount, bonus_credit_amount, free_voucher_qty, grants_reward)
    values ('T460 Bundle S$140 + 2 vouchers', 140, 100, 40, 2, true) returning id into pbv;
  insert into premium_bundle_stores(bundle_id, store_id) values (pbv, st), (pbv, st2);
  insert into premium_bundle_vouchers(bundle_id, voucher_id) values (pbv, v);
  insert into t460 values ('own', own), ('store', st), ('store2', st2), ('pm', pm), ('v', v), ('vl', vl),
                          ('cp', cp), ('cpb', cpb), ('pbv', pbv);
end $$;
-- A S$20 therapy session (the Therapy Services page's calls), paid from a
-- customer's Credit Package Paid credit with the wallet method (443's).
do $$
declare svc uuid;
begin
  svc := (upsert_therapy_service(null, 'T460-SESSION', 'T460 Session', 20, 30, 'per_hours', 1, 5, null, true, null) ->> 'id')::uuid;
  perform set_therapy_service_store(svc, pg_temp.t460_id('store'), true, null);
  insert into t460 values ('svc', svc),
    ('wallet', (select id from payment_methods where name = 'Wallet — Credit Package Paid' and is_wallet_credit and deleted_at is null));
  perform pg_temp.t460_check(pg_temp.t460_id('svc') is not null and pg_temp.t460_id('wallet') is not null, 'setup: the session or the wallet method');
end $$;

-- ── The app's calls ─────────────────────────────────────────────────────────
-- A customer of one run of one case.
create function pg_temp.t460_cust(p_k text) returns uuid language plpgsql as $f$
declare c uuid;
begin
  insert into customers(full_name, phone) values ('T460 ' || p_k, '+61491570' || (600 + nextval('t460_phone'))::text) returning id into c;
  return pg_temp.t460_put(p_k, c);
end $f$;
-- The invoice form with these lines ('v' / 'vl' a voucher line of p_qtys[i]
-- units, 'cp' / 'cpb' a Credit Package, 'pbv' the Premium Bundle), for
-- p_cust at p_store, paid in full through the Pay dialog.
create function pg_temp.t460_sale(p_cust uuid, p_kinds text[], p_qtys int[] default null, p_store text default 'store')
  returns uuid language plpgsql as $f$
declare inv uuid; v_lines jsonb := '[]'; i int;
begin
  for i in 1 .. cardinality(p_kinds) loop
    v_lines := v_lines || jsonb_build_array(case
      when p_kinds[i] in ('v', 'vl') then jsonb_build_object('kind', 'voucher', 'voucher_id', pg_temp.t460_id(p_kinds[i]),
                                                            'quantity', coalesce(p_qtys[i], 1))
      when p_kinds[i] in ('cp', 'cpb') then jsonb_build_object('kind', 'credit_package', 'credit_package_id', pg_temp.t460_id(p_kinds[i]), 'quantity', 1)
      else jsonb_build_object('kind', 'premium_bundle', 'premium_bundle_id', pg_temp.t460_id('pbv'), 'quantity', 1,
        'voucher_selection', jsonb_build_array(jsonb_build_object('voucher_id', pg_temp.t460_id('v'), 'quantity', 2))) end);
  end loop;
  inv := create_invoice_with_details(pg_temp.t460_id(p_store), p_cust, v_lines, jsonb_build_object('business_date', sg_today()::text));
  perform record_invoice_settlement(inv, jsonb_build_object('receipts', jsonb_build_array(jsonb_build_object(
    'key', 'line-0', 'payment_method_id', pg_temp.t460_id('pm'), 'amount', (select total_amount from invoices where id = inv),
    'payment_date', sg_today()::text)), 'arrangements', '[]'::jsonb), gen_random_uuid());
  return inv;
end $f$;
-- Record Payment of what is outstanding (nothing when it is settled).
create function pg_temp.t460_pay(p_inv uuid) returns void language plpgsql as $f$
begin
  if (invoice_financial_position(p_inv)->>'outstanding')::numeric > 0 then
    perform record_invoice_payment(p_inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.t460_id('pm'),
      'amount', (invoice_financial_position(p_inv)->>'outstanding')::numeric)), gen_random_uuid());
  end if;
end $f$;
-- The receipts that still hold p_amount between them, as the Finance panel
-- splits a refund across them.
create function pg_temp.t460_sources(p_inv uuid, p_amount numeric) returns jsonb language plpgsql as $f$
declare src jsonb := '[]'; left_ numeric := p_amount; p record;
begin
  for p in select id, invoice_payment_remaining(id) as rem from invoice_payments
            where invoice_id = p_inv and entry_kind = 'receipt' and invoice_payment_remaining(id) > 0 order by created_at, id loop
    exit when left_ <= 0;
    src := src || jsonb_build_array(jsonb_build_object('payment_id', p.id, 'amount', least(p.rem, left_)));
    left_ := left_ - least(p.rem, left_);
  end loop;
  return src;
end $f$;
-- Line n of a kind ('v', 'vl', 'cp', 'cpb', 'pbv'), by id.
create function pg_temp.t460_line(p_inv uuid, p_kind text, p_n int default 1) returns uuid language sql as $f$
  select it.id from invoice_items it
   where it.invoice_id = p_inv
     and case p_kind when 'v' then it.voucher_id = pg_temp.t460_id('v') when 'vl' then it.voucher_id = pg_temp.t460_id('vl')
                     when 'pbv' then it.premium_bundle_id is not null else it.credit_package_id = pg_temp.t460_id(p_kind) end
   order by it.id offset p_n - 1 limit 1 $f$;
-- The Finance panel's refund of a line: p_amount off its Paid credit, or
-- every unused benefit it still holds (all of it).
create function pg_temp.t460_back(p_inv uuid, p_item uuid, p_amount numeric default null) returns void language plpgsql as $f$
declare opts jsonb; ben jsonb; tot numeric;
begin
  opts := invoice_refund_options_before_sessions(p_inv);
  if p_amount is not null then
    select jsonb_build_array(jsonb_build_object('benefit_id', b->>'id', 'amount', p_amount)), p_amount
      into ben, tot from jsonb_array_elements(opts->'benefits') b
     where b->>'invoice_item_id' = p_item::text and b->>'benefit_kind' = 'paid' order by (b->>'paid_value')::numeric desc limit 1;
  else
    select jsonb_agg(jsonb_build_object('benefit_id', b->>'id', 'amount', (b->>'max_refund')::numeric)), sum((b->>'max_refund')::numeric)
      into ben, tot from jsonb_array_elements(opts->'benefits') b
     where b->>'invoice_item_id' = p_item::text and (b->>'max_refund')::numeric > 0;
  end if;
  if ben is null then raise exception 'T460: nothing to refund on that line'; end if;
  perform refund_invoice_recorded(p_inv, jsonb_build_array(jsonb_build_object('invoice_item_id', p_item, 'amount', tot, 'benefits', ben)),
    pg_temp.t460_sources(p_inv, tot), '[]'::jsonb, 'T460 by line', gen_random_uuid());
end $f$;
-- Cancelled, every line paid back by line, reopened: it waits, unpaid.
create function pg_temp.t460_wait(p_inv uuid) returns void language plpgsql as $f$
declare it record;
begin
  perform cancel_invoice_recorded(p_inv, 'T460 cancel', gen_random_uuid());
  for it in select id from invoice_items where invoice_id = p_inv order by id loop
    perform pg_temp.t460_back(p_inv, it.id);
  end loop;
  perform reopen_invoice(p_inv, 'T460 reopen', gen_random_uuid());
  if (select status::text from invoices where id = p_inv) <> 'unpaid'
     or not (exists (select 1 from invoice_reopen_benefits where invoice_id = p_inv and applied_at is null)
             or exists (select 1 from invoice_reopen_vouchers where invoice_id = p_inv and applied_at is null)) then
    raise exception 'T460: the reopened invoice does not wait'; end if;
end $f$;
create function pg_temp.t460_cancel_reopen(p_inv uuid) returns void language plpgsql as $f$
begin
  perform cancel_invoice_recorded(p_inv, 'T460 cancel', gen_random_uuid());
  perform reopen_invoice(p_inv, 'T460 reopen', gen_random_uuid());
end $f$;
-- The invoice form's customer change, its lines as they are (and the store,
-- when given), with 'transfer' or 'keep'.
create function pg_temp.t460_lines(p_inv uuid) returns jsonb language sql as $f$
  select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('invoice_item_id', it.id, 'kind', it.line_kind,
           'credit_package_id', it.credit_package_id, 'premium_bundle_id', it.premium_bundle_id, 'voucher_id', it.voucher_id,
           'quantity', it.quantity, 'unit_price', it.unit_price, 'voucher_selection', it.bundle_voucher_selection)) order by it.id)
    from invoice_items it where it.invoice_id = p_inv $f$;
create function pg_temp.t460_header(p_inv uuid, p_cust uuid, p_action text, p_store text default null) returns jsonb language sql as $f$
  select jsonb_build_object('expected_edit_count', (select edit_count from invoices where id = p_inv),
    'customer_id', p_cust, 'store_id', coalesce(pg_temp.t460_id(p_store), (select store_id from invoices where id = p_inv)),
    'benefit_action', p_action) $f$;
create function pg_temp.t460_change(p_inv uuid, p_cust uuid, p_action text default 'transfer', p_store text default null)
  returns void language plpgsql as $f$
begin
  perform correct_invoice(p_inv, pg_temp.t460_lines(p_inv), pg_temp.t460_header(p_inv, p_cust, p_action, p_store),
    'T460 wrong customer', gen_random_uuid());
end $f$;
create function pg_temp.t460_merge(p_keep uuid, p_dup uuid) returns void language plpgsql as $f$
begin
  perform merge_customer_records(p_keep, p_dup, 'T460 the same person', gen_random_uuid());
end $f$;
-- The Finance panel's Move of a line's unused benefit (its Paid credit, or
-- its voucher) to p_to.
create function pg_temp.t460_move(p_inv uuid, p_item uuid, p_to uuid) returns void language plpgsql as $f$
declare b uuid;
begin
  select bv.id into b from invoice_benefit_values bv
    left join customer_reward_vouchers v on v.id = bv.reward_voucher_id
    left join customer_credit_lots l on l.id = bv.lot_id
   where bv.invoice_item_id = p_item and (v.status = 'held' or l.remaining_amount > 0)
   order by bv.granted_value desc limit 1;
  perform transfer_invoice_unused_benefit(b, p_to, (select store_id from invoices where id = p_inv), 'T460 move', gen_random_uuid());
end $f$;
-- The invoice form: one S$20 session for p_cust, paid with the wallet
-- (Credit Package Paid credit) through Record Payment.
create function pg_temp.t460_spend(p_cust uuid) returns uuid language plpgsql as $f$
declare inv uuid;
begin
  inv := create_invoice_with_details(pg_temp.t460_id('store'), p_cust,
    jsonb_build_array(jsonb_build_object('kind', 'therapy', 'therapy_service_id', pg_temp.t460_id('svc'), 'quantity', 1)),
    jsonb_build_object('business_date', sg_today()::text));
  perform record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.t460_id('wallet'),
    'amount', (select total_amount from invoices where id = inv))), gen_random_uuid());
  return inv;
end $f$;
-- The session cancelled and "Record refund paid": what it took goes back to
-- its payment, so the credit goes back on the lot it came from.
create function pg_temp.t460_unspend(p_inv uuid) returns void language plpgsql as $f$
declare due numeric;
begin
  perform cancel_invoice_recorded(p_inv, 'T460 cancel session', gen_random_uuid());
  due := (invoice_financial_position(p_inv)->>'refund_due')::numeric;
  if due is null or due <= 0 then due := (invoice_action_plan(p_inv, 'cancel', '[]')->>'refund_due')::numeric; end if;
  perform refund_invoice_recorded(p_inv, jsonb_build_array(jsonb_build_object('amount', due)), pg_temp.t460_sources(p_inv, due), '[]'::jsonb,
    'T460 refund paid', gen_random_uuid());
end $f$;

-- ── What the records say ────────────────────────────────────────────────────
-- What a customer holds: credit on their lots, vouchers held.
create function pg_temp.t460_holds(p_cust uuid) returns text language sql as $f$
  select round(coalesce((select sum(l.remaining_amount) from customer_credit_lots l where l.customer_id = p_cust), 0), 2)::text
         || '/' || coalesce((select sum(v.quantity) from customer_reward_vouchers v where v.customer_id = p_cust and v.status = 'held'), 0)::text $f$;
create function pg_temp.t460_codes(p_inv uuid, p_action text) returns text language sql as $f$
  select coalesce(string_agg(o->>'code', ',' order by o->>'code'), '-')
    from jsonb_array_elements(coalesce(invoice_action_plan(p_inv, p_action, '[]')->'overrides_required', '[]')) o $f$;
create function pg_temp.t460_used(p_inv uuid) returns text language sql as $f$
  select coalesce(nullif(array_to_string(cancelled_invoice_used_value(p_inv), ','), ''), '-') $f$;
create function pg_temp.t460_stock(p_store text) returns int language sql as $f$
  select current_qty from voucher_store_stock where voucher_id = pg_temp.t460_id('vl') and store_id = pg_temp.t460_id(p_store) $f$;
-- What is wrong with the invoice's records ('' when nothing): every credit
-- benefit row names a lot that holds its credit; every lot its sale names
-- is one its benefit rows name; a lot that replaced another keeps that
-- one's origin; the commission source of each benefit row is found.
create function pg_temp.t460_records(p_inv uuid) returns text language plpgsql as $f$
declare probs text := ''; b record; root record; s record;
begin
  for b in select bv.*, l.customer_id as holder, l.remaining_amount, l.source_type, l.source_record_id, l.category, l.usage_restrictions
             from invoice_benefit_values bv left join customer_credit_lots l on l.id = bv.lot_id
            where bv.invoice_id = p_inv and bv.lot_id is not null loop
    with recursive c(id, n) as (select b.lot_id, 0 union all
                                select l.reassigned_from_lot_id, c.n + 1 from c join customer_credit_lots l on l.id = c.id
                                 where l.reassigned_from_lot_id is not null and c.n < 12)
    select l.* into root from c join customer_credit_lots l on l.id = c.id order by c.n desc limit 1;
    if (b.source_type, b.source_record_id, b.category, b.usage_restrictions)
       is distinct from (root.source_type, root.source_record_id, root.category, root.usage_restrictions) then
      probs := probs || ' benefit ' || b.id || ' lot lost its origin;'; end if;
    begin
      perform invoice_commission_benefit_source(b.id);
    exception when others then probs := probs || ' commission: ' || sqlerrm || ';';
    end;
  end loop;
  for s in select x.lot from credit_package_sales c cross join lateral unnest(array[c.credit_lot_id, c.bonus_credit_lot_id]) x(lot)
            where c.invoice_id = p_inv and x.lot is not null
           union all
           select x.lot from premium_bundle_sales c cross join lateral unnest(array[c.paid_credit_lot_id, c.bonus_credit_lot_id]) x(lot)
            where c.invoice_id = p_inv and x.lot is not null loop
    if not exists (select 1 from invoice_benefit_values bv where bv.invoice_id = p_inv and bv.lot_id = s.lot) then
      probs := probs || ' a sale names a lot no benefit row names;'; end if;
  end loop;
  return probs;
end $f$;
-- The outcome of a case: its status and money, what each of its customers
-- holds, what waits, the plans' codes, what reads as used, the lots each
-- holds credit on, the change's records, and what is wrong with the
-- invoice's records.
create function pg_temp.t460_outcome(p_case text, p_inv uuid) returns jsonb language sql as $f$
  select jsonb_build_object(
    'status', i.status::text, 'net', invoice_net_received(i.id),
    'holds', (select jsonb_object_agg(split_part(t.k, '/', 3), pg_temp.t460_holds(t.id)) from t460 t where t.k like p_case || '/%'),
    'lots', (select jsonb_object_agg(split_part(t.k, '/', 3),
               (select count(*) from customer_credit_lots l where l.customer_id = t.id and l.remaining_amount > 0))
               from t460 t where t.k like p_case || '/%'),
    'waiting', (select coalesce(sum(amount), 0) from invoice_reopen_benefits where invoice_id = i.id and applied_at is null)::text
               || '/' || (select coalesce(sum(quantity), 0) from invoice_reopen_vouchers where invoice_id = i.id and applied_at is null)::text,
    'cancel', pg_temp.t460_codes(i.id, 'cancel'),
    'due', invoice_action_plan(i.id, 'cancel', '[]')->>'refund_due',
    'invoice_customer', (select split_part(t.k, '/', 3) from t460 t where t.id = i.customer_id and t.k like p_case || '/%'),
    'records', pg_temp.t460_records(i.id))
    from invoices i where i.id = p_inv $f$;

-- ── The cases ───────────────────────────────────────────────────────────────
-- Each run has its own customers ('<case>/<run>/A' and so on).
create function pg_temp.t460_run(p_case text, p_run text) returns jsonb language plpgsql as $f$
declare pre text := p_case || '/' || p_run; a uuid; b uuid; c uuid; k uuid; k2 uuid; f uuid; inv uuid;
begin
  a := pg_temp.t460_cust(pre || '/A');
  if p_case !~ '^M[1-7]$|^K[4689]$' or p_case = 'M5' then b := pg_temp.t460_cust(pre || '/B'); end if;
  if p_case ~ '^M|^X7$|^X1[03]$|^K[69]$' then k := pg_temp.t460_cust(pre || '/K'); end if;
  if p_case in ('X6', 'X11', 'X12') then c := pg_temp.t460_cust(pre || '/C'); end if;
  if p_case in ('M4', 'M7') then k2 := pg_temp.t460_cust(pre || '/K2'); end if;
  if p_case in ('M5', 'M6', 'M7', 'X9', 'X10', 'X11', 'X12', 'X13', 'K4', 'K5', 'K6', 'K8', 'K9') then f := pg_temp.t460_cust(pre || '/F'); end if;
  case p_case
  when 'M1' then
    inv := pg_temp.t460_sale(a, array['cp']);
    perform pg_temp.t460_back(inv, pg_temp.t460_line(inv, 'cp'), 40);
    perform pg_temp.t460_merge(k, a);
    perform pg_temp.t460_cancel_reopen(inv);
    perform pg_temp.t460_pay(inv);
  when 'M2' then
    inv := pg_temp.t460_sale(a, array['cpb', 'v'], array[1, 2]);
    perform pg_temp.t460_wait(inv);
    perform pg_temp.t460_merge(k, a);
    perform pg_temp.t460_pay(inv);
  when 'M3' then
    inv := pg_temp.t460_sale(a, array['cp', 'cp']);
    perform pg_temp.t460_back(inv, pg_temp.t460_line(inv, 'cp', 1));
    perform pg_temp.t460_merge(k, a);
    perform pg_temp.t460_cancel_reopen(inv);
    perform pg_temp.t460_pay(inv);
  when 'M4' then
    inv := pg_temp.t460_sale(a, array['cpb', 'v'], array[1, 2]);
    perform pg_temp.t460_wait(inv);
    perform pg_temp.t460_merge(k, a);
    perform pg_temp.t460_merge(k2, k);
    perform pg_temp.t460_pay(inv);
  when 'M5' then
    inv := pg_temp.t460_sale(a, array['cp']);
    perform pg_temp.t460_move(inv, pg_temp.t460_line(inv, 'cp'), f);
    perform pg_temp.t460_wait(inv);
    perform pg_temp.t460_merge(k, f);
    perform pg_temp.t460_pay(inv);
  when 'M6' then
    inv := pg_temp.t460_sale(a, array['cp']);
    perform pg_temp.t460_back(inv, pg_temp.t460_line(inv, 'cp'), 40);
    perform pg_temp.t460_merge(k, a);
    perform pg_temp.t460_move(inv, pg_temp.t460_line(inv, 'cp'), f);
    perform pg_temp.t460_cancel_reopen(inv);
    perform pg_temp.t460_pay(inv);
  when 'X1' then
    inv := pg_temp.t460_sale(a, array['cpb', 'cpb']);
    perform pg_temp.t460_back(inv, pg_temp.t460_line(inv, 'cpb', 1));
    perform pg_temp.t460_change(inv, b);
    perform pg_temp.t460_cancel_reopen(inv);
    perform pg_temp.t460_pay(inv);
  when 'X2' then
    inv := pg_temp.t460_sale(a, array['v', 'v']);
    perform pg_temp.t460_back(inv, pg_temp.t460_line(inv, 'v', 1));
    perform pg_temp.t460_change(inv, b);
    perform pg_temp.t460_cancel_reopen(inv);
    perform pg_temp.t460_pay(inv);
  when 'X3' then
    inv := pg_temp.t460_sale(a, array['cpb', 'v'], array[1, 2]);
    perform pg_temp.t460_wait(inv);
    perform pg_temp.t460_change(inv, b);
    perform pg_temp.t460_pay(inv);
  when 'X4' then
    inv := pg_temp.t460_sale(a, array['v'], array[2]);
    perform pg_temp.t460_cancel_reopen(inv);
    perform pg_temp.t460_change(inv, b);
  when 'X5' then
    inv := pg_temp.t460_sale(a, array['vl'], array[2]);
    perform pg_temp.t460_cancel_reopen(inv);
    perform pg_temp.t460_change(inv, b, 'transfer', 'store2');
  when 'X6' then
    inv := pg_temp.t460_sale(a, array['cpb', 'v'], array[1, 2]);
    perform pg_temp.t460_wait(inv);
    perform pg_temp.t460_change(inv, b);
    perform pg_temp.t460_change(inv, c, 'keep');
    perform pg_temp.t460_pay(inv);
  when 'X7' then
    inv := pg_temp.t460_sale(a, array['cpb', 'v'], array[1, 2]);
    perform pg_temp.t460_wait(inv);
    perform pg_temp.t460_change(inv, b);
    perform pg_temp.t460_merge(k, b);
    perform pg_temp.t460_pay(inv);
  when 'X8' then
    inv := pg_temp.t460_sale(a, array['pbv']);
    perform pg_temp.t460_wait(inv);
    perform pg_temp.t460_change(inv, b);
    perform pg_temp.t460_pay(inv);
  when 'X9' then
    inv := pg_temp.t460_sale(a, array['cpb']);
    perform pg_temp.t460_back(inv, pg_temp.t460_line(inv, 'cpb'), 40);
    perform pg_temp.t460_change(inv, b);
    perform pg_temp.t460_move(inv, pg_temp.t460_line(inv, 'cpb'), f);
    perform pg_temp.t460_cancel_reopen(inv);
    perform pg_temp.t460_pay(inv);
  when 'X10' then
    inv := pg_temp.t460_sale(a, array['cpb']);
    perform pg_temp.t460_back(inv, pg_temp.t460_line(inv, 'cpb'), 40);
    perform pg_temp.t460_change(inv, b);
    perform pg_temp.t460_move(inv, pg_temp.t460_line(inv, 'cpb'), f);
    perform pg_temp.t460_merge(k, b);
    perform pg_temp.t460_cancel_reopen(inv);
    perform pg_temp.t460_pay(inv);
  -- KNOWN (460's NOT COVERED 4 (b), the review of 24 Oct 2026): the
  -- benefits leave the holder of the lot the records name after the Move.
  when 'M7' then
    inv := pg_temp.t460_sale(a, array['cp']);
    perform pg_temp.t460_back(inv, pg_temp.t460_line(inv, 'cp'), 40);
    perform pg_temp.t460_merge(k, a);
    perform pg_temp.t460_move(inv, pg_temp.t460_line(inv, 'cp'), f);
    perform pg_temp.t460_cancel_reopen(inv);
    perform pg_temp.t460_merge(k2, k);
    perform pg_temp.t460_pay(inv);
  -- X11, X12: two customer changes in one transaction share a time, so the
  -- second change's record is dated after the first, as two calls are (the
  -- holder is the customer the latest change moved the benefits to).
  when 'X11' then
    inv := pg_temp.t460_sale(a, array['cpb']);
    perform pg_temp.t460_back(inv, pg_temp.t460_line(inv, 'cpb'), 40);
    perform pg_temp.t460_change(inv, b);
    perform pg_temp.t460_move(inv, pg_temp.t460_line(inv, 'cpb'), f);
    perform pg_temp.t460_change(inv, c);
    update audit_logs set created_at = clock_timestamp()
     where record_id = inv and action = 'invoice_benefits_followed_reassignment' and new_data->>'to_customer' = c::text;
    perform pg_temp.t460_cancel_reopen(inv);
    perform pg_temp.t460_pay(inv);
  when 'X12' then
    inv := pg_temp.t460_sale(a, array['cpb']);
    perform pg_temp.t460_back(inv, pg_temp.t460_line(inv, 'cpb'), 40);
    perform pg_temp.t460_change(inv, b);
    perform pg_temp.t460_move(inv, pg_temp.t460_line(inv, 'cpb'), f);
    perform pg_temp.t460_cancel_reopen(inv);
    perform pg_temp.t460_change(inv, c);
    update audit_logs set created_at = clock_timestamp()
     where record_id = inv and action = 'invoice_benefits_followed_reassignment' and new_data->>'to_customer' = c::text;
    perform pg_temp.t460_pay(inv);
  when 'X13' then
    inv := pg_temp.t460_sale(a, array['cpb']);
    perform pg_temp.t460_back(inv, pg_temp.t460_line(inv, 'cpb'), 40);
    perform pg_temp.t460_change(inv, b);
    perform pg_temp.t460_move(inv, pg_temp.t460_line(inv, 'cpb'), f);
    perform pg_temp.t460_cancel_reopen(inv);
    perform pg_temp.t460_merge(k, b);
    perform pg_temp.t460_pay(inv);
  when 'K1' then
    inv := pg_temp.t460_sale(a, array['cpb', 'v'], array[1, 2]);
    perform pg_temp.t460_wait(inv);
    perform pg_temp.t460_change(inv, b, 'keep');
    perform pg_temp.t460_pay(inv);
  when 'K2' then
    inv := pg_temp.t460_sale(a, array['cp', 'cp']);
    perform pg_temp.t460_back(inv, pg_temp.t460_line(inv, 'cp', 1));
    perform pg_temp.t460_change(inv, b, 'keep');
    perform pg_temp.t460_cancel_reopen(inv);
    perform pg_temp.t460_pay(inv);
  when 'K3' then
    inv := pg_temp.t460_sale(a, array['cpb', 'v'], array[1, 2]);
    perform pg_temp.t460_back(inv, pg_temp.t460_line(inv, 'cpb'), 40);
    perform pg_temp.t460_cancel_reopen(inv);
    perform pg_temp.t460_pay(inv);
  when 'K4' then
    inv := pg_temp.t460_sale(a, array['cp']);
    perform pg_temp.t460_move(inv, pg_temp.t460_line(inv, 'cp'), f);
    perform pg_temp.t460_cancel_reopen(inv);
  when 'K5' then
    inv := pg_temp.t460_sale(a, array['cp']);
    perform pg_temp.t460_back(inv, pg_temp.t460_line(inv, 'cp'), 40);
    perform pg_temp.t460_move(inv, pg_temp.t460_line(inv, 'cp'), f);
    perform pg_temp.t460_cancel_reopen(inv);
    perform pg_temp.t460_change(inv, b);
    perform pg_temp.t460_pay(inv);
  when 'K6' then
    inv := pg_temp.t460_sale(a, array['cp']);
    perform pg_temp.t460_back(inv, pg_temp.t460_line(inv, 'cp'), 40);
    perform pg_temp.t460_move(inv, pg_temp.t460_line(inv, 'cp'), f);
    perform pg_temp.t460_cancel_reopen(inv);
    perform pg_temp.t460_merge(k, a);
    perform pg_temp.t460_pay(inv);
  when 'K8' then
    inv := pg_temp.t460_sale(a, array['cp']);
    perform pg_temp.t460_back(inv, pg_temp.t460_line(inv, 'cp'), 40);
    perform pg_temp.t460_move(inv, pg_temp.t460_line(inv, 'cp'), f);
    perform pg_temp.t460_cancel_reopen(inv);
    perform pg_temp.t460_pay(inv);
  when 'K9' then
    inv := pg_temp.t460_sale(a, array['cp']);
    perform pg_temp.t460_back(inv, pg_temp.t460_line(inv, 'cp'), 40);
    perform pg_temp.t460_move(inv, pg_temp.t460_line(inv, 'cp'), f);
    perform pg_temp.t460_cancel_reopen(inv);
    perform pg_temp.t460_pay(inv);
    perform pg_temp.t460_merge(k, a);
  end case;
  perform pg_temp.t460_put(pre, inv);
  return pg_temp.t460_outcome(pre, inv);
end $f$;
-- Who holds what in each case after 460 (and, under R, without it). Only
-- the customers that hold something are listed (the rest hold 0/0).
create temp table t460_case(k text primary key, ord int, kind text, after text, before text);
insert into t460_case values
  ('M1', 1, 'case', 'K 100.00/0',           'A 40.00/0, K 60.00/0'),
  ('M2', 2, 'case', 'K 110.00/2',           'A 110.00/0, K 0.00/2'),
  ('M3', 3, 'case', 'K 200.00/0',           'A 100.00/0, K 100.00/0'),
  ('M4', 4, 'case', 'K2 110.00/2',          'A 110.00/0, K2 0.00/2'),
  ('M5', 5, 'case', 'K 100.00/0',           'F 100.00/0'),
  ('X1', 6, 'case', 'B 220.00/0',           'A 110.00/0, B 110.00/0'),
  ('X2', 7, 'case', 'B 0.00/2',             'A 0.00/1, B 0.00/1'),
  ('X3', 8, 'case', 'B 110.00/2',           'A 110.00/2'),
  ('X4', 9, 'case', 'B 0.00/2',             'A 0.00/2'),
  ('X5', 10, 'case', 'B 0.00/2',            'A 0.00/2'),
  ('X6', 11, 'case', 'B 110.00/2',          'A 110.00/2'),
  ('X7', 12, 'case', 'K 110.00/2',          'A 110.00/2'),
  ('X8', 13, 'case', 'A 0.00/2, B 140.00/0', 'A 140.00/2'),
  ('M6', 14, 'case', 'F 60.00/0, K 40.00/0', 'A 40.00/0, F 60.00/0'),
  -- X9 and X10 need 461 (before it a customer change refuses a partly
  -- refunded lot as "Partly spent", so the path cannot happen): checked
  -- where 461 is in, and the refusal where it is not (section 5).
  ('X9', 15, 'case461', 'B 54.00/0, F 56.00/0', 'A 44.00/0, B 10.00/0, F 56.00/0'),
  ('X10', 16, 'case461', 'B 44.00/0, F 56.00/0, K 10.00/0', 'A 44.00/0, F 56.00/0, K 10.00/0'),
  ('K1', 21, 'control', 'A 110.00/2', 'A 110.00/2'),
  ('K2', 22, 'control', 'A 200.00/0', 'A 200.00/0'),
  ('K3', 23, 'control', 'A 110.00/2', 'A 110.00/2'),
  ('K4', 24, 'control', 'F 100.00/0', 'F 100.00/0'),
  ('K5', 25, 'control', 'A 40.00/0, F 60.00/0', 'A 40.00/0, F 60.00/0'),
  ('K6', 26, 'control', 'A 40.00/0, F 60.00/0', 'A 40.00/0, F 60.00/0'),
  ('K8', 28, 'control', 'A 40.00/0, F 60.00/0', 'A 40.00/0, F 60.00/0'),
  ('K9', 29, 'control', 'F 60.00/0, K 40.00/0', 'F 60.00/0, K 40.00/0');
create function pg_temp.t460_who(p_out jsonb) returns text language sql as $f$
  select coalesce(string_agg(h.key || ' ' || h.value, ', ' order by h.key), '-')
    from jsonb_each_text(p_out->'holds') h where h.value <> '0.00/0' $f$;

-- ===== R. Without 460: each case gives back to the record the benefits left (undone) =====
\if :{?nomig}
do $$ begin raise notice 'NOTE R: -v nomig=1 (460 in), so the faults without it are not reproduced'; end $$;
\else
do $$
declare c record; o jsonb; res text := '';
begin
  insert into t460_fp values ('start', pg_temp.t460_fingerprint());
  if pg_temp.t460_in() then
    raise notice 'NOTE R: 460 was in before this suite started, so the faults are not reproduced'; return; end if;
  begin
    for c in select * from t460_case where kind = 'case' or kind = 'case461' and pg_temp.t460_461_in() order by ord loop
      o := pg_temp.t460_run(c.k, 'R');
      perform pg_temp.t460_check(pg_temp.t460_who(o) = c.before,
        'R ' || c.k || ' without 460 holds ' || pg_temp.t460_who(o) || ', not ' || c.before || ': ' || o::text);
      res := res || format(E'\n  %s: %s (%s)', c.k, pg_temp.t460_who(o), o->>'status');
    end loop;
    -- M1 is 448's NOT COVERED 2 as it read: the kept record's S$60 reads as
    -- spent.
    perform pg_temp.t460_check(pg_temp.t460_codes(pg_temp.t460_id('M1/R'), 'cancel') = 'credit_used',
      'R M1 without 460 asks ' || pg_temp.t460_codes(pg_temp.t460_id('M1/R'), 'cancel'));
    -- M6 (and X9 where 461 is in) without 460: THE GAP, the S$40 (S$44) on
    -- a lot no record names: Cancel asks credit_used and its refund due is
    -- S$60 although S$100 was received.
    perform pg_temp.t460_check(pg_temp.t460_codes(pg_temp.t460_id('M6/R'), 'cancel') = 'credit_used'
        and invoice_action_plan(pg_temp.t460_id('M6/R'), 'cancel', '[]')->>'refund_due' = '60.00'
        and invoice_net_received(pg_temp.t460_id('M6/R')) = 100,
      'R M6 without 460: ' || pg_temp.t460_codes(pg_temp.t460_id('M6/R'), 'cancel') || ' / '
      || coalesce(invoice_action_plan(pg_temp.t460_id('M6/R'), 'cancel', '[]')->>'refund_due', '?'));
    if pg_temp.t460_461_in() then
      perform pg_temp.t460_check(pg_temp.t460_codes(pg_temp.t460_id('X9/R'), 'cancel') = 'credit_used'
          and invoice_action_plan(pg_temp.t460_id('X9/R'), 'cancel', '[]')->>'refund_due' = '60.00'
          and pg_temp.t460_codes(pg_temp.t460_id('X10/R'), 'cancel') = 'credit_used',
        'R X9/X10 without 460 (461 in): ' || pg_temp.t460_codes(pg_temp.t460_id('X9/R'), 'cancel') || ' / '
        || coalesce(invoice_action_plan(pg_temp.t460_id('X9/R'), 'cancel', '[]')->>'refund_due', '?'));
    end if;
    -- X3 and X4 without 460: the change while it waited left no record.
    perform pg_temp.t460_check(not exists (select 1 from audit_logs where record_id = pg_temp.t460_id('X3/R')
                                             and action = 'invoice_benefits_followed_reassignment'),
      'R X3 without 460 recorded the change');
    raise notice 'PASS R: without 460 (undone), each case gives back to the record the benefits left (who holds what):%', res;
    raise exception using errcode = 'P0990', message = 'undo';
  exception when sqlstate 'P0990' then null;
  end;
end $$;
\endif

-- ===== 0. The controls before 460 =====
do $$
declare c record; o jsonb;
begin
  if not exists (select 1 from t460_fp where k = 'start') then
    insert into t460_fp values ('start', pg_temp.t460_fingerprint()); end if;
  if pg_temp.t460_in() then
    raise notice 'NOTE 0: 460 was in before this suite started, so the before/after comparison is skipped; the controls are still checked after it';
    return;
  end if;
  for c in select * from t460_case where kind = 'control' order by ord loop
    o := pg_temp.t460_run(c.k, 'before');
    perform pg_temp.t460_check(pg_temp.t460_who(o) = c.before and o->>'records' = '',
      '0 ' || c.k || ' before 460 holds ' || pg_temp.t460_who(o) || ': ' || o::text);
    insert into t460_before values (c.k, o);
  end loop;
  raise notice 'PASS 0: before 460 the controls hold as expected (%); outcomes recorded',
    (select string_agg(k || ' ' || after, '; ' order by ord) from t460_case where kind = 'control');
end $$;

-- ===== 9. The refusal (before 460 is installed) =====
\if :{?nomig}
do $$ begin raise notice 'NOTE 9: -v nomig=1 (460 in), so its refusal is not tried'; end $$;
\else
-- (1) Credit given back to a record the benefits had left: M1 and X1.
savepoint t460_refusal;
do $$ begin perform pg_temp.t460_run('M1', 'F'); perform pg_temp.t460_run('X1', 'F'); end $$;
select string_agg(invoice_no, ', ' order by invoice_no) as t460_faulty from invoices
 where id in (pg_temp.t460_id('M1/F'), pg_temp.t460_id('X1/F')) \gset
\set ON_ERROR_STOP 0
\ir ../../../supabase/460_reopened_benefits_go_to_current_customer.sql
\set ON_ERROR_STOP 1
rollback to savepoint t460_refusal;
select pg_temp.t460_check(:'LAST_ERROR_MESSAGE' = '460: 2 invoice(s) had credit put back by a reopening on a record its benefits had left ('
         || :'t460_faulty' || '). Decide what each customer should hold, then apply. Nothing was changed.',
       '9 (1) 460 on credit given back to the wrong record: ' || :'LAST_ERROR_MESSAGE') as t460_9_1 \gset
-- (1b) THE GAP (the together check of 460 and 461, 24 Oct 2026): credit
-- given back on the lot a merge (M6), or with 461 in a customer change
-- (X9), had replaced before the benefit row was moved on (Move): on a lot
-- no record names.
savepoint t460_refusal;
do $$ begin perform pg_temp.t460_run('M6', 'F'); if pg_temp.t460_461_in() then perform pg_temp.t460_run('X9', 'F'); end if; end $$;
select count(*) as t460_nf, string_agg(invoice_no, ', ' order by invoice_no) as t460_faulty from invoices
 where id in (pg_temp.t460_id('M6/F'), pg_temp.t460_id('X9/F')) \gset
\set ON_ERROR_STOP 0
\ir ../../../supabase/460_reopened_benefits_go_to_current_customer.sql
\set ON_ERROR_STOP 1
rollback to savepoint t460_refusal;
select pg_temp.t460_check(:'LAST_ERROR_MESSAGE' = '460: ' || :'t460_nf' || ' invoice(s) had credit put back by a reopening on a record its benefits had left ('
         || :'t460_faulty' || '). Decide what each customer should hold, then apply. Nothing was changed.',
       '9 (1b) 460 on credit given back on a lot a merge or a change replaced before a Move: ' || :'LAST_ERROR_MESSAGE') as t460_9_1b \gset
-- (2) A voucher given again to the old customer after a recorded change: X2.
savepoint t460_refusal;
do $$ begin perform pg_temp.t460_run('X2', 'F'); end $$;
select invoice_no as t460_faulty from invoices where id = pg_temp.t460_id('X2/F') \gset
\set ON_ERROR_STOP 0
\ir ../../../supabase/460_reopened_benefits_go_to_current_customer.sql
\set ON_ERROR_STOP 1
rollback to savepoint t460_refusal;
select pg_temp.t460_check(:'LAST_ERROR_MESSAGE' = '460: 1 invoice(s) have a voucher a reopening gave again held by a customer its benefits had left ('
         || :'t460_faulty' || '). Decide what each customer should hold, then apply. Nothing was changed.',
       '9 (2) 460 on a voucher given again to the old customer: ' || :'LAST_ERROR_MESSAGE') as t460_9_2 \gset
-- (4) A reopened invoice waiting for a customer who holds none of it: X3
-- up to the change.
savepoint t460_refusal;
do $$
declare a uuid := pg_temp.t460_cust('W/F/A'); b uuid := pg_temp.t460_cust('W/F/B'); inv uuid;
begin
  inv := pg_temp.t460_sale(a, array['cpb', 'v'], array[1, 2]);
  perform pg_temp.t460_wait(inv);
  perform pg_temp.t460_change(inv, b);
  perform pg_temp.t460_put('W/F', inv);
end $$;
select invoice_no as t460_faulty from invoices where id = pg_temp.t460_id('W/F') \gset
\set ON_ERROR_STOP 0
\ir ../../../supabase/460_reopened_benefits_go_to_current_customer.sql
\set ON_ERROR_STOP 1
rollback to savepoint t460_refusal;
select pg_temp.t460_check(:'LAST_ERROR_MESSAGE' = '460: 1 reopened invoice(s) wait with credit or vouchers held by someone other than their customer ('
         || :'t460_faulty' || '). Decide who should receive them, then apply. Nothing was changed.',
       '9 (4) 460 on a reopened invoice waiting for another customer: ' || :'LAST_ERROR_MESSAGE') as t460_9_4 \gset
do $$
begin
  perform pg_temp.t460_check(pg_temp.t460_fingerprint() = (select fp from t460_fp where k = 'start') and not pg_temp.t460_in(),
    '9 a refused 460 changed functions');
  raise notice 'PASS 9: where a reopening already gave credit back to a record its benefits had left (M1, X1) or on a lot a merge or a change had replaced before a Move (M6%), gave a voucher again to the old customer after a recorded change (X2), or a reopened invoice waits for a customer who holds none of it (X3 before it is paid), 460 refuses, names the invoices and changes nothing',
    case when pg_temp.t460_461_in() then '; with 461 in, X9' else '' end;
end $$;
\endif

-- ===== 3. Either order with 461 (before 460 is installed) =====
\if :{?nomig}
do $$ begin raise notice 'NOTE 3: -v nomig=1 (460 in), so installing it over a stand-in for 461 is not tried'; end $$;
\else
savepoint t460_order;
-- A stand-in for 461: a line added inside the lots' selection of
-- move_invoice_benefits_to_customer and inside the credit rows of
-- invoice_transferable_benefits (461 changes those two parts), at lines 460
-- itself needs there, so also on top of the real 461 where it is in.
do $$
declare d text; c_sep constant text := E'\n  union all\n';
  c_mv_s constant text := E'  for r_lot in\n    select l.* from public.customer_credit_lots l\n';
begin
  if pg_temp.t460_461_in() then
    raise notice 'NOTE 3: 461 is in already, so the stand-in goes on top of its text'; end if;
  d := pg_get_functiondef('public.move_invoice_benefits_to_customer(uuid,uuid,uuid,text)'::regprocedure);
  perform pg_temp.t460_check(position(c_mv_s in d) > 0, '3 the lots'' selection 460 needs is not in move_invoice_benefits_to_customer');
  execute replace(d, c_mv_s, c_mv_s || E'       -- T460 stand-in for 461\n');
  d := pg_get_functiondef('public.invoice_transferable_benefits(uuid)'::regprocedure);
  perform pg_temp.t460_check(position(c_sep in d) > 0, '3 the list has no second part');
  execute overlay(d placing c_sep || E'  -- T460 stand-in for 461\n' from position(c_sep in d) for length(c_sep));
  perform pg_temp.t460_check(position('T460 stand-in' in pg_get_functiondef('public.move_invoice_benefits_to_customer(uuid,uuid,uuid,text)'::regprocedure)) > 0
    and position('T460 stand-in' in pg_get_functiondef('public.invoice_transferable_benefits(uuid)'::regprocedure)) > 0, '3 the stand-in is not in');
end $$;
\ir ../../../supabase/460_reopened_benefits_go_to_current_customer.sql
do $$
declare o jsonb;
begin
  perform pg_temp.t460_check(pg_temp.t460_in()
    and position('T460 stand-in' in pg_get_functiondef('public.move_invoice_benefits_to_customer(uuid,uuid,uuid,text)'::regprocedure)) > 0
    and position('-- 460 (the Owner' in pg_get_functiondef('public.move_invoice_benefits_to_customer(uuid,uuid,uuid,text)'::regprocedure)) > 0
    and position('T460 stand-in' in pg_get_functiondef('public.invoice_transferable_benefits(uuid)'::regprocedure)) > 0
    and position('-- 460 (the Owner' in pg_get_functiondef('public.invoice_transferable_benefits(uuid)'::regprocedure)) > 0,
    '3 460 over the stand-in did not keep both');
  o := pg_temp.t460_run('X4', 'O');
  perform pg_temp.t460_check(pg_temp.t460_who(o) = 'B 0.00/2', '3 X4 with 460 over the stand-in holds ' || pg_temp.t460_who(o));
end $$;
rollback to savepoint t460_order;
-- Changed outside those parts: refused.
savepoint t460_order;
do $$
declare d text;
begin
  d := pg_get_functiondef('public.move_invoice_benefits_to_customer(uuid,uuid,uuid,text)'::regprocedure);
  execute replace(d, E'  v_wallet := public.ensure_customer_wallet(p_customer_id);\n',
                     E'  -- T460 a change elsewhere\n  v_wallet := public.ensure_customer_wallet(p_customer_id);\n');
end $$;
\set ON_ERROR_STOP 0
\ir ../../../supabase/460_reopened_benefits_go_to_current_customer.sql
\set ON_ERROR_STOP 1
rollback to savepoint t460_order;
select pg_temp.t460_check(:'LAST_ERROR_MESSAGE' like '460: public.move_invoice_benefits_to_customer(uuid,uuid,uuid,text) is not the version this was tested against, outside the lots'' selection 461 may change (md5 %',
       '3 460 over a change outside the lots'' selection: ' || :'LAST_ERROR_MESSAGE') as t460_3_refused \gset
do $$
begin
  perform pg_temp.t460_check(pg_temp.t460_fingerprint() = (select fp from t460_fp where k = 'start') and not pg_temp.t460_in(),
    '3 the order checks left a change');
  raise notice 'PASS 3: over a stand-in for 461 (a change inside the lots'' selection and the credit rows) 460 installs, keeps the change and works (X4); over a change elsewhere in move_invoice_benefits_to_customer it refuses';
end $$;
\endif

-- ===== 10. Install 460, twice =====
\if :{?nomig}
do $$ begin perform pg_temp.t460_check(pg_temp.t460_in(), '10 -v nomig=1 but 460 is not in'); end $$;
\else
do $$
begin
  insert into t460_fp values ('grants',
    pg_temp.t460_grants('apply_reopened_invoice_benefits()') || ' | ' || pg_temp.t460_grants('apply_reopened_invoice_vouchers()')
    || ' | ' || pg_temp.t460_grants('move_invoice_benefits_to_customer(uuid,uuid,uuid,text)')
    || ' | ' || pg_temp.t460_grants('invoice_transferable_benefits(uuid)')
    || ' | ' || pg_temp.t460_grants('invoice_reopen_preview(uuid)'));
end $$;
\ir ../../../supabase/460_reopened_benefits_go_to_current_customer.sql
do $$ begin insert into t460_fp values ('first', pg_temp.t460_fingerprint()); end $$;
\ir ../../../supabase/460_reopened_benefits_go_to_current_customer.sql
do $$ begin insert into t460_fp values ('second', pg_temp.t460_fingerprint()); end $$;
\endif
do $$
begin
  perform pg_temp.t460_check(pg_temp.t460_in()
    and md5(pg_get_functiondef('public.apply_reopened_invoice_benefits()'::regprocedure)) = '3e659dafdbacb00ad953f99d00c3c6c9'
    and md5(pg_get_functiondef('public.invoice_reopen_preview(uuid)'::regprocedure)) = '4b49c0c64eeb1b5962b605bbf56ea159'
    and md5(pg_get_functiondef('public.apply_reopened_invoice_vouchers()'::regprocedure)) = '28d3b7a69b91ddebcdb200559d96a0ef'
    and md5(pg_get_functiondef('public.invoice_own_voucher_ids(uuid)'::regprocedure)) = '9340840f1ce4e031ec3613198688ba2e'
    and md5(pg_get_functiondef('public.invoice_benefits_holder(uuid,uuid,timestamp with time zone)'::regprocedure)) = '55995ff6e1ffd4a1172cb930512a34b0',
    '10 460 is not installed as tested');
  -- The two functions 461 also changes: 460's AFTER with 461's part left
  -- out, always; their whole text where 461 is not in.
  perform pg_temp.t460_check(pg_temp.t460_no461('move_invoice_benefits_to_customer(uuid,uuid,uuid,text)') = 'b434f77373e6ba07cc4b1fb30a2f4d50'
    and pg_temp.t460_no461('invoice_transferable_benefits(uuid)') = 'e5df1d68f73847f5d9faa7b04bfd81fe',
    '10 the two functions 461 also changes are not 460''s AFTER outside 461''s part');
  if not pg_temp.t460_461_in() then
    perform pg_temp.t460_check(md5(pg_get_functiondef('public.move_invoice_benefits_to_customer(uuid,uuid,uuid,text)'::regprocedure)) = '5a165f7035151f8f711fc2ac293e9b62'
      and md5(pg_get_functiondef('public.invoice_transferable_benefits(uuid)'::regprocedure)) = 'c568df874f2667f6a313d7aac0b4c086',
      '10 the two functions 461 also changes are not 460''s AFTER (461 not in)');
  end if;
  if exists (select 1 from t460_fp where k = 'first') then
    perform pg_temp.t460_check((select fp from t460_fp where k = 'second') = (select fp from t460_fp where k = 'first'),
      '10 the second run of 460 changed functions');
    perform pg_temp.t460_check(split_part((select fp from t460_fp where k = 'first'), ' ', 2)::int
                               = split_part((select fp from t460_fp where k = 'start'), ' ', 2)::int + 2,
      '10 460 did not add exactly two functions');
    perform pg_temp.t460_check(
      pg_temp.t460_grants('apply_reopened_invoice_benefits()') || ' | ' || pg_temp.t460_grants('apply_reopened_invoice_vouchers()')
      || ' | ' || pg_temp.t460_grants('move_invoice_benefits_to_customer(uuid,uuid,uuid,text)')
      || ' | ' || pg_temp.t460_grants('invoice_transferable_benefits(uuid)')
      || ' | ' || pg_temp.t460_grants('invoice_reopen_preview(uuid)') = (select fp from t460_fp where k = 'grants'),
      '10 the grants changed');
  end if;
  perform pg_temp.t460_check((select count(*) from pg_proc where pronamespace = 'public'::regnamespace
                               and proname in ('apply_reopened_invoice_benefits', 'apply_reopened_invoice_vouchers',
                                               'move_invoice_benefits_to_customer', 'invoice_transferable_benefits',
                                               'invoice_own_voucher_ids', 'invoice_benefits_holder', 'invoice_reopen_preview')) = 7, '10 an overload exists');
  perform pg_temp.t460_check(not has_function_privilege('anon', 'public.invoice_own_voucher_ids(uuid)', 'execute')
    and not has_function_privilege('authenticated', 'public.invoice_own_voucher_ids(uuid)', 'execute')
    and has_function_privilege('service_role', 'public.invoice_own_voucher_ids(uuid)', 'execute')
    and not has_function_privilege('anon', 'public.invoice_benefits_holder(uuid,uuid,timestamp with time zone)', 'execute')
    and not has_function_privilege('authenticated', 'public.invoice_benefits_holder(uuid,uuid,timestamp with time zone)', 'execute')
    and has_function_privilege('service_role', 'public.invoice_benefits_holder(uuid,uuid,timestamp with time zone)', 'execute')
    and has_function_privilege('authenticated', 'public.invoice_transferable_benefits(uuid)', 'execute')
    and not has_function_privilege('authenticated', 'public.move_invoice_benefits_to_customer(uuid,uuid,uuid,text)', 'execute')
    and has_function_privilege('authenticated', 'public.invoice_reopen_preview(uuid)', 'execute')
    and not has_function_privilege('anon', 'public.invoice_reopen_preview(uuid)', 'execute'),
    '10 who may call them is not as intended');
  raise notice 'PASS 10: 460 installed as tested (%); %; no overload; the two helpers the server''s alone, the list still signed-in staff''s',
    case when pg_temp.t460_461_in() then 'with 461 in: its two shared functions checked with 461''s part left out' else '461 not in' end,
    coalesce('the second run changed nothing (' || (select fp from t460_fp where k = 'second') || '), two functions added, grants as before',
             'it was in before the suite (nomig)');
end $$;

-- ===== 1. Each case after 460 =====
do $$
declare c record; o jsonb; inv uuid; pre text; holds0 jsonb; lots0 jsonb; res text := '';
begin
  for c in select * from t460_case where kind = 'case' or kind = 'case461' and pg_temp.t460_461_in() order by ord loop
    o := pg_temp.t460_run(c.k, 'after');
    pre := c.k || '/after'; inv := pg_temp.t460_id(pre);
    perform pg_temp.t460_check(pg_temp.t460_who(o) = c.after,
      '1 ' || c.k || ' holds ' || pg_temp.t460_who(o) || ', not ' || c.after || ': ' || o::text);
    perform pg_temp.t460_check(o->>'status' = 'paid' and o->>'waiting' = '0/0' and o->>'records' = ''
      and o->>'cancel' !~ 'credit_used|voucher_redeemed', '1 ' || c.k || ' after 460: ' || o::text);
    -- The invoice's records name the lots that hold its credit: every lot
    -- of the case's customers that holds credit is one the invoice names.
    perform pg_temp.t460_check(not exists (
        select 1 from customer_credit_lots l join t460 t on t.id = l.customer_id and t.k like pre || '/%'
         where l.remaining_amount > 0
           and not exists (select 1 from invoice_benefit_values b where b.invoice_id = inv and b.lot_id = l.id)),
      '1 ' || c.k || ': credit sits on a lot the invoice does not name');
    -- Each customer's credit statement (its ledger) ends at what their lots
    -- hold: the credit given back and moved is in their ledger as it is on
    -- their lots.
    perform pg_temp.t460_check(not exists (
        select 1 from t460 t
         where t.k like pre || '/%'
           and coalesce((select s.wallet_balance from customer_credit_statement(t.id) s order by s.entry_date desc, s.entry_seq desc limit 1), 0)
               <> coalesce((select sum(l.remaining_amount) from customer_credit_lots l where l.customer_id = t.id), 0)),
      '1 ' || c.k || ': a credit statement does not end at what the lots hold');
    -- A further cancel takes it back from the same holder, and a reopening
    -- (the money still held: settled at once) gives it back there, adding no lot.
    holds0 := o->'holds'; lots0 := o->'lots';
    perform cancel_invoice_recorded(inv, 'T460 again', gen_random_uuid());
    perform pg_temp.t460_check(pg_temp.t460_used(inv) = '-'
      and not exists (select 1 from customer_credit_lots l join t460 t on t.id = l.customer_id and t.k like pre || '/%'
                       where l.remaining_amount > 0 and l.id in (select b.lot_id from invoice_benefit_values b where b.invoice_id = inv)),
      '1 ' || c.k || ' cancelled again: used ' || pg_temp.t460_used(inv) || ', ' || (pg_temp.t460_outcome(pre, inv)->'holds')::text);
    perform reopen_invoice(inv, 'T460 again', gen_random_uuid());
    o := pg_temp.t460_outcome(pre, inv);
    perform pg_temp.t460_check(o->'holds' = holds0 and o->'lots' = lots0 and o->>'status' = 'paid' and o->>'records' = '',
      '1 ' || c.k || ' reopened again: ' || o::text || ', before the cancel ' || holds0::text);
    res := res || format(E'\n  %s: %s', c.k, c.after);
  end loop;
  -- M1: the kept record's new lot takes a refund by line (capped by it) and
  -- a Move, as any lot.
  inv := pg_temp.t460_id('M1/after');
  perform pg_temp.t460_back(inv, pg_temp.t460_line(inv, 'cp'), 40);
  perform pg_temp.t460_check(pg_temp.t460_holds(pg_temp.t460_id('M1/after/K')) = '60.00/0',
    '1 M1: S$40 refunded by line after 460, the kept record holds ' || pg_temp.t460_holds(pg_temp.t460_id('M1/after/K')));
  perform pg_temp.t460_move(inv, pg_temp.t460_line(inv, 'cp'), pg_temp.t460_cust('M1/after/F'));
  perform pg_temp.t460_check(pg_temp.t460_holds(pg_temp.t460_id('M1/after/K')) = '0.00/0'
      and pg_temp.t460_holds(pg_temp.t460_id('M1/after/F')) = '60.00/0',
    '1 M1: moved after 460, the kept record holds ' || pg_temp.t460_holds(pg_temp.t460_id('M1/after/K'))
    || ', the friend ' || pg_temp.t460_holds(pg_temp.t460_id('M1/after/F')));
  -- X5: the limited vouchers moved with their stock (taken at the other
  -- store, given back at the first).
  perform pg_temp.t460_check((select string_agg(distinct s.code, ',') from invoice_benefit_values b
                                join customer_reward_vouchers v on v.id = b.reward_voucher_id join stores s on s.id = v.store_id
                               where b.invoice_id = pg_temp.t460_id('X5/after') and v.status = 'held') = 'T460S2'
      and pg_temp.t460_stock('store') = 100 and pg_temp.t460_stock('store2') = 98,
    '1 X5: the vouchers are not at the other store with their stock (' || pg_temp.t460_stock('store') || '/' || pg_temp.t460_stock('store2') || ')');
  raise notice 'PASS 1: after 460, each case gives back to whoever the benefits belong to now, on lots the invoice names with their origin kept; nothing reads as used; cancelled and reopened again, the same holder, no lot added:%', res;
end $$;

-- ===== 2. The controls after 460 =====
do $$
declare c record; o jsonb; b jsonb;
begin
  for c in select * from t460_case where kind = 'control' order by ord loop
    o := pg_temp.t460_run(c.k, 'after');
    perform pg_temp.t460_check(pg_temp.t460_who(o) = c.after and o->>'records' = '',
      '2 ' || c.k || ' after 460 holds ' || pg_temp.t460_who(o) || ': ' || o::text);
    select v into b from t460_before where k = c.k;
    if b is not null then
      perform pg_temp.t460_check(o = b, '2 ' || c.k || ' changed with 460: before ' || b::text || ', after ' || o::text);
    end if;
    -- K5, K6 (NOT COVERED 4) and K8 (the plain Move): nothing reads as spent, the cancel's refund
    -- due is the S$100 the invoice holds, and Cancel takes back the S$40 on
    -- A's lot and F's S$60 (the first draft of 460: credit_used, S$60, and
    -- the S$40 kept on a lot no record named).
    if c.k in ('K5', 'K6', 'K8') then
      perform pg_temp.t460_check(o->>'cancel' = '-' and o->>'due' = '100.00'
          and pg_temp.t460_used(pg_temp.t460_id(c.k || '/after')) = '-'
          and pg_temp.t460_codes(pg_temp.t460_id(c.k || '/after'), 'refund_full') = '-'
          and not exists (select 1 from customer_credit_lots l join t460 t on t.id = l.customer_id and t.k like c.k || '/after/%'
                           where l.remaining_amount > 0
                             and not exists (select 1 from invoice_benefit_values bv
                                              where bv.invoice_id = pg_temp.t460_id(c.k || '/after') and bv.lot_id = l.id)),
        '2 ' || c.k || ' after 460 reads as spent, or credit sits on a lot the invoice does not name: ' || o::text
        || ', used ' || pg_temp.t460_used(pg_temp.t460_id(c.k || '/after')));
      perform cancel_invoice_recorded(pg_temp.t460_id(c.k || '/after'), 'T460 cancel K5/K6/K8', gen_random_uuid());
      perform pg_temp.t460_check(pg_temp.t460_who(pg_temp.t460_outcome(c.k || '/after', pg_temp.t460_id(c.k || '/after'))) = '-',
        '2 ' || c.k || ' cancelled after 460: ' || pg_temp.t460_outcome(c.k || '/after', pg_temp.t460_id(c.k || '/after'))::text);
    end if;
  end loop;
  raise notice 'PASS 2: the controls (''keep'' while waiting and before the cancel, a plain cycle, a Move, a Move after a refund then a change or a merge, a Move after a refund with neither, and a merge after that reopening was settled) read %; K5, K6 and K8 read nothing as spent (refund due S$100) and Cancel takes all of it back',
    case when exists (select 1 from t460_before) then 'exactly as before 460 (status, money, who holds what, lots, plans)'
         else 'as expected (no before figures: 460 was in already)' end;
end $$;

-- ===== 4. The change is recorded; the summary lists what moves =====
do $$
declare a uuid := pg_temp.t460_cust('P/after/A'); b uuid := pg_temp.t460_cust('P/after/B'); inv uuid; r jsonb; n int;
begin
  -- A change made while it waits moves nothing and is recorded; 'keep' is not.
  inv := pg_temp.t460_sale(a, array['v'], array[2]);
  perform pg_temp.t460_cancel_reopen(inv);
  perform pg_temp.t460_check((select count(*) from audit_logs where record_id = pg_temp.t460_id('X3/after')
                               and action = 'invoice_benefits_followed_reassignment'
                               and new_data->>'to_customer' = pg_temp.t460_id('X3/after/B')::text
                               and (new_data->>'vouchers')::int = 0 and (new_data->>'credit_lots')::int = 0) = 1,
    '4 X3''s change while it waited is not recorded');
  perform pg_temp.t460_check(not exists (select 1 from audit_logs where record_id = pg_temp.t460_id('K1/after')
                                           and action = 'invoice_benefits_followed_reassignment'),
    '4 K1''s ''keep'' was recorded as taking the benefits along');
  -- The review summary before the save lists the reopening's 2 as moving.
  r := preview_invoice_correction(inv, pg_temp.t460_header(inv, b, 'transfer'));
  select count(*) into n from jsonb_array_elements(r->'effects') e, jsonb_array_elements(coalesce(e->'items', '[]')) x
   where e->>'area' = 'benefits' and e->>'change' = 'transferring';
  perform pg_temp.t460_check(n = 1, '4 the summary lists ' || n || ' moving, not the 2 the reopening gave: ' || coalesce((r->'effects')::text, '<none>'));
  raise notice 'PASS 4: a change that takes the benefits along is recorded also when nothing was left to move (X3); ''keep'' records none (K1); the review summary lists the vouchers a reopening gave as moving';
end $$;

-- ===== 5. The reopening is refused where what would go back fills the lot =====
-- The refund before the merge (or, with 461 in, the customer change) and
-- the Move after it, as M6 and X9, with more refunded: what the payment
-- would give back is as much as the lot the records name was granted, or
-- more, so it cannot go there (its credit would read as untouched, or the
-- lot cannot hold it), and the reopening is refused, changing nothing; just
-- below that it goes there, and a later customer change refuses the lot as
-- partly spent (not moving it without its records).
create function pg_temp.t460_r5(p_tag text, p_route text, p_amount numeric) returns jsonb language plpgsql as $f$
declare a uuid := pg_temp.t460_cust('R5/' || p_tag || '/A'); k uuid := pg_temp.t460_cust('R5/' || p_tag || '/K');
        f uuid := pg_temp.t460_cust('R5/' || p_tag || '/F'); inv uuid; pv jsonb; msg text; q int;
begin
  inv := pg_temp.t460_sale(a, array[case when p_route = 'merge' then 'cp' else 'cpb' end]);
  perform pg_temp.t460_back(inv, pg_temp.t460_line(inv, case when p_route = 'merge' then 'cp' else 'cpb' end), p_amount);
  if p_route = 'merge' then perform pg_temp.t460_merge(k, a); else perform pg_temp.t460_change(inv, k); end if;
  perform pg_temp.t460_move(inv, pg_temp.t460_line(inv, case when p_route = 'merge' then 'cp' else 'cpb' end), f);
  perform cancel_invoice_recorded(inv, 'T460 cancel', gen_random_uuid());
  pv := invoice_reopen_preview(inv);
  begin
    perform reopen_invoice(inv, 'T460 reopen', gen_random_uuid());
  exception when others then msg := sqlerrm;
  end;
  select count(*) into q from invoice_reopen_benefits where invoice_id = inv;
  if msg is null then perform pg_temp.t460_pay(inv); end if;
  perform pg_temp.t460_put('R5/' || p_tag, inv);
  return jsonb_build_object('can_reopen', pv->'can_reopen', 'blockers', pv->'blockers', 'refused', msg, 'queued', q,
    'status', (select status::text from invoices where id = inv), 'due', invoice_action_plan(inv, 'cancel', '[]')->>'refund_due',
    'cancel', pg_temp.t460_codes(inv, 'cancel'), 'K', pg_temp.t460_holds(k), 'A', pg_temp.t460_holds(a), 'F', pg_temp.t460_holds(f));
end $f$;
do $$
declare o jsonb; c text; m text := 'Reopening would give back S$%s of credit refunded before this invoice''s customer was changed or merged, the rest of which was then moved to someone else (Move); the credit lot the invoice names for it cannot take that much back. Keep the invoice cancelled (its refund due stands), or ask the Owner.';
begin
  -- S$60 refunded of S$100 (the S$40 left moved on): refused.
  o := pg_temp.t460_r5('m60', 'merge', 60);
  perform pg_temp.t460_check(o->>'can_reopen' = 'false' and o->'blockers' ? format(m, '60.00')
      and o->>'refused' = 'Reopening requires resolution: ' || jsonb_build_array(format(m, '60.00'))::text
      and o->>'queued' = '0' and o->>'status' = 'cancelled' and o->>'due' = '40.00' and o->>'K' = '0.00/0' and o->>'F' = '0.00/0',
    '5 S$60 refunded, merged, moved, cancelled: the reopening is not refused as it should be: ' || o::text);
  -- Exactly half (S$50, the S$50 left moved on): the lot would hold all it
  -- was granted and read as untouched: refused.
  o := pg_temp.t460_r5('m50', 'merge', 50);
  perform pg_temp.t460_check(o->>'can_reopen' = 'false' and o->'blockers' ? format(m, '50.00') and o->>'status' = 'cancelled' and o->>'queued' = '0',
    '5 S$50 refunded, merged, moved, cancelled: the reopening is not refused: ' || o::text);
  -- S$49.99: it goes on the kept record's lot (S$49.99 of S$50.01), and a
  -- later customer change refuses that lot as partly spent.
  o := pg_temp.t460_r5('m4999', 'merge', 49.99);
  perform pg_temp.t460_check(o->>'refused' is null and o->>'status' = 'paid' and o->>'K' = '49.99/0' and o->>'F' = '50.01/0' and o->>'A' = '0.00/0'
      and o->>'cancel' = '-' and o->>'due' = '100.00',
    '5 S$49.99 refunded, merged, moved, cancelled, reopened, paid: ' || o::text);
  begin
    perform pg_temp.t460_change(pg_temp.t460_id('R5/m4999'), pg_temp.t460_cust('R5/m4999/C'));
    c := 'the change went through';
  exception when others then c := sqlerrm;
  end;
  perform pg_temp.t460_check(c like 'These benefits have already been used and cannot move with the invoice: Paid credit 49.99 (Partly spent).%',
    '5 S$49.99: a later customer change taking the benefits along: ' || c);
  if pg_temp.t460_461_in() then
    -- The customer change route (461): S$50 of a S$100 + S$10 package
    -- refunded (S$55 of credit), changed, the S$45 left moved on: refused.
    o := pg_temp.t460_r5('c50', 'change', 50);
    perform pg_temp.t460_check(o->>'can_reopen' = 'false' and o->'blockers' ? format(m, '55.00') and o->>'status' = 'cancelled' and o->>'queued' = '0'
        and o->>'due' = '50.00',
      '5 (461) S$50 refunded, changed, moved, cancelled: the reopening is not refused: ' || o::text);
  else
    -- Without 461 the change route cannot happen: a customer change refuses
    -- a partly refunded lot as partly spent (461's gap).
    begin
      perform pg_temp.t460_r5('c50', 'change', 50);
      c := 'the change went through';
    exception when others then c := sqlerrm;
    end;
    perform pg_temp.t460_check(c like 'These benefits have already been used and cannot move with the invoice: Paid credit 45.00 (Partly spent).%',
      '5 without 461: a change after a part refund: ' || c);
  end if;
  raise notice 'PASS 5: where what a reopening would give back is as much as the lot the records name was granted or more (S$60 or S$50 refunded of S$100, a merge, the rest moved on), the reopening is refused with the reason, changing nothing (still cancelled, refund due as it was); at S$49.99 it goes on that lot and a later customer change refuses it as partly spent%',
    case when pg_temp.t460_461_in() then '; with 461 in, by a customer change too (S$55 of a S$100 + S$10 package: refused)'
         else '; without 461 a customer change refuses the part-refunded lot as partly spent, so that route cannot happen' end;
end $$;

-- ===== 6. Credit of that lot that paid for another sale counts as taken =====
-- (the review of 24 Oct 2026). The holder of the lot the records name pays
-- a S$20 session from it (the wallet) after the merge or the change and
-- before the Move. A refund of that session gives its credit back on that
-- lot, so what the reopening puts there must leave room for it: otherwise
-- the refund could not be recorded (the lot would hold more than it was
-- granted; it goes through at 455), or it filled the lot back to all it was
-- granted and a later customer change moved it without its records (THE
-- GAP again); and with the reopening allowed, the session refunded while it
-- waited left the S$44 behind, silently, on the lot no record names.
create function pg_temp.t460_s6(p_tag text, p_route text, p_kind text, p_amount numeric) returns jsonb language plpgsql as $f$
declare a uuid := pg_temp.t460_cust('S6/' || p_tag || '/A'); k uuid := pg_temp.t460_cust('S6/' || p_tag || '/K');
        f uuid := pg_temp.t460_cust('S6/' || p_tag || '/F'); inv uuid; ses uuid; pv jsonb; msg text; q int; lot uuid;
        o jsonb; c text;
begin
  inv := pg_temp.t460_sale(a, array[p_kind]);
  perform pg_temp.t460_back(inv, pg_temp.t460_line(inv, p_kind), p_amount);
  if p_route = 'merge' then perform pg_temp.t460_merge(k, a); else perform pg_temp.t460_change(inv, k); end if;
  ses := pg_temp.t460_spend(k);
  perform pg_temp.t460_move(inv, pg_temp.t460_line(inv, p_kind), f);
  select bv.lot_id into lot from invoice_benefit_values bv join invoice_benefit_transfers bt on bt.source_benefit_id = bv.id
   where bv.invoice_id = inv;
  perform cancel_invoice_recorded(inv, 'T460 cancel', gen_random_uuid());
  pv := invoice_reopen_preview(inv);
  begin
    perform reopen_invoice(inv, 'T460 reopen', gen_random_uuid());
  exception when others then msg := sqlerrm;
  end;
  select count(*) into q from invoice_reopen_benefits where invoice_id = inv;
  if msg is null then perform pg_temp.t460_pay(inv); end if;
  perform pg_temp.t460_put('S6/' || p_tag, inv); perform pg_temp.t460_put('S6/' || p_tag || '/session', ses);
  o := jsonb_build_object('can_reopen', pv->'can_reopen', 'blockers', pv->'blockers', 'refused', msg, 'queued', q,
    'status', (select status::text from invoices where id = inv), 'due', invoice_action_plan(inv, 'cancel', '[]')->>'refund_due',
    'net', invoice_net_received(inv), 'cancel', pg_temp.t460_codes(inv, 'cancel'), 'refund_full', pg_temp.t460_codes(inv, 'refund_full'),
    'records', pg_temp.t460_records(inv),
    'lot', (select remaining_amount || '/' || original_amount from customer_credit_lots where id = lot),
    'K', pg_temp.t460_holds(k), 'A', pg_temp.t460_holds(a), 'F', pg_temp.t460_holds(f));
  -- The session's refund afterwards (cancelled and "Record refund paid").
  begin
    perform pg_temp.t460_unspend(ses);
    c := 'refunded';
  exception when others then c := sqlerrm;
  end;
  o := o || jsonb_build_object('session_refund', c, 'session_net', invoice_net_received(ses),
    'lot_after', (select remaining_amount || '/' || original_amount from customer_credit_lots where id = lot),
    'K_after', pg_temp.t460_holds(k), 'cancel_after', pg_temp.t460_codes(inv, 'cancel'),
    'due_after', invoice_action_plan(inv, 'cancel', '[]')->>'refund_due');
  return o;
end $f$;
do $$
declare o jsonb; c text; ses_ok text; m6 text := 'Reopening would give back S$%s of credit refunded before this invoice''s customer was changed or merged, the rest of which was then moved to someone else (Move); the credit lot the invoice names for it cannot take that much back (S$%s of its credit paid for other sales, which a refund puts back there). Keep the invoice cancelled (its refund due stands), or ask the Owner.';
  routes text[] := case when pg_temp.t460_461_in() then array['merge', 'change'] else array['merge'] end; r text;
begin
  foreach r in array routes loop
    -- (a) The reviewer's case (AA4 by the merge, AA1 by the change): S$40 of
    -- a S$100 + S$10 package refunded (S$44 of credit), the S$20 session
    -- paid from the S$56 lot, the S$36 left moved on: S$44 to go back and
    -- S$20 that can come back would hold S$64 of S$56, so the reopening is
    -- refused, changing nothing; the session's refund then goes through,
    -- its S$20 back on that lot (as at 455).
    o := pg_temp.t460_s6('a-' || r, r, 'cpb', 40);
    perform pg_temp.t460_check(o->>'can_reopen' = 'false' and o->'blockers' ? format(m6, '44.00', '20.00')
        and o->>'refused' = 'Reopening requires resolution: ' || jsonb_build_array(format(m6, '44.00', '20.00'))::text
        and o->>'queued' = '0' and o->>'status' = 'cancelled' and o->>'lot' = '0.00/56.00'
        and o->>'session_refund' = 'refunded' and o->>'lot_after' = '20.00/56.00' and o->>'A' = '0.00/0',
      '6 (a) ' || r || ': S$44 to go back, S$20 of the lot spent on a session: ' || o::text);
    -- (b) The same with S$20 refunded (S$22 of credit): S$22 + S$20 of S$78
    -- fits, so it is reopened and the S$22 goes on the lot the records
    -- name. While the session holds its S$20, Cancel rightly asks
    -- credit_used and its refund due is S$81.82 (S$20 of the S$110 of
    -- credit used is S$18.18 of the S$100 received); once the session is
    -- refunded nothing reads as spent and the refund due is the S$100
    -- received, the lot stays below what it was granted (S$42 of S$78), so
    -- a customer change still refuses it as partly spent, and Cancel takes
    -- it all back.
    o := pg_temp.t460_s6('b-' || r, r, 'cpb', 20);
    perform pg_temp.t460_check(o->>'refused' is null and o->>'status' = 'paid' and o->>'lot' = '22.00/78.00'
        and o->>'K' = '32.00/0' and o->>'F' = '58.00/0' and o->>'A' = '0.00/0' and o->>'records' = ''
        and o->>'cancel' = 'credit_used' and o->>'due' = '81.82' and (o->>'net')::numeric = 100
        and o->>'session_refund' = 'refunded' and o->>'lot_after' = '42.00/78.00' and o->>'K_after' = '52.00/0'
        and o->>'cancel_after' = '-' and o->>'due_after' = '100.00',
      '6 (b) ' || r || ': S$22 to go back, S$20 spent, reopened, paid, the session refunded: ' || o::text);
    begin
      perform pg_temp.t460_change(pg_temp.t460_id('S6/b-' || r), pg_temp.t460_cust('S6/b-' || r || '/C'));
      c := 'the change went through';
    exception when others then c := sqlerrm;
    end;
    perform pg_temp.t460_check(c like 'These benefits have already been used and cannot move with the invoice: Paid credit 42.00 (Partly spent).%',
      '6 (b) ' || r || ': a customer change after the session''s refund: ' || c);
    perform cancel_invoice_recorded(pg_temp.t460_id('S6/b-' || r), 'T460 cancel 6b', gen_random_uuid());
    perform pg_temp.t460_check(pg_temp.t460_holds(pg_temp.t460_id('S6/b-' || r || '/K')) = '0.00/0'
        and pg_temp.t460_holds(pg_temp.t460_id('S6/b-' || r || '/F')) = '0.00/0'
        and pg_temp.t460_holds(pg_temp.t460_id('S6/b-' || r || '/A')) = '0.00/0',
      '6 (b) ' || r || ': Cancel did not take it all back');
    -- (c) The reviewer's second case: a S$100 package, S$40 refunded, the
    -- S$20 session paid from the S$60 lot, the S$40 left moved on: S$40 +
    -- S$20 would fill the lot (all S$60 after the session's refund, which a
    -- later customer change would move without its records): refused.
    o := pg_temp.t460_s6('c-' || r, r, 'cp', 40);
    perform pg_temp.t460_check(o->>'can_reopen' = 'false' and o->'blockers' ? format(m6, '40.00', '20.00')
        and o->>'queued' = '0' and o->>'status' = 'cancelled' and o->>'lot' = '0.00/60.00'
        and o->>'session_refund' = 'refunded' and o->>'lot_after' = '20.00/60.00',
      '6 (c) ' || r || ': S$40 to go back, S$20 spent of S$60: ' || o::text);
  end loop;
  -- Without the session (M6, X9: S$40 of S$100) it is reopened, as section 1
  -- checks. With the session never refunded the reopening is refused all the
  -- same, as in (a), although the S$44 would then fit (whether it will be
  -- refunded cannot be known): NOT COVERED 4 (c).
  raise notice 'PASS 6: credit of the lot the records name that paid for another sale counts as taken: S$44 to go back with S$20 of a S$56 lot paid for a session, or S$40 with S$20 of a S$60 lot: the reopening is refused with the reason naming the S$20, changing nothing, and the session''s refund then goes through (as at 455); S$22 with S$20 of S$78: reopened, the S$22 on the lot the records name, nothing reads as spent once the session is refunded, the lot stays below what it was granted (S$42 of S$78) and a customer change still refuses it as partly spent, and Cancel takes it all back (%)',
    array_to_string(routes, ' and ') || ' route' || case when cardinality(routes) > 1 then 's' else '' end;
end $$;
-- (e) Credit coming back on that lot while the reopening waits, by a way
-- the counting does not see (a stand-in: the lot's balance raised in
-- place): the payment that would settle it is refused with the reason,
-- changing nothing (the first text of the fix left the S$40 on the lot no
-- record names, silently). Undone.
do $$
declare a uuid := pg_temp.t460_cust('S6/e/A'); k uuid := pg_temp.t460_cust('S6/e/K'); f uuid := pg_temp.t460_cust('S6/e/F');
        inv uuid; lot uuid; msg text; n int; w text;
begin
  inv := pg_temp.t460_sale(a, array['cp']);
  perform pg_temp.t460_back(inv, pg_temp.t460_line(inv, 'cp'), 40);
  perform pg_temp.t460_merge(k, a);
  perform pg_temp.t460_move(inv, pg_temp.t460_line(inv, 'cp'), f);
  perform pg_temp.t460_cancel_reopen(inv);
  select bv.lot_id into lot from invoice_benefit_values bv join invoice_benefit_transfers bt on bt.source_benefit_id = bv.id where bv.invoice_id = inv;
  begin
    update customer_credit_lots set remaining_amount = remaining_amount + 20, updated_at = now() where id = lot;
    select count(*) into n from invoice_payments where invoice_id = inv;
    begin
      perform pg_temp.t460_pay(inv);
    exception when others then msg := sqlerrm;
    end;
    w := (select status::text from invoices where id = inv) || ' ' || (select count(*) from invoice_payments where invoice_id = inv) - n
         || ' ' || (select coalesce(sum(amount), 0) from invoice_reopen_benefits where invoice_id = inv and applied_at is null)
         || ' ' || pg_temp.t460_holds(a) || ' ' || (select remaining_amount from customer_credit_lots where id = lot);
    perform pg_temp.t460_check(msg = format('Invoice %s cannot be settled: it would give back S$40.00 of credit refunded before its customer was changed or merged, the rest of which was then moved to someone else (Move), and the credit lot the invoice names for it cannot take that much back (it holds S$20.00 of S$60.00 granted, and S$0.00 of its credit paid for other sales, which a refund puts back there). Nothing was recorded. Cancel the invoice again (its refund due stands), or ask the Owner.',
                                       (select invoice_no from invoices where id = inv))
        and w = 'partially_paid 0 100.00 0.00/0 20.00',
      '6 (e) credit back on the lot while it waits, paid: ' || coalesce(msg, 'not refused') || ' / ' || w);
    raise exception using errcode = 'P0991', message = 'undo';
  exception when sqlstate 'P0991' then null;
  end;
  raise notice 'PASS 6 (e): with S$20 come back on the lot the records name while the reopening waits (a stand-in), the payment that would settle it is refused with the reason (nothing recorded: still part paid, no payment added, all S$100 still waiting: the S$40 refunded and the S$60 the cancel took back from the friend); undone';
end $$;

-- ===== 8. KNOWN: 460's NOT COVERED, as they are =====
do $$
declare a uuid := pg_temp.t460_cust('S/after/A'); b uuid := pg_temp.t460_cust('S/after/B'); inv uuid; st text; o5 jsonb; o6 jsonb; o9 jsonb; o10 jsonb;
begin
  -- 2. A Premium Bundle's vouchers (X8) stay with whoever holds the
  -- voucher they replace: a customer change has never taken them along.
  perform pg_temp.t460_check(pg_temp.t460_holds(pg_temp.t460_id('X8/after/A')) = '0.00/2',
    '8 (2) X8''s bundle vouchers are not with A: look at 460''s NOT COVERED 2 again');
  -- 3. Two vouchers waiting, the customer and the store changed
  -- ('transfer'), paid: the new customer holds them at the first store
  -- (where the ones they replace were), as before 460.
  inv := pg_temp.t460_sale(a, array['v'], array[2]);
  perform pg_temp.t460_wait(inv);
  perform pg_temp.t460_change(inv, b, 'transfer', 'store2');
  perform pg_temp.t460_pay(inv);
  select string_agg(distinct s.code, ',') into st from customer_reward_vouchers v join stores s on s.id = v.store_id
   where v.customer_id = b and v.status = 'held';
  perform pg_temp.t460_check(pg_temp.t460_holds(b) = '0.00/2' and st = 'T460S1',
    '8 (3) waiting, changed with the store, paid: B holds ' || pg_temp.t460_holds(b) || ' at ' || coalesce(st, '-')
    || ': look at 460''s NOT COVERED 3 again');
  -- 4. A lot whose benefit row was moved on (Move) keeps its records: what
  -- a reopening gives back on it stays with whoever holds that lot, the old
  -- customer after a change (K5), the retired record after a merge (K6),
  -- as before 460 (2. checks that nothing reads as spent and Cancel takes
  -- it back). What went back on a lot it replaced goes onto it (M6, X9,
  -- X10), so in X10 (B merged into K after the Move) the S$44 is on B's lot,
  -- the retired record's, which the records name. A merge after such a
  -- reopening was settled (K9) moves that lot's credit to the kept record
  -- without its records (445), so Cancel then asks credit_used and its
  -- refund due is S$60: there at 455, not changed here.
  o5 := pg_temp.t460_run('K5', 'known');
  o6 := pg_temp.t460_run('K6', 'known');
  o9 := pg_temp.t460_run('K9', 'known');
  perform pg_temp.t460_check(pg_temp.t460_who(o5) = 'A 40.00/0, F 60.00/0' and pg_temp.t460_who(o6) = 'A 40.00/0, F 60.00/0'
      and o5->>'cancel' = '-' and o6->>'cancel' = '-'
      and (select deleted_at is not null from customers where id = pg_temp.t460_id('K6/known/A'))
      and (select l.customer_id from invoice_benefit_values bv join invoice_benefit_transfers bt on bt.source_benefit_id = bv.id
             join customer_credit_lots l on l.id = bv.lot_id where bv.invoice_id = pg_temp.t460_id('K5/known')) = pg_temp.t460_id('K5/known/A')
      -- K9: the kept record's S$40 on a lot no record names, as at 455.
      and pg_temp.t460_who(o9) = 'F 60.00/0, K 40.00/0' and o9->>'cancel' = 'credit_used' and o9->>'due' = '60.00'
      and exists (select 1 from customer_credit_lots l where l.customer_id = pg_temp.t460_id('K9/known/K') and l.remaining_amount = 40
                     and not exists (select 1 from invoice_benefit_values bv where bv.lot_id = l.id)),
    '8 (4) a Move after a refund, then a change (K5) or a merge (K6), or a merge after such a reopening was settled (K9): not as 460''s NOT COVERED 4 says ('
    || o5::text || '; ' || o6::text || '; ' || o9::text || '): look at it again');
  if pg_temp.t460_461_in() then
    o10 := pg_temp.t460_run('X10', 'known');
    perform pg_temp.t460_check(pg_temp.t460_who(o10) = 'B 44.00/0, F 56.00/0, K 10.00/0' and o10->>'cancel' = '-' and o10->>'due' = '100.00'
        and (select deleted_at is not null from customers where id = pg_temp.t460_id('X10/known/B'))
        and (select l.customer_id from invoice_benefit_values bv join invoice_benefit_transfers bt on bt.source_benefit_id = bv.id
               join customer_credit_lots l on l.id = bv.lot_id where bv.invoice_id = pg_temp.t460_id('X10/known')) = pg_temp.t460_id('X10/known/B'),
      '8 (4) X10: the S$44 is not on the retired record''s lot the records name: ' || o10::text || ': look at 460''s NOT COVERED 4 again');
  end if;
  -- 4 (b), the review of 24 Oct 2026: the benefits leave the holder of the
  -- lot the records name after the Move (K merged into K2 while it waits,
  -- M7; with 461, B changed to C before the cancel, X11, or while it waits,
  -- X12, or B merged into K while it waits, X13): the S$40 (S$44) stays on
  -- that lot, not with the benefits' current holder; nothing reads as spent,
  -- the refund due is what was received; an Owner's Move of that benefit
  -- row to the current holder puts it right (X13).
  o10 := pg_temp.t460_run('M7', 'known');
  perform pg_temp.t460_check(pg_temp.t460_who(o10) = 'F 60.00/0, K 40.00/0' and o10->>'cancel' = '-' and o10->>'due' = '100.00'
      and o10->>'records' = '' and (select deleted_at is not null from customers where id = pg_temp.t460_id('M7/known/K')),
    '8 (4b) M7: ' || o10::text || ': look at 460''s NOT COVERED 4 (b) again');
  if pg_temp.t460_461_in() then
    o10 := pg_temp.t460_run('X11', 'known');
    perform pg_temp.t460_check(pg_temp.t460_who(o10) = 'B 44.00/0, C 10.00/0, F 56.00/0' and o10->>'cancel' = '-' and o10->>'due' = '100.00'
        and o10->>'records' = '',
      '8 (4b) X11: ' || o10::text || ': look at 460''s NOT COVERED 4 (b) again');
    o10 := pg_temp.t460_run('X12', 'known');
    perform pg_temp.t460_check(pg_temp.t460_who(o10) = 'B 44.00/0, C 10.00/0, F 56.00/0' and o10->>'cancel' = '-' and o10->>'due' = '100.00'
        and o10->>'records' = '',
      '8 (4b) X12: ' || o10::text || ': look at 460''s NOT COVERED 4 (b) again');
    o10 := pg_temp.t460_run('X13', 'known');
    perform pg_temp.t460_check(pg_temp.t460_who(o10) = 'B 44.00/0, F 56.00/0, K 10.00/0' and o10->>'cancel' = '-' and o10->>'due' = '100.00'
        and o10->>'records' = '' and (select deleted_at is not null from customers where id = pg_temp.t460_id('X13/known/B')),
      '8 (4b) X13: ' || o10::text || ': look at 460''s NOT COVERED 4 (b) again');
    perform transfer_invoice_unused_benefit(
      (select bv.id from invoice_benefit_values bv join invoice_benefit_transfers bt on bt.source_benefit_id = bv.id
        where bv.invoice_id = pg_temp.t460_id('X13/known') and bv.lot_id in (select l.id from customer_credit_lots l
                                                                            where l.customer_id = pg_temp.t460_id('X13/known/B') and l.remaining_amount > 0)),
      pg_temp.t460_id('X13/known/K'), pg_temp.t460_id('store'), 'T460 put it with the kept record', gen_random_uuid());
    o10 := pg_temp.t460_outcome('X13/known', pg_temp.t460_id('X13/known'));
    perform pg_temp.t460_check(pg_temp.t460_who(o10) = 'F 56.00/0, K 54.00/0' and o10->>'cancel' = '-' and o10->>'due' = '100.00',
      '8 (4b) X13 then moved to the kept record: ' || o10::text);
  end if;
  raise notice 'KNOWN 8: (not covered by 460) (2) a Premium Bundle''s vouchers, which a customer change has never taken along (not transferable), are given back to whoever holds the voucher they replace (X8: A holds them, B the bundle''s credit). (3) a voucher a reopening gives again is given at the store of the one it replaces, as before: waiting, changed with the store to B, paid, B holds them at the first store (a change that also moves the store moves the vouchers held then with their stock, X5). (4) a lot whose benefit row was moved on (Move): S$40 refunded, the S$60 left moved to F, cancelled, reopened, changed to B (K5) or A merged into K (K6), paid: the S$40 goes back on A''s lot, which the benefit row and the sale name (in K6 A is the retired record), as before 460; nothing reads as spent and Cancel takes it back. With the refund before a change and the Move after it, and the new customer merged into K before the cancel (X10, with 461 in), the S$44 goes on B''s lot, which the records name: B is the retired record. A merge after such a reopening was settled (K9) moves the lot''s S$40 to the kept record without its records (445): Cancel asks credit_used and its refund due is S$60, as at 455. (1) a customer change with ''transfer'' made before 460 that moved nothing left no record: what a later reopening gives back goes where it did before 460 (460 refuses to install where such an invoice still waits)';
  raise notice 'KNOWN 8: (not covered by 460) (4 b) the benefits leave the holder of the lot the records name after the Move: the S$40 (S$44) stays on that lot, its holder''s, not with the benefits'' current holder: K merged into K2 while it waits (M7: K, the retired record, holds the S$40)%; nothing reads as spent, the refund due is what was received (S$100)%',
    case when pg_temp.t460_461_in() then '; B changed to C before the cancel (X11) or while it waits (X12): B holds the S$44, C the S$10 Bonus; B merged into K while it waits (X13): B, the retired record, holds the S$44, K the S$10' else ' (with 461 in, the change routes X11 to X13 too)' end,
    case when pg_temp.t460_461_in() then '; an Owner''s Move of that benefit row to the kept record puts it right (X13: K then holds S$54, the refund due S$100)' else '' end;
end $$;

-- 7. The review summary of a change made while a reopened invoice waits
-- (460's NOT COVERED 7): with 'transfer' it lists no benefits (nothing is
-- held to move then), yet once the invoice is paid the new customer holds
-- what waited (X3).
do $$
declare a uuid := pg_temp.t460_cust('S7/after/A'); b uuid := pg_temp.t460_cust('S7/after/B'); inv uuid; r jsonb;
begin
  inv := pg_temp.t460_sale(a, array['cpb', 'v'], array[1, 2]);
  perform pg_temp.t460_wait(inv);
  r := preview_invoice_correction(inv, pg_temp.t460_header(inv, b, 'transfer'));
  perform pg_temp.t460_check(exists (select 1 from jsonb_array_elements(r->'effects') e where e->>'area' = 'customer')
      and not exists (select 1 from jsonb_array_elements(r->'effects') e where e->>'area' = 'benefits'),
    '8 (7) the summary of a change while it waits: ' || coalesce((r->'effects')::text, '<none>') || ': look at 460''s NOT COVERED 7 again');
  perform pg_temp.t460_change(inv, b);
  perform pg_temp.t460_pay(inv);
  perform pg_temp.t460_check(pg_temp.t460_holds(a) = '0.00/0' and pg_temp.t460_holds(b) = '110.00/2',
    '8 (7) changed while it waits, paid: A holds ' || pg_temp.t460_holds(a) || ', B ' || pg_temp.t460_holds(b));
  raise notice 'KNOWN 8: (not covered by 460) (7) a customer change (''transfer'') made while a reopened invoice waits: the review summary shows the customer change and no benefits entry (nothing is held to move then), yet once the invoice is paid the new customer holds what waited (S$110 and 2 vouchers); preview_invoice_correction is not changed by 460';
end $$;

rollback;
