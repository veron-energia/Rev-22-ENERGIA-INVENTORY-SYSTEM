-- 461: credit a line refund paid back is not spent when an invoice's
-- customer is changed with its benefits taken along (448's NOT COVERED 3;
-- the Owner, 22 Oct 2026: "fix the other two rare gaps too").
--
-- Every step goes through the app's own calls: the invoice form
-- (create_invoice_with_details) and the Pay dialog (record_invoice_settlement),
-- the invoice form's customer change (correct_invoice with benefit_action
-- 'transfer', or 'keep' for the footprint in 9g; the list it is offered from,
-- invoice_transferable_benefits, and its summary, preview_invoice_correction), the Finance panel's refund by line
-- (refund_invoice_recorded with the line's benefits), the guided "Refund some
-- items" and Refund in full (invoice_action_plan, request_invoice_action_v2,
-- resolve_invoice_action_v2), Cancel (cancel_invoice_recorded), Reopen
-- (reopen_invoice), Record Payment (record_invoice_payment), Move
-- (transfer_invoice_unused_benefit) and a customer merge
-- (merge_customer_records). Spent credit is taken off its lot and a redeemed
-- voucher set 'redeemed', as the other suites do.
--
--   A. The cases and the controls, built before 461 (one invoice each, its
--      own buyer and new customers; the key in brackets).
--      Cases (the list's answer changes): a S$100 Credit Package with a S$10
--      Bonus, S$40 of its Paid benefit refunded by line (S$44 of credit, S$56
--      left), then Refund in full after the change [CA], or Cancel [CB]; a
--      Premium Bundle (S$100 Paid, S$20 Bonus), S$40 of its Paid refunded
--      [CC]; two packages, line A wholly refunded [CD]; S$40 of the Paid and
--      S$5 of the Bonus refunded [CE]; S$40 refunded, then changed twice, A
--      to B to C [CF]; S$40 refunded, changed, S$10 spent by the new
--      customer, then a second change [CG]; two packages, line A wholly
--      refunded, cancelled and reopened, waiting [CH]; S$40 refunded, then
--      cancelled [CI]; S$40 refunded, changed, S$20 more refunded by line
--      from the new customer's lot, then a second change [CJ]; S$40
--      refunded by line, then the guided Refund in full [CK]; S$40
--      refunded, changed, cancelled, reopened and paid [CN, KNOWN without
--      460]; S$30 spent on a session, the guided Refund in full with the
--      credit_used override, then the session refunded (S$30 back on the
--      lot, nothing on it spent) [CM]; S$40 refunded, S$56 spent on a
--      session, cancelled and paid back, reopened (waiting), then the session
--      refunded (S$56 back while the reopening waits: still blocks; the
--      Bonus label alone changes) [CW].
--      Controls (the same answer before and after): an untouched package
--      [K1]; S$10 spent [K2]; S$40 refunded and S$10 spent [K3]; S$40
--      refunded and the rest spent [K4]; the Paid credit moved by an Owner
--      [K5]; S$40 refunded and the rest moved [K6]; cancelled [K7]; S$40
--      refunded, the buyer merged into another record (445 reissues the lot)
--      [K8]; a part-paid package's released credit (no benefit row yet),
--      S$10 spent [K9]; line A wholly refunded, cancelled, reopened and
--      settled [K10]; credit back on a lot something else still has a claim
--      on (a session it paid for refunded, or a reopening settled): a
--      cancellation holding S$70 back (S$30 spent, Cancel with the
--      credit_used override, the due not recorded) [K11], an Owner's Move of
--      the rest (S$30 spent, moved, the session refunded) [K12], (S$40
--      refunded, moved, cancelled, reopened and paid) [K13], a cancelled
--      invoice (S$40 refunded, S$56 spent, cancelled) [K14]. Vouchers: a
--      line of two, one unit refunded [V1], both refunded [V2], one redeemed
--      [V3].
--   R. Before 461 (skipped, with a notice, where 461 was in before the suite
--      started): the cases read as found (a partly refunded lot "Partly
--      spent", blocking; the change refused naming it; the summary asking a
--      review; a wholly refunded lot "Fully spent").
--   Q. The read-only query in 461's header, run before 461 is installed (the
--      same text): afterwards it is checked to list exactly the invoices
--      whose list changed, none held by another customer.
--   9. Refusals (before 461; skipped with -v nomig=1): an unknown version of
--      a function it patches, of a function it relies on, the cancel plans
--      without 448's test, 448's helper missing, a new caller of the move:
--      each stops it, changing nothing. The same grants listed in another
--      order do not. The gap's footprint (S$40 refunded, the customer
--      changed keeping the benefits: the lot stayed with the buyer), and a
--      shared package's share partly refunded (held by its share's customer;
--      set_invoice_credit_split, the server's alone, older invoices), stop
--      it, naming those two invoices alone; the same change with the lot
--      untouched, wholly refunded or spent beside the refund does not, nor
--      with credit back on a lot 461 still blocks (an Owner's Move, a
--      cancellation holding credit back, a cancelled invoice, a reopening
--      waiting) [9g, 9h].
--  10. 461 installed twice: the second run changes nothing; only its two
--      functions change (the others' md5s, the grants, the count as before);
--      no overload; who may call each as before. Its texts are 461's alone,
--      or, with 460 in (installed before the suite), the texts 460 and 461
--      give together. 10b, with -v also460=<path of 460's file>: the real
--      460 installed after 461, then 461 again (left alone); all that follows
--      is checked with both in.
--   0. The controls read and change exactly as before 461 (the whole list;
--      the change's outcome, tried and undone).
--   1. Each case after 461: the list; the summary; the change through the
--      invoice form; what the new customer holds, with the lot's origin; the
--      invoice's records on the new lots; the refund options as before the
--      change; the plans (nothing asked); the money afterwards (Refund in
--      full; Cancel and the refund due recorded by line; a second change;
--      real spending at the new customer blocking again; a refund after the
--      change; the refunded part never moved or paid back twice).
--  1b. The money after 461 where the change is still refused (K11 reopened
--      and refunded in full; K12 and K13 cancelled): everything taken back
--      from whoever holds it, as before 461.
--   8. KNOWN, checked as they are: [CN] the refunded part goes back to the
--      first customer's emptied lot when the changed invoice is cancelled,
--      reopened and settled (446's NOT COVERED 5, 448's NOT COVERED 2; there
--      before 461 for a line wholly refunded beside another, and since 461
--      reached by a partly refunded lot too, whose change was refused
--      before; 460 fixes it: where it is in, checked the fixed way and
--      printed as FIXED); [K5], [K6], [K7] a lot an Owner moved, or a
--      cancellation took back, still reads "Fully spent" (461's NOT COVERED
--      2; no page shows it).
--
-- Where 462 is in (move-merge-leftovers-462.sql: an Owner's Move is no
-- claim any more, its records follow the change), 10 takes 462's AFTERs and
-- 0 expects K12 and K13 to move.
-- Run on a copy of production as it is (455 in: b43a0781, 1372 functions):
--   psql -X -v ON_ERROR_STOP=1 -f scripts/invoices/tests/customer-change-refunded-461.sql
-- It installs 461 itself, twice, inside its transaction. The same on a copy
-- with 460 applied first (460 then 461); and, for 461 then 460, on a copy of
-- 455 with -v also460=<path of 460's file>. Where 461 is in already (with
-- or without 460), add -v nomig=1 (R, 9 and the before/after comparisons
-- are then skipped with a notice; every figure after 461 is still checked).
-- Disposable database only; everything is rolled back. Every name, code and
-- amount is invented (@example.com); the phones are numbers kept for fiction
-- (ACMA, +61491570500 to +61491570599).
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '10s';
set local statement_timeout = '900s';

create temp table t461(k text primary key, id uuid);
create temp table t461_case(k text primary key, ord serial, kind text);
create temp table t461_before(k text primary key, list jsonb, tried text, summary jsonb);
create temp table t461_q(invoice_no text primary key, status text, lots_no_longer_blocking bigint, lots_now_read_refunded bigint,
                         held_by_another_customer bigint);
create temp table t461_fp(k text primary key, fp text);
create temp table t461_md5(sig text primary key, md5 text);
create temp table t461_phone(n serial primary key, k text);
create function pg_temp.t461_id(p_k text) returns uuid language sql as $f$ select id from t461 where k = p_k $f$;
create function pg_temp.t461_check(p_ok boolean, p_label text) returns void language plpgsql as $f$
begin
  if not coalesce(p_ok, false) then raise exception 'FAIL %', p_label; end if;
end $f$;
create function pg_temp.t461_fingerprint() returns text language sql as $f$
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.oid::regprocedure::text)) || ' ' || count(*)
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prokind in ('f', 'p') $f$;
create function pg_temp.t461_in() returns boolean language sql as $f$
  select position('-- 461 (the Owner' in pg_get_functiondef('public.invoice_transferable_benefits(uuid)'::regprocedure)) > 0
     and position('-- 461 (the Owner' in pg_get_functiondef('public.move_invoice_benefits_to_customer(uuid,uuid,uuid,text)'::regprocedure)) > 0 $f$;
-- 460 (built beside 461: what a reopened invoice gives back goes to whoever
-- its benefits belong to now; it changes 461's two functions outside 461's
-- part).
create function pg_temp.t461_460_in() returns boolean language sql as $f$
  select to_regprocedure('public.invoice_benefits_holder(uuid,uuid,timestamp with time zone)') is not null
     and position('-- 460 (the Owner' in pg_get_functiondef('public.apply_reopened_invoice_benefits()'::regprocedure)) > 0 $f$;
-- 462 (move-merge-leftovers-462.sql), where it is in: an Owner's Move is no
-- claim on a lot any more (the moved credit is traced through the Move's
-- own ledger rows, so the records follow a change), a reissued lot a
-- benefit row names is judged by that row, and credit a refunded sale gives
-- back follows to whoever holds the benefits (at commit: t461_commit runs
-- that here). Its claims K12 and K13 then move (checked the fixed way).
create function pg_temp.t461_462_in() returns boolean language sql as $f$
  select to_regprocedure('public.credit_given_back_follows(uuid)') is not null
     and exists (select 1 from pg_trigger where tgname = 'credit_given_back_follows'
                  and tgrelid = 'public.customer_credit_ledger'::regclass) $f$;
create function pg_temp.t461_commit() returns void language plpgsql as $f$
begin
  if pg_temp.t461_462_in() then
    execute 'set constraints public.credit_given_back_follows immediate';
    execute 'set constraints public.credit_given_back_follows deferred';
  end if;
end $f$;
-- 461's two functions as installed: 461's AFTERs alone, or with 460 in (in
-- either order), or with 462 over both (462's AFTERs), or with 463 over 462
-- (463's AFTERs: a Move to the same customer at another store and a Premium
-- Bundle's vouchers go along too, the Owner's decisions 2 and 3), or with
-- 473 over 463 (473's AFTER of the list: a lot judged with the other lots of
-- its package line, which only a package paid in part has; no case here is
-- one, so every case ends as with 463), or with 476 over 473 (476's AFTERs
-- of the list and the mover: one more row, for the credit a package paid in
-- part has still to release once what it released was spent, and a lot of
-- credit released before full payment judged by its release record; no case
-- here is a package paid in part either).
create function pg_temp.t461_463_in() returns boolean language sql as $f$
  select to_regprocedure('public.invoice_benefit_moved_to_other(uuid)') is not null $f$;
create function pg_temp.t461_as_tested() returns boolean language sql as $f$
  select (md5(pg_get_functiondef('public.invoice_transferable_benefits(uuid)'::regprocedure)),
          md5(pg_get_functiondef('public.move_invoice_benefits_to_customer(uuid,uuid,uuid,text)'::regprocedure)))
         in (('ab86a3fa6305d1efd49d0ee7d7e688f6', 'dd592a5cf2383c84bcf0986dd0f01523'),
             ('362d6d076c4751ab5dbe760f6d7a0d37', 'c1827889748d29f7a6626294333bd94f'),
             ('d0d19b7c765337c3cd68096fdc6de7dd', '130c25c6ce3d91b7b421e6f4c3d02353'),
             ('68736a39ed765ee787242bc62bbaeebb', 'c01606c84ee13ddcd88c15521d6d9aed'),
             ('a2332a22fe9975667e848de0d1e4480b', 'c01606c84ee13ddcd88c15521d6d9aed'),
             ('1546de1f83d970424d26e65941f4dcb8', '142dd3252911480bd4a17e7c55b488d3')) $f$;
create function pg_temp.t461_grants(p_sig text) returns text language sql as $f$
  select coalesce(string_agg(x::text, ',' order by x::text), '') from pg_proc p, unnest(p.proacl) x
   where p.oid = to_regprocedure('public.' || p_sig) $f$;

do $$
declare own uuid := gen_random_uuid(); st uuid; pm uuid; v uuid; cpb uuid; pbb uuid;
begin
  insert into auth.users(id, email) values (own, 't461-owner@example.com');
  insert into profiles(id, full_name, email, role, is_active) values (own, 'T461 Owner', 't461-owner@example.com', 'owner', true);
  perform set_config('request.jwt.claims', json_build_object('sub', own, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', own::text, true);
  insert into stores(name, code, country_code) values ('T461 Store', 'T461S1', 'SG') returning id into st;
  insert into payment_methods(name, is_active) values ('T461 Cash', true) returning id into pm;
  insert into vouchers(name, code, voucher_kind, qty_type, selling_price, is_active)
    values ('T461 Plain 30', 'T461-P30', 'normal', 'unlimited', 30, true) returning id into v;
  insert into voucher_store_prices(voucher_id, store_id, selling_price, available_at_store) values (v, st, 30, true);
  -- A S$100 Credit Package with a S$10 Bonus (its Paid benefit is worth
  -- S$90.91 of the price, its Bonus S$9.09), and a Premium Bundle of S$100
  -- Paid and S$20 Bonus for S$100.
  insert into credit_packages(name, customer_price, paid_credit_amount, bonus_enabled, bonus_value, allow_product, allow_therapy, grants_reward)
    values ('T461 S$100 + S$10', 100, 100, true, 10, true, true, false) returning id into cpb;
  insert into credit_package_stores(package_id, store_id) values (cpb, st);
  insert into premium_bundles(name, customer_payment_amount, paid_credit_amount, bonus_credit_amount, free_voucher_qty, grants_reward)
    values ('T461 Bundle S$100 + S$20', 100, 100, 20, 0, false) returning id into pbb;
  insert into premium_bundle_stores(bundle_id, store_id) values (pbb, st);
  insert into t461 values ('own', own), ('store', st), ('pm', pm), ('v', v), ('cpb', cpb), ('pbb', pbb);
  -- Therapy sessions of S$30 and S$56, paid from the package's Paid credit
  -- ("Wallet — Credit Package Paid", the payment method the Pay dialog offers
  -- for it): credit spent on another invoice, which comes back to the lot
  -- when that invoice is refunded.
  insert into t461 values
    ('s30', (upsert_therapy_service(null, 'T461-S30', 'T461 Session 30', 30, 30, 'per_hours', 1, 5, null, true, null) ->> 'id')::uuid),
    ('s56', (upsert_therapy_service(null, 'T461-S56', 'T461 Session 56', 56, 30, 'per_hours', 1, 5, null, true, null) ->> 'id')::uuid),
    ('wallet', (select id from payment_methods where name = 'Wallet — Credit Package Paid' and is_active));
  perform set_therapy_service_store(pg_temp.t461_id('s30'), st, true, null);
  perform set_therapy_service_store(pg_temp.t461_id('s56'), st, true, null);
  if pg_temp.t461_id('wallet') is null then raise exception 'FIXTURE: no "Wallet — Credit Package Paid" payment method'; end if;
end $$;

-- ── The app's calls ─────────────────────────────────────────────────────────
-- A customer of this run, named for its case (each case has its own).
create function pg_temp.t461_cust(p_k text) returns uuid language plpgsql as $f$
declare n int; c uuid;
begin
  insert into t461_phone(k) values (p_k) returning t461_phone.n into n;
  if n > 99 then raise exception 'Fixture: out of fictional phones'; end if;
  insert into customers(full_name, phone) values ('T461 ' || p_k, '+614915705' || lpad(n::text, 2, '0')) returning id into c;
  insert into t461 values (p_k, c);
  return c;
end $f$;
-- The invoice form with the lines given ('cpb' a Credit Package, 'pbb' a
-- Premium Bundle, 'v' a voucher line of p_qtys[i]), paid through the Pay
-- dialog (all of it, or p_pay), for p_cust.
create function pg_temp.t461_sale(p_cust text, p_kinds text[], p_qtys int[] default null, p_pay numeric default null) returns uuid language plpgsql as $f$
declare inv uuid; v_lines jsonb := '[]'; i int;
begin
  for i in 1 .. cardinality(p_kinds) loop
    v_lines := v_lines || jsonb_build_array(case
      when p_kinds[i] = 'v' then jsonb_build_object('kind', 'voucher', 'voucher_id', pg_temp.t461_id('v'), 'quantity', coalesce(p_qtys[i], 1))
      when p_kinds[i] = 'pbb' then jsonb_build_object('kind', 'premium_bundle', 'premium_bundle_id', pg_temp.t461_id('pbb'), 'quantity', 1)
      else jsonb_build_object('kind', 'credit_package', 'credit_package_id', pg_temp.t461_id('cpb'), 'quantity', 1) end);
  end loop;
  inv := create_invoice_with_details(pg_temp.t461_id('store'), pg_temp.t461_id(p_cust), v_lines,
    jsonb_build_object('business_date', sg_today()::text));
  perform record_invoice_settlement(inv, jsonb_build_object('receipts', jsonb_build_array(jsonb_build_object(
    'key', 'line-0', 'payment_method_id', pg_temp.t461_id('pm'), 'amount', coalesce(p_pay, (select total_amount from invoices where id = inv)),
    'payment_date', sg_today()::text)), 'arrangements', '[]'::jsonb), gen_random_uuid());
  return inv;
end $f$;
-- A therapy session ('s30' or 's56') on an invoice of p_cust's own, paid
-- through the Pay dialog from the customer's Paid package credit.
create function pg_temp.t461_wallet(p_cust text, p_svc text) returns uuid language plpgsql as $f$
declare y uuid;
begin
  y := create_invoice_with_details(pg_temp.t461_id('store'), pg_temp.t461_id(p_cust),
    jsonb_build_array(jsonb_build_object('kind', 'therapy', 'therapy_service_id', pg_temp.t461_id(p_svc), 'quantity', 1)),
    jsonb_build_object('business_date', sg_today()::text));
  perform record_invoice_payment(y, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.t461_id('wallet'),
    'amount', (select total_amount from invoices where id = y))), gen_random_uuid());
  if (select status::text from invoices where id = y) <> 'paid' then raise exception 'Fixture: the session paid from credit is %', (select status from invoices where id = y); end if;
  return y;
end $f$;
-- Record Payment: what is outstanding.
create function pg_temp.t461_pay(p_inv uuid) returns void language plpgsql as $f$
begin
  perform record_invoice_payment(p_inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.t461_id('pm'),
    'amount', (invoice_financial_position(p_inv)->>'outstanding')::numeric)), gen_random_uuid());
end $f$;
-- The receipts that still hold p_amount between them, as the Finance panel
-- splits a refund across them.
create function pg_temp.t461_sources(p_inv uuid, p_amount numeric) returns jsonb language plpgsql as $f$
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
create function pg_temp.t461_line(p_inv uuid, p_n int) returns uuid language sql as $f$
  select id from invoice_items where invoice_id = p_inv order by id offset p_n - 1 limit 1 $f$;
-- The Finance panel's refund by line of the invoice's n-th line: every
-- unused benefit of it at what it can still refund (p_paid null), or
-- p_paid off its Paid benefit and p_bonus off its Bonus. 'recorded', or the
-- refusal.
create function pg_temp.t461_cline_back(p_inv uuid, p_n int, p_paid numeric default null, p_bonus numeric default null)
  returns text language plpgsql as $f$
declare opts jsonb; ben jsonb; tot numeric; item uuid := pg_temp.t461_line(p_inv, p_n);
begin
  opts := invoice_refund_options_before_sessions(p_inv);
  if p_paid is null then
    select jsonb_agg(jsonb_build_object('benefit_id', b->>'id', 'amount', (b->>'max_refund')::numeric)), sum((b->>'max_refund')::numeric)
      into ben, tot from jsonb_array_elements(opts->'benefits') b
     where b->>'invoice_item_id' = item::text and (b->>'max_refund')::numeric > 0;
  else
    select jsonb_agg(jsonb_build_object('benefit_id', b->>'id',
             'amount', case when b->>'benefit_kind' = 'paid' then p_paid else p_bonus end)),
           sum(case when b->>'benefit_kind' = 'paid' then p_paid else p_bonus end)
      into ben, tot from jsonb_array_elements(opts->'benefits') b
     where b->>'invoice_item_id' = item::text
       and (b->>'benefit_kind' = 'paid' or b->>'benefit_kind' = 'bonus' and p_bonus is not null);
  end if;
  perform refund_invoice_recorded(p_inv, jsonb_build_array(jsonb_build_object('invoice_item_id', item, 'amount', tot, 'benefits', ben)),
    pg_temp.t461_sources(p_inv, tot), '[]'::jsonb, 'T461 credit paid back', gen_random_uuid());
  return 'recorded';
exception when others then return sqlerrm;
end $f$;
-- The guided Refund / Cancel as an Owner confirms it (InvoiceGuidedAction):
-- the plan, the request, the approval with a reason for every override the
-- plan asks for; the money recorded as paid back when p_record. Returns the
-- codes the plan asked for ('-' for none), or 'ERR ' and the refusal.
create function pg_temp.t461_guided(p_inv uuid, p_action text, p_lines jsonb default '[]', p_record boolean default false)
  returns text language plpgsql as $f$
declare plan jsonb; req jsonb; ov jsonb;
begin
  plan := invoice_action_plan(p_inv, p_action, p_lines);
  req := request_invoice_action_v2(p_inv, p_action, p_lines, 'T461 ' || p_action, null, gen_random_uuid());
  select coalesce(jsonb_agg(case when coalesce((o->>'amount_required')::boolean, false)
           then jsonb_build_object('code', o->>'code', 'reason', 'T461 override', 'amount', (o->>'default_amount')::numeric)
           else jsonb_build_object('code', o->>'code', 'reason', 'T461 override') end), '[]'::jsonb)
    into ov from jsonb_array_elements(coalesce(plan->'overrides_required', '[]')) o;
  perform resolve_invoice_action_v2((req->>'request_id')::uuid, true, 'T461 ' || p_action, plan->>'plan_hash', ov, null, p_record);
  return (select coalesce(string_agg(o->>'code', ',' order by o->>'code'), '-')
            from jsonb_array_elements(coalesce(plan->'overrides_required', '[]')) o);
exception when others then return 'ERR ' || sqlerrm;
end $f$;
-- The guided "Refund some items": p_qty units of the n-th line, recorded.
create function pg_temp.t461_refund_some(p_inv uuid, p_n int, p_qty int) returns void language plpgsql as $f$
declare r text;
begin
  r := pg_temp.t461_guided(p_inv, 'refund_partial',
    jsonb_build_array(jsonb_build_object('invoice_item_id', pg_temp.t461_line(p_inv, p_n), 'quantity', p_qty)), true);
  if r like 'ERR %' then raise exception 'Fixture: the guided refund of line % failed: %', p_n, r; end if;
end $f$;
-- The Finance panel's refund by line of what a cancelled invoice still owes
-- (it goes by line for credit): the cancel plan's lines and their benefits.
create function pg_temp.t461_by_line(p_inv uuid) returns text language plpgsql as $f$
declare plan jsonb; v_lines jsonb; tot numeric;
begin
  plan := invoice_action_plan(p_inv, 'cancel', '[]');
  select jsonb_agg(jsonb_build_object('invoice_item_id', l->>'invoice_item_id', 'amount', (l->>'amount')::numeric,
           'benefits', (select coalesce(jsonb_agg(jsonb_build_object('benefit_id', x->>'benefit_id', 'amount', (x->>'amount')::numeric)), '[]'::jsonb)
                          from jsonb_array_elements(l->'benefits') x))),
         sum((l->>'amount')::numeric)
    into v_lines, tot from jsonb_array_elements(plan->'lines') l where (l->>'amount')::numeric > 0;
  if v_lines is null then return 'nothing to allocate: the cancel plan''s lines are S$0'; end if;
  perform refund_invoice_recorded(p_inv, v_lines, pg_temp.t461_sources(p_inv, tot), '[]'::jsonb, 'T461 by line', gen_random_uuid());
  return 'recorded';
exception when others then return sqlerrm;
end $f$;
-- The invoice form's customer change, the benefits taken along: 'changed',
-- or the refusal.
create function pg_temp.t461_change(p_inv uuid, p_cust text) returns text language plpgsql as $f$
declare x jsonb;
begin
  select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('invoice_item_id', it.id, 'kind', it.line_kind,
           'credit_package_id', it.credit_package_id, 'premium_bundle_id', it.premium_bundle_id, 'voucher_id', it.voucher_id,
           'quantity', it.quantity, 'unit_price', it.unit_price, 'voucher_selection', it.bundle_voucher_selection)) order by it.id)
    into x from invoice_items it where it.invoice_id = p_inv;
  perform correct_invoice(p_inv, x, jsonb_build_object('expected_edit_count', (select edit_count from invoices where id = p_inv),
    'customer_id', pg_temp.t461_id(p_cust), 'store_id', pg_temp.t461_id('store'), 'benefit_action', 'transfer'),
    'T461 wrong customer', gen_random_uuid());
  return 'changed';
exception when others then return sqlerrm;
end $f$;
-- What a customer holds: each lot as 'category remaining/original', and
-- each held voucher's units.
create function pg_temp.t461_holds(p_cust text) returns text language sql as $f$
  select coalesce((select string_agg(l.category || ' ' || l.remaining_amount || '/' || l.original_amount, ', '
                                     order by l.category, l.remaining_amount, l.original_amount)
                     from customer_credit_lots l where l.customer_id = pg_temp.t461_id(p_cust)), 'no credit')
      || ' | ' || coalesce((select sum(v.quantity) || ' voucher(s)' from customer_reward_vouchers v
                             where v.customer_id = pg_temp.t461_id(p_cust) and v.status = 'held'), 'no voucher') $f$;
-- The invoice form's customer change keeping the benefits with whoever
-- holds them ('keep'): 'kept', or the refusal.
create function pg_temp.t461_keep(p_inv uuid, p_cust text) returns text language plpgsql as $f$
declare x jsonb;
begin
  select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('invoice_item_id', it.id, 'kind', it.line_kind,
           'credit_package_id', it.credit_package_id, 'premium_bundle_id', it.premium_bundle_id, 'voucher_id', it.voucher_id,
           'quantity', it.quantity, 'unit_price', it.unit_price, 'voucher_selection', it.bundle_voucher_selection)) order by it.id)
    into x from invoice_items it where it.invoice_id = p_inv;
  perform correct_invoice(p_inv, x, jsonb_build_object('expected_edit_count', (select edit_count from invoices where id = p_inv),
    'customer_id', pg_temp.t461_id(p_cust), 'store_id', pg_temp.t461_id('store'), 'benefit_action', 'keep'),
    'T461 wrong customer', gen_random_uuid());
  return 'kept';
exception when others then return sqlerrm;
end $f$;
-- The refund options the Finance panel reads for the invoice's benefits
-- (each row's remaining value and what it can still refund).
create function pg_temp.t461_options(p_inv uuid) returns jsonb language sql as $f$
  select coalesce(jsonb_agg(jsonb_build_object('id', b->>'id', 'remaining', b->>'remaining_value', 'max', b->>'max_refund')
                            order by b->>'id'), '[]'::jsonb)
    from jsonb_array_elements(invoice_refund_options_before_sessions(p_inv)->'benefits') b $f$;
-- The change tried and undone: its outcome and what the new customer then
-- holds (the same text before and after 461 for the controls).
create function pg_temp.t461_try_change(p_inv uuid, p_cust text) returns text language plpgsql as $f$
declare r text;
begin
  begin
    r := pg_temp.t461_change(p_inv, p_cust);
    if r = 'changed' then r := 'changed: ' || pg_temp.t461_holds(p_cust); end if;
    raise exception using errcode = 'Z4611', message = r;
  exception when sqlstate 'Z4611' then r := sqlerrm;
  end;
  return r;
end $f$;
-- Move (the Finance panel): the n-th line's Paid credit to p_cust.
create function pg_temp.t461_move(p_inv uuid, p_n int, p_cust text) returns void language plpgsql as $f$
begin
  perform transfer_invoice_unused_benefit((select b.id from invoice_benefit_values b
      join customer_credit_lots l on l.id = b.lot_id
     where b.invoice_item_id = pg_temp.t461_line(p_inv, p_n) and l.remaining_amount > 0 and l.category = 'paid'),
    pg_temp.t461_id(p_cust), pg_temp.t461_id('store'), 'T461 move', gen_random_uuid());
end $f$;
-- Credit spent: p_amount off the lot of the n-th line's Paid credit (or the
-- invoice's released lot, p_n null).
create function pg_temp.t461_spend(p_inv uuid, p_n int, p_amount numeric) returns void language plpgsql as $f$
begin
  update customer_credit_lots set remaining_amount = remaining_amount - p_amount
   where id = (select x.lot_id from invoice_credit_lot_ids(p_inv) x join customer_credit_lots l on l.id = x.lot_id
                where l.category = 'paid' and l.remaining_amount >= p_amount
                  and (p_n is null or x.lot_id in (select b.lot_id from invoice_benefit_values b
                                                    where b.invoice_item_id = pg_temp.t461_line(p_inv, p_n)))
                order by l.remaining_amount desc limit 1);
  if not found then raise exception 'Fixture: no Paid lot to spend S$% from on %', p_amount, p_inv; end if;
end $f$;
-- What the screens read: the list (whole, in a fixed order), the summary's
-- benefit parts, the plan's codes.
create function pg_temp.t461_list(p_inv uuid) returns jsonb language sql as $f$
  select coalesce(jsonb_agg(jsonb_build_object('kind', x.kind, 'what', x.description, 'units', x.units,
                                               'movable', x.movable, 'blocking', x.blocking, 'why', x.blocked_reason)
                            order by x.kind, x.description, coalesce(x.blocked_reason, ''), x.movable, x.blocking), '[]'::jsonb)
    from invoice_transferable_benefits(p_inv) x $f$;
create function pg_temp.t461_list_txt(p_inv uuid) returns text language sql as $f$
  select coalesce(string_agg((e->>'what') || case when (e->>'movable')::boolean then ' moves'
                                                  when (e->>'blocking')::boolean then ' BLOCKS' else ' stays' end
                             || coalesce(' (' || (e->>'why') || ')', ''), '; ' order by n), '-')
    from jsonb_array_elements(pg_temp.t461_list(p_inv)) with ordinality x(e, n) $f$;
create function pg_temp.t461_summary(p_inv uuid, p_cust text) returns jsonb language sql as $f$
  select jsonb_build_object(
    'moving', coalesce((select jsonb_agg(i->>'what' order by i->>'what') from jsonb_array_elements(p->'effects') e,
                          jsonb_array_elements(coalesce(e->'items', '[]')) i
                         where e->>'area' = 'benefits' and e->>'change' = 'transferring'), '[]'),
    'review', coalesce((select jsonb_agg((i->>'what') || ' — ' || (i->>'why') order by i->>'what') from jsonb_array_elements(p->'needs_review') e,
                          jsonb_array_elements(coalesce(e->'items', '[]')) i
                         where e->>'area' = 'benefits'), '[]'))
    from (select preview_invoice_correction(p_inv, jsonb_build_object('customer_id', pg_temp.t461_id(p_cust),
            'benefit_action', 'transfer')) as p) x $f$;
create function pg_temp.t461_codes(p_inv uuid, p_action text) returns text language sql as $f$
  select coalesce(string_agg(o->>'code', ',' order by o->>'code'), '-')
    from jsonb_array_elements(coalesce(invoice_action_plan(p_inv, p_action, '[]')->'overrides_required', '[]')) o $f$;
create function pg_temp.t461_money(p_inv uuid) returns text language sql as $f$
  select status::text || ' net ' || invoice_net_received(id) || ' due ' || (invoice_financial_position(id)->>'refund_due')
    from invoices where id = p_inv $f$;

-- ===== A. The cases and the controls, built before 461 =====
do $$
declare inv uuid; r text; k text;
begin
  foreach k in array array['CA', 'CB', 'CC', 'CD', 'CE', 'CF', 'CG', 'CH', 'CI', 'CJ', 'CK', 'CN', 'CM', 'CW'] loop insert into t461_case(k, kind) values (k, 'case'); end loop;
  foreach k in array array['K1', 'K2', 'K3', 'K4', 'K5', 'K6', 'K7', 'K8', 'K9', 'K10', 'K11', 'K12', 'K13', 'K14', 'V1', 'V2', 'V3'] loop insert into t461_case(k, kind) values (k, 'same'); end loop;
  for k in select c.k from t461_case c order by c.ord loop
    perform pg_temp.t461_cust(k || ' Buyer');
    perform pg_temp.t461_cust(k || ' New');
  end loop;
  perform pg_temp.t461_cust('CF Third');
  perform pg_temp.t461_cust('CG Third');
  perform pg_temp.t461_cust('CJ Third');
  perform pg_temp.t461_cust('K5 Friend');
  perform pg_temp.t461_cust('K6 Friend');
  perform pg_temp.t461_cust('K8 Kept');
  perform pg_temp.t461_cust('K12 Friend');
  perform pg_temp.t461_cust('K13 Friend');

  -- Cases.
  for k in select unnest(array['CA', 'CB', 'CF', 'CG', 'CJ', 'CN']) loop
    inv := pg_temp.t461_sale(k || ' Buyer', array['cpb']);
    r := pg_temp.t461_cline_back(inv, 1, 40);
    perform pg_temp.t461_check(r = 'recorded', k || ' S$40 of the Paid credit refunded by line: ' || r);
    insert into t461 values (k, inv);
  end loop;
  inv := pg_temp.t461_sale('CC Buyer', array['pbb']);
  perform pg_temp.t461_check(pg_temp.t461_cline_back(inv, 1, 40) = 'recorded', 'CC S$40 of the bundle''s Paid credit');
  insert into t461 values ('CC', inv);
  inv := pg_temp.t461_sale('CD Buyer', array['cpb', 'cpb']);
  perform pg_temp.t461_check(pg_temp.t461_cline_back(inv, 1) = 'recorded', 'CD line A wholly refunded');
  insert into t461 values ('CD', inv);
  inv := pg_temp.t461_sale('CE Buyer', array['cpb']);
  r := pg_temp.t461_cline_back(inv, 1, 40, 5);
  perform pg_temp.t461_check(r = 'recorded', 'CE S$40 of the Paid and S$5 of the Bonus: ' || r);
  insert into t461 values ('CE', inv);
  inv := pg_temp.t461_sale('CH Buyer', array['cpb', 'cpb']);
  perform pg_temp.t461_check(pg_temp.t461_cline_back(inv, 1) = 'recorded', 'CH line A wholly refunded');
  perform cancel_invoice_recorded(inv, 'T461 CH', gen_random_uuid());
  perform reopen_invoice(inv, 'T461 CH', gen_random_uuid());
  perform pg_temp.t461_check((select status::text from invoices where id = inv) = 'partially_paid'
    and (select count(*) from invoice_reopen_benefits where invoice_id = inv and applied_at is null) = 4, 'CH reopened, waiting');
  insert into t461 values ('CH', inv);
  inv := pg_temp.t461_sale('CI Buyer', array['cpb']);
  perform pg_temp.t461_check(pg_temp.t461_cline_back(inv, 1, 40) = 'recorded', 'CI S$40');
  perform cancel_invoice_recorded(inv, 'T461 CI', gen_random_uuid());
  insert into t461 values ('CI', inv);
  inv := pg_temp.t461_sale('CK Buyer', array['cpb']);
  perform pg_temp.t461_check(pg_temp.t461_cline_back(inv, 1, 40) = 'recorded', 'CK S$40');
  r := pg_temp.t461_guided(inv, 'refund_full', '[]', true);
  perform pg_temp.t461_check(r = '-' and pg_temp.t461_money(inv) = 'refunded net 0.00 due 0.00', 'CK the guided Refund in full: ' || r || ' / ' || pg_temp.t461_money(inv));
  insert into t461 values ('CK', inv);
  -- CM: S$30 of the Paid credit spent on a session; the guided Refund in full
  -- with the credit_used override pays back S$72.73 and takes back the S$70
  -- and S$10 left (the invoice stays paid, net S$27.27); then the session is
  -- refunded in full, which gives the S$30 back to the lot: nothing on it is
  -- spent any more.
  inv := pg_temp.t461_sale('CM Buyer', array['cpb']);
  insert into t461 values ('CM Y', pg_temp.t461_wallet('CM Buyer', 's30'));
  r := pg_temp.t461_guided(inv, 'refund_full', '[]', true);
  perform pg_temp.t461_check(r = 'credit_used' and pg_temp.t461_money(inv) = 'paid net 27.27 due 0.00', 'CM the guided Refund in full: ' || r || ' / ' || pg_temp.t461_money(inv));
  r := pg_temp.t461_guided(pg_temp.t461_id('CM Y'), 'refund_full', '[]', true);
  perform pg_temp.t461_check(r = '-' and pg_temp.t461_holds('CM Buyer') = 'bonus 0.00/10.00, paid 30.00/100.00 | no voucher',
    'CM the session refunded: ' || r || ' / ' || pg_temp.t461_holds('CM Buyer'));
  insert into t461 values ('CM', inv);
  -- CW: S$40 refunded by line, the S$56 left spent on a session; cancelled
  -- (credit_used; the refund due recorded), reopened (a reopening waits to
  -- give the S$44 and S$10 back), then the session refunded: S$56 back on
  -- the lot while the reopening waits.
  inv := pg_temp.t461_sale('CW Buyer', array['cpb']);
  perform pg_temp.t461_check(pg_temp.t461_cline_back(inv, 1, 40) = 'recorded', 'CW S$40');
  insert into t461 values ('CW Y', pg_temp.t461_wallet('CW Buyer', 's56'));
  r := pg_temp.t461_guided(inv, 'cancel', '[]', true);
  perform pg_temp.t461_check(r = 'credit_used' and pg_temp.t461_money(inv) = 'cancelled net 50.91 due 0.00', 'CW cancelled: ' || r || ' / ' || pg_temp.t461_money(inv));
  perform reopen_invoice(inv, 'T461 CW', gen_random_uuid());
  r := pg_temp.t461_guided(pg_temp.t461_id('CW Y'), 'refund_full', '[]', true);
  perform pg_temp.t461_check(r = '-' and (select status::text from invoices where id = inv) = 'partially_paid'
    and (select count(*) from invoice_reopen_benefits where invoice_id = inv and applied_at is null) = 2
    and pg_temp.t461_holds('CW Buyer') = 'bonus 0.00/10.00, paid 56.00/100.00 | no voucher',
    'CW reopened, waiting, the session refunded: ' || r || ' / ' || pg_temp.t461_money(inv) || ' / ' || pg_temp.t461_holds('CW Buyer'));
  insert into t461 values ('CW', inv);

  -- Controls.
  insert into t461 values ('K1', pg_temp.t461_sale('K1 Buyer', array['cpb']));
  inv := pg_temp.t461_sale('K2 Buyer', array['cpb']);
  perform pg_temp.t461_spend(inv, 1, 10);
  insert into t461 values ('K2', inv);
  inv := pg_temp.t461_sale('K3 Buyer', array['cpb']);
  perform pg_temp.t461_check(pg_temp.t461_cline_back(inv, 1, 40) = 'recorded', 'K3 S$40');
  perform pg_temp.t461_spend(inv, 1, 10);
  insert into t461 values ('K3', inv);
  inv := pg_temp.t461_sale('K4 Buyer', array['cpb']);
  perform pg_temp.t461_check(pg_temp.t461_cline_back(inv, 1, 40) = 'recorded', 'K4 S$40');
  perform pg_temp.t461_spend(inv, 1, 56);
  insert into t461 values ('K4', inv);
  inv := pg_temp.t461_sale('K5 Buyer', array['cpb']);
  perform pg_temp.t461_move(inv, 1, 'K5 Friend');
  insert into t461 values ('K5', inv);
  inv := pg_temp.t461_sale('K6 Buyer', array['cpb']);
  perform pg_temp.t461_check(pg_temp.t461_cline_back(inv, 1, 40) = 'recorded', 'K6 S$40');
  perform pg_temp.t461_move(inv, 1, 'K6 Friend');
  insert into t461 values ('K6', inv);
  inv := pg_temp.t461_sale('K7 Buyer', array['cpb']);
  perform cancel_invoice_recorded(inv, 'T461 K7', gen_random_uuid());
  insert into t461 values ('K7', inv);
  inv := pg_temp.t461_sale('K8 Buyer', array['cpb']);
  perform pg_temp.t461_check(pg_temp.t461_cline_back(inv, 1, 40) = 'recorded', 'K8 S$40');
  perform merge_customer_records(pg_temp.t461_id('K8 Kept'), pg_temp.t461_id('K8 Buyer'), 'T461 the same person', gen_random_uuid());
  insert into t461 values ('K8', inv);
  inv := pg_temp.t461_sale('K9 Buyer', array['cpb'], null, 30);
  perform pg_temp.t461_spend(inv, null, 10);
  perform pg_temp.t461_check((select count(*) from invoice_benefit_values where invoice_id = inv) = 0, 'K9 a part-paid package has no benefit row yet');
  insert into t461 values ('K9', inv);
  inv := pg_temp.t461_sale('K10 Buyer', array['cpb', 'cpb']);
  perform pg_temp.t461_check(pg_temp.t461_cline_back(inv, 1) = 'recorded', 'K10 line A wholly refunded');
  perform cancel_invoice_recorded(inv, 'T461 K10', gen_random_uuid());
  perform reopen_invoice(inv, 'T461 K10', gen_random_uuid());
  perform pg_temp.t461_pay(inv);
  perform pg_temp.t461_check((select status::text from invoices where id = inv) = 'paid', 'K10 settled');
  insert into t461 values ('K10', inv);
  -- K11: S$30 spent on a session; Cancel with the credit_used override (the
  -- refund due not recorded: S$72.73), so the cancellation still holds S$70
  -- and S$10 back; then the session refunded: S$30 back on the lot.
  inv := pg_temp.t461_sale('K11 Buyer', array['cpb']);
  insert into t461 values ('K11 Y', pg_temp.t461_wallet('K11 Buyer', 's30'));
  r := pg_temp.t461_guided(inv, 'cancel', '[]', false);
  perform pg_temp.t461_check(r = 'credit_used' and pg_temp.t461_money(inv) = 'cancelled net 100.00 due 72.73', 'K11 cancelled: ' || r || ' / ' || pg_temp.t461_money(inv));
  r := pg_temp.t461_guided(pg_temp.t461_id('K11 Y'), 'refund_full', '[]', true);
  perform pg_temp.t461_check(r = '-' and pg_temp.t461_holds('K11 Buyer') = 'bonus 0.00/10.00, paid 30.00/100.00 | no voucher',
    'K11 the session refunded: ' || r || ' / ' || pg_temp.t461_holds('K11 Buyer'));
  insert into t461 values ('K11', inv);
  -- K12: S$30 spent on a session; the S$70 left moved to a friend by an
  -- Owner (Move); then the session refunded: S$30 back on the buyer's lot.
  inv := pg_temp.t461_sale('K12 Buyer', array['cpb']);
  insert into t461 values ('K12 Y', pg_temp.t461_wallet('K12 Buyer', 's30'));
  perform pg_temp.t461_move(inv, 1, 'K12 Friend');
  r := pg_temp.t461_guided(pg_temp.t461_id('K12 Y'), 'refund_full', '[]', true);
  perform pg_temp.t461_check(r = '-' and pg_temp.t461_holds('K12 Buyer') = 'bonus 10.00/10.00, paid 30.00/100.00 | no voucher'
    and pg_temp.t461_holds('K12 Friend') = 'paid 70.00/70.00 | no voucher',
    'K12 moved, the session refunded: ' || r || ' / ' || pg_temp.t461_holds('K12 Buyer') || ' / ' || pg_temp.t461_holds('K12 Friend'));
  insert into t461 values ('K12', inv);
  -- K13: S$40 refunded by line; the S$56 left moved to a friend by an Owner;
  -- cancelled, reopened and paid: the S$44 refunded goes back on the
  -- buyer's lot.
  inv := pg_temp.t461_sale('K13 Buyer', array['cpb']);
  perform pg_temp.t461_check(pg_temp.t461_cline_back(inv, 1, 40) = 'recorded', 'K13 S$40');
  perform pg_temp.t461_move(inv, 1, 'K13 Friend');
  perform cancel_invoice_recorded(inv, 'T461 K13', gen_random_uuid());
  perform reopen_invoice(inv, 'T461 K13', gen_random_uuid());
  perform pg_temp.t461_pay(inv);
  perform pg_temp.t461_check(pg_temp.t461_money(inv) = 'paid net 100.00 due 0.00'
    and pg_temp.t461_holds('K13 Buyer') = 'bonus 10.00/10.00, paid 44.00/100.00 | no voucher'
    and pg_temp.t461_holds('K13 Friend') = 'paid 56.00/56.00 | no voucher',
    'K13 moved, cancelled, reopened and paid: ' || pg_temp.t461_money(inv) || ' / ' || pg_temp.t461_holds('K13 Buyer') || ' / ' || pg_temp.t461_holds('K13 Friend'));
  insert into t461 values ('K13', inv);
  -- K14: S$40 refunded by line, the S$56 left spent on a session; Cancel
  -- with the credit_used override (nothing left on the Paid lot to hold
  -- back); then the session refunded: S$56 back on the lot of a cancelled
  -- invoice.
  inv := pg_temp.t461_sale('K14 Buyer', array['cpb']);
  perform pg_temp.t461_check(pg_temp.t461_cline_back(inv, 1, 40) = 'recorded', 'K14 S$40');
  insert into t461 values ('K14 Y', pg_temp.t461_wallet('K14 Buyer', 's56'));
  r := pg_temp.t461_guided(inv, 'cancel', '[]', false);
  perform pg_temp.t461_check(r = 'credit_used' and pg_temp.t461_money(inv) = 'cancelled net 60.00 due 9.09', 'K14 cancelled: ' || r || ' / ' || pg_temp.t461_money(inv));
  r := pg_temp.t461_guided(pg_temp.t461_id('K14 Y'), 'refund_full', '[]', true);
  perform pg_temp.t461_check(r = '-' and pg_temp.t461_holds('K14 Buyer') = 'bonus 0.00/10.00, paid 56.00/100.00 | no voucher'
    and (select b.cancelled_unused_value from invoice_benefit_values b join customer_credit_lots l on l.id = b.lot_id
          where b.invoice_id = inv and l.category = 'paid') = 0,
    'K14 the session refunded: ' || r || ' / ' || pg_temp.t461_holds('K14 Buyer'));
  insert into t461 values ('K14', inv);
  inv := pg_temp.t461_sale('V1 Buyer', array['v'], array[2]);
  perform pg_temp.t461_refund_some(inv, 1, 1);
  insert into t461 values ('V1', inv);
  inv := pg_temp.t461_sale('V2 Buyer', array['v'], array[2]);
  perform pg_temp.t461_refund_some(inv, 1, 2);
  insert into t461 values ('V2', inv);
  inv := pg_temp.t461_sale('V3 Buyer', array['v'], array[2]);
  update customer_reward_vouchers set status = 'redeemed', redeemed_at = now()
   where id in (select b.reward_voucher_id from invoice_benefit_values b where b.invoice_id = inv) and status = 'held';
  insert into t461 values ('V3', inv);

  -- What each reads now, and its change tried and undone.
  for k in select c.k from t461_case c order by c.ord loop
    insert into t461_before values (k, pg_temp.t461_list(pg_temp.t461_id(k)),
      case when k = 'CN' then null else pg_temp.t461_try_change(pg_temp.t461_id(k), k || ' New') end,
      pg_temp.t461_summary(pg_temp.t461_id(k), k || ' New'));
  end loop;
  raise notice 'PASS A: % cases and % controls built (%)', (select count(*) from t461_case where kind = 'case'),
    (select count(*) from t461_case where kind = 'same'), case when pg_temp.t461_in() then '461 already in' else 'before 461' end;
end $$;

-- ===== R. Before 461: the cases read as found =====
\if :{?nomig}
do $$ begin raise notice 'NOTE R: -v nomig=1 (461 in), so the old answers are not reproduced'; end $$;
\else
do $$
declare b record;
begin
  perform pg_temp.t461_check(not pg_temp.t461_in(), 'R 461 is in already: run with -v nomig=1');
  -- CA: the Paid lot partly refunded (S$56 left of S$100) blocks as partly
  -- spent; the change is refused naming it; the summary asks a review.
  select * into b from t461_before where k = 'CA';
  perform pg_temp.t461_check(pg_temp.t461_list_txt(pg_temp.t461_id('CA')) = 'Bonus credit 10.00 moves; Paid credit 56.00 BLOCKS (Partly spent)'
    and b.tried = 'These benefits have already been used and cannot move with the invoice: Paid credit 56.00 (Partly spent). Resolve each one through the benefit transfer review before reassigning.'
    and b.summary = '{"moving": ["Bonus credit 10.00"], "review": ["Paid credit 56.00 — Partly spent"]}'::jsonb,
    'R CA before 461: ' || pg_temp.t461_list_txt(pg_temp.t461_id('CA')) || ' / ' || b.tried || ' / ' || b.summary::text);
  -- The other partly refunded ones the same.
  for b in select c.k from t461_case c where c.k in ('CB', 'CF', 'CG', 'CJ', 'CN') loop
    perform pg_temp.t461_check(pg_temp.t461_list_txt(pg_temp.t461_id(b.k)) = 'Bonus credit 10.00 moves; Paid credit 56.00 BLOCKS (Partly spent)'
      and (b.k = 'CN' or (select tried from t461_before where k = b.k) like 'These benefits have already been used and cannot move with the invoice: Paid credit 56.00 (Partly spent).%'),
      'R ' || b.k || ' before 461: ' || pg_temp.t461_list_txt(pg_temp.t461_id(b.k)));
  end loop;
  perform pg_temp.t461_check(pg_temp.t461_list_txt(pg_temp.t461_id('CC')) = 'Bonus credit 20.00 moves; Paid credit 52.00 BLOCKS (Partly spent)'
    and (select tried from t461_before where k = 'CC') like 'These benefits have already been used and cannot move with the invoice: Paid credit 52.00 (Partly spent).%',
    'R CC before 461: ' || pg_temp.t461_list_txt(pg_temp.t461_id('CC')));
  perform pg_temp.t461_check(pg_temp.t461_list_txt(pg_temp.t461_id('CE')) = 'Bonus credit 4.50 BLOCKS (Partly spent); Paid credit 56.00 BLOCKS (Partly spent)'
    and (select tried from t461_before where k = 'CE') like 'These benefits have already been used and cannot move with the invoice: %Partly spent%Partly spent%',
    'R CE before 461: ' || pg_temp.t461_list_txt(pg_temp.t461_id('CE')));
  -- CD: line A's two lots, wholly refunded, read "Fully spent" (the change
  -- goes: they are empty).
  perform pg_temp.t461_check(pg_temp.t461_list_txt(pg_temp.t461_id('CD')) =
      'Bonus credit 0.00 stays (Fully spent; it stays with the original customer); Bonus credit 10.00 moves; '
      || 'Paid credit 0.00 stays (Fully spent; it stays with the original customer); Paid credit 100.00 moves'
    and (select tried from t461_before where k = 'CD') = 'changed: bonus 10.00/10.00, paid 100.00/100.00 | no voucher',
    'R CD before 461: ' || pg_temp.t461_list_txt(pg_temp.t461_id('CD')) || ' / ' || (select tried from t461_before where k = 'CD'));
  -- CH, CI and CK: what a refund took reads "Fully spent" too.
  perform pg_temp.t461_check(pg_temp.t461_list_txt(pg_temp.t461_id('CK')) = 'Bonus credit 0.00 stays (Fully spent; it stays with the original customer); Paid credit 0.00 stays (Fully spent; it stays with the original customer)'
    and (select tried from t461_before where k = 'CK') = 'changed: no credit | no voucher',
    'R CK before 461: ' || pg_temp.t461_list_txt(pg_temp.t461_id('CK')));
  perform pg_temp.t461_check(pg_temp.t461_list_txt(pg_temp.t461_id('CH')) not like '%Refunded%'
    and pg_temp.t461_list_txt(pg_temp.t461_id('CI')) = 'Bonus credit 0.00 stays (Fully spent; it stays with the original customer); Paid credit 0.00 stays (Fully spent; it stays with the original customer)',
    'R CH, CI before 461: ' || pg_temp.t461_list_txt(pg_temp.t461_id('CH')) || ' / ' || pg_temp.t461_list_txt(pg_temp.t461_id('CI')));
  -- CM: the S$30 back on the lot blocks as "Partly spent"; CW: the S$56 back
  -- while a reopening waits blocks too, its Bonus (refunded) reads "Fully
  -- spent".
  perform pg_temp.t461_check(pg_temp.t461_list_txt(pg_temp.t461_id('CM')) = 'Bonus credit 0.00 stays (Fully spent; it stays with the original customer); Paid credit 30.00 BLOCKS (Partly spent)'
    and (select tried from t461_before where k = 'CM') like 'These benefits have already been used and cannot move with the invoice: Paid credit 30.00 (Partly spent).%'
    and pg_temp.t461_list_txt(pg_temp.t461_id('CW')) = 'Bonus credit 0.00 stays (Fully spent; it stays with the original customer); Paid credit 56.00 BLOCKS (Partly spent)'
    and (select tried from t461_before where k = 'CW') like 'These benefits have already been used and cannot move with the invoice: Paid credit 56.00 (Partly spent).%',
    'R CM, CW before 461: ' || pg_temp.t461_list_txt(pg_temp.t461_id('CM')) || ' / ' || pg_temp.t461_list_txt(pg_temp.t461_id('CW')));
  raise notice 'PASS R: before 461, a lot partly refunded and not spent blocks a customer change as "Partly spent" (Credit Package, Premium Bundle, Paid and Bonus), the change is refused naming it and its summary asks a review; a lot a refund emptied reads "Fully spent" (CA: %)',
    (select tried from t461_before where k = 'CA');
end $$;
\endif

-- ===== Q. 461's header query, before 461 is installed =====
\if :{?nomig}
do $$ begin raise notice 'NOTE Q: -v nomig=1 (461 in), so the header''s query is not run before it'; end $$;
\else
insert into t461_q
select i.invoice_no, i.status::text as status,
       count(*) filter (where l.remaining_amount > 0) as lots_no_longer_blocking,
       count(*) filter (where l.remaining_amount = 0) as lots_now_read_refunded,
       count(*) filter (where l.remaining_amount > 0 and l.status = 'active' and i.deleted_at is null
                          and l.customer_id is distinct from i.customer_id) as held_by_another_customer
  from public.invoice_benefit_values b
  join public.invoices i on i.id = b.invoice_id
  join public.customer_credit_lots l on l.id = b.lot_id
 where l.id in (select x.lot_id from public.invoice_credit_lot_ids(b.invoice_id) x)
   and l.remaining_amount < l.original_amount
   and l.remaining_amount + b.cancelled_unused_value + public.invoice_benefit_unused_elsewhere(b.id) >= b.granted_value
   and (l.remaining_amount > 0 and b.cancelled_unused_value = 0 and i.status not in ('cancelled', 'refunded')
          and not exists (select 1 from public.invoice_benefit_transfers t where t.source_benefit_id = b.id)
          and not exists (select 1 from public.invoice_reopen_benefits q where q.invoice_id = i.id and q.applied_at is null)
        or l.remaining_amount = 0 and public.invoice_benefit_unused_elsewhere(b.id) > 0
          and not exists (select 1 from public.invoice_benefit_transfers t
                           where t.source_benefit_id = b.id and t.replacement_benefit_id is not null))
 group by i.id, i.invoice_no, i.status
 order by i.invoice_no;
do $$ begin raise notice 'PASS Q: the header''s query, before 461, lists % invoice(s)', (select count(*) from t461_q); end $$;
\endif

-- ===== 9. Refusals (before 461) =====
\if :{?nomig}
do $$ begin raise notice 'NOTE 9: -v nomig=1 (461 in), so its refusals are not tried'; end $$;
\else
do $$
begin
  insert into t461_fp values ('start', pg_temp.t461_fingerprint());
  insert into t461_md5 select p.oid::regprocedure::text, md5(pg_get_functiondef(p.oid)) from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p');
  insert into t461_fp values ('grants', (select md5(string_agg(p.oid::regprocedure::text || '=' || coalesce(p.proacl::text, ''), '|' order by p.oid::regprocedure::text))
                                           from pg_proc p where p.pronamespace = 'public'::regnamespace));
end $$;
-- 9a an unknown version of a function it patches.
savepoint t461_r;
do $$ begin
  execute replace(pg_get_functiondef('public.move_invoice_benefits_to_customer(uuid,uuid,uuid,text)'::regprocedure),
                  'declare v_blocked text;', 'declare /* another version */ v_blocked text;');
end $$;
\set ON_ERROR_STOP off
\ir ../../../supabase/461_refunded_credit_is_not_spent_for_customer_change.sql
\set ON_ERROR_STOP on
rollback to savepoint t461_r;
select :'LAST_ERROR_MESSAGE' as t461_9a \gset
-- 9b an unknown version of a function it relies on.
do $$ begin
  execute replace(pg_get_functiondef('public.invoice_credit_lot_ids(uuid)'::regprocedure),
                  '-- The exact lots the credit package sale issued.', '-- The exact lots the credit package sale issued (another version).');
end $$;
\set ON_ERROR_STOP off
\ir ../../../supabase/461_refunded_credit_is_not_spent_for_customer_change.sql
\set ON_ERROR_STOP on
rollback to savepoint t461_r;
select :'LAST_ERROR_MESSAGE' as t461_9b \gset
-- 9c the cancel plans no longer testing a benefit with 448's helper.
do $$ begin
  execute replace(pg_get_functiondef('public.cancelled_invoice_used_value(uuid)'::regprocedure),
                  '+ public.invoice_benefit_unused_elsewhere(b.id)', '+ 0');
end $$;
\set ON_ERROR_STOP off
\ir ../../../supabase/461_refunded_credit_is_not_spent_for_customer_change.sql
\set ON_ERROR_STOP on
rollback to savepoint t461_r;
select :'LAST_ERROR_MESSAGE' as t461_9c \gset
-- 9d 448's helper missing.
drop function public.invoice_benefit_unused_elsewhere(uuid);
\set ON_ERROR_STOP off
\ir ../../../supabase/461_refunded_credit_is_not_spent_for_customer_change.sql
\set ON_ERROR_STOP on
rollback to savepoint t461_r;
select :'LAST_ERROR_MESSAGE' as t461_9d \gset
-- 9e a new caller of the move.
create function public.t461_new_caller(p uuid) returns jsonb language sql as
  $f$ select public.move_invoice_benefits_to_customer(p, p, p, 'x') $f$;
\set ON_ERROR_STOP off
\ir ../../../supabase/461_refunded_credit_is_not_spent_for_customer_change.sql
\set ON_ERROR_STOP on
rollback to savepoint t461_r;
select :'LAST_ERROR_MESSAGE' as t461_9e \gset
-- 9f the same grants listed in another order: installs (undone).
revoke execute on function public.invoice_transferable_benefits(uuid) from postgres;
grant execute on function public.invoice_transferable_benefits(uuid) to postgres;
select proacl::text as t461_9f_acl from pg_proc where oid = 'public.invoice_transferable_benefits(uuid)'::regprocedure \gset
\set ON_ERROR_STOP off
\ir ../../../supabase/461_refunded_credit_is_not_spent_for_customer_change.sql
\set t461_9f_failed :ERROR
\set ON_ERROR_STOP on
select pg_temp.t461_in() as t461_9f_in \gset
rollback to savepoint t461_r;
select pg_temp.t461_check(:'t461_9a' like '461: public.move_invoice_benefits_to_customer(uuid,uuid,uuid,text) is not the version this was tested against%',
         '9a an unknown version of the move: ' || :'t461_9a') as ok \gset
select pg_temp.t461_check(:'t461_9b' like '461: public.invoice_credit_lot_ids(uuid) is missing or not the version this was tested against%',
         '9b an unknown version of a function relied on: ' || :'t461_9b') as ok \gset
select pg_temp.t461_check(:'t461_9c' like '461: the cancel plans no longer test a benefit with invoice_benefit_unused_elsewhere (448)%',
         '9c the cancel plans without 448''s test: ' || :'t461_9c') as ok \gset
select pg_temp.t461_check(:'t461_9d' like '461: public.invoice_benefit_unused_elsewhere(uuid) is missing%',
         '9d 448''s helper missing: ' || :'t461_9d') as ok \gset
select pg_temp.t461_check(:'t461_9e' like '461: the functions that call move_invoice_benefits_to_customer are not as read on 22 Oct 2026 (correct_invoice(uuid,jsonb,jsonb,text,uuid), t461_new_caller(uuid))%',
         '9e a new caller of the move: ' || :'t461_9e') as ok \gset
select pg_temp.t461_check(:'t461_9f_failed' = 'false' and :'t461_9f_in' = 't'
         and :'t461_9f_acl' = '{service_role=X/postgres,authenticated=X/postgres,postgres=X/postgres}',
         '9f the same grants in another order (' || :'t461_9f_acl' || ') stop it') as ok \gset
-- 9g the gap's footprint: S$40 refunded, the customer changed keeping the
-- benefits, so the lot stayed with the buyer [G1]; beside it the same change
-- with the lot untouched [G2], with line A of two wholly refunded [G3], and
-- with S$10 spent beside the S$40 refunded [G4], and four lots 461 still
-- blocks [G6 to G9, below]; and a shared package's share partly refunded
-- [G5]. 461 stops, naming G1 and G5 alone.
do $$
declare inv uuid; k text;
begin
  foreach k in array array['G1 Buyer', 'G1 New', 'G2 Buyer', 'G2 New', 'G3 Buyer', 'G3 New', 'G4 Buyer', 'G4 New'] loop
    perform pg_temp.t461_cust(k); end loop;
  inv := pg_temp.t461_sale('G2 Buyer', array['cpb']);
  perform pg_temp.t461_check(pg_temp.t461_keep(inv, 'G2 New') = 'kept', '9g G2 kept');
  insert into t461 values ('G2', inv);
  inv := pg_temp.t461_sale('G3 Buyer', array['cpb', 'cpb']);
  perform pg_temp.t461_check(pg_temp.t461_cline_back(inv, 1) = 'recorded', '9g G3 line A wholly refunded');
  perform pg_temp.t461_check(pg_temp.t461_keep(inv, 'G3 New') = 'kept', '9g G3 kept');
  insert into t461 values ('G3', inv);
  inv := pg_temp.t461_sale('G4 Buyer', array['cpb']);
  perform pg_temp.t461_check(pg_temp.t461_cline_back(inv, 1, 40) = 'recorded', '9g G4 S$40');
  perform pg_temp.t461_spend(inv, 1, 10);
  perform pg_temp.t461_check(pg_temp.t461_keep(inv, 'G4 New') = 'kept', '9g G4 kept');
  insert into t461 values ('G4', inv);
  -- Credit back on a lot that 461 still blocks, held by the buyer after a
  -- change keeping the benefits: an Owner moved the rest (S$40 refunded,
  -- moved, cancelled, reopened and paid: S$44 back) [G6]; a cancellation
  -- still holds S$70 back (S$30 spent on a session, cancelled, the session
  -- refunded) [G7]; a cancelled invoice holding nothing back (S$40 refunded,
  -- S$56 spent, cancelled, the session refunded) [G8]; a reopening waiting
  -- (the same, cancelled and paid back, reopened, the session refunded)
  -- [G9]. None is named.
  foreach k in array array['G6 Buyer', 'G6 New', 'G6 Friend', 'G7 Buyer', 'G7 New', 'G8 Buyer', 'G8 New', 'G9 Buyer', 'G9 New'] loop
    perform pg_temp.t461_cust(k); end loop;
  inv := pg_temp.t461_sale('G6 Buyer', array['cpb']);
  perform pg_temp.t461_check(pg_temp.t461_cline_back(inv, 1, 40) = 'recorded', '9g G6 S$40');
  perform pg_temp.t461_move(inv, 1, 'G6 Friend');
  perform cancel_invoice_recorded(inv, 'T461 G6', gen_random_uuid());
  perform reopen_invoice(inv, 'T461 G6', gen_random_uuid());
  perform pg_temp.t461_pay(inv);
  perform pg_temp.t461_check(pg_temp.t461_keep(inv, 'G6 New') = 'kept' and pg_temp.t461_holds('G6 Buyer') = 'bonus 10.00/10.00, paid 44.00/100.00 | no voucher',
    '9g G6 kept: ' || pg_temp.t461_holds('G6 Buyer'));
  insert into t461 values ('G6', inv);
  inv := pg_temp.t461_sale('G7 Buyer', array['cpb']);
  insert into t461 values ('G7 Y', pg_temp.t461_wallet('G7 Buyer', 's30'));
  perform pg_temp.t461_check(pg_temp.t461_guided(inv, 'cancel', '[]', false) = 'credit_used', '9g G7 cancelled');
  perform pg_temp.t461_check(pg_temp.t461_guided(pg_temp.t461_id('G7 Y'), 'refund_full', '[]', true) = '-', '9g G7 the session refunded');
  perform pg_temp.t461_check(pg_temp.t461_keep(inv, 'G7 New') = 'kept' and pg_temp.t461_holds('G7 Buyer') = 'bonus 0.00/10.00, paid 30.00/100.00 | no voucher',
    '9g G7 kept: ' || pg_temp.t461_holds('G7 Buyer'));
  insert into t461 values ('G7', inv);
  inv := pg_temp.t461_sale('G8 Buyer', array['cpb']);
  perform pg_temp.t461_check(pg_temp.t461_cline_back(inv, 1, 40) = 'recorded', '9g G8 S$40');
  insert into t461 values ('G8 Y', pg_temp.t461_wallet('G8 Buyer', 's56'));
  perform pg_temp.t461_check(pg_temp.t461_guided(inv, 'cancel', '[]', false) = 'credit_used', '9g G8 cancelled');
  perform pg_temp.t461_check(pg_temp.t461_guided(pg_temp.t461_id('G8 Y'), 'refund_full', '[]', true) = '-', '9g G8 the session refunded');
  perform pg_temp.t461_check(pg_temp.t461_keep(inv, 'G8 New') = 'kept' and pg_temp.t461_holds('G8 Buyer') = 'bonus 0.00/10.00, paid 56.00/100.00 | no voucher',
    '9g G8 kept: ' || pg_temp.t461_holds('G8 Buyer'));
  insert into t461 values ('G8', inv);
  inv := pg_temp.t461_sale('G9 Buyer', array['cpb']);
  perform pg_temp.t461_check(pg_temp.t461_cline_back(inv, 1, 40) = 'recorded', '9g G9 S$40');
  insert into t461 values ('G9 Y', pg_temp.t461_wallet('G9 Buyer', 's56'));
  perform pg_temp.t461_check(pg_temp.t461_guided(inv, 'cancel', '[]', true) = 'credit_used', '9g G9 cancelled and paid back');
  perform reopen_invoice(inv, 'T461 G9', gen_random_uuid());
  perform pg_temp.t461_check(pg_temp.t461_guided(pg_temp.t461_id('G9 Y'), 'refund_full', '[]', true) = '-', '9g G9 the session refunded');
  perform pg_temp.t461_check(pg_temp.t461_keep(inv, 'G9 New') = 'kept' and pg_temp.t461_holds('G9 Buyer') = 'bonus 0.00/10.00, paid 56.00/100.00 | no voucher'
    and (select count(*) from invoice_reopen_benefits where invoice_id = inv and applied_at is null) = 2,
    '9g G9 kept while the reopening waits: ' || pg_temp.t461_holds('G9 Buyer'));
  insert into t461 values ('G9', inv);
end $$;
savepoint t461_g;
do $$
declare inv uuid; item uuid;
begin
  perform pg_temp.t461_cust('G5 Buyer'); perform pg_temp.t461_cust('G5 Share');
  inv := pg_temp.t461_sale('G1 Buyer', array['cpb']);
  perform pg_temp.t461_check(pg_temp.t461_cline_back(inv, 1, 40) = 'recorded', '9g G1 S$40');
  perform pg_temp.t461_check(pg_temp.t461_keep(inv, 'G1 New') = 'kept'
    and pg_temp.t461_list_txt(inv) = 'Bonus credit 10.00 moves; Paid credit 56.00 BLOCKS (Partly spent)'
    and pg_temp.t461_holds('G1 Buyer') = 'bonus 10.00/10.00, paid 56.00/100.00 | no voucher', '9g G1 kept: ' || pg_temp.t461_list_txt(inv));
  insert into t461 values ('G1', inv);
  -- G5 a shared package (an older invoice's split, 141), the share's Paid
  -- credit partly refunded by line.
  inv := create_invoice_with_details(pg_temp.t461_id('store'), pg_temp.t461_id('G5 Buyer'),
    jsonb_build_array(jsonb_build_object('kind', 'credit_package', 'credit_package_id', pg_temp.t461_id('cpb'), 'quantity', 1)),
    jsonb_build_object('business_date', sg_today()::text));
  select id into item from invoice_items where invoice_id = inv;
  perform set_invoice_credit_split(item, jsonb_build_array(jsonb_build_object('customer_id', pg_temp.t461_id('G5 Buyer'), 'amount', 40),
                                                           jsonb_build_object('customer_id', pg_temp.t461_id('G5 Share'), 'amount', 60)));
  perform pg_temp.t461_pay(inv);
  perform refund_invoice_recorded(inv, jsonb_build_array(jsonb_build_object('invoice_item_id', item, 'amount', 10,
      'benefits', (select jsonb_build_array(jsonb_build_object('benefit_id', b.id, 'amount', 10)) from invoice_benefit_values b
                     join customer_credit_lots l on l.id = b.lot_id
                    where b.invoice_id = inv and l.category = 'paid' and l.customer_id = pg_temp.t461_id('G5 Share')))),
    pg_temp.t461_sources(inv, 10), '[]'::jsonb, 'T461 G5', gen_random_uuid());
  perform pg_temp.t461_check((select count(*) from customer_credit_lots l where l.customer_id = pg_temp.t461_id('G5 Share')
                                and l.category = 'paid' and l.remaining_amount > 0 and l.remaining_amount < l.original_amount) = 1,
    '9g G5 the share''s Paid credit partly refunded: ' || pg_temp.t461_holds('G5 Share'));
  insert into t461 values ('G5', inv);
end $$;
select string_agg(invoice_no, ', ' order by invoice_no) as t461_9g_no from invoices where id in (pg_temp.t461_id('G1'), pg_temp.t461_id('G5')) \gset
\set ON_ERROR_STOP off
\ir ../../../supabase/461_refunded_credit_is_not_spent_for_customer_change.sql
\set ON_ERROR_STOP on
rollback to savepoint t461_g;
select :'LAST_ERROR_MESSAGE' as t461_9g \gset
-- 9h the same without G1 and G5 (G2 to G4 and G6 to G9 still there): 461
-- installs (undone).
\set ON_ERROR_STOP off
\ir ../../../supabase/461_refunded_credit_is_not_spent_for_customer_change.sql
\set t461_9h_failed :ERROR
\set ON_ERROR_STOP on
select pg_temp.t461_in() as t461_9h_in \gset
rollback to savepoint t461_r;
select pg_temp.t461_check(:'t461_9g' = '461: 2 invoice(s) have a partly refunded credit lot, not spent, held by someone other than the invoice''s customer ('
           || :'t461_9g_no' || '): the customer was changed keeping the benefits, or the lot is a shared package''s share. 461 would list that credit as moving with a later change. Decide where each should be, then apply. Nothing was changed.',
         '9g the footprint (' || :'t461_9g_no' || '): ' || :'t461_9g') as ok \gset
select pg_temp.t461_check(:'t461_9h_failed' = 'false' and :'t461_9h_in' = 't',
         '9h without the footprint 461 is refused or not in: ' || :'t461_9h_failed') as ok \gset
do $$
begin
  perform pg_temp.t461_check(pg_temp.t461_fingerprint() = (select fp from t461_fp where k = 'start') and not pg_temp.t461_in(),
    '9 a refused 461 changed functions');
  raise notice 'PASS 9: an unknown version of the move or of invoice_credit_lot_ids, the cancel plans without 448''s test, 448''s helper missing and a new caller of the move each stop 461, changing nothing; the same grants listed in another order do not; the gap''s footprint (S$40 refunded, the customer changed keeping the benefits) and a shared package''s share partly refunded stop it naming those invoices alone, and the same change with the lot untouched, wholly refunded, spent beside the refund, moved by an Owner, held back by a cancellation, on a cancelled invoice or while a reopening waits does not';
end $$;
\endif

-- ===== 10. Install 461, twice (on 455, or with 460 in first) =====
\if :{?nomig}
do $$ begin perform pg_temp.t461_check(pg_temp.t461_in(), '10 -v nomig=1 but 461 is not in'); end $$;
\else
\ir ../../../supabase/461_refunded_credit_is_not_spent_for_customer_change.sql
do $$ begin insert into t461_fp values ('first', pg_temp.t461_fingerprint()); end $$;
\ir ../../../supabase/461_refunded_credit_is_not_spent_for_customer_change.sql
do $$ begin insert into t461_fp values ('second', pg_temp.t461_fingerprint()); end $$;
\endif
do $$
declare tb text := 'invoice_transferable_benefits(uuid)'; mv text := 'move_invoice_benefits_to_customer(uuid,uuid,uuid,text)';
begin
  perform pg_temp.t461_check(pg_temp.t461_in() and pg_temp.t461_as_tested(), '10 461 is not installed as tested (the list '
    || md5(pg_get_functiondef(('public.' || tb)::regprocedure)) || ', the move ' || md5(pg_get_functiondef(('public.' || mv)::regprocedure)) || ')');
  -- With 460 in (installed before the suite, or before 461 on this copy),
  -- the texts both give; without it, 461's alone.
  -- (With 462 in too, 462's AFTER of the list; with 463 over it, 463's; with
  -- 473 over 463, 473's; with 476 over 473, 476's.)
  perform pg_temp.t461_check((md5(pg_get_functiondef(('public.' || tb)::regprocedure))
                              in ('362d6d076c4751ab5dbe760f6d7a0d37', 'd0d19b7c765337c3cd68096fdc6de7dd', '68736a39ed765ee787242bc62bbaeebb',
                                  'a2332a22fe9975667e848de0d1e4480b', '1546de1f83d970424d26e65941f4dcb8')) = pg_temp.t461_460_in()
      and (md5(pg_get_functiondef(('public.' || tb)::regprocedure)) in ('d0d19b7c765337c3cd68096fdc6de7dd', '68736a39ed765ee787242bc62bbaeebb',
                                                                         'a2332a22fe9975667e848de0d1e4480b', '1546de1f83d970424d26e65941f4dcb8')) = pg_temp.t461_462_in()
      and (md5(pg_get_functiondef(('public.' || tb)::regprocedure)) in ('68736a39ed765ee787242bc62bbaeebb', 'a2332a22fe9975667e848de0d1e4480b',
                                                                         '1546de1f83d970424d26e65941f4dcb8')) = pg_temp.t461_463_in(),
    '10 461''s texts do not match whether 460 is in (' || pg_temp.t461_460_in()::text || ') and 462 (' || pg_temp.t461_462_in()::text || ')');
  if exists (select 1 from t461_fp where k = 'first') then
    perform pg_temp.t461_check((select fp from t461_fp where k = 'second') = (select fp from t461_fp where k = 'first'),
      '10 the second run of 461 changed functions');
    perform pg_temp.t461_check(split_part((select fp from t461_fp where k = 'first'), ' ', 2) = split_part((select fp from t461_fp where k = 'start'), ' ', 2),
      '10 461 changed the number of functions');
    perform pg_temp.t461_check((select string_agg(m.sig, ', ' order by m.sig) from t461_md5 m
                                 where m.md5 is distinct from md5(pg_get_functiondef(to_regprocedure('public.' || m.sig)))) = tb || ', ' || mv,
      '10 461 changed another function: ' || (select string_agg(m.sig, ', ' order by m.sig) from t461_md5 m
                                 where m.md5 is distinct from md5(pg_get_functiondef(to_regprocedure('public.' || m.sig)))));
    perform pg_temp.t461_check((select md5(string_agg(p.oid::regprocedure::text || '=' || coalesce(p.proacl::text, ''), '|' order by p.oid::regprocedure::text))
                                  from pg_proc p where p.pronamespace = 'public'::regnamespace) = (select fp from t461_fp where k = 'grants'),
      '10 the grants changed');
  end if;
  perform pg_temp.t461_check((select count(*) from pg_proc where pronamespace = 'public'::regnamespace
                               and proname in ('invoice_transferable_benefits', 'move_invoice_benefits_to_customer')) = 2, '10 an overload exists');
  perform pg_temp.t461_check(has_function_privilege('authenticated', 'public.' || tb, 'execute') and has_function_privilege('service_role', 'public.' || tb, 'execute')
    and not has_function_privilege('anon', 'public.' || tb, 'execute')
    and has_function_privilege('service_role', 'public.' || mv, 'execute') and not has_function_privilege('authenticated', 'public.' || mv, 'execute')
    and not has_function_privilege('anon', 'public.' || mv, 'execute'), '10 who may call them changed');
  raise notice 'PASS 10: 461 installed (the list %, the move %; %); %; no overload; the list for signed-in staff and the service role, the move for the service role alone',
    md5(pg_get_functiondef(('public.' || tb)::regprocedure)), md5(pg_get_functiondef(('public.' || mv)::regprocedure)),
    case when pg_temp.t461_460_in() then 'with 460 in' else '460 not in' end,
    coalesce('only its two functions changed, the grants as before, and the second run changed nothing (' || (select fp from t461_fp where k = 'second') || ')',
             'it was in before the suite (nomig)');
end $$;
-- 10b With -v also460=<path of 460's file> (on a copy without 460): the
-- real 460 installed after 461, then 461 run again (left alone). Everything
-- after is then checked with both in.
\if :{?also460}
\i :also460
\ir ../../../supabase/461_refunded_credit_is_not_spent_for_customer_change.sql
do $$
begin
  perform pg_temp.t461_check(pg_temp.t461_460_in() and pg_temp.t461_in()
    and md5(pg_get_functiondef('public.invoice_transferable_benefits(uuid)'::regprocedure)) = '362d6d076c4751ab5dbe760f6d7a0d37'
    and md5(pg_get_functiondef('public.move_invoice_benefits_to_customer(uuid,uuid,uuid,text)'::regprocedure)) = 'c1827889748d29f7a6626294333bd94f',
    '10b 460 after 461 did not give the tested texts');
  raise notice 'PASS 10b: the real 460 installed after 461, and 461 run again left both alone (the list 362d6d07, the move c1827889: the texts 460 then 461 gives; %)',
    pg_temp.t461_fingerprint();
end $$;
\endif

-- ===== Q (after). The header's query listed exactly the invoices whose list changed =====
\if :{?nomig}
do $$ begin raise notice 'NOTE Q: -v nomig=1, so the query''s list is not compared'; end $$;
\else
do $$
declare v_changed text; v_listed text;
begin
  select string_agg(i.invoice_no, ', ' order by i.invoice_no) into v_changed
    from t461_before b join invoices i on i.id = pg_temp.t461_id(b.k)
   where b.list is distinct from pg_temp.t461_list(pg_temp.t461_id(b.k));
  select string_agg(invoice_no, ', ' order by invoice_no) into v_listed from t461_q;
  perform pg_temp.t461_check(v_changed = v_listed
    and v_changed = (select string_agg(i.invoice_no, ', ' order by i.invoice_no) from t461_case c join invoices i on i.id = pg_temp.t461_id(c.k)
                      where c.kind = 'case')
    and not exists (select 1 from t461_q where held_by_another_customer <> 0),
    'Q the header''s query lists ' || coalesce(v_listed, 'none') || '; the lists changed on ' || coalesce(v_changed, 'none'));
  raise notice 'PASS Q: the header''s query, run before 461, listed exactly the % invoices whose list changed (the cases), none held by another customer, and none of the controls',
    (select count(*) from t461_q);
end $$;
\endif

-- ===== 0. The controls read and change exactly as before 461 =====
do $$
declare c record; now_list jsonb; now_tried text;
begin
  for c in select x.k from t461_case x where x.kind = 'same' order by x.ord loop
    now_list := pg_temp.t461_list(pg_temp.t461_id(c.k));
    now_tried := pg_temp.t461_try_change(pg_temp.t461_id(c.k), c.k || ' New');
    if exists (select 1 from t461_fp where k = 'first') then
      perform pg_temp.t461_check(now_list = (select list from t461_before where k = c.k)
        and now_tried = (select tried from t461_before where k = c.k)
        and pg_temp.t461_summary(pg_temp.t461_id(c.k), c.k || ' New') = (select summary from t461_before where k = c.k),
        '0 ' || c.k || ' reads otherwise after 461: ' || pg_temp.t461_list_txt(pg_temp.t461_id(c.k)) || ' / ' || now_tried
        || ' (before: ' || (select list::text || ' / ' || tried from t461_before where k = c.k) || ')');
    end if;
  end loop;
  -- What they read (checked with or without the before/after comparison).
  perform pg_temp.t461_check(pg_temp.t461_list_txt(pg_temp.t461_id('K1')) = 'Bonus credit 10.00 moves; Paid credit 100.00 moves'
    and pg_temp.t461_try_change(pg_temp.t461_id('K1'), 'K1 New') = 'changed: bonus 10.00/10.00, paid 100.00/100.00 | no voucher', '0 K1 untouched');
  perform pg_temp.t461_check(pg_temp.t461_list_txt(pg_temp.t461_id('K2')) = 'Bonus credit 10.00 moves; Paid credit 90.00 BLOCKS (Partly spent)'
    and pg_temp.t461_try_change(pg_temp.t461_id('K2'), 'K2 New') like 'These benefits have already been used and cannot move with the invoice: Paid credit 90.00 (Partly spent).%',
    '0 K2 S$10 spent: ' || pg_temp.t461_list_txt(pg_temp.t461_id('K2')));
  perform pg_temp.t461_check(pg_temp.t461_list_txt(pg_temp.t461_id('K3')) = 'Bonus credit 10.00 moves; Paid credit 46.00 BLOCKS (Partly spent)'
    and pg_temp.t461_try_change(pg_temp.t461_id('K3'), 'K3 New') like 'These benefits have already been used and cannot move with the invoice: Paid credit 46.00 (Partly spent).%',
    '0 K3 S$40 refunded and S$10 spent: ' || pg_temp.t461_list_txt(pg_temp.t461_id('K3')));
  perform pg_temp.t461_check(pg_temp.t461_list_txt(pg_temp.t461_id('K4')) = 'Bonus credit 10.00 moves; Paid credit 0.00 stays (Fully spent; it stays with the original customer)',
    '0 K4 S$40 refunded and the rest spent: ' || pg_temp.t461_list_txt(pg_temp.t461_id('K4')));
  perform pg_temp.t461_check(pg_temp.t461_list_txt(pg_temp.t461_id('K8')) = 'Bonus credit 10.00 moves; Paid credit 56.00 moves'
    and pg_temp.t461_try_change(pg_temp.t461_id('K8'), 'K8 New') = 'changed: bonus 10.00/10.00, paid 56.00/56.00 | no voucher',
    '0 K8 merged after S$40 was refunded: ' || pg_temp.t461_list_txt(pg_temp.t461_id('K8')));
  perform pg_temp.t461_check(pg_temp.t461_list_txt(pg_temp.t461_id('K9')) = 'Paid credit 20.00 BLOCKS (Partly spent)',
    '0 K9 a part-paid package''s released credit, S$10 spent: ' || pg_temp.t461_list_txt(pg_temp.t461_id('K9')));
  perform pg_temp.t461_check(pg_temp.t461_list_txt(pg_temp.t461_id('K10')) = 'Bonus credit 10.00 moves; Bonus credit 10.00 moves; Paid credit 100.00 moves; Paid credit 100.00 moves',
    '0 K10 reopened and settled: ' || pg_temp.t461_list_txt(pg_temp.t461_id('K10')));
  -- Credit back on a lot (a session it paid for refunded, or a reopening
  -- settled) where something else still has a claim on it: a cancellation
  -- holding S$70 back [K11], an Owner's Move (the invoice's records stay on
  -- the buyer's lot) [K12, K13], a cancelled invoice [K14]. Each still
  -- blocks as "Partly spent" and the change is refused.
  perform pg_temp.t461_check(pg_temp.t461_list_txt(pg_temp.t461_id('K11')) = 'Bonus credit 0.00 stays (Fully spent; it stays with the original customer); Paid credit 30.00 BLOCKS (Partly spent)'
    and pg_temp.t461_try_change(pg_temp.t461_id('K11'), 'K11 New') like 'These benefits have already been used and cannot move with the invoice: Paid credit 30.00 (Partly spent).%'
    and pg_temp.t461_summary(pg_temp.t461_id('K11'), 'K11 New') = '{"moving": [], "review": ["Paid credit 30.00 — Partly spent"]}'::jsonb,
    '0 K11 a cancellation holding credit back: ' || pg_temp.t461_list_txt(pg_temp.t461_id('K11')) || ' / ' || pg_temp.t461_summary(pg_temp.t461_id('K11'), 'K11 New')::text);
  if pg_temp.t461_462_in() then
    -- 462: an Owner's Move is no claim any more (its records follow the
    -- change): nothing on the lot was spent, so it moves, with its records.
    perform pg_temp.t461_check(pg_temp.t461_list_txt(pg_temp.t461_id('K12')) = 'Bonus credit 10.00 moves; Paid credit 30.00 moves'
      and pg_temp.t461_try_change(pg_temp.t461_id('K12'), 'K12 New') = 'changed: bonus 10.00/10.00, paid 30.00/30.00 | no voucher',
      '0 (462) K12 moved by an Owner, the session refunded: ' || pg_temp.t461_list_txt(pg_temp.t461_id('K12'))
      || ' / ' || pg_temp.t461_try_change(pg_temp.t461_id('K12'), 'K12 New'));
    perform pg_temp.t461_check(pg_temp.t461_list_txt(pg_temp.t461_id('K13')) = 'Bonus credit 10.00 moves; Paid credit 44.00 moves'
      and pg_temp.t461_try_change(pg_temp.t461_id('K13'), 'K13 New') = 'changed: bonus 10.00/10.00, paid 44.00/44.00 | no voucher',
      '0 (462) K13 moved by an Owner, reopened and paid: ' || pg_temp.t461_list_txt(pg_temp.t461_id('K13'))
      || ' / ' || pg_temp.t461_try_change(pg_temp.t461_id('K13'), 'K13 New'));
  else
  perform pg_temp.t461_check(pg_temp.t461_list_txt(pg_temp.t461_id('K12')) = 'Bonus credit 10.00 moves; Paid credit 30.00 BLOCKS (Partly spent)'
    and pg_temp.t461_try_change(pg_temp.t461_id('K12'), 'K12 New') like 'These benefits have already been used and cannot move with the invoice: Paid credit 30.00 (Partly spent).%',
    '0 K12 moved by an Owner, the session refunded: ' || pg_temp.t461_list_txt(pg_temp.t461_id('K12')));
  perform pg_temp.t461_check(pg_temp.t461_list_txt(pg_temp.t461_id('K13')) = 'Bonus credit 10.00 moves; Paid credit 44.00 BLOCKS (Partly spent)'
    and pg_temp.t461_try_change(pg_temp.t461_id('K13'), 'K13 New') like 'These benefits have already been used and cannot move with the invoice: Paid credit 44.00 (Partly spent).%',
    '0 K13 moved by an Owner, reopened and paid: ' || pg_temp.t461_list_txt(pg_temp.t461_id('K13')));
  end if;
  perform pg_temp.t461_check(pg_temp.t461_list_txt(pg_temp.t461_id('K14')) = 'Bonus credit 0.00 stays (Fully spent; it stays with the original customer); Paid credit 56.00 BLOCKS (Partly spent)'
    and pg_temp.t461_try_change(pg_temp.t461_id('K14'), 'K14 New') like 'These benefits have already been used and cannot move with the invoice: Paid credit 56.00 (Partly spent).%',
    '0 K14 a cancelled invoice: ' || pg_temp.t461_list_txt(pg_temp.t461_id('K14')));
  perform pg_temp.t461_check(pg_temp.t461_list_txt(pg_temp.t461_id('V1')) = 'T461 Plain 30 × 1 moves'
    and pg_temp.t461_try_change(pg_temp.t461_id('V1'), 'V1 New') = 'changed: no credit | 1 voucher(s)'
    and pg_temp.t461_list_txt(pg_temp.t461_id('V2')) = 'T461 Plain 30 × 2 stays (Already revoked; it stays with the original customer)'
    and pg_temp.t461_list_txt(pg_temp.t461_id('V3')) = 'T461 Plain 30 × 2 stays (Already redeemed; it stays with the original customer)',
    '0 vouchers: ' || pg_temp.t461_list_txt(pg_temp.t461_id('V1')) || ' / ' || pg_temp.t461_list_txt(pg_temp.t461_id('V2')) || ' / ' || pg_temp.t461_list_txt(pg_temp.t461_id('V3')));
  raise notice 'PASS 0: the controls read and change exactly as before 461 (%): real spending still blocks as "Partly spent" (also beside a refund, and on released credit with no benefit row), credit spent to nothing still reads "Fully spent", a lot a merge reissued moves as before; credit back on a lot a cancellation still holds credit back for, or of a cancelled invoice, still blocks, and one whose benefit an Owner moved %; vouchers are unchanged (a unit refunded by line leaves the held units moving, a voucher wholly refunded reads "Already revoked", not used)',
    case when exists (select 1 from t461_fp where k = 'first') then 'compared whole, list and change' else 'their answers checked; -v nomig=1, not compared' end,
    case when pg_temp.t461_462_in() then 'moves (462 in)' else 'still blocks' end;
end $$;

-- ===== 1. Each case after 461 =====
do $$
declare inv uuid; r text; b_paid uuid; old_lot uuid; new_lot uuid; o record; n2 record; opts jsonb;
begin
  -- CA: the list, the summary, the change; the lot's origin and the
  -- invoice's records follow; nothing asked; Refund in full pays back the
  -- S$60 still held and takes back the S$66 from the new customer.
  inv := pg_temp.t461_id('CA');
  perform pg_temp.t461_check(pg_temp.t461_list_txt(inv) = 'Bonus credit 10.00 moves; Paid credit 56.00 moves'
    and pg_temp.t461_summary(inv, 'CA New') = '{"moving": ["Bonus credit 10.00", "Paid credit 56.00"], "review": []}'::jsonb,
    '1 CA after 461: ' || pg_temp.t461_list_txt(inv) || ' / ' || pg_temp.t461_summary(inv, 'CA New')::text);
  select b.id, b.lot_id into b_paid, old_lot from invoice_benefit_values b join customer_credit_lots l on l.id = b.lot_id
   where b.invoice_id = inv and l.category = 'paid';
  select * into o from customer_credit_lots where id = old_lot;
  opts := pg_temp.t461_options(inv);
  r := pg_temp.t461_change(inv, 'CA New');
  select b.lot_id into new_lot from invoice_benefit_values b where b.id = b_paid;
  select * into n2 from customer_credit_lots where id = new_lot;
  perform pg_temp.t461_check(r = 'changed'
    and (select customer_id from invoices where id = inv) = pg_temp.t461_id('CA New')
    and pg_temp.t461_holds('CA New') = 'bonus 10.00/10.00, paid 56.00/56.00 | no voucher'
    and pg_temp.t461_holds('CA Buyer') = 'bonus 0.00/10.00, paid 0.00/100.00 | no voucher'
    and n2.reassigned_from_lot_id = old_lot and n2.customer_id = pg_temp.t461_id('CA New')
    and (n2.category, n2.source_type, n2.source_record_id, n2.usage_restrictions, n2.store_id, n2.effective_date, n2.original_purchase_date)
        is not distinct from (o.category, o.source_type, o.source_record_id, o.usage_restrictions, o.store_id, o.effective_date, o.original_purchase_date)
    and (select credit_lot_id from credit_package_sales where invoice_id = inv) = new_lot
    and (select count(*) from customer_credit_ledger where source_record_id = inv and source_type = 'invoice_reassignment_out' and amount = 56 and lot_id = old_lot) = 1
    and (select count(*) from customer_credit_ledger where source_record_id = inv and source_type = 'invoice_reassignment_in' and amount = 56 and lot_id = new_lot) = 1
    and pg_temp.t461_options(inv) = opts,
    '1 CA the change: ' || r || ' / ' || pg_temp.t461_holds('CA New') || ' / ' || pg_temp.t461_holds('CA Buyer')
    || ' / options ' || pg_temp.t461_options(inv)::text || ' (before ' || opts::text || ')');
  perform pg_temp.t461_check(pg_temp.t461_codes(inv, 'cancel') = '-' and pg_temp.t461_codes(inv, 'refund_full') = '-'
    and (invoice_action_plan(inv, 'cancel', '[]')->>'refund_due')::numeric = 60
    and pg_temp.t461_list_txt(inv) = 'Bonus credit 10.00 moves; Paid credit 56.00 moves',
    '1 CA after the change, the plans ask ' || pg_temp.t461_codes(inv, 'cancel') || ' / ' || pg_temp.t461_codes(inv, 'refund_full'));
  r := pg_temp.t461_guided(inv, 'refund_full', '[]', true);
  perform pg_temp.t461_check(r = '-' and pg_temp.t461_money(inv) = 'refunded net 0.00 due 0.00'
    and pg_temp.t461_holds('CA New') = 'bonus 0.00/10.00, paid 0.00/56.00 | no voucher'
    and pg_temp.t461_holds('CA Buyer') = 'bonus 0.00/10.00, paid 0.00/100.00 | no voucher',
    '1 CA Refund in full: ' || r || ' / ' || pg_temp.t461_money(inv) || ' / ' || pg_temp.t461_holds('CA New'));

  -- CB: changed, then cancelled: the new customer's credit is taken back,
  -- nothing reads as used, and the S$60 due is recorded by line.
  inv := pg_temp.t461_id('CB');
  r := pg_temp.t461_change(inv, 'CB New');
  perform pg_temp.t461_check(r = 'changed' and pg_temp.t461_holds('CB New') = 'bonus 10.00/10.00, paid 56.00/56.00 | no voucher', '1 CB the change: ' || r);
  perform cancel_invoice_recorded(inv, 'T461 CB', gen_random_uuid());
  perform pg_temp.t461_check(pg_temp.t461_holds('CB New') = 'bonus 0.00/10.00, paid 0.00/56.00 | no voucher'
    and cardinality(cancelled_invoice_used_value(inv)) = 0 and pg_temp.t461_money(inv) = 'cancelled net 60.00 due 60.00',
    '1 CB cancelled: ' || pg_temp.t461_holds('CB New') || ' / ' || pg_temp.t461_money(inv));
  r := pg_temp.t461_by_line(inv);
  perform pg_temp.t461_check(r = 'recorded' and pg_temp.t461_money(inv) = 'cancelled net 0.00 due 0.00',
    '1 CB the S$60 due recorded by line: ' || r || ' / ' || pg_temp.t461_money(inv));

  -- CC: a Premium Bundle's Paid credit, S$40 refunded (S$48 of credit).
  inv := pg_temp.t461_id('CC');
  r := pg_temp.t461_change(inv, 'CC New');
  perform pg_temp.t461_check(r = 'changed' and pg_temp.t461_holds('CC New') = 'bonus 20.00/20.00, paid 52.00/52.00 | no voucher'
    and (select paid_credit_lot_id from premium_bundle_sales where invoice_id = inv)
        = (select l.id from customer_credit_lots l where l.customer_id = pg_temp.t461_id('CC New') and l.category = 'paid')
    and pg_temp.t461_codes(inv, 'cancel') = '-' and (invoice_action_plan(inv, 'cancel', '[]')->>'refund_due')::numeric = 60,
    '1 CC the bundle: ' || r || ' / ' || pg_temp.t461_holds('CC New') || ' / ' || pg_temp.t461_codes(inv, 'cancel'));

  -- CD: line A wholly refunded reads "Refunded", stays; line B moves.
  inv := pg_temp.t461_id('CD');
  perform pg_temp.t461_check(pg_temp.t461_list_txt(inv) =
      'Bonus credit 0.00 stays (Refunded; nothing is left to move); Bonus credit 10.00 moves; '
      || 'Paid credit 0.00 stays (Refunded; nothing is left to move); Paid credit 100.00 moves'
    and pg_temp.t461_summary(inv, 'CD New') = '{"moving": ["Bonus credit 10.00", "Paid credit 100.00"], "review": []}'::jsonb,
    '1 CD after 461: ' || pg_temp.t461_list_txt(inv));
  r := pg_temp.t461_change(inv, 'CD New');
  perform pg_temp.t461_check(r = 'changed' and pg_temp.t461_holds('CD New') = 'bonus 10.00/10.00, paid 100.00/100.00 | no voucher'
    and pg_temp.t461_holds('CD Buyer') = 'bonus 0.00/10.00, bonus 0.00/10.00, paid 0.00/100.00, paid 0.00/100.00 | no voucher'
    and pg_temp.t461_list_txt(inv) like 'Bonus credit 0.00 stays (Refunded; nothing is left to move); Bonus credit 10.00 moves; Paid credit 0.00 stays (Refunded; nothing is left to move); Paid credit 100.00 moves'
    and pg_temp.t461_codes(inv, 'cancel') = '-',
    '1 CD the change: ' || r || ' / ' || pg_temp.t461_holds('CD New'));

  -- CE: the Paid and the Bonus both partly refunded: both move.
  inv := pg_temp.t461_id('CE');
  perform pg_temp.t461_check(pg_temp.t461_list_txt(inv) = 'Bonus credit 4.50 moves; Paid credit 56.00 moves', '1 CE after 461: ' || pg_temp.t461_list_txt(inv));
  r := pg_temp.t461_change(inv, 'CE New');
  perform pg_temp.t461_check(r = 'changed' and pg_temp.t461_holds('CE New') = 'bonus 4.50/4.50, paid 56.00/56.00 | no voucher'
    and pg_temp.t461_codes(inv, 'cancel') = '-' and (invoice_action_plan(inv, 'cancel', '[]')->>'refund_due')::numeric = 55,
    '1 CE the change: ' || r || ' / ' || pg_temp.t461_holds('CE New') || ' / due ' || (invoice_action_plan(inv, 'cancel', '[]')->>'refund_due'));

  -- CF: changed twice, A to B to C: C holds the S$56 and S$10; a cancel
  -- takes them back from C and the S$60 due is recorded by line.
  inv := pg_temp.t461_id('CF');
  r := pg_temp.t461_change(inv, 'CF New');
  perform pg_temp.t461_check(r = 'changed', '1 CF the first change: ' || r);
  r := pg_temp.t461_change(inv, 'CF Third');
  perform pg_temp.t461_check(r = 'changed' and pg_temp.t461_holds('CF Third') = 'bonus 10.00/10.00, paid 56.00/56.00 | no voucher'
    and pg_temp.t461_holds('CF New') = 'bonus 0.00/10.00, paid 0.00/56.00 | no voucher'
    and pg_temp.t461_list_txt(inv) = 'Bonus credit 10.00 moves; Paid credit 56.00 moves',
    '1 CF the second change: ' || r || ' / ' || pg_temp.t461_holds('CF Third'));
  perform cancel_invoice_recorded(inv, 'T461 CF', gen_random_uuid());
  r := pg_temp.t461_by_line(inv);
  perform pg_temp.t461_check(pg_temp.t461_holds('CF Third') = 'bonus 0.00/10.00, paid 0.00/56.00 | no voucher'
    and cardinality(cancelled_invoice_used_value(inv)) = 0 and r = 'recorded' and pg_temp.t461_money(inv) = 'cancelled net 0.00 due 0.00',
    '1 CF cancelled and paid back: ' || r || ' / ' || pg_temp.t461_money(inv));

  -- CG: changed, then the new customer spends S$10: real spending blocks a
  -- second change again ("Partly spent", the S$46 left), and Cancel asks
  -- credit_used for it alone.
  inv := pg_temp.t461_id('CG');
  r := pg_temp.t461_change(inv, 'CG New');
  perform pg_temp.t461_check(r = 'changed' and pg_temp.t461_holds('CG New') = 'bonus 10.00/10.00, paid 56.00/56.00 | no voucher', '1 CG the change: ' || r);
  perform pg_temp.t461_spend(inv, 1, 10);
  r := pg_temp.t461_change(inv, 'CG Third');
  perform pg_temp.t461_check(pg_temp.t461_list_txt(inv) = 'Bonus credit 10.00 moves; Paid credit 46.00 BLOCKS (Partly spent)'
    and r like 'These benefits have already been used and cannot move with the invoice: Paid credit 46.00 (Partly spent).%'
    and pg_temp.t461_holds('CG Third') = 'no credit | no voucher' and pg_temp.t461_holds('CG New') = 'bonus 10.00/10.00, paid 46.00/56.00 | no voucher'
    and pg_temp.t461_codes(inv, 'cancel') = 'credit_used',
    '1 CG S$10 spent at the new customer: ' || pg_temp.t461_list_txt(inv) || ' / ' || r || ' / ' || pg_temp.t461_codes(inv, 'cancel'));

  -- CJ: changed, then S$20 more of the Paid refunded by line (from the new
  -- customer's lot): what is left still moves with a second change, and a
  -- cancel takes it back from the third customer; the S$40 due is recorded.
  inv := pg_temp.t461_id('CJ');
  r := pg_temp.t461_change(inv, 'CJ New');
  perform pg_temp.t461_check(r = 'changed', '1 CJ the change: ' || r);
  r := pg_temp.t461_cline_back(inv, 1, 20);
  perform pg_temp.t461_check(r = 'recorded' and pg_temp.t461_holds('CJ New') = 'bonus 10.00/10.00, paid 34.00/56.00 | no voucher'
    and pg_temp.t461_list_txt(inv) = 'Bonus credit 10.00 moves; Paid credit 34.00 moves' and pg_temp.t461_codes(inv, 'cancel') = '-',
    '1 CJ S$20 refunded after the change: ' || r || ' / ' || pg_temp.t461_holds('CJ New') || ' / ' || pg_temp.t461_list_txt(inv));
  r := pg_temp.t461_change(inv, 'CJ Third');
  perform pg_temp.t461_check(r = 'changed' and pg_temp.t461_holds('CJ Third') = 'bonus 10.00/10.00, paid 34.00/34.00 | no voucher'
    and pg_temp.t461_holds('CJ New') = 'bonus 0.00/10.00, paid 0.00/56.00 | no voucher'
    and pg_temp.t461_codes(inv, 'cancel') = '-' and (invoice_action_plan(inv, 'cancel', '[]')->>'refund_due')::numeric = 40,
    '1 CJ the second change: ' || r || ' / ' || pg_temp.t461_holds('CJ Third') || ' / due ' || (invoice_action_plan(inv, 'cancel', '[]')->>'refund_due'));
  perform cancel_invoice_recorded(inv, 'T461 CJ', gen_random_uuid());
  r := pg_temp.t461_by_line(inv);
  perform pg_temp.t461_check(pg_temp.t461_holds('CJ Third') = 'bonus 0.00/10.00, paid 0.00/34.00 | no voucher'
    and cardinality(cancelled_invoice_used_value(inv)) = 0 and r = 'recorded' and pg_temp.t461_money(inv) = 'cancelled net 0.00 due 0.00',
    '1 CJ cancelled and paid back: ' || r || ' / ' || pg_temp.t461_money(inv));

  -- CH: reopened, waiting: what the refund took reads "Refunded"; what the
  -- cancellation took back reads as before (NOT COVERED). Nothing moves.
  inv := pg_temp.t461_id('CH');
  perform pg_temp.t461_check(pg_temp.t461_list_txt(inv) =
      'Bonus credit 0.00 stays (Fully spent; it stays with the original customer); Bonus credit 0.00 stays (Refunded; nothing is left to move); '
      || 'Paid credit 0.00 stays (Fully spent; it stays with the original customer); Paid credit 0.00 stays (Refunded; nothing is left to move)',
    '1 CH after 461: ' || pg_temp.t461_list_txt(inv));
  -- CK: S$40 by line, then the guided Refund in full: both lots read
  -- "Refunded"; the change moves nothing.
  inv := pg_temp.t461_id('CK');
  perform pg_temp.t461_check(pg_temp.t461_list_txt(inv) = 'Bonus credit 0.00 stays (Refunded; nothing is left to move); Paid credit 0.00 stays (Refunded; nothing is left to move)'
    and pg_temp.t461_try_change(inv, 'CK New') = 'changed: no credit | no voucher',
    '1 CK after 461: ' || pg_temp.t461_list_txt(inv));
  -- CI: S$40 refunded then cancelled: the Paid lot reads "Refunded" (S$44
  -- refunded, S$56 taken back), the Bonus as before.
  inv := pg_temp.t461_id('CI');
  perform pg_temp.t461_check(pg_temp.t461_list_txt(inv) =
      'Bonus credit 0.00 stays (Fully spent; it stays with the original customer); Paid credit 0.00 stays (Refunded; nothing is left to move)',
    '1 CI after 461: ' || pg_temp.t461_list_txt(inv));

  -- CM: the S$30 a refunded session gave back to the lot, of a package the
  -- guided Refund in full (credit_used) took the rest of: nothing on it is
  -- spent, so it moves; the Bonus reads "Refunded". Refund in full then takes
  -- the S$30 back from the new customer and pays back the S$27.27 left.
  inv := pg_temp.t461_id('CM');
  perform pg_temp.t461_check(pg_temp.t461_list_txt(inv) = 'Bonus credit 0.00 stays (Refunded; nothing is left to move); Paid credit 30.00 moves'
    and pg_temp.t461_summary(inv, 'CM New') = '{"moving": ["Paid credit 30.00"], "review": []}'::jsonb,
    '1 CM after 461: ' || pg_temp.t461_list_txt(inv) || ' / ' || pg_temp.t461_summary(inv, 'CM New')::text);
  opts := pg_temp.t461_options(inv);
  r := pg_temp.t461_change(inv, 'CM New');
  perform pg_temp.t461_check(r = 'changed' and pg_temp.t461_holds('CM New') = 'paid 30.00/30.00 | no voucher'
    and pg_temp.t461_holds('CM Buyer') = 'bonus 0.00/10.00, paid 0.00/100.00 | no voucher'
    and pg_temp.t461_options(inv) = opts and pg_temp.t461_codes(inv, 'refund_full') = '-',
    '1 CM the change: ' || r || ' / ' || pg_temp.t461_holds('CM New') || ' / ' || pg_temp.t461_holds('CM Buyer') || ' / asks ' || pg_temp.t461_codes(inv, 'refund_full'));
  r := pg_temp.t461_guided(inv, 'refund_full', '[]', true);
  perform pg_temp.t461_check(r = '-' and pg_temp.t461_money(inv) = 'refunded net 0.00 due 0.00'
    and pg_temp.t461_holds('CM New') = 'paid 0.00/30.00 | no voucher' and pg_temp.t461_holds('CM Buyer') = 'bonus 0.00/10.00, paid 0.00/100.00 | no voucher',
    '1 CM Refund in full: ' || r || ' / ' || pg_temp.t461_money(inv) || ' / ' || pg_temp.t461_holds('CM New'));

  -- CW: the S$56 a refunded session gave back while a reopening waits to
  -- give the refunded S$44 and S$10 back: the reopening holds a claim on the
  -- lot, so it still blocks and the change is refused (the Bonus, refunded,
  -- reads "Refunded"). Settled, the buyer holds all S$110 and Refund in full
  -- takes it all back.
  inv := pg_temp.t461_id('CW');
  r := pg_temp.t461_change(inv, 'CW New');
  perform pg_temp.t461_check(pg_temp.t461_list_txt(inv) = 'Bonus credit 0.00 stays (Refunded; nothing is left to move); Paid credit 56.00 BLOCKS (Partly spent)'
    and r like 'These benefits have already been used and cannot move with the invoice: Paid credit 56.00 (Partly spent).%',
    '1 CW after 461, a reopening waiting: ' || pg_temp.t461_list_txt(inv) || ' / ' || r);
  perform pg_temp.t461_pay(inv);
  perform pg_temp.t461_check(pg_temp.t461_money(inv) = 'paid net 100.00 due 0.00'
    and pg_temp.t461_holds('CW Buyer') = 'bonus 10.00/10.00, paid 100.00/100.00 | no voucher' and pg_temp.t461_holds('CW New') = 'no credit | no voucher'
    and pg_temp.t461_codes(inv, 'refund_full') = '-',
    '1 CW settled: ' || pg_temp.t461_money(inv) || ' / ' || pg_temp.t461_holds('CW Buyer') || ' / asks ' || pg_temp.t461_codes(inv, 'refund_full'));
  r := pg_temp.t461_guided(inv, 'refund_full', '[]', true);
  perform pg_temp.t461_check(r = '-' and pg_temp.t461_money(inv) = 'refunded net 0.00 due 0.00'
    and pg_temp.t461_holds('CW Buyer') = 'bonus 0.00/10.00, paid 0.00/100.00 | no voucher',
    '1 CW Refund in full: ' || r || ' / ' || pg_temp.t461_money(inv) || ' / ' || pg_temp.t461_holds('CW Buyer'));

  raise notice 'PASS 1: after 461, a lot partly refunded and not spent moves with a customer change (Credit Package and Premium Bundle, Paid and Bonus, twice in a row, and again after a further refund), keeping its origin; the invoice''s records name the new lots and the refund options are as before the change; nothing is asked; real spending at the new customer blocks again; Refund in full, Cancel and the refund due recorded by line take back and pay back exactly what is left (CA: %); a lot a refund emptied reads "Refunded; nothing is left to move"',
    pg_temp.t461_money(pg_temp.t461_id('CA'));
end $$;

-- ===== 1b. The money after 461 where the change is still refused =====
-- What each customer holds after what follows (a reopening and Refund in
-- full, or Cancel): all of it taken back from the buyer, as before 461; no
-- credit kept beside the money paid back, none left with a customer no
-- record names.
do $$
declare inv uuid; r text;
begin
  -- K11: reopened (settled at once: the refund due was never recorded), the
  -- buyer holds all S$110 again; Refund in full pays back S$100 and takes
  -- it all.
  inv := pg_temp.t461_id('K11');
  perform reopen_invoice(inv, 'T461 K11', gen_random_uuid());
  if (invoice_financial_position(inv)->>'outstanding')::numeric > 0 then perform pg_temp.t461_pay(inv); end if;
  perform pg_temp.t461_check(pg_temp.t461_money(inv) = 'paid net 100.00 due 0.00'
    and pg_temp.t461_holds('K11 Buyer') = 'bonus 10.00/10.00, paid 100.00/100.00 | no voucher' and pg_temp.t461_holds('K11 New') = 'no credit | no voucher'
    and pg_temp.t461_codes(inv, 'refund_full') = '-'
    and not exists (select 1 from invoice_benefit_values b where b.invoice_id = inv and b.cancelled_unused_value <> 0),
    '1b K11 reopened: ' || pg_temp.t461_money(inv) || ' / ' || pg_temp.t461_holds('K11 Buyer') || ' / ' || pg_temp.t461_holds('K11 New'));
  r := pg_temp.t461_guided(inv, 'refund_full', '[]', true);
  perform pg_temp.t461_check(r = '-' and pg_temp.t461_money(inv) = 'refunded net 0.00 due 0.00'
    and (select sum(amount) from invoice_refunds where invoice_id = inv) = 100
    and pg_temp.t461_holds('K11 Buyer') = 'bonus 0.00/10.00, paid 0.00/100.00 | no voucher' and pg_temp.t461_holds('K11 New') = 'no credit | no voucher',
    '1b K11 Refund in full: ' || r || ' / ' || pg_temp.t461_money(inv) || ' / ' || pg_temp.t461_holds('K11 Buyer'));
  -- K12 and K13: Cancel asks nothing and the whole S$100 is due; the buyer's
  -- and the friend's credit are taken back.
  inv := pg_temp.t461_id('K12');
  r := pg_temp.t461_guided(inv, 'cancel', '[]', false);
  perform pg_temp.t461_check(r = '-' and pg_temp.t461_money(inv) = 'cancelled net 100.00 due 100.00'
    and pg_temp.t461_holds('K12 Buyer') = 'bonus 0.00/10.00, paid 0.00/100.00 | no voucher'
    and pg_temp.t461_holds('K12 Friend') = 'paid 0.00/70.00 | no voucher' and pg_temp.t461_holds('K12 New') = 'no credit | no voucher',
    '1b K12 Cancel: ' || r || ' / ' || pg_temp.t461_money(inv) || ' / ' || pg_temp.t461_holds('K12 Buyer') || ' / ' || pg_temp.t461_holds('K12 Friend'));
  inv := pg_temp.t461_id('K13');
  r := pg_temp.t461_guided(inv, 'cancel', '[]', false);
  perform pg_temp.t461_check(r = '-' and pg_temp.t461_money(inv) = 'cancelled net 100.00 due 100.00'
    and pg_temp.t461_holds('K13 Buyer') = 'bonus 0.00/10.00, paid 0.00/100.00 | no voucher'
    and pg_temp.t461_holds('K13 Friend') = 'paid 0.00/56.00 | no voucher' and pg_temp.t461_holds('K13 New') = 'no credit | no voucher',
    '1b K13 Cancel: ' || r || ' / ' || pg_temp.t461_money(inv) || ' / ' || pg_temp.t461_holds('K13 Buyer') || ' / ' || pg_temp.t461_holds('K13 Friend'));
  raise notice 'PASS 1b: where something still holds a claim on the credit back on a lot (a cancellation holding it back, an Owner''s Move), the change stays refused and what follows takes it all back from whoever holds it: K11 reopened then refunded in full (%), K12 and K13 cancelled with the S$100 due',
    pg_temp.t461_money(pg_temp.t461_id('K11'));
end $$;

-- ===== 8. KNOWN =====
do $$
declare inv uuid; r text; v_held_buyer numeric; v_held_new numeric;
begin
  -- CN: S$40 refunded, changed, cancelled, reopened and paid: the reopening
  -- puts the refunded S$44 back on the lot the refund came from, the first
  -- customer's emptied one (446's NOT COVERED 5, 448's NOT COVERED 2).
  inv := pg_temp.t461_id('CN');
  r := pg_temp.t461_change(inv, 'CN New');
  perform pg_temp.t461_check(r = 'changed', '8 CN the change: ' || r);
  perform cancel_invoice_recorded(inv, 'T461 CN', gen_random_uuid());
  perform reopen_invoice(inv, 'T461 CN', gen_random_uuid());
  perform pg_temp.t461_pay(inv);
  select coalesce(sum(remaining_amount), 0) into v_held_buyer from customer_credit_lots where customer_id = pg_temp.t461_id('CN Buyer') and category = 'paid';
  select coalesce(sum(remaining_amount), 0) into v_held_new from customer_credit_lots where customer_id = pg_temp.t461_id('CN New') and category = 'paid';
  if pg_temp.t461_460_in() then
    perform pg_temp.t461_check(v_held_buyer = 0 and v_held_new = 100 and pg_temp.t461_codes(inv, 'cancel') = '-' and pg_temp.t461_money(inv) = 'paid net 100.00 due 0.00',
      '8 CN with 460 in, the refunded credit following the lot: the first customer holds ' || v_held_buyer || ', the new one ' || v_held_new
      || ', the plan asks ' || pg_temp.t461_codes(inv, 'cancel') || ' / ' || pg_temp.t461_money(inv));
    raise notice 'FIXED 8 CN (460 in): S$40 refunded, the customer changed (461 moves the S$56 left), cancelled, reopened and paid: the new customer holds all S$100 of Paid credit, the first customer none, nothing is asked (%)',
      pg_temp.t461_holds('CN New');
  else
    perform pg_temp.t461_check(v_held_buyer = 44 and v_held_new = 56 and pg_temp.t461_codes(inv, 'cancel') = 'credit_used'
      and pg_temp.t461_money(inv) = 'paid net 100.00 due 0.00',
      '8 CN: the first customer holds ' || v_held_buyer || ', the new one ' || v_held_new || ', the plan asks ' || pg_temp.t461_codes(inv, 'cancel')
      || ': look at 461''s NOT COVERED 1 and this case again');
    raise notice 'KNOWN 8 CN: (461''s NOT COVERED 1; 446''s NOT COVERED 5 and 448''s NOT COVERED 2, which 460 is to fix: there before 461 for a line wholly refunded beside another, and since 461 reached by a partly refunded lot too, whose change was refused before) S$40 refunded, the customer changed (461 moves the S$56 left), cancelled, reopened and paid: the reopening puts the refunded S$44 back on the first customer''s emptied lot (it holds S$%), the new customer S$% of Paid credit, and Cancel asks %',
      v_held_buyer, v_held_new, pg_temp.t461_codes(inv, 'cancel');
  end if;
  raise notice 'KNOWN 8 labels: (461''s NOT COVERED 2, there before it, not changed) a lot an Owner moved reads "%" (K5), refunded and moved "%" (K6), and one a cancellation took back "%" (K7): none was spent; nothing moves either way',
    (select e->>'why' from jsonb_array_elements(pg_temp.t461_list(pg_temp.t461_id('K5'))) e where e->>'what' = 'Paid credit 0.00'),
    (select e->>'why' from jsonb_array_elements(pg_temp.t461_list(pg_temp.t461_id('K6'))) e where e->>'what' = 'Paid credit 0.00'),
    (select e->>'why' from jsonb_array_elements(pg_temp.t461_list(pg_temp.t461_id('K7'))) e where e->>'what' = 'Paid credit 0.00');
end $$;

rollback;
