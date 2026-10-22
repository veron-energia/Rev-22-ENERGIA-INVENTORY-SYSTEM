-- 448: a voucher unit, or credit, that a line refund already paid back is not
-- "used" (438's NOT COVERED 2, 446's NOT COVERED 1; the Owner, 22 Oct 2026:
-- "build the warning fix").
--
-- Every step goes through the app's own calls: the invoice form
-- (create_invoice_with_details) and the Pay dialog (record_invoice_settlement),
-- the guided "Refund some items", Refund in full and Cancel
-- (invoice_action_plan, request_invoice_action_v2, resolve_invoice_action_v2),
-- Cancel (cancel_invoice_recorded), the Finance panel's "Record refund paid"
-- (refund_invoice_recorded with no item), its line-by-line refund
-- (refund_invoice_recorded with the line's benefits), Reopen (reopen_invoice),
-- Record Payment (record_invoice_payment), Move
-- (transfer_invoice_unused_benefit), the invoice form's customer change
-- (correct_invoice, 'transfer'), a customer merge (merge_customer_records) and
-- the FOC taken off (correct_invoice). A redeemed voucher is set 'redeemed'
-- (or, for one unit of a voucher of several, its quantity lowered by one) and
-- spent credit is taken off its lot, as the other suites do.
--
--   A. The cases, built before 448 is installed (one invoice each; the key in
--      brackets), and the controls.
--      Vouchers: a line of two, one unit refunded [VA], then cancelled [VB];
--      two lines, line A refunded [VC]; a line of two, one unit refunded and
--      the other redeemed [VD]; a line of three, one refunded, one redeemed,
--      one held [VE]; two limited vouchers, line A refunded, cancelled and
--      reopened, the rest waiting [VF]; a line of two, one unit refunded,
--      cancelled and reopened, waiting [VG]; line A refunded while the
--      reopening's vouchers waited (446), then settled [VH]; a line of two,
--      one unit refunded and the other moved to a friend [VI], and the
--      friend redeems it [VI2]; two lines, line A refunded, the customer
--      changed with the benefits taken along [VJ]; an FOC taken off and
--      paid (416 gives the vouchers again), one unit refunded [VK]; a
--      session line with a session delivered beside a line of two with one
--      unit refunded [VL].
--      Credit: two S$100 Credit Packages with a S$10 Bonus, line A refunded
--      [CA], then cancelled [CB]; S$40 of a S$100 package refunded [CC], and
--      the same with a guided Refund in full requested before 448 [CQ];
--      line A's Paid credit alone refunded [CD]; two Premium Bundles (S$100
--      Paid, S$20 Bonus), line A refunded [CE]; two Premium Bundles with two
--      S$30 vouchers each, line A refunded [CV]; S$40 refunded and S$10 spent
--      on the same lot [CF]; two packages, line A refunded, cancelled and
--      reopened, waiting [CG]; S$40 refunded, cancelled and reopened, waiting
--      [CH]; line A refunded while the reopening's credit waited (446), then
--      settled [CI]; S$40 refunded and the rest moved to a friend [CJ], and
--      the friend spends S$10 [CJ2]; two packages, line A refunded, the
--      customer changed with the benefits taken along [CK]; S$40 refunded,
--      the buyer then merged into another record [CL]; a part-paid package's
--      released credit, settled, line A refunded [CM].
--      Controls (no line refund, or one whose answer stays): a paid sale;
--      one of two redeemed; cancelled, unused and redeemed; credit spent,
--      and then cancelled; cancelled, reopened and settled (438); a voucher
--      and credit moved (438); a session delivered; credit taken along by a
--      customer change (447); a part-paid package whose released credit was
--      spent, never settled; an FOC taken off and paid (438); credit
--      cancelled and reopened straight to paid.
--   R. Before 448 (skipped, with a notice, where 448 was in before the suite
--      started): each case asks the false override it was found asking, and
--      cancelled directly it reads as used.
--   Q. The read-only query in 448's header, run before 448 is installed
--      (the same text): it lists exactly the invoices whose answer changes.
--  10. 448 installed twice: the second run changes nothing; one function
--      added (the helper), none dropped; the helper is the server's alone;
--      the two patched functions keep their grants; no overload.
--   0. The controls read exactly as before 448: "used", and the whole plans
--      of Cancel and Refund in full (codes, money, hash).
--   1. Each case asks what it should after 448 (only real use: VD, VE, VI2,
--      VL's session, CF, CJ2), and its plans' money is exactly as before 448
--      (lines, amounts, benefits, sources, refund due): only the overrides,
--      the amount owed question, the summary and the hash change.
--   2. The money afterwards, through the app's own calls: a refunded unit or
--      credit is not paid back twice and the rest is (Refund in full; the
--      guided Cancel with and without the money recorded; "Record refund
--      paid" up to the refund due and not a cent more; the line-by-line
--      refund of a credit invoice); a real use still needs the amount owed
--      stated, and "Record refund paid" is held to it.
--   3. Interplay after 448: reopened and settled (VF, VG, CG, CH), cancelled
--      again (nothing used, the money recorded); the voucher stock back.
--   4. A guided request raised before 448 on a case invoice (CQ): approving
--      it now asks to confirm the revised plan (its hash changed), as 438's
--      did; confirmed, it goes with no override.
--   8. KNOWN (448's header, NOT COVERED 1-3), checked as they are: (1) one
--      unit of a line of two refunded, cancelled and reopened (waiting),
--      cancelled again, the other unit refunded by line while waiting,
--      reopened again: the reopening queues one unit too few (446 takes the
--      second unit off the queue and 417's "only what is more" then queues
--      nothing for it; before 446 it was right), settled the customer holds
--      1 voucher for S$60, and 448 reads the unit never given as redeemed
--      (where 451 is in, checked the fixed way: 2 wait, 2 vouchers for S$60
--      once settled, nothing asked; printed as FIXED);
--      (2) a refunded credit line, the buyer merged away, cancelled, reopened
--      and settled: the refund is reinstated on the merged-away record's lot
--      (there before 448), and it reads as spent; (3) a partly refunded
--      credit lot still blocks a customer change as "Partly spent".
--
-- Run on a copy of production as it is (450 in: 46683a93, 1370 functions; it
-- passes the same on 447's head without 450, 9d2e2fdd):
--   psql -v ON_ERROR_STOP=1 -f scripts/invoices/tests/refunded-units-not-used-448.sql
-- It installs 448 itself, twice, inside its transaction. Where 448 is in
-- already, add -v nomig=1 (R and the before/after comparisons are then
-- skipped with a notice; every figure after 448 is still checked).
-- Disposable database only; everything is rolled back. Every name, code and
-- amount is invented (@example.com); the phones are numbers kept for fiction
-- (ACMA).
\set ON_ERROR_STOP on
begin;

create temp table t448(k text primary key, id uuid);
create temp table t448_before(k text primary key, reads jsonb);
create temp table t448_q(invoice_id uuid primary key);
create temp table t448_fp(k text primary key, fp text);
create temp table t448_known(k text primary key, v text);
create function pg_temp.t448_id(p_k text) returns uuid language sql as $f$ select id from t448 where k = p_k $f$;
create function pg_temp.t448_check(p_ok boolean, p_label text) returns void language plpgsql as $f$
begin
  if not coalesce(p_ok, false) then raise exception 'FAIL %', p_label; end if;
end $f$;
create function pg_temp.t448_fingerprint() returns text language sql as $f$
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.oid::regprocedure::text)) || ' ' || count(*)
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prokind in ('f', 'p') $f$;
-- 451 (448's NOT COVERED 1 fixed): the reopening queues a unit refunded on
-- each side of an earlier reopening.
create function pg_temp.t448_451_in() returns boolean language sql as $f$
  select position('-- 451 (the Owner' in pg_get_functiondef('public.reopen_invoice(uuid,text,uuid)'::regprocedure)) > 0 $f$;
create function pg_temp.t448_in() returns boolean language sql as $f$
  select to_regprocedure('public.invoice_benefit_unused_elsewhere(uuid)') is not null
     and position('-- 448:' in pg_get_functiondef('public.cancelled_invoice_used_value(uuid)'::regprocedure)) > 0
     and position('-- 448 (the Owner' in pg_get_functiondef('public.invoice_action_plan(uuid,text,jsonb)'::regprocedure)) > 0 $f$;

do $$
declare own uuid := gen_random_uuid(); st uuid; c uuid; c2 uuid; mk uuid; md uuid; md2 uuid; pm uuid; v uuid; vl uuid;
        cp uuid; cpb uuid; pbb uuid; pbv uuid; ts uuid;
begin
  insert into auth.users(id, email) values (own, 't448-owner@example.com');
  insert into profiles(id, full_name, email, role, is_active) values (own, 'T448 Owner', 't448-owner@example.com', 'owner', true);
  perform set_config('request.jwt.claims', json_build_object('sub', own, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', own::text, true);
  insert into stores(name, code, country_code) values ('T448 Store', 'T448S1', 'SG') returning id into st;
  insert into customers(full_name, phone) values ('T448 Buyer', '+61491570441') returning id into c;
  insert into customers(full_name, phone) values ('T448 Friend', '+61491570442') returning id into c2;
  -- A record kept and its duplicate, for the merge (CL, KNOWN 8).
  insert into customers(full_name, phone) values ('T448 Kept', '+61491570443') returning id into mk;
  insert into customers(full_name, phone) values ('T448 Duplicate', '+61491570444') returning id into md;
  insert into customers(full_name, phone) values ('T448 Duplicate Two', '+61491570445') returning id into md2;
  insert into payment_methods(name, is_active) values ('T448 Cash', true) returning id into pm;
  -- A plain S$30 voucher, and a limited one (100 in stock) to follow stock.
  insert into vouchers(name, code, voucher_kind, qty_type, selling_price, is_active)
    values ('T448 Plain 30', 'T448-P30', 'normal', 'unlimited', 30, true) returning id into v;
  insert into voucher_store_prices(voucher_id, store_id, selling_price, available_at_store) values (v, st, 30, true);
  insert into vouchers(name, code, voucher_kind, qty_type, selling_price, is_active)
    values ('T448 Limited 30', 'T448-L30', 'normal', 'limited', 30, true) returning id into vl;
  insert into voucher_store_prices(voucher_id, store_id, selling_price, available_at_store) values (vl, st, 30, true);
  insert into voucher_store_stock(voucher_id, store_id, current_qty) values (vl, st, 100);
  -- A S$100 Credit Package (S$100 Paid), one with a S$10 Bonus, and a Premium
  -- Bundle of S$100 Paid and S$20 Bonus, each S$100.
  insert into credit_packages(name, customer_price, paid_credit_amount, bonus_enabled, allow_product, allow_therapy)
    values ('T448 S$100', 100, 100, false, true, true) returning id into cp;
  insert into credit_package_stores(package_id, store_id) values (cp, st);
  insert into credit_packages(name, customer_price, paid_credit_amount, bonus_enabled, bonus_value, allow_product, allow_therapy, grants_reward)
    values ('T448 S$100 + S$10', 100, 100, true, 10, true, true, false) returning id into cpb;
  insert into credit_package_stores(package_id, store_id) values (cpb, st);
  insert into premium_bundles(name, customer_payment_amount, paid_credit_amount, bonus_credit_amount, free_voucher_qty, grants_reward)
    values ('T448 Bundle S$100 + S$20', 100, 100, 20, 0, false) returning id into pbb;
  insert into premium_bundle_stores(bundle_id, store_id) values (pbb, st);
  -- And one of S$140: S$100 Paid, S$40 Bonus and two S$30 vouchers.
  insert into premium_bundles(name, customer_payment_amount, paid_credit_amount, bonus_credit_amount, free_voucher_qty, grants_reward)
    values ('T448 Bundle S$140 + 2 vouchers', 140, 100, 40, 2, true) returning id into pbv;
  insert into premium_bundle_stores(bundle_id, store_id) values (pbv, st);
  insert into premium_bundle_vouchers(bundle_id, voucher_id) values (pbv, v);
  -- A S$30 therapy session.
  insert into therapy_services(service_code, name, standard_price, duration_minutes, is_active)
    values ('T448S30', 'T448 Session', 30, 30, true) returning id into ts;
  insert into therapy_service_stores(service_id, store_id) values (ts, st);
  insert into t448 values ('own', own), ('store', st), ('buyer', c), ('friend', c2), ('kept', mk), ('dup', md), ('dup2', md2), ('pm', pm),
                          ('v', v), ('vl', vl), ('cp', cp), ('cpb', cpb), ('pbb', pbb), ('pbv', pbv), ('session', ts);
end $$;

-- ── The app's calls ─────────────────────────────────────────────────────────
-- The invoice form with the lines given (p_kinds: 'v' / 'vl' a voucher line,
-- 'cp' / 'cpb' a Credit Package, 'pbb' a Premium Bundle, 'session' a
-- session line; p_qtys: each line's quantity), paid through the Pay dialog
-- (p_pay; all of it by default), for p_cust ('buyer' by default).
create function pg_temp.t448_sale(p_kinds text[], p_qtys int[] default null, p_pay numeric default null,
                                  p_cust text default 'buyer') returns uuid language plpgsql as $f$
declare inv uuid; v_lines jsonb := '[]'; i int;
begin
  for i in 1 .. cardinality(p_kinds) loop
    v_lines := v_lines || jsonb_build_array(case
      when p_kinds[i] in ('v', 'vl') then jsonb_build_object('kind', 'voucher', 'voucher_id', pg_temp.t448_id(p_kinds[i]),
                                                            'quantity', coalesce(p_qtys[i], 1))
      when p_kinds[i] in ('cp', 'cpb') then jsonb_build_object('kind', 'credit_package', 'credit_package_id', pg_temp.t448_id(p_kinds[i]), 'quantity', 1)
      when p_kinds[i] = 'pbb' then jsonb_build_object('kind', 'premium_bundle', 'premium_bundle_id', pg_temp.t448_id('pbb'), 'quantity', 1)
      when p_kinds[i] = 'pbv' then jsonb_build_object('kind', 'premium_bundle', 'premium_bundle_id', pg_temp.t448_id('pbv'), 'quantity', 1,
        'voucher_selection', jsonb_build_array(jsonb_build_object('voucher_id', pg_temp.t448_id('v'), 'quantity', 2)))
      else jsonb_build_object('kind', 'therapy', 'therapy_service_id', pg_temp.t448_id('session'), 'quantity', coalesce(p_qtys[i], 1)) end);
  end loop;
  inv := create_invoice_with_details(pg_temp.t448_id('store'), pg_temp.t448_id(p_cust), v_lines,
    jsonb_build_object('business_date', sg_today()::text));
  perform record_invoice_settlement(inv, jsonb_build_object('receipts', jsonb_build_array(jsonb_build_object(
    'key', 'line-0', 'payment_method_id', pg_temp.t448_id('pm'), 'amount', coalesce(p_pay, (select total_amount from invoices where id = inv)),
    'payment_date', sg_today()::text)), 'arrangements', '[]'::jsonb), gen_random_uuid());
  return inv;
end $f$;
-- Record Payment: what is outstanding, or p_amount.
create function pg_temp.t448_pay(p_inv uuid, p_amount numeric default null) returns void language plpgsql as $f$
begin
  perform record_invoice_payment(p_inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.t448_id('pm'),
    'amount', coalesce(p_amount, (invoice_financial_position(p_inv)->>'outstanding')::numeric))), gen_random_uuid());
end $f$;
-- The receipts that still hold p_amount between them, as the Finance panel
-- splits a refund across them.
create function pg_temp.t448_sources(p_inv uuid, p_amount numeric) returns jsonb language plpgsql as $f$
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
-- "Record refund paid": one line with no item. 'recorded', or the refusal.
create function pg_temp.t448_record_refund(p_inv uuid, p_amount numeric) returns text language plpgsql as $f$
begin
  perform refund_invoice_recorded(p_inv, jsonb_build_array(jsonb_build_object('invoice_item_id', null, 'amount', p_amount)),
    pg_temp.t448_sources(p_inv, p_amount), '[]'::jsonb, 'T448 paid back', gen_random_uuid());
  return 'recorded';
exception when others then return sqlerrm;
end $f$;
-- The guided Refund / Cancel as an Owner confirms it (InvoiceGuidedAction):
-- the plan, the request, the approval with a reason for every override the
-- plan asks for and, when p_owed is given, 417's amount owed back; the money
-- recorded as paid back when p_record. Returns the codes the plan asked for
-- ('-' for none), or 'ERR ' and the refusal.
create function pg_temp.t448_guided(p_inv uuid, p_action text, p_owed numeric default null,
                                    p_lines jsonb default '[]', p_record boolean default false) returns text language plpgsql as $f$
declare plan jsonb; req jsonb; ov jsonb;
begin
  plan := invoice_action_plan(p_inv, p_action, p_lines);
  req := request_invoice_action_v2(p_inv, p_action, p_lines, 'T448 ' || p_action, null, gen_random_uuid());
  select coalesce(jsonb_agg(case when coalesce((o->>'amount_required')::boolean, false)
           then jsonb_build_object('code', o->>'code', 'reason', 'T448 override', 'amount', (o->>'default_amount')::numeric)
           else jsonb_build_object('code', o->>'code', 'reason', 'T448 override') end), '[]'::jsonb)
    into ov from jsonb_array_elements(coalesce(plan->'overrides_required', '[]')) o;
  if p_owed is not null then
    ov := ov || jsonb_build_array(jsonb_build_object('code', 'refund_owed', 'amount', p_owed, 'reason', 'T448 owed')); end if;
  perform resolve_invoice_action_v2((req->>'request_id')::uuid, true, 'T448 ' || p_action, plan->>'plan_hash', ov, null, p_record);
  return (select coalesce(string_agg(o->>'code', ',' order by o->>'code'), '-')
            from jsonb_array_elements(coalesce(plan->'overrides_required', '[]')) o);
exception when others then return 'ERR ' || sqlerrm;
end $f$;
-- The invoice's n-th line (by id; the invoices with two lines here have two
-- of a kind), or its line of one kind.
create function pg_temp.t448_line(p_inv uuid, p_n int) returns uuid language sql as $f$
  select id from invoice_items where invoice_id = p_inv order by id offset p_n - 1 limit 1 $f$;
create function pg_temp.t448_line_n(p_inv uuid, p_kind text) returns int language sql as $f$
  select n::int from (select id, line_kind, row_number() over (order by id) n from invoice_items where invoice_id = p_inv) x
   where x.line_kind::text = p_kind limit 1 $f$;
-- The guided "Refund some items": p_qty units of the invoice's n-th line,
-- recorded as paid back.
create function pg_temp.t448_refund_some(p_inv uuid, p_n int, p_qty int default 1) returns void language plpgsql as $f$
declare r text;
begin
  r := pg_temp.t448_guided(p_inv, 'refund_partial', null,
    jsonb_build_array(jsonb_build_object('invoice_item_id', pg_temp.t448_line(p_inv, p_n), 'quantity', p_qty)), true);
  if r like 'ERR %' then raise exception 'Fixture: the guided refund of line % of % failed: %', p_n, p_inv, r; end if;
end $f$;
-- The Finance panel's line-by-line refund of one line (a credit line, or a
-- voucher line on a cancelled invoice, where the guided refund is not
-- offered): each of the line's unused benefits at what it can still refund,
-- or p_amount off its Paid benefit, or (p_kind) only the benefits of that
-- kind. 'recorded', or the refusal.
create function pg_temp.t448_cline_back(p_inv uuid, p_n int, p_amount numeric default null, p_kind text default null)
  returns text language plpgsql as $f$
declare opts jsonb; ben jsonb; tot numeric; item uuid := pg_temp.t448_line(p_inv, p_n);
begin
  opts := invoice_refund_options_before_sessions(p_inv);
  if p_amount is null then
    select jsonb_agg(jsonb_build_object('benefit_id', b->>'id', 'amount', (b->>'max_refund')::numeric)), sum((b->>'max_refund')::numeric)
      into ben, tot from jsonb_array_elements(opts->'benefits') b
     where b->>'invoice_item_id' = item::text and (b->>'max_refund')::numeric > 0
       and (p_kind is null or b->>'benefit_kind' = p_kind);
  else
    select jsonb_build_array(jsonb_build_object('benefit_id', b->>'id', 'amount', p_amount)), p_amount
      into ben, tot from jsonb_array_elements(opts->'benefits') b
     where b->>'invoice_item_id' = item::text and b->>'benefit_kind' = 'paid'
     order by (b->>'paid_value')::numeric desc limit 1;
  end if;
  perform refund_invoice_recorded(p_inv, jsonb_build_array(jsonb_build_object('invoice_item_id', item, 'amount', tot, 'benefits', ben)),
    pg_temp.t448_sources(p_inv, tot), '[]'::jsonb, 'T448 credit paid back', gen_random_uuid());
  return 'recorded';
exception when others then return sqlerrm;
end $f$;
-- The Finance panel's line-by-line refund of what a cancelled invoice still
-- owes (it goes by line for credit and sold vouchers): the cancel plan's
-- lines and their benefits. 'recorded', or the refusal.
create function pg_temp.t448_by_line(p_inv uuid) returns text language plpgsql as $f$
declare plan jsonb; v_lines jsonb; tot numeric;
begin
  plan := invoice_action_plan(p_inv, 'cancel', '[]');
  select jsonb_agg(jsonb_build_object('invoice_item_id', l->>'invoice_item_id', 'amount', (l->>'amount')::numeric,
           'benefits', (select coalesce(jsonb_agg(jsonb_build_object('benefit_id', x->>'benefit_id', 'amount', (x->>'amount')::numeric)), '[]'::jsonb)
                          from jsonb_array_elements(l->'benefits') x))),
         sum((l->>'amount')::numeric)
    into v_lines, tot from jsonb_array_elements(plan->'lines') l where (l->>'amount')::numeric > 0;
  if v_lines is null then return 'nothing to allocate: the cancel plan''s lines are S$0'; end if;
  perform refund_invoice_recorded(p_inv, v_lines, pg_temp.t448_sources(p_inv, tot), '[]'::jsonb, 'T448 by line', gen_random_uuid());
  return 'recorded';
exception when others then return sqlerrm;
end $f$;
-- Sold, paid, cancelled, p_back recorded as paid back (vouchers: "Record
-- refund paid"; credit: line p_back_line by line), reopened.
create function pg_temp.t448_reopened(p_inv uuid) returns void language plpgsql as $f$
begin perform reopen_invoice(p_inv, 'T448 reopen', gen_random_uuid()); end $f$;
-- Redeemed: the voucher a line's benefit holds (all of it), or one unit of it.
create function pg_temp.t448_redeem(p_inv uuid, p_n int, p_one boolean default false) returns void language plpgsql as $f$
begin
  if p_one then
    update customer_reward_vouchers set quantity = quantity - 1
     where id in (select b.reward_voucher_id from invoice_benefit_values b
                   where b.invoice_item_id = pg_temp.t448_line(p_inv, p_n)) and status = 'held' and quantity > 1;
  else
    update customer_reward_vouchers set status = 'redeemed', redeemed_at = now()
     where id in (select b.reward_voucher_id from invoice_benefit_values b
                   where b.invoice_item_id = pg_temp.t448_line(p_inv, p_n)) and status = 'held';
  end if;
  if not found then raise exception 'Fixture: no held voucher to redeem on line % of %', p_n, p_inv; end if;
end $f$;
-- Credit spent: p_amount off the lot of the n-th line's Paid benefit.
create function pg_temp.t448_spend(p_inv uuid, p_n int, p_amount numeric) returns void language plpgsql as $f$
begin
  update customer_credit_lots set remaining_amount = remaining_amount - p_amount
   where id = (select b.lot_id from invoice_benefit_values b join customer_credit_lots l on l.id = b.lot_id
                where b.invoice_item_id = pg_temp.t448_line(p_inv, p_n) and l.category = 'paid' and l.remaining_amount >= p_amount
                order by b.granted_value desc limit 1);
  if not found then raise exception 'Fixture: no Paid lot to spend S$% from on line % of %', p_amount, p_n, p_inv; end if;
end $f$;
-- The customer changed with the benefits taken along (the invoice form).
create function pg_temp.t448_change(p_inv uuid, p_cust text) returns jsonb language plpgsql as $f$
declare x jsonb;
begin
  select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('invoice_item_id', it.id, 'kind', it.line_kind,
           'credit_package_id', it.credit_package_id, 'premium_bundle_id', it.premium_bundle_id, 'voucher_id', it.voucher_id,
           'quantity', it.quantity, 'unit_price', it.unit_price, 'voucher_selection', it.bundle_voucher_selection)) order by it.id)
    into x from invoice_items it where it.invoice_id = p_inv;
  return correct_invoice(p_inv, x, jsonb_build_object('expected_edit_count', (select edit_count from invoices where id = p_inv),
    'customer_id', pg_temp.t448_id(p_cust), 'store_id', pg_temp.t448_id('store'), 'benefit_action', 'transfer'), 'T448 wrong customer', gen_random_uuid());
end $f$;
-- Move: the n-th line's held voucher, or its credit benefit (p_kind), to the friend.
create function pg_temp.t448_move(p_inv uuid, p_n int, p_kind text default null) returns void language plpgsql as $f$
begin
  perform transfer_invoice_unused_benefit((select b.id from invoice_benefit_values b
      left join customer_reward_vouchers v on v.id = b.reward_voucher_id
      left join customer_credit_lots l on l.id = b.lot_id
     where b.invoice_item_id = pg_temp.t448_line(p_inv, p_n)
       and (v.status = 'held' or l.remaining_amount > 0) and (p_kind is null or l.category = p_kind)
     order by b.granted_value desc limit 1),
    pg_temp.t448_id('friend'), pg_temp.t448_id('store'), 'T448 move', gen_random_uuid());
end $f$;
-- A completed FOC of p_qty limited vouchers, the FOC taken off at S$30 each
-- (416), paid.
create function pg_temp.t448_foc_off_paid(p_qty int) returns uuid language plpgsql as $f$
declare inv uuid; x jsonb;
begin
  inv := create_invoice(pg_temp.t448_id('store'), pg_temp.t448_id('buyer'), null, jsonb_build_array(jsonb_build_object(
    'kind', 'voucher', 'voucher_id', pg_temp.t448_id('vl'), 'quantity', p_qty, 'foc_quantity', p_qty, 'foc_reason', 'T448 goodwill')));
  perform confirm_foc_invoice(inv, 'T448 FOC');
  select jsonb_agg(jsonb_build_object('invoice_item_id', it.id, 'kind', 'voucher', 'voucher_id', it.voucher_id,
           'quantity', p_qty, 'unit_price', 30, 'foc_quantity', 0)) into x
    from invoice_items it where it.invoice_id = inv;
  perform correct_invoice(inv, x, jsonb_build_object('expected_edit_count', (select edit_count from invoices where id = inv)),
    'T448 FOC off', gen_random_uuid());
  perform pg_temp.t448_pay(inv, 30 * p_qty);
  return inv;
end $f$;
-- What the screens read.
create function pg_temp.t448_codes(p_inv uuid, p_action text) returns text language sql as $f$
  select coalesce(string_agg(o->>'code', ',' order by o->>'code'), '-')
    from jsonb_array_elements(coalesce(invoice_action_plan(p_inv, p_action, '[]')->'overrides_required', '[]')) o $f$;
create function pg_temp.t448_used(p_inv uuid) returns text language sql as $f$
  select coalesce(nullif(array_to_string(cancelled_invoice_used_value(p_inv), ','), ''), '-') $f$;
create function pg_temp.t448_reads(p_inv uuid) returns jsonb language sql as $f$
  select jsonb_build_object('status', i.status, 'used', to_jsonb(cancelled_invoice_used_value(p_inv)),
           'cancel', invoice_action_plan(p_inv, 'cancel', '[]'),
           'refund_full', case when i.status in ('paid', 'partially_paid') then invoice_action_plan(p_inv, 'refund_full', '[]') end)
    from invoices i where i.id = p_inv $f$;
-- The codes a reads snapshot holds: 'cancel codes / Refund in full codes /
-- used', each '-' for none ('x' for a plan not read).
create function pg_temp.t448_sum(p_reads jsonb) returns text language sql as $f$
  select coalesce((select string_agg(o->>'code', ',' order by o->>'code') from jsonb_array_elements(p_reads->'cancel'->'overrides_required') o), '-')
      || ' / ' || case when p_reads->'refund_full' = 'null'::jsonb then 'x'
                       else coalesce((select string_agg(o->>'code', ',' order by o->>'code') from jsonb_array_elements(p_reads->'refund_full'->'overrides_required') o), '-') end
      || ' / ' || coalesce(nullif((select string_agg(u #>> '{}', ',' order by u #>> '{}') from jsonb_array_elements(p_reads->'used') u), ''), '-') $f$;
-- A plan's money, without what 448 changes (the overrides, the amount owed
-- question, the summary that names them, the hash).
create function pg_temp.t448_money(p_plan jsonb) returns jsonb language sql as $f$
  select case when p_plan is null or p_plan = 'null'::jsonb then null else
    (p_plan - 'overrides_required' - 'refund_owed' - 'requires_override' - 'plan_hash' - 'summary')
    || jsonb_build_object('effects', (p_plan->'effects') - 'overrides',
         'lines', (select coalesce(jsonb_agg(l - 'override_codes' order by n), '[]'::jsonb)
                     from jsonb_array_elements(p_plan->'lines') with ordinality x(l, n))) end $f$;
-- Units of the invoice's vouchers held (by anyone).
create function pg_temp.t448_held(p_inv uuid) returns int language sql as $f$
  select coalesce(sum(v.quantity), 0)::int from invoice_benefit_values b join customer_reward_vouchers v on v.id = b.reward_voucher_id
   where b.invoice_id = p_inv and v.status = 'held' $f$;
create function pg_temp.t448_credit(p_inv uuid) returns numeric language sql as $f$
  select round(coalesce(sum(l.remaining_amount), 0), 2) from invoice_benefit_values b join customer_credit_lots l on l.id = b.lot_id
   where b.invoice_id = p_inv $f$;
create function pg_temp.t448_stock() returns int language sql as $f$
  select current_qty from voucher_store_stock where voucher_id = pg_temp.t448_id('vl') and store_id = pg_temp.t448_id('store') $f$;
create function pg_temp.t448_money_of(p_inv uuid) returns text language sql as $f$
  select status::text || ' net ' || invoice_net_received(id) || ' due ' || (invoice_financial_position(id)->>'refund_due')
         || ' held ' || pg_temp.t448_held(id) || ' credit ' || pg_temp.t448_credit(id)
    from invoices where id = p_inv $f$;

-- ===== A. The cases and the controls, built before 448 =====
do $$
declare inv uuid; s0 int;
begin
  -- Vouchers.
  inv := pg_temp.t448_sale(array['v'], array[2]);                      -- VA: one unit of two refunded
  perform pg_temp.t448_refund_some(inv, 1);
  insert into t448 values ('VA', inv);
  inv := pg_temp.t448_sale(array['v'], array[2]);                      -- VB: the same, cancelled
  perform pg_temp.t448_refund_some(inv, 1);
  perform cancel_invoice_recorded(inv, 'T448 VB', gen_random_uuid());
  insert into t448 values ('VB', inv);
  inv := pg_temp.t448_sale(array['v', 'v']);                           -- VC: line A refunded
  perform pg_temp.t448_refund_some(inv, 1);
  insert into t448 values ('VC', inv);
  inv := pg_temp.t448_sale(array['v'], array[2]);                      -- VD: one refunded, the other redeemed
  perform pg_temp.t448_refund_some(inv, 1);
  perform pg_temp.t448_redeem(inv, 1);
  insert into t448 values ('VD', inv);
  inv := pg_temp.t448_sale(array['v'], array[3]);                      -- VE: one refunded, one redeemed, one held
  perform pg_temp.t448_refund_some(inv, 1);
  perform pg_temp.t448_redeem(inv, 1, true);
  insert into t448 values ('VE', inv);
  inv := pg_temp.t448_sale(array['vl', 'vl']);                         -- VF: line A refunded, cancelled, reopened: waiting
  perform pg_temp.t448_refund_some(inv, 1);
  perform cancel_invoice_recorded(inv, 'T448 VF', gen_random_uuid());
  perform pg_temp.t448_reopened(inv);
  insert into t448 values ('VF', inv);
  inv := pg_temp.t448_sale(array['v'], array[2]);                      -- VG: one of two refunded, cancelled, reopened: waiting
  perform pg_temp.t448_refund_some(inv, 1);
  perform cancel_invoice_recorded(inv, 'T448 VG', gen_random_uuid());
  perform pg_temp.t448_reopened(inv);
  insert into t448 values ('VG', inv);
  inv := pg_temp.t448_sale(array['v', 'v']);                           -- VH: line A refunded while waiting (446), settled
  perform cancel_invoice_recorded(inv, 'T448 VH', gen_random_uuid());
  perform pg_temp.t448_check(pg_temp.t448_record_refund(inv, 30) = 'recorded', 'fixture VH: S$30 paid back');
  perform pg_temp.t448_reopened(inv);
  perform pg_temp.t448_refund_some(inv, 1);
  perform pg_temp.t448_pay(inv);
  insert into t448 values ('VH', inv);
  inv := pg_temp.t448_sale(array['v'], array[2]);                      -- VI: one refunded, the other moved
  perform pg_temp.t448_refund_some(inv, 1);
  perform pg_temp.t448_move(inv, 1);
  insert into t448 values ('VI', inv);
  inv := pg_temp.t448_sale(array['v'], array[2]);                      -- VI2: the same, the friend redeems it
  perform pg_temp.t448_refund_some(inv, 1);
  perform pg_temp.t448_move(inv, 1);
  update customer_reward_vouchers set status = 'redeemed', redeemed_at = now()
   where customer_id = pg_temp.t448_id('friend') and status = 'held' and source_type = 'invoice_benefit_transfer'
     and id in (select reward_voucher_id from invoice_benefit_values where invoice_id = inv);
  insert into t448 values ('VI2', inv);
  inv := pg_temp.t448_sale(array['v', 'v']);                           -- VJ: line A refunded, customer changed
  perform pg_temp.t448_refund_some(inv, 1);
  perform pg_temp.t448_change(inv, 'friend');
  insert into t448 values ('VJ', inv);
  inv := pg_temp.t448_foc_off_paid(2);                                 -- VK: FOC taken off, paid, one unit refunded
  perform pg_temp.t448_refund_some(inv, 1);
  insert into t448 values ('VK', inv);
  inv := pg_temp.t448_sale(array['session', 'v'], array[3, 2]);         -- VL: a session delivered; one voucher unit refunded
  update customer_therapy_sessions set quantity_used = 1 where invoice_id = inv and is_current;
  perform pg_temp.t448_refund_some(inv, pg_temp.t448_line_n(inv, 'voucher'));
  insert into t448 values ('VL', inv);
  -- Credit.
  inv := pg_temp.t448_sale(array['cpb', 'cpb']);                       -- CA: line A refunded
  perform pg_temp.t448_refund_some(inv, 1);
  insert into t448 values ('CA', inv);
  inv := pg_temp.t448_sale(array['cpb', 'cpb']);                       -- CB: the same, cancelled
  perform pg_temp.t448_refund_some(inv, 1);
  perform cancel_invoice_recorded(inv, 'T448 CB', gen_random_uuid());
  insert into t448 values ('CB', inv);
  inv := pg_temp.t448_sale(array['cp']);                               -- CC: S$40 refunded (the Finance panel)
  perform pg_temp.t448_check(pg_temp.t448_cline_back(inv, 1, 40) = 'recorded', 'fixture CC: S$40');
  insert into t448 values ('CC', inv);
  inv := pg_temp.t448_sale(array['cp']);                               -- CQ: the same; Refund in full requested now (4)
  perform pg_temp.t448_check(pg_temp.t448_cline_back(inv, 1, 40) = 'recorded', 'fixture CQ: S$40');
  insert into t448 values ('CQ', inv);
  insert into t448 values ('req CQ', (request_invoice_action_v2(inv, 'refund_full', '[]', 'T448 CQ raised before 448', null,
                                        gen_random_uuid())->>'request_id')::uuid);
  insert into t448_known values ('CQ raised with 448', pg_temp.t448_in()::text);
  inv := pg_temp.t448_sale(array['cpb', 'cpb']);                       -- CD: line A's Paid credit alone
  perform pg_temp.t448_check(pg_temp.t448_cline_back(inv, 1, null, 'paid') = 'recorded', 'fixture CD: Paid credit');
  insert into t448 values ('CD', inv);
  inv := pg_temp.t448_sale(array['pbb', 'pbb']);                       -- CE: bundles, line A refunded
  perform pg_temp.t448_refund_some(inv, 1);
  insert into t448 values ('CE', inv);
  inv := pg_temp.t448_sale(array['pbv', 'pbv']);                       -- CV: bundles with vouchers, line A refunded
  perform pg_temp.t448_refund_some(inv, 1);
  insert into t448 values ('CV', inv);
  inv := pg_temp.t448_sale(array['cp']);                               -- CF: S$40 refunded, S$10 spent
  perform pg_temp.t448_check(pg_temp.t448_cline_back(inv, 1, 40) = 'recorded', 'fixture CF: S$40');
  perform pg_temp.t448_spend(inv, 1, 10);
  insert into t448 values ('CF', inv);
  inv := pg_temp.t448_sale(array['cpb', 'cpb']);                       -- CG: line A refunded, cancelled, reopened: waiting
  perform pg_temp.t448_refund_some(inv, 1);
  perform cancel_invoice_recorded(inv, 'T448 CG', gen_random_uuid());
  perform pg_temp.t448_reopened(inv);
  insert into t448 values ('CG', inv);
  inv := pg_temp.t448_sale(array['cp']);                               -- CH: S$40 refunded, cancelled, reopened: waiting
  perform pg_temp.t448_check(pg_temp.t448_cline_back(inv, 1, 40) = 'recorded', 'fixture CH: S$40');
  perform cancel_invoice_recorded(inv, 'T448 CH', gen_random_uuid());
  perform pg_temp.t448_reopened(inv);
  insert into t448 values ('CH', inv);
  inv := pg_temp.t448_sale(array['cpb', 'cpb']);                       -- CI: line A refunded while waiting (446), settled
  perform cancel_invoice_recorded(inv, 'T448 CI', gen_random_uuid());
  perform pg_temp.t448_check(pg_temp.t448_cline_back(inv, 2) = 'recorded', 'fixture CI: line B paid back');
  perform pg_temp.t448_reopened(inv);
  perform pg_temp.t448_refund_some(inv, 1);
  perform pg_temp.t448_pay(inv);
  insert into t448 values ('CI', inv);
  inv := pg_temp.t448_sale(array['cp']);                               -- CJ: S$40 refunded, the rest moved
  perform pg_temp.t448_check(pg_temp.t448_cline_back(inv, 1, 40) = 'recorded', 'fixture CJ: S$40');
  perform pg_temp.t448_move(inv, 1);
  insert into t448 values ('CJ', inv);
  inv := pg_temp.t448_sale(array['cp']);                               -- CJ2: the same, the friend spends S$10
  perform pg_temp.t448_check(pg_temp.t448_cline_back(inv, 1, 40) = 'recorded', 'fixture CJ2: S$40');
  perform pg_temp.t448_move(inv, 1);
  update customer_credit_lots set remaining_amount = remaining_amount - 10
   where customer_id = pg_temp.t448_id('friend') and source_type = 'invoice_benefit_transfer'
     and id in (select lot_id from invoice_benefit_values where invoice_id = inv);
  insert into t448 values ('CJ2', inv);
  inv := pg_temp.t448_sale(array['cpb', 'cpb']);                       -- CK: line A refunded, customer changed
  perform pg_temp.t448_refund_some(inv, 1);
  perform pg_temp.t448_change(inv, 'friend');
  insert into t448 values ('CK', inv);
  inv := pg_temp.t448_sale(array['cp'], null, null, 'dup');            -- CL: S$40 refunded, the duplicate merged away
  perform pg_temp.t448_check(pg_temp.t448_cline_back(inv, 1, 40) = 'recorded', 'fixture CL: S$40');
  perform merge_customer_records(pg_temp.t448_id('kept'), pg_temp.t448_id('dup'), 'T448 the same person', gen_random_uuid());
  insert into t448 values ('CL', inv);
  inv := pg_temp.t448_sale(array['cpb', 'cpb'], null, 120);            -- CM: part-paid (released credit), settled, line A refunded
  perform pg_temp.t448_pay(inv);
  perform pg_temp.t448_refund_some(inv, 1);
  insert into t448 values ('CM', inv);
  -- Controls.
  insert into t448 values ('K1', pg_temp.t448_sale(array['v']));      -- a paid sale
  inv := pg_temp.t448_sale(array['v', 'v']);                           -- one of two redeemed
  perform pg_temp.t448_redeem(inv, 1);
  insert into t448 values ('K2', inv);
  inv := pg_temp.t448_sale(array['v']);                                -- cancelled, unused
  perform cancel_invoice_recorded(inv, 'T448 K3', gen_random_uuid());
  insert into t448 values ('K3', inv);
  inv := pg_temp.t448_sale(array['v']);                                -- redeemed, then cancelled
  perform pg_temp.t448_redeem(inv, 1);
  perform cancel_invoice_recorded(inv, 'T448 K4', gen_random_uuid());
  insert into t448 values ('K4', inv);
  inv := pg_temp.t448_sale(array['cpb']);                              -- S$25 spent
  perform pg_temp.t448_spend(inv, 1, 25);
  insert into t448 values ('K5', inv);
  inv := pg_temp.t448_sale(array['cpb']);                              -- S$25 spent, then cancelled
  perform pg_temp.t448_spend(inv, 1, 25);
  perform cancel_invoice_recorded(inv, 'T448 K6', gen_random_uuid());
  insert into t448 values ('K6', inv);
  inv := pg_temp.t448_sale(array['v', 'vl']);                          -- cancelled, reopened (paid), settled (438)
  perform cancel_invoice_recorded(inv, 'T448 K7', gen_random_uuid());
  perform pg_temp.t448_reopened(inv);
  insert into t448 values ('K7', inv);
  inv := pg_temp.t448_sale(array['v']);                                -- a voucher moved (438)
  perform pg_temp.t448_move(inv, 1);
  insert into t448 values ('K8', inv);
  inv := pg_temp.t448_sale(array['cp']);                               -- credit moved (438)
  perform pg_temp.t448_move(inv, 1);
  insert into t448 values ('K9', inv);
  inv := pg_temp.t448_sale(array['session'], array[3]);                -- a session delivered
  update customer_therapy_sessions set quantity_used = 1 where invoice_id = inv and is_current;
  insert into t448 values ('K10', inv);
  inv := pg_temp.t448_sale(array['cpb']);                              -- credit taken along by a customer change (447)
  perform pg_temp.t448_change(inv, 'friend');
  insert into t448 values ('K11', inv);
  inv := pg_temp.t448_sale(array['cpb', 'cpb'], null, 120);            -- part-paid, released credit spent, not settled
  update customer_credit_lots set remaining_amount = remaining_amount - 10
   where id in (select public.credit_lot_current(pl.lot_id) from credit_package_progress_lots pl
                 where pl.invoice_id = inv and pl.released_amount > 0 order by pl.lot_id limit 1);
  insert into t448 values ('K12', inv);
  insert into t448 values ('K13', pg_temp.t448_foc_off_paid(1));      -- the FOC taken off and paid (438)
  inv := pg_temp.t448_sale(array['cpb', 'cpb']);                       -- credit cancelled, reopened straight to paid
  perform cancel_invoice_recorded(inv, 'T448 K14', gen_random_uuid());
  perform pg_temp.t448_reopened(inv);
  insert into t448 values ('K14', inv);
  inv := pg_temp.t448_sale(array['v'], array[2]);                      -- cancelled, reopened (paid), one unit redeemed
  perform cancel_invoice_recorded(inv, 'T448 K15', gen_random_uuid());
  perform pg_temp.t448_reopened(inv);
  perform pg_temp.t448_redeem(inv, 1, true);
  insert into t448 values ('K15', inv);
end $$;

-- The states the cases were built into.
do $$
begin
  perform pg_temp.t448_check((select string_agg(k || ' ' || (select status::text from invoices where id = t448.id), ', ' order by k)
                                from t448 where k in ('VF', 'VG', 'CG', 'CH'))
    = 'CG partially_paid, CH partially_paid, VF partially_paid, VG partially_paid', 'A the reopened cases are not waiting part-paid');
  perform pg_temp.t448_check((select sum(quantity) from invoice_reopen_vouchers where invoice_id = pg_temp.t448_id('VF') and applied_at is null) = 2
    and (select sum(quantity) from invoice_reopen_vouchers where invoice_id = pg_temp.t448_id('VG') and applied_at is null) = 2
    and (select sum(amount) from invoice_reopen_benefits where invoice_id = pg_temp.t448_id('CG') and applied_at is null) = 220
    and (select sum(amount) from invoice_reopen_benefits where invoice_id = pg_temp.t448_id('CH') and applied_at is null) = 100,
    'A the reopened cases do not wait with every unit and all the credit');
  perform pg_temp.t448_check((select status::text from invoices where id = pg_temp.t448_id('VH')) = 'paid'
    and (select status::text from invoices where id = pg_temp.t448_id('CI')) = 'paid'
    and pg_temp.t448_held(pg_temp.t448_id('VH')) = 1 and pg_temp.t448_credit(pg_temp.t448_id('CI')) = 110,
    'A 446''s cases (refunded while waiting) are not settled as 446 leaves them');
  perform pg_temp.t448_check((select customer_id from invoices where id = pg_temp.t448_id('CK')) = pg_temp.t448_id('friend')
    and (select customer_id from invoices where id = pg_temp.t448_id('VJ')) = pg_temp.t448_id('friend')
    and (select customer_id from invoices where id = pg_temp.t448_id('CL')) = pg_temp.t448_id('kept')
    and exists (select 1 from invoice_benefit_values b join customer_credit_lots l on l.id = b.lot_id
                 where b.invoice_id = pg_temp.t448_id('CL') and l.customer_id = pg_temp.t448_id('kept') and l.reassigned_from_lot_id is not null),
    'A the customer change or the merge did not happen as tested');
  perform pg_temp.t448_check(exists (select 1 from credit_package_progress_lots where invoice_id = pg_temp.t448_id('CM') and released_amount > 0)
    and (select status::text from invoices where id = pg_temp.t448_id('CM')) = 'paid', 'A CM is not a settled part-paid package');
  raise notice 'PASS A: the cases and controls are built as described (waiting, settled, changed, merged, moved)';
end $$;

-- ===== R. Before 448: the false prompts =====
do $$
declare r record; bad text;
begin
  if pg_temp.t448_in() then
    raise notice 'NOTE R: 448 was in before this suite started, so the false prompts are not reproduced here; every figure after 448 is still checked';
    return;
  end if;
  insert into t448_before(k, reads) select k, pg_temp.t448_reads(id) from t448 where k ~ '^[VCK]' and id is not null
    and k not in ('own', 'store', 'buyer', 'friend', 'kept', 'dup', 'pm', 'v', 'vl', 'cp', 'cpb', 'pbb', 'session');
  -- 'cancel codes / Refund in full codes / used' before 448.
  for r in select * from (values
      ('VA', 'voucher_redeemed / voucher_redeemed / voucher_redeemed'),
      ('VB', 'voucher_redeemed / x / voucher_redeemed'),
      ('VC', 'voucher_redeemed / - / voucher_redeemed'),
      ('VD', 'voucher_redeemed / voucher_redeemed / voucher_redeemed'),
      ('VE', 'voucher_redeemed / voucher_redeemed / voucher_redeemed'),
      ('VF', 'voucher_redeemed / voucher_redeemed / voucher_redeemed'),
      ('VG', 'voucher_redeemed / voucher_redeemed / voucher_redeemed'),
      ('VH', 'voucher_redeemed / - / voucher_redeemed'),
      ('VI', 'voucher_redeemed / voucher_redeemed / voucher_redeemed'),
      ('VI2', 'voucher_redeemed,voucher_redeemed / voucher_redeemed,voucher_redeemed / voucher_redeemed'),
      ('VJ', 'voucher_redeemed / - / voucher_redeemed'),
      ('VK', 'voucher_redeemed / voucher_redeemed / voucher_redeemed'),
      ('VL', 'session_used,voucher_redeemed / session_used,voucher_redeemed / session_used,voucher_redeemed'),
      ('CA', 'credit_used,credit_used / - / credit_used'),
      ('CB', 'credit_used,credit_used / x / credit_used'),
      ('CC', 'credit_used / credit_used / credit_used'),
      ('CQ', 'credit_used / credit_used / credit_used'),
      ('CD', 'credit_used / credit_used / credit_used'),
      ('CE', 'credit_used,credit_used / - / credit_used'),
      ('CV', 'credit_used,credit_used,voucher_redeemed / - / credit_used,voucher_redeemed'),
      ('CF', 'credit_used / credit_used / credit_used'),
      ('CG', 'credit_used,credit_used / credit_used,credit_used / credit_used'),
      ('CH', 'credit_used / credit_used / credit_used'),
      ('CI', 'credit_used,credit_used / - / credit_used'),
      ('CJ', 'credit_used / credit_used / credit_used'),
      ('CJ2', 'credit_used,credit_used / credit_used,credit_used / credit_used'),
      ('CK', 'credit_used,credit_used / - / credit_used'),
      ('CL', 'credit_used / credit_used / credit_used'),
      ('CM', 'credit_used,credit_used / - / credit_used')) x(k, want)
  loop
    if pg_temp.t448_sum((select reads from t448_before where k = r.k)) is distinct from r.want then
      bad := coalesce(bad || '; ', '') || r.k || ' reads ' || pg_temp.t448_sum((select reads from t448_before where k = r.k)) || ', not ' || r.want;
    end if;
  end loop;
  if bad is not null then raise exception 'FAIL R before 448: %', bad; end if;
  -- The consequences, through the app: the guided Cancel asks the amount owed;
  -- cancelled directly, "Record refund paid" is refused.
  perform pg_temp.t448_check((select reads->'cancel'->'refund_owed'->>'needed' from t448_before where k = 'VA') = 'true'
    and (select reads->'cancel'->'refund_owed'->>'needed' from t448_before where k = 'CA') = 'true',
    'R the guided Cancel did not ask "State how much is owed back"');
  perform pg_temp.t448_check(pg_temp.t448_record_refund(pg_temp.t448_id('VB'), 30) like 'Part of what % sold has been used (vouchers redeemed)%',
    'R VB "Record refund paid" was not refused');
  raise notice 'PASS R: before 448, a voucher unit or credit paid back by a line refund reads as redeemed or spent in each case (Cancel, Refund in full, "used"); the guided Cancel asks "State how much is owed back"; cancelled directly, "Record refund paid" is refused as vouchers redeemed';
end $$;

-- ===== Q. 448's read-only query, before 448 (the same text as its header) =====
insert into t448_q(invoice_id)
select i.id from (
with recursive b as (
  select bv.id, bv.invoice_id, bv.lot_id, bv.reward_voucher_id, bv.granted_value, bv.cancelled_unused_value,
         case when bv.reward_voucher_id is not null
              then coalesce((select case when v.status = 'held' then v.quantity else 0 end
                               from public.customer_reward_vouchers v where v.id = bv.reward_voucher_id), 0)
              else coalesce((select l.remaining_amount from public.customer_credit_lots l where l.id = bv.lot_id), 0) end
         + bv.cancelled_unused_value
         + coalesce((select sum(t.transferred_value) from public.invoice_benefit_transfers t
                      where t.source_benefit_id = bv.id and t.replacement_benefit_id is not null), 0)
         + coalesce((select sum(q.quantity) from public.invoice_reopen_vouchers q
                      where q.benefit_id = bv.id and q.applied_at is not null), 0) as unused_now
    from public.invoice_benefit_values bv
), chain(benefit_id, lot_id, n) as (
  select b.id, b.lot_id, 0 from b where b.lot_id is not null
  union all
  select c.benefit_id, l.reassigned_from_lot_id, c.n + 1
    from chain c join public.customer_credit_lots l on l.id = c.lot_id
   where l.reassigned_from_lot_id is not null and c.n < 12
), x as (
  select b.*, case
    when b.reward_voucher_id is not null then
      greatest(coalesce((select c.quantity from public.invoice_voucher_reopen_candidates(b.invoice_id) c
                          where c.benefit_id = b.id), 0) - b.cancelled_unused_value, 0)
    + greatest(coalesce((select sum(q.quantity) from public.invoice_reopen_vouchers q
                          where q.benefit_id = b.id and q.applied_at is null), 0) - b.cancelled_unused_value, 0)
    when b.lot_id is not null then
      greatest(coalesce((select sum(e.amount) from public.customer_credit_ledger e
                          where e.lot_id in (select c.lot_id from chain c where c.benefit_id = b.id)
                            and (e.source_type = 'invoice_cancel_benefit' and e.source_record_id = b.invoice_id
                                 or e.source_type = 'invoice_benefit_refund'
                                    and exists (select 1 from public.invoice_refunds r
                                                 where r.invoice_id = b.invoice_id and r.request_id = e.source_record_id))
                            and not exists (select 1 from public.invoice_reopen_benefits q where q.source_ledger_id = e.id)), 0)
             + coalesce((select sum(q.amount) from public.invoice_reopen_benefits q
                           join public.customer_credit_ledger e on e.id = q.source_ledger_id
                          where q.invoice_id = b.invoice_id and q.applied_at is null
                            and e.lot_id in (select c.lot_id from chain c where c.benefit_id = b.id)), 0)
             - b.cancelled_unused_value, 0)
    else 0 end as refunded
    from b
)
select i.invoice_no, i.status::text as status,
       count(*) filter (where x.unused_now < x.granted_value and x.unused_now + x.refunded >= x.granted_value) as rows_no_longer_used,
       count(*) filter (where x.unused_now + x.refunded < x.granted_value) as rows_still_used,
       i.cancel_refund_owed is not null as owed_stated,
       (select count(*) from public.approval_requests r
         where r.related_record_id = i.id and r.status = 'pending'
           and r.request_type in ('invoice_cancel', 'invoice_refund')) as pending_requests
  from x join public.invoices i on i.id = x.invoice_id
 group by i.id, i.invoice_no, i.status, i.cancel_refund_owed
having count(*) filter (where x.unused_now < x.granted_value and x.unused_now + x.refunded >= x.granted_value) > 0
 order by i.invoice_no
) q join invoices i on i.invoice_no = q.invoice_no;

-- ===== Install 448, twice =====
do $$ begin insert into t448_fp values ('start', pg_temp.t448_fingerprint()); end $$;
\if :{?nomig}
do $$ begin perform pg_temp.t448_check(pg_temp.t448_in(), '10 -v nomig=1 but 448 is not in'); end $$;
\else
\ir ../../../supabase/448_refunded_units_count_as_unused.sql
do $$ begin insert into t448_fp values ('first', pg_temp.t448_fingerprint()); end $$;
\ir ../../../supabase/448_refunded_units_count_as_unused.sql
do $$ begin insert into t448_fp values ('second', pg_temp.t448_fingerprint()); end $$;
\endif

-- ===== 10. Installed =====
do $$
declare h text := 'public.invoice_benefit_unused_elsewhere(uuid)'; uv text := 'public.cancelled_invoice_used_value(uuid)';
        pl text := 'public.invoice_action_plan(uuid,text,jsonb)';
begin
  perform pg_temp.t448_check(pg_temp.t448_in(), '10 448 is not installed');
  perform pg_temp.t448_check(md5(pg_get_functiondef(h::regprocedure)) = 'd35d7c8ae7187985ea64f8a5c38a7d79'
    and md5(pg_get_functiondef(uv::regprocedure)) = '055a3b07b1c15ffb1ac19039fa6cb650'
    and md5(pg_get_functiondef(pl::regprocedure)) = '383d618edb28c3c9a360242d038a022c', '10 448 is not installed as tested');
  if exists (select 1 from t448_fp where k = 'first') then
    perform pg_temp.t448_check((select fp from t448_fp where k = 'second') = (select fp from t448_fp where k = 'first'),
      '10 the second run of 448 changed functions');
    perform pg_temp.t448_check(split_part((select fp from t448_fp where k = 'first'), ' ', 2)::int
                               = split_part((select fp from t448_fp where k = 'start'), ' ', 2)::int + 1,
      '10 448 did not add exactly one function');
  end if;
  perform pg_temp.t448_check((select count(*) from pg_proc where pronamespace = 'public'::regnamespace
                               and proname in ('cancelled_invoice_used_value', 'invoice_action_plan', 'invoice_benefit_unused_elsewhere')) = 3,
    '10 an overload exists');
  perform pg_temp.t448_check(
    (select array_agg(x::text order by x::text) from pg_proc p, unnest(p.proacl) x where p.oid = h::regprocedure)
      = array['postgres=X/postgres', 'service_role=X/postgres']
    and not has_function_privilege('anon', h, 'execute') and not has_function_privilege('authenticated', h, 'execute'),
    '10 the helper is not the server''s alone');
  perform pg_temp.t448_check(
    has_function_privilege('service_role', uv, 'execute') and not has_function_privilege('authenticated', uv, 'execute')
    and not has_function_privilege('anon', uv, 'execute')
    and has_function_privilege('service_role', pl, 'execute') and has_function_privilege('authenticated', pl, 'execute')
    and not has_function_privilege('anon', pl, 'execute')
    and (select array_agg(x::text order by x::text) from pg_proc p, unnest(p.proacl) x where p.oid = uv::regprocedure)
        = array['postgres=X/postgres', 'service_role=X/postgres']
    and (select array_agg(x::text order by x::text) from pg_proc p, unnest(p.proacl) x where p.oid = pl::regprocedure)
        = array['authenticated=X/postgres', 'postgres=X/postgres', 'service_role=X/postgres'],
    '10 the grants of the two patched functions changed');
  raise notice 'PASS 10: 448 installed (helper d35d7c8a, cancelled_invoice_used_value 055a3b07, invoice_action_plan 383d618e); %; no overload; the helper is the server''s alone; the two patched functions keep their grants',
    coalesce('the second run changed nothing (' || (select fp from t448_fp where k = 'second') || ', one function more than at the start)',
             'it was in before the suite (nomig)');
end $$;

-- ===== 0. The controls read exactly as before 448 =====
do $$
declare r record; n int := 0;
begin
  for r in select t.k, t.id, b.reads from t448 t left join t448_before b on b.k = t.k where t.k ~ '^K[0-9]+$' order by t.k loop
    if r.reads is not null then
      if pg_temp.t448_reads(r.id) is distinct from r.reads then
        raise exception 'FAIL 0 % reads differently with 448: before % after %', r.k, r.reads, pg_temp.t448_reads(r.id); end if;
      n := n + 1;
    end if;
  end loop;
  -- The absolute figures, either way: 'cancel / Refund in full / used'.
  for r in select * from (values
      ('K1', '- / - / -'), ('K2', 'voucher_redeemed / voucher_redeemed / voucher_redeemed'), ('K3', '- / x / -'),
      ('K4', 'voucher_redeemed / x / voucher_redeemed'), ('K5', 'credit_used / credit_used / credit_used'),
      ('K6', 'credit_used / x / credit_used'), ('K7', '- / - / -'), ('K8', '- / - / -'), ('K9', '- / - / -'),
      ('K10', 'session_used / session_used / session_used'), ('K11', '- / - / -'), ('K12', '- / - / credit_used'),
      ('K13', '- / - / -'), ('K14', '- / - / -'), ('K15', 'voucher_redeemed / voucher_redeemed / voucher_redeemed')) x(k, want)
  loop
    perform pg_temp.t448_check(pg_temp.t448_sum(pg_temp.t448_reads(pg_temp.t448_id(r.k))) = r.want,
      '0 ' || r.k || ' reads ' || pg_temp.t448_sum(pg_temp.t448_reads(pg_temp.t448_id(r.k))) || ', not ' || r.want);
  end loop;
  if n > 0 then
    raise notice 'PASS 0: % controls read exactly as before 448 ("used", and the whole Cancel and Refund in full plans: codes, money, hash): a paid sale, redeemed, cancelled, credit spent, reopened and settled, moved, a session delivered, a customer change, released credit spent, an FOC taken off, reopened to paid', n;
  else
    raise notice 'PASS 0: (448 was in before the suite) the 15 controls ask what they asked before it';
  end if;
end $$;

-- ===== 1. Each case after 448 =====
do $$
declare r record; bad text; n int := 0; a jsonb;
begin
  for r in select * from (values
      ('VA', '- / - / -'), ('VB', '- / x / -'), ('VC', '- / - / -'),
      ('VD', 'voucher_redeemed / voucher_redeemed / voucher_redeemed'),
      ('VE', 'voucher_redeemed / voucher_redeemed / voucher_redeemed'),
      ('VF', '- / - / -'), ('VG', '- / - / -'), ('VH', '- / - / -'), ('VI', '- / - / -'),
      ('VI2', 'voucher_redeemed / voucher_redeemed / voucher_redeemed'),
      ('VJ', '- / - / -'), ('VK', '- / - / -'),
      ('VL', 'session_used / session_used / session_used'),
      ('CA', '- / - / -'), ('CB', '- / x / -'), ('CC', '- / - / -'), ('CQ', '- / - / -'), ('CD', '- / - / -'), ('CE', '- / - / -'), ('CV', '- / - / -'),
      ('CF', 'credit_used / credit_used / credit_used'),
      ('CG', '- / - / -'), ('CH', '- / - / -'), ('CI', '- / - / -'), ('CJ', '- / - / -'),
      ('CJ2', 'credit_used / credit_used / credit_used'),
      ('CK', '- / - / -'), ('CL', '- / - / -'), ('CM', '- / - / -')) x(k, want)
  loop
    a := pg_temp.t448_reads(pg_temp.t448_id(r.k));
    if pg_temp.t448_sum(a) is distinct from r.want then
      bad := coalesce(bad || '; ', '') || r.k || ' reads ' || pg_temp.t448_sum(a) || ', not ' || r.want; end if;
    -- The money of each plan is exactly as before 448.
    if exists (select 1 from t448_before where k = r.k) then
      if pg_temp.t448_money(a->'cancel') is distinct from pg_temp.t448_money((select reads->'cancel' from t448_before where k = r.k))
         or pg_temp.t448_money(a->'refund_full') is distinct from pg_temp.t448_money((select reads->'refund_full' from t448_before where k = r.k)) then
        raise exception 'FAIL 1 % the plans'' money changed with 448: before % after %', r.k,
          pg_temp.t448_money((select reads->'cancel' from t448_before where k = r.k)), pg_temp.t448_money(a->'cancel'); end if;
      n := n + 1;
    end if;
  end loop;
  if bad is not null then raise exception 'FAIL 1 after 448: %', bad; end if;
  -- The amount owed question only where something was really used; held as
  -- the money the invoice holds; the refund due is what is still unused.
  perform pg_temp.t448_check(jsonb_typeof(invoice_action_plan(pg_temp.t448_id('VA'), 'cancel', '[]')->'refund_owed') = 'null'
    and (invoice_action_plan(pg_temp.t448_id('VA'), 'cancel', '[]')->>'refund_due')::numeric = 30
    and jsonb_typeof(invoice_action_plan(pg_temp.t448_id('CA'), 'cancel', '[]')->'refund_owed') = 'null'
    and (invoice_action_plan(pg_temp.t448_id('CA'), 'cancel', '[]')->>'refund_due')::numeric = 100,
    '1 VA / CA: the Cancel plan still asks an amount owed, or its refund due is not what is still unused');
  perform pg_temp.t448_check(invoice_action_plan(pg_temp.t448_id('VD'), 'cancel', '[]')->'refund_owed'->>'held' = '30.00'
    and (invoice_action_plan(pg_temp.t448_id('VD'), 'cancel', '[]')->>'refund_due')::numeric = 0
    and invoice_action_plan(pg_temp.t448_id('VE'), 'cancel', '[]')->'refund_owed'->>'held' = '60.00'
    and (invoice_action_plan(pg_temp.t448_id('VE'), 'cancel', '[]')->>'refund_due')::numeric = 30
    and invoice_action_plan(pg_temp.t448_id('CF'), 'cancel', '[]')->'refund_owed'->>'held' = '60.00'
    and (invoice_action_plan(pg_temp.t448_id('CF'), 'cancel', '[]')->>'refund_due')::numeric = 50,
    '1 VD / VE / CF: the real use is not asked with the money as it is: '
    || (invoice_action_plan(pg_temp.t448_id('VE'), 'cancel', '[]')->'refund_owed')::text);
  if n > 0 then
    raise notice 'PASS 1: % cases: a unit or credit a line refund paid back no longer reads as redeemed or spent (Cancel, Refund in full, "used"), with or without a reopening, a wait, a Move, a customer change, a merge, an FOC taken off, a released lot; real use still does, asked once (VD, VE, VI2, CF, CJ2, VL''s session), with the amount owed held to the money still held; every plan''s money is exactly as before 448', n;
  else
    raise notice 'PASS 1: (448 was in before the suite) each case asks only for real use; the refund due is what is still unused';
  end if;
end $$;

-- ===== Q. The query listed exactly the invoices whose answer changed =====
do $$
declare want text; got text;
begin
  select string_agg(k, ',' order by k) into want from t448
   where k in ('VA', 'VB', 'VC', 'VF', 'VG', 'VH', 'VI', 'VJ', 'VK', 'VL', 'CA', 'CB', 'CC', 'CQ', 'CD', 'CE', 'CV', 'CG', 'CH', 'CI', 'CJ', 'CK', 'CL', 'CM',
               'VI2', 'CJ2');
  select string_agg(t.k, ',' order by t.k) into got from t448_q q join t448 t on t.id = q.invoice_id;
  -- VI2 and CJ2 change too (their refunded row is no longer asked, the
  -- moved one that was used still is); VD and VE do not (the refunded unit
  -- and the redeemed one are on the same row, which still reads redeemed).
  perform pg_temp.t448_check(got = want, 'Q the header query lists ' || coalesce(got, 'nothing') || ', not ' || want);
  -- Where the before reads exist: listed exactly where the Cancel plan's codes changed.
  if exists (select 1 from t448_before) then
    select string_agg(b.k, ',' order by b.k) into want from t448_before b
     where pg_temp.t448_sum(b.reads) is distinct from pg_temp.t448_sum(pg_temp.t448_reads(pg_temp.t448_id(b.k)))
        or b.reads->'cancel'->'overrides_required' is distinct from invoice_action_plan(pg_temp.t448_id(b.k), 'cancel', '[]')->'overrides_required';
    perform pg_temp.t448_check(got = want, 'Q the header query lists ' || coalesce(got, 'nothing') || ', but these changed: ' || coalesce(want, 'none'));
  end if;
  raise notice 'PASS Q: the read-only query in 448''s header, run before it, lists exactly the % invoices whose answer changes, no control', (select count(*) from t448_q);
end $$;

-- ===== 2. The money afterwards =====
do $$
declare inv uuid; codes text; msg text;
begin
  -- VA: the guided Refund in full pays back the other unit, no override.
  inv := pg_temp.t448_id('VA');
  codes := pg_temp.t448_guided(inv, 'refund_full', null, '[]', true);
  perform pg_temp.t448_check(codes = '-' and pg_temp.t448_money_of(inv) = 'refunded net 0.00 due 0.00 held 0 credit 0.00',
    '2 VA Refund in full (asked ' || codes || '): ' || pg_temp.t448_money_of(inv));
  -- VB: cancelled directly before 448: "Record refund paid" is held to the
  -- S$30 still due, and records it.
  inv := pg_temp.t448_id('VB');
  msg := pg_temp.t448_record_refund(inv, 30.01);
  perform pg_temp.t448_check(msg = 'Amount exceeds the correction refund due', '2 VB S$30.01: ' || msg);
  msg := pg_temp.t448_record_refund(inv, 30);
  perform pg_temp.t448_check(msg = 'recorded', '2 VB Record refund paid: ' || msg);
  perform pg_temp.t448_check(pg_temp.t448_money_of(inv) = 'cancelled net 0.00 due 0.00 held 0 credit 0.00', '2 VB: ' || pg_temp.t448_money_of(inv));
  -- VC: the guided Cancel, the money not recorded: no amount owed, no audit
  -- row for it; the S$30 due, then recorded.
  inv := pg_temp.t448_id('VC');
  codes := pg_temp.t448_guided(inv, 'cancel');
  perform pg_temp.t448_check(codes = '-' and (select cancel_refund_owed from invoices where id = inv) is null
    and not exists (select 1 from audit_logs where record_id = inv and action = 'cancel_refund_owed_stated')
    and pg_temp.t448_money_of(inv) = 'cancelled net 30.00 due 30.00 held 0 credit 0.00',
    '2 VC the guided Cancel (asked ' || codes || '): ' || pg_temp.t448_money_of(inv));
  msg := pg_temp.t448_record_refund(inv, 30);
  perform pg_temp.t448_check(msg = 'recorded' and (invoice_financial_position(inv)->>'refund_due')::numeric = 0, '2 VC Record refund paid: ' || msg);
  -- VD: one refunded, one redeemed: the guided Cancel asks the amount owed;
  -- stated S$0, nothing more can be recorded.
  inv := pg_temp.t448_id('VD');
  codes := pg_temp.t448_guided(inv, 'cancel', 0);
  perform pg_temp.t448_check(codes = 'voucher_redeemed' and (select cancel_refund_owed from invoices where id = inv) = 0
    and pg_temp.t448_used(inv) = 'voucher_redeemed',
    '2 VD the guided Cancel (asked ' || codes || '): ' || pg_temp.t448_money_of(inv));
  msg := pg_temp.t448_record_refund(inv, 30);
  perform pg_temp.t448_check(msg like 'That is more than the S$0.00 still owed back%', '2 VD S$30: ' || msg);
  -- VE: one refunded, one redeemed, one held: the guided Cancel stating the
  -- S$30 the held unit is worth; "Record refund paid" held to it.
  inv := pg_temp.t448_id('VE');
  codes := pg_temp.t448_guided(inv, 'cancel', 30);
  perform pg_temp.t448_check(codes = 'voucher_redeemed' and (select cancel_refund_owed from invoices where id = inv) = 30,
    '2 VE the guided Cancel (asked ' || codes || ')');
  msg := pg_temp.t448_record_refund(inv, 31);
  perform pg_temp.t448_check(msg like 'That is more than the S$30.00 still owed back%', '2 VE S$31: ' || msg);
  msg := pg_temp.t448_record_refund(inv, 30);
  perform pg_temp.t448_check(msg = 'recorded' and pg_temp.t448_money_of(inv) = 'cancelled net 30.00 due 0.00 held 0 credit 0.00',
    '2 VE S$30 (' || msg || '): ' || pg_temp.t448_money_of(inv));
  -- VL: the session is still asked, with the amount owed; the voucher unit
  -- refunded is not.
  inv := pg_temp.t448_id('VL');
  perform pg_temp.t448_check(invoice_action_plan(inv, 'cancel', '[]')->'refund_owed'->'used' = '["session_used"]',
    '2 VL the amount owed names ' || (invoice_action_plan(inv, 'cancel', '[]')->'refund_owed'->'used')::text);
  -- CA: the guided Cancel with the money recorded: S$100 back, no override.
  inv := pg_temp.t448_id('CA');
  codes := pg_temp.t448_guided(inv, 'cancel', null, '[]', true);
  perform pg_temp.t448_check(codes = '-' and pg_temp.t448_money_of(inv) = 'cancelled net 0.00 due 0.00 held 0 credit 0.00',
    '2 CA the guided Cancel (asked ' || codes || '): ' || pg_temp.t448_money_of(inv));
  -- CB: cancelled directly before 448: nothing used; "Record refund paid" as
  -- one line is refused for any credit invoice, by design; the line-by-line
  -- refund records the S$100 still due.
  inv := pg_temp.t448_id('CB');
  msg := pg_temp.t448_record_refund(inv, 100);
  perform pg_temp.t448_check(msg like 'Allocate a correction refund to the original unused purchased benefits%', '2 CB Record refund paid: ' || msg);
  msg := pg_temp.t448_by_line(inv);
  perform pg_temp.t448_check(msg = 'recorded' and pg_temp.t448_money_of(inv) = 'cancelled net 0.00 due 0.00 held 0 credit 0.00',
    '2 CB by line (' || msg || '): ' || pg_temp.t448_money_of(inv));
  -- CC: S$40 refunded: Refund in full pays back the other S$60, no override.
  inv := pg_temp.t448_id('CC');
  codes := pg_temp.t448_guided(inv, 'refund_full', null, '[]', true);
  perform pg_temp.t448_check(codes = '-' and pg_temp.t448_money_of(inv) = 'refunded net 0.00 due 0.00 held 0 credit 0.00',
    '2 CC Refund in full (asked ' || codes || '): ' || pg_temp.t448_money_of(inv));
  -- CF: S$40 refunded and S$10 spent: the guided Cancel stating the S$50
  -- unused; S$50.01 refused, S$50 recorded by line.
  inv := pg_temp.t448_id('CF');
  codes := pg_temp.t448_guided(inv, 'cancel', 50);
  perform pg_temp.t448_check(codes = 'credit_used' and (select cancel_refund_owed from invoices where id = inv) = 50
    and pg_temp.t448_money_of(inv) = 'cancelled net 60.00 due 50.00 held 0 credit 0.00',
    '2 CF the guided Cancel (asked ' || codes || '): ' || pg_temp.t448_money_of(inv));
  msg := pg_temp.t448_by_line(inv);
  perform pg_temp.t448_check(msg = 'recorded' and pg_temp.t448_money_of(inv) = 'cancelled net 10.00 due 0.00 held 0 credit 0.00',
    '2 CF by line (' || msg || '): ' || pg_temp.t448_money_of(inv));
  raise notice 'PASS 2: afterwards, through the app: Refund in full pays back what is left with no override (VA, CC); "Record refund paid" records the S$30 still due and not a cent more (VB); the guided Cancel asks no amount owed and leaves the refund due (VC), or records it (CA); a credit invoice''s S$100 due recorded by line (CB); a real use still asks the amount owed, held to it (VD S$0, VE S$30, CF S$50), and VL still asks for its session';
end $$;

-- ===== 3. Interplay after 448: settled, cancelled again =====
do $$
declare inv uuid; msg text; k text; s0 int; s1 int;
begin
  -- VF (limited): settled (both units given again: two units of stock out),
  -- then cancelled again: the stock is back.
  inv := pg_temp.t448_id('VF');
  s0 := pg_temp.t448_stock();
  perform pg_temp.t448_pay(inv);
  s1 := pg_temp.t448_stock();
  perform pg_temp.t448_check(pg_temp.t448_money_of(inv) = 'paid net 60.00 due 0.00 held 2 credit 0.00'
    and pg_temp.t448_codes(inv, 'cancel') = '-' and pg_temp.t448_codes(inv, 'refund_full') = '-',
    '3 VF settled: ' || pg_temp.t448_money_of(inv) || ', asks ' || pg_temp.t448_codes(inv, 'cancel'));
  perform cancel_invoice_recorded(inv, 'T448 3 VF', gen_random_uuid());
  msg := pg_temp.t448_record_refund(inv, 60);
  perform pg_temp.t448_check(pg_temp.t448_used(inv) = '-' and msg = 'recorded'
    and s1 = s0 - 2 and pg_temp.t448_stock() = s0,
    '3 VF cancelled again: used ' || pg_temp.t448_used(inv) || ', ' || msg || ', stock ' || s0 || ' -> ' || s1 || ' -> ' || pg_temp.t448_stock());
  -- VG, CG, CH: settled, cancelled again: nothing used.
  foreach k in array array['VG', 'CG', 'CH'] loop
    inv := pg_temp.t448_id(k);
    perform pg_temp.t448_pay(inv);
    perform pg_temp.t448_check((select status::text from invoices where id = inv) = 'paid'
      and pg_temp.t448_codes(inv, 'cancel') = '-' and pg_temp.t448_codes(inv, 'refund_full') = '-',
      '3 ' || k || ' settled: ' || pg_temp.t448_money_of(inv) || ', asks ' || pg_temp.t448_codes(inv, 'cancel'));
    perform cancel_invoice_recorded(inv, 'T448 3 ' || k, gen_random_uuid());
    perform pg_temp.t448_check(pg_temp.t448_used(inv) = '-', '3 ' || k || ' cancelled again reads ' || pg_temp.t448_used(inv));
  end loop;
  perform pg_temp.t448_check(pg_temp.t448_money_of(pg_temp.t448_id('VG')) = 'cancelled net 60.00 due 60.00 held 0 credit 0.00'
    and pg_temp.t448_money_of(pg_temp.t448_id('CG')) = 'cancelled net 200.00 due 200.00 held 0 credit 0.00'
    and pg_temp.t448_money_of(pg_temp.t448_id('CH')) = 'cancelled net 100.00 due 100.00 held 0 credit 0.00',
    '3 the money after the second cancel: ' || pg_temp.t448_money_of(pg_temp.t448_id('VG')) || ' / '
    || pg_temp.t448_money_of(pg_temp.t448_id('CG')) || ' / ' || pg_temp.t448_money_of(pg_temp.t448_id('CH')));
  perform pg_temp.t448_check(pg_temp.t448_record_refund(pg_temp.t448_id('VG'), 60) = 'recorded'
    and pg_temp.t448_by_line(pg_temp.t448_id('CG')) = 'recorded' and pg_temp.t448_by_line(pg_temp.t448_id('CH')) = 'recorded',
    '3 the refund due of VG / CG / CH was not recorded');
  -- CK, CJ, CL, VJ, VI, VK cancelled: nothing used.
  foreach k in array array['CK', 'CJ', 'CL', 'VJ', 'VI', 'VK', 'CM', 'CD', 'CE', 'CV', 'CI', 'VH'] loop
    inv := pg_temp.t448_id(k);
    perform cancel_invoice_recorded(inv, 'T448 3 ' || k, gen_random_uuid());
    perform pg_temp.t448_check(pg_temp.t448_used(inv) = '-', '3 ' || k || ' cancelled reads ' || pg_temp.t448_used(inv));
  end loop;
  perform pg_temp.t448_check(pg_temp.t448_credit(pg_temp.t448_id('CK')) = 0
    and (select coalesce(sum(remaining_amount), 0) from customer_credit_lots where customer_id = pg_temp.t448_id('friend')
          and id in (select lot_id from invoice_benefit_values where invoice_id = pg_temp.t448_id('CK'))) = 0,
    '3 CK cancelled: the friend still holds credit');
  raise notice 'PASS 3: reopened and waiting, then settled: nothing asked (VF, VG, CG, CH); cancelled again: nothing used, the refund due recorded, the limited voucher stock back; the Move, customer change, merge, FOC, released-lot, bundle and 446 cases cancelled read nothing used';
end $$;

-- ===== 4. A guided request raised before 448 =====
-- CQ's Refund in full was requested before 448 was installed (A), with the
-- plan of that time, which asked credit_used.
do $$
declare inv uuid := pg_temp.t448_id('CQ'); res jsonb;
begin
  res := resolve_invoice_action_v2((select id from t448 where k = 'req CQ'), true, 'T448 4', null, '[]', null, true);
  if (select v from t448_known where k = 'CQ raised with 448') = 'true' then
    perform pg_temp.t448_check(res->>'status' = 'approved' and pg_temp.t448_money_of(inv) = 'refunded net 0.00 due 0.00 held 0 credit 0.00',
      '4 (448 in when raised) the request was not approved: ' || res::text);
    raise notice 'PASS 4: (448 was in when the request was raised) approved with no override; S$60 paid back';
  else
    perform pg_temp.t448_check(coalesce((res->>'confirmation_required')::boolean, false)
      and res->>'message' = 'What this request would do has changed since it was submitted. Review the revised effects and confirm them explicitly.'
      and jsonb_array_length(res->'revised_plan'->'overrides_required') = 0
      and (res->'requested_plan'->'overrides_required'->0->>'code') = 'credit_used',
      '4 a request raised before 448: ' || res::text);
    -- Confirmed with the revised plan's hash: approved, no override.
    res := resolve_invoice_action_v2((select id from t448 where k = 'req CQ'), true, 'T448 4', res->'revised_plan'->>'plan_hash', '[]', null, true);
    perform pg_temp.t448_check(res->>'status' = 'approved' and pg_temp.t448_money_of(inv) = 'refunded net 0.00 due 0.00 held 0 credit 0.00',
      '4 confirmed: ' || res::text || ' ' || pg_temp.t448_money_of(inv));
    raise notice 'PASS 4: a guided Refund in full requested before 448 (its plan asked credit_used) asks, once 448 is in, to confirm the revised plan (no override); confirmed, the S$60 still unused is paid back';
  end if;
end $$;

-- ===== 8. KNOWN: not covered by 448 =====
do $$
declare inv uuid; msg text; held int; a uuid;
begin
  -- (1) A line of two, one unit refunded, cancelled, reopened (both units
  -- wait), cancelled again before settling, the other unit refunded by line
  -- while waiting (446 takes it off the queue), reopened again: 417's "only
  -- what is more" finds one unit waiting (the first refund's) and queues
  -- nothing for the second, so one unit fewer waits than the line charges
  -- again; settled, the customer holds 1 voucher for S$60, and 448 reads the
  -- unit never given as redeemed. (Before 446 the queue kept both: 2 for
  -- S$60. A gap of 446's, on one line of two or more only; checked on the
  -- copy with 417's refund_invoice_recorded rebuilt.)
  inv := pg_temp.t448_sale(array['v'], array[2]);
  perform pg_temp.t448_refund_some(inv, 1);
  perform cancel_invoice_recorded(inv, 'T448 8', gen_random_uuid());
  perform pg_temp.t448_reopened(inv);
  perform cancel_invoice_recorded(inv, 'T448 8 again', gen_random_uuid());
  perform pg_temp.t448_check(pg_temp.t448_used(inv) = '-', '8 (1) cancelled again while waiting reads ' || pg_temp.t448_used(inv));
  perform pg_temp.t448_check(pg_temp.t448_cline_back(inv, 1) = 'recorded', '8 (1) the other unit refunded by line while waiting');
  perform pg_temp.t448_check(pg_temp.t448_used(inv) = '-', '8 (1) the other unit refunded while waiting reads ' || pg_temp.t448_used(inv));
  perform pg_temp.t448_reopened(inv);
  if pg_temp.t448_451_in() then
    -- 451 (the Owner, 22 Oct 2026: "fix the rare 446 voucher case too"): the
    -- reopening takes off only the cancellation's part of what waits, so the
    -- second unit is queued: 2 wait for the S$60, nothing asked; settled, 2
    -- vouchers for S$60.
    perform pg_temp.t448_check((select sum(quantity) from invoice_reopen_vouchers where invoice_id = inv and applied_at is null) = 2
      and invoice_charge_total(inv) = 60 and pg_temp.t448_codes(inv, 'cancel') = '-',
      '8 (1) with 451 waits ' || coalesce((select sum(quantity) from invoice_reopen_vouchers where invoice_id = inv and applied_at is null), 0)
      || ' for S$' || invoice_charge_total(inv) || ' and asks ' || pg_temp.t448_codes(inv, 'cancel'));
    perform pg_temp.t448_pay(inv);
    held := pg_temp.t448_held(inv);
    perform pg_temp.t448_check(held = 2 and invoice_net_received(inv) = 60 and pg_temp.t448_codes(inv, 'cancel') = '-'
      and pg_temp.t448_codes(inv, 'refund_full') = '-',
      '8 (1) with 451, settled: ' || pg_temp.t448_money_of(inv) || ', asks ' || pg_temp.t448_codes(inv, 'cancel'));
    insert into t448_known values ('8.1', 'FIXED by 451: ' || pg_temp.t448_money_of(inv));
  else
    perform pg_temp.t448_check((select sum(quantity) from invoice_reopen_vouchers where invoice_id = inv and applied_at is null) = 1
      and invoice_charge_total(inv) = 60 and pg_temp.t448_codes(inv, 'cancel') = 'voucher_redeemed',
      '8 (1) now waits ' || coalesce((select sum(quantity) from invoice_reopen_vouchers where invoice_id = inv and applied_at is null), 0)
      || ' for S$' || invoice_charge_total(inv) || ' and asks ' || pg_temp.t448_codes(inv, 'cancel') || ': look at 448''s NOT COVERED 1 and this case again');
    perform pg_temp.t448_pay(inv);
    held := pg_temp.t448_held(inv);
    perform pg_temp.t448_check(held = 1 and invoice_net_received(inv) = 60 and pg_temp.t448_codes(inv, 'cancel') = 'voucher_redeemed',
      '8 (1) settled: ' || pg_temp.t448_money_of(inv) || ', asks ' || pg_temp.t448_codes(inv, 'cancel')
      || ': look at 448''s NOT COVERED 1 and this case again');
    insert into t448_known values ('8.1', pg_temp.t448_money_of(inv));
  end if;
  -- (2) S$40 of a package refunded, the buyer merged into another record,
  -- cancelled, reopened and settled: the S$40 is reinstated on the merged
  -- record's emptied lot (the reopening puts a refund back on the lot it
  -- came from), so the kept record's lot holds S$60, and 448 reads it as
  -- spent (as before 448).
  inv := pg_temp.t448_sale(array['cp'], null, null, 'dup2');
  perform pg_temp.t448_check(pg_temp.t448_cline_back(inv, 1, 40) = 'recorded', '8 (2) S$40');
  perform merge_customer_records(pg_temp.t448_id('kept'), pg_temp.t448_id('dup2'), 'T448 the same person', gen_random_uuid());
  perform pg_temp.t448_check(pg_temp.t448_codes(inv, 'cancel') = '-', '8 (2) merged after the refund asks ' || pg_temp.t448_codes(inv, 'cancel'));
  perform cancel_invoice_recorded(inv, 'T448 8 (2)', gen_random_uuid());
  perform pg_temp.t448_reopened(inv);
  perform pg_temp.t448_check(pg_temp.t448_codes(inv, 'cancel') = '-', '8 (2) reopened, waiting, asks ' || pg_temp.t448_codes(inv, 'cancel'));
  perform pg_temp.t448_pay(inv);
  select b.id into a from invoice_benefit_values b where b.invoice_id = inv;
  perform pg_temp.t448_check(pg_temp.t448_codes(inv, 'cancel') = 'credit_used'
    and (select l.customer_id from invoice_benefit_values b join customer_credit_lots l on l.id = b.lot_id where b.id = a) = pg_temp.t448_id('kept')
    and (select sum(l.remaining_amount) from customer_credit_lots l where l.customer_id = pg_temp.t448_id('dup2')) = 40
    and pg_temp.t448_credit(inv) = 60,
    '8 (2) settled: ' || pg_temp.t448_money_of(inv) || ', asks ' || pg_temp.t448_codes(inv, 'cancel')
    || ', the merged record holds ' || coalesce((select sum(l.remaining_amount) from customer_credit_lots l where l.customer_id = pg_temp.t448_id('dup2')), 0)
    || ': look at 448''s NOT COVERED 2 and this case again');
  -- (3) A partly refunded credit lot blocks a customer change as "Partly spent".
  inv := pg_temp.t448_sale(array['cp']);
  perform pg_temp.t448_check(pg_temp.t448_cline_back(inv, 1, 40) = 'recorded', '8 (3) S$40');
  begin
    perform pg_temp.t448_change(inv, 'friend');
    msg := 'changed';
  exception when others then msg := sqlerrm;
  end;
  perform pg_temp.t448_check(msg like '%Partly spent%', '8 (3) a customer change after S$40 was refunded: ' || msg
    || ': look at 448''s NOT COVERED 3 and this case again');
  if pg_temp.t448_451_in() then
    raise notice 'FIXED 8 (1) (451 in): one unit of a line of two refunded, cancelled, reopened, cancelled again, the other unit refunded by line while waiting, reopened again: 2 units wait for the S$60 the line charges again, nothing asked; once settled the customer holds 2 vouchers for S$60 (%)',
      (select v from t448_known where k = '8.1');
    raise notice 'KNOWN 8: (not covered by 448; there before it) (2) S$40 of a package refunded, the buyer merged away, cancelled, reopened and settled: the S$40 is reinstated on the merged-away record''s lot, the kept record''s lot holds S$60, and it reads credit_used. (3) a credit lot partly refunded blocks a customer change as "Partly spent": %',
      msg;
  else
    raise notice 'KNOWN 8: (not covered by 448; there before it) (1) one unit of a line of two refunded, cancelled, reopened, cancelled again, the other unit refunded by line while waiting, reopened again: the reopening queues 1 unit for the S$60 the line charges again (446 took the second unit off the queue; 417''s "only what is more" then queues nothing for it), and once settled the customer holds 1 voucher for S$60 (%); before 446 it was 2; 448 reads the unit never given as redeemed (451 fixes it). (2) S$40 of a package refunded, the buyer merged away, cancelled, reopened and settled: the S$40 is reinstated on the merged-away record''s lot, the kept record''s lot holds S$60, and it reads credit_used. (3) a credit lot partly refunded blocks a customer change as "Partly spent": %',
      (select v from t448_known where k = '8.1'), msg;
  end if;
end $$;

rollback;
