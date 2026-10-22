-- 438: a voucher a reopening (or a payment) gave again, or a unit an Owner
-- moved, is not "used".
--
-- Found by the Health Seminar session (436), round 6, 20-21 Oct 2026: a
-- plain S$30 voucher sale, paid, cancelled, reopened and cancelled again read
-- "vouchers redeemed" (cancelled_invoice_used_value), so "Record refund paid"
-- was refused, and the guided Cancel of the reopened invoice asked for a
-- voucher_redeemed override that was not true. The same after the Finance
-- panel's Move, and after the FOC was taken off (the same voucher, the
-- quantity not lowered) and the invoice paid.
--   0. Invoices never reopened or moved: with 438 installed by this suite,
--      every plan and every "used" reads exactly as before it (a paid sale,
--      Refund in full and Cancel; one of two redeemed; a direct cancel, with
--      and without use; credit spent; a line refund of one unit; the FOC
--      taken off with the quantity lowered; the FOC taken off with the
--      voucher swapped, paid, and then cancelled; credit taken along by a
--      customer change, and then cancelled). Skipped, with a notice, when 438
--      was in before the suite started; the absolute figures are checked
--      either way.
--   1. Cancelled, reopened, cancelled again, through direct calls (the
--      claim exactly): nothing reads as used, the guided Cancel of the
--      reopened invoice asked for no override and no amount owed, and
--      "Record refund paid" records the S$30 (refund due 0).
--   2. The same through the app's own path (the invoice form, the Pay
--      dialog, the guided Cancel twice, Reopen): no override asked either
--      time, no amount owed stated, no 'cancel_refund_owed_stated' audit
--      row, and the S$30 recorded afterwards.
--   3. The reopening's voucher redeemed, then cancelled: still
--      voucher_redeemed (asked once in the plan, not twice), and the S$30
--      refused as used.
--   4. Partial use: two S$30 vouchers, one redeemed, cancelled, reopened
--      (only the unused one is given again): the plan asks voucher_redeemed
--      once (the real one) and an amount owed; the guided Cancel stating S$30
--      owed records S$30 and refuses more; cancelled directly instead, the
--      S$60 is refused as used.
--   5. Reopened twice (cancel, reopen, cancel, reopen, cancel): nothing
--      used; the S$30 recorded.
--   6. Moved (the Finance panel's Move) to a friend: Refund in full asks no
--      override; cancelled, nothing used and the S$30 recorded. The friend
--      redeems the moved voucher instead: voucher_redeemed, refused.
--   7. Credit moved to a friend (a S$100 package): Refund in full asks no
--      credit_used; cancelled, nothing used. The friend spends S$10 of it
--      instead: credit_used.
--   8. A completed FOC, the FOC taken off (416) with the same voucher and
--      quantity, and paid: the payment gives the voucher again; Refund in
--      full and Cancel ask no override; cancelled, nothing used and the S$30
--      recorded.
--   9. Not covered by 438 (its header, NOT COVERED 1, 2, 4 and 5), checked
--      as they are so a change is noticed, and printed as KNOWN notices:
--      (1) the FOC taken off with the quantity lowered, paid: Refund in full
--      still asks voucher_redeemed; the FOC taken off with the voucher
--      swapped, paid: no reopening row, Refund in full and Cancel ask
--      voucher_redeemed; cancelled, it reads so and the S$30 is refused.
--      (2) one unit of a line of two refunded by line: Refund in full still
--      asks it. (4) two vouchers sold, cancelled, S$30 paid back, reopened,
--      line A refunded through the guided "Refund some items" while the
--      reopening's vouchers wait, the rest paid: the customer holds 2
--      vouchers for S$30 net; the plans asked voucher_redeemed before 438
--      and ask nothing with it; the guided Refund in full pays back the S$30
--      and line A's voucher stays held. Where 446 is in (it fixes (4)): 1
--      voucher held (line B's) for S$30 net, Refund in full asks nothing and
--      takes it back, Cancel asks voucher_redeemed for the refunded unit
--      (NOT COVERED 2; 446's NOT COVERED 1). (5) credit taken along by a customer
--      change: no transfer row, credit_used asked; cancelled, credit_used, the
--      friend keeps the S$100, and both refund calls are refused. Where 447
--      is in (the Owner, 22 Oct 2026: the invoice's records follow the
--      credit), (5) is checked as fixed instead and printed as FIXED: still
--      no transfer row, but the benefit value names the friend's lot,
--      Refund in full asks nothing; cancelled, nothing used, the friend's
--      S$100 taken back, and the line refund records the S$100 ("Record
--      refund paid" as one line stays refused for any credit invoice).
--  10. Installed twice: the second run changes nothing (function
--      fingerprint); both functions keep their grants and have no overload.
--
-- Run on a copy of the stack after 430 (production now + 417, 434, 422,
-- 423, 419, 425, 426, 430), with or without 436, with
--   psql -v ON_ERROR_STOP=1 -v mig=supabase/438_reopened_and_moved_benefits_count_as_unused.sql -f scripts/invoices/tests/reopen-recancel-438.sql
-- It installs 438 itself, twice, inside its transaction. Disposable database
-- only; everything is rolled back. Every name, code and amount is invented
-- (@example.com); the phones are numbers kept for fiction (ACMA).
\set ON_ERROR_STOP on
begin;

create temp table t438(k text primary key, id uuid);
create temp table t438_controls(k text primary key, before jsonb, after jsonb);
create temp table t438_fp(k text primary key, fp text);
create temp table t438_known(k text primary key, before text);
-- 446: whether it was in when U4 was made (U4 is checked the fixed way then).
create temp table t438_446(k text primary key, v boolean);
create function pg_temp.t438_id(p_k text) returns uuid language sql as $f$ select id from t438 where k = p_k $f$;
create function pg_temp.t438_check(p_ok boolean, p_label text) returns void language plpgsql as $f$
begin
  if not coalesce(p_ok, false) then raise exception 'FAIL %', p_label; end if;
end $f$;
create function pg_temp.t438_fingerprint() returns text language sql as $f$
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.oid::regprocedure::text)) || ' ' || count(*)
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prokind in ('f', 'p') $f$;
create function pg_temp.t438_in() returns boolean language sql as $f$
  select position('-- 438:' in pg_get_functiondef('public.cancelled_invoice_used_value(uuid)'::regprocedure)) > 0
     and position('-- 438:' in pg_get_functiondef('public.invoice_action_plan(uuid,text,jsonb)'::regprocedure)) > 0 $f$;
-- 447 (NOT COVERED 5 fixed): a customer change's credit is followed by the
-- invoice's own records.
create function pg_temp.t447_in() returns boolean language sql as $f$
  select position('-- 447 (the Owner, 22 Oct 2026)' in
                  pg_get_functiondef('public.move_invoice_benefits_to_customer(uuid,uuid,uuid,text)'::regprocedure)) > 0 $f$;

do $$
declare own uuid := gen_random_uuid(); st uuid; c uuid; c2 uuid; pm uuid; v uuid; vl uuid; cp uuid;
begin
  insert into auth.users(id, email) values (own, 't438-owner@example.com');
  insert into profiles(id, full_name, email, role, is_active) values (own, 'T438 Owner', 't438-owner@example.com', 'owner', true);
  perform set_config('request.jwt.claims', json_build_object('sub', own, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', own::text, true);
  insert into stores(name, code, country_code) values ('T438 Store', 'T438S1', 'SG') returning id into st;
  insert into customers(full_name, phone) values ('T438 Buyer', '+61491579455') returning id into c;
  insert into customers(full_name, phone) values ('T438 Friend', '+61491570313') returning id into c2;
  insert into payment_methods(name, is_active) values ('T438 Cash', true) returning id into pm;
  -- A plain S$30 voucher (the claim's), and a limited one for the FOC cases.
  insert into vouchers(name, code, voucher_kind, qty_type, selling_price, is_active)
    values ('T438 Plain 30', 'T438-P30', 'normal', 'unlimited', 30, true) returning id into v;
  insert into voucher_store_prices(voucher_id, store_id, selling_price, available_at_store) values (v, st, 30, true);
  insert into vouchers(name, code, voucher_kind, qty_type, selling_price, is_active)
    values ('T438 Limited 30', 'T438-L30', 'normal', 'limited', 30, true) returning id into vl;
  insert into voucher_store_prices(voucher_id, store_id, selling_price, available_at_store) values (vl, st, 30, true);
  insert into voucher_store_stock(voucher_id, store_id, current_qty) values (vl, st, 10);
  -- A S$100 credit package (S$100 paid credit, no bonus).
  insert into credit_packages(name, customer_price, paid_credit_amount, bonus_enabled, allow_product, allow_therapy)
    values ('T438 S$100', 100, 100, false, true, true) returning id into cp;
  insert into credit_package_stores(package_id, store_id) values (cp, st);
  insert into t438 values ('own', own), ('store', st), ('buyer', c), ('friend', c2), ('pm', pm), ('v', v), ('vl', vl), ('cp', cp);
end $$;

-- The invoice form (create_invoice_with_details) with p_lines lines of
-- p_qty vouchers, paid in full through the Pay dialog (record_invoice_settlement).
create function pg_temp.t438_sale(p_voucher text, p_lines int, p_qty int) returns uuid language plpgsql as $f$
declare inv uuid; v_lines jsonb := '[]';
begin
  for n in 1 .. p_lines loop
    v_lines := v_lines || jsonb_build_array(jsonb_build_object('kind', 'voucher', 'voucher_id', pg_temp.t438_id(p_voucher), 'quantity', p_qty));
  end loop;
  inv := create_invoice_with_details(pg_temp.t438_id('store'), pg_temp.t438_id('buyer'), v_lines,
    jsonb_build_object('business_date', sg_today()::text));
  perform record_invoice_settlement(inv, jsonb_build_object('receipts', jsonb_build_array(jsonb_build_object(
    'key', 'line-0', 'payment_method_id', pg_temp.t438_id('pm'), 'amount', (select total_amount from invoices where id = inv),
    'payment_date', sg_today()::text)), 'arrangements', '[]'::jsonb), gen_random_uuid());
  return inv;
end $f$;
-- A S$100 credit package, paid.
create function pg_temp.t438_credit_sale() returns uuid language plpgsql as $f$
declare inv uuid;
begin
  inv := create_invoice(pg_temp.t438_id('store'), pg_temp.t438_id('buyer'), null,
    jsonb_build_array(jsonb_build_object('kind', 'credit_package', 'credit_package_id', pg_temp.t438_id('cp'), 'quantity', 1)));
  perform record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.t438_id('pm'), 'amount', 100)),
    gen_random_uuid());
  return inv;
end $f$;
-- The same, then the customer changed to the friend with the benefits taken
-- along (the invoice form's customer change, benefit_action 'transfer').
create function pg_temp.t438_credit_customer_changed() returns uuid language plpgsql as $f$
declare inv uuid; x jsonb;
begin
  inv := pg_temp.t438_credit_sale();
  select jsonb_agg(jsonb_build_object('invoice_item_id', it.id, 'kind', 'credit_package', 'credit_package_id', it.credit_package_id,
           'quantity', 1, 'unit_price', it.unit_price)) into x
    from invoice_items it where it.invoice_id = inv;
  perform correct_invoice(inv, x, jsonb_build_object('expected_edit_count', (select edit_count from invoices where id = inv),
    'customer_id', pg_temp.t438_id('friend'), 'benefit_action', 'transfer'), 'T438 customer change', gen_random_uuid());
  return inv;
end $f$;
-- A completed FOC of p_qty limited vouchers, then the FOC taken off with the
-- line at p_new_qty x S$30 (correct_invoice, 416), then paid. p_swap_to: the
-- voucher the same save puts on the line instead (the invoice form keeps the
-- line when its catalogue item is changed); null keeps it.
create function pg_temp.t438_foc_off_paid(p_qty int, p_new_qty int, p_swap_to text default null) returns uuid language plpgsql as $f$
declare inv uuid; x jsonb;
begin
  inv := create_invoice(pg_temp.t438_id('store'), pg_temp.t438_id('buyer'), null, jsonb_build_array(jsonb_build_object(
    'kind', 'voucher', 'voucher_id', pg_temp.t438_id('vl'), 'quantity', p_qty, 'foc_quantity', p_qty, 'foc_reason', 'T438 goodwill')));
  perform confirm_foc_invoice(inv, 'T438 FOC');
  select jsonb_agg(jsonb_build_object('invoice_item_id', it.id, 'kind', 'voucher',
           'voucher_id', coalesce(pg_temp.t438_id(p_swap_to), it.voucher_id),
           'quantity', p_new_qty, 'unit_price', 30, 'foc_quantity', 0)) into x
    from invoice_items it where it.invoice_id = inv;
  perform correct_invoice(inv, x, jsonb_build_object('expected_edit_count', (select edit_count from invoices where id = inv)),
    'T438 FOC off', gen_random_uuid());
  perform record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.t438_id('pm'),
    'amount', 30 * p_new_qty)), gen_random_uuid());
  return inv;
end $f$;
-- The override codes a plan asks for, sorted ('-' for none).
create function pg_temp.t438_codes(p_inv uuid, p_action text) returns text language sql as $f$
  select coalesce(string_agg(o->>'code', ',' order by o->>'code'), '-')
    from jsonb_array_elements(coalesce(invoice_action_plan(p_inv, p_action, '[]')->'overrides_required', '[]')) o $f$;
create function pg_temp.t438_used(p_inv uuid) returns text language sql as $f$
  select coalesce(nullif(array_to_string(cancelled_invoice_used_value(p_inv), ','), ''), '-') $f$;
-- The guided Refund / Cancel as an Owner confirms it (InvoiceGuidedAction):
-- the plan, the request, then the approval with a reason for every override
-- the plan asks for and, when p_owed is given, 417's amount owed back; the
-- money left held unless p_record (then recorded as paid back). p_lines: the
-- lines of a "Refund some items". Returns the codes the plan asked for.
create function pg_temp.t438_guided(p_inv uuid, p_action text, p_owed numeric default null,
                                    p_lines jsonb default '[]', p_record boolean default false) returns text language plpgsql as $f$
declare plan jsonb; req jsonb; ov jsonb; stock jsonb;
begin
  plan := invoice_action_plan(p_inv, p_action, p_lines);
  req := request_invoice_action_v2(p_inv, p_action, p_lines, 'T438 ' || p_action, null, gen_random_uuid());
  select coalesce(jsonb_agg(case when coalesce((o->>'amount_required')::boolean, false)
           then jsonb_build_object('code', o->>'code', 'reason', 'T438 override', 'amount', (o->>'default_amount')::numeric)
           else jsonb_build_object('code', o->>'code', 'reason', 'T438 override') end), '[]'::jsonb)
    into ov from jsonb_array_elements(coalesce(plan->'overrides_required', '[]')) o;
  if p_owed is not null then
    ov := ov || jsonb_build_array(jsonb_build_object('code', 'refund_owed', 'amount', p_owed, 'reason', 'T438 owed')); end if;
  select jsonb_agg(jsonb_build_object('movement_id', s->>'movement_id', 'sellable_quantity', (s->>'proposed_sellable')::int,
           'damaged_quantity', 0, 'not_returned_quantity', 0)) into stock
    from jsonb_array_elements(coalesce(plan->'stock', '[]')) s;
  perform resolve_invoice_action_v2((req->>'request_id')::uuid, true, 'T438 ' || p_action, plan->>'plan_hash', ov, stock, p_record);
  return (select coalesce(string_agg(o->>'code', ',' order by o->>'code'), '-')
            from jsonb_array_elements(coalesce(plan->'overrides_required', '[]')) o);
end $f$;
-- "Record refund paid" (the Finance panel, refund due): one line with no
-- item, through the first receipt. 'recorded', or the refusal.
create function pg_temp.t438_record_refund(p_inv uuid, p_amount numeric) returns text language plpgsql as $f$
begin
  perform refund_invoice_recorded(p_inv, jsonb_build_array(jsonb_build_object('invoice_item_id', null, 'amount', p_amount)),
    jsonb_build_array(jsonb_build_object('payment_id',
      (select id from invoice_payments where invoice_id = p_inv and entry_kind = 'receipt' order by created_at limit 1), 'amount', p_amount)),
    '[]'::jsonb, 'T438 paid back', gen_random_uuid());
  return 'recorded';
exception when others then return sqlerrm;
end $f$;
-- The vouchers of the invoice still held, redeemed (p_source: only those of
-- that source; null: the first one by id).
create function pg_temp.t438_redeem(p_inv uuid, p_source text) returns void language plpgsql as $f$
begin
  update customer_reward_vouchers set status = 'redeemed', redeemed_at = now()
   where id in (select v.id from invoice_benefit_values b join customer_reward_vouchers v on v.id = b.reward_voucher_id
                 where b.invoice_id = p_inv and v.status = 'held' and (p_source is null or v.source_type = p_source)
                 order by v.id limit case when p_source is null then 1 end);
  if not found then raise exception 'Fixture: no held voucher to redeem on %', p_inv; end if;
end $f$;
-- The vouchers of the invoice still held (units).
create function pg_temp.t438_held(p_inv uuid) returns int language sql as $f$
  select coalesce(sum(v.quantity), 0)::int from invoice_benefit_values b join customer_reward_vouchers v on v.id = b.reward_voucher_id
   where b.invoice_id = p_inv and v.status = 'held' $f$;
-- What the screens read for an invoice, kept for the before/after compare.
create function pg_temp.t438_reads(p_inv uuid) returns jsonb language sql as $f$
  select jsonb_build_object('used', to_jsonb(cancelled_invoice_used_value(p_inv)),
           'cancel', invoice_action_plan(p_inv, 'cancel', '[]'),
           'refund_full', case when i.status in ('paid', 'partially_paid') then invoice_action_plan(p_inv, 'refund_full', '[]') end)
    from invoices i where i.id = p_inv $f$;

-- ===== 0. Invoices never reopened or moved: before 438 =====
do $$
declare inv uuid; it uuid; b uuid;
begin
  -- K1 a paid S$30 voucher.
  insert into t438 values ('K1', pg_temp.t438_sale('v', 1, 1));
  -- K2 two S$30 vouchers, one redeemed.
  inv := pg_temp.t438_sale('v', 2, 1);
  perform pg_temp.t438_redeem(inv, null);
  insert into t438 values ('K2', inv);
  -- K3 cancelled directly, nothing used.
  inv := pg_temp.t438_sale('v', 1, 1);
  perform cancel_invoice_recorded(inv, 'T438 K3', gen_random_uuid());
  insert into t438 values ('K3', inv);
  -- K4 redeemed, then cancelled directly.
  inv := pg_temp.t438_sale('v', 1, 1);
  perform pg_temp.t438_redeem(inv, null);
  perform cancel_invoice_recorded(inv, 'T438 K4', gen_random_uuid());
  insert into t438 values ('K4', inv);
  -- K5 a S$100 credit package, S$25 spent.
  inv := pg_temp.t438_credit_sale();
  update customer_credit_lots set remaining_amount = remaining_amount - 25
   where id in (select lot_id from invoice_benefit_values where invoice_id = inv and lot_id is not null);
  insert into t438 values ('K5', inv);
  -- K6 the same, then cancelled.
  inv := pg_temp.t438_credit_sale();
  update customer_credit_lots set remaining_amount = remaining_amount - 25
   where id in (select lot_id from invoice_benefit_values where invoice_id = inv and lot_id is not null);
  perform cancel_invoice_recorded(inv, 'T438 K6', gen_random_uuid());
  insert into t438 values ('K6', inv);
  -- K7 a line of two S$30 vouchers, one unit refunded by line.
  inv := pg_temp.t438_sale('v', 1, 2);
  select bv.id, bv.invoice_item_id into b, it from invoice_benefit_values bv where bv.invoice_id = inv;
  perform refund_invoice_recorded(inv, jsonb_build_array(jsonb_build_object('invoice_item_id', it, 'amount', 30,
      'benefits', jsonb_build_array(jsonb_build_object('benefit_id', b, 'amount', 30)))),
    jsonb_build_array(jsonb_build_object('payment_id', (select id from invoice_payments where invoice_id = inv order by created_at limit 1), 'amount', 30)),
    '[]', 'T438 K7 one unit', gen_random_uuid());
  insert into t438 values ('K7', inv);
  -- K8 a completed FOC of 2, the FOC taken off with 1 charged, paid.
  insert into t438 values ('K8', pg_temp.t438_foc_off_paid(2, 1));
  -- K9 a completed FOC of 1, the FOC taken off with the voucher swapped
  -- (limited to plain) in the same save, paid.
  insert into t438 values ('K9', pg_temp.t438_foc_off_paid(1, 1, 'v'));
  -- K10 the same, then cancelled.
  inv := pg_temp.t438_foc_off_paid(1, 1, 'v');
  perform cancel_invoice_recorded(inv, 'T438 K10', gen_random_uuid());
  insert into t438 values ('K10', inv);
  -- K11 a S$100 credit package, paid, the customer changed to the friend
  -- with the credit taken along.
  insert into t438 values ('K11', pg_temp.t438_credit_customer_changed());
  -- K12 the same, then cancelled.
  inv := pg_temp.t438_credit_customer_changed();
  perform cancel_invoice_recorded(inv, 'T438 K12', gen_random_uuid());
  insert into t438 values ('K12', inv);
  -- U4 (438's NOT COVERED 4; not a control: 438 changes what it asks) two
  -- S$30 vouchers sold and paid, cancelled, S$30 recorded as paid back,
  -- reopened (part-paid: both vouchers wait), line A refunded through the
  -- guided "Refund some items", the S$30 outstanding paid.
  insert into t438_446 values ('U4', position('-- 446 (the Owner' in
    pg_get_functiondef('public.refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid)'::regprocedure)) > 0);
  inv := pg_temp.t438_sale('v', 2, 1);
  perform cancel_invoice_recorded(inv, 'T438 U4 cancel', gen_random_uuid());
  perform pg_temp.t438_check(pg_temp.t438_record_refund(inv, 30) = 'recorded', 'fixture U4: the S$30 paid back');
  perform reopen_invoice(inv, 'T438 U4 reopen', gen_random_uuid());
  perform pg_temp.t438_check((select status::text from invoices where id = inv) = 'partially_paid'
    and (select sum(quantity) from invoice_reopen_vouchers where invoice_id = inv and applied_at is null) = 2,
    'fixture U4: not reopened part-paid with both vouchers waiting');
  insert into t438 values ('U4A', (select id from invoice_items where invoice_id = inv order by id limit 1));
  perform pg_temp.t438_guided(inv, 'refund_partial', null,
    jsonb_build_array(jsonb_build_object('invoice_item_id', pg_temp.t438_id('U4A'), 'quantity', 1)), true);
  perform record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.t438_id('pm'),
    'amount', (invoice_financial_position(inv)->>'outstanding')::numeric)), gen_random_uuid());
  insert into t438 values ('U4', inv);
  if pg_temp.t438_in() then
    raise notice 'NOTE 0: 438 was in before this suite started, so the before/after comparison is skipped; the figures are still checked';
  else
    insert into t438_controls(k, before)
    select k, pg_temp.t438_reads(id) from t438 where k ~ '^K[0-9]+$';
    insert into t438_known values ('U4 refund_full', pg_temp.t438_codes(inv, 'refund_full')), ('U4 cancel', pg_temp.t438_codes(inv, 'cancel'));
  end if;
  insert into t438_fp values ('start', pg_temp.t438_fingerprint());
end $$;

-- ===== Install 438, twice =====
\i :mig
do $$ begin insert into t438_fp values ('first', pg_temp.t438_fingerprint()); end $$;
\i :mig
do $$
begin
  insert into t438_fp values ('second', pg_temp.t438_fingerprint());
  perform pg_temp.t438_check(pg_temp.t438_in(), '10 438 is not installed');
  perform pg_temp.t438_check((select fp from t438_fp where k = 'second') = (select fp from t438_fp where k = 'first'),
    '10 the second run of 438 changed functions');
  perform pg_temp.t438_check(split_part((select fp from t438_fp where k = 'first'), ' ', 2) = split_part((select fp from t438_fp where k = 'start'), ' ', 2),
    '10 438 changed the number of functions');
  perform pg_temp.t438_check(
    (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace
       and p.proname in ('cancelled_invoice_used_value', 'invoice_action_plan')) = 2, '10 an overload exists');
  perform pg_temp.t438_check(
    has_function_privilege('service_role', 'public.cancelled_invoice_used_value(uuid)', 'execute')
    and not has_function_privilege('authenticated', 'public.cancelled_invoice_used_value(uuid)', 'execute')
    and not has_function_privilege('anon', 'public.cancelled_invoice_used_value(uuid)', 'execute')
    and has_function_privilege('service_role', 'public.invoice_action_plan(uuid,text,jsonb)', 'execute')
    and has_function_privilege('authenticated', 'public.invoice_action_plan(uuid,text,jsonb)', 'execute')
    and not has_function_privilege('anon', 'public.invoice_action_plan(uuid,text,jsonb)', 'execute'),
    '10 the grants of the two functions changed');
  raise notice 'PASS 10: 438 installed; the second run changed nothing (%); no overload; cancelled_invoice_used_value is the service role''s alone, invoice_action_plan signed-in staff''s and the service role''s',
    (select fp from t438_fp where k = 'second');
end $$;

-- ===== 0. ... and after 438: the same =====
do $$
declare r record; n int := 0;
begin
  update t438_controls c set after = pg_temp.t438_reads(t.id) from t438 t where t.k = c.k;
  for r in select * from t438_controls order by k loop
    if r.after is distinct from r.before then
      raise exception 'FAIL 0 % reads differently with 438: before % after %', r.k, r.before, r.after; end if;
    n := n + 1;
  end loop;
  perform pg_temp.t438_check(pg_temp.t438_codes(pg_temp.t438_id('K1'), 'refund_full') = '-'
    and pg_temp.t438_codes(pg_temp.t438_id('K1'), 'cancel') = '-', '0 K1 a paid sale asks an override');
  perform pg_temp.t438_check(pg_temp.t438_codes(pg_temp.t438_id('K2'), 'refund_full') = 'voucher_redeemed'
    and pg_temp.t438_codes(pg_temp.t438_id('K2'), 'cancel') = 'voucher_redeemed', '0 K2 one of two redeemed');
  perform pg_temp.t438_check(pg_temp.t438_used(pg_temp.t438_id('K3')) = '-', '0 K3 cancelled unused reads used');
  perform pg_temp.t438_check(pg_temp.t438_used(pg_temp.t438_id('K4')) = 'voucher_redeemed', '0 K4 redeemed then cancelled');
  perform pg_temp.t438_check(pg_temp.t438_codes(pg_temp.t438_id('K5'), 'refund_full') = 'credit_used', '0 K5 credit spent');
  perform pg_temp.t438_check(pg_temp.t438_used(pg_temp.t438_id('K6')) = 'credit_used', '0 K6 credit spent then cancelled');
  if n > 0 then
    raise notice 'PASS 0: % invoices never reopened or moved read exactly as before 438 (plans for Refund in full and Cancel, and "used"): a paid sale asks nothing, one of two redeemed and spent credit ask theirs, a cancel reads what was used', n;
  else
    raise notice 'PASS 0: (438 was in before the suite) a paid sale asks nothing, one of two redeemed and spent credit ask theirs, a cancel reads what was used';
  end if;
end $$;

-- ===== 1. Cancelled, reopened, cancelled again (direct calls) =====
do $$
declare inv uuid; plan jsonb;
begin
  inv := pg_temp.t438_sale('v', 1, 1);
  perform cancel_invoice_recorded(inv, 'T438 1 cancel', gen_random_uuid());
  perform reopen_invoice(inv, 'T438 1 reopen', gen_random_uuid());
  perform pg_temp.t438_check((select status::text from invoices where id = inv) = 'paid', '1 reopened to paid');
  perform pg_temp.t438_check((select sum(quantity) from invoice_reopen_vouchers where invoice_id = inv and applied_at is not null) = 1,
    '1 the reopening gave the voucher again');
  perform pg_temp.t438_check(pg_temp.t438_used(inv) = '-', '1 the reopened invoice reads ' || pg_temp.t438_used(inv));
  plan := invoice_action_plan(inv, 'cancel', '[]');
  perform pg_temp.t438_check(pg_temp.t438_codes(inv, 'cancel') = '-',
    '1 the guided Cancel of the reopened invoice asks ' || pg_temp.t438_codes(inv, 'cancel'));
  perform pg_temp.t438_check(jsonb_typeof(plan->'refund_owed') is distinct from 'object', '1 the guided Cancel asks an amount owed');
  perform pg_temp.t438_check(pg_temp.t438_codes(inv, 'refund_full') = '-', '1 Refund in full asks an override');
  perform cancel_invoice_recorded(inv, 'T438 1 cancel again', gen_random_uuid());
  perform pg_temp.t438_check(pg_temp.t438_used(inv) = '-', '1 cancelled again it reads ' || pg_temp.t438_used(inv));
  perform pg_temp.t438_check(pg_temp.t438_record_refund(inv, 30) = 'recorded', '1 Record refund paid: ' || pg_temp.t438_record_refund(inv, 30));
  perform pg_temp.t438_check((invoice_financial_position(inv)->>'refund_due')::numeric = 0
    and (select count(*) from invoice_refunds where invoice_id = inv) = 1, '1 the S$30 is not recorded once');
  raise notice 'PASS 1: paid, cancelled, reopened, cancelled again: nothing reads as used, the plans ask no override and no amount owed, and the S$30 is recorded as paid back (refund due 0)';
end $$;

-- ===== 2. The same through the app's own path =====
do $$
declare inv uuid; codes text;
begin
  inv := pg_temp.t438_sale('v', 1, 1);
  codes := pg_temp.t438_guided(inv, 'cancel');
  perform pg_temp.t438_check(codes = '-' and (select status::text from invoices where id = inv) = 'cancelled', '2 the first guided Cancel: ' || codes);
  perform reopen_invoice(inv, 'T438 2 reopen', gen_random_uuid());
  codes := pg_temp.t438_guided(inv, 'cancel');
  perform pg_temp.t438_check(codes = '-', '2 the guided Cancel after the reopening asked ' || codes);
  perform pg_temp.t438_check((select status::text from invoices where id = inv) = 'cancelled'
    and (select cancel_refund_owed from invoices where id = inv) is null, '2 an amount owed was stated');
  perform pg_temp.t438_check(not exists (select 1 from audit_logs where record_id = inv and action = 'cancel_refund_owed_stated'),
    '2 a cancel_refund_owed_stated audit row was written');
  perform pg_temp.t438_check(pg_temp.t438_used(inv) = '-', '2 it reads ' || pg_temp.t438_used(inv));
  perform pg_temp.t438_check(pg_temp.t438_record_refund(inv, 30) = 'recorded', '2 Record refund paid refused');
  perform pg_temp.t438_check((invoice_financial_position(inv)->>'refund_due')::numeric = 0, '2 refund due left');
  raise notice 'PASS 2: through the invoice form, the Pay dialog, the guided Cancel and Reopen: no override asked either time, no amount owed or its audit row, and the S$30 recorded';
end $$;

-- ===== 3. The reopening's voucher redeemed =====
do $$
declare inv uuid; msg text;
begin
  inv := pg_temp.t438_sale('v', 1, 1);
  perform cancel_invoice_recorded(inv, 'T438 3 cancel', gen_random_uuid());
  perform reopen_invoice(inv, 'T438 3 reopen', gen_random_uuid());
  perform pg_temp.t438_redeem(inv, 'invoice_reopen');
  perform pg_temp.t438_check(pg_temp.t438_codes(inv, 'cancel') = 'voucher_redeemed',
    '3 the guided Cancel asks ' || pg_temp.t438_codes(inv, 'cancel') || ', not voucher_redeemed once');
  perform pg_temp.t438_check(invoice_action_plan(inv, 'cancel', '[]')->'refund_owed'->'used' = '["voucher_redeemed"]', '3 no amount owed asked');
  perform cancel_invoice_recorded(inv, 'T438 3 cancel again', gen_random_uuid());
  perform pg_temp.t438_check(pg_temp.t438_used(inv) = 'voucher_redeemed', '3 a redeemed replacement reads ' || pg_temp.t438_used(inv));
  msg := pg_temp.t438_record_refund(inv, 30);
  perform pg_temp.t438_check(msg like 'Part of what % sold has been used (vouchers redeemed)%', '3 the S$30 was not refused as used: ' || msg);
  raise notice 'PASS 3: the reopening''s voucher redeemed: the guided Cancel asks voucher_redeemed once and an amount owed; cancelled, it reads voucher_redeemed and the S$30 is refused';
end $$;

-- ===== 4. Partial use =====
do $$
declare inv uuid; inv2 uuid; codes text; msg text;
begin
  inv := pg_temp.t438_sale('v', 2, 1);
  perform pg_temp.t438_redeem(inv, null);
  perform cancel_invoice_recorded(inv, 'T438 4 cancel', gen_random_uuid());
  perform reopen_invoice(inv, 'T438 4 reopen', gen_random_uuid());
  perform pg_temp.t438_check((select sum(quantity) from invoice_reopen_vouchers where invoice_id = inv and applied_at is not null) = 1,
    '4 the reopening gave again only the unused voucher');
  perform pg_temp.t438_check(pg_temp.t438_codes(inv, 'cancel') = 'voucher_redeemed',
    '4 the guided Cancel asks ' || pg_temp.t438_codes(inv, 'cancel') || ', not voucher_redeemed once');
  codes := pg_temp.t438_guided(inv, 'cancel', 30);
  perform pg_temp.t438_check((select cancel_refund_owed from invoices where id = inv) = 30, '4 the S$30 owed was not kept');
  perform pg_temp.t438_check(pg_temp.t438_used(inv) = 'voucher_redeemed', '4 it reads ' || pg_temp.t438_used(inv));
  msg := pg_temp.t438_record_refund(inv, 60);
  perform pg_temp.t438_check(msg like 'That is more than the S$30.00 still owed back%', '4 S$60 was not refused: ' || msg);
  perform pg_temp.t438_check(pg_temp.t438_record_refund(inv, 30) = 'recorded', '4 the S$30 owed was not recorded');
  -- Cancelled directly instead: no amount stated, so the S$60 is refused.
  inv2 := pg_temp.t438_sale('v', 2, 1);
  perform pg_temp.t438_redeem(inv2, null);
  perform cancel_invoice_recorded(inv2, 'T438 4 cancel', gen_random_uuid());
  perform reopen_invoice(inv2, 'T438 4 reopen', gen_random_uuid());
  perform cancel_invoice_recorded(inv2, 'T438 4 cancel again', gen_random_uuid());
  perform pg_temp.t438_check(pg_temp.t438_used(inv2) = 'voucher_redeemed', '4 cancelled directly it reads ' || pg_temp.t438_used(inv2));
  msg := pg_temp.t438_record_refund(inv2, 60);
  perform pg_temp.t438_check(msg like 'Part of what % sold has been used (vouchers redeemed)%', '4 the S$60 was not refused as used: ' || msg);
  raise notice 'PASS 4: one of two redeemed, cancelled, reopened: voucher_redeemed asked once (the real one) with an amount owed; S$30 owed is recorded and S$60 refused; cancelled directly the S$60 is refused as used';
end $$;

-- ===== 5. Reopened twice =====
do $$
declare inv uuid;
begin
  inv := pg_temp.t438_sale('v', 1, 1);
  perform cancel_invoice_recorded(inv, 'T438 5 cancel', gen_random_uuid());
  perform reopen_invoice(inv, 'T438 5 reopen', gen_random_uuid());
  perform cancel_invoice_recorded(inv, 'T438 5 cancel again', gen_random_uuid());
  perform reopen_invoice(inv, 'T438 5 reopen again', gen_random_uuid());
  perform pg_temp.t438_check(pg_temp.t438_codes(inv, 'cancel') = '-', '5 the guided Cancel asks ' || pg_temp.t438_codes(inv, 'cancel'));
  perform cancel_invoice_recorded(inv, 'T438 5 cancel a third time', gen_random_uuid());
  perform pg_temp.t438_check(pg_temp.t438_used(inv) = '-', '5 it reads ' || pg_temp.t438_used(inv));
  perform pg_temp.t438_check(pg_temp.t438_record_refund(inv, 30) = 'recorded', '5 Record refund paid refused');
  raise notice 'PASS 5: reopened twice and cancelled three times: nothing used, no override, the S$30 recorded';
end $$;

-- ===== 6. A voucher moved to a friend =====
do $$
declare inv uuid; msg text;
begin
  inv := pg_temp.t438_sale('v', 1, 1);
  perform transfer_invoice_unused_benefit((select id from invoice_benefit_values where invoice_id = inv),
    pg_temp.t438_id('friend'), pg_temp.t438_id('store'), 'T438 6 move', gen_random_uuid());
  perform pg_temp.t438_check(pg_temp.t438_codes(inv, 'refund_full') = '-', '6 Refund in full asks ' || pg_temp.t438_codes(inv, 'refund_full'));
  perform pg_temp.t438_check(pg_temp.t438_codes(inv, 'cancel') = '-', '6 Cancel asks ' || pg_temp.t438_codes(inv, 'cancel'));
  perform cancel_invoice_recorded(inv, 'T438 6 cancel', gen_random_uuid());
  perform pg_temp.t438_check(pg_temp.t438_used(inv) = '-', '6 it reads ' || pg_temp.t438_used(inv));
  perform pg_temp.t438_check(pg_temp.t438_record_refund(inv, 30) = 'recorded', '6 Record refund paid refused');
  -- The friend redeems the moved voucher instead.
  inv := pg_temp.t438_sale('v', 1, 1);
  perform transfer_invoice_unused_benefit((select id from invoice_benefit_values where invoice_id = inv),
    pg_temp.t438_id('friend'), pg_temp.t438_id('store'), 'T438 6 move', gen_random_uuid());
  perform pg_temp.t438_redeem(inv, 'invoice_benefit_transfer');
  perform pg_temp.t438_check(pg_temp.t438_codes(inv, 'refund_full') = 'voucher_redeemed', '6 the friend''s redeemed voucher: ' || pg_temp.t438_codes(inv, 'refund_full'));
  perform cancel_invoice_recorded(inv, 'T438 6 cancel', gen_random_uuid());
  perform pg_temp.t438_check(pg_temp.t438_used(inv) = 'voucher_redeemed', '6 the friend''s redeemed voucher reads ' || pg_temp.t438_used(inv));
  msg := pg_temp.t438_record_refund(inv, 30);
  perform pg_temp.t438_check(msg like 'Part of what % (vouchers redeemed)%', '6 not refused: ' || msg);
  raise notice 'PASS 6: a voucher moved to a friend is not used (no override; cancelled, the S$30 recorded); once the friend redeems it, it is';
end $$;

-- ===== 7. Credit moved to a friend =====
do $$
declare inv uuid;
begin
  inv := pg_temp.t438_credit_sale();
  perform transfer_invoice_unused_benefit((select id from invoice_benefit_values where invoice_id = inv and lot_id is not null),
    pg_temp.t438_id('friend'), pg_temp.t438_id('store'), 'T438 7 move', gen_random_uuid());
  perform pg_temp.t438_check(pg_temp.t438_codes(inv, 'refund_full') = '-', '7 Refund in full asks ' || pg_temp.t438_codes(inv, 'refund_full'));
  perform cancel_invoice_recorded(inv, 'T438 7 cancel', gen_random_uuid());
  perform pg_temp.t438_check(pg_temp.t438_used(inv) = '-', '7 it reads ' || pg_temp.t438_used(inv));
  -- The friend spends S$10 of it instead.
  inv := pg_temp.t438_credit_sale();
  perform transfer_invoice_unused_benefit((select id from invoice_benefit_values where invoice_id = inv and lot_id is not null),
    pg_temp.t438_id('friend'), pg_temp.t438_id('store'), 'T438 7 move', gen_random_uuid());
  update customer_credit_lots set remaining_amount = remaining_amount - 10
   where customer_id = pg_temp.t438_id('friend') and source_type = 'invoice_benefit_transfer'
     and id in (select lot_id from invoice_benefit_values where invoice_id = inv);
  perform pg_temp.t438_check(pg_temp.t438_codes(inv, 'refund_full') = 'credit_used', '7 the friend''s spend: ' || pg_temp.t438_codes(inv, 'refund_full'));
  perform cancel_invoice_recorded(inv, 'T438 7 cancel', gen_random_uuid());
  perform pg_temp.t438_check(pg_temp.t438_used(inv) = 'credit_used', '7 the friend''s spend reads ' || pg_temp.t438_used(inv));
  raise notice 'PASS 7: credit moved to a friend is not spent (Refund in full asks nothing; cancelled, nothing used); once the friend spends S$10 of it, it is';
end $$;

-- ===== 8. The FOC taken off (same voucher and quantity) and paid (416 gives the voucher again) =====
do $$
declare inv uuid;
begin
  inv := pg_temp.t438_foc_off_paid(1, 1);
  perform pg_temp.t438_check((select sum(quantity) from invoice_reopen_vouchers where invoice_id = inv and applied_at is not null) = 1,
    '8 the payment did not give the voucher again');
  perform pg_temp.t438_check(pg_temp.t438_codes(inv, 'refund_full') = '-' and pg_temp.t438_codes(inv, 'cancel') = '-',
    '8 the plans ask ' || pg_temp.t438_codes(inv, 'refund_full') || ' / ' || pg_temp.t438_codes(inv, 'cancel'));
  perform cancel_invoice_recorded(inv, 'T438 8 cancel', gen_random_uuid());
  perform pg_temp.t438_check(pg_temp.t438_used(inv) = '-', '8 it reads ' || pg_temp.t438_used(inv));
  perform pg_temp.t438_check(pg_temp.t438_record_refund(inv, 30) = 'recorded', '8 Record refund paid refused');
  raise notice 'PASS 8: the FOC taken off (same voucher and quantity) and paid: the voucher given again is not used; no override; cancelled, the S$30 recorded';
end $$;

-- ===== 9. Not covered by 438, as they are =====
do $$
declare inv uuid; msg text; b uuid;
begin
  -- NOT COVERED 1: the FOC taken off with the quantity lowered, or with the
  -- voucher swapped.
  perform pg_temp.t438_check(pg_temp.t438_codes(pg_temp.t438_id('K8'), 'refund_full') = 'voucher_redeemed',
    '9 the FOC taken off with the quantity lowered now reads ' || pg_temp.t438_codes(pg_temp.t438_id('K8'), 'refund_full')
    || ': look at 438''s NOT COVERED 1 and this case again');
  inv := pg_temp.t438_id('K9');
  perform pg_temp.t438_check(not exists (select 1 from invoice_reopen_vouchers where invoice_id = inv)
    and exists (select 1 from invoice_benefit_values bv join customer_reward_vouchers v on v.id = bv.reward_voucher_id
                 where bv.invoice_id = inv and v.status = 'held' and v.source_type = 'invoice_voucher_sale'
                   and v.voucher_id = pg_temp.t438_id('v')),
    '9 the FOC taken off with the voucher swapped: the payment no longer sells the new voucher without a reopening row: look at 438''s NOT COVERED 1 and this case again');
  perform pg_temp.t438_check(pg_temp.t438_codes(inv, 'refund_full') = 'voucher_redeemed' and pg_temp.t438_codes(inv, 'cancel') = 'voucher_redeemed',
    '9 the FOC taken off with the voucher swapped now reads ' || pg_temp.t438_codes(inv, 'refund_full') || ' / ' || pg_temp.t438_codes(inv, 'cancel')
    || ': look at 438''s NOT COVERED 1 and this case again');
  inv := pg_temp.t438_id('K10');
  msg := pg_temp.t438_record_refund(inv, 30);
  perform pg_temp.t438_check(pg_temp.t438_used(inv) = 'voucher_redeemed' and msg like 'Part of what % (vouchers redeemed)%',
    '9 the FOC taken off with the voucher swapped, cancelled, now reads ' || pg_temp.t438_used(inv) || ' and Record refund paid: ' || msg
    || ': look at 438''s NOT COVERED 1 and this case again');
  -- NOT COVERED 2: one unit refunded by line.
  perform pg_temp.t438_check(pg_temp.t438_codes(pg_temp.t438_id('K7'), 'refund_full') = 'voucher_redeemed',
    '9 a unit refunded by line now reads ' || pg_temp.t438_codes(pg_temp.t438_id('K7'), 'refund_full')
    || ': look at 438''s NOT COVERED 2 and this case again');
  -- NOT COVERED 4: a line refunded while the reopening's vouchers wait.
  -- 446 (the Owner, 22 Oct 2026) fixes it: where 446 was in when U4 was
  -- made, the refund took line A's unit off the queue, so the payment gave
  -- only line B's voucher; Cancel then asks voucher_redeemed for the refunded
  -- unit, as for any refunded unit (NOT COVERED 2; 446's NOT COVERED 1).
  inv := pg_temp.t438_id('U4');
  perform pg_temp.t438_check((select status::text from invoices where id = inv) = 'paid' and invoice_net_received(inv) = 30
    and (select count(*) from invoice_refunds where invoice_id = inv) = 2
    and pg_temp.t438_held(inv) = case when (select v from t438_446 where k = 'U4') then 1 else 2 end,
    '9 U4 now ends ' || (select status::text from invoices where id = inv) || ', net ' || invoice_net_received(inv) || ', '
    || pg_temp.t438_held(inv) || ' vouchers held (446 '
    || case when (select v from t438_446 where k = 'U4') then 'in' else 'not in' end
    || '): look at 438''s NOT COVERED 4 (446) and this case again');
  perform pg_temp.t438_check(pg_temp.t438_codes(inv, 'refund_full') = '-'
    and pg_temp.t438_codes(inv, 'cancel') = case when (select v from t438_446 where k = 'U4') then 'voucher_redeemed' else '-' end,
    '9 U4 with 438 asks ' || pg_temp.t438_codes(inv, 'refund_full') || ' / ' || pg_temp.t438_codes(inv, 'cancel'));
  perform pg_temp.t438_check(coalesce((select before from t438_known where k = 'U4 refund_full'), 'voucher_redeemed') = 'voucher_redeemed'
    and coalesce((select before from t438_known where k = 'U4 cancel'), 'voucher_redeemed,voucher_redeemed') = 'voucher_redeemed,voucher_redeemed',
    '9 U4 before 438 asked ' || (select string_agg(k || ': ' || before, ', ' order by k) from t438_known));
  perform pg_temp.t438_check(pg_temp.t438_guided(inv, 'refund_full', null, '[]', true) = '-', '9 U4 Refund in full asked an override');
  perform pg_temp.t438_check((select status::text from invoices where id = inv) = 'refunded' and invoice_net_received(inv) = 0
    and (select coalesce(sum(v.quantity), 0) from invoice_benefit_values bv join customer_reward_vouchers v on v.id = bv.reward_voucher_id
          where bv.invoice_id = inv and v.status = 'held' and bv.invoice_item_id = pg_temp.t438_id('U4A'))
        = case when (select v from t438_446 where k = 'U4') then 0 else 1 end
    and pg_temp.t438_held(inv) = case when (select v from t438_446 where k = 'U4') then 0 else 1 end,
    '9 U4 Refund in full now ends ' || (select status::text from invoices where id = inv) || ', net ' || invoice_net_received(inv) || ', '
    || pg_temp.t438_held(inv) || ' vouchers held: look at 438''s NOT COVERED 4 (446) and this case again');
  -- NOT COVERED 5: credit taken along by a customer change. 447 (the
  -- Owner, 22 Oct 2026) makes the invoice's own records follow the credit to
  -- the new customer's lot: checked as fixed where 447 is in, as before where
  -- it is not.
  inv := pg_temp.t438_id('K11');
  perform pg_temp.t438_check(not exists (select 1 from invoice_benefit_transfers t join invoice_benefit_values bv on bv.id = t.source_benefit_id
                                          where bv.invoice_id = inv)
    and (select sum(l.remaining_amount) from customer_credit_lots l where l.id in (select lot_id from invoice_credit_lot_ids(inv))
          and l.customer_id = pg_temp.t438_id('friend') and l.status = 'active') = 100
    and pg_temp.t438_codes(inv, 'refund_full') = case when pg_temp.t447_in() then '-' else 'credit_used' end
    and (select count(*) from invoice_benefit_values bv join customer_credit_lots l on l.id = bv.lot_id
          where bv.invoice_id = inv and l.customer_id = pg_temp.t438_id('friend')) = case when pg_temp.t447_in() then 1 else 0 end,
    '9 credit taken along by a customer change now reads ' || pg_temp.t438_codes(inv, 'refund_full')
    || case when pg_temp.t447_in() then ' (447 in)' else ' (447 not in)' end || ': look at 438''s NOT COVERED 5 and this case again');
  inv := pg_temp.t438_id('K12');
  perform pg_temp.t438_check(pg_temp.t438_used(inv) = case when pg_temp.t447_in() then '-' else 'credit_used' end
    and (invoice_financial_position(inv)->>'refund_due')::numeric = 100
    and (select sum(l.remaining_amount) from customer_credit_lots l where l.id in (select lot_id from invoice_credit_lot_ids(inv))
          and l.customer_id = pg_temp.t438_id('friend') and l.status = 'active') = case when pg_temp.t447_in() then 0 else 100 end,
    '9 credit taken along by a customer change, cancelled, now reads ' || pg_temp.t438_used(inv)
    || case when pg_temp.t447_in() then ' (447 in)' else ' (447 not in)' end || ': look at 438''s NOT COVERED 5 and this case again');
  -- "Record refund paid" as one line with no item is refused for any credit
  -- invoice (the panel then goes line by line), with 447 or without.
  msg := pg_temp.t438_record_refund(inv, 100);
  perform pg_temp.t438_check(msg like 'Allocate a correction refund to the original unused purchased benefits%',
    '9 K12 Record refund paid: ' || msg || ': look at 438''s NOT COVERED 5 and this case again');
  select id into b from invoice_benefit_values where invoice_id = inv;
  begin
    perform refund_invoice_recorded(inv, jsonb_build_array(jsonb_build_object('invoice_item_id',
        (select invoice_item_id from invoice_benefit_values where id = b), 'amount', 100,
        'benefits', jsonb_build_array(jsonb_build_object('benefit_id', b, 'amount', 100)))),
      jsonb_build_array(jsonb_build_object('payment_id',
        (select id from invoice_payments where invoice_id = inv and entry_kind = 'receipt' order by created_at limit 1), 'amount', 100)),
      '[]', 'T438 9 line', gen_random_uuid());
    msg := 'recorded';
  exception when others then msg := sqlerrm;
  end;
  if pg_temp.t447_in() then
    perform pg_temp.t438_check(msg = 'recorded' and (invoice_financial_position(inv)->>'refund_due')::numeric = 0,
      '9 K12 line refund (447 in): ' || msg || ', refund due ' || (invoice_financial_position(inv)->>'refund_due') || ': look at 447 and this case again');
  else
    perform pg_temp.t438_check(msg like 'Refund exceeds the unused paid value of this benefit%',
      '9 K12 line refund (447 not in): ' || msg || ': look at 438''s NOT COVERED 5 and this case again');
  end if;
  raise notice 'KNOWN 9: (not covered by 438) (1) the FOC taken off with 2 given and 1 charged, paid: Refund in full still asks voucher_redeemed; the FOC taken off with the voucher swapped, paid: sold anew with no reopening row, Refund in full and Cancel ask voucher_redeemed, and once cancelled the S$30 is refused. (2) one unit of two refunded by line: Refund in full still asks voucher_redeemed';
  if (select v from t438_446 where k = 'U4') then
    raise notice 'FIXED 9 by 446: (4) a line refunded while the reopening''s vouchers waited, then paid: 1 voucher held (line B''s) for S$30 net; Refund in full asks nothing and pays back the S$30, taking it back; Cancel asks voucher_redeemed for the refunded unit (NOT COVERED 2; 446''s NOT COVERED 1); the plans asked % before 438',
      coalesce((select string_agg(k || ' ' || before, ', ' order by k) from t438_known), '(not read: 438 was in)');
  else
    raise notice 'KNOWN 9: (not covered by 438; there before it; 446 not in) (4) a line refunded while the reopening''s vouchers waited, then paid: 2 vouchers held for S$30 net; the plans asked % before 438 and ask nothing with it; Refund in full pays back the S$30 and line A''s voucher stays held',
      coalesce((select string_agg(k || ' ' || before, ', ' order by k) from t438_known), '(not read: 438 was in)');
  end if;
  if pg_temp.t447_in() then
    raise notice 'FIXED 9 by 447: (5) credit taken along by a customer change: the invoice''s benefit value names the friend''s lot, Refund in full asks nothing; cancelled, the S$100 comes back from the friend, nothing reads as used, and the S$100 is recorded by line ("Record refund paid" as one line is refused for any credit invoice, by design)';
  else
    raise notice 'KNOWN 9: (not covered by 438; there before it; 447 not in) (5) credit taken along by a customer change: credit_used before and after 438; cancelled, the friend keeps S$100 and both refund calls are refused';
  end if;
end $$;

rollback;
