-- 446: a voucher or credit refunded while a reopened invoice waits to be
-- settled is not given again when it is settled (438's NOT COVERED 4; the
-- Owner, 22 Oct 2026: "Fix it", and the same for credit).
--
-- Every step goes through the app's own calls: the invoice form
-- (create_invoice_with_details) and the Pay dialog (record_invoice_settlement),
-- Cancel (cancel_invoice_recorded), "Record refund paid" and the Finance
-- panel's Reopen (refund_invoice_recorded with no item, or for a credit line
-- with the line's unused benefits, reopen_invoice), the guided "Refund some
-- items", Refund in full and Cancel (invoice_action_plan,
-- request_invoice_action_v2, resolve_invoice_action_v2), Record Payment
-- (record_invoice_payment) and the Finance panel's Move
-- (transfer_invoice_unused_benefit). "Waiting" below: a reopened invoice left
-- part-paid, whose vouchers wait in invoice_reopen_vouchers, and whose credit
-- waits in invoice_reopen_benefits, until it is settled. The suite runs in one
-- transaction, where now() never moves; the credit queue's rows are stamped
-- with the time of the reopening or payment that wrote them, as production's
-- are (446's refusal reads those times).
--   R. The faults, without 446 (skipped, with a notice, when 446 was in before
--      the suite started): two S$30 limited vouchers sold and paid, cancelled,
--      S$30 paid back, reopened, line A refunded while waiting, the S$30
--      outstanding paid: 2 vouchers held for S$30 net and 2 units of stock out;
--      cancelled again, reopened and paid: 3 held for two lines of one. A line
--      of two with one unit refunded: 2 held for S$30. Credit: two S$100
--      Credit Packages, cancelled, line B's S$100 paid back, reopened, line A
--      refunded while waiting, paid: S$200 of credit for S$100 net (S$220 with
--      a S$10 Bonus each; S$240 for two Premium Bundles of S$100 Paid and S$20
--      Bonus); S$40 of line A refunded: S$200 for S$160. Run inside a block
--      that is undone, so 446 can be installed after it (446 refuses a
--      database in that state: cases 9 and 9b).
--   0. Controls, refunds with nothing waiting (a paid sale, a line of two,
--      a reopened invoice paid straight away, a cancelled invoice not
--      reopened, a Credit Package, a reopened invoice refunded once settled;
--      for credit, a cancelled invoice not reopened, a reopened invoice
--      refunded once settled, Premium Bundles reopened straight to paid):
--      run before 446 and again after it, their outcomes compared whole
--      (status, money, every benefit row, its voucher or lot, both queues,
--      the lot's ledger, stock, refunds, Audit Log actions, the plans and
--      "used").
--   9. The refusal: a database where a line refund was made while vouchers
--      waited (one still waiting, one settled since): 446 refuses, changing
--      nothing, and names both invoices.
--  9b. The same for credit (one still waiting, one settled since), beside
--      a credit line paid back before its reopening and still waiting, and a
--      line refunded once settled: 446 refuses, changing nothing, and names
--      the two faulty invoices only.
--  10. Installed twice: the second run changes nothing; grants kept; no
--      overload.
--   1. The fix, two lines of one (plain and limited): line A's queued row is
--      removed, B's waits, the invoice's Audit Log has it; paid: 1 voucher
--      (line B's) for S$30 net, 1 unit of stock out; cancelled again,
--      reopened and paid: 2 held for S$60, the refund counted once; stock
--      back on cancelling.
--   2. A line of two, one unit refunded while waiting: the queued row is
--      lowered to one (the same row); paid: 1 held for S$30. A line of two
--      and a line of one, the line of two refunded whole while waiting: its
--      row removed; paid: 1 held.
--   3. Refunded while waiting, cancelled again before settling, reopened:
--      2 wait (the refund counted once); paid: 2 held for S$60.
--   4. A completed FOC, the FOC taken off (416), paid, cancelled, reopened,
--      line A refunded while waiting: paid: 1 held for S$30, stock right.
--   5. Move: refused while vouchers wait (as before); after the refund and
--      the payment, line B's voucher moved to a friend, then the invoice
--      cancelled: taken back from the friend, stock right.
--   6. 438's counting: a reopened invoice settled with no refund asks no
--      override (438). After a refund while waiting and settled: Refund in
--      full asks none and pays back the S$30 taking line B's voucher back;
--      Cancel asks voucher_redeemed (446's NOT COVERED 1, 438's NOT COVERED 2:
--      KNOWN); the guided Cancel stating S$30 owed lets the S$30 be recorded.
--      Where 448 is in (the Owner, 22 Oct 2026: a unit or credit a line
--      refund paid back is not used), Cancel asks nothing and no amount owed
--      is kept, and the S$30 is recorded the same.
--   7. The controls after 446: the same.
--   8. KNOWN (446's NOT COVERED 1-4, checked as they are): a line of two with
--      one unit refunded while waiting and settled: Refund in full asks
--      voucher_redeemed; a credit line refunded, while waiting or not, reads
--      credit_used to Cancel (NOT COVERED 1: where 448 is in, checked as
--      fixed: nothing asked, nothing used, "Record refund paid" records the
--      money, printed as FIXED); a unit, or credit, queued because an earlier
--      line refund took it cannot be refunded while waiting; an FOC taken
--      off and not yet paid cannot be refunded by line; a part-paid package
--      never settled has nothing waiting and no line refund.
--  8b. KNOWN (446's NOT COVERED 5, checked as it is, with or without 447): a
--      line refunded by line, then the customer changed to the friend with
--      the benefits taken along, cancelled, reopened and paid: the invoice is
--      the friend's and paid in full, and line A's credit (S$110) or voucher
--      is back with the buyer; the same for a line refunded while the credit
--      or the vouchers waited, once settled, then changed. Where 460 is in
--      (the Owner, 22 Oct 2026: what a reopened invoice gives back goes to
--      whoever its benefits belong to now), checked the fixed way: line A's
--      credit or voucher is the friend's once paid (printed as FIXED).
--  11. Credit, a line refunded whole while waiting (a S$100 Credit Package,
--      one with a S$10 Bonus, a Premium Bundle of S$100 Paid and S$20 Bonus):
--      line A's queued rows (Paid and Bonus) closed, each with its reverse
--      and the refund in the ledger, the lots unmoved, the Audit Log, the
--      customer's statement; a Move still refused; paid: line B's credit
--      alone for S$100 net; Refund in full afterwards asks nothing; cancelled
--      again, B paid back, reopened (the Reopen dialog counts the refund
--      once) and paid: all the credit for S$200.
--  12. Credit, part refunded while waiting: S$40 of line A (its row lowered
--      to S$60, the same row; paid: S$160 for S$160; reopened straight after
--      a cancel and paid: S$200 for S$200); S$40 and then the rest (the row
--      lowered, then closed); line A's Paid credit alone (its Bonus still
--      waits and is reinstated).
--  13. Credit refunded while waiting, cancelled again before settling,
--      reopened: all of it waits again, the refund counted once (part and
--      whole); paid: all the credit for S$200. (Where 474 is in, the Reopen
--      dialog also counts the credit still waiting: S$200, what the payment
--      gives, where it said S$40, the refund's own row alone: 471's NOT
--      COVERED 7.)
--  14. A part-paid package's released lot, settled, cancelled, reopened,
--      refunded while waiting: line B's credit alone; the second cycle right.
--  15. Credit refunded before the reopening (its own ledger row waits too)
--      and while waiting: what waits for the lot is lowered across both rows;
--      paid: S$130 for S$130; the second cycle right.
--
-- Run on a copy of production as it is (445 in: 83a90dbf, 1370 functions),
-- with or without 447, with
--   psql -v ON_ERROR_STOP=1 -f scripts/invoices/tests/reopen-refund-waiting-446.sql
-- It installs 446 itself, twice, inside its transaction. Where 446 is in
-- already, add -v nomig=1 (R, the before/after comparison and the refusals
-- are then skipped with a notice; every figure after 446 is still checked).
-- Cases 9 and 9b each let one statement fail on purpose (psql prints its
-- ERROR); the suite then checks that message. Disposable database only;
-- everything is rolled back. Every name, code and amount is invented
-- (@example.com); the phones are numbers kept for fiction (ACMA).
\set ON_ERROR_STOP on
begin;

create temp table t446(k text primary key, id uuid);
create temp table t446_ctl(k text primary key, before jsonb, after jsonb);
create temp table t446_fp(k text primary key, fp text);
create temp table t446_known(k text primary key, v text);
create function pg_temp.t446_id(p_k text) returns uuid language sql as $f$ select id from t446 where k = p_k $f$;
create function pg_temp.t446_check(p_ok boolean, p_label text) returns void language plpgsql as $f$
begin
  if not coalesce(p_ok, false) then raise exception 'FAIL %', p_label; end if;
end $f$;
create function pg_temp.t446_fingerprint() returns text language sql as $f$
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.oid::regprocedure::text)) || ' ' || count(*)
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prokind in ('f', 'p') $f$;
create function pg_temp.t446_in() returns boolean language sql as $f$
  select position('-- 446 (the Owner' in pg_get_functiondef('public.refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid)'::regprocedure)) > 0 $f$;
-- 474 (471's NOT COVERED 7): the Reopen dialog's credit to reinstate also
-- counts what an earlier reopening queued and still waits.
create function pg_temp.t446_474_in() returns boolean language sql as $f$
  select position('-- 474 (the Owner, 26 Oct 2026' in pg_get_functiondef('public.invoice_reopen_preview_before_sessions(uuid)'::regprocedure)) > 0 $f$;
-- 448 (446's NOT COVERED 1 fixed): a unit or credit a line refund paid back
-- is not used.
create function pg_temp.t448_in() returns boolean language sql as $f$
  select to_regprocedure('public.invoice_benefit_unused_elsewhere(uuid)') is not null
     and position('-- 448:' in pg_get_functiondef('public.cancelled_invoice_used_value(uuid)'::regprocedure)) > 0 $f$;
-- 460 (446's NOT COVERED 5 fixed): what a reopened invoice gives back goes
-- to whoever its benefits belong to now.
create function pg_temp.t460_in() returns boolean language sql as $f$
  select to_regprocedure('public.invoice_benefits_holder(uuid,uuid,timestamp with time zone)') is not null
     and position('-- 460 (the Owner' in pg_get_functiondef('public.apply_reopened_invoice_benefits()'::regprocedure)) > 0 $f$;

do $$
declare own uuid := gen_random_uuid(); st uuid; c uuid; c2 uuid; pm uuid; v uuid; vl uuid; cp uuid; cpb uuid; pbb uuid;
begin
  insert into auth.users(id, email) values (own, 't446-owner@example.com');
  insert into profiles(id, full_name, email, role, is_active) values (own, 'T446 Owner', 't446-owner@example.com', 'owner', true);
  perform set_config('request.jwt.claims', json_build_object('sub', own, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', own::text, true);
  insert into stores(name, code, country_code) values ('T446 Store', 'T446S1', 'SG') returning id into st;
  insert into customers(full_name, phone) values ('T446 Buyer', '+61491570461') returning id into c;
  insert into customers(full_name, phone) values ('T446 Friend', '+61491570462') returning id into c2;
  insert into payment_methods(name, is_active) values ('T446 Cash', true) returning id into pm;
  -- A plain S$30 voucher, and a limited one (100 in stock) to follow stock.
  insert into vouchers(name, code, voucher_kind, qty_type, selling_price, is_active)
    values ('T446 Plain 30', 'T446-P30', 'normal', 'unlimited', 30, true) returning id into v;
  insert into voucher_store_prices(voucher_id, store_id, selling_price, available_at_store) values (v, st, 30, true);
  insert into vouchers(name, code, voucher_kind, qty_type, selling_price, is_active)
    values ('T446 Limited 30', 'T446-L30', 'normal', 'limited', 30, true) returning id into vl;
  insert into voucher_store_prices(voucher_id, store_id, selling_price, available_at_store) values (vl, st, 30, true);
  insert into voucher_store_stock(voucher_id, store_id, current_qty) values (vl, st, 100);
  -- A S$100 Credit Package (S$100 paid credit, no bonus).
  insert into credit_packages(name, customer_price, paid_credit_amount, bonus_enabled, allow_product, allow_therapy)
    values ('T446 S$100', 100, 100, false, true, true) returning id into cp;
  insert into credit_package_stores(package_id, store_id) values (cp, st);
  -- One with a S$10 Bonus, and a Premium Bundle of S$100 Paid and S$20 Bonus.
  insert into credit_packages(name, customer_price, paid_credit_amount, bonus_enabled, bonus_value, allow_product, allow_therapy, grants_reward)
    values ('T446 S$100 + S$10', 100, 100, true, 10, true, true, false) returning id into cpb;
  insert into credit_package_stores(package_id, store_id) values (cpb, st);
  insert into premium_bundles(name, customer_payment_amount, paid_credit_amount, bonus_credit_amount, free_voucher_qty, grants_reward)
    values ('T446 Bundle S$100 + S$20', 100, 100, 20, 0, false) returning id into pbb;
  insert into premium_bundle_stores(bundle_id, store_id) values (pbb, st);
  insert into t446 values ('own', own), ('store', st), ('buyer', c), ('friend', c2), ('pm', pm), ('v', v), ('vl', vl), ('cp', cp),
                          ('cpb', cpb), ('pbb', pbb);
end $$;

-- The invoice form with one voucher line per quantity given, paid in full
-- through the Pay dialog.
create function pg_temp.t446_sale_lines(p_voucher text, p_qtys int[]) returns uuid language plpgsql as $f$
declare inv uuid; v_lines jsonb := '[]'; q int;
begin
  foreach q in array p_qtys loop
    v_lines := v_lines || jsonb_build_array(jsonb_build_object('kind', 'voucher', 'voucher_id', pg_temp.t446_id(p_voucher), 'quantity', q));
  end loop;
  inv := create_invoice_with_details(pg_temp.t446_id('store'), pg_temp.t446_id('buyer'), v_lines,
    jsonb_build_object('business_date', sg_today()::text));
  perform record_invoice_settlement(inv, jsonb_build_object('receipts', jsonb_build_array(jsonb_build_object(
    'key', 'line-0', 'payment_method_id', pg_temp.t446_id('pm'), 'amount', (select total_amount from invoices where id = inv),
    'payment_date', sg_today()::text)), 'arrangements', '[]'::jsonb), gen_random_uuid());
  return inv;
end $f$;
create function pg_temp.t446_sale(p_voucher text, p_lines int, p_qty int) returns uuid language sql as $f$
  select pg_temp.t446_sale_lines(p_voucher, array_fill(p_qty, array[p_lines])) $f$;
-- Record Payment: what is outstanding, or p_amount.
create function pg_temp.t446_pay(p_inv uuid, p_amount numeric default null) returns void language plpgsql as $f$
begin
  perform record_invoice_payment(p_inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.t446_id('pm'),
    'amount', coalesce(p_amount, (invoice_financial_position(p_inv)->>'outstanding')::numeric))), gen_random_uuid());
end $f$;
-- "Record refund paid": one line with no item, through a receipt that still
-- holds it. 'recorded', or the refusal.
create function pg_temp.t446_record_refund(p_inv uuid, p_amount numeric) returns text language plpgsql as $f$
begin
  perform refund_invoice_recorded(p_inv, jsonb_build_array(jsonb_build_object('invoice_item_id', null, 'amount', p_amount)),
    jsonb_build_array(jsonb_build_object('payment_id',
      (select id from invoice_payments where invoice_id = p_inv and entry_kind = 'receipt' and invoice_payment_remaining(id) >= p_amount
        order by created_at limit 1), 'amount', p_amount)),
    '[]'::jsonb, 'T446 paid back', gen_random_uuid());
  return 'recorded';
exception when others then return sqlerrm;
end $f$;
-- The guided Refund / Cancel as an Owner confirms it (InvoiceGuidedAction):
-- the plan, the request, the approval with a reason for every override the
-- plan asks for and, when p_owed is given, 417's amount owed back; the money
-- recorded as paid back when p_record. Returns the codes the plan asked for
-- ('-' for none), or 'ERR ' and the refusal.
create function pg_temp.t446_guided(p_inv uuid, p_action text, p_owed numeric default null,
                                    p_lines jsonb default '[]', p_record boolean default false) returns text language plpgsql as $f$
declare plan jsonb; req jsonb; ov jsonb; stock jsonb;
begin
  plan := invoice_action_plan(p_inv, p_action, p_lines);
  req := request_invoice_action_v2(p_inv, p_action, p_lines, 'T446 ' || p_action, null, gen_random_uuid());
  select coalesce(jsonb_agg(case when coalesce((o->>'amount_required')::boolean, false)
           then jsonb_build_object('code', o->>'code', 'reason', 'T446 override', 'amount', (o->>'default_amount')::numeric)
           else jsonb_build_object('code', o->>'code', 'reason', 'T446 override') end), '[]'::jsonb)
    into ov from jsonb_array_elements(coalesce(plan->'overrides_required', '[]')) o;
  if p_owed is not null then
    ov := ov || jsonb_build_array(jsonb_build_object('code', 'refund_owed', 'amount', p_owed, 'reason', 'T446 owed')); end if;
  select jsonb_agg(jsonb_build_object('movement_id', s->>'movement_id', 'sellable_quantity', (s->>'proposed_sellable')::int,
           'damaged_quantity', 0, 'not_returned_quantity', 0)) into stock
    from jsonb_array_elements(coalesce(plan->'stock', '[]')) s;
  perform resolve_invoice_action_v2((req->>'request_id')::uuid, true, 'T446 ' || p_action, plan->>'plan_hash', ov, stock, p_record);
  return (select coalesce(string_agg(o->>'code', ',' order by o->>'code'), '-')
            from jsonb_array_elements(coalesce(plan->'overrides_required', '[]')) o);
exception when others then return 'ERR ' || sqlerrm;
end $f$;
-- The invoice's n-th line (by id), or its line of p_qty units.
create function pg_temp.t446_line(p_inv uuid, p_n int) returns uuid language sql as $f$
  select id from invoice_items where invoice_id = p_inv order by id offset p_n - 1 limit 1 $f$;
create function pg_temp.t446_line_of(p_inv uuid, p_qty int) returns uuid language sql as $f$
  select id from invoice_items where invoice_id = p_inv and quantity = p_qty order by id limit 1 $f$;
-- The guided "Refund some items": p_qty units of one line, recorded as paid back.
create function pg_temp.t446_refund_some(p_inv uuid, p_item uuid, p_qty int) returns text language sql as $f$
  select pg_temp.t446_guided(p_inv, 'refund_partial', null,
    jsonb_build_array(jsonb_build_object('invoice_item_id', p_item, 'quantity', p_qty)), true) $f$;
-- Sold with the lines given, paid, cancelled, p_back recorded as paid back,
-- reopened: part-paid, every unit waiting.
create function pg_temp.t446_waiting(p_voucher text, p_qtys int[], p_back numeric default 30) returns uuid language plpgsql as $f$
declare inv uuid; units int := (select sum(q) from unnest(p_qtys) q);
begin
  inv := pg_temp.t446_sale_lines(p_voucher, p_qtys);
  perform cancel_invoice_recorded(inv, 'T446 cancel', gen_random_uuid());
  perform pg_temp.t446_check(pg_temp.t446_record_refund(inv, p_back) = 'recorded', 'fixture: S$' || p_back || ' paid back');
  perform reopen_invoice(inv, 'T446 reopen', gen_random_uuid());
  perform pg_temp.t446_check((select status::text from invoices where id = inv) = 'partially_paid'
    and (select sum(quantity) from invoice_reopen_vouchers where invoice_id = inv and applied_at is null) = units,
    'fixture: not reopened part-paid with every unit waiting');
  return inv;
end $f$;
-- Units of the invoice's vouchers held (by anyone), on one line or all.
create function pg_temp.t446_held(p_inv uuid, p_item uuid default null) returns int language sql as $f$
  select coalesce(sum(v.quantity), 0)::int from invoice_benefit_values b join customer_reward_vouchers v on v.id = b.reward_voucher_id
   where b.invoice_id = p_inv and v.status = 'held' and (p_item is null or b.invoice_item_id = p_item) $f$;
create function pg_temp.t446_waiting_units(p_inv uuid) returns int language sql as $f$
  select coalesce(sum(quantity), 0)::int from invoice_reopen_vouchers where invoice_id = p_inv and applied_at is null $f$;
create function pg_temp.t446_stock() returns int language sql as $f$
  select current_qty from voucher_store_stock where voucher_id = pg_temp.t446_id('vl') and store_id = pg_temp.t446_id('store') $f$;
create function pg_temp.t446_codes(p_inv uuid, p_action text) returns text language sql as $f$
  select coalesce(string_agg(o->>'code', ',' order by o->>'code'), '-')
    from jsonb_array_elements(coalesce(invoice_action_plan(p_inv, p_action, '[]')->'overrides_required', '[]')) o $f$;
create function pg_temp.t446_used(p_inv uuid) returns text language sql as $f$
  select coalesce(nullif(array_to_string(cancelled_invoice_used_value(p_inv), ','), ''), '-') $f$;
create function pg_temp.t446_money(p_inv uuid) returns text language sql as $f$
  select status::text || ' net ' || invoice_net_received(id) || ' held ' || pg_temp.t446_held(id) || ' waiting ' || pg_temp.t446_waiting_units(id)
    from invoices where id = p_inv $f$;
-- ── Credit ──────────────────────────────────────────────────────────────
-- 'cp' a S$100 Credit Package (S$100 Paid), 'cpb' one with a S$10 Bonus,
-- 'pbb' a Premium Bundle (S$100 Paid, S$20 Bonus), each S$100.
-- The suite is one transaction: now() never moves, but production's queue
-- rows carry the time of the reopening, and of the payment that settled
-- them, each its own transaction. Re-stamped so, after each such step (446's
-- refusal compares them with the refunds' times).
create function pg_temp.t446_stamp(p_inv uuid) returns void language sql as $f$
  update invoice_reopen_benefits set created_at = clock_timestamp() where invoice_id = p_inv and created_at = now();
  update invoice_reopen_benefits set applied_at = clock_timestamp() where invoice_id = p_inv and applied_at = now();
$f$;
-- The invoice form with one line per kind given; the Pay dialog with p_pay
-- (all of it by default).
create function pg_temp.t446_csale(p_kinds text[], p_pay numeric default null) returns uuid language plpgsql as $f$
declare inv uuid; v_lines jsonb := '[]'; k text;
begin
  foreach k in array p_kinds loop
    v_lines := v_lines || jsonb_build_array(case when k in ('cp', 'cpb')
      then jsonb_build_object('kind', 'credit_package', 'credit_package_id', pg_temp.t446_id(k), 'quantity', 1)
      else jsonb_build_object('kind', 'premium_bundle', 'premium_bundle_id', pg_temp.t446_id(k), 'quantity', 1) end);
  end loop;
  inv := create_invoice_with_details(pg_temp.t446_id('store'), pg_temp.t446_id('buyer'), v_lines,
    jsonb_build_object('business_date', sg_today()::text));
  perform record_invoice_settlement(inv, jsonb_build_object('receipts', jsonb_build_array(jsonb_build_object(
    'key', 'line-0', 'payment_method_id', pg_temp.t446_id('pm'),
    'amount', coalesce(p_pay, (select total_amount from invoices where id = inv)),
    'payment_date', sg_today()::text)), 'arrangements', '[]'::jsonb), gen_random_uuid());
  perform pg_temp.t446_stamp(inv);
  return inv;
end $f$;
-- Record Payment and Reopen, stamped.
create function pg_temp.t446_cpay(p_inv uuid, p_amount numeric default null) returns void language plpgsql as $f$
begin perform pg_temp.t446_pay(p_inv, p_amount); perform pg_temp.t446_stamp(p_inv); end $f$;
create function pg_temp.t446_creopen(p_inv uuid) returns void language plpgsql as $f$
begin perform reopen_invoice(p_inv, 'T446 reopen', gen_random_uuid()); perform pg_temp.t446_stamp(p_inv); end $f$;
-- The Finance panel's refund of a credit line: each of the line's unused
-- benefits at what it can still refund, or p_amount off its Paid benefit
-- alone, through the receipts that still hold it. 'recorded', or the refusal.
create function pg_temp.t446_cline_back(p_inv uuid, p_item uuid, p_amount numeric default null,
                                        p_kind text default null) returns text language plpgsql as $f$
declare opts jsonb; ben jsonb; tot numeric; src jsonb := '[]'; left_ numeric; p record;
begin
  opts := invoice_refund_options_before_sessions(p_inv);
  if p_amount is null then
    select jsonb_agg(jsonb_build_object('benefit_id', b->>'id', 'amount', (b->>'max_refund')::numeric)), sum((b->>'max_refund')::numeric)
      into ben, tot from jsonb_array_elements(opts->'benefits') b
     where b->>'invoice_item_id' = p_item::text and (b->>'max_refund')::numeric > 0
       and (p_kind is null or b->>'benefit_kind' = p_kind);
  else
    select jsonb_build_array(jsonb_build_object('benefit_id', b->>'id', 'amount', p_amount)), p_amount
      into ben, tot from jsonb_array_elements(opts->'benefits') b
     where b->>'invoice_item_id' = p_item::text and b->>'benefit_kind' = 'paid'
     order by (b->>'paid_value')::numeric desc limit 1;
  end if;
  left_ := tot;
  for p in select id, invoice_payment_remaining(id) as rem from invoice_payments
            where invoice_id = p_inv and entry_kind = 'receipt' and invoice_payment_remaining(id) > 0 order by created_at, id loop
    exit when left_ <= 0;
    src := src || jsonb_build_array(jsonb_build_object('payment_id', p.id, 'amount', least(p.rem, left_)));
    left_ := left_ - least(p.rem, left_);
  end loop;
  perform refund_invoice_recorded(p_inv, jsonb_build_array(jsonb_build_object('invoice_item_id', p_item, 'amount', tot, 'benefits', ben)),
    src, '[]'::jsonb, 'T446 credit paid back', gen_random_uuid());
  return 'recorded';
exception when others then return sqlerrm;
end $f$;
-- Sold (the kinds given), paid, cancelled, the last line's credit paid back
-- on the cancelled invoice, reopened: part-paid, all its credit waiting.
create function pg_temp.t446_cwaiting(p_kinds text[]) returns uuid language plpgsql as $f$
declare inv uuid; granted numeric;
begin
  inv := pg_temp.t446_csale(p_kinds);
  select sum(b.granted_value) into granted from invoice_benefit_values b where b.invoice_id = inv and b.lot_id is not null;
  perform cancel_invoice_recorded(inv, 'T446 cancel', gen_random_uuid());
  perform pg_temp.t446_check(pg_temp.t446_cline_back(inv, pg_temp.t446_line(inv, cardinality(p_kinds))) = 'recorded',
    'fixture: the last line''s credit paid back');
  perform pg_temp.t446_creopen(inv);
  perform pg_temp.t446_check((select status::text from invoices where id = inv) = 'partially_paid'
    and (select sum(amount) from invoice_reopen_benefits where invoice_id = inv and applied_at is null) = granted,
    'fixture: not reopened part-paid with all its credit waiting');
  return inv;
end $f$;
-- Credit the invoice's lots hold (by anyone), on one line or all; what waits.
create function pg_temp.t446_credit(p_inv uuid, p_item uuid default null) returns numeric language sql as $f$
  select round(coalesce(sum(l.remaining_amount), 0), 2) from invoice_benefit_values b join customer_credit_lots l on l.id = b.lot_id
   where b.invoice_id = p_inv and (p_item is null or b.invoice_item_id = p_item) $f$;
create function pg_temp.t446_cwait(p_inv uuid, p_item uuid default null) returns numeric language sql as $f$
  select round(coalesce(sum(q.amount), 0), 2) from invoice_reopen_benefits q join customer_credit_ledger e on e.id = q.source_ledger_id
   where q.invoice_id = p_inv and q.applied_at is null
     and (p_item is null or e.lot_id in (select b.lot_id from invoice_benefit_values b where b.invoice_item_id = p_item)) $f$;
create function pg_temp.t446_cmoney(p_inv uuid) returns text language sql as $f$
  select status::text || ' net ' || invoice_net_received(id) || ' credit ' || pg_temp.t446_credit(id) || ' waiting ' || pg_temp.t446_cwait(id)
    from invoices where id = p_inv $f$;
-- The buyer's credit statement ends at the credit the buyer's lots hold.
create function pg_temp.t446_statement_ok() returns boolean language sql as $f$
  select coalesce((select s.wallet_balance from customer_credit_statement(pg_temp.t446_id('buyer')) s
                    order by s.entry_date desc, s.entry_seq desc limit 1), 0)
       = (select coalesce(sum(remaining_amount), 0) from customer_credit_lots where customer_id = pg_temp.t446_id('buyer')) $f$;
-- The queued credit rows of a line's lots: 'amount' + w(aiting) / a(pplied).
create function pg_temp.t446_cqueue(p_inv uuid, p_item uuid) returns text language sql as $f$
  select coalesce(string_agg(q.amount || case when q.applied_at is null then 'w' else 'a' end, ',' order by q.amount, q.applied_at is null), '-')
    from invoice_reopen_benefits q join customer_credit_ledger e on e.id = q.source_ledger_id
   where q.invoice_id = p_inv and e.lot_id in (select b.lot_id from invoice_benefit_values b where b.invoice_item_id = p_item) $f$;
-- The last refund's request id on the invoice.
create function pg_temp.t446_last_refund(p_inv uuid) returns uuid language sql as $f$
  select request_id from invoice_refunds where invoice_id = p_inv order by created_at desc limit 1 $f$;
-- What 446 wrote for a line's lots under one refund, from the invoice's
-- Audit Log: 'r' and the amount for each queued row it took credit off (with
-- the reverse of that row in the ledger, or a note that it is missing), 'd'
-- and the amount for the refund's own ledger rows.
create function pg_temp.t446_cpair(p_inv uuid, p_item uuid, p_req uuid) returns text language sql as $f$
  select coalesce(string_agg(x, ',' order by x collate "C"), '-') from (
    select 'r' || (a.new_data->>'refunded_amount')::numeric
             || case when exists (select 1 from customer_credit_ledger e
                                    join invoice_reopen_benefits q on q.id = (a.new_data->>'reopen_benefit_id')::uuid
                                   where e.entry_type = 'reverse' and e.source_type = 'invoice_reopen'
                                     and e.reverses_entry_id = q.source_ledger_id and e.source_record_id = q.request_id
                                     and e.lot_id = (a.new_data->>'lot_id')::uuid and e.amount = (a.new_data->>'refunded_amount')::numeric
                                     and e.reason = 'Reopened invoice: refunded before it was settled')
                     then '' else '(no reverse)' end as x
      from audit_logs a
     where a.record_id = p_inv and a.table_name = 'invoices' and a.action = 'reopen_credit_refunded'
       and (a.new_data->>'request_id')::uuid = p_req
       and (a.new_data->>'lot_id')::uuid in (select b.lot_id from invoice_benefit_values b where b.invoice_item_id = p_item)
    union all
    select 'd' || e.amount from customer_credit_ledger e
     where e.entry_type = 'adjust_decrease' and e.source_type = 'invoice_benefit_refund' and e.source_record_id = p_req
       and e.lot_id in (select b.lot_id from invoice_benefit_values b where b.invoice_item_id = p_item)) s $f$;
-- Everything a refund can touch on an invoice, with no ids, for comparing the
-- same steps run before and after 446.
create function pg_temp.t446_outcome(p_inv uuid, p_stock0 int) returns jsonb language sql as $f$
  select jsonb_build_object(
    'status', i.status, 'total', i.total_amount, 'paid_amount', i.paid_amount, 'owed', i.cancel_refund_owed,
    'net', invoice_net_received(i.id), 'charge', invoice_charge_total(i.id), 'stock_out', p_stock0 - pg_temp.t446_stock(),
    'benefits', (select jsonb_agg(x order by x::text) from (
        select jsonb_build_object('line_qty', it.quantity, 'granted', b.granted_value, 'paid', b.paid_value,
                 'cuv', b.cancelled_unused_value, 'voucher', v.status, 'qty', v.quantity, 'source', v.source_type,
                 'buyer_holds', v.customer_id = i.customer_id or l.customer_id = i.customer_id, 'lot', l.remaining_amount,
                 'queued', (select coalesce(jsonb_agg(jsonb_build_object('q', q.quantity, 'applied', q.applied_at is not null)
                                                      order by q.quantity, q.applied_at is not null), '[]'::jsonb)
                              from invoice_reopen_vouchers q where q.benefit_id = b.id),
                 'cqueued', (select coalesce(jsonb_agg(jsonb_build_object('a', q.amount, 'applied', q.applied_at is not null)
                                                       order by q.amount, q.applied_at is not null), '[]'::jsonb)
                               from invoice_reopen_benefits q join customer_credit_ledger e on e.id = q.source_ledger_id
                              where e.lot_id = b.lot_id),
                 'ledger', (select coalesce(jsonb_agg(e.entry_type || ':' || e.source_type || ':' || e.amount order by e.entry_seq), '[]'::jsonb)
                              from customer_credit_ledger e where e.lot_id = b.lot_id)) as x
          from invoice_benefit_values b join invoice_items it on it.id = b.invoice_item_id
          left join customer_reward_vouchers v on v.id = b.reward_voucher_id
          left join customer_credit_lots l on l.id = b.lot_id
         where b.invoice_id = i.id) s),
    'refunds', (select jsonb_agg(jsonb_build_object('amount', r.amount, 'kind', r.kind, 'credit', r.credit_returned,
                                                    'lines', jsonb_array_length(coalesce(r.outcome->'lines', '[]'::jsonb)))
                                 order by r.created_at, r.amount) from invoice_refunds r where r.invoice_id = i.id),
    'audit', (select jsonb_agg(a.action order by a.action) from audit_logs a
               where a.record_id = i.id
                  or a.record_id in (select bv.reward_voucher_id from invoice_benefit_values bv where bv.invoice_id = i.id)),
    'plans', jsonb_build_object(
       'cancel', case when i.status::text <> 'cancelled' then pg_temp.t446_codes(i.id, 'cancel') end,
       'refund_full', case when i.status::text in ('paid', 'partially_paid') then pg_temp.t446_codes(i.id, 'refund_full') end),
    'used', pg_temp.t446_used(i.id))
  from invoices i where i.id = p_inv $f$;
-- The controls: refunds made with nothing waiting. Run before and after 446.
create function pg_temp.t446_controls() returns jsonb language plpgsql as $f$
declare out jsonb := '{}'; inv uuid; s0 int; b uuid; a uuid;
begin
  -- C1 a paid sale of two plain vouchers, line A refunded (guided).
  s0 := pg_temp.t446_stock(); inv := pg_temp.t446_sale('v', 2, 1);
  perform pg_temp.t446_check(pg_temp.t446_refund_some(inv, pg_temp.t446_line(inv, 1), 1) = '-', 'C1 refund');
  out := out || jsonb_build_object('C1', pg_temp.t446_outcome(inv, s0));
  -- C2 a paid line of two limited vouchers, one unit refunded (guided).
  s0 := pg_temp.t446_stock(); inv := pg_temp.t446_sale('vl', 1, 2);
  perform pg_temp.t446_check(pg_temp.t446_refund_some(inv, pg_temp.t446_line(inv, 1), 1) = '-', 'C2 refund');
  out := out || jsonb_build_object('C2', pg_temp.t446_outcome(inv, s0));
  -- C3 two limited vouchers, cancelled, reopened straight to paid (the money
  -- was held), then line A refunded (guided).
  s0 := pg_temp.t446_stock(); inv := pg_temp.t446_sale('vl', 2, 1);
  perform cancel_invoice_recorded(inv, 'T446 C3', gen_random_uuid());
  perform reopen_invoice(inv, 'T446 C3', gen_random_uuid());
  perform pg_temp.t446_check(pg_temp.t446_refund_some(inv, pg_temp.t446_line(inv, 1), 1) = '-', 'C3 refund');
  out := out || jsonb_build_object('C3', pg_temp.t446_outcome(inv, s0));
  -- C4 two limited vouchers, cancelled (not reopened), line A refunded on the
  -- cancelled invoice (the units the cancellation took back; nothing waits).
  s0 := pg_temp.t446_stock(); inv := pg_temp.t446_sale('vl', 2, 1);
  perform cancel_invoice_recorded(inv, 'T446 C4', gen_random_uuid());
  a := pg_temp.t446_line(inv, 1);
  select id into b from invoice_benefit_values where invoice_item_id = a;
  perform refund_invoice_recorded(inv, jsonb_build_array(jsonb_build_object('invoice_item_id', a, 'amount', 30,
      'benefits', jsonb_build_array(jsonb_build_object('benefit_id', b, 'amount', 30)))),
    jsonb_build_array(jsonb_build_object('payment_id', (select id from invoice_payments where invoice_id = inv order by created_at limit 1), 'amount', 30)),
    '[]', 'T446 C4', gen_random_uuid());
  out := out || jsonb_build_object('C4', pg_temp.t446_outcome(inv, s0));
  -- C5 a S$100 Credit Package, paid, refunded by line (guided; the credit branch).
  s0 := pg_temp.t446_stock();
  inv := create_invoice(pg_temp.t446_id('store'), pg_temp.t446_id('buyer'), null,
    jsonb_build_array(jsonb_build_object('kind', 'credit_package', 'credit_package_id', pg_temp.t446_id('cp'), 'quantity', 1)));
  perform pg_temp.t446_pay(inv, 100);
  perform pg_temp.t446_check(pg_temp.t446_refund_some(inv, pg_temp.t446_line(inv, 1), 1) = '-', 'C5 refund');
  out := out || jsonb_build_object('C5', pg_temp.t446_outcome(inv, s0));
  -- C6 two limited vouchers, cancelled, S$30 paid back, reopened (waiting),
  -- settled, then line A refunded (guided): the normal path once settled.
  s0 := pg_temp.t446_stock(); inv := pg_temp.t446_waiting('vl', array[1, 1]);
  perform pg_temp.t446_pay(inv);
  perform pg_temp.t446_check(pg_temp.t446_refund_some(inv, pg_temp.t446_line(inv, 1), 1) = '-', 'C6 refund');
  out := out || jsonb_build_object('C6', pg_temp.t446_outcome(inv, s0));
  -- C7 two S$100 Credit Packages with a S$10 Bonus, cancelled (not
  -- reopened), line A refunded on the cancelled invoice (the credit the
  -- cancellation took back; nothing waits).
  s0 := pg_temp.t446_stock(); inv := pg_temp.t446_csale(array['cpb', 'cpb']);
  perform cancel_invoice_recorded(inv, 'T446 C7', gen_random_uuid());
  perform pg_temp.t446_check(pg_temp.t446_cline_back(inv, pg_temp.t446_line(inv, 1)) = 'recorded', 'C7 refund');
  out := out || jsonb_build_object('C7', pg_temp.t446_outcome(inv, s0));
  -- C8 the same, line B paid back, reopened (waiting), settled, then line A
  -- refunded (guided): the normal path once settled.
  s0 := pg_temp.t446_stock(); inv := pg_temp.t446_cwaiting(array['cpb', 'cpb']);
  perform pg_temp.t446_cpay(inv);
  perform pg_temp.t446_check(pg_temp.t446_refund_some(inv, pg_temp.t446_line(inv, 1), 1) = '-', 'C8 refund');
  out := out || jsonb_build_object('C8', pg_temp.t446_outcome(inv, s0));
  -- C9 two Premium Bundles, cancelled, reopened straight to paid (the money
  -- was held), then line A refunded (guided).
  s0 := pg_temp.t446_stock(); inv := pg_temp.t446_csale(array['pbb', 'pbb']);
  perform cancel_invoice_recorded(inv, 'T446 C9', gen_random_uuid());
  perform pg_temp.t446_creopen(inv);
  perform pg_temp.t446_check(pg_temp.t446_refund_some(inv, pg_temp.t446_line(inv, 1), 1) = '-', 'C9 refund');
  out := out || jsonb_build_object('C9', pg_temp.t446_outcome(inv, s0));
  return out;
end $f$;

-- ===== R. The fault, without 446 (undone) =====
do $$
declare inv uuid; s0 int; r1 text; r2 text; r3 text;
begin
  if pg_temp.t446_in() then
    raise notice 'NOTE R: 446 was in before this suite started, so the fault is not reproduced here; every figure after 446 is still checked';
    return;
  end if;
  begin
    s0 := pg_temp.t446_stock();
    inv := pg_temp.t446_waiting('vl', array[1, 1]);
    perform pg_temp.t446_check(pg_temp.t446_refund_some(inv, pg_temp.t446_line(inv, 1), 1) = '-', 'R refund A');
    perform pg_temp.t446_pay(inv);
    r1 := pg_temp.t446_money(inv) || ' stock out ' || (s0 - pg_temp.t446_stock());
    perform cancel_invoice_recorded(inv, 'T446 R cancel 2', gen_random_uuid());
    perform reopen_invoice(inv, 'T446 R reopen 2', gen_random_uuid());
    perform pg_temp.t446_pay(inv);
    r2 := pg_temp.t446_money(inv);
    inv := pg_temp.t446_waiting('v', array[2]);
    perform pg_temp.t446_check(pg_temp.t446_refund_some(inv, pg_temp.t446_line(inv, 1), 1) = '-', 'R refund 1 of 2');
    perform pg_temp.t446_pay(inv);
    r3 := pg_temp.t446_money(inv);
    raise exception using errcode = 'P0991', message = 'T446 R undone';
  exception when sqlstate 'P0991' then null;
  end;
  perform pg_temp.t446_check(r1 = 'paid net 30.00 held 2 waiting 0 stock out 2',
    'R two lines, line A refunded while waiting, settled: ' || r1 || ' (the fault is gone without 446? look again)');
  perform pg_temp.t446_check(r2 = 'paid net 60.00 held 3 waiting 0', 'R cancelled again, reopened and paid: ' || r2);
  perform pg_temp.t446_check(r3 = 'paid net 30.00 held 2 waiting 0', 'R a line of two, one unit refunded while waiting, settled: ' || r3);
  raise notice 'PASS R: without 446 (undone): line A refunded while waiting, then paid: %; cancelled again, reopened and paid: %; a line of two with one unit refunded: %',
    r1, r2, r3;
end $$;

-- ===== R (credit). The fault, without 446 (undone) =====
do $$
declare inv uuid; k text; res text[] := '{}';
begin
  if pg_temp.t446_in() then
    raise notice 'NOTE R (credit): 446 was in before this suite started, so the fault is not reproduced here; every figure after 446 is still checked';
    return;
  end if;
  begin
    foreach k in array array['cp', 'cpb', 'pbb'] loop
      inv := pg_temp.t446_cwaiting(array[k, k]);
      perform pg_temp.t446_check(pg_temp.t446_refund_some(inv, pg_temp.t446_line(inv, 1), 1) = '-', 'R credit: the guided refund of line A ' || k);
      perform pg_temp.t446_cpay(inv);
      res := res || pg_temp.t446_cmoney(inv);
    end loop;
    inv := pg_temp.t446_cwaiting(array['cp', 'cp']);
    perform pg_temp.t446_check(pg_temp.t446_cline_back(inv, pg_temp.t446_line(inv, 1), 40) = 'recorded', 'R credit: S$40 of line A');
    perform pg_temp.t446_cpay(inv);
    res := res || pg_temp.t446_cmoney(inv);
    raise exception using errcode = 'P0992', message = 'T446 R credit undone';
  exception when sqlstate 'P0992' then null;
  end;
  perform pg_temp.t446_check(res = array['paid net 100.00 credit 200.00 waiting 0.00', 'paid net 100.00 credit 220.00 waiting 0.00',
                                         'paid net 100.00 credit 240.00 waiting 0.00', 'paid net 160.00 credit 200.00 waiting 0.00'],
    'R credit refunded while waiting, then settled: ' || array_to_string(res, ' / ') || ' (the fault is gone without 446? look again)');
  raise notice 'PASS R (credit): without 446 (undone): line A refunded while the credit waited, then paid: % (Credit Package), % (with a S$10 Bonus), % (Premium Bundle, S$20 Bonus); S$40 of line A refunded: %',
    res[1], res[2], res[3], res[4];
end $$;

-- ===== 0. Controls before 446 =====
do $$
declare o jsonb;
begin
  insert into t446_fp values ('start', pg_temp.t446_fingerprint());
  if pg_temp.t446_in() then
    raise notice 'NOTE 0: 446 was in before this suite started, so the before/after comparison is skipped; the controls are still checked after it';
    return;
  end if;
  o := pg_temp.t446_controls();
  insert into t446_ctl(k, before) select k, v from jsonb_each(o) x(k, v);
end $$;

-- ===== 9. The refusal (before 446 is installed) =====
\if :{?nomig}
do $$ begin raise notice 'NOTE 9: -v nomig=1 (446 in), so its refusal on a database in the faulty state is not tried'; end $$;
\else
savepoint t446_refusal;
do $$
declare inv uuid;
begin
  -- One invoice still waiting after line A was refunded, one settled since.
  inv := pg_temp.t446_waiting('v', array[1, 1]);
  perform pg_temp.t446_refund_some(inv, pg_temp.t446_line(inv, 1), 1);
  insert into t446 values ('F1', inv);
  inv := pg_temp.t446_waiting('v', array[1, 1]);
  perform pg_temp.t446_refund_some(inv, pg_temp.t446_line(inv, 1), 1);
  perform pg_temp.t446_pay(inv);
  insert into t446 values ('F2', inv);
end $$;
select string_agg(invoice_no, ', ' order by invoice_no) as t446_faulty from invoices
 where id in (pg_temp.t446_id('F1'), pg_temp.t446_id('F2')) \gset
\set ON_ERROR_STOP 0
\ir ../../../supabase/446_line_refund_takes_waiting_reopen_voucher.sql
\set ON_ERROR_STOP 1
rollback to savepoint t446_refusal;
select pg_temp.t446_check(:'LAST_ERROR_MESSAGE' = '446: 2 invoice(s) had a voucher line refunded while their reopened vouchers waited ('
         || :'t446_faulty' || '): the refunded units were, or will be, given again. Decide what each customer should hold, then apply. Nothing was changed.',
       '9 446 on a database in the faulty state: ' || :'LAST_ERROR_MESSAGE') as t446_9_refused \gset
do $$
begin
  perform pg_temp.t446_check(pg_temp.t446_fingerprint() = (select fp from t446_fp where k = 'start') and not pg_temp.t446_in(),
    '9 the refused 446 changed functions');
  raise notice 'PASS 9: on a database where a line was refunded while vouchers waited (one still waiting, one settled since), 446 refuses, names both invoices and changes nothing';
end $$;
\endif

-- ===== 9b. The refusal for credit (before 446 is installed) =====
\if :{?nomig}
do $$ begin raise notice 'NOTE 9b: -v nomig=1 (446 in), so its refusal on a database in the faulty state is not tried'; end $$;
\else
savepoint t446_crefusal;
do $$
declare inv uuid;
begin
  -- Faulty: line A refunded while the credit waited; one still waiting, one
  -- settled since.
  inv := pg_temp.t446_cwaiting(array['cp', 'cp']);
  perform pg_temp.t446_check(pg_temp.t446_refund_some(inv, pg_temp.t446_line(inv, 1), 1) = '-', '9b F3 refund');
  insert into t446 values ('F3', inv);
  inv := pg_temp.t446_cwaiting(array['cpb', 'cpb']);
  perform pg_temp.t446_check(pg_temp.t446_refund_some(inv, pg_temp.t446_line(inv, 1), 1) = '-', '9b F4 refund');
  perform pg_temp.t446_cpay(inv);
  insert into t446 values ('F4', inv);
  -- Not faulty: a line paid back before its reopening, its credit still
  -- waiting; a line refunded once the reopened invoice was settled.
  inv := pg_temp.t446_cwaiting(array['cp', 'cp']);
  insert into t446 values ('N1', inv);
  inv := pg_temp.t446_cwaiting(array['cp', 'cp']);
  perform pg_temp.t446_cpay(inv);
  perform pg_temp.t446_check(pg_temp.t446_refund_some(inv, pg_temp.t446_line(inv, 1), 1) = '-', '9b N2 refund');
  insert into t446 values ('N2', inv);
end $$;
select string_agg(invoice_no, ', ' order by invoice_no) as t446_cfaulty from invoices
 where id in (pg_temp.t446_id('F3'), pg_temp.t446_id('F4')) \gset
\set ON_ERROR_STOP 0
\ir ../../../supabase/446_line_refund_takes_waiting_reopen_voucher.sql
\set ON_ERROR_STOP 1
rollback to savepoint t446_crefusal;
select pg_temp.t446_check(:'LAST_ERROR_MESSAGE' = '446: 2 invoice(s) had a credit line refunded while their reopened credit waited ('
         || :'t446_cfaulty' || '): the refunded credit was, or will be, reinstated. Decide what each customer should hold, then apply. Nothing was changed.',
       '9b 446 on a database in the faulty state: ' || :'LAST_ERROR_MESSAGE') as t446_9b_refused \gset
do $$
begin
  perform pg_temp.t446_check(pg_temp.t446_fingerprint() = (select fp from t446_fp where k = 'start') and not pg_temp.t446_in(),
    '9b the refused 446 changed functions');
  raise notice 'PASS 9b: on a database where a credit line was refunded while its credit waited (one still waiting, one settled since), 446 refuses, names those two only (not a line paid back before its reopening, nor one refunded once settled) and changes nothing';
end $$;
\endif

-- ===== Install 446, twice =====
\if :{?nomig}
do $$ begin perform pg_temp.t446_check(pg_temp.t446_in(), '10 -v nomig=1 but 446 is not in'); end $$;
\else
\ir ../../../supabase/446_line_refund_takes_waiting_reopen_voucher.sql
do $$ begin insert into t446_fp values ('first', pg_temp.t446_fingerprint()); end $$;
\ir ../../../supabase/446_line_refund_takes_waiting_reopen_voucher.sql
do $$ begin insert into t446_fp values ('second', pg_temp.t446_fingerprint()); end $$;
\endif
do $$
declare s text := 'public.refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid)';
begin
  perform pg_temp.t446_check(pg_temp.t446_in()
    and md5(pg_get_functiondef(s::regprocedure)) = '804ecd829cfecf713783a09a05d93c7e', '10 446 is not installed as tested');
  if exists (select 1 from t446_fp where k = 'first') then
    perform pg_temp.t446_check((select fp from t446_fp where k = 'second') = (select fp from t446_fp where k = 'first'),
      '10 the second run of 446 changed functions');
    perform pg_temp.t446_check(split_part((select fp from t446_fp where k = 'first'), ' ', 2) = split_part((select fp from t446_fp where k = 'start'), ' ', 2),
      '10 446 changed the number of functions');
  end if;
  perform pg_temp.t446_check((select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'refund_invoice_recorded') = 1,
    '10 an overload exists');
  perform pg_temp.t446_check(has_function_privilege('service_role', s, 'execute') and has_function_privilege('authenticated', s, 'execute')
    and not has_function_privilege('anon', s, 'execute'), '10 the grants of refund_invoice_recorded changed');
  raise notice 'PASS 10: 446 installed (%); %; no overload; refund_invoice_recorded is for signed-in staff and the service role, not anon',
    md5(pg_get_functiondef(s::regprocedure)),
    coalesce('the second run changed nothing (' || (select fp from t446_fp where k = 'second') || ')', 'it was in before the suite (nomig)');
end $$;

-- ===== 1. Two lines of one, line A refunded while waiting =====
do $$
declare inv uuid; s0 int; a uuid; vk text; ba uuid; n int;
begin
  foreach vk in array array['v', 'vl'] loop
    s0 := pg_temp.t446_stock();
    inv := pg_temp.t446_waiting(vk, array[1, 1]);
    a := pg_temp.t446_line(inv, 1);
    select id into ba from invoice_benefit_values where invoice_item_id = a;
    perform pg_temp.t446_check(pg_temp.t446_refund_some(inv, a, 1) = '-', '1 the guided refund of line A');
    perform pg_temp.t446_check(not exists (select 1 from invoice_reopen_vouchers where benefit_id = ba)
      and pg_temp.t446_waiting_units(inv) = 1
      and (select cancelled_unused_value from invoice_benefit_values where id = ba) = 0,
      '1 ' || vk || ' line A''s unit was not taken off the queue: ' || pg_temp.t446_money(inv));
    select count(*) into n from audit_logs where table_name = 'invoices' and record_id = inv and action = 'reopen_voucher_refunded'
       and new_data->>'benefit_id' = ba::text and (new_data->>'refunded_units')::int = 1 and (new_data->>'still_waiting')::int = 0
       and (old_data->>'quantity')::int = 1 and old_data->>'applied_at' is null;
    perform pg_temp.t446_check(n = 1, '1 the Audit Log has ' || n || ' reopen_voucher_refunded rows for line A');
    perform pg_temp.t446_pay(inv);
    perform pg_temp.t446_check(pg_temp.t446_money(inv) = 'paid net 30.00 held 1 waiting 0'
      and pg_temp.t446_held(inv, a) = 0 and pg_temp.t446_held(inv, pg_temp.t446_line(inv, 2)) = 1,
      '1 ' || vk || ' settled: ' || pg_temp.t446_money(inv));
    perform pg_temp.t446_check(vk = 'v' or s0 - pg_temp.t446_stock() = 1, '1 stock out after settling: ' || (s0 - pg_temp.t446_stock()));
    -- Cancelled again, reopened, paid: the refund is counted once.
    perform cancel_invoice_recorded(inv, 'T446 1 cancel 2', gen_random_uuid());
    perform pg_temp.t446_check(vk = 'v' or s0 = pg_temp.t446_stock(), '1 stock after the second cancel: ' || (s0 - pg_temp.t446_stock()));
    perform reopen_invoice(inv, 'T446 1 reopen 2', gen_random_uuid());
    perform pg_temp.t446_check((select status::text from invoices where id = inv) = 'partially_paid' and invoice_charge_total(inv) = 60
      and pg_temp.t446_waiting_units(inv) = 2, '1 ' || vk || ' reopened again: ' || pg_temp.t446_money(inv));
    perform pg_temp.t446_pay(inv);
    perform pg_temp.t446_check(pg_temp.t446_money(inv) = 'paid net 60.00 held 2 waiting 0'
      and pg_temp.t446_held(inv, a) = 1, '1 ' || vk || ' paid again: ' || pg_temp.t446_money(inv));
    perform pg_temp.t446_check(vk = 'v' or s0 - pg_temp.t446_stock() = 2, '1 stock out paid again: ' || (s0 - pg_temp.t446_stock()));
    perform cancel_invoice_recorded(inv, 'T446 1 cancel 3', gen_random_uuid());
    perform pg_temp.t446_check(pg_temp.t446_held(inv) = 0 and (vk = 'v' or s0 = pg_temp.t446_stock()),
      '1 cancelled a third time: held ' || pg_temp.t446_held(inv) || ', stock out ' || (s0 - pg_temp.t446_stock()));
  end loop;
  raise notice 'PASS 1: two lines of one (plain and limited), line A refunded while waiting: its queued row removed (Audit Log), B''s waits; paid: line B''s voucher alone for S$30, 1 unit of stock out; cancelled, reopened and paid again: 2 held for S$60 (the refund counted once); stock back on each cancel';
end $$;

-- ===== 2. A line of two =====
do $$
declare inv uuid; a uuid; ba uuid; q uuid; s0 int;
begin
  -- One unit of a line of two refunded while waiting: the row is lowered.
  s0 := pg_temp.t446_stock();
  inv := pg_temp.t446_waiting('vl', array[2]);
  a := pg_temp.t446_line(inv, 1);
  select id into ba from invoice_benefit_values where invoice_item_id = a;
  select id into q from invoice_reopen_vouchers where benefit_id = ba and applied_at is null and quantity = 2;
  perform pg_temp.t446_check(pg_temp.t446_refund_some(inv, a, 1) = '-', '2 the guided refund of one unit');
  perform pg_temp.t446_check((select string_agg(id::text || ':' || quantity, ',') from invoice_reopen_vouchers where invoice_id = inv) = q::text || ':1'
    and (select cancelled_unused_value from invoice_benefit_values where id = ba) = 1, '2 the queued row of two was not lowered to one');
  perform pg_temp.t446_check(exists (select 1 from audit_logs where record_id = inv and action = 'reopen_voucher_refunded'
    and new_data->>'reopen_voucher_id' = q::text and (new_data->>'still_waiting')::int = 1), '2 no Audit Log row for the lowered row');
  perform pg_temp.t446_pay(inv);
  perform pg_temp.t446_check(pg_temp.t446_money(inv) = 'paid net 30.00 held 1 waiting 0' and s0 - pg_temp.t446_stock() = 1,
    '2 settled: ' || pg_temp.t446_money(inv) || ', stock out ' || (s0 - pg_temp.t446_stock()));
  -- A line of two and a line of one (S$90, S$30 paid back), the line of two
  -- refunded whole while waiting: its row is removed.
  s0 := pg_temp.t446_stock();
  inv := pg_temp.t446_waiting('vl', array[2, 1]);
  a := pg_temp.t446_line_of(inv, 2);
  perform pg_temp.t446_check(pg_temp.t446_refund_some(inv, a, 2) = '-', '2 the guided refund of the line of two');
  perform pg_temp.t446_check(pg_temp.t446_waiting_units(inv) = 1
    and not exists (select 1 from invoice_reopen_vouchers q join invoice_benefit_values b on b.id = q.benefit_id where b.invoice_item_id = a),
    '2 the line of two refunded whole: ' || pg_temp.t446_money(inv));
  perform pg_temp.t446_pay(inv);
  perform pg_temp.t446_check(pg_temp.t446_money(inv) = 'paid net 30.00 held 1 waiting 0' and pg_temp.t446_held(inv, a) = 0
    and s0 - pg_temp.t446_stock() = 1, '2 the line of two refunded whole, settled: ' || pg_temp.t446_money(inv));
  raise notice 'PASS 2: a line of two with one unit refunded while waiting: its queued row lowered to one (Audit Log); paid: 1 held for S$30. A line of two refunded whole while waiting: its row removed; paid: the line of one''s voucher alone';
end $$;

-- ===== 3. Refunded while waiting, cancelled before settling, reopened =====
do $$
declare inv uuid; s0 int;
begin
  s0 := pg_temp.t446_stock();
  inv := pg_temp.t446_waiting('vl', array[1, 1]);
  perform pg_temp.t446_check(pg_temp.t446_refund_some(inv, pg_temp.t446_line(inv, 1), 1) = '-', '3 refund');
  perform cancel_invoice_recorded(inv, 'T446 3 cancel 2', gen_random_uuid());
  perform reopen_invoice(inv, 'T446 3 reopen 2', gen_random_uuid());
  perform pg_temp.t446_check(pg_temp.t446_waiting_units(inv) = 2 and invoice_charge_total(inv) = 60,
    '3 reopened again: ' || pg_temp.t446_money(inv));
  perform pg_temp.t446_pay(inv);
  perform pg_temp.t446_check(pg_temp.t446_money(inv) = 'paid net 60.00 held 2 waiting 0' and s0 - pg_temp.t446_stock() = 2,
    '3 settled: ' || pg_temp.t446_money(inv) || ', stock out ' || (s0 - pg_temp.t446_stock()));
  raise notice 'PASS 3: refunded while waiting, cancelled before settling, reopened: 2 wait (the refund counted once); paid: 2 held for S$60';
end $$;

-- ===== 4. The FOC taken off (416), paid, cancelled, reopened, refunded while waiting =====
do $$
declare inv uuid; x jsonb; s0 int;
begin
  s0 := pg_temp.t446_stock();
  inv := create_invoice(pg_temp.t446_id('store'), pg_temp.t446_id('buyer'), null, jsonb_build_array(
    jsonb_build_object('kind', 'voucher', 'voucher_id', pg_temp.t446_id('vl'), 'quantity', 1, 'foc_quantity', 1, 'foc_reason', 'T446 goodwill'),
    jsonb_build_object('kind', 'voucher', 'voucher_id', pg_temp.t446_id('vl'), 'quantity', 1, 'foc_quantity', 1, 'foc_reason', 'T446 goodwill')));
  perform confirm_foc_invoice(inv, 'T446 FOC');
  select jsonb_agg(jsonb_build_object('invoice_item_id', it.id, 'kind', 'voucher', 'voucher_id', it.voucher_id,
           'quantity', 1, 'unit_price', 30, 'foc_quantity', 0)) into x
    from invoice_items it where it.invoice_id = inv;
  perform correct_invoice(inv, x, jsonb_build_object('expected_edit_count', (select edit_count from invoices where id = inv)),
    'T446 FOC off', gen_random_uuid());
  perform pg_temp.t446_pay(inv, 60);
  perform pg_temp.t446_check(pg_temp.t446_money(inv) = 'paid net 60.00 held 2 waiting 0'
    and (select sum(quantity) from invoice_reopen_vouchers where invoice_id = inv and applied_at is not null) = 2,
    '4 the FOC taken off and paid: 416 did not give both again: ' || pg_temp.t446_money(inv));
  perform cancel_invoice_recorded(inv, 'T446 4 cancel', gen_random_uuid());
  perform pg_temp.t446_check(pg_temp.t446_record_refund(inv, 30) = 'recorded', '4 S$30 paid back');
  perform reopen_invoice(inv, 'T446 4 reopen', gen_random_uuid());
  perform pg_temp.t446_check(pg_temp.t446_waiting_units(inv) = 2, '4 reopened: ' || pg_temp.t446_money(inv));
  perform pg_temp.t446_check(pg_temp.t446_refund_some(inv, pg_temp.t446_line(inv, 1), 1) = '-', '4 refund');
  perform pg_temp.t446_check(pg_temp.t446_waiting_units(inv) = 1, '4 after the refund: ' || pg_temp.t446_money(inv));
  perform pg_temp.t446_pay(inv);
  perform pg_temp.t446_check(pg_temp.t446_money(inv) = 'paid net 30.00 held 1 waiting 0'
    and pg_temp.t446_held(inv, pg_temp.t446_line(inv, 1)) = 0 and s0 - pg_temp.t446_stock() = 1,
    '4 settled: ' || pg_temp.t446_money(inv) || ', stock out ' || (s0 - pg_temp.t446_stock()));
  raise notice 'PASS 4: an FOC taken off and paid (416 gave both again), cancelled, reopened, line A refunded while waiting: paid, line B''s voucher alone for S$30, 1 unit of stock out';
end $$;

-- ===== 5. Move =====
do $$
declare inv uuid; msg text; s0 int;
begin
  s0 := pg_temp.t446_stock();
  inv := pg_temp.t446_waiting('vl', array[1, 1]);
  begin
    perform transfer_invoice_unused_benefit((select id from invoice_benefit_values where invoice_item_id = pg_temp.t446_line(inv, 2)),
      pg_temp.t446_id('friend'), pg_temp.t446_id('store'), 'T446 5 move', gen_random_uuid());
    msg := 'moved';
  exception when others then msg := sqlerrm;
  end;
  perform pg_temp.t446_check(msg = 'Settle the reopened invoice before moving its reinstated benefits', '5 a Move while waiting: ' || msg);
  perform pg_temp.t446_check(pg_temp.t446_refund_some(inv, pg_temp.t446_line(inv, 1), 1) = '-', '5 refund');
  perform pg_temp.t446_pay(inv);
  perform transfer_invoice_unused_benefit((select b.id from invoice_benefit_values b join customer_reward_vouchers v on v.id = b.reward_voucher_id
      where b.invoice_id = inv and v.status = 'held'), pg_temp.t446_id('friend'), pg_temp.t446_id('store'), 'T446 5 move', gen_random_uuid());
  perform pg_temp.t446_check((select coalesce(sum(quantity), 0) from customer_reward_vouchers
                               where customer_id = pg_temp.t446_id('friend') and status = 'held'
                                 and id in (select reward_voucher_id from invoice_benefit_values where invoice_id = inv)) = 1
    and pg_temp.t446_held(inv) = 1, '5 after the Move: ' || pg_temp.t446_money(inv));
  perform cancel_invoice_recorded(inv, 'T446 5 cancel', gen_random_uuid());
  perform pg_temp.t446_check(pg_temp.t446_held(inv) = 0 and s0 = pg_temp.t446_stock(),
    '5 cancelled: held ' || pg_temp.t446_held(inv) || ', stock out ' || (s0 - pg_temp.t446_stock()));
  raise notice 'PASS 5: a Move is refused while vouchers wait (as before); after the refund and the payment, line B''s voucher moved to a friend; cancelled, it is taken back from the friend and the stock is back';
end $$;

-- ===== 6. 438's counting =====
do $$
declare inv uuid; codes text; msg text;
begin
  -- Reopened and settled with no refund: no override (438).
  inv := pg_temp.t446_waiting('v', array[1, 1]);
  perform pg_temp.t446_pay(inv);
  perform pg_temp.t446_check(pg_temp.t446_codes(inv, 'refund_full') = '-' and pg_temp.t446_codes(inv, 'cancel') = '-',
    '6 a reopened invoice settled with no refund asks ' || pg_temp.t446_codes(inv, 'refund_full') || ' / ' || pg_temp.t446_codes(inv, 'cancel'));
  perform cancel_invoice_recorded(inv, 'T446 6 cancel', gen_random_uuid());
  perform pg_temp.t446_check(pg_temp.t446_used(inv) = '-', '6 cancelled, it reads ' || pg_temp.t446_used(inv));
  -- Refunded while waiting, settled: the guided Refund in full.
  inv := pg_temp.t446_waiting('v', array[1, 1]);
  perform pg_temp.t446_refund_some(inv, pg_temp.t446_line(inv, 1), 1);
  perform pg_temp.t446_pay(inv);
  insert into t446 values ('U', inv);
  insert into t446_known values ('U refund_full', pg_temp.t446_codes(inv, 'refund_full')), ('U cancel', pg_temp.t446_codes(inv, 'cancel'));
  codes := pg_temp.t446_guided(inv, 'refund_full', null, '[]', true);
  perform pg_temp.t446_check(codes = '-', '6 Refund in full asked ' || codes);
  perform pg_temp.t446_check(pg_temp.t446_money(inv) = 'refunded net 0.00 held 0 waiting 0', '6 refunded in full: ' || pg_temp.t446_money(inv));
  -- The same, the guided Cancel stating S$30 owed, then "Record refund paid".
  inv := pg_temp.t446_waiting('v', array[1, 1]);
  perform pg_temp.t446_refund_some(inv, pg_temp.t446_line(inv, 1), 1);
  perform pg_temp.t446_pay(inv);
  codes := pg_temp.t446_guided(inv, 'cancel', 30);
  -- (448 in: nothing is asked, so no amount owed is kept.)
  perform pg_temp.t446_check((select status::text from invoices where id = inv) = 'cancelled'
    and (select cancel_refund_owed from invoices where id = inv) is not distinct from case when pg_temp.t448_in() then null else 30 end
    and codes = case when pg_temp.t448_in() then '-' else 'voucher_redeemed' end, '6 the guided Cancel (asked ' || codes || ')');
  -- (Recorded first, in a statement of its own: the reads below are STABLE
  -- and would otherwise see the invoice as it was when the statement began.)
  msg := pg_temp.t446_record_refund(inv, 30);
  perform pg_temp.t446_check(msg = 'recorded'
    and (invoice_financial_position(inv)->>'refund_due')::numeric = 0 and pg_temp.t446_held(inv) = 0,
    '6 the S$30 owed was not recorded (' || msg || '): ' || pg_temp.t446_money(inv));
  insert into t446_known values ('U guided cancel', codes);
  raise notice 'PASS 6: a reopened invoice settled with no refund asks no override (438); refunded while waiting and settled: Refund in full asks none and pays back the S$30, taking line B''s voucher back; the guided Cancel stating S$30 owed lets it be recorded';
end $$;

-- ===== 7. The controls after 446 =====
do $$
declare o jsonb; r record; n int := 0;
begin
  o := pg_temp.t446_controls();
  if exists (select 1 from t446_ctl) then
    update t446_ctl c set after = o->c.k;
    for r in select * from t446_ctl order by k loop
      if r.after is distinct from r.before then
        raise exception 'FAIL 7 % differs with 446: before % after %', r.k, r.before, r.after; end if;
      n := n + 1;
    end loop;
  end if;
  -- The absolute figures, either way.
  perform pg_temp.t446_check(o->'C1'->>'status' = 'paid' and (o->'C1'->>'net')::numeric = 30
    and o->'C1'->'plans'->>'cancel' = case when pg_temp.t448_in() then '-' else 'voucher_redeemed' end,
    '7 C1 reads ' || (o->'C1')::text);
  perform pg_temp.t446_check((o->'C2'->>'stock_out')::int = 1 and (o->'C2'->>'net')::numeric = 30, '7 C2 reads ' || (o->'C2')::text);
  perform pg_temp.t446_check((o->'C3'->>'stock_out')::int = 1 and (o->'C3'->>'net')::numeric = 30, '7 C3 reads ' || (o->'C3')::text);
  perform pg_temp.t446_check((o->'C4'->>'stock_out')::int = 0 and (o->'C4'->>'net')::numeric = 30 and o->'C4'->>'status' = 'cancelled',
    '7 C4 reads ' || (o->'C4')::text);
  perform pg_temp.t446_check(o->'C5'->>'status' = 'refunded' and (o->'C5'->>'net')::numeric = 0, '7 C5 reads ' || (o->'C5')::text);
  perform pg_temp.t446_check((o->'C6'->>'stock_out')::int = 1 and (o->'C6'->>'net')::numeric = 30 and o->'C6'->>'status' = 'paid',
    '7 C6 reads ' || (o->'C6')::text);
  perform pg_temp.t446_check(o->'C7'->>'status' = 'cancelled' and (o->'C7'->>'net')::numeric = 100
    and (select sum((x->>'lot')::numeric) from jsonb_array_elements(o->'C7'->'benefits') x) = 0, '7 C7 reads ' || (o->'C7')::text);
  perform pg_temp.t446_check(o->'C8'->>'status' = 'paid' and (o->'C8'->>'net')::numeric = 100
    and (select sum((x->>'lot')::numeric) from jsonb_array_elements(o->'C8'->'benefits') x) = 110, '7 C8 reads ' || (o->'C8')::text);
  perform pg_temp.t446_check(o->'C9'->>'status' = 'paid' and (o->'C9'->>'net')::numeric = 100
    and (select sum((x->>'lot')::numeric) from jsonb_array_elements(o->'C9'->'benefits') x) = 120, '7 C9 reads ' || (o->'C9')::text);
  perform pg_temp.t446_check(not (o::text like '%reopen_voucher_refunded%'), '7 a refund with nothing waiting wrote a reopen_voucher_refunded row');
  perform pg_temp.t446_check(not (o::text like '%reopen_credit_refunded%'), '7 a credit refund with nothing waiting wrote a reopen_credit_refunded row');
  if n > 0 then
    raise notice 'PASS 7: % refunds made with nothing waiting (a paid sale, a line of two, a reopened invoice paid straight away, a cancelled one, a Credit Package, a reopened invoice once settled; credit: a cancelled invoice, a reopened invoice once settled, bundles reopened straight to paid) end exactly as before 446 (status, money, benefit rows, vouchers, lots and their ledger, both queues, stock, refunds, Audit Log, plans, used)', n;
  else
    raise notice 'PASS 7: (446 was in before the suite) the nine refunds made with nothing waiting end as checked';
  end if;
end $$;

-- ===== 8. KNOWN: not covered by 446 =====
do $$
declare inv uuid; msg text; x jsonb; b uuid; a uuid; codes text;
begin
  -- NOT COVERED 1 (438's NOT COVERED 2): a refunded unit reads as used.
  -- 448 (the Owner, 22 Oct 2026) fixes it: where 448 is in, checked as fixed.
  perform pg_temp.t446_check((select v from t446_known where k = 'U refund_full') = '-'
    and (select v from t446_known where k = 'U cancel') = case when pg_temp.t448_in() then '-' else 'voucher_redeemed' end
    and (select v from t446_known where k = 'U guided cancel') = case when pg_temp.t448_in() then '-' else 'voucher_redeemed' end,
    '8 a unit refunded while waiting, settled, now reads ' || (select string_agg(k || ': ' || v, ', ' order by k) from t446_known)
    || case when pg_temp.t448_in() then ' (448 in)' else ' (448 not in)' end
    || ': look at 446''s NOT COVERED 1 and this case again');
  inv := pg_temp.t446_waiting('v', array[2]);
  perform pg_temp.t446_refund_some(inv, pg_temp.t446_line(inv, 1), 1);
  perform pg_temp.t446_pay(inv);
  perform pg_temp.t446_check(pg_temp.t446_codes(inv, 'refund_full') = case when pg_temp.t448_in() then '-' else 'voucher_redeemed' end,
    '8 a line of two, one unit refunded while waiting, settled: Refund in full now asks ' || pg_temp.t446_codes(inv, 'refund_full')
    || ': look at 446''s NOT COVERED 1 and this case again');
  perform cancel_invoice_recorded(inv, 'T446 8 cancel', gen_random_uuid());
  msg := pg_temp.t446_record_refund(inv, 30);
  if pg_temp.t448_in() then
    perform pg_temp.t446_check(pg_temp.t446_used(inv) = '-' and msg = 'recorded'
      and (invoice_financial_position(inv)->>'refund_due')::numeric = 0,
      '8 (448 in) cancelled directly it reads ' || pg_temp.t446_used(inv) || ' and Record refund paid: ' || msg || ': look at 448 and this case again');
  else
    perform pg_temp.t446_check(pg_temp.t446_used(inv) = 'voucher_redeemed' and msg like 'Part of what % (vouchers redeemed)%',
      '8 cancelled directly it reads ' || pg_temp.t446_used(inv) || ' and Record refund paid: ' || msg || ': look at 446''s NOT COVERED 1 and this case again');
  end if;
  -- NOT COVERED 1, credit: a credit line refunded by line reads credit_used
  -- to Cancel, with nothing waiting (as before 446) and once refunded while
  -- waiting and settled; Refund in full asks nothing.
  inv := pg_temp.t446_csale(array['cp', 'cp']);
  perform pg_temp.t446_check(pg_temp.t446_refund_some(inv, pg_temp.t446_line(inv, 1), 1) = '-', '8 credit refund, nothing waiting');
  insert into t446_known values ('CN cancel', pg_temp.t446_codes(inv, 'cancel')), ('CN refund_full', pg_temp.t446_codes(inv, 'refund_full'));
  inv := pg_temp.t446_cwaiting(array['cp', 'cp']);
  perform pg_temp.t446_check(pg_temp.t446_refund_some(inv, pg_temp.t446_line(inv, 1), 1) = '-', '8 credit refund while waiting');
  perform pg_temp.t446_cpay(inv);
  insert into t446_known values ('CW cancel', pg_temp.t446_codes(inv, 'cancel')), ('CW refund_full', pg_temp.t446_codes(inv, 'refund_full'));
  codes := pg_temp.t446_guided(inv, 'cancel', 100, '[]', true);
  insert into t446_known values ('CW guided cancel', codes);
  perform pg_temp.t446_check(pg_temp.t446_cmoney(inv) = 'cancelled net 0.00 credit 0.00 waiting 0.00',
    '8 the guided Cancel stating S$100 owed (asked ' || codes || '): ' || pg_temp.t446_cmoney(inv));
  perform pg_temp.t446_check((select v from t446_known where k = 'CN cancel') = case when pg_temp.t448_in() then '-' else 'credit_used' end
    and (select v from t446_known where k = 'CN refund_full') = '-'
    and (select v from t446_known where k = 'CW cancel') = case when pg_temp.t448_in() then '-' else 'credit_used' end
    and (select v from t446_known where k = 'CW refund_full') = '-'
    and codes = case when pg_temp.t448_in() then '-' else 'credit_used' end,
    '8 a credit line refunded now reads ' || (select string_agg(k || ': ' || v, ', ' order by k) from t446_known where k like 'C%')
    || ': look at 446''s NOT COVERED 1 and this case again');
  -- NOT COVERED 2, credit: a line paid back on the cancelled invoice before
  -- the reopening (its credit waits) cannot be refunded while it waits.
  inv := pg_temp.t446_cwaiting(array['cp', 'cp']);
  msg := pg_temp.t446_refund_some(inv, pg_temp.t446_line(inv, 2), 1);
  perform pg_temp.t446_check(msg = 'ERR There is nothing left to refund on this invoice' and pg_temp.t446_cwait(inv) = 200,
    '8 refunding credit queued after an earlier refund took it now gives ' || msg || ': look at 446''s NOT COVERED 2 and this case again');
  -- NOT COVERED 2: a unit queued because an earlier line refund took it.
  inv := pg_temp.t446_sale('v', 2, 1);
  perform pg_temp.t446_check(pg_temp.t446_refund_some(inv, pg_temp.t446_line(inv, 1), 1) = '-', '8 refund before cancelling');
  perform cancel_invoice_recorded(inv, 'T446 8 cancel', gen_random_uuid());
  perform reopen_invoice(inv, 'T446 8 reopen', gen_random_uuid());
  perform pg_temp.t446_check(pg_temp.t446_waiting_units(inv) = 2 and (select status::text from invoices where id = inv) = 'partially_paid',
    '8 the earlier refund''s unit is not queued: ' || pg_temp.t446_money(inv));
  msg := pg_temp.t446_refund_some(inv, pg_temp.t446_line(inv, 1), 1);
  perform pg_temp.t446_check(msg = 'ERR There is nothing left to refund on this invoice' and pg_temp.t446_waiting_units(inv) = 2,
    '8 refunding a unit queued because an earlier refund took it now gives ' || msg || ': look at 446''s NOT COVERED 2 and this case again');
  -- NOT COVERED 3: the FOC taken off, not yet paid: no line refund.
  inv := create_invoice(pg_temp.t446_id('store'), pg_temp.t446_id('buyer'), null, jsonb_build_array(
    jsonb_build_object('kind', 'voucher', 'voucher_id', pg_temp.t446_id('vl'), 'quantity', 1, 'foc_quantity', 1, 'foc_reason', 'T446 goodwill'),
    jsonb_build_object('kind', 'voucher', 'voucher_id', pg_temp.t446_id('vl'), 'quantity', 1, 'foc_quantity', 1, 'foc_reason', 'T446 goodwill')));
  perform confirm_foc_invoice(inv, 'T446 FOC');
  select jsonb_agg(jsonb_build_object('invoice_item_id', it.id, 'kind', 'voucher', 'voucher_id', it.voucher_id,
           'quantity', 1, 'unit_price', 30, 'foc_quantity', 0)) into x from invoice_items it where it.invoice_id = inv;
  perform correct_invoice(inv, x, jsonb_build_object('expected_edit_count', (select edit_count from invoices where id = inv)), 'T446 FOC off', gen_random_uuid());
  perform pg_temp.t446_pay(inv, 30);
  msg := pg_temp.t446_refund_some(inv, pg_temp.t446_line(inv, 1), 1);
  perform pg_temp.t446_check(msg = 'ERR There is nothing left to refund on this invoice',
    '8 the FOC taken off, part-paid: a line refund now gives ' || msg || ': look at 446''s NOT COVERED 3 and this case again');
  -- NOT COVERED 4: a part-paid package never settled: its released credit is
  -- written off on cancelling, nothing waits, no line refund.
  inv := pg_temp.t446_csale(array['cpb', 'cpb'], 120);
  perform cancel_invoice_recorded(inv, 'T446 8 cancel', gen_random_uuid());
  perform pg_temp.t446_creopen(inv);
  msg := pg_temp.t446_refund_some(inv, pg_temp.t446_line(inv, 1), 1);
  perform pg_temp.t446_check((select status::text from invoices where id = inv) = 'partially_paid'
    and not exists (select 1 from invoice_reopen_benefits where invoice_id = inv)
    and not exists (select 1 from invoice_benefit_values where invoice_id = inv)
    and msg = 'ERR There is nothing left to refund on this invoice',
    '8 a part-paid package never settled, cancelled and reopened: a line refund now gives ' || msg || ': look at 446''s NOT COVERED 4 and this case again');
  if pg_temp.t448_in() then
    raise notice 'FIXED 8 by 448: (1) a unit refunded while waiting, settled: Refund in full asks %, Cancel asks %, the guided Cancel %; a line of two with one unit refunded: Refund in full asks nothing and, cancelled directly, Record refund paid records the S$30. The same for credit: a credit line refunded, with nothing waiting or while waiting, reads nothing used to Cancel',
      (select v from t446_known where k = 'U refund_full'), (select v from t446_known where k = 'U cancel'), (select v from t446_known where k = 'U guided cancel');
    raise notice 'KNOWN 8: (not covered by 446) (2) a unit, or credit, queued because an earlier line refund took it cannot be refunded while waiting. (3) an FOC taken off and not yet paid cannot be refunded by line. (4) a part-paid package never settled: nothing waits once cancelled and reopened, and no line refund';
  else
    raise notice 'KNOWN 8: (not covered by 446) (1) a unit refunded while waiting reads as used, as any refunded unit (438''s NOT COVERED 2): settled, Refund in full asks %, Cancel asks %, the guided Cancel %; a line of two with one unit refunded: Refund in full asks voucher_redeemed and, cancelled directly, Record refund paid is refused. The same for credit: a credit line refunded, with nothing waiting or while waiting, reads credit_used to Cancel (the guided Cancel stating the amount owed goes through), Refund in full asks nothing. (2) a unit, or credit, queued because an earlier line refund took it cannot be refunded while waiting. (3) an FOC taken off and not yet paid cannot be refunded by line. (4) a part-paid package never settled: nothing waits once cancelled and reopened, and no line refund',
      (select v from t446_known where k = 'U refund_full'), (select v from t446_known where k = 'U cancel'), (select v from t446_known where k = 'U guided cancel');
  end if;
end $$;

-- ===== 8b. KNOWN: a customer change after a line refund (446's NOT COVERED 5) =====
-- The invoice form's customer change, its lines as they are, the benefits
-- taken along ("Move the unused benefits to the new customer").
create function pg_temp.t446_change(p_inv uuid, p_cust uuid) returns jsonb language plpgsql as $f$
declare x jsonb;
begin
  select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('invoice_item_id', it.id, 'kind', it.line_kind,
           'credit_package_id', it.credit_package_id, 'premium_bundle_id', it.premium_bundle_id, 'voucher_id', it.voucher_id,
           'quantity', it.quantity, 'unit_price', it.unit_price, 'voucher_selection', it.bundle_voucher_selection)) order by it.id)
    into x from invoice_items it where it.invoice_id = p_inv;
  return correct_invoice(p_inv, x, jsonb_build_object('expected_edit_count', (select edit_count from invoices where id = p_inv),
    'customer_id', p_cust, 'store_id', pg_temp.t446_id('store'), 'benefit_action', 'transfer'), 'T446 wrong customer', gen_random_uuid());
end $f$;
-- The credit a line's lots hold for one customer ('buyer' / 'friend'); the
-- units of a line's vouchers one customer holds.
create function pg_temp.t446_credit_of(p_item uuid, p_k text) returns numeric language sql as $f$
  select round(coalesce(sum(l.remaining_amount), 0), 2) from invoice_benefit_values b join customer_credit_lots l on l.id = b.lot_id
   where b.invoice_item_id = p_item and l.customer_id = pg_temp.t446_id(p_k) $f$;
create function pg_temp.t446_held_by(p_item uuid, p_k text) returns int language sql as $f$
  select coalesce(sum(v.quantity), 0)::int from invoice_benefit_values b join customer_reward_vouchers v on v.id = b.reward_voucher_id
   where b.invoice_item_id = p_item and v.status = 'held' and v.customer_id = pg_temp.t446_id(p_k) $f$;
-- What waits for a line's lots, and whose lots they are.
create function pg_temp.t446_cwait_whose(p_inv uuid, p_item uuid) returns text language sql as $f$
  select coalesce(string_agg(distinct case l.customer_id when pg_temp.t446_id('buyer') then 'buyer' when pg_temp.t446_id('friend') then 'friend'
                                      else 'other' end || ':' || e.source_type, ','), '-')
    from invoice_reopen_benefits q join customer_credit_ledger e on e.id = q.source_ledger_id join customer_credit_lots l on l.id = e.lot_id
   where q.invoice_id = p_inv and q.applied_at is null
     and e.lot_id in (select b.lot_id from invoice_benefit_values b where b.invoice_item_id = p_item) $f$;
create function pg_temp.t446_whose(p_inv uuid) returns text language sql as $f$
  select case customer_id when pg_temp.t446_id('buyer') then 'buyer' when pg_temp.t446_id('friend') then 'friend' else 'other' end
           || ' ' || status::text || ' net ' || invoice_net_received(id)
    from invoices where id = p_inv $f$;
do $$
declare inv uuid; a uuid; b uuid; w text;
        -- 460 (where it is in) gives line A back to the friend, whom the
        -- benefits were moved to: checked the fixed way then.
        fx boolean := pg_temp.t460_in(); cb numeric; cf numeric; vb int; vf int; how text;
begin
  cb := case when fx then 0 else 110 end; cf := case when fx then 110 else 0 end;
  vb := case when fx then 0 else 1 end; vf := case when fx then 1 else 0 end;
  how := case when fx then ': 460 is in, so line A should be the friend''s' else ': look at 446''s NOT COVERED 5 and this case again' end;
  -- Credit: line A refunded on the paid invoice (its credit taken off the
  -- buyer's lot, which is then empty), the customer changed to the friend
  -- (line B's credit taken along), cancelled, reopened, paid.
  inv := pg_temp.t446_csale(array['cpb', 'cpb']);
  a := pg_temp.t446_line(inv, 1); b := pg_temp.t446_line(inv, 2);
  perform pg_temp.t446_check(pg_temp.t446_cline_back(inv, a) = 'recorded', '8b credit: line A refunded');
  perform pg_temp.t446_change(inv, pg_temp.t446_id('friend'));
  perform pg_temp.t446_check(pg_temp.t446_whose(inv) = 'friend paid net 100.00' and pg_temp.t446_credit_of(a, 'buyer') = 0
    and pg_temp.t446_credit_of(b, 'buyer') = 0, '8b credit: changed to the friend: ' || pg_temp.t446_whose(inv));
  perform cancel_invoice_recorded(inv, 'T446 8b cancel', gen_random_uuid());
  perform pg_temp.t446_creopen(inv);
  w := pg_temp.t446_cwait_whose(inv, a);
  perform pg_temp.t446_check(pg_temp.t446_cwait(inv, a) = 110 and w = 'buyer:invoice_benefit_refund',
    '8b credit: reopened, line A''s refund waits ' || pg_temp.t446_cwait(inv, a) || ' on ' || w
    || ': look at 446''s NOT COVERED 5 and this case again');
  perform pg_temp.t446_cpay(inv);
  perform pg_temp.t446_check(pg_temp.t446_whose(inv) = 'friend paid net 200.00' and pg_temp.t446_credit_of(a, 'buyer') = cb
    and pg_temp.t446_credit_of(a, 'friend') = cf,
    '8b credit: paid, ' || pg_temp.t446_whose(inv) || ', line A''s credit with the buyer ' || pg_temp.t446_credit_of(a, 'buyer')
    || ', the friend ' || pg_temp.t446_credit_of(a, 'friend') || how);
  -- Credit refunded while it waited (446's own refund row), settled (line
  -- B's S$110 alone, right), then the same.
  inv := pg_temp.t446_cwaiting(array['cpb', 'cpb']);
  a := pg_temp.t446_line(inv, 1); b := pg_temp.t446_line(inv, 2);
  perform pg_temp.t446_check(pg_temp.t446_refund_some(inv, a, 1) = '-', '8b credit: line A refunded while waiting');
  perform pg_temp.t446_cpay(inv);
  perform pg_temp.t446_check(pg_temp.t446_whose(inv) = 'buyer paid net 100.00' and pg_temp.t446_credit_of(a, 'buyer') = 0
    and pg_temp.t446_credit_of(b, 'buyer') = 110, '8b credit: refunded while waiting, settled: ' || pg_temp.t446_cmoney(inv));
  perform pg_temp.t446_change(inv, pg_temp.t446_id('friend'));
  perform cancel_invoice_recorded(inv, 'T446 8b cancel', gen_random_uuid());
  perform pg_temp.t446_creopen(inv);
  w := pg_temp.t446_cwait_whose(inv, a);
  perform pg_temp.t446_check(pg_temp.t446_cwait(inv, a) = 110 and w = 'buyer:invoice_benefit_refund',
    '8b credit refunded while waiting: reopened, line A''s refund waits ' || pg_temp.t446_cwait(inv, a) || ' on ' || w
    || ': look at 446''s NOT COVERED 5 and this case again');
  perform pg_temp.t446_cpay(inv);
  perform pg_temp.t446_check(pg_temp.t446_whose(inv) = 'friend paid net 200.00' and pg_temp.t446_credit_of(a, 'buyer') = cb
    and pg_temp.t446_credit_of(a, 'friend') = cf,
    '8b credit refunded while waiting: paid, ' || pg_temp.t446_whose(inv) || ', line A''s credit with the buyer '
    || pg_temp.t446_credit_of(a, 'buyer') || ', the friend ' || pg_temp.t446_credit_of(a, 'friend') || how);
  -- Vouchers: line A refunded on the paid invoice (guided), changed to the
  -- friend (line B's voucher taken along), cancelled, reopened, paid.
  inv := pg_temp.t446_sale('vl', 2, 1);
  a := pg_temp.t446_line(inv, 1); b := pg_temp.t446_line(inv, 2);
  perform pg_temp.t446_check(pg_temp.t446_refund_some(inv, a, 1) = '-', '8b vouchers: line A refunded');
  perform pg_temp.t446_change(inv, pg_temp.t446_id('friend'));
  perform pg_temp.t446_check(pg_temp.t446_held_by(b, 'friend') = 1, '8b vouchers: line B''s voucher not taken along');
  perform cancel_invoice_recorded(inv, 'T446 8b cancel', gen_random_uuid());
  perform reopen_invoice(inv, 'T446 8b reopen', gen_random_uuid());
  perform pg_temp.t446_pay(inv);
  perform pg_temp.t446_check(pg_temp.t446_whose(inv) = 'friend paid net 60.00' and pg_temp.t446_held_by(a, 'buyer') = vb
    and pg_temp.t446_held_by(a, 'friend') = vf and pg_temp.t446_held_by(b, 'friend') = 1,
    '8b vouchers: paid, ' || pg_temp.t446_whose(inv) || ', line A''s voucher with the buyer ' || pg_temp.t446_held_by(a, 'buyer')
    || ', the friend ' || pg_temp.t446_held_by(a, 'friend') || how);
  -- Vouchers: line A refunded while they waited (446 takes its unit off the
  -- queue), settled, changed, cancelled, reopened, paid. (Line B's voucher
  -- is then a reopening's replacement, which a customer change did not take
  -- along before 460, a separate matter: read only where 460 is in.)
  inv := pg_temp.t446_waiting('vl', array[1, 1]);
  a := pg_temp.t446_line(inv, 1); b := pg_temp.t446_line(inv, 2);
  perform pg_temp.t446_check(pg_temp.t446_refund_some(inv, a, 1) = '-', '8b vouchers: line A refunded while waiting');
  perform pg_temp.t446_pay(inv);
  perform pg_temp.t446_check(pg_temp.t446_money(inv) = 'paid net 30.00 held 1 waiting 0' and pg_temp.t446_held(inv, a) = 0,
    '8b vouchers: refunded while waiting, settled: ' || pg_temp.t446_money(inv));
  perform pg_temp.t446_change(inv, pg_temp.t446_id('friend'));
  perform cancel_invoice_recorded(inv, 'T446 8b cancel', gen_random_uuid());
  perform reopen_invoice(inv, 'T446 8b reopen', gen_random_uuid());
  perform pg_temp.t446_pay(inv);
  perform pg_temp.t446_check(pg_temp.t446_whose(inv) = 'friend paid net 60.00' and pg_temp.t446_held_by(a, 'buyer') = vb
    and pg_temp.t446_held_by(a, 'friend') = vf and (not fx or pg_temp.t446_held_by(b, 'friend') = 1),
    '8b vouchers refunded while waiting: paid, ' || pg_temp.t446_whose(inv) || ', line A''s voucher with the buyer '
    || pg_temp.t446_held_by(a, 'buyer') || ', the friend ' || pg_temp.t446_held_by(a, 'friend')
    || ', line B''s with the friend ' || pg_temp.t446_held_by(b, 'friend') || how);
  if fx then
    raise notice 'FIXED 8b (460 in): a line refunded by line, then the customer changed to the friend with the benefits taken along, cancelled, reopened and paid: line A''s refund still waits on the buyer''s emptied lot, or against the buyer''s voucher, but is given to the friend once paid (S$110 of credit on a lot of the friend''s, or the voucher); the same for a line refunded while the credit or the vouchers waited (446), once settled, then changed, and line B''s voucher a reopening gave moves with the change';
    return;
  end if;
  raise notice 'KNOWN 8b: (not covered by 446: NOT COVERED 5, there before 446 and 447) a line refunded by line, then the customer changed to the friend with the benefits taken along, cancelled, reopened and paid: the invoice is the friend''s and paid in full (S$200 / S$60 net), but line A''s refund was queued on the buyer''s emptied lot, or against the buyer''s voucher, and given back to the buyer: line A''s S$110 of credit, or its voucher. The same for a line refunded while the credit or the vouchers waited (446), once settled, then changed';
end $$;

-- ===== 11. Credit: a line refunded whole while waiting =====
do $$
declare inv uuid; k text; a uuid; b uuid; g numeric; req uuid; msg text; aq text; n int;
begin
  foreach k in array array['cp', 'cpb', 'pbb'] loop
    inv := pg_temp.t446_cwaiting(array[k, k]);
    a := pg_temp.t446_line(inv, 1); b := pg_temp.t446_line(inv, 2);
    select sum(granted_value) into g from invoice_benefit_values where invoice_item_id = a and lot_id is not null;
    if k = 'cp' then
      -- A Move is refused while the credit waits, as before.
      begin
        perform transfer_invoice_unused_benefit((select id from invoice_benefit_values where invoice_item_id = b and lot_id is not null),
          pg_temp.t446_id('friend'), pg_temp.t446_id('store'), 'T446 11 move', gen_random_uuid());
        msg := 'moved';
      exception when others then msg := sqlerrm;
      end;
      perform pg_temp.t446_check(msg = 'Settle the reopened invoice before moving its reinstated benefits', '11 a Move while the credit waits: ' || msg);
    end if;
    aq := pg_temp.t446_cqueue(inv, a);
    perform pg_temp.t446_check(pg_temp.t446_refund_some(inv, a, 1) = '-', '11 ' || k || ' the guided refund of line A');
    req := pg_temp.t446_last_refund(inv);
    -- Line A's rows closed (their amounts kept), B's wait, no lot moved.
    perform pg_temp.t446_check(pg_temp.t446_cqueue(inv, a) = replace(aq, 'w', 'a') and pg_temp.t446_cwait(inv) = g
      and pg_temp.t446_cwait(inv, b) = g and pg_temp.t446_credit(inv) = 0
      and (select sum(cancelled_unused_value) from invoice_benefit_values where invoice_item_id = a) = 0,
      '11 ' || k || ' line A''s credit was not taken off the queue: ' || pg_temp.t446_cmoney(inv) || ', A ' || pg_temp.t446_cqueue(inv, a));
    -- Each of A's rows reinstated and refunded at once in the ledger, with
    -- its Audit Log row; the statement still ends at the credit held.
    perform pg_temp.t446_check(pg_temp.t446_cpair(inv, a, req) = case k when 'cp' then 'd100.00,r100.00'
                                 when 'cpb' then 'd10.00,d100.00,r10.00,r100.00' else 'd100.00,d20.00,r100.00,r20.00' end,
      '11 ' || k || ' the ledger and the Audit Log read ' || pg_temp.t446_cpair(inv, a, req));
    select count(*) into n from audit_logs where table_name = 'invoices' and record_id = inv and action = 'reopen_credit_refunded'
       and (new_data->>'still_waiting')::numeric = 0 and old_data->>'applied_at' is null
       and (new_data->>'benefit_id')::uuid in (select id from invoice_benefit_values where invoice_item_id = a);
    perform pg_temp.t446_check(n = case k when 'cp' then 1 else 2 end, '11 ' || k || ' the Audit Log has ' || n || ' reopen_credit_refunded rows');
    perform pg_temp.t446_check(pg_temp.t446_statement_ok(), '11 ' || k || ' the buyer''s statement does not end at the credit held');
    perform pg_temp.t446_cpay(inv);
    perform pg_temp.t446_check(pg_temp.t446_cmoney(inv) = 'paid net 100.00 credit ' || g || ' waiting 0.00'
      and pg_temp.t446_credit(inv, a) = 0 and pg_temp.t446_credit(inv, b) = g and pg_temp.t446_statement_ok(),
      '11 ' || k || ' settled: ' || pg_temp.t446_cmoney(inv));
    perform pg_temp.t446_check(pg_temp.t446_codes(inv, 'refund_full') = '-', '11 ' || k || ' Refund in full asks ' || pg_temp.t446_codes(inv, 'refund_full'));
    -- Cancelled again, line B paid back, reopened, paid: the refund counted once.
    perform cancel_invoice_recorded(inv, 'T446 11 cancel 2', gen_random_uuid());
    perform pg_temp.t446_check(pg_temp.t446_cline_back(inv, b) = 'recorded', '11 ' || k || ' line B paid back again');
    perform pg_temp.t446_check((invoice_reopen_preview_before_sessions(inv)->>'credit_to_reinstate_after_settlement')::numeric = 2 * g,
      '11 ' || k || ' the Reopen dialog would reinstate ' || (invoice_reopen_preview_before_sessions(inv)->>'credit_to_reinstate_after_settlement'));
    perform pg_temp.t446_creopen(inv);
    perform pg_temp.t446_check(invoice_charge_total(inv) = 200 and pg_temp.t446_cwait(inv) = 2 * g, '11 ' || k || ' reopened again: ' || pg_temp.t446_cmoney(inv));
    perform pg_temp.t446_cpay(inv);
    perform pg_temp.t446_check(pg_temp.t446_cmoney(inv) = 'paid net 200.00 credit ' || (2 * g) || ' waiting 0.00' and pg_temp.t446_statement_ok(),
      '11 ' || k || ' paid again: ' || pg_temp.t446_cmoney(inv));
  end loop;
  -- Refund in full once settled: line B's credit taken back, nothing asked.
  inv := pg_temp.t446_cwaiting(array['cpb', 'cpb']);
  perform pg_temp.t446_check(pg_temp.t446_refund_some(inv, pg_temp.t446_line(inv, 1), 1) = '-', '11 refund before Refund in full');
  perform pg_temp.t446_cpay(inv);
  msg := pg_temp.t446_guided(inv, 'refund_full', null, '[]', true);
  perform pg_temp.t446_check(msg = '-', '11 Refund in full asked ' || msg);
  perform pg_temp.t446_check(pg_temp.t446_cmoney(inv) = 'refunded net 0.00 credit 0.00 waiting 0.00' and pg_temp.t446_statement_ok(),
    '11 refunded in full: ' || pg_temp.t446_cmoney(inv));
  raise notice 'PASS 11: credit, line A refunded whole while waiting (a S$100 Credit Package, one with a S$10 Bonus, a Premium Bundle with a S$20 Bonus): each of its queued rows closed with its reverse and the refund in the ledger (Audit Log), no lot moved, the statement right, a Move still refused; paid: line B''s S$100 / S$110 / S$120 alone for S$100 net; cancelled, B paid back, reopened (the Reopen dialog counts the refund once) and paid: S$200 / S$220 / S$240 for S$200; Refund in full afterwards asks nothing and takes line B''s credit back';
end $$;

-- ===== 12. Credit: part refunded while waiting =====
do $$
declare inv uuid; a uuid; q uuid; req uuid;
begin
  -- S$40 of line A: its row lowered to S$60 (the same row).
  inv := pg_temp.t446_cwaiting(array['cp', 'cp']);
  a := pg_temp.t446_line(inv, 1);
  select q2.id into q from invoice_reopen_benefits q2 join customer_credit_ledger e on e.id = q2.source_ledger_id
   where q2.invoice_id = inv and e.lot_id = (select lot_id from invoice_benefit_values where invoice_item_id = a);
  perform pg_temp.t446_check(pg_temp.t446_cline_back(inv, a, 40) = 'recorded', '12 S$40 of line A');
  req := pg_temp.t446_last_refund(inv);
  perform pg_temp.t446_check(pg_temp.t446_cqueue(inv, a) = '60.00w' and (select amount from invoice_reopen_benefits where id = q) = 60
    and pg_temp.t446_cpair(inv, a, req) = 'd40.00,r40.00'
    and exists (select 1 from audit_logs where record_id = inv and action = 'reopen_credit_refunded' and (new_data->>'reopen_benefit_id')::uuid = q
                  and (new_data->>'still_waiting')::numeric = 60 and (new_data->>'refunded_amount')::numeric = 40
                  and (old_data->>'amount')::numeric = 100)
    and pg_temp.t446_credit(inv) = 0 and pg_temp.t446_statement_ok(),
    '12 S$40 of line A: A ' || pg_temp.t446_cqueue(inv, a) || ', ' || pg_temp.t446_cpair(inv, a, req));
  perform pg_temp.t446_cpay(inv);
  perform pg_temp.t446_check(pg_temp.t446_cmoney(inv) = 'paid net 160.00 credit 160.00 waiting 0.00' and pg_temp.t446_credit(inv, a) = 60,
    '12 S$40 of line A, settled: ' || pg_temp.t446_cmoney(inv));
  -- Cancelled, reopened straight away (S$160 held), the rest paid: the
  -- refund counted once.
  perform cancel_invoice_recorded(inv, 'T446 12 cancel 2', gen_random_uuid());
  perform pg_temp.t446_creopen(inv);
  perform pg_temp.t446_check(pg_temp.t446_cwait(inv) = 200 and invoice_charge_total(inv) = 200, '12 reopened again: ' || pg_temp.t446_cmoney(inv));
  perform pg_temp.t446_cpay(inv);
  perform pg_temp.t446_check(pg_temp.t446_cmoney(inv) = 'paid net 200.00 credit 200.00 waiting 0.00' and pg_temp.t446_statement_ok(),
    '12 paid again: ' || pg_temp.t446_cmoney(inv));
  -- S$40, then the rest: the row lowered, then closed.
  inv := pg_temp.t446_cwaiting(array['cp', 'cp']);
  a := pg_temp.t446_line(inv, 1);
  perform pg_temp.t446_check(pg_temp.t446_cline_back(inv, a, 40) = 'recorded', '12 S$40 first');
  perform pg_temp.t446_check(pg_temp.t446_cline_back(inv, a) = 'recorded', '12 then the rest');
  req := pg_temp.t446_last_refund(inv);
  perform pg_temp.t446_check(pg_temp.t446_cqueue(inv, a) = '60.00a' and pg_temp.t446_cpair(inv, a, req) = 'd60.00,r60.00'
    and pg_temp.t446_cwait(inv) = 100, '12 S$40 then the rest: A ' || pg_temp.t446_cqueue(inv, a) || ', ' || pg_temp.t446_cpair(inv, a, req));
  perform pg_temp.t446_cpay(inv);
  perform pg_temp.t446_check(pg_temp.t446_cmoney(inv) = 'paid net 100.00 credit 100.00 waiting 0.00' and pg_temp.t446_statement_ok(),
    '12 S$40 then the rest, settled: ' || pg_temp.t446_cmoney(inv));
  -- Line A's Paid credit alone (S$90.91): its Bonus still waits and is
  -- reinstated.
  inv := pg_temp.t446_cwaiting(array['cpb', 'cpb']);
  a := pg_temp.t446_line(inv, 1);
  perform pg_temp.t446_check(pg_temp.t446_cline_back(inv, a, null, 'paid') = 'recorded', '12 line A''s Paid credit');
  perform pg_temp.t446_check(pg_temp.t446_cqueue(inv, a) = '10.00w,100.00a' and pg_temp.t446_cwait(inv) = 120,
    '12 line A''s Paid credit: A ' || pg_temp.t446_cqueue(inv, a));
  perform pg_temp.t446_cpay(inv);
  perform pg_temp.t446_check(pg_temp.t446_cmoney(inv) = 'paid net 109.09 credit 120.00 waiting 0.00' and pg_temp.t446_credit(inv, a) = 10,
    '12 line A''s Paid credit, settled: ' || pg_temp.t446_cmoney(inv));
  raise notice 'PASS 12: credit part refunded while waiting: S$40 of line A lowers its row to S$60 (the same row; ledger and Audit Log); paid: S$160 for S$160; cancelled, reopened and paid: S$200 for S$200 (the refund counted once). S$40 then the rest: the row lowered, then closed; paid: S$100 for S$100. Line A''s Paid credit alone: its Bonus still waits and is reinstated (S$120 for S$109.09)';
end $$;

-- ===== 13. Credit refunded while waiting, cancelled before settling, reopened =====
do $$
declare inv uuid;
begin
  -- S$40 of line A.
  inv := pg_temp.t446_cwaiting(array['cp', 'cp']);
  perform pg_temp.t446_check(pg_temp.t446_cline_back(inv, pg_temp.t446_line(inv, 1), 40) = 'recorded', '13 S$40 of line A');
  perform cancel_invoice_recorded(inv, 'T446 13 cancel 2', gen_random_uuid());
  -- (474, where it is in: with the S$160 still waiting, S$200, what the
  -- payment below gives)
  perform pg_temp.t446_check((invoice_reopen_preview_before_sessions(inv)->>'credit_to_reinstate_after_settlement')::numeric
                               = case when pg_temp.t446_474_in() then 200 else 40 end,
    '13 the Reopen dialog would add ' || (invoice_reopen_preview_before_sessions(inv)->>'credit_to_reinstate_after_settlement'));
  perform pg_temp.t446_creopen(inv);
  perform pg_temp.t446_check(pg_temp.t446_cwait(inv) = 200 and invoice_charge_total(inv) = 200, '13 reopened again: ' || pg_temp.t446_cmoney(inv));
  perform pg_temp.t446_cpay(inv);
  perform pg_temp.t446_check(pg_temp.t446_cmoney(inv) = 'paid net 200.00 credit 200.00 waiting 0.00' and pg_temp.t446_statement_ok(),
    '13 S$40, settled: ' || pg_temp.t446_cmoney(inv));
  -- Line A whole (with a Bonus).
  inv := pg_temp.t446_cwaiting(array['cpb', 'cpb']);
  perform pg_temp.t446_check(pg_temp.t446_refund_some(inv, pg_temp.t446_line(inv, 1), 1) = '-', '13 line A');
  perform cancel_invoice_recorded(inv, 'T446 13 cancel 2', gen_random_uuid());
  perform pg_temp.t446_creopen(inv);
  perform pg_temp.t446_check(pg_temp.t446_cwait(inv) = 220 and invoice_charge_total(inv) = 200, '13 line A, reopened again: ' || pg_temp.t446_cmoney(inv));
  perform pg_temp.t446_cpay(inv);
  perform pg_temp.t446_check(pg_temp.t446_cmoney(inv) = 'paid net 200.00 credit 220.00 waiting 0.00' and pg_temp.t446_statement_ok(),
    '13 line A, settled: ' || pg_temp.t446_cmoney(inv));
  raise notice 'PASS 13: credit refunded while waiting (S$40, or line A whole with its Bonus), cancelled again before settling, reopened: all of it waits again (the Reopen dialog %); paid: S$200 / S$220 for S$200',
    case when pg_temp.t446_474_in() then 'shows all S$200 that waits, 474' else 'adds the refund once' end;
end $$;

-- ===== 14. A part-paid package's released credit, settled, then waiting =====
do $$
declare inv uuid; a uuid; b uuid;
begin
  inv := pg_temp.t446_csale(array['cpb', 'cpb'], 120);
  perform pg_temp.t446_check((select sum(released_amount) from credit_package_progress_lots where invoice_id = inv) = 120,
    '14 fixture: S$120 of Paid credit not released before settlement');
  perform pg_temp.t446_cpay(inv);
  perform cancel_invoice_recorded(inv, 'T446 14 cancel', gen_random_uuid());
  a := pg_temp.t446_line(inv, 1); b := pg_temp.t446_line(inv, 2);
  perform pg_temp.t446_check(pg_temp.t446_cline_back(inv, b) = 'recorded', '14 line B paid back');
  perform pg_temp.t446_creopen(inv);
  perform pg_temp.t446_check(pg_temp.t446_cwait(inv) = 220
    and exists (select 1 from invoice_reopen_benefits q join customer_credit_ledger e on e.id = q.source_ledger_id
                  join credit_package_progress_lots pl on pl.lot_id = e.lot_id and pl.invoice_id = inv
                 where q.invoice_id = inv and q.applied_at is null),
    '14 the released lots do not wait: ' || pg_temp.t446_cmoney(inv));
  perform pg_temp.t446_check(pg_temp.t446_refund_some(inv, a, 1) = '-', '14 the guided refund of line A');
  perform pg_temp.t446_check(pg_temp.t446_cwait(inv, a) = 0 and pg_temp.t446_cwait(inv) = 110 and pg_temp.t446_credit(inv) = 0,
    '14 line A refunded while waiting: ' || pg_temp.t446_cmoney(inv));
  perform pg_temp.t446_cpay(inv);
  perform pg_temp.t446_check(pg_temp.t446_cmoney(inv) = 'paid net 100.00 credit 110.00 waiting 0.00' and pg_temp.t446_credit(inv, b) = 110
    and pg_temp.t446_statement_ok(), '14 settled: ' || pg_temp.t446_cmoney(inv));
  perform cancel_invoice_recorded(inv, 'T446 14 cancel 2', gen_random_uuid());
  perform pg_temp.t446_check(pg_temp.t446_cline_back(inv, b) = 'recorded', '14 line B paid back again');
  perform pg_temp.t446_creopen(inv);
  perform pg_temp.t446_cpay(inv);
  perform pg_temp.t446_check(pg_temp.t446_cmoney(inv) = 'paid net 200.00 credit 220.00 waiting 0.00' and pg_temp.t446_statement_ok(),
    '14 paid again: ' || pg_temp.t446_cmoney(inv));
  raise notice 'PASS 14: a part-paid package''s released credit (S$120 released, then settled), cancelled, line B paid back, reopened (the released lots wait), line A refunded while waiting: paid: line B''s S$110 alone for S$100; cancelled, reopened and paid again: S$220 for S$200';
end $$;

-- ===== 15. Credit refunded before the reopening and while waiting =====
do $$
declare inv uuid; a uuid; b uuid; req uuid;
begin
  inv := pg_temp.t446_csale(array['cp', 'cp']);
  a := pg_temp.t446_line(inv, 1); b := pg_temp.t446_line(inv, 2);
  perform pg_temp.t446_check(pg_temp.t446_cline_back(inv, a, 30) = 'recorded', '15 S$30 of line A refunded while paid');
  perform cancel_invoice_recorded(inv, 'T446 15 cancel', gen_random_uuid());
  perform pg_temp.t446_check(pg_temp.t446_cline_back(inv, b) = 'recorded', '15 line B paid back');
  perform pg_temp.t446_creopen(inv);
  -- The reopening gives the earlier S$30 back too (its own ledger row) and
  -- charges line A whole again.
  perform pg_temp.t446_check(pg_temp.t446_cqueue(inv, a) = '30.00w,70.00w' and pg_temp.t446_cwait(inv) = 200
    and invoice_charge_total(inv) = 200 and invoice_net_received(inv) = 70, '15 reopened: ' || pg_temp.t446_cmoney(inv) || ', A ' || pg_temp.t446_cqueue(inv, a));
  -- What line A can still refund while waiting (S$70, what the cancellation took back).
  perform pg_temp.t446_check(pg_temp.t446_cline_back(inv, a) = 'recorded', '15 line A refunded while waiting');
  req := pg_temp.t446_last_refund(inv);
  perform pg_temp.t446_check(pg_temp.t446_cwait(inv, a) = 30 and pg_temp.t446_cwait(inv) = 130
    and (select sum((new_data->>'refunded_amount')::numeric) from audit_logs where record_id = inv and action = 'reopen_credit_refunded'
          and (new_data->>'request_id')::uuid = req) = 70
    and (select string_agg(amount::text, ',') from customer_credit_ledger where source_record_id = req and entry_type = 'adjust_decrease') = '70.00',
    '15 line A refunded while waiting: ' || pg_temp.t446_cmoney(inv) || ', A ' || pg_temp.t446_cqueue(inv, a));
  perform pg_temp.t446_cpay(inv);
  perform pg_temp.t446_check(pg_temp.t446_cmoney(inv) = 'paid net 130.00 credit 130.00 waiting 0.00' and pg_temp.t446_credit(inv, a) = 30
    and pg_temp.t446_statement_ok(), '15 settled: ' || pg_temp.t446_cmoney(inv));
  perform cancel_invoice_recorded(inv, 'T446 15 cancel 2', gen_random_uuid());
  perform pg_temp.t446_creopen(inv);
  perform pg_temp.t446_check(pg_temp.t446_cwait(inv) = 200 and invoice_charge_total(inv) = 200, '15 reopened again: ' || pg_temp.t446_cmoney(inv));
  perform pg_temp.t446_cpay(inv);
  perform pg_temp.t446_check(pg_temp.t446_cmoney(inv) = 'paid net 200.00 credit 200.00 waiting 0.00' and pg_temp.t446_statement_ok(),
    '15 paid again: ' || pg_temp.t446_cmoney(inv));
  raise notice 'PASS 15: S$30 of line A refunded while paid, cancelled, line B paid back, reopened (S$30 + S$70 wait for line A), S$70 refunded while waiting: S$30 still waits for A; paid: S$130 for S$130; cancelled, reopened and paid: S$200 for S$200';
end $$;

rollback;
