-- 451: a voucher unit refunded on both sides of a reopening is given back
-- once the invoice is paid again; after any line refunds, cancels and
-- reopenings the customer holds what the invoice's net payment buys (448's
-- NOT COVERED 1; the Owner, 22 Oct 2026: "fix the rare 446 voucher case
-- too"), and the same holds for credit with no change (the credit analogue
-- does not exist).
--
-- Every step goes through the app's own calls: the invoice form
-- (create_invoice_with_details) and the Pay dialog (record_invoice_settlement),
-- the guided "Refund some items", Refund in full and Cancel
-- (invoice_action_plan, request_invoice_action_v2, resolve_invoice_action_v2),
-- Cancel (cancel_invoice_recorded), the Finance panel's Reopen and its Reopen
-- dialog (reopen_invoice, invoice_reopen_preview), its refund by line
-- (refund_invoice_recorded with the line's benefits) and "Record refund paid"
-- (refund_invoice_recorded with no item), Record Payment
-- (record_invoice_payment), Move (transfer_invoice_unused_benefit), the
-- invoice form's customer change (correct_invoice, 'transfer') and the FOC
-- taken off (confirm_foc_invoice, correct_invoice).
--
-- Steps are written as in the search that found the siblings: G<n> the
-- guided "Refund some items" (one unit of line n; G<n>x2 two), L<n> the
-- Finance panel's refund by line (one voucher unit of line n, L<n>x2 two;
-- all of a credit line), A<n> S$40 off line n's Paid credit (the Finance
-- panel), C Cancel, O Reopen, P Record Payment of what is outstanding, B
-- "Record refund paid" S$30, F the guided Refund in full, Kr the guided
-- Cancel with the money recorded, M<n> Move line n's unused benefit to a
-- friend, X the customer changed (benefits taken along), V<n> one voucher
-- unit of a Premium Bundle line (the Finance panel). Lines are counted
-- largest first (by quantity, then id), so a line of two comes before a
-- line of one.
--
-- The check after every step (the oracle): for each line, what it charges
-- now (its value less its line refunds since the last reopening) buys its
-- units and credit pro rata; paid: the customer (whoever holds them) has
-- exactly that; part-paid or unpaid: what they have plus what waits to be
-- given; cancelled: nothing out. Cancel's and Refund in full's plans ask no
-- voucher_redeemed or credit_used, a cancelled invoice reads nothing used
-- (nothing is redeemed or spent here); a limited voucher's stock out equals
-- the units out; and at each Reopen the dialog's "Voucher units to replace
-- after settlement" and "Stock to issue" equal what the reopening queues and
-- takes.
--
--   R. Without 451 (skipped, with a notice, where 451 was in before the suite
--      started), in a block that is undone (451 refuses a database in that
--      state, case 9): each sibling found, as it was: a line of two, one unit
--      refunded, cancelled, reopened, cancelled again, the other refunded by
--      line, reopened, paid: 1 voucher for S$60, Cancel asks
--      voucher_redeemed, the dialog said 1 [V1]; the second refund while
--      waiting [V2]; the first on the cancelled invoice [V3]; the guided
--      Cancel with the money recorded [V4]; the guided Refund in full [V5];
--      a line of three, one then two [V6] and two then one [V7]; a limited
--      voucher (stock follows the short count) [V8]; after a Move [V9]; after
--      a customer change [V10]; an FOC taken off and paid [V11]; a Premium
--      Bundle's vouchers [V12]; three cycles on a line of three [V13]. And a
--      bounded search of every sequence (a line of two) finds faults, every
--      one of this kind: a unit refunded before a reopening, another after
--      it, then reopened.
--   0. Controls (no part of the fault), outcomes recorded before 451: 417's
--      own case (cancelled again unsettled, nothing refunded by line), 446's
--      (a unit refunded while waiting, cancelled again, reopened), a refund
--      before the reopening only, refunded while waiting and settled, two
--      lines of one, an FOC taken off and paid then cancelled and reopened,
--      a Move after settling then cancelled; and credit: the same sequences
--      as V1 to V7 on Credit Packages (whole, with a Bonus, S$40 at a time),
--      Premium Bundles, a guided Cancel and Refund in full while waiting.
--   9. The refusal: on a database carrying the fault's footprint (V1's steps
--      up to the second reopening; and one settled since), 451 refuses,
--      names both and changes nothing; the footprint's three conditions are
--      each needed (446's own case, a refund while waiting not yet followed
--      by a reopening, and a no-item refund before it, are not listed).
--  10. 451 installed twice: the second run changes nothing; no function
--      added or dropped; grants as before, compared as sets; no overload.
--   1. Each case after 451: what it holds, net received, stock, the dialog,
--      448's counting (nothing asked waiting or settled; cancelled, nothing
--      used and "Record refund paid" records what is due), and a further
--      cycle (cancelled, reopened, paid) still right.
--   2. The controls after 451: outcomes identical, whole (status, money,
--      what each line holds and waits, both queues' totals, the credit
--      ledger's totals by kind, stock, the plans' codes, the dialogs; totals,
--      not rows, because which queued row 446 lowers first can differ between
--      runs in one transaction); and each right by the oracle.
--      For credit that is the proof that the analogue does not exist: right
--      before 451 and unchanged by it.
--   3. A bounded search of every sequence after 451: a line of two (guided
--      and Finance-panel refunds, Cancel, Reopen, payments, guided Cancel), a
--      limited line of two with Move and the customer change, one S$100
--      Credit Package (S$40 and whole refunds), and two packages: no fault.
--   4. 448's counting after 451: a unit really redeemed beside the cycle
--      still reads voucher_redeemed (no real redemption missed).
--   8. KNOWN (451's NOT COVERED 1, checked as it is): a 'larger_refund'
--      override (no page sends it) keeps a unit held through a reopening;
--      cancelled and reopened again, one unit too few waits, with or without
--      451.
--
-- Run on a copy of production as it is (448, 449 and 450 in: 63219bad, 1371
-- functions):
--   psql -v ON_ERROR_STOP=1 -f scripts/invoices/tests/reopen-refund-cycles-451.sql
-- It installs 451 itself, twice, inside its transaction. Where 451 is in
-- already, add -v nomig=1 (R, the before/after comparison and the refusal
-- are then skipped with a notice; every figure after 451 is still checked).
-- Case 9 lets one statement fail on purpose (psql prints its ERROR); the
-- suite then checks that message. Disposable database only; everything is
-- rolled back. Every name, code and amount is invented (@example.com); the
-- phones are numbers kept for fiction (ACMA).
-- Where 474 is in (-v nomig=1; 471's NOT COVERED 7, the Owner, 26 Oct 2026:
-- "fix the leftover gaps too"), the preview is at 474's AFTER: its voucher
-- units, which this suite reads, are 451's text unchanged; its credit to
-- reinstate also counts the credit still waiting (474's suite,
-- reopen-dialog-waiting-credit-474, checks that). 10 then reads 474's md5.
\set ON_ERROR_STOP on
begin;

create temp table t451(k text primary key, id uuid);
create temp table t451_out(k text primary key, before jsonb, after jsonb);
create temp table t451_fp(k text primary key, fp text);
create temp table t451_dialog(inv uuid, n int generated always as identity, units int, waiting_before int, queued int);
create temp sequence t451_steps;
create temp sequence t451_found;
create temp sequence t451_other;
create function pg_temp.t451_id(p_k text) returns uuid language sql as $f$ select id from t451 where k = p_k $f$;
create function pg_temp.t451_check(p_ok boolean, p_label text) returns void language plpgsql as $f$
begin
  if not coalesce(p_ok, false) then raise exception 'FAIL %', p_label; end if;
end $f$;
create function pg_temp.t451_fingerprint() returns text language sql as $f$
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.oid::regprocedure::text)) || ' ' || count(*)
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prokind in ('f', 'p') $f$;
create function pg_temp.t451_in() returns boolean language sql as $f$
  select position('-- 451 (the Owner' in pg_get_functiondef('public.reopen_invoice(uuid,text,uuid)'::regprocedure)) > 0
     and position('-- 451:' in pg_get_functiondef('public.invoice_reopen_preview_before_sessions(uuid)'::regprocedure)) > 0 $f$;
create function pg_temp.t451_grants(p_sig text) returns text language sql as $f$
  select coalesce(string_agg(x::text, ',' order by x::text), '') from pg_proc p, unnest(p.proacl) x
   where p.oid = to_regprocedure('public.' || p_sig) $f$;

do $$
declare own uuid := gen_random_uuid(); st uuid; c uuid; c2 uuid; pm uuid; v uuid; vl uuid; cp uuid; cpb uuid; pbb uuid; pbv uuid;
begin
  insert into auth.users(id, email) values (own, 't451-owner@example.com');
  insert into profiles(id, full_name, email, role, is_active) values (own, 'T451 Owner', 't451-owner@example.com', 'owner', true);
  perform set_config('request.jwt.claims', json_build_object('sub', own, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', own::text, true);
  insert into stores(name, code, country_code) values ('T451 Store', 'T451S1', 'SG') returning id into st;
  insert into customers(full_name, phone) values ('T451 Buyer', '+61491570456') returning id into c;
  insert into customers(full_name, phone) values ('T451 Friend', '+61491570457') returning id into c2;
  insert into payment_methods(name, is_active) values ('T451 Cash', true) returning id into pm;
  -- A plain S$30 voucher, and a limited one (1000 in stock) to follow stock.
  insert into vouchers(name, code, voucher_kind, qty_type, selling_price, is_active)
    values ('T451 Plain 30', 'T451-P30', 'normal', 'unlimited', 30, true) returning id into v;
  insert into voucher_store_prices(voucher_id, store_id, selling_price, available_at_store) values (v, st, 30, true);
  insert into vouchers(name, code, voucher_kind, qty_type, selling_price, is_active)
    values ('T451 Limited 30', 'T451-L30', 'normal', 'limited', 30, true) returning id into vl;
  insert into voucher_store_prices(voucher_id, store_id, selling_price, available_at_store) values (vl, st, 30, true);
  insert into voucher_store_stock(voucher_id, store_id, current_qty) values (vl, st, 1000);
  -- A S$100 Credit Package (S$100 Paid), one with a S$10 Bonus, a Premium
  -- Bundle of S$100 Paid and S$20 Bonus (S$100), and one of S$100 Paid, S$40
  -- Bonus and two S$30 vouchers (S$140).
  insert into credit_packages(name, customer_price, paid_credit_amount, bonus_enabled, allow_product, allow_therapy)
    values ('T451 S$100', 100, 100, false, true, true) returning id into cp;
  insert into credit_package_stores(package_id, store_id) values (cp, st);
  insert into credit_packages(name, customer_price, paid_credit_amount, bonus_enabled, bonus_value, allow_product, allow_therapy, grants_reward)
    values ('T451 S$100 + S$10', 100, 100, true, 10, true, true, false) returning id into cpb;
  insert into credit_package_stores(package_id, store_id) values (cpb, st);
  insert into premium_bundles(name, customer_payment_amount, paid_credit_amount, bonus_credit_amount, free_voucher_qty, grants_reward)
    values ('T451 Bundle S$100 + S$20', 100, 100, 20, 0, false) returning id into pbb;
  insert into premium_bundle_stores(bundle_id, store_id) values (pbb, st);
  insert into premium_bundles(name, customer_payment_amount, paid_credit_amount, bonus_credit_amount, free_voucher_qty, grants_reward)
    values ('T451 Bundle S$140 + 2 vouchers', 140, 100, 40, 2, true) returning id into pbv;
  insert into premium_bundle_stores(bundle_id, store_id) values (pbv, st);
  insert into premium_bundle_vouchers(bundle_id, voucher_id) values (pbv, v);
  insert into t451 values ('own', own), ('store', st), ('buyer', c), ('friend', c2), ('pm', pm), ('v', v), ('vl', vl),
                          ('cp', cp), ('cpb', cpb), ('pbb', pbb), ('pbv', pbv);
end $$;

-- ── The app's calls ─────────────────────────────────────────────────────────
-- The invoice form with these lines ('v' / 'vl' a voucher line of p_qtys[i]
-- units, 'cp' / 'cpb' a Credit Package, 'pbb' / 'pbv' a Premium Bundle), paid
-- in full through the Pay dialog.
create function pg_temp.t451_sale(p_kinds text[], p_qtys int[] default null) returns uuid language plpgsql as $f$
declare inv uuid; v_lines jsonb := '[]'; i int;
begin
  for i in 1 .. cardinality(p_kinds) loop
    v_lines := v_lines || jsonb_build_array(case
      when p_kinds[i] in ('v', 'vl') then jsonb_build_object('kind', 'voucher', 'voucher_id', pg_temp.t451_id(p_kinds[i]),
                                                            'quantity', coalesce(p_qtys[i], 1))
      when p_kinds[i] in ('cp', 'cpb') then jsonb_build_object('kind', 'credit_package', 'credit_package_id', pg_temp.t451_id(p_kinds[i]), 'quantity', 1)
      when p_kinds[i] = 'pbb' then jsonb_build_object('kind', 'premium_bundle', 'premium_bundle_id', pg_temp.t451_id('pbb'), 'quantity', 1)
      else jsonb_build_object('kind', 'premium_bundle', 'premium_bundle_id', pg_temp.t451_id('pbv'), 'quantity', 1,
        'voucher_selection', jsonb_build_array(jsonb_build_object('voucher_id', pg_temp.t451_id('v'), 'quantity', 2))) end);
  end loop;
  inv := create_invoice_with_details(pg_temp.t451_id('store'), pg_temp.t451_id('buyer'), v_lines,
    jsonb_build_object('business_date', sg_today()::text));
  perform record_invoice_settlement(inv, jsonb_build_object('receipts', jsonb_build_array(jsonb_build_object(
    'key', 'line-0', 'payment_method_id', pg_temp.t451_id('pm'), 'amount', (select total_amount from invoices where id = inv),
    'payment_date', sg_today()::text)), 'arrangements', '[]'::jsonb), gen_random_uuid());
  return inv;
end $f$;
-- A completed FOC of p_qty limited vouchers, the FOC taken off at S$30 each
-- (416); paid when p_paid.
create function pg_temp.t451_foc_off(p_qty int, p_paid boolean) returns uuid language plpgsql as $f$
declare inv uuid; x jsonb;
begin
  inv := create_invoice(pg_temp.t451_id('store'), pg_temp.t451_id('buyer'), null, jsonb_build_array(jsonb_build_object(
    'kind', 'voucher', 'voucher_id', pg_temp.t451_id('vl'), 'quantity', p_qty, 'foc_quantity', p_qty, 'foc_reason', 'T451 goodwill')));
  perform confirm_foc_invoice(inv, 'T451 FOC');
  select jsonb_agg(jsonb_build_object('invoice_item_id', it.id, 'kind', 'voucher', 'voucher_id', it.voucher_id,
           'quantity', p_qty, 'unit_price', 30, 'foc_quantity', 0)) into x
    from invoice_items it where it.invoice_id = inv;
  perform correct_invoice(inv, x, jsonb_build_object('expected_edit_count', (select edit_count from invoices where id = inv)),
    'T451 FOC off', gen_random_uuid());
  if p_paid then
    perform record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.t451_id('pm'),
      'amount', 30 * p_qty)), gen_random_uuid());
  end if;
  return inv;
end $f$;
-- The receipts that still hold p_amount between them, as the Finance panel
-- splits a refund across them.
create function pg_temp.t451_sources(p_inv uuid, p_amount numeric) returns jsonb language plpgsql as $f$
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
create function pg_temp.t451_line(p_inv uuid, p_n int) returns uuid language sql as $f$
  select id from invoice_items where invoice_id = p_inv order by quantity desc, id offset p_n - 1 limit 1 $f$;
-- The guided Refund / Cancel as an Owner confirms it (InvoiceGuidedAction):
-- the plan, the request, the approval with a reason for every override the
-- plan asks for; the money recorded as paid back when p_record. Returns the
-- codes asked ('-' for none), or 'ERR ' and the refusal.
create function pg_temp.t451_guided(p_inv uuid, p_action text, p_lines jsonb default '[]', p_record boolean default false)
  returns text language plpgsql as $f$
declare plan jsonb; req jsonb; ov jsonb; stock jsonb;
begin
  plan := invoice_action_plan(p_inv, p_action, p_lines);
  req := request_invoice_action_v2(p_inv, p_action, p_lines, 'T451 ' || p_action, null, gen_random_uuid());
  select coalesce(jsonb_agg(case when coalesce((o->>'amount_required')::boolean, false)
           then jsonb_build_object('code', o->>'code', 'reason', 'T451 override', 'amount', (o->>'default_amount')::numeric)
           else jsonb_build_object('code', o->>'code', 'reason', 'T451 override') end), '[]'::jsonb)
    into ov from jsonb_array_elements(coalesce(plan->'overrides_required', '[]')) o;
  select jsonb_agg(jsonb_build_object('movement_id', s->>'movement_id', 'sellable_quantity', (s->>'proposed_sellable')::int,
           'damaged_quantity', 0, 'not_returned_quantity', 0)) into stock
    from jsonb_array_elements(coalesce(plan->'stock', '[]')) s;
  perform resolve_invoice_action_v2((req->>'request_id')::uuid, true, 'T451 ' || p_action, plan->>'plan_hash', ov, stock, p_record);
  return (select coalesce(string_agg(o->>'code', ',' order by o->>'code'), '-')
            from jsonb_array_elements(coalesce(plan->'overrides_required', '[]')) o);
exception when others then return 'ERR ' || sqlerrm;
end $f$;
-- The Finance panel's refund of line n: p_units of its vouchers, or p_amount
-- off its Paid credit, or (neither) every unused benefit it still holds.
-- 'recorded', or the refusal.
create function pg_temp.t451_line_back(p_inv uuid, p_n int, p_units int default null, p_amount numeric default null)
  returns text language plpgsql as $f$
declare opts jsonb; ben jsonb; tot numeric; item uuid := pg_temp.t451_line(p_inv, p_n);
begin
  opts := invoice_refund_options_before_sessions(p_inv);
  if p_amount is not null then
    select jsonb_build_array(jsonb_build_object('benefit_id', b->>'id', 'amount', p_amount)), p_amount
      into ben, tot from jsonb_array_elements(opts->'benefits') b
     where b->>'invoice_item_id' = item::text and b->>'benefit_kind' = 'paid' and (b->>'max_refund')::numeric > 0
     order by (b->>'paid_value')::numeric desc limit 1;
  elsif p_units is not null then
    select jsonb_build_array(jsonb_build_object('benefit_id', b->>'id',
             'amount', round((b->>'paid_value')::numeric * p_units / (b->>'granted_value')::numeric, 2))),
           round((b->>'paid_value')::numeric * p_units / (b->>'granted_value')::numeric, 2)
      into ben, tot from jsonb_array_elements(opts->'benefits') b
     where b->>'invoice_item_id' = item::text and b->>'benefit_kind' = 'voucher'
       and (b->>'remaining_value')::numeric >= p_units and (b->>'max_refund')::numeric > 0
     order by (b->>'remaining_value')::numeric desc limit 1;
  else
    select jsonb_agg(jsonb_build_object('benefit_id', b->>'id', 'amount', (b->>'max_refund')::numeric)), sum((b->>'max_refund')::numeric)
      into ben, tot from jsonb_array_elements(opts->'benefits') b
     where b->>'invoice_item_id' = item::text and (b->>'max_refund')::numeric > 0;
  end if;
  if ben is null then return 'nothing to refund on line ' || p_n; end if;
  perform refund_invoice_recorded(p_inv, jsonb_build_array(jsonb_build_object('invoice_item_id', item, 'amount', tot, 'benefits', ben)),
    pg_temp.t451_sources(p_inv, tot), '[]'::jsonb, 'T451 by line', gen_random_uuid());
  return 'recorded';
exception when others then return sqlerrm;
end $f$;
-- "Record refund paid": one line with no item. 'recorded', or the refusal.
create function pg_temp.t451_record_refund(p_inv uuid, p_amount numeric) returns text language plpgsql as $f$
begin
  perform refund_invoice_recorded(p_inv, jsonb_build_array(jsonb_build_object('invoice_item_id', null, 'amount', p_amount)),
    pg_temp.t451_sources(p_inv, p_amount), '[]'::jsonb, 'T451 paid back', gen_random_uuid());
  return 'recorded';
exception when others then return sqlerrm;
end $f$;
-- Move: line n's held voucher, or its credit (the largest), to the friend.
create function pg_temp.t451_move(p_inv uuid, p_n int) returns text language plpgsql as $f$
declare b uuid;
begin
  select bv.id into b from invoice_benefit_values bv
    left join customer_reward_vouchers v on v.id = bv.reward_voucher_id
    left join customer_credit_lots l on l.id = bv.lot_id
   where bv.invoice_item_id = pg_temp.t451_line(p_inv, p_n) and (v.status = 'held' or l.remaining_amount > 0)
     and coalesce(v.customer_id, l.customer_id) <> pg_temp.t451_id('friend')
   order by bv.granted_value desc limit 1;
  if b is null then return 'nothing to move'; end if;
  perform transfer_invoice_unused_benefit(b, pg_temp.t451_id('friend'), pg_temp.t451_id('store'), 'T451 move', gen_random_uuid());
  return null;
exception when others then return 'refused: ' || sqlerrm;
end $f$;
-- The customer changed, benefits taken along (the invoice form): to the
-- friend, or back.
create function pg_temp.t451_change(p_inv uuid) returns text language plpgsql as $f$
declare x jsonb; cust uuid;
begin
  select customer_id into cust from invoices where id = p_inv;
  select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('invoice_item_id', it.id, 'kind', it.line_kind,
           'credit_package_id', it.credit_package_id, 'premium_bundle_id', it.premium_bundle_id, 'voucher_id', it.voucher_id,
           'quantity', it.quantity, 'unit_price', it.unit_price, 'voucher_selection', it.bundle_voucher_selection)) order by it.id)
    into x from invoice_items it where it.invoice_id = p_inv;
  perform correct_invoice(p_inv, x, jsonb_build_object('expected_edit_count', (select edit_count from invoices where id = p_inv),
    'customer_id', case when cust = pg_temp.t451_id('buyer') then pg_temp.t451_id('friend') else pg_temp.t451_id('buyer') end,
    'store_id', pg_temp.t451_id('store'), 'benefit_action', 'transfer'), 'T451 wrong customer', gen_random_uuid());
  return null;
exception when others then return 'refused: ' || sqlerrm;
end $f$;

-- ── What the screens and the records say ───────────────────────────────────
create function pg_temp.t451_waiting(p_inv uuid) returns int language sql as $f$
  select coalesce(sum(quantity), 0)::int from invoice_reopen_vouchers where invoice_id = p_inv and applied_at is null $f$;
-- Units out on a line (held or redeemed, by anyone), or on the invoice.
create function pg_temp.t451_held(p_inv uuid, p_item uuid default null) returns int language sql as $f$
  select coalesce(sum(v.quantity), 0)::int from invoice_benefit_values b join customer_reward_vouchers v on v.id = b.reward_voucher_id
   where b.invoice_id = p_inv and v.status in ('held', 'redeemed') and (p_item is null or b.invoice_item_id = p_item) $f$;
create function pg_temp.t451_credit(p_inv uuid) returns numeric language sql as $f$
  select round(coalesce(sum(l.remaining_amount), 0), 2) from invoice_benefit_values b join customer_credit_lots l on l.id = b.lot_id
   where b.invoice_id = p_inv $f$;
create function pg_temp.t451_cwaiting(p_inv uuid) returns numeric language sql as $f$
  select coalesce(sum(amount), 0) from invoice_reopen_benefits where invoice_id = p_inv and applied_at is null $f$;
create function pg_temp.t451_codes(p_inv uuid, p_action text) returns text language sql as $f$
  select coalesce(string_agg(o->>'code', ',' order by o->>'code'), '-')
    from jsonb_array_elements(coalesce(invoice_action_plan(p_inv, p_action, '[]')->'overrides_required', '[]')) o $f$;
create function pg_temp.t451_used(p_inv uuid) returns text language sql as $f$
  select coalesce(nullif(array_to_string(cancelled_invoice_used_value(p_inv), ','), ''), '-') $f$;
create function pg_temp.t451_stock() returns int language sql as $f$
  select current_qty from voucher_store_stock where voucher_id = pg_temp.t451_id('vl') and store_id = pg_temp.t451_id('store') $f$;
create function pg_temp.t451_state(p_inv uuid) returns text language sql as $f$
  select i.status::text || ' net ' || invoice_net_received(i.id) || ' held ' || pg_temp.t451_held(i.id)
         || ' waiting ' || pg_temp.t451_waiting(i.id) || ' credit ' || pg_temp.t451_credit(i.id)
         || ' cwaiting ' || pg_temp.t451_cwaiting(i.id)
    from invoices i where i.id = p_inv $f$;

-- ── The oracle ──────────────────────────────────────────────────────────────
-- What line p_item charges now: its value less its line refunds since the
-- last reopening.
create function pg_temp.t451_owed_money(p_item uuid) returns numeric language sql as $f$
  select coalesce(invoice_discounted_line_value(it.id), 0)
         - coalesce((select sum((x->>'amount')::numeric) from invoice_refunds r
                      cross join lateral jsonb_array_elements(coalesce(r.outcome->'lines', '[]')) x
                      join invoices i on i.id = r.invoice_id
                     where r.invoice_id = it.invoice_id and x->>'invoice_item_id' = it.id::text
                       and (i.reopened_at is null or r.created_at > i.reopened_at)), 0)
    from invoice_items it where it.id = p_item $f$;
-- What the line gives at its full price: voucher units, or credit.
create function pg_temp.t451_grant(p_item uuid, p_what text) returns numeric language sql as $f$
  select case
    when p_what = 'units' and it.line_kind::text = 'voucher' then it.quantity
    when p_what = 'units' and it.line_kind::text = 'premium_bundle'
      then coalesce((select pb.free_voucher_qty from premium_bundles pb where pb.id = it.premium_bundle_id), 0)
    when p_what = 'credit' and it.line_kind::text = 'credit_package' then
      (select cp.paid_credit_amount + case when cp.bonus_enabled then coalesce(cp.bonus_value, 0) else 0 end
         from credit_packages cp where cp.id = it.credit_package_id)
    when p_what = 'credit' and it.line_kind::text = 'premium_bundle' then
      (select pb.paid_credit_amount + pb.bonus_credit_amount from premium_bundles pb where pb.id = it.premium_bundle_id)
    else 0 end
    from invoice_items it where it.id = p_item $f$;
-- Units waiting for a line: queued, and (416) units an FOC taken off keeps to
-- give at payment (cancelled_unused_value beyond what is queued for the row).
create function pg_temp.t451_line_waiting(p_item uuid) returns int language sql as $f$
  select (coalesce((select sum(q.quantity) from invoice_reopen_vouchers q join invoice_benefit_values b on b.id = q.benefit_id
                     where b.invoice_item_id = p_item and q.applied_at is null), 0)
          + coalesce((select sum(greatest(b.cancelled_unused_value
                                          - coalesce((select sum(q.quantity) from invoice_reopen_vouchers q
                                                       where q.benefit_id = b.id and q.applied_at is null), 0), 0))
                        from invoice_benefit_values b join customer_reward_vouchers v on v.id = b.reward_voucher_id
                       where b.invoice_item_id = p_item and v.status = 'revoked'
                         and (select status::text from invoices where id = b.invoice_id) in ('unpaid', 'partially_paid')), 0))::int $f$;
create function pg_temp.t451_line_credit(p_item uuid) returns numeric language sql as $f$
  select coalesce(sum(l.remaining_amount), 0) from invoice_benefit_values b join customer_credit_lots l on l.id = b.lot_id
   where b.invoice_item_id = p_item $f$;
create function pg_temp.t451_line_cwaiting(p_item uuid) returns numeric language sql as $f$
  select coalesce(sum(q.amount), 0) from invoice_reopen_benefits q join customer_credit_ledger e on e.id = q.source_ledger_id
   where q.applied_at is null
     and e.lot_id in (select b.lot_id from invoice_benefit_values b where b.invoice_item_id = p_item and b.lot_id is not null) $f$;
-- Everything wrong with the invoice now ('' when nothing), p_stock0 the
-- limited voucher's stock before it was sold (null: no limited voucher).
create function pg_temp.t451_problems(p_inv uuid, p_stock0 int) returns text language plpgsql as $f$
declare st text; it record; ou numeric; oc numeric; h int; w int; cr numeric; cw numeric; val numeric; probs text := ''; c text;
begin
  select status::text into st from invoices where id = p_inv;
  for it in select id, row_number() over (order by quantity desc, id) n from invoice_items where invoice_id = p_inv order by quantity desc, id loop
    val := coalesce(invoice_discounted_line_value(it.id), 0);
    ou := round(pg_temp.t451_grant(it.id, 'units') * pg_temp.t451_owed_money(it.id) / nullif(val, 0), 2);
    oc := round(pg_temp.t451_grant(it.id, 'credit') * pg_temp.t451_owed_money(it.id) / nullif(val, 0), 2);
    h := pg_temp.t451_held(p_inv, it.id); w := pg_temp.t451_line_waiting(it.id);
    cr := pg_temp.t451_line_credit(it.id); cw := pg_temp.t451_line_cwaiting(it.id);
    if pg_temp.t451_grant(it.id, 'units') > 0 then
      if st = 'paid' and h <> ou then probs := probs || format(' line%s: paid, %s out for %s owed (waiting %s);', it.n, h, ou, w); end if;
      if st in ('partially_paid', 'unpaid') and h + w <> ou then
        probs := probs || format(' line%s: %s, %s out + %s waiting for %s owed;', it.n, st, h, w, ou); end if;
      if st = 'cancelled' and h <> 0 then probs := probs || format(' line%s: cancelled, %s still out;', it.n, h); end if;
    end if;
    if pg_temp.t451_grant(it.id, 'credit') > 0 then
      if st = 'paid' and abs(cr - oc) > 0.011 then probs := probs || format(' line%s: paid, credit %s for %s owed;', it.n, cr, oc); end if;
      if st in ('partially_paid', 'unpaid') and abs(cr + cw - oc) > 0.011 then
        probs := probs || format(' line%s: %s, credit %s + %s waiting for %s owed;', it.n, st, cr, cw, oc); end if;
      if st = 'cancelled' and cr <> 0 then probs := probs || format(' line%s: cancelled, credit %s still out;', it.n, cr); end if;
    end if;
  end loop;
  if st not in ('cancelled', 'refunded') then
    c := pg_temp.t451_codes(p_inv, 'cancel');
    if c ~ 'voucher_redeemed|credit_used' then probs := probs || ' Cancel asks ' || c || ';'; end if;
    if st in ('paid', 'partially_paid') then
      c := pg_temp.t451_codes(p_inv, 'refund_full');
      if c ~ 'voucher_redeemed|credit_used' then probs := probs || ' Refund in full asks ' || c || ';'; end if;
    end if;
  elsif st = 'cancelled' and cardinality(cancelled_invoice_used_value(p_inv)) > 0 then
    probs := probs || ' cancelled reads ' || array_to_string(cancelled_invoice_used_value(p_inv), ',') || ';';
  end if;
  if p_stock0 is not null and p_stock0 - pg_temp.t451_stock() <> pg_temp.t451_held(p_inv) then
    probs := probs || format(' stock out %s for %s units out;', p_stock0 - pg_temp.t451_stock(), pg_temp.t451_held(p_inv));
  end if;
  probs := probs || coalesce(current_setting('t451.dialog', true), '');
  perform set_config('t451.dialog', '', true);
  return probs;
end $f$;

-- Reopen through the Finance panel: its dialog first (recorded), then the
-- reopening; what the dialog said is compared with what the reopening queued
-- and took (read by t451_problems).
create function pg_temp.t451_reopen(p_inv uuid) returns void language plpgsql as $f$
declare pv jsonb; units int; stk int; w0 int; req uuid := gen_random_uuid(); queued int; s0 int; s1 int; st text; ded int; probs text := '';
begin
  pv := invoice_reopen_preview(p_inv);
  units := (pv->>'voucher_units_to_reinstate_after_settlement')::int;
  stk := coalesce((select sum((s->>'quantity')::int) from jsonb_array_elements(pv->'stock_to_issue') s
                    where s->>'item_id' = pg_temp.t451_id('vl')::text), 0);
  w0 := pg_temp.t451_waiting(p_inv);
  s0 := pg_temp.t451_stock();
  perform reopen_invoice(p_inv, 'T451 reopen', req);
  s1 := pg_temp.t451_stock();
  queued := coalesce((select sum(quantity) from invoice_reopen_vouchers where invoice_id = p_inv and request_id = req), 0);
  insert into t451_dialog(inv, units, waiting_before, queued) values (p_inv, units, w0, queued);
  select status::text into st from invoices where id = p_inv;
  if units <> w0 + queued then
    probs := probs || format(' the dialog said %s units to replace, %s were (%s waiting + %s queued);', units, w0 + queued, w0, queued); end if;
  if st in ('paid', 'completed_foc') then
    -- reopened straight to paid: its stock taken now, and what waited given
    -- at once (its stock too, the voucher limited)
    ded := (s0 - s1) - case when exists (select 1 from invoice_items where invoice_id = p_inv and voucher_id = pg_temp.t451_id('vl'))
                            then w0 + queued else 0 end;
  else
    ded := coalesce((select quantity from invoice_stock_to_deduct(p_inv) where kind <> 'product' and item_id = pg_temp.t451_id('vl')), 0);
  end if;
  if stk <> ded then
    probs := probs || format(' the dialog said stock to issue %s, the reopening and its payment take %s besides what waits;', stk, ded); end if;
  perform set_config('t451.dialog', probs, true);
end $f$;

-- One step (the letters above); null when done, 'n/a' when it does not
-- apply in this state, or the refusal.
create function pg_temp.t451_step(p_inv uuid, p_op text) returns text language plpgsql as $f$
declare st text; r text; n int; k int; outst numeric; due numeric; nlines int;
begin
  select status::text into st from invoices where id = p_inv;
  select count(*) into nlines from invoice_items where invoice_id = p_inv;
  outst := (invoice_financial_position(p_inv)->>'outstanding')::numeric;
  due := (invoice_financial_position(p_inv)->>'refund_due')::numeric;
  k := case when p_op like '%x2' then 2 else 1 end;
  n := coalesce(nullif(substring(p_op from '^[A-Za-z]+([0-9])'), '')::int, 1);
  if n > nlines then return 'n/a'; end if;
  if p_op = 'C' then
    if st = 'cancelled' then return 'n/a'; end if;
    perform cancel_invoice_recorded(p_inv, 'T451 cancel', gen_random_uuid()); return null;
  elsif p_op = 'O' then
    if st not in ('cancelled', 'refunded') then return 'n/a'; end if;
    perform pg_temp.t451_reopen(p_inv); return null;
  elsif p_op = 'P' then
    if st not in ('partially_paid', 'unpaid') or outst <= 0 then return 'n/a'; end if;
    perform record_invoice_payment(p_inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.t451_id('pm'),
      'amount', outst)), gen_random_uuid());
    return null;
  elsif p_op = 'B' then
    if st <> 'cancelled' or due < 30 then return 'n/a'; end if;
    r := pg_temp.t451_record_refund(p_inv, 30);
    return case when r = 'recorded' then null else 'refused: ' || r end;
  elsif p_op = 'F' then
    if st not in ('paid', 'partially_paid') then return 'n/a'; end if;
    r := pg_temp.t451_guided(p_inv, 'refund_full', '[]', true);
    return case when r like 'ERR%' then 'refused: ' || r end;
  elsif p_op = 'Kr' then
    if st not in ('paid', 'partially_paid', 'unpaid') then return 'n/a'; end if;
    r := pg_temp.t451_guided(p_inv, 'cancel', '[]', true);
    return case when r like 'ERR%' then 'refused: ' || r end;
  elsif p_op like 'G%' then
    if st not in ('paid', 'partially_paid') then return 'n/a'; end if;
    r := pg_temp.t451_guided(p_inv, 'refund_partial',
      jsonb_build_array(jsonb_build_object('invoice_item_id', pg_temp.t451_line(p_inv, n), 'quantity', k)), true);
    return case when r like 'ERR%' then 'refused: ' || r end;
  elsif p_op like 'L%' then
    if exists (select 1 from invoice_items where id = pg_temp.t451_line(p_inv, n) and line_kind::text = 'voucher') then
      r := pg_temp.t451_line_back(p_inv, n, k);
    else
      r := pg_temp.t451_line_back(p_inv, n);
    end if;
    return case when r = 'recorded' then null else 'refused: ' || r end;
  elsif p_op like 'V%' then                       -- one voucher unit of a bundle line
    r := pg_temp.t451_line_back(p_inv, n, 1);
    return case when r = 'recorded' then null else 'refused: ' || r end;
  elsif p_op like 'A%' then
    r := pg_temp.t451_line_back(p_inv, n, null, 40);
    return case when r = 'recorded' then null else 'refused: ' || r end;
  elsif p_op like 'M%' then
    if st not in ('paid', 'partially_paid', 'unpaid') then return 'n/a'; end if;
    return pg_temp.t451_move(p_inv, n);
  elsif p_op = 'X' then
    if st not in ('paid', 'partially_paid', 'unpaid') then return 'n/a'; end if;
    return pg_temp.t451_change(p_inv);
  end if;
  raise exception 'Fixture: unknown step %', p_op;
end $f$;
-- Steps in order, each required to apply; returns the invoice.
create function pg_temp.t451_steps(p_inv uuid, p_steps text) returns uuid language plpgsql as $f$
declare op text; r text;
begin
  -- Cleared before the steps, not after, so the reopenings' dialog checks
  -- reach t451_problems (it reads and clears them).
  perform set_config('t451.dialog', '', true);
  foreach op in array string_to_array(p_steps, ' ') loop
    r := pg_temp.t451_step(p_inv, op);
    if r is not null then raise exception 'Fixture: step % of "%" on % did not apply: %', op, p_steps, p_inv, r; end if;
  end loop;
  return p_inv;
end $f$;
-- A case from a fresh sale: p_spec 'v2' (a line of two), 'v3', 'vv' (two
-- lines of one), 'v2v' (a line of two and one of one), 'vl2' (limited),
-- 'foc2p' (an FOC of two limited vouchers taken off and paid), 'cp', 'cpcp',
-- 'cpb2', 'pbb2', 'pbv' (one Premium Bundle with vouchers).
create function pg_temp.t451_new(p_spec text) returns uuid language sql as $f$
  select case p_spec
    when 'v2' then pg_temp.t451_sale(array['v'], array[2])
    when 'v3' then pg_temp.t451_sale(array['v'], array[3])
    when 'vv' then pg_temp.t451_sale(array['v', 'v'], array[1, 1])
    when 'v2v' then pg_temp.t451_sale(array['v', 'v'], array[2, 1])
    when 'vl2' then pg_temp.t451_sale(array['vl'], array[2])
    when 'foc2p' then pg_temp.t451_foc_off(2, true)
    when 'cp' then pg_temp.t451_sale(array['cp'])
    when 'cpcp' then pg_temp.t451_sale(array['cp', 'cp'])
    when 'cpb2' then pg_temp.t451_sale(array['cpb', 'cpb'])
    when 'pbb2' then pg_temp.t451_sale(array['pbb', 'pbb'])
    when 'pbv' then pg_temp.t451_sale(array['pbv'])
  end $f$;
-- The whole outcome of an invoice, for comparing runs: status and money,
-- each line's units and credit out and waiting, both queues, the credit
-- ledger of its lots, the plans' codes, what is "used", the dialogs.
create function pg_temp.t451_outcome(p_inv uuid, p_stock0 int default null) returns jsonb language sql as $f$
  select jsonb_build_object(
    'status', i.status, 'net', invoice_net_received(i.id), 'charge', invoice_charge_total(i.id),
    'due', invoice_financial_position(i.id)->'refund_due',
    'lines', (select jsonb_agg(jsonb_build_array(pg_temp.t451_held(i.id, it.id), pg_temp.t451_line_waiting(it.id),
                                                 pg_temp.t451_line_credit(it.id), pg_temp.t451_line_cwaiting(it.id)) order by it.quantity desc, it.id)
                from invoice_items it where it.invoice_id = i.id),
    -- Totals, not rows: 446 lowers the most recently queued row first, and
    -- rows queued in one transaction tie on their time (a suite's do), so
    -- which row of a lot it lowers may differ between runs; the totals not.
    -- (Credit: what still waits only. 446 closes a credit row it refunds in
    -- full keeping its amount, which nothing reads, and lowers one it
    -- refunds in part, so the closed rows' amounts depend on that choice;
    -- the ledger below has what was given.)
    'vqueue', (select jsonb_build_array(coalesce(sum(q.quantity) filter (where q.applied_at is null), 0),
                                        coalesce(sum(q.quantity) filter (where q.applied_at is not null), 0))
                 from invoice_reopen_vouchers q where q.invoice_id = i.id),
    'cqueue', (select coalesce(sum(q.amount) filter (where q.applied_at is null), 0)
                 from invoice_reopen_benefits q where q.invoice_id = i.id),
    'ledger', (select coalesce(jsonb_agg(jsonb_build_array(x.entry_type, x.category, x.source_type, x.amount)
                                         order by x.entry_type, x.category, x.source_type), '[]')
                 from (select e.entry_type, e.category, e.source_type, sum(e.amount) as amount
                         from customer_credit_ledger e
                        where e.lot_id in (select b.lot_id from invoice_benefit_values b where b.invoice_id = i.id)
                        group by e.entry_type, e.category, e.source_type) x),
    'cancel', case when i.status in ('cancelled', 'refunded') then null else pg_temp.t451_codes(i.id, 'cancel') end,
    'refund_full', case when i.status in ('paid', 'partially_paid') then pg_temp.t451_codes(i.id, 'refund_full') end,
    'used', case when i.status = 'cancelled' then pg_temp.t451_used(i.id) end,
    'stock_out', case when p_stock0 is not null then p_stock0 - pg_temp.t451_stock() end,
    'dialogs', (select coalesce(jsonb_agg(d.units order by d.n), '[]') from t451_dialog d where d.inv = i.id))
    from invoices i where i.id = p_inv $f$;

-- ── The search: every sequence of the given steps, to p_depth, each undone ──
-- A fault is counted (t451_found) and printed; one of the kind 451 fixes (a
-- refund before a reopening, another after it, then a reopening) is not
-- also counted in t451_other.
create function pg_temp.t451_family(p_path text) returns boolean language plpgsql as $f$
declare t text; s int := 0;
begin
  foreach t in array string_to_array(btrim(split_part(p_path, ':', 2)), ' ') loop
    if s in (0, 2) and t ~ '^(G[0-9]|L[0-9]|Kr|F|V[0-9])' then s := s + 1;
    elsif s in (1, 3) and t = 'O' then s := s + 1;
    end if;
  end loop;
  return s >= 4;
end $f$;
create function pg_temp.t451_explore(p_inv uuid, p_path text, p_depth int, p_ops text[], p_stock0 int) returns void language plpgsql as $f$
declare op text; r text; pr text;
begin
  if p_depth <= 0 then return; end if;
  foreach op in array p_ops loop
    begin
      r := pg_temp.t451_step(p_inv, op);
      if r is null then
        perform nextval('t451_steps');
        pr := pg_temp.t451_problems(p_inv, p_stock0);
        if pr <> '' then
          raise exception using errcode = 'P0991', message = p_path || ' ' || op || ' =>' || pr;
        end if;
        perform pg_temp.t451_explore(p_inv, p_path || ' ' || op, p_depth - 1, p_ops, p_stock0);
      end if;
      raise exception using errcode = 'P0990', message = 'undo';
    exception
      when sqlstate 'P0990' then null;
      when sqlstate 'P0991' then
        perform nextval('t451_found');
        if not pg_temp.t451_family(split_part(sqlerrm, ' =>', 1)) then perform nextval('t451_other'); end if;
        if currval('t451_found') <= 3 or not pg_temp.t451_family(split_part(sqlerrm, ' =>', 1)) then
          raise notice 'search found: %', sqlerrm; end if;
    end;
  end loop;
end $f$;
-- One search from a fresh sale; returns 'steps found other' counted.
create function pg_temp.t451_search(p_spec text, p_ops text[], p_depth int) returns int[] language plpgsql as $f$
declare inv uuid; s0 int; n0 bigint; f0 bigint; o0 bigint;
begin
  perform nextval('t451_steps'); perform nextval('t451_found'); perform nextval('t451_other');
  n0 := currval('t451_steps'); f0 := currval('t451_found'); o0 := currval('t451_other');
  s0 := pg_temp.t451_stock();
  inv := pg_temp.t451_new(p_spec);
  perform pg_temp.t451_explore(inv, p_spec || ':', p_depth, p_ops,
    case when exists (select 1 from invoice_items where invoice_id = inv and voucher_id = pg_temp.t451_id('vl')) then s0 end);
  return array[(currval('t451_steps') - n0)::int, (currval('t451_found') - f0)::int, (currval('t451_other') - o0)::int];
end $f$;

-- The cases (the siblings found) and the controls: name, how sold, steps.
create temp table t451_case(k text primary key, spec text, steps text, kind text, ord int generated always as identity);
insert into t451_case(k, spec, steps, kind) values
  ('V1', 'v2', 'G1 C O C L1 O P', 'case'),        -- the case in 448's NOT COVERED 1
  ('V2', 'v2', 'L1 C O L1 C O P', 'case'),        -- the second refund while waiting
  ('V3', 'v2', 'C L1 O L1 C O P', 'case'),        -- the first on the cancelled invoice
  ('V4', 'v2', 'G1 C O Kr O P', 'case'),          -- the guided Cancel with the money recorded
  ('V5', 'v2', 'G1 C O F C O P', 'case'),         -- the guided Refund in full while waiting
  ('V6', 'v3', 'G1 C O L1x2 C O P', 'case'),      -- a line of three: one, then two
  ('V7', 'v3', 'G1x2 C O L1 C O P', 'case'),      -- two, then one
  ('V8', 'vl2', 'G1 C O C L1 O P', 'case'),       -- limited: its stock
  ('V9', 'vl2', 'M1 L1 C O Kr O P', 'case'),      -- after a Move to the friend
  ('V10', 'vl2', 'X G1 C O Kr O P', 'case'),      -- after a customer change
  ('V11', 'foc2p', 'L1 C O C L1 O P', 'case'),    -- an FOC taken off and paid (416's rows)
  ('V12', 'pbv', 'V1 C O C V1 O P', 'case'),      -- a Premium Bundle's two vouchers
  ('V13', 'v3', 'G1 C O C L1 O L1 C O P', 'case'),-- three cycles on a line of three
  ('N1', 'v2', 'C B O C O P', 'control'),         -- 417's own case
  ('N2', 'v2', 'C B O L1 C O P', 'control'),      -- 446's: refunded while waiting, cancelled again, reopened
  ('N3', 'v2', 'G1 C O P', 'control'),            -- a refund before the reopening only
  ('N4', 'vl2', 'C B O L1 P', 'control'),         -- refunded while waiting, settled (446's fix)
  ('N5', 'vv', 'G1 C O L2 C O P', 'control'),     -- two lines of one
  ('N6', 'foc2p', 'C B O P', 'control'),          -- an FOC taken off, paid, cancelled, reopened
  ('N7', 'vl2', 'C B O P M1 C', 'control'),       -- a Move after settling, then cancelled
  ('N8', 'v2v', 'G2 C O L1 C O P', 'control'),    -- the line of one refunded before, the line of two after
  ('K1', 'cp', 'A1 C O A1 C O P', 'credit'),      -- S$40 before, S$40 while waiting
  ('K2', 'cp', 'A1 C O C A1 O P', 'credit'),      -- the second S$40 on the cancelled invoice
  ('K3', 'cp', 'C A1 O A1 C O P', 'credit'),      -- the first S$40 on the cancelled invoice
  ('K4', 'cp', 'A1 C O Kr O P', 'credit'),        -- the guided Cancel with the money recorded
  ('K5', 'cp', 'A1 C O F C O P', 'credit'),       -- the guided Refund in full while waiting
  ('K6', 'cpb2', 'G1 C O C L2 O P', 'credit'),    -- a package with a Bonus each side, whole lines
  ('K7', 'cpb2', 'A1 C O A1 C O P', 'credit'),    -- S$40 of a Bonus package's Paid credit each side
  ('K8', 'pbb2', 'G1 C O L2 C O P', 'credit'),    -- Premium Bundles
  ('K9', 'cpcp', 'A1 C O C A1 O A2 C O P', 'credit'); -- three reopenings, two packages
-- Run one listed case from a fresh sale; its outcome.
create function pg_temp.t451_run(p_k text) returns jsonb language plpgsql as $f$
declare c record; inv uuid; s0 int;
begin
  select * into c from t451_case where k = p_k;
  s0 := pg_temp.t451_stock();
  inv := pg_temp.t451_new(c.spec);
  perform pg_temp.t451_steps(inv, c.steps);
  insert into t451 values (p_k || case when pg_temp.t451_in() then ' after' else ' before' end, inv)
    on conflict (k) do update set id = excluded.id;
  return pg_temp.t451_outcome(inv, case when c.spec in ('vl2', 'foc2p') then s0 end)
         || jsonb_build_object('problems', pg_temp.t451_problems(inv, case when c.spec in ('vl2', 'foc2p') then s0 end));
end $f$;

-- ===== R. Without 451: the shortfall, every sibling (undone) =====
\if :{?nomig}
do $$ begin raise notice 'NOTE R: -v nomig=1 (451 in), so the shortfall without it is not reproduced'; end $$;
\else
do $$
declare c record; o jsonb; res text := ''; s int[];
begin
  insert into t451_fp values ('start', pg_temp.t451_fingerprint());
  if pg_temp.t451_in() then
    raise notice 'NOTE R: 451 was in before this suite started, so the shortfall is not reproduced';
    return;
  end if;
  begin
    for c in select * from t451_case where kind = 'case' order by ord loop
      o := pg_temp.t451_run(c.k);
      -- Each is short: the line charges more than the customer has (paid).
      perform pg_temp.t451_check(o->>'status' = 'paid' and o->>'problems' like '%paid, % out for % owed%',
        'R ' || c.k || ' (' || c.spec || ': ' || c.steps || ') is right without 451? ' || o::text);
      res := res || format(E'\n  %s %s: %s (%s); dialogs said %s', c.k, c.spec || ': ' || c.steps,
        o->>'problems', pg_temp.t451_state(pg_temp.t451_id(c.k || ' before')), o->'dialogs');
    end loop;
    -- V1 in figures: 1 voucher for S$60, Cancel and Refund in full ask
    -- voucher_redeemed, the second Reopen dialog said 1.
    o := pg_temp.t451_outcome(pg_temp.t451_id('V1 before'));
    perform pg_temp.t451_check(pg_temp.t451_held(pg_temp.t451_id('V1 before')) = 1 and (o->>'net')::numeric = 60
      and o->>'cancel' = 'voucher_redeemed' and o->>'refund_full' = 'voucher_redeemed' and o->'dialogs' = '[2, 1]'::jsonb,
      'R V1 in figures: ' || o::text);
    -- The search: every sequence of six steps on a line of two finds faults,
    -- all of this kind.
    s := pg_temp.t451_search('v2', array['G1', 'L1', 'C', 'O', 'P', 'Kr'], 6);
    perform pg_temp.t451_check(s[2] > 0 and s[3] = 0,
      format('R the search without 451: %s steps, %s faults, %s of another kind', s[1], s[2], s[3]));
    raise notice 'PASS R: without 451 (undone), each sibling is short once paid:%', res;
    raise notice 'PASS R: without 451 (undone), V1 holds 1 voucher for S$60, Cancel and Refund in full ask voucher_redeemed, the dialog said 2 then 1; the search of every 6-step sequence on a line of two (% steps) finds % faults, all a unit refunded before a reopening and another after it, then reopened', s[1], s[2];
    raise exception using errcode = 'P0990', message = 'undo';
  exception when sqlstate 'P0990' then null;
  end;
end $$;
\endif

-- ===== 0. Controls and credit before 451 =====
do $$
declare c record;
begin
  if not exists (select 1 from t451_fp where k = 'start') then
    insert into t451_fp values ('start', pg_temp.t451_fingerprint()); end if;
  if pg_temp.t451_in() then
    raise notice 'NOTE 0: 451 was in before this suite started, so the before/after comparison is skipped; the controls and credit are still checked after it';
    return;
  end if;
  for c in select * from t451_case where kind in ('control', 'credit') order by ord loop
    insert into t451_out(k, before) values (c.k, pg_temp.t451_run(c.k));
  end loop;
  -- Right without 451 too (credit: the analogue does not exist).
  perform pg_temp.t451_check(not exists (select 1 from t451_out where before->>'problems' <> ''),
    '0 a control or credit case is wrong before 451: '
    || (select string_agg(k || ' ' || (before->>'problems'), '; ') from t451_out where before->>'problems' <> ''));
  raise notice 'PASS 0: before 451, the controls (%) and the credit cases (%) are right by the oracle; outcomes recorded',
    (select string_agg(k, ' ' order by ord) from t451_case where kind = 'control'),
    (select string_agg(k, ' ' order by ord) from t451_case where kind = 'credit');
end $$;

-- ===== 9. The refusal (before 451 is installed) =====
\if :{?nomig}
do $$ begin raise notice 'NOTE 9: -v nomig=1 (451 in), so its refusal on a database carrying the fault is not tried'; end $$;
\else
savepoint t451_refusal;
do $$
declare inv uuid;
begin
  -- The footprint: V1's steps up to the second reopening (still waiting),
  -- and V2's paid since.
  inv := pg_temp.t451_steps(pg_temp.t451_new('v2'), 'G1 C O C L1 O');
  insert into t451 values ('F1', inv);
  inv := pg_temp.t451_steps(pg_temp.t451_new('v2'), 'L1 C O L1 C O P');
  insert into t451 values ('F2', inv);
  -- Not listed: 446's own case (no line refund before the first reopening);
  -- a refund while waiting not yet followed by a reopening; a no-item refund
  -- before the reopening.
  perform pg_temp.t451_steps(pg_temp.t451_new('v2'), 'C B O L1 C O');
  perform pg_temp.t451_steps(pg_temp.t451_new('v2'), 'G1 C O C L1');
  perform pg_temp.t451_steps(pg_temp.t451_new('v2'), 'C B O C L1 O');
end $$;
select string_agg(invoice_no, ', ' order by invoice_no) as t451_faulty from invoices
 where id in (pg_temp.t451_id('F1'), pg_temp.t451_id('F2')) \gset
\set ON_ERROR_STOP 0
\ir ../../../supabase/451_reopen_refund_cycles_give_what_was_paid.sql
\set ON_ERROR_STOP 1
rollback to savepoint t451_refusal;
select pg_temp.t451_check(:'LAST_ERROR_MESSAGE' = '451: 2 invoice(s) had a voucher unit refunded by line before a reopening and another while it waited, and were reopened again ('
         || :'t451_faulty' || '): that reopening may have queued too few. Decide what each customer should hold, then apply. Nothing was changed.',
       '9 451 on a database carrying the fault: ' || :'LAST_ERROR_MESSAGE') as t451_9_refused \gset
do $$
begin
  perform pg_temp.t451_check(pg_temp.t451_fingerprint() = (select fp from t451_fp where k = 'start') and not pg_temp.t451_in(),
    '9 the refused 451 changed functions');
  raise notice 'PASS 9: on a database carrying the fault (one invoice still waiting, one paid since), 451 refuses, names those two only (not 446''s own case, a refund while waiting not yet reopened, nor a no-item refund before the reopening) and changes nothing';
end $$;
\endif

-- ===== 10. Install 451, twice =====
\if :{?nomig}
do $$ begin perform pg_temp.t451_check(pg_temp.t451_in(), '10 -v nomig=1 but 451 is not in'); end $$;
\else
do $$
begin
  insert into t451_fp values ('grants', pg_temp.t451_grants('reopen_invoice(uuid,text,uuid)') || ' | '
                                        || pg_temp.t451_grants('invoice_reopen_preview_before_sessions(uuid)'));
end $$;
\ir ../../../supabase/451_reopen_refund_cycles_give_what_was_paid.sql
do $$ begin insert into t451_fp values ('first', pg_temp.t451_fingerprint()); end $$;
\ir ../../../supabase/451_reopen_refund_cycles_give_what_was_paid.sql
do $$ begin insert into t451_fp values ('second', pg_temp.t451_fingerprint()); end $$;
\endif
do $$
declare ro text := 'reopen_invoice(uuid,text,uuid)'; pv text := 'invoice_reopen_preview_before_sessions(uuid)';
begin
  perform pg_temp.t451_check(pg_temp.t451_in()
    -- reopen_invoice: 451's AFTER, or 458's (rentals follow the reopening: one line, where it raises the items),
    -- or 475's (a session still waiting from an earlier reopening is not queued again; 451's voucher step as it is)
    and md5(pg_get_functiondef(('public.' || ro)::regprocedure)) in ('cb647331300b0a476c1da7b2cb599889', '0ff61e4ead121c198ea7f90a7fc78274',
                                                                    '30066e137b9b75b5789a050c14debc04')
    -- the preview: 451's AFTER, or 474's (it also counts the credit still waiting for a reopening's payment),
    -- or 478's (it also names what a reopening of a package paid in part gives at once, what the settling payment gives, its vouchers
    -- and a package's reward units among them, and to whom; 451's voucher figure as it is)
    and md5(pg_get_functiondef(('public.' || pv)::regprocedure)) in ('12206ed066495024421b3b44a6a9d8e2', '7e1ef2d25415e69b3f770fe2efd45190',
                                                                    'acbfc38a20a000e1af0e78d26fc7fc4c'), '10 451 is not installed as tested');
  if exists (select 1 from t451_fp where k = 'first') then
    perform pg_temp.t451_check((select fp from t451_fp where k = 'second') = (select fp from t451_fp where k = 'first'),
      '10 the second run of 451 changed functions');
    perform pg_temp.t451_check(split_part((select fp from t451_fp where k = 'first'), ' ', 2) = split_part((select fp from t451_fp where k = 'start'), ' ', 2),
      '10 451 changed the number of functions');
    perform pg_temp.t451_check(pg_temp.t451_grants(ro) || ' | ' || pg_temp.t451_grants(pv) = (select fp from t451_fp where k = 'grants'),
      '10 the grants changed');
  end if;
  perform pg_temp.t451_check((select count(*) from pg_proc where pronamespace = 'public'::regnamespace
                               and proname in ('reopen_invoice', 'invoice_reopen_preview_before_sessions')) = 2, '10 an overload exists');
  perform pg_temp.t451_check(has_function_privilege('authenticated', 'public.' || ro, 'execute') and has_function_privilege('service_role', 'public.' || ro, 'execute')
    and not has_function_privilege('anon', 'public.' || ro, 'execute')
    and has_function_privilege('service_role', 'public.' || pv, 'execute') and not has_function_privilege('authenticated', 'public.' || pv, 'execute')
    and not has_function_privilege('anon', 'public.' || pv, 'execute'), '10 who may call them changed');
  raise notice 'PASS 10: 451 installed (reopen_invoice %, the preview %); %; no overload; reopen_invoice for signed-in staff and the service role, the preview for the service role alone',
    md5(pg_get_functiondef(('public.' || ro)::regprocedure)), md5(pg_get_functiondef(('public.' || pv)::regprocedure)),
    coalesce('the second run changed nothing (' || (select fp from t451_fp where k = 'second') || ')', 'it was in before the suite (nomig)');
end $$;

-- ===== 1. Each case after 451 =====
do $$
declare c record; o jsonb; inv uuid; res text := ''; s0 int; r text;
begin
  for c in select * from t451_case where kind = 'case' order by ord loop
    o := pg_temp.t451_run(c.k);
    inv := pg_temp.t451_id(c.k || ' after');
    perform pg_temp.t451_check(o->>'status' = 'paid' and o->>'problems' = '' and o->>'cancel' = '-' and o->>'refund_full' = '-',
      '1 ' || c.k || ' (' || c.spec || ': ' || c.steps || ') after 451: ' || o::text);
    -- A further cycle: cancelled (nothing used), reopened, paid: still right.
    s0 := case when c.spec in ('vl2', 'foc2p') then pg_temp.t451_stock() + pg_temp.t451_held(inv) end;
    perform pg_temp.t451_steps(inv, 'C');
    perform pg_temp.t451_check(pg_temp.t451_used(inv) = '-' and pg_temp.t451_problems(inv, s0) = '',
      '1 ' || c.k || ' cancelled again reads ' || pg_temp.t451_used(inv));
    perform pg_temp.t451_steps(inv, 'O');
    if (select status::text from invoices where id = inv) <> 'paid' then perform pg_temp.t451_steps(inv, 'P'); end if;
    perform pg_temp.t451_check(pg_temp.t451_problems(inv, s0) = '' and (select status::text from invoices where id = inv) = 'paid',
      '1 ' || c.k || ' a further cycle: ' || pg_temp.t451_state(inv) || pg_temp.t451_problems(inv, s0));
    res := res || format(E'\n  %s %s: %s; dialogs said %s', c.k, c.spec || ': ' || c.steps, pg_temp.t451_state(inv), o->'dialogs');
  end loop;
  -- V1 in figures: 2 vouchers for S$60 (the further cycle reopened it
  -- straight to paid, its S$60 still held); the second dialog said 2 (1
  -- waiting, 1 queued now); the further cycle's 2 (both queued).
  o := pg_temp.t451_outcome(pg_temp.t451_id('V1 after'));
  perform pg_temp.t451_check((o->>'net')::numeric = 60 and pg_temp.t451_held(pg_temp.t451_id('V1 after')) = 2
    and o->'dialogs' = '[2, 2, 2]'::jsonb
    and (select string_agg(d.waiting_before || '+' || d.queued, ' ' order by d.n) from t451_dialog d
          where d.inv = pg_temp.t451_id('V1 after')) = '0+2 1+1 0+2',
    '1 V1 in figures: ' || o::text);
  -- Cancelled, "Record refund paid" records all that is due (nothing used).
  inv := pg_temp.t451_steps(pg_temp.t451_new('v2'), 'G1 C O C L1 O P C');
  perform pg_temp.t451_check(pg_temp.t451_used(inv) = '-' and (invoice_financial_position(inv)->>'refund_due')::numeric = 60,
    '1 V1 cancelled once settled: ' || pg_temp.t451_state(inv) || ' used ' || pg_temp.t451_used(inv));
  r := pg_temp.t451_record_refund(inv, 60);
  perform pg_temp.t451_check(r = 'recorded' and invoice_net_received(inv) = 0,
    '1 V1 cancelled once settled, "Record refund paid" S$60: ' || r || ' ' || pg_temp.t451_state(inv));
  raise notice 'PASS 1: with 451 each sibling holds what its lines charge once paid, with nothing asked by Cancel or Refund in full; cancelled again, reopened and paid: still right:%', res;
  raise notice 'PASS 1: V1 (a line of two): 2 vouchers for S$60, the dialogs said 2, 2 and 2 (the second reopening: 1 waiting + 1 queued); cancelled once settled, nothing reads used and "Record refund paid" records the S$60';
end $$;

-- ===== 2. The controls and credit after 451: unchanged and right =====
do $$
declare c record; o jsonb; diff text := '';
begin
  for c in select * from t451_case where kind in ('control', 'credit') order by ord loop
    o := pg_temp.t451_run(c.k);
    perform pg_temp.t451_check(o->>'problems' = '', '2 ' || c.k || ' (' || c.spec || ': ' || c.steps || ') is wrong after 451: ' || o::text);
    update t451_out set after = o where k = c.k;
    if not found then insert into t451_out(k, after) values (c.k, o); end if;
  end loop;
  if exists (select 1 from t451_out where before is not null) then
    select string_agg(k || E':\n    before ' || before::text || E'\n    after  ' || after::text, E'\n') into diff
      from t451_out where before is distinct from after;
    perform pg_temp.t451_check(diff is null, E'2 a control or credit case changed with 451:\n' || coalesce(diff, ''));
    raise notice 'PASS 2: the controls and the credit cases are exactly as before 451, whole (status, money, each line''s units and credit out and waiting, both queues, the credit ledger, stock, the plans'' codes, the dialogs), and right';
  else
    raise notice 'PASS 2: the controls and the credit cases are right with 451 (not compared: it was in before the suite)';
  end if;
  raise notice 'PASS 2 (credit): no shortfall: % each right %(credit is queued by ledger row, once, and given once)',
    (select string_agg(k || ' ' || spec || ': ' || steps || ' -> ' || pg_temp.t451_state(pg_temp.t451_id(k || ' after')), '; ' order by ord)
       from t451_case where kind = 'credit'),
    case when exists (select 1 from t451_out where before is not null) then 'without 451 and, unchanged, with it ' else 'with 451 ' end;
end $$;

-- ===== 3. The search after 451: every sequence, no fault =====
do $$
declare s int[]; res text := ''; c record;
begin
  for c in select * from (values
      ('v2', array['G1', 'L1', 'C', 'O', 'P', 'Kr'], 6),
      ('vl2', array['G1', 'L1', 'C', 'O', 'P', 'Kr', 'M1', 'X'], 5),
      ('cp', array['A1', 'L1', 'C', 'O', 'P', 'Kr'], 6),
      ('cpcp', array['G1', 'A1', 'A2', 'C', 'O', 'P', 'Kr'], 5)) x(spec, ops, depth) loop
    s := pg_temp.t451_search(c.spec, c.ops, c.depth);
    perform pg_temp.t451_check(s[2] = 0, format('3 the search on %s (%s, %s steps deep) found %s faults (above)', c.spec, array_to_string(c.ops, ' '), c.depth, s[2]));
    res := res || format(E'\n  %s, %s, %s deep: %s steps, no fault', c.spec, array_to_string(c.ops, ' '), c.depth, s[1]);
  end loop;
  raise notice 'PASS 3: with 451, every sequence of these steps leaves each line holding what it charges, with what waits, the stock, the dialog and 448''s counting right:%', res;
end $$;

-- ===== 4. 448's counting after 451: a real redemption still asked =====
do $$
declare inv uuid;
begin
  -- A line of three: one unit refunded, cancelled, reopened, cancelled again,
  -- one refunded by line, reopened, paid (3 held), then one redeemed.
  inv := pg_temp.t451_steps(pg_temp.t451_new('v3'), 'G1 C O C L1 O P');
  perform pg_temp.t451_check(pg_temp.t451_held(inv) = 3 and pg_temp.t451_codes(inv, 'cancel') = '-', '4 fixture: ' || pg_temp.t451_state(inv));
  update customer_reward_vouchers set status = 'redeemed', redeemed_at = now()
   where id = (select v.id from invoice_benefit_values b join customer_reward_vouchers v on v.id = b.reward_voucher_id
                where b.invoice_id = inv and v.status = 'held' order by v.quantity, v.id limit 1);
  perform pg_temp.t451_check(pg_temp.t451_codes(inv, 'cancel') = 'voucher_redeemed' and pg_temp.t451_codes(inv, 'refund_full') = 'voucher_redeemed',
    '4 a unit redeemed after the cycles is not asked: ' || pg_temp.t451_codes(inv, 'cancel'));
  perform pg_temp.t451_steps(inv, 'C');
  perform pg_temp.t451_check(pg_temp.t451_used(inv) = 'voucher_redeemed', '4 cancelled, the redemption reads ' || pg_temp.t451_used(inv));
  raise notice 'PASS 4: after the cycles (451), a unit really redeemed still reads voucher_redeemed to Cancel and Refund in full, and once cancelled';
end $$;

-- ===== 8. KNOWN: not covered by 451 =====
do $$
declare inv uuid; it uuid; b uuid;
begin
  -- 451's NOT COVERED 1: a direct call with the 'larger_refund' override (no
  -- page sends it) pays back S$60 for one unit of a line of two; reopened
  -- (1 held, 1 waits), cancelled, reopened again: 1 waits for S$60.
  inv := pg_temp.t451_new('v2');
  select id into it from invoice_items where invoice_id = inv;
  select id into b from invoice_benefit_values where invoice_id = inv;
  perform refund_invoice_recorded(inv, jsonb_build_array(jsonb_build_object('invoice_item_id', it, 'amount', 60,
      'benefits', jsonb_build_array(jsonb_build_object('benefit_id', b, 'amount', 30)),
      'override', jsonb_build_object('code', 'larger_refund', 'reason', 'T451 direct call', 'amount', 60))),
    pg_temp.t451_sources(inv, 60), '[]'::jsonb, 'T451 larger refund', gen_random_uuid());
  perform pg_temp.t451_steps(inv, 'O C O P');
  perform pg_temp.t451_check(pg_temp.t451_held(inv) = 1 and invoice_net_received(inv) = 60,
    '8 the larger_refund case: ' || pg_temp.t451_state(inv) || ': look at 451''s NOT COVERED 1 and this case again');
  raise notice 'KNOWN 8: (not covered by 451; 417''s rule, there before 446) a direct call with the ''larger_refund'' override (no page sends it) refunds S$60 for one unit of a line of two, the other stays held through the reopening; cancelled and reopened again, then paid: % (1 voucher for S$60); %',
    pg_temp.t451_state(inv), case when pg_temp.t451_in() then 'the same with 451' else 'without 451' end;
end $$;

rollback;
